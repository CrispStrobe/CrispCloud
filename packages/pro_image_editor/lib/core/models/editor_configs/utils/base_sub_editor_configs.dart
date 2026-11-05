/// Base configuration class for all sub-editors.
///
/// This class defines shared settings that can be reused across different
/// sub-editor configurations. It provides a common contract for features
/// that control navigation behavior or editor-specific options.
///
/// Extend this class when creating custom sub-editor configs to ensure
/// consistent behavior across all editors.
abstract class BaseSubEditorConfigs {
  /// Creates a base configuration for a sub-editor.
  ///
  /// The [enableGesturePop] property defaults to `true`.
  const BaseSubEditorConfigs({this.enableGesturePop = true});

  /// {@template layerFractionalOffset}
  /// Whether the user can dismiss (pop) this editor using system gestures.
  ///
  /// When `true`:
  /// - On **Android**, the hardware back button and the predictive back swipe
  ///   gesture can close the editor.
  ///
  /// When `false`:
  /// - All user-triggered back navigation is blocked, and the editor cannot
  ///   be closed by gestures or hardware buttons.
  ///
  /// **Important:** This only affects user-initiated actions. Calling
  /// `Navigator.pop(context)` programmatically will always close the editor,
  /// regardless of this setting.
  /// {@endtemplate}
  final bool enableGesturePop;
}
