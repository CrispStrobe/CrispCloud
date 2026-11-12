import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'panel_source_service.dart';
import 'native_file_primitives.dart';
import 'native_metadata.dart';
import 'storage_identity.dart';
import 'transfer_spool.dart';
import '../utils/system_links.dart';

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

class _NativeCloneUnavailable implements Exception {
  const _NativeCloneUnavailable();
}

class LocalOperationBackend extends FileOperationBackend {
  LocalOperationBackend(this.service, {required bool Function() isCurrent})
    // Keep the public named callback while storing it privately.
    // ignore: prefer_initializing_formals
    : _isCurrent = isCurrent;
  static StorageReference get _reference =>
      storageReferenceForSource(const LocalPanelSource('/'));
  final LocalFileService service;
  final bool Function() _isCurrent;
  @override
  Object get identity => _reference.id;
  @override
  String get persistentStorageId => _reference.id;
  @override
  StorageReference get storageReference => _reference;
  @override
  bool get canRecover => !kIsWeb && _reference.persistent;
  @override
  bool get supportsStagedVerification =>
      !kIsWeb || service is LocalTransferFileOperations;
  @override
  bool get supportsRetainedStageCleanup => !kIsWeb;
  @override
  bool isRetainedStagePath(String stagePath, String destinationPath) {
    final directory = paths.dirname(stagePath);
    final name = paths.basename(directory);
    return !kIsWeb &&
        !stagePath.contains('\u0000') &&
        !destinationPath.contains('\u0000') &&
        paths.isAbsolute(stagePath) &&
        paths.isAbsolute(destinationPath) &&
        paths.normalize(stagePath) == stagePath &&
        paths.basename(stagePath) == 'payload' &&
        name.startsWith('.crisp-transfer-') &&
        name.length > '.crisp-transfer-'.length &&
        samePath(paths.dirname(directory), paths.dirname(destinationPath));
  }

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
    setAccessedTime: !kIsWeb,
    setCreatedTime: !kIsWeb && supportsNativeCreatedTime,
    symbolicLinks: !kIsWeb,
    deleteEmptyDirectory: !kIsWeb || service is LocalTransferFileOperations,
    boundedUpload: !kIsWeb || service is LocalTransferFileOperations,
    boundedDownload: !kIsWeb || service is LocalTransferFileOperations,
    preallocate: !kIsWeb && supportsNativePreallocation,
    copyOnWrite: !kIsWeb && supportsNativeCopyOnWrite,
    permissions: !kIsWeb && supportsNativePermissions,
    ownership: !kIsWeb && supportsNativeOwnership,
    extendedAttributes: !kIsWeb && supportsNativeExtendedAttributes,
    accessControlLists: !kIsWeb && supportsNativeAccessControlLists,
    windowsAttributes: !kIsWeb && supportsNativeWindowsAttributes,
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
        final item = await _nativeItemOrNull(entity.path);
        if (item != null) items.add(item);
      }
      _check();
      return items;
    });
  }

  bool _isMissing(FileSystemException error) =>
      error.osError?.errorCode == 2 ||
      (Platform.isWindows && error.osError?.errorCode == 3);

  /// Dart type/stat suppress permission errors as notFound. Resolve only on
  /// that error path to recover the real OS failure; absence alone returns null.
  Future<bool> _confirmMissing(String path) async {
    try {
      await File(path).resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      if (_isMissing(error)) return true;
      rethrow;
    }
    return false;
  }

  Future<FileItem?> _nativeItemOrNull(String path) async {
    var type = await entityTypeTrustingSystemLinks(path);
    if (type == FileSystemEntityType.notFound) {
      if (await _confirmMissing(path)) return null;
      type = await entityTypeTrustingSystemLinks(path);
      if (type == FileSystemEntityType.notFound) {
        throw FileSystemException('Cannot inspect the requested item.', path);
      }
    }
    if (type == FileSystemEntityType.link) {
      String target;
      try {
        target = await Link(path).target();
      } on FileSystemException catch (error) {
        if (_isMissing(error)) return null;
        rethrow;
      }
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: true,
        symlinkTarget: target,
      );
    }
    final info = await FileStat.stat(path);
    if (info.type == FileSystemEntityType.notFound) {
      if (await _confirmMissing(path)) return null;
      throw FileSystemException(
        'Cannot read the requested item metadata.',
        path,
      );
    }
    if (info.type != type ||
        await entityTypeTrustingSystemLinks(path) != type) {
      throw FileSystemException(
        'Item changed while it was being inspected.',
        path,
      );
    }
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: type == FileSystemEntityType.directory,
      isSymlink: false,
      size: type == FileSystemEntityType.file ? info.size : null,
      updatedAt: info.modified,
    );
  }

  Future<FileItem> _nativeItem(String path) async {
    final item = await _nativeItemOrNull(path);
    if (item == null) {
      throw FileSystemException(
        'The requested item no longer exists.',
        path,
        const OSError('No such file or directory', 2),
      );
    }
    return item;
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = paths.normalize(path);
    final parent = paths.dirname(path);
    if (!kIsWeb) {
      if (parent != path &&
          await FileSystemEntity.type(parent, followLinks: false) ==
              FileSystemEntityType.notFound &&
          !await service.hasAccessToPath(path)) {
        // A committed stage may have removed its private parent directory.
        // Inspect that parent under the same scoped stat contract, reaching
        // an existing ancestor instead of requesting a picker for a vanished
        // child. Existing scopes covering the exact path stay on the normal
        // path below. _nativeItemOrNull confirms ENOENT and propagates denied
        // or unknown access; FileSystemEntity.type alone is not absence proof.
        final currentParent = await stat(parent);
        _check();
        if (currentParent == null) return null;
        if (!currentParent.isFolder || currentParent.isSymlink == true) {
          throw FileSystemException(
            'The parent is not a regular directory.',
            parent,
          );
        }
      }
      return service.withFileOperationAccess(path, () async {
        _check();
        if (parent != path) {
          final parentType = await entityTypeTrustingSystemLinks(parent);
          if (parentType == FileSystemEntityType.link) {
            throw FileSystemException(
              'Destination parent is a symbolic link.',
              parent,
            );
          }
          if (parentType != FileSystemEntityType.directory &&
              parentType != FileSystemEntityType.notFound) {
            throw FileSystemException('The parent is not a directory.', parent);
          }
        }
        final item = await _nativeItemOrNull(path);
        _check();
        return item;
      });
    }
    if (parent == path) return FileItem(name: path, path: path, isFolder: true);
    if (!await service.hasAccessToPath(parent)) {
      final ancestor = await stat(parent);
      if (ancestor == null) return null;
    }
    final entries = await list(parent);
    final name = paths.basename(path);
    final matches = entries.where((item) => item.name == name).toList();
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
    return _readNativeRange(file, 0);
  }

  Stream<List<int>> _readNativeRange(FileItem file, int offset) {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    // Keep the scoped callback alive until the stream finishes or is cancelled.
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    final finished = Completer<void>();
    controller = StreamController<List<int>>(
      onListen: () async {
        try {
          await service.withFileOperationAccess(file.path!, () async {
            _check();
            final current = await stat(file.path!);
            if (current == null ||
                current.isFolder ||
                current.isSymlink == true ||
                await FileSystemEntity.type(file.path!, followLinks: false) !=
                    FileSystemEntityType.file) {
              throw FileSystemException(
                'Only regular files can be streamed.',
                file.path,
              );
            }
            if (offset > (current.size ?? 0)) {
              throw StateError('Source is shorter than the resume offset.');
            }
            if (finished.isCompleted) return;
            subscription = File(file.path!)
                .openRead(offset)
                .listen(
                  (chunk) {
                    try {
                      _check();
                      controller.add(chunk);
                    } catch (error, stack) {
                      controller.addError(error, stack);
                      subscription?.cancel();
                      if (!finished.isCompleted) finished.complete();
                    }
                  },
                  onError: (Object error, StackTrace stack) =>
                      controller.addError(error, stack),
                  onDone: () {
                    if (!finished.isCompleted) finished.complete();
                  },
                );
            if (controller.isPaused) subscription!.pause();
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
  }) => _writePreparedFile(
    path,
    data,
    length,
    replace: replace,
    verifyStaged: verifyStaged,
    checkpoint: checkpoint,
  );

  @override
  Future<void> writeConfiguredFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    bool preallocate = false,
    bool retainPartialFileOnFailure = false,
    String? resumeUploadPath,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    if (resumeUploadPath != null) {
      throw UnsupportedError('Native storage cannot resume a provider upload.');
    }
    return _writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      preallocate: preallocate,
      retainPartialFileOnFailure: retainPartialFileOnFailure,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
  }

  @override
  Future<bool> clonePreparedFile(
    FileItem source,
    String destination, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    if (!capabilities.copyOnWrite) return false;
    return service.withFileOperationAccess(source.path!, () async {
      try {
        await _writePreparedFile(
          destination,
          const Stream.empty(),
          source.size,
          replace: replace,
          cloneSource: source,
          verifyStaged: verifyStaged,
          checkpoint: checkpoint,
        );
        return true;
      } on _NativeCloneUnavailable {
        return false;
      }
    });
  }

  Future<void> _writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    bool preallocate = false,
    bool retainPartialFileOnFailure = false,
    FileItem? cloneSource,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    _check();
    if (preallocate && (!capabilities.preallocate || length == null)) {
      throw UnsupportedError(
        'Physical space reservation requires a known size and a supported native destination.',
      );
    }
    if (kIsWeb && service is LocalTransferFileOperations) {
      final transfer = service as LocalTransferFileOperations;
      final stagedPath = paths.join(
        paths.dirname(path),
        '.crisp-transfer-${const Uuid().v4()}.tmp',
      );
      await checkpoint?.call({
        'phase': 'staging',
        'destination': path,
        'stagedPath': stagedPath,
      });
      var committed = false;
      try {
        await transfer.writeTransferStream(
          stagedPath,
          data,
          length,
          replace: false,
        );
        final staged = await stat(stagedPath);
        if (staged == null) {
          throw StateError('Browser staged file is unavailable.');
        }
        await verifyStaged?.call(staged);
        _check();
        await checkpoint?.call({
          'phase': 'committing',
          'destination': path,
          'stagedPath': stagedPath,
        });
        await transfer.writeTransferStream(
          path,
          transfer.readTransferStream(stagedPath),
          staged.size,
          replace: replace,
        );
        committed = true;
        await checkpoint?.call({'phase': 'committed', 'destination': path});
      } finally {
        if (isCurrent) {
          try {
            await service.deleteEntry(stagedPath, false);
          } catch (_) {
            if (!committed) {
              /* The journal retains the staged path for review. */
            }
          }
        }
      }
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
        if (await entityTypeTrustingSystemLinks(ancestor) ==
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
      var journalOwnsStage = false;
      var committed = false;
      try {
        await checkpoint?.call({
          'phase': 'staging',
          'destination': path,
          'stagedPath': staged.path,
          'stagingDirectory': staging.path,
        });
        journalOwnsStage =
            retainPartialFileOnFailure &&
            checkpoint != null &&
            canRecover &&
            cloneSource == null &&
            !preallocate &&
            length != null;
        int? originalMode;
        if (initialType == FileSystemEntityType.file) {
          final mode = (await destination.stat()).mode;
          if (!Platform.isWindows && (mode & 0x92) == 0) {
            throw FileSystemException('Destination is read-only.', path);
          }
          originalMode = mode;
          if (!capabilities.permissions && cloneSource == null) {
            // Retain platform-specific existing attributes when no separate
            // metadata primitive is available (notably Windows).
            await destination.copy(staged.path);
          }
        }
        var received = 0;
        if (cloneSource != null) {
          final before = await stat(cloneSource.path!);
          if (!_matchesNativeSource(cloneSource, before)) {
            throw StateError('Source changed before cloning.');
          }
          if (!await cloneNativeFile(cloneSource.path!, staged.path)) {
            throw const _NativeCloneUnavailable();
          }
          if (!_matchesNativeSource(
                cloneSource,
                await stat(cloneSource.path!),
              ) ||
              await FileSystemEntity.type(staged.path, followLinks: false) !=
                  FileSystemEntityType.file) {
            throw StateError('Source changed during cloning.');
          }
          received = await staged.length();
        } else if (preallocate) {
          final writer = await staged.open(mode: FileMode.write);
          try {
            await checkpoint?.call({
              'phase': 'allocating',
              'destination': path,
              'stagedPath': staged.path,
              'stagingDirectory': staging.path,
            });
            if (!await preallocateNativeFile(staged.path, length!)) {
              throw UnsupportedError(
                'This volume cannot reserve physical disk space.',
              );
            }
            await for (final chunk in data) {
              _check();
              received += chunk.length;
              if (received > length) throw StateError('Source length changed.');
              await writer.writeFrom(chunk);
            }
            await writer.flush();
          } finally {
            await writer.close();
          }
        } else if (journalOwnsStage) {
          // IOSink.addStream can discard buffered input on a source error.
          // A journal-owned partial must contain the bytes already accepted,
          // so complete each write and flush even when its source is canceled.
          final writer = await staged.open(mode: FileMode.write);
          try {
            await for (final chunk in data) {
              _check();
              received += chunk.length;
              if (received > length) {
                throw StateError('Source length changed.');
              }
              await writer.writeFrom(chunk);
            }
          } finally {
            try {
              await writer.flush();
            } finally {
              await writer.close();
            }
          }
        } else {
          final sink = staged.openWrite();
          try {
            await sink.addStream(
              data.map((chunk) {
                _check();
                received += chunk.length;
                return chunk;
              }),
            );
            await sink.flush();
          } catch (_) {
            try {
              await sink.close();
            } catch (_) {
              /* Retain the initial failure. */
            }
            rethrow;
          }
          await sink.close();
        }
        if (length != null &&
            (received != length || await staged.length() != length)) {
          throw StateError(
            'Source length changed; destination was not replaced.',
          );
        }
        if (originalMode != null && capabilities.permissions) {
          await setNativeFileMode(staged.path, originalMode);
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
            committed = true;
            await checkpoint?.call({'phase': 'committed', 'destination': path});
            return;
          }
          throw UnsupportedError(
            'This volume cannot commit an exclusive copy safely.',
          );
        }
        await staged.rename(path);
        committed = true;
        await checkpoint?.call({'phase': 'committed', 'destination': path});
      } finally {
        var keepPartial = false;
        if (journalOwnsStage && !committed) {
          try {
            if (await FileSystemEntity.type(staged.path, followLinks: false) ==
                FileSystemEntityType.file) {
              final size = await staged.length();
              keepPartial = size > 0 && size <= length!;
            }
          } catch (_) {
            // An acknowledged journal owns an inaccessible stage as well.
            // Retain it for explicit recovery rather than lose its evidence.
            keepPartial = true;
          }
        }
        if (!keepPartial) {
          try {
            if (retainPartialFileOnFailure) {
              // A journaled attempt must never recursively delete another
              // entry placed in its private directory. The durable reference
              // remains available if exact cleanup cannot be confirmed.
              final entries = staging.listSync(followLinks: false);
              if (entries.every((entry) => entry.path == staged.path)) {
                final type = FileSystemEntity.typeSync(
                  staged.path,
                  followLinks: false,
                );
                if (!committed &&
                    type == FileSystemEntityType.file &&
                    (!journalOwnsStage || staged.lengthSync() == 0)) {
                  staged.deleteSync();
                }
                staging.deleteSync();
              }
            } else {
              await staging.delete(recursive: true);
            }
          } catch (_) {
            /* Preserve write result. */
          }
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
    return _readNativeRange(file, offset);
  }

  bool _matchesNativeSource(FileItem before, FileItem? after) =>
      after != null &&
      !after.isFolder &&
      after.isSymlink != true &&
      before.size == after.size &&
      (before.updatedAt == null ||
          (after.updatedAt != null &&
              before.updatedAt!.isAtSameMomentAs(after.updatedAt!)));

  @override
  Future<TransferMetadata> readMetadata(String path) =>
      readMetadataFields(path);

  @override
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool created = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
    bool windowsAttributes = true,
  }) async {
    if (kIsWeb) return super.readMetadata(path);
    return service.withFileOperationAccess(path, () async {
      _check();
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Metadata requires a regular file or directory.',
          path,
        );
      }
      final info = await FileStat.stat(path);
      final extra =
          supportsNativeMetadata &&
              (ownership ||
                  extendedAttributes ||
                  acl ||
                  (created && supportsNativeCreatedTime) ||
                  (windowsAttributes && supportsNativeWindowsAttributes))
          ? await readNativeMetadata(
              path,
              ownership: ownership,
              extendedAttributes: extendedAttributes,
              acl: acl,
              created: created,
              windowsAttributes: windowsAttributes,
            )
          : const TransferMetadata();
      _check();
      return TransferMetadata(
        modified: modified ? info.modified : null,
        accessed: accessed ? info.accessed : null,
        created: extra.created,
        mode: permissions && capabilities.permissions
            ? info.mode & 0xfff
            : null,
        owner: extra.owner,
        group: extra.group,
        extendedAttributes: extra.extendedAttributes,
        acl: extra.acl,
        windowsAttributes: extra.windowsAttributes,
      );
    });
  }

  @override
  Future<void> writeMetadata(String path, TransferMetadata metadata) async {
    if (kIsWeb) return super.writeMetadata(path, metadata);
    if (!supportsNativeMetadata &&
        (metadata.owner != null ||
            metadata.group != null ||
            metadata.extendedAttributes.isNotEmpty ||
            metadata.acl != null ||
            metadata.created != null ||
            metadata.windowsAttributes != null)) {
      throw UnsupportedError(
        'This native backend does not implement the requested ownership, attributes, or ACL.',
      );
    }
    await service.withFileOperationAccess(path, () async {
      _check();
      if (supportsNativeMetadata) {
        await writeNativeMetadata(path, metadata);
        _check();
        return;
      }
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw UnsupportedError('Metadata on symbolic links is not changed.');
      }
      if (metadata.mode != null) await setNativeFileMode(path, metadata.mode!);
      if (metadata.modified != null) {
        await setModified(path, metadata.modified!);
      }
      if (metadata.accessed != null) {
        await File(path).setLastAccessed(metadata.accessed!);
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
  Future<void> cleanupRetainedStage(
    String stagePath, {
    required FileItem published,
    required String publishedSha256,
    TransferCheckpoint? checkpoint,
  }) async {
    if (kIsWeb) {
      return super.cleanupRetainedStage(
        stagePath,
        published: published,
        publishedSha256: publishedSha256,
        checkpoint: checkpoint,
      );
    }
    final destination = published.path;
    final stageDirectory = paths.dirname(stagePath);
    if (destination == null ||
        !isRetainedStagePath(stagePath, destination) ||
        published.isFolder ||
        published.isSymlink == true ||
        published.size == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(publishedSha256)) {
      throw StateError(
        'The retained staging path is outside its exact private layout.',
      );
    }
    await service.withFileOperationAccess(paths.dirname(destination), () async {
      _check();
      await checkpoint?.call();

      void checkParents() {
        var parent = paths.dirname(stageDirectory);
        while (true) {
          if (entityTypeTrustingSystemLinksSync(parent) !=
              FileSystemEntityType.directory) {
            throw FileSystemException(
              'Recovery cleanup parent is not a regular directory.',
              parent,
            );
          }
          final next = paths.dirname(parent);
          if (next == parent) break;
          parent = next;
        }
      }

      void checkPrivateDirectory() {
        if (FileSystemEntity.typeSync(stageDirectory, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException(
            'Recovery staging directory changed.',
            stageDirectory,
          );
        }
        final entries = Directory(stageDirectory).listSync(followLinks: false);
        if (entries.any((entry) => !samePath(entry.path, stagePath))) {
          throw FileSystemException(
            'Recovery staging directory contains other entries.',
            stageDirectory,
          );
        }
      }

      bool sameStat(FileStat first, FileStat second) =>
          first.type == second.type &&
          first.size == second.size &&
          first.mode == second.mode &&
          first.modified.isAtSameMomentAs(second.modified) &&
          first.changed.isAtSameMomentAs(second.changed);

      checkParents();
      final directoryType = FileSystemEntity.typeSync(
        stageDirectory,
        followLinks: false,
      );
      if (directoryType == FileSystemEntityType.notFound) {
        final missing = await _confirmMissing(stageDirectory);
        _check();
        if (missing) return;
        throw StateError(
          'The retained staging directory could not be inspected.',
        );
      }
      checkPrivateDirectory();
      if (FileSystemEntity.typeSync(destination, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('The published destination is not a regular file.');
      }
      final destinationBefore = FileStat.statSync(destination);
      if (destinationBefore.size != published.size ||
          (published.updatedAt != null &&
              !published.updatedAt!.isAtSameMomentAs(
                destinationBefore.modified,
              ))) {
        throw StateError(
          'The published destination changed before recovery cleanup.',
        );
      }
      final stageType = FileSystemEntity.typeSync(
        stagePath,
        followLinks: false,
      );
      if (stageType != FileSystemEntityType.file &&
          stageType != FileSystemEntityType.notFound) {
        throw StateError('The retained payload is not a regular file.');
      }
      if (stageType == FileSystemEntityType.notFound &&
          !await _confirmMissing(stagePath)) {
        throw StateError('The retained payload could not be inspected.');
      }
      final stageBefore = stageType == FileSystemEntityType.file
          ? FileStat.statSync(stagePath)
          : null;
      if (stageBefore != null &&
          (stageBefore.size < 0 || stageBefore.size > destinationBefore.size)) {
        throw StateError(
          'The retained payload is not a valid published prefix.',
        );
      }
      String? stageDigest;
      if (stageBefore != null) {
        var received = 0;
        stageDigest =
            (await sha256
                    .bind(
                      File(stagePath).openRead().asyncMap((chunk) async {
                        await checkpoint?.call();
                        _check();
                        received += chunk.length;
                        return chunk;
                      }),
                    )
                    .first)
                .toString();
        if (received != stageBefore.size) {
          throw StateError(
            'The retained payload changed while verifying cleanup.',
          );
        }
      }
      final fullDigest = _NativeStageDigest();
      final prefixDigest = _NativeStageDigest();
      final fullSink = sha256.startChunkedConversion(fullDigest);
      final prefixSink = sha256.startChunkedConversion(prefixDigest);
      var received = 0;
      var prefixRemaining = stageBefore?.size ?? 0;
      try {
        await for (final chunk in File(destination).openRead()) {
          await checkpoint?.call();
          _check();
          received += chunk.length;
          fullSink.add(chunk);
          if (prefixRemaining > 0) {
            final count = chunk.length < prefixRemaining
                ? chunk.length
                : prefixRemaining;
            prefixSink.add(
              count == chunk.length ? chunk : chunk.sublist(0, count),
            );
            prefixRemaining -= count;
          }
        }
      } finally {
        fullSink.close();
        prefixSink.close();
      }
      if (received != destinationBefore.size ||
          prefixRemaining != 0 ||
          fullDigest.value?.toString() != publishedSha256 ||
          (stageDigest != null &&
              prefixDigest.value?.toString() != stageDigest)) {
        throw StateError(
          'Published contents or the retained prefix changed; recovery files retained.',
        );
      }
      await checkpoint?.call();
      _check();
      // Recheck every path and snapshot after the final asynchronous boundary.
      // Delete exactly the verified payload, then only its empty directory.
      checkParents();
      checkPrivateDirectory();
      if (FileSystemEntity.typeSync(destination, followLinks: false) !=
              FileSystemEntityType.file ||
          !sameStat(destinationBefore, FileStat.statSync(destination))) {
        throw StateError(
          'The published destination changed during recovery cleanup.',
        );
      }
      if (stageBefore != null) {
        if (FileSystemEntity.typeSync(stagePath, followLinks: false) !=
                FileSystemEntityType.file ||
            !sameStat(stageBefore, FileStat.statSync(stagePath))) {
          throw StateError(
            'The retained payload changed during recovery cleanup.',
          );
        }
        File(stagePath).deleteSync();
      } else if (FileSystemEntity.typeSync(stagePath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('A new payload appeared during recovery cleanup.');
      }
      Directory(stageDirectory).deleteSync();
    });
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    _check();
    await service.withFileOperationAccess(
      path,
      () => supportsNativeMetadata
          ? writeNativeMetadata(path, TransferMetadata(modified: modified))
          : File(path).setLastModified(modified),
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

class _NativeStageDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

class CloudOperationBackend extends FileOperationBackend {
  CloudOperationBackend(this.client, {required bool Function() isCurrent})
    // Keep the public named callback while storing it privately.
    // ignore: prefer_initializing_formals
    : _isCurrent = isCurrent;
  final CloudStorageClient client;
  final bool Function() _isCurrent;
  @override
  Object get identity => storageReferenceForClient(client).id;
  @override
  String get persistentStorageId => storageReferenceForClient(client).id;
  @override
  StorageReference get storageReference => storageReferenceForClient(client);
  @override
  bool get canRecover => storageReferenceForClient(client).persistent;
  @override
  bool get supportsStagedVerification => true;
  @override
  StorageTransferCapabilities get capabilities => client.transferCapabilities;
  @override
  bool get supportsModifiedTime => capabilities.setModifiedTime;
  @override
  bool get supportsSymbolicLinks => capabilities.symbolicLinks;
  @override
  bool get statRequiresDirectoryListing => true;
  @override
  bool isRootPath(String path) => path == '/' || path == client.rootPath;
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
    final result = client is FreshCloudDirectoryReader
        ? await (client as FreshCloudDirectoryReader).readDirectoryForEdit(path)
        : await client.listPath(path);
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
        final metadata = item['metadata'];
        final declaredDownloadSize =
            item['downloadSize'] ??
            (metadata is Map ? metadata['downloadSize'] : null);
        int? downloadSize;
        if (declaredDownloadSize != null) {
          if (declaredDownloadSize is! num ||
              !declaredDownloadSize.isFinite ||
              declaredDownloadSize < 0 ||
              declaredDownloadSize != declaredDownloadSize.toInt()) {
            throw StateError('$label returned an invalid download length.');
          }
          downloadSize = declaredDownloadSize.toInt();
        }
        entries.add(
          FileItem(
            name: name,
            path: paths.join(path, name),
            isFolder: group == 'folders',
            uuid: item['uuid']?.toString(),
            // Transformed/encrypted adapters expose the byte count yielded by
            // their stream separately from their stored object size. Retain
            // that original stored size in metadata for provider operations.
            size: downloadSize ?? (item['size'] as num?)?.toInt(),
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
  Future<bool> hasPendingUpload(String path, {int? length}) async {
    _check();
    final operations = client;
    if (!capabilities.resumableUpload ||
        operations is! CloudTransferOperations) {
      return false;
    }
    final pending = await (operations as CloudTransferOperations)
        .hasPendingUpload(path, length: length);
    _check();
    return pending;
  }

  @override
  Future<void> writeConfiguredFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    bool preallocate = false,
    bool retainPartialFileOnFailure = false,
    String? resumeUploadPath,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    if (preallocate) {
      throw UnsupportedError('Cloud storage cannot reserve local disk space.');
    }
    return _writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      resumeUploadPath: resumeUploadPath,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) => _writePreparedFile(
    path,
    data,
    length,
    replace: replace,
    verifyStaged: verifyStaged,
    checkpoint: checkpoint,
  );

  Future<void> _writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    String? resumeUploadPath,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    _check();
    if (client is ObjectStorageNamespace && !_supportsExactRelocation) {
      throw UnsupportedError(
        '$label cannot commit a staged object without overwriting an '
        'unreviewed destination. Exact conditional copy and deletion are required.',
      );
    }
    final initialDestination = await stat(path);
    if (!replace && initialDestination != null) {
      throw StateError('Destination already exists: $path');
    }
    final parent = paths.dirname(path);
    final token = const Uuid().v4();
    if (resumeUploadPath != null) {
      final name = paths.basename(resumeUploadPath);
      if (!paths.isAbsolute(resumeUploadPath) ||
          paths.normalize(resumeUploadPath) != resumeUploadPath ||
          paths.dirname(resumeUploadPath) != parent ||
          !RegExp(
            r'^\.crisp-transfer-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.tmp$',
          ).hasMatch(name) ||
          !await hasPendingUpload(resumeUploadPath, length: length) ||
          await stat(resumeUploadPath) != null) {
        throw StateError(
          'The saved multipart upload is no longer usable. Review and restart this item.',
        );
      }
    }
    final stagedName = resumeUploadPath == null
        ? '.crisp-transfer-$token.tmp'
        : paths.basename(resumeUploadPath);
    final stagedPath = resumeUploadPath ?? paths.join(parent, stagedName);
    final backupName = '.crisp-replaced-$token.bak';
    final backupPath = paths.join(parent, backupName);
    var backupRenameAttempted = false;
    var originalBackedUp = false;
    var committed = false;
    var commitAttempted = false;
    FileItem? capturedStage;
    FileItem? capturedBackup;
    var backupVerified = false;
    var received = 0;
    TransferSpool? spool;
    await checkpoint?.call({
      'phase': 'uploading',
      'multipartUploadPending':
          capabilities.resumableUpload && length != null && length > 0,
      'destination': path,
      'stagedPath': stagedPath,
      'backupPath': backupPath,
    });
    try {
      if (length == null) {
        spool = await createTransferSpool(
          data,
          checkpoint: () async => _check(),
        );
        length = spool.length;
        data = spool.openRead();
        if (capabilities.resumableUpload && length > 0) {
          await checkpoint?.call({
            'phase': 'uploading',
            'multipartUploadPending': true,
            'destination': path,
            'stagedPath': stagedPath,
            'backupPath': backupPath,
          });
        }
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
      capturedStage = staged;
      await verifyStaged?.call(staged);
      await checkpoint?.call({
        'phase': 'staged',
        'multipartUploadPending': false,
        'destination': path,
        'stagedPath': stagedPath,
        'backupPath': backupPath,
      });
      final existing = await stat(path);
      if (!_sameCapturedFile(initialDestination, existing)) {
        throw StateError('Destination changed while uploading: $path');
      }
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
        capturedBackup = await _relocateStagedFile(
          existing,
          backupPath,
          checkpoint: (state) async => checkpoint?.call({
            'destination': path,
            'stagedPath': stagedPath,
            'backupPath': backupPath,
            ...state,
          }),
          purpose: 'backup',
          confirmedCopy: (file) {
            capturedBackup = file;
            backupVerified = true;
          },
        );
        backupVerified = true;
        originalBackedUp = true;
        await checkpoint?.call({
          'phase': 'backedUp',
          'destination': path,
          'stagedPath': stagedPath,
          'backupPath': backupPath,
          // Native moves do not pass through backupCopied. Persist the
          // verified destination revision for either relocation route.
          'backupVersion': _fileVersion(capturedBackup!),
          'backupId': capturedBackup!.uuid,
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
      commitAttempted = true;
      await _relocateStagedFile(
        staged,
        path,
        checkpoint: (state) async => checkpoint?.call({
          'destination': path,
          'stagedPath': stagedPath,
          'backupPath': originalBackedUp ? backupPath : null,
          ...state,
        }),
        purpose: 'commit',
      );
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
          await _deleteCapturedFile(capturedBackup!);
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
          capturedBackup = await stat(backupPath);
          originalBackedUp = capturedBackup != null;
        } catch (_) {
          throw StateError(
            '$error. The backup rename could not be confirmed. '
            'Check $path and $backupPath before retrying.',
          );
        }
      }
      if (originalBackedUp && backupVerified && !committed && isCurrent) {
        try {
          if (await stat(path) == null) {
            _check();
            capturedBackup ??= await stat(backupPath);
            final backupToRestore = capturedBackup;
            if (backupToRestore == null) {
              throw StateError('The recovery backup disappeared.');
            }
            await checkpoint?.call({
              'phase': 'restoringBackup',
              'destination': path,
              'stagedPath': stagedPath,
              'backupPath': backupPath,
            });
            final restored = await _relocateStagedFile(
              backupToRestore,
              path,
              checkpoint: (state) async => checkpoint?.call({
                'destination': path,
                'stagedPath': stagedPath,
                'backupPath': backupPath,
                ...state,
              }),
              purpose: 'restore',
            );
            originalBackedUp = false;
            if (capabilities.nativeMove &&
                capabilities.atomicMove &&
                capabilities.noReplaceMove) {
              // A rename may change the provider revision. Record the verified
              // restored revision so a later reviewed retry can recognize it.
              await checkpoint?.call({
                'phase': 'restoringBackup',
                'destination': path,
                'stagedPath': stagedPath,
                'backupPath': backupPath,
                'restoreMovePath': path,
                'restoreMoveVersion': _fileVersion(restored),
                'restoreMoveId': restored.uuid,
              });
            }
          }
        } catch (_) {
          /* Report the preserved recovery location below. */
        }
      }
      if (originalBackedUp && !committed) {
        throw StateError(
          backupVerified
              ? '$error. The original destination is preserved at $backupPath'
              : '$error. A possible recovery copy remains at $backupPath. '
                    'Verify it before restoring.',
        );
      }
      rethrow;
    } finally {
      await spool?.dispose();
      // Account changes prohibit even cleanup against the replacement account.
      if (isCurrent && !committed && !commitAttempted) {
        try {
          final remaining = await stat(stagedPath);
          if (remaining != null &&
              (capturedStage == null ||
                  _sameCapturedFile(capturedStage, remaining))) {
            _check();
            await _deleteCapturedFile(remaining);
          }
        } catch (_) {
          /* Preserve the original failure and any recoverable stage. */
        }
      }
    }
  }

  bool get _supportsExactRelocation =>
      client is CloudTransferOperations &&
      ((capabilities.nativeMove &&
              capabilities.atomicMove &&
              capabilities.noReplaceMove) ||
          (capabilities.nativeCopy &&
              capabilities.noReplaceCopy &&
              capabilities.conditionalCopy &&
              capabilities.conditionalDelete));

  bool _sameCapturedFile(FileItem? before, FileItem? after) {
    if (before == null || after == null) return before == after;
    return before.isFolder == after.isFolder &&
        (before.isSymlink == true) == (after.isSymlink == true) &&
        before.size == after.size &&
        _fileVersion(before) == _fileVersion(after) &&
        before.uuid == after.uuid &&
        (before.updatedAt == null
            ? after.updatedAt == null
            : after.updatedAt != null &&
                  before.updatedAt!.isAtSameMomentAs(after.updatedAt!));
  }

  Future<void> _deleteCapturedFile(FileItem file) async {
    _check();
    final current = await stat(file.path!);
    if (current == null) return;
    if (!_sameCapturedFile(file, current)) {
      throw StateError('File changed before cleanup: ${file.path}');
    }
    await deleteFile(file);
  }

  /// Object storage renames are two mutations. Confirm and durably record the
  /// new object's version before conditionally deleting the captured source.
  /// Every target is vacant: a concurrent writer must never be overwritten.
  Future<FileItem> _relocateStagedFile(
    FileItem source,
    String destination, {
    required String purpose,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
    void Function(FileItem)? confirmedCopy,
  }) async {
    _check();
    String? confirmedVersion;
    String? confirmedId;
    if (await stat(destination) != null) {
      throw StateError('Destination changed while committing: $destination');
    }
    final current = await stat(source.path!);
    if (!_sameCapturedFile(source, current)) {
      throw StateError('File changed before $purpose: ${source.path}');
    }
    _check();
    if (!_supportsExactRelocation) {
      // Hierarchical legacy protocols keep their existing rename contract.
      // Virtual object prefixes must never enter this compatibility path.
      if (client is ObjectStorageNamespace) {
        throw UnsupportedError(
          'Exact conditional object relocation is unavailable.',
        );
      }
      await client.renamePath(source.path!, paths.basename(destination));
    } else {
      final operations = client as CloudTransferOperations;
      if (capabilities.nativeMove &&
          capabilities.atomicMove &&
          capabilities.noReplaceMove) {
        final result = await operations.moveToExact(
          source.path!,
          destination,
          checkpoint: () async => _check(),
          expectedSourceVersion: capabilities.conditionalMove
              ? _fileVersion(source)
              : null,
        );
        if (destinationPathKey(result.path) !=
            destinationPathKey(destination)) {
          throw StateError('Provider moved the file to an unexpected path.');
        }
        confirmedVersion = result.version;
        confirmedId = result.id;
      } else {
        final version = _fileVersion(source);
        if (version == null) {
          throw UnsupportedError(
            'Conditional $purpose requires a captured object version.',
          );
        }
        final result = await operations.copyToExact(
          source.path!,
          destination,
          expectedSourceVersion: version,
          checkpoint: () async => _check(),
        );
        _check();
        if (destinationPathKey(result.path) !=
                destinationPathKey(destination) ||
            result.version == null) {
          throw StateError(
            'Provider did not confirm the exact copied object version.',
          );
        }
        final copied = await stat(destination);
        if (copied == null ||
            copied.isFolder ||
            copied.isSymlink == true ||
            _fileVersion(copied) != result.version ||
            (source.size != null && copied.size != source.size)) {
          throw StateError(
            'The copied $purpose object changed before source cleanup.',
          );
        }
        confirmedVersion = result.version;
        confirmedId = result.id;
        confirmedCopy?.call(copied);
        await checkpoint?.call({
          'phase': '${purpose}Copied',
          '${purpose}SourcePath': source.path,
          '${purpose}SourceVersion': version,
          '${purpose}CopyPath': destination,
          '${purpose}CopyVersion': result.version,
        });
        _check();
        try {
          await operations.deleteTransferFile(
            source.path!,
            expectedVersion: version,
          );
        } catch (_) {
          // A delete reply may be lost. Accept only absence and the exact
          // confirmed destination revision; otherwise preserve both copies.
          _check();
          if (await stat(source.path!) != null ||
              !_sameCapturedFile(copied, await stat(destination))) {
            rethrow;
          }
        }
      }
    }
    _check();
    final moved = await stat(destination);
    if (moved == null ||
        moved.isFolder ||
        moved.isSymlink == true ||
        (confirmedVersion != null && _fileVersion(moved) != confirmedVersion) ||
        (confirmedId != null && moved.uuid != confirmedId) ||
        (source.size != null && moved.size != source.size)) {
      throw StateError('The $purpose destination could not be verified.');
    }
    confirmedCopy?.call(moved);
    return moved;
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
      expectedSourceVersion: capabilities.conditionalMove
          ? _fileVersion(file)
          : null,
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
    if (!capabilities.nativeCopy ||
        !capabilities.noReplaceCopy ||
        client is! CloudTransferOperations) {
      return false;
    }
    // A replacement still uses staging/backup in writeFile. Native adapters
    // must guarantee exact-name, no-clobber semantics for this direct fast path.
    if (replace) return false;
    late CloudTransferResult result;
    try {
      result = await (client as CloudTransferOperations).copyToExact(
        file.path!,
        destination,
        expectedSourceVersion: capabilities.conditionalCopy
            ? _fileVersion(file)
            : null,
        checkpoint: checkpoint,
      );
    } on UnsupportedError {
      // Adapters may decline a large object or an unsupported conditional
      // operation before mutation. Stream the same reviewed item instead.
      return false;
    }
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
      expectedVersion: file.metadata?['rangeReadSnapshot'] is String
          ? file.metadata!['rangeReadSnapshot'] as String
          : _fileVersion(file),
    );
  }

  String? _fileVersion(FileItem file) {
    for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
      if (file.metadata?[key] != null) return file.metadata![key].toString();
    }
    return null;
  }
}
