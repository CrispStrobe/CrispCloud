import '../interp/pdf_display_list.dart';
import '../model/pdf_file.dart';

/// Isolate (or sync) result of opening a PDF.
class PdfOpenPayload {
  /// PdfOpenPayload API.
  const PdfOpenPayload({required this.file, required this.lists});

  /// file API.
  final PdfFile file;

  /// lists API.
  final List<PdfDisplayList> lists;
}
