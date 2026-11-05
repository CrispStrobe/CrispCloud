import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/action_history_provider.dart';
import '../providers/panel_provider.dart';

Future<void> showFileDeleteDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) async {
  if (files.isEmpty) return;
  final panel = ref.read(panelProvider(side));
  final canTrash = panel.canTrashFiles(files);
  var permanent = !canTrash;
  var busy = false;
  var deletedCount = 0;
  String? deletionId;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(permanent ? 'Delete without restore' : 'Move to trash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${files.length} selected item(s)'),
              const SizedBox(height: 12),
              if (canTrash)
                CheckboxListTile(
                  value: permanent,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => permanent = value ?? false),
                  title: const Text('Delete permanently'),
                  subtitle: const Text('Bypass trash and disable Undo.'),
                  contentPadding: EdgeInsets.zero,
                ),
              Text(
                permanent
                    ? 'CrispCloud cannot restore this deletion. The provider may retain its own versions or trash.'
                    : 'Files go to the system or provider trash. Undo restores them if their original paths remain available.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      deletedCount = await panel.deleteFiles(
                        files,
                        permanently: permanent,
                      );
                      if (deletedCount > 0)
                        deletionId = ref
                            .read(actionHistoryProvider)
                            .lastAction
                            ?.id;
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
              child: Text(
                busy
                    ? 'Working…'
                    : permanent
                    ? 'Delete'
                    : 'Move to trash',
              ),
            ),
          ],
        );
      },
    ),
  );
  if (!context.mounted) return;
  final history = ref.read(actionHistoryProvider);
  final action = history.lastAction;
  if (deletedCount > 0 &&
      action != null &&
      action.id == deletionId &&
      action.type == ActionType.delete &&
      history.canUndo(action)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$deletedCount item(s) moved to trash.'),
        action: SnackBarAction(
          label: 'Undo last',
          onPressed: () async {
            final result = await ref
                .read(actionHistoryProvider)
                .undo(action.id, const UndoContext());
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result.message)));
            }
          },
        ),
      ),
    );
  }
}
