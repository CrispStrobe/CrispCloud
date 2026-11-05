import 'package:flutter/widgets.dart';

/// A model representing a single line of text and its layout metrics,
/// with support for cursor adjustments and rounded background rendering.
///
/// This class wraps [LineMetrics] and provides additional information
/// such as custom width/position overrides, text alignment adjustments,
/// and control over corner rounding.
class LineMetricsModel {
  /// Creates a [LineMetricsModel] with the given layout data.
  LineMetricsModel({
    required this.metrics,
    required this.length,
    required this.textAlign,
    this.cursorWidth = 0,
  });

  /// Whether the line has custom overrides for width or x-position.
  bool get isOverriden => overrideWidth != null || overrideX != null;

  /// Optional custom width to override the line's original width.
  double? overrideWidth;

  /// Optional custom x-position to override the line's calculated x.
  double? overrideX;

  /// Whether the top-left corner should be rounded when rendering.
  bool roundTopLeft = true;

  /// Whether the bottom-left corner should be rounded when rendering.
  bool roundBottomLeft = true;

  /// Whether the top-right corner should be rounded when rendering.
  bool roundTopRight = true;

  /// Whether the bottom-right corner should be rounded when rendering.
  bool roundBottomRight = true;

  /// The width reserved for the text cursor.
  final double cursorWidth;

  /// The horizontal alignment of the text on this line.
  final TextAlign textAlign;

  /// Flutter's layout metrics for the text line.
  final LineMetrics metrics;

  /// The total number of lines in the full text layout.
  final int length;

  /// Returns `true` if the line has no visible width.
  bool get isEmpty => rawWidth == 0.0;

  /// Returns `true` if this is the first line in the text.
  bool get isFirst => metrics.lineNumber == 0;

  /// Returns `true` if this is the last line in the text.
  bool get isLast => metrics.lineNumber == length - 1;

  /// Computes the outer border radius based on the line height.
  double outerRadius(double outerRadius) => (rawHeight * outerRadius) / 35;

  /// Computes the inner border radius based on the line height.
  double innerRadius(double innerRadius) => (rawHeight * innerRadius) / 35;

  /// The x-coordinate at which the line starts.
  double get startX => x;

  /// The x-coordinate at which the line ends.
  double get endX => x + rawWidth;

  /// The y-coordinate at which the line starts.
  double get startY => y;

  /// The y-coordinate at which the line ends.
  double get endY => y + rawHeight;

  /// The x position of the line
  double get x => overrideX ?? metrics.left;

  /// The y-position of the line's top edge.
  double get y => metrics.baseline - metrics.ascent;

  /// The total height of the line (ascent + descent).
  double get rawHeight => metrics.ascent + metrics.descent;

  /// The width of the line, using override if set.
  double get rawWidth => overrideWidth ?? metrics.width;

  /// The full width of the line including its x-position.
  double get fullWidth => x + rawWidth;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LineMetricsModel &&
        other.cursorWidth == cursorWidth &&
        other.textAlign == textAlign &&
        other.metrics == metrics &&
        other.length == length &&
        other.isOverriden == isOverriden &&
        other.overrideWidth == overrideWidth &&
        other.overrideX == overrideX &&
        other.roundTopLeft == roundTopLeft &&
        other.roundBottomLeft == roundBottomLeft &&
        other.roundTopRight == roundTopRight &&
        other.roundBottomRight == roundBottomRight;
  }

  @override
  int get hashCode {
    return cursorWidth.hashCode ^
        textAlign.hashCode ^
        metrics.hashCode ^
        length.hashCode ^
        isOverriden.hashCode ^
        overrideWidth.hashCode ^
        overrideX.hashCode ^
        roundTopLeft.hashCode ^
        roundBottomLeft.hashCode ^
        roundTopRight.hashCode ^
        roundBottomRight.hashCode;
  }
}
