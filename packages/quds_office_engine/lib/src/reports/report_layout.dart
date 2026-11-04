/// Paginated output of the report generator: pages of drawing primitives.
///
/// The same layout feeds the PDF writer and the Flutter live preview, so the
/// designer shows exactly the page breaks and line breaks that are exported.
library;

import 'dart:typed_data';

import 'report_chart.dart';
import 'report_fonts.dart';
import 'report_template.dart';
import 'report_units.dart';
import 'report_value.dart';

/// Drawing operation on a page. Coordinates are page points, y down.
sealed class ReportPrimitive {
  const ReportPrimitive({required this.bounds, this.elementId, this.band});

  /// Box covered by the primitive.
  final ReportRect bounds;

  /// Template element that produced it (designer back-reference).
  final String? elementId;

  /// Band that produced it.
  final ReportBandKind? band;
}

/// One styled slice inside a [ReportFlowText].
final class ReportFlowSpan {
  /// ReportFlowSpan API.
  const ReportFlowSpan({
    required this.text,
    required this.font,
    required this.color,
    this.underline = false,
    this.link,
  });

  /// text API.
  final String text;

  /// font API.
  final ReportFontSpec font;

  /// color API.
  final ReportColor color;

  /// underline API.
  final bool underline;

  /// link API.
  final String? link;
}

/// Shaped paragraph inside [contentRect].
final class ReportTextPrimitive extends ReportPrimitive {
  /// ReportTextPrimitive API.
  const ReportTextPrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    required this.text,
    required this.shaped,
    required this.contentRect,
    required this.font,
    required this.color,
    required this.align,
    required this.verticalAlign,
    required this.rtl,
    this.underline = false,
    this.link,
  });

  /// Full logical text.
  final String text;

  /// Lines with metrics.
  final ReportShapedText shaped;

  /// Area inside padding; lines are clipped to it.
  final ReportRect contentRect;

  /// font API.
  final ReportFontSpec font;

  /// color API.
  final ReportColor color;

  /// Physical alignment: left, right, center, or justify.
  final ReportTextAlign align;

  /// verticalAlign API.
  final ReportVerticalAlign verticalAlign;

  /// Paragraph direction.
  final bool rtl;

  /// underline API.
  final bool underline;

  /// URI annotation for this slice. Null is plain text.
  final String? link;

  /// Top of the first line box after vertical alignment.
  double get firstLineTop {
    final double slack = contentRect.height - shaped.height;
    return switch (verticalAlign) {
      ReportVerticalAlign.top => contentRect.top,
      ReportVerticalAlign.middle =>
        contentRect.top + (slack > 0 ? slack / 2 : 0),
      ReportVerticalAlign.bottom => contentRect.top + (slack > 0 ? slack : 0),
    };
  }

  /// Left x of line [index] after horizontal alignment.
  double lineLeft(int index) {
    final ReportTextLine line = shaped.lines[index];
    final double slack = contentRect.width - line.width;
    final bool isLast = index == shaped.lines.length - 1;
    final ReportTextAlign a = align == ReportTextAlign.justify && isLast
        ? (rtl ? ReportTextAlign.right : ReportTextAlign.left)
        : align;
    return switch (a) {
      ReportTextAlign.right => contentRect.left + slack,
      ReportTextAlign.center => contentRect.left + slack / 2,
      ReportTextAlign.justify =>
        rtl ? contentRect.left + (slack > 0 ? slack : 0) : contentRect.left,
      _ => contentRect.left,
    };
  }
}

/// Rectangle, rounded rectangle, or ellipse.
final class ReportRectPrimitive extends ReportPrimitive {
  /// ReportRectPrimitive API.
  const ReportRectPrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.radius = 0,
    this.ellipse = false,
    this.lineStyle = ReportLineStyle.solid,
  });

  /// fill API.
  final ReportColor? fill;

  /// stroke API.
  final ReportColor? stroke;

  /// strokeWidth API.
  final double strokeWidth;

  /// radius API.
  final double radius;

  /// ellipse API.
  final bool ellipse;

  /// lineStyle API.
  final ReportLineStyle lineStyle;
}

/// Straight line.
final class ReportLinePrimitive extends ReportPrimitive {
  /// ReportLinePrimitive API.
  const ReportLinePrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.color,
    required this.width,
    this.lineStyle = ReportLineStyle.solid,
  });

  /// x1 API.
  final double x1;

  /// y1 API.
  final double y1;

  /// x2 API.
  final double x2;

  /// y2 API.
  final double y2;

  /// color API.
  final ReportColor color;

  /// width API.
  final double width;

  /// lineStyle API.
  final ReportLineStyle lineStyle;
}

/// Polyline or polygon (chart lines, areas, and pie wedges).
final class ReportPathPrimitive extends ReportPrimitive {
  /// ReportPathPrimitive API.
  const ReportPathPrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    required this.points,
    this.closed = false,
    this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.lineStyle = ReportLineStyle.solid,
  });

  /// Path through [points] with bounds computed from them.
  factory ReportPathPrimitive.through(
    Float64List points, {
    String? elementId,
    ReportBandKind? band,
    bool closed = false,
    ReportColor? fill,
    ReportColor? stroke,
    double strokeWidth = 0,
    ReportLineStyle lineStyle = ReportLineStyle.solid,
  }) => ReportPathPrimitive(
    bounds: boundsOf(points),
    elementId: elementId,
    band: band,
    points: points,
    closed: closed,
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    lineStyle: lineStyle,
  );

  /// Interleaved x, y vertex coordinates.
  final Float64List points;

  /// Close back to the first vertex (polygons are filled when [fill] is set).
  final bool closed;

  /// fill API.
  final ReportColor? fill;

  /// stroke API.
  final ReportColor? stroke;

  /// strokeWidth API.
  final double strokeWidth;

  /// lineStyle API.
  final ReportLineStyle lineStyle;

  /// Number of vertices.
  int get length => points.length ~/ 2;

  /// Smallest rectangle holding [points].
  static ReportRect boundsOf(Float64List points) {
    if (points.length < 2) {
      return const ReportRect(0, 0, 0, 0);
    }
    var minX = points[0];
    var maxX = points[0];
    var minY = points[1];
    var maxY = points[1];
    for (int i = 2; i + 1 < points.length; i += 2) {
      final double x = points[i];
      final double y = points[i + 1];
      if (x < minX) {
        minX = x;
      } else if (x > maxX) {
        maxX = x;
      }
      if (y < minY) {
        minY = y;
      } else if (y > maxY) {
        maxY = y;
      }
    }
    return ReportRect(minX, minY, maxX - minX, maxY - minY);
  }
}

/// Raster image placed at [imageRect], clipped to [bounds].
final class ReportImagePrimitive extends ReportPrimitive {
  /// ReportImagePrimitive API.
  const ReportImagePrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    required this.bytes,
    required this.imageRect,
    this.cropTop = 0,
    this.cropHeight = 1,
  });

  /// PNG or JPEG bytes.
  final Uint8List bytes;

  /// Fitted destination (may exceed [bounds] for `cover`).
  final ReportRect imageRect;

  /// Fraction of the source skipped above this slice (0–1).
  final double cropTop;

  /// Fraction of the source drawn in [bounds] (1 is the whole image).
  final double cropHeight;
}

/// Barcode modules painted inside [bounds].
final class ReportBarcodePrimitive extends ReportPrimitive {
  /// ReportBarcodePrimitive API.
  const ReportBarcodePrimitive({
    required super.bounds,
    super.elementId,
    super.band,
    required this.symbology,
    required this.color,
    this.modules = const <bool>[],
    this.matrix = const <List<bool>>[],
  });

  /// symbology API.
  final ReportBarcodeType symbology;

  /// color API.
  final ReportColor color;

  /// 1-D modules left to right (Code 128), including quiet zones.
  final List<bool> modules;

  /// 2-D modules, row-major (QR).
  final List<List<bool>> matrix;

  /// Dark module rectangles in page coordinates.
  Iterable<ReportRect> get darkRects sync* {
    if (symbology == ReportBarcodeType.qr) {
      final int n = matrix.length;
      if (n == 0) {
        return;
      }
      final double side = bounds.width < bounds.height
          ? bounds.width
          : bounds.height;
      final double cell = side / (n + 8);
      final double ox = bounds.left + (bounds.width - cell * n) / 2;
      final double oy = bounds.top + (bounds.height - cell * n) / 2;
      for (int r = 0; r < n; r++) {
        final List<bool> row = matrix[r];
        var c = 0;
        while (c < row.length) {
          if (!row[c]) {
            c++;
            continue;
          }
          final int start = c;
          while (c < row.length && row[c]) {
            c++;
          }
          yield ReportRect(
            ox + start * cell,
            oy + r * cell,
            (c - start) * cell,
            cell,
          );
        }
      }
      return;
    }
    if (modules.isEmpty) {
      return;
    }
    final double w = bounds.width / modules.length;
    var i = 0;
    while (i < modules.length) {
      if (!modules[i]) {
        i++;
        continue;
      }
      final int start = i;
      while (i < modules.length && modules[i]) {
        i++;
      }
      yield ReportRect(
        bounds.left + start * w,
        bounds.top,
        (i - start) * w,
        bounds.height,
      );
    }
  }
}

/// Logical content of a band instance, independent of page geometry.
///
/// Flow entries are recorded once per printed band / table row in document
/// order (repeated page headers and continuation table headers are not), so
/// flow-based exporters (XLSX, DOCX) keep values typed and tables real.
sealed class ReportFlowEntry {
  const ReportFlowEntry(this.band);

  /// Source band.
  final ReportBandKind band;
}

/// A printed band with its positioned items (y relative to the band top).
final class ReportFlowBand extends ReportFlowEntry {
  /// ReportFlowBand API.
  const ReportFlowBand(super.band, {required this.height, required this.items});

  /// height API.
  final double height;

  /// items API.
  final List<ReportFlowItem> items;
}

/// Table header, body row, or totals row.
final class ReportFlowTableRow extends ReportFlowEntry {
  /// ReportFlowTableRow API.
  const ReportFlowTableRow(
    super.band, {
    required this.table,
    required this.cells,
    required this.header,
    required this.footer,
    required this.columnWidths,
    required this.height,
    this.fill,
  });

  /// table API.
  final ReportTableElement table;

  /// One cell per column, logical column order.
  final List<ReportFlowCell> cells;

  /// header API.
  final bool header;

  /// footer API.
  final bool footer;

  /// Resolved widths, points.
  final List<double> columnWidths;

  /// Laid-out row height, points.
  final double height;

  /// Row fill (header background or stripe).
  final ReportColor? fill;
}

/// Evaluated table cell.
class ReportFlowCell {
  /// ReportFlowCell API.
  const ReportFlowCell({
    required this.text,
    required this.value,
    required this.format,
    required this.bold,
    required this.italic,
    required this.align,
    required this.color,
    required this.fontSize,
    this.background,
  });

  /// Display text.
  final String text;

  /// Typed value before formatting.
  final ReportValue value;

  /// Format spec (`currency:LYD`), if any.
  final String? format;

  /// bold API.
  final bool bold;

  /// italic API.
  final bool italic;

  /// Physical alignment.
  final ReportTextAlign align;

  /// color API.
  final ReportColor color;

  /// fontSize API.
  final double fontSize;

  /// background API.
  final ReportColor? background;
}

/// Positioned item inside a [ReportFlowBand].
sealed class ReportFlowItem {
  const ReportFlowItem({required this.elementId, required this.rect});

  /// elementId API.
  final String elementId;

  /// Page x, band-relative y.
  final ReportRect rect;
}

/// Evaluated text element.
final class ReportFlowText extends ReportFlowItem {
  /// ReportFlowText API.
  const ReportFlowText({
    required super.elementId,
    required super.rect,
    required this.text,
    required this.value,
    required this.format,
    required this.font,
    required this.color,
    required this.align,
    required this.rtl,
    this.underline = false,
    this.background,
    this.spans = const <ReportFlowSpan>[],
  });

  /// text API.
  final String text;

  /// value API.
  final ReportValue value;

  /// format API.
  final String? format;

  /// font API.
  final ReportFontSpec font;

  /// color API.
  final ReportColor color;

  /// Physical alignment.
  final ReportTextAlign align;

  /// rtl API.
  final bool rtl;

  /// underline API.
  final bool underline;

  /// background API.
  final ReportColor? background;

  /// Mixed slices. Empty means [text] is one run.
  final List<ReportFlowSpan> spans;
}

/// Image element with resolved bytes.
final class ReportFlowImage extends ReportFlowItem {
  /// ReportFlowImage API.
  const ReportFlowImage({
    required super.elementId,
    required super.rect,
    required this.bytes,
  });

  /// bytes API.
  final Uint8List bytes;
}

/// Horizontal rule (a line shape flatter than it is wide).
final class ReportFlowRule extends ReportFlowItem {
  /// ReportFlowRule API.
  const ReportFlowRule({
    required super.elementId,
    required super.rect,
    required this.color,
    required this.width,
  });

  /// color API.
  final ReportColor color;

  /// width API.
  final double width;
}

/// Table printed atomically inside a non-detail band.
final class ReportFlowTableBlock extends ReportFlowItem {
  /// ReportFlowTableBlock API.
  const ReportFlowTableBlock({
    required super.elementId,
    required super.rect,
    required this.rows,
  });

  /// rows API.
  final List<ReportFlowTableRow> rows;
}

/// Chart with its aggregated data (XLSX / DOCX write native charts).
final class ReportFlowChart extends ReportFlowItem {
  /// ReportFlowChart API.
  const ReportFlowChart({
    required super.elementId,
    required super.rect,
    required this.data,
  });

  /// Resolved categories and series.
  final ReportChartData data;
}

/// One output page.
class ReportPageLayout {
  /// ReportPageLayout API.
  ReportPageLayout({
    required this.pageNumber,
    List<ReportPrimitive>? primitives,
  }) : primitives = primitives ?? <ReportPrimitive>[];

  /// 1-based.
  final int pageNumber;

  /// Paint order.
  final List<ReportPrimitive> primitives;
}

/// Complete paginated report.
class ReportDocumentLayout {
  /// ReportDocumentLayout API.
  const ReportDocumentLayout({
    required this.template,
    required this.pageWidth,
    required this.pageHeight,
    required this.pages,
    required this.warnings,
    required this.fonts,
    this.flow = const <ReportFlowEntry>[],
  });

  /// Logical band / table-row stream (see [ReportFlowEntry]).
  final List<ReportFlowEntry> flow;

  /// Source template.
  final ReportTemplate template;

  /// pageWidth API.
  final double pageWidth;

  /// pageHeight API.
  final double pageHeight;

  /// pages API.
  final List<ReportPageLayout> pages;

  /// Non-fatal problems (missing images, unencodable barcodes, …).
  final List<String> warnings;

  /// Fonts used for shaping (the PDF writer embeds the same faces).
  final ReportFontRegistry fonts;
}
