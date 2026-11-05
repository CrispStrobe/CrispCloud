/// Metadata obtained from the decoder. Duration rounds up to a microsecond so
/// the default selection contains the final sample, including at 44.1 kHz.
class AudioMetadata {
  const AudioMetadata({
    required this.frames,
    required this.sampleRate,
    required this.channels,
  });

  final int frames;
  final int sampleRate;
  final int channels;

  Duration get duration => Duration(
    microseconds: (frames * Duration.microsecondsPerSecond + sampleRate - 1) ~/
        sampleRate,
  );
}

/// A single selected region. Edits do not modify the source.
class AudioRenderRequest {
  const AudioRenderRequest({
    required this.inputPath,
    required this.outputPath,
    required this.start,
    required this.end,
    this.gainDb = 0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.muted = false,
  });

  final String inputPath;
  final String outputPath;
  final Duration start;
  final Duration end;
  final double gainDb;
  final Duration fadeIn;
  final Duration fadeOut;
  final bool muted;
}

enum AudioFailure {
  invalidArgument,
  invalidInput,
  unsupported,
  io,
  outOfMemory,
  outputExists,
}

class AudioException implements Exception {
  const AudioException(this.reason);
  final AudioFailure reason;

  @override
  String toString() => 'AudioException(${reason.name})';
}

class AudioCancelled implements Exception {
  const AudioCancelled();

  @override
  String toString() => 'AudioCancelled';
}

/// Cancellation is delivered to a native atomic flag, including while a worker
/// isolate is inside a blocking decoder call. A token is never reset/reused.
class AudioCancellationToken {
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
    if (_cancelled) throw const AudioCancelled();
  }
}
