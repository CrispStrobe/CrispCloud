import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'archive_hfs_reader.dart';
import 'archive_iso_reader.dart';
import 'archive_types.dart';

const _sectorBytes = 512;
const _maxPlistBytes = 8 * 1024 * 1024;
const _maxChunkBytes = 16 * 1024 * 1024;
const _maxImageBytes = 2 * 1024 * 1024 * 1024 * 1024;

/// Reads unencrypted, single-segment UDIF disk images without mounting them.
/// Raw/zero/zlib/bzip2 blocks form bounded random-access partition sources.
/// Supported HFS+/HFSX or ISO files are exposed under `files/`; raw partition
/// images are independently available under `partitions/`.
Future<ViewerArchive> openDmgArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
}) async {
  final children = <ViewerArchive>[];
  final partitions = <_DmgPartition>[];
  try {
    if (maxMemberBytes <= 0) {
      throw ArgumentError.value(maxMemberBytes, 'maxMemberBytes');
    }
    if (source.length < 512) _bad('Missing UDIF trailer.');
    final trailer = await _readExact(source, source.length - 512, 512);
    if (!_magic(trailer, 0, 'koly')) {
      _bad('Only unencrypted UDIF images with a koly trailer are supported.');
    }
    final data = ByteData.sublistView(trailer);
    if (data.getUint32(4) != 4 || data.getUint32(8) != 512) {
      _bad('Unsupported UDIF version or trailer size.');
    }
    if (data.getUint32(56) != 1 ||
        data.getUint32(60) != 1 ||
        _u64(data, 16) != 0) {
      _bad('Segmented disk images are not supported.');
    }
    final forkOffset = _u64(data, 24);
    final forkLength = _u64(data, 32);
    final xmlOffset = _u64(data, 216);
    final xmlLength = _u64(data, 224);
    final sectors = _u64(data, 492);
    if (sectors <= 0 || sectors > _maxImageBytes ~/ _sectorBytes) {
      _bad('The declared disk size exceeds the supported range.');
    }
    _range(source.length - 512, forkOffset, forkLength);
    _range(source.length - 512, xmlOffset, xmlLength);
    if (xmlLength <= 0 ||
        xmlLength > _maxPlistBytes ||
        (forkLength > 0 &&
            xmlOffset < forkOffset + forkLength &&
            forkOffset < xmlOffset + xmlLength)) {
      _bad('Invalid, overlapping or oversized XML metadata.');
    }
    final plist = _plist(
      utf8.decode(await _readExact(source, xmlOffset, xmlLength)),
    );
    final root = _dict(plist.rootElement.getElement('dict'));
    final resources = _dict(root['resource-fork']);
    final blockArray = resources['blkx'];
    if (blockArray == null || blockArray.name.local != 'array') {
      _bad(
        'The UDIF block map is absent. Binary resource forks are unsupported.',
      );
    }
    final tables = blockArray.childElements.toList();
    if (tables.isEmpty || tables.length > 128) {
      _bad('The disk image must contain between 1 and 128 block maps.');
    }
    final cache = _ChunkCache();
    var chunkCount = 0;
    for (var i = 0; i < tables.length; i++) {
      final entry = _dict(tables[i]);
      final encoded = entry['Data'];
      if (encoded == null || encoded.name.local != 'data') {
        _bad('A UDIF block map has no binary data.');
      }
      final table = base64.decode(
        encoded.innerText.replaceAll(RegExp(r'\s'), ''),
      );
      final label = entry['Name']?.innerText ?? 'Partition';
      final partition = _partition(
        source,
        table,
        label,
        i,
        forkOffset,
        forkLength,
        sectors,
        cache,
      );
      chunkCount += partition.chunks.length;
      if (chunkCount > 100000) _bad('The disk image has too many chunks.');
      partitions.add(partition);
    }

    final members = <ViewerArchiveMember>[];
    final reads = <Future<Uint8List> Function(int)>[];
    final streams = <Stream<List<int>> Function(int)>[];
    final notices = <String>[
      'Read-only disk image. Files are data forks; filesystem permissions, '
          'resource forks and extended attributes are not restored.',
      'Compressed-block checksums are checked on read. Whole-image checksums '
          'and publisher signatures are not verified.',
    ];
    void add(
      ViewerArchiveMember member,
      Future<Uint8List> Function(int) read,
      Stream<List<int>> Function(int) stream,
    ) {
      if (members.length >= 200000) {
        _bad('The disk image has too many members.');
      }
      members.add(member);
      reads.add(read);
      streams.add(stream);
    }

    for (final partition in partitions) {
      final stem =
          '${(partition.ordinal + 1).toString().padLeft(3, '0')}-'
          '${_label(partition.name)}';
      var extension = 'img';
      if (partition.length >= 1536) {
        final signature = await partition.read(1024, 2);
        if (_magic(signature, 0, 'H+') || _magic(signature, 0, 'HX')) {
          extension = 'hfs';
        }
      }
      if (extension == 'img' && partition.length >= 17 * 2048) {
        if (_magic(await partition.read(16 * 2048 + 1, 5), 0, 'CD001')) {
          extension = 'iso';
        }
      }
      add(
        ViewerArchiveMember(
          name: 'partitions/$stem.$extension',
          size: partition.length,
          isFile: true,
          isEncrypted: false,
          pathEscapedRoot: false,
          index: members.length,
        ),
        (limit) async {
          if (partition.length > maxMemberBytes || partition.length > limit) {
            _bad('The partition image exceeds the member extraction limit.');
          }
          final bytes = await partition.read(0, partition.length);
          partition.verifyChecksum(bytes);
          return bytes;
        },
        (chunkSize) async* {
          if (partition.length > maxMemberBytes) {
            _bad('The partition image exceeds the member extraction limit.');
          }
          yield* partition.openRead(chunkSize);
        },
      );

      ViewerArchive? filesystem;
      try {
        // Each filesystem gets its own close state over the shared partition.
        // Failure/closing a reader must not close the raw partition entry.
        if (extension == 'hfs') {
          filesystem = await openHfsArchive(
            _BorrowedPartition(partition),
            maxMemberBytes: maxMemberBytes,
          );
        } else if (extension == 'iso') {
          filesystem = await openIsoArchive(
            _BorrowedPartition(partition),
            maxMemberBytes: maxMemberBytes,
          );
        }
      } on ArchiveViewException catch (error) {
        notices.add(
          '$stem: filesystem browsing unavailable: $error '
          'The raw partition image remains available.',
        );
      }
      if (filesystem != null) {
        children.add(filesystem);
        final opened = filesystem;
        for (final member in opened.members) {
          // Links remain visible only in the raw image, never as fake files.
          // In particular DMGs routinely contain an /Applications symlink.
          if (member.isSpecial || member.pathEscapedRoot) {
            if (!notices.contains(_skippedLinks)) notices.add(_skippedLinks);
            continue;
          }
          add(
            ViewerArchiveMember(
              name: 'files/$stem/${member.name}',
              size: member.size,
              isFile: member.isFile,
              isEncrypted: false,
              pathEscapedRoot: false,
              index: members.length,
              modified: member.modified,
              posixMode: member.posixMode,
            ),
            (limit) => opened.readMember(member, maxBytes: limit),
            (chunkSize) => opened.openMember(
              member,
              maxBytes: maxMemberBytes,
              chunkSize: chunkSize,
            ),
          );
        }
      }
    }
    if (!members.any((m) => m.name.startsWith('files/'))) {
      notices.add(
        'No supported filesystem could be opened. The listed members '
        'are raw partition images, not files inside APFS or another filesystem.',
      );
    }
    return ViewerArchive.reader(
      formatName: 'dmg',
      members: members,
      notices: notices,
      read: (member, limit) =>
          reads[member.index](limit < maxMemberBytes ? limit : maxMemberBytes),
      streamReader: (member, chunkSize) => streams[member.index](chunkSize),
      close: () async {
        for (final child in children) {
          await child.close();
        }
        for (final partition in partitions) {
          await partition.close();
        }
        cache.clear();
        await source.close();
      },
    );
  } catch (error) {
    for (final child in children) {
      await child.close();
    }
    for (final partition in partitions) {
      await partition.close();
    }
    await source.close();
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw ArchiveViewException('Could not read the disk image: $error');
  }
}

const _skippedLinks =
    'Symbolic links and other special filesystem entries are '
    'omitted from the file view and preserved only in the raw partition image.';

Never _bad(String detail) =>
    throw ArchiveViewException('Unsupported or invalid DMG: $detail');

bool _magic(List<int> bytes, int at, String value) {
  if (at < 0 || at + value.length > bytes.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (bytes[at + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

int _u64(ByteData data, int offset) {
  final high = data.getUint32(offset);
  if (high > 0x1fffff) _bad('A 64-bit field exceeds the exact integer range.');
  return high * 0x100000000 + data.getUint32(offset + 4);
}

void _range(int total, int offset, int length) {
  if (offset < 0 || length < 0 || offset > total || length > total - offset) {
    _bad('A declared range leaves its containing data.');
  }
}

Future<Uint8List> _readExact(
  koni.ByteSource source,
  int offset,
  int length,
) async {
  _range(source.length, offset, length);
  final bytes = await source.read(offset, length);
  if (bytes.length != length) _bad('The disk image is truncated.');
  return bytes;
}

XmlDocument _plist(String text) {
  if (text.contains('<!ENTITY')) _bad('XML entities are not supported.');
  var depth = 0;
  var count = 0;
  for (final event in parseEvents(
    text,
    validateNesting: true,
    validateDocument: true,
  )) {
    if (++count > 100000) _bad('The XML metadata has too many elements.');
    if (event is XmlStartElementEvent && !event.isSelfClosing) {
      if (++depth > 16) _bad('The XML metadata is too deeply nested.');
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
  final document = XmlDocument.parse(text);
  if (document.rootElement.name.local != 'plist') {
    _bad('Expected an XML plist.');
  }
  return document;
}

Map<String, XmlElement> _dict(XmlElement? element) {
  if (element == null || element.name.local != 'dict') {
    _bad('Expected a plist dictionary.');
  }
  final children = element.childElements.toList();
  if (children.length.isOdd) _bad('A plist dictionary has an unmatched key.');
  final result = <String, XmlElement>{};
  for (var i = 0; i < children.length; i += 2) {
    if (children[i].name.local != 'key') _bad('Invalid plist dictionary key.');
    final key = children[i].innerText;
    if (result.containsKey(key)) _bad('Duplicate plist dictionary key.');
    result[key] = children[i + 1];
  }
  return result;
}

String _label(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll('..', '_')
      .trim();
  if (cleaned.isEmpty || cleaned == '.') return 'partition';
  return cleaned.length > 96 ? cleaned.substring(0, 96) : cleaned;
}

_DmgPartition _partition(
  koni.ByteSource source,
  Uint8List table,
  String name,
  int ordinal,
  int forkOffset,
  int forkLength,
  int diskSectors,
  _ChunkCache cache,
) {
  if (table.length < 204 || !_magic(table, 0, 'mish')) {
    _bad('Invalid block map header.');
  }
  final data = ByteData.sublistView(table);
  if (data.getUint32(4) != 1) _bad('Unsupported block map version.');
  final firstSector = _u64(data, 8);
  final sectorCount = _u64(data, 16);
  final dataStart = _u64(data, 24);
  _range(diskSectors, firstSector, sectorCount);
  final count = data.getUint32(200);
  if (count <= 0 ||
      count > 100000 ||
      count > (table.length - 204) ~/ 40 ||
      table.length != 204 + count * 40) {
    _bad('Invalid or oversized chunk table.');
  }
  final chunks = <_DmgChunk>[];
  var endSector = 0;
  var terminated = false;
  for (var i = 0; i < count; i++) {
    final at = 204 + i * 40;
    final type = data.getUint32(at);
    final start = _u64(data, at + 8);
    final sectors = _u64(data, at + 16);
    final packedOffset = _u64(data, at + 24);
    final packedLength = _u64(data, at + 32);
    if (terminated) _bad('Data follows the chunk-table terminator.');
    if (type == 0xffffffff) {
      if (sectors != 0 || packedLength != 0) {
        _bad('Invalid chunk-table terminator.');
      }
      terminated = true;
      continue;
    }
    if (type == 0x7ffffffe) {
      if (sectors != 0 || packedLength != 0) _bad('Invalid comment chunk.');
      continue;
    }
    if (!const [0, 1, 2, 0x80000005, 0x80000006].contains(type)) {
      _bad(
        'Compression method 0x${type.toRadixString(16)} is unavailable '
        '(ADC, LZFSE and LZMA are not supported).',
      );
    }
    _range(sectorCount, start, sectors);
    if (sectors <= 0 || start != endSector) {
      _bad('Missing, overlapping or unordered chunks.');
    }
    endSector = start + sectors;
    final size = sectors * _sectorBytes;
    if (type == 0 || type == 2) {
      if (packedLength != 0) _bad('A zero-fill chunk contains packed bytes.');
    } else {
      _range(forkLength, dataStart, packedOffset);
      _range(forkLength, dataStart + packedOffset, packedLength);
      if (type == 1 && packedLength != size) _bad('Raw chunk size mismatch.');
      if (type != 1 &&
          (size > _maxChunkBytes ||
              packedLength > _maxChunkBytes ||
              packedLength == 0)) {
        _bad('Compressed chunks are limited to 16 MiB each.');
      }
    }
    chunks.add(
      _DmgChunk(
        type,
        start * _sectorBytes,
        size,
        forkOffset + dataStart + packedOffset,
        packedLength,
      ),
    );
  }
  if (!terminated || endSector != sectorCount) {
    _bad('Incomplete partition block map.');
  }
  final checksumType = data.getUint32(64);
  final checksumBits = data.getUint32(68);
  if ((checksumType == 2 && checksumBits != 32) ||
      (checksumType != 0 && checksumType != 2)) {
    _bad('Unsupported partition checksum.');
  }
  return _DmgPartition(
    source,
    name,
    ordinal,
    sectorCount * _sectorBytes,
    chunks,
    checksumType == 2 ? data.getUint32(72) : null,
    cache,
  );
}

class _DmgChunk {
  const _DmgChunk(
    this.type,
    this.start,
    this.length,
    this.offset,
    this.packedLength,
  );
  final int type, start, length, offset, packedLength;
}

/// One shared cache across all partitions; metadata walks never retain a full
/// decompressed image or one buffer for every partition.
class _ChunkCache {
  _DmgChunk? chunk;
  Uint8List? data;
  void clear() {
    chunk = null;
    data = null;
  }
}

class _DmgPartition implements koni.ByteSource {
  _DmgPartition(
    this.source,
    this.name,
    this.ordinal,
    this.length,
    this.chunks,
    this.checksum,
    this.cache,
  );
  final koni.ByteSource source;
  @override
  final String name;
  final int ordinal;
  @override
  final int length;
  final List<_DmgChunk> chunks;
  final int? checksum;
  final _ChunkCache cache;
  bool _closed = false;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) _bad('The partition is closed.');
    _range(this.length, offset, length);
    if (length > kArchiveReadLimit) _bad('A partition read exceeds 64 MiB.');
    final output = Uint8List(length);
    var written = 0;
    var low = 0, high = chunks.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final chunk = chunks[middle];
      if (chunk.start + chunk.length <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var i = low; i < chunks.length && written < length; i++) {
      final chunk = chunks[i];
      final from = offset + written - chunk.start;
      final count = (length - written < chunk.length - from)
          ? length - written
          : chunk.length - from;
      if (from < 0 || count <= 0) _bad('The partition has a missing extent.');
      if (chunk.type == 1) {
        output.setRange(
          written,
          written + count,
          await _readExact(source, chunk.offset + from, count),
        );
      } else if (chunk.type != 0 && chunk.type != 2) {
        Uint8List? expanded = identical(cache.chunk, chunk) ? cache.data : null;
        if (expanded == null) {
          final packed = await _readExact(
            source,
            chunk.offset,
            chunk.packedLength,
          );
          try {
            expanded = chunk.type == 0x80000005
                ? const ar.ZLibDecoder().decodeBytes(
                    packed,
                    verify: true,
                    maxOutputSize: chunk.length,
                  )
                : ar.BZip2Decoder().decodeBytes(
                    packed,
                    verify: true,
                    maxOutputSize: chunk.length,
                  );
          } catch (error) {
            _bad('A compressed partition chunk is corrupt: $error');
          }
          if (expanded.length != chunk.length) {
            _bad('Expanded chunk size mismatch.');
          }
          cache.chunk = chunk;
          cache.data = expanded;
        }
        output.setRange(written, written + count, expanded, from);
      }
      written += count;
    }
    if (written != length) _bad('The partition is truncated.');
    return output;
  }

  void verifyChecksum(Uint8List bytes) {
    if (checksum == null) return;
    var actual = 0;
    for (final chunk in chunks) {
      // UDIF BLOCK_IGNORE denotes unallocated sectors. They are emitted as
      // deterministic zeros but do not participate in the partition CRC.
      if (chunk.type == 2) continue;
      actual = ar.getCrc32(
        Uint8List.sublistView(bytes, chunk.start, chunk.start + chunk.length),
        actual,
      );
    }
    if (actual != checksum) {
      _bad('The extracted partition checksum does not match.');
    }
  }

  /// Reads positional chunks and checks the same partition CRC as the buffered
  /// API. Unallocated BLOCK_IGNORE sectors are output as zeros but excluded
  /// from the checksum; no whole-partition allocation is needed.
  Stream<List<int>> openRead(int chunkSize) async* {
    var actual = 0;
    for (final chunk in chunks) {
      for (var within = 0; within < chunk.length; within += chunkSize) {
        final remaining = chunk.length - within;
        final bytes = await read(
          chunk.start + within,
          remaining < chunkSize ? remaining : chunkSize,
        );
        if (checksum != null && chunk.type != 2) {
          actual = ar.getCrc32(bytes, actual);
        }
        yield bytes;
      }
    }
    if (checksum != null && actual != checksum) {
      _bad('The extracted partition checksum does not match.');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

class _BorrowedPartition implements koni.ByteSource {
  _BorrowedPartition(this.partition);
  final _DmgPartition partition;
  bool _closed = false;
  @override
  String get name => partition.name;
  @override
  int get length => partition.length;
  @override
  Future<Uint8List> read(int offset, int length) {
    if (_closed) _bad('The filesystem reader is closed.');
    return partition.read(offset, length);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
