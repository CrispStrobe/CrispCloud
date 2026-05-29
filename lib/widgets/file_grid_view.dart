// lib/widgets/file_grid_view.dart
//
// Grid/gallery view for file listing. Alternative to FileListView.
// Shows files as icon cards with name and size underneath.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'file_list_view.dart' show getFileIcon;

class FileGridView extends ConsumerWidget {
  final PanelSide side;
  final List<FileItem> files;
  final ScrollController scrollController;

  const FileGridView({
    super.key,
    required this.side,
    required this.files,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));

    if (files.isEmpty) {
      return const Center(child: Text('Empty folder'));
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = panel.isSelected(file);

        return _FileGridTile(
          file: file,
          side: side,
          isSelected: isSelected,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            panel.toggleSelection(file, shiftKey: shiftPressed, ctrlKey: ctrlPressed);
          },
          onDoubleTap: () => panel.navigateInto(file),
          onSecondaryTap: (details) => showFileContextMenu(context, ref, side, file, details.globalPosition),
        );
      },
    );
  }
}

class _FileGridTile extends StatelessWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails) onSecondaryTap;

  const _FileGridTile({
    required this.file,
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTap,
      onDoubleTap: onDoubleTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : null,
            border: isSelected
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                file.isFolder ? Icons.folder : getFileIcon(file.name),
                color: file.isFolder ? Colors.amber : theme.colorScheme.onSurfaceVariant,
                size: 40,
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (!file.isFolder && file.size != null)
                Text(
                  formatBytes(file.size!),
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
