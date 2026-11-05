import 'float_select_i18n.dart';
import 'float_select_style.dart';
import 'float_select_widgets.dart';

export 'float_select_i18n.dart';
export 'float_select_style.dart';
export 'float_select_widgets.dart';

/// Holds config for style, i18n, and custom widgets
class FloatSelectConfigs {
  /// Creates a config with optional overrides
  const FloatSelectConfigs({
    this.style = const FloatSelectStyle(),
    this.i18n = const FloatSelectI18n(),
    this.widgets = const FloatSelectWidgets(),
    this.enableEditButton = true,
    this.enableForwardButton = false,
    this.enableBackwardButton = false,
    this.enableMoveToFrontButton = false,
    this.enableMoveToBackButton = false,
    this.enableDuplicateButton = true,
    this.enableDeleteButton = true,
  });

  /// Style settings for the widget
  final FloatSelectStyle style;

  /// Localization settings
  final FloatSelectI18n i18n;

  /// Widget overrides
  final FloatSelectWidgets widgets;

  /// Whether the edit button is shown
  final bool enableEditButton;

  /// Whether the forward button is shown
  final bool enableForwardButton;

  /// Whether the backward button is shown
  final bool enableBackwardButton;

  /// Whether the move-to-front button is shown
  final bool enableMoveToFrontButton;

  /// Whether the move-to-back button is shown
  final bool enableMoveToBackButton;

  /// Whether the duplicate button is shown
  final bool enableDuplicateButton;

  /// Whether the delete button is shown
  final bool enableDeleteButton;

  /// Returns a copy with overridden values
  FloatSelectConfigs copyWith({
    FloatSelectStyle? style,
    FloatSelectI18n? i18n,
    FloatSelectWidgets? widgets,
    bool? enableEditButton,
    bool? enableForwardButton,
    bool? enableBackwardButton,
    bool? enableMoveToFrontButton,
    bool? enableMoveToBackButton,
    bool? enableDuplicateButton,
    bool? enableDeleteButton,
  }) {
    return FloatSelectConfigs(
      style: style ?? this.style,
      i18n: i18n ?? this.i18n,
      widgets: widgets ?? this.widgets,
      enableEditButton: enableEditButton ?? this.enableEditButton,
      enableForwardButton: enableForwardButton ?? this.enableForwardButton,
      enableBackwardButton: enableBackwardButton ?? this.enableBackwardButton,
      enableMoveToFrontButton:
          enableMoveToFrontButton ?? this.enableMoveToFrontButton,
      enableMoveToBackButton:
          enableMoveToBackButton ?? this.enableMoveToBackButton,
      enableDuplicateButton:
          enableDuplicateButton ?? this.enableDuplicateButton,
      enableDeleteButton: enableDeleteButton ?? this.enableDeleteButton,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FloatSelectConfigs &&
        other.style == style &&
        other.i18n == i18n &&
        other.widgets == widgets &&
        other.enableEditButton == enableEditButton &&
        other.enableForwardButton == enableForwardButton &&
        other.enableBackwardButton == enableBackwardButton &&
        other.enableMoveToFrontButton == enableMoveToFrontButton &&
        other.enableMoveToBackButton == enableMoveToBackButton &&
        other.enableDuplicateButton == enableDuplicateButton &&
        other.enableDeleteButton == enableDeleteButton;
  }

  @override
  int get hashCode {
    return style.hashCode ^
        i18n.hashCode ^
        widgets.hashCode ^
        enableEditButton.hashCode ^
        enableForwardButton.hashCode ^
        enableBackwardButton.hashCode ^
        enableMoveToFrontButton.hashCode ^
        enableMoveToBackButton.hashCode ^
        enableDuplicateButton.hashCode ^
        enableDeleteButton.hashCode;
  }
}
