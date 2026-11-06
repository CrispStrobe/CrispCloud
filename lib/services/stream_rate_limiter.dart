import 'dart:async';
import 'dart:math' as math;

/// Pause/cancellation signals shared with a reviewed file operation.
abstract interface class StreamRateControl {
  bool get isCancelled;
  bool get isPaused;
  Future<void> checkpoint();
  Stream<void> get changes;
}

typedef StreamRateTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

StreamRateLimiter createStreamRateLimiter(int bytesPerSecond) =>
    StreamRateLimiter(bytesPerSecond: bytesPerSecond);

/// Paces bytes delivered to a client-side copy stream, with backpressure.
///
/// This is not a wire-level bandwidth limit: an adapter can spool these bytes
/// before uploading, and server-side copies do not consume this stream. Each
/// emitted slice is charged before delivery; idle/paused time never accrues
/// credit for a later burst. Clock and timer injection keep timing tests exact.
class StreamRateLimiter {
  StreamRateLimiter({
    required this.bytesPerSecond,
    Duration Function()? clock,
    StreamRateTimerFactory? createTimer,
  }) : _clock = clock ?? _monotonicClock(),
       _createTimer = createTimer ?? Timer.new {
    if (bytesPerSecond <= 0 || bytesPerSecond > maximumBytesPerSecond) {
      throw ArgumentError.value(bytesPerSecond, 'bytesPerSecond');
    }
  }

  static const maximumBytesPerSecond = 1099511627776;
  final int bytesPerSecond;
  final Duration Function() _clock;
  final StreamRateTimerFactory _createTimer;

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  Stream<List<int>> bind(
    Stream<List<int>> input, {
    required StreamRateControl control,
  }) async* {
    // Keep ordinary slices within 100 ms of the selected rate and 64 KiB.
    // At very low rates one byte may take longer, but remains cancellable.
    final sliceSize = math.max(1, math.min(64 * 1024, bytesPerSecond ~/ 10));
    await for (final chunk in input) {
      for (var offset = 0; offset < chunk.length;) {
        await control.checkpoint();
        final end = math.min(offset + sliceSize, chunk.length);
        await _pace(end - offset, control);
        yield chunk.sublist(offset, end);
        offset = end;
      }
    }
  }

  Future<void> _pace(int count, StreamRateControl control) async {
    var remaining =
        (count * Duration.microsecondsPerSecond + bytesPerSecond - 1) ~/
        bytesPerSecond;
    while (remaining > 0) {
      await control.checkpoint();
      final done = Completer<void>();
      Timer? timer;
      Duration? stopped;
      void wake() {
        if (!done.isCompleted) {
          stopped = _clock();
          done.complete();
        }
      }

      final changes = control.changes.listen((_) => wake());
      final started = _clock();
      try {
        // A signal before the listener was installed must not leave a timer
        // running through a pause or hold cancellation until its deadline.
        if (!control.isCancelled && !control.isPaused) {
          timer = _createTimer(Duration(microseconds: remaining), wake);
          await done.future;
          final elapsed = (stopped! - started).inMicroseconds;
          remaining -= elapsed.clamp(0, remaining);
        }
      } finally {
        timer?.cancel();
        await changes.cancel();
      }
      await control.checkpoint();
    }
  }
}
