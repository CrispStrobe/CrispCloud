/// Constraint-laid [Table] for PDF pages (aligned with package:pdf ideas).
library;

import '../../pdf/pdf_canvas.dart';
import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// How a cell sits inside its row height (package:pdf `TableCellVerticalAlignment`).
enum TableCellVerticalAlignment {
  /// Top of the row.
  top,

  /// Vertically centered.
  middle,

  /// Bottom of the row.
  bottom,

  /// Child is re-laid out to the full cell size (fills background).
  full,
}

/// Table cell wrapping a child widget.
class TableCell {
  /// TableCell API.
  const TableCell({required this.child, this.colSpan = 1, this.fill});

  /// child API.
  final Widget child;

  /// colSpan API.
  final int colSpan;

  /// fill API.
  final String? fill;
}

/// Table row. Same role as Flutter / `package:pdf` [TableRow].
class TableRow {
  /// TableRow API.
  const TableRow({
    this.children = const <Widget>[],
    this.repeat = false,
    this.decoration,
    this.verticalAlignment,
  });

  /// children API.
  final List<Widget> children;

  /// When true, painted as a header row (reserved for multi-page repeat).
  final bool repeat;

  /// Painted behind the whole row (alternating fills, header band).
  final BoxDecoration? decoration;

  /// Overrides [Table.defaultVerticalAlignment] for this row.
  final TableCellVerticalAlignment? verticalAlignment;
}

/// Interior + exterior borders for a [Table] (package:pdf [TableBorder]).
class TableBorder {
  /// TableBorder API.
  const TableBorder({
    this.left = BorderSide.none,
    this.top = BorderSide.none,
    this.right = BorderSide.none,
    this.bottom = BorderSide.none,
    this.horizontalInside = BorderSide.none,
    this.verticalInside = BorderSide.none,
  });

  /// Uniform border on every edge and divider.
  factory TableBorder.all({
    String color = '000000',
    double width = 0.4,
  }) {
    final BorderSide side = BorderSide(color: color, width: width);
    return TableBorder(
      left: side,
      top: side,
      right: side,
      bottom: side,
      horizontalInside: side,
      verticalInside: side,
    );
  }

  /// Same styling inside and outside.
  factory TableBorder.symmetric({
    BorderSide inside = BorderSide.none,
    BorderSide outside = BorderSide.none,
  }) {
    return TableBorder(
      left: outside,
      top: outside,
      right: outside,
      bottom: outside,
      horizontalInside: inside,
      verticalInside: inside,
    );
  }

  /// left API.
  final BorderSide left;

  /// top API.
  final BorderSide top;

  /// right API.
  final BorderSide right;

  /// bottom API.
  final BorderSide bottom;

  /// horizontalInside API.
  final BorderSide horizontalInside;

  /// verticalInside API.
  final BorderSide verticalInside;
}

/// Column sizing strategy (package:pdf [TableColumnWidth]).
abstract class TableColumnWidth {
  /// TableColumnWidth API.
  const TableColumnWidth();

  /// Intrinsic or fixed contribution before flex distribution.
  ({double width, double flex}) measure(
    Widget child,
    Context context,
    BoxConstraints constraints,
  );
}

/// Size to the child's intrinsic width; optional flex for leftover space.
class IntrinsicColumnWidth extends TableColumnWidth {
  /// IntrinsicColumnWidth API.
  const IntrinsicColumnWidth({this.flex});

  /// flex API.
  final double? flex;

  @override
  ({double width, double flex}) measure(
    Widget child,
    Context context,
    BoxConstraints constraints,
  ) {
    if (flex != null) {
      return (width: 0, flex: flex!);
    }
    final PwBox box = child.layout(context, const BoxConstraints());
    final double w = box.size.width.isFinite ? box.size.width : 0;
    return (width: w, flex: w <= 0 ? 1 : 0);
  }
}

/// Fixed point width.
class FixedColumnWidth extends TableColumnWidth {
  /// FixedColumnWidth API.
  const FixedColumnWidth(this.width);

  /// width API.
  final double width;

  @override
  ({double width, double flex}) measure(
    Widget child,
    Context context,
    BoxConstraints constraints,
  ) {
    return (width: width, flex: 0);
  }
}

/// Flex share of remaining width after fixed columns.
class FlexColumnWidth extends TableColumnWidth {
  /// FlexColumnWidth API.
  const FlexColumnWidth([this.flex = 1]);

  /// flex API.
  final double flex;

  @override
  ({double width, double flex}) measure(
    Widget child,
    Context context,
    BoxConstraints constraints,
  ) {
    return (width: 0, flex: flex);
  }
}

/// Fraction of the table's max width.
class FractionColumnWidth extends TableColumnWidth {
  /// FractionColumnWidth API.
  const FractionColumnWidth(this.value);

  /// value API.
  final double value;

  @override
  ({double width, double flex}) measure(
    Widget child,
    Context context,
    BoxConstraints constraints,
  ) {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth * value : 0;
    return (width: w, flex: 0);
  }
}

/// Grid table with optional borders and flex column widths.
class Table extends Widget {
  /// Table API.
  const Table({
    this.children = const <TableRow>[],
    this.border = true,
    this.tableBorder,
    this.columnWidths,
    this.columnWidthSpec,
    this.defaultColumnWidth,
    this.defaultColumnWidthSpec = const FlexColumnWidth(),
    this.borderColor = '90A4AE',
    this.defaultVerticalAlignment = TableCellVerticalAlignment.full,
  });

  /// fromTextArray API — mirrors package:pdf [TableHelper.fromTextArray].
  factory Table.fromTextArray({
    List<String>? headers,
    required List<List<String>> data,
    bool border = true,
    TableBorder? tableBorder,
    List<double>? columnWidths,
    Map<int, TableColumnWidth>? columnWidthSpec,
    TextStyle? headerStyle,
    TextStyle? cellStyle,
    TextStyle? oddCellStyle,
    AlignmentGeometry headerAlignment = Alignment.center,
    AlignmentGeometry cellAlignment = AlignmentDirectional.topStart,
    Map<int, AlignmentGeometry>? cellAlignments,
    Map<int, AlignmentGeometry>? headerAlignments,
    EdgeInsets cellPadding = const EdgeInsets.all(5),
    EdgeInsets? headerPadding,
    double cellHeight = 0,
    double? headerHeight,
    String? headerDecoration,
    String? headerCellDecoration,
    String? rowDecoration,
    String? oddRowDecoration,
    TableCellVerticalAlignment verticalAlignment =
        TableCellVerticalAlignment.full,
  }) {
    headerPadding ??= cellPadding;
    headerHeight ??= cellHeight;
    // Match package:pdf: only zebra when the caller asks for it.
    final String? oddBand = oddRowDecoration;
    final String? evenBand = rowDecoration;
    oddCellStyle ??= cellStyle;
    final Map<int, AlignmentGeometry> cellAlign =
        cellAlignments ?? const <int, AlignmentGeometry>{};
    final Map<int, AlignmentGeometry> headerAlign =
        headerAlignments ?? cellAlign;

    final List<TableRow> rows = <TableRow>[];
    if (headers != null) {
      rows.add(
        TableRow(
          repeat: true,
          decoration: BoxDecoration(
            color: headerDecoration ?? '1A237E',
          ),
          verticalAlignment: verticalAlignment,
          children: <Widget>[
            for (int i = 0; i < headers.length; i++)
              Container(
                color: headerCellDecoration,
                padding: headerPadding,
                alignment: headerAlign[i] ?? headerAlignment,
                constraints: headerHeight > 0
                    ? BoxConstraints(minHeight: headerHeight)
                    : null,
                child: Text(
                  headers[i],
                  style:
                      headerStyle ??
                      const TextStyle(
                        color: 'FFFFFF',
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                ),
              ),
          ],
        ),
      );
    }
    for (int r = 0; r < data.length; r++) {
      final bool odd = r.isOdd;
      final String? band = odd ? oddBand : evenBand;
      rows.add(
        TableRow(
          decoration: band == null ? null : BoxDecoration(color: band),
          verticalAlignment: verticalAlignment,
          children: <Widget>[
            for (int c = 0; c < data[r].length; c++)
              Container(
                padding: cellPadding,
                alignment: cellAlign[c] ?? cellAlignment,
                constraints: cellHeight > 0
                    ? BoxConstraints(minHeight: cellHeight)
                    : null,
                child: Text(
                  data[r][c],
                  style: (odd ? oddCellStyle : cellStyle) ??
                      const TextStyle(fontSize: 10),
                ),
              ),
          ],
        ),
      );
    }
    return Table(
      children: rows,
      border: border,
      tableBorder: tableBorder,
      columnWidths: columnWidths,
      columnWidthSpec: columnWidthSpec,
      borderColor: '90A4AE',
      defaultVerticalAlignment: verticalAlignment,
    );
  }

  /// children API.
  final List<TableRow> children;

  /// When true and [tableBorder] is null, draws a simple grid.
  final bool border;

  /// Rich border (overrides [border] / [borderColor] when non-null).
  final TableBorder? tableBorder;

  /// Flex weights, or point widths when any value is `> 10`.
  final List<double>? columnWidths;

  /// Per-column width strategies (package:pdf style). Takes precedence when set.
  final Map<int, TableColumnWidth>? columnWidthSpec;

  /// defaultColumnWidth API (legacy flex weight).
  final double? defaultColumnWidth;

  /// Default strategy when [columnWidthSpec] omits a column.
  final TableColumnWidth defaultColumnWidthSpec;

  /// borderColor API.
  final String borderColor;

  /// defaultVerticalAlignment API.
  final TableCellVerticalAlignment defaultVerticalAlignment;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    if (children.isEmpty) {
      return EmptyBox();
    }
    var cols = 1;
    for (final TableRow row in children) {
      if (row.children.length > cols) {
        cols = row.children.length;
      }
    }
    final double maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 400;
    final List<double> widths = _resolveWidths(context, cols, maxW, constraints);
    final List<List<PwBox>> cells = <List<PwBox>>[];
    final List<double> rowH = <double>[];
    final List<TableCellVerticalAlignment> aligns =
        <TableCellVerticalAlignment>[];

    // Pass 1: measure with tight column width (height unconstrained).
    for (final TableRow row in children) {
      final TableCellVerticalAlignment align =
          row.verticalAlignment ?? defaultVerticalAlignment;
      aligns.add(align);
      final List<PwBox> measured = <PwBox>[];
      var h = 0.0;
      for (int c = 0; c < cols; c++) {
        final Widget child = c < row.children.length
            ? row.children[c]
            : const SizedBox.shrink();
        final PwBox box = child.layout(
          context,
          BoxConstraints.tightFor(width: widths[c]),
        );
        measured.add(box);
        if (box.size.height > h) {
          h = box.size.height;
        }
      }
      rowH.add(h < 14 ? 14 : h);
      cells.add(measured);
    }

    // Pass 2: re-layout to full cell size when alignment is [full]
    // (package:pdf default for fromTextArray — fills cell backgrounds).
    for (int r = 0; r < children.length; r++) {
      if (aligns[r] != TableCellVerticalAlignment.full) {
        continue;
      }
      final TableRow row = children[r];
      final List<PwBox> laid = <PwBox>[];
      for (int c = 0; c < cols; c++) {
        final Widget child = c < row.children.length
            ? row.children[c]
            : const SizedBox.shrink();
        laid.add(
          child.layout(
            context,
            BoxConstraints.tight(PwSize(widths[c], rowH[r])),
          ),
        );
      }
      cells[r] = laid;
    }

    var totalH = 0.0;
    for (final double h in rowH) {
      totalH += h;
    }
    final bool rtl = context.textDirection == TextDirection.rtl;
    final List<double> placedWidths = rtl
        ? widths.reversed.toList(growable: false)
        : widths;
    final List<List<PwBox>> placedCells = rtl
        ? <List<PwBox>>[
            for (final List<PwBox> row in cells) row.reversed.toList(),
          ]
        : cells;
    return _TableBox(
      constraints.constrain(PwSize(maxW, totalH)),
      placedWidths,
      rowH,
      placedCells,
      aligns,
      children,
      border,
      tableBorder,
      borderColor,
    );
  }

  /// Splits a tall table across [MultiPage] pages, repeating `repeat` header rows.
  @override
  SpanSlice? layoutSpan(Context context, BoxConstraints constraints) {
    if (children.isEmpty) {
      return SpanSlice(EmptyBox(), null);
    }
    if (!constraints.hasBoundedHeight) {
      return SpanSlice(layout(context, constraints), null);
    }
    final List<TableRow> headers = <TableRow>[
      for (final TableRow row in children)
        if (row.repeat) row,
    ];
    final List<TableRow> body = <TableRow>[
      for (final TableRow row in children)
        if (!row.repeat) row,
    ];
    if (body.isEmpty) {
      return SpanSlice(layout(context, constraints), null);
    }
    final double maxW =
        constraints.hasBoundedWidth ? constraints.maxWidth : 400;
    final List<double> headerH = _rowHeights(context, headers, maxW);
    final List<double> bodyH = _rowHeights(context, body, maxW);
    var chrome = 0.0;
    for (final double h in headerH) {
      chrome += h;
    }
    final double limit = constraints.maxHeight;
    var take = 0;
    var used = chrome;
    for (int i = 0; i < body.length; i++) {
      final double next = used + bodyH[i];
      if (take > 0 && next > limit + 0.5) {
        break;
      }
      used = next;
      take++;
      if (take == 1 && used > limit) {
        break;
      }
    }
    if (take <= 0) {
      take = 1;
    }
    if (take >= body.length) {
      return SpanSlice(layout(context, constraints), null);
    }
    final Table slice = _copyWith(<TableRow>[
      ...headers,
      ...body.take(take),
    ]);
    final Table rest = _copyWith(<TableRow>[
      ...headers,
      ...body.skip(take),
    ]);
    return SpanSlice(
      slice.layout(
        context,
        BoxConstraints(maxWidth: maxW),
      ),
      rest,
    );
  }

  Table _copyWith(List<TableRow> rows) {
    return Table(
      children: rows,
      border: border,
      tableBorder: tableBorder,
      columnWidths: columnWidths,
      columnWidthSpec: columnWidthSpec,
      defaultColumnWidth: defaultColumnWidth,
      defaultColumnWidthSpec: defaultColumnWidthSpec,
      borderColor: borderColor,
      defaultVerticalAlignment: defaultVerticalAlignment,
    );
  }

  List<double> _rowHeights(Context context, List<TableRow> rows, double maxW) {
    if (rows.isEmpty) {
      return const <double>[];
    }
    var cols = 1;
    for (final TableRow row in rows) {
      if (row.children.length > cols) {
        cols = row.children.length;
      }
    }
    final List<double> widths = _resolveWidths(
      context,
      cols,
      maxW,
      BoxConstraints(maxWidth: maxW),
    );
    final List<double> heights = <double>[];
    for (final TableRow row in rows) {
      var h = 0.0;
      for (int c = 0; c < cols; c++) {
        final Widget child = c < row.children.length
            ? row.children[c]
            : const SizedBox.shrink();
        final PwBox box = child.layout(
          context,
          BoxConstraints.tightFor(width: widths[c]),
        );
        if (box.size.height > h) {
          h = box.size.height;
        }
      }
      heights.add(h < 14 ? 14 : h);
    }
    return heights;
  }

  List<double> _resolveWidths(
    Context context,
    int cols,
    double maxW,
    BoxConstraints constraints,
  ) {
    final Map<int, TableColumnWidth>? spec = columnWidthSpec;
    if (spec != null && spec.isNotEmpty) {
      final List<double> flex = List<double>.filled(cols, 0);
      final List<double> widths = List<double>.filled(cols, 0);
      for (int c = 0; c < cols; c++) {
        final TableColumnWidth strategy = spec[c] ?? defaultColumnWidthSpec;
        // Probe with an empty child when the column has no cells yet.
        Widget probe = const SizedBox.shrink();
        for (final TableRow row in children) {
          if (c < row.children.length) {
            probe = row.children[c];
            break;
          }
        }
        final ({double width, double flex}) m =
            strategy.measure(probe, context, constraints);
        widths[c] = m.width;
        flex[c] = m.flex;
      }
      var fixed = 0.0;
      var flexSum = 0.0;
      for (int c = 0; c < cols; c++) {
        if (flex[c] <= 0) {
          fixed += widths[c];
        } else {
          flexSum += flex[c];
        }
      }
      final double leftover = (maxW - fixed).clamp(0, maxW);
      if (flexSum > 0) {
        for (int c = 0; c < cols; c++) {
          if (flex[c] > 0) {
            widths[c] = leftover * flex[c] / flexSum;
          }
        }
      } else if (fixed > 0 && fixed != maxW) {
        for (int c = 0; c < cols; c++) {
          widths[c] = maxW * widths[c] / fixed;
        }
      } else {
        for (int c = 0; c < cols; c++) {
          widths[c] = maxW / cols;
        }
      }
      return widths;
    }
    return _colWidths(cols, maxW);
  }

  List<double> _colWidths(int cols, double maxW) {
    final List<double>? given = columnWidths;
    if (given == null || given.isEmpty) {
      final double w = maxW / cols;
      return <double>[for (int i = 0; i < cols; i++) w];
    }
    final List<double> raw = <double>[
      for (int i = 0; i < cols; i++)
        i < given.length ? given[i] : (defaultColumnWidth ?? 1),
    ];
    var points = false;
    for (final double v in raw) {
      if (v > 10) {
        points = true;
        break;
      }
    }
    if (points) {
      var sum = 0.0;
      for (final double v in raw) {
        sum += v;
      }
      if (sum <= 0) {
        return <double>[for (int i = 0; i < cols; i++) maxW / cols];
      }
      return <double>[for (final double v in raw) maxW * v / sum];
    }
    var flex = 0.0;
    for (final double v in raw) {
      flex += v;
    }
    if (flex <= 0) {
      return <double>[for (int i = 0; i < cols; i++) maxW / cols];
    }
    return <double>[for (final double v in raw) maxW * v / flex];
  }
}

class _TableBox extends PwBox {
  _TableBox(
    super.size,
    this.widths,
    this.rowH,
    this.cells,
    this.aligns,
    this.rows,
    this.border,
    this.tableBorder,
    this.borderColor,
  );

  final List<double> widths;
  final List<double> rowH;
  final List<List<PwBox>> cells;
  final List<TableCellVerticalAlignment> aligns;
  final List<TableRow> rows;
  final bool border;
  final TableBorder? tableBorder;
  final String borderColor;

  @override
  void paint(Context context, PwOffset offset) {
    var y = offset.dy;
    for (int r = 0; r < cells.length; r++) {
      final BoxDecoration? rowDeco = rows[r].decoration;
      if (rowDeco != null) {
        _paintRowDecoration(context, offset.dx, y, size.width, rowH[r], rowDeco);
      }
      var x = offset.dx;
      final TableCellVerticalAlignment align = aligns[r];
      for (int c = 0; c < cells[r].length; c++) {
        final PwBox cell = cells[r][c];
        var cy = y;
        if (align != TableCellVerticalAlignment.full) {
          final double gap = rowH[r] - cell.size.height;
          cy = switch (align) {
            TableCellVerticalAlignment.middle => y + gap / 2,
            TableCellVerticalAlignment.bottom => y + gap,
            TableCellVerticalAlignment.top ||
            TableCellVerticalAlignment.full => y,
          };
        }
        cell.paint(context, PwOffset(x, cy));
        x += widths[c];
      }
      y += rowH[r];
    }
    _paintBorders(context, offset);
  }

  void _paintRowDecoration(
    Context context,
    double x,
    double y,
    double w,
    double h,
    BoxDecoration decoration,
  ) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null || decoration.color == null) {
      return;
    }
    canvas.endText();
    canvas.fillRect(x, y, w, h, decoration.color!);
  }

  void _paintBorders(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    final TableBorder? rich = tableBorder;
    if (rich != null) {
      canvas.endText();
      _strokeSide(
        canvas,
        rich.top,
        offset.dx,
        offset.dy,
        offset.dx + size.width,
        offset.dy,
      );
      _strokeSide(
        canvas,
        rich.bottom,
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height,
      );
      _strokeSide(
        canvas,
        rich.left,
        offset.dx,
        offset.dy,
        offset.dx,
        offset.dy + size.height,
      );
      _strokeSide(
        canvas,
        rich.right,
        offset.dx + size.width,
        offset.dy,
        offset.dx + size.width,
        offset.dy + size.height,
      );
      var gy = offset.dy;
      for (int r = 0; r < rowH.length - 1; r++) {
        gy += rowH[r];
        _strokeSide(
          canvas,
          rich.horizontalInside,
          offset.dx,
          gy,
          offset.dx + size.width,
          gy,
        );
      }
      var gx = offset.dx;
      for (int c = 0; c < widths.length - 1; c++) {
        gx += widths[c];
        _strokeSide(
          canvas,
          rich.verticalInside,
          gx,
          offset.dy,
          gx,
          offset.dy + size.height,
        );
      }
      return;
    }
    if (!border) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(borderColor);
    canvas.setLineWidth(0.4);
    canvas.rect(offset.dx, offset.dy, size.width, size.height);
    canvas.stroke();
    var gy = offset.dy;
    for (int r = 0; r < rowH.length - 1; r++) {
      gy += rowH[r];
      canvas.moveTo(offset.dx, gy);
      canvas.lineTo(offset.dx + size.width, gy);
      canvas.stroke();
    }
    var gx = offset.dx;
    for (int c = 0; c < widths.length - 1; c++) {
      gx += widths[c];
      canvas.moveTo(gx, offset.dy);
      canvas.lineTo(gx, offset.dy + size.height);
      canvas.stroke();
    }
  }

  void _strokeSide(
    PdfCanvas canvas,
    BorderSide side,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    if (side.width <= 0) {
      return;
    }
    canvas.setStrokeColor(side.color);
    canvas.setLineWidth(side.width);
    canvas.moveTo(x1, y1);
    canvas.lineTo(x2, y2);
    canvas.stroke();
  }
}
