import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'caret_engine.dart';

/// Rebuilds a logical string for Flutter/HarfBuzz painting.
///
/// The layout engine stores glyphs in visual order and may remap Arabic
/// letters to presentation forms. [TextPainter] must receive the original
/// logical letters plus the run's bidi direction, or the line is drawn
/// reversed and unjoined.
abstract final class PaintRunText {
  /// fontFallbacks API.
  static const List<String> fontFallbacks = <String>[
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Tajawal',
    'DejaVu Sans',
    'Segoe UI',
    'Tahoma',
    'Arial',
  ];

  /// latinFallbacks API.
  static const List<String> latinFallbacks = <String>[
    'Calibri',
    'Carlito',
    'Liberation Serif',
    'Times New Roman',
    'Noto Serif',
    'DejaVu Serif',
    'Georgia',
    'serif',
  ];

  /// familyFor API.
  static String familyFor({
    required String text,
    String? runFamily,
    String? themeFamily,
  }) {
    return OfficeTypeface.paintFamily(
      text: text,
      runFamily: runFamily,
      themeFamily: themeFamily,
    );
  }

  /// fallbacksFor API.
  static List<String> fallbacksFor(String text, {String? runFamily}) {
    final List<String> base = looksRtl(text) ? fontFallbacks : latinFallbacks;
    if (runFamily == null || runFamily.isEmpty) {
      return base;
    }
    return <String>[
      runFamily,
      ...base.where((String family) => family != runFamily),
    ];
  }

  /// isRtlLevel API.
  static bool isRtlLevel(int level) => level.isOdd;

  /// looksRtl API.
  static bool looksRtl(String text) => OfficeTypeface.isRtlText(text);

  /// directionFor API.
  static TextDirection directionFor({
    required int bidiLevel,
    String text = '',
  }) {
    if (isRtlLevel(bidiLevel) || looksRtl(text)) {
      return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  /// logicalSlice API.
  static String logicalSlice(String paragraph, Iterable<int> logicalIndices) {
    if (paragraph.isEmpty) {
      return '';
    }
    var start = paragraph.length;
    var end = 0;
    for (final int i in logicalIndices) {
      if (i < 0 || i >= paragraph.length) {
        continue;
      }
      if (i < start) {
        start = i;
      }
      var e = i + 1;
      final int cu = paragraph.codeUnitAt(i);
      if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < paragraph.length) {
        e = i + 2;
      }
      while (e < paragraph.length && _isMark(paragraph.codeUnitAt(e))) {
        e++;
      }
      if (e > end) {
        end = e;
      }
    }
    if (start >= end) {
      return '';
    }
    return paragraph.substring(start, end);
  }

  /// Justified lines paint each word at [LaidOutGlyph.x]; caret/hit must too.
  static bool splitsWordsForPaint(LaidOutLine line) {
    return (line.justification == WmlJustification.justify ||
            line.justification == WmlJustification.distributed) &&
        line.justificationRatio != 0;
  }

  static bool _isTab(LaidOutGlyph glyph) => glyph.glyph.codePoint == 0x09;

  /// samePaintRun API.
  static bool samePaintRun(LaidOutGlyph a, LaidOutGlyph b) {
    if (_isTab(a) || _isTab(b)) {
      return false;
    }
    return a.color == b.color &&
        a.fontSize == b.fontSize &&
        a.bold == b.bold &&
        a.italic == b.italic &&
        a.underline == b.underline &&
        a.highlight == b.highlight &&
        a.fontFamily == b.fontFamily &&
        a.vertAlign == b.vertAlign &&
        a.commentIds.join(',') == b.commentIds.join(',') &&
        a.glyph.level.isOdd == b.glyph.level.isOdd;
  }

  /// Runs painted as a single [TextPainter] (word-split when justified).
  static Iterable<List<LaidOutGlyph>> paintSegments(LaidOutLine line) sync* {
    var start = 0;
    final bool splitWords = splitsWordsForPaint(line);
    while (start < line.glyphs.length) {
      final LaidOutGlyph first = line.glyphs[start];
      var end = start + 1;
      while (end < line.glyphs.length &&
          samePaintRun(first, line.glyphs[end])) {
        end++;
      }
      if (!splitWords) {
        yield line.glyphs.sublist(start, end);
        start = end;
        continue;
      }
      var i = start;
      while (i < end) {
        if (line.glyphs[i].glyph.isSpace) {
          yield <LaidOutGlyph>[line.glyphs[i]];
          i++;
          continue;
        }
        var j = i + 1;
        while (j < end && !line.glyphs[j].glyph.isSpace) {
          j++;
        }
        yield line.glyphs.sublist(i, j);
        i = j;
      }
      start = end;
    }
  }

  /// Measures each paint run and places it after the previous one.
  ///
  /// Run origins stay sequential (so mixed styles never overlap). Within a
  /// run, each glyph box comes from [TextPainter] selection boxes / caret
  /// offsets so the caret lands on real ink edges, not proportional shares.
  static void fitLine(
    LaidOutLine line,
    String paragraph, {
    String? themeFamily,
  }) {
    if (line.glyphs.isEmpty) {
      return;
    }
    final double origin = line.x;
    final double previousWidth = line.width;
    var x = line.x;
    var start = 0;
    while (start < line.glyphs.length) {
      final LaidOutGlyph first = line.glyphs[start];
      var end = start + 1;
      while (end < line.glyphs.length &&
          samePaintRun(first, line.glyphs[end])) {
        end++;
      }
      final List<LaidOutGlyph> run = line.glyphs.sublist(start, end);
      final String text = runText(paragraph, run);
      if (text.isEmpty || run.every(_isTab)) {
        for (final LaidOutGlyph glyph in run) {
          glyph.x = x + glyph.paintDx;
          x += glyph.advance;
        }
        start = end;
        continue;
      }
      final TextPainter painter = painterFor(
        text: text,
        first: first,
        themeFamily: themeFamily,
      )..layout();
      _placeRun(run, painter, text, paragraph, x);
      x += painter.width;
      start = end;
    }
    line.width = (x - line.x).clamp(0, double.infinity);
    _realignAfterFit(line, origin, previousWidth);
    line.applyJustification(targetWidth: previousWidth);
  }

  static void _realignAfterFit(
    LaidOutLine line,
    double origin,
    double previousWidth,
  ) {
    final double dx = switch (line.justification) {
      WmlJustification.right =>
        (origin + previousWidth) - (line.x + line.width),
      WmlJustification.center => (previousWidth - line.width) / 2,
      WmlJustification.left ||
      WmlJustification.justify ||
      WmlJustification.distributed => 0,
    };
    if (dx == 0) {
      return;
    }
    line.x += dx;
    for (final LaidOutGlyph glyph in line.glyphs) {
      glyph.x += dx;
    }
  }

  /// painterFor API.
  static TextPainter painterFor({
    required String text,
    required LaidOutGlyph first,
    String? themeFamily,
    Color? color,
    TextDecoration? decoration,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: first.fontSize,
          fontFamily: familyFor(
            text: text,
            runFamily: first.fontFamily,
            themeFamily: themeFamily,
          ),
          fontFamilyFallback: fallbacksFor(text, runFamily: first.fontFamily),
          fontWeight: first.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: first.italic ? FontStyle.italic : FontStyle.normal,
          color: color,
          decoration: decoration,
          height: 1.0,
        ),
      ),
      textDirection: directionFor(bidiLevel: first.glyph.level, text: text),
      maxLines: 1,
    );
  }

  static final Map<String, double> _advanceCache = <String, double>{};

  /// Forgets measured widths, e.g. after new fonts finish loading.
  static void clearAdvanceCache() => _advanceCache.clear();

  /// Width of [codePoint] painted in [props] at [sizePoints], as
  /// [painterFor] would paint it. Feeds [WordLayoutEngine.measure] so line
  /// breaks agree with [fitLine].
  static double advanceOf(
    int codePoint,
    double sizePoints,
    WmlRunProps props, {
    String? themeFamily,
  }) {
    final String text = String.fromCharCode(codePoint);
    final String runFamily = OfficeTypeface.familyForRun(props, codePoint);
    final String key =
        '$runFamily|$themeFamily|$sizePoints|${props.bold}|${props.italic}|'
        '$codePoint';
    final double? cached = _advanceCache[key];
    if (cached != null) {
      return cached;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: sizePoints,
          fontFamily: familyFor(
            text: text,
            runFamily: runFamily,
            themeFamily: themeFamily,
          ),
          fontFamilyFallback: fallbacksFor(text, runFamily: runFamily),
          fontWeight: props.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: props.italic ? FontStyle.italic : FontStyle.normal,
          height: 1.0,
        ),
      ),
      textDirection: looksRtl(text) ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    if (_advanceCache.length >= 20000) {
      _advanceCache.clear();
    }
    _advanceCache[key] = width;
    return width;
  }

  /// runText API.
  static String runText(String paragraph, List<LaidOutGlyph> run) {
    if (paragraph.isEmpty || run.isEmpty) {
      return '';
    }
    final List<int> indices = <int>[
      for (final LaidOutGlyph glyph in run)
        if (glyph.glyph.logicalIndex >= 0 &&
            glyph.glyph.logicalIndex < paragraph.length)
          glyph.glyph.logicalIndex,
    ]..sort();
    if (indices.isEmpty) {
      return '';
    }
    var start = indices.first;
    var end = indices.last + 1;
    if (end < paragraph.length && _isMark(paragraph.codeUnitAt(end))) {
      while (end < paragraph.length && _isMark(paragraph.codeUnitAt(end))) {
        end++;
      }
    }
    if (end - start <= indices.length + 8) {
      return paragraph.substring(start, end.clamp(0, paragraph.length));
    }
    final StringBuffer buffer = StringBuffer();
    var last = -1;
    for (final int i in indices) {
      if (i == last) {
        continue;
      }
      buffer.writeCharCode(paragraph.codeUnitAt(i));
      last = i;
    }
    return buffer.toString();
  }

  /// Page X where [painter] should be painted for [run].
  static double runPaintOrigin(
    List<LaidOutGlyph> run,
    TextPainter painter,
    String text,
    String paragraph,
  ) {
    if (run.isEmpty) {
      return 0;
    }
    final LaidOutGlyph first = run.first;
    if (text.isEmpty) {
      return first.x;
    }
    final int base = _runTextBase(paragraph, run, text);
    final int offset = (first.glyph.logicalIndex - base).clamp(0, text.length);
    final int extent = math.min(text.length, offset + _utf16Len(text, offset));
    final List<ui.TextBox> boxes = extent > offset
        ? painter.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: extent),
          )
        : const <ui.TextBox>[];
    if (boxes.isNotEmpty) {
      var left = boxes.first.left;
      for (final ui.TextBox box in boxes) {
        left = math.min(left, box.left);
      }
      return first.x - left;
    }
    return first.x - caretDx(painter, offset);
  }

  static void _placeRun(
    List<LaidOutGlyph> run,
    TextPainter painter,
    String text,
    String paragraph,
    double originX,
  ) {
    final double width = painter.width;
    if (text.isEmpty || width <= 0) {
      _placeRunProportional(run, width, originX);
      return;
    }
    final int base = _runTextBase(paragraph, run, text);
    for (final LaidOutGlyph glyph in run) {
      final int li = glyph.glyph.logicalIndex;
      final int offset = (li - base).clamp(0, text.length);
      final int extent = math.min(
        text.length,
        offset + _utf16Len(text, offset),
      );
      final List<ui.TextBox> boxes = extent > offset
          ? painter.getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: extent),
            )
          : const <ui.TextBox>[];
      if (boxes.isNotEmpty) {
        var left = boxes.first.left;
        var right = boxes.first.right;
        for (final ui.TextBox box in boxes) {
          left = math.min(left, box.left);
          right = math.max(right, box.right);
        }
        glyph.x = originX + left;
        glyph.advance = math.max(0, right - left);
        continue;
      }
      final double x0 = caretDx(painter, offset);
      final double x1 = caretDx(painter, extent);
      glyph.x = originX + math.min(x0, x1);
      glyph.advance = (x0 - x1).abs();
    }
  }

  static void _placeRunProportional(
    List<LaidOutGlyph> run,
    double width,
    double originX,
  ) {
    var weight = 0.0;
    for (final LaidOutGlyph glyph in run) {
      weight += glyph.glyph.advance;
    }
    if (weight <= 0) {
      weight = run.length.toDouble();
    }
    var x = originX;
    for (int i = 0; i < run.length; i++) {
      final LaidOutGlyph glyph = run[i];
      final double share = i == run.length - 1
          ? originX + width - x
          : width * (glyph.glyph.advance / weight);
      glyph.x = x + glyph.paintDx;
      glyph.advance = share.clamp(0, width);
      x += glyph.advance;
    }
  }

  static int _runTextBase(
    String paragraph,
    List<LaidOutGlyph> run,
    String text,
  ) {
    if (paragraph.isEmpty || run.isEmpty || text.isEmpty) {
      return 0;
    }
    var min = run.first.glyph.logicalIndex;
    for (final LaidOutGlyph glyph in run) {
      if (glyph.glyph.logicalIndex < min) {
        min = glyph.glyph.logicalIndex;
      }
    }
    if (min >= 0 && min < paragraph.length && paragraph.startsWith(text, min)) {
      return min;
    }
    final int at = paragraph.indexOf(text);
    return at >= 0 ? at : min;
  }

  static int _utf16Len(String text, int offset) {
    if (offset < 0 || offset >= text.length) {
      return 0;
    }
    final int cu = text.codeUnitAt(offset);
    if (cu >= 0xD800 && cu <= 0xDBFF && offset + 1 < text.length) {
      return 2;
    }
    return 1;
  }

  /// Page X of the insertion point using the same [TextPainter] as ink.
  static double caretXOnLine(
    LaidOutLine line,
    int logicalIndex, {
    required String paragraph,
    String? themeFamily,
    bool paragraphRtl = false,
    double? contentRight,
  }) {
    if (line.glyphs.isEmpty) {
      return CaretEngine.caretX(
        line,
        logicalIndex,
        paragraphRtl: paragraphRtl,
        contentRight: contentRight,
      );
    }
    final double? fromPainter = _caretXFromPainters(
      line,
      logicalIndex,
      paragraph: paragraph,
      themeFamily: themeFamily,
    );
    if (fromPainter != null) {
      return fromPainter;
    }
    return CaretEngine.caretX(
      line,
      logicalIndex,
      paragraphRtl: paragraphRtl,
      contentRight: contentRight,
    );
  }

  static double? _caretXFromPainters(
    LaidOutLine line,
    int logicalIndex, {
    required String paragraph,
    String? themeFamily,
  }) {
    final List<List<LaidOutGlyph>> segments = paintSegments(
      line,
    ).toList(growable: false);
    for (int s = 0; s < segments.length; s++) {
      final List<LaidOutGlyph> run = segments[s];
      final LaidOutGlyph first = run.first;
      final (:int min, :int max) = _runSpan(run);
      final bool lastRun = s == segments.length - 1;
      final bool inRun =
          logicalIndex >= min &&
          (logicalIndex < max || (logicalIndex == max && lastRun));
      if (!inRun) {
        continue;
      }
      if (logicalIndex == max && !lastRun) {
        continue;
      }
      if (run.length == 1 && first.glyph.isSpace) {
        return logicalIndex <= first.glyph.logicalIndex
            ? first.x
            : first.x + first.advance;
      }
      final String text = runText(paragraph, run);
      if (text.isEmpty) {
        continue;
      }
      final TextPainter painter = painterFor(
        text: text,
        first: first,
        themeFamily: themeFamily,
      )..layout();
      final int base = _runTextBase(paragraph, run, text);
      final int offset = (logicalIndex - base).clamp(0, text.length);
      final double origin = runPaintOrigin(run, painter, text, paragraph);
      return origin + caretDx(painter, offset);
    }
    return null;
  }

  /// Logical index for a click using shaped run painters.
  static int hitLogicalIndexOnLine(
    LaidOutLine line,
    double x, {
    required String paragraph,
    String? themeFamily,
  }) {
    if (line.glyphs.isEmpty) {
      return 0;
    }
    TextPainter? bestPainter;
    String bestText = '';
    var bestBase = 0;
    var bestOrigin = line.x;
    var bestDist = double.infinity;
    for (final List<LaidOutGlyph> run in paintSegments(line)) {
      final LaidOutGlyph first = run.first;
      if (run.length == 1 && first.glyph.isSpace) {
        final double left = first.x;
        final double right = first.x + first.advance;
        if (x >= left && x <= right) {
          return x <= left + first.advance / 2
              ? first.glyph.logicalIndex
              : first.glyph.logicalIndex + 1;
        }
        final double dist = x < left ? left - x : x - right;
        if (dist < bestDist) {
          bestDist = dist;
          bestPainter = null;
          bestText = '';
          bestBase = first.glyph.logicalIndex;
          bestOrigin = left;
        }
        continue;
      }
      final String text = runText(paragraph, run);
      if (text.isEmpty) {
        continue;
      }
      final TextPainter painter = painterFor(
        text: text,
        first: first,
        themeFamily: themeFamily,
      )..layout();
      final double origin = runPaintOrigin(run, painter, text, paragraph);
      final double left = origin;
      final double right = origin + painter.width;
      if (x >= left && x <= right) {
        final int local = hitIndex(painter, Offset(x - left, 0), text.length);
        final int base = _runTextBase(paragraph, run, text);
        final int max = paragraph.isEmpty ? 0 : paragraph.length;
        return (base + local).clamp(0, max);
      }
      final double dist = x < left ? left - x : x - right;
      if (dist < bestDist) {
        bestDist = dist;
        bestPainter = painter;
        bestText = text;
        bestBase = _runTextBase(paragraph, run, text);
        bestOrigin = left;
      }
    }
    if (bestPainter == null) {
      return CaretEngine.hitLogicalIndex(line, x);
    }
    final double localX = (x - bestOrigin).clamp(0.0, bestPainter.width);
    final int local = hitIndex(bestPainter, Offset(localX, 0), bestText.length);
    final int max = paragraph.isEmpty ? 0 : paragraph.length;
    return (bestBase + local).clamp(0, max);
  }

  static ({int min, int max}) _runSpan(List<LaidOutGlyph> run) {
    var min = run.first.glyph.logicalIndex;
    var max = min + 1;
    for (final LaidOutGlyph glyph in run) {
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

  /// plain API.
  static TextPainter plain({
    required String text,
    required double fontSize,
    required Color color,
    String? themeFamily,
    int maxLines = 1,
    TextAlign? align,
    bool? rtl,
    bool bold = false,
  }) {
    final bool useRtl = rtl ?? looksRtl(text);
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: familyFor(text: text, themeFamily: themeFamily),
          fontFamilyFallback: fallbacksFor(text),
          color: color,
        ),
      ),
      textDirection: useRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: align ?? (useRtl ? TextAlign.right : TextAlign.left),
      maxLines: maxLines,
    );
  }

  /// hitIndex API.
  static int hitIndex(TextPainter painter, Offset local, int textLength) {
    if (textLength <= 0) {
      return 0;
    }
    return painter.getPositionForOffset(local).offset.clamp(0, textLength);
  }

  /// caretDx API.
  static double caretDx(TextPainter painter, int index) {
    return painter.getOffsetForCaret(TextPosition(offset: index), Rect.zero).dx;
  }

  static bool _isMark(int cu) {
    return (cu >= 0x064B && cu <= 0x065F) ||
        cu == 0x0670 ||
        (cu >= 0x06D6 && cu <= 0x06ED) ||
        (cu >= 0x08D3 && cu <= 0x08FF);
  }
}
