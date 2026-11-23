import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../embed/office_host_fonts.dart';
import 'paint_run_text.dart';

typedef _RunMetricsKey = ({
  String text,
  double sizePoints,
  String requestedFamily,
  String? themeFamily,
  bool bold,
  bool italic,
  bool kerning,
  int bidiLevel,
  int fontRevision,
});

/// Measures logical Word runs with the same Flutter shaping used to paint them.
///
/// The returned source ranges use UTF-16 offsets and never split an extended
/// grapheme. Their advances come from the shaped selection/caret geometry, not
/// sums of independently shaped characters. The engine remains independent of
/// Flutter: hosts opt into this implementation through [WordRunMeasure].
///
/// A result describes this complete run in its supplied context. It does not
/// promise that reshaping either half at an arbitrary line break preserves the
/// original advances, nor expose font glyph IDs for PDF export. Callers must
/// retain shaping context and remeasure when text, style or boundaries change.
abstract final class WordRunMetrics {
  static const int _maxEntries = 256;
  static const int _maxKeyUnits = 65536;
  static const int _maxFamilyUnits = 256;

  // Only immutable Dart values are cached. Native paragraphs are released at
  // the end of every measurement, including unsuccessful measurements.
  static final _cache = <_RunMetricsKey, List<WordMeasuredCluster>?>{};
  static var _retainedKeyUnits = 0;
  static var _fontRevision = -1;
  static final _layoutControl = RegExp(r'[\t\n\r\v\f\u0085\u2028\u2029]');

  /// Releases cached values. Font registration also invalidates them lazily.
  static void clearCache() {
    _cache.clear();
    _retainedKeyUnits = 0;
  }

  /// Measures a run with one style, script font and bidi level.
  ///
  /// Tabs and line separators belong to the document layout engine; this
  /// callback declines them. It also declines invalid input or geometry that
  /// cannot be reconciled with the shaped run width, allowing the engine's
  /// existing measurement path to handle it without invented advances.
  static List<WordMeasuredCluster>? measure(
    String text,
    double sizePoints,
    WmlRunProps props,
    int bidiLevel, {
    String? themeFamily,
    // Word uses unkerned line-fit widths unless w:kern enables them at this
    // size. Keep the general shaping API contextual for non-Word consumers.
    bool respectKerningThreshold = false,
  }) {
    if (!sizePoints.isFinite || sizePoints <= 0 || bidiLevel < 0) return null;
    if (text.isEmpty) return const <WordMeasuredCluster>[];
    if (_layoutControl.hasMatch(text) || !_hasValidUtf16(text)) return null;

    final revision = OfficeHostFonts.registrationRevision;
    if (_fontRevision != revision) {
      clearCache();
      _fontRevision = revision;
    }
    final requestedFamily = OfficeTypeface.familyForRun(
      props,
      text.runes.first,
    );
    final threshold = props.kerningHalfPoints;
    final kerning =
        !respectKerningThreshold ||
        threshold != null && threshold > 0 && sizePoints * 2 >= threshold;
    final _RunMetricsKey key = (
      text: text,
      sizePoints: sizePoints,
      requestedFamily: requestedFamily,
      themeFamily: themeFamily,
      bold: props.bold,
      italic: props.italic,
      kerning: kerning,
      bidiLevel: bidiLevel,
      fontRevision: revision,
    );
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    final family = PaintRunText.familyFor(
      text: text,
      runFamily: requestedFamily,
      themeFamily: themeFamily,
    );
    final measured = _measure(key, family);
    final keyUnits = _keyUnits(key);
    if (keyUnits <= _maxKeyUnits &&
        requestedFamily.length <= _maxFamilyUnits &&
        family.length <= _maxFamilyUnits &&
        (themeFamily?.length ?? 0) <= _maxFamilyUnits) {
      _cache[key] = measured;
      _retainedKeyUnits += keyUnits;
      while (_cache.length > _maxEntries || _retainedKeyUnits > _maxKeyUnits) {
        final oldest = _cache.keys.first;
        _retainedKeyUnits -= _keyUnits(oldest);
        _cache.remove(oldest);
      }
    }
    return measured;
  }

  static List<WordMeasuredCluster>? _measure(
    _RunMetricsKey key,
    String family,
  ) {
    final text = key.text;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: key.sizePoints,
          fontFamily: family,
          fontFamilyFallback: PaintRunText.fallbacksFor(
            text,
            runFamily: key.requestedFamily,
          ),
          fontWeight: key.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: key.italic ? FontStyle.italic : FontStyle.normal,
          fontFeatures: key.kerning
              ? null
              : const [ui.FontFeature.disable('kern')],
          height: 1.0,
        ),
      ),
      textDirection: PaintRunText.directionFor(
        bidiLevel: key.bidiLevel,
        text: text,
      ),
      maxLines: 1,
    );
    try {
      painter.layout();
      final width = painter.width;
      if (!width.isFinite || width < 0 || painter.didExceedMaxLines) {
        return null;
      }
      final measured = <WordMeasuredCluster>[];
      var total = 0.0;
      var start = 0;
      for (final end in GraphemeClusters.endOffsets(text)) {
        final advance = _clusterAdvance(painter, start, end);
        if (advance == null || !advance.isFinite || advance < 0) return null;
        measured.add(
          WordMeasuredCluster(start: start, end: end, advance: advance),
        );
        total += advance;
        start = end;
      }
      // Range geometry and paragraph metrics can differ by floating-point
      // roundoff. A material difference signals that this decomposition is
      // unsupported; never scale the clusters to conceal it.
      if ((total - width).abs() > math.max(0.0001, width.abs() * 0.000001)) {
        return null;
      }
      return List<WordMeasuredCluster>.unmodifiable(measured);
    } finally {
      painter.dispose();
    }
  }

  static int _keyUnits(_RunMetricsKey key) =>
      key.text.length +
      key.requestedFamily.length +
      (key.themeFamily?.length ?? 0);

  static double? _clusterAdvance(TextPainter painter, int start, int end) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isEmpty) {
      final leading = painter.getOffsetForCaret(
        TextPosition(offset: start),
        Rect.zero,
      );
      final trailing = painter.getOffsetForCaret(
        TextPosition(offset: end, affinity: TextAffinity.upstream),
        Rect.zero,
      );
      return (trailing.dx - leading.dx).abs();
    }
    if (boxes.length == 1) {
      final box = boxes.single;
      return box.right - box.left;
    }
    // A logical range can have multiple visual boxes. Count their union so
    // fallback or mark boxes sharing the same horizontal span are not added
    // twice, and never include the gaps between separate visual intervals.
    boxes.sort((a, b) => a.left.compareTo(b.left));
    var total = 0.0;
    var left = boxes.first.left;
    var right = boxes.first.right;
    for (final ui.TextBox box in boxes) {
      if (!box.left.isFinite || !box.right.isFinite || box.right < box.left) {
        return null;
      }
      if (box.left > right) {
        total += right - left;
        left = box.left;
        right = box.right;
      } else {
        right = math.max(right, box.right);
      }
    }
    return total + right - left;
  }

  static bool _hasValidUtf16(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (++i >= text.length) return false;
        final low = text.codeUnitAt(i);
        if (low < 0xDC00 || low > 0xDFFF) return false;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return false;
      }
    }
    return true;
  }
}
