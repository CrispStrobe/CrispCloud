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
  final Uri? gateway;

  /// Ordered outermost first; the gateway, if any, reaches the first hop.
  final List<SshJumpHost> jumpHosts;
  final TmuxSessionOptions? tmux;
  final ScreenSessionOptions? screen;

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
    gateway: gateway,
    jumpHosts: List.unmodifiable(
      jumpHosts.map((jump) => jump.withoutSecrets()),
    ),
    tmux: tmux,
    screen: screen,
  );
}
