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

  SshTerminalConfig withoutSecrets() => SshTerminalConfig(
    host: host,
    port: port,
    username: username,
    authentication: authentication,
    gateway: gateway,
    tmux: tmux,
  );
}
