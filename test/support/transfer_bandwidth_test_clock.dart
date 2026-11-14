// Shared by Flutter tests and the SDK-only VM/JavaScript acceptance entry point.

import 'dart:async';

/// Deterministic monotonic clock for the real allocator and transport tests.
/// Advance timers synchronously, then drain normal asynchronous continuations.
class ManualBandwidthClock {
  Duration elapsed = Duration.zero;
  final _timers = <_ManualBandwidthTimer>[];

  int get activeTimers => _timers.where((timer) => timer.isActive).length;

  Timer timer(Duration duration, void Function() callback) {
    if (duration <= Duration.zero) {
      throw StateError('A pacing timer must have a positive duration.');
    }
    final timer = _ManualBandwidthTimer(elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
    final until = elapsed + duration;
    final due =
        _timers.where((timer) => timer.isActive && timer.due <= until).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    for (final timer in due) {
      elapsed = timer.due;
      timer.fire();
    }
    elapsed = until;
    _timers.removeWhere((timer) => !timer.isActive);
  }

  void advanceToNextTimer() {
    final active = _timers.where((timer) => timer.isActive).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    if (active.isEmpty) throw StateError('Expected a pacing timer.');
    advance(active.first.due - elapsed);
  }

  Future<void> next() async {
    await Future<void>.delayed(Duration.zero);
    advanceToNextTimer();
    await Future<void>.delayed(Duration.zero);
  }
}

class _ManualBandwidthTimer implements Timer {
  _ManualBandwidthTimer(this.due, this.callback);
  final Duration due;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}
