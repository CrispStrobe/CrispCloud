import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<FileItem> files, {
  bool permanent = false,
}) async {
  if (files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(FileDeleteStrings(context).text('noFiles'))),
    );
    return;
  }
  final panel = ref.read(panelProvider(side));
  late final bool networkTarget;
  try {
    files = await panel.prepareOperationFiles(files);
    networkTarget = await panel.hasNetworkTrashTarget(files);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedProviderError(context, error))),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final canTrash = !networkTarget && panel.canTrashFiles(files);
  final focusConfirm = permanent || canTrash;
  var busy = false;
  var deletedCount = 0;
  String? deletionId;
  Object? deleteError;
  var deletedPermanently = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final strings = FileDeleteStrings(context);
        final l =
            AppLocalizations.of(context) ??
            lookupAppLocalizations(const Locale('en'));
        void dismiss() {
          if (!busy) Navigator.pop(context);
        }

        final dialog = AlertDialog(
          title: Text(
            strings.text(permanent ? 'permanentTitle' : 'trashTitle'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.count('selected', files.length)),
              if (files.length == 1)
                Text(
                  files.single.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: permanent,
                onChanged: busy
                    ? null
                    : (value) => setState(() => permanent = value ?? false),
                title: Text(strings.text('permanent')),
                subtitle: Text(strings.text('skipTrash')),
                contentPadding: EdgeInsets.zero,
              ),
              Text(
                strings.text(
                  permanent
                      ? 'permanentHelp'
                      : canTrash
                      ? 'trashHelp'
                      : networkTarget
                      ? 'trashNetwork'
                      : 'trashUnavailable',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: !focusConfirm,
              onPressed: busy ? null : dismiss,
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('file-delete-confirm'),
              autofocus: focusConfirm,
              onPressed: busy || (!canTrash && !permanent)
                  ? null
                  : () async {
                      setState(() => busy = true);
                      deletedPermanently = permanent;
                      deletedCount = await panel.deleteFiles(
                        files,
                        permanently: permanent,
                        onError: (error) => deleteError = error,
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
                    ? strings.text('permanent')
                    : strings.text('trashTitle'),
              ),
            ),
          ],
        );
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): dismiss},
          child: PopScope(canPop: !busy, child: dialog),
        );
      },
    ),
  );
  if (!context.mounted) return;
  final strings = FileDeleteStrings(context);
  if (deleteError case final error?) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_deleteErrorMessage(context, error))),
    );
  }
  if (deletedCount > 0 && deletedPermanently) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.count('permanentlyDeleted', deletedCount)),
      ),
    );
  }
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

String _deleteErrorMessage(BuildContext context, Object error) {
  final strings = FileDeleteStrings(context);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final code = switch (error) {
      FileSystemException(:final osError) => osError?.errorCode,
      PlatformException(code: 'trash_failed', details: final int status)
          when status & 0xffff0000 == 0x80070000 =>
        status & 0xffff,
      _ => null,
    };
    switch (code) {
      case 32 || 33:
        return strings.text('fileInUse');
      case 5:
        return strings.text('accessDenied');
      case 2 || 3:
        return strings.text('fileMissing');
    }
  }
  return switch (error) {
    PlatformException(code: 'trash_failed') => strings.text('trashFailed'),
    PlatformException(code: 'trash_unsupported') => strings.text(
      'trashUnavailable',
    ),
    _ => localizedProviderError(context, error),
  };
}
