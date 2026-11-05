import 'models.dart';

/// A web build compiles without dart:ffi and advertises no native audio editor.
class CrispAudio {
  CrispAudio({String? libraryPath});

  Future<AudioMetadata> probe(
    String inputPath, {
    AudioCancellationToken? cancellation,
  }) async => throw const AudioException(AudioFailure.unsupported);

  Future<List<double>> waveform(
    String inputPath, {
    int points = 800,
    AudioCancellationToken? cancellation,
    void Function(double)? onProgress,
  }) async => throw const AudioException(AudioFailure.unsupported);

  Future<void> render(
    AudioRenderRequest request, {
    AudioCancellationToken? cancellation,
    void Function(double)? onProgress,
  }) async => throw const AudioException(AudioFailure.unsupported);
}
