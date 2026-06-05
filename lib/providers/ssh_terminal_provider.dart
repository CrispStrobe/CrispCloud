// lib/providers/ssh_terminal_provider.dart
//
// Riverpod providers for the embedded SSH terminal service.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh_terminal_service.dart';

// ---------------------------------------------------------------------------
// Singleton service
// ---------------------------------------------------------------------------

/// Singleton [SshTerminalService] instance.
///
/// The service is created lazily and disposed when the provider is no longer
/// listened to.
final sshTerminalServiceProvider = Provider<SshTerminalService>((ref) {
  final service = SshTerminalService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Active sessions
// ---------------------------------------------------------------------------

/// Derived provider that returns the list of currently active [SshSession]s.
///
/// Because [SshTerminalService] is not itself a [Notifier], callers that need
/// reactive updates should invalidate this provider after connect/disconnect
/// operations, or use a [StateNotifier]-backed variant.
final sshSessionsProvider = Provider<List<SshSession>>((ref) {
  final service = ref.watch(sshTerminalServiceProvider);
  return service.getActiveSessions();
});

// ---------------------------------------------------------------------------
// Notifier (for reactive UI)
// ---------------------------------------------------------------------------

/// A [StateNotifier] that wraps [SshTerminalService] and exposes reactive
/// session state to the UI layer.
///
/// Preferred over [sshSessionsProvider] when the UI must react to
/// connect/disconnect events without manual invalidation.
class SshTerminalNotifier extends StateNotifier<List<SshSession>> {
  final SshTerminalService _service;

  SshTerminalNotifier(this._service) : super([]);

  /// Connects using password authentication and refreshes state.
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password,
  ) async {
    final session = await _service.connect(host, port, username, password);
    _refresh();
    return session;
  }

  /// Connects using a PEM private key and refreshes state.
  Future<SshSession> connectWithKey(
    String host,
    int port,
    String username,
    String privateKey,
  ) async {
    final session =
        await _service.connectWithKey(host, port, username, privateKey);
    _refresh();
    return session;
  }

  /// Disconnects [sessionId] and refreshes state.
  Future<void> disconnect(String sessionId) async {
    await _service.disconnect(sessionId);
    _refresh();
  }

  /// Disconnects all sessions and refreshes state.
  Future<void> disconnectAll() async {
    await _service.disconnectAll();
    _refresh();
  }

  /// Delegates to [SshTerminalService.execute].
  Future<String> execute(String sessionId, String command) =>
      _service.execute(sessionId, command);

  /// Delegates to [SshTerminalService.startShell].
  Future<Stream<String>> startShell(String sessionId) =>
      _service.startShell(sessionId);

  /// Delegates to [SshTerminalService.writeToShell].
  Future<void> writeToShell(String sessionId, String input) =>
      _service.writeToShell(sessionId, input);

  /// Delegates to [SshTerminalService.resizeTerminal].
  Future<void> resizeTerminal(String sessionId, int width, int height) =>
      _service.resizeTerminal(sessionId, width, height);

  void _refresh() {
    state = _service.getActiveSessions();
  }
}

/// Provider for [SshTerminalNotifier].
final sshTerminalNotifierProvider =
    StateNotifierProvider<SshTerminalNotifier, List<SshSession>>((ref) {
  final service = ref.watch(sshTerminalServiceProvider);
  return SshTerminalNotifier(service);
});
