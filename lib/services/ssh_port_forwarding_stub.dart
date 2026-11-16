import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ssh_port_forwarding.dart';

const sshPortForwardingSupported = false;

SshPortForwarding createSshPortForwarding(
  SSHClient client, {
  VoidCallback? onActivity,
  required Duration connectTimeout,
  required Duration handshakeTimeout,
}) => _UnsupportedForwarding();

class _UnsupportedForwarding extends SshPortForwarding {
  _UnsupportedForwarding() : super.base();
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  @override
  List<SshPortForwardSnapshot> get forwards => const [];
  @override
  Future<SshPortForwardSnapshot> start(SshPortForwardSpec spec) async =>
      throw const SshPortForwardException(
        'Port forwarding requires native TCP sockets and is unavailable in the browser.',
      );
  @override
  Future<void> stop(String id) async {}
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    notifyListeners();
  }
}
