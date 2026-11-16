import 'ssh_agent.dart';

bool get sshAgentSupported => false;
bool get sshAgentAvailable => false;

SshAgentConnection createSystemSshAgent({required bool Function() isCurrent}) =>
    throw const SshAgentException(SshAgentException.unsupported);
