import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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
    await ref
        .read(fileClipboardProvider)
        .capture(
          panel,
          files,
          ref.read(nativeFileOperationsProvider),
          cut: cut,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${files.length} item(s) ${cut ? 'cut' : 'copied'}. Open the destination and paste.',
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
    final destination = panel.captureCurrentOrigin();
    final clipboard = ref.read(fileClipboardProvider);
    final native = ref.read(nativeFileOperationsProvider);
    final internal = await clipboard.stillOwnsClipboard(native)
        ? clipboard.selection
        : null;
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
    await showFileOperationDialog(
      context,
      ref,
      internal?.side ?? side,
      files,
      kind: cut ? FileOperationKind.move : FileOperationKind.copy,
      sourceOrigin: source,
      sourceGroups: internal?.groups,
      destinationOrigin: destination,
      destinationPath: destination.source.currentPath,
    );
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
      if (!remaining) clipboard.clear();
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
