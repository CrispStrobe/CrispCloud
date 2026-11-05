import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'panel_source_service.dart';
import 'native_file_primitives.dart';
import 'storage_identity.dart';

FileOperationBackend fileOperationBackend({
  required PanelSource source,
  required LocalFileService local,
  required bool Function() isCurrent,
}) {
  if (source is LocalPanelSource) {
    return LocalOperationBackend(local, isCurrent: isCurrent);
  }
  if (source is RemotePanelSource) {
    return CloudOperationBackend(source.client, isCurrent: isCurrent);
  }
  throw UnsupportedError('Extract items from archives or containers first.');
}

class LocalOperationBackend extends FileOperationBackend {
  LocalOperationBackend(this.service, {required this._isCurrent});
  static final _reference = storageReferenceForSource(
    const LocalPanelSource('/'),
  );
  final LocalFileService service;
  final bool Function() _isCurrent;
  @override
  Object get identity => _reference.id;
  @override
  String get persistentStorageId => _reference.id;
  @override
  bool get canRecover => !kIsWeb;
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    caseSensitivity: !kIsWeb && (Platform.isWindows || Platform.isMacOS)
        ? StorageCaseSensitivity.insensitive
        : StorageCaseSensitivity.sensitive,
    nativeMove: !kIsWeb,
    atomicMove: !kIsWeb,
    noReplaceMove: !kIsWeb && supportsNativeExclusiveRename,
    readRanges: !kIsWeb,
    setModifiedTime: !kIsWeb,
    symbolicLinks: !kIsWeb,
    deleteEmptyDirectory: !kIsWeb || service is LocalTransferFileOperations,
    boundedUpload: !kIsWeb || service is LocalTransferFileOperations,
    boundedDownload: !kIsWeb || service is LocalTransferFileOperations,
  );
  @override
  String get label => 'Local';
  @override
  p.Context get paths => kIsWeb ? p.posix : p.context;
  @override
  String pathKey(String path) {
    final normalized = paths.normalize(path);
    // Conservatively reject case aliases on platforms commonly backed by a
    // case-insensitive volume, rather than risk moving an item onto itself.
    return !kIsWeb && (Platform.isWindows || Platform.isMacOS)
        ? normalized.toLowerCase()
        : normalized;
  }

  @override
  bool get isCurrent => _isCurrent();
  @override
  bool get supportsModifiedTime => !kIsWeb;
  @override
  bool get supportsSymbolicLinks => !kIsWeb;

  void _check() {
    if (!isCurrent) throw StateError('The source is no longer available.');
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    if (kIsWeb) {
      if (!await service.hasAccessToPath(path)) {
        throw FileSystemException('Directory access is unavailable.', path);
      }
      final entities = await service.listDirectory(path);
      if (entities == null) {
        throw FileSystemException('Cannot list directory.', path);
      }
      return entities.map((entity) {
        final metadata = service.getWebMetadata(entity.path);
        return FileItem(
          name: paths.basename(entity.path),
          path: entity.path,
          isFolder: entity is Directory,
          size: (metadata['size'] as num?)?.toInt(),
          updatedAt: metadata['modified'] is DateTime
              ? metadata['modified']
              : null,
        );
      }).toList();
    }
    return service.withFileOperationAccess(path, () async {
      final items = <FileItem>[];
      await for (final entity in Directory(path).list(followLinks: false)) {
        items.add(await _nativeItem(entity.path));
      }
      _check();
      return items;
    });
  }

  Future<FileItem> _nativeItem(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Item disappeared while listing.', path);
    }
    final info = await FileStat.stat(path);
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: type == FileSystemEntityType.directory,
      isSymlink: type == FileSystemEntityType.link,
      symlinkTarget: type == FileSystemEntityType.link
          ? await Link(path).target()
          : null,
      size: type == FileSystemEntityType.file ? info.size : null,
      updatedAt: type == FileSystemEntityType.link ? null : info.modified,
    );
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = paths.normalize(path);
    final parent = paths.dirname(path);
    if (parent == path) {
      if (kIsWeb) return FileItem(name: path, path: path, isFolder: true);
      return service.withFileOperationAccess(path, () => _nativeItem(path));
    }
    // Listing propagates permission errors; absence alone means missing.
    // Resolve missing intermediate directories recursively.
    final parentExists = kIsWeb
        ? await service.hasAccessToPath(parent)
        : await service.withFileOperationAccess(
            parent,
            () => FileSystemEntity.type(parent, followLinks: false),
          );
    if (parentExists == false ||
        parentExists == FileSystemEntityType.notFound) {
      final ancestor = await stat(parent);
      if (ancestor == null) return null;
    }
    if (parentExists == FileSystemEntityType.link) {
      throw FileSystemException(
        'Destination parent is a symbolic link.',
        parent,
      );
    }
    final entries = await list(parent);
    final name = paths.basename(path);
    final matches = entries
        .where(
          (item) =>
              item.name == name ||
              (!kIsWeb &&
                  (Platform.isWindows || Platform.isMacOS) &&
                  item.name.toLowerCase() == name.toLowerCase()),
        )
        .toList();
    if (matches.length > 1) throw StateError('Ambiguous filename: $path');
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<void> createDirectory(String path) async {
    _check();
    if (kIsWeb) {
      await service.createDirectory(path);
      return;
    }
    await service.withFileOperationAccess(paths.dirname(path), () async {
      _check();
      await Directory(path).create();
    });
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    if (kIsWeb && service is LocalTransferFileOperations) {
      return (service as LocalTransferFileOperations).readTransferStream(
        file.path!,
      );
    }
    if (kIsWeb) {
      return Stream.fromFuture(
        service.readFileForEdit(file.path!, fileItem: file),
      );
    }
    // Keep the scoped callback alive until the stream finishes or is cancelled.
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    final finished = Completer<void>();
    controller = StreamController<List<int>>(
      onListen: () async {
        try {
          await service.withFileOperationAccess(file.path!, () async {
            _check();
            subscription = File(file.path!).openRead().listen(
              controller.add,
              onError: (Object error, StackTrace stack) =>
                  controller.addError(error, stack),
              onDone: () {
                if (!finished.isCompleted) finished.complete();
              },
            );
            await finished.future;
          });
        } catch (error, stack) {
          controller.addError(error, stack);
        } finally {
          await controller.close();
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        await subscription?.cancel();
        if (!finished.isCompleted) finished.complete();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    _check();
    if (kIsWeb && service is LocalTransferFileOperations) {
      await (service as LocalTransferFileOperations).writeTransferStream(
        path,
        data,
        length,
        replace: replace,
      );
      return;
    }
    if (kIsWeb) {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in data) {
        _check();
        bytes.add(chunk);
      }
      if (length != null && bytes.length != length) {
        throw StateError('Source length changed.');
      }
      final result = await service.saveFileReportingResult(
        path,
        bytes.takeBytes(),
        overwrite: replace,
      );
      if (result != LocalFileSaveResult.written) {
        throw StateError(
          'Browser downloaded a copy but did not write the destination. Source retained.',
        );
      }
      return;
    }
    await service.withFileOperationAccess(paths.dirname(path), () async {
      _check();
      var ancestor = paths.dirname(path);
      while (true) {
        if (await FileSystemEntity.type(ancestor, followLinks: false) ==
            FileSystemEntityType.link) {
          throw FileSystemException(
            'Destination parent is a symbolic link.',
            ancestor,
          );
        }
        final next = paths.dirname(ancestor);
        if (next == ancestor) break;
        ancestor = next;
      }
      final destination = File(path);
      final initialType = await FileSystemEntity.type(path, followLinks: false);
      if (initialType != FileSystemEntityType.notFound &&
          (!replace || initialType != FileSystemEntityType.file)) {
        throw FileSystemException(
          'Destination already exists or has an incompatible type.',
          path,
        );
      }
      final staging = await Directory(paths.dirname(path))
          .createTemp('.crisp-transfer-');
      final staged = File(paths.join(staging.path, 'payload'));
      await checkpoint?.call({
        'phase': 'staging',
        'destination': path,
        'stagedPath': staged.path,
        'stagingDirectory': staging.path,
      });
      try {
        // A copy keeps existing mode bits when replacing a local file.
        if (initialType == FileSystemEntityType.file) {
          final mode = (await destination.stat()).mode;
          if (!Platform.isWindows && (mode & 0x92) == 0) {
            throw FileSystemException('Destination is read-only.', path);
          }
          await destination.copy(staged.path);
        }
        final sink = staged.openWrite();
        try {
          await sink.addStream(data);
          await sink.flush();
        } catch (_) {
          // addStream may already close the file after a read/write failure.
          // Closing it again must not hide the original transfer error.
          try {
            await sink.close();
          } catch (_) {
            /* Preserve the first read or write failure. */
          }
          rethrow;
        }
        await sink.close();
        if (length != null && await staged.length() != length) {
          throw StateError(
            'Source length changed; destination was not replaced.',
          );
        }
        _check();
        await verifyStaged?.call(await _nativeItem(staged.path));
        await checkpoint?.call({
          'phase': 'committing',
          'destination': path,
          'stagedPath': staged.path,
          'stagingDirectory': staging.path,
        });
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.directory) {
          throw FileSystemException(
            'Destination changed to an incompatible type.',
            path,
          );
        }
        if (!replace) {
          if (await moveNativeNoReplace(staged.path, path)) {
            await checkpoint?.call({'phase': 'committed', 'destination': path});
            return;
          }
          throw UnsupportedError(
            'This volume cannot commit an exclusive copy safely.',
          );
        }
        await staged.rename(path);
        await checkpoint?.call({'phase': 'committed', 'destination': path});
      } finally {
        try {
          await staging.delete(recursive: true);
        } catch (_) {
          /* Preserve write result. */
        }
      }
    });
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    _check();
    if (kIsWeb) return false;
    return service.withFileOperationAccess(file.path!, () async {
      return service.withFileOperationAccess(
        paths.dirname(destination),
        () async {
          _check();
          return moveNativeNoReplace(file.path!, destination);
        },
      );
    });
  }

  @override
  Stream<List<int>> readRange(FileItem file, int offset) {
    if (kIsWeb) return super.readRange(file, offset);
    // Reuse the scoped, backpressure-aware stream; native bytes are skipped
    // without buffering. Provider-specific ranged streams override this below.
    return super.readRange(file, offset);
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    _check();
    if (kIsWeb) {
      await service.deleteEntry(file.path!, false);
      return;
    }
    await service.withFileOperationAccess(file.path!, () async {
      _check();
      if (file.isSymlink == true) {
        await Link(file.path!).delete();
      } else {
        await File(file.path!).delete();
      }
    });
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    _check();
    if (kIsWeb) {
      final transfer = service;
      if (transfer is! LocalTransferFileOperations) {
        throw UnsupportedError(
          'This browser cannot delete an empty directory safely.',
        );
      }
      await (transfer as LocalTransferFileOperations).deleteDirectoryIfEmpty(
        path,
      );
      return;
    }
    await service.withFileOperationAccess(path, () async {
      _check();
      await Directory(path).delete();
    });
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    _check();
    await service.withFileOperationAccess(
      path,
      () => File(path).setLastModified(modified),
    );
  }

  @override
  Future<void> copySymbolicLink(
    FileItem source,
    String destination, {
    required bool replace,
  }) async {
    _check();
    if (kIsWeb) {
      throw UnsupportedError('Symbolic links require native storage.');
    }
    if (replace) {
      throw UnsupportedError(
        'Existing files are never replaced by symbolic links.',
      );
    }
    final linkTarget = source.symlinkTarget;
    if (linkTarget == null) {
      throw StateError('Symbolic link target is unavailable.');
    }
    await service.withFileOperationAccess(paths.dirname(destination), () async {
      _check();
      await Link(destination).create(linkTarget);
    });
  }
}

class CloudOperationBackend extends FileOperationBackend {
  CloudOperationBackend(this.client, {required this._isCurrent});
  final CloudStorageClient client;
  final bool Function() _isCurrent;
  @override
  Object get identity => storageReferenceForClient(client).id;
  @override
  String get persistentStorageId => storageReferenceForClient(client).id;
  @override
  bool get canRecover => storageReferenceForClient(client).persistent;
  @override
  StorageTransferCapabilities get capabilities => client.transferCapabilities;
  @override
  bool get supportsModifiedTime => capabilities.setModifiedTime;
  @override
  bool get supportsSymbolicLinks => capabilities.symbolicLinks;
  @override
  String get label => client.providerName;
  @override
  p.Context get paths => p.posix;
  @override
  String destinationPathKey(String path) =>
      capabilities.caseSensitivity == StorageCaseSensitivity.sensitive
      ? paths.normalize(path)
      : paths.normalize(path).toLowerCase();
  @override
  bool get isCurrent => _isCurrent() && client.isAuthenticated;
  void _check() {
    if (!isCurrent) {
      throw StateError('The cloud account changed. Reopen the operation.');
    }
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    final result = await client.listPath(path);
    _check();
    final entries = <FileItem>[];
    for (final group in ['folders', 'files']) {
      for (final raw in (result[group] as List?) ?? const []) {
        final item = Map<String, dynamic>.from(raw as Map);
        var name = item['name']?.toString() ?? '';
        final fileType = item['fileType']?.toString() ?? '';
        if (group == 'files' &&
            fileType.isNotEmpty &&
            fileType.toLowerCase() != 'file' &&
            !name.toLowerCase().endsWith('.${fileType.toLowerCase()}')) {
          name = '$name.$fileType';
        }
        if (name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains('\\')) {
          throw StateError('Invalid filename returned by $label.');
        }
        final rawDate =
            item['modificationTime'] ??
            item['lastModified'] ??
            item['timestamp'];
        DateTime? modified;
        if (rawDate is DateTime) {
          modified = rawDate;
        } else if (rawDate is num) {
          modified = DateTime.fromMillisecondsSinceEpoch(rawDate.toInt());
        } else if (rawDate != null) {
          modified = DateTime.tryParse(rawDate.toString());
        }
        entries.add(
          FileItem(
            name: name,
            path: paths.join(path, name),
            isFolder: group == 'folders',
            uuid: item['uuid']?.toString(),
            size: (item['size'] as num?)?.toInt(),
            updatedAt: modified,
            isSymlink: item['isSymlink'] == true,
            metadata: item,
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = paths.normalize(path);
    if (path == '/' || path == client.rootPath) {
      return FileItem(name: path, path: path, isFolder: true);
    }
    var parent = paths.dirname(path);
    // Resolve parents without converting permission/API errors into absence.
    if (parent != '/' && parent != client.rootPath) {
      final existingParent = await stat(parent);
      if (existingParent == null) return null;
      if (!existingParent.isFolder || existingParent.isSymlink == true) {
        throw StateError('Cloud parent is not a regular directory: $parent');
      }
      parent = existingParent.path ?? parent;
    }
    final requestedName = destinationPathKey(paths.basename(path));
    final matches = (await list(parent))
        .where((file) => destinationPathKey(file.name) == requestedName)
        .toList();
    if (matches.length > 1) {
      throw StateError('Several cloud items have case-ambiguous paths: $path');
    }
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<void> createDirectory(String path) async {
    _check();
    await client.createFolderPath(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    await for (final chunk in client.downloadStream(file.path!)) {
      _check();
      yield chunk;
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    _check();
    if (!replace && await stat(path) != null) {
      throw StateError('Destination already exists: $path');
    }
    final parent = paths.dirname(path);
    final name = paths.basename(path);
    final token = const Uuid().v4();
    final stagedName = '.crisp-transfer-$token.tmp';
    final stagedPath = paths.join(parent, stagedName);
    final backupName = '.crisp-replaced-$token.bak';
    final backupPath = paths.join(parent, backupName);
    var backupRenameAttempted = false;
    var originalBackedUp = false;
    var committed = false;
    var received = 0;
    await checkpoint?.call({
      'phase': 'uploading',
      'destination': path,
      'stagedPath': stagedPath,
      'backupPath': backupPath,
    });
    try {
      if (length == null) {
        // Cloud upload contracts require a real content length. Unknown-size
        // sources are buffered rather than falsely advertised as empty files.
        final buffered = BytesBuilder(copy: false);
        await for (final chunk in data) {
          _check();
          buffered.add(chunk);
        }
        final bytes = buffered.takeBytes();
        length = bytes.length;
        data = Stream.value(bytes);
      }
      // Never stream into an existing destination: FTP/SFTP and some web APIs
      // truncate as soon as upload begins. Stage alongside it first.
      await client.uploadStream(
        data.map((chunk) {
          _check();
          received += chunk.length;
          return chunk;
        }),
        length,
        stagedName,
        parent,
      );
      _check();
      if (received != length) {
        throw StateError('Source length changed.');
      }
      final staged = await stat(stagedPath);
      if (staged == null ||
          staged.isFolder ||
          (staged.size != null && staged.size != received)) {
        throw StateError('The staged cloud copy could not be verified.');
      }
      await verifyStaged?.call(staged);
      await checkpoint?.call({
        'phase': 'staged',
        'destination': path,
        'stagedPath': stagedPath,
        'backupPath': backupPath,
      });
      final existing = await stat(path);
      if (existing != null) {
        if (!replace || existing.isFolder || existing.isSymlink == true) {
          throw StateError(
            'Destination already exists or has an incompatible type: $path',
          );
        }
        _check();
        backupRenameAttempted = true;
        await checkpoint?.call({
          'phase': 'backingUp',
          'destination': path,
          'stagedPath': stagedPath,
          'backupPath': backupPath,
        });
        await client.renamePath(path, backupName);
        originalBackedUp = true;
        await checkpoint?.call({
          'phase': 'backedUp',
          'destination': path,
          'stagedPath': stagedPath,
          'backupPath': backupPath,
        });
      }
      _check();
      if (await stat(path) != null) {
        throw StateError('Destination changed while committing: $path');
      }
      await checkpoint?.call({
        'phase': 'committing',
        'destination': path,
        'stagedPath': stagedPath,
        'backupPath': backupPath,
      });
      await client.renamePath(stagedPath, name);
      _check();
      final written = await stat(path);
      if (written == null ||
          written.isFolder ||
          (written.size != null && written.size != received)) {
        throw StateError('The committed cloud copy could not be verified.');
      }
      committed = true;
      await checkpoint?.call({
        'phase': 'committed',
        'destination': path,
        'stagedPath': stagedPath,
        'backupPath': originalBackedUp ? backupPath : null,
      });
      if (originalBackedUp) {
        // Failure to remove the backup does not undo a verified transfer.
        try {
          _check();
          await client.deletePath(backupPath);
        } catch (_) {
          /* Preserve the old file as a recovery copy. */
        }
      }
    } catch (error) {
      if (backupRenameAttempted && !originalBackedUp && !committed) {
        // A remote rename can complete before its acknowledgement is lost.
        // Discover that backup before deciding whether there is anything to
        // restore; never omit its possible recovery location on an API error.
        if (!isCurrent) {
          throw StateError(
            '$error. The backup rename could not be confirmed. '
            'Check $path and $backupPath before retrying.',
          );
        }
        try {
          originalBackedUp = await stat(backupPath) != null;
        } catch (_) {
          throw StateError(
            '$error. The backup rename could not be confirmed. '
            'Check $path and $backupPath before retrying.',
          );
        }
      }
      if (originalBackedUp && !committed && isCurrent) {
        try {
          if (await stat(path) == null) {
            _check();
            await client.renamePath(backupPath, name);
            originalBackedUp = false;
          }
        } catch (_) {
          /* Report the preserved recovery location below. */
        }
      }
      if (originalBackedUp && !committed) {
        throw StateError(
          '$error. The original destination is preserved at $backupPath',
        );
      }
      rethrow;
    } finally {
      // Account changes prohibit even cleanup against the replacement account.
      if (isCurrent && !committed) {
        try {
          if (await stat(stagedPath) != null) {
            _check();
            await client.deletePath(stagedPath);
          }
        } catch (_) {
          /* Preserve the original failure and any recoverable stage. */
        }
      }
    }
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    _check();
    if (capabilities.conditionalDelete && client is CloudTransferOperations) {
      await (client as CloudTransferOperations).deleteTransferFile(
        file.path!,
        expectedVersion: _fileVersion(file),
      );
    } else {
      await client.deletePath(file.path!);
    }
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    _check();
    if (!capabilities.deleteEmptyDirectory ||
        client is! CloudTransferOperations) {
      throw UnsupportedError(
        'This provider cannot delete an empty directory safely.',
      );
    }
    await (client as CloudTransferOperations).deleteDirectoryIfEmpty(path);
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    _check();
    if (!capabilities.nativeMove ||
        !capabilities.noReplaceMove ||
        !capabilities.atomicMove ||
        client is! CloudTransferOperations) {
      return false;
    }
    final result = await (client as CloudTransferOperations).moveToExact(
      file.path!,
      destination,
      expectedSourceVersion: _fileVersion(file),
    );
    _check();
    if (destinationPathKey(result.path) != destinationPathKey(destination)) {
      throw StateError(
        'Provider moved the item to an unexpected path: ${result.path}',
      );
    }
    return true;
  }

  @override
  Future<bool> copyNative(
    FileItem file,
    String destination, {
    required bool replace,
    TransferCheckpoint? checkpoint,
  }) async {
    _check();
    if (!capabilities.nativeCopy || client is! CloudTransferOperations) {
      return false;
    }
    // A replacement still uses staging/backup in writeFile. Native adapters
    // must guarantee exact-name, no-clobber semantics for this direct fast path.
    if (replace) return false;
    final result = await (client as CloudTransferOperations).copyToExact(
      file.path!,
      destination,
      expectedSourceVersion: _fileVersion(file),
      checkpoint: checkpoint,
    );
    _check();
    if (destinationPathKey(result.path) != destinationPathKey(destination)) {
      throw StateError(
        'Provider copied the item to an unexpected path: ${result.path}',
      );
    }
    return true;
  }

  @override
  Future<TransferMetadata> readMetadata(String path) async {
    _check();
    if (client is! CloudTransferOperations) return super.readMetadata(path);
    return (client as CloudTransferOperations).readTransferMetadata(path);
  }

  @override
  Future<void> writeMetadata(String path, TransferMetadata metadata) async {
    _check();
    if (client is! CloudTransferOperations) {
      return super.writeMetadata(path, metadata);
    }
    await (client as CloudTransferOperations).setTransferMetadata(
      path,
      metadata,
    );
  }

  @override
  Future<void> setModified(String path, DateTime modified) =>
      writeMetadata(path, TransferMetadata(modified: modified));

  @override
  Stream<List<int>> readRange(FileItem file, int offset) {
    _check();
    if (!capabilities.readRanges || client is! CloudTransferOperations) {
      return super.readRange(file, offset);
    }
    return (client as CloudTransferOperations).readTransferRange(
      file.path!,
      offset,
      expectedVersion: _fileVersion(file),
    );
  }

  String? _fileVersion(FileItem file) {
    for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
      if (file.metadata?[key] != null) return file.metadata![key].toString();
    }
    return null;
  }
}
