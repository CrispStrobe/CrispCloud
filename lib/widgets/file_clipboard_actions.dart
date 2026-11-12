import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_endpoint_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/file_clipboard_provider.dart';
import '../providers/native_file_operations_provider.dart';
import '../providers/panel_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/native_file_operations.dart';
import 'file_operation_dialog.dart';
import 'archive_endpoint_actions.dart';

Future<void> copyFilesToClipboard(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  bool cut = false,
  List<FileItem>? items,
}) async {
  try {
    final panel = ref.read(panelProvider(side));
    final files =
        items ??
        (panel.selection.isNotEmpty
            ? panel.selection.toList()
            : [
                if (panel.cursorItem != null && panel.cursorItem!.name != '..')
                  panel.cursorItem!,
              ]);
    if (files.isEmpty) return;
    final prepared = await panel.prepareOperationFiles(files);
    if (!context.mounted) return;
    await ref
        .read(fileClipboardProvider)
        .capture(
          panel,
          prepared,
          ref.read(nativeFileOperationsProvider),
          cut: cut,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${prepared.length} item(s) ${cut ? 'cut' : 'copied'}. Open the destination and paste.',
          ),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

Future<void> pasteFilesFromClipboard(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  try {
    final panel = ref.read(panelProvider(side));
    final archiveDestination = panel.isInArchive
        ? CapturedArchiveImportDestination.capture(ref, side)
        : null;
    final destination = archiveDestination == null
        ? panel.captureCurrentOrigin()
        : null;
    final clipboard = ref.read(fileClipboardProvider);
    final native = ref.read(nativeFileOperationsProvider);
    final capturedSelection = clipboard.selection;
    final changedClipboardMessage = archiveEndpointText(
      context,
      'clipboardChanged',
    );
    final ownsClipboard = await clipboard.stillOwnsClipboard(native);
    if (!identical(clipboard.selection, capturedSelection)) {
      throw StateError(changedClipboardMessage);
    }
    final internal = ownsClipboard ? capturedSelection : null;
    late final PanelFileOrigin source;
    late final List<FileItem> files;
    late final bool cut;
    if (internal != null) {
      if (!internal.isCurrent) {
        throw StateError(
          'Reconnect and copy the original files again before pasting.',
        );
      }
      source = internal.origin;
      files = internal.files;
      cut = internal.cut;
    } else {
      if (!NativeFileOperations.supported) {
        throw StateError('Copy files inside CrispCloud before pasting here.');
      }
      final external = await native.readClipboard();
      if (!identical(clipboard.selection, capturedSelection)) {
        throw StateError(changedClipboardMessage);
      }
      if (external == null || external.paths.isEmpty) {
        throw StateError('The clipboard contains no files.');
      }
      source = panel.captureLocalClipboardOrigin(
        p.dirname(external.paths.first),
      );
      final backend = fileOperationBackend(
        source: source.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: () => source.isCurrent,
      );
      files = [];
      final seen = <String>{};
      for (final raw in external.paths) {
        final path = p.normalize(raw);
        if (!p.isAbsolute(path) || p.dirname(path) == path) {
          throw StateError('Clipboard filesystem roots are not supported.');
        }
        if (!seen.add(path)) continue;
        final file = await backend.stat(path);
        if (file == null) throw StateError('Clipboard item is missing: $path');
        files.add(file);
      }
      cut = external.cut;
    }
    if (!context.mounted) return;
    if (archiveDestination != null) {
      final result = await showCapturedArchiveImport(
        context,
        ref,
        sourceSide: internal?.side ?? side,
        files: files,
        destination: archiveDestination,
        sourceOrigin: source,
        sourceGroups: internal?.groups,
        moveSources: cut,
      );
      // Cancellation cannot consume a cut selection merely because another
      // actor removed its source. Partial publication/removal remains retryable.
      if (result == null ||
          cut &&
              (result.retainedSources.isNotEmpty ||
                  result.removedSources != files.length)) {
        return;
      }
    } else {
      await showFileOperationDialog(
        context,
        ref,
        internal?.side ?? side,
        files,
        kind: cut ? FileOperationKind.move : FileOperationKind.copy,
        sourceOrigin: source,
        sourceGroups: internal?.groups,
        destinationOrigin: destination!,
        destinationPath: destination.source.currentPath,
      );
    }
    // A cut selection is kept until the source is consumed; a cancelled or
    // partial transfer must remain available for retry.
    if (cut && internal != null && internal.isCurrent) {
      var remaining = false;
      for (final group in internal.groups.entries) {
        final backend = fileOperationBackend(
          source: group.key.source,
          local: ref.read(localFileServiceProvider),
          isCurrent: () => group.key.isCurrent,
        );
        for (final file in group.value) {
          if (await backend.stat(file.path!) != null) {
            remaining = true;
            break;
          }
        }
        if (remaining) break;
      }
      if (!remaining && identical(clipboard.selection, internal)) {
        clipboard.clear();
      }
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
