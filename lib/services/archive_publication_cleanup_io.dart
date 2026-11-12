import 'dart:io';

import '../utils/system_links.dart';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'storage_transfer_contract.dart';

/// Native cleanup has no async path lookup between its final snapshot checks
/// and exact unlink. It never traverses symlinks or recursively removes paths.
Future<bool> deleteNativeArchiveRecoveryFile(
  FileOperationBackend backend,
  FileItem recovery,
  FileItem published, {
  required String recoverySha256,
  required String publishedSha256,
  required TransferCheckpoint checkpoint,
  TransferCheckpoint? beforeDelete,
}) async {
  if (backend is! LocalOperationBackend) return false;
  final path = recovery.path!, destination = published.path!;
  if (backend.paths.dirname(path) != backend.paths.dirname(destination)) {
    throw StateError('Recovery cleanup escaped its container directory.');
  }
  await backend.service.withFileOperationAccess(
    backend.paths.dirname(path),
    () async {
      void parents() {
        var parent = backend.paths.dirname(path);
        while (true) {
          if (entityTypeTrustingSystemLinksSync(parent) !=
              FileSystemEntityType.directory) {
            throw StateError('Recovery cleanup parent changed.');
          }
          final next = backend.paths.dirname(parent);
          if (next == parent) break;
          parent = next;
        }
      }

      FileStat snapshot(String name, FileItem expected) {
        if (FileSystemEntity.typeSync(name, followLinks: false) !=
            FileSystemEntityType.file) {
          throw StateError('Recovery cleanup requires regular files.');
        }
        final stat = FileStat.statSync(name);
        if (stat.size != expected.size ||
            expected.updatedAt != null && stat.modified != expected.updatedAt) {
          throw StateError('Recovery cleanup file changed.');
        }
        return stat;
      }

      bool same(FileStat a, FileStat b) =>
          a.type == b.type &&
          a.size == b.size &&
          a.modified == b.modified &&
          a.changed == b.changed &&
          a.mode == b.mode;
      await checkpoint();
      parents();
      final before = snapshot(path, recovery),
          destinationBefore = snapshot(destination, published);
      Future<String> digest(String name, int expected) async {
        var received = 0;
        final result =
            (await sha256
                    .bind(
                      File(name)
                          .openRead(0, expected + 1)
                          .asyncMap((chunk) async {
                            await checkpoint();
                            received += chunk.length;
                            if (received > expected) {
                              throw StateError(
                                'Recovery cleanup file grew while reading.',
                              );
                            }
                            return chunk;
                          }),
                    )
                    .first)
                .toString();
        if (received != expected) {
          throw StateError('Recovery cleanup file size changed.');
        }
        return result;
      }

      if (await digest(path, before.size) != recoverySha256 ||
          await digest(destination, destinationBefore.size) !=
              publishedSha256) {
        throw StateError('Recovery cleanup contents changed.');
      }
      await checkpoint();
      await beforeDelete?.call();
      parents();
      if (!same(before, snapshot(path, recovery)) ||
          !same(destinationBefore, snapshot(destination, published))) {
        throw StateError('Recovery cleanup snapshot changed.');
      }
      File(path).deleteSync();
    },
  );
  return true;
}
