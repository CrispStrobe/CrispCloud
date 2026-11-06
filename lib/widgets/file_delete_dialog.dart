import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/file_delete_strings.dart';
import '../l10n/provider_operation_strings.dart';
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
  try {
    files = await panel.prepareOperationFiles(files);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedProviderError(context, error))),
      );
    }
    return;
  }
  if (!context.mounted) return;
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
        final strings = FileDeleteStrings(context);
        final l =
            AppLocalizations.of(context) ??
            lookupAppLocalizations(const Locale('en'));
        return AlertDialog(
          title: Text(
            strings.text(permanent ? 'permanentTitle' : 'trashTitle'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.count('selected', files.length)),
              const SizedBox(height: 12),
              if (canTrash)
                CheckboxListTile(
                  value: permanent,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => permanent = value ?? false),
                  title: Text(strings.text('permanent')),
                  subtitle: Text(strings.text('skipTrash')),
                  contentPadding: EdgeInsets.zero,
                ),
              Text(strings.text(permanent ? 'permanentHelp' : 'trashHelp')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(l.cancel),
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
                      if (deletedCount > 0) {
                        deletionId = ref
                            .read(actionHistoryProvider)
                            .lastAction
                            ?.id;
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
              child: Text(
                busy
                    ? strings.text('working')
                    : permanent
                    ? l.delete
                    : strings.text('trashTitle'),
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
        content: Text(
          FileDeleteStrings(context).count('deleted', deletedCount),
        ),
        action: SnackBarAction(
          label: FileDeleteStrings(context).text('undo'),
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
