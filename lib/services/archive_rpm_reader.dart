// Read-only RPM package payloads. Format references:
// https://rpm.org/docs/4.20.x/manual/format_v3.html
// https://rpm.org/docs/4.20.x/manual/format_v4.html
// https://rpm.org/docs/4.20.x/manual/format_header.html
// https://rpm.org/docs/latest/manual/tags (RPMFORMAT 5114; digest tag IDs)
// No package scripts run, and OpenPGP/publisher signatures are not verified.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart' as crypto;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_package_readers.dart';
import 'archive_types.dart';

const _maxMetadataBytes = 16 * 1024 * 1024;
const _maxIndexEntries = 200000;

/// Opens the newc/CRC CPIO payload of a classic RPM v3/v4 package.
///
/// Both the packed payload and expanded CPIO are bounded independently by
/// [maxBufferedContainerBytes]. This is a package browser, not an installer:
/// scripts, dependencies, ownership, capabilities and signatures are not applied.
/// This function owns [source], including when opening fails.
Future<ViewerArchive> openRpmArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxBufferedContainerBytes = kArchiveReadLimit,
}) async {
  final input = _RpmInput(source);
  ViewerArchive? payloadArchive;
  try {
    if (maxMemberBytes <= 0 || maxBufferedContainerBytes <= 0) {
      throw ArgumentError('RPM limits must be positive.');
    }
    final lead = await input.metadata(0, 96);
    if (!_startsWith(lead, const [0xed, 0xab, 0xee, 0xdb])) {
      throw _corrupt('Invalid RPM lead signature.');
    }
    final leadData = ByteData.sublistView(lead);
    if ((lead[4] != 3 && lead[4] != 4) ||
        lead[5] != 0 ||
        leadData.getUint16(6) > 1 ||
        leadData.getUint16(78) != 5) {
      throw const ArchiveViewException(
        'This RPM lead or signature format is unavailable. '
        'Classic v3/v4 packages with header-style signatures are supported.',
      );
    }
    final signature = await input.header(96);
    final headerOffset = (signature.end + 7) ~/ 8 * 8;
    if ((await input.metadata(
      signature.end,
      headerOffset - signature.end,
    )).any((byte) => byte != 0)) {
      throw _corrupt('Invalid RPM signature padding.');
    }
    final header = await input.header(headerOffset);
    final rpmFormat = header.uint32(5114);
    if (rpmFormat != null && rpmFormat != 3 && rpmFormat != 4) {
      throw const ArchiveViewException(
        'This RPM package version is unavailable. Classic v3/v4 packages '
        'are supported.',
      );
    }
    final format = header.string(1124) ?? 'cpio';
    if (format != 'cpio') {
      throw const ArchiveViewException(
        'Only RPM packages with a CPIO payload are supported.',
      );
    }
    // RPM v3 predates the compressor tag and uses gzip by default.
    final compressor = header.string(1125) ?? 'gzip';
    if (!const {'gzip', 'bzip2', 'xz', 'zstd', 'none'}.contains(compressor)) {
      throw ArchiveViewException(
        'This RPM payload compressor is unavailable: $compressor.',
      );
    }
    final packedLength = source.length - header.end;
    if (packedLength <= 0 || packedLength > maxBufferedContainerBytes) {
      throw const ArchiveViewException(
        'The RPM payload is missing or exceeds the buffered container limit.',
      );
    }
    final packed = await input.read(header.end, packedLength);
    if (_compression(packed) != compressor) {
      throw _corrupt(
        'The RPM payload does not match its declared compression format.',
      );
    }
    final declaredSize = signature.uint32(1000);
    final longSize = signature.uint64(270);
    if ((declaredSize != null &&
            declaredSize != source.length - headerOffset) ||
        (longSize != null && longSize != source.length - headerOffset)) {
      throw _corrupt('The RPM header and payload size do not match.');
    }
    final md5 = signature.binary(1004, expectedLength: 16);
    if (md5 != null) {
      final sink = _DigestSink();
      final digest = crypto.md5.startChunkedConversion(sink)
        ..add(header.prefix)
        ..add(header.body)
        ..add(packed);
      digest.close();
      if (!_equalBytes(sink.value!.bytes, md5)) {
        throw _corrupt('RPM header/payload MD5 checksum mismatch.');
      }
    }
    final algorithm = header.uint32(5093);
    if (algorithm != null && algorithm != 8) {
      throw const ArchiveViewException(
        'This RPM payload digest algorithm is unavailable.',
      );
    }
    _verifyPayloadDigest(header, 5092, packed, 'compressed');
    final decoded = _decode(packed, compressor, maxBufferedContainerBytes);
    _verifyPayloadDigest(header, 5097, decoded, 'uncompressed');
    final declaredExpanded = header.uint32(1046);
    final signatureExpanded = signature.uint32(1007);
    final longExpanded = signature.uint64(271);
    if ((declaredExpanded != null && declaredExpanded != decoded.length) ||
        (signatureExpanded != null && signatureExpanded != decoded.length) ||
        (longExpanded != null && longExpanded != decoded.length)) {
      throw _corrupt('The RPM expanded payload size does not match.');
    }
    if (!_startsWith(decoded, ascii.encode('070701')) &&
        !_startsWith(decoded, ascii.encode('070702'))) {
      throw const ArchiveViewException(
        'This RPM CPIO variant is unavailable. Only newc and CRC payloads '
        'are supported; stripped large-file payloads are not decoded.',
      );
    }
    payloadArchive = await openCpioArchive(
      koni.MemoryByteSource(decoded, name: 'payload.cpio'),
      maxMemberBytes: maxMemberBytes,
    );
    final archive = payloadArchive;
    return ViewerArchive.reader(
      formatName: 'rpm',
      members: archive.members,
      notices: [
        'RPM payload files only. Publisher signatures and separate '
            'header/file digests are not verified. Package scripts are never '
            'executed; links and special entries cannot be extracted.',
        ...archive.notices,
      ],
      read: (member, limit) => archive.readMember(
        member,
        maxBytes: limit < maxMemberBytes ? limit : maxMemberBytes,
      ),
      streamReader: (member, chunkSize) => archive.openMember(
        member,
        maxBytes: maxMemberBytes,
        chunkSize: chunkSize,
      ),
      close: () async {
        try {
          await archive.close();
        } finally {
          await input.close();
        }
      },
    );
  } catch (error) {
    try {
      await payloadArchive?.close();
    } finally {
      await input.close();
    }
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw _corrupt('Could not read RPM package: $error');
  }
}

Uint8List _decode(Uint8List bytes, String compressor, int limit) {
  if (compressor == 'none') return bytes;
  final input = ar.InputMemoryStream(bytes);
  final output = ar.OutputMemoryStream();
  try {
    final decoded = switch (compressor) {
      'gzip' => const ar.GZipDecoder().decodeStream(
        input,
        output,
        verify: true,
        throwOnError: true,
        maxOutputSize: limit,
      ),
      'bzip2' => ar.BZip2Decoder().decodeStream(
        input,
        output,
        verify: true,
        throwOnError: true,
        maxOutputSize: limit,
      ),
      'xz' =>
        ar.XZDecoder(
          maxDictionarySize: 64 * 1024 * 1024,
          maxPreallocateSize: limit,
        ).decodeStream(
          input,
          output,
          verify: true,
          throwOnError: true,
          maxOutputSize: limit,
        ),
      'zstd' => ar.ZstdDecoder(maxWindowSize: 64 * 1024 * 1024).decodeStream(
        input,
        output,
        verify: true,
        throwOnError: true,
        maxOutputSize: limit,
      ),
      _ => false,
    };
    if (!decoded || !input.isEOS) {
      throw _corrupt(
        'The RPM compressed payload is incomplete or has trailing data.',
      );
    }
    return output.getBytes();
  } on ArchiveViewException {
    rethrow;
  } catch (error) {
    throw _corrupt(
      'The RPM compressed payload is corrupt or exceeds the buffered '
      'container limit: $error',
    );
  }
}

String? _compression(List<int> bytes) {
  if (_startsWith(bytes, const [0x1f, 0x8b])) return 'gzip';
  if (_startsWith(bytes, const [0x42, 0x5a, 0x68])) return 'bzip2';
  if (_startsWith(bytes, const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0])) return 'xz';
  if (_startsWith(bytes, const [0x28, 0xb5, 0x2f, 0xfd])) return 'zstd';
  if (_startsWith(bytes, ascii.encode('07070'))) return 'none';
  return null;
}

void _verifyPayloadDigest(
  _RpmHeader header,
  int tag,
  Uint8List bytes,
  String label,
) {
  final digests = header.strings(tag);
  if (digests == null) return;
  if (digests.length != 1 ||
      !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digests.single)) {
    throw _corrupt('Invalid RPM $label payload SHA-256 digest.');
  }
  if (crypto.sha256.convert(bytes).toString() != digests.single.toLowerCase()) {
    throw _corrupt('RPM $label payload SHA-256 checksum mismatch.');
  }
}

class _RpmInput {
  _RpmInput(this.source);
  final koni.ByteSource source;
  int _metadataBytes = 0;
  int _entries = 0;
  bool _closed = false;

  Future<Uint8List> read(int offset, int length) async {
    if (_closed ||
        offset < 0 ||
        length < 0 ||
        offset > source.length ||
        length > source.length - offset) {
      throw _corrupt('An RPM extent leaves its source.');
    }
    final bytes = await source.read(offset, length);
    if (bytes.length != length) throw _corrupt('The RPM source is truncated.');
    return bytes;
  }

  Future<Uint8List> metadata(int offset, int length) async {
    if (length < 0 || length > _maxMetadataBytes - _metadataBytes) {
      throw _corrupt('RPM metadata exceeds the 16 MiB limit.');
    }
    _metadataBytes += length;
    return read(offset, length);
  }

  Future<_RpmHeader> header(int offset) async {
    final prefix = await metadata(offset, 16);
    if (!_startsWith(prefix, const [0x8e, 0xad, 0xe8, 1, 0, 0, 0, 0])) {
      throw _corrupt('Invalid RPM header signature.');
    }
    final prefixData = ByteData.sublistView(prefix);
    final count = prefixData.getUint32(8);
    final dataLength = prefixData.getUint32(12);
    if (count > _maxIndexEntries - _entries) {
      throw _corrupt('The RPM headers have too many index entries.');
    }
    _entries += count;
    final indexLength = count * 16;
    final body = await metadata(offset + 16, indexLength + dataLength);
    final data = Uint8List.sublistView(body, indexLength);
    final table = ByteData.sublistView(body, 0, indexLength);
    final entries = <int, _RpmEntry>{};
    var scannedStrings = 0;
    var lastTag = 0;
    for (var i = 0; i < count; i++) {
      final at = i * 16;
      final tag = table.getUint32(at);
      final type = table.getUint32(at + 4);
      final start = table.getInt32(at + 8);
      final values = table.getUint32(at + 12);
      if (tag <= lastTag ||
          type < 1 ||
          type > 9 ||
          start < 0 ||
          start > dataLength ||
          values == 0) {
        throw _corrupt('Invalid or duplicate RPM header index entry.');
      }
      lastTag = tag;
      final width = switch (type) {
        3 => 2,
        4 => 4,
        5 => 8,
        _ => 1,
      };
      if (start % width != 0) {
        throw _corrupt('Misaligned RPM integer metadata.');
      }
      var end = start;
      if (type == 6 || type == 8 || type == 9) {
        if ((type == 6 && values != 1) || values > _maxIndexEntries) {
          throw _corrupt('Invalid RPM string count.');
        }
        for (var item = 0; item < values; item++) {
          while (true) {
            if (end >= dataLength || ++scannedStrings > _maxMetadataBytes) {
              throw _corrupt('Unterminated or oversized RPM string metadata.');
            }
            if (data[end++] == 0) break;
          }
        }
      } else {
        final bytes = values * width;
        if (bytes > dataLength - start) {
          throw _corrupt('An RPM header value leaves its data region.');
        }
        end += bytes;
      }
      entries[tag] = _RpmEntry(
        type,
        values,
        Uint8List.sublistView(data, start, end),
      );
    }
    return _RpmHeader(prefix, body, offset + 16 + body.length, entries);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await source.close();
  }
}

class _RpmEntry {
  const _RpmEntry(this.type, this.count, this.bytes);
  final int type, count;
  final Uint8List bytes;
}

class _RpmHeader {
  const _RpmHeader(this.prefix, this.body, this.end, this.entries);
  final Uint8List prefix, body;
  final int end;
  final Map<int, _RpmEntry> entries;

  String? string(int tag) {
    final entry = entries[tag];
    if (entry == null) return null;
    if (entry.type != 6 || entry.count != 1) {
      throw _corrupt('An RPM string tag has the wrong type.');
    }
    return ascii.decode(entry.bytes.sublist(0, entry.bytes.length - 1));
  }

  List<String>? strings(int tag) {
    final entry = entries[tag];
    if (entry == null) return null;
    if (entry.type != 8) {
      throw _corrupt('An RPM string-array tag has the wrong type.');
    }
    return ascii
        .decode(entry.bytes.sublist(0, entry.bytes.length - 1))
        .split('\u0000');
  }

  int? uint32(int tag) {
    final entry = entries[tag];
    if (entry == null) return null;
    if (entry.type != 4 || entry.count != 1) {
      throw _corrupt('An RPM integer tag has the wrong type.');
    }
    return ByteData.sublistView(entry.bytes).getUint32(0);
  }

  int? uint64(int tag) {
    final entry = entries[tag];
    if (entry == null) return null;
    if (entry.type != 5 || entry.count != 1) {
      throw _corrupt('An RPM long-integer tag has the wrong type.');
    }
    final data = ByteData.sublistView(entry.bytes);
    final high = data.getUint32(0);
    if (high > 0x1fffff) {
      throw _corrupt('An RPM integer exceeds the safe range.');
    }
    return high * 4294967296 + data.getUint32(4);
  }

  Uint8List? binary(int tag, {required int expectedLength}) {
    final entry = entries[tag];
    if (entry == null) return null;
    if (entry.type != 7 || entry.bytes.length != expectedLength) {
      throw _corrupt('An RPM binary tag has the wrong type or size.');
    }
    return entry.bytes;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

bool _startsWith(List<int> bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

bool _equalBytes(List<int> a, List<int> b) =>
    a.length == b.length && _startsWith(a, b);

ArchiveViewException _corrupt(String message) => ArchiveViewException(
  message,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': message},
);
