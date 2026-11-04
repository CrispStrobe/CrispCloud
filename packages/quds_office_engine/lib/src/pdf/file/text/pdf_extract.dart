import '../interp/pdf_display_list.dart';
import '../model/pdf_extra.dart';
import '../model/pdf_file.dart';

/// Text helpers for an opened [PdfFile].
abstract final class PdfExtract {
  /// pageText API.
  static String pageText(PdfFile file, int pageIndex) {
    final PdfDisplayList list = file.displayList(pageIndex);
    if (file.redactions.isEmpty) {
      return list.plainText;
    }
    final StringBuffer buf = StringBuffer();
    for (final PdfTextRun run in list.runs) {
      if (_hidden(file, pageIndex, run.x, run.y, run.width, run.height)) {
        continue;
      }
      if (buf.isNotEmpty && run.breakBefore) {
        buf.write('\n');
      }
      buf.write(run.text);
    }
    return buf.toString();
  }

  static bool _hidden(
    PdfFile file,
    int page,
    double x,
    double y,
    double w,
    double h,
  ) {
    for (final PdfRedactRect r in file.redactions) {
      if (r.pageIndex != page) {
        continue;
      }
      final bool overlap =
          x < r.rect.x + r.rect.width &&
          x + w > r.rect.x &&
          y < r.rect.y + r.rect.height &&
          y + h > r.rect.y;
      if (overlap) {
        return true;
      }
    }
    return false;
  }

  /// documentText API.
  static String documentText(PdfFile file) {
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < file.pageCount; i++) {
      final String text = pageText(file, i);
      if (text.isEmpty) {
        continue;
      }
      if (buf.isNotEmpty) {
        buf.write('\n');
      }
      buf.write(text);
    }
    return buf.toString();
  }

  /// PDF/UA reading order from `/StructTreeRoot` when it carries text.
  static String readingOrder(PdfFile file) {
    final PdfStructNode? root = file.structTree;
    if (root == null) {
      return documentText(file);
    }
    final StringBuffer buf = StringBuffer();
    void walk(PdfStructNode node) {
      if (node.actualText.isNotEmpty) {
        if (buf.isNotEmpty) {
          buf.write('\n');
        }
        buf.write(node.actualText);
        return;
      }
      if (node.alt.isNotEmpty) {
        if (buf.isNotEmpty) {
          buf.write('\n');
        }
        buf.write(node.alt);
        return;
      }
      for (final PdfStructNode kid in node.kids) {
        walk(kid);
      }
    }

    walk(root);
    final String tagged = buf.toString().trim();
    return tagged.isEmpty ? documentText(file) : tagged;
  }

  /// paragraphs API.
  static List<String> paragraphs(PdfFile file) {
    return <String>[
      for (int i = 0; i < file.pageCount; i++)
        ...pageText(file, i)
            .split(RegExp(r'\n+'))
            .where((String line) => line.trim().isNotEmpty),
    ];
  }
}
