// SPDX-License-Identifier: MPL-2.0
// Independent fixture author/oracle. No Dart parser, converter, ISF encoder,
// Office document, input font, or external artwork is used by this program.
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

internal sealed record PointInput(double XHimetric, double YHimetric, float Pressure = 0.5f);
internal sealed record StrokeInput(
    PointInput[] Points, string ColorArgb, double WidthHimetric, double HeightHimetric,
    bool IgnorePressure = true, StylusTip Tip = StylusTip.Ellipse);
internal sealed record InkCase(string Name, string Purpose, StrokeInput[] Strokes);
internal sealed record RenderResult(byte[] Pixels, object Receipt);

internal static class Program
{
    private const string InspectedWpfSource = "e7acf467c05e51901b17684b1f2c330e7dc5fc4d";
    private const double DipPerHimetric = 96.0 / 2540.0;
    private const int PixelWidth = 256, PixelHeight = 192;
    private const double Translation = 32;
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private static readonly InkCase[] Cases =
    {
        new("polyline-solid", "Black constant-width polyline with integer-Himetric coordinates.", new[]
        {
            new StrokeInput(new[] { new PointInput(0, 0), new(1270, 0), new(1270, 635),
                new(2540, 635), new(3175, 1270) }, "#FF000000", 53, 53),
        }),
        new("single-dot", "A single stylus sample must remain a visible elliptical dot.", new[]
        {
            new StrokeInput(new[] { new PointInput(1270, 1270) }, "#FF0080FF", 212, 212),
        }),
        new("paint-ellipse-alpha", "Independent alpha color and unequal tip width/height.", new[]
        {
            new StrokeInput(new[] { new PointInput(0, 635), new(1270, 1270), new(2540, 635) },
                "#804080D0", 212, 106),
        }),
        new("multiple-strokes", "Three ordered strokes with separate colors, widths and tip shapes.", new[]
        {
            new StrokeInput(new[] { new PointInput(0, 0), new(2540, 0) }, "#FFFF0000", 53, 53),
            new StrokeInput(new[] { new PointInput(635, 635), new(635, 1905) }, "#FF008000", 159, 53,
                Tip: StylusTip.Rectangle),
            new StrokeInput(new[] { new PointInput(1270, 635), new(2540, 1905) }, "#FF0000FF", 106, 106),
        }),
        new("pressure-ramp", "Pressure varies from zero to full with pressure-sensitive drawing.", new[]
        {
            new StrokeInput(new[] { new PointInput(0, 1270, 0), new(635, 635, 0.125f),
                new(1270, 1270, 0.5f), new(1905, 635, 0.875f), new(2540, 1270, 1) },
                "#FF7020A0", 212, 212, IgnorePressure: false),
        }),
        new("signed-quantization", "Signed half-Himetric boundaries disclose coordinate quantization.", new[]
        {
            new StrokeInput(new[] { new PointInput(-635.49, -317.5), new(-0.5, 0.5),
                new(635.49, 317.5), new(1270.5, 635.5) }, "#FFB05010", 79.5, 79.5),
        }),
    };

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 2 || !System.Text.RegularExpressions.Regex.IsMatch(args[1], "^[0-9a-f]{40}$"))
        {
            Console.Error.WriteLine("Usage: InkOracle NEW_OUTPUT_DIRECTORY SOURCE_COMMIT_SHA");
            return 64;
        }
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Actual Windows WPF is required.");
        var output = Path.GetFullPath(args[0]);
        if (Directory.Exists(output) || File.Exists(output)) throw new IOException("Output already exists.");
        Directory.CreateDirectory(output);
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
        var caseRecords = new List<object>();
        var compressedDiffers = 0;
        foreach (var input in Cases)
        {
            var directory = Path.Combine(output, input.Name);
            Directory.CreateDirectory(directory);
            WriteJson(Path.Combine(directory, "authored.json"), new
            {
                input.Name, input.Purpose, CoordinateUnit = "Himetric (1/100 millimeter)",
                DipPerHimetric, ExpectedStrokeCount = input.Strokes.Length,
                ExpectedPointCounts = input.Strokes.Select(s => s.Points.Length).ToArray(),
                Strokes = input.Strokes,
            });
            var original = Create(input);
            var originalSnapshot = Snapshot(original);
            var originalJson = JsonSerializer.Serialize(originalSnapshot, Json);
            WriteJson(Path.Combine(directory, "original.json"), originalSnapshot);
            var originalRender = Render(original, Path.Combine(directory, "original.png"));
            var encodings = new List<object>();
            var saved = new List<byte[]>();
            foreach (var compress in new[] { false, true })
            {
                var mode = compress ? "compressed" : "uncompressed";
                var raw = Save(original, compress);
                saved.Add(raw);
                Require(raw.Length > 2 && raw[0] == 0, "WPF did not write nonempty raw ISF.");
                File.WriteAllBytes(Path.Combine(directory, mode + ".isf"), raw);
                var reloaded = Reload(raw);
                ValidateStructure(input, reloaded);
                WriteJson(Path.Combine(directory, mode + ".reloaded.json"), Snapshot(reloaded));
                var reloadedRender = Render(reloaded, Path.Combine(directory, mode + ".reloaded.png"));
                var roundtrip = Save(reloaded, compress);
                File.WriteAllBytes(Path.Combine(directory, mode + ".roundtrip.isf"), roundtrip);
                var second = Reload(roundtrip);
                ValidateStructure(input, second);
                WriteJson(Path.Combine(directory, mode + ".second-reloaded.json"), Snapshot(second));
                var secondRender = Render(second, Path.Combine(directory, mode + ".second-reloaded.png"));
                Require(JsonSerializer.Serialize(Snapshot(original), Json) == originalJson,
                    "Saving mutated the original WPF strokes.");
                encodings.Add(new
                {
                    Mode = mode, CompressArgument = compress,
                    Isf = new { Path = mode + ".isf", Bytes = raw.Length, Sha256 = Sha(raw) },
                    RoundtripIsf = new { Path = mode + ".roundtrip.isf", Bytes = roundtrip.Length, Sha256 = Sha(roundtrip) },
                    BytesStableAfterReload = raw.SequenceEqual(roundtrip),
                    OriginalToReloaded = Difference(original, reloaded),
                    ReloadedToSecond = Difference(reloaded, second),
                    OriginalToReloadedChangedPixels = ChangedPixels(originalRender.Pixels, reloadedRender.Pixels),
                    ReloadedToSecondChangedPixels = ChangedPixels(reloadedRender.Pixels, secondRender.Pixels),
                    ReloadedRender = reloadedRender.Receipt, SecondReloadedRender = secondRender.Receipt,
                });
            }
            var distinct = !saved[0].SequenceEqual(saved[1]);
            if (distinct) compressedDiffers++;
            caseRecords.Add(new
            {
                input.Name, input.Purpose, StrokeCount = input.Strokes.Length,
                CompressionChangesBytes = distinct, OriginalUnchanged = true,
                OriginalRender = originalRender.Receipt, Encodings = encodings,
            });
            Console.WriteLine($"{input.Name}: {original.Count} stroke(s), both WPF save/load modes complete");
        }
        Require(compressedDiffers > 0, "Compression controls did not distinguish any output bytes.");
        var assembly = typeof(StrokeCollection).Assembly;
        WriteJson(Path.Combine(output, "summary.json"), new
        {
            Schema = "legacy-doc-parser/wpf-isf-oracle", Version = 1, SourceCommit = args[1],
            InspectedWpfSourceCommit = InspectedWpfSource,
            Scope = "Actual WPF ISF encode/decode and ink rendering; not Word/OfficeArt rendering.",
            Framework = RuntimeInformation.FrameworkDescription,
            OperatingSystem = RuntimeInformation.OSDescription,
            Architecture = RuntimeInformation.ProcessArchitecture.ToString(),
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
            Cases = caseRecords, Status = "complete",
        });
        var files = Directory.GetFiles(output, "*", SearchOption.AllDirectories).OrderBy(p => p, StringComparer.Ordinal)
            .Select(path => new { Path = Path.GetRelativePath(output, path).Replace('\\', '/'),
                Bytes = new FileInfo(path).Length, Sha256 = Sha(File.ReadAllBytes(path)) }).ToArray();
        WriteJson(Path.Combine(output, "manifest.json"), new
        {
            Schema = "legacy-doc-parser/wpf-isf-files", Version = 1, SourceCommit = args[1],
            FileCount = files.Length, TotalBytes = files.Sum(f => f.Bytes), Files = files,
        });
        Console.WriteLine($"Complete: {Cases.Length} cases, {Cases.Length * 2} independently reloaded ISFs, {files.Length} retained files.");
        return 0;
    }

    private static StrokeCollection Create(InkCase input)
    {
        var collection = new StrokeCollection();
        foreach (var stroke in input.Strokes)
        {
            var points = new StylusPointCollection(stroke.Points.Select(p => new StylusPoint(
                p.XHimetric * DipPerHimetric, p.YHimetric * DipPerHimetric, p.Pressure)));
            var color = (Color)ColorConverter.ConvertFromString(stroke.ColorArgb);
            collection.Add(new Stroke(points, new DrawingAttributes
            {
                Color = color, Width = stroke.WidthHimetric * DipPerHimetric,
                Height = stroke.HeightHimetric * DipPerHimetric,
                IgnorePressure = stroke.IgnorePressure, StylusTip = stroke.Tip,
                FitToCurve = false, IsHighlighter = false, StylusTipTransform = Matrix.Identity,
            }));
        }
        ValidateStructure(input, collection);
        return collection;
    }

    private static void ValidateStructure(InkCase input, StrokeCollection strokes)
    {
        Require(strokes.Count == input.Strokes.Length && strokes.Count > 0, "Stroke count differs from authored input.");
        for (var i = 0; i < strokes.Count; i++)
            Require(strokes[i].StylusPoints.Count == input.Strokes[i].Points.Length,
                "Point count differs from authored input.");
    }

    private static byte[] Save(StrokeCollection strokes, bool compress)
    {
        using var stream = new MemoryStream();
        strokes.Save(stream, compress);
        return stream.ToArray();
    }

    private static StrokeCollection Reload(byte[] data)
    {
        using var stream = new MemoryStream(data, writable: false);
        return new StrokeCollection(stream);
    }

    private static object Snapshot(StrokeCollection strokes) => new
    {
        CoordinateUnit = "DIP (1/96 inch)", DipPerHimetric, StrokeCount = strokes.Count,
        Strokes = strokes.Select((stroke, index) => new
        {
            Index = index, BoundsDip = Bounds(stroke.GetBounds()),
            Attributes = Attributes(stroke.DrawingAttributes),
            PressureMetric = new
            {
                stroke.StylusPoints.Description.GetPropertyInfo(StylusPointProperties.NormalPressure).Minimum,
                stroke.StylusPoints.Description.GetPropertyInfo(StylusPointProperties.NormalPressure).Maximum,
                Unit = stroke.StylusPoints.Description.GetPropertyInfo(StylusPointProperties.NormalPressure).Unit.ToString(),
                stroke.StylusPoints.Description.GetPropertyInfo(StylusPointProperties.NormalPressure).Resolution,
            },
            Points = stroke.StylusPoints.Select(p => new
            {
                p.X, p.Y, p.PressureFactor,
                HimetricX = p.X / DipPerHimetric, HimetricY = p.Y / DipPerHimetric,
                PressurePropertyValue = p.GetPropertyValue(StylusPointProperties.NormalPressure),
            }).ToArray(),
        }).ToArray(),
    };

    private static object Attributes(DrawingAttributes value) => new
    {
        ColorArgb = value.Color.ToString(CultureInfo.InvariantCulture),
        value.Width, value.Height, WidthHimetric = value.Width / DipPerHimetric,
        HeightHimetric = value.Height / DipPerHimetric,
        value.FitToCurve, value.IgnorePressure, value.IsHighlighter,
        StylusTip = value.StylusTip.ToString(),
        StylusTipTransform = new[] { value.StylusTipTransform.M11, value.StylusTipTransform.M12,
            value.StylusTipTransform.M21, value.StylusTipTransform.M22,
            value.StylusTipTransform.OffsetX, value.StylusTipTransform.OffsetY },
    };

    private static object Difference(StrokeCollection left, StrokeCollection right)
    {
        Require(left.Count == right.Count, "Cannot compare different stroke counts.");
        double coordinate = 0, pressure = 0, width = 0, height = 0;
        var attributesEqual = true;
        for (var i = 0; i < left.Count; i++)
        {
            Require(left[i].StylusPoints.Count == right[i].StylusPoints.Count, "Cannot compare different point counts.");
            for (var j = 0; j < left[i].StylusPoints.Count; j++)
            {
                var a = left[i].StylusPoints[j]; var b = right[i].StylusPoints[j];
                coordinate = Math.Max(coordinate, Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y)));
                pressure = Math.Max(pressure, Math.Abs(a.PressureFactor - b.PressureFactor));
            }
            width = Math.Max(width, Math.Abs(left[i].DrawingAttributes.Width - right[i].DrawingAttributes.Width));
            height = Math.Max(height, Math.Abs(left[i].DrawingAttributes.Height - right[i].DrawingAttributes.Height));
            attributesEqual &= JsonSerializer.Serialize(Attributes(left[i].DrawingAttributes), Json)
                == JsonSerializer.Serialize(Attributes(right[i].DrawingAttributes), Json);
        }
        return new { MaximumCoordinateDeltaDip = coordinate, MaximumCoordinateDeltaHimetric = coordinate / DipPerHimetric,
            MaximumPressureDelta = pressure, MaximumWidthDeltaDip = width, MaximumHeightDeltaDip = height,
            DrawingAttributesExactlyEqual = attributesEqual };
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
        Require(left > 0 && top > 0 && right < PixelWidth - 1 && bottom < PixelHeight - 1,
            "Authored ink touches the viewport boundary.");
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using (var stream = new FileStream(path, FileMode.CreateNew)) encoder.Save(stream);
        var receipt = new
        {
            Path = Path.GetFileName(path), PngSha256 = Sha(File.ReadAllBytes(path)),
            PixelSha256 = Sha(pixels), NonWhitePixelCount = count,
            NonWhiteBoundsPixels = new[] { left, top, right + 1, bottom + 1 },
        };
        return new(pixels, receipt);
    }

    private static int ChangedPixels(byte[] a, byte[] b)
    {
        Require(a.Length == b.Length, "Raster dimensions differ.");
        var count = 0;
        for (var at = 0; at < a.Length; at += 4)
            if (!a.AsSpan(at, 4).SequenceEqual(b.AsSpan(at, 4))) count++;
        return count;
    }

    private static double[] Bounds(Rect value) => new[] { value.X, value.Y, value.Width, value.Height };
    private static string Sha(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static void WriteJson(string path, object value) => File.WriteAllText(path, JsonSerializer.Serialize(value, Json) + "\n");
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidDataException(message); }
}
