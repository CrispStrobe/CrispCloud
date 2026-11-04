import 'dart:math' as math;
import 'dart:ui';

import 'package:quds_office_engine/pdf_file.dart';

/// Shared page-stack metrics for the PDF canvas, thumbs, and [goToPage].
abstract final class PdfPageLayout {
  /// Gap between pages (device pixels).
  static const double gap = 24;

  /// Side inset when the view is wider than the paper.
  static const double gutter = 36;

  /// Overlay scrollbar thickness.
  static const double scrollBar = 14;

  /// CSS pixels per PDF point (same as the Word canvas).
  static const double pointsToPixels = 96 / 72;

  /// viewScale API.
  static double viewScale(double scale) => scale * pointsToPixels;

  /// Content-Y of the top of [index] (including the leading gap).
  static double stackTop(List<PdfDisplayList> lists, int index, double scale) {
    final double vs = viewScale(scale);
    var top = gap;
    final int last = index < lists.length ? index : lists.length;
    for (int i = 0; i < last; i++) {
      top += lists[i].page.height * vs + gap;
    }
    return top;
  }

  /// Content-X of the start of [index] for a horizontal stack.
  static double stackStart(
    List<PdfDisplayList> lists,
    int index,
    double scale,
  ) {
    final double vs = viewScale(scale);
    var left = gutter;
    final int last = index < lists.length ? index : lists.length;
    for (int i = 0; i < last; i++) {
      left += lists[i].page.width * vs + gap;
    }
    return left;
  }

  /// Scrollable document size at [scale].
  static Size contentSize(
    List<PdfDisplayList> lists,
    double scale, {
    bool horizontal = false,
  }) {
    final double vs = viewScale(scale);
    if (horizontal) {
      var maxH = 0.0;
      var w = gutter;
      for (final PdfDisplayList list in lists) {
        maxH = math.max(maxH, list.page.height);
        w += list.page.width * vs + gap;
      }
      if (maxH <= 0) {
        maxH = 842;
      }
      return Size(w + gutter, maxH * vs + gap * 2 + scrollBar);
    }
    var maxW = 0.0;
    var h = gap;
    for (final PdfDisplayList list in lists) {
      maxW = math.max(maxW, list.page.width);
      h += list.page.height * vs + gap;
    }
    if (maxW <= 0) {
      maxW = 595;
    }
    return Size(maxW * vs + gutter * 2 + scrollBar, h);
  }

  /// Page whose band contains content-Y [y].
  static int pageAtY(List<PdfDisplayList> lists, double y, double scale) {
    if (lists.isEmpty) {
      return 0;
    }
    final double vs = viewScale(scale);
    var top = gap;
    for (int i = 0; i < lists.length; i++) {
      final double band = lists[i].page.height * vs + gap;
      if (y < top + band) {
        return i;
      }
      top += band;
    }
    return lists.length - 1;
  }

  /// Page whose band contains content-X [x] in a horizontal stack.
  static int pageAtX(List<PdfDisplayList> lists, double x, double scale) {
    if (lists.isEmpty) {
      return 0;
    }
    final double vs = viewScale(scale);
    var left = gutter;
    for (int i = 0; i < lists.length; i++) {
      final double band = lists[i].page.width * vs + gap;
      if (x < left + band) {
        return i;
      }
      left += band;
    }
    return lists.length - 1;
  }

  /// Origin that keeps [focal] (content space at [oldScale]) on screen.
  static Offset originAfterScale({
    required List<PdfDisplayList> lists,
    required Offset origin,
    required Offset focal,
    required double oldScale,
    required double nextScale,
    bool horizontal = false,
  }) {
    if (lists.isEmpty || oldScale <= 0 || nextScale <= 0) {
      return origin;
    }
    final double oldVs = viewScale(oldScale);
    final double newVs = viewScale(nextScale);
    if (horizontal) {
      final int page = pageAtX(lists, focal.dx, oldScale);
      final double localX =
          (focal.dx - stackStart(lists, page, oldScale)) / oldVs;
      final double newX = stackStart(lists, page, nextScale) + localX * newVs;
      final double newY = focal.dy * (newVs / oldVs);
      return Offset(
        newX - (focal.dx - origin.dx),
        newY - (focal.dy - origin.dy),
      );
    }
    final int page = pageAtY(lists, focal.dy, oldScale);
    final double localY = (focal.dy - stackTop(lists, page, oldScale)) / oldVs;
    final double newY = stackTop(lists, page, nextScale) + localY * newVs;
    final double newX = focal.dx * (newVs / oldVs);
    return Offset(newX - (focal.dx - origin.dx), newY - (focal.dy - origin.dy));
  }
}
