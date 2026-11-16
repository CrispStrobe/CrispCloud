import 'ssh_port_forwarding.dart';

/// Optional transport capability; the SSH service retains tunnel ownership.
abstract interface class TerminalForwardingConnection {
  SshPortForwarding? get portForwarding;
}
