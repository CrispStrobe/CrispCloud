import 'ssh_terminal_authentication.dart';

export 'ssh_terminal_authentication.dart';

/// One SSH server reached before the final terminal destination.
///
/// Credentials live only for a connection attempt. Persist [toJson] or retain
/// [withoutSecrets], never the original object. A route uses independent SSH
/// authentication and host-key verification at every hop.
class SshJumpHost {
  const SshJumpHost({
    required this.host,
    this.port = 22,
    required this.username,
    this.authentication = SshTerminalAuthentication.password,
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  final String host;
  final int port;
  final String username;
  final SshTerminalAuthentication authentication;
  final String password;
  final String privateKey;
  final String passphrase;

  static const maxJumpHosts = 3;

  static final _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');

  static bool isValidHost(String value) =>
      value.isNotEmpty &&
      value.length <= 253 &&
      value == value.trim() &&
      !RegExp(r'[\s\[\]/\\@?#]').hasMatch(value) &&
      !_controlCharacters.hasMatch(value);

  static bool isValidUsername(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      value == value.trim() &&
      !_controlCharacters.hasMatch(value);

  static void validateDestination(String host, int port, String username) {
    if (!isValidHost(host) ||
        !isValidUsername(username) ||
        port < 1 ||
        port > 65535) {
      throw ArgumentError('Invalid SSH destination');
    }
  }

  /// Reject duplicate written endpoints, including DNS case and a trailing
  /// root dot. DNS aliases and context-dependent names are not resolved here.
  static void validateRoute({
    required String host,
    required int port,
    required String username,
    required List<SshJumpHost> jumpHosts,
  }) {
    validateDestination(host, port, username);
    if (jumpHosts.length > maxJumpHosts) {
      throw ArgumentError('Use at most three SSH jump hosts');
    }
    String endpoint(String name, int port) {
      final normalized = name.toLowerCase();
      return '${normalized.endsWith('.') ? normalized.substring(0, normalized.length - 1) : normalized}:$port';
    }

    final endpoints = <String>{endpoint(host, port)};
    for (final jump in jumpHosts) {
      validateDestination(jump.host, jump.port, jump.username);
      if (!endpoints.add(endpoint(jump.host, jump.port))) {
        throw ArgumentError('SSH jump hosts and target must be distinct');
      }
    }
  }

  SshJumpHost withoutSecrets() => SshJumpHost(
    host: host,
    port: port,
    username: username,
    authentication: authentication,
  );

  /// Explicit allowlist: passwords, private keys and passphrases never enter
  /// profile or arrangement storage, even if provided in external records.
  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'authentication': authentication.name,
  };

  factory SshJumpHost.fromJson(Map<String, dynamic> value) {
    final host = value['host'];
    final port = value['port'];
    final username = value['username'];
    if (host is! String || port is! int || username is! String) {
      throw const FormatException('Invalid SSH jump host');
    }
    final authentication = switch (value['authentication']) {
      'password' => SshTerminalAuthentication.password,
      'privateKey' => SshTerminalAuthentication.privateKey,
      'agent' => SshTerminalAuthentication.agent,
      _ => throw const FormatException('Unknown SSH jump authentication'),
    };
    try {
      validateDestination(host, port, username);
    } on ArgumentError {
      throw const FormatException('Invalid SSH jump destination');
    }
    return SshJumpHost(
      host: host,
      port: port,
      username: username,
      authentication: authentication,
    );
  }
}
