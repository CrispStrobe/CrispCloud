import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/rename_batch.dart';
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
    this.fallbackRename,
    this.isCancelled,
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
  final Future<void> Function(FileItem, String)? fallbackRename;
  final bool Function()? isCancelled;
  late final FileOperationBackend _backend;

  @override
  bool get isCurrent => _isCurrent();
  @override
  p.Context get paths => _backend.paths;
  @override
  bool get exclusiveMoves => source is LocalPanelSource
      ? !kIsWeb && supportsNativeExclusiveRename
      : source is RemotePanelSource &&
            ((source as RemotePanelSource)
                    .client
                    .transferCapabilities
                    .noReplaceMove ||
                _supportsConditionalObjectRename);
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
    if (isCancelled?.call() == true) {
      throw StateError(
        'Rename cancelled. Review rename history for completed steps.',
      );
    }
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

  bool get _isObjectStorage =>
      source is RemotePanelSource &&
      (source as RemotePanelSource).client is ObjectStorageNamespace;

  bool get _supportsConditionalObjectRename {
    if (!_isObjectStorage) return false;
    final client = (source as RemotePanelSource).client;
    final capabilities = client.transferCapabilities;
    return client is CloudTransferOperations &&
        capabilities.nativeCopy &&
        capabilities.noReplaceCopy &&
        capabilities.conditionalCopy &&
        capabilities.conditionalDelete;
  }

  @override
  String? renameProblem(FileItem item) {
    if (kIsWeb && source is LocalPanelSource && item.isFolder) {
      return 'This browser cannot rename local folders. Use a native desktop window.';
    }
    if (!_isObjectStorage) return null;
    if (item.isFolder) {
      return 'This folder is an object-key prefix. Use a recursive move to rename its contents; a single directory rename is unavailable.';
    }
    if (!_supportsConditionalObjectRename) {
      return 'This object-storage connection does not provide exclusive copy and version-conditional deletion. Batch rename cannot safely delete the original.';
    }
    final version = RenameFingerprint.fromFile(item).version;
    if (version == null || version.isEmpty) {
      return 'The object has no captured version. Refresh its metadata before renaming.';
    }
    return null;
  }

  @override
  Future<void> moveWithJournal(
    FileItem source,
    String destination, {
    RenameFingerprint? copied,
    required Future<void> Function(RenameFingerprint) onCopied,
  }) async {
    if (!_isObjectStorage) {
      if (copied != null) {
        throw StateError('The original conditional-copy capability changed.');
      }
      await move(source, destination);
      return;
    }
    _check();
    final problem = renameProblem(source);
    if (problem != null) throw UnsupportedError(problem);
    if (paths.dirname(source.path!) != paths.dirname(destination)) {
      throw const FormatException(
        'Rename targets must remain in their current parent directory.',
      );
    }
    final expected = RenameFingerprint.fromFile(source);
    final client = (this.source as RemotePanelSource).client;
    final operations = client as CloudTransferOperations;
    if (copied == null) {
      if (await stat(destination) != null) {
        throw StateError('Destination already exists: $destination');
      }
      _check();
      final result = await operations.copyToExact(
        source.path!,
        destination,
        replace: false,
        expectedSourceVersion: expected.version,
        checkpoint: () async => _check(),
      );
      _check();
      if (paths.normalize(result.path) != paths.normalize(destination) ||
          result.version == null ||
          result.version!.isEmpty) {
        throw RenameBatchNeedsReview(
          'The provider did not confirm an exact versioned copy. The source was retained: ${source.path}',
        );
      }
      final destinationItem = await stat(destination);
      if (destinationItem == null) {
        throw RenameBatchNeedsReview(
          'The confirmed copy cannot be inspected. The source was retained: ${source.path}',
        );
      }
      copied = RenameFingerprint.fromFile(destinationItem);
      if (copied.version != result.version ||
          copied.folder ||
          (expected.size != null && copied.size != expected.size)) {
        throw RenameBatchNeedsReview(
          'The copied destination differs from the provider receipt. The source was retained: ${source.path}',
        );
      }
      // A failed journal save must leave both objects intact. Resume only uses
      // this receipt after the store has acknowledged its durable write.
      await onCopied(copied);
    }
    _check();
    final beforeDelete = await stat(source.path!);
    final confirmedCopy = await stat(destination);
    if (copied.version == null ||
        beforeDelete == null ||
        !expected.matches(RenameFingerprint.fromFile(beforeDelete)) ||
        confirmedCopy == null ||
        !copied.matches(RenameFingerprint.fromFile(confirmedCopy))) {
      throw RenameBatchNeedsReview(
        'The source or copied destination changed before deletion. Both objects were retained: ${source.path} → $destination',
      );
    }
    _check();
    await operations.deleteTransferFile(
      source.path!,
      expectedVersion: expected.version,
    );
    _check();
    if (await stat(source.path!) != null) {
      throw RenameBatchNeedsReview(
        'The provider did not confirm deletion of the copied source: ${source.path}',
      );
    }
  }

  @override
  Future<void> move(FileItem file, String destination) async {
    _check();
    final problem = renameProblem(file);
    if (problem != null) throw UnsupportedError(problem);
    if (_isObjectStorage) {
      throw StateError('An object rename requires a durable copy checkpoint.');
    }
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
          expectedSourceVersion: client.transferCapabilities.conditionalMove
              ? RenameFingerprint.fromFile(file).version
              : null,
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
        await _fallbackRename(file, paths.basename(destination));
      }
    } else {
      await _fallbackRename(file, paths.basename(destination));
    }
    _check();
  }

  Future<void> _fallbackRename(FileItem file, String name) async {
    final supplied = fallbackRename;
    if (supplied != null) {
      await supplied(file, name);
      return;
    }
    if (source is RemotePanelSource) {
      await (source as RemotePanelSource).client.renamePath(file.path!, name);
      return;
    }
    if (source is! LocalPanelSource || !kIsWeb || file.isFolder) {
      throw UnsupportedError(
        'This filesystem cannot safely rename the selected item.',
      );
    }
    // Browser compatibility uses the same copy-then-delete behavior as before,
    // with an explicit bound for the whole-buffer local-file API.
    if (file.size == null || file.size! > 64 * 1024 * 1024) {
      throw UnsupportedError(
        'Use the transfer dialog to move browser files larger than 64 MiB.',
      );
    }
    final destination = paths.join(paths.dirname(file.path!), name);
    final bytes = await local.readFile(file.path!, fileItem: file);
    _check();
    final saved = await local.saveFileReportingResult(
      destination,
      bytes,
      overwrite: false,
    );
    if (saved != LocalFileSaveResult.written) {
      throw StateError(
        'The browser downloaded a copy; the source was retained.',
      );
    }
    _check();
    final current = await stat(file.path!);
    if (current == null ||
        !RenameFingerprint.fromFile(file)
            .matches(RenameFingerprint.fromFile(current))) {
      throw StateError('The original file changed; both copies were retained.');
    }
    await local.deleteEntry(file.path!, false);
  }
}
