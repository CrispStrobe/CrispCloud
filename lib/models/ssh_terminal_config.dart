import 'screen_session_options.dart';
import 'ssh_jump_host.dart';
import 'tmux_session_options.dart';

export 'ssh_jump_host.dart';

/// Connection details for a single SSH terminal attempt.
///
/// Credentials are deliberately not serialized. Retain [withoutSecrets] for
/// reconnecting and ask for credentials again in the connection dialog.
class SshTerminalConfig {
  const SshTerminalConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
    this.authentication = SshTerminalAuthentication.password,
    this.forwardAgent = false,
    this.gateway,
    this.jumpHosts = const [],
    this.tmux,
    this.screen,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;
  final String passphrase;
  final SshTerminalAuthentication authentication;

  /// Explicit permission for the final server to request agent signatures.
  /// This does not expose the agent to jump hosts or store any key material.
  final bool forwardAgent;
  final Uri? gateway;

  /// Ordered outermost first; the gateway, if any, reaches the first hop.
  final List<SshJumpHost> jumpHosts;
  final TmuxSessionOptions? tmux;
  final ScreenSessionOptions? screen;

  bool get usesAgent =>
      authentication == SshTerminalAuthentication.agent ||
      forwardAgent ||
      jumpHosts.any(
        (jump) => jump.authentication == SshTerminalAuthentication.agent,
      );

  /// Validate mutually exclusive launch options before replacing a connection.
  void validateSessionOptions() {
    SshJumpHost.validateRoute(
      host: host,
      port: port,
      username: username,
      jumpHosts: jumpHosts,
    );
    if (tmux != null && screen != null) {
      throw ArgumentError('Choose either tmux or screen, not both');
    }
    final tmuxOptions = tmux;
    if (tmuxOptions != null &&
        !TmuxSessionOptions.isValidSessionName(tmuxOptions.sessionName)) {
      throw ArgumentError.value(
        tmuxOptions.sessionName,
        'tmux',
        'Invalid tmux name',
      );
    }
    final screenOptions = screen;
    if (screenOptions != null && !screenOptions.isValid) {
      throw ArgumentError.value(
        screenOptions.sessionName,
        'screen',
        'Invalid screen target',
      );
    }
  }

  SshTerminalConfig withoutSecrets() => SshTerminalConfig(
    host: host,
    port: port,
    username: username,
    authentication: authentication,
    forwardAgent: forwardAgent,
    gateway: gateway,
    jumpHosts: List.unmodifiable(
      jumpHosts.map((jump) => jump.withoutSecrets()),
    ),
    tmux: tmux,
    screen: screen,
  );

  /// Reconnect metadata for an explicitly shared plain shell. The live route
  /// supplies authentication; neither secrets nor tmux/Screen launch options
  /// belong to the new terminal's saved destination.
  SshTerminalConfig forSharedShell() => SshTerminalConfig(
    host: host,
    port: port,
    username: username,
    authentication: authentication,
    forwardAgent: forwardAgent,
    gateway: gateway,
    jumpHosts: List.unmodifiable(
      jumpHosts.map((jump) => jump.withoutSecrets()),
    ),
  );
}
