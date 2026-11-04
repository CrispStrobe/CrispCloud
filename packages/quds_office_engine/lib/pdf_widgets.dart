/// Flutter-like PDF widgets. Pure Dart — no `dart:ui`.
///
/// ```dart
/// import 'package:quds_office_engine/pdf_widgets.dart' as pw;
///
/// final doc = pw.Document(title: 'Invoice');
/// doc.addPage(
///   pw.MultiPage(
///     pageFormat: pw.PdfPageFormat.a4,
///     build: (context) => <pw.Widget>[
///       pw.Header(level: 1, text: 'Invoice'),
///       pw.Paragraph(text: 'Payable on receipt.'),
///     ],
///   ),
/// );
/// final bytes = doc.save();
/// ```
///
/// The writer types ([PdfDocument], [PdfPage], [PdfCanvas]) stay separate.
/// Subclass [Widget] and implement [Widget.layout] for custom boxes.
library;

export 'src/builders/office_markup.dart' show ChartPoint;
export 'src/pdf/widgets/pw_barcode.dart';
export 'src/pdf/widgets/pw_box.dart';
export 'src/pdf/widgets/pw_chrome.dart';
export 'src/pdf/widgets/pw_content.dart';
export 'src/pdf/widgets/pw_core.dart';
export 'src/pdf/widgets/pw_flutter.dart';
export 'src/pdf/widgets/pw_layout.dart';
export 'src/pdf/widgets/pw_media.dart';
export 'src/pdf/widgets/pw_qr.dart';
export 'src/pdf/widgets/pw_style.dart';
export 'src/pdf/widgets/pw_svg.dart';
export 'src/pdf/widgets/pw_table.dart';
export 'src/pdf/widgets/pw_text.dart';
export 'src/pdf/widgets/pw_types.dart';
