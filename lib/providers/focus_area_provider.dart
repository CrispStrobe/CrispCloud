import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';

/// Which surface owns keyboard focus right now:
/// the left browser pane, the right browser pane, or the embedded terminal.
///
/// The value is sticky: it changes only when the user clicks/switches to
/// another surface, never because a pane refreshed or a dialog closed.
enum FocusArea { local, remote, terminal }

final focusAreaProvider = StateProvider<FocusArea>((ref) => FocusArea.local);

extension FocusAreaSide on FocusArea {
  PanelSide? get panelSide => switch (this) {
    FocusArea.local => PanelSide.local,
    FocusArea.remote => PanelSide.remote,
    FocusArea.terminal => null,
  };
}
