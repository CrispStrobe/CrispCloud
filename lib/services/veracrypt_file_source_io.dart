// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';
import 'local_file_service.dart';

/// Opens one regular file with an independent access scope for its lifetime.
/// Reads are serialized and fail if the captured file is replaced or changed.
Future<koni.ByteSource> openVeraCryptFileSource(String path) async {
  final local = LocalFileService();
  if (!await local.beginStreamAccess(path)) {
    throw const ArchiveViewException('Container file access was not granted.');
  }
  RandomAccessFile? handle;
  try {
    final file = File(path);
    final snapshot = await file.stat();
    if (snapshot.type != FileSystemEntityType.file ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const ArchiveViewException('A container must be a regular file.');
    }
    handle = await file.open(mode: FileMode.read);
    final result = _ContainerFileSource(file, handle, snapshot, local);
    await result.checkUnchanged();
    return result;
  } catch (_) {
    try {
      await handle?.close();
    } finally {
      await local.endStreamAccess();
    }
    rethrow;
  }
}

class _ContainerFileSource implements koni.ByteSource {
  _ContainerFileSource(this.file, this.handle, this.snapshot, this.local);
  final File file;
  final RandomAccessFile handle;
  final FileStat snapshot;
  final LocalFileService local;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  @override
  int get length => snapshot.size;
  @override
  String get name => file.path;

  Future<void> checkUnchanged() async {
    if (_closed) throw const ArchiveViewException('Container file is closed.');
    final current = await file.stat();
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        current.type != snapshot.type ||
        current.size != snapshot.size ||
        current.modified != snapshot.modified ||
        current.changed != snapshot.changed ||
        await handle.length() != snapshot.size) {
      throw const ArchiveViewException(
        'The container file changed. Close and reopen it before reading.',
      );
    }
    if (_closed) throw const ArchiveViewException('Container file is closed.');
  }

  @override
  Future<Uint8List> read(int offset, int count) {
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        if (offset < 0 ||
            count < 0 ||
            offset > length ||
            count > length - offset ||
            count > 64 * 1024) {
          throw const ArchiveViewException('Invalid bounded container read.');
        }
        await checkUnchanged();
        await handle.setPosition(offset);
        final bytes = Uint8List(count);
        var read = 0;
        while (read < count) {
          final received = await handle.readInto(bytes, read);
          if (received == 0) {
            throw const ArchiveViewException(
              'The container file is truncated.',
            );
          }
          read += received;
        }
        await checkUnchanged();
        result.complete(bytes);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _tail.then((_) async {
      try {
        await handle.close();
      } finally {
        await local.endStreamAccess();
      }
    });
  }
}
