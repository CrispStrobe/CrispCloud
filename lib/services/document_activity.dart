import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/providers.dart';
import 'document_history.dart';
import 'file_operation_backend.dart';
import 'panel_source_service.dart';

class DocumentActivity {
  DocumentActivity(this.history, this.file);
  final DocumentHistory history;
  final FileReference file;
  void opened() => unawaited(history.record(file, edited: false));
  void edited() => unawaited(history.record(file, edited: true));
  void editedSibling(String name) {
    final paths = file.storage.isLocal ? p.context : p.posix;
    if (paths.basename(name) != name || name == '.' || name == '..') return;
    unawaited(
      history.record(
        FileReference(
          storage: file.storage,
          path: paths.join(paths.dirname(file.path), name),
        ),
        edited: true,
      ),
    );
  }
}

DocumentActivity? captureDocumentActivity(
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) {
  try {
    final origin = ref.read(panelProvider(side)).originForOperation(file);
    if (origin == null ||
        !origin.isCurrent ||
        (origin.source is! LocalPanelSource &&
            origin.source is! RemotePanelSource))
      return null;
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final path =
        file.path ?? backend.paths.join(origin.source.currentPath, file.name);
    return DocumentActivity(
      ref.read(documentHistoryProvider),
      FileReference(storage: origin.storageReference, path: path),
    );
  } catch (_) {
    return null;
  } // transient attachments and unverified origins have no reopenable history target
}
