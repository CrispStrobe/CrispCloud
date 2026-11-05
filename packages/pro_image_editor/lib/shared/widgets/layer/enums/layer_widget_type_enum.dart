/// Represents the different types of layer widgets that can be used in the
/// application.
enum LayerWidgetType {
  /// A layer that contains an emoji.
  emoji,

  /// A layer that contains text.
  text,

  /// A layer that contains a generic widget.
  widget,

  /// A layer that represents a drawable canvas.
  canvas,

  /// A layer that applies a censoring effect, such as blurring or pixelation.
  censor,

  /// An unknown or undefined layer type.
  unknown,
}
