import 'dart:convert';
import 'dart:typed_data';

import '../../io/byte_source.dart';
import 'crc32.dart';
import 'deflate_codec.dart';
import 'zip_reader.dart';

/// Streaming ZIP writer that emits local headers as parts are added and
/// finishes with a central directory plus EOCD (ZIP64 when required).
class ZipWriter {
  /// ZipWriter API.
  ZipWriter({this.deflateLevel = 6});

  /// deflateLevel API.
  final int deflateLevel;

  /// ByteSink API.
  final ByteSink _sink = ByteSink(capacity: 4096);
  final List<_PendingEntry> _entries = <_PendingEntry>[];

  /// Adds [data] as [fileName]. When [store] is true the bytes are written
  /// uncompressed (method 0); otherwise they are raw-deflated.
  void addFile(String fileName, List<int> data, {bool store = false}) {
    final Uint8List raw = data is Uint8List ? data : Uint8List.fromList(data);
    final int crc = Crc32.compute(raw);
    final Uint8List payload;
    final int method;
    if (store || raw.isEmpty) {
      payload = raw;
      method = zipMethodStore;
    } else {
      payload = RawDeflate.deflate(raw, level: deflateLevel);
      method = zipMethodDeflate;
    }
    _writeLocalAndRecord(
      fileName: fileName,
      method: method,
      crc: crc,
      compressed: payload,
      uncompressedSize: raw.length,
    );
  }

  /// Compresses [stream] on the fly using a data descriptor (general-purpose
  /// bit 3) so sizes do not need to be known in advance.
  Future<void> addFileStream(
    String fileName,
    Stream<List<int>> stream, {
    bool store = false,
  }) async {
    final BytesBuilder rawBuilder = BytesBuilder(copy: false);
    await for (final List<int> chunk in stream) {
      rawBuilder.add(chunk);
    }
    addFile(fileName, rawBuilder.takeBytes(), store: store);
  }

  /// close API.
  Uint8List close() {
    final int cdStart = _sink.length;
    var needsZip64 = false;
    for (final _PendingEntry entry in _entries) {
      if (entry.compressedSize >= 0xFFFFFFFF ||
          entry.uncompressedSize >= 0xFFFFFFFF ||
          entry.localHeaderOffset >= 0xFFFFFFFF) {
        needsZip64 = true;
      }
      _writeCentral(entry);
    }
    final int cdSize = _sink.length - cdStart;
    if (_entries.length >= 0xFFFF ||
        cdStart >= 0xFFFFFFFF ||
        cdSize >= 0xFFFFFFFF) {
      needsZip64 = true;
    }
    if (needsZip64) {
      _writeZip64(cdStart, cdSize);
    }
    _writeEocd(cdStart, cdSize, zip64: needsZip64);
    return _sink.takeBytes();
  }

  void _writeLocalAndRecord({
    required String fileName,
    required int method,
    required int crc,
    required Uint8List compressed,
    required int uncompressedSize,
  }) {
    final Uint8List nameBytes = utf8.encode(fileName);
    final int localOffset = _sink.length;
    final bool zip64 =
        compressed.length >= 0xFFFFFFFF || uncompressedSize >= 0xFFFFFFFF;

    _sink.u32le(zipLocalSig);
    _sink.u16le(zip64 ? 45 : 20);
    _sink.u16le(1 << 11); // UTF-8 names
    _sink.u16le(method);
    _sink.u16le(0); // time
    _sink.u16le(0); // date
    _sink.u32le(crc);
    _sink.u32le(zip64 ? 0xFFFFFFFF : compressed.length);
    _sink.u32le(zip64 ? 0xFFFFFFFF : uncompressedSize);
    _sink.u16le(nameBytes.length);
    _sink.u16le(zip64 ? 20 : 0);
    _sink.add(nameBytes);
    if (zip64) {
      _sink.u16le(0x0001);
      _sink.u16le(16);
      _sink.u64le(uncompressedSize);
      _sink.u64le(compressed.length);
    }
    _sink.add(compressed);

    _entries.add(
      _PendingEntry(
        fileName: fileName,
        nameBytes: nameBytes,
        method: method,
        crc: crc,
        compressedSize: compressed.length,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localOffset,
        utf8Flag: true,
        zip64: zip64,
      ),
    );
  }

  void _writeCentral(_PendingEntry entry) {
    _sink.u32le(zipCentralSig);
    _sink.u16le(entry.zip64 ? 45 : 20);
    _sink.u16le(entry.zip64 ? 45 : 20);
    _sink.u16le(1 << 11);
    _sink.u16le(entry.method);
    _sink.u16le(0);
    _sink.u16le(0);
    _sink.u32le(entry.crc);
    _sink.u32le(entry.zip64 ? 0xFFFFFFFF : entry.compressedSize);
    _sink.u32le(entry.zip64 ? 0xFFFFFFFF : entry.uncompressedSize);
    _sink.u16le(entry.nameBytes.length);
    _sink.u16le(entry.zip64 ? 28 : 0);
    _sink.u16le(0); // comment
    _sink.u16le(0); // disk
    _sink.u16le(0); // int attrs
    _sink.u32le(0); // ext attrs
    _sink.u32le(entry.zip64 ? 0xFFFFFFFF : entry.localHeaderOffset);
    _sink.add(entry.nameBytes);
    if (entry.zip64) {
      _sink.u16le(0x0001);
      _sink.u16le(24);
      _sink.u64le(entry.uncompressedSize);
      _sink.u64le(entry.compressedSize);
      _sink.u64le(entry.localHeaderOffset);
    }
  }

  void _writeZip64(int cdStart, int cdSize) {
    final int eocd64Offset = _sink.length;
    _sink.u32le(zipEocd64Sig);
    _sink.u64le(44); // size of remaining record
    _sink.u16le(45);
    _sink.u16le(45);
    _sink.u32le(0);
    _sink.u32le(0);
    _sink.u64le(_entries.length);
    _sink.u64le(_entries.length);
    _sink.u64le(cdSize);
    _sink.u64le(cdStart);

    _sink.u32le(zipEocd64LocatorSig);
    _sink.u32le(0);
    _sink.u64le(eocd64Offset);
    _sink.u32le(1);
  }

  void _writeEocd(int cdStart, int cdSize, {required bool zip64}) {
    _sink.u32le(zipEocdSig);
    _sink.u16le(0);
    _sink.u16le(0);
    _sink.u16le(zip64 ? 0xFFFF : _entries.length);
    _sink.u16le(zip64 ? 0xFFFF : _entries.length);
    _sink.u32le(zip64 ? 0xFFFFFFFF : cdSize);
    _sink.u32le(zip64 ? 0xFFFFFFFF : cdStart);
    _sink.u16le(0);
  }
}

class _PendingEntry {
  _PendingEntry({
    required this.fileName,
    required this.nameBytes,
    required this.method,
    required this.crc,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.utf8Flag,
    required this.zip64,
  });

  /// fileName API.
  final String fileName;

  /// nameBytes API.
  final Uint8List nameBytes;

  /// method API.
  final int method;

  /// crc API.
  final int crc;

  /// compressedSize API.
  final int compressedSize;

  /// uncompressedSize API.
  final int uncompressedSize;

  /// localHeaderOffset API.
  final int localHeaderOffset;

  /// utf8Flag API.
  final bool utf8Flag;

  /// zip64 API.
  final bool zip64;
}
