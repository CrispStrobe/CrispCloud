import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Excel-like rainbow colors for formula references.
abstract final class FormulaRefStyle {
  /// palette API.
  static const List<Color> palette = <Color>[
    Color(0xFF0070C0),
    Color(0xFFE03636),
    Color(0xFF7030A0),
    Color(0xFF548235),
    Color(0xFF00B0F0),
    Color(0xFFED7D31),
    Color(0xFFC000C0),
    Color(0xFF833C0C),
  ];

  /// colored API.
  static List<(FormulaRefSpan span, Color color)> colored(String formula) {
    final Map<String, Color> assigned = <String, Color>{};
    var next = 0;
    final List<(FormulaRefSpan, Color)> out = <(FormulaRefSpan, Color)>[];
    for (final FormulaRefSpan span in FormulaRefScanner.scan(formula)) {
      final Color color = assigned.putIfAbsent(
        span.colorKey,
        () => palette[next++ % palette.length],
      );
      out.add((span, color));
    }
    return out;
  }

  /// textSpan API.
  static TextSpan textSpan(
    String formula, {
    required Color baseColor,
    required double fontSize,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    final TextStyle base = TextStyle(
      color: baseColor,
      fontSize: fontSize,
      height: 1.0,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    final List<(FormulaRefSpan, Color)> refs = colored(formula);
    if (refs.isEmpty) {
      return TextSpan(text: formula, style: base);
    }
    final List<InlineSpan> children = <InlineSpan>[];
    var cursor = 0;
    for (final (FormulaRefSpan span, Color color) in refs) {
      final int start = span.start.clamp(0, formula.length);
      final int end = span.end.clamp(start, formula.length);
      if (start > cursor) {
        children.add(
          TextSpan(text: formula.substring(cursor, start), style: base),
        );
      }
      if (end > start) {
        children.add(
          TextSpan(
            text: formula.substring(start, end),
            style: base.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        );
      }
      cursor = end > cursor ? end : cursor;
    }
    if (cursor < formula.length) {
      children.add(TextSpan(text: formula.substring(cursor), style: base));
    }
    return TextSpan(style: base, children: children);
  }
}
