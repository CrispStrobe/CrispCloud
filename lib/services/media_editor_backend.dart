import 'media_edit_session.dart';

abstract class MediaEditorBackend {
  Future<MediaInfo> probe(String inputPath);
  Future<List<double>> waveform(String inputPath, {int points = 800});

  /// Writes a complete output, or throws. The caller owns the output's lifetime
  /// and must not persist it until both rendering and validation have succeeded.
  Future<void> render({
    required String inputPath,
    required String outputPath,
    required MediaEdit edit,
    required MediaCancellation cancellation,
    void Function(double)? onProgress,
  });
}

class MediaOperationCancelled implements Exception {
  const MediaOperationCancelled();
  @override
  String toString() => 'MediaOperationCancelled';
}

/// Cooperative cancellation with an immediate native-adapter notification.
class MediaCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void throwIfCancelled() {
    if (_cancelled) throw const MediaOperationCancelled();
  }
}
