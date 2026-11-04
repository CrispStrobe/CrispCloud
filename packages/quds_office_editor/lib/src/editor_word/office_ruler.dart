import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../embed/office_theme.dart';
import '../ui_components/office_chrome.dart';

/// Which control the pointer is on.
enum RulerHitKind {
  firstLine,
  hanging,
  leftIndent,
  rightIndent,
  tab,
  marginLeft,
  marginRight,
  marginTop,
  marginBottom,
  track,
}

/// Hit result on the Word ruler.
class RulerHit {
  /// RulerHit API.
  const RulerHit(this.kind, {this.tabIndex});

  /// kind API.
  final RulerHitKind kind;

  /// tabIndex API.
  final int? tabIndex;

  /// True for the stacked left-indent family.
  bool get isLeftFamily =>
      kind == RulerHitKind.firstLine ||
      kind == RulerHitKind.hanging ||
      kind == RulerHitKind.leftIndent;
}

/// Live values pushed while a ruler drag is in progress.
class WordRulerEdit {
  /// WordRulerEdit API.
  const WordRulerEdit({this.indent, this.tabs, this.margins});

  /// indent API.
  final WmlIndent? indent;

  /// tabs API.
  final List<WmlTabStop>? tabs;

  /// margins API.
  final WmlPageMargins? margins;
}

/// Page-aligned Word ruler: ticks, margins, indent triangles, and tabs.
abstract final class WordRuler {
  /// Thickness of the painted bars (matches [OfficeChrome.rulerSize]).
  static const double size = OfficeChrome.rulerSize;

  /// Default Word tab interval (0.5 inch).
  static const double defaultTab = kDefaultTabWidth;

  /// Snap step (1/16 inch).
  static const double snapStep = 4.5;

  static const double _inch = 72;

  /// Widget X of a page point.
  static double localX(
    double pageX, {
    required double pageLeft,
    required double scale,
  }) {
    return pageLeft + pageX * scale;
  }

  /// Widget Y of a page point.
  static double localY(
    double pageY, {
    required double pageTop,
    required double scale,
  }) {
    return pageTop + pageY * scale;
  }

  /// Page X from a widget position.
  static double pageX(
    double localX, {
    required double pageLeft,
    required double scale,
  }) {
    final double s = scale <= 0 ? 1 : scale;
    return (localX - pageLeft) / s;
  }

  /// Page Y from a widget position.
  static double pageY(
    double localY, {
    required double pageTop,
    required double scale,
  }) {
    final double s = scale <= 0 ? 1 : scale;
    return (localY - pageTop) / s;
  }

  /// Physical left/right of the current text box (page, column, or frame).
  static ({double left, double right}) resolveContent({
    required WmlPageMargins margins,
    required double pageWidth,
    double? contentLeft,
    double? contentRight,
  }) {
    return (
      left: contentLeft ?? margins.left,
      right: contentRight ?? (pageWidth - margins.right),
    );
  }

  /// Line the ruler should follow: the caret when it is on [activePageIndex],
  /// otherwise the first content line on that active page.
  static LaidOutLine? pickFocusLine({
    required int activePageIndex,
    LaidOutLine? caretLine,
    required List<LaidOutLine> pageLines,
  }) {
    if (caretLine != null &&
        caretLine.pageIndex == activePageIndex &&
        caretLine.boxWidth > 0) {
      return caretLine;
    }
    for (final LaidOutLine line in pageLines) {
      if (line.boxWidth > 0) {
        return line;
      }
    }
    if (pageLines.isNotEmpty) {
      return pageLines.first;
    }
    return caretLine;
  }

  /// Content box for the paragraph under the caret: laid-out line, then
  /// table cell, frame, column, then the page margins.
  static ({double left, double right}) paragraphContentBox({
    required WmlPageMargins margins,
    required double pageWidth,
    double? lineBoxX,
    double? lineBoxWidth,
    double? cellX,
    double? cellWidth,
    double? frameX,
    double? frameWidth,
    int columnCount = 1,
    int columnIndex = 0,
    double columnWidth = 0,
    double columnSpace = 0,
    bool preferFrame = false,
  }) {
    if (preferFrame &&
        frameX != null &&
        frameWidth != null &&
        frameWidth > 12) {
      return (
        left: frameX + LaidOutLine.framePad,
        right: frameX + frameWidth - LaidOutLine.framePad,
      );
    }
    if (lineBoxX != null && lineBoxWidth != null && lineBoxWidth > 0) {
      return (left: lineBoxX, right: lineBoxX + lineBoxWidth);
    }
    if (cellX != null && cellWidth != null && cellWidth > 12) {
      return (
        left: cellX + LaidOutLine.tableCellPad,
        right: cellX + cellWidth - LaidOutLine.tableCellPad,
      );
    }
    if (frameX != null && frameWidth != null && frameWidth > 12) {
      return (
        left: frameX + LaidOutLine.framePad,
        right: frameX + frameWidth - LaidOutLine.framePad,
      );
    }
    if (columnCount > 1 && columnWidth > 0) {
      final double left =
          margins.left + columnIndex * (columnWidth + columnSpace);
      return (left: left, right: left + columnWidth);
    }
    return (left: margins.left, right: pageWidth - margins.right);
  }

  /// Page X of the content origin (0 on the ruler): start of the text box.
  static double contentOriginX({
    required WmlPageMargins margins,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    return rtl ? box.right : box.left;
  }

  /// Page Y of the content origin (0 on the vertical ruler): top margin.
  static double contentOriginY({required WmlPageMargins margins}) =>
      margins.top;

  /// Widget-space guide for the active drag handle. Horizontal markers yield
  /// [guideX]; top/bottom margins yield [guideY].
  static (double?, double?) guideLocal({
    required RulerHit? active,
    required double pageLeft,
    required double pageTop,
    required double scale,
    required double pageWidth,
    required double pageHeight,
    required WmlPageMargins margins,
    required WmlIndent indent,
    required List<WmlTabStop> tabs,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    if (active == null || active.kind == RulerHitKind.track) {
      return (null, null);
    }
    switch (active.kind) {
      case RulerHitKind.firstLine:
        return (
          localX(
            firstLinePageX(
              margins: margins,
              indent: indent,
              pageWidth: pageWidth,
              rtl: rtl,
              contentLeft: contentLeft,
              contentRight: contentRight,
            ),
            pageLeft: pageLeft,
            scale: scale,
          ),
          null,
        );
      case RulerHitKind.hanging:
      case RulerHitKind.leftIndent:
        return (
          localX(
            hangingPageX(
              margins: margins,
              indent: indent,
              pageWidth: pageWidth,
              rtl: rtl,
              contentLeft: contentLeft,
              contentRight: contentRight,
            ),
            pageLeft: pageLeft,
            scale: scale,
          ),
          null,
        );
      case RulerHitKind.rightIndent:
        return (
          localX(
            rightIndentPageX(
              margins: margins,
              indent: indent,
              pageWidth: pageWidth,
              rtl: rtl,
              contentLeft: contentLeft,
              contentRight: contentRight,
            ),
            pageLeft: pageLeft,
            scale: scale,
          ),
          null,
        );
      case RulerHitKind.tab:
        final int? i = active.tabIndex;
        if (i == null || i < 0 || i >= tabs.length) {
          return (null, null);
        }
        return (
          localX(
            _tabPageX(
              tabs[i],
              margins: margins,
              pageWidth: pageWidth,
              rtl: rtl,
              contentLeft: contentLeft,
              contentRight: contentRight,
            ),
            pageLeft: pageLeft,
            scale: scale,
          ),
          null,
        );
      case RulerHitKind.marginLeft:
        return (localX(margins.left, pageLeft: pageLeft, scale: scale), null);
      case RulerHitKind.marginRight:
        return (
          localX(pageWidth - margins.right, pageLeft: pageLeft, scale: scale),
          null,
        );
      case RulerHitKind.marginTop:
        return (null, localY(margins.top, pageTop: pageTop, scale: scale));
      case RulerHitKind.marginBottom:
        return (
          null,
          localY(pageHeight - margins.bottom, pageTop: pageTop, scale: scale),
        );
      case RulerHitKind.track:
        return (null, null);
    }
  }

  /// Snap [points] to 1/16", unless [disable] (Alt).
  static double snap(double points, {required bool disable}) {
    if (disable) {
      return points;
    }
    return (points / snapStep).round() * snapStep;
  }

  /// First-line marker page X (from the page left edge).
  static double firstLinePageX({
    required WmlPageMargins margins,
    required WmlIndent indent,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final double start = indent.left + indent.firstLine - indent.hanging;
    final double origin = contentOriginX(
      margins: margins,
      pageWidth: pageWidth,
      rtl: rtl,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    return rtl ? origin - start : origin + start;
  }

  /// Hanging / body-text marker page X.
  static double hangingPageX({
    required WmlPageMargins margins,
    required WmlIndent indent,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final double origin = contentOriginX(
      margins: margins,
      pageWidth: pageWidth,
      rtl: rtl,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    return rtl ? origin - indent.left : origin + indent.left;
  }

  /// Right-indent marker page X.
  static double rightIndentPageX({
    required WmlPageMargins margins,
    required WmlIndent indent,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    return rtl ? box.left + indent.right : box.right - indent.right;
  }

  /// Apply a horizontal indent drag to [indent].
  static WmlIndent applyIndentDrag({
    required WmlIndent indent,
    required RulerHitKind kind,
    required double pageX,
    required WmlPageMargins margins,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    final double contentW = (box.right - box.left).clamp(36, pageWidth);
    if (rtl) {
      return _applyRtl(
        indent: indent,
        kind: kind,
        pageX: pageX,
        contentLeft: box.left,
        contentRight: box.right,
        contentW: contentW,
      );
    }
    return _applyLtr(
      indent: indent,
      kind: kind,
      pageX: pageX,
      contentLeft: box.left,
      contentRight: box.right,
      contentW: contentW,
    );
  }

  static WmlIndent _applyLtr({
    required WmlIndent indent,
    required RulerHitKind kind,
    required double pageX,
    required double contentLeft,
    required double contentRight,
    required double contentW,
  }) {
    switch (kind) {
      case RulerHitKind.firstLine:
        final double rel = (pageX - contentLeft - indent.left).clamp(
          -indent.left,
          contentW - indent.left - 12,
        );
        if (rel >= 0) {
          return indent.copyWith(firstLine: rel, hanging: 0);
        }
        return indent.copyWith(firstLine: 0, hanging: -rel);
      case RulerHitKind.hanging:
        final double firstPos = indent.left + indent.firstLine - indent.hanging;
        final double newLeft = (pageX - contentLeft).clamp(0, contentW - 24);
        if (firstPos >= newLeft) {
          return indent.copyWith(
            left: newLeft,
            firstLine: firstPos - newLeft,
            hanging: 0,
          );
        }
        return indent.copyWith(
          left: newLeft,
          firstLine: 0,
          hanging: newLeft - firstPos,
        );
      case RulerHitKind.leftIndent:
        final double newLeft = (pageX - contentLeft).clamp(0, contentW - 24);
        return indent.copyWith(left: newLeft);
      case RulerHitKind.rightIndent:
        final double right = (contentRight - pageX).clamp(0, contentW - 24);
        return indent.copyWith(right: right);
      default:
        return indent;
    }
  }

  static WmlIndent _applyRtl({
    required WmlIndent indent,
    required RulerHitKind kind,
    required double pageX,
    required double contentLeft,
    required double contentRight,
    required double contentW,
  }) {
    switch (kind) {
      case RulerHitKind.firstLine:
        final double rel = (contentRight - pageX - indent.left).clamp(
          -indent.left,
          contentW - indent.left - 12,
        );
        if (rel >= 0) {
          return indent.copyWith(firstLine: rel, hanging: 0);
        }
        return indent.copyWith(firstLine: 0, hanging: -rel);
      case RulerHitKind.hanging:
        final double firstPos = indent.left + indent.firstLine - indent.hanging;
        final double newLeft = (contentRight - pageX).clamp(0, contentW - 24);
        if (firstPos >= newLeft) {
          return indent.copyWith(
            left: newLeft,
            firstLine: firstPos - newLeft,
            hanging: 0,
          );
        }
        return indent.copyWith(
          left: newLeft,
          firstLine: 0,
          hanging: newLeft - firstPos,
        );
      case RulerHitKind.leftIndent:
        final double newLeft = (contentRight - pageX).clamp(0, contentW - 24);
        return indent.copyWith(left: newLeft);
      case RulerHitKind.rightIndent:
        final double right = (pageX - contentLeft).clamp(0, contentW - 24);
        return indent.copyWith(right: right);
      default:
        return indent;
    }
  }

  /// New left/right/top/bottom margin from a page-edge drag.
  static WmlPageMargins applyMarginDrag({
    required WmlPageMargins margins,
    required RulerHitKind kind,
    required double pagePos,
    required double pageWidth,
    required double pageHeight,
  }) {
    const double minM = 18;
    switch (kind) {
      case RulerHitKind.marginLeft:
        return margins.copyWith(
          left: pagePos.clamp(minM, pageWidth - margins.right - 72),
        );
      case RulerHitKind.marginRight:
        return margins.copyWith(
          right: (pageWidth - pagePos).clamp(
            minM,
            pageWidth - margins.left - 72,
          ),
        );
      case RulerHitKind.marginTop:
        return margins.copyWith(
          top: pagePos.clamp(minM, pageHeight - margins.bottom - 72),
        );
      case RulerHitKind.marginBottom:
        return margins.copyWith(
          bottom: (pageHeight - pagePos).clamp(
            minM,
            pageHeight - margins.top - 72,
          ),
        );
      default:
        return margins;
    }
  }

  /// Next tab alignment in the Word cycle.
  static WmlTabAlignment cycleAlignment(WmlTabAlignment current) {
    return switch (current) {
      WmlTabAlignment.left => WmlTabAlignment.center,
      WmlTabAlignment.center => WmlTabAlignment.right,
      WmlTabAlignment.right => WmlTabAlignment.decimal,
      WmlTabAlignment.decimal => WmlTabAlignment.left,
    };
  }

  /// Hit-test the horizontal and vertical bars.
  static RulerHit? hit({
    required Offset local,
    required Size view,
    required double pageLeft,
    required double pageTop,
    required double scale,
    required double pageWidth,
    required double pageHeight,
    required WmlPageMargins margins,
    required WmlIndent indent,
    required List<WmlTabStop> tabs,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > view.width ||
        local.dy > view.height) {
      return null;
    }
    final bool onH = local.dy <= size;
    final bool onV = local.dx <= size;
    if (!onH && !onV) {
      return null;
    }
    if (onH) {
      final double px = pageX(local.dx, pageLeft: pageLeft, scale: scale);
      final double first = firstLinePageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      );
      final double hang = hangingPageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      );
      final double right = rightIndentPageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      );
      final double xFirst = localX(first, pageLeft: pageLeft, scale: scale);
      final double xHang = localX(hang, pageLeft: pageLeft, scale: scale);
      final double xRight = localX(right, pageLeft: pageLeft, scale: scale);
      if (_nearX(local.dx, xFirst) && local.dy <= 11) {
        return const RulerHit(RulerHitKind.firstLine);
      }
      if (_nearX(local.dx, xHang) && local.dy >= 14) {
        return const RulerHit(RulerHitKind.leftIndent);
      }
      if (_nearX(local.dx, xHang) && local.dy >= 8) {
        return const RulerHit(RulerHitKind.hanging);
      }
      if (_nearX(local.dx, xRight) && local.dy >= 8) {
        return const RulerHit(RulerHitKind.rightIndent);
      }
      for (int i = tabs.length - 1; i >= 0; i--) {
        final double tabX = localX(
          _tabPageX(
            tabs[i],
            margins: margins,
            pageWidth: pageWidth,
            rtl: rtl,
            contentLeft: contentLeft,
            contentRight: contentRight,
          ),
          pageLeft: pageLeft,
          scale: scale,
        );
        if (_nearX(local.dx, tabX, slop: 6)) {
          return RulerHit(RulerHitKind.tab, tabIndex: i);
        }
      }
      final double leftM = localX(
        margins.left,
        pageLeft: pageLeft,
        scale: scale,
      );
      final double rightM = localX(
        pageWidth - margins.right,
        pageLeft: pageLeft,
        scale: scale,
      );
      if ((local.dx - leftM).abs() <= 5) {
        return const RulerHit(RulerHitKind.marginLeft);
      }
      if ((local.dx - rightM).abs() <= 5) {
        return const RulerHit(RulerHitKind.marginRight);
      }
      if (px >= 0 && px <= pageWidth) {
        return const RulerHit(RulerHitKind.track);
      }
      return const RulerHit(RulerHitKind.track);
    }
    final double topM = localY(margins.top, pageTop: pageTop, scale: scale);
    final double botM = localY(
      pageHeight - margins.bottom,
      pageTop: pageTop,
      scale: scale,
    );
    if ((local.dy - topM).abs() <= 5) {
      return const RulerHit(RulerHitKind.marginTop);
    }
    if ((local.dy - botM).abs() <= 5) {
      return const RulerHit(RulerHitKind.marginBottom);
    }
    return const RulerHit(RulerHitKind.track);
  }

  static bool _nearX(double a, double b, {double slop = 7}) =>
      (a - b).abs() <= slop;

  static double _tabPageX(
    WmlTabStop tab, {
    required WmlPageMargins margins,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    return rtl ? box.right - tab.position : box.left + tab.position;
  }

  /// Cursor for a ruler hit.
  static MouseCursor cursorFor(RulerHit? hit) {
    if (hit == null) {
      return SystemMouseCursors.basic;
    }
    return switch (hit.kind) {
      RulerHitKind.marginTop ||
      RulerHitKind.marginBottom => SystemMouseCursors.resizeRow,
      RulerHitKind.track => SystemMouseCursors.precise,
      _ => SystemMouseCursors.resizeColumn,
    };
  }

  /// Paints both bars, ticks, margins, indent markers, and tab stops.
  static void paint(
    Canvas canvas,
    Size view, {
    required double pageLeft,
    required double pageTop,
    required double scale,
    required double pageWidth,
    required double pageHeight,
    required WmlPageMargins margins,
    required WmlIndent indent,
    required List<WmlTabStop> tabs,
    required bool rtl,
    required OfficeTheme theme,
    RulerHit? hover,
    RulerHit? active,
    String? readout,
    double? contentLeft,
    double? contentRight,
  }) {
    const Color barFill = Color(0xFFEEEEEE);
    const Color marginWell = Color(0xFFD0D0D0);
    const Color contentWell = Color(0xFFFAFAFA);
    const Color wellStroke = Color(0xFFB8B8B8);
    const Color hairline = Color(0xFFB0B0B0);
    const Color tickColor = Color(0xFF5C5C5C);

    final Rect hBar = Rect.fromLTWH(0, 0, view.width, size);
    final Rect vBar = Rect.fromLTWH(0, 0, size, view.height);
    canvas.drawRect(hBar, Paint()..color = barFill);
    canvas.drawRect(vBar, Paint()..color = barFill);

    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    final double left = localX(0, pageLeft: pageLeft, scale: scale);
    final double right = localX(pageWidth, pageLeft: pageLeft, scale: scale);
    final double top = localY(0, pageTop: pageTop, scale: scale);
    final double bottom = localY(pageHeight, pageTop: pageTop, scale: scale);
    final double contentL = localX(box.left, pageLeft: pageLeft, scale: scale);
    final double contentR = localX(box.right, pageLeft: pageLeft, scale: scale);
    final double contentT = localY(margins.top, pageTop: pageTop, scale: scale);
    final double contentB = localY(
      pageHeight - margins.bottom,
      pageTop: pageTop,
      scale: scale,
    );
    final double originX = contentOriginX(
      margins: margins,
      pageWidth: pageWidth,
      rtl: rtl,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    final double originY = contentOriginY(margins: margins);
    final RulerHit? lit = active ?? hover;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(size, 0, math.max(0, view.width - size), size),
    );
    final double wellLeft = math.min(left, right);
    final double wellRight = math.max(left, right);
    final double wellCL = math.min(contentL, contentR);
    final double wellCR = math.max(contentL, contentR);
    _paintHWell(
      canvas,
      page: Rect.fromLTRB(wellLeft, 5, wellRight, size - 2),
      content: Rect.fromLTRB(wellCL, 5, math.max(wellCL, wellCR), size - 2),
      marginFill: marginWell,
      contentFill: contentWell,
      stroke: wellStroke,
      accent: theme.focusRing,
      highlight: lit?.kind == RulerHitKind.marginLeft
          ? contentL
          : lit?.kind == RulerHitKind.marginRight
          ? contentR
          : null,
    );
    _paintHTicks(
      canvas,
      pageLeft: pageLeft,
      scale: scale,
      pageWidth: pageWidth,
      originPageX: originX,
      rtl: rtl,
      color: tickColor,
    );
    canvas.restore();

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, size, size, math.max(0, view.height - size)),
    );
    _paintVWell(
      canvas,
      page: Rect.fromLTRB(5, top, size - 2, bottom),
      content: Rect.fromLTRB(5, contentT, size - 2, contentB),
      marginFill: marginWell,
      contentFill: contentWell,
      stroke: wellStroke,
      accent: theme.focusRing,
      highlight: lit?.kind == RulerHitKind.marginTop
          ? contentT
          : lit?.kind == RulerHitKind.marginBottom
          ? contentB
          : null,
    );
    _paintVTicks(
      canvas,
      pageTop: pageTop,
      scale: scale,
      pageHeight: pageHeight,
      originPageY: originY,
      color: tickColor,
    );
    canvas.restore();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = const Color(0xFFE4E4E4),
    );
    canvas.drawLine(
      Offset(3, 3),
      Offset(size - 4, size - 4),
      Paint()
        ..color = const Color(0xFFC0C0C0)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size - 1, view.width, 1),
      Paint()..color = hairline,
    );
    canvas.drawRect(
      Rect.fromLTWH(size - 1, 0, 1, view.height),
      Paint()..color = hairline,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size, view.width, 3),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, size),
          Offset(0, size + 3),
          const <Color>[Color(0x22000000), Color(0x00000000)],
        ),
    );

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(size, 0, math.max(0, view.width - size), size),
    );
    _paintDefaultTabs(
      canvas,
      pageLeft: pageLeft,
      scale: scale,
      margins: margins,
      pageWidth: pageWidth,
      tabs: tabs,
      rtl: rtl,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    for (int i = 0; i < tabs.length; i++) {
      final bool on =
          (hover?.kind == RulerHitKind.tab && hover?.tabIndex == i) ||
          (active?.kind == RulerHitKind.tab && active?.tabIndex == i);
      _paintTab(
        canvas,
        localX(
          _tabPageX(
            tabs[i],
            margins: margins,
            pageWidth: pageWidth,
            rtl: rtl,
            contentLeft: contentLeft,
            contentRight: contentRight,
          ),
          pageLeft: pageLeft,
          scale: scale,
        ),
        tabs[i].alignment,
        theme: theme,
        active: on,
      );
    }
    final double xFirst = localX(
      firstLinePageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      ),
      pageLeft: pageLeft,
      scale: scale,
    );
    final double xHang = localX(
      hangingPageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      ),
      pageLeft: pageLeft,
      scale: scale,
    );
    final double xRight = localX(
      rightIndentPageX(
        margins: margins,
        indent: indent,
        pageWidth: pageWidth,
        rtl: rtl,
        contentLeft: contentLeft,
        contentRight: contentRight,
      ),
      pageLeft: pageLeft,
      scale: scale,
    );
    _paintRightMarker(
      canvas,
      xRight,
      theme: theme,
      active:
          hover?.kind == RulerHitKind.rightIndent ||
          active?.kind == RulerHitKind.rightIndent,
    );
    _paintLeftFamily(
      canvas,
      xFirst,
      xHang,
      theme: theme,
      firstActive:
          hover?.kind == RulerHitKind.firstLine ||
          active?.kind == RulerHitKind.firstLine,
      hangActive:
          hover?.kind == RulerHitKind.hanging ||
          active?.kind == RulerHitKind.hanging,
      boxActive:
          hover?.kind == RulerHitKind.leftIndent ||
          active?.kind == RulerHitKind.leftIndent,
    );
    canvas.restore();

    final (double? guideX, double? guideY) = guideLocal(
      active: active,
      pageLeft: pageLeft,
      pageTop: pageTop,
      scale: scale,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      margins: margins,
      indent: indent,
      tabs: tabs,
      rtl: rtl,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    _paintGuides(
      canvas,
      view,
      guideX: guideX,
      guideY: guideY,
      color: theme.focusRing,
    );

    if (readout != null && readout.isNotEmpty && active != null) {
      _paintReadout(
        canvas,
        view,
        readout,
        theme: theme,
        active: active,
        xFirst: xFirst,
        xHang: xHang,
        xRight: xRight,
      );
    }
  }

  static void _paintHWell(
    Canvas canvas, {
    required Rect page,
    required Rect content,
    required Color marginFill,
    required Color contentFill,
    required Color stroke,
    required Color accent,
    double? highlight,
  }) {
    if (page.width <= 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      Paint()..color = marginFill,
    );
    if (content.width > 0) {
      canvas.drawRect(content, Paint()..color = contentFill);
      canvas.drawLine(
        Offset(content.left, content.top + 0.5),
        Offset(content.right, content.top + 0.5),
        Paint()..color = const Color(0x66FFFFFF),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (highlight != null) {
      canvas.drawLine(
        Offset(highlight, page.top),
        Offset(highlight, page.bottom),
        Paint()
          ..color = accent
          ..strokeWidth = 1.5,
      );
    }
  }

  static void _paintVWell(
    Canvas canvas, {
    required Rect page,
    required Rect content,
    required Color marginFill,
    required Color contentFill,
    required Color stroke,
    required Color accent,
    double? highlight,
  }) {
    if (page.height <= 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      Paint()..color = marginFill,
    );
    if (content.height > 0) {
      canvas.drawRect(content, Paint()..color = contentFill);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (highlight != null) {
      canvas.drawLine(
        Offset(page.left, highlight),
        Offset(page.right, highlight),
        Paint()
          ..color = accent
          ..strokeWidth = 1.5,
      );
    }
  }

  static void _paintHTicks(
    Canvas canvas, {
    required double pageLeft,
    required double scale,
    required double pageWidth,
    required double originPageX,
    required bool rtl,
    required Color color,
  }) {
    final Paint tick = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final double sign = rtl ? -1 : 1;
    final double eighth = _inch / 8;
    final int span =
        ((math.max(originPageX, pageWidth - originPageX) + _inch) / eighth)
            .ceil() +
        2;
    for (int n = -span; n <= span; n++) {
      final double page = originPageX + sign * n * eighth;
      if (page < -0.5 || page > pageWidth + 0.5) {
        continue;
      }
      final double x = localX(page, pageLeft: pageLeft, scale: scale);
      final bool inch = n % 8 == 0;
      final bool half = n % 4 == 0;
      final double top = inch ? 6 : (half ? 9 : 12);
      canvas.drawLine(Offset(x, top), Offset(x, size - 3), tick);
      if (inch) {
        _labelCentered(canvas, '${n ~/ 8}', Offset(x, 3.5), color);
      }
    }
  }

  static void _paintVTicks(
    Canvas canvas, {
    required double pageTop,
    required double scale,
    required double pageHeight,
    required double originPageY,
    required Color color,
  }) {
    final Paint tick = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final double eighth = _inch / 8;
    final int start = ((0 - originPageY) / eighth).floor() - 1;
    final int end = ((pageHeight - originPageY) / eighth).ceil() + 1;
    for (int n = start; n <= end; n++) {
      final double page = originPageY + n * eighth;
      if (page < -0.5 || page > pageHeight + 0.5) {
        continue;
      }
      final double y = localY(page, pageTop: pageTop, scale: scale);
      final bool inch = n % 8 == 0;
      final bool half = n % 4 == 0;
      final double left = inch ? 6 : (half ? 9 : 12);
      canvas.drawLine(Offset(left, y), Offset(size - 3, y), tick);
      if (inch) {
        _labelCentered(canvas, '${n ~/ 8}', Offset(size / 2, y - 5.5), color);
      }
    }
  }

  static void _paintGuides(
    Canvas canvas,
    Size view, {
    required double? guideX,
    required double? guideY,
    required Color color,
  }) {
    if (guideX != null && guideX >= size && guideX <= view.width) {
      _paintDashedGuide(
        canvas,
        Offset(guideX, size),
        Offset(guideX, view.height),
        color,
      );
    }
    if (guideY != null && guideY >= size && guideY <= view.height) {
      _paintDashedGuide(
        canvas,
        Offset(size, guideY),
        Offset(view.width, guideY),
        color,
      );
    }
  }

  static void _paintDashedGuide(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
  ) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..strokeWidth = 3,
    );
    final Paint dash = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    const double on = 5;
    const double off = 3;
    final double len = (b - a).distance;
    if (len < 1) {
      return;
    }
    final Offset dir = Offset((b.dx - a.dx) / len, (b.dy - a.dy) / len);
    var t = 0.0;
    while (t < len) {
      final double t2 = math.min(t + on, len);
      canvas.drawLine(a + dir * t, a + dir * t2, dash);
      t += on + off;
    }
  }

  static void _paintDefaultTabs(
    Canvas canvas, {
    required double pageLeft,
    required double scale,
    required WmlPageMargins margins,
    required double pageWidth,
    required List<WmlTabStop> tabs,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final Paint mark = Paint()
      ..color = const Color(0xFFB8B8B8)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    final double contentW = box.right - box.left;
    for (double pos = defaultTab; pos < contentW - 4; pos += defaultTab) {
      if (tabs.any((WmlTabStop t) => (t.position - pos).abs() < 3)) {
        continue;
      }
      final double x = localX(
        rtl ? box.right - pos : box.left + pos,
        pageLeft: pageLeft,
        scale: scale,
      );
      canvas.drawLine(Offset(x, size - 5), Offset(x, size - 2), mark);
    }
  }

  static void _paintLeftFamily(
    Canvas canvas,
    double firstX,
    double hangX, {
    required OfficeTheme theme,
    required bool firstActive,
    required bool hangActive,
    required bool boxActive,
  }) {
    _triangle(canvas, firstX, 5, down: true, active: firstActive, theme: theme);
    _triangle(canvas, hangX, 13, down: false, active: hangActive, theme: theme);
    _square(canvas, hangX, active: boxActive, theme: theme);
  }

  static void _paintRightMarker(
    Canvas canvas,
    double x, {
    required OfficeTheme theme,
    required bool active,
  }) {
    _triangle(canvas, x, 13, down: false, active: active, theme: theme);
  }

  static void _triangle(
    Canvas canvas,
    double x,
    double y, {
    required bool down,
    required bool active,
    required OfficeTheme theme,
  }) {
    const double w = 9;
    const double h = 7;
    final Path path = Path();
    if (down) {
      path
        ..moveTo(x - w / 2, y)
        ..lineTo(x + w / 2, y)
        ..lineTo(x, y + h)
        ..close();
    } else {
      path
        ..moveTo(x, y)
        ..lineTo(x + w / 2, y + h)
        ..lineTo(x - w / 2, y + h)
        ..close();
    }
    _fillMarker(canvas, path, active: active, theme: theme);
  }

  static void _square(
    Canvas canvas,
    double x, {
    required bool active,
    required OfficeTheme theme,
  }) {
    final RRect box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, 20.5), width: 9, height: 5),
      const Radius.circular(0.8),
    );
    canvas.drawRRect(
      box.shift(const Offset(0.4, 0.7)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(
      box,
      Paint()
        ..color = active ? const Color(0xFFD6E8F8) : const Color(0xFFFBFBFB),
    );
    canvas.drawRRect(
      box,
      Paint()
        ..color = active ? theme.focusRing : const Color(0xFF3D3D3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.35 : 1,
    );
  }

  static void _fillMarker(
    Canvas canvas,
    Path path, {
    required bool active,
    required OfficeTheme theme,
  }) {
    canvas.drawPath(
      path.shift(const Offset(0.4, 0.7)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = active ? const Color(0xFFD6E8F8) : const Color(0xFFFBFBFB),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = active ? theme.focusRing : const Color(0xFF3D3D3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.35 : 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static void _paintTab(
    Canvas canvas,
    double x,
    WmlTabAlignment alignment, {
    required OfficeTheme theme,
    required bool active,
  }) {
    final Color color = active ? theme.focusRing : const Color(0xFF2B579A);
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const double y = 16.5;
    switch (alignment) {
      case WmlTabAlignment.left:
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 3.5), stroke);
        canvas.drawLine(Offset(x, y + 3.5), Offset(x + 5.5, y + 3.5), stroke);
      case WmlTabAlignment.right:
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 3.5), stroke);
        canvas.drawLine(Offset(x, y + 3.5), Offset(x - 5.5, y + 3.5), stroke);
      case WmlTabAlignment.center:
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 3.5), stroke);
        canvas.drawLine(
          Offset(x - 4.5, y + 3.5),
          Offset(x + 4.5, y + 3.5),
          stroke,
        );
      case WmlTabAlignment.decimal:
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 3.5), stroke);
        canvas.drawLine(
          Offset(x - 4.5, y + 3.5),
          Offset(x + 4.5, y + 3.5),
          stroke,
        );
        canvas.drawCircle(Offset(x + 5, y + 1), 1.15, Paint()..color = color);
    }
  }

  static void _labelCentered(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
  ) {
    final ParagraphBuilder b =
        ParagraphBuilder(
          ParagraphStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            textAlign: TextAlign.center,
          ),
        )..pushStyle(
          TextStyle(
            color: color.withValues(alpha: 0.92),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );
    b.addText(text);
    final Paragraph p = b.build()
      ..layout(const ParagraphConstraints(width: 28));
    canvas.drawParagraph(p, Offset(center.dx - 14, center.dy));
  }

  static void _paintReadout(
    Canvas canvas,
    Size view,
    String text, {
    required OfficeTheme theme,
    required RulerHit active,
    required double xFirst,
    required double xHang,
    required double xRight,
  }) {
    var x = switch (active.kind) {
      RulerHitKind.firstLine => xFirst,
      RulerHitKind.rightIndent => xRight,
      _ => xHang,
    };
    x = x.clamp(size + 8, view.width - 72);
    final ParagraphBuilder b = ParagraphBuilder(
      ParagraphStyle(fontSize: 10, textAlign: TextAlign.center),
    )..pushStyle(TextStyle(color: theme.chromeText, fontSize: 10));
    b.addText(text);
    final Paragraph p = b.build()
      ..layout(const ParagraphConstraints(width: 64));
    final Rect box = Rect.fromLTWH(x - 32, size + 6, 64, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xF2FFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = theme.focusRing.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawParagraph(p, Offset(box.left, box.top + 3));
  }

  /// Inches label for a page-X drag.
  static String inchLabel(double pageX) {
    final double inches = pageX / _inch;
    return '${inches.toStringAsFixed(2)}"';
  }

  /// Tab position from a page X (distance from the start margin).
  static double tabPosition({
    required double pageX,
    required WmlPageMargins margins,
    required double pageWidth,
    required bool rtl,
    double? contentLeft,
    double? contentRight,
  }) {
    final ({double left, double right}) box = resolveContent(
      margins: margins,
      pageWidth: pageWidth,
      contentLeft: contentLeft,
      contentRight: contentRight,
    );
    final double raw = rtl ? box.right - pageX : pageX - box.left;
    return raw.clamp(0, box.right - box.left);
  }
}
