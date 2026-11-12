/// FTP control/data protection. Persisted names are part of the connection
/// format; an unknown value is rejected instead of weakening the connection.
enum FtpSecurityMode {
  plain,
  implicitTls,
  explicitTls;

  bool get isSecure => this != plain;
  int get defaultPort => this == implicitTls ? 990 : 21;

  static FtpSecurityMode fromStored({String? mode, String? legacyUseTls}) {
    if (mode != null) {
      for (final value in values) {
        if (value.name == mode) return value;
      }
      throw const FormatException('Unknown FTP security mode.');
    }
    // Existing useTLS/tls=true configurations have always used implicit TLS.
    // Do not silently migrate them to a different wire protocol or port.
    if (legacyUseTls == null || legacyUseTls == 'false') return plain;
    if (legacyUseTls == 'true') return implicitTls;
    throw const FormatException('Invalid legacy FTP security setting.');
  }
}

/// Validated, non-secret FTP login identity used by both the dialog and adapter.
class FtpLoginIdentity {
  const FtpLoginIdentity({
    required this.username,
    required this.host,
    required this.port,
    required this.securityMode,
  });

  final String username;
  final String host;
  final int port;
  final FtpSecurityMode securityMode;

  factory FtpLoginIdentity.parse(String identity) {
    final separator = identity.lastIndexOf('@');
    if (separator <= 0 || separator == identity.length - 1) {
      throw const FormatException('FTP identity must be user@host[:port].');
    }
    final username = identity.substring(0, separator);
    final address = Uri.parse('//${identity.substring(separator + 1)}');
    if (address.host.isEmpty ||
        address.userInfo.isNotEmpty ||
        (address.path.isNotEmpty && address.path != '/') ||
        address.fragment.isNotEmpty ||
        RegExp(r'[\r\n\x00]').hasMatch(identity)) {
      throw const FormatException('Invalid FTP login identity.');
    }
    final parameters = address.queryParametersAll;
    if (parameters.values.any((values) => values.length != 1) ||
        parameters.keys.any((key) => key != 'security' && key != 'tls')) {
      throw const FormatException('Invalid FTP security parameters.');
    }
    final mode = FtpSecurityMode.fromStored(
      mode: address.queryParameters['security'],
      legacyUseTls: address.queryParameters['tls'],
    );
    if (parameters.containsKey('security') && parameters.containsKey('tls')) {
      throw const FormatException('Choose one FTP security setting.');
    }
    final port = address.hasPort ? address.port : mode.defaultPort;
    if (port < 1 || port > 65535) {
      throw const FormatException('FTP port must be between 1 and 65535.');
    }
    return FtpLoginIdentity(
      username: username,
      host: address.host,
      port: port,
      securityMode: mode,
    );
  }

  String encode() {
    // Uri supplies IPv6 brackets and correct escaping for the host/port.
    final address = Uri(
      host: host,
      port: port,
      queryParameters: {'security': securityMode.name},
    ).toString().substring(2);
    return '$username@$address';
  }
}
