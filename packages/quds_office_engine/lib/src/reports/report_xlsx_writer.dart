/// Writes the logical report flow to an XLSX worksheet.
library;

import 'dart:typed_data';

import '../builders/xlsx_io.dart';
import 'arabic_tafqeet.dart';
import 'report_chart.dart';
import 'report_layout.dart';
import 'report_template.dart';
import 'report_units.dart';
import 'report_value.dart';

/// Data-oriented Excel export of a laid-out report.
///
/// Band texts become rows (side-by-side elements share a row, mapped to the
/// columns under them); table rows become real rows with typed cells — numbers
/// stay numeric with a number format derived from the cell `format`, dates
/// become Excel serials. Charts become native Excel charts. Images, barcodes,
/// and non-line shapes are drawings. A text-only page header or footer becomes
/// the sheet header or footer.
class ReportXlsxWriter {
  /// ReportXlsxWriter API.
  const ReportXlsxWriter();

  /// Serializes [layout] as a single-sheet workbook.
  Uint8List write(ReportDocumentLayout layout) {
    final ReportTemplate t = layout.template;
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    final XlsxSheetBuilder sheet = book.addSheet(
      t.name.isEmpty ? 'Report' : t.name,
    );
    sheet.rightToLeft = t.isRtl;
    final _Columns columns = _Columns.of(layout);
    for (int c = 0; c < columns.count; c++) {
      sheet.colWidth(c, _excelWidth(columns.widths[c]));
    }
    sheet.oddHeader = _bandPlainText(t.band(ReportBandKind.pageHeader));
    sheet.oddFooter = _bandPlainText(t.band(ReportBandKind.pageFooter));
    final _Writer w = _Writer(book, sheet, columns, t);
    ReportFlowEntry? previous;
    for (final ReportFlowEntry entry in layout.flow) {
      final bool switched =
          previous != null &&
          (previous is ReportFlowTableRow) != (entry is ReportFlowTableRow);
      if (switched) {
        w.row++;
      }
      switch (entry) {
        case ReportFlowBand():
          w.band(entry);
        case ReportFlowTableRow():
          w.tableRow(entry);
      }
      previous = entry;
    }
    return book.build();
  }

  static String? _bandPlainText(ReportBand? band) {
    if (band == null) {
      return null;
    }
    final StringBuffer buf = StringBuffer();
    for (final ReportElement e in band.elements) {
      if (e is ReportTextElement && e.plainText.trim().isNotEmpty) {
        if (buf.isNotEmpty) {
          buf.write(' ');
        }
        buf.write(e.plainText.trim());
      }
    }
    final String text = buf.toString();
    return text.isEmpty ? null : text;
  }

  static double _excelWidth(double points) {
    final double chars = (points * 4 / 3 - 5) / 7;
    return chars.clamp(3, 120).toDouble();
  }
}

/// Sheet column geometry in page points (logical column order).
class _Columns {
  _Columns(this.lefts, this.widths, {required this.rtl});

  /// Columns under the first detail table, or six equal content columns.
  factory _Columns.of(ReportDocumentLayout layout) {
    final ReportTemplate t = layout.template;
    for (final ReportFlowEntry e in layout.flow) {
      if (e is ReportFlowTableRow && e.band == ReportBandKind.detail) {
        return _fromTable(t, e.table, e.columnWidths);
      }
    }
    for (final ReportFlowEntry e in layout.flow) {
      if (e is ReportFlowBand) {
        for (final ReportFlowItem item in e.items) {
          if (item is ReportFlowTableBlock && item.rows.isNotEmpty) {
            return _fromTable(
              t,
              item.rows.first.table,
              item.rows.first.columnWidths,
            );
          }
        }
      }
    }
    const int n = 6;
    final double w = t.contentWidth / n;
    return _Columns(
      <double>[
        for (int i = 0; i < n; i++)
          t.isRtl
              ? t.margins.left + t.contentWidth - (i + 1) * w
              : t.margins.left + i * w,
      ],
      List<double>.filled(n, w),
      rtl: t.isRtl,
    );
  }

  static _Columns _fromTable(
    ReportTemplate t,
    ReportTableElement table,
    List<double> widths,
  ) {
    var total = 0.0;
    for (final double w in widths) {
      total += w;
    }
    final double x0 = t.elementLeft(table.x, total);
    final List<double> lefts = <double>[];
    var acc = 0.0;
    for (final double w in widths) {
      lefts.add(t.isRtl ? x0 + total - acc - w : x0 + acc);
      acc += w;
    }
    return _Columns(lefts, widths, rtl: t.isRtl);
  }

  final List<double> lefts;
  final List<double> widths;
  final bool rtl;

  int get count => widths.length;

  /// Logical column whose span contains page x [x] (nearest when outside).
  int columnAt(double x) {
    var best = 0;
    var bestDist = double.infinity;
    for (int i = 0; i < count; i++) {
      final double l = lefts[i];
      final double r = l + widths[i];
      if (x >= l && x <= r) {
        return i;
      }
      final double d = x < l ? l - x : x - r;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// First and last logical column covered by [rect].
  (int, int) span(ReportRect rect) {
    final int a = columnAt(rtl ? rect.right - 0.5 : rect.left + 0.5);
    final int b = columnAt(rtl ? rect.left + 0.5 : rect.right - 0.5);
    return a <= b ? (a, b) : (b, a);
  }
}

class _Writer {
  _Writer(this.book, this.sheet, this.columns, this.t);

  final XlsxWorkbookBuilder book;
  final XlsxSheetBuilder sheet;
  final _Columns columns;
  final ReportTemplate t;
  int row = 0;

  void band(ReportFlowBand entry) {
    final List<ReportFlowItem> items =
        <ReportFlowItem>[
          for (final ReportFlowItem i in entry.items)
            if (i is ReportFlowText && i.text.trim().isNotEmpty)
              i
            else if (i is ReportFlowTableBlock)
              i
            else if (i is ReportFlowChart && !i.data.isEmpty)
              i
            else if (i is ReportFlowImage)
              i,
        ]..sort(
          (ReportFlowItem a, ReportFlowItem b) =>
              a.rect.top.compareTo(b.rect.top),
        );
    var i = 0;
    while (i < items.length) {
      final ReportFlowItem first = items[i];
      if (first is ReportFlowTableBlock) {
        for (final ReportFlowTableRow r in first.rows) {
          tableRow(r);
        }
        i++;
        continue;
      }
      if (first is ReportFlowChart) {
        _chart(first);
        i++;
        continue;
      }
      if (first is ReportFlowImage) {
        final (int col, int _) = columns.span(first.rect);
        sheet.addPicture(
          row: row,
          col: col,
          widthPoints: first.rect.width,
          heightPoints: first.rect.height,
          bytes: first.bytes,
        );
        row++;
        i++;
        continue;
      }
      final List<ReportFlowText> cluster = <ReportFlowText>[];
      final double top = first.rect.top;
      while (i < items.length) {
        final ReportFlowItem item = items[i];
        if (item is! ReportFlowText || (item.rect.top - top).abs() > 3) {
          break;
        }
        cluster.add(item);
        i++;
      }
      _textRow(cluster);
    }
  }

  void _textRow(List<ReportFlowText> cluster) {
    cluster.sort(
      (ReportFlowText a, ReportFlowText b) => columns.rtl
          ? b.rect.right.compareTo(a.rect.right)
          : a.rect.left.compareTo(b.rect.left),
    );
    final List<bool> used = List<bool>.filled(columns.count, false);
    var height = 0.0;
    for (int k = 0; k < cluster.length; k++) {
      final ReportFlowText item = cluster[k];
      var (int from, int to) = columns.span(item.rect);
      while (from < columns.count && used[from]) {
        from++;
      }
      if (from >= columns.count) {
        from = columns.count - 1;
      }
      if (to < from) {
        to = from;
      }
      if (cluster.length == 1) {
        to = columns.count - 1;
      }
      for (int c = from + 1; c <= to; c++) {
        if (used[c]) {
          to = c - 1;
          break;
        }
      }
      for (int c = from; c <= to; c++) {
        used[c] = true;
      }
      final (Object? value, String? numFmt) = _cellValue(
        item.value,
        item.format,
        item.text,
      );
      final int style = book.style(
        bold: item.font.bold,
        size: item.font.size,
        color: 'FF${item.color.hex}',
        fillRgb: item.background == null || item.background!.alpha == 0
            ? null
            : 'FF${item.background!.hex}',
        horizontal: _horizontal(item.align),
        wrap: true,
        numFmt: numFmt,
        rightToLeft: item.rtl,
      );
      sheet.setCell(row, from, value, style: style);
      if (to > from) {
        sheet.merge(row, from, row, to);
      }
      if (item.rect.height > height) {
        height = item.rect.height;
      }
    }
    if (height > 0) {
      sheet.rowHeight(row, height.clamp(12, 409).toDouble());
    }
    row++;
  }

  /// Native chart over blank rows, followed by its data as a typed table.
  void _chart(ReportFlowChart item) {
    final ReportChartData d = item.data;
    final (int col, _) = columns.span(item.rect);
    sheet.addChart(
      row: row,
      col: col,
      widthPoints: item.rect.width,
      heightPoints: item.rect.height,
      chartXml: d.toDrawingml(),
    );
    final int blank = (item.rect.height / _defaultRowHeight).ceil() + 1;
    for (int r = row; r < row + blank; r++) {
      sheet.rowHeight(r, _defaultRowHeight);
    }
    row += blank;
    final int header = book.style(
      bold: true,
      fillRgb: 'FFF2F2F2',
      border: true,
      horizontal: 'center',
      rightToLeft: t.isRtl,
    );
    sheet.setCell(row, col, t.isRtl ? 'الفئة' : 'Category', style: header);
    for (int s = 0; s < d.series.length; s++) {
      final String name = d.series[s].name;
      sheet.setCell(
        row,
        col + 1 + s,
        name.isEmpty ? (t.isRtl ? 'القيمة' : 'Value') : name,
        style: header,
      );
    }
    row++;
    final int label = book.style(border: true, rightToLeft: t.isRtl);
    for (int c = 0; c < d.categories.length; c++) {
      sheet.setCell(row, col, d.categories[c], style: label);
      for (int s = 0; s < d.series.length; s++) {
        final double v = d.series[s].values[c];
        final (Object? value, String? numFmt) = _cellValue(
          ReportNumber(
            v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v,
          ),
          d.valueFormat,
          '$v',
        );
        sheet.setCell(
          row,
          col + 1 + s,
          value,
          style: book.style(
            border: true,
            horizontal: 'right',
            numFmt: numFmt,
            rightToLeft: t.isRtl,
          ),
        );
      }
      row++;
    }
    row++;
  }

  static const double _defaultRowHeight = 15;

  void tableRow(ReportFlowTableRow entry) {
    final int n = entry.cells.length < columns.count
        ? entry.cells.length
        : columns.count;
    final ReportColor? rowFill = entry.fill;
    final ReportTableElement table = entry.table;
    for (int c = 0; c < n; c++) {
      final ReportFlowCell cell = entry.cells[c];
      final ReportColor? fill = cell.background ?? rowFill;
      final (Object? value, String? numFmt) = entry.header
          ? (cell.text, null)
          : _cellValue(cell.value, cell.format, cell.text);
      final int style = book.style(
        bold: cell.bold,
        size: cell.fontSize,
        color: 'FF${cell.color.hex}',
        fillRgb: fill == null || fill.alpha == 0 ? null : 'FF${fill.hex}',
        border: table.showGrid,
        horizontal: _horizontal(cell.align),
        wrap: true,
        numFmt: numFmt,
        rightToLeft: t.isRtl,
      );
      sheet.setCell(row, c, value, style: style);
    }
    sheet.rowHeight(row, entry.height.clamp(12, 409).toDouble());
    row++;
  }

  static String _horizontal(ReportTextAlign a) => switch (a) {
    ReportTextAlign.right => 'right',
    ReportTextAlign.center => 'center',
    ReportTextAlign.justify => 'justify',
    _ => 'left',
  };

  /// Typed cell value plus an Excel number format for [format].
  static (Object?, String?) _cellValue(
    ReportValue value,
    String? format,
    String text,
  ) {
    final String spec = (format ?? '').trim();
    final String kind = spec.contains(':')
        ? spec.substring(0, spec.indexOf(':')).toLowerCase()
        : spec.toLowerCase();
    final String arg = spec.contains(':')
        ? spec.substring(spec.indexOf(':') + 1).trim()
        : '';
    switch (value) {
      case ReportNumber(:final num value):
        final String? fmt = _numberFormat(kind, arg, spec);
        if (fmt == null && spec.isNotEmpty) {
          return (text, null);
        }
        return (value, fmt);
      case ReportDate(:final DateTime value):
        if (spec.isNotEmpty &&
            kind != 'date' &&
            kind != 'datetime' &&
            kind != 'time') {
          return (text, null);
        }
        final String pattern = switch (kind) {
          'time' => 'hh:mm',
          'datetime' => 'yyyy/mm/dd hh:mm',
          _ =>
            value.hour == 0 && value.minute == 0 && value.second == 0
                ? 'yyyy/mm/dd'
                : 'yyyy/mm/dd hh:mm',
        };
        return (_serial(value), pattern);
      case ReportBool(:final bool value):
        return spec.isEmpty ? (value, null) : (text, null);
      case ReportNull():
        return (null, null);
      default:
        return (text, null);
    }
  }

  static String? _numberFormat(String kind, String arg, String spec) {
    String decimals(int n) => n <= 0 ? '' : '.${'0' * n}';
    switch (kind) {
      case '':
        return null;
      case 'currency':
      case 'money':
      case 'currencycode':
        final ArabicCurrency? cur = arg.isEmpty
            ? null
            : ArabicTafqeet.currency(arg);
        final int digits = cur?.fractionDigits ?? 2;
        final String label = kind == 'currencycode'
            ? arg
            : (cur?.symbol ?? arg);
        final String quoted = label.isEmpty
            ? ''
            : ' "${label.replaceAll('"', '')}"';
        return '#,##0${decimals(digits)}$quoted';
      case 'number':
      case 'numeric':
      case 'decimal':
        return '#,##0${decimals(arg.isEmpty ? 2 : int.tryParse(arg) ?? 2)}';
      case 'integer':
      case 'int':
        return '#,##0';
      case 'percent':
      case 'pct':
        return '0${decimals(arg.isEmpty ? 0 : int.tryParse(arg) ?? 0)}%';
    }
    final RegExpMatch? short = RegExp(r'^[nN](\d+)$').firstMatch(spec);
    if (short != null) {
      return '#,##0${decimals(int.parse(short.group(1)!))}';
    }
    if (RegExp(r'^[#0,.\s%]+$').hasMatch(spec)) {
      return spec;
    }
    return null;
  }

  static double _serial(DateTime d) {
    final DateTime utc = DateTime.utc(
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
    );
    return utc.difference(DateTime.utc(1899, 12, 30)).inMilliseconds /
        86400000.0;
  }
}
