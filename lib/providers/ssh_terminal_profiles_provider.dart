import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh_terminal_profiles.dart';

final sshTerminalProfilesProvider = Provider<SshTerminalProfiles>(
  (ref) => SshTerminalProfiles(),
);
