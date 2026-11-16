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
  TerminalSession({int maxLines = 10000, this.maximumPendingInputCodeUnits})
    : _maxLines = maxLines {
    if (maxLines < 1 || maxLines > 10000) {
      throw ArgumentError.value(
        maxLines,
        'maxLines',
        'Invalid scrollback limit',
      );
    }
    if (maximumPendingInputCodeUnits != null &&
        maximumPendingInputCodeUnits! < 1) {
      throw ArgumentError('Pending terminal input limit must be positive');
    }
    _triggerEngine = TerminalTriggerEngine(onMatch: _onTrigger);
    terminal = _createTerminal(TerminalSessionKind.local, _maxLines);
    _bindTerminal();
  }

  final int _maxLines;
  final int? maximumPendingInputCodeUnits;

  static Terminal _createTerminal(TerminalSessionKind kind, int maxLines) =>
      InputAwareTerminal(
        maxLines: maxLines,
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
  TerminalWorkspaceConnection? _workspaceConnection;

  /// A snapshot capability: a menu opened for one connection cannot silently
  /// acquire a shell on its replacement. After acquisition, the new shell's
  /// lease belongs to its own session and survives closure of this source.
  TerminalConnectionOpening? get siblingConnectionOpening {
    final connection = _connection;
    if (!isConnected ||
        connection is! TerminalConnectionSharing ||
        !(connection as TerminalConnectionSharing).canOpenSibling) {
      return null;
    }
    final sharing = connection as TerminalConnectionSharing;
    final generation = _generation;
    final cancellation = TerminalConnectionCancellation();
    return TerminalConnectionOpening((columns, rows) async {
      if (cancellation.isCancelled ||
          !_current(generation) ||
          !isConnected ||
          !identical(_connection, connection) ||
          !sharing.canOpenSibling) {
        throw StateError('The source SSH connection is no longer available.');
      }
      return sharing.openSibling(columns, rows, cancellation: cancellation);
    }, cancellation);
  }

  /// Starts an explicitly shared shell with ownership of its pending lease.
  Future<void> connectOpening(
    TerminalConnectionOpening opening, {
    required TerminalSessionKind kind,
    String? label,
  }) => connect(
    opening.claim(),
    kind: kind,
    label: label,
    openingCleanup: opening,
  );

  int get sharedConnectionSessionCount {
    final connection = _connection;
    return isConnected && connection is TerminalConnectionSharing
        ? (connection as TerminalConnectionSharing).sharedSessionCount
        : 0;
  }

  /// A workspace survives viewport removal and transport disconnect. The
  /// session releases its buffers only when replaced or explicitly disposed.
  TerminalWorkspaceConnection? get workspaceConnection => _workspaceConnection;

  void _replaceWorkspace(TerminalWorkspaceConnection? connection) {
    if (identical(_workspaceConnection, connection)) return;
    final previous = _workspaceConnection;
    _workspaceConnection = connection;
    previous?.disposeWorkspace();
  }

  StreamSubscription<String>? _subscription;
  Future<void> _writes = Future<void>.value();
  int _pendingInputCodeUnits = 0;
  Future<void> _resizes = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  final _failedCleanup = <TerminalCloseable, Object>{};
  final _pendingCleanup = <TerminalCloseable, Future<void>>{};
  final _pendingOpenings = <TerminalCloseable>{};
  int _pendingOpeners = 0;
  int _inputReplayDepth = 0;
  bool Function()? _inputLease;

  /// Replaced for each attempt; broadcast membership captures this identity.
  Object get connectionIdentity => terminal;
  void Function(TerminalUserInput)? onUserInput;

  void sendUserInput(TerminalUserInput input, {bool Function()? isCurrent}) {
    if (!acceptsDirectInput ||
        _disposed ||
        (isCurrent != null && !isCurrent())) {
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
  bool get acceptsDirectInput {
    final connection = _connection;
    return isConnected &&
        (connection is! TerminalWorkspaceConnection ||
            (connection as TerminalWorkspaceConnection).acceptsDirectInput);
  }

  bool get isSandbox => kind == TerminalSessionKind.sandbox;
  bool get isConnecting =>
      !_disposed && status == TerminalSessionStatus.connecting;
  bool get canDisconnect =>
      !_disposed &&
      (_connection != null ||
          _failedCleanup.isNotEmpty ||
          _pendingCleanup.isNotEmpty ||
          _pendingOpenings.isNotEmpty ||
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
    TerminalCloseable? openingCleanup,
  }) async {
    if (_disposed) {
      if (openingCleanup != null) await _closeConnection(openingCleanup);
      return;
    }
    if (openingCleanup != null) _pendingOpenings.add(openingCleanup);
    try {
      await _connect(
        open,
        kind: kind,
        label: label,
        openingCleanup: openingCleanup,
      );
    } finally {
      // A destination may cancel before the adapter registers the child-ID
      // release callback. Revisit the opening when it settles so a late failed
      // release remains tracked and retryable even after a generation change.
      // Successful adapters transfer ownership and unregister before returning.
      if (openingCleanup != null) await _release(openingCleanup, null);
      final removed = _pendingOpenings.remove(openingCleanup);
      if (removed && !_disposed) notifyListeners();
    }
  }

  Future<void> _connect(
    TerminalConnectionFactory open, {
    required TerminalSessionKind kind,
    String? label,
    TerminalCloseable? openingCleanup,
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    // Replacing a pending opener revokes its reserved lease immediately, even
    // when the remote server has not answered its channel-open request.
    for (final pending in _pendingOpenings.toList()) {
      if (!identical(pending, openingCleanup)) {
        unawaited(_closeConnection(pending));
      }
    }
    final previous = _connection;
    final subscription = _subscription;
    final pendingCleanup = _failedCleanup.keys.toList();
    _connection = null;
    _replaceWorkspace(null);
    _subscription = null;
    _writes = Future<void>.value();
    _pendingInputCodeUnits = 0;
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
    terminal = _createTerminal(kind, _maxLines)..resize(columns, rows);
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
      _replaceWorkspace(
        connection is TerminalWorkspaceConnection
            ? connection as TerminalWorkspaceConnection
            : null,
      );
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
    if (!acceptsDirectInput || connection == null || data.isEmpty) return;
    final pendingLimit = maximumPendingInputCodeUnits;
    if (pendingLimit != null &&
        _pendingInputCodeUnits + data.length > pendingLimit) {
      _fail(generation, StateError('Pending terminal input exceeds the limit'));
      return;
    }
    _pendingInputCodeUnits += data.length;
    _writes = _writes
        .then((_) async {
          try {
            if (_current(generation) &&
                acceptsDirectInput &&
                (lease == null || lease())) {
              await connection.write(data);
            }
          } finally {
            if (_current(generation)) _pendingInputCodeUnits -= data.length;
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
    for (final pending in _pendingOpenings.toList()) {
      unawaited(_closeConnection(pending));
    }
    _pendingInputCodeUnits = 0;
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
    for (final pending in _pendingOpenings.toList()) {
      unawaited(_closeConnection(pending));
    }
    _pendingInputCodeUnits = 0;
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

  Future<void> _retryCleanup(List<TerminalCloseable> connections) async {
    for (final connection in connections) {
      if (_failedCleanup.containsKey(connection)) {
        await _release(connection, null);
      }
    }
  }

  Future<void> _release(
    TerminalCloseable? connection,
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
    // A late opener or a replaced workspace was never retained by the current
    // session. Disconnection of the current workspace keeps its screen intact.
    if (connection is TerminalWorkspaceConnection &&
        !identical(connection, _workspaceConnection)) {
      (connection as TerminalWorkspaceConnection).disposeWorkspace();
    }
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

  Future<void> _closeConnection(TerminalCloseable connection) {
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
    for (final pending in _pendingOpenings.toList()) {
      unawaited(_closeConnection(pending));
    }
    _pendingInputCodeUnits = 0;
    shellIntegration.dispose();
    onUserInput = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    final connection = _connection;
    final subscription = _subscription;
    final pendingCleanup = _failedCleanup.keys.toList();
    _replaceWorkspace(null);
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
