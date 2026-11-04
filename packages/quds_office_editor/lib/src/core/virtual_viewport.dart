import 'dart:math' as math;
import 'dart:ui';

/// 2D axis-aligned virtualization with an overscan buffer.
class VirtualViewport {
  /// VirtualViewport API.
  VirtualViewport({
    this.overscan = 64,
    this.origin = Offset.zero,
    this.extent = Size.zero,
    this.scale = 1,
    this.clampMin = minScale,
    this.clampMax = maxScale,
  });

  /// overscan API.
  double overscan;

  /// origin API.
  Offset origin;

  /// extent API.
  Size extent;

  /// scale API.
  double scale;

  /// Per-viewport lower zoom bound.
  double clampMin;

  /// Per-viewport upper zoom bound.
  double clampMax;

  /// Default lower zoom bound (also the initial [clampMin]).
  static const double minScale = 0.25;

  /// Default upper zoom bound (also the initial [clampMax]).
  static const double maxScale = 4;

  /// setScale API.
  void setScale(double value) {
    scale = value.clamp(clampMin, clampMax);
  }

  /// Apply host zoom limits from viewer options.
  void applyZoomLimits({required double min, required double max}) {
    clampMin = min;
    clampMax = max < min ? min : max;
    scale = scale.clamp(clampMin, clampMax);
  }

  /// visible API.
  Rect get visible => Rect.fromLTWH(
    origin.dx - overscan,
    origin.dy - overscan,
    extent.width + overscan * 2,
    extent.height + overscan * 2,
  );

  /// pan API.
  void pan(Offset delta) {
    origin += delta;
  }

  /// Keeps [origin] inside the document so the user cannot scroll forever.
  void clampTo({required Size content, required Size view, double pad = 0}) {
    final double maxX = math.max(0, content.width - view.width + pad);
    final double maxY = math.max(0, content.height - view.height + pad);
    origin = Offset(origin.dx.clamp(-pad, maxX), origin.dy.clamp(-pad, maxY));
  }

  /// zoomAt API.
  void zoomAt(Offset focal, double factor) {
    origin = Offset(
      focal.dx - (focal.dx - origin.dx) * factor,
      focal.dy - (focal.dy - origin.dy) * factor,
    );
  }

  /// intersects API.
  bool intersects(Rect box) => visible.overlaps(box);

  /// Visible integer range along one axis given [sizes] starting at [start].
  (int, int) visibleSpan(List<double> sizes, double start) {
    var cursor = start;
    var first = 0;
    var last = sizes.length;
    for (int i = 0; i < sizes.length; i++) {
      if (cursor + sizes[i] >= visible.top && first == 0 && i > 0) {
        first = i;
      }
      if (cursor > visible.bottom) {
        last = i;
        break;
      }
      cursor += sizes[i];
    }
    return (math.max(0, first), math.min(sizes.length, last));
  }
}
