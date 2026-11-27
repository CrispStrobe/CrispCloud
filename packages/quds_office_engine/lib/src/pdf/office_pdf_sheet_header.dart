part of 'office_pdf_export.dart';

typedef _SheetPrintStyle = ({
  double size,
  String color,
  String? family,
  bool bold,
  bool italic,
});

typedef _SheetPrintRun = ({String text, _SheetPrintStyle style});

/// Interpret the text and font codes in one left, center, or right section.
List<List<_SheetPrintRun>> _sheetPrintLines(
  String template,
  _SheetPrintStyle initial, {
  required String sheetName,
  required String fileName,
  required int page,
  required int pageCount,
}) {
  final lines = <List<_SheetPrintRun>>[<_SheetPrintRun>[]];
  final text = StringBuffer();
  var style = initial;
  final explicitColor = RegExp(r'^[0-9a-fA-F]{6}$');
  void flush() {
    if (text.isEmpty) return;
    lines.last.add((text: text.toString(), style: style));
    text.clear();
  }

  void format({
    double? size,
    String? color,
    String? family,
    bool? bold,
    bool? italic,
  }) {
    flush();
    style = (
      size: size ?? style.size,
      color: color ?? style.color,
      family: family ?? style.family,
      bold: bold ?? style.bold,
      italic: italic ?? style.italic,
    );
  }

  var index = 0;
  while (index < template.length) {
    final ch = template[index++];
    if (ch == '\r') continue;
    if (ch == '\n') {
      flush();
      lines.add(<_SheetPrintRun>[]);
      continue;
    }
    if (ch != '&' || index == template.length) {
      text.write(ch);
      continue;
    }
    final code = template[index++];
    switch (code) {
      case '&':
        text.write('&');
      case 'A':
        text.write(sheetName);
      case 'F':
        text.write(fileName);
      case 'P':
        text.write(page);
      case 'N':
        text.write(pageCount);
      case 'D':
        final now = DateTime.now();
        text.write('${now.year}-${_two(now.month)}-${_two(now.day)}');
      case 'T':
        final now = DateTime.now();
        text.write('${_two(now.hour)}:${_two(now.minute)}');
      case '"':
        final end = template.indexOf('"', index);
        if (end < 0) {
          index = template.length;
          continue;
        }
        final value = template.substring(index, end);
        final comma = value.lastIndexOf(',');
        final family = comma < 0 ? value : value.substring(0, comma);
        final variant = comma < 0
            ? null
            : value.substring(comma + 1).toLowerCase();
        index = end + 1;
        format(
          family: family.isEmpty || family == '-' ? null : family,
          bold: variant == null
              ? null
              : variant.contains('bold') ||
                    variant.contains('fett') ||
                    variant.contains('gras'),
          italic: variant == null
              ? null
              : variant.contains('italic') ||
                    variant.contains('kursiv') ||
                    variant.contains('italique'),
        );
      case 'B':
        format(bold: !style.bold);
      case 'I':
        format(italic: !style.italic);
      case 'K':
        final end = math.min(index + 6, template.length);
        final value = template.substring(index, end);
        index = end;
        if (explicitColor.hasMatch(value)) format(color: value);
      default:
        // The remaining supported visual slot ('&G') is painted separately.
        if (_sheetPrintDigit(code.codeUnitAt(0))) {
          final start = index - 1;
          while (index < template.length &&
              _sheetPrintDigit(template.codeUnitAt(index))) {
            index++;
          }
          final points = int.tryParse(template.substring(start, index));
          if (points != null && points >= 1 && points <= 409) {
            format(size: points.toDouble());
          }
        }
    }
  }
  flush();
  return lines;
}

bool _sheetPrintDigit(int code) => code >= 0x30 && code <= 0x39;

String _two(int number) => number.toString().padLeft(2, '0');
