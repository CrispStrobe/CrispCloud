// lib/services/ssh_terminal_service.dart
//
// Embedded SSH terminal service for SFTP connections.
//
// Supports password-based and key-based authentication.
// Manages a pool of up to [maxSessions] concurrent sessions.
// Sessions idle longer than [idleTimeout] are automatically disconnected.
//
// Desktop-only: attempting to use this service on web or mobile platforms
// throws [UnsupportedError].

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Represents an active (or recently closed) SSH session.
class SshSession {
  final String id;
  final String host;
  final int port;
  final String username;
  final bool connected;
  final DateTime startedAt;
  final DateTime lastActivityAt;

  const SshSession({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    required this.connected,
    required this.startedAt,
    required this.lastActivityAt,
  });

  SshSession copyWith({
    String? id,
    String? host,
    int? port,
    String? username,
    bool? connected,
    DateTime? startedAt,
    DateTime? lastActivityAt,
  }) {
    return SshSession(
      id: id ?? this.id,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      connected: connected ?? this.connected,
      startedAt: startedAt ?? this.startedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        'username': username,
        'connected': connected,
        'startedAt': startedAt.toIso8601String(),
        'lastActivityAt': lastActivityAt.toIso8601String(),
      };

  factory SshSession.fromJson(Map<String, dynamic> json) => SshSession(
        id: json['id'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        connected: json['connected'] as bool,
        startedAt: DateTime.parse(json['startedAt'] as String),
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is SshSession && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SshSession(id: $id, host: $host:$port, user: $username, connected: $connected)';
}

// ---------------------------------------------------------------------------
// Internal per-session state
// ---------------------------------------------------------------------------

class _SessionState {
  final SshSession session;
  SSHClient? client;
  SSHSession? shellSession;
  StreamController<String>? shellOutput;

  _SessionState({required this.session, this.client});
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Embedded SSH terminal service.
///
/// Usage:
/// ```dart
/// final service = SshTerminalService();
/// final session = await service.connect('example.com', 22, 'alice', 'secret');
/// final output  = await service.execute(session.id, 'uname -a');
/// await service.disconnect(session.id);
/// ```
class SshTerminalService {
  static const _log = Log('SshTerminalService');

  /// Maximum number of concurrent SSH sessions.
  static const int maxSessions = 5;

  /// Default idle timeout after which sessions are automatically closed.
  static const Duration defaultIdleTimeout = Duration(minutes: 30);

  final Duration idleTimeout;

  /// Internal session registry.
  final Map<String, _SessionState> _sessions = {};

  /// Periodic idle-check timer.
  Timer? _idleTimer;

  SshTerminalService({this.idleTimeout = defaultIdleTimeout}) {
    _idleTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sweepIdle());
  }

  // -------------------------------------------------------------------------
  // Platform guard
  // -------------------------------------------------------------------------

  /// Returns true when SSH is supported on the current platform (desktop only).
  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  void _checkPlatform() {
    if (!isSupported) {
      throw UnsupportedError(
        'SSH terminal is not supported on web or mobile platforms.',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Connect (password)
  // -------------------------------------------------------------------------

  /// Establishes an SSH connection using password authentication.
  ///
  /// Throws [UnsupportedError] on web/mobile.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password,
  ) async {
    _checkPlatform();
    _checkPoolCapacity();

    final id = _generateId();
    final now = DateTime.now();

    _log.info('Connecting to $host:$port as $username (id=$id)');

    SSHClient client;
    try {
      final socket = await SSHSocket.connect(host, port);
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      await client.authenticated;
    } catch (e) {
      _log.error('SSH connect failed', e);
      throw Exception('SSH connection failed: $e');
    }

    final session = SshSession(
      id: id,
      host: host,
      port: port,
      username: username,
      connected: true,
      startedAt: now,
      lastActivityAt: now,
    );

    _sessions[id] = _SessionState(session: session, client: client);
    _log.info('Session $id established');
    return session;
  }

  // -------------------------------------------------------------------------
  // Connect (private key)
  // -------------------------------------------------------------------------

  /// Establishes an SSH connection using public-key authentication.
  ///
  /// [privateKey] should be a PEM-encoded private key string.
  ///
  /// Throws [UnsupportedError] on web/mobile.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connectWithKey(
    String host,
    int port,
    String username,
    String privateKey,
  ) async {
    _checkPlatform();
    _checkPoolCapacity();

    final id = _generateId();
    final now = DateTime.now();

    _log.info('Connecting to $host:$port as $username via key (id=$id)');

    SSHClient client;
    try {
      final keyPair = _parseKeyPair(privateKey);
      final socket = await SSHSocket.connect(host, port);
      client = SSHClient(
        socket,
        username: username,
        identities: keyPair != null ? [keyPair] : [],
      );
      await client.authenticated;
    } catch (e) {
      _log.error('SSH key-connect failed', e);
      throw Exception('SSH key-based connection failed: $e');
    }

    final session = SshSession(
      id: id,
      host: host,
      port: port,
      username: username,
      connected: true,
      startedAt: now,
      lastActivityAt: now,
    );

    _sessions[id] = _SessionState(session: session, client: client);
    _log.info('Session $id established via key');
    return session;
  }

  // -------------------------------------------------------------------------
  // Disconnect
  // -------------------------------------------------------------------------

  /// Closes the SSH connection for [sessionId] and removes it from the pool.
  Future<void> disconnect(String sessionId) async {
    final state = _sessions.remove(sessionId);
    if (state == null) return;

    _log.info('Disconnecting session $sessionId');
    await _closeState(state);
  }

  /// Closes all active sessions.
  Future<void> disconnectAll() async {
    final ids = List<String>.from(_sessions.keys);
    for (final id in ids) {
      await disconnect(id);
    }
  }

  // -------------------------------------------------------------------------
  // Execute
  // -------------------------------------------------------------------------

  /// Runs [command] on the remote host and returns the combined stdout/stderr.
  ///
  /// Throws [ArgumentError] when [sessionId] is not found.
  Future<String> execute(String sessionId, String command) async {
    final state = _requireSession(sessionId);
    final client = state.client;
    if (client == null || client.isClosed) {
      throw StateError('Session $sessionId is not connected');
    }

    _touch(sessionId);
    _log.info('execute($sessionId): $command');

    try {
      final result = await client.run(command);
      final output = String.fromCharCodes(result);
      return output;
    } catch (e) {
      _log.error('execute error', e);
      throw Exception('Command execution failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Interactive shell
  // -------------------------------------------------------------------------

  /// Starts an interactive PTY shell on [sessionId].
  ///
  /// Returns a [Stream<String>] that emits terminal output lines.
  Future<Stream<String>> startShell(String sessionId) async {
    final state = _requireSession(sessionId);
    final client = state.client;
    if (client == null || client.isClosed) {
      throw StateError('Session $sessionId is not connected');
    }

    _touch(sessionId);
    _log.info('startShell($sessionId)');

    // Close existing shell if any.
    if (state.shellSession != null) {
      await state.shellSession!.close();
      await state.shellOutput?.close();
    }

    final shell = await client.shell(
      pty: const SSHPtyConfig(
        type: 'xterm-256color',
        width: 80,
        height: 24,
      ),
    );

    state.shellSession = shell;

    final controller = StreamController<String>.broadcast();
    state.shellOutput = controller;

    // Pipe stdout.
    shell.stdout
        .transform(const _BytesToStringTransformer())
        .listen(
          (data) {
            _touch(sessionId);
            controller.add(data);
          },
          onError: controller.addError,
          onDone: controller.close,
          cancelOnError: false,
        );

    // Pipe stderr (if distinct).
    shell.stderr
        .transform(const _BytesToStringTransformer())
        .listen(
          (data) {
            _touch(sessionId);
            controller.add(data);
          },
          onError: (e) {},
          cancelOnError: false,
        );

    return controller.stream;
  }

  /// Sends [input] to the active interactive shell of [sessionId].
  Future<void> writeToShell(String sessionId, String input) async {
    final state = _requireSession(sessionId);
    final shell = state.shellSession;
    if (shell == null) {
      throw StateError('No active shell for session $sessionId');
    }

    _touch(sessionId);
    shell.stdin.add(input.codeUnits);
  }

  /// Notifies the remote host of a terminal resize to [width] × [height].
  ///
  /// Throws [ArgumentError] when dimensions are not positive.
  Future<void> resizeTerminal(
    String sessionId,
    int width,
    int height,
  ) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Terminal dimensions must be positive (got ${width}x$height)',
      );
    }

    final state = _requireSession(sessionId);
    final shell = state.shellSession;
    if (shell == null) {
      throw StateError('No active shell for session $sessionId');
    }

    _touch(sessionId);
    _log.info('resizeTerminal($sessionId): ${width}x$height');
    shell.resizeTerminal(width, height);
  }

  // -------------------------------------------------------------------------
  // Query
  // -------------------------------------------------------------------------

  /// Returns a snapshot of all currently active sessions.
  List<SshSession> getActiveSessions() {
    return _sessions.values
        .map((s) => s.session)
        .where((s) => s.connected)
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Releases all resources. Call when the service is no longer needed.
  Future<void> dispose() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await disconnectAll();
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  void _checkPoolCapacity() {
    if (_sessions.length >= maxSessions) {
      throw StateError(
        'SSH session pool is full (max $maxSessions concurrent sessions).',
      );
    }
  }

  _SessionState _requireSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw ArgumentError('Unknown session id: $sessionId');
    }
    return state;
  }

  void _touch(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) return;
    _sessions[sessionId] = _SessionState(
      session: state.session.copyWith(lastActivityAt: DateTime.now()),
      client: state.client,
    )
      ..shellSession = state.shellSession
      ..shellOutput = state.shellOutput;
  }

  Future<void> _closeState(_SessionState state) async {
    try {
      await state.shellSession?.close();
    } catch (_) {}
    try {
      await state.shellOutput?.close();
    } catch (_) {}
    try {
      state.client?.close();
    } catch (_) {}
  }

  void _sweepIdle() {
    final cutoff = DateTime.now().subtract(idleTimeout);
    final stale = _sessions.entries
        .where((e) => e.value.session.lastActivityAt.isBefore(cutoff))
        .map((e) => e.key)
        .toList();

    for (final id in stale) {
      _log.info('Auto-disconnecting idle session $id');
      disconnect(id);
    }
  }

  /// Parses a PEM private key string into an [SSHKeyPair].
  /// Returns null when parsing fails (falls back to no identity).
  SSHKeyPair? _parseKeyPair(String pemKey) {
    try {
      return SSHKeyPair.fromPem(pemKey);
    } catch (e) {
      _log.error('Failed to parse private key', e);
      return null;
    }
  }

  String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (_sessions.length).toRadixString(36);
}

// ---------------------------------------------------------------------------
// Utility transformer
// ---------------------------------------------------------------------------

class _BytesToStringTransformer
    implements StreamTransformer<Uint8List, String> {
  const _BytesToStringTransformer();

  @override
  Stream<String> bind(Stream<Uint8List> stream) =>
      stream.map((bytes) => String.fromCharCodes(bytes));

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom(this);
}
