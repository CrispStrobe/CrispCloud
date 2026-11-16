/// Which side listens, and how the target is selected.
enum SshPortForwardKind { local, remote, dynamic }

enum SshPortForwardStatus { starting, active, stopping, failed }

/// A runtime forwarding request, never an instruction to execute a command.
/// Bind addresses are deliberately literal loopback addresses. Target names
/// resolve at the SSH server for local/SOCKS forwarding, and here for remote
/// forwarding.
class SshPortForwardSpec {
  SshPortForwardSpec({
    required this.kind,
    this.bindHost = '127.0.0.1',
    this.bindPort = 0,
    this.targetHost,
    this.targetPort,
  }) {
    if (!loopbackHosts.contains(bindHost)) {
      throw const FormatException('Choose a loopback bind address.');
    }
    if (bindPort < 0 || bindPort > 65535) {
      throw const FormatException(
        'The listening port must be between 0 and 65535.',
      );
    }
    if (kind == SshPortForwardKind.dynamic) {
      if (targetHost != null || targetPort != null) {
        throw const FormatException('A SOCKS proxy has no fixed destination.');
      }
    } else if (!isValidTargetHost(targetHost ?? '') ||
        targetPort == null ||
        targetPort! < 1 ||
        targetPort! > 65535) {
      throw const FormatException(
        'Enter a destination host and port between 1 and 65535.',
      );
    }
  }

  static const loopbackHosts = ['127.0.0.1', '::1'];
  static bool isValidTargetHost(String value) =>
      value.isNotEmpty &&
      value.length <= 253 &&
      value == value.trim() &&
      !RegExp(r'[\s\x00-\x20\x7f-\x9f/\\@\[\]]').hasMatch(value);

  final SshPortForwardKind kind;
  final String bindHost;
  final int bindPort;
  final String? targetHost;
  final int? targetPort;
}

/// An immutable view of one listener. [port] is the assigned port once active.
class SshPortForwardSnapshot {
  const SshPortForwardSnapshot({
    required this.id,
    required this.spec,
    required this.status,
    required this.port,
    required this.activeConnections,
    this.error,
  });

  final String id;
  final SshPortForwardSpec spec;
  final SshPortForwardStatus status;
  final int port;
  final int activeConnections;
  final String? error;
}

class SshPortForwardException implements Exception {
  const SshPortForwardException(this.message);
  final String message;
  @override
  String toString() => message;
}
