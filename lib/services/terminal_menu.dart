import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TerminalMenuAction { copy, paste, disconnect, hide }

/// While terminal input has focus, native menus must not invoke file actions
/// for keys such as Enter, F5, Ctrl+C or Cmd+W.
class TerminalMenuActions {
  const TerminalMenuActions({
    required this.owner,
    required this.perform,
    required this.canCopy,
    required this.canPaste,
    required this.canDisconnect,
  });

  final Object owner;
  final void Function(TerminalMenuAction action) perform;
  final bool canCopy;
  final bool canPaste;
  final bool canDisconnect;
}

final terminalMenuProvider = StateProvider<TerminalMenuActions?>((ref) => null);
