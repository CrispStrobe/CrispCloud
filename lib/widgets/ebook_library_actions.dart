import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/ebook_strings.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/ebook_library.dart';
import '../services/file_operation_backend.dart';
import 'ebook_editor_dialog.dart';
import 'ebook_library_dialog.dart';

/// Re-resolve a saved reference against its exact account and root every time.
/// Library metadata never grants access to a file or selects a replacement
/// account merely because it has the same provider label.
Future<void> showEbookLibrary(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  EbookLibrary? library,
  String? currentEntryId,
}) async {
  final ownsLibrary = library == null;
  EbookLibrary? catalog;
  try {
    catalog = library ?? await EbookLibrary.open();
    if (!context.mounted) return;
    await catalog.reload();
    if (!context.mounted) return;
    final activeCatalog = catalog;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => EbookLibraryDialog(
        library: activeCatalog,
        currentEntryId: currentEntryId,
        translate: context.ebookTr,
        errorMessage: (error) =>
            context.ebookTr(error.toString().replaceFirst('Bad state: ', '')),
        onOpen: (entry) async {
          if (entry.id == currentEntryId) {
            Navigator.pop(dialogContext);
            return;
          }
          final source = entry.source;
          if (source == null || !source.storage.persistent) {
            throw StateError('Locate this file manually to read it again.');
          }
          final paths = source.storage.isLocal ? p.context : p.posix;
          final parent = paths.dirname(source.path);
          final panel = ref.read(panelProvider(side));
          final origin = panel.resolveStorageReference(source.storage, parent);
          if (origin == null || !origin.isCurrent) {
            throw StateError(
              'Reconnect the original account or folder to open this book.',
            );
          }
          final backend = fileOperationBackend(
            source: origin.source,
            local: ref.read(localFileServiceProvider),
            isCurrent: () => origin.isCurrent,
          );
          final file = await backend.stat(source.path);
          if (!context.mounted || !dialogContext.mounted) return;
          if (!origin.isCurrent) {
            throw StateError(
              'The original book source is no longer available.',
            );
          }
          if (file == null ||
              file.isFolder ||
              (source.objectId != null && file.uuid != source.objectId)) {
            throw StateError(
              'The original book was moved or replaced. Locate it manually.',
            );
          }
          if (!const {
            'epub',
            'mobi',
            'azw',
            'azw3',
            'fb2',
            'fbz',
            'fb2zip',
            'cbz',
          }.contains(file.extension)) {
            throw StateError(
              'This file format cannot be opened in the ebook reader.',
            );
          }
          await showDialog<void>(
            context: dialogContext,
            barrierDismissible: false,
            builder: (_) => Dialog.fullscreen(
              child: EbookEditorDialog(
                file: file.copyWith(
                  path: source.path,
                  storageId: origin.storageId,
                ),
                side: side,
                origin: origin,
              ),
            ),
          );
          await activeCatalog.reload();
        },
        onLocate: (entry) async {
          final source = entry.source;
          if (source == null || !source.storage.persistent) {
            throw StateError('Locate this file manually to read it again.');
          }
          final paths = source.storage.isLocal ? p.context : p.posix;
          final parent = paths.dirname(source.path);
          final panel = ref.read(panelProvider(side));
          final origin = panel.resolveStorageReference(source.storage, parent);
          if (origin == null || !origin.isCurrent) {
            throw StateError(
              'Reconnect the original account or folder to open this book.',
            );
          }
          await panel.navigateToPath(parent, origin: origin);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
      ),
    );
  } catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.ebookTr('Ebook library')),
          content: SelectableText(
            context.ebookTr(error.toString().replaceFirst('Bad state: ', '')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.ebookTr('Close')),
            ),
          ],
        ),
      );
    }
  } finally {
    if (ownsLibrary) catalog?.dispose();
  }
}
