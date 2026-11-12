import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_output_spool.dart';
import 'archive_types.dart';

const _memoryLimit = 256 * 1024 * 1024;

Future<ArchiveOutputSpool> createArchiveOutputSpool({
  required int maxBytes,
}) async {
  validateArchiveSpoolLimit(maxBytes);
  return _MemorySpool(maxBytes < _memoryLimit ? maxBytes : _memoryLimit);
}

class _MemorySpool extends ArchiveOutputSpool {
  _MemorySpool(this.maxBytes);
  @override
  final int maxBytes;
  final _chunks = <Uint8List>[];
  final _offsets = <int>[];
  int _length = 0;
  @override
  int get length => _length;
  bool _finished = false, _disposed = false, _failed = false;
  @override
  bool get isSealed => _finished && !_disposed && !_failed;

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

  @override
  Future<void> write(List<int> bytes) async {
    _alive();
    if (_finished) throw StateError('Archive output is already sealed.');
    if (bytes.length > maxBytes - _length) {
      _failed = true;
      throw const ArchiveViewException(
        'Created archive exceeds the browser output limit.',
      );
    }
    if (bytes is! Uint8List && bytes.any((byte) => byte < 0 || byte > 255)) {
      _failed = true;
      throw const ArchiveViewException('Archive writer emitted invalid bytes.');
    }
    for (var at = 0; at < bytes.length; at += 256 * 1024) {
      final end = at + 256 * 1024 < bytes.length
          ? at + 256 * 1024
          : bytes.length;
      _offsets.add(_length);
      final copy = Uint8List.fromList(bytes.sublist(at, end));
      _chunks.add(copy);
      _length += copy.length;
    }
  }

  @override
  Future<void> finish() async {
    _alive();
    _finished = true;
  }

  @override
  Future<koni.ByteSource> openByteSource() async {
    _readable();
    return _MemorySource(this, length);
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
  Future<void> dispose() async {
    _disposed = true;
    _chunks.clear();
    _offsets.clear();
  }
}

class _MemorySource implements koni.ByteSource {
  _MemorySource(this.owner, this.length);
  final _MemorySpool owner;
  @override
  final int length;
  @override
  String get name => 'created-archive';
  bool _closed = false;
  @override
  Future<Uint8List> read(int offset, int count) async {
    owner._readable();
    if (_closed) throw StateError('Archive spool source was closed.');
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw RangeError('A read leaves the archive output.');
    }
    if (count > 256 * 1024 * 1024) {
      throw const ArchiveViewException(
        'Archive spool reads are limited to 256 MiB.',
      );
    }
    final bytes = Uint8List(count);
    if (count == 0) return bytes;
    var low = 0, high = owner._offsets.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (owner._offsets[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var copied = 0;
    for (var i = low - 1; i < owner._chunks.length && copied < count; i++) {
      final chunk = owner._chunks[i];
      final from = offset + copied - owner._offsets[i];
      final available = chunk.length - from;
      final take = available < count - copied ? available : count - copied;
      bytes.setRange(copied, copied + take, chunk, from);
      copied += take;
    }
    if (copied != count) {
      throw StateError('Archive spool chunks are incomplete.');
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
