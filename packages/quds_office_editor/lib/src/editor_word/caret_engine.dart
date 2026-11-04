import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quds_office_engine/quds_office_engine.dart';

/// BiDi-aware visual caret plus disjoint selection rectangles.
class CaretEngine {
  /// CaretEngine API.
  CaretEngine();

  /// Index into [WmlDocument.paragraphs].
  int paragraphIndex = 0;

  /// logicalIndex API.
  int logicalIndex = 0;

  /// selectionAnchor API.
  int selectionAnchor = 0;

  /// selectionAnchorParagraph API.
  int selectionAnchorParagraph = 0;

  /// visible API.
  var visible = true;

  /// now API.
  DateTime _lastBlink = DateTime.now();

  /// resetBlink API.
  void resetBlink() {
    visible = true;
    _lastBlink = DateTime.now();
  }

  /// tick API.
  void tick(Duration elapsed) {
    if (DateTime.now().difference(_lastBlink).inMilliseconds >= 500) {
      visible = !visible;
      _lastBlink = DateTime.now();
    }
  }

  /// RegExp API.
  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

  /// isCollapsed API.
  bool get isCollapsed =>
      selectionAnchorParagraph == paragraphIndex &&
      selectionAnchor == logicalIndex;

  /// normalizedRange API.
  ({int startPara, int startIdx, int endPara, int endIdx}) get normalizedRange {
    final bool forward =
        selectionAnchorParagraph < paragraphIndex ||
        (selectionAnchorParagraph == paragraphIndex &&
            selectionAnchor <= logicalIndex);
    if (forward) {
      return (
        startPara: selectionAnchorParagraph,
        startIdx: selectionAnchor,
        endPara: paragraphIndex,
        endIdx: logicalIndex,
      );
    }
    return (
      startPara: paragraphIndex,
      startIdx: logicalIndex,
      endPara: selectionAnchorParagraph,
      endIdx: selectionAnchor,
    );
  }

  /// collapseSelection API.
  void collapseSelection() {
    selectionAnchorParagraph = paragraphIndex;
    selectionAnchor = logicalIndex;
    resetBlink();
  }

  /// moveLogical API.
  void moveLogical(int delta, int max) {
    logicalIndex = (logicalIndex + delta).clamp(0, max);
    collapseSelection();
  }

  /// Selects the word that contains [index], or the nearest token.
  void selectWord(String text, int index) {
    final ({int start, int end}) span = wordBounds(text, index);
    selectionAnchorParagraph = paragraphIndex;
    selectionAnchor = span.start;
    logicalIndex = span.end;
    resetBlink();
  }

  /// Selects the whole paragraph.
  void selectParagraph(String text) {
    selectionAnchorParagraph = paragraphIndex;
    selectionAnchor = 0;
    logicalIndex = text.length;
    resetBlink();
  }

  static ({int start, int end}) wordBounds(String text, int index) {
    if (text.isEmpty) {
      return (start: 0, end: 0);
    }
    var i = index.clamp(0, text.length);
    if (i == text.length) {
      i = text.length - 1;
    }
    if (!_isWordChar(text, i) && i > 0 && _isWordChar(text, i - 1)) {
      i--;
    }
    var start = i;
    var end = i + 1;
    if (_isWordChar(text, i)) {
      while (start > 0 && _isWordChar(text, start - 1)) {
        start--;
      }
      while (end < text.length && _isWordChar(text, end)) {
        end++;
      }
    } else if (_isSpace(text, i)) {
      while (start > 0 && _isSpace(text, start - 1)) {
        start--;
      }
      while (end < text.length && _isSpace(text, end)) {
        end++;
      }
    } else {
      while (start > 0 &&
          !_isWordChar(text, start - 1) &&
          !_isSpace(text, start - 1)) {
        start--;
      }
      while (end < text.length &&
          !_isWordChar(text, end) &&
          !_isSpace(text, end)) {
        end++;
      }
    }
    return (start: start, end: end);
  }

  /// Line between `\n` characters that contains [index].
  static ({int start, int end}) paragraphBounds(String text, int index) {
    if (text.isEmpty) {
      return (start: 0, end: 0);
    }
    final int i = index.clamp(0, text.length);
    var start = i;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = i;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    return (start: start, end: end);
  }

  /// coversIndex API.
  bool coversIndex(int paragraph, int index) {
    if (isCollapsed) {
      return false;
    }
    final ({int startPara, int startIdx, int endPara, int endIdx}) range =
        normalizedRange;
    if (paragraph < range.startPara || paragraph > range.endPara) {
      return false;
    }
    if (paragraph == range.startPara && index < range.startIdx) {
      return false;
    }
    if (paragraph == range.endPara && index > range.endIdx) {
      return false;
    }
    return true;
  }

  /// coversParagraph API.
  bool coversParagraph(int index) {
    final int a = selectionAnchorParagraph < paragraphIndex
        ? selectionAnchorParagraph
        : paragraphIndex;
    final int b = selectionAnchorParagraph > paragraphIndex
        ? selectionAnchorParagraph
        : paragraphIndex;
    if (a == b && selectionAnchor == logicalIndex) {
      return false;
    }
    return index >= a && index <= b;
  }

  static bool _isWordChar(String text, int index) {
    if (index < 0 || index >= text.length) {
      return false;
    }
    return _wordChar.hasMatch(text[index]);
  }

  static bool _isSpace(String text, int index) {
    if (index < 0 || index >= text.length) {
      return false;
    }
    return text[index].trim().isEmpty;
  }

  /// moveVisual API.
  void moveVisual(BrokenLine line, bool right) {
    final double x = logicalToVisualX(line, logicalIndex);
    final double next = right ? x + 1 : x - 1;
    logicalIndex = visualXToLogical(line, next);
    collapseSelection();
  }

  /// selectionRects API.
  List<Rect> selectionRects(
    BrokenLine line,
    double y,
    double height, {
    int? paragraph,
  }) {
    final ({int from, int to})? span = _selectionSpan(paragraph: paragraph);
    if (span == null) {
      return const <Rect>[];
    }
    return rangeRects(line, y, height, span.from, span.to);
  }

  /// Selection boxes from laid-out glyph X (matches justified ink).
  List<Rect> selectionRectsOnLine(
    LaidOutLine line,
    double y,
    double height, {
    int? paragraph,
  }) {
    final ({int from, int to})? span = _selectionSpan(
      paragraph: paragraph ?? line.paragraphIndex,
    );
    if (span == null) {
      return const <Rect>[];
    }
    return rangeRectsOnLine(line, y, height, span.from, span.to);
  }

  ({int from, int to})? _selectionSpan({int? paragraph}) {
    final int linePara = paragraph ?? paragraphIndex;
    final int aPara = selectionAnchorParagraph;
    final int bPara = paragraphIndex;
    final int aIdx = selectionAnchor;
    final int bIdx = logicalIndex;
    final bool forward = aPara < bPara || (aPara == bPara && aIdx <= bIdx);
    final int startPara = forward ? aPara : bPara;
    final int endPara = forward ? bPara : aPara;
    final int startIdx = forward ? aIdx : bIdx;
    final int endIdx = forward ? bIdx : aIdx;
    if (startPara == endPara && startIdx == endIdx) {
      return null;
    }
    if (linePara < startPara || linePara > endPara) {
      return null;
    }
    if (startPara == endPara) {
      return (from: startIdx, to: endIdx);
    }
    if (linePara == startPara) {
      return (from: startIdx, to: 1 << 20);
    }
    if (linePara == endPara) {
      return (from: 0, to: endIdx);
    }
    return (from: 0, to: 1 << 20);
  }

  /// rangeRects API.
  static List<Rect> rangeRects(
    BrokenLine line,
    double y,
    double height,
    int from,
    int to,
  ) {
    if (from >= to) {
      return const <Rect>[];
    }
    if (line.glyphs.isEmpty) {
      return <Rect>[Rect.fromLTWH(0, y, 8, height)];
    }
    final List<Rect> rects = <Rect>[];
    var x = 0.0;
    double? runStart;
    for (final ShapedGlyph g in line.glyphs) {
      final bool inside = g.logicalIndex >= from && g.logicalIndex < to;
      if (inside) {
        runStart ??= x;
      } else if (runStart != null) {
        rects.add(Rect.fromLTWH(runStart, y, x - runStart, height));
        runStart = null;
      }
      x += g.advance;
    }
    if (runStart != null) {
      rects.add(Rect.fromLTWH(runStart, y, x - runStart, height));
    }
    return rects;
  }

  /// Absolute-page selection boxes using [LaidOutGlyph.x].
  static List<Rect> rangeRectsOnLine(
    LaidOutLine line,
    double y,
    double height,
    int from,
    int to,
  ) {
    if (from >= to) {
      return const <Rect>[];
    }
    if (line.glyphs.isEmpty) {
      return <Rect>[Rect.fromLTWH(line.x, y, 8, height)];
    }
    final List<Rect> rects = <Rect>[];
    double? runStart;
    var runEnd = 0.0;
    for (final LaidOutGlyph g in line.glyphs) {
      final bool inside =
          g.glyph.logicalIndex >= from && g.glyph.logicalIndex < to;
      if (inside) {
        runStart ??= g.x;
        runEnd = g.x + g.advance;
      } else if (runStart != null) {
        rects.add(Rect.fromLTWH(runStart, y, runEnd - runStart, height));
        runStart = null;
      }
    }
    if (runStart != null) {
      rects.add(Rect.fromLTWH(runStart, y, runEnd - runStart, height));
    }
    return rects;
  }

  /// caretRect API.
  Rect caretRect(BrokenLine line, double y, double height) {
    final double x = logicalToVisualX(line, logicalIndex);
    return Rect.fromLTWH(x, y, 1.0, height);
  }

  /// Visual X of the insertion point on a laid-out line.
  ///
  /// RTL runs store glyphs in visual order (last logical letter on the
  /// left). The caret after the last typed letter belongs at the left of
  /// that glyph, not at the visual end of the line.
  static double caretX(
    LaidOutLine line,
    int logicalIndex, {
    bool paragraphRtl = false,
    double? contentRight,
  }) {
    if (line.glyphs.isEmpty) {
      if (paragraphRtl) {
        final double right = contentRight ?? (line.x + line.width);
        return right > line.x ? right : line.x;
      }
      return line.x;
    }
    for (final LaidOutGlyph glyph in line.glyphs) {
      if (glyph.glyph.logicalIndex != logicalIndex) {
        continue;
      }
      return glyph.glyph.level.isOdd ? glyph.x + glyph.advance : glyph.x;
    }
    LaidOutGlyph? before;
    for (final LaidOutGlyph glyph in line.glyphs) {
      if (glyph.glyph.logicalIndex >= logicalIndex) {
        continue;
      }
      if (before == null ||
          glyph.glyph.logicalIndex > before.glyph.logicalIndex) {
        before = glyph;
      }
    }
    if (before != null) {
      return before.glyph.level.isOdd ? before.x : before.x + before.advance;
    }
    if (paragraphRtl) {
      final double right = contentRight ?? (line.x + line.width);
      return right > line.x ? right : line.x;
    }
    return line.x;
  }

  /// Next logical index one visual step on [line], or null at the edge.
  static int? visualNeighbor(
    LaidOutLine line,
    int logicalIndex, {
    required bool toRight,
  }) {
    final List<({double x, int index})> stops = visualStops(line);
    if (stops.isEmpty) {
      return null;
    }
    var at = -1;
    for (int i = 0; i < stops.length; i++) {
      if (stops[i].index == logicalIndex) {
        at = i;
        break;
      }
    }
    if (at >= 0) {
      final int next = toRight ? at + 1 : at - 1;
      if (next < 0 || next >= stops.length) {
        return null;
      }
      return stops[next].index;
    }
    final double x = caretX(line, logicalIndex);
    if (toRight) {
      for (final ({double x, int index}) stop in stops) {
        if (stop.x > x + 0.25) {
          return stop.index;
        }
      }
      return null;
    }
    for (int i = stops.length - 1; i >= 0; i--) {
      if (stops[i].x < x - 0.25) {
        return stops[i].index;
      }
    }
    return null;
  }

  /// Insertion points on [line] in left-to-right visual order.
  static List<({double x, int index})> visualStops(LaidOutLine line) {
    if (line.glyphs.isEmpty) {
      return const <({double x, int index})>[];
    }
    final Set<int> seen = <int>{};
    final List<({double x, int index})> stops = <({double x, int index})>[];
    void add(int index) {
      if (!seen.add(index)) {
        return;
      }
      stops.add((x: caretX(line, index), index: index));
    }

    for (final LaidOutGlyph glyph in line.glyphs) {
      if (glyph.advance <= 0) {
        continue;
      }
      add(glyph.glyph.logicalIndex);
    }
    var end = 0;
    for (final LaidOutGlyph glyph in line.glyphs) {
      final int after = glyph.glyph.logicalIndex + 1;
      if (after > end) {
        end = after;
      }
    }
    add(end);
    stops.sort((({double x, int index}) a, ({double x, int index}) b) {
      final int byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.index.compareTo(b.index);
    });
    return stops;
  }

  /// Logical index for a click on [line] at page X [x].
  static int hitLogicalIndex(LaidOutLine line, double x) {
    if (line.glyphs.isEmpty) {
      return 0;
    }
    for (final LaidOutGlyph glyph in line.glyphs) {
      if (x < glyph.x || x > glyph.x + glyph.advance) {
        continue;
      }
      final bool leftHalf = x <= glyph.x + glyph.advance / 2;
      if (glyph.glyph.level.isOdd) {
        return leftHalf
            ? glyph.glyph.logicalIndex + 1
            : glyph.glyph.logicalIndex;
      }
      return leftHalf ? glyph.glyph.logicalIndex : glyph.glyph.logicalIndex + 1;
    }
    if (x < line.glyphs.first.x) {
      final LaidOutGlyph first = line.glyphs.first;
      return first.glyph.level.isOdd
          ? first.glyph.logicalIndex + 1
          : first.glyph.logicalIndex;
    }
    final LaidOutGlyph last = line.glyphs.last;
    return last.glyph.level.isOdd
        ? last.glyph.logicalIndex
        : last.glyph.logicalIndex + 1;
  }

  /// Inclusive logical range covered by [line] (min index … end after last).
  static ({int min, int max}) logicalSpan(LaidOutLine line) {
    if (line.glyphs.isEmpty) {
      return (min: 0, max: 0);
    }
    var min = line.glyphs.first.glyph.logicalIndex;
    var max = min + 1;
    for (final LaidOutGlyph glyph in line.glyphs) {
      if (glyph.glyph.logicalIndex < min) {
        min = glyph.glyph.logicalIndex;
      }
      final int end = glyph.glyph.logicalIndex + 1;
      if (end > max) {
        max = end;
      }
    }
    return (min: min, max: max);
  }

  /// True when this caret should be painted on [line].
  ///
  /// Uses min/max logical indices so RTL visual order (high index first)
  /// still matches. The exclusive end belongs to [line] only when it is
  /// the last line of the paragraph.
  bool isOnLine(LaidOutLine line, {required bool lastOfParagraph}) {
    if (line.paragraphIndex != paragraphIndex) {
      return false;
    }
    if (line.glyphs.isEmpty) {
      return lastOfParagraph;
    }
    final (:int min, :int max) = logicalSpan(line);
    if (logicalIndex < min) {
      return false;
    }
    if (logicalIndex < max) {
      return true;
    }
    return logicalIndex == max && lastOfParagraph;
  }

  /// Direction hook: true when the insertion point writes RTL.
  bool rtlAtCaret(
    BrokenLine line, {
    bool? paragraphRtl,
    String nearbyText = '',
  }) {
    return resolveRtl(
      line: line,
      logicalIndex: logicalIndex,
      paragraphRtl: paragraphRtl,
      nearbyText: nearbyText,
    );
  }

  /// Same as [rtlAtCaret] using a laid-out Word line (glyph levels).
  bool rtlAtLaidOut(
    LaidOutLine line, {
    bool? paragraphRtl,
    String nearbyText = '',
  }) {
    if (line.glyphs.isNotEmpty) {
      for (final LaidOutGlyph g in line.glyphs) {
        if (g.glyph.logicalIndex == logicalIndex) {
          return g.glyph.level.isOdd;
        }
      }
      if (logicalIndex > 0) {
        for (final LaidOutGlyph g in line.glyphs) {
          if (g.glyph.logicalIndex == logicalIndex - 1) {
            return g.glyph.level.isOdd;
          }
        }
      }
      return line.glyphs.last.glyph.level.isOdd;
    }
    return resolveRtl(
      logicalIndex: logicalIndex,
      paragraphRtl: paragraphRtl,
      nearbyText: nearbyText,
    );
  }

  /// Word-style writing direction at [logicalIndex].
  static bool resolveRtl({
    BrokenLine? line,
    int logicalIndex = 0,
    bool? paragraphRtl,
    String nearbyText = '',
  }) {
    if (line != null && line.glyphs.isNotEmpty) {
      for (final ShapedGlyph g in line.glyphs) {
        if (g.logicalIndex == logicalIndex) {
          return g.level.isOdd;
        }
      }
      if (logicalIndex > 0) {
        for (final ShapedGlyph g in line.glyphs) {
          if (g.logicalIndex == logicalIndex - 1) {
            return g.level.isOdd;
          }
        }
      }
      return line.glyphs.last.level.isOdd;
    }
    final bool? fromText = strongRtlAt(nearbyText, logicalIndex);
    if (fromText != null) {
      return fromText;
    }
    return paragraphRtl ?? false;
  }

  /// First strong character around [index], or `null` when none.
  static bool? strongRtlAt(String text, int index) {
    if (text.isEmpty) {
      return null;
    }
    final int i = index.clamp(0, text.length);
    for (int k = i - 1; k >= 0; k--) {
      final bool? dir = _strongDir(text.codeUnitAt(k));
      if (dir != null) {
        return dir;
      }
    }
    for (int k = i; k < text.length; k++) {
      final bool? dir = _strongDir(text.codeUnitAt(k));
      if (dir != null) {
        return dir;
      }
    }
    return null;
  }

  static bool? _strongDir(int cp) {
    if (OfficeTypeface.isRtlCodePoint(cp)) {
      return true;
    }
    if ((cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A) ||
        (cp >= 0x00C0 && cp <= 0x024F)) {
      return false;
    }
    return null;
  }

  /// Device UI language writes RTL (Arabic, Hebrew, …).
  static bool deviceRtl({Locale? locale}) {
    if (locale != null) {
      return _localeWritesRtl(locale);
    }
    final PlatformDispatcher dispatcher = PlatformDispatcher.instance;
    if (_localeWritesRtl(dispatcher.locale)) {
      return true;
    }
    if (!kIsWeb) {
      final String tag = Platform.localeName.toLowerCase().replaceAll('-', '_');
      final String lang = tag.split(RegExp(r'[_.]')).first;
      if (_langWritesRtl(lang)) {
        return true;
      }
    }
    return false;
  }

  static bool _localeWritesRtl(Locale locale) {
    final String script = (locale.scriptCode ?? '').toLowerCase();
    if (script == 'arab' || script == 'hebr') {
      return true;
    }
    return _langWritesRtl(locale.languageCode.toLowerCase());
  }

  static bool _langWritesRtl(String lang) {
    return lang == 'ar' ||
        lang == 'he' ||
        lang == 'fa' ||
        lang == 'ur' ||
        lang == 'yi' ||
        lang == 'ps' ||
        lang == 'iw' ||
        lang == 'ku' ||
        lang == 'sd';
  }

  /// Soft Office-style stem; optional RTL direction flag.
  ///
  /// LTR: thin rounded bar only. RTL: same bar plus a left-pointing
  /// flag at the top, matching Word's writing-direction caret.
  static Path flaggedPath(Rect stem, {required bool rtl}) {
    final double w = stem.width.clamp(0.95, 1.35);
    final Rect bar = Rect.fromCenter(
      center: Offset(stem.center.dx, stem.center.dy),
      width: w,
      height: stem.height,
    );
    final Radius round = Radius.circular(w * 0.55);
    final Path path = Path()..addRRect(RRect.fromRectAndRadius(bar, round));
    if (!rtl) {
      return path;
    }
    final double flagLen = (stem.height * 0.34).clamp(4.5, 7.5);
    final double flagH = flagLen * 0.95;
    final double midX = bar.center.dx;
    final double top = bar.top;
    path
      ..moveTo(midX + w * 0.15, top)
      ..lineTo(midX - flagLen, top + flagH * 0.08)
      ..lineTo(midX + w * 0.05, top + flagH)
      ..close();
    return path;
  }

  /// Soft fill; [rtl] true draws the direction flag.
  ///
  /// Callers should pass writing direction (paragraph / surface / BiDi at
  /// caret). Falls back to [deviceRtl] only when [rtl] is omitted.
  static void paintFlagged(
    Canvas canvas, {
    required Rect stem,
    required Color color,
    bool? rtl,
  }) {
    final bool showFlag = rtl ?? deviceRtl();
    final double alpha = (color.a * 0.78).clamp(0.45, 0.9);
    canvas.drawPath(
      flaggedPath(stem, rtl: showFlag),
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
  }
}
