import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/directory_selection_comparison.dart';

bool canCompareDirectories(WidgetRef ref) =>
    [PanelSide.local, PanelSide.remote].every((side) {
      final panel = ref.read(panelProvider(side));
      return !panel.isLoading &&
          panel.files != null &&
          panel.hasVerifiedDirectoryListing &&
          !panel.isPagedCollection;
    });

void compareDirectories(WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final active = ref.read(panelProvider(side));
  final other = ref.read(
    panelProvider(side == PanelSide.local ? PanelSide.remote : PanelSide.local),
  );
  if (!canCompareDirectories(ref)) return;
  active.selectVisibleItems(
    compareDirectorySelection(active.files!, other.files!),
  );
}

void copySelectionNamesOrPaths(WidgetRef ref, {required bool namesOnly}) {
  final panel = ref.read(panelProvider(ref.read(activePanelProvider)));
  final files = panel.selection.isNotEmpty
      ? panel.selection.toList()
      : [if (panel.cursorItem != null) panel.cursorItem!];
  final text = files
      .where((file) => file.name != '..')
      .map((file) => namesOnly ? file.name : file.path ?? file.name)
      .join('\n');
  if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
}
