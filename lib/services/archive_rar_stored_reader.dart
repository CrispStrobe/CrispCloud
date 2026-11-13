// Independent RAR5 Store container reader; format source:
// https://www.rarlab.com/technote.htm. No proprietary compression code is used.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_rar_stored_format.dart';
import 'archive_streaming_unsupported.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

/// Opens an owned, positional RAR5 Store source. Indexing and member payloads
/// remain bounded. Compressed/encrypted/solid/split profiles explicitly defer
/// to the existing RAR reader; every failed open closes [source].
/// [isCancelled] covers indexing; consumers can cancel member subscriptions.
Future<ViewerArchive> openStoredRarArchive(
  koni.ByteSource source, {
  int maxBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
}) async {
  try {
    final parsed = await _parse(source, maxBytes, isCancelled);
    final members = <ViewerArchiveMember>[
      for (var index = 0; index < parsed.entries.length; index++)
        parsed.entries[index].member(index),
    ];
    Stream<List<int>> read(_StoredRarEntry entry, int chunkSize) async* {
      var crc = 0;
      final step = chunkSize < rarStoredChunkBytes
          ? chunkSize
          : rarStoredChunkBytes;
      var chunks = 0;
      for (var offset = 0; offset < entry.size; offset += step) {
        final remaining = entry.size - offset;
        final bytes = await _readExact(
          source,
          entry.dataOffset + offset,
          remaining < step ? remaining : step,
        );
        crc = getCrc32(bytes, crc);
        yield bytes;
        if (++chunks % 16 == 0) await Future<void>.delayed(Duration.zero);
      }
      if (entry.crc != null && crc != entry.crc) {
        throw ArchiveViewException(
          'RAR5 member checksum mismatch: ${entry.name}',
        );
      }
    }

    return ViewerArchive.reader(
      formatName: 'rar',
      maxStreamingMemberBytes: maxBytes,
      members: members,
      notices: [
        'RAR5 Store: file data is not compressed.',
        if (parsed.reason != null) parsed.reason!,
      ],
      read: (member, limit) async {
        if (member.size > limit || member.size > maxBytes) {
          rarStoredError('RAR5 member exceeds the requested read limit.');
        }
        final output = BytesBuilder(copy: false);
        await for (final chunk in read(
          parsed.entries[member.index],
          rarStoredChunkBytes,
        )) {
          output.add(chunk);
        }
        return output.takeBytes();
      },
      streamReader: (member, chunkSize) =>
          read(parsed.entries[member.index], chunkSize),
      close: source.close,
    );
  } catch (_) {
    await source.close();
    rethrow;
  }
}

/// Borrows [source]. Only a fully understood unencrypted, nonsplit, nonsolid
/// Store profile is writable. Header CRCs and field bounds are checked here;
/// file CRCs are checked while their payload streams are consumed.
Future<ArchiveRewriteInspection> inspectStoredRarRewriteSource(
  koni.ByteSource source, {
  int maxBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
}) async {
  try {
    final parsed = await _parse(source, maxBytes, isCancelled);
    return ArchiveRewriteInspection(
      reason: parsed.reason,
      container: const {
        'package.kind': 'rar',
        'rar5.store': true,
        'rar5.version': 5,
      },
      attributes: {
        for (var index = 0; index < parsed.entries.length; index++)
          parsed.entries[index].name: {
            'package.sourcePath': parsed.entries[index].name,
            'package.order': index,
            ...parsed.entries[index].attributes,
          },
      },
    );
  } on _RarStoredCancelled {
    rethrow;
  } catch (error) {
    return ArchiveRewriteInspection(
      reason: 'The RAR5 Store metadata cannot be preserved safely: $error',
      container: const {
        'package.kind': 'rar',
        'rar5.store': true,
        'rar5.version': 5,
      },
    );
  }
}

class _StoredRarIndex {
  final entries = <_StoredRarEntry>[];
  String? reason;
  void readOnly(String message) => reason ??= message;
}

class _RarStoredCancelled extends ArchiveViewException {
  const _RarStoredCancelled() : super('RAR5 opening was cancelled.');
}

class _StoredRarEntry {
  const _StoredRarEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.special,
    required this.unsafePath,
    required this.dataOffset,
    required this.crc,
    required this.modified,
    required this.mode,
    required this.attributes,
  });
  final String name;
  final int size;
  final bool isDirectory, special, unsafePath;
  final int dataOffset;
  final int? crc;
  final DateTime? modified;
  final int? mode;
  final Map<String, Object?> attributes;

  ViewerArchiveMember member(int index) => ViewerArchiveMember(
    name: name,
    size: size,
    isFile: !isDirectory && !special,
    isEncrypted: false,
    isSpecial: special,
    pathEscapedRoot: unsafePath,
    modified: modified,
    posixMode: mode,
    index: index,
  );
}

class _Header {
  const _Header(
    this.type,
    this.flags,
    this.fields,
    this.extra,
    this.dataOffset,
    this.dataSize,
    this.bytes,
  );
  final int type, flags, dataOffset, dataSize, bytes;
  final RarStoredCursor fields;
  final Uint8List extra;
  int get next => dataOffset + dataSize;
}

Future<Uint8List> _readExact(koni.ByteSource source, int at, int count) async {
  if (at < 0 || count < 0 || at > source.length || count > source.length - at) {
    rarStoredError('RAR5 block leaves the source archive.');
  }
  final bytes = await source.read(at, count);
  if (bytes.length != count) rarStoredError('RAR5 source was truncated.');
  return bytes;
}

Future<_Header> _header(koni.ByteSource source, int at) async {
  final available = source.length - at;
  if (available < 7) rarStoredError('Truncated RAR5 block header.');
  final prefix = await _readExact(source, at, 7);
  final start = RarStoredCursor(prefix);
  final expectedCrc = start.uint32();
  final size = start.vint(maxBytes: 3, maxValue: rarStoredMaxHeaderBytes);
  final lengthBytes = start.offset - 4;
  final body = await _readExact(source, at + start.offset, size);
  var crc = getCrc32(Uint8List.sublistView(prefix, 4, 4 + lengthBytes));
  crc = getCrc32(body, crc);
  if (crc != expectedCrc) rarStoredError('RAR5 header checksum mismatch.');
  final input = RarStoredCursor(body);
  final type = input.vint();
  final flags = input.vint();
  final extraSize = flags & 1 == 0 ? 0 : input.vint();
  final dataSize = flags & 2 == 0 ? 0 : input.vint();
  if (extraSize > input.remaining) {
    rarStoredError('RAR5 extra area leaves its header.');
  }
  final fields = RarStoredCursor(
    body,
    offset: input.offset,
    end: body.length - extraSize,
  );
  final extra = Uint8List.sublistView(body, body.length - extraSize);
  final dataOffset = at + 4 + lengthBytes + body.length;
  if (dataSize > source.length - dataOffset) {
    rarStoredError('Truncated RAR5 payload.');
  }
  return _Header(
    type,
    flags,
    fields,
    extra,
    dataOffset,
    dataSize,
    dataOffset - at,
  );
}

Future<_StoredRarIndex> _parse(
  koni.ByteSource source,
  int maxBytes,
  bool Function()? isCancelled,
) async {
  void check() {
    if (isCancelled?.call() ?? false) throw const _RarStoredCancelled();
  }

  if (maxBytes <= 0 ||
      maxBytes > kArchiveStreamingLimit ||
      source.length < 0 ||
      source.length > maxBytes) {
    rarStoredError('RAR5 source exceeds its supported size limit.');
  }
  check();
  final signature = await _readExact(
    source,
    0,
    source.length < 8 ? source.length : 8,
  );
  if (signature.length != 8 ||
      List.generate(
        8,
        (i) => i,
      ).any((i) => signature[i] != rarStoredSignature[i])) {
    throw const ArchiveStreamingUnsupported(
      'This source is not a plain RAR5 Store container.',
    );
  }
  final result = _StoredRarIndex();
  final names = <String, bool>{};
  var at = 8, metadata = 0, nameBytes = 0, total = 0, blocks = 0;
  var main = false, end = false;
  while (at < source.length) {
    check();
    final header = await _header(source, at);
    metadata += header.bytes;
    if (metadata > rarStoredMaxMetadataBytes ||
        ++blocks > rarStoredMaxEntries + 2) {
      rarStoredError('RAR5 metadata exceeds its supported limit.');
    }
    if (header.flags & 0x18 != 0) {
      throw const ArchiveStreamingUnsupported(
        'Split RAR5 archives use the existing reader.',
      );
    }
    if (header.flags & ~3 != 0) {
      result.readOnly('Unknown RAR5 block flags cannot be rewritten.');
    }
    if (header.type == 4) {
      throw const ArchiveStreamingUnsupported(
        'Encrypted RAR5 archives use the existing password reader.',
      );
    }
    if (!main && header.type != 1) {
      rarStoredError('RAR5 main header is missing.');
    }
    if (header.type == 1) {
      if (main || header.dataSize != 0) {
        rarStoredError('Invalid RAR5 main header.');
      }
      main = true;
      final flags = header.fields.vint();
      if (flags & 7 != 0) {
        throw const ArchiveStreamingUnsupported(
          'Solid or multivolume RAR5 archives use the existing reader.',
        );
      }
      if (flags != 0 ||
          header.extra.isNotEmpty ||
          header.fields.remaining != 0) {
        result.readOnly(
          'RAR5 archive extensions, locks and recovery metadata cannot be rewritten.',
        );
      }
    } else if (header.type == 2) {
      final input = header.fields;
      final flags = input.vint();
      if (flags & 8 != 0) {
        throw const ArchiveStreamingUnsupported(
          'RAR5 entries with unknown sizes use the existing reader.',
        );
      }
      if (flags & ~7 != 0) {
        result.readOnly('Unknown RAR5 file flags cannot be rewritten.');
      }
      final directory = flags & 1 != 0;
      final size = input.vint(maxValue: maxBytes);
      final attributes = input.vint(maxValue: 0xffffffff);
      final headerMtime = flags & 2 == 0 ? null : input.uint32();
      final crc = flags & 4 == 0 ? null : input.uint32();
      final compression = input.vint();
      if (compression & 0x3ff != 0 ||
          compression & ~0x7fff != 0 ||
          (compression & 0x7c00) ~/ 0x400 > 15) {
        throw const ArchiveStreamingUnsupported(
          'Compressed RAR5 entries use the existing reader.',
        );
      }
      final host = input.vint();
      if (host != 0 && host != 1) {
        result.readOnly('Unknown RAR5 host attributes cannot be rewritten.');
      }
      final nameLength = input.vint(maxValue: 4096);
      final rawNameBytes = input.take(nameLength);
      nameBytes += nameLength;
      if (nameBytes > 8 * 1024 * 1024) {
        rarStoredError('RAR5 member names exceed their bound.');
      }
      String rawName;
      try {
        rawName = utf8.decode(rawNameBytes, allowMalformed: false);
      } on FormatException {
        rarStoredError('RAR5 member name is not valid UTF-8.');
      }
      if (input.remaining != 0) {
        result.readOnly('Unknown RAR5 file header data cannot be rewritten.');
      }
      final trailingSlash = directory && rawName.endsWith('/');
      final name = trailingSlash
          ? rawName.substring(0, rawName.length - 1)
          : rawName;
      var unsafe = false;
      try {
        validateRarStoredPath(name);
      } on ArchiveViewException {
        unsafe = true;
        result.readOnly('Unsafe RAR5 member paths cannot be rewritten.');
      }
      var special = false;
      if (host == 1) {
        final kind = attributes & 0xf000;
        special = kind != 0 && kind != (directory ? 0x4000 : 0x8000);
        if (attributes & ~0xffff != 0 || attributes & 0xc00 != 0) {
          result.readOnly(
            'RAR5 ownership-related or unknown Unix mode bits cannot be rewritten.',
          );
        }
      } else if (host == 0) {
        special = attributes & 0x400 != 0;
        if ((attributes & 0x10 != 0) != directory) {
          result.readOnly(
            'Conflicting RAR5 Windows directory attributes cannot be rewritten.',
          );
        }
      }
      RarStoredTimes? times;
      final extras = RarStoredCursor(header.extra);
      while (extras.remaining != 0) {
        final length = extras.vint(maxValue: rarStoredMaxHeaderBytes);
        final record = RarStoredCursor(extras.take(length));
        final type = record.vint();
        if (type == 1) {
          throw const ArchiveStreamingUnsupported(
            'Encrypted RAR5 entries use the existing password reader.',
          );
        }
        if (type == 3) {
          if (times != null) rarStoredError('Duplicate RAR5 time record.');
          times = RarStoredTimes.decode(record.take(record.remaining));
        } else {
          if (type == 5) special = true;
          result.readOnly(
            'RAR5 links, owners, hashes and unknown extra records cannot be rewritten.',
          );
        }
      }
      if (special) {
        result.readOnly(
          'RAR5 links and special filesystem entries cannot be rewritten.',
        );
      }
      if (size != header.dataSize ||
          directory && (size != 0 || crc != null && crc != 0)) {
        rarStoredError(
          'RAR5 Store data size or directory checksum is invalid.',
        );
      }
      if (!directory && crc == null) {
        result.readOnly(
          'RAR5 files without a data checksum cannot be rewritten.',
        );
      }
      total += size;
      if (total > maxBytes) {
        rarStoredError('RAR5 expanded contents exceed their limit.');
      }
      if (names.containsKey(name)) {
        result.readOnly('Duplicate RAR5 member paths cannot be rewritten.');
      }
      names[name] = directory;
      result.entries.add(
        _StoredRarEntry(
          name: name,
          size: size,
          isDirectory: directory,
          special: special,
          unsafePath: unsafe,
          dataOffset: header.dataOffset,
          crc: crc,
          modified:
              times?.modified ??
              (headerMtime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      headerMtime * 1000,
                      isUtc: true,
                    )),
          mode: host == 1 ? attributes : null,
          attributes: Map.unmodifiable({
            'rar5.hostOs': host,
            'rar5.attributes': attributes,
            'rar5.compression': compression,
            'rar5.hasCrc': crc != null,
            'rar5.trailingSlash': trailingSlash,
            if (headerMtime != null) 'rar5.headerMtime': headerMtime,
            if (times != null) 'rar5.times': times.toAttributes(),
          }),
        ),
      );
    } else if (header.type == 5) {
      final flags = header.fields.vint();
      if (flags & 1 != 0) {
        throw const ArchiveStreamingUnsupported(
          'Multivolume RAR5 archives use the existing reader.',
        );
      }
      if (header.dataSize != 0) {
        rarStoredError('RAR5 end marker contains a data area.');
      }
      if (flags != 0 ||
          header.fields.remaining != 0 ||
          header.extra.isNotEmpty ||
          header.flags != 0) {
        result.readOnly('Unknown RAR5 end metadata cannot be rewritten.');
      }
      end = true;
      at = header.next;
      break;
    } else {
      result.readOnly('RAR5 service and unknown records cannot be rewritten.');
    }
    at = header.next;
    if (blocks % 512 == 0) await Future<void>.delayed(Duration.zero);
  }
  if (!main || !end) rarStoredError('RAR5 archive end marker is missing.');
  if (at != source.length) {
    result.readOnly('RAR5 trailing signatures or data cannot be rewritten.');
  }
  for (final entry in result.entries) {
    final parts = entry.name.split('/');
    for (var count = 1; count < parts.length; count++) {
      if (names[parts.take(count).join('/')] == false) {
        result.readOnly('A RAR5 regular file occupies a directory path.');
      }
    }
  }
  check();
  return result;
}
