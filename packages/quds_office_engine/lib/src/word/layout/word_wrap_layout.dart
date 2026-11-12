part of 'word_layout.dart';

/// One available horizontal interval at the requested line's page position.
typedef _WrapBand = ({double left, double width, double y});

/// Exclude already anchored frames from subsequent body flow on this page.
///
/// Square wrap uses the widest remaining interval (direction breaks ties).
/// Top/bottom wrap excludes the whole intersected column. When no interval can
/// fit, advance to the nearest frame bottom and retry; page/column movement is
/// still handled by the normal paragraph flow and clears old page exclusions.
_WrapBand _frameWrapBand(
  List<LaidOutBox> frames, {
  required double left,
  required double width,
  required double y,
  required double height,
  required bool rightToLeft,
  double minimumWidth = 12,
}) {
  final right = left + width;
  var top = y;
  while (true) {
    var intervals = <({double left, double right})>[(left: left, right: right)];
    var nextBottom = double.infinity;
    for (final box in frames) {
      final frame = box.frame;
      if (frame == null ||
          frame.wrap == WmlFrameWrap.none ||
          box.width <= 0 ||
          box.height <= 0 ||
          box.y + box.height <= top + 0.001 ||
          box.y >= top + height - 0.001 ||
          box.x + box.width <= left ||
          box.x >= right) {
        continue;
      }
      nextBottom = math.min(nextBottom, box.y + box.height);
      if (frame.wrap == WmlFrameWrap.topBottom) {
        intervals.clear();
        continue;
      }
      final remaining = <({double left, double right})>[];
      for (final interval in intervals) {
        if (box.x >= interval.right || box.x + box.width <= interval.left) {
          remaining.add(interval);
          continue;
        }
        if (box.x > interval.left) {
          remaining.add((left: interval.left, right: box.x));
        }
        if (box.x + box.width < interval.right) {
          remaining.add((left: box.x + box.width, right: interval.right));
        }
      }
      intervals = remaining;
    }
    intervals.sort((a, b) {
      final byWidth = (b.right - b.left).compareTo(a.right - a.left);
      if (byWidth != 0) return byWidth;
      return rightToLeft ? b.left.compareTo(a.left) : a.left.compareTo(b.left);
    });
    if (intervals.isNotEmpty &&
        intervals.first.right - intervals.first.left >= minimumWidth - 0.001) {
      final chosen = intervals.first;
      return (left: chosen.left, width: chosen.right - chosen.left, y: top);
    }
    if (!nextBottom.isFinite) return (left: left, width: width, y: top);
    top = nextBottom;
  }
}
