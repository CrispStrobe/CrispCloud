import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../embed/office_theme.dart';
import 'report_layout_painter.dart';
import 'report_pinch_zoom.dart';

/// Paginated live preview of a [ReportDocumentLayout].
class ReportPreviewSurface extends LeafRenderObjectWidget {
  /// ReportPreviewSurface API.
  const ReportPreviewSurface({
    super.key,
    required this.document,
    this.error,
    this.zoom = 1,
    this.theme = OfficeTheme.light,
    this.onZoom,
    this.onPickElement,
  });

  /// Pages to show; null shows [error] (or nothing).
  final ReportDocumentLayout? document;

  /// Generation error message.
  final String? error;

  /// Logical pixels per point.
  final double zoom;

  /// theme API.
  final OfficeTheme theme;

  /// Ctrl + wheel zoom request.
  final ValueChanged<double>? onZoom;

  /// Double-click on output produced by a template element.
  final ValueChanged<String>? onPickElement;

  @override
  RenderReportPreview createRenderObject(BuildContext context) =>
      RenderReportPreview(
        document: document,
        error: error,
        zoom: zoom,
        theme: theme,
        onZoom: onZoom,
        onPickElement: onPickElement,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportPreview renderObject,
  ) {
    renderObject
      ..document = document
      ..error = error
      ..zoom = zoom
      ..theme = theme
      ..onZoom = onZoom
      ..onPickElement = onPickElement;
  }
}

/// RenderBox behind [ReportPreviewSurface].
class RenderReportPreview extends RenderBox {
  /// RenderReportPreview API.
  RenderReportPreview({
    ReportDocumentLayout? document,
    this._error,
    this._zoom = 1,
    required this._theme,
    this.onZoom,
    this.onPickElement,
  }) : _layout = document {
    _painter.onImageReady = markNeedsPaint;
  }

  ReportDocumentLayout? _layout;
  String? _error;
  double _zoom;
  OfficeTheme _theme;

  /// onZoom API.
  ValueChanged<double>? onZoom;

  /// onPickElement API.
  ValueChanged<String>? onPickElement;

  final ReportLayoutPainter _painter = ReportLayoutPainter();
  final Map<String, TextPainter> _labels = <String, TextPainter>{};
  Offset _scroll = Offset.zero;
  Offset? _dragLast;
  late final ReportPinchZoom _pinch = ReportPinchZoom(
    zoom: () => _zoom,
    onZoom: _zoomAround,
    onPinchStart: () => _dragLast = null,
  );

  /// Sets the zoom keeping the content under [focal] in place, then pans by
  /// [pan]. The host gets the new zoom through [onZoom].
  void _zoomAround(double zoom, Offset focal, Offset pan) {
    final double z = zoom.clamp(0.25, 4).toDouble();
    const Offset margin = Offset(gap, gap);
    final Offset content = focal + _scroll - margin;
    final double k = z / _zoom;
    _zoom = z;
    onZoom?.call(z);
    _scroll = margin + content * k - focal - pan;
    _clamp();
    markNeedsPaint();
  }

  Duration _lastTap = Duration.zero;
  Offset _lastTapPos = Offset.zero;

  /// Gap between pages, logical pixels.
  static const double gap = 20;

  /// Pages shown.
  ReportDocumentLayout? get document => _layout;

  set document(ReportDocumentLayout? value) {
    if (identical(value, _layout)) {
      return;
    }
    _layout = value;
    if (hasSize) {
      _clamp();
    }
    markNeedsPaint();
  }

  /// error API.
  String? get error => _error;

  set error(String? value) {
    if (value == _error) {
      return;
    }
    _error = value;
    markNeedsPaint();
  }

  /// zoom API.
  double get zoom => _zoom;

  set zoom(double value) {
    if (value == _zoom) {
      return;
    }
    _zoom = value;
    if (hasSize) {
      _clamp();
    }
    markNeedsPaint();
  }

  /// theme API.
  OfficeTheme get theme => _theme;

  set theme(OfficeTheme value) {
    if (identical(value, _theme)) {
      return;
    }
    _theme = value;
    markNeedsPaint();
  }

  /// Current page (1-based) at the top of the viewport.
  int get currentPage {
    final ReportDocumentLayout? doc = _layout;
    if (doc == null || doc.pages.isEmpty) {
      return 0;
    }
    final double pitch = doc.pageHeight * _zoom + gap;
    final int i = ((_scroll.dy + size.height / 3) / pitch).floor();
    return i.clamp(0, doc.pages.length - 1) + 1;
  }

  /// Scrolls so page [number] (1-based) is at the top.
  void showPage(int number) {
    final ReportDocumentLayout? doc = _layout;
    if (doc == null) {
      return;
    }
    _scroll = Offset(_scroll.dx, (number - 1) * (doc.pageHeight * _zoom + gap));
    _clamp();
    markNeedsPaint();
  }

  @override
  void dispose() {
    _painter.dispose();
    for (final TextPainter tp in _labels.values) {
      tp.dispose();
    }
    _labels.clear();
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size s = constraints.biggest;
    return s.isFinite ? s : constraints.constrain(const Size(900, 700));
  }

  @override
  bool hitTestSelf(Offset position) => true;

  Size get _content {
    final ReportDocumentLayout? doc = _layout;
    if (doc == null) {
      return Size.zero;
    }
    return Size(
      doc.pageWidth * _zoom + 2 * gap,
      doc.pages.length * (doc.pageHeight * _zoom + gap) + gap,
    );
  }

  void _clamp() {
    final Size c = _content;
    _scroll = Offset(
      _scroll.dx.clamp(0, math.max(0, c.width - size.width)).toDouble(),
      _scroll.dy.clamp(0, math.max(0, c.height - size.height)).toDouble(),
    );
  }

  Offset _pageOrigin(int index) {
    final ReportDocumentLayout doc = _layout!;
    final double pw = doc.pageWidth * _zoom;
    final double x = pw + 2 * gap < size.width
        ? (size.width - pw) / 2
        : gap - _scroll.dx;
    final double y = gap + index * (doc.pageHeight * _zoom + gap) - _scroll.dy;
    return Offset(x, y);
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, _onSignal);
      return;
    }
    if (_pinch.handle(event)) {
      return;
    }
    if (event is PointerDownEvent) {
      _dragLast = event.localPosition;
      final bool quick =
          event.timeStamp - _lastTap < const Duration(milliseconds: 400);
      final bool near = (event.localPosition - _lastTapPos).distance < 6;
      _lastTap = event.timeStamp;
      _lastTapPos = event.localPosition;
      if (quick && near) {
        final String? id = elementAt(event.localPosition);
        if (id != null) {
          onPickElement?.call(id);
        }
      }
      return;
    }
    if (event is PointerMoveEvent && _dragLast != null) {
      _scroll -= event.localPosition - _dragLast!;
      _dragLast = event.localPosition;
      _clamp();
      markNeedsPaint();
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _dragLast = null;
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      onZoom?.call(_zoom * (event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1));
      return;
    }
    _scroll += HardwareKeyboard.instance.isShiftPressed
        ? Offset(event.scrollDelta.dy, 0)
        : event.scrollDelta;
    _clamp();
    markNeedsPaint();
  }

  /// Template element id of the topmost output at [local], if any.
  String? elementAt(Offset local) {
    final ReportDocumentLayout? doc = _layout;
    if (doc == null) {
      return null;
    }
    for (int i = 0; i < doc.pages.length; i++) {
      final Offset o = _pageOrigin(i);
      final Offset p = (local - o) / _zoom;
      if (p.dx < 0 ||
          p.dy < 0 ||
          p.dx > doc.pageWidth ||
          p.dy > doc.pageHeight) {
        continue;
      }
      final List<ReportPrimitive> prims = doc.pages[i].primitives;
      for (int k = prims.length - 1; k >= 0; k--) {
        final ReportPrimitive prim = prims[k];
        final ReportRect b = prim.bounds;
        final String? id = prim.elementId;
        if (id != null &&
            p.dx >= b.left &&
            p.dx <= b.right &&
            p.dy >= b.top &&
            p.dy <= b.bottom) {
          return id;
        }
      }
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _theme.canvasBackground,
    );
    final ReportDocumentLayout? doc = _layout;
    if (doc == null) {
      final String message = _error ?? 'Nothing to preview';
      _label(
        message,
        13,
        const Color(0xFFFFFFFF),
        size.width - 40,
      ).paint(canvas, const Offset(20, 20));
      canvas.restore();
      return;
    }
    final double pw = doc.pageWidth * _zoom;
    final double ph = doc.pageHeight * _zoom;
    for (int i = 0; i < doc.pages.length; i++) {
      final Offset o = _pageOrigin(i);
      if (o.dy > size.height || o.dy + ph < 0) {
        continue;
      }
      final Rect page = Rect.fromLTWH(o.dx, o.dy, pw, ph);
      canvas.drawRect(
        page.shift(const Offset(2, 3)),
        Paint()
          ..color = const Color(0x50000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawRect(page, Paint()..color = const Color(0xFFFFFFFF));
      canvas.save();
      canvas.clipRect(page);
      canvas.translate(o.dx, o.dy);
      canvas.scale(_zoom);
      _painter.paintPage(canvas, doc, doc.pages[i]);
      canvas.restore();
    }
    final String status = doc.warnings.isEmpty
        ? 'Page $currentPage of ${doc.pages.length}'
        : 'Page $currentPage of ${doc.pages.length}  ·  '
              '${doc.warnings.length} warning'
              '${doc.warnings.length == 1 ? '' : 's'}: ${doc.warnings.first}';
    final TextPainter tp = _label(
      status,
      11,
      const Color(0xFFFFFFFF),
      size.width - 40,
    );
    final Rect pill = Rect.fromLTWH(
      size.width - tp.width - 28,
      size.height - tp.height - 18,
      tp.width + 16,
      tp.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(6)),
      Paint()..color = const Color(0xB0202020),
    );
    tp.paint(canvas, pill.topLeft + const Offset(8, 4));
    canvas.restore();
  }

  TextPainter _label(String text, double fontSize, Color color, double maxW) {
    final String key = '$text|$fontSize|${color.toARGB32()}|$maxW';
    final TextPainter? hit = _labels[key];
    if (hit != null) {
      return hit;
    }
    if (_labels.length > 64) {
      for (final TextPainter tp in _labels.values) {
        tp.dispose();
      }
      _labels.clear();
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: fontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxW < 40 ? 40 : maxW);
    _labels[key] = tp;
    return tp;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final ReportDocumentLayout? doc = _layout;
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = 'Report preview'
      ..value = doc == null
          ? (_error ?? '')
          : '${doc.pages.length} page${doc.pages.length == 1 ? '' : 's'}';
  }
}
