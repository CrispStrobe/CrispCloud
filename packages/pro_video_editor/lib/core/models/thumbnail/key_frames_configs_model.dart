import 'thumbnail_base_abstract.dart';

/// Configuration model for extracting key frames from a video.
///
/// Defines video input, output size, maximum number of key frames,
/// and rendering options for the resulting thumbnails.
class KeyFramesConfigs extends ThumbnailBase {
  /// Creates a [KeyFramesConfigs] instance with the given settings.
  ///
  /// If [maxOutputFrames] is not provided, it defaults to unlimited.
  KeyFramesConfigs({
    required super.video,
    required super.outputSize,
    super.outputFormat,
    super.boxFit,
    super.id,
    super.jpegQuality,
    int? maxOutputFrames,
  }) : maxOutputFrames = maxOutputFrames ??= double.infinity.toInt();

  /// The maximum number of frames to extract as thumbnails.
  ///
  /// Defaults to no limit when not specified.
  final int maxOutputFrames;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jpegQuality': jpegQuality,
      'boxFit': boxFit.name,
      'outputFormat': outputFormat.name,
      'outputWidth': outputSize.width.round(),
      'outputHeight': outputSize.height.round(),
      'maxOutputFrames': maxOutputFrames,
    };
  }
}
