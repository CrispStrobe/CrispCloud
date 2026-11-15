import 'screen_session_options.dart';
import 'tmux_session_options.dart';

enum SshTerminalAuthentication { password, privateKey }

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
  final TmuxSessionOptions? tmux;
  final ScreenSessionOptions? screen;

  /// Validate mutually exclusive launch options before replacing a connection.
  void validateSessionOptions() {
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
    tmux: tmux,
    screen: screen,
  );
}
