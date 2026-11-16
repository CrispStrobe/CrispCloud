import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal_workspace_recovery.dart';

final terminalWorkspaceRecoveryProvider = Provider<TerminalWorkspaceRecovery>(
  (ref) => TerminalWorkspaceRecovery(),
);
