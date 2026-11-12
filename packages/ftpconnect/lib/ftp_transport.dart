import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'src/ftp_stream_socket.dart';

/// Owns the native connection before TCP completes and throughout a TLS
/// upgrade. Closing a high-level Socket after SecureSocket.secure has detached
/// it does not close that pending handshake; this owner retains the raw socket.
///
/// A transport is single use. Callers keep it before awaiting [connect], then
/// close it on cancellation and in their transfer's finally block. Certificate
/// and hostname verification always use the native TLS policy/context.
class FtpSocketTransport {
  RawSocket? _raw;
  _FtpStreamSocket? _stream;
  ConnectionTask<RawSocket>? _pending;
  final _closedSignal = Completer<void>();
  Object? _closeReason;
  StackTrace? _closeTrace;
  bool _started = false;
  bool _busy = false;

  bool get isClosed => _closedSignal.isCompleted;
  Future<void> get whenClosed => _closedSignal.future;

  /// For the metadata protocol's raw reader. Never mix this with [socket]
  /// reads on the same transport.
  RawSocket get raw {
    _check();
    return _raw ?? (throw StateError('The FTP transport is not connected.'));
  }

  /// Bounded streaming adapter over the owned raw connection. After [secure],
  /// obtain this again; the previous plaintext stream has been detached.
  Socket get socket => _stream ??= _FtpStreamSocket(raw);

  Future<void> connect(
    dynamic host,
    int port, {
    required Duration timeout,
    String? tlsHost,
    SecurityContext? securityContext,
  }) async {
    _check();
    if (_started) throw StateError('The FTP transport has already been used.');
    _started = true;
    await _bounded(timeout, () async {
      final task = await RawSocket.startConnect(host, port);
      if (isClosed) {
        // DNS/TCP setup itself may finish after cancellation. Observe that
        // task's result even though the caller already received cancellation.
        unawaited(task.socket.then<void>(
          (socket) => socket.close().then<void>((_) {}, onError: (Object _) {}),
          onError: (Object _) {},
        ));
        task.cancel();
        _check();
      }
      _pending = task;
      final connected = await task.socket;
      if (isClosed) {
        await connected.close();
        _check();
      }
      _pending = null;
      _raw = connected;
      if (tlsHost != null) await _upgrade(tlsHost, securityContext);
    });
  }

  Future<void> secure(
    String host, {
    required Duration timeout,
    SecurityContext? securityContext,
  }) =>
      _bounded(timeout, () => _upgrade(host, securityContext));

  Future<void> _upgrade(String host, SecurityContext? context) async {
    final original = raw;
    if (original is RawSecureSocket) {
      throw StateError('The FTP transport is already protected by TLS.');
    }
    final stream = _stream;
    if (stream != null) await stream.flush();
    _check();
    // Keep original in _raw until the upgrade has completed. Closing it also
    // closes the native transport while the handshake Future is outstanding.
    final protected = await RawSecureSocket.secure(
      original,
      subscription: stream?.detachForTls(),
      host: host,
      context: context,
    );
    if (isClosed) {
      await protected.close();
      _check();
    }
    _raw = protected;
    _stream = null;
  }

  Future<void> _bounded(
    Duration timeout,
    Future<void> Function() operation,
  ) async {
    _check();
    if (_busy) throw StateError('An FTP connection step is already pending.');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    _busy = true;
    final deadline = Timer(
      timeout,
      () =>
          close(reason: TimeoutException('FTP connection timed out.', timeout)),
    );
    try {
      // Future.any also observes a late native completion/error after close.
      // The operation checks ownership before adopting any completed socket.
      await Future.any<void>([
        Future<void>.sync(operation),
        whenClosed.then((_) => _check()),
      ]);
      _check();
    } catch (error, trace) {
      close(reason: error, trace: trace);
      rethrow;
    } finally {
      deadline.cancel();
      _busy = false;
    }
  }

  void _check() {
    if (isClosed) {
      Error.throwWithStackTrace(
        _closeReason ?? const SocketException('FTP connection cancelled.'),
        _closeTrace ?? StackTrace.current,
      );
    }
  }

  /// Stops pending TCP/TLS work and closes the underlying native descriptor,
  /// including while a high-level stream has been detached for TLS.
  void close({Object? reason, StackTrace? trace}) {
    if (isClosed) return;
    _closeReason = reason ?? const SocketException('FTP connection cancelled.');
    _closeTrace = trace;
    _closedSignal.complete();
    _pending?.cancel();
    _pending = null;
    _stream?.destroy();
    final raw = _raw;
    _raw = null;
    if (raw != null) {
      try {
        raw.shutdown(SocketDirection.both);
      } catch (_) {
        // A native TLS error may already have shut the descriptor down.
      }
      unawaited(raw.close().then<void>((_) {}, onError: (Object _) {}));
    }
  }
}
