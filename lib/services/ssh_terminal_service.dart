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

import '../models/screen_session_options.dart';
import '../models/ssh_jump_host.dart';
import '../models/ssh_multiplexer_session.dart';
import '../models/tmux_session_options.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'ssh_agent.dart';
import 'ssh_gateway.dart';
import 'ssh_port_forwarding.dart';
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

/// Lower-level test seams retain the production route and trust checks.
typedef SshSocketConnector = Future<SSHSocket> Function(
  String host,
  int port, {
  Uri? gateway,
});

typedef SshVerifiedClientOpener = Future<SSHClient> Function(
  SSHSocket socket, {
  required String username,
  String? password,
  List<SSHIdentity>? identities,
  SSHAgentHandler? agentHandler,
  required FutureOr<bool> Function(String, Uint8List) verify,
  void Function(SSHClient)? onCreated,
});

/// Terminal output with the SSH channel's eventual process exit status.
///
/// Keep the public shell API stream-compatible, including services used by
/// embedders and tests that return a plain stream. Channel completion does not
/// close this stream early: its original stdout/stderr still drain normally.
class SshShellOutput extends StreamView<String> {
  SshShellOutput(super.stream, this.exitCode) {
    // The channel may finish before a terminal subscribes or requests its exit
    // status. Observe errors now while preserving them for the eventual reader.
    unawaited(
      exitCode.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  final Future<int?> exitCode;
}

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
  final _SshClientRoute route;
  SSHClient get client => route.clients.last;
  SSHSession? shellSession;
  TerminalOutput? shellOutput;
  int shellGeneration = 0;
  bool discoveryRunning = false;
  SshPortForwarding? forwarding;

  _SessionState({required this.session, required this.route});
}

/// Owns each transport as soon as it exists, including clients still awaiting
/// host-key approval or authentication. Late arrivals are closed after cancel.
class _SshClientRoute {
  final clients = <SSHClient>[];
  final _sockets = <SSHClient, SSHSocket>{};
  SSHSocket? _pendingSocket;
  bool closed = false;
  Future<void>? _closing;
  SshAgentConnection? agent;

  void ownSocket(SSHSocket socket) {
    if (closed) {
      unawaited(_closeSocket(socket));
    } else {
      _pendingSocket = socket;
    }
  }

  void ownClient(SSHClient client) {
    final socket = _pendingSocket;
    _pendingSocket = null; // Ownership has transferred to SSHClient.
    if (closed) {
      unawaited(_closeClient(client, socket));
    } else if (!clients.contains(client)) {
      clients.add(client);
      if (socket != null) _sockets[client] = socket;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    agent?.close();
    final pending = _pendingSocket;
    _pendingSocket = null;
    if (pending != null) await _closeSocket(pending);
    for (final client in clients.reversed.toList()) {
      await _closeClient(client, _sockets[client]);
    }
  }

  static Future<void> _closeSocket(SSHSocket socket) async {
    // Forwarded channel.close waits for the remote peer. Initiate protocol
    // close, then release the local channel even if that peer never replies.
    Future<void>? closing;
    try {
      closing = socket.close();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
    try {
      await closing?.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static Future<void> _closeClient(
    SSHClient client, [
    SSHSocket? socket,
  ]) async {
    Future<void>? closing;
    try {
      closing = client.close();
    } catch (_) {}
    try {
      socket?.destroy();
    } catch (_) {}
    try {
      await closing?.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}

class _SshRouteTarget {
  const _SshRouteTarget(
    this.host,
    this.port,
    this.username, {
    this.password,
    this.identities,
    this.agentAuthentication = false,
    this.forwardAgent = false,
  });

  final String host;
  final int port;
  final String username;
  final String? password;
  final List<SSHIdentity>? identities;
  final bool agentAuthentication;
  final bool forwardAgent;
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
  final SshSocketConnector? _socketConnector;
  final SshVerifiedClientOpener _verifiedClientOpener;
  final SshAgentFactory _agentFactory;
  final _pendingRoutes = <_SshClientRoute>{};

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
    @visibleForTesting this._socketConnector,
    @visibleForTesting SshVerifiedClientOpener? verifiedClientOpener,
    @visibleForTesting SshAgentFactory? agentFactory,
  }) : _secure = secureStorage ?? PlatformSecureStorage(),
       _verifiedClientOpener = verifiedClientOpener ?? openVerifiedSsh,
       _agentFactory = agentFactory ?? SshAgentConnection.system;

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
  /// [hostKeyPrompt] applies only to this connection attempt. When omitted,
  /// the current [confirmHostKey] callback is captured before connecting.
  /// [isCurrent] lets a terminal reject its stale attempt at each route and
  /// authentication boundary without disconnecting other terminal sessions.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password, {
    Uri? gateway,
    List<SshJumpHost> jumpHosts = const [],
    bool forwardAgent = false,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) => _connect(
    host,
    port,
    username,
    password: password,
    gateway: gateway,
    jumpHosts: jumpHosts,
    forwardAgent: forwardAgent,
    hostKeyPrompt: hostKeyPrompt,
    isCurrent: isCurrent,
  );

  // -------------------------------------------------------------------------
  // Connect (private key)
  // -------------------------------------------------------------------------

  /// Establishes an SSH connection using public-key authentication.
  ///
  /// [privateKey] should be a PEM-encoded private key string.
  /// [passphrase] decrypts a protected key locally; it is not sent as a password.
  ///
  /// [gateway] is required on web and optional on native platforms.
  /// [hostKeyPrompt] overrides [confirmHostKey] for this connection attempt.
  /// [isCurrent] is checked before every hop and after asynchronous work.
  /// Throws [StateError] when the session pool is full.
  Future<SshSession> connectWithKey(
    String host,
    int port,
    String username,
    String privateKey, {
    Uri? gateway,
    List<SshJumpHost> jumpHosts = const [],
    bool forwardAgent = false,
    String? passphrase,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) async {
    final keyPair = _parseKeyPair(privateKey, passphrase);
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
      jumpHosts: jumpHosts,
      forwardAgent: forwardAgent,
      hostKeyPrompt: hostKeyPrompt,
      isCurrent: isCurrent,
    );
  }

  /// Authenticate with public keys advertised by the local Unix SSH agent.
  /// Key material never leaves the agent. Jump hosts choose independently.
  Future<SshSession> connectWithAgent(
    String host,
    int port,
    String username, {
    Uri? gateway,
    List<SshJumpHost> jumpHosts = const [],
    bool forwardAgent = false,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) => _connect(
    host,
    port,
    username,
    agentAuthentication: true,
    forwardAgent: forwardAgent,
    gateway: gateway,
    jumpHosts: jumpHosts,
    hostKeyPrompt: hostKeyPrompt,
    isCurrent: isCurrent,
  );

  Future<SshSession> _connect(
    String host,
    int port,
    String username, {
    String? password,
    List<SSHIdentity>? identities,
    Uri? gateway,
    List<SshJumpHost> jumpHosts = const [],
    bool agentAuthentication = false,
    bool forwardAgent = false,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) async {
    // A later attempt may have a different UI or prompt owner. Capture the
    // default now so a slow socket/handshake never consults another attempt's
    // mutable callback after an await.
    final effectiveHostKeyPrompt = hostKeyPrompt ?? confirmHostKey;
    // Snapshot before the first await, so a mutable caller list cannot change
    // the route or inject a different destination during host-key approval.
    final jumps = List<SshJumpHost>.unmodifiable(jumpHosts);
    SshJumpHost.validateRoute(
      host: host,
      port: port,
      username: username,
      jumpHosts: jumps,
    );
    final targets = <_SshRouteTarget>[
      for (final jump in jumps)
        _SshRouteTarget(
          jump.host,
          jump.port,
          jump.username,
          password: jump.authentication == SshTerminalAuthentication.password
              ? jump.password
              : null,
          identities:
              jump.authentication == SshTerminalAuthentication.privateKey
              ? [_requireKeyPair(jump.privateKey, jump.passphrase)]
              : null,
          agentAuthentication:
              jump.authentication == SshTerminalAuthentication.agent,
        ),
      _SshRouteTarget(
        host,
        port,
        username,
        password: password,
        identities: identities,
        agentAuthentication: agentAuthentication,
        forwardAgent: forwardAgent,
      ),
    ];
    _checkPlatform(gateway);
    if (_disposed) throw StateError('SSH terminal service is disposed');
    if (isCurrent != null && !isCurrent()) {
      throw StateError('SSH connection was cancelled');
    }
    _checkPoolCapacity();
    _pendingConnections++;
    final generation = _connectionGeneration;
    final route = _SshClientRoute();
    _pendingRoutes.add(route);
    bool current() =>
        !_disposed &&
        generation == _connectionGeneration &&
        !route.closed &&
        (isCurrent?.call() ?? true);
    var registered = false;
    try {
      List<SSHIdentity>? agentIdentities;
      if (forwardAgent || targets.any((target) => target.agentAuthentication)) {
        final agent = _agentFactory(
          isCurrent: () =>
              !_disposed &&
              !route.closed &&
              generation == _connectionGeneration &&
              (registered || (isCurrent?.call() ?? true)),
        );
        route.agent = agent;
        agentIdentities = await agent.loadIdentities();
        if (!current()) throw StateError('SSH connection was cancelled');
      }
      final connector = _clientConnector;
      late final SSHClient client;
      if (connector != null && jumps.isEmpty && !forwardAgent) {
        // Keep the original direct-client seam compatible with existing tests.
        client = await connector(
          host,
          port,
          username: username,
          password: password,
          identities: agentAuthentication ? agentIdentities : identities,
          gateway: gateway,
        );
        route.ownClient(client);
      } else {
        client = await _openRoute(
          targets,
          route,
          gateway: gateway,
          hostKeyPrompt: effectiveHostKeyPrompt,
          current: current,
          agentIdentities: agentIdentities,
        );
      }
      if (!current()) throw StateError('SSH connection was cancelled');
      await client.authenticated;
      // A slow connection must not resurrect a session after sign-out/dispose.
      if (!current()) {
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
      final state = _SessionState(session: session, route: route);
      registered = true;
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
      await route.close();
      _log.error('SSH connect failed', error);
      // Keep cancellation as a StateError for the session lifecycle. Transport
      // failures carry stable codes so the UI can translate them at display time.
      if (_disposed ||
          generation != _connectionGeneration ||
          !(isCurrent?.call() ?? true)) {
        throw StateError('SSH connection was cancelled');
      }
      if (error is SshAgentException) rethrow;
      throw TerminalMountException(
        identities == null
            ? TerminalMountCode.sshConnection
            : TerminalMountCode.sshKeyConnection,
        'SSH connection failed: $error',
        {'error': error},
      );
    } finally {
      _pendingRoutes.remove(route);
      _pendingConnections--;
    }
  }

  Future<SSHClient> _openRoute(
    List<_SshRouteTarget> targets,
    _SshClientRoute route, {
    Uri? gateway,
    HostKeyPrompt? hostKeyPrompt,
    required bool Function() current,
    List<SSHIdentity>? agentIdentities,
  }) async {
    void ensureCurrent() {
      if (!current()) throw StateError('SSH connection was cancelled');
    }

    SSHClient? previous;
    for (final target in targets) {
      ensureCurrent();
      final SSHSocket socket;
      if (previous == null) {
        final connector = _socketConnector;
        socket = connector != null
            ? await connector(target.host, target.port, gateway: gateway)
            : gateway == null
            ? await SSHSocket.connect(
                target.host,
                target.port,
                timeout: const Duration(seconds: 15),
              )
            : await openSshGateway(gateway);
      } else {
        final forwarded = previous.forwardLocal(target.host, target.port);
        try {
          socket = await forwarded.timeout(const Duration(seconds: 15));
        } catch (_) {
          // A channel can arrive after the timeout. It still belongs to this
          // attempt and must not keep a server-side forwarding channel alive.
          unawaited(
            forwarded.then<void>(
              (late) => _SshClientRoute._closeSocket(late),
              onError: (Object _, StackTrace __) {},
            ),
          );
          rethrow;
        }
      }
      route.ownSocket(socket);
      ensureCurrent();
      final client = await _verifiedClientOpener(
        socket,
        username: target.username,
        password: target.password,
        identities: target.agentAuthentication
            ? agentIdentities
            : target.identities,
        agentHandler: target.forwardAgent ? route.agent : null,
        onCreated: route.ownClient,
        verify: (_, fingerprint) async {
          ensureCurrent();
          final accepted = await _knownHosts.verify(
            SshKnownHosts.endpoint(target.host, target.port),
            utf8.decode(fingerprint),
            prompt: hostKeyPrompt == null
                ? null
                : (endpoint, key) async {
                    if (!current()) return false;
                    final accepted = await hostKeyPrompt(endpoint, key);
                    return current() && accepted;
                  },
          );
          ensureCurrent();
          return accepted;
        },
      );
      route.ownClient(client);
      ensureCurrent();
      if (client.isClosed) throw StateError('SSH connection closed');
      previous = client;
    }
    return previous!;
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
    for (final route in _pendingRoutes.toList()) {
      await route.close();
    }
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

  /// Lists remote sessions on this already verified SSH connection. The
  /// discovery channel is independent of any interactive shell and has no PTY.
  /// Both output streams and the eventual exit status must complete.
  Future<List<SshMultiplexerSession>> listMultiplexerSessions(
    String sessionId, {
    required SshMultiplexer kind,
    bool Function()? isCurrent,
  }) async {
    final state = _requireSession(sessionId);
    bool current() =>
        !_disposed &&
        identical(_sessions[sessionId], state) &&
        state.session.connected &&
        !state.client.isClosed &&
        (isCurrent?.call() ?? true);
    if (!current()) throw StateError('SSH session discovery was cancelled');
    if (state.discoveryRunning) {
      throw StateError('SSH session discovery is already running');
    }
    state.discoveryRunning = true;
    _touch(sessionId);

    final completed = Completer<void>();
    final output = BytesBuilder(copy: false);
    final errors = BytesBuilder(copy: false);
    var totalBytes = 0;
    var finishedParts = 0;
    int? exitCode;
    SSHSession? channel;
    StreamSubscription<Uint8List>? stdoutSubscription;
    StreamSubscription<Uint8List>? stderrSubscription;

    void closeChannel(SSHSession? session) {
      try {
        session?.close();
      } catch (_) {}
    }

    void fail(Object error) {
      if (completed.isCompleted) return;
      completed.completeError(
        current() ? error : StateError('SSH session discovery was cancelled'),
      );
      closeChannel(channel);
    }

    void partFinished() {
      if (completed.isCompleted) return;
      if (!current()) {
        fail(StateError('SSH session discovery was cancelled'));
      } else if (++finishedParts == 3) {
        completed.complete();
      }
    }

    void receive(BytesBuilder destination, Uint8List data) {
      if (completed.isCompleted) return;
      if (!current()) {
        fail(StateError('SSH session discovery was cancelled'));
        return;
      }
      totalBytes += data.length;
      if (totalBytes > sshMultiplexerMaxOutputBytes) {
        fail(
          SshMultiplexerDiscoveryException(
            kind,
            SshMultiplexerDiscoveryFailure.tooMuchOutput,
          ),
        );
        return;
      }
      destination.add(data);
      _touch(sessionId);
    }

    void ioFailed(Object _, StackTrace __) => fail(
      SshMultiplexerDiscoveryException(
        kind,
        SshMultiplexerDiscoveryFailure.commandFailed,
      ),
    );

    final deadline = Timer(
      const Duration(seconds: 10),
      () => fail(
        SshMultiplexerDiscoveryException(
          kind,
          SshMultiplexerDiscoveryFailure.timeout,
        ),
      ),
    );
    // A closed/replaced tab must release a quiet listing too, rather than
    // waiting for another chunk of output to notice its stale generation.
    final cancellation = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!current()) fail(StateError('SSH session discovery was cancelled'));
    });

    try {
      final request = Future<SSHSession>.sync(
        () => state.client.execute(sshMultiplexerListCommand(kind)),
      );
      unawaited(
        request.then<void>((opened) {
          if (completed.isCompleted || !current()) {
            closeChannel(opened);
            if (!completed.isCompleted) {
              fail(StateError('SSH session discovery was cancelled'));
            }
            return;
          }
          channel = opened;
          try {
            stdoutSubscription = opened.stdout.listen(
              (data) => receive(output, data),
              onError: ioFailed,
              onDone: partFinished,
            );
            stderrSubscription = opened.stderr.listen(
              (data) => receive(errors, data),
              onError: ioFailed,
              onDone: partFinished,
            );
            unawaited(
              opened.done.then<void>((_) {
                exitCode = opened.exitCode;
                partFinished();
              }, onError: ioFailed),
            );
          } catch (error) {
            fail(error);
          }
        }, onError: ioFailed),
      );
      await completed.future;
      if (!current()) throw StateError('SSH session discovery was cancelled');
      try {
        return parseSshMultiplexerSessions(
          kind,
          utf8.decode(output.takeBytes()),
          exitCode: exitCode,
          stderr: utf8.decode(errors.takeBytes(), allowMalformed: true),
        );
      } on FormatException {
        throw SshMultiplexerDiscoveryException(
          kind,
          SshMultiplexerDiscoveryFailure.invalidListing,
        );
      }
    } finally {
      deadline.cancel();
      cancellation.cancel();
      closeChannel(channel);
      try {
        await stdoutSubscription?.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await stderrSubscription?.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {}
      state.discoveryRunning = false;
    }
  }

  // -------------------------------------------------------------------------
  // Interactive shell
  // -------------------------------------------------------------------------

  /// Starts an interactive PTY shell or a remote [tmux] / [screen] session.
  ///
  /// Returns a single-subscription stream of decoded terminal output, including
  /// ANSI sequences. The initial prompt is buffered until a listener attaches.
  /// A tmux launch uses an SSH exec request with a PTY, not shell input. Closing
  /// its connection detaches the client without asking tmux to kill the session.
  Future<Stream<String>> startShell(
    String sessionId, {
    int width = 80,
    int height = 24,
    TmuxSessionOptions? tmux,
    ScreenSessionOptions? screen,
  }) async {
    _validateDimensions(width, height);
    // Validate before replacing a running shell or sending any remote request.
    if (tmux != null && screen != null) {
      throw ArgumentError('Choose either tmux or screen, not both');
    }
    final command = tmux?.command ?? screen?.command;
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
      final pty = SSHPtyConfig(
        type: 'xterm-256color',
        width: width,
        height: height,
      );
      shell = command == null
          ? await client.shell(pty: pty)
          : await client.execute(command, pty: pty);
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
    final exitCode = shell.done.then<int?>((_) => shell.exitCode);

    Future<void> disconnectAfterExit() async {
      try {
        // SSH EOF closes the output streams, but the remote process may still
        // run or report its exit status later. Keep the channel alive until it
        // finishes as well. Explicit cancellation still disconnects below.
        await exitCode;
      } catch (_) {
        // SshShellOutput preserves this error for the terminal's exit reader.
        // A failed channel still needs cleanup after its output has drained.
      }
      if (_isCurrentShell(sessionId, state, generation)) {
        await disconnect(sessionId);
      }
    }

    final output = TerminalOutput(
      [shell.stdout, shell.stderr],
      onActivity: () => _touch(sessionId),
      onDone: () {
        // Neither stream EOF nor channel completion is sufficient on its own:
        // retain both final output and a later exit-status request.
        unawaited(disconnectAfterExit());
      },
      onCancel: () async {
        if (_isCurrentShell(sessionId, state, generation)) {
          await disconnect(sessionId);
        }
      },
    );
    state.shellOutput = output;
    return SshShellOutput(output.stream, exitCode);
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

  /// Runtime tunnels belong to this exact verified connection. A reconnect
  /// gets a fresh manager; listeners and destinations are never persisted.
  /// Capability probes never create a manager or throw for expired sessions.
  bool canForwardPorts(String sessionId) {
    final state = _sessions[sessionId];
    return SshPortForwarding.supported &&
        !_disposed &&
        state != null &&
        state.session.connected &&
        !state.client.isClosed;
  }

  SshPortForwarding forwarding(String sessionId) {
    final state = _requireSession(sessionId);
    if (_disposed || !state.session.connected || state.client.isClosed) {
      throw const SshPortForwardException('The SSH connection is closed.');
    }
    return state.forwarding ??= SshPortForwarding(
      state.client,
      onActivity: () {
        if (identical(_sessions[sessionId], state)) _touch(sessionId);
      },
    );
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
    state.route.agent?.close();
    unawaited(state.forwarding?.close());
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
    state.route.agent?.close();
    await state.forwarding?.close();
    try {
      state.shellSession?.close();
    } catch (_) {}
    try {
      await state.shellOutput?.dispose();
    } catch (_) {}
    await state.route.close();
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
  /// Returns null when parsing or decryption fails; no connection is attempted.
  SSHKeyPair? _parseKeyPair(String pemKey, String? passphrase) {
    try {
      // Form fields and jump-host models represent an omitted passphrase as
      // an empty string. dartssh2 rejects even an empty non-null passphrase for
      // an unencrypted OpenSSH key. Preserve nonempty values exactly.
      final pairs = SSHKeyPair.fromPem(
        pemKey,
        passphrase == null || passphrase.isEmpty ? null : passphrase,
      );
      return pairs.isNotEmpty ? pairs.first : null;
    } catch (_) {
      // Parser exceptions can contain source text. Do not log key material or
      // passphrases; callers receive the stable, localized invalid-key error.
      _log.error('Failed to parse or decrypt SSH private key');
      return null;
    }
  }

  SSHKeyPair _requireKeyPair(String pemKey, String? passphrase) {
    final key = _parseKeyPair(pemKey, passphrase);
    if (key == null) {
      throw const TerminalMountFormatException(
        TerminalMountCode.sshInvalidKey,
        'Invalid SSH private key',
      );
    }
    return key;
  }

  String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (_nextId++).toRadixString(36);
}
