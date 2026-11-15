import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfRect, PdfAnnotationEditing;

/// Immutable text geometry belonging to one PDF revision. A note is /Contents
/// on a highlight with the selection's QuadPoints, rather than a loose icon.
class PdfSelectionNote {
  PdfSelectionNote.capture(this.controller, Map<int, List<PdfRect>> rectangles)
    : revision = controller.revisionId,
      quads = Map.unmodifiable({
        for (final entry in rectangles.entries)
          if (entry.value.isNotEmpty)
            entry.key: List<PdfRect>.unmodifiable(entry.value),
      });

  final PdfEditingController controller;
  final int revision;
  final Map<int, List<PdfRect>> quads;
  bool get isEmpty => quads.isEmpty;

  bool attach(String text) {
    if (text.trim().isEmpty || isEmpty) return false;
    if (controller.revisionId != revision) {
      throw StateError('The PDF changed. Select the text again.');
    }
    for (final entry in quads.entries) {
      if (entry.key < 0 ||
          entry.key >= controller.document.pageCount ||
          entry.value.any(
            (r) =>
                !r.left.isFinite ||
                !r.right.isFinite ||
                !r.top.isFinite ||
                !r.bottom.isFinite ||
                r.width <= 0 ||
                r.height <= 0,
          )) {
        throw const FormatException('Invalid PDF selection geometry.');
      }
    }
    return controller.apply((editor) {
      for (final entry in quads.entries) {
        editor.addHighlight(
          entry.key,
          entry.value,
          color: 0xFFD54F,
          opacity: 0.35,
          contents: text.trim(),
          author: controller.preferences.author,
        );
      }
    });
  }
}
