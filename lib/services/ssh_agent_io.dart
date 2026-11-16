import 'dart:io';
import 'dart:typed_data';

import 'ssh_agent.dart';

bool get sshAgentSupported => Platform.isLinux || Platform.isMacOS;

bool get sshAgentAvailable =>
    sshAgentSupported &&
    _validSocketPath(Platform.environment['SSH_AUTH_SOCK']);

bool _validSocketPath(String? path) =>
    path != null &&
    path.startsWith('/') &&
    path.length <= 4096 &&
    !RegExp(r'[\x00\r\n]').hasMatch(path);

SshAgentConnection createSystemSshAgent({required bool Function() isCurrent}) {
  if (!sshAgentSupported) {
    throw const SshAgentException(SshAgentException.unsupported);
  }
  final path = Platform.environment['SSH_AUTH_SOCK'];
  if (!_validSocketPath(path)) {
    throw const SshAgentException(SshAgentException.unavailable);
  }
  // Capture one exact environment path for the route. Never search key files,
  // run shell commands, expand path expressions, or change an agent's state.
  return SshAgentConnection(
    isCurrent: isCurrent,
    connect: () async => _SocketTransport(
      await Socket.connect(
        InternetAddress(path!, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 5),
      ),
    ),
  );
}

class _SocketTransport implements SshAgentTransport {
  _SocketTransport(this.socket);
  final Socket socket;
  @override
  Stream<List<int>> get input => socket;
  @override
  void add(Uint8List bytes) => socket.add(bytes);
  @override
  void destroy() => socket.destroy();
}
