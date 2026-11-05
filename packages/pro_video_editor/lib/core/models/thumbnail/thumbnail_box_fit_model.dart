/// Defines how the video content should be fit within the thumbnail bounds.
///
/// Similar to [BoxFit], this determines whether the thumbnail should fill
/// or fit within the specified size.
enum ThumbnailBoxFit {
  /// Scales the content to completely fill the thumbnail bounds.
  ///
  /// This may crop parts of the video to maintain the aspect ratio.
  cover,

  /// Scales the content to fit entirely within the thumbnail bounds.
  ///
  /// This may result in empty space (letterboxing) to preserve aspect ratio.
  contain,
}
