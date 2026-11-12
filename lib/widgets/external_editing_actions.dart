import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/external_editing_strings.dart';
import '../models/external_edit_session.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/core_providers.dart';
import '../providers/external_remote_editing_provider.dart';
import '../providers/panel_provider.dart';
import '../services/command_entry_service.dart';
import '../services/panel_source_service.dart';
import 'external_editing_dialog.dart';

/// Captures one verified remote row before opening a menu or awaiting a dialog.
/// Navigation invalidates the initial review, while an already launched editor
/// remains bound to its original account independently of the visible pane.
ExternalEditSource captureExternalEditingSource(
  WidgetRef ref,
  PanelSide side,
  FileItem file, {
  bool Function()? isReviewCurrent,
}) {
  final panel = ref.read(panelProvider(side));
  final origin = panel.captureOperationOrigin([file]);
  final source = origin.source;
  if (source is! RemotePanelSource || file.path == null) {
    throw const ExternalEditException(ExternalEditFailure.unsupported);
  }
  final session = panel.captureOperationSession();
  final navigation = panel.navigationIntentRevision;
  var unavailable = false;
  bool available() {
    if (!unavailable) unavailable = !origin.isCurrent;
    return !unavailable;
  }

  var expiredReview = false;
  bool reviewCurrent() {
    if (!expiredReview) {
      expiredReview =
          !ref.context.mounted ||
          !available() ||
          !session() ||
          panel.navigationIntentRevision != navigation ||
          !(isReviewCurrent?.call() ?? true);
    }
    return !expiredReview;
  }

  final captured = ExternalEditSource(
    reference: FileReference(
      storage: origin.storageReference,
      path: file.path!,
      objectId: file.uuid,
    ),
    file: file,
    client: source.client,
    isCurrent: available,
    isReviewCurrent: reviewCurrent,
  );
  captured.check(review: true);
  return captured;
}

ExternalEditSource captureExternalEditingSelection(WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final files = panel.selection.isNotEmpty
      ? panel.selection.toList(growable: false)
      : [if (panel.cursorItem case final file? when file.name != '..') file];
  if (files.length != 1) {
    throw const ExternalEditException(ExternalEditFailure.invalid);
  }
  return captureExternalEditingSource(ref, side, files.single);
}

Future<void> showExternalEditingForSelection(
  BuildContext context,
  WidgetRef ref,
) async {
  ExternalEditSource? source;
  Object? error;
  try {
    source = captureExternalEditingSelection(ref);
  } catch (caught) {
    error = caught is ExternalEditException
        ? caught
        : const ExternalEditException(ExternalEditFailure.sourceChanged);
  }
  await showExternalEditingDialog(
    context,
    service: ref.read(externalRemoteEditingServiceProvider),
    source: source,
    initialError: error,
  );
}

Future<void> showExternalEditingSessions(BuildContext context, WidgetRef ref) =>
    showExternalEditingDialog(
      context,
      service: ref.read(externalRemoteEditingServiceProvider),
    );

/// The popup owns only the initial review. It never acquires authority to save
/// a remote file; explicit review and consent remain inside the editor dialog.
class ExternalEditingMenuAction {
  ExternalEditingMenuAction._(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;
  late final ExternalEditSource _source;
  bool _handedOff = false, _reviewOpen = true;

  static ExternalEditingMenuAction? capture(
    BuildContext context,
    WidgetRef ref,
    PanelSide side,
    List<FileItem> files,
  ) {
    if (const NativeCommandEntryHost().platform == null || files.length != 1) {
      return null;
    }
    final action = ExternalEditingMenuAction._(context, ref);
    try {
      action._source = captureExternalEditingSource(
        ref,
        side,
        files.single,
        isReviewCurrent: () => action._reviewOpen,
      );
      return action;
    } catch (_) {
      return null;
    }
  }

  PopupMenuItem<void> buildItem() => PopupMenuItem<void>(
    child: Row(
      children: [
        const Icon(Icons.edit_note, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(ExternalEditingStrings(context).text('openAction')),
        ),
      ],
    ),
    onTap: () {
      _handedOff = true;
      unawaited(
        Future<void>.delayed(Duration.zero, () async {
          try {
            if (!context.mounted) return;
            await showExternalEditingDialog(
              context,
              service: ref.read(externalRemoteEditingServiceProvider),
              source: _source,
            );
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ExternalEditingStrings(context).failure(error)),
                ),
              );
            }
          } finally {
            _reviewOpen = false;
          }
        }),
      );
    },
  );

  void menuClosed() {
    if (!_handedOff) _reviewOpen = false;
  }
}
