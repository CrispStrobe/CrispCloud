import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/ssh_port_forward.dart';
import 'ssh_port_forwarding_stub.dart'
    if (dart.library.io) 'ssh_port_forwarding_io.dart'
    as platform;

export '../models/ssh_port_forward.dart';

/// Owns listeners and their channels for exactly one verified SSH connection.
/// The owner must close this manager before closing its SSH route. Closing a
/// listener also closes its existing clients; reconnect never restores it.
abstract class SshPortForwarding extends ChangeNotifier {
  factory SshPortForwarding(
    SSHClient client, {
    VoidCallback? onActivity,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) => platform.createSshPortForwarding(
    client,
    onActivity: onActivity,
    connectTimeout: connectTimeout,
    handshakeTimeout: handshakeTimeout,
  );

  SshPortForwarding.base();

  static bool get supported => platform.sshPortForwardingSupported;
  static const maximumForwards = 16;
  static const maximumConnections = 32;

  List<SshPortForwardSnapshot> get forwards;
  bool get isClosed;
  Future<SshPortForwardSnapshot> start(SshPortForwardSpec spec);
  Future<void> stop(String id);
  Future<void> close();
}
