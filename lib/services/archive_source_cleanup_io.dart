import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../models/file_item.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'storage_transfer_contract.dart';

/// Private evidence is captured during preview, checked around the import read,
/// and required again after publication. It never enters a recovery journal.
Future<Object?> captureNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source,
) async {
  if (backend is! LocalOperationBackend || source.isFolder) return null;
  return backend.service.withFileOperationAccess(source.path!, () async {
    if (!backend.isCurrent) throw StateError('Source account changed.');
    final result = _nativeSnapshot(backend, source);
    if (!backend.isCurrent) throw StateError('Source account changed.');
    return result;
  });
}

Future<void> verifyNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source,
  Object? captured,
) async {
  if (backend is! LocalOperationBackend || source.isFolder) return;
  if (captured is! _NativeImportSnapshot ||
      await captureNativeArchiveImportSource(backend, source) != captured) {
    throw StateError('The original native source identity changed.');
  }
}

_NativeImportSnapshot _nativeSnapshot(
  LocalOperationBackend backend,
  FileItem source,
) {
  final path = source.path!;
  var parent = backend.paths.dirname(path);
  while (true) {
    if (FileSystemEntity.typeSync(parent, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Source parent changed.');
    }
    final next = backend.paths.dirname(parent);
    if (next == parent) break;
    parent = next;
  }
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('Source is no longer a regular file.');
  }
  final value = FileStat.statSync(path);
  if (value.size != source.size ||
      source.updatedAt != null && value.modified != source.updatedAt) {
    throw StateError('Source snapshot changed.');
  }
  return _NativeImportSnapshot(path, value);
}

class _NativeImportSnapshot {
  const _NativeImportSnapshot(this.path, this.stat);
  final String path;
  final FileStat stat;
  @override
  bool operator ==(Object other) =>
      other is _NativeImportSnapshot &&
      path == other.path &&
      stat.type == other.stat.type &&
      stat.size == other.stat.size &&
      stat.modified == other.stat.modified &&
      stat.changed == other.stat.changed &&
      stat.mode == other.stat.mode;
  @override
  int get hashCode => Object.hash(
    path,
    stat.type,
    stat.size,
    stat.modified,
    stat.changed,
    stat.mode,
  );
}

/// Exact unlink after bounded content verification; no asynchronous path lookup
/// occurs between the final no-follow checks and deletion. Never recursive.
Future<bool> deleteNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source, {
  required String sha256,
  required TransferCheckpoint checkpoint,
  required TransferCheckpoint verifyPublication,
  required Object? capturedIdentity,
}) async {
  if (backend is! LocalOperationBackend) return false;
  final path = source.path!;
  await backend.service.withFileOperationAccess(path, () async {
    void parents() {
      var parent = backend.paths.dirname(path);
      while (true) {
        if (FileSystemEntity.typeSync(parent, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw StateError('Source parent changed.');
        }
        final next = backend.paths.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
    }

    FileStat snapshot() {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('Source is no longer a regular file.');
      }
      final value = FileStat.statSync(path);
      if (value.size != source.size ||
          source.updatedAt != null && value.modified != source.updatedAt) {
        throw StateError('Source snapshot changed.');
      }
      return value;
    }

    await checkpoint();
    parents();
    final before = snapshot();
    if (capturedIdentity is! _NativeImportSnapshot ||
        _nativeSnapshot(backend, source) != capturedIdentity) {
      throw StateError(
        'The original native source identity changed after import.',
      );
    }
    var count = 0;
    final hash = await crypto.sha256
        .bind(
          File(path).openRead(0, before.size + 1).asyncMap((bytes) async {
            await checkpoint();
            if ((count += bytes.length) > before.size) {
              throw StateError('Source grew while verifying.');
            }
            return bytes;
          }),
        )
        .first;
    if (count != before.size || hash.toString() != sha256) {
      throw StateError('Source contents changed.');
    }
    await verifyPublication();
    await checkpoint();
    parents();
    final after = snapshot();
    if (_nativeSnapshot(backend, source) != capturedIdentity) {
      throw StateError('The original native source changed before deletion.');
    }
    if (!backend.isCurrent ||
        before.changed != after.changed ||
        before.mode != after.mode ||
        before.modified != after.modified ||
        before.size != after.size) {
      throw StateError('Source changed before deletion.');
    }
    File(path).deleteSync();
  });
  return true;
}
