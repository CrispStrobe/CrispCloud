import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/provider_operation_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/providers.dart';
import '../providers/office_conversion_provider.dart';
import '../services/captured_file_target.dart';
import '../services/file_bytes_loader.dart';
import '../services/file_operation_backend.dart';
import '../services/legacy_word_copy_target.dart';
import '../services/panel_source_service.dart';
import 'legacy_word_conversion_dialog.dart';
import 'internal_viewer_dialog.dart';
import 'office_editor_dialog.dart';

/// Converts a verified legacy document into a separate file. Native conversion
/// opens that exact package for viewing; editing is an explicit subsequent
/// action. Pane changes cannot redirect either write.
Future<void> showLegacyWordConversionForFile(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  PanelFileOrigin? origin,
}) async {
  try {
    final captured =
        origin ?? ref.read(panelProvider(side)).originForOperation(file);
    if (file.isFolder || captured == null || !captured.isCurrent) {
      throw const FileTargetConflict(
        'Refresh or reopen the original file before converting it.',
      );
    }
    final local = ref.read(localFileServiceProvider);
    final cache = ref.read(fileCacheProvider);
    final backend = fileOperationBackend(
      source: captured.source,
      local: local,
      isCurrent: () => captured.isCurrent,
    );
    final sourcePath =
        file.path ?? backend.paths.join(captured.source.currentPath, file.name);
    final destination = LegacyWordCopyTarget(
      backend: backend,
      sourcePath: sourcePath,
    );
    final bytes = await loadFileBytes(
      ref,
      file,
      side,
      capBytes: 64 * 1024 * 1024,
      origin: captured,
    );
    if (!context.mounted) return;
    FileItem? created;
    final copy = await showLegacyWordConversionDialog(
      context,
      sourceName: file.name,
      bytes: bytes,
      discover: ref.read(installedOfficeDiscoveryProvider),
      convert: ref.read(installedOfficeConversionProvider),
      onPreviewPdf: (pdf, name) async {
        if (!context.mounted) return;
        await showInternalViewer(
          context,
          file: FileItem(name: name, isFolder: false, size: pdf.length),
          side: side,
          bytesOverride: pdf,
          displayName: name,
        );
      },
      onSave: (copy) async {
        created = await destination.create(copy);
      },
      describeSaveError: (error) => localizedProviderError(context, error),
    );
    if (!context.mounted || copy == null || created == null) return;
    final newFile = created!;
    final reference = FileReference(
      storage: captured.storageReference,
      path: newFile.path!,
      objectId: newFile.uuid,
    );
    final source = captured.source;
    final CapturedFileTarget target;
    if (source is LocalPanelSource) {
      target = CapturedFileTarget.local(
        reference: reference,
        service: local,
        file: newFile,
        isCurrent: () => captured.isCurrent,
      );
    } else if (source is RemotePanelSource) {
      target = CapturedFileTarget.remote(
        reference: reference,
        client: source.client,
        cache: cache,
        file: newFile,
        isCurrent: () => captured.isCurrent,
      );
    } else {
      throw const FileTargetConflict('Extract this file before converting it.');
    }
    await ref.read(panelProvider(side)).refresh();
    if (!context.mounted) return;
    if (!copy.isTextOnly) {
      final action = await showInternalViewer(
        context,
        file: newFile,
        side: side,
        origin: captured,
      );
      if (!context.mounted || action != InternalViewerAction.edit) return;
    }
    await showOfficeEditorDialog(
      context,
      ref,
      newFile,
      side,
      targetOverride: target,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedProviderError(context, error))),
      );
    }
  }
}
