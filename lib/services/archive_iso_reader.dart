import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

/// Read-only ISO 9660 images (2048-byte sectors), including Joliet and the
/// ordinary Rock Ridge name/POSIX extensions. File data is read on demand.
///
/// Based on ECMA-119 sections 7–9 and Annex C. This does not mount the image,
/// execute boot records, follow symbolic links, or implement UDF. Relocated,
/// interleaved and multi-extent files are refused rather than misrepresented.
/// The returned archive owns [source], including when opening fails.
Future<ViewerArchive> openIsoArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = 100000,
  int maxDirectoryBytes = 32 * 1024 * 1024,
  int maxDepth = 64,
}) async {
  try {
    if (maxMemberBytes <= 0 ||
        maxEntries <= 0 ||
        maxDirectoryBytes <= 0 ||
        maxDepth <= 0) {
      throw ArgumentError('ISO reader limits must be positive.');
    }
    return await _IsoReader(
      source,
      maxMemberBytes,
      maxEntries,
      maxDirectoryBytes,
      maxDepth,
    ).open();
  } catch (error) {
    await source.close();
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw ArchiveViewException('Could not read the ISO image: $error');
  }
}

class _IsoReader {
  _IsoReader(
    this.source,
    this.maxMemberBytes,
    this.maxEntries,
    this.maxDirectoryBytes,
    this.maxDepth,
  );

  static const sectorSize = 2048;
  final koni.ByteSource source;
  final int maxMemberBytes;
  final int maxEntries;
  final int maxDirectoryBytes;
  final int maxDepth;
  int _volumeBytes = 0;
  int _directoryBytes = 0;
  int _continuationBytes = 0;
  int _nameBytes = 0;
  int _descriptorEnd = 0;
  int? _suspSkip;
  bool _joliet = false;
  final _members = <ViewerArchiveMember>[];
  final _extents = <_IsoRecord>[];
  final _names = <String>{};
  final _directories = <int>{};

  Never _bad(String detail) =>
      throw ArchiveViewException('Invalid ISO image: $detail');
  Never _unsupported(String detail) =>
      throw ArchiveViewException('Unsupported ISO image: $detail');

  Future<Uint8List> _read(int offset, int length) async {
    final bound = _volumeBytes == 0 ? source.length : _volumeBytes;
    if (offset < 0 || length < 0 || offset > bound || length > bound - offset) {
      _bad('An extent leaves the image.');
    }
    final bytes = await source.read(offset, length);
    if (bytes.length != length) _bad('The image is truncated.');
    return bytes;
  }

  int _both16(Uint8List bytes, int at) {
    final data = ByteData.sublistView(bytes);
    final value = data.getUint16(at, Endian.little);
    if (value != data.getUint16(at + 2, Endian.big)) {
      _bad('The two byte orders disagree.');
    }
    return value;
  }

  int _both32(Uint8List bytes, int at) {
    final data = ByteData.sublistView(bytes);
    final value = data.getUint32(at, Endian.little);
    if (value != data.getUint32(at + 4, Endian.big)) {
      _bad('The two byte orders disagree.');
    }
    return value;
  }

  Future<ViewerArchive> open() async {
    Uint8List? primary;
    Uint8List? joliet;
    var terminated = false;
    // Descriptor sequences are tiny on ordinary media; an explicit ceiling
    // also bounds adversarial chains of boot/supplementary descriptors.
    for (var sector = 16; sector < 16 + 128; sector++) {
      final data = await _read(sector * sectorSize, sectorSize);
      if (ascii.decode(data.sublist(1, 6), allowInvalid: true) != 'CD001' ||
          data[6] != 1) {
        _bad(
          'No valid ISO 9660 volume descriptor. UDF-only images are unsupported.',
        );
      }
      if (data[0] == 1) primary ??= data;
      if (data[0] == 2 &&
          data[7] & 1 == 0 &&
          data[88] == 0x25 &&
          data[89] == 0x2f &&
          const [0x40, 0x43, 0x45].contains(data[90])) {
        joliet = data;
      }
      if (data[0] == 255) {
        terminated = true;
        _descriptorEnd = (sector + 1) * sectorSize;
        break;
      }
    }
    if (!terminated || primary == null) {
      _bad('The primary descriptor or descriptor terminator is missing.');
    }
    final primaryRoot = _volume(primary);
    // Rock Ridge carries types and POSIX names that Joliet cannot express.
    // Prefer that hierarchy when SUSP is explicitly advertised by its root.
    final first = await _read(primaryRoot.offset, sectorSize);
    final self = _record(first, 0);
    if (!self.self ||
        !self.directory ||
        self.offset != primaryRoot.offset ||
        self.size != primaryRoot.size) {
      _bad('The root directory has an invalid self record.');
    }
    _suspSkip = _detectSusp(self.systemUse);
    var root = primaryRoot;
    if (_suspSkip == null && joliet != null) {
      _joliet = true;
      root = _volume(joliet);
    }
    await _directory(root, '', 0);
    return ViewerArchive.reader(
      formatName: 'iso',
      members: List<ViewerArchiveMember>.unmodifiable(_members),
      read: (member, requested) async {
        if (member.isSpecial || !member.isFile) {
          throw const ArchiveViewException(
            'ISO links and special entries cannot be read as files.',
          );
        }
        final limit = requested < maxMemberBytes ? requested : maxMemberBytes;
        if (member.size > limit) {
          throw ArchiveViewException(
            'ISO entry exceeds the $limit-byte read limit.',
          );
        }
        return _read(_extents[member.index].offset, member.size);
      },
      close: source.close,
    );
  }

  _IsoRecord _volume(Uint8List descriptor) {
    if (_both16(descriptor, 128) != sectorSize) {
      _unsupported('Only 2048-byte logical blocks are supported.');
    }
    if (_both16(descriptor, 120) != 1 || _both16(descriptor, 124) != 1) {
      _unsupported('Multi-volume images are not supported.');
    }
    if (descriptor[881] != 1) _bad('Invalid file structure version.');
    final bytes = _both32(descriptor, 80) * sectorSize;
    if (bytes < _descriptorEnd || bytes > source.length) {
      _bad('The declared volume size leaves the image.');
    }
    if (_volumeBytes != 0 && _volumeBytes != bytes) {
      _bad('Primary and supplementary volume sizes disagree.');
    }
    _volumeBytes = bytes;
    final root = _record(descriptor, 156);
    if (!root.directory || !root.self || root.size < sectorSize) {
      _bad('Invalid root directory.');
    }
    return root;
  }

  _IsoRecord _record(Uint8List data, int at) {
    final length = data[at];
    if (length < 34 ||
        length.isOdd ||
        at + length > data.length ||
        (at % sectorSize) + length > sectorSize) {
      _bad('A directory record is truncated or crosses a sector.');
    }
    final raw = Uint8List.sublistView(data, at, at + length);
    final nameLength = raw[32];
    final nameEnd = 33 + nameLength;
    final systemAt = nameEnd + (nameLength.isEven ? 1 : 0);
    if (nameLength == 0 ||
        systemAt > raw.length ||
        (nameLength.isEven && raw[nameEnd] != 0)) {
      _bad('Invalid directory identifier length or padding.');
    }
    if (raw[25] & 0x80 != 0) {
      _unsupported('Multi-extent files are not supported.');
    }
    if (raw[26] != 0 || raw[27] != 0) {
      _unsupported('Interleaved files are not supported.');
    }
    if (raw[25] & 0x64 != 0) {
      _unsupported(
        'Associated files or reserved directory flags are not supported.',
      );
    }
    if (_both16(raw, 28) != 1) {
      _unsupported('An entry references another volume.');
    }
    final extent = _both32(raw, 2);
    final size = _both32(raw, 10);
    final offset = (extent + raw[1]) * sectorSize;
    if (offset > _volumeBytes ||
        size > _volumeBytes - offset ||
        (size > 0 && offset < _descriptorEnd)) {
      _bad('A member extent leaves the volume.');
    }
    final directory = raw[25] & 2 != 0;
    if (directory && (size == 0 || size % sectorSize != 0)) {
      _bad('A directory length is not a positive whole number of sectors.');
    }
    final self = nameLength == 1 && raw[33] == 0;
    final parent = nameLength == 1 && raw[33] == 1;
    if ((self || parent) && !directory) {
      _bad('A special identifier is not a directory.');
    }
    final identifier = Uint8List.sublistView(raw, 33, nameEnd);
    return _IsoRecord(
      offset: offset,
      size: size,
      directory: directory,
      self: self,
      parent: parent,
      identifier: identifier,
      modified: _date(Uint8List.sublistView(raw, 18, 25)),
      systemUse: Uint8List.sublistView(raw, systemAt),
    );
  }

  DateTime? _date(Uint8List raw) {
    if (raw.every((value) => value == 0)) return null;
    final zone = raw[6] >= 128 ? raw[6] - 256 : raw[6];
    if (raw[1] < 1 ||
        raw[1] > 12 ||
        raw[2] < 1 ||
        raw[2] > 31 ||
        raw[3] > 23 ||
        raw[4] > 59 ||
        raw[5] > 59 ||
        zone < -48 ||
        zone > 52) {
      _bad('Invalid directory timestamp.');
    }
    final date = DateTime.utc(
      1900 + raw[0],
      raw[1],
      raw[2],
      raw[3],
      raw[4],
      raw[5],
    );
    if (date.month != raw[1] || date.day != raw[2]) {
      _bad('Invalid directory date.');
    }
    return date.subtract(Duration(minutes: 15 * zone));
  }

  int? _detectSusp(Uint8List bytes) {
    // CD-XA leaves a 14-byte prefix before SUSP; no arbitrary byte scanning.
    for (final at in const [0, 14]) {
      if (bytes.length < at + 7 || bytes[at] != 0x53 || bytes[at + 1] != 0x50) {
        continue;
      }
      if (bytes[at + 2] != 7 ||
          bytes[at + 3] != 1 ||
          bytes[at + 4] != 0xbe ||
          bytes[at + 5] != 0xef ||
          bytes[at + 6] != at) {
        _bad('Invalid SUSP indicator.');
      }
      return at;
    }
    return null;
  }

  String _identifier(_IsoRecord record) {
    String name;
    if (_joliet) {
      if (record.identifier.length.isOdd) _bad('An odd-length Joliet name.');
      final words = <int>[];
      for (var at = 0; at < record.identifier.length; at += 2) {
        final word = record.identifier[at] * 256 + record.identifier[at + 1];
        if (word >= 0xd800 && word <= 0xdfff) {
          _bad('A Joliet name is not UCS-2.');
        }
        words.add(word);
      }
      name = String.fromCharCodes(words);
    } else {
      name = ascii.decode(record.identifier);
    }
    if (!record.directory) {
      name = name.replaceFirst(RegExp(r';[0-9]+$'), '');
      if (name.endsWith('.')) name = name.substring(0, name.length - 1);
    }
    return name;
  }

  void _checkName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]'))) {
      _bad('An unsafe member name.');
    }
  }

  Future<void> _directory(_IsoRecord directory, String path, int depth) async {
    if (depth > maxDepth) _bad('The directory nesting limit was exceeded.');
    if (!_directories.add(directory.offset)) {
      _bad('A directory extent is reused or cyclic.');
    }
    _directoryBytes += directory.size;
    if (directory.size > 8 * 1024 * 1024 ||
        _directoryBytes > maxDirectoryBytes) {
      _bad('The directory metadata budget was exceeded.');
    }
    final bytes = await _read(directory.offset, directory.size);
    final children = <(_IsoRecord, String)>[];
    var records = 0;
    for (var at = 0; at < bytes.length;) {
      if (bytes[at] == 0) {
        final end = ((at ~/ sectorSize) + 1) * sectorSize;
        if (bytes.sublist(at, end).any((value) => value != 0)) {
          _bad('Nonzero data follows directory sector padding.');
        }
        at = end;
        continue;
      }
      final record = _record(bytes, at);
      at += bytes[at];
      records++;
      if (records == 1 &&
          (!record.self ||
              record.offset != directory.offset ||
              record.size != directory.size)) {
        _bad('A directory has no matching self record.');
      }
      if (records == 2 && !record.parent) {
        _bad('A directory has no parent record.');
      }
      if (record.self || record.parent) {
        if (records > 2) _bad('A directory repeats a special identifier.');
        if (_suspSkip != null) await _rockRidge(record);
        continue;
      }
      final rock = _suspSkip == null ? null : await _rockRidge(record);
      final name = rock?.name ?? _identifier(record);
      _checkName(name);
      final fullName = path.isEmpty ? name : '$path/$name';
      _nameBytes += fullName.length;
      if (fullName.length > 4096 || _nameBytes > 8 * 1024 * 1024) {
        _bad('The member name budget was exceeded.');
      }
      if (!_names.add(fullName)) _bad('Duplicate member path: $fullName');
      if (_members.length >= maxEntries) {
        _bad('The member count limit was exceeded.');
      }
      final mode = rock?.mode;
      final type = mode == null ? 0 : mode & 0xf000;
      final special =
          rock?.special == true ||
          (type != 0 && type != 0x8000 && type != 0x4000);
      if (!special && mode != null && ((type == 0x4000) != record.directory)) {
        _bad('ISO and POSIX file types disagree.');
      }
      _members.add(
        ViewerArchiveMember(
          name: fullName,
          size: record.directory ? 0 : record.size,
          isFile: !record.directory && !special,
          isEncrypted: false,
          isSpecial: special,
          modified: record.modified,
          posixMode: mode,
          pathEscapedRoot: false,
          index: _members.length,
        ),
      );
      _extents.add(record);
      if (record.directory && !special) children.add((record, fullName));
    }
    if (records < 2) _bad('A directory lacks its self and parent records.');
    for (final child in children) {
      await _directory(child.$1, child.$2, depth + 1);
    }
  }

  Future<_RockRidge> _rockRidge(_IsoRecord record) async {
    final skip = _suspSkip!;
    if (record.systemUse.length < skip) _bad('Truncated system-use prefix.');
    final pending = <Uint8List>[Uint8List.sublistView(record.systemUse, skip)];
    final continuations = <String>{};
    final name = BytesBuilder(copy: false);
    var hasName = false;
    var nameContinues = false;
    var special = false;
    int? mode;
    for (var area = 0; area < pending.length; area++) {
      final bytes = pending[area];
      for (var at = 0; at < bytes.length;) {
        if (bytes.length - at == 1 && bytes[at] == 0) break;
        if (at + 4 > bytes.length) _bad('Truncated system-use entry.');
        final length = bytes[at + 2];
        if (length < 4 || at + length > bytes.length || bytes[at + 3] != 1) {
          _bad('Invalid system-use entry.');
        }
        final field = Uint8List.sublistView(bytes, at, at + length);
        final tag = ascii.decode(field.sublist(0, 2), allowInvalid: true);
        at += length;
        if (tag == 'ST') break;
        if (tag == 'CE') {
          if (length != 28 || continuations.length >= 8) {
            _bad('Invalid or excessive SUSP continuations.');
          }
          final block = _both32(field, 4);
          final offset = _both32(field, 12);
          final size = _both32(field, 20);
          if (offset >= sectorSize ||
              size == 0 ||
              size > 64 * 1024 ||
              !continuations.add('$block:$offset:$size')) {
            _bad('Invalid or cyclic SUSP continuation.');
          }
          _continuationBytes += size;
          if (_continuationBytes > 8 * 1024 * 1024) {
            _bad('SUSP metadata budget exceeded.');
          }
          pending.add(await _read(block * sectorSize + offset, size));
        } else if (tag == 'NM') {
          if (length < 5 ||
              field[4] & ~7 != 0 ||
              (field[4] & 6 != 0 && !record.self && !record.parent)) {
            _bad('Invalid Rock Ridge name.');
          }
          if (record.self || record.parent) continue;
          if (hasName && !nameContinues) _bad('Duplicate Rock Ridge name.');
          hasName = true;
          nameContinues = field[4] & 1 != 0;
          name.add(Uint8List.sublistView(field, 5));
          if (name.length > 4096) _bad('Rock Ridge name limit exceeded.');
        } else if (tag == 'PX') {
          if (length != 36 && length != 44) {
            _bad('Invalid Rock Ridge POSIX attributes.');
          }
          if (mode != null) _bad('Duplicate Rock Ridge POSIX attributes.');
          mode = _both32(field, 4);
          for (var pos = 12; pos + 8 <= length; pos += 8) {
            _both32(field, pos);
          }
        } else if (tag == 'SL' || tag == 'PN') {
          special = true;
        } else if (tag == 'CL' || tag == 'PL' || tag == 'RE') {
          _unsupported('Rock Ridge directory relocation is not supported.');
        } else if (tag == 'ZF') {
          _unsupported('Compressed zisofs members are not supported.');
        }
      }
    }
    if (nameContinues) _bad('An unfinished Rock Ridge name continuation.');
    return _RockRidge(
      hasName ? utf8.decode(name.takeBytes()) : null,
      mode,
      special,
    );
  }
}

class _IsoRecord {
  const _IsoRecord({
    required this.offset,
    required this.size,
    required this.directory,
    required this.self,
    required this.parent,
    required this.identifier,
    required this.modified,
    required this.systemUse,
  });
  final int offset;
  final int size;
  final bool directory;
  final bool self;
  final bool parent;
  final Uint8List identifier;
  final DateTime? modified;
  final Uint8List systemUse;
}

class _RockRidge {
  const _RockRidge(this.name, this.mode, this.special);
  final String? name;
  final int? mode;
  final bool special;
}
