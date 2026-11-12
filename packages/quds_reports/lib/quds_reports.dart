/// Band reports: `.qrep` templates, expressions, Arabic Tafqeet, pagination,
/// charts, shape maps, and PDF, XLSX, and DOCX export.
///
/// ```dart
/// import 'package:quds_reports/quds_reports.dart';
///
/// final QudsReportEngine engine = QudsReportEngine.fromPackage(qrepBytes);
/// final Uint8List pdf = await engine.exportToPdf(data);
/// ```
///
/// One import covers the template model, the XML parser and writer, the
/// expression engine, data and sample schemas, embedded images and fonts,
/// the paginating generator, and the three exporters. [PdfSaveOptions] is
/// included because PDF export takes it. [SfntFont], [BrokenLine], and
/// [ShapedGlyph] are included because font registration and laid-out lines
/// name them.
///
/// The same objects are the ones [QudsReportDesigner] edits. A Flutter host
/// imports `package:quds_office_editor/quds_reports.dart` and receives this
/// library together with the designer, the data explorer, and the bundled
/// templates.
library;

export 'package:quds_office_engine/quds_office_engine.dart'
    show BrokenLine, PdfSaveOptions, SfntFont, ShapedGlyph;
export 'package:quds_office_engine/quds_reports.dart';
