using System.Text.Json;
using System.Security.Cryptography;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using DocumentFormat.OpenXml.Wordprocessing;

// External schema/semantic validator, independent of Quds' own XML reader.
// API: https://learn.microsoft.com/office/open-xml/word/how-to-validate-a-word-processing-document
var validator = new OpenXmlValidator(FileFormatVersions.Office2019);
if (args.Length == 1 && args[0] == "--self-test")
{
    RunSelfTests(validator);
    return 0;
}
if (args.Length != 2)
{
    Console.Error.WriteLine("Usage: OfficeValidation INPUT_DIRECTORY REPORT.json");
    return 64;
}
var reports = new List<object>();
var failures = 0;
var paths = DiscoverOfficeFiles(args[0]);
if (paths.Count == 0) throw new Exception("No Office outputs to validate");
foreach (var path in paths)
{
    string? sha256 = null;
    try
    {
        // Bind the validation receipt to the exact bytes inspected, so a
        // renderer cannot reuse a passing receipt after an output changes.
        var bytes = File.ReadAllBytes(path);
        sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        using var input = new MemoryStream(bytes, writable: false);
        using OpenXmlPackage package = OpenOfficePackage(input, path);
        var errors = validator.Validate(package).Select(e => new
        {
            e.Id, e.Description, Type = e.ErrorType.ToString(),
            Part = e.Part?.Uri.ToString(), XPath = e.Path?.XPath,
        }).ToList();
        failures += errors.Count;
        reports.Add(new { File = path, Sha256 = sha256, Errors = errors });
        Console.WriteLine($"{path}: {errors.Count} validation errors");
        foreach (var e in errors.Take(20)) Console.WriteLine($"  {e.Id}: {e.Description} [{e.Part} {e.XPath}]");
    }
    catch (Exception error)
    {
        failures++;
        reports.Add(new { File = path, Sha256 = sha256, Exception = error.ToString() });
        Console.Error.WriteLine($"{path}: {error.Message}");
    }
}
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);
File.WriteAllText(args[1], JsonSerializer.Serialize(new { Files = paths.Count, Failures = failures, Reports = reports },
    new JsonSerializerOptions { WriteIndented = true }));
return failures == 0 ? 0 : 1;

static WordprocessingDocumentType? ExpectedWordType(string extension) => extension switch
{
    ".docx" => WordprocessingDocumentType.Document,
    ".docm" => WordprocessingDocumentType.MacroEnabledDocument,
    ".dotx" => WordprocessingDocumentType.Template,
    ".dotm" => WordprocessingDocumentType.MacroEnabledTemplate,
    _ => null,
};

static List<string> DiscoverOfficeFiles(string directory) =>
    Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories)
        .Where(path =>
        {
            var extension = Path.GetExtension(path).ToLowerInvariant();
            return ExpectedWordType(extension) is not null || extension is ".xlsx" or ".pptx";
        }).Order().ToList();

static OpenXmlPackage OpenOfficePackage(Stream input, string path)
{
    var extension = Path.GetExtension(path).ToLowerInvariant();
    if (ExpectedWordType(extension) is { } expected)
    {
        var document = WordprocessingDocument.Open(input, false);
        if (document.DocumentType != expected)
        {
            var actual = document.DocumentType;
            document.Dispose();
            throw new InvalidDataException(
                $"Word package type {actual} does not match {extension} (expected {expected}): {path}");
        }
        return document;
    }
    return extension switch
    {
        ".xlsx" => SpreadsheetDocument.Open(input, false),
        ".pptx" => PresentationDocument.Open(input, false),
        _ => throw new NotSupportedException(path),
    };
}

static byte[] WordControl(WordprocessingDocumentType type, bool invalid)
{
    using var bytes = new MemoryStream();
    using (var document = WordprocessingDocument.Create(bytes, type))
    {
        var main = document.AddMainDocumentPart();
        main.Document = new Document(new Body(new Paragraph(new Run(new Text("Valid")))));
        if (invalid) main.Document.Body!.AppendChild(new Text("Invalid direct child of body"));
    }
    return bytes.ToArray();
}

static void RunSelfTests(OpenXmlValidator validator)
{
    // These are public format contracts, independent of the production suffix
    // resolver. Exercise discovery and the real read-only package opener too.
    var formats = new[]
    {
        (Extension: ".docx", Type: WordprocessingDocumentType.Document),
        (Extension: ".docm", Type: WordprocessingDocumentType.MacroEnabledDocument),
        (Extension: ".dotx", Type: WordprocessingDocumentType.Template),
        (Extension: ".dotm", Type: WordprocessingDocumentType.MacroEnabledTemplate),
    };
    var temporary = Directory.CreateTempSubdirectory("office-validation-self-test-");
    try
    {
        var expectedPaths = new HashSet<string>();
        var positive = 0;
        var invalidXml = 0;
        var mismatchedTypes = 0;
        foreach (var format in formats)
        {
            var validBytes = WordControl(format.Type, invalid: false);
            foreach (var extension in new[] { format.Extension, format.Extension.ToUpperInvariant() })
            {
                var letterCase = extension == format.Extension ? "lower" : "upper";
                var path = Path.Combine(temporary.FullName, "valid-" + letterCase + "-" + format.Extension[1..] + extension);
                File.WriteAllBytes(path, validBytes);
                expectedPaths.Add(path);
                using var input = File.OpenRead(path);
                using var document = OpenOfficePackage(input, path);
                if (validator.Validate(document).Any())
                    throw new Exception($"Positive {extension} control rejected");
                positive++;
            }

            var invalidPath = Path.Combine(temporary.FullName, "invalid" + format.Extension);
            File.WriteAllBytes(invalidPath, WordControl(format.Type, invalid: true));
            expectedPaths.Add(invalidPath);
            using (var input = File.OpenRead(invalidPath))
            using (var document = OpenOfficePackage(input, invalidPath))
            {
                if (!validator.Validate(document).Any())
                    throw new Exception($"Invalid XML {format.Extension} control accepted");
                invalidXml++;
            }

            foreach (var other in formats.Where(other => other.Type != format.Type))
            {
                var path = Path.Combine(temporary.FullName, "mislabeled-" + format.Extension[1..] + other.Extension);
                File.WriteAllBytes(path, validBytes);
                expectedPaths.Add(path);
                var rejected = false;
                try
                {
                    using var input = File.OpenRead(path);
                    using var document = OpenOfficePackage(input, path);
                }
                catch (InvalidDataException)
                {
                    rejected = true;
                }
                if (!rejected)
                    throw new Exception($"Mislabeled {format.Extension} as {other.Extension} control accepted");
                mismatchedTypes++;
            }
        }
        File.WriteAllText(Path.Combine(temporary.FullName, "ignored.txt"), "Not an Office output");
        var discovered = DiscoverOfficeFiles(temporary.FullName);
        if (discovered.Count != expectedPaths.Count || !expectedPaths.SetEquals(discovered))
            throw new Exception("Office discovery omitted a Word type/case or included an unrelated file");
        Console.WriteLine($"Open XML SDK controls passed: {positive} valid Word packages, " +
            $"{invalidXml} invalid XML, {mismatchedTypes} mismatched types, and exact discovery.");
    }
    finally
    {
        temporary.Delete(recursive: true);
    }
}
