import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/catalogue_format.dart';
import '../services/file_operation_backend.dart';
import '../services/panel_source_service.dart';
import 'catalogue_dialog.dart';
import 'catalogue_actions.dart';

/// Header routing is independent of extension-only media detection. Remote and
/// archive catalogues are streamed into owned storage before SQLite/CAF reads.
Future<bool> tryShowCatalogueFile(
  BuildContext context, {
  required FileItem file,
  required PanelSide side,
  PanelFileOrigin? origin,
  Uint8List? bytesOverride,
}) async {
  final name = file.name.toLowerCase();
  if (!const CrispCatalog().supported ||
      (!name.endsWith('.caf') && !name.endsWith('.crispindex'))) {
    return false;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final local = container.read(localFileServiceProvider);
  final captured =
      origin ?? container.read(panelProvider(side)).originForOperation(file);
  if (bytesOverride != null) {
    final format = catalogueFormat(file.name, bytesOverride.take(16).toList());
    if (format == null || !context.mounted) return false;
    await showCatalogueLibrary(
      context,
      local: local,
      onReveal: captureCatalogueReveal(context, container),
      incoming: CatalogueInput(
        name: file.name,
        format: format,
        read: () => Stream.value(bytesOverride),
        isCurrent: () => true,
      ),
    );
    return true;
  }
  if (captured == null || !captured.isCurrent) return false;
  if (captured.source is! LocalPanelSource &&
      captured.source is! RemotePanelSource) {
    return false;
  }
  final backend = fileOperationBackend(
    source: captured.source,
    local: local,
    isCurrent: () => captured.isCurrent,
  );
  final prefix = <int>[];
  final stream = StreamIterator(backend.readFile(file));
  try {
    while (prefix.length < 16 && await stream.moveNext()) {
      prefix.addAll(stream.current.take(16 - prefix.length));
    }
  } catch (_) {
    return false;
  } finally {
    await stream.cancel();
  }
  final format = catalogueFormat(file.name, prefix);
  if (format == null || !context.mounted) return false;
  if (captured.source is LocalPanelSource && file.path != null) {
    await showCatalogueLibrary(
      context,
      local: local,
      onReveal: captureCatalogueReveal(context, container),
      initialPath: file.path,
      initialFormat: format,
    );
  } else {
    Stream<List<int>> download() async* {
      if (!captured.isCurrent) {
        throw StateError('Original catalogue source is no longer available.');
      }
      final before = await backend.stat(file.path!);
      if (before == null ||
          before.isFolder ||
          (file.uuid != null && file.uuid != before.uuid)) {
        throw StateError('The catalogue changed before download.');
      }
      var received = 0;
      await for (final chunk in backend.readFile(before)) {
        if (!captured.isCurrent) {
          throw StateError('Original catalogue source changed.');
        }
        received += chunk.length;
        yield chunk;
      }
      final after = await backend.stat(file.path!);
      if (!captured.isCurrent ||
          after == null ||
          after.size != before.size ||
          after.updatedAt != before.updatedAt ||
          (before.size != null && received != before.size) ||
          [
            'etag',
            'versionId',
            'revision',
          ].any((key) => before.metadata?[key] != after.metadata?[key])) {
        throw StateError(
          'The catalogue changed during download; no catalogue was imported.',
        );
      }
    }

    await showCatalogueLibrary(
      context,
      local: local,
      onReveal: captureCatalogueReveal(context, container),
      incoming: CatalogueInput(
        name: file.name,
        format: format,
        read: download,
        isCurrent: () => captured.isCurrent,
      ),
    );
  }
  return true;
}
