import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal_workspace_service.dart';

/// One journal owner coordinates staging and uploads across terminal dialogs.
final terminalWorkspaceServiceProvider = Provider<TerminalWorkspaceService>(
  (ref) => TerminalWorkspaceService(),
);
