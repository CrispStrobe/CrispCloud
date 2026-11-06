// lib/services/ssh_terminal_service.dart
//
// Embedded SSH terminal service for SFTP connections.
//
// Supports password-based and key-based authentication.
// Manages a pool of up to [maxSessions] concurrent sessions.
// Sessions idle longer than [idleTimeout] are automatically disconnected.
//
// Native platforms use TCP. Browsers require an explicit secure WebSocket
// gateway that already forwards to the chosen SSH host.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart'
    show SshKnownHosts, HostKeyPrompt, openVerifiedSsh;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'log_service.dart';
import 'secure_storage_service.dart';
import 'ssh_gateway.dart';
import 'terminal_output.dart';
import 'terminal_mount_failure.dart';

export 'ssh_gateway.dart' show sshGatewayValidationMessage;

/// Connection boundary used to exercise the terminal without a live SSH server.
typedef SshClientConnector = Future<SSHClient> Function(
  String host,
  int port, {
  required String username,
  String? password,
  List<SSHIdentity>? identities,
  Uri? gateway,
});

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
  bool operator ==(Object other) => other is SshSession && other.id == id;

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
  SshSession session;
  final SSHClient client;
  SSHSession? shellSession;
  TerminalOutput? shellOutput;
  int shellGeneration = 0;

  _SessionState({required this.session, required this.client});
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
  HostKeyPrompt? confirmHostKey;
  late final SshKnownHosts _knownHosts = SshKnownHosts(
    read: () => _secure.read('ssh_known_hosts_v1'),
    write: (value) => _secure.write('ssh_known_hosts_v1', value),
  );
  final SecureStorage _secure;
  final SshClientConnector? _clientConnector;

  /// Internal session registry.
  final Map<String, _SessionState> _sessions = {};

  /// Periodic idle-check timer.
  Timer? _idleTimer;
  bool _disposed = false;
  int _pendingConnections = 0;
  int _connectionGeneration = 0;
  int _nextId = 0;

  SshTerminalService({
    this.idleTimeout = defaultIdleTimeout,
    SecureStorage? secureStorage,
    this.confirmHostKey,
    @visibleForTesting this._clientConnector,
  }) : _secure = secureStorage ?? PlatformSecureStorage();

  // -------------------------------------------------------------------------
  // Platform guard
  // -------------------------------------------------------------------------

  /// Whether this platform has an SSH transport. Web needs an explicit gateway.
  static bool get isSupported {
    if (kIsWeb) return true;
    try {
      // dartssh2 works on mobile too; SSH is the only terminal option on
      // sandboxed iOS/macOS builds.
      return Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  void _checkPlatform(Uri? gateway) {
    if (!isSupported) {
      throw TerminalMountUnsupportedError(
        TerminalMountCode.sshUnsupported,
        'SSH terminal is not supported on this platform.',
      );
    }
    final validation = sshGatewayValidationMessage(gateway, required: kIsWeb);
    if (validation != null) throw ArgumentError(validation);
  }

  // -------------------------------------------------------------------------
  // Connect (password)
  // -------------------------------------------------------------------------

  /// Establishes an SSH connection using password authentication.
  ///
  /// [gateway] is required on web and optional on native platforms. It is never
  /// used as the SSH host-key identity; [host] and [port] still identify that.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password, {
    Uri? gateway,
  }) => _connect(host, port, username, password: password, gateway: gateway);

  // -------------------------------------------------------------------------
  // Connect (private key)
  // -------------------------------------------------------------------------

  /// Establishes an SSH connection using public-key authentication.
  ///
  /// [privateKey] should be a PEM-encoded private key string.
  ///
  /// [gateway] is required on web and optional on native platforms.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connectWithKey(
    String host,
    int port,
    String username,
    String privateKey, {
    Uri? gateway,
  }) async {
    final keyPair = _parseKeyPair(privateKey);
    if (keyPair == null) {
      throw const TerminalMountFormatException(
        TerminalMountCode.sshInvalidKey,
        'Invalid SSH private key',
      );
    }
    return _connect(
      host,
      port,
      username,
      identities: [keyPair],
      gateway: gateway,
    );
  }

  Future<SshSession> _connect(
    String host,
    int port,
    String username, {
    String? password,
    List<SSHIdentity>? identities,
    Uri? gateway,
  }) async {
    _checkPlatform(gateway);
    if (_disposed) throw StateError('SSH terminal service is disposed');
    _checkPoolCapacity();
    _pendingConnections++;
    final generation = _connectionGeneration;
    SSHClient? client;
    try {
      client = await (_clientConnector ?? _openClient)(
        host,
        port,
        username: username,
        password: password,
        identities: identities,
        gateway: gateway,
      );
      await client.authenticated;
      // A slow connection must not resurrect a session after sign-out/dispose.
      if (_disposed || generation != _connectionGeneration) {
        throw StateError('SSH connection was cancelled');
      }
      if (client.isClosed) throw StateError('SSH connection closed');

      final now = DateTime.now();
      final session = SshSession(
        id: _generateId(),
        host: host,
        port: port,
        username: username,
        connected: true,
        startedAt: now,
        lastActivityAt: now,
      );
      final state = _SessionState(session: session, client: client);
      _sessions[session.id] = state;
      _idleTimer ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) => _sweepIdle(),
      );
      unawaited(
        client.done.then<void>(
          (_) => _clientClosed(session.id, state),
          onError: (Object error, StackTrace stack) {
            _log.error('SSH connection closed', error);
            _clientClosed(session.id, state);
          },
        ),
      );
      _log.info('Session ${session.id} established to $host:$port');
      return session;
    } catch (error) {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {}
      }
      _log.error('SSH connect failed', error);
      // Keep cancellation as a StateError for the session lifecycle. Transport
      // failures carry stable codes so the UI can translate them at display time.
      if (_disposed || generation != _connectionGeneration) rethrow;
      throw TerminalMountException(
        identities == null
            ? TerminalMountCode.sshConnection
            : TerminalMountCode.sshKeyConnection,
        'SSH connection failed: $error',
        {'error': error},
      );
    } finally {
      _pendingConnections--;
    }
  }

  Future<SSHClient> _openClient(
    String host,
    int port, {
    required String username,
    String? password,
    List<SSHIdentity>? identities,
    Uri? gateway,
  }) async {
    final socket = gateway == null
        ? await SSHSocket.connect(
            host,
            port,
            timeout: const Duration(seconds: 15),
          )
        : await openSshGateway(gateway);
    return openVerifiedSsh(
      socket,
      username: username,
      password: password,
      identities: identities,
      verify: (_, fingerprint) => _knownHosts.verify(
        SshKnownHosts.endpoint(host, port),
        utf8.decode(fingerprint),
        prompt: confirmHostKey,
      ),
    );
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
    _connectionGeneration++;
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
    if (client.isClosed) {
      throw TerminalMountStateError(
        TerminalMountCode.sshDisconnected,
        'Session $sessionId is not connected',
        {'session': sessionId},
      );
    }

    _touch(sessionId);
    _log.info('execute($sessionId)');

    try {
      final result = await client.run(command);
      final output = utf8.decode(result, allowMalformed: true);
      return output;
    } catch (e) {
      _log.error('execute error', e);
      throw TerminalMountException(
        TerminalMountCode.sshCommand,
        'Command execution failed: $e',
        {'error': e},
      );
    }
  }

  // -------------------------------------------------------------------------
  // Interactive shell
  // -------------------------------------------------------------------------

  /// Starts an interactive PTY shell on [sessionId].
  ///
  /// Returns a single-subscription stream of decoded terminal output, including
  /// ANSI sequences. The initial prompt is buffered until a listener attaches.
  Future<Stream<String>> startShell(
    String sessionId, {
    int width = 80,
    int height = 24,
  }) async {
    _validateDimensions(width, height);
    final state = _requireSession(sessionId);
    final client = state.client;
    if (client.isClosed) {
      throw TerminalMountStateError(
        TerminalMountCode.sshDisconnected,
        'Session $sessionId is not connected',
        {'session': sessionId},
      );
    }

    _touch(sessionId);
    _log.info('startShell($sessionId)');

    // Invalidates callbacks from the previous shell before closing its stream.
    final generation = ++state.shellGeneration;
    final previousOutput = state.shellOutput;
    final previousShell = state.shellSession;
    state.shellOutput = null;
    state.shellSession = null;
    previousShell?.close();
    await previousOutput?.dispose();
    if (!_isCurrentShell(sessionId, state, generation)) {
      throw StateError('SSH shell start was cancelled');
    }

    SSHSession shell;
    try {
      shell = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: width, height: height),
      );
    } catch (_) {
      if (_isCurrentShell(sessionId, state, generation)) {
        await disconnect(sessionId);
      }
      rethrow;
    }
    if (!_isCurrentShell(sessionId, state, generation)) {
      shell.close();
      throw StateError('SSH shell start was cancelled');
    }
    state.shellSession = shell;
    final output = TerminalOutput(
      [shell.stdout, shell.stderr],
      onActivity: () => _touch(sessionId),
      onDone: () {
        if (_isCurrentShell(sessionId, state, generation)) {
          // Both streams have drained. SSHSession.done alone can complete while
          // final output is still pending in either channel.
          unawaited(disconnect(sessionId));
        }
      },
      onCancel: () async {
        if (_isCurrentShell(sessionId, state, generation)) {
          await disconnect(sessionId);
        }
      },
    );
    state.shellOutput = output;
    return output.stream;
  }

  /// Sends [input] to the active interactive shell of [sessionId].
  Future<void> writeToShell(String sessionId, String input) async {
    final state = _requireSession(sessionId);
    final shell = state.shellSession;
    if (shell == null) {
      throw TerminalMountStateError(
        TerminalMountCode.sshNoShell,
        'No active shell for session $sessionId',
        {'session': sessionId},
      );
    }

    _touch(sessionId);
    shell.stdin.add(Uint8List.fromList(utf8.encode(input)));
  }

  /// Notifies the remote host of a terminal resize to [width] × [height].
  ///
  /// Throws [ArgumentError] when dimensions are not positive.
  Future<void> resizeTerminal(String sessionId, int width, int height) async {
    _validateDimensions(width, height);

    final state = _requireSession(sessionId);
    final shell = state.shellSession;
    if (shell == null) {
      throw TerminalMountStateError(
        TerminalMountCode.sshNoShell,
        'No active shell for session $sessionId',
        {'session': sessionId},
      );
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
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    await disconnectAll();
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  void _checkPoolCapacity() {
    if (_sessions.length + _pendingConnections >= maxSessions) {
      throw TerminalMountStateError(
        TerminalMountCode.sshPoolFull,
        'SSH session pool is full (max $maxSessions concurrent sessions).',
        {'max': maxSessions},
      );
    }
  }

  _SessionState _requireSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw TerminalMountArgumentError(
        TerminalMountCode.sshUnknownSession,
        'Unknown session id: $sessionId',
        {'session': sessionId},
      );
    }
    return state;
  }

  void _touch(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) return;
    state.session = state.session.copyWith(lastActivityAt: DateTime.now());
  }

  bool _isCurrentShell(String id, _SessionState state, int generation) =>
      identical(_sessions[id], state) && state.shellGeneration == generation;

  void _clientClosed(String id, _SessionState state) {
    if (!identical(_sessions[id], state)) return;
    state.session = state.session.copyWith(connected: false);
    // An attached shell drains its stdout/stderr before removing the session.
    // Connections used only for execute have no terminal streams to drain.
    if (state.shellOutput == null) unawaited(disconnect(id));
  }

  static void _validateDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Terminal dimensions must be positive (got ${width}x$height)',
      );
    }
  }

  Future<void> _closeState(_SessionState state) async {
    state.shellGeneration++;
    try {
      state.shellSession?.close();
    } catch (_) {}
    try {
      await state.shellOutput?.dispose();
    } catch (_) {}
    try {
      await state.client.close();
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
      final pairs = SSHKeyPair.fromPem(pemKey);
      return pairs.isNotEmpty ? pairs.first : null;
    } catch (e) {
      _log.error('Failed to parse private key', e);
      return null;
    }
  }

  String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (_nextId++).toRadixString(36);
}
