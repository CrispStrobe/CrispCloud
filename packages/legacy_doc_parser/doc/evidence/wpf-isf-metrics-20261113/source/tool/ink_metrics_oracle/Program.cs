// SPDX-License-Identifier: MPL-2.0
// Actual Windows WPF oracle for deliberately authored ISF headers. No production
// parser or custom ISF packet decoder is referenced by this assembly.
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Ink;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class InkMetricsOracle
{
    private const double DipPerHimetric = 96.0 / 2540.0;
    private const int PixelWidth = 512, PixelHeight = 256;
    private const double Translation = 32;
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    // Compile the original helper unchanged and reuse its exact snapshot, load,
    // save and comparison methods. This runner alone supplies the larger canvas.
    private static T Reuse<T>(string method, params object[] arguments)
    {
        var target = typeof(Program).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(typeof(Program).FullName, method);
        return (T)(target.Invoke(null, arguments) ?? throw new InvalidDataException("Missing oracle result."));
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 3 || !System.Text.RegularExpressions.Regex.IsMatch(args[2], "^[0-9a-f]{40}$"))
        {
            Console.Error.WriteLine("Usage: InkMetricsOracle INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY SOURCE_COMMIT_SHA");
            return 64;
        }
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Actual Windows WPF is required.");
        var input = Path.GetFullPath(args[0]);
        var output = Path.GetFullPath(args[1]);
        Require(!Directory.Exists(output) && !File.Exists(output), "New output directory required.");
        using var controls = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(input, "controls.json")));
        Require(controls.RootElement.GetProperty("sourceCommit").GetString() == args[2], "Authored source identity.");
        Directory.CreateDirectory(output);
        File.Copy(Path.Combine(input, "controls.json"), Path.Combine(output, "controls.json"));
        File.Copy(Path.Combine(input, "source-inventory.json"), Path.Combine(output, "source-inventory.json"));
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
        var cases = new List<object>();
        var bases = new Dictionary<string, (StrokeCollection Strokes, byte[] Pixels)>();
        var all = new Dictionary<string, (StrokeCollection Strokes, byte[] Pixels)>();
        foreach (var control in controls.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = control.GetProperty("name").GetString()!;
            var sourceName = control.GetProperty("sourceName").GetString()!;
            Require(System.Text.RegularExpressions.Regex.IsMatch(name, "^[a-z0-9-]+$"), "Safe case name.");
            var raw = File.ReadAllBytes(Path.Combine(input, name, "input.isf"));
            Require(raw.Length == control.GetProperty("bytes").GetInt32()
                    && Sha(raw) == control.GetProperty("sha256").GetString(), "Exact authored input bytes.");
            var directory = Path.Combine(output, name);
            Directory.CreateDirectory(directory);
            File.WriteAllBytes(Path.Combine(directory, "input.isf"), raw);
            var first = Reuse<StrokeCollection>("Reload", raw);
            ValidateStructure(first);
            var snapshotBeforeSave = JsonSerializer.Serialize(Reuse<object>("Snapshot", first), Json);
            WriteJson(Path.Combine(directory, "reloaded.json"), Reuse<object>("Snapshot", first));
            var firstRender = Render(first, Path.Combine(directory, "reloaded.png"));
            var roundtrip = Reuse<byte[]>("Save", first, false);
            File.WriteAllBytes(Path.Combine(directory, "roundtrip.isf"), roundtrip);
            var second = Reuse<StrokeCollection>("Reload", roundtrip);
            ValidateStructure(second);
            WriteJson(Path.Combine(directory, "second-reloaded.json"), Reuse<object>("Snapshot", second));
            var secondRender = Render(second, Path.Combine(directory, "second-reloaded.png"));
            Require(JsonSerializer.Serialize(Reuse<object>("Snapshot", first), Json) == snapshotBeforeSave,
                    "WPF save mutated the first decoded strokes.");
            if (name == sourceName + "-baseline") bases.Add(sourceName, (first, firstRender.Pixels));
            var baseline = bases[sourceName];
            all.Add(name, (first, firstRender.Pixels));
            var formula = FormulaObservation(control, first);
            WriteJson(Path.Combine(directory, "formula-observation.json"), formula);
            cases.Add(new
            {
                Name = name, SourceName = sourceName, InputBytes = raw.Length, InputSha256 = Sha(raw),
                RoundtripBytes = roundtrip.Length, RoundtripSha256 = Sha(roundtrip),
                BytesStableAfterReload = raw.SequenceEqual(roundtrip),
                OriginalDecodedObjectsUnchanged = true,
                SourceFormulaObservation = formula,
                BaselineToReloaded = Reuse<object>("Difference", baseline.Strokes, first),
                BaselineToReloadedChangedPixels = Reuse<int>("ChangedPixels", baseline.Pixels, firstRender.Pixels),
                ReloadedToSecond = Reuse<object>("Difference", first, second),
                ReloadedToSecondChangedPixels = Reuse<int>("ChangedPixels", firstRender.Pixels, secondRender.Pixels),
                ReloadedRender = firstRender.Receipt, SecondReloadedRender = secondRender.Receipt,
            });
            Console.WriteLine($"{name}: WPF loaded {first.Count} stroke / {first[0].StylusPoints.Count} points; saved and loaded again.");
        }
        var comparisons = new List<object>();
        foreach (var name in all.Keys.Where(n => n.EndsWith("-float-only", StringComparison.Ordinal)))
            comparisons.Add(Compare(name, name.Replace("-float-only", "-float-and-double", StringComparison.Ordinal), all));
        foreach (var mode in new[] { "float-only", "float-and-double" })
        {
            comparisons.Add(Compare("translate-100-minus50-" + mode, "affine-translate-100-minus50-" + mode, all));
            comparisons.Add(Compare("scale-translate-2-half-100-minus50-" + mode,
                "affine-scale-translate-2-half-100-minus50-" + mode, all));
        }
        comparisons.Add(Compare("pressure-ramp-baseline", "pressure-explicit-0-1023", all));
        comparisons.Add(Compare("pressure-ramp-baseline", "pressure-explicit-0-2047", all));
        var assembly = typeof(StrokeCollection).Assembly;
        WriteJson(Path.Combine(output, "summary.json"), new
        {
            Schema = "legacy-doc-parser/wpf-isf-header-oracle", Version = 1, SourceCommit = args[2],
            BaseCommit = controls.RootElement.GetProperty("baseCommit").GetString(),
            InspectedWpfSourceCommit = controls.RootElement.GetProperty("inspectedWpfSourceCommit").GetString(),
            Scope = "Actual WPF decoding/rendering of minimally changed retained ISFs; no Word or production parser claim.",
            ActualArguments = args, Framework = RuntimeInformation.FrameworkDescription,
            OperatingSystem = RuntimeInformation.OSDescription, Architecture = RuntimeInformation.ProcessArchitecture.ToString(),
            WpfAssembly = assembly.FullName,
            WpfInformationalVersion = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
            WpfFileVersion = FileVersionInfo.GetVersionInfo(assembly.Location).FileVersion,
            WpfAssemblySha256 = Sha(File.ReadAllBytes(assembly.Location)),
            GitHub = new
            {
                Repository = Environment.GetEnvironmentVariable("GITHUB_REPOSITORY"),
                RunId = Environment.GetEnvironmentVariable("GITHUB_RUN_ID"),
                RunAttempt = Environment.GetEnvironmentVariable("GITHUB_RUN_ATTEMPT"),
                Workflow = Environment.GetEnvironmentVariable("GITHUB_WORKFLOW"),
                Sha = Environment.GetEnvironmentVariable("GITHUB_SHA"),
            },
            Render = new { PixelWidth, PixelHeight, Dpi = 96, TranslationDip = new[] { Translation, Translation },
                BackgroundArgb = "#FFFFFFFF", ModePreference = "SoftwareOnly", PixelFormat = "Pbgra32" },
            Cases = cases, Comparisons = comparisons, CaseCount = cases.Count, Status = "complete",
            ObservationPolicy = "Formula differences are observations, not success criteria or replacement expectations.",
        });
        var files = Directory.GetFiles(output, "*", SearchOption.AllDirectories).OrderBy(p => p, StringComparer.Ordinal)
            .Select(path => new { Path = Path.GetRelativePath(output, path).Replace('\\', '/'),
                Bytes = new FileInfo(path).Length, Sha256 = Sha(File.ReadAllBytes(path)) }).ToArray();
        WriteJson(Path.Combine(output, "manifest.json"), new
        {
            Schema = "legacy-doc-parser/wpf-isf-header-files", Version = 1, SourceCommit = args[2],
            FileCount = files.Length, TotalBytes = files.Sum(f => f.Bytes), Files = files,
        });
        Console.WriteLine($"Complete: {cases.Count} cases, {comparisons.Count} recorded comparisons, {files.Length} inventoried output files.");
        return 0;
    }

    private static object FormulaObservation(JsonElement control, StrokeCollection actual)
    {
        var expected = control.GetProperty("sourceFormula").GetProperty("points").EnumerateArray().ToArray();
        var pressure = control.GetProperty("sourceFormula").GetProperty("pressureFactors");
        double coordinates = 0, factors = 0;
        for (var i = 0; i < expected.Length; i++)
        {
            var point = actual[0].StylusPoints[i];
            coordinates = Math.Max(coordinates, Math.Max(Math.Abs(point.X / DipPerHimetric - expected[i][0].GetDouble()),
                Math.Abs(point.Y / DipPerHimetric - expected[i][1].GetDouble())));
            if (pressure.ValueKind != JsonValueKind.Null)
                factors = Math.Max(factors, Math.Abs(point.PressureFactor - pressure[i].GetDouble()));
        }
        var metric = actual[0].StylusPoints.Description.GetPropertyInfo(StylusPointProperties.NormalPressure);
        var declared = control.GetProperty("pressureMetric");
        var metricMatches = metric.Minimum == declared.GetProperty("minimum").GetInt32()
            && metric.Maximum == declared.GetProperty("maximum").GetInt32()
            && metric.Unit.ToString() == declared.GetProperty("unit").GetString()
            && metric.Resolution == declared.GetProperty("resolution").GetSingle();
        return new
        {
            MaximumCoordinateDeltaHimetric = coordinates, MaximumPressureFactorDelta = factors,
            PressureMetricMatchesDeclaration = metricMatches,
            CoordinatesMatchSourceFormulaWithinTolerance = coordinates < 1e-8,
            PressureMatchesSourceFormulaWithinFloatTolerance = factors < 1e-7,
            ObservedPressurePropertyValues = actual[0].StylusPoints.Select(p => p.GetPropertyValue(StylusPointProperties.NormalPressure)).ToArray(),
            ObservedPressureFactors = actual[0].StylusPoints.Select(p => p.PressureFactor).ToArray(),
            ObservedPressureMetric = new { metric.Minimum, metric.Maximum, Unit = metric.Unit.ToString(), metric.Resolution },
            Policy = "Recorded WPF result. A source-formula mismatch is retained, not corrected or declared unsupported input.",
        };
    }

    private static object Compare(string left, string right,
        Dictionary<string, (StrokeCollection Strokes, byte[] Pixels)> values) => new
    {
        Left = left, Right = right,
        Difference = Reuse<object>("Difference", values[left].Strokes, values[right].Strokes),
        ChangedPixels = Reuse<int>("ChangedPixels", values[left].Pixels, values[right].Pixels),
    };

    private static void ValidateStructure(StrokeCollection strokes)
    {
        Require(strokes.Count == 1 && strokes[0].StylusPoints.Count == 5, "Retained source stroke/point counts.");
        foreach (var point in strokes[0].StylusPoints)
            Require(double.IsFinite(point.X) && double.IsFinite(point.Y) && float.IsFinite(point.PressureFactor), "Finite WPF result.");
    }

    private static RenderResult Render(StrokeCollection strokes, string path)
    {
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(Brushes.White, null, new Rect(0, 0, PixelWidth, PixelHeight));
            drawing.PushTransform(new TranslateTransform(Translation, Translation));
            foreach (var stroke in strokes) stroke.Draw(drawing);
            drawing.Pop();
        }
        var bitmap = new RenderTargetBitmap(PixelWidth, PixelHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var pixels = new byte[PixelWidth * PixelHeight * 4];
        bitmap.CopyPixels(pixels, PixelWidth * 4, 0);
        var count = 0; var left = PixelWidth; var top = PixelHeight; var right = -1; var bottom = -1;
        for (var y = 0; y < PixelHeight; y++) for (var x = 0; x < PixelWidth; x++)
        {
            var at = (y * PixelWidth + x) * 4;
            if (pixels[at] == 255 && pixels[at + 1] == 255 && pixels[at + 2] == 255 && pixels[at + 3] == 255) continue;
            count++; left = Math.Min(left, x); top = Math.Min(top, y); right = Math.Max(right, x); bottom = Math.Max(bottom, y);
        }
        Require(count > 0, "WPF ink rendered no visible pixels.");
        Require(left > 0 && top > 0 && right < PixelWidth - 1 && bottom < PixelHeight - 1, "WPF ink touches viewport boundary.");
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using (var stream = new FileStream(path, FileMode.CreateNew)) encoder.Save(stream);
        return new(pixels, new
        {
            Path = Path.GetFileName(path), PngSha256 = Sha(File.ReadAllBytes(path)), PixelSha256 = Sha(pixels),
            NonWhitePixelCount = count, NonWhiteBoundsPixels = new[] { left, top, right + 1, bottom + 1 },
        });
    }

    private static string Sha(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static void WriteJson(string path, object value) => File.WriteAllText(path, JsonSerializer.Serialize(value, Json) + "\n");
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidDataException(message); }
}
