// Read-only package readers. These decode containers, never install packages
// or verify publisher/code signatures. Payloads stay in the owned ByteSource
// until a bounded member read is requested.
//
// Format references: GNU binutils ar; SVR4 cpio newc/crc; Apple's xar format.
// The format capability registry keeps these readers separate from writers.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart' as crypto;
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'archive_types.dart';

const _maxEntries = 200000;
const _maxMetadataBytes = 16 * 1024 * 1024;
const _maxNameBytes = 16384;
const _maxTocBytes = 8 * 1024 * 1024;
const _maxSafeInteger = 9007199254740991;

/// Reads ordinary, GNU and BSD AR archives, including Debian .deb containers.
/// Thin archives are refused because they refer to files outside the container.
Future<ViewerArchive> openArArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
}) => _ownSource(source, 'AR', () async {
  final input = _PackageInput(source, maxMemberBytes);
  final magic = await input.metadata(0, 8);
  if (ascii.decode(magic, allowInvalid: true) != '!<arch>\n') {
    throw const ArchiveViewException(
      'Only ordinary AR archives are supported; thin archives are unavailable.',
    );
  }
  final members = <ViewerArchiveMember>[];
  final payloads = <_Payload>[];
  Map<int, String>? longNames;
  var offset = 8;
  var recordCount = 0;
  while (offset < source.length) {
    _checkCount(++recordCount);
    final header = await input.metadata(offset, 60);
    if (header[58] != 0x60 || header[59] != 0x0a) {
      throw _corrupt('Invalid AR member header.');
    }
    String field(int start, int end) =>
        ascii.decode(header.sublist(start, end)).trim();
    var name = field(0, 16);
    final packedSize = _number(field(48, 58), 10, 'AR member size');
    final modifiedSeconds = _number(
      field(16, 28),
      10,
      'AR modification time',
      emptyIsZero: true,
      allowNegative: true,
    );
    final mode = _number(field(40, 48), 8, 'AR mode', emptyIsZero: true);
    _number(field(28, 34), 10, 'AR owner', emptyIsZero: true);
    _number(field(34, 40), 10, 'AR group', emptyIsZero: true);
    var dataOffset = offset + 60;
    var size = packedSize;
    input.checkRange(dataOffset, size);
    final next = dataOffset + packedSize + (packedSize.isOdd ? 1 : 0);
    input.checkRange(dataOffset + packedSize, packedSize.isOdd ? 1 : 0);
    if (packedSize.isOdd && (await input.metadata(next - 1, 1))[0] != 0x0a) {
      throw _corrupt('Invalid AR member padding.');
    }
    if (name == '//') {
      if (longNames != null || size > _maxMetadataBytes) {
        throw _corrupt('Invalid or oversized AR long-name table.');
      }
      final table = await input.metadata(dataOffset, size);
      longNames = <int, String>{};
      var start = 0;
      for (var at = 0; at < table.length; at++) {
        if (table[at] != 0x0a) continue;
        if (at == start && at == table.length - 1) {
          start = at + 1;
          continue;
        }
        final end = at > start && table[at - 1] == 0x2f ? at - 1 : at;
        if (end <= start || end - start > _maxNameBytes) {
          throw _corrupt('Invalid AR long name.');
        }
        longNames[start] = utf8.decode(table.sublist(start, end));
        _checkCount(longNames.length);
        start = at + 1;
      }
      // GNU ar can pad its string table with a final newline.
      if (start != table.length) {
        throw _corrupt('Unterminated AR long-name table.');
      }
      offset = next;
      continue;
    }
    if (name == '/' || name == '/SYM64/') {
      offset = next;
      continue;
    }
    if (name.startsWith('#1/')) {
      final nameSize = _number(name.substring(3), 10, 'BSD AR name length');
      if (nameSize <= 0 || nameSize > _maxNameBytes || nameSize > size) {
        throw _corrupt('Invalid BSD AR name length.');
      }
      final nameBytes = await input.metadata(dataOffset, nameSize);
      var end = nameBytes.length;
      while (end > 0 && nameBytes[end - 1] == 0) {
        end--;
      }
      name = utf8.decode(nameBytes.sublist(0, end));
      dataOffset += nameSize;
      size -= nameSize;
    } else if (name.startsWith('/')) {
      final nameOffset = _number(name.substring(1), 10, 'GNU AR name offset');
      final resolved = longNames?[nameOffset];
      if (resolved == null) throw _corrupt('Invalid GNU AR name reference.');
      name = resolved;
    } else if (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    if (name == '__.SYMDEF' ||
        name == '__.SYMDEF SORTED' ||
        name == '__.SYMDEF_64' ||
        name == '__.SYMDEF_64 SORTED') {
      offset = next;
      continue;
    }
    final path = _memberPath(name);
    members.add(
      ViewerArchiveMember(
        name: path.name,
        size: size,
        isFile: true,
        isEncrypted: false,
        pathEscapedRoot: path.unsafe,
        index: members.length,
        modified: _date(modifiedSeconds),
        posixMode: mode,
      ),
    );
    payloads.add(_Payload(dataOffset, size));
    offset = next;
  }
  return _rawArchive('ar', input, members, payloads);
});

/// Reads modern binary little/big-endian CPIO, portable ASCII/odc (070707),
/// SVR4 newc (070701) and CRC (070702).
/// Links and special files are listed as non-extractable metadata. Concatenated
/// archives and PWB-specific type semantics are not silently interpreted.
/// A separate preservation inspector determines eligibility for rewriting.
/// https://github.com/libarchive/libarchive/blob/master/libarchive/cpio.5
Future<ViewerArchive> openCpioArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
}) => _ownSource(source, 'CPIO', () async {
  final input = _PackageInput(source, maxMemberBytes);
  final members = <ViewerArchiveMember>[];
  final payloads = <_Payload>[];
  var offset = 0;
  var records = 0;
  var trailer = false;
  String? profile;
  while (offset < source.length) {
    _checkCount(++records);
    final signature = await input.metadata(offset, 6);
    final little = signature[0] == 0xc7 && signature[1] == 0x71;
    final binary = little || (signature[0] == 0x71 && signature[1] == 0xc7);
    final magic = binary
        ? (little ? 'binary-le' : 'binary-be')
        : ascii.decode(signature);
    final odc = magic == '070707';
    if (!binary && !odc && magic != '070701' && magic != '070702') {
      throw const ArchiveViewException(
        'This CPIO variant is unavailable. Supported variants are modern binary, odc, newc and CRC.',
      );
    }
    // newc and CRC use the same record layout and may be mixed; the existing
    // writer preserves the variant of each record. Only layout or byte-order
    // transitions would make this archive's interpretation ambiguous.
    final currentProfile = binary || odc ? magic : 'newc-crc';
    if (profile != null && profile != currentProfile) {
      throw _corrupt(
        'Mixed CPIO header profiles or byte orders are unavailable.',
      );
    }
    profile = currentProfile;
    final headerSize = binary ? 26 : (odc ? 76 : 110);
    final int mode, links, modified, size, nameSize, checksum;
    if (binary) {
      final data = ByteData.sublistView(await input.metadata(offset, 26));
      final order = little ? Endian.little : Endian.big;
      int word(int index) => data.getUint16(index * 2, order);
      // CPIO stores the high 16-bit word first even in its little-endian
      // layout. Reading these fields as ordinary uint32 would swap the words.
      mode = word(3);
      links = word(6);
      modified = word(8) * 65536 + word(9);
      nameSize = word(10);
      size = word(11) * 65536 + word(12);
      checksum = 0;
      if (size > 0x7fffffff) throw _corrupt('Invalid binary CPIO member size.');
    } else {
      final fields = await input.metadata(offset + 6, headerSize - 6);
      final values = <int>[];
      var fieldOffset = 0;
      for (final width
          in odc
              ? const [6, 6, 6, 6, 6, 6, 6, 11, 6, 11]
              : const [8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]) {
        values.add(
          _number(
            ascii.decode(fields.sublist(fieldOffset, fieldOffset + width)),
            odc ? 8 : 16,
            'CPIO header field',
          ),
        );
        fieldOffset += width;
      }
      mode = values[odc ? 2 : 1];
      links = values[odc ? 5 : 4];
      modified = values[odc ? 7 : 5];
      size = values[odc ? 9 : 6];
      nameSize = values[odc ? 8 : 11];
      checksum = odc ? 0 : values[12];
    }
    if (nameSize < 1 || nameSize > _maxNameBytes) {
      throw _corrupt('Invalid CPIO name length.');
    }
    final nameBytes = await input.metadata(offset + headerSize, nameSize);
    if (nameBytes.last != 0 || nameBytes.take(nameSize - 1).contains(0)) {
      throw _corrupt('Invalid CPIO member name terminator.');
    }
    final name = utf8.decode(nameBytes.sublist(0, nameSize - 1));
    final nameEnd = offset + headerSize + nameSize;
    int align(int value) =>
        binary ? (value + 1) ~/ 2 * 2 : (odc ? value : _align4(value));
    final dataOffset = align(nameEnd);
    input.checkRange(dataOffset, size);
    final next = align(dataOffset + size);
    input.checkRange(dataOffset + size, next - dataOffset - size);
    if (binary &&
        ((await input.metadata(
              nameEnd,
              dataOffset - nameEnd,
            )).any((byte) => byte != 0) ||
            (await input.metadata(
              dataOffset + size,
              next - dataOffset - size,
            )).any((byte) => byte != 0))) {
      throw _corrupt('Invalid binary CPIO alignment padding.');
    }
    if ((magic == '070701' || size == 0) && checksum != 0) {
      throw _corrupt('Invalid CPIO checksum field.');
    }
    if (name == 'TRAILER!!!') {
      if (size != 0) throw _corrupt('Invalid CPIO trailer.');
      offset = next;
      trailer = true;
      break;
    }
    final kind = mode & 0xf000;
    final directory = kind == 0x4000;
    final file = kind == 0x8000 && links <= 1;
    if (directory && size != 0) {
      throw _corrupt('A CPIO directory contains unexpected file data.');
    }
    final path = _memberPath(name, allowRoot: directory);
    if (path.name != '/') {
      members.add(
        ViewerArchiveMember(
          name: path.name,
          size: size,
          isFile: file,
          isEncrypted: false,
          isSpecial: !file && !directory,
          pathEscapedRoot: path.unsafe,
          index: members.length,
          modified: _date(modified),
          posixMode: mode,
        ),
      );
      payloads.add(
        _Payload(
          dataOffset,
          size,
          checksum: magic == '070702' ? checksum : null,
        ),
      );
    }
    offset = next;
  }
  if (!trailer) throw _corrupt('The CPIO end-of-archive trailer is missing.');
  final padding = source.length - offset;
  if (padding > 65536) {
    throw _corrupt('CPIO trailing data exceeds the padding limit.');
  }
  if ((await input.metadata(offset, padding)).any((byte) => byte != 0)) {
    throw _corrupt(
      'Concatenated or non-padding CPIO trailing data is unavailable.',
    );
  }
  return _rawArchive('cpio', input, members, payloads);
});

/// Reads XAR v1 containers, including the outer container of PKG and XIP.
/// SHA-1/MD5/SHA-256/SHA-512 content checksums are checked when present; these
/// checksums do not authenticate a package publisher or its signing chain.
Future<ViewerArchive> openXarArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
}) => _ownSource(source, 'XAR', () async {
  final input = _PackageInput(source, maxMemberBytes);
  final header = await input.metadata(0, 28);
  final data = ByteData.sublistView(header);
  if (data.getUint32(0) != 0x78617221 || data.getUint16(6) != 1) {
    throw _corrupt('Invalid or unsupported XAR header.');
  }
  final headerSize = data.getUint16(4);
  final compressedSize = _uint64(data, 8);
  final tocSize = _uint64(data, 16);
  final algorithm = data.getUint32(24);
  if (headerSize < 28 ||
      headerSize > 4096 ||
      compressedSize < 1 ||
      compressedSize > _maxTocBytes ||
      tocSize < 1 ||
      tocSize > _maxTocBytes) {
    throw _corrupt('XAR table of contents exceeds its metadata limits.');
  }
  final tocStyle = switch (algorithm) {
    0 => 'none',
    1 => 'sha1',
    2 => 'md5',
    3 => 'sha256',
    4 => 'sha512',
    _ => throw const ArchiveViewException(
      'This XAR table-of-contents checksum is unavailable.',
    ),
  };
  final compressed = await input.metadata(headerSize, compressedSize);
  input.chargeMetadata(tocSize);
  final tocBytes = const ar.ZLibDecoder().decodeBytes(
    compressed,
    verify: true,
    maxOutputSize: tocSize,
  );
  if (tocBytes.length != tocSize) throw _corrupt('Incorrect XAR TOC size.');
  final text = utf8.decode(tocBytes);
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    throw _corrupt(
      'DTD and entity declarations are not supported in XAR metadata.',
    );
  }
  var depth = 0, elements = 0, events = 0;
  for (final event in parseEvents(text)) {
    if (++events > 200000) {
      throw _corrupt('XAR metadata contains too many XML events.');
    }
    if (event is XmlStartElementEvent) {
      if (++elements > 100000 || ++depth > 128) {
        throw _corrupt('XAR metadata is too deeply nested or too large.');
      }
      if (event.isSelfClosing) depth--;
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
  final root = XmlDocument.parse(text).rootElement;
  if (root.name.qualified != 'xar') throw _corrupt('Invalid XAR XML root.');
  final toc = _child(root, 'toc', required: true)!;
  final heapOffset = headerSize + compressedSize;
  input.checkRange(heapOffset, 0);
  final tocChecksum = _child(toc, 'checksum');
  int? protectedOffset;
  var protectedLength = 0;
  if (tocStyle != 'none') {
    if (tocChecksum == null || tocChecksum.getAttribute('style') != tocStyle) {
      throw _corrupt('XAR header and TOC checksum disagree.');
    }
    final expectedLength = _hash(tocStyle).convert(const <int>[]).bytes.length;
    final checksumOffset = _xmlNumber(tocChecksum, 'offset');
    final checksumSize = _xmlNumber(tocChecksum, 'size');
    if (checksumSize != expectedLength) {
      throw _corrupt('Invalid XAR TOC checksum size.');
    }
    input.checkRange(heapOffset, checksumOffset);
    protectedOffset = heapOffset + checksumOffset;
    protectedLength = checksumSize;
    final expected = await input.metadata(protectedOffset, checksumSize);
    final actual = _hash(tocStyle).convert(compressed).bytes;
    if (!_equalBytes(actual, expected)) {
      throw _corrupt('XAR TOC checksum mismatch.');
    }
  } else if (tocChecksum != null &&
      tocChecksum.getAttribute('style') != 'none') {
    throw _corrupt('XAR header and TOC checksum disagree.');
  }
  final members = <ViewerArchiveMember>[];
  final payloads = <_XarPayload?>[];
  final pending =
      <({XmlElement element, String parent, int depth, bool unsafe})>[];
  for (final element
      in toc.childElements
          .where((e) => e.name.qualified == 'file')
          .toList()
          .reversed) {
    pending.add((element: element, parent: '', depth: 0, unsafe: false));
  }
  while (pending.isNotEmpty) {
    final item = pending.removeLast();
    _checkCount(members.length + 1);
    if (item.depth > 64) throw _corrupt('XAR file hierarchy is too deep.');
    final element = item.element;
    final rawName = _child(element, 'name', required: true)!.innerText;
    final typeElement = _child(element, 'type', required: true)!;
    final type = typeElement.innerText.trim();
    final directory = type == 'directory';
    final file = type == 'file' && typeElement.getAttribute('link') == null;
    final path = _memberPath(
      item.parent.isEmpty ? rawName : '${item.parent}/$rawName',
    );
    final unsafe =
        item.unsafe ||
        path.unsafe ||
        rawName.contains('/') ||
        rawName.contains('\\');
    final dataElement = _child(element, 'data');
    _XarPayload? payload;
    var size = 0;
    if (dataElement != null && file) {
      size = _xmlNumber(dataElement, 'size');
      final length = _xmlNumber(dataElement, 'length');
      final relativeOffset = _xmlNumber(dataElement, 'offset');
      input.checkRange(heapOffset, relativeOffset);
      final offset = heapOffset + relativeOffset;
      input.checkRange(offset, length);
      if (protectedOffset != null &&
          length > 0 &&
          offset < protectedOffset + protectedLength &&
          protectedOffset < offset + length) {
        throw _corrupt('XAR member overlaps its TOC checksum.');
      }
      final encoding =
          _child(dataElement, 'encoding')?.getAttribute('style') ??
          'application/octet-stream';
      payload = _XarPayload(
        offset,
        length,
        size,
        encoding,
        _checksum(dataElement, 'archived-checksum'),
        _checksum(dataElement, 'extracted-checksum'),
      );
    } else if (dataElement != null && directory) {
      throw _corrupt('A XAR directory contains unexpected file data.');
    }
    final modeText = _child(element, 'mode')?.innerText.trim();
    members.add(
      ViewerArchiveMember(
        name: path.name,
        size: size,
        isFile: file,
        isEncrypted: false,
        isSpecial: !file && !directory,
        pathEscapedRoot: unsafe,
        index: members.length,
        modified: DateTime.tryParse(
          _child(element, 'mtime')?.innerText.trim() ?? '',
        ),
        posixMode: modeText == null ? null : _number(modeText, 8, 'XAR mode'),
      ),
    );
    payloads.add(payload);
    final children = element.childElements
        .where((e) => e.name.qualified == 'file')
        .toList();
    if (!directory && children.isNotEmpty) {
      throw _corrupt('XAR files cannot contain child entries.');
    }
    for (final child in children.reversed) {
      pending.add((
        element: child,
        parent: path.name,
        depth: item.depth + 1,
        unsafe: unsafe,
      ));
    }
  }
  return ViewerArchive.reader(
    formatName: 'xar',
    members: List.unmodifiable(members),
    read: (member, requestedLimit) async {
      final limit = requestedLimit < maxMemberBytes
          ? requestedLimit
          : maxMemberBytes;
      _checkReadable(member, limit);
      final payload = payloads[member.index];
      if (payload == null) return Uint8List(0);
      final outputLimit = payload.size < limit ? payload.size : limit;
      try {
        if (payload.length > maxMemberBytes + 65536) {
          throw _corrupt(
            'The compressed XAR member exceeds the input safety limit.',
          );
        }
        final packed = await input.read(payload.offset, payload.length);
        _verifyHash(payload.archivedChecksum, packed);
        final Uint8List unpacked;
        switch (payload.encoding) {
          case 'application/octet-stream':
            if (payload.length != payload.size) {
              throw _corrupt(
                'Stored XAR member size does not match its metadata.',
              );
            }
            unpacked = Uint8List.fromList(packed);
          case 'application/x-gzip':
          case 'application/zlib':
            // XAR's historical x-gzip spelling denotes a zlib stream.
            unpacked = const ar.ZLibDecoder().decodeBytes(
              packed,
              verify: true,
              maxOutputSize: outputLimit,
            );
          case 'application/x-bzip2':
            unpacked = ar.BZip2Decoder().decodeBytes(
              packed,
              verify: true,
              maxOutputSize: outputLimit,
            );
          case 'application/x-xz':
            unpacked = ar.XZDecoder().decodeBytes(
              packed,
              verify: true,
              maxOutputSize: outputLimit,
            );
          default:
            throw ArchiveViewException(
              'This XAR member compression is unavailable: ${payload.encoding}',
            );
        }
        if (unpacked.length != payload.size || unpacked.length > limit) {
          throw _corrupt('XAR member size does not match its metadata.');
        }
        _verifyHash(payload.extractedChecksum, unpacked);
        return unpacked;
      } on ArchiveViewException {
        rethrow;
      } catch (error) {
        throw _corrupt('Could not decode the XAR member: $error');
      }
    },
    close: source.close,
  );
});

Future<ViewerArchive> _ownSource(
  koni.ByteSource source,
  String format,
  Future<ViewerArchive> Function() open,
) async {
  try {
    return await open();
  } catch (error) {
    try {
      await source.close();
    } catch (_) {
      /* Preserve the parse error. */
    }
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw _corrupt('Could not read the $format container: $error');
  }
}

ViewerArchive _rawArchive(
  String format,
  _PackageInput input,
  List<ViewerArchiveMember> members,
  List<_Payload> payloads,
) => ViewerArchive.reader(
  formatName: format,
  members: List.unmodifiable(members),
  read: (member, requestedLimit) async {
    final limit = requestedLimit < input.maxMemberBytes
        ? requestedLimit
        : input.maxMemberBytes;
    _checkReadable(member, limit);
    final payload = payloads[member.index];
    final bytes = await input.read(payload.offset, payload.length);
    if (payload.checksum != null) {
      var sum = 0;
      for (final byte in bytes) {
        sum = (sum + byte) & 0xffffffff;
      }
      if (sum != payload.checksum) {
        throw _corrupt('CPIO member checksum mismatch.');
      }
    }
    return Uint8List.fromList(bytes);
  },
  close: input.source.close,
);

void _checkReadable(ViewerArchiveMember member, int limit) {
  if (!member.isFile || member.isSpecial || member.pathEscapedRoot) {
    throw _corrupt('This archive member is not a safe regular file.');
  }
  if (member.size > limit) {
    throw ArchiveViewException(
      'The archive member exceeds the read safety limit.',
      code: ArchiveMessageCode.entryLimit,
      arguments: {'limit': '$limit bytes'},
    );
  }
}

class _PackageInput {
  _PackageInput(this.source, this.maxMemberBytes) {
    if (maxMemberBytes <= 0) {
      throw ArgumentError.value(maxMemberBytes, 'maxMemberBytes');
    }
    if (source.length < 0 || source.length > _maxSafeInteger) {
      throw _corrupt('The container size cannot be represented safely.');
    }
  }
  final koni.ByteSource source;
  final int maxMemberBytes;
  var _metadataBytes = 0;
  void checkRange(int offset, int length) {
    if (offset < 0 ||
        length < 0 ||
        offset > source.length ||
        length > source.length - offset) {
      throw _corrupt('A container record extends beyond the available input.');
    }
  }

  void chargeMetadata(int length) {
    if (length < 0 || length > _maxMetadataBytes - _metadataBytes) {
      throw _corrupt('The container exceeds the metadata safety limit.');
    }
    _metadataBytes += length;
  }

  Future<Uint8List> metadata(int offset, int length) {
    chargeMetadata(length);
    return read(offset, length);
  }

  Future<Uint8List> read(int offset, int length) async {
    checkRange(offset, length);
    final bytes = await source.read(offset, length);
    if (bytes.length != length) {
      throw _corrupt('The container source returned a truncated record.');
    }
    return bytes;
  }
}

class _Payload {
  const _Payload(this.offset, this.length, {this.checksum});
  final int offset, length;
  final int? checksum;
}

class _XarPayload extends _Payload {
  const _XarPayload(
    super.offset,
    super.length,
    this.size,
    this.encoding,
    this.archivedChecksum,
    this.extractedChecksum,
  );
  final int size;
  final String encoding;
  final ({String style, String hex})? archivedChecksum, extractedChecksum;
}

({String name, bool unsafe}) _memberPath(
  String stored, {
  bool allowRoot = false,
}) {
  if (stored.isEmpty || utf8.encode(stored).length > _maxNameBytes) {
    throw _corrupt('Invalid or oversized archive member name.');
  }
  final path = stored.replaceAll('\\', '/');
  var unsafe =
      path.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path) ||
      path.codeUnits.any((c) => c < 32 || c == 127);
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      unsafe = true;
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      if (part.contains(':')) unsafe = true;
      parts.add(part);
    }
  }
  if (parts.isEmpty) {
    if (allowRoot && !unsafe) return (name: '/', unsafe: false);
    throw _corrupt('An archive member has an empty normalized name.');
  }
  return (name: parts.join('/'), unsafe: unsafe);
}

int _number(
  String value,
  int radix,
  String label, {
  bool emptyIsZero = false,
  bool allowNegative = false,
}) {
  if (value.isEmpty && emptyIsZero) return 0;
  final digits = radix == 16
      ? r'[0-9a-fA-F]+'
      : radix == 8
      ? r'[0-7]+'
      : r'[0-9]+';
  if (!RegExp('^${allowNegative ? '-?' : ''}$digits\$').hasMatch(value)) {
    throw _corrupt('Invalid $label.');
  }
  final result = int.tryParse(value, radix: radix);
  if (result == null || result.abs() > _maxSafeInteger) {
    throw _corrupt('Oversized $label.');
  }
  return result;
}

int _uint64(ByteData data, int offset) {
  final high = data.getUint32(offset), low = data.getUint32(offset + 4);
  if (high > 0x1fffff) {
    throw _corrupt('A container integer exceeds the safe range.');
  }
  return high * 4294967296 + low;
}

DateTime? _date(int seconds) => seconds.abs() <= 8640000000000
    ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
    : null;
int _align4(int value) => value + (4 - value % 4) % 4;
void _checkCount(int count) {
  if (count > _maxEntries) {
    throw _corrupt('The container has too many members.');
  }
}

ArchiveViewException _corrupt(String message) => ArchiveViewException(
  message,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': message},
);

XmlElement? _child(XmlElement parent, String name, {bool required = false}) {
  final children = parent.childElements
      .where((e) => e.name.qualified == name)
      .toList();
  if (children.length > 1 || required && children.isEmpty) {
    throw _corrupt('Missing or duplicate XAR $name metadata.');
  }
  return children.isEmpty ? null : children.single;
}

int _xmlNumber(XmlElement parent, String name) => _number(
  _child(parent, name, required: true)!.innerText.trim(),
  10,
  'XAR $name',
);

crypto.Hash _hash(String style) => switch (style.toLowerCase()) {
  'sha1' => crypto.sha1,
  'md5' => crypto.md5,
  'sha256' => crypto.sha256,
  'sha512' => crypto.sha512,
  _ => throw ArchiveViewException('This XAR checksum is unavailable: $style'),
};
({String style, String hex})? _checksum(XmlElement parent, String name) {
  final element = _child(parent, name);
  if (element == null || element.getAttribute('style') == 'none') return null;
  final style = element.getAttribute('style') ?? '';
  final hex = element.innerText.trim().toLowerCase();
  final length = _hash(style).convert(const <int>[]).bytes.length * 2;
  if (hex.length != length || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    throw _corrupt('Invalid XAR $name.');
  }
  return (style: style, hex: hex);
}

void _verifyHash(({String style, String hex})? expected, Uint8List bytes) {
  if (expected != null &&
      _hash(expected.style).convert(bytes).toString() != expected.hex) {
    throw _corrupt('XAR member checksum mismatch.');
  }
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
