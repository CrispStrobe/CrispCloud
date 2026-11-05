import 'package:crisp_audio/crisp_audio.dart';

import 'media_edit_session.dart';
import 'media_editor_backend.dart';

/// Native WAV/FLAC/MP3 editing. The conditional export in crisp_audio keeps
/// web builds free from dart:ffi and fails explicitly if called there.
class MediaAudioBackend implements MediaEditorBackend {
  MediaAudioBackend({CrispAudio? engine}) : _engine = engine ?? CrispAudio();

  final CrispAudio _engine;

  @override
  Future<MediaInfo> probe(String inputPath) async {
    final metadata = await _engine.probe(inputPath);
    return _info(metadata);
  }

  MediaInfo _info(AudioMetadata metadata) => MediaInfo(
    kind: MediaKind.audio,
    duration: metadata.duration,
    sampleRate: metadata.sampleRate,
    channels: metadata.channels,
  );

  @override
  Future<List<double>> waveform(String inputPath, {int points = 800}) =>
      _engine.waveform(inputPath, points: points);

  @override
  Future<void> render({
    required String inputPath,
    required String outputPath,
    required MediaEdit edit,
    required MediaCancellation cancellation,
    void Function(double)? onProgress,
  }) async {
    cancellation.throwIfCancelled();
    final token = AudioCancellationToken();
    cancellation.addListener(token.cancel);
    try {
      // Validate against fresh decoder metadata. The native render validates
      // again and creates the destination exclusively, so a failed export
      // cannot overwrite another file or be reported as a completed edit.
      final metadata = await _engine.probe(inputPath, cancellation: token);
      edit.validate(_info(metadata));
      token.throwIfCancelled();
      await _engine.render(
        AudioRenderRequest(
          inputPath: inputPath,
          outputPath: outputPath,
          start: edit.start,
          end: edit.end,
          gainDb: edit.gainDb,
          fadeIn: edit.fadeIn,
          fadeOut: edit.fadeOut,
          muted: edit.muted,
        ),
        cancellation: token,
        onProgress: onProgress,
      );
      cancellation.throwIfCancelled();
    } on AudioCancelled {
      throw const MediaOperationCancelled();
    } finally {
      cancellation.removeListener(token.cancel);
    }
  }
}
