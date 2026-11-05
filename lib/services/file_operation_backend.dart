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
  static final Object _localIdentity = Object();
  final LocalFileService service;
  final bool Function() _isCurrent;
  @override
  Object get identity => _localIdentity;
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
  }) async {
    _check();
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
      var reserved = false;
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
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.directory) {
          throw FileSystemException(
            'Destination changed to an incompatible type.',
            path,
          );
        }
        if (!replace) {
          await destination.create(exclusive: true);
          reserved = true;
        }
        await staged.rename(path);
        reserved = false;
      } finally {
        if (reserved) {
          try {
            await destination.delete();
          } catch (_) {
            /* Preserve write failure. */
          }
        }
        try {
          await staging.delete(recursive: true);
        } catch (_) {
          /* Preserve write result. */
        }
      }
    });
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
      // The browser abstraction only offers recursive delete; never use it for
      // move cleanup, because a new file could appear after the emptiness check.
      throw UnsupportedError(
        'Empty source folders are retained in the browser.',
      );
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
  Object get identity => client;
  @override
  String get label => client.providerName;
  @override
  p.Context get paths => p.posix;
  @override
  String destinationPathKey(String path) => paths.normalize(path).toLowerCase();
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
    final requestedName = paths.basename(path).toLowerCase();
    final matches = (await list(parent))
        .where((file) => file.name.toLowerCase() == requestedName)
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
      final existing = await stat(path);
      if (existing != null) {
        if (!replace || existing.isFolder || existing.isSymlink == true) {
          throw StateError(
            'Destination already exists or has an incompatible type: $path',
          );
        }
        _check();
        backupRenameAttempted = true;
        await client.renamePath(path, backupName);
        originalBackedUp = true;
      }
      _check();
      if (await stat(path) != null) {
        throw StateError('Destination changed while committing: $path');
      }
      await client.renamePath(stagedPath, name);
      _check();
      final written = await stat(path);
      if (written == null ||
          written.isFolder ||
          (written.size != null && written.size != received)) {
        throw StateError('The committed cloud copy could not be verified.');
      }
      committed = true;
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
    await client.deletePath(file.path!);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    // CloudStorageClient.deletePath is recursive for several providers and
    // has no conditional-empty delete contract. Keep source folders safely.
    throw UnsupportedError(
      'Empty source folders are retained by this cloud provider.',
    );
  }
}
