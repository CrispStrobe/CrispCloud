using System.Text.Json;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using DocumentFormat.OpenXml.Wordprocessing;

// External schema/semantic validator, independent of Quds' own XML reader.
// API: https://learn.microsoft.com/office/open-xml/word/how-to-validate-a-word-processing-document
var validator = new OpenXmlValidator(FileFormatVersions.Office2019);
if (args.Length == 1 && args[0] == "--self-test")
{
    using var bytes = new MemoryStream();
    using var document = WordprocessingDocument.Create(bytes, WordprocessingDocumentType.Document);
    var main = document.AddMainDocumentPart();
    main.Document = new Document(new Body(new Paragraph(new Run(new Text("Valid")))));
    if (validator.Validate(document).Any()) throw new Exception("Positive control rejected");
    main.Document.Body!.AppendChild(new Text("Invalid direct child of body"));
    if (!validator.Validate(document).Any()) throw new Exception("Negative control accepted");
    Console.WriteLine("Open XML SDK positive and negative controls passed.");
    return 0;
}
if (args.Length != 2)
{
    Console.Error.WriteLine("Usage: OfficeValidation INPUT_DIRECTORY REPORT.json");
    return 64;
}
var reports = new List<object>();
var failures = 0;
var paths = Directory.EnumerateFiles(args[0], "*", SearchOption.AllDirectories)
    .Where(p => new[] { ".docx", ".xlsx", ".pptx" }.Contains(Path.GetExtension(p))).Order().ToList();
if (paths.Count == 0) throw new Exception("No Office outputs to validate");
foreach (var path in paths)
{
    try
    {
        using OpenXmlPackage package = Path.GetExtension(path) switch
        {
            ".docx" => WordprocessingDocument.Open(path, false),
            ".xlsx" => SpreadsheetDocument.Open(path, false),
            ".pptx" => PresentationDocument.Open(path, false),
            _ => throw new NotSupportedException(path),
        };
        var errors = validator.Validate(package).Select(e => new
        {
            e.Id, e.Description, Type = e.ErrorType.ToString(),
            Part = e.Part?.Uri.ToString(), XPath = e.Path?.XPath,
        }).ToList();
        failures += errors.Count;
        reports.Add(new { File = path, Errors = errors });
        Console.WriteLine($"{path}: {errors.Count} validation errors");
        foreach (var e in errors.Take(20)) Console.WriteLine($"  {e.Id}: {e.Description} [{e.Part} {e.XPath}]");
    }
    catch (Exception error)
    {
        failures++;
        reports.Add(new { File = path, Exception = error.ToString() });
        Console.Error.WriteLine($"{path}: {error.Message}");
    }
}
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);
File.WriteAllText(args[1], JsonSerializer.Serialize(new { Files = paths.Count, Failures = failures, Reports = reports },
    new JsonSerializerOptions { WriteIndented = true }));
return failures == 0 ? 0 : 1;
