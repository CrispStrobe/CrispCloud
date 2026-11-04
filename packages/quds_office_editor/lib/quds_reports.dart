/// Flutter band-report designer, together with the report engine.
///
/// ```dart
/// import 'package:quds_office_editor/quds_reports.dart';
///
/// final ReportDesignerController controller =
///     ReportDesignerController.fromXml(xml);
/// QudsReportDesigner(
///   controller: controller,
///   onExport: (ReportExportFormat format, Uint8List bytes) {},
/// );
/// ```
///
/// This library is the designer (canvas, inspector, toolbox, preview, data
/// explorer, bundled fonts, and ready-made templates) plus everything in
/// `package:quds_reports/quds_reports.dart`: `QudsReportEngine`, `.qrep`
/// packages, expressions, and PDF / XLSX / DOCX export. A server or CLI host
/// that does not use Flutter depends on `quds_reports` alone.
library;

export 'package:quds_reports/quds_reports.dart';
export 'src/editor_reports/quds_report_designer.dart';
export 'src/editor_reports/render_report_data_explorer.dart';
export 'src/editor_reports/render_report_designer.dart';
export 'src/editor_reports/render_report_inspector.dart';
export 'src/editor_reports/render_report_preview.dart';
export 'src/editor_reports/render_report_problems.dart';
export 'src/editor_reports/render_report_toolbar.dart';
export 'src/editor_reports/render_report_toolbox.dart';
export 'src/editor_reports/report_bundled_fonts.dart';
export 'src/editor_reports/report_completion_popup.dart';
export 'src/editor_reports/report_design_layout.dart';
export 'src/editor_reports/report_designer_controller.dart';
export 'src/editor_reports/report_designer_strings.dart';
export 'src/editor_reports/report_element_painter.dart';
export 'src/editor_reports/report_layout_painter.dart';
export 'src/editor_reports/report_template_library.dart';
export 'src/editor_sheet/inline_cell_editor.dart';
export 'src/embed/office_theme.dart';
