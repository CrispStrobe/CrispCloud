import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_batch_integrity_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_service.dart';
import '../services/file_operation_backend.dart';
import 'archive_batch_integrity_dialog.dart';
import 'archive_batch_extraction_dialog.dart';

List<FileItem> _selection(WidgetRef ref, PanelSide side) {
  final panel = ref.read(panelProvider(side));
  return panel.selection.isNotEmpty
      ? panel.selection.toList(growable: false)
      : [if (panel.cursorItem case final file? when file.name != '..') file];
}

bool canTestArchiveSelection(WidgetRef ref) {
  final files = _selection(ref, ref.read(activePanelProvider));
  return files.isNotEmpty &&
      files.every(
        (file) =>
            !file.isFolder &&
            file.isSymlink != true &&
            ArchiveService.isArchive(file.name),
      );
}

bool canExtractArchiveSelection(WidgetRef ref) =>
    !kIsWeb && canTestArchiveSelection(ref);

Future<void> showArchiveBatchExtractionForSelection(
  BuildContext context,
  WidgetRef ref, {
  PanelSide? side,
  List<FileItem>? files,
  PanelFileOrigin? sourceOrigin,
}) async {
  if (kIsWeb) return;
  try {
    final PanelSide selectedSide = side ?? ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(selectedSide));
    final selection = List<FileItem>.unmodifiable(
      files ?? _selection(ref, selectedSide),
    );
    final origin = sourceOrigin ?? panel.captureOperationOrigin(selection);
    if (selection.isEmpty || !origin.isCurrent) {
      throw StateError(
        archiveBatchIntegrityText(
          context,
          'The captured source is no longer available.',
        ),
      );
    }
    final local = ref.read(localFileServiceProvider);
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => context.mounted && origin.isCurrent,
    );
    final captured = [
      for (final file in selection)
        file.copyWith(
          path:
              file.path ??
              backend.paths.join(origin.source.currentPath, file.name),
        ),
    ];
    final otherSide = selectedSide == PanelSide.local
        ? PanelSide.remote
        : PanelSide.local;
    final targetOrigin = ref
        .read(panelProvider(otherSide))
        .directoryPresentationOrigin;
    // Capture the suggested path now. Changing panes while the review is open
    // cannot redirect writes; the extraction plan revalidates the reviewed path.
    final target =
        targetOrigin?.isCurrent == true && targetOrigin!.source.isLocal
        ? targetOrigin.source.currentPath
        : origin.source.isLocal
        ? backend.paths.dirname(captured.first.path!)
        : await local.getSafeFallbackDirectory();
    if (!context.mounted || !origin.isCurrent) return;
    await showArchiveBatchExtractionDialog(
      context,
      source: backend,
      files: captured,
      targetDirectory: target,
      local: local,
    );
    if (context.mounted) {
      await Future.wait([
        ref.read(panelProvider(selectedSide)).refresh(),
        ref.read(panelProvider(otherSide)).refresh(),
      ]);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

/// Capture the pane and selection before presenting any asynchronous UI. Later
/// navigation cannot substitute a new account, file set or archive namespace.
Future<void> showArchiveBatchIntegrityForSelection(
  BuildContext context,
  WidgetRef ref, {
  PanelSide? side,
  List<FileItem>? files,
  PanelFileOrigin? sourceOrigin,
}) async {
  try {
    final PanelSide selectedSide = side ?? ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(selectedSide));
    final selection = List<FileItem>.unmodifiable(
      files ?? _selection(ref, selectedSide),
    );
    final origin = sourceOrigin ?? panel.captureOperationOrigin(selection);
    if (selection.isEmpty || !origin.isCurrent) {
      throw StateError(
        archiveBatchIntegrityText(
          context,
          'The captured source is no longer available.',
        ),
      );
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => context.mounted && origin.isCurrent,
    );
    final captured = [
      for (final file in selection)
        file.copyWith(
          path:
              file.path ??
              backend.paths.join(origin.source.currentPath, file.name),
        ),
    ];
    await showArchiveBatchIntegrityDialog(
      context,
      source: backend,
      files: captured,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
