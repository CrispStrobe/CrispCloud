import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// A control channel preserves stdout bytes and keeps stderr out of the tmux
/// grammar. In particular, UTF-8 decoding belongs to each individual pane.
class SshTmuxControlOutput {
  SshTmuxControlOutput({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required this.exitCode,
    required this._write,
    required this._close,
    void Function()? onActivity,
    void Function()? onDone,
  }) {
    unawaited(
      exitCode.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    _controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        _listening = true;
        _pendingBytes = 0;
      },
      onPause: () => _stdout?.pause(),
      onResume: () => _stdout?.resume(),
      onCancel: _cancelFromListener,
    );
    var remaining = 2;
    void channelDone() {
      if (_closed || --remaining != 0) return;
      _closed = true;
      unawaited(_controller.close());
      onDone?.call();
    }

    void error(Object error, StackTrace stack) {
      if (!_closed) _controller.addError(error, stack);
    }

    _stdout = stdout.listen(
      (data) {
        if (_closed) return;
        onActivity?.call();
        if (!_listening) {
          _pendingBytes += data.length;
          if (_pendingBytes > maxPendingBytes) {
            _controller.addError(
              StateError('tmux control startup output exceeds the limit'),
            );
            unawaited(_abort());
            return;
          }
        }
        _controller.add(Uint8List.fromList(data));
      },
      onError: error,
      onDone: channelDone,
    );
    _stderr = stderr.listen(
      (data) {
        if (_closed) return;
        onActivity?.call();
        final available = maxDiagnosticBytes - _diagnostics.length;
        if (available > 0) {
          _diagnostics.addAll(data.take(available));
        }
      },
      onError: error,
      onDone: channelDone,
    );
  }

  static const maxPendingBytes = 1024 * 1024;
  static const maxDiagnosticBytes = 16 * 1024;
  final Future<int?> exitCode;
  final Future<void> Function(String) _write;
  final Future<void> Function() _close;
  late final StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _stdout;
  StreamSubscription<List<int>>? _stderr;
  final _diagnostics = <int>[];
  bool _listening = false;
  bool _closed = false;
  int _pendingBytes = 0;
  Future<void>? _disposing;
  Future<void>? _closing;

  Stream<List<int>> get output => _controller.stream;

  String get diagnostics => utf8
      .decode(_diagnostics, allowMalformed: true)
      .replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), '')
      .trim();

  /// The callback captures the exact SSH channel generation. A stale control
  /// client can neither write to nor close a replacement shell.
  Future<void> write(String command) async {
    if (_closed) throw StateError('tmux control channel is closed');
    await _write(command);
  }

  Future<void> close() =>
      _closing ??= Future<void>.sync(_close)
          .onError((Object error, StackTrace stack) {
            _closing = null;
            Error.throwWithStackTrace(error, stack);
          });

  Future<void> _abort() async {
    await dispose();
    try {
      await close();
    } catch (_) {
      // The stream has already reported the failure; transport cleanup is
      // also owned by the service and the terminal's close operation.
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    await Future.wait([
      if (_stdout != null) _stdout!.cancel(),
      if (_stderr != null) _stderr!.cancel(),
    ]);
    unawaited(_controller.close());
  }

  Future<void> _cancelFromListener() async {
    final wasClosed = _closed;
    await dispose();
    if (!wasClosed) await close();
  }
}
