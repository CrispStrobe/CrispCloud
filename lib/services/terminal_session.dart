import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart';

import '../models/terminal_trigger.dart';
import 'ssh_port_forwarding.dart';
import 'terminal_connection.dart';
import 'terminal_forwarding_connection.dart';
import 'terminal_shell_integration.dart';
import 'terminal_triggers.dart';
import 'terminal_user_input.dart';

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
    _triggerEngine = TerminalTriggerEngine(onMatch: _onTrigger);
    terminal = _createTerminal(TerminalSessionKind.local);
    _bindTerminal();
  }

  static Terminal _createTerminal(TerminalSessionKind kind) =>
      InputAwareTerminal(
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
    shellIntegration = TerminalShellIntegration(terminal)
      ..addListener(_shellChanged);
  }

  late Terminal terminal;
  late TerminalShellIntegration shellIntegration;
  late final TerminalTriggerEngine _triggerEngine;
  bool _hasOutputTriggers = false;
  int triggerNotificationSerial = 0;
  TerminalTriggerMatch? triggerNotification;

  /// Configuration follows the workspace, while cooldown and one-shot state
  /// belong to this connection. Rebuilds must not reset those runtime limits.
  void updateTriggers(List<TerminalTrigger> triggers) {
    if (_disposed) return;
    _triggerEngine.updateTriggers(triggers);
    _hasOutputTriggers = triggers.any((trigger) => trigger.enabled);
  }

  void _onTrigger(TerminalTriggerMatch match) {
    if (_disposed || terminal.isUsingAltBuffer) return;
    switch (match.trigger.action) {
      case TerminalTriggerAction.mark:
        shellIntegration.addMark();
      case TerminalTriggerAction.notify:
        triggerNotification = match;
        triggerNotificationSerial++;
        notifyListeners();
    }
  }

  void _readOutput(String data) {
    if (!_hasOutputTriggers) {
      final alternate = terminal.isUsingAltBuffer;
      terminal.write(data);
      _triggerEngine.addOutput(data, alternateScreen: alternate);
      return;
    }
    // Emit each completed line while the emulator's cursor still belongs to
    // that line. Multiple matches in one transport chunk get distinct marks,
    // and fragmented output has the same result as a single large write.
    var start = 0;
    while (true) {
      final newline = data.indexOf('\n', start);
      final end = newline < 0 ? data.length : newline;
      if (end > start) {
        final fragment = data.substring(start, end);
        final alternate = terminal.isUsingAltBuffer;
        terminal.write(fragment);
        _triggerEngine.addOutput(fragment, alternateScreen: alternate);
      }
      if (newline < 0) break;
      _triggerEngine.addOutput(
        '\n',
        alternateScreen: terminal.isUsingAltBuffer,
      );
      terminal.write('\n');
      start = newline + 1;
    }
  }

  SshPortForwarding? get portForwarding {
    final connection = _connection;
    return isConnected && connection is TerminalForwardingConnection
        ? (connection as TerminalForwardingConnection).portForwarding
        : null;
  }

  void _shellChanged() {
    if (!_disposed) notifyListeners();
  }

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
  final _pendingCleanup = <TerminalConnection, Future<void>>{};
  int _pendingOpeners = 0;
  int _inputReplayDepth = 0;
  bool Function()? _inputLease;

  /// Replaced for each attempt; broadcast membership captures this identity.
  Object get connectionIdentity => terminal;
  void Function(TerminalUserInput)? onUserInput;

  void sendUserInput(TerminalUserInput input, {bool Function()? isCurrent}) {
    if (!isConnected || _disposed || (isCurrent != null && !isCurrent())) {
      return;
    }
    final previous = _inputLease;
    _inputLease = isCurrent;
    _inputReplayDepth++;
    try {
      input.applyTo(terminal);
    } finally {
      _inputReplayDepth--;
      _inputLease = previous;
    }
  }

  bool get isConnected =>
      !_disposed && status == TerminalSessionStatus.connected;
  bool get isSandbox => kind == TerminalSessionKind.sandbox;
  bool get isConnecting =>
      !_disposed && status == TerminalSessionStatus.connecting;
  bool get canDisconnect =>
      !_disposed &&
      (_connection != null ||
          _failedCleanup.isNotEmpty ||
          _pendingCleanup.isNotEmpty ||
          _pendingOpeners != 0 ||
          isConnecting ||
          isConnected ||
          status == TerminalSessionStatus.waitingForExit);

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
    _triggerEngine.reset();
    triggerNotification = null;
    triggerNotificationSerial = 0;
    status = TerminalSessionStatus.connecting;
    final previousTerminal = terminal;
    shellIntegration.dispose();
    terminal = _createTerminal(kind)..resize(columns, rows);
    _bindTerminal();
    previousTerminal.onOutput = null;
    previousTerminal.onResize = null;
    previousTerminal.dispose();
    notifyListeners();
    await _release(previous, subscription);
    await Future.wait(_pendingCleanup.values.toList());
    if (!_current(generation)) return;

    TerminalConnection? connection;
    var opening = false;
    try {
      await _retryCleanup(pendingCleanup);
      if (!_current(generation)) return;
      if (_failedCleanup.isNotEmpty) {
        throw TerminalCleanupFailure(_failedCleanup.values.first);
      }
      opening = true;
      _pendingOpeners++;
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
          if (_current(generation)) _readOutput(data);
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
    } finally {
      if (opening) {
        _pendingOpeners--;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void _write(String data) {
    final connection = _connection;
    final generation = _generation;
    final lease = _inputLease;
    if (!isConnected || connection == null || data.isEmpty) return;
    _writes = _writes
        .then((_) async {
          if (_current(generation) &&
              isConnected &&
              (lease == null || lease())) {
            await connection.write(data);
          }
        })
        .catchError((Object error) => _fail(generation, error));
    if (_inputReplayDepth == 0 && terminal is InputAwareTerminal) {
      final input = (terminal as InputAwareTerminal).takeUserInput();
      if (input != null) onUserInput?.call(input);
    }
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
    _triggerEngine.finish();
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
    unawaited(_release(connection, subscription));
    notifyListeners();
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
    final releasing = _release(connection, subscription);
    notifyListeners();
    await releasing;
    await Future.wait(_pendingCleanup.values.toList());
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
        : _closeConnection(connection);
    try {
      await subscription?.cancel();
    } catch (_) {
      // Still close the process if its output stream already failed.
    }
    await closing;
    if (!_disposed) {
      if (_failedCleanup.isNotEmpty &&
          _connection == null &&
          (status == TerminalSessionStatus.disconnected ||
              status == TerminalSessionStatus.exited)) {
        status = TerminalSessionStatus.failed;
        error = TerminalCleanupFailure(_failedCleanup.values.first);
      }
      notifyListeners();
    }
  }

  Future<void> _closeConnection(TerminalConnection connection) {
    final existing = _pendingCleanup[connection];
    if (existing != null) return existing;
    final completion = Completer<void>();
    _pendingCleanup[connection] = completion.future;
    unawaited(
      Future<void>.sync(connection.close)
          .then<void>(
            (_) => _failedCleanup.remove(connection),
            onError: (Object failure, StackTrace _) {
              _failedCleanup[connection] = failure;
            },
          )
          .whenComplete(() {
            _pendingCleanup.remove(connection);
            completion.complete();
          }),
    );
    return completion.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    shellIntegration.dispose();
    onUserInput = null;
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
