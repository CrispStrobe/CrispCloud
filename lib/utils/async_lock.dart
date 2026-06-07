import 'dart:async';

/// Simple async lock using [Completer] to serialize access to critical sections.
///
/// Each lock instance is independent, so methods guarded by different locks
/// can run concurrently (avoiding deadlocks when one locked method calls another).
class AsyncLock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await action();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}
