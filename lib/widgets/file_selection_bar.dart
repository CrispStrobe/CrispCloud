// widgets/file_selection_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart' show formatBytes;
import 'file_context_menu.dart' show showCopyDialog, showMoveDialog, confirmDelete;

class FileSelectionBar extends ConsumerWidget {
  final PanelSide side;
  final Set<FileItem> selection;

  const FileSelectionBar({
    super.key,
    required this.side,
    required this.selection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.read(panelProvider(side));
    final auth = ref.watch(authProvider);
    final transfers = ref.read(transferProvider);

    final totalSize = selection.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
    final files = selection.toList();
    final theme = Theme.of(context);

    Widget responsiveButton({
      required IconData icon,
      required String label,
      required String tooltip,
      required VoidCallback onPressed,
      required bool showLabel,
    }) {
      if (showLabel) {
        return TextButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSecondaryContainer),
        );
      } else {
        return IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          color: theme.colorScheme.onSecondaryContainer,
          onPressed: onPressed,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.secondaryContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool showLabels = MediaQuery.of(context).size.width > 600;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('${selection.length} selected',
                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSecondaryContainer)),
                if (totalSize > 0) ...[
                  const SizedBox(width: 8),
                  Text('• ${formatBytes(totalSize)}',
                      style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
                ],
                const SizedBox(width: 16),

                if (side == PanelSide.local && auth.isConnected)
                  responsiveButton(
                    icon: Icons.upload, label: 'Upload', tooltip: 'Upload', showLabel: showLabels,
                    onPressed: () => transfers.uploadFiles(files),
                  ),

                if (side == PanelSide.remote)
                  responsiveButton(
                    icon: Icons.download, label: 'Download', tooltip: 'Download', showLabel: showLabels,
                    onPressed: () => transfers.downloadFiles(files),
                  ),

                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.content_copy, size: 20),
                  tooltip: 'Copy to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showCopyDialog(context, ref, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move, size: 20),
                  tooltip: 'Move to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showMoveDialog(context, ref, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'Delete',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => confirmDelete(context, ref, side, files),
                ),

                const SizedBox(width: 16),
                responsiveButton(
                  icon: Icons.clear, label: 'Clear', tooltip: 'Clear selection', showLabel: showLabels,
                  onPressed: () => panel.clearSelection(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
