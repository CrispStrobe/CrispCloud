import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gallery_strings.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/toolbar_provider.dart';
import '../services/panel_view_mode_service.dart';

String fileViewName(ViewMode mode) => switch (mode) {
  ViewMode.list => 'List', ViewMode.grid => 'Icons', ViewMode.tiles => 'Tiles',
  ViewMode.gallery => 'Gallery', ViewMode.column => 'Columns',
};

IconData fileViewIcon(ViewMode mode) => switch (mode) {
  ViewMode.list => Icons.view_list, ViewMode.grid => Icons.grid_view,
  ViewMode.tiles => Icons.view_module_outlined,
  ViewMode.gallery => Icons.photo_library_outlined,
  ViewMode.column => Icons.view_column,
};

void setFileView(WidgetRef ref, PanelSide side, ViewMode mode) {
  final notifier = side == PanelSide.local
      ? ref.read(localViewModeProvider.notifier)
      : ref.read(remoteViewModeProvider.notifier);
  notifier.state = mode;
  final density = ref.read(panelViewModeProvider(side));
  // Every explicit layout choice supersedes a pending saved tree restore.
  // Preserve brief density only when the user chooses the list layout.
  ref.read(panelViewModeProvider(side).notifier).setMode(
    mode == ViewMode.list && density == PanelViewMode.brief
        ? PanelViewMode.brief : PanelViewMode.full,
  );
}

class FileViewSelector extends ConsumerWidget {
  const FileViewSelector({super.key, required this.side, this.color});
  final PanelSide side;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = side == PanelSide.local
        ? ref.watch(localViewModeProvider) : ref.watch(remoteViewModeProvider);
    return PopupMenuButton<ViewMode>(
      tooltip: context.galleryTr('View'),
      icon: Icon(fileViewIcon(current), size: 20, color: color),
      initialValue: current,
      onSelected: (mode) => setFileView(ref, side, mode),
      itemBuilder: (context) => [
        for (final mode in [ViewMode.list, ViewMode.grid, ViewMode.tiles,
            ViewMode.gallery, ViewMode.column])
          CheckedPopupMenuItem(
            value: mode, checked: current == mode,
            child: Row(children: [
              Icon(fileViewIcon(mode), size: 18), const SizedBox(width: 10),
              Text(context.galleryTr(fileViewName(mode))),
            ]),
          ),
      ],
    );
  }
}
