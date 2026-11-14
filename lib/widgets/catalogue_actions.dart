import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../providers/providers.dart';
import '../services/catalogue_files.dart';
import '../services/local_file_service.dart';
import '../services/panel_source_service.dart';
import 'catalogue_dialog.dart';
import 'storage_analyzer_dialog.dart';

CatalogueReveal? captureCatalogueReveal(
  BuildContext context,
  ProviderContainer container,
) {
  final side = container.read(activePanelProvider);
  final panel = container.read(panelProvider(side));
  final local = container.read(localFileServiceProvider);
  try {
    final origin = panel.captureCurrentOrigin();
    if (origin.source is! LocalPanelSource) return null;
    return (String root, Map<String, dynamic> row) async {
      if (!origin.isCurrent) {
        throw StateError('The original local pane is no longer available.');
      }
      await local.withFileOperationAccess(root, () async {
        final target = await resolveCatalogueReference(
          root,
          row['relativePath'] as String,
        );
        final path = target['path'] as String;
        final directory = p.dirname(path);
        final file = FileItem(
          name: p.basename(path),
          path: path,
          isFolder: target['isFolder'] as bool,
          size: target['bytes'] as int,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (target['modified'] as int) * 1000,
            isUtc: true,
          ),
        );
        if (!origin.isCurrent) {
          throw StateError('The original local pane changed.');
        }
        await panel.navigateToPath(directory, origin: origin, selectItem: file);
        final current = panel.captureCurrentOrigin();
        if (!origin.isCurrent ||
            current.storageId != origin.storageId ||
            !p.equals(current.source.currentPath, directory) ||
            !panel.selection.any(
              (e) => e.path != null && p.equals(e.path!, path),
            )) {
          throw StateError('The local pane could not reveal the indexed file.');
        }
        if (context.mounted &&
            (target['bytes'] != row['bytes'] ||
                target['modified'] != row['mtimeUnix'])) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'The current file metadata differs from the catalogue.',
              ),
            ),
          );
        }
      });
    };
  } catch (_) {
    return null;
  }
}

Future<void> showCatalogues(BuildContext context, WidgetRef ref) =>
    showCatalogueLibrary(
      context,
      local: ref.read(localFileServiceProvider),
      onReveal: captureCatalogueReveal(
        context,
        ProviderScope.containerOf(context, listen: false),
      ),
      onSavedReports: () => showDialog<void>(
        context: context,
        builder: (_) => const StorageAnalyzerDialog(historyOnly: true),
      ),
    );
