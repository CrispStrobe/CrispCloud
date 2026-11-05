/// Defines the cropping shape to apply to an image or video.
enum CropMode {
  /// Applies an oval crop. The resulting shape is an ellipse that may appear
  /// as a perfect circle when the aspect ratio is 1:1, or as an oval otherwise.
  /// Commonly used for avatars or soft-edged cropping.
  oval,

  /// Applies a rectangular crop. The resulting shape is a rectangle
  /// and may include custom aspect ratios or sizes.
  rectangular,
}
