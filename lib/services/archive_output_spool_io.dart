import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as path;

import 'archive_output_spool.dart';
import 'archive_types.dart';

Future<ArchiveOutputSpool> createArchiveOutputSpool({
  required int maxBytes,
}) async {
  validateArchiveSpoolLimit(maxBytes);
  final directory = await Directory.systemTemp.createTemp(
    'crisp-archive-output-',
  );
  try {
    final file = File(path.join(directory.path, 'output'));
    final output = await file.open(mode: FileMode.writeOnly);
    return _NativeSpool(directory, file, output, maxBytes);
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}

class _NativeSpool extends ArchiveOutputSpool {
  _NativeSpool(this.directory, this.file, this.output, this.maxBytes);
  final Directory directory;
  final File file;
  RandomAccessFile? output;
  @override
  final int maxBytes;
  int _length = 0;
  @override
  int get length => _length;
  bool _finished = false, _disposed = false, _failed = false;
  Completer<void>? _operation;
  Future<void>? _disposal;
  final _sources = <_FileSource>{};
  final _openings = <Future<void>>{};

  void _alive() {
    if (_disposed) throw StateError('Archive output spool was disposed.');
    if (_failed) throw StateError('Archive output spool has failed.');
  }

  void _readable() {
    _alive();
    if (!_finished) {
      throw StateError('Finish archive output before reading it.');
    }
  }

  void _begin() {
    _alive();
    if (_finished) throw StateError('Archive output is already sealed.');
    if (_operation != null) {
      throw StateError('Await the previous spool operation.');
    }
    _operation = Completer<void>();
  }

  void _end() {
    _operation!.complete();
    _operation = null;
  }

  @override
  Future<void> write(List<int> bytes) async {
    _begin();
    try {
      if (bytes.length > maxBytes - _length) {
        throw const ArchiveViewException(
          'Created archive exceeds its output limit.',
        );
      }
      if (bytes is! Uint8List && bytes.any((byte) => byte < 0 || byte > 255)) {
        throw const ArchiveViewException(
          'Archive writer emitted invalid bytes.',
        );
      }
      for (var at = 0; at < bytes.length; at += 256 * 1024) {
        _alive();
        final end = at + 256 * 1024 < bytes.length
            ? at + 256 * 1024
            : bytes.length;
        final chunk = Uint8List.fromList(bytes.sublist(at, end));
        await output!.writeFrom(chunk);
        _length += chunk.length;
      }
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _end();
    }
  }

  @override
  Future<void> finish() async {
    _alive();
    if (_finished) return;
    _begin();
    try {
      await output!.flush();
      await output!.close();
      output = null;
      if (await file.length() != _length) {
        throw const ArchiveViewException(
          'Created archive spool changed length.',
        );
      }
      _alive();
      _finished = true;
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _end();
    }
  }

  @override
  Future<koni.ByteSource> openByteSource() async {
    _readable();
    final opening = Completer<void>();
    _openings.add(opening.future);
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      _readable();
      if (await handle.length() != _length) {
        throw const ArchiveViewException(
          'Created archive spool changed length.',
        );
      }
      _readable();
      final source = _FileSource(handle, _length, _readable, _sources.remove);
      _sources.add(source);
      return source;
    } catch (_) {
      await handle?.close();
      rethrow;
    } finally {
      _openings.remove(opening.future);
      opening.complete();
    }
  }

  @override
  Stream<List<int>> openRead({int chunkSize = 256 * 1024}) async* {
    validateArchiveSpoolChunkSize(chunkSize);
    final source = await openByteSource();
    try {
      for (var at = 0; at < length; at += chunkSize) {
        final remaining = length - at;
        yield await source.read(
          at,
          remaining < chunkSize ? remaining : chunkSize,
        );
      }
    } finally {
      await source.close();
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await _operation?.future;
    await Future.wait(_openings.toList());
    Object? failure;
    for (final source in _sources.toList()) {
      try {
        await source.close();
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      await output?.close();
    } catch (error) {
      failure ??= error;
    }
    output = null;
    try {
      await directory.delete(recursive: true);
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }
}

class _FileSource implements koni.ByteSource {
  _FileSource(this.file, this.length, this.checkOwner, this.onClose);
  final RandomAccessFile file;
  @override
  final int length;
  @override
  String get name => 'created-archive';
  final void Function() checkOwner;
  final void Function(_FileSource) onClose;
  bool _closed = false;
  Future<void> _tail = Future.value();
  Future<void>? _closing;

  @override
  Future<Uint8List> read(int offset, int count) {
    final result = _tail.then((_) async {
      checkOwner();
      if (_closed) throw StateError('Archive spool source was closed.');
      if (offset < 0 ||
          count < 0 ||
          offset > length ||
          count > length - offset) {
        throw RangeError('A read leaves the archive output.');
      }
      // Existing buffered compression codecs read their complete bounded
      // container. Disk readers use much smaller positional chunks.
      if (count > 256 * 1024 * 1024) {
        throw const ArchiveViewException(
          'Archive spool reads are limited to 256 MiB.',
        );
      }
      await file.setPosition(offset);
      final bytes = await file.read(count);
      if (bytes.length != count) {
        throw const ArchiveViewException(
          'Created archive spool was truncated.',
        );
      }
      checkOwner();
      return bytes;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _tail;
    try {
      await file.close();
    } finally {
      onClose(this);
    }
  }
}
