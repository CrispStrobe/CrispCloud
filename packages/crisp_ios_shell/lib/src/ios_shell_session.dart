import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'canonical_input.dart';

/// One interactive, in-process Dash session backed by bundled iOS frameworks.
///
/// Only one native session can be active because ios_system's utilities retain
/// process-wide cwd and other legacy state. The caller must retain any security
/// scoped directory grant until [exitCode] completes, and use absolute paths for
/// its own concurrent file work. Commands run with the app's OS sandbox access.
class IosShellSession {
  IosShellSession._(this._channel, this._id) {
    _controller = StreamController<String>(
      onListen: _startPump,
      onPause: () => _paused = true,
      onResume: _resume,
      onCancel: () {
        _discard = true;
        return close();
      },
    );
    _decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(_TextSink(_emitNative));
    // Exit may fail before a UI has attached its observer. Preserve that error
    // for callers while preventing an unhandled asynchronous error race.
    unawaited(_exit.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  static const _defaultChannel = MethodChannel('crisp_ios_shell/control');
  final MethodChannel _channel;
  final String _id;
  final CanonicalInput _input = CanonicalInput();
  final Completer<int> _exit = Completer<int>();
  late final StreamController<String> _controller;
  late final ByteConversionSink _decoder;
  Future<void>? _pump;
  Future<void>? _close;
  Future<void> _writeTail = Future.value();
  Completer<void>? _resumeWaiter;
  bool _paused = false;
  bool _closing = false;
  bool _discard = false;
  bool _ended = false;
  bool _previousCr = false;

  /// Starts Dash in an existing absolute directory. Native errors are explicit:
  /// `session_busy`, `invalid_directory`, `engine_error`, or `invalid_arguments`.
  static Future<IosShellSession> start({
    required String workingDirectory,
    int columns = 80,
    int rows = 24,
    @visibleForTesting MethodChannel channel = _defaultChannel,
  }) async {
    if (!workingDirectory.startsWith('/') || workingDirectory.contains('\x00')) {
      throw ArgumentError.value(workingDirectory, 'workingDirectory',
          'An absolute directory without NUL is required');
    }
    _validateSize(columns, rows);
    final reply = await channel.invokeMapMethod<String, Object?>('start', {
      'workingDirectory': workingDirectory,
      'columns': columns,
      'rows': rows,
    });
    final id = reply?['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Native shell returned no session identifier');
    }
    return IosShellSession._(channel, id);
  }

  /// Buffered until listened to, then pulled with bounded native backpressure.
  /// Final native output is delivered before this stream ends.
  Stream<String> get output => _controller.stream;

  /// Completes after native cleanup and output drain. Subscribe to [output] or
  /// call [close] to drive the drain.
  Future<int> get exitCode => _exit.future;

  Future<void> write(String data) {
    if (_closing || _ended) return Future.value();
    final next = _writeTail.then((_) async {
      if (_closing || _ended) return;
      for (final action in _input.accept(data)) {
        if (_closing || _ended) return;
        switch (action.kind) {
          case 'echo':
            _emit(action.text);
          case 'write':
            await _invoke('write', {'data': Uint8List.fromList(utf8.encode(action.text))});
          case 'interrupt':
            await interrupt();
          case 'eof':
            await sendEof();
        }
      }
    });
    _writeTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> resize(int columns, int rows) async {
    _validateSize(columns, rows);
    if (_closing || _ended) return;
    await _invoke('resize', {'columns': columns, 'rows': rows});
  }

  /// Cooperatively interrupts the active command; Dash remains interactive.
  Future<void> interrupt() async {
    if (_closing || _ended) return;
    await _invoke('interrupt');
  }

  /// Closes the input stream. Unlike a PTY's transient VEOF, this is permanent
  /// EOF for the session; commands and Dash finish after any queued input.
  Future<void> sendEof() async {
    if (_closing || _ended) return;
    await _invoke('eof');
  }

  /// Idempotently cancels the command tree, releases native resources, and drains
  /// remaining output. Closing a paused/unlistened stream discards its tail so
  /// resource cleanup cannot depend on a subscriber resuming.
  Future<void> close() => _close ??= _closeSession();

  Future<void> _closeSession() async {
    if (_ended) return;
    _closing = true;
    if (_paused || !_controller.hasListener) _discard = true;
    _resume();
    final cancellation = _invoke('close');
    _startPump();
    try {
      await cancellation;
    } catch (error, stack) {
      _fail(error, stack);
    }
    await _exit.future;
  }

  Future<void> _invoke(String method, [Map<String, Object?> fields = const {}]) =>
      _channel.invokeMethod<void>(method, {'sessionId': _id, ...fields});

  void _startPump() {
    _pump ??= _readLoop();
  }

  void _resume() {
    _paused = false;
    _resumeWaiter?.complete();
    _resumeWaiter = null;
  }

  Future<void> _readLoop() async {
    try {
      while (!_ended) {
        if (_paused && !_closing) {
          _resumeWaiter ??= Completer<void>();
          await _resumeWaiter!.future;
          continue;
        }
        final reply = await _channel.invokeMapMethod<String, Object?>('read', {'sessionId': _id});
        if (reply == null) throw const FormatException('Native shell returned no read result');
        final data = reply['data'];
        if (data is! Uint8List) throw const FormatException('Native shell returned invalid output');
        if (data.isNotEmpty) _decoder.add(data);
        final status = reply['exitCode'];
        if (status != null) {
          if (status is! int) throw const FormatException('Native shell returned invalid exit code');
          _decoder.close();
          _ended = true;
          if (!_exit.isCompleted) _exit.complete(status);
          unawaited(_controller.close());
        }
      }
    } catch (error, stack) {
      _fail(error, stack);
      // A failed transport must still attempt cancellation; never hide the
      // original error or keep the native singleton reserved indefinitely.
      try {
        await _invoke('close');
      } catch (_) {}
    }
  }

  void _emitNative(String data) {
    final text = StringBuffer();
    for (final code in data.codeUnits) {
      if (code == 10 && !_previousCr) text.writeCharCode(13);
      text.writeCharCode(code);
      _previousCr = code == 13;
    }
    _emit(text.toString());
  }

  void _emit(String text) {
    if (!_ended && !_discard && text.isNotEmpty) _controller.add(text);
  }

  void _fail(Object error, StackTrace stack) {
    if (_ended) return;
    _ended = true;
    if (!_discard) _controller.addError(error, stack);
    if (!_exit.isCompleted) _exit.completeError(error, stack);
    _resume();
    unawaited(_controller.close());
  }

  static void _validateSize(int columns, int rows) {
    if (columns < 1 || rows < 1 || columns > 9999 || rows > 9999) {
      throw ArgumentError('Terminal dimensions must be between 1 and 9999');
    }
  }
}

class _TextSink implements Sink<String> {
  _TextSink(this.addText);
  final void Function(String) addText;
  @override
  void add(String data) => addText(data);
  @override
  void close() {}
}
