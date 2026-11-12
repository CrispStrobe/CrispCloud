// Apple's block-compression framing (compression_tool): "pbzx", a big-endian
// block size, then pairs of uncompressed/stored sizes and stored or XZ data.
// These integers are sizes, not continuation flags. See the format references
// and independent fixture provenance in docs/archive-format-coverage.md.

import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const kPbzxChunkLimit = 16 * 1024 * 1024;
const kPbzxDecodedLimit = 2 * 1024 * 1024 * 1024;
const _maxChunks = 100000;

/// A positional view of a PBZX stream. Indexing reads only framing metadata;
/// reads decode at most one bounded XZ chunk at a time. The source owns its
/// parent and keeps one shared chunk cache, including for concurrent readers.
/// Present XZ checksums are verified when read. Stored chunks and XZ streams
/// using CHECK_NONE have no data checksum; this is not publisher verification.
class ArchivePbzxSource implements koni.ByteSource {
  ArchivePbzxSource._(
    this._parent,
    this._chunks,
    this.length,
    this.name,
    this._maxReadBytes,
  );

  final koni.ByteSource _parent;
  final List<_Chunk> _chunks;
  @override
  final int length;
  @override
  final String? name;
  final int _maxReadBytes;
  var _closed = false;
  var _cachedIndex = -1;
  Uint8List? _cached;
  Future<void> _queue = Future<void>.value();

  static Future<ArchivePbzxSource> open(
    koni.ByteSource source, {
    String? name,
    int maxChunkBytes = kPbzxChunkLimit,
    int maxDecodedBytes = kPbzxDecodedLimit,
    int maxReadBytes = kArchiveReadLimit,
  }) async {
    try {
      if (maxChunkBytes <= 0 ||
          maxChunkBytes > kPbzxChunkLimit ||
          maxDecodedBytes <= 0 ||
          maxDecodedBytes > kPbzxDecodedLimit ||
          maxReadBytes <= 0 ||
          maxReadBytes > kArchiveReadLimit) {
        throw ArgumentError('Invalid PBZX resource limits.');
      }
      if (source.length < 12 || source.length > kPbzxDecodedLimit) {
        throw _bad('Invalid or oversized PBZX input.');
      }
      final header = ByteData.sublistView(await _readExact(source, 0, 12));
      if (header.getUint32(0) != 0x70627a78) {
        throw _bad('Only PBZX block compression is supported.');
      }
      final blockSize = _size(header, 4, maxChunkBytes);
      final chunks = <_Chunk>[];
      var offset = 12;
      var decoded = 0;
      var shortChunk = false;
      while (offset < source.length) {
        if (chunks.length >= _maxChunks) {
          throw _bad('PBZX contains too many chunks.');
        }
        if (shortChunk) {
          throw _bad(
            'Only the final PBZX chunk may be shorter than its block size.',
          );
        }
        final record = ByteData.sublistView(
          await _readExact(source, offset, 16),
        );
        final size = _size(record, 0, blockSize);
        final stored = _size(record, 8, size);
        offset += 16;
        _checkRange(source.length, offset, stored);
        if (size > maxDecodedBytes - decoded) {
          throw _bad('PBZX exceeds the decoded-size safety limit.');
        }
        chunks.add(_Chunk(offset, stored, decoded, size));
        offset += stored;
        decoded += size;
        shortChunk = size < blockSize;
      }
      return ArchivePbzxSource._(
        source,
        List.unmodifiable(chunks),
        decoded,
        name,
        maxReadBytes,
      );
    } catch (error) {
      try {
        await source.close();
      } catch (_) {
        // Preserve the original parse error.
      }
      if (error is ArchiveViewException || error is ArgumentError) rethrow;
      throw _bad('Could not read PBZX framing: $error');
    }
  }

  @override
  Future<Uint8List> read(int offset, int count) {
    _checkOpen();
    _checkRange(length, offset, count);
    if (count > _maxReadBytes) {
      throw _bad('PBZX read exceeds the per-read safety limit.');
    }
    // Serializing the complete request avoids concurrent full-folder decodes
    // and keeps a slow underlying read from repopulating the cache after close.
    final next = _queue.then((_) => _read(offset, count));
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Uint8List> _read(int offset, int count) async {
    _checkOpen();
    final output = Uint8List(count);
    if (count == 0) return output;
    var index = _findChunk(offset);
    var written = 0;
    while (written < count) {
      _checkOpen();
      final chunk = _chunks[index];
      final start = offset + written - chunk.decodedOffset;
      final remaining = chunk.size - start;
      final take = remaining < count - written ? remaining : count - written;
      final data = await _decode(index);
      _checkOpen();
      output.setRange(written, written + take, data, start);
      written += take;
      index++;
    }
    return output;
  }

  int _findChunk(int offset) {
    var low = 0, high = _chunks.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      final chunk = _chunks[middle];
      if (chunk.decodedOffset + chunk.size <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Future<Uint8List> _decode(int index) async {
    if (_cachedIndex == index) return _cached!;
    _cached = null;
    _cachedIndex = -1;
    final chunk = _chunks[index];
    final stored = await _readExact(_parent, chunk.offset, chunk.stored);
    _checkOpen();
    final Uint8List data;
    if (chunk.stored == chunk.size) {
      data = stored;
    } else {
      if (stored.length < 6 ||
          stored[0] != 0xfd ||
          stored[1] != 0x37 ||
          stored[2] != 0x7a ||
          stored[3] != 0x58 ||
          stored[4] != 0x5a ||
          stored[5] != 0) {
        throw _bad('A compressed PBZX chunk is not an XZ stream.');
      }
      try {
        data = codec.XZDecoder(
          maxDictionarySize: kPbzxChunkLimit,
          maxPreallocateSize: chunk.size,
        ).decodeBytes(stored, verify: true, maxOutputSize: chunk.size);
      } catch (error) {
        throw _bad('Could not verify a PBZX XZ chunk: $error');
      }
      if (data.length != chunk.size) {
        throw _bad('PBZX chunk size does not match its decoded content.');
      }
    }
    _checkOpen();
    _cached = data;
    _cachedIndex = index;
    return data;
  }

  void _checkOpen() {
    if (_closed) throw _bad('This PBZX source is closed.');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cached = null;
    _cachedIndex = -1;
    await _parent.close();
  }
}

class _Chunk {
  const _Chunk(this.offset, this.stored, this.decodedOffset, this.size);
  final int offset, stored, decodedOffset, size;
}

int _size(ByteData data, int offset, int max) {
  // Read high/low words separately: a hostile uint64 must never wrap on the
  // VM or lose precision when the same reader is compiled for JavaScript.
  final high = data.getUint32(offset), low = data.getUint32(offset + 4);
  if (high != 0 || low == 0 || low > max) {
    throw _bad('Invalid or oversized PBZX chunk size.');
  }
  return low;
}

void _checkRange(int total, int offset, int count) {
  if (offset < 0 || count < 0 || offset > total || count > total - offset) {
    throw _bad('PBZX chunk or read leaves the available input.');
  }
}

Future<Uint8List> _readExact(
  koni.ByteSource source,
  int offset,
  int count,
) async {
  _checkRange(source.length, offset, count);
  final bytes = await source.read(offset, count);
  if (bytes.length != count) throw _bad('The PBZX source is truncated.');
  return bytes;
}

ArchiveViewException _bad(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': detail},
);
