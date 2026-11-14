import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/csv_spreadsheet_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/providers.dart';
import '../services/captured_file_target.dart';
import '../services/csv_spreadsheet_import.dart';
import '../services/file_bytes_loader.dart';
import '../services/file_operation_backend.dart';
import '../services/panel_source_service.dart';
import 'csv_spreadsheet_import_dialog.dart';
import 'office_editor_dialog.dart';

Future<void> showCsvSpreadsheetImportForFile(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  PanelFileOrigin? origin,
  String? textOverride,
}) async {
  try {
    final captured =
        origin ?? ref.read(panelProvider(side)).originForOperation(file);
    if (captured == null || !captured.isCurrent || file.isFolder) {
      throw const FileTargetConflict(
        'Reopen the original CSV file before importing.',
      );
    }
    if (captured.source is! LocalPanelSource &&
        captured.source is! RemotePanelSource) {
      throw const FileTargetConflict(
        'Extract this CSV file before importing it as a spreadsheet.',
      );
    }
    final local = ref.read(localFileServiceProvider);
    final backend = fileOperationBackend(
      source: captured.source,
      local: local,
      isCurrent: () => captured.isCurrent,
    );
    final sourcePath =
        file.path ?? backend.paths.join(captured.source.currentPath, file.name);
    final sourceBytes = textOverride == null
        ? await loadFileBytes(
            ref,
            file,
            side,
            origin: captured,
            capBytes: csvSpreadsheetInputLimit,
          )
        : null;
    if (!context.mounted) return;
    FileItem? created;
    final accepted = await showCsvSpreadsheetImportDialog(
      context,
      sourceName: file.name,
      text: textOverride ?? '',
      sourceBytes: sourceBytes,
      onCreate: (name, bytes) async {
        created = await createSpreadsheetCopy(
          backend: backend,
          sourcePath: sourcePath,
          name: name,
          bytes: bytes,
        );
      },
    );
    if (!context.mounted || accepted != true || created == null) return;
    final output = created!;
    final reference = FileReference(
      storage: captured.storageReference,
      path: output.path!,
      objectId: output.uuid,
    );
    final source = captured.source;
    final target = source is LocalPanelSource
        ? CapturedFileTarget.local(
            reference: reference,
            service: local,
            file: output,
            isCurrent: () => captured.isCurrent,
          )
        : CapturedFileTarget.remote(
            reference: reference,
            client: (source as RemotePanelSource).client,
            cache: ref.read(fileCacheProvider),
            file: output,
            isCurrent: () => captured.isCurrent,
          );
    await ref.read(panelProvider(side)).refresh();
    if (!context.mounted) return;
    await showOfficeEditorDialog(
      context,
      ref,
      output,
      side,
      targetOverride: target,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CsvSpreadsheetStrings(context).failure(error))),
      );
    }
  }
}
