import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'native_file_primitives.dart';
import 'panel_source_service.dart';
import 'rename_batch_digest.dart';
import 'rename_batch_service.dart';

class SourceRenameBatchStorage extends RenameBatchStorage {
  SourceRenameBatchStorage({
    required this.reference,
    required this.source,
    required this.local,
    required bool Function() isCurrent,
    required this.fallbackRename,
  }) : _isCurrent = isCurrent {
    _backend = fileOperationBackend(
      source: source,
      local: local,
      isCurrent: isCurrent,
    );
  }

  @override
  final StorageReference reference;
  final PanelSource source;
  final LocalFileService local;
  final bool Function() _isCurrent;
  final Future<void> Function(FileItem, String) fallbackRename;
  late final FileOperationBackend _backend;

  @override
  bool get isCurrent => _isCurrent();
  @override
  p.Context get paths => _backend.paths;
  @override
  bool get exclusiveMoves => source is LocalPanelSource
      ? !kIsWeb && supportsNativeExclusiveRename
      : source is RemotePanelSource &&
            (source as RemotePanelSource)
                .client
                .transferCapabilities
                .noReplaceMove;
  @override
  bool get caseSensitivePaths {
    if (source is RemotePanelSource) {
      return (source as RemotePanelSource)
              .client
              .transferCapabilities
              .caseSensitivity ==
          StorageCaseSensitivity.sensitive;
    }
    return _backend.pathKey('/Aa') != _backend.pathKey('/aa');
  }

  void _check() {
    if (!isCurrent) throw StateError('The captured storage account changed.');
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    final item = await _backend.stat(path);
    _check();
    return item;
  }

  Future<List<FileItem>> list(String path) async {
    _check();
    final items = await _backend.list(path);
    _check();
    return items;
  }

  @override
  Future<String?> contentDigest(FileItem item) async {
    if (source is! LocalPanelSource || kIsWeb) return null;
    return local.withFileOperationAccess(
      item.path!,
      () => nativeRenameDigest(item.path!, _check),
    );
  }

  @override
  Future<void> move(FileItem file, String destination) async {
    _check();
    if (paths.dirname(file.path!) != paths.dirname(destination)) {
      throw const FormatException(
        'Rename targets must remain in their current parent directory.',
      );
    }
    if (await stat(destination) != null) {
      throw StateError('Destination already exists: $destination');
    }
    _check();
    if (source is LocalPanelSource &&
        !kIsWeb &&
        supportsNativeExclusiveRename) {
      await local.withFileOperationAccess(file.path!, () async {
        _check();
        if (!await moveNativeNoReplace(file.path!, destination)) {
          throw UnsupportedError(
            'Exclusive rename is unavailable on this filesystem. The original item was retained.',
          );
        }
      });
    } else if (source is RemotePanelSource) {
      final client = (source as RemotePanelSource).client;
      if (client is CloudTransferOperations &&
          client.transferCapabilities.nativeMove) {
        final result = await (client as CloudTransferOperations).moveToExact(
          file.path!,
          destination,
          expectedSourceVersion:
              file.metadata?['version']?.toString() ??
              file.metadata?['eTag']?.toString() ??
              file.metadata?['etag']?.toString(),
          checkpoint: () async {
            _check();
          },
        );
        if (paths.normalize(result.path) != paths.normalize(destination)) {
          throw StateError(
            'The provider returned an unexpected rename destination: ${result.path}',
          );
        }
      } else {
        await fallbackRename(file, paths.basename(destination));
      }
    } else {
      await fallbackRename(file, paths.basename(destination));
    }
    _check();
  }
}
