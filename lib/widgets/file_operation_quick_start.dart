// Commander-style copy/move without a blocking options dialog.
//
// Total Commander and Double Commander confirm F5/F6 with a one-line target
// box and then hand the work to a background queue; the screen stays free.
// The full option dialog remains one keystroke away ("Options…", and the
// cases below that need its review, e.g. archives or mixed-account sources).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/error_provider.dart';
import '../providers/panel_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_options.dart';
import '../services/file_operation_profiles.dart';
import '../services/file_operation_service.dart';
import 'file_operation_conflict_dialog.dart';
import 'file_operation_dialog.dart';

PanelSide _opposite(PanelSide side) =>
    side == PanelSide.local ? PanelSide.remote : PanelSide.local;

/// Plans and queues a copy/move with the saved default options, without any
/// dialog. Progress shows in the status bar; an overwrite question appears
/// only when a conflict actually occurs. Cases that need the full review
/// (archives, several source accounts, an invalid plan) open the full dialog
/// instead, so nothing is ever silently dropped.
///
/// [onSettled] runs once the queued transfer has finished, failed or been
/// cancelled — or right away when the full dialog took over and closed.
Future<void> startFileOperationDirect(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required FileOperationKind kind,
  PanelFileOrigin? sourceOrigin,
  Map<PanelFileOrigin, List<FileItem>>? sourceGroups,
  PanelFileOrigin? destinationOrigin,
  String? destinationPath,
  Future<void> Function()? onSettled,
}) async {
  if (files.isEmpty) return;
  final errors = ref.read(errorProvider);
  final verb = kind == FileOperationKind.copy ? 'Copy' : 'Move';

  Future<void> fullDialog() async {
    await showFileOperationDialog(
      context,
      ref,
      side,
      files,
      kind: kind,
      sourceOrigin: sourceOrigin,
      sourceGroups: sourceGroups,
      destinationOrigin: destinationOrigin,
      destinationPath: destinationPath,
    );
    await onSettled?.call();
  }

  final sourcePanel = ref.read(panelProvider(side));
  final targetSide = _opposite(side);
  final targetPanel = ref.read(panelProvider(targetSide));
  // Archive endpoints own their own container review.
  if ((destinationOrigin == null && targetPanel.isInArchive) ||
      (sourceOrigin == null &&
          sourceGroups == null &&
          sourcePanel.isInArchive)) {
    return await fullDialog();
  }

  try {
    var groups = sourceGroups;
    if (groups == null && sourceOrigin == null) {
      files = await sourcePanel.prepareOperationFiles(files);
      groups = sourcePanel.captureOperationGroups(files);
    }
    if (groups != null && groups.length > 1) return await fullDialog();
    final origin =
        sourceOrigin ??
        groups?.keys.firstOrNull ??
        sourcePanel.captureOperationOrigin(files);
    if (groups != null) files = groups.values.first;

    final PanelFileOrigin destination;
    try {
      destination = destinationOrigin ?? targetPanel.captureCurrentOrigin();
    } catch (_) {
      // No verified destination in the other pane: let the dialog ask.
      return await fullDialog();
    }
    final local = ref.read(localFileServiceProvider);
    final sourceBackend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final destinationBackend = fileOperationBackend(
      source: destination.source,
      local: local,
      isCurrent: () => destination.isCurrent,
    );

    var options = FileOperationOptions(kind: kind);
    try {
      final saved = (await FileOperationProfiles()
          .load())['@default:${kind.name}'];
      if (saved != null && saved.kind == kind) options = saved;
    } catch (_) {
      // Unreadable defaults fall back to the built-in safe defaults.
    }

    final control = FileOperationControl();
    final plan = await const FileOperationService().prepare(
      files: files,
      source: sourceBackend,
      destination: destinationBackend,
      targetDirectory: destinationPath ?? destination.source.currentPath,
      control: control,
      options: options,
    );
    if (!context.mounted) return;
    if (!plan.canExecute) return await fullDialog();

    final rememberSelection = sourcePanel.captureSelectionMemoryForOperation(
      files,
    );
    final run = ref
        .read(transferProvider)
        .runFileOperation(
          plan,
          control: control,
          resolveDetailedConflict: (entry, existing) {
            if (!context.mounted) {
              return Future.value(
                const FileConflictResolution(FileConflictDecision.cancel),
              );
            }
            return showFileOperationConflict(
              context,
              entry: entry,
              existing: existing,
              source: plan.source,
              destination: plan.destination,
              copyMethod: plan.options.copyMethod,
            );
          },
          onQueued: () {
            if (plan.source.isCurrent && plan.destination.isCurrent) {
              rememberSelection?.call();
            }
          },
          onEntryComplete: (entry) {
            if (entry.outcome == FileOperationOutcome.moved) {
              unawaited(
                sourcePanel.applyFileListChanges({
                  entry.source.path!: null,
                }, origin: origin),
              );
            }
          },
        );
    unawaited(
      run
          .then((_) async {
            final failed = plan.entries.where((e) => e.failed).length;
            if (failed > 0) {
              errors.addError('$verb: $failed item(s) need review.');
            }
          })
          .catchError((Object error) {
            errors.addError('$verb failed: $error', cause: error);
          })
          .whenComplete(() async {
            try {
              // Paste may land in either pane; refresh both.
              for (final pane in PanelSide.values) {
                await ref.read(panelProvider(pane)).refresh();
              }
            } catch (_) {
              // A pane closed meanwhile; nothing to refresh.
            }
            await onSettled?.call();
          }),
    );
  } catch (error) {
    errors.addError('$verb failed: $error', cause: error);
  }
}

enum _QuickChoice { start, options }

/// F5/F6: a one-line target box (Enter starts, "Options…" opens the full
/// dialog). It closes as soon as the transfer is queued.
Future<void> showQuickFileOperation(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  required FileOperationKind kind,
}) async {
  if (files.isEmpty) return;
  final targetPanel = ref.read(panelProvider(_opposite(side)));
  final sourcePanel = ref.read(panelProvider(side));
  String target;
  try {
    if (targetPanel.isInArchive || sourcePanel.isInArchive) {
      throw StateError('archive');
    }
    target = targetPanel.captureCurrentOrigin().source.currentPath;
  } catch (_) {
    // Archives and unverified destinations need the full review.
    await showFileOperationDialog(context, ref, side, files, kind: kind);
    return;
  }
  final controller = TextEditingController(text: target)
    ..selection = TextSelection(baseOffset: 0, extentOffset: target.length);
  final label = kind == FileOperationKind.copy ? 'Copy' : 'Move';
  final focusBefore = FocusManager.instance.primaryFocus;
  final choice = await showDialog<_QuickChoice>(
    context: context,
    builder: (dialogContext) {
      void submit() => Navigator.pop(dialogContext, _QuickChoice.start);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              Navigator.pop(dialogContext, _QuickChoice.options),
        },
        child: AlertDialog(
          title: Text(
            dialogContext.commanderTr('{0} {1} item(s) to:', [
              dialogContext.commanderTr(label),
              files.length,
            ]),
          ),
          content: SizedBox(
            width: 520,
            child: TextField(
              key: const ValueKey('quick-transfer-target'),
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('quick-transfer-options'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _QuickChoice.options),
              child: Text('${dialogContext.commanderTr('Options…')} (F2)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.commanderTr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('quick-transfer-start'),
              onPressed: submit,
              child: Text(dialogContext.commanderTr(label)),
            ),
          ],
        ),
      );
    },
  );
  final edited = controller.text.trim();
  controller.dispose();
  if (focusBefore != null && focusBefore.context != null) {
    focusBefore.requestFocus();
  }
  if (choice == null || !context.mounted) return;
  final destinationPath = edited.isEmpty || edited == target ? null : edited;
  if (choice == _QuickChoice.options) {
    await showFileOperationDialog(
      context,
      ref,
      side,
      files,
      kind: kind,
      destinationPath: destinationPath,
    );
    return;
  }
  await startFileOperationDirect(
    context,
    ref,
    side,
    files,
    kind: kind,
    destinationPath: destinationPath,
  );
}
