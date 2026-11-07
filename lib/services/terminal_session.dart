import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart';

import 'terminal_connection.dart';

enum TerminalSessionStatus {
  idle,
  connecting,
  connected,
  waitingForExit,
  disconnected,
  exited,
  failed,
}

enum TerminalSessionKind { local, sandbox, ios, ssh }

class TerminalCleanupFailure implements Exception {
  const TerminalCleanupFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'Shell cleanup could not be confirmed: $cause';
}

/// Owns the emulator and exactly one transport, independently of its viewport.
///
/// A generation guards every asynchronous operation: closing or restarting
/// during connection cannot attach a stale process or mix two shells' output.
class TerminalSession extends ChangeNotifier {
  TerminalSession() {
    terminal = _createTerminal(TerminalSessionKind.local);
    _bindTerminal();
  }

  static Terminal _createTerminal(TerminalSessionKind kind) => Terminal(
    maxLines: 10000,
    platform: kIsWeb
        ? TerminalTargetPlatform.web
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => TerminalTargetPlatform.android,
            TargetPlatform.iOS => TerminalTargetPlatform.ios,
            TargetPlatform.fuchsia => TerminalTargetPlatform.fuchsia,
            TargetPlatform.linux => TerminalTargetPlatform.linux,
            TargetPlatform.macOS => TerminalTargetPlatform.macos,
            TargetPlatform.windows => TerminalTargetPlatform.windows,
          },
    windowsPtyMode:
        kind == TerminalSessionKind.local &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows,
    // TerminalView supplies OS clipboard handlers when these are null.
    // Remote escape sequences must not read/write the local clipboard;
    // explicit user copy/paste remains available in the viewport.
    onClipboardQuery: (_) => null,
    onClipboardStore: (_, __) {},
    clipboardDecoder: (_, __) => null,
    allowITerm2ClipboardCapture: false,
    allowKittyClipboard: false,
  );

  void _bindTerminal() {
    terminal.onOutput = _write;
    terminal.onResize = (_, __, ___, ____) => _resize();
  }

  late Terminal terminal;
  TerminalSessionStatus status = TerminalSessionStatus.idle;
  TerminalSessionKind kind = TerminalSessionKind.local;
  String? label;
  Object? error;
  int? exitCode;

  TerminalConnection? _connection;
  StreamSubscription<String>? _subscription;
  Future<void> _writes = Future<void>.value();
  Future<void> _resizes = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  final _failedCleanup = <TerminalConnection, Object>{};

  bool get isConnected => status == TerminalSessionStatus.connected;
  bool get isSandbox => kind == TerminalSessionKind.sandbox;
  bool get isConnecting => status == TerminalSessionStatus.connecting;
  bool get canDisconnect =>
      _failedCleanup.isNotEmpty ||
      isConnecting ||
      isConnected ||
      status == TerminalSessionStatus.waitingForExit;

  int get columns => terminal.viewWidth.clamp(1, 10000);
  int get rows => terminal.viewHeight.clamp(1, 10000);

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> connect(
    TerminalConnectionFactory open, {
    required TerminalSessionKind kind,
    String? label,
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    final previous = _connection;
    final subscription = _subscription;
    final pendingCleanup = _failedCleanup.keys.toList();
    _connection = null;
    _subscription = null;
    _writes = Future<void>.value();
    _resizes = Future<void>.value();
    this.kind = kind;
    this.label = label;
    error = null;
    exitCode = null;
    status = TerminalSessionStatus.connecting;
    final previousTerminal = terminal;
    terminal = _createTerminal(kind)..resize(columns, rows);
    _bindTerminal();
    previousTerminal.onOutput = null;
    previousTerminal.onResize = null;
    previousTerminal.dispose();
    notifyListeners();
    await _release(previous, subscription);
    if (!_current(generation)) return;

    TerminalConnection? connection;
    try {
      await _retryCleanup(pendingCleanup);
      if (!_current(generation)) return;
      if (_failedCleanup.isNotEmpty) {
        throw TerminalCleanupFailure(_failedCleanup.values.first);
      }
      connection = await open(columns, rows);
      if (!_current(generation)) {
        await _release(connection, null);
        return;
      }
      _connection = connection;
      this.kind = switch (connection.terminalBackend) {
        TerminalBackend.sandbox => TerminalSessionKind.sandbox,
        TerminalBackend.ios => TerminalSessionKind.ios,
        TerminalBackend.ssh => TerminalSessionKind.ssh,
        TerminalBackend.host => kind,
      };
      status = TerminalSessionStatus.connected;
      _subscription = connection.output.listen(
        (data) {
          if (_current(generation)) terminal.write(data);
        },
        onError: (Object error) => _fail(generation, error),
        onDone: () => unawaited(_ended(generation, connection!)),
      );
      // Layout may have changed while the process or SSH handshake started.
      _resize();
      notifyListeners();
    } catch (error) {
      if (_current(generation)) {
        _fail(generation, error);
      } else if (connection != null) {
        await _release(connection, null);
      }
    }
  }

  void _write(String data) {
    final connection = _connection;
    final generation = _generation;
    if (!isConnected || connection == null || data.isEmpty) return;
    _writes = _writes
        .then((_) async {
          if (_current(generation) && isConnected) await connection.write(data);
        })
        .catchError((Object error) => _fail(generation, error));
  }

  void _resize() {
    final connection = _connection;
    final generation = _generation;
    if (!isConnected || connection == null) return;
    _resizes = _resizes
        .then((_) async {
          if (_current(generation) && isConnected) {
            await connection.resize(columns, rows);
          }
        })
        .catchError((Object error) => _fail(generation, error));
  }

  Future<void> _ended(int generation, TerminalConnection connection) async {
    if (!_current(generation)) return;
    _subscription = null;
    // A process can close its terminal output and keep running. Disable input
    // while preserving the user's ability to disconnect that owned process.
    status = TerminalSessionStatus.waitingForExit;
    notifyListeners();
    try {
      final code = await connection.exitCode;
      if (_current(generation)) {
        exitCode = code;
        status = TerminalSessionStatus.exited;
        notifyListeners();
      }
    } catch (error) {
      if (_current(generation)) _fail(generation, error);
    } finally {
      // Output EOF can precede process exit. Keep ownership while awaiting the
      // status so disconnect/restart/dispose can still terminate that process.
      if (identical(_connection, connection)) {
        _connection = null;
        await _release(connection, null);
      }
    }
  }

  void _fail(int generation, Object failure) {
    if (!_current(generation)) return;
    ++_generation;
    final connection = _connection;
    final subscription = _subscription;
    _connection = null;
    _subscription = null;
    error = failure;
    status = TerminalSessionStatus.failed;
    notifyListeners();
    unawaited(_release(connection, subscription));
  }

  /// Ends the process but leaves its screen available for selection/copying.
  Future<void> disconnect() async {
    if (_disposed) return;
    final generation = ++_generation;
    final connection = _connection;
    final subscription = _subscription;
    final pendingCleanup = _failedCleanup.keys.toList();
    _connection = null;
    _subscription = null;
    status = TerminalSessionStatus.disconnected;
    error = null;
    notifyListeners();
    await _release(connection, subscription);
    await _retryCleanup(pendingCleanup);
    if (!_current(generation)) return;
    if (_failedCleanup.isEmpty) {
      status = TerminalSessionStatus.disconnected;
      error = null;
    } else {
      status = TerminalSessionStatus.failed;
      error = TerminalCleanupFailure(_failedCleanup.values.first);
    }
    notifyListeners();
  }

  Future<void> _retryCleanup(List<TerminalConnection> connections) async {
    for (final connection in connections) {
      if (_failedCleanup.containsKey(connection)) {
        await _release(connection, null);
      }
    }
  }

  Future<void> _release(
    TerminalConnection? connection,
    StreamSubscription<String>? subscription,
  ) async {
    // Register shutdown before cancellation: a stream's onCancel may itself
    // wait for native cleanup, while a replacement viewport is opening.
    final closing = connection == null
        ? Future<void>.value()
        : Future<void>.sync(connection.close).then<void>(
            (_) => _failedCleanup.remove(connection),
            onError: (Object failure, StackTrace _) {
              _failedCleanup[connection] = failure;
            },
          );
    try {
      await subscription?.cancel();
    } catch (_) {
      // Still close the process if its output stream already failed.
    }
    await closing;
    if (!_disposed && _failedCleanup.isNotEmpty) {
      if (_connection == null &&
          (status == TerminalSessionStatus.disconnected ||
              status == TerminalSessionStatus.exited)) {
        status = TerminalSessionStatus.failed;
        error = TerminalCleanupFailure(_failedCleanup.values.first);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    terminal.onOutput = null;
    terminal.onResize = null;
    final connection = _connection;
    final subscription = _subscription;
    final pendingCleanup = _failedCleanup.keys.toList();
    unawaited(() async {
      await _release(connection, subscription);
      await _retryCleanup(pendingCleanup);
    }());
    _connection = null;
    _subscription = null;
    terminal.dispose();
    super.dispose();
  }
}
