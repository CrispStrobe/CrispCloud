// Bounded regular-file package writers. An inspection is a preservation
// contract, not merely confirmation that a reader accepted the container.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crypto/crypto.dart' as crypto;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'archive_types.dart';
import 'archive_compression_writer.dart';
import 'archive_viewer_service.dart' show openViewerArchive;
import 'archive_write_model.dart';

const _maxMetadata = 16 * 1024 * 1024;
const _maxToc = 8 * 1024 * 1024;
const _maxEntries = 200000;
const _maxOutput = 256 * 1024 * 1024;
const _identityKeys = {'package.sourcePath', 'package.order'};
const _arKeys = {'ar.uid', 'ar.gid', 'ar.nameStyle'};
const _cpioKeys = {
  'cpio.ino',
  'cpio.uid',
  'cpio.gid',
  'cpio.nlink',
  'cpio.devmajor',
  'cpio.devminor',
  'cpio.rdevmajor',
  'cpio.rdevminor',
  'cpio.variant',
  'cpio.storedPath',
};
const _cpioLegacyKeys = {
  'cpio.ino',
  'cpio.uid',
  'cpio.gid',
  'cpio.nlink',
  'cpio.dev',
  'cpio.rdev',
  'cpio.variant',
  'cpio.storedPath',
};

/// Explicit profiles for a newly created CPIO archive. Existing archives keep
/// the inspected profile (including each newc/CRC record), independently of
/// this creation preference. Binary means the modern regular-file layout,
/// never the historically ambiguous PWB interpretation.
enum ArchiveCpioFormat { newc, odc, binaryLittleEndian, binaryBigEndian }

/// Inspect the original structures that the generic member model omits.
/// Unsupported metadata returns a refusal, without changing any input bytes.
Future<ArchiveRewriteInspection> inspectPackageRewrite(
  Uint8List bytes,
  String kind,
  ViewerArchive archive,
) async {
  try {
    if (bytes.length > _maxOutput) _refuse('Package input exceeds 256 MiB.');
    if (archive.isClosed) _refuse('The package reader is closed.');
    final inspection = switch (kind) {
      'ar' || 'deb' => _inspectAr(bytes, kind, archive),
      'cpio' => _inspectCpio(bytes, archive),
      'xar' => _inspectXar(bytes, archive),
      _ => throw _Refusal('No package writer is available for $kind.'),
    };
    if (kind == 'deb') {
      await _validateDebian([
        for (final member in archive.members)
          ArchiveWriteEntry(
            path: member.name,
            isDirectory: !member.isFile,
            size: member.size,
            modified: member.modified,
            mode: member.posixMode,
            attributes: inspection.attributes[member.name] ?? const {},
            readChunks: () async* {
              yield await archive.readMember(member);
            },
          ),
      ], () {});
    }
    return inspection;
  } catch (error) {
    return ArchiveRewriteInspection(
      reason: error is _Refusal
          ? error.message
          : 'The package cannot be rewritten without losing metadata: $error',
      container: {'package.kind': kind},
    );
  }
}

/// Write to an unpublished destination. A failure may leave partial output;
/// the caller must verify the complete result before replacing its original.
Future<void> writePackageArchive(
  String kind,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  ArchiveCpioFormat cpioFormat = ArchiveCpioFormat.newc,
  int maxOutputBytes = _maxOutput,
  bool Function()? isCancelled,
}) async {
  if (maxOutputBytes <= 0 || maxOutputBytes > _maxOutput) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Package writing was cancelled.');
    }
  }

  check();
  if (source != null &&
      (!source.supported || source.container['package.kind'] != kind)) {
    throw ArchiveViewException(
      source.reason ?? 'The package inspection belongs to another format.',
    );
  }
  validateArchiveWriteEntries(
    entries,
    allowDirectories: kind != 'ar' && kind != 'deb',
  );
  final output = _Output(sink, maxOutputBytes, check);
  try {
    switch (kind) {
      case 'ar':
        await _writeAr(entries, output, source);
      case 'deb':
        if (source == null) {
          _refuse(
            'Creating Debian packages requires a package build workflow.',
          );
        }
        final required = source.container['requiredMembers'];
        if (required is! List ||
            required.length != entries.length ||
            List.generate(
              entries.length,
              (i) => entries[i].path,
            ).any((path) => !required.contains(path))) {
          _refuse(
            'Debian package members cannot be added, removed or renamed.',
          );
        }
        final ordered = [
          for (final path in required)
            entries.singleWhere((entry) => entry.path == path),
        ];
        final payloads = await _validateDebian(ordered, check);
        await _writeAr(payloads, output, source, debian: true);
      case 'cpio':
        await _writeCpio(entries, output, source, cpioFormat);
      case 'xar':
        await _writeXar(entries, output, source);
      default:
        _refuse('No package writer is available for $kind.');
    }
    check();
  } on _Refusal catch (error) {
    throw ArchiveViewException(error.message);
  }
}

ArchiveRewriteInspection _inspectAr(
  Uint8List bytes,
  String kind,
  ViewerArchive archive,
) {
  final input = _Input(bytes);
  if (input.text(0, 8) != '!<arch>\n' || archive.formatName != 'ar') {
    _refuse('Only ordinary AR containers can be rewritten.');
  }
  final attributes = <String, Map<String, Object?>>{};
  final names = <int, String>{};
  var at = 8, records = 0, memberIndex = 0;
  var style = 'common', sawNames = false;
  while (at < bytes.length) {
    if (++records > _maxEntries) _refuse('AR has too many records.');
    input.range(at, 60);
    if (input.text(at + 58, 2) != '`\n') _refuse('Invalid AR header.');
    String field(int offset, int width) =>
        input.text(at + offset, width).trim();
    var name = field(0, 16);
    final size = _number(field(48, 10), 10);
    final uid = _number(field(28, 6), 10, empty: true);
    final gid = _number(field(34, 6), 10, empty: true);
    final mode = _number(field(40, 8), 8, empty: true);
    if (mode & 0xf000 != 0 && mode & 0xf000 != 0x8000) {
      _refuse('AR special-file mode metadata cannot be preserved.');
    }
    final modified = _number(field(16, 12), 10, empty: true, negative: true);
    var offset = at + 60, contentSize = size;
    input.range(offset, size + (size & 1));
    if (size.isOdd && bytes[offset + size] != 10) {
      _refuse('Invalid AR padding.');
    }
    at = offset + size + (size & 1);
    if (name == '/' || name == '/SYM64/') {
      _refuse('AR symbol indexes require an object-library-aware rebuild.');
    }
    if (name == '//') {
      if (sawNames || size > _maxMetadata || kind == 'deb') {
        _refuse('This AR string-table layout cannot be preserved.');
      }
      sawNames = true;
      style = 'gnu';
      final table = input.slice(offset, size);
      var start = 0;
      for (var index = 0; index < table.length; index++) {
        if (table[index] != 10) continue;
        if (index == start && index == table.length - 1) {
          start = index + 1;
          continue;
        }
        final end = index > start && table[index - 1] == 47 ? index - 1 : index;
        if (end <= start) _refuse('Invalid AR long name.');
        names[start] = utf8.decode(table.sublist(start, end));
        start = index + 1;
      }
      if (start != table.length) _refuse('Unterminated AR string table.');
      continue;
    }
    var entryStyle = 'common';
    if (name.startsWith('#1/')) {
      if (kind == 'deb') _refuse('Debian packages require common AR names.');
      final length = _number(name.substring(3), 10);
      if (length <= 0 || length > size || length > 4096) {
        _refuse('Invalid BSD AR name.');
      }
      final stored = input.slice(offset, length);
      var end = stored.length;
      while (end > 0 && stored[end - 1] == 0) {
        end--;
      }
      name = utf8.decode(stored.sublist(0, end));
      offset += length;
      contentSize -= length;
      entryStyle = 'bsd';
      if (style == 'common') style = 'bsd';
    } else if (name.startsWith('/')) {
      final resolved = names[_number(name.substring(1), 10)];
      if (resolved == null) _refuse('Unresolved GNU AR long name.');
      name = resolved;
      entryStyle = 'gnu';
    } else if (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    if (_arReserved(name)) {
      _refuse('AR symbol indexes require an object-library-aware rebuild.');
    }
    _safePath(name, flat: true);
    _matchMember(
      archive,
      memberIndex,
      name,
      contentSize,
      false,
      mode,
      modified,
    );
    if (attributes.containsKey(name)) _refuse('Duplicate AR member names.');
    attributes[name] = {
      'package.sourcePath': name,
      'package.order': memberIndex++,
      'ar.uid': uid,
      'ar.gid': gid,
      'ar.nameStyle': entryStyle,
    };
  }
  if (memberIndex != archive.members.length) _refuse('AR member list changed.');
  final order = attributes.keys.toList(growable: false);
  if (kind == 'deb') _debianNames(order);
  return ArchiveRewriteInspection(
    container: {
      'package.kind': kind,
      'ar.nameStyle': style,
      if (kind == 'deb') 'requiredMembers': List.unmodifiable(order),
    },
    attributes: attributes,
  );
}

Future<void> _writeAr(
  List<ArchiveWriteEntry> entries,
  _Output output,
  ArchiveRewriteInspection? source, {
  bool debian = false,
}) async {
  final preferred = source?.container['ar.nameStyle'] ?? 'common';
  if (!const {'common', 'gnu', 'bsd'}.contains(preferred)) {
    _refuse('Unsupported AR filename representation.');
  }
  final nameTable = BytesBuilder(copy: false);
  final names = <String, ({String header, Uint8List inline})>{};
  var planned = 8;
  for (final entry in entries) {
    _attributes(entry, _arKeys);
    _safePath(entry.path, flat: true);
    if (_arReserved(entry.path)) _refuse('Reserved AR symbol-table name.');
    final raw = utf8.encode(entry.path);
    final short =
        raw.length <= 15 && raw.every((byte) => byte > 32 && byte < 127);
    var style = entry.attributes['ar.nameStyle'] ?? preferred;
    if (debian) style = 'common';
    if (!const {'common', 'gnu', 'bsd'}.contains(style)) {
      _refuse('Unsupported AR member name representation.');
    }
    String header;
    var inline = Uint8List(0);
    if (short && style != 'bsd') {
      header = '${entry.path}/';
    } else if (style == 'gnu') {
      header = '/${nameTable.length}';
      nameTable.add(raw);
      nameTable.add(const [47, 10]);
    } else {
      if (debian) _refuse('Debian AR member names must fit the common header.');
      inline = Uint8List.fromList(raw);
      header = '#1/${inline.length}';
    }
    names[entry.path] = (header: header, inline: inline);
    final packed = entry.size + inline.length;
    _arHeader(header, entry, packed);
    planned += 60 + packed + (packed & 1);
  }
  if (nameTable.length > _maxMetadata) {
    _refuse('AR names exceed metadata limits.');
  }
  final table = nameTable.takeBytes();
  if (table.isNotEmpty) planned += 60 + table.length + (table.length & 1);
  output.requireSpace(planned);
  await output.add(ascii.encode('!<arch>\n'));
  if (table.isNotEmpty) {
    await output.add(_arRawHeader('//', table.length, 0, 0, 0, 0));
    await output.add(table);
    if (table.length.isOdd) await output.add(const [10]);
  }
  for (final entry in entries) {
    final name = names[entry.path]!;
    final packed = entry.size + name.inline.length;
    await output.add(_arHeader(name.header, entry, packed));
    await output.add(name.inline);
    await for (final chunk in entry.openRead()) {
      await output.add(chunk);
    }
    if (packed.isOdd) await output.add(const [10]);
  }
}

Uint8List _arHeader(String name, ArchiveWriteEntry entry, int size) =>
    _arRawHeader(
      name,
      size,
      _seconds(entry.modified),
      _attributeInt(entry, 'ar.uid', 0, 999999),
      _attributeInt(entry, 'ar.gid', 0, 999999),
      entry.mode ?? 0x81a4,
    );

Uint8List _arRawHeader(
  String name,
  int size,
  int time,
  int uid,
  int gid,
  int mode,
) {
  String field(String value, int width) {
    if (value.length > width || value.codeUnits.any((byte) => byte > 127)) {
      _refuse('AR metadata does not fit its header field.');
    }
    return value.padRight(width);
  }

  if (size < 0 || uid < 0 || gid < 0 || mode < 0) {
    _refuse('Negative AR metadata.');
  }
  if (mode & 0xf000 != 0 && mode & 0xf000 != 0x8000) {
    _refuse('AR writers accept regular-file permission metadata only.');
  }
  return Uint8List.fromList(
    ascii.encode(
      '${field(name, 16)}${field('$time', 12)}${field('$uid', 6)}'
      '${field('$gid', 6)}${field(mode.toRadixString(8), 8)}${field('$size', 10)}`\n',
    ),
  );
}

bool _arReserved(String name) =>
    name == '/' ||
    name == '//' ||
    name == '/SYM64/' ||
    name == '__.LIBDEP' ||
    name.startsWith('__.SYMDEF');

ArchiveRewriteInspection _inspectCpio(Uint8List bytes, ViewerArchive archive) {
  if (archive.formatName != 'cpio') _refuse('The source is not CPIO.');
  final input = _Input(bytes);
  final initialVariant = _cpioMagic(input, 0);
  if (_isLegacyCpio(initialVariant)) {
    return _inspectLegacyCpio(input, archive, initialVariant);
  }
  final attributes = <String, Map<String, Object?>>{};
  var at = 0, index = 0, records = 0;
  String? variant;
  Map<String, Object?>? root;
  List<int>? trailerFields;
  String? trailerVariant;
  var foundTrailer = false;
  while (at < bytes.length) {
    if (++records > _maxEntries) _refuse('CPIO has too many records.');
    final magic = input.text(at, 6);
    if (magic != '070701' && magic != '070702') {
      _refuse('Only newc/CRC CPIO is writable.');
    }
    variant ??= magic;
    final values = [
      for (var i = 0; i < 13; i++) _number(input.text(at + 6 + i * 8, 8), 16),
    ];
    final size = values[6], nameSize = values[11], mode = values[1];
    if (nameSize < 1 || nameSize > 4097) {
      _refuse('CPIO name exceeds its limit.');
    }
    final nameBytes = input.slice(at + 110, nameSize);
    if (nameBytes.last != 0 || nameBytes.take(nameSize - 1).contains(0)) {
      _refuse('Invalid CPIO name.');
    }
    final stored = utf8.decode(nameBytes.sublist(0, nameSize - 1));
    final data = _align4(at + 110 + nameSize);
    final next = _align4(data + size);
    input.range(data, next - data);
    if (bytes.sublist(at + 110 + nameSize, data).any((byte) => byte != 0) ||
        bytes.sublist(data + size, next).any((byte) => byte != 0)) {
      _refuse('Nonzero CPIO alignment metadata cannot be preserved.');
    }
    at = next;
    if ((magic == '070701' || size == 0) && values[12] != 0) {
      _refuse('Invalid CPIO checksum.');
    }
    if (magic == '070702' && _sum(input.slice(data, size)) != values[12]) {
      _refuse('CPIO checksum mismatch.');
    }
    if (stored == 'TRAILER!!!') {
      if (size != 0) _refuse('Invalid CPIO trailer.');
      trailerFields = List.unmodifiable(values);
      trailerVariant = magic;
      foundTrailer = true;
      break;
    }
    final directory = mode & 0xf000 == 0x4000;
    if (!directory && mode & 0xf000 != 0x8000 ||
        !directory && values[4] != 1 ||
        directory && size != 0) {
      _refuse(
        'CPIO links and special records require a filesystem-aware writer.',
      );
    }
    final path = _cpioPath(stored, directory: directory);
    final attrs = <String, Object?>{
      'package.sourcePath': path,
      'package.order': index,
      'cpio.ino': values[0],
      'cpio.uid': values[2],
      'cpio.gid': values[3],
      'cpio.nlink': values[4],
      'cpio.devmajor': values[7],
      'cpio.devminor': values[8],
      'cpio.rdevmajor': values[9],
      'cpio.rdevminor': values[10],
      'cpio.variant': magic,
      'cpio.storedPath': stored,
    };
    if (path.isEmpty) {
      if (root != null) _refuse('Duplicate CPIO root directory.');
      root = {...attrs, 'mode': mode, 'modified': values[5]};
      continue;
    }
    _matchMember(archive, index++, path, size, directory, mode, values[5]);
    if (attributes.containsKey(path)) _refuse('Duplicate CPIO member path.');
    attributes[path] = attrs;
  }
  if (!foundTrailer ||
      index != archive.members.length ||
      bytes.length - at > 65536 ||
      bytes.sublist(at).any((byte) => byte != 0)) {
    _refuse('CPIO has missing or unsupported trailing records.');
  }
  return ArchiveRewriteInspection(
    container: {
      'package.kind': 'cpio',
      'cpio.variant': variant ?? '070701',
      'cpio.trailingPadding': bytes.length - at,
      'cpio.trailerFields': trailerFields,
      'cpio.trailerVariant': trailerVariant,
      if (root != null) 'cpio.root': Map<String, Object?>.unmodifiable(root),
    },
    attributes: attributes,
  );
}

Future<void> _writeCpio(
  List<ArchiveWriteEntry> entries,
  _Output output,
  ArchiveRewriteInspection? source,
  ArchiveCpioFormat format,
) async {
  final variant =
      source?.container['cpio.variant'] ??
      switch (format) {
        ArchiveCpioFormat.newc => '070701',
        ArchiveCpioFormat.odc => '070707',
        ArchiveCpioFormat.binaryLittleEndian => 'binary-le',
        ArchiveCpioFormat.binaryBigEndian => 'binary-be',
      };
  if (variant is! String) _refuse('Invalid CPIO profile metadata.');
  if (_isLegacyCpio(variant)) {
    await _writeLegacyCpio(entries, output, source, variant);
  } else if (variant == '070701' || variant == '070702') {
    await _writeNewcCpio(entries, output, source);
  } else {
    _refuse('Unsupported CPIO variant.');
  }
}

Future<void> _writeNewcCpio(
  List<ArchiveWriteEntry> entries,
  _Output output,
  ArchiveRewriteInspection? source,
) async {
  final variant = source?.container['cpio.variant'] ?? '070701';
  if (variant != '070701' && variant != '070702') {
    _refuse('Unsupported CPIO variant.');
  }
  final all = <ArchiveWriteEntry>[];
  final root = source?.container['cpio.root'];
  if (root != null) {
    if (root is! Map<String, Object?>) _refuse('Invalid CPIO root metadata.');
    all.add(
      ArchiveWriteEntry(
        path: '.',
        isDirectory: true,
        size: 0,
        mode: root['mode'] as int?,
        modified: DateTime.fromMillisecondsSinceEpoch(
          (root['modified'] as int) * 1000,
          isUtc: true,
        ),
        attributes: {
          for (final key in {..._identityKeys, ..._cpioKeys})
            if (root.containsKey(key)) key: root[key],
        },
      ),
    );
  }
  if (all.isEmpty) {
    all.addAll(entries);
  } else {
    final rootEntry = all.removeLast();
    all.addAll(entries);
    final position = rootEntry.attributes['package.order'];
    all.insert(
      position is int ? _cpioRootPosition(all, position) : 0,
      rootEntry,
    );
  }
  var planned = 0, nextInode = 1;
  for (final entry in entries) {
    _attributes(entry, _cpioKeys);
    if (entry.path == 'TRAILER!!!') _refuse('Reserved CPIO trailer name.');
    final inode = _attributeInt(entry, 'cpio.ino', 0, 0xffffffff);
    if (inode >= nextInode) nextInode = inode + 1;
  }
  final records =
      <
        ({ArchiveWriteEntry entry, String name, List<int> fields, String magic})
      >[];
  for (final entry in all) {
    output.check();
    final sourcePath = entry.attributes['package.sourcePath'];
    final stored = entry.attributes['cpio.storedPath'];
    final name = sourcePath == entry.path || entry.path == '.'
        ? stored is String
              ? stored
              : entry.path
        : entry.path;
    _cpioPath(name, directory: entry.isDirectory);
    final magic = entry.attributes['cpio.variant'] ?? variant;
    if (magic != '070701' && magic != '070702') {
      _refuse('Unsupported CPIO entry variant.');
    }
    final fields = [
      _attributeInt(entry, 'cpio.ino', nextInode++, 0xffffffff),
      _typedMode(entry),
      _attributeInt(entry, 'cpio.uid', 0, 0xffffffff),
      _attributeInt(entry, 'cpio.gid', 0, 0xffffffff),
      _attributeInt(entry, 'cpio.nlink', 1, 0xffffffff),
      _seconds(entry.modified),
      entry.size,
      _attributeInt(entry, 'cpio.devmajor', 0, 0xffffffff),
      _attributeInt(entry, 'cpio.devminor', 0, 0xffffffff),
      _attributeInt(entry, 'cpio.rdevmajor', 0, 0xffffffff),
      _attributeInt(entry, 'cpio.rdevminor', 0, 0xffffffff),
      utf8.encode(name).length + 1,
      0,
    ];
    if (!entry.isDirectory && fields[4] != 1) {
      _refuse('CPIO hard-link metadata is not writable.');
    }
    if (fields.any((value) => value < 0 || value > 0xffffffff)) {
      _refuse('CPIO metadata exceeds its 32-bit fields.');
    }
    planned += _align4(110 + fields[11]) + _align4(entry.size);
    records.add((
      entry: entry,
      name: name,
      fields: fields,
      magic: magic as String,
    ));
  }
  final padding = source?.container['cpio.trailingPadding'] ?? 0;
  if (padding is! int || padding < 0 || padding > 65536) {
    _refuse('Invalid CPIO trailing padding.');
  }
  planned += _align4(110 + 11) + padding;
  output.requireSpace(planned);
  for (final record in records) {
    final entry = record.entry;
    final fields = record.fields;
    int? expectedSum;
    if (record.magic == '070702' && !entry.isDirectory) {
      var sum = 0;
      await for (final chunk in entry.openRead()) {
        output.check();
        sum = (sum + _sum(chunk)) & 0xffffffff;
      }
      fields[12] = expectedSum = sum;
    }
    await output.add(_cpioHeader(record.magic, fields));
    await output.add([...utf8.encode(record.name), 0]);
    await output.pad4();
    var writtenSum = 0;
    await for (final chunk in entry.openRead()) {
      if (expectedSum != null) {
        writtenSum = (writtenSum + _sum(chunk)) & 0xffffffff;
      }
      await output.add(chunk);
    }
    if (expectedSum != null && writtenSum != expectedSum) {
      _refuse('The CPIO member changed while its checksum was written.');
    }
    await output.pad4();
  }
  final trailer =
      source?.container['cpio.trailerFields'] ??
      [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 0];
  final trailerMagic = source?.container['cpio.trailerVariant'] ?? variant;
  if (trailer is! List<int> ||
      trailer.length != 13 ||
      trailer.any((field) => field < 0 || field > 0xffffffff) ||
      trailer[6] != 0 ||
      trailer[11] != 11 ||
      trailer[12] != 0 ||
      trailerMagic != '070701' && trailerMagic != '070702') {
    _refuse('Invalid CPIO trailer metadata.');
  }
  await output.add(_cpioHeader(trailerMagic as String, trailer));
  await output.add([...ascii.encode('TRAILER!!!'), 0]);
  await output.pad4();
  await output.add(Uint8List(padding));
}

Uint8List _cpioHeader(String magic, List<int> fields) => Uint8List.fromList(
  ascii.encode(
    '$magic${fields.map((value) => value.toRadixString(16).padLeft(8, '0')).join()}',
  ),
);

// The legacy layouts use raw device identifiers rather than newc's separate
// major/minor fields. Keep their preservation model separate: converting those
// numbers would depend on the originating operating system's device encoding.
// Layout reference: libarchive's cpio(5), New Binary / Portable ASCII sections.
// https://github.com/libarchive/libarchive/blob/master/libarchive/cpio.5
String _cpioMagic(_Input input, int offset) {
  final bytes = input.slice(offset, 2);
  if (bytes[0] == 0xc7 && bytes[1] == 0x71) return 'binary-le';
  if (bytes[0] == 0x71 && bytes[1] == 0xc7) return 'binary-be';
  return input.text(offset, 6);
}

bool _isLegacyCpio(String variant) =>
    variant == '070707' || variant == 'binary-le' || variant == 'binary-be';

// The stored root position counts original non-root records. Deleting an
// earlier record must not move the root behind a surviving later member;
// additions have no original order and do not shift this anchor.
int _cpioRootPosition(List<ArchiveWriteEntry> entries, int originalPosition) {
  var position = 0;
  for (var index = 0; index < entries.length; index++) {
    final order = entries[index].attributes['package.order'];
    if (order is int && order < originalPosition) position = index + 1;
  }
  return position;
}

int _legacyCpioAlign(int value, String variant) =>
    variant == '070707' ? value : value + value % 2;

const _odcWidths = [6, 6, 6, 6, 6, 6, 6, 11, 6, 11];

// Canonical legacy fields: dev, ino, mode, uid, gid, nlink, rdev, mtime,
// namesize, filesize. This is the exact odc order, excluding its magic.
List<int> _legacyCpioFields(_Input input, int offset, String variant) {
  if (variant == '070707') {
    var at = offset + 6;
    return [
      for (final width in _odcWidths)
        (() {
          final value = _number(input.text(at, width), 8);
          at += width;
          return value;
        })(),
    ];
  }
  final data = ByteData.sublistView(input.slice(offset, 26));
  final endian = variant == 'binary-le' ? Endian.little : Endian.big;
  int word(int index) => data.getUint16(index * 2, endian);
  return [
    for (var index = 1; index <= 7; index++) word(index),
    word(8) * 65536 + word(9),
    word(10),
    word(11) * 65536 + word(12),
  ];
}

void _checkLegacyCpioFields(List<int> fields, String variant) {
  if (fields.length != 10) _refuse('Invalid legacy CPIO header metadata.');
  final odc = variant == '070707';
  for (var index = 0; index < fields.length; index++) {
    final maximum = index == 7
        ? (odc ? 0x1ffffffff : 0xffffffff)
        : index == 9
        ? (odc ? 0x1ffffffff : 0x7fffffff)
        : (odc ? 0x3ffff : 0xffff);
    if (fields[index] < 0 || fields[index] > maximum) {
      _refuse('CPIO metadata does not fit its $variant header fields.');
    }
  }
}

Uint8List _legacyCpioHeader(List<int> fields, String variant) {
  _checkLegacyCpioFields(fields, variant);
  if (variant == '070707') {
    return Uint8List.fromList(
      ascii.encode(
        '070707${List.generate(10, (index) => fields[index].toRadixString(8).padLeft(_odcWidths[index], '0')).join()}',
      ),
    );
  }
  final result = Uint8List(26);
  final data = ByteData.sublistView(result);
  final endian = variant == 'binary-le' ? Endian.little : Endian.big;
  final words = [
    0x71c7,
    ...fields.take(7),
    fields[7] ~/ 65536,
    fields[7] % 65536,
    fields[8],
    fields[9] ~/ 65536,
    fields[9] % 65536,
  ];
  for (var index = 0; index < words.length; index++) {
    data.setUint16(index * 2, words[index], endian);
  }
  return result;
}

ArchiveRewriteInspection _inspectLegacyCpio(
  _Input input,
  ViewerArchive archive,
  String variant,
) {
  final bytes = input.bytes;
  final attributes = <String, Map<String, Object?>>{};
  final identities = <String>{};
  final headerSize = variant == '070707' ? 76 : 26;
  var at = 0, index = 0, records = 0;
  Map<String, Object?>? root;
  List<int>? trailerFields;
  while (at < bytes.length) {
    if (++records > _maxEntries) _refuse('CPIO has too many records.');
    if (_cpioMagic(input, at) != variant) {
      _refuse('Mixed CPIO header profiles or byte orders cannot be rewritten.');
    }
    final fields = _legacyCpioFields(input, at, variant);
    _checkLegacyCpioFields(fields, variant);
    final size = fields[9], nameSize = fields[8], mode = fields[2];
    if (nameSize < 1 || nameSize > 4097) {
      _refuse('CPIO name exceeds its limit.');
    }
    final nameBytes = input.slice(at + headerSize, nameSize);
    if (nameBytes.last != 0 || nameBytes.take(nameSize - 1).contains(0)) {
      _refuse('Invalid CPIO name.');
    }
    final stored = utf8.decode(nameBytes.sublist(0, nameSize - 1));
    final nameEnd = at + headerSize + nameSize;
    final data = _legacyCpioAlign(nameEnd, variant);
    final next = _legacyCpioAlign(data + size, variant);
    input.range(data, next - data);
    if (input.slice(nameEnd, data - nameEnd).any((byte) => byte != 0) ||
        input.slice(data + size, next - data - size).any((byte) => byte != 0)) {
      _refuse('Nonzero CPIO alignment metadata cannot be preserved.');
    }
    at = next;
    if (stored == 'TRAILER!!!') {
      if (size != 0) _refuse('Invalid CPIO trailer.');
      trailerFields = List<int>.unmodifiable(fields);
      break;
    }
    final directory = mode & 0xf000 == 0x4000;
    if (mode > 0xffff ||
        !directory && mode & 0xf000 != 0x8000 ||
        !directory && fields[5] != 1 ||
        directory && (size != 0 || fields[5] == 0)) {
      _refuse('Legacy CPIO links and special records cannot be rewritten.');
    }
    if (!identities.add('${fields[0]}:${fields[1]}')) {
      _refuse('Repeated legacy CPIO device/inode identities are unsupported.');
    }
    final path = _cpioPath(stored, directory: directory);
    if (path == 'TRAILER!!!') _refuse('Reserved CPIO trailer name.');
    final attrs = <String, Object?>{
      'package.sourcePath': path,
      'package.order': index,
      'cpio.dev': fields[0],
      'cpio.ino': fields[1],
      'cpio.uid': fields[3],
      'cpio.gid': fields[4],
      'cpio.nlink': fields[5],
      'cpio.rdev': fields[6],
      'cpio.variant': variant,
      'cpio.storedPath': stored,
    };
    if (path.isEmpty) {
      if (root != null) _refuse('Duplicate CPIO root directory.');
      root = {...attrs, 'mode': mode, 'modified': fields[7]};
      continue;
    }
    _matchMember(archive, index++, path, size, directory, mode, fields[7]);
    if (attributes.containsKey(path)) _refuse('Duplicate CPIO member path.');
    attributes[path] = attrs;
  }
  if (trailerFields == null ||
      index != archive.members.length ||
      bytes.length - at > 65536 ||
      input.slice(at, bytes.length - at).any((byte) => byte != 0)) {
    _refuse('CPIO has missing or unsupported trailing records.');
  }
  return ArchiveRewriteInspection(
    container: {
      'package.kind': 'cpio',
      'cpio.variant': variant,
      'cpio.trailingPadding': bytes.length - at,
      'cpio.trailerFields': trailerFields,
      'cpio.trailerVariant': variant,
      if (root != null) 'cpio.root': Map<String, Object?>.unmodifiable(root),
    },
    attributes: attributes,
  );
}

Future<void> _writeLegacyCpio(
  List<ArchiveWriteEntry> entries,
  _Output output,
  ArchiveRewriteInspection? source,
  String variant,
) async {
  final all = List<ArchiveWriteEntry>.of(entries);
  final root = source?.container['cpio.root'];
  if (root != null) {
    if (root is! Map<String, Object?> ||
        root['mode'] is! int ||
        root['modified'] is! int ||
        root['package.order'] is! int ||
        (root['package.order'] as int) < 0 ||
        (root['package.order'] as int) > _maxEntries ||
        (root['modified'] as int) < 0 ||
        (root['modified'] as int) > 0x1ffffffff ||
        root.keys.any(
          (key) => !{
            ..._identityKeys,
            ..._cpioLegacyKeys,
            'mode',
            'modified',
          }.contains(key),
        )) {
      _refuse('Invalid legacy CPIO root metadata.');
    }
    all.insert(
      _cpioRootPosition(all, root['package.order'] as int),
      ArchiveWriteEntry(
        path: '.',
        isDirectory: true,
        size: 0,
        mode: root['mode'] as int,
        modified: DateTime.fromMillisecondsSinceEpoch(
          (root['modified'] as int) * 1000,
          isUtc: true,
        ),
        attributes: {
          for (final key in {..._identityKeys, ..._cpioLegacyKeys})
            if (root.containsKey(key)) key: root[key],
        },
      ),
    );
  }
  if (all.length + 1 > _maxEntries) _refuse('CPIO has too many records.');
  final maximum = variant == '070707' ? 0x3ffff : 0xffff;
  final usedIdentities = <String>{};
  for (final entry in all) {
    _attributes(entry, _cpioLegacyKeys);
    if (entry.path == 'TRAILER!!!') _refuse('Reserved CPIO trailer name.');
    final dev = _attributeInt(entry, 'cpio.dev', 0, maximum);
    if (entry.attributes.containsKey('cpio.ino')) {
      final inode = _attributeInt(entry, 'cpio.ino', 0, maximum);
      if (!usedIdentities.add('$dev:$inode')) {
        _refuse(
          'Repeated legacy CPIO device/inode identities are unsupported.',
        );
      }
    }
  }
  // Fill unused inode values instead of assigning max(existing)+1: a valid
  // binary source can already contain inode 65535 and still have free slots.
  final nextInode = <int, int>{};
  int allocateInode(int dev) {
    var inode = nextInode[dev] ?? 1;
    while (inode <= maximum && usedIdentities.contains('$dev:$inode')) {
      inode++;
    }
    if (inode > maximum) _refuse('No unused CPIO inode fits this profile.');
    usedIdentities.add('$dev:$inode');
    nextInode[dev] = inode + 1;
    return inode;
  }

  var planned = 0;
  final records =
      <({ArchiveWriteEntry entry, Uint8List header, List<int> name})>[];
  final headerSize = variant == '070707' ? 76 : 26;
  for (final entry in all) {
    output.check();
    final entryVariant = entry.attributes['cpio.variant'] ?? variant;
    if (entryVariant != variant) {
      _refuse('The CPIO entry profile differs from its container.');
    }
    final sourcePath = entry.attributes['package.sourcePath'];
    final stored = entry.attributes['cpio.storedPath'];
    if (stored != null && stored is! String) {
      _refuse('Invalid CPIO stored pathname metadata.');
    }
    final name =
        (sourcePath == entry.path || entry.path == '.') && stored is String
        ? stored
        : entry.path;
    final normalized = _cpioPath(name, directory: entry.isDirectory);
    if (normalized != (entry.path == '.' ? '' : entry.path)) {
      _refuse('The CPIO stored pathname does not match its member.');
    }
    final nameBytes = [...utf8.encode(name), 0];
    if (nameBytes.length > 4097) _refuse('CPIO name exceeds its limit.');
    final dev = _attributeInt(entry, 'cpio.dev', 0, maximum);
    final inode = entry.attributes.containsKey('cpio.ino')
        ? _attributeInt(entry, 'cpio.ino', 0, maximum)
        : allocateInode(dev);
    final links = _attributeInt(
      entry,
      'cpio.nlink',
      entry.isDirectory ? 2 : 1,
      maximum,
    );
    if (links == 0 || !entry.isDirectory && links != 1) {
      _refuse('Legacy CPIO hard-link metadata is not writable.');
    }
    final fields = [
      dev,
      inode,
      _typedMode(entry),
      _attributeInt(entry, 'cpio.uid', 0, maximum),
      _attributeInt(entry, 'cpio.gid', 0, maximum),
      links,
      _attributeInt(entry, 'cpio.rdev', 0, maximum),
      _seconds(entry.modified),
      nameBytes.length,
      entry.size,
    ];
    final header = _legacyCpioHeader(fields, variant);
    planned +=
        _legacyCpioAlign(headerSize + nameBytes.length, variant) +
        _legacyCpioAlign(entry.size, variant);
    records.add((entry: entry, header: header, name: nameBytes));
  }
  final padding = source?.container['cpio.trailingPadding'] ?? 0;
  final trailer =
      source?.container['cpio.trailerFields'] ??
      [0, 0, 0, 0, 0, 1, 0, 0, 11, 0];
  final trailerVariant = source?.container['cpio.trailerVariant'] ?? variant;
  if (padding is! int ||
      padding < 0 ||
      padding > 65536 ||
      trailer is! List<int> ||
      trailer.length != 10 ||
      trailer[8] != 11 ||
      trailer[9] != 0 ||
      trailerVariant != variant) {
    _refuse('Invalid legacy CPIO trailer metadata.');
  }
  final trailerHeader = _legacyCpioHeader(trailer, variant);
  planned += _legacyCpioAlign(headerSize + 11, variant) + padding;
  output.requireSpace(planned);
  Future<void> align() => output.add(
    Uint8List(_legacyCpioAlign(output.length, variant) - output.length),
  );
  for (final record in records) {
    await output.add(record.header);
    await output.add(record.name);
    await align();
    await for (final chunk in record.entry.openRead()) {
      await output.add(chunk);
    }
    await align();
  }
  await output.add(trailerHeader);
  await output.add([...ascii.encode('TRAILER!!!'), 0]);
  await align();
  await output.add(Uint8List(padding));
}

String _cpioPath(String stored, {required bool directory}) {
  var path = stored;
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (directory && (path.isEmpty || path == '.')) return '';
  if (directory && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  _safePath(path);
  return path;
}

const _xarFields = {
  'name',
  'type',
  'mode',
  'uid',
  'gid',
  'user',
  'group',
  'inode',
  'deviceno',
  'mtime',
  'atime',
  'ctime',
  'data',
  'file',
};
const _xarKeys = {
  'xar.id',
  'xar.uid',
  'xar.gid',
  'xar.user',
  'xar.group',
  'xar.inode',
  'xar.deviceno',
  'xar.mtime',
  'xar.atime',
  'xar.ctime',
  'xar.encoding',
  'xar.archivedChecksum',
  'xar.extractedChecksum',
  'xar.hasData',
  'xar.hasMode',
  'xar.xzCheck',
};
const _xarEncodings = {
  'application/octet-stream',
  'application/x-gzip',
  'application/zlib',
  'application/x-bzip2',
  'application/x-xz',
};

ArchiveRewriteInspection _inspectXar(Uint8List bytes, ViewerArchive archive) {
  final input = _Input(bytes);
  input.range(0, 28);
  final header = ByteData.sublistView(bytes, 0, 28);
  if (archive.formatName != 'xar' ||
      header.getUint32(0) != 0x78617221 ||
      header.getUint16(4) != 28 ||
      header.getUint16(6) != 1) {
    _refuse('Only XAR v1 with an ordinary header can be rewritten.');
  }
  final packedSize = _u64(header, 8), size = _u64(header, 16);
  if (size < 1 || size > _maxToc || packedSize < 1 || packedSize > _maxToc) {
    _refuse('XAR TOC exceeds its metadata limit.');
  }
  final style = switch (header.getUint32(24)) {
    0 => 'none',
    1 => 'sha1',
    2 => 'md5',
    3 => 'sha256',
    4 => 'sha512',
    _ => throw _Refusal('Unsupported XAR TOC checksum.'),
  };
  final packed = input.slice(28, packedSize);
  final raw = const codec.ZLibDecoder().decodeBytes(
    packed,
    verify: true,
    maxOutputSize: size,
  );
  if (raw.length != size) _refuse('Incorrect XAR TOC size.');
  final text = utf8.decode(raw);
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    _refuse('DTD/entity XAR metadata cannot be rewritten.');
  }
  var depth = 0, events = 0, elements = 0;
  for (final event in parseEvents(text)) {
    if (++events > 200000) _refuse('XAR TOC has too many events.');
    if (event is XmlStartElementEvent) {
      if (++elements > 100000 || ++depth > 128) {
        _refuse('XAR TOC is too complex.');
      }
      if (event.isSelfClosing) depth--;
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
  final document = XmlDocument.parse(text);
  if (document.children.any(
    (node) =>
        node is! XmlElement &&
        node is! XmlDeclaration &&
        !(node is XmlText && node.value.trim().isEmpty),
  )) {
    _refuse('Opaque XAR document metadata cannot be preserved.');
  }
  final root = document.rootElement;
  if (root.name.qualified != 'xar') _refuse('Invalid XAR root.');
  _xmlProfile(root, {'toc'});
  final toc = _child(root, 'toc', required: true)!;
  if (toc.descendantElements.any(
    (element) => element.name.local.toLowerCase().contains('signature'),
  )) {
    _refuse('Signed XAR/PKG/XIP containers require a signing-aware rebuild.');
  }
  _xmlProfile(toc, {'creation-time', 'checksum', 'file'}, repeated: {'file'});
  final creation = _value(toc, 'creation-time');
  if (creation != null && DateTime.tryParse(creation) == null) {
    _refuse('Invalid XAR creation time.');
  }
  final heap = 28 + packedSize;
  final spans = <(int, int)>[];
  final tocChecksum = _child(toc, 'checksum');
  if (style == 'none') {
    if (tocChecksum != null) {
      _xmlProfile(tocChecksum, {'offset', 'size'}, attributes: {'style'});
      if (tocChecksum.getAttribute('style') != 'none') {
        _refuse('Conflicting XAR TOC checksum.');
      }
      if ((_value(tocChecksum, 'size') ?? '0') != '0') {
        _refuse('Unknown XAR checksum payload.');
      }
    }
  } else {
    if (tocChecksum == null || tocChecksum.getAttribute('style') != style) {
      _refuse('Missing XAR TOC checksum.');
    }
    _xmlProfile(tocChecksum, {'offset', 'size'}, attributes: {'style'});
    final offset = _xmlInt(tocChecksum, 'offset'),
        length = _xmlInt(tocChecksum, 'size');
    final expected = _hash(style).convert(packed).bytes;
    if (length != expected.length ||
        !_same(input.slice(heap + offset, length), expected)) {
      _refuse('XAR TOC checksum mismatch.');
    }
    spans.add((offset, offset + length));
  }
  final attributes = <String, Map<String, Object?>>{};
  final identifiers = <int>{};
  final pending = <({XmlElement node, String parent, int depth})>[
    for (final file
        in toc.childElements
            .where((e) => e.name.qualified == 'file')
            .toList()
            .reversed)
      (node: file, parent: '', depth: 0),
  ];
  while (pending.isNotEmpty) {
    final item = pending.removeLast(), node = item.node;
    if (attributes.length >= 5000 || item.depth > 64) {
      _refuse('XAR file tree exceeds its limit.');
    }
    _xmlProfile(node, _xarFields, attributes: {'id'}, repeated: {'file'});
    final id = _number(node.getAttribute('id') ?? '', 10);
    if (id < 1 || !identifiers.add(id)) {
      _refuse('XAR file identifiers must be unique.');
    }
    final leaf = _value(node, 'name', required: true)!;
    _safePath(leaf, flat: true);
    final path = item.parent.isEmpty ? leaf : '${item.parent}/$leaf';
    _safePath(path);
    final type = _value(node, 'type', required: true);
    if (type != 'file' && type != 'directory') {
      _refuse('XAR links and special files cannot be rewritten.');
    }
    final directory = type == 'directory';
    final attrs = <String, Object?>{
      'package.sourcePath': path,
      'package.order': attributes.length,
      'xar.id': id,
    };
    for (final key in ['uid', 'gid', 'inode', 'deviceno']) {
      final value = _value(node, key);
      if (value != null) attrs['xar.$key'] = _number(value, 10);
    }
    for (final key in ['user', 'group', 'mtime', 'atime', 'ctime']) {
      final value = _value(node, key);
      if (value != null) {
        if (key.endsWith('time')) _validateXarTime(value);
        attrs['xar.$key'] = value;
      }
    }
    final modeText = _value(node, 'mode');
    final mode = modeText == null ? null : _number(modeText, 8);
    if (mode != null && mode > 0xfff) {
      _refuse('Unsupported XAR permission flags.');
    }
    attrs['xar.hasMode'] = mode != null;
    final data = _child(node, 'data');
    attrs['xar.hasData'] = data != null;
    var contentSize = 0;
    if (data != null) {
      if (directory) _refuse('XAR directories cannot contain file data.');
      _xmlProfile(data, {
        'size',
        'length',
        'offset',
        'encoding',
        'archived-checksum',
        'extracted-checksum',
      });
      contentSize = _xmlInt(data, 'size');
      final length = _xmlInt(data, 'length'), offset = _xmlInt(data, 'offset');
      input.range(heap + offset, length);
      if (length > 0) spans.add((offset, offset + length));
      final encoding = _child(data, 'encoding');
      if (encoding != null) _xmlProfile(encoding, {}, attributes: {'style'});
      final compression =
          encoding?.getAttribute('style') ?? 'application/octet-stream';
      if (!_xarEncodings.contains(compression)) {
        _refuse('This XAR compression is not writable: $compression');
      }
      attrs['xar.encoding'] = compression;
      if (compression == 'application/x-xz') {
        if (length < 12) _refuse('Truncated XAR XZ member.');
        final check = bytes[heap + offset + 7];
        if (!const [0, 1, 4, 10].contains(check)) {
          _refuse('Unsupported XAR XZ checksum.');
        }
        attrs['xar.xzCheck'] = check;
      }
      for (final key in ['archived-checksum', 'extracted-checksum']) {
        final checksum = _child(data, key);
        var algorithm = 'none';
        if (checksum != null) {
          if (checksum.childElements.isNotEmpty ||
              checksum.attributes.any(
                (attribute) => attribute.name.qualified != 'style',
              )) {
            _refuse('Unsupported XAR checksum metadata.');
          }
          algorithm = checksum.getAttribute('style') ?? '';
          if (algorithm != 'none') {
            final hash = _hash(algorithm),
                expected = checksum.innerText.trim().toLowerCase();
            if (expected.length !=
                    hash.convert(const <int>[]).bytes.length * 2 ||
                !RegExp(r'^[0-9a-f]+$').hasMatch(expected)) {
              _refuse('Invalid XAR member checksum.');
            }
            if (key == 'archived-checksum' &&
                hash.convert(input.slice(heap + offset, length)).toString() !=
                    expected) {
              _refuse('XAR archived member checksum mismatch.');
            }
          }
        }
        attrs[key == 'archived-checksum'
                ? 'xar.archivedChecksum'
                : 'xar.extractedChecksum'] =
            algorithm;
      }
    }
    if (attributes.length >= archive.members.length) {
      _refuse('XAR member list changed.');
    }
    final member = archive.members[attributes.length];
    if (member.name != path ||
        member.size != contentSize ||
        member.isFile == directory ||
        member.isSpecial ||
        member.pathEscapedRoot ||
        member.isEncrypted ||
        member.posixMode != mode ||
        member.modified !=
            DateTime.tryParse(attrs['xar.mtime'] as String? ?? '')) {
      _refuse('XAR member metadata does not match the source.');
    }
    if (attributes.containsKey(path)) _refuse('Duplicate XAR member path.');
    attributes[path] = attrs;
    final children = node.childElements
        .where((child) => child.name.qualified == 'file')
        .toList();
    if (!directory && children.isNotEmpty) {
      _refuse('XAR files cannot contain children.');
    }
    for (final child in children.reversed) {
      pending.add((node: child, parent: path, depth: item.depth + 1));
    }
  }
  if (attributes.length != archive.members.length) {
    _refuse('XAR member list changed.');
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  var covered = 0;
  (int, int)? previous;
  for (final span in spans) {
    if (span.$1 < covered && span != previous) {
      _refuse('Overlapping XAR heap structures cannot be preserved.');
    }
    if (span.$1 >= covered &&
        input
            .slice(heap + covered, span.$1 - covered)
            .any((byte) => byte != 0)) {
      _refuse('Opaque XAR heap metadata cannot be discarded.');
    }
    if (span.$2 > covered) covered = span.$2;
    previous = span;
  }
  if (input
      .slice(heap + covered, bytes.length - heap - covered)
      .any((byte) => byte != 0)) {
    _refuse('Opaque XAR trailing data cannot be discarded.');
  }
  return ArchiveRewriteInspection(
    container: {
      'package.kind': 'xar',
      'xar.tocChecksum': style,
      if (creation != null) 'xar.creationTime': creation,
    },
    attributes: attributes,
  );
}

Future<void> _writeXar(
  List<ArchiveWriteEntry> entries,
  _Output output,
  ArchiveRewriteInspection? source,
) async {
  if (entries.length > 5000) {
    _refuse('XAR writing is limited to 5,000 members.');
  }
  final style = source?.container['xar.tocChecksum'] ?? 'sha1';
  if (style is! String) _refuse('Invalid XAR TOC checksum metadata.');
  final tocHash = style == 'none' ? null : _hash(style);
  final hashSize = tocHash?.convert(const <int>[]).bytes.length ?? 0;
  final identifiers = <int>{};
  var nextId = 1;
  for (final entry in entries) {
    _attributes(entry, _xarKeys);
    if (entry.path.split('/').length > 65) {
      _refuse('XAR file tree exceeds its depth limit.');
    }
    final id = entry.attributes['xar.id'];
    if (id != null) {
      if (id is! int ||
          id < 1 ||
          id > 0x1fffffffffffff ||
          !identifiers.add(id)) {
        _refuse('XAR file identifiers must be unique.');
      }
      if (id >= nextId) nextId = id + 1;
    }
  }
  final staged = <String, _XarWriteMember>{};
  var heapSize = hashSize;
  for (final entry in entries) {
    output.check();
    final id = entry.attributes['xar.id'] as int? ?? nextId++;
    if (id > 0x1fffffffffffff) {
      _refuse('XAR file identifiers exceed their limit.');
    }
    final mode = entry.mode;
    if (mode != null && (mode < 0 || mode > 0xfff)) {
      _refuse('Unsupported XAR permission metadata.');
    }
    if (entry.modified != null) _xarTime(entry.modified!);
    for (final key in ['xar.uid', 'xar.gid', 'xar.inode', 'xar.deviceno']) {
      if (entry.attributes.containsKey(key)) {
        _attributeInt(entry, key, 0, 0x1fffffffffffff);
      }
    }
    for (final key in [
      'xar.user',
      'xar.group',
      'xar.mtime',
      'xar.atime',
      'xar.ctime',
    ]) {
      final value = entry.attributes[key];
      if (value != null &&
          (value is! String ||
              utf8.encode(value).length > 4096 ||
              RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(value))) {
        _refuse('Invalid $key metadata.');
      }
      if (value is String && key.endsWith('time')) _validateXarTime(value);
    }
    var data = Uint8List(0), encoding = 'application/octet-stream';
    String? archived, extracted;
    final archivedStyle = entry.attributes['xar.archivedChecksum'] ?? 'sha256';
    final extractedStyle =
        entry.attributes['xar.extractedChecksum'] ?? 'sha256';
    if (archivedStyle is! String || extractedStyle is! String) {
      _refuse('Invalid XAR member checksum style.');
    }
    if (archivedStyle != 'none') _hash(archivedStyle);
    if (extractedStyle != 'none') _hash(extractedStyle);
    if (!entry.isDirectory &&
        (entry.size > 0 || entry.attributes['xar.hasData'] != false)) {
      final content = await _readEntry(
        entry,
        output.check,
        maximum: output.limit,
      );
      final chosen = entry.attributes['xar.encoding'] ?? 'application/x-gzip';
      if (chosen is! String || !_xarEncodings.contains(chosen)) {
        _refuse('Unsupported XAR compression policy.');
      }
      encoding = chosen;
      data = switch (encoding) {
        'application/octet-stream' => content,
        'application/x-gzip' || 'application/zlib' => Uint8List.fromList(
          const codec.ZLibEncoder().encode(content),
        ),
        'application/x-bzip2' => codec.BZip2Encoder().encodeBytes(content),
        'application/x-xz' => encodeArchiveCompression(
          content,
          ArchiveCompressionKind.xz,
          maxOutputBytes: output.limit - heapSize,
          xzCheck: _attributeInt(entry, 'xar.xzCheck', 4, 10),
        ),
        _ => throw _Refusal('Unsupported XAR compression.'),
      };
      output.check();
      if (archivedStyle != 'none') {
        archived = _hash(archivedStyle).convert(data).toString();
      }
      if (extractedStyle != 'none') {
        extracted = _hash(extractedStyle).convert(content).toString();
      }
    }
    if (data.length > output.limit - heapSize) {
      _refuse('XAR heap exceeds the output limit.');
    }
    staged[entry.path] = _XarWriteMember(
      entry,
      id,
      heapSize,
      data,
      encoding,
      archivedStyle,
      archived,
      extractedStyle,
      extracted,
    );
    heapSize += data.length;
  }
  final children = <String, List<_XarWriteMember>>{};
  for (final record in staged.values) {
    final slash = record.entry.path.lastIndexOf('/');
    final parent = slash < 0 ? '' : record.entry.path.substring(0, slash);
    if (parent.isNotEmpty && staged[parent]?.entry.isDirectory != true) {
      _refuse('XAR nested members require an explicit parent directory.');
    }
    (children[parent] ??= []).add(record);
  }
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  void value(String name, String text) => builder.element(name, nest: text);
  void file(_XarWriteMember record) {
    final entry = record.entry, attrs = entry.attributes;
    builder.element(
      'file',
      attributes: {'id': '${record.id}'},
      nest: () {
        value('name', entry.path.split('/').last);
        value('type', entry.isDirectory ? 'directory' : 'file');
        if (entry.mode != null || attrs['xar.hasMode'] != false) {
          value(
            'mode',
            (entry.mode ?? (entry.isDirectory ? 0x1ed : 0x1a4))
                .toRadixString(8)
                .padLeft(4, '0'),
          );
        }
        for (final key in [
          'uid',
          'gid',
          'user',
          'group',
          'inode',
          'deviceno',
          'atime',
          'ctime',
        ]) {
          if (attrs['xar.$key'] case final Object value_) value(key, '$value_');
        }
        final originalTime = attrs['xar.mtime'] as String?;
        if (entry.modified != null) {
          value(
            'mtime',
            originalTime != null &&
                    DateTime.tryParse(originalTime)
                            ?.isAtSameMomentAs(entry.modified!) ==
                        true
                ? originalTime
                : _xarTime(entry.modified!),
          );
        } else if (originalTime != null) {
          value('mtime', originalTime);
        }
        if (!entry.isDirectory &&
            (entry.size > 0 || attrs['xar.hasData'] != false)) {
          builder.element(
            'data',
            nest: () {
              value('size', '${entry.size}');
              value('length', '${record.data.length}');
              value('offset', '${record.offset}');
              builder.element(
                'encoding',
                attributes: {'style': record.encoding},
              );
              if (record.archived != null) {
                builder.element(
                  'archived-checksum',
                  attributes: {'style': record.archivedStyle},
                  nest: record.archived,
                );
              }
              if (record.extracted != null) {
                builder.element(
                  'extracted-checksum',
                  attributes: {'style': record.extractedStyle},
                  nest: record.extracted,
                );
              }
            },
          );
        }
        for (final child in children[entry.path] ?? const <_XarWriteMember>[]) {
          file(child);
        }
      },
    );
  }

  builder.element(
    'xar',
    nest: () => builder.element(
      'toc',
      nest: () {
        final created = source?.container['xar.creationTime'];
        if (created != null) {
          if (created is! String || DateTime.tryParse(created) == null) {
            _refuse('Invalid XAR creation metadata.');
          }
          value('creation-time', created);
        }
        if (source == null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          value(
            'creation-time',
            _xarTime(
              DateTime.fromMillisecondsSinceEpoch(
                now ~/ 1000 * 1000,
                isUtc: true,
              ),
            ),
          );
        }
        if (tocHash != null) {
          builder.element(
            'checksum',
            attributes: {'style': style},
            nest: () {
              value('offset', '0');
              value('size', '$hashSize');
            },
          );
        }
        for (final record in children[''] ?? const <_XarWriteMember>[]) {
          file(record);
        }
      },
    ),
  );
  final raw = utf8.encode(builder.buildDocument().toXmlString());
  if (raw.length > _maxToc) _refuse('XAR TOC exceeds its metadata limit.');
  final packed = const codec.ZLibEncoder().encode(raw);
  if (packed.length > _maxToc) _refuse('Compressed XAR TOC exceeds its limit.');
  output.requireSpace(28 + packed.length + heapSize);
  final header = ByteData(28)
    ..setUint32(0, 0x78617221)
    ..setUint16(4, 28)
    ..setUint16(6, 1)
    ..setUint64(8, packed.length)
    ..setUint64(16, raw.length)
    ..setUint32(
      24,
      {'none': 0, 'sha1': 1, 'md5': 2, 'sha256': 3, 'sha512': 4}[style]!,
    );
  await output.add(header.buffer.asUint8List());
  await output.add(packed);
  if (tocHash != null) await output.add(tocHash.convert(packed).bytes);
  for (final record in staged.values) {
    await output.add(record.data);
  }
}

class _XarWriteMember {
  _XarWriteMember(
    this.entry,
    this.id,
    this.offset,
    this.data,
    this.encoding,
    this.archivedStyle,
    this.archived,
    this.extractedStyle,
    this.extracted,
  );
  final ArchiveWriteEntry entry;
  final int id, offset;
  final Uint8List data;
  final String encoding, archivedStyle, extractedStyle;
  final String? archived, extracted;
}

void _xmlProfile(
  XmlElement node,
  Set<String> children, {
  Set<String> attributes = const {},
  Set<String> repeated = const {},
}) {
  if (node.attributes.any(
    (attr) => !attributes.contains(attr.name.qualified),
  )) {
    _refuse('Unsupported XAR ${node.name} attribute.');
  }
  final seen = <String>{};
  for (final child in node.children) {
    if (child is XmlText && child.value.trim().isEmpty) continue;
    if (child is! XmlElement || !children.contains(child.name.qualified)) {
      _refuse('Unsupported XAR metadata in ${node.name}.');
    }
    if (!seen.add(child.name.qualified) &&
        !repeated.contains(child.name.qualified)) {
      _refuse('Duplicate XAR metadata field.');
    }
  }
}

XmlElement? _child(XmlElement node, String key, {bool required = false}) {
  final found = node.childElements
      .where((child) => child.name.qualified == key)
      .toList();
  if (found.length > 1 || required && found.isEmpty) {
    _refuse('Missing or repeated XAR $key.');
  }
  return found.isEmpty ? null : found.single;
}

String? _value(XmlElement node, String key, {bool required = false}) {
  final child = _child(node, key, required: required);
  if (child == null) return null;
  if (child.attributes.isNotEmpty ||
      child.children.any((node) => node is! XmlText)) {
    _refuse('Unsupported XAR $key metadata.');
  }
  final value = child.innerText;
  if (utf8.encode(value).length > 4096 ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(value)) {
    _refuse('XAR scalar metadata exceeds its limit.');
  }
  return value;
}

int _xmlInt(XmlElement node, String key) =>
    _number(_value(node, key, required: true)!.trim(), 10);
int _u64(ByteData data, int at) {
  final high = data.getUint32(at), low = data.getUint32(at + 4);
  if (high > 0x1fffff) _refuse('Package size exceeds safe integer limits.');
  return high * 4294967296 + low;
}

crypto.Hash _hash(String style) => switch (style) {
  'sha1' => crypto.sha1,
  'md5' => crypto.md5,
  'sha256' => crypto.sha256,
  'sha512' => crypto.sha512,
  _ => throw _Refusal('Unsupported XAR checksum algorithm: $style'),
};
bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<Uint8List> _readEntry(
  ArchiveWriteEntry entry,
  void Function() check, {
  int maximum = kArchiveReadLimit,
}) async {
  if (entry.size > kArchiveReadLimit || entry.size > maximum) {
    _refuse('The package member exceeds the buffered writer limit.');
  }
  final data = BytesBuilder(copy: false);
  await for (final chunk in entry.openRead()) {
    check();
    data.add(chunk);
  }
  check();
  return data.takeBytes();
}

void _debianNames(List<String> names) {
  if (names.length != 3 ||
      names[0] != 'debian-binary' ||
      !RegExp(r'^control\.tar(?:\.(?:gz|xz|zst))?$').hasMatch(names[1]) ||
      !RegExp(r'^data\.tar(?:\.(?:gz|xz|zst|bz2))?$').hasMatch(names[2])) {
    _refuse(
      'This Debian profile requires debian-binary, control.tar and data.tar in their required order.',
    );
  }
}

Future<List<ArchiveWriteEntry>> _validateDebian(
  List<ArchiveWriteEntry> entries,
  void Function() check,
) async {
  _debianNames(entries.map((entry) => entry.path).toList());
  if (entries.any((entry) => entry.isDirectory)) {
    _refuse('Debian AR members must be regular files.');
  }
  final payloads = <Uint8List>[];
  for (final entry in entries) {
    payloads.add(await _readEntry(entry, check));
  }
  for (var i = 1; i < 3; i++) {
    final expected = entries[i].path.endsWith('.gz')
        ? ArchiveCompressionKind.gzip
        : entries[i].path.endsWith('.xz')
        ? ArchiveCompressionKind.xz
        : entries[i].path.endsWith('.zst')
        ? ArchiveCompressionKind.zstd
        : entries[i].path.endsWith('.bz2')
        ? ArchiveCompressionKind.bzip2
        : null;
    if (archiveCompressionForBytes(payloads[i]) != expected) {
      _refuse('Debian payload compression does not match its member name.');
    }
  }
  if (!_same(payloads[0], const [50, 46, 48, 10])) {
    _refuse('Only the Debian 2.0 wrapper is writable.');
  }
  final control = await openViewerArchive(payloads[1], name: entries[1].path);
  ViewerArchive? data;
  try {
    data = await openViewerArchive(payloads[2], name: entries[2].path);
    if (control.formatName != 'tar' || data.formatName != 'tar') {
      _refuse('Debian control and data members must contain TAR archives.');
    }
    final controlFiles = <String, ViewerArchiveMember>{};
    for (final member in control.members) {
      check();
      if (!member.isFile && member.name == '/' && !member.isSpecial) continue;
      if (!member.isFile ||
          member.isSpecial ||
          member.pathEscapedRoot ||
          member.isEncrypted) {
        _refuse('Unsupported Debian control entry.');
      }
      _safePath(member.name, flat: true);
      if (controlFiles.containsKey(member.name)) {
        _refuse('Duplicate Debian control entry.');
      }
      controlFiles[member.name] = member;
    }
    final manifest = controlFiles['control'];
    if (manifest == null || manifest.size > 1024 * 1024) {
      _refuse('A bounded Debian control file is required.');
    }
    final controlText = utf8.decode(await control.readMember(manifest));
    final requiredFields = {
      'package',
      'version',
      'architecture',
      'maintainer',
      'description',
    };
    final seen = <String>{};
    for (final line in const LineSplitter().convert(controlText)) {
      if (line.startsWith(' ') || line.startsWith('\t')) continue;
      if (line.trim().isEmpty) continue;
      final split = line.indexOf(':');
      if (split < 1 || line.substring(split + 1).trim().isEmpty) {
        _refuse('Invalid Debian control field.');
      }
      final key = line.substring(0, split).toLowerCase();
      if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(key) || !seen.add(key)) {
        _refuse('Invalid or duplicate Debian control field.');
      }
    }
    if (!seen.containsAll(requiredFields)) {
      _refuse('Debian control metadata is incomplete.');
    }
    final digests = <String, String>{};
    final checksumFile = controlFiles['md5sums'];
    if (checksumFile != null) {
      if (checksumFile.size > _maxMetadata) {
        _refuse('Debian md5sums exceeds its metadata limit.');
      }
      final checksums = utf8.decode(await control.readMember(checksumFile));
      for (final line in const LineSplitter().convert(checksums)) {
        final match = RegExp(r'^([0-9a-fA-F]{32})  (.+)$').firstMatch(line);
        if (match == null) _refuse('Malformed Debian md5sums entry.');
        final path = match.group(2)!;
        _safePath(path);
        if (digests.containsKey(path)) {
          _refuse('Duplicate Debian md5sums entry.');
        }
        digests[path] = match.group(1)!.toLowerCase();
      }
    }
    final paths = <String>{};
    for (final member in data.members) {
      check();
      if (!member.isFile && member.name == '/' && !member.isSpecial) continue;
      if (member.pathEscapedRoot || member.isEncrypted || member.isSpecial) {
        _refuse(
          'This Debian writer profile excludes links and special filesystem records.',
        );
      }
      _safePath(member.name);
      if (!paths.add(member.name)) _refuse('Duplicate Debian data member.');
      if (member.isFile) {
        final bytes = await data.readMember(member);
        final expected = digests.remove(member.name);
        if (expected != null &&
            crypto.md5.convert(bytes).toString() != expected) {
          _refuse(
            'Debian md5sums no longer matches ${member.name}; rebuild its control payload explicitly.',
          );
        }
      }
    }
    if (digests.isNotEmpty) {
      _refuse('Debian md5sums references a removed or non-file payload.');
    }
    // Validate every control payload, including scripts not referenced above.
    for (final member in controlFiles.values) {
      check();
      await control.readMember(member);
    }
  } finally {
    await control.close();
    await data?.close();
  }
  return [
    for (var i = 0; i < entries.length; i++)
      ArchiveWriteEntry(
        path: entries[i].path,
        isDirectory: false,
        size: payloads[i].length,
        modified: entries[i].modified,
        mode: entries[i].mode,
        attributes: entries[i].attributes,
        readChunks: () => Stream<List<int>>.value(payloads[i]),
      ),
  ];
}

class _Refusal implements Exception {
  _Refusal(this.message);
  final String message;
  @override
  String toString() => message;
}

Never _refuse(String message) => throw _Refusal(message);

class _Input {
  _Input(this.bytes);
  final Uint8List bytes;
  void range(int offset, int count) {
    if (offset < 0 ||
        count < 0 ||
        offset > bytes.length ||
        count > bytes.length - offset) {
      _refuse('A package record is truncated.');
    }
  }

  Uint8List slice(int offset, int count) {
    range(offset, count);
    return Uint8List.sublistView(bytes, offset, offset + count);
  }

  String text(int offset, int count) => ascii.decode(slice(offset, count));
}

class _Output {
  _Output(this.sink, this.limit, this.check);
  final Future<void> Function(List<int>) sink;
  final int limit;
  final void Function() check;
  var length = 0;
  void requireSpace(int count) {
    check();
    if (count < 0 || count > limit - length) {
      _refuse('The package exceeds its output limit.');
    }
  }

  Future<void> add(List<int> bytes) async {
    requireSpace(bytes.length);
    if (bytes.isEmpty) return;
    await sink(bytes);
    length += bytes.length;
    check();
  }

  Future<void> pad4() => add(Uint8List((_align4(length) - length)));
}

int _align4(int value) => value + ((4 - value % 4) % 4);
int _sum(List<int> bytes) =>
    bytes.fold(0, (sum, byte) => (sum + byte) & 0xffffffff);
int _number(
  String text,
  int radix, {
  bool empty = false,
  bool negative = false,
}) {
  if (empty && text.isEmpty) return 0;
  final pattern = radix == 16
      ? r'[0-9a-fA-F]+'
      : radix == 8
      ? r'[0-7]+'
      : r'[0-9]+';
  if (!RegExp('^${negative ? '-?' : ''}$pattern\$').hasMatch(text)) {
    _refuse('Invalid package numeric metadata.');
  }
  final value = int.tryParse(text, radix: radix);
  if (value == null || value.abs() > 0x1fffffffffffff) {
    _refuse('Package numeric metadata is out of range.');
  }
  return value;
}

int _attributeInt(
  ArchiveWriteEntry entry,
  String key,
  int fallback,
  int maximum,
) {
  final value = entry.attributes[key] ?? fallback;
  if (value is! int || value < 0 || value > maximum) {
    _refuse('Unsupported $key metadata for ${entry.path}.');
  }
  return value;
}

int _seconds(DateTime? date) {
  if (date == null) return 0;
  if (date.microsecondsSinceEpoch % Duration.microsecondsPerSecond != 0) {
    _refuse('This package format cannot preserve fractional timestamps.');
  }
  return date.microsecondsSinceEpoch ~/ Duration.microsecondsPerSecond;
}

// The portable XAR profile uses the whole-second UTC text understood by
// libarchive. Dart's default `.000Z` spelling is not accepted by its
// timestamp parser; a fractional source timestamp must remain read-only.
String _xarTime(DateTime date) {
  _seconds(date);
  final utc = date.toUtc();
  if (utc.year < 1900 || utc.year > 9999) {
    _refuse('Unsupported XAR timestamp metadata.');
  }
  return utc.toIso8601String().replaceFirst('.000Z', 'Z');
}

void _validateXarTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _xarTime(parsed) != value) {
    _refuse('Unsupported XAR timestamp metadata.');
  }
}

int _typedMode(ArchiveWriteEntry entry) {
  final type = entry.isDirectory ? 0x4000 : 0x8000;
  final mode = entry.mode ?? (entry.isDirectory ? 0x1ed : 0x1a4);
  if (mode < 0 ||
      mode > 0xffff ||
      mode & 0xf000 != 0 && mode & 0xf000 != type) {
    _refuse('The member mode does not match its regular-file/directory type.');
  }
  return type | (mode & 0xfff);
}

void _attributes(ArchiveWriteEntry entry, Set<String> supported) {
  for (final key in entry.attributes.keys) {
    if (!_identityKeys.contains(key) && !supported.contains(key)) {
      _refuse('Unsupported package member metadata: $key.');
    }
  }
}

void _safePath(String path, {bool flat = false}) {
  final parts = path.split('/');
  if (path.isEmpty ||
      utf8.encode(path).length > 4096 ||
      path.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f:]').hasMatch(path) ||
      parts.length > 200 ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
      flat && parts.length != 1) {
    _refuse('The package path cannot be preserved safely: $path');
  }
}

void _matchMember(
  ViewerArchive archive,
  int index,
  String path,
  int size,
  bool directory,
  int mode,
  int modified,
) {
  if (index >= archive.members.length) {
    _refuse('The package member list changed.');
  }
  final member = archive.members[index];
  if (member.name != path ||
      member.size != size ||
      member.isFile == directory ||
      member.isSpecial ||
      member.pathEscapedRoot ||
      member.isEncrypted ||
      member.posixMode != mode ||
      member.modified == null ||
      member.modified!.millisecondsSinceEpoch != modified * 1000) {
    _refuse('The package metadata does not match its inspected member: $path');
  }
}
