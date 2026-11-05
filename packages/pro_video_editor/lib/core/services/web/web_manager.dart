import 'dart:typed_data';

import '/core/models/thumbnail/key_frames_configs_model.dart';
import '/core/models/thumbnail/thumbnail_configs_model.dart';
import '/core/models/video/editor_video_model.dart';
import '/core/models/video/video_metadata_model.dart';
import '/core/services/web/web_thumbnail_generator.dart';
import 'web_meta_data_reader.dart';

/// A platform-specific implementation for handling video operations on web.
///
/// This class provides methods to extract metadata and generate thumbnails
/// using browser capabilities.
class WebManager {
  /// Retrieves metadata from the provided [EditorVideo] on the web.
  ///
  /// Loads the video using an HTML video element and extracts duration,
  /// resolution, file size, and format.
  ///
  /// Returns a [VideoMetadata] object.
  Future<VideoMetadata> getMetadata(EditorVideo value) async {
    return await WebMetaDataReader().getMetaData(value);
  }

  /// Generates thumbnails for a video based on the given [ThumbnailConfigs].
  ///
  /// Extracts frames from specified timestamps and returns them as a list of
  /// image data in [Uint8List] format.
  Future<List<Uint8List>> getThumbnails(
    ThumbnailConfigs value, {
    void Function(double progress)? onProgress,
  }) async {
    return await WebThumbnailGenerator().getThumbnails(
      value,
      onProgress: onProgress,
    );
  }

  /// Extracts evenly spaced key frames using the [KeyFramesConfigs] settings.
  ///
  /// Returns a list of [Uint8List] image data captured at calculated
  /// intervals throughout the video.
  Future<List<Uint8List>> getKeyFrames(
    KeyFramesConfigs value, {
    void Function(double progress)? onProgress,
  }) async {
    return await WebThumbnailGenerator().getKeyFrames(
      value,
      onProgress: onProgress,
    );
  }
}
