import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgBytesLoader, vg;
import 'package:quds_office_engine/quds_office_engine.dart';

import '../editor_word/paint_run_text.dart';
import '../embed/office_host_fonts.dart';

typedef VisualImageDecoder =
    void Function(Uint8List bytes, void Function(ui.Image image) onDecoded);

/// Owns decoded pictures for one Office canvas, including pending decodes.
class VisualImageCache {
  VisualImageCache({VisualImageDecoder? decodeImage, this.decodedByteBudget})
    // Keep the public decoder parameter name independent of its private field.
    // ignore: prefer_initializing_formals
    : _decodeImage = decodeImage;

  final VisualImageDecoder? _decodeImage;

  /// Budget for decoded pixels outside the current viewport.
  final int? decodedByteBudget;
  final Set<Uint8List> _painted = Set<Uint8List>.identity();
  int _decodedBytes = 0;

  static int _decodedSize(ui.Image image) => image.width * image.height * 4;

  /// Optional bounded converter supplied by the embedding app for metafiles.
  static FutureOr<Uint8List?> Function(Uint8List bytes)? metafileAsSvg;

  final Map<Uint8List, ui.Image> _ready = Map<Uint8List, ui.Image>.identity();
  final Set<Uint8List> _loading = Set<Uint8List>.identity();
  final Set<Uint8List> _failed = Set<Uint8List>.identity();
  static final _svgElement = RegExp(r'<(?:[\w.-]+:)?svg[\s/>]');
  static const _maxSvgBytes = 8 * 1024 * 1024;
  static const _maxSvgPixels = 2048;
  bool _disposed = false;

  ui.Image? get(Uint8List bytes) {
    final image = _ready[bytes];
    if (image != null && decodedByteBudget != null) _painted.add(bytes);
    return image;
  }

  /// Release offscreen images after painting. All images drawn in the current
  /// frame stay resident even if a large page temporarily exceeds the budget.
  void endFrame() {
    final budget = decodedByteBudget;
    if (budget == null) return;
    if (_decodedBytes > budget) {
      for (final key in _ready.keys.toList()) {
        if (_decodedBytes <= budget) break;
        if (_painted.contains(key)) continue;
        final image = _ready.remove(key)!;
        _decodedBytes -= _decodedSize(image);
        image.dispose();
      }
    }
    _painted.clear();
  }

  /// load API.
  void load(Uint8List bytes, VoidCallback onReady) {
    if (_disposed ||
        _ready.containsKey(bytes) ||
        _loading.contains(bytes) ||
        _failed.contains(bytes)) {
      return;
    }
    _loading.add(bytes);
    void decoded(ui.Image image) {
      _loading.remove(bytes);
      if (_disposed) {
        image.dispose();
        return;
      }
      _ready[bytes] = image;
      _decodedBytes += _decodedSize(image);
      onReady();
    }

    void failed() {
      _loading.remove(bytes);
      if (!_disposed) _failed.add(bytes);
    }

    final decoder = _decodeImage;
    if (decoder == null) {
      _decodeDefault(bytes, decoded, failed);
    } else {
      var callbackStarted = false;
      try {
        decoder(bytes, (image) {
          callbackStarted = true;
          decoded(image);
        });
      } catch (_) {
        if (callbackStarted) rethrow;
        failed();
      }
    }
  }

  Future<void> _decodeDefault(
    Uint8List bytes,
    void Function(ui.Image) onDecoded,
    VoidCallback onError,
  ) async {
    ui.Image image;
    try {
      final vector = _looksLikeSvg(bytes)
          ? bytes
          : await metafileAsSvg?.call(bytes);
      image = await (vector == null
          ? _decodeRaster(bytes)
          : _rasterizeSvg(vector));
    } catch (_) {
      onError();
      return;
    }
    onDecoded(image);
  }

  static bool _looksLikeSvg(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxSvgBytes) return false;
    final first = bytes.first;
    if (first != 0x3c &&
        first != 0xef &&
        first != 0x20 &&
        (first < 0x09 || first > 0x0d)) {
      return false;
    }
    final prefix = utf8
        .decode(
          Uint8List.sublistView(bytes, 0, math.min(bytes.length, 4096)),
          allowMalformed: true,
        )
        .trimLeft();
    return (prefix.startsWith('<') || prefix.startsWith('\uFEFF')) &&
        _svgElement.hasMatch(prefix);
  }

  static Future<ui.Image> _decodeRaster(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final longest = math.max(descriptor.width, descriptor.height);
        final scale = math.min(1.0, 4096 / longest);
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  static Future<ui.Image> _rasterizeSvg(Uint8List bytes) async {
    // The byte loader resolves inline assets without fetching external URLs.
    final svg = await vg.loadPicture(SvgBytesLoader(bytes), null);
    try {
      final size = svg.size;
      if (!size.isFinite || size.isEmpty) {
        throw const FormatException('Invalid embedded SVG size.');
      }
      final target = (size.longestSide * 2).clamp(256, _maxSvgPixels);
      final scale = target / size.longestSide;
      if (!scale.isFinite) {
        throw const FormatException('Invalid embedded SVG scale.');
      }
      final width = (size.width * scale).ceil().clamp(1, _maxSvgPixels);
      final height = (size.height * scale).ceil().clamp(1, _maxSvgPixels);
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(scale)
        ..drawPicture(svg.picture);
      final scaled = recorder.endRecording();
      try {
        return await scaled.toImage(width, height);
      } finally {
        scaled.dispose();
      }
    } finally {
      svg.picture.dispose();
    }
  }

  /// A late decode must release its image without repainting a disposed owner.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
    _painted.clear();
    _decodedBytes = 0;
    _loading.clear();
    _failed.clear();
  }
}

/// Class PaintOfficeVisual.
abstract final class PaintOfficeVisual {
  /// paint API.
  static void paint(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual, {
    required String fontFamily,
    VisualImageCache? images,
    VoidCallback? onImageReady,
    bool cropPreview = false,
    double shapeRotationDegrees = 0,
  }) {
    switch (visual.kind) {
      case OfficeVisualKind.picture:
        _picture(
          canvas,
          rect,
          visual,
          images,
          onImageReady,
          cropPreview: cropPreview,
          shapeRotationDegrees: shapeRotationDegrees,
        );
      case OfficeVisualKind.chartColumn:
        _column(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartBar:
        _bar(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartPie:
        _pie(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartLine:
        _line(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramProcess:
        _process(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramCycle:
        _cycle(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramHierarchy:
        _hierarchy(canvas, rect, visual, fontFamily);
    }
  }

  static void _picture(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    VisualImageCache? images,
    VoidCallback? onImageReady, {
    bool cropPreview = false,
    required double shapeRotationDegrees,
  }) {
    final Uint8List? bytes = visual.imageBytes;
    if (bytes == null || bytes.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = const Color(0xFFF3F6FB),
      );
      _label(
        canvas,
        rect,
        visual.title.isEmpty ? 'Picture' : visual.title,
        fontSize: 12,
      );
      return;
    }
    if (images == null) {
      return;
    }
    final ui.Image? image = images.get(bytes);
    if (image == null) {
      images.load(bytes, onImageReady ?? () {});
      return;
    }
    final PictureAdjust adj = visual.picture;
    final Rect dest = adj.borderWidth > 0
        ? rect.deflate(adj.borderWidth)
        : rect;
    canvas.save();
    final Offset c = dest.center;
    if (adj.rotationDeg.abs() > 0.05 || adj.flipH || adj.flipV) {
      canvas.translate(c.dx, c.dy);
      if (adj.rotationDeg.abs() > 0.05) {
        canvas.rotate(adj.rotationDeg * math.pi / 180);
      }
      canvas.scale(adj.flipH ? -1 : 1, adj.flipV ? -1 : 1);
      canvas.translate(-c.dx, -c.dy);
    }
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;
    if (adj.brightness.abs() > 0.01 ||
        (adj.contrast - 1).abs() > 0.01 ||
        adj.transparency > 0.001) {
      final double k = adj.contrast;
      final double b = adj.brightness * 255;
      paint.colorFilter = ColorFilter.matrix(<double>[
        k,
        0,
        0,
        0,
        b,
        0,
        k,
        0,
        0,
        b,
        0,
        0,
        k,
        0,
        b,
        0,
        0,
        0,
        1 - adj.transparency,
        0,
      ]);
    }
    final double sl = (image.width * adj.cropLeft).clamp(0, image.width * 0.99);
    final double st = (image.height * adj.cropTop).clamp(
      0,
      image.height * 0.99,
    );
    final double sr = (image.width * adj.cropRight).clamp(
      0,
      image.width * 0.99,
    );
    final double sb = (image.height * adj.cropBottom).clamp(
      0,
      image.height * 0.99,
    );
    if (cropPreview) {
      final double keepW = (1 - adj.cropLeft - adj.cropRight).clamp(0.12, 1);
      final double keepH = (1 - adj.cropTop - adj.cropBottom).clamp(0.12, 1);
      final Rect full = Rect.fromLTWH(
        dest.left - dest.width * adj.cropLeft / keepW,
        dest.top - dest.height * adj.cropTop / keepH,
        dest.width / keepW,
        dest.height / keepH,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        full,
        Paint()..color = const Color(0x99FFFFFF),
      );
    }
    final source = Rect.fromLTWH(
      sl,
      st,
      (image.width - sl - sr).clamp(1, image.width.toDouble()),
      (image.height - st - sb).clamp(1, image.height.toDouble()),
    );
    final matrix = canvas.getTransform();
    final screenWidth =
        dest.width * math.sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]);
    final screenHeight =
        dest.height * math.sqrt(matrix[4] * matrix[4] + matrix[5] * matrix[5]);
    if (source.width > 2 * screenWidth || source.height > 2 * screenHeight) {
      // Mipmaps retain thin marks in highly reduced worksheet art. Bicubic
      // samples a fixed neighborhood and can miss them at those scales.
      paint.filterQuality = FilterQuality.medium;
    }
    if (adj.shadow) {
      final effect = adj.outerShadow;
      final rotation = effect?.rotatesWithShape == false
          ? shapeRotationDegrees + adj.rotationDeg
          : 0;
      final angle =
          ((effect?.directionDegrees ?? 45) - rotation) * math.pi / 180;
      final distance = effect?.distance ?? math.sqrt(8);
      final shadowRect = dest.shift(
        Offset(math.cos(angle) * distance, math.sin(angle) * distance),
      );
      final sigma = effect == null
          ? 3.0
          : (effect.blurRadius / 2).clamp(0.0, 128.0);
      final tint = _hex(effect?.color ?? '000000').withValues(
        alpha: ((effect?.opacity ?? 1 / 3) * (1 - adj.transparency)).clamp(
          0.0,
          1.0,
        ),
      );
      final shadowPaint = Paint()
        ..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn)
        ..filterQuality = paint.filterQuality;
      if (sigma > 0) {
        shadowPaint.imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        );
      }
      // Draw the cropped alpha mask so transparent pixels cast no shadow.
      canvas.drawImageRect(image, source, shadowRect, shadowPaint);
    }
    canvas.drawImageRect(image, source, dest, paint);
    if (adj.borderWidth > 0 && adj.borderColor.isNotEmpty) {
      canvas.drawRect(
        dest.inflate(adj.borderWidth / 2),
        Paint()
          ..color = _hex(adj.borderColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = adj.borderWidth,
      );
    }
    canvas.restore();
  }

  static void _column(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final double gap = 8;
    final double barW = (plot.width - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double h = plot.height * (pts[i].value / maxV);
      final Rect bar = Rect.fromLTWH(
        plot.left + gap + i * (barW + gap),
        plot.bottom - h,
        barW,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = _hex(pts[i].color),
      );
      if (visual.chart.showDataLabels) {
        _label(
          canvas,
          Rect.fromLTWH(bar.left, bar.top - 14, barW, 14),
          pts[i].value.toStringAsFixed(0),
          fontSize: 8,
          fontFamily: fontFamily,
        );
      }
      _label(
        canvas,
        Rect.fromLTWH(bar.left, plot.bottom + 2, barW, 14),
        pts[i].label,
        fontSize: 9,
        fontFamily: fontFamily,
      );
    }
  }

  static void _bar(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final double gap = 6;
    final double barH = (plot.height - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double w = plot.width * (pts[i].value / maxV);
      final Rect bar = Rect.fromLTWH(
        plot.left,
        plot.top + gap + i * (barH + gap),
        w,
        barH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        Rect.fromLTWH(bar.right + 4, bar.top, 48, barH),
        pts[i].label,
        fontSize: 9,
        fontFamily: fontFamily,
        align: TextAlign.left,
      );
    }
  }

  static void _pie(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    final layout = OfficePieLayout(visual, rect.width, rect.height);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFD0D0D0)
        ..style = PaintingStyle.stroke,
    );
    for (final (index, title) in layout.titleLines.indexed) {
      _label(
        canvas,
        Rect.fromLTWH(
          rect.left + 8,
          rect.top + 3 + index * layout.titleSize,
          rect.width - 16,
          layout.titleSize + 5,
        ),
        title,
        fontSize: layout.titleSize,
        fontFamily: fontFamily,
        bold: true,
      );
    }
    final cx = rect.left + layout.cx;
    final cy = rect.top + layout.cy;
    final pie = Rect.fromCircle(center: Offset(cx, cy), radius: layout.radius);
    for (final slice in layout.slices) {
      if (slice.sweep == 0) continue;
      canvas.drawArc(
        pie,
        slice.start,
        slice.sweep,
        true,
        Paint()..color = _hex(slice.point.color),
      );
    }
    for (final slice in layout.slices) {
      if (slice.label.isEmpty) continue;
      final angle = slice.start + slice.sweep / 2;
      final distance = layout.radius * (slice.sweep < .22 ? 1.10 : .73);
      _label(
        canvas,
        Rect.fromCenter(
          center: Offset(
            cx + distance * math.cos(angle),
            cy + distance * math.sin(angle),
          ),
          width: 48,
          height: 12,
        ),
        slice.label,
        fontSize: 9,
        fontFamily: fontFamily,
      );
    }
    for (final entry in layout.legend) {
      final left = rect.left + entry.x;
      final top = rect.top + entry.y;
      canvas.drawRect(
        Rect.fromLTWH(left + 2, top + 4, 6, 6),
        Paint()..color = _hex(entry.point.color),
      );
      _label(
        canvas,
        Rect.fromLTWH(left + 10, top, entry.width - 10, 12),
        entry.point.label,
        fontSize: 8,
        fontFamily: fontFamily,
        align: TextAlign.left,
      );
    }
  }

  static void _line(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    final imported = visual.importedLineChart;
    if (imported != null && rect.width >= 90 && rect.height >= 70) {
      _importedLine(canvas, rect, visual, imported, fontFamily);
      return;
    }
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.length < 2) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final Path path = Path();
    for (int i = 0; i < pts.length; i++) {
      final double x = plot.left + plot.width * i / (pts.length - 1);
      final double y = plot.bottom - plot.height * (pts[i].value / maxV);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = _hex(pts[i].color));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2B579A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _importedLine(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    OfficeLineChart chart,
    String fontFamily,
  ) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFD0D0D0)
        ..style = PaintingStyle.stroke,
    );
    final titleSize = visual.chart.titleSize ?? 11;
    final titleLines = visual.chartTitleLines(rect.width, titleSize);
    for (final (index, title) in titleLines.indexed) {
      _label(
        canvas,
        Rect.fromLTWH(
          rect.left + 8,
          rect.top + 3 + index * titleSize,
          rect.width - 16,
          titleSize + 5,
        ),
        title,
        fontSize: titleSize,
        fontFamily: fontFamily,
        bold: true,
      );
    }
    final plot = Rect.fromLTRB(
      rect.left +
          (visual.chart.showAxes
              ? (visual.chart.valueTitle.isEmpty ? 48 : 63)
              : 10),
      rect.top + (titleLines.isEmpty ? 8 : titleSize * titleLines.length + 13),
      rect.right - 18,
      rect.bottom - (visual.chart.showLegend ? 42 : 24),
    );
    if (plot.isEmpty) return;
    final ticks = chart.axisTicks;
    final limits = (min: ticks.first, max: ticks.last);
    double category(int index) =>
        plot.left + chart.categoryFraction(index) * plot.width;
    double ordinate(double value) =>
        plot.bottom -
        OfficeLineChart.valueFraction(value, limits) * plot.height;
    for (final (tick, value) in ticks.indexed) {
      final y = ordinate(value);
      if (visual.chart.showGridlines || (tick == 0 && visual.chart.showAxes)) {
        canvas.drawLine(
          Offset(plot.left, y),
          Offset(plot.right, y),
          Paint()
            ..color = tick == 0
                ? const Color(0xFF808080)
                : const Color(0xFFD0D0D0),
        );
      }
      if (visual.chart.showAxes) {
        _label(
          canvas,
          Rect.fromLTWH(plot.left - 47, y - 6, 43, 12),
          chart.axisLabel(value),
          fontFamily: fontFamily,
          fontSize: 8,
          align: TextAlign.right,
        );
      }
    }
    if (visual.chart.showAxes) {
      for (final index in chart.labelIndices) {
        _label(
          canvas,
          Rect.fromLTWH(category(index) - 21, plot.bottom, 42, 14),
          chart.categories[index],
          fontFamily: fontFamily,
          fontSize: 8,
        );
      }
      _label(
        canvas,
        Rect.fromLTWH(plot.left, plot.bottom + 12, plot.width, 12),
        visual.chart.categoryTitle,
        fontFamily: fontFamily,
        fontSize: 8,
      );
      if (visual.chart.valueTitle.isNotEmpty) {
        canvas.save();
        canvas.translate(rect.left + 10, plot.center.dy);
        canvas.rotate(-math.pi / 2);
        _label(
          canvas,
          Rect.fromLTWH(-plot.height / 2, -6, plot.height, 12),
          visual.chart.valueTitle,
          fontFamily: fontFamily,
          fontSize: 8,
        );
        canvas.restore();
      }
    }
    canvas.save();
    canvas.clipRect(plot.inflate(3));
    for (final series in chart.series) {
      final color = _hex(series.color ?? series.points.first.color);
      final path = Path();
      int? previous;
      final markers = <Offset>[];
      for (final point in series.points) {
        final index = point.x!.toInt();
        final offset = Offset(category(index), ordinate(point.value));
        if (previous == null || (!chart.connectGaps && index != previous + 1)) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
        markers.add(offset);
        previous = index;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.drawPoints(
        ui.PointMode.points,
        markers,
        Paint()
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4,
      );
    }
    canvas.restore();
    if (visual.chart.showDataLabels) {
      for (final (index, series) in chart.series.indexed) {
        for (final point in series.points) {
          final label = chart.pointLabel(index, point.value);
          if (label.isEmpty) continue;
          final px = category(point.x!.toInt());
          _label(
            canvas,
            Rect.fromLTWH(px - 28, ordinate(point.value) - 14, 56, 11),
            label,
            fontFamily: fontFamily,
            fontSize: 7,
          );
        }
      }
    }
    if (visual.chart.showLegend) {
      final slot = (rect.width - 20) / chart.series.length;
      for (final (index, series) in chart.series.indexed) {
        final left = rect.left + 10 + index * slot;
        if (slot <= 10) break;
        canvas.drawRect(
          Rect.fromLTWH(left, rect.bottom - 11, 6, 6),
          Paint()..color = _hex(series.color ?? series.points.first.color),
        );
        _label(
          canvas,
          Rect.fromLTWH(left + 8, rect.bottom - 15, slot - 8, 13),
          series.name,
          fontFamily: fontFamily,
          fontSize: 8,
          align: TextAlign.left,
        );
      }
    }
  }

  static void _process(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double boxW = math.min(
      110,
      (plot.width - 24 * pts.length) / pts.length,
    );
    final double boxH = 44;
    final double y = plot.center.dy - boxH / 2;
    for (int i = 0; i < pts.length; i++) {
      final double x = plot.left + i * (boxW + 24);
      final Rect box = Rect.fromLTWH(x, y, boxW, boxH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        box,
        pts[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
      if (i < pts.length - 1) {
        final Offset a = Offset(box.right + 2, box.center.dy);
        final Offset b = Offset(box.right + 20, box.center.dy);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          b,
          Offset(b.dx - 6, b.dy - 4),
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          b,
          Offset(b.dx - 6, b.dy + 4),
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  static void _cycle(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final Offset c = plot.center;
    final double r = math.min(plot.width, plot.height) / 2 - 28;
    for (int i = 0; i < pts.length; i++) {
      final double a = -math.pi / 2 + i * (math.pi * 2 / pts.length);
      final Offset p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final Rect box = Rect.fromCenter(center: p, width: 72, height: 28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(14)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        box,
        pts[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
    }
    canvas.drawCircle(
      c,
      18,
      Paint()
        ..color = const Color(0xFF2B579A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _hierarchy(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final Rect root = Rect.fromCenter(
      center: Offset(plot.center.dx, plot.top + 22),
      width: 100,
      height: 28,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(root, const Radius.circular(4)),
      Paint()..color = _hex(pts.first.color),
    );
    _label(
      canvas,
      root,
      pts.first.label,
      fontFamily: fontFamily,
      color: const Color(0xFFFFFFFF),
    );
    final List<ChartPoint> kids = pts.length > 1
        ? pts.sublist(1)
        : <ChartPoint>[];
    if (kids.isEmpty) {
      return;
    }
    final double gap = plot.width / kids.length;
    for (int i = 0; i < kids.length; i++) {
      final Rect child = Rect.fromCenter(
        center: Offset(plot.left + gap * (i + 0.5), plot.bottom - 22),
        width: math.min(90, gap - 8),
        height: 28,
      );
      canvas.drawLine(
        root.bottomCenter,
        child.topCenter,
        Paint()..color = const Color(0xFF888888),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(child, const Radius.circular(4)),
        Paint()..color = _hex(kids[i].color),
      );
      _label(
        canvas,
        child,
        kids[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
    }
  }

  static void _frame(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFF8FAADC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    if (visual.title.isNotEmpty &&
        (!visual.isChart || visual.chart.showTitle)) {
      _label(
        canvas,
        Rect.fromLTWH(rect.left + 8, rect.top + 4, rect.width - 16, 16),
        visual.title,
        fontSize: 11,
        fontFamily: fontFamily,
        align: TextAlign.left,
        bold: true,
      );
    }
    if (visual.chart.showAxes &&
        visual.isChart &&
        visual.kind != OfficeVisualKind.chartPie) {
      final Rect plot = _plot(rect, visual);
      final Paint axis = Paint()
        ..color = const Color(0xFF888888)
        ..strokeWidth = 0.8;
      canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
      canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
      if (visual.chart.showGridlines) {
        final Paint grid = Paint()
          ..color = const Color(0xFFD0D0D0)
          ..strokeWidth = 0.6;
        for (int i = 1; i <= 3; i++) {
          final double y = plot.bottom - plot.height * i / 4;
          canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        }
      }
    }
    if (visual.chart.showLegend &&
        visual.isChart &&
        visual.kind != OfficeVisualKind.chartPie) {
      var x = rect.left + 10;
      final double y = rect.bottom - 16;
      for (final ChartPoint p in visual.points.take(6)) {
        canvas.drawRect(
          Rect.fromLTWH(x, y + 3, 8, 8),
          Paint()..color = _hex(p.color),
        );
        _label(
          canvas,
          Rect.fromLTWH(x + 10, y, 36, 14),
          p.label,
          fontSize: 8,
          fontFamily: fontFamily,
          align: TextAlign.left,
        );
        x += 48;
      }
    }
  }

  /// Plot area inside the frame: title strip on top, category labels below,
  /// plus a legend strip when an axis chart shows its bottom legend.
  static Rect _plot(Rect rect, OfficeVisual visual) {
    final bool legend =
        visual.isChart &&
        visual.chart.showLegend &&
        visual.kind != OfficeVisualKind.chartPie;
    return Rect.fromLTWH(
      rect.left + 10,
      rect.top + 24,
      rect.width - 20,
      rect.height - (legend ? 56 : 40),
    );
  }

  static void _label(
    Canvas canvas,
    Rect rect,
    String text, {
    double fontSize = 11,
    String? fontFamily,
    Color color = const Color(0xFF222222),
    TextAlign align = TextAlign.center,
    bool bold = false,
  }) {
    if (text.isEmpty || rect.width <= 2) {
      return;
    }
    final bool rtl = PaintRunText.looksRtl(text);
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFamily: OfficeHostFonts.paintFamily(
            fontFamily ?? PaintRunText.fontFallbacks.first,
          ),
          fontFamilyFallback: PaintRunText.fontFallbacks,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(
        align == TextAlign.left
            ? rect.left
            : rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  static Color _hex(String hex) {
    final String clean = hex.replaceFirst('#', '');
    return Color(
      0xFF000000 | (int.tryParse(clean.padLeft(6, '0'), radix: 16) ?? 0x4472C4),
    );
  }
}
