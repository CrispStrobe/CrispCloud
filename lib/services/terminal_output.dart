import 'dart:async';
import 'dart:convert';

/// Combines terminal channels without losing their initial or final output.
///
/// Each channel has its own streaming UTF-8 decoder: a code point split across
/// network packets must not be decoded separately, or joined to another
/// channel's bytes. ANSI/control sequences pass through untouched.
class TerminalOutput {
  TerminalOutput(
    Iterable<Stream<List<int>>> channels, {
    void Function()? onActivity,
    void Function()? onDone,
    this._onCancel,
  }) {
    final sources = channels.toList(growable: false);
    var remaining = sources.length;
    // A single-subscription controller buffers the prompt until the terminal
    // attaches, unlike a broadcast stream which drops it in that interval.
    _controller = StreamController<String>(
      onPause: () {
        for (final subscription in _subscriptions) {
          subscription.pause();
        }
      },
      onResume: () {
        for (final subscription in _subscriptions) {
          subscription.resume();
        }
      },
      onCancel: _cancelFromListener,
    );

    void channelDone() {
      if (_closed || --remaining != 0) return;
      _closed = true;
      // Do not await close: a not-yet-attached or paused consumer must not keep
      // its SSH connection alive after both source channels have drained.
      unawaited(_controller.close());
      onDone?.call();
    }

    if (sources.isEmpty) {
      _closed = true;
      unawaited(_controller.close());
      onDone?.call();
      return;
    }
    for (final source in sources) {
      _subscriptions.add(
        source
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(
              (data) {
                if (_closed) return;
                onActivity?.call();
                _controller.add(data);
              },
              onError: (Object error, StackTrace stack) {
                if (!_closed) _controller.addError(error, stack);
              },
              onDone: channelDone,
            ),
      );
    }
  }

  final Future<void> Function()? _onCancel;
  final _subscriptions = <StreamSubscription<String>>[];
  late final StreamController<String> _controller;
  bool _closed = false;
  Future<void>? _cancelling;

  Stream<String> get stream => _controller.stream;

  /// Stops reading without waiting for a consumer to listen or resume.
  Future<void> dispose() => _cancelling ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    unawaited(_controller.close());
  }

  Future<void> _cancelFromListener() async {
    final wasClosed = _closed;
    await dispose();
    // A normal done event also invokes onCancel. Only an explicit cancellation
    // should ask the service to disconnect the still-running shell.
    if (!wasClosed) await _onCancel?.call();
  }
}
