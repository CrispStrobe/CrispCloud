// Container metadata only, independently implemented from:
// https://www.rarlab.com/technote.htm
// RAR compressed data and encryption remain owned by the existing decoder.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_rar_stored_format.dart';
import 'archive_types.dart';

/// Borrows [source] to recover RAR5 high-precision modification times that the
/// pinned general decoder does not expose. Every file is bound to the existing
/// decoder's ordered entry, including normalized name, type, size, permissions,
/// checksum and encryption state. This does not grant any rewrite capability.
///
/// Returns null for RAR4, encrypted headers, volumes and unknown structural
/// extensions, leaving their existing reader behavior unchanged. Corrupt
/// plaintext metadata, an incomplete archive or mismatched entries fail closed.
Future<List<DateTime?>?> readRar5ModifiedTimes(
  koni.ByteSource source,
  List<koni.ArchiveEntry> entries, {
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('RAR5 metadata reading was cancelled.');
    }
  }

  check();
  if (source.length < 0 ||
      source.length > rarStoredMaxExact ||
      entries.length > rarStoredMaxEntries) {
    rarStoredError('RAR5 metadata source exceeds its supported bound.');
  }
  if (source.length < rarStoredSignature.length) return null;
  final signature = await _read(source, 0, rarStoredSignature.length);
  for (var i = 0; i < signature.length; i++) {
    if (signature[i] != rarStoredSignature[i]) return null;
  }
  var at = rarStoredSignature.length, metadataBytes = at, blocks = 0;
  var main = false, ended = false;
  final modified = <DateTime?>[];
  while (at < source.length) {
    check();
    final header = await _header(source, at);
    metadataBytes += header.headerBytes;
    if (metadataBytes > rarStoredMaxMetadataBytes ||
        ++blocks > rarStoredMaxEntries + 1024) {
      rarStoredError('RAR5 metadata exceeds its supported limit.');
    }
    if (header.flags & ~0x7f != 0 || header.flags & 0x18 != 0) return null;
    if (header.type == 4) return null;
    if (!main && header.type != 1) {
      rarStoredError('RAR5 main header is missing.');
    }
    final input = header.fields;
    if (header.type == 1) {
      if (main || header.dataSize != 0) {
        rarStoredError('Invalid RAR5 main header.');
      }
      main = true;
      final flags = input.vint();
      if (flags & 3 != 0 || flags & ~0x1f != 0) return null;
      if (input.remaining != 0) return null;
      _validateExtraRecords(header.extra);
    } else if (header.type == 2) {
      if (modified.length >= entries.length) {
        rarStoredError('RAR5 metadata entry count changed.');
      }
      final flags = input.vint();
      if (flags & ~7 != 0) return null;
      final size = input.vint();
      final attributes = input.vint(maxValue: 0xffffffff);
      final seconds = flags & 2 == 0 ? null : input.uint32();
      final crc = flags & 4 == 0 ? null : input.uint32();
      input.vint(); // Compression belongs to the independent payload decoder.
      final host = input.vint();
      if (host != 0 && host != 1) return null;
      final nameLength = input.vint(maxValue: 4096);
      String name;
      try {
        name = utf8.decode(input.take(nameLength), allowMalformed: false);
      } on FormatException {
        rarStoredError('Invalid UTF-8 in RAR5 metadata.');
      }
      if (input.remaining != 0) return null;
      var encrypted = false, redirected = false;
      RarStoredTimes? times;
      final extras = RarStoredCursor(header.extra);
      while (extras.remaining != 0) {
        final length = extras.vint(maxValue: rarStoredMaxHeaderBytes);
        final record = RarStoredCursor(extras.take(length));
        final type = record.vint();
        if (type == 1) {
          encrypted = true;
        } else if (type == 3) {
          if (times != null) rarStoredError('Duplicate RAR5 time record.');
          times = RarStoredTimes.decode(record.take(record.remaining));
        } else if (type == 5) {
          final kind = record.vint();
          record.vint(); // Redirection flags; never followed by this reader.
          record.take(record.vint(maxValue: 4096));
          record.finish();
          redirected = kind != 0;
        }
      }
      final normalized = koni.normalizeEntryPath(name);
      final directory = flags & 1 != 0 || host == 0 && attributes & 0x10 != 0;
      final expectedType = directory
          ? koni.ArchiveEntryType.directory
          : redirected
          ? koni.ArchiveEntryType.symlink
          : koni.ArchiveEntryType.file;
      final entry = entries[modified.length];
      if (entry.path != normalized.path ||
          entry.pathEscapedRoot != normalized.escapedRoot ||
          entry.type != expectedType ||
          entry.uncompressedSize != size ||
          entry.compressedSize != header.dataSize ||
          entry.crc32 != crc ||
          entry.posixMode != (host == 1 ? attributes & 0xfff : null) ||
          entry.isEncrypted != encrypted) {
        rarStoredError(
          'RAR5 metadata no longer matches its decoded member index.',
        );
      }
      modified.add(
        times?.modified ??
            (seconds == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    seconds * 1000,
                    isUtc: true,
                  )),
      );
    } else if (header.type == 3) {
      // Recovery/quick-open/comment/ACL service data is never interpreted as
      // a file. Bounds and CRC still cover its header and payload range.
      _validateExtraRecords(header.extra);
    } else if (header.type == 5) {
      final flags = input.vint();
      if (flags != 0) return null;
      input.finish();
      if (header.extra.isNotEmpty || header.dataSize != 0) {
        rarStoredError('Invalid RAR5 end header.');
      }
      if (header.next != source.length) {
        rarStoredError('RAR5 has trailing data after its end header.');
      }
      ended = true;
      break;
    } else {
      if (header.flags & 4 == 0) return null;
      _validateExtraRecords(header.extra);
    }
    at = header.next;
    if (blocks % 256 == 0) await Future<void>.delayed(Duration.zero);
  }
  if (!main || !ended || modified.length != entries.length) {
    rarStoredError('RAR5 metadata is incomplete or its entry count changed.');
  }
  check();
  return List.unmodifiable(modified);
}

void _validateExtraRecords(Uint8List bytes) {
  final input = RarStoredCursor(bytes);
  while (input.remaining != 0) {
    final size = input.vint(maxValue: rarStoredMaxHeaderBytes);
    final record = RarStoredCursor(input.take(size));
    record.vint(); // Record type is required; unknown types are safely skipped.
  }
}

class _MetadataHeader {
  const _MetadataHeader(
    this.type,
    this.flags,
    this.fields,
    this.extra,
    this.dataOffset,
    this.dataSize,
    this.headerBytes,
  );
  final int type, flags, dataOffset, dataSize, headerBytes;
  final RarStoredCursor fields;
  final Uint8List extra;
  int get next => dataOffset + dataSize;
}

Future<Uint8List> _read(koni.ByteSource source, int offset, int length) async {
  if (offset < 0 ||
      length < 0 ||
      offset > source.length ||
      length > source.length - offset) {
    rarStoredError('RAR5 metadata range leaves the source.');
  }
  final bytes = await source.read(offset, length);
  if (bytes.length != length) {
    rarStoredError('RAR5 metadata source was truncated.');
  }
  return bytes;
}

Future<_MetadataHeader> _header(koni.ByteSource source, int offset) async {
  final prefix = await _read(source, offset, 7);
  final start = RarStoredCursor(prefix);
  final expected = start.uint32();
  final size = start.vint(maxBytes: 3, maxValue: rarStoredMaxHeaderBytes);
  final bodyOffset = offset + start.offset;
  final body = await _read(source, bodyOffset, size);
  var crc = getCrc32(Uint8List.sublistView(prefix, 4, start.offset));
  crc = getCrc32(body, crc);
  if (crc != expected) {
    rarStoredError('RAR5 metadata header checksum mismatch.');
  }
  final input = RarStoredCursor(body);
  final type = input.vint(), flags = input.vint();
  final extraSize = flags & 1 == 0 ? 0 : input.vint();
  final dataSize = flags & 2 == 0 ? 0 : input.vint();
  if (extraSize > input.remaining) {
    rarStoredError('RAR5 extra area exceeds its header.');
  }
  final dataOffset = bodyOffset + size;
  if (dataSize > source.length - dataOffset) {
    rarStoredError('RAR5 payload extends beyond the source.');
  }
  return _MetadataHeader(
    type,
    flags,
    RarStoredCursor(body, offset: input.offset, end: body.length - extraSize),
    Uint8List.sublistView(body, body.length - extraSize),
    dataOffset,
    dataSize,
    dataOffset - offset,
  );
}
