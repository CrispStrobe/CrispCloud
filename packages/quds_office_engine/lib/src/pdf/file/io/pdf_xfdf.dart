import '../model/pdf_annot.dart';
import '../model/pdf_file.dart';
import '../model/pdf_form.dart';

/// XFDF import/export (ISO 32000-1 §12.7.8 / XFDF spec subset).
abstract final class PdfXfdf {
  /// exportXml API.
  static String exportXml(PdfFile file) {
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<xfdf xmlns="http://ns.adobe.com/xfdf/" xml:space="preserve">\n'
      '<fields>\n',
    );
    for (final PdfFormField field in file.form.fields) {
      buf.write(
        '<field name="${_esc(field.name)}"><value>${_esc(field.value)}</value></field>\n',
      );
    }
    buf.write('</fields>\n<annots>\n');
    for (int p = 0; p < file.pageCount; p++) {
      for (final PdfAnnot annot in file.annotsOn(p)) {
        buf.write(
          '<${annot.subtype.toLowerCase()} page="$p" '
          'rect="${annot.rect.x},${annot.rect.y},'
          '${annot.rect.x + annot.rect.width},${annot.rect.y + annot.rect.height}"'
          ' color="#${annot.color.toRadixString(16).padLeft(8, '0').substring(2)}">',
        );
        if (annot.contents.isNotEmpty) {
          buf.write('<contents>${_esc(annot.contents)}</contents>');
        }
        buf.write('</${annot.subtype.toLowerCase()}>\n');
      }
    }
    buf.write('</annots>\n</xfdf>\n');
    return buf.toString();
  }

  /// Applies field values and simple highlight/text annots from [xml].
  static void importXml(PdfFile file, String xml) {
    final Iterable<RegExpMatch> fields = RegExp(
      r'<field name="([^"]*)">\s*<value>([^<]*)</value>',
    ).allMatches(xml);
    for (final RegExpMatch match in fields) {
      final PdfFormField? field = file.form.field(_unesc(match.group(1)!));
      if (field != null && !field.readOnly) {
        field.value = _unesc(match.group(2)!);
        file.markDirty(field.pageIndex);
      }
    }
    final Iterable<RegExpMatch> annots = RegExp(
      r'<(highlight|text|ink|square|circle) page="(\d+)" rect="([^"]+)"[^>]*>(?:<contents>([^<]*)</contents>)?',
      caseSensitive: false,
    ).allMatches(xml);
    for (final RegExpMatch match in annots) {
      final int page = int.tryParse(match.group(2) ?? '') ?? 0;
      final List<String> parts = (match.group(3) ?? '').split(',');
      if (parts.length < 4) {
        continue;
      }
      final double x = double.tryParse(parts[0]) ?? 0;
      final double y = double.tryParse(parts[1]) ?? 0;
      final double x2 = double.tryParse(parts[2]) ?? x;
      final double y2 = double.tryParse(parts[3]) ?? y;
      final String subtype = _subtype(match.group(1)!);
      file.addAnnot(
        page,
        PdfAnnot(
          id: 0,
          subtype: subtype,
          rect: PdfRect(x: x, y: y, width: x2 - x, height: y2 - y),
          contents: _unesc(match.group(4) ?? ''),
        ),
      );
    }
  }

  static String _subtype(String tag) {
    return switch (tag.toLowerCase()) {
      'highlight' => 'Highlight',
      'text' => 'Text',
      'ink' => 'Ink',
      'square' => 'Square',
      'circle' => 'Circle',
      _ => 'Highlight',
    };
  }

  static String _esc(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _unesc(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&amp;', '&');
  }
}
