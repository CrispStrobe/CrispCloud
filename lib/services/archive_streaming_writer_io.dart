import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_codecs/koni_codecs.dart' show Lzma2Encoder;

import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart' show archiveGzipHeader;
import 'archive_output_spool.dart';
import 'archive_tar_writer.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const _chunkBytes = 256 * 1024;
const _maxMetadataBytes = 32 * 1024 * 1024;
const _zip32 = 0xffffffff;

bool supportsStreamingArchiveWriting(
  ArchiveEndpointFormat format, {
  String? password,
  bool encryptNames = false,
}) =>
    password == null &&
    !encryptNames &&
    const {
      ArchiveEndpointFormat.zip,
      ArchiveEndpointFormat.sevenZip,
      ArchiveEndpointFormat.tar,
      ArchiveEndpointFormat.tarGzip,
      ArchiveEndpointFormat.gzip,
    }.contains(format);

Future<void> writeStreamingArchiveEntries(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  Uint8List? gzipHeader,
  int level = 6,
  String? password,
  bool encryptNames = false,
  bool Function()? isCancelled,
}) async {
  if (!supportsStreamingArchiveWriting(
    format,
    password: password,
    encryptNames: encryptNames,
  )) {
    throw const ArchiveViewException(
      'This format or encryption profile has no bounded-memory archive writer.',
    );
  }
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveStreamingLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  if (level < 0 || level > 9) throw ArgumentError.value(level, 'level');
  if (source?.supported == false) {
    throw ArchiveViewException(source!.reason!);
  }
  if (gzipHeader != null &&
      format != ArchiveEndpointFormat.gzip &&
      format != ArchiveEndpointFormat.tarGzip) {
    throw ArgumentError('A gzip header requires gzip compression.');
  }
  validateArchiveWriteEntries(entries);
  var logicalBytes = 0;
  for (final entry in entries) {
    logicalBytes += entry.size;
    if (logicalBytes > kArchiveStreamingLimit) {
      throw const ArchiveViewException(
        'Archive contents exceed the native streaming limit.',
      );
    }
    final mode = entry.mode;
    final type = entry.isDirectory ? 0x4000 : 0x8000;
    if (mode != null &&
        (mode < 0 ||
            mode > 0xffff ||
            mode & 0xf000 != 0 && mode & 0xf000 != type)) {
      throw ArchiveViewException('Unsupported member mode: ${entry.path}');
    }
  }
  final output = _Output(sink, maxOutputBytes, isCancelled);
  output.check();
  switch (format) {
    case ArchiveEndpointFormat.zip:
      await _writeZip(entries, output, level);
    case ArchiveEndpointFormat.sevenZip:
      await _writeSevenZip(entries, output, level);
    case ArchiveEndpointFormat.tar:
      await writeTarArchive(
        entries,
        sink: output.add,
        source: source,
        maxOutputBytes: maxOutputBytes,
        streamed: true,
        isCancelled: isCancelled,
      );
    case ArchiveEndpointFormat.tarGzip:
    case ArchiveEndpointFormat.gzip:
      if (format == ArchiveEndpointFormat.gzip &&
          (entries.length != 1 || entries.single.isDirectory)) {
        throw const ArchiveViewException(
          'A gzip file requires exactly one regular payload.',
        );
      }
      final header = gzipHeader == null
          ? Uint8List.fromList([
              0x1f,
              0x8b,
              8,
              0,
              0,
              0,
              0,
              0,
              level == 9 ? 2 : (level == 1 ? 4 : 0),
              255,
            ])
          : archiveGzipHeader(gzipHeader);
      if (gzipHeader != null && header.length != gzipHeader.length) {
        throw const ArchiveViewException('Unsupported gzip header.');
      }
      await output.add(header);
      var crc = 0, size = 0;
      final compressor = _Deflater(output.add, level);
      Future<void> feed(List<int> bytes) async {
        output.check();
        size += bytes.length;
        if (size > kArchiveStreamingLimit) {
          throw const ArchiveViewException(
            'Gzip contents exceed the native streaming limit.',
          );
        }
        crc = getCrc32(bytes, crc);
        await compressor.add(bytes);
        await output.cooperate();
      }
      try {
        if (format == ArchiveEndpointFormat.gzip) {
          await for (final bytes in entries.single.openRead()) {
            await feed(bytes);
          }
        } else {
          await writeTarArchive(
            entries,
            sink: feed,
            source: source,
            maxOutputBytes: kArchiveStreamingLimit,
            streamed: true,
            isCancelled: isCancelled,
          );
        }
        await compressor.finish();
      } finally {
        compressor.dispose();
      }
      final trailer = Uint8List(8);
      ByteData.sublistView(trailer)
        ..setUint32(0, crc, Endian.little)
        ..setUint32(4, size % 0x100000000, Endian.little);
      await output.add(trailer);
    default:
      throw const ArchiveViewException('Unsupported streaming archive writer.');
  }
  output.check();
}

/// The native compressor emits synchronously during one bounded input chunk.
/// Drain that chunk's output before accepting the next input, so a slow sink
/// cannot build an unbounded queue of compressed bytes.
class _Deflater {
  _Deflater(this.emit, int level) {
    _input = ZLibEncoder(raw: true, level: level).startChunkedConversion(
      _CollectedSink((bytes) {
        if (_discard) return;
        _pendingBytes += bytes.length;
        if (_pendingBytes > 2 * _chunkBytes) {
          throw const ArchiveViewException(
            'Compression chunk exceeded its bound.',
          );
        }
        _pending.add(Uint8List.fromList(bytes));
      }),
    );
  }
  final Future<void> Function(List<int>) emit;
  late final Sink<List<int>> _input;
  final _pending = <Uint8List>[];
  var _pendingBytes = 0;
  var _closed = false, _discard = false;

  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('Compressor is closed.');
    for (var at = 0; at < bytes.length; at += _chunkBytes) {
      final end = (at + _chunkBytes).clamp(0, bytes.length);
      _input.add(bytes.sublist(at, end));
      await _drain();
    }
  }

  Future<void> _drain() async {
    for (final chunk in _pending) {
      await emit(chunk);
    }
    _pending.clear();
    _pendingBytes = 0;
  }

  Future<void> finish() async {
    if (_closed) return;
    _closed = true;
    _input.close();
    await _drain();
  }

  void dispose() {
    _discard = true;
    _pending.clear();
    if (!_closed) {
      _closed = true;
      _input.close();
    }
  }
}

class _CollectedSink implements Sink<List<int>> {
  _CollectedSink(this.onAdd);
  final void Function(List<int>) onAdd;
  @override
  void add(List<int> data) => onAdd(data);
  @override
  void close() {}
}

class _Output {
  _Output(this.sink, this.limit, this.isCancelled);
  final Future<void> Function(List<int>) sink;
  final int limit;
  final bool Function()? isCancelled;
  var length = 0;
  var _chunks = 0;

  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Archive writing was cancelled.');
    }
  }

  Future<void> cooperate() async {
    check();
    if (++_chunks % 16 == 0) {
      await Future<void>.delayed(Duration.zero);
      check();
    }
  }

  Future<void> add(List<int> bytes) async {
    check();
    if (bytes.length > limit - length) {
      throw const ArchiveViewException(
        'The packed archive exceeds its output limit.',
      );
    }
    for (var at = 0; at < bytes.length; at += _chunkBytes) {
      check();
      final end = (at + _chunkBytes).clamp(0, bytes.length);
      await sink(Uint8List.fromList(bytes.sublist(at, end)));
      length += end - at;
      check();
    }
  }
}

class _ZipRecord {
  _ZipRecord(this.entry, int level)
    : name = Uint8List.fromList(
        utf8.encode('${entry.path}${entry.isDirectory ? '/' : ''}'),
      ),
      method = level == 0 || entry.size == 0 ? 0 : 8,
      zip64 = entry.size + ((entry.size + 16382) ~/ 16383) * 5 + 6 >= _zip32 {
    final time = entry.modified?.toUtc();
    if (time != null) {
      final micros = time.microsecondsSinceEpoch;
      final seconds = micros ~/ 1000000;
      if (micros % 1000000 != 0) {
        throw ArchiveViewException(
          'ZIP cannot preserve subsecond modification time: ${entry.path}',
        );
      }
      if (seconds >= 0 && seconds <= 0x7fffffff) {
        timestamp = Uint8List(9);
        ByteData.sublistView(timestamp)
          ..setUint16(0, 0x5455, Endian.little)
          ..setUint16(2, 5, Endian.little)
          ..setUint8(4, 1)
          ..setUint32(5, seconds, Endian.little);
      } else if (time.year < 1980 || time.year > 2107 || time.second.isOdd) {
        throw ArchiveViewException(
          'ZIP cannot preserve this modification time: ${entry.path}',
        );
      }
    }
    final dos = time != null && time.year >= 1980 && time.year <= 2107
        ? time
        : DateTime.utc(1980);
    dosTime = dos.hour << 11 | dos.minute << 5 | dos.second ~/ 2;
    dosDate = (dos.year - 1980) << 9 | dos.month << 5 | dos.day;
  }
  final ArchiveWriteEntry entry;
  final Uint8List name;
  final int method;
  final bool zip64;
  Uint8List timestamp = Uint8List(0);
  late final int dosTime, dosDate;
  int offset = 0, packedSize = 0, crc = 0;
  int get flags => 0x800 | (entry.isDirectory ? 0 : 8);
}

Future<void> _writeZip(
  List<ArchiveWriteEntry> entries,
  _Output output,
  int level,
) async {
  // All metadata is checked before any output or source read.
  final records = entries.map((entry) => _ZipRecord(entry, level)).toList();
  for (final record in records) {
    output.check();
    record.offset = output.length;
    final extra = BytesBuilder(copy: false);
    if (record.zip64) {
      final sizes = Uint8List(20);
      ByteData.sublistView(sizes)
        ..setUint16(0, 1, Endian.little)
        ..setUint16(2, 16, Endian.little)
        ..setUint64(4, record.entry.size, Endian.little);
      extra.add(sizes);
    }
    extra.add(record.timestamp);
    final header = Uint8List(30);
    ByteData.sublistView(header)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, record.zip64 ? 45 : 20, Endian.little)
      ..setUint16(6, record.flags, Endian.little)
      ..setUint16(8, record.method, Endian.little)
      ..setUint16(10, record.dosTime, Endian.little)
      ..setUint16(12, record.dosDate, Endian.little)
      ..setUint32(18, record.zip64 ? _zip32 : 0, Endian.little)
      ..setUint32(22, record.zip64 ? _zip32 : 0, Endian.little)
      ..setUint16(26, record.name.length, Endian.little)
      ..setUint16(28, extra.length, Endian.little);
    await output.add(header);
    await output.add(record.name);
    await output.add(extra.takeBytes());
    final start = output.length;
    final compressor = record.method == 8 ? _Deflater(output.add, level) : null;
    try {
      await for (final chunk in record.entry.openRead()) {
        output.check();
        record.crc = getCrc32(chunk, record.crc);
        if (compressor == null) {
          await output.add(chunk);
        } else {
          await compressor.add(chunk);
        }
        await output.cooperate();
      }
      await compressor?.finish();
    } finally {
      compressor?.dispose();
    }
    record.packedSize = output.length - start;
    if (!record.zip64 && record.packedSize >= _zip32) {
      throw const ArchiveViewException(
        'ZIP entry requires a ZIP64 size field.',
      );
    }
    if (!record.entry.isDirectory) {
      final descriptor = Uint8List(record.zip64 ? 24 : 16);
      final fields = ByteData.sublistView(descriptor)
        ..setUint32(0, 0x08074b50, Endian.little)
        ..setUint32(4, record.crc, Endian.little);
      if (record.zip64) {
        fields
          ..setUint64(8, record.packedSize, Endian.little)
          ..setUint64(16, record.entry.size, Endian.little);
      } else {
        fields
          ..setUint32(8, record.packedSize, Endian.little)
          ..setUint32(12, record.entry.size, Endian.little);
      }
      await output.add(descriptor);
    }
  }
  final directoryOffset = output.length;
  for (final record in records) {
    final largeOffset = record.offset >= _zip32;
    final extra = BytesBuilder(copy: false);
    if (record.zip64 || largeOffset) {
      final sizes = Uint8List(
        4 + (record.zip64 ? 16 : 0) + (largeOffset ? 8 : 0),
      );
      final fields = ByteData.sublistView(sizes)
        ..setUint16(0, 1, Endian.little)
        ..setUint16(2, sizes.length - 4, Endian.little);
      var at = 4;
      if (record.zip64) {
        fields
          ..setUint64(at, record.entry.size, Endian.little)
          ..setUint64(at + 8, record.packedSize, Endian.little);
        at += 16;
      }
      if (largeOffset) fields.setUint64(at, record.offset, Endian.little);
      extra.add(sizes);
    }
    extra.add(record.timestamp);
    final mode =
        (record.entry.isDirectory ? 0x4000 : 0x8000) |
        ((record.entry.mode ?? (record.entry.isDirectory ? 0x1ed : 0x1a4)) &
            0xfff);
    final central = Uint8List(46);
    ByteData.sublistView(central)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 0x032d, Endian.little)
      ..setUint16(6, record.zip64 || largeOffset ? 45 : 20, Endian.little)
      ..setUint16(8, record.flags, Endian.little)
      ..setUint16(10, record.method, Endian.little)
      ..setUint16(12, record.dosTime, Endian.little)
      ..setUint16(14, record.dosDate, Endian.little)
      ..setUint32(16, record.crc, Endian.little)
      ..setUint32(20, record.zip64 ? _zip32 : record.packedSize, Endian.little)
      ..setUint32(24, record.zip64 ? _zip32 : record.entry.size, Endian.little)
      ..setUint16(28, record.name.length, Endian.little)
      ..setUint16(30, extra.length, Endian.little)
      ..setUint32(
        38,
        mode * 0x10000 | (record.entry.isDirectory ? 0x10 : 0),
        Endian.little,
      )
      ..setUint32(42, largeOffset ? _zip32 : record.offset, Endian.little);
    await output.add(central);
    await output.add(record.name);
    await output.add(extra.takeBytes());
  }
  final directoryBytes = output.length - directoryOffset;
  final zip64 =
      records.any((record) => record.zip64) ||
      records.length >= 0xffff ||
      directoryOffset >= _zip32 ||
      directoryBytes >= _zip32;
  if (zip64) {
    final position = output.length;
    final footer = Uint8List(56);
    ByteData.sublistView(footer)
      ..setUint32(0, 0x06064b50, Endian.little)
      ..setUint64(4, 44, Endian.little)
      ..setUint16(12, 45, Endian.little)
      ..setUint16(14, 45, Endian.little)
      ..setUint64(24, records.length, Endian.little)
      ..setUint64(32, records.length, Endian.little)
      ..setUint64(40, directoryBytes, Endian.little)
      ..setUint64(48, directoryOffset, Endian.little);
    await output.add(footer);
    final locator = Uint8List(20);
    ByteData.sublistView(locator)
      ..setUint32(0, 0x07064b50, Endian.little)
      ..setUint64(8, position, Endian.little)
      ..setUint32(16, 1, Endian.little);
    await output.add(locator);
  }
  final end = Uint8List(22);
  ByteData.sublistView(end)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, records.length.clamp(0, 0xffff), Endian.little)
    ..setUint16(10, records.length.clamp(0, 0xffff), Endian.little)
    ..setUint32(12, directoryBytes.clamp(0, _zip32), Endian.little)
    ..setUint32(16, directoryOffset.clamp(0, _zip32), Endian.little);
  await output.add(end);
}

class _SevenFolder {
  const _SevenFolder(this.size, this.packed, this.crc);
  final int size, packed, crc;
}

Future<void> _writeSevenZip(
  List<ArchiveWriteEntry> entries,
  _Output output,
  int level,
) async {
  // Validate timestamps before opening sources or allocating the payload spool.
  for (final entry in entries) {
    if (entry.modified != null) _fileTime(entry.modified!);
  }
  final spool = await ArchiveOutputSpool.create(maxBytes: output.limit);
  final folders = <_SevenFolder>[];
  final compress = level > 0;
  // Bounded dictionary profiles: fast (1–3), balanced (4–6), maximum (7–9).
  // These tune the independently reset block size without retaining a member.
  final dictionaryBytes = level <= 3
      ? 64 * 1024
      : level <= 6
      ? 256 * 1024
      : 1024 * 1024;
  final dictionaryProperty = level <= 3
      ? 8
      : level <= 6
      ? 12
      : 16;
  try {
    for (final entry in entries) {
      output.check();
      final start = spool.length;
      var crc = 0;
      final block = compress && entry.size > 0
          ? Uint8List(dictionaryBytes)
          : null;
      var used = 0;
      Future<void> flushBlock() async {
        if (used == 0) return;
        output.check();
        // Every bounded block resets dictionary/state/properties. Remove
        // only its end marker so all blocks form one valid LZMA2 stream.
        final packed = Lzma2Encoder(dictSize: dictionaryBytes)
            .encode(Uint8List.sublistView(block!, 0, used));
        await spool.write(Uint8List.sublistView(packed, 0, packed.length - 1));
        used = 0;
      }

      await for (final data in entry.openRead(chunkSize: _chunkBytes)) {
        output.check();
        crc = getCrc32(data, crc);
        if (compress) {
          for (var at = 0; at < data.length;) {
            final count = (data.length - at).clamp(0, dictionaryBytes - used);
            block!.setRange(used, used + count, data, at);
            used += count;
            at += count;
            if (used == dictionaryBytes) await flushBlock();
          }
        } else {
          await spool.write(data);
        }
        await output.cooperate();
      }
      if (entry.size > 0) {
        if (compress) {
          await flushBlock();
          await spool.write(const [0]);
        }
        folders.add(_SevenFolder(entry.size, spool.length - start, crc));
      }
    }
    final header = _sevenHeader(
      entries,
      folders,
      compress ? dictionaryProperty : null,
    );
    if (32 + spool.length + header.length > output.limit) {
      throw const ArchiveViewException(
        'The packed archive exceeds its output limit.',
      );
    }
    await spool.finish();
    final signature = Uint8List(32)
      ..setRange(0, 8, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]);
    final fields = ByteData.sublistView(signature)
      ..setUint64(12, spool.length, Endian.little)
      ..setUint64(20, header.length, Endian.little)
      ..setUint32(28, getCrc32(header), Endian.little);
    fields.setUint32(
      8,
      getCrc32(Uint8List.sublistView(signature, 12)),
      Endian.little,
    );
    await output.add(signature);
    await for (final chunk in spool.openRead()) {
      await output.add(chunk);
    }
    await output.add(header);
  } finally {
    await spool.dispose();
  }
}

Uint8List _sevenHeader(
  List<ArchiveWriteEntry> entries,
  List<_SevenFolder> folders,
  int? dictionaryProperty,
) {
  final header = _SevenBuffer()..byte(1); // kHeader
  if (folders.isNotEmpty) {
    header
      ..byte(4) // MainStreamsInfo
      ..byte(6) // PackInfo
      ..number(0)
      ..number(folders.length)
      ..byte(9); // Size
    for (final folder in folders) {
      header.number(folder.packed);
    }
    header
      ..byte(0)
      ..byte(7) // UnpackInfo
      ..byte(11) // Folder
      ..number(folders.length)
      ..byte(0); // inline folders
    for (final _ in folders) {
      header.bytes(
        dictionaryProperty != null
            ? [1, 0x21, 0x21, 1, dictionaryProperty]
            : const [1, 1, 0],
      );
    }
    header.byte(12); // CodersUnpackSize
    for (final folder in folders) {
      header.number(folder.size);
    }
    header.bytes(const [10, 1]); // CRC, all defined
    for (final folder in folders) {
      header.u32(folder.crc);
    }
    // Explicit SubStreamsInfo selects the default one stream per folder.
    // Some independent readers reject its omission even though this default
    // can be inferred; keep this interoperable framing instead.
    header.bytes(const [0, 8, 0, 0]);
  }
  if (entries.isNotEmpty) {
    header
      ..byte(5)
      ..number(entries.length); // FilesInfo
    final empty = entries.where((e) => e.size == 0).toList();
    if (empty.isNotEmpty) {
      header.property(
        14,
        _SevenBuffer()..bits(entries.map((e) => e.size == 0)),
      );
      if (empty.any((e) => !e.isDirectory)) {
        header.property(
          15,
          _SevenBuffer()..bits(empty.map((e) => !e.isDirectory)),
        );
      }
    }
    final names = _SevenBuffer()..byte(0);
    for (final entry in entries) {
      for (final unit in entry.path.codeUnits) {
        names.u16(unit);
      }
      names.u16(0);
    }
    header.property(17, names);
    if (entries.any((e) => e.modified != null)) {
      final times = _SevenBuffer()
        ..defined(entries.map((e) => e.modified != null))
        ..byte(0);
      for (final entry in entries) {
        if (entry.modified != null) times.u64(_fileTime(entry.modified!));
      }
      header.property(20, times);
    }
    final attributes = _SevenBuffer()..bytes(const [1, 0]); // all, inline
    for (final entry in entries) {
      final mode =
          (entry.isDirectory ? 0x4000 : 0x8000) |
          ((entry.mode ?? (entry.isDirectory ? 0x1ed : 0x1a4)) & 0xfff);
      attributes.u32(mode * 0x10000 | 0x8000 | (entry.isDirectory ? 0x10 : 0));
    }
    header
      ..property(21, attributes)
      ..byte(0);
  }
  header.byte(0);
  return header.take();
}

int _fileTime(DateTime value) {
  final micros = value.toUtc().microsecondsSinceEpoch + 11644473600000000;
  if (micros < 0 || micros > 922337203685477580) {
    throw const ArchiveViewException(
      '7z cannot preserve this modification time.',
    );
  }
  return micros * 10;
}

class _SevenBuffer {
  Uint8List _bytes = Uint8List(4096);
  int _length = 0;
  void _reserve(int count) {
    if (count > _maxMetadataBytes - _length) {
      throw const ArchiveViewException('7z metadata exceeds its limit.');
    }
    if (_length + count <= _bytes.length) return;
    var capacity = _bytes.length;
    while (capacity < _length + count) {
      capacity = (capacity * 2).clamp(0, _maxMetadataBytes);
    }
    _bytes = Uint8List(capacity)..setRange(0, _length, _bytes);
  }

  void byte(int value) {
    _reserve(1);
    _bytes[_length++] = value;
  }

  void bytes(List<int> value) {
    _reserve(value.length);
    _bytes.setRange(_length, _length + value.length, value);
    _length += value.length;
  }

  void u16(int value) {
    _reserve(2);
    ByteData.sublistView(_bytes).setUint16(_length, value, Endian.little);
    _length += 2;
  }

  void u32(int value) {
    _reserve(4);
    ByteData.sublistView(_bytes).setUint32(_length, value, Endian.little);
    _length += 4;
  }

  void u64(int value) {
    _reserve(8);
    ByteData.sublistView(_bytes).setUint64(_length, value, Endian.little);
    _length += 8;
  }

  void number(int value) {
    var prefix = 0, rest = value;
    final tail = <int>[];
    for (var count = 0; count < 8; count++) {
      if (rest < (1 << (7 - count))) {
        byte(prefix | rest);
        bytes(tail);
        return;
      }
      prefix |= 0x80 >> count;
      tail.add(rest & 0xff);
      rest >>= 8;
    }
    byte(0xff);
    bytes(tail);
  }

  void bits(Iterable<bool> flags) {
    var value = 0, count = 0;
    for (final flag in flags) {
      if (flag) value |= 0x80 >> count;
      if (++count == 8) {
        byte(value);
        value = 0;
        count = 0;
      }
    }
    if (count > 0) byte(value);
  }

  void defined(Iterable<bool> flags) {
    final values = flags.toList();
    if (values.every((value) => value)) {
      byte(1);
    } else {
      byte(0);
      bits(values);
    }
  }

  void property(int id, _SevenBuffer payload) {
    final value = payload.take();
    byte(id);
    number(value.length);
    bytes(value);
  }

  Uint8List take() => Uint8List.sublistView(_bytes, 0, _length);
}
