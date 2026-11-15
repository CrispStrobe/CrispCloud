import '../services/ssh_gateway.dart';
import 'screen_session_options.dart';
import 'ssh_terminal_config.dart';
import 'tmux_session_options.dart';

/// A saved destination. The credential fields are removed at construction and
/// never read from or written to the persisted schema.
class SshTerminalProfile {
  SshTerminalProfile({required this.name, required SshTerminalConfig config})
    : config = config.withoutSecrets() {
    if (!isValidName(name) || name != name.trim()) {
      throw const FormatException('Invalid SSH profile name');
    }
    _validateConfig(this.config);
  }

  final String name;
  final SshTerminalConfig config;

  static bool isValidName(String value) =>
      value.trim().isNotEmpty &&
      value.trim().length <= 80 &&
      !_controlCharacters.hasMatch(value);

  static final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

  static void _validateConfig(SshTerminalConfig config) {
    if (config.host.isEmpty ||
        config.host.length > 253 ||
        config.host != config.host.trim() ||
        RegExp(r'\s').hasMatch(config.host) ||
        _controlCharacters.hasMatch(config.host) ||
        config.username.isEmpty ||
        config.username.length > 128 ||
        config.username != config.username.trim() ||
        _controlCharacters.hasMatch(config.username) ||
        config.port < 1 ||
        config.port > 65535 ||
        (config.gateway?.toString().length ?? 0) > 2048 ||
        sshGatewayValidationMessage(config.gateway, required: false) != null) {
      throw const FormatException('Invalid SSH profile destination');
    }
    try {
      config.validateSessionOptions();
    } on ArgumentError {
      throw const FormatException('Invalid SSH profile session');
    }
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'host': config.host,
    'port': config.port,
    'username': config.username,
    'authentication': config.authentication.name,
    if (config.gateway != null) 'gateway': config.gateway.toString(),
    'session': config.tmux != null
        ? {
            'kind': 'tmux',
            'mode': config.tmux!.mode.name,
            'name': config.tmux!.sessionName,
          }
        : config.screen != null
        ? {
            'kind': 'screen',
            'mode': config.screen!.mode.name,
            'name': config.screen!.sessionName,
          }
        : {'kind': 'shell'},
  };

  factory SshTerminalProfile.fromJson(Map<String, dynamic> value) {
    String text(String key) {
      final field = value[key];
      if (field is! String) throw const FormatException('Invalid SSH profile');
      return field;
    }

    final port = value['port'];
    if (port is! int) throw const FormatException('Invalid SSH profile port');
    final authentication = switch (text('authentication')) {
      'password' => SshTerminalAuthentication.password,
      'privateKey' => SshTerminalAuthentication.privateKey,
      _ => throw const FormatException('Unknown SSH authentication method'),
    };
    final gatewayValue = value['gateway'];
    if (gatewayValue != null && gatewayValue is! String) {
      throw const FormatException('Invalid SSH profile gateway');
    }
    final session = value['session'];
    if (session is! Map<String, dynamic>) {
      throw const FormatException('Invalid SSH profile session');
    }
    TmuxSessionOptions? tmux;
    ScreenSessionOptions? screen;
    switch (session['kind']) {
      case 'shell':
        break;
      case 'tmux':
        final name = session['name'];
        if (name is! String) throw const FormatException('Invalid tmux target');
        tmux = TmuxSessionOptions(
          sessionName: name,
          mode: switch (session['mode']) {
            'createOrAttach' => TmuxSessionMode.createOrAttach,
            'attach' => TmuxSessionMode.attach,
            _ => throw const FormatException('Unknown tmux mode'),
          },
        );
      case 'screen':
        final name = session['name'];
        if (name is! String) {
          throw const FormatException('Invalid screen target');
        }
        screen = ScreenSessionOptions(
          sessionName: name,
          mode: switch (session['mode']) {
            'create' => ScreenSessionMode.create,
            'attach' => ScreenSessionMode.attach,
            _ => throw const FormatException('Unknown screen mode'),
          },
        );
      default:
        throw const FormatException('Unknown SSH session kind');
    }
    return SshTerminalProfile(
      name: text('name'),
      config: SshTerminalConfig(
        host: text('host'),
        port: port,
        username: text('username'),
        authentication: authentication,
        gateway: gatewayValue == null
            ? null
            : Uri.parse(gatewayValue as String),
        tmux: tmux,
        screen: screen,
      ),
    );
  }
}
