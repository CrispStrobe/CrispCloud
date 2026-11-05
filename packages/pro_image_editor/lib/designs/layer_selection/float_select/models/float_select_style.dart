import 'package:flutter/widgets.dart';

/// Defines visual styles for FloatSelect elements
class FloatSelectStyle {
  /// Creates a style with optional visual overrides
  const FloatSelectStyle({
    this.outsideSpace = 5.0,
    this.strokeWidth = 2.0,
    this.handlerLength,
    this.handlerGap = 10.0,
    this.strokeColor = const Color(0xFFFFFFFF),
    this.offset = const Offset(0, -10),
    this.selectionPadding = const EdgeInsets.all(16),
    this.buttonTextStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontWeight: FontWeight.bold,
    ),
    this.buttonDisabledTextStyle = const TextStyle(
      color: Color(0x61FFFFFF),
      fontWeight: FontWeight.bold,
    ),
    this.toolbarColor = const Color(0xDD000000),
    this.toolbarRadius = 8.0,
  });

  /// Space around the selected element
  final double outsideSpace;

  /// Width of the selection stroke
  final double strokeWidth;

  /// Optional length of handlers
  final double? handlerLength;

  /// Gap between handlers and content
  final double handlerGap;

  /// Color of the selection stroke
  final Color strokeColor;

  /// Offset of the toolbar
  final Offset offset;

  /// Padding around the selection box
  final EdgeInsets selectionPadding;

  /// Style for enabled toolbar buttons
  final TextStyle buttonTextStyle;

  /// Style for disabled toolbar buttons
  final TextStyle buttonDisabledTextStyle;

  /// Background color of the toolbar
  final Color toolbarColor;

  /// Border radius of the toolbar
  final double toolbarRadius;

  /// Returns a copy with overridden style values
  FloatSelectStyle copyWith({
    double? outsideSpace,
    double? strokeWidth,
    double? handlerLength,
    double? handlerGap,
    Color? strokeColor,
    Offset? offset,
    EdgeInsets? selectionPadding,
    TextStyle? buttonTextStyle,
    TextStyle? buttonDisabledTextStyle,
    Color? toolbarColor,
    double? toolbarRadius,
  }) {
    return FloatSelectStyle(
      outsideSpace: outsideSpace ?? this.outsideSpace,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      handlerLength: handlerLength ?? this.handlerLength,
      handlerGap: handlerGap ?? this.handlerGap,
      strokeColor: strokeColor ?? this.strokeColor,
      offset: offset ?? this.offset,
      selectionPadding: selectionPadding ?? this.selectionPadding,
      buttonTextStyle: buttonTextStyle ?? this.buttonTextStyle,
      buttonDisabledTextStyle:
          buttonDisabledTextStyle ?? this.buttonDisabledTextStyle,
      toolbarColor: toolbarColor ?? this.toolbarColor,
      toolbarRadius: toolbarRadius ?? this.toolbarRadius,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FloatSelectStyle &&
        other.outsideSpace == outsideSpace &&
        other.strokeWidth == strokeWidth &&
        other.handlerLength == handlerLength &&
        other.handlerGap == handlerGap &&
        other.strokeColor == strokeColor &&
        other.offset == offset &&
        other.selectionPadding == selectionPadding &&
        other.buttonTextStyle == buttonTextStyle &&
        other.buttonDisabledTextStyle == buttonDisabledTextStyle &&
        other.toolbarColor == toolbarColor &&
        other.toolbarRadius == toolbarRadius;
  }

  @override
  int get hashCode {
    return outsideSpace.hashCode ^
        strokeWidth.hashCode ^
        handlerLength.hashCode ^
        handlerGap.hashCode ^
        strokeColor.hashCode ^
        offset.hashCode ^
        selectionPadding.hashCode ^
        buttonTextStyle.hashCode ^
        buttonDisabledTextStyle.hashCode ^
        toolbarColor.hashCode ^
        toolbarRadius.hashCode;
  }
}
