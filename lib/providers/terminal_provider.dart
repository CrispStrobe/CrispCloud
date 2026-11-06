// lib/providers/terminal_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import 'core_providers.dart';
import 'focus_area_provider.dart';

/// Whether the embedded terminal panel is visible.
final showTerminalProvider = StateProvider<bool>((ref) => false);

/// Height of the terminal panel in pixels.
final terminalHeightProvider = StateProvider<double>((ref) => 220.0);

/// True while the embedded terminal command field owns the keyboard.
final terminalInputFocusedProvider = StateProvider<bool>((ref) => false);

/// Toggle the terminal and move keyboard ownership with it. When shown, the
/// terminal becomes the sticky focus target; when hidden, focus returns to the
/// last active browser pane.
void setTerminalVisible(WidgetRef ref, bool show) {
  ref.read(showTerminalProvider.notifier).state = show;
  if (show) {
    ref.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    return;
  }
  final side = ref.read(activePanelProvider);
  ref.read(focusAreaProvider.notifier).state = side == PanelSide.local
      ? FocusArea.local
      : FocusArea.remote;
}
