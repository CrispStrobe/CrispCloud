// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original small NTFS assembler for malformed-input and boundary tests.
// External mkntfs fixtures provide independent interoperability evidence.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

void ntfsPut16(Uint8List b, int at, int value) =>
    ByteData.sublistView(b).setUint16(at, value, Endian.little);
void ntfsPut32(Uint8List b, int at, int value) =>
    ByteData.sublistView(b).setUint32(at, value, Endian.little);
void ntfsPut64(Uint8List b, int at, int value) {
  ntfsPut32(b, at, value % 4294967296);
  ntfsPut32(b, at + 4, value ~/ 4294967296);
}

int ntfsGet16(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint16(at, Endian.little);
int ntfsGet32(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint32(at, Endian.little);
int _align(int n) => (n + 7) ~/ 8 * 8;
Uint8List _utf16(String value) {
  final bytes = Uint8List(value.length * 2);
  for (var i = 0; i < value.length; i++) {
    ntfsPut16(bytes, i * 2, value.codeUnitAt(i));
  }
  return bytes;
}

Uint8List ntfsResidentAttribute(
  int type,
  List<int> value, {
  String name = '',
  int flags = 0,
}) {
  final nameBytes = _utf16(name);
  final valueOffset = _align(24 + nameBytes.length);
  final bytes = Uint8List(_align(valueOffset + value.length));
  ntfsPut32(bytes, 0, type);
  ntfsPut32(bytes, 4, bytes.length);
  bytes[9] = name.length;
  ntfsPut16(bytes, 10, 24);
  ntfsPut16(bytes, 12, flags);
  ntfsPut32(bytes, 16, value.length);
  ntfsPut16(bytes, 20, valueOffset);
  bytes.setRange(24, 24 + nameBytes.length, nameBytes);
  bytes.setRange(valueOffset, valueOffset + value.length, value);
  return bytes;
}

class NtfsFixtureRun {
  const NtfsFixtureRun(this.count, this.lcn);
  final int count;
  final int? lcn;
}

List<int> _integerBytes(int value, {bool signed = false}) {
  var width = 1, span = 256;
  while (signed ? value < -span ~/ 2 || value >= span ~/ 2 : value >= span) {
    width++;
    span *= 256;
  }
  var encoded = value < 0 ? span + value : value;
  return List<int>.generate(width, (_) {
    final byte = encoded % 256;
    encoded ~/= 256;
    return byte;
  });
}

Uint8List ntfsMappedAttribute(
  int type, {
  required int size,
  required List<NtfsFixtureRun> runs,
  String name = '',
  int initialized = -1,
  int clusterBytes = 1024,
  int flags = 0,
  int compressionUnit = 0,
}) {
  final mappings = <int>[];
  var previous = 0, clusters = 0, physical = 0;
  for (final run in runs) {
    final count = _integerBytes(run.count);
    final offset = run.lcn == null
        ? <int>[]
        : _integerBytes(run.lcn! - previous, signed: true);
    mappings.add(count.length + offset.length * 16);
    mappings.addAll(count);
    mappings.addAll(offset);
    clusters += run.count;
    if (run.lcn != null) {
      previous = run.lcn!;
      physical += run.count;
    }
  }
  mappings.add(0);
  final sparse = flags & 0x8000 != 0;
  final header = sparse ? 72 : 64;
  final nameBytes = _utf16(name), runOffset = _align(header + name.length * 2);
  final bytes = Uint8List(_align(runOffset + mappings.length));
  ntfsPut32(bytes, 0, type);
  ntfsPut32(bytes, 4, bytes.length);
  bytes[8] = 1;
  bytes[9] = name.length;
  ntfsPut16(bytes, 10, header);
  ntfsPut16(bytes, 12, flags);
  if (clusters == 0) {
    ntfsPut32(bytes, 24, 0xffffffff);
    ntfsPut32(bytes, 28, 0xffffffff);
  } else {
    ntfsPut64(bytes, 24, clusters - 1);
  }
  ntfsPut16(bytes, 32, runOffset);
  ntfsPut16(bytes, 34, compressionUnit);
  ntfsPut64(bytes, 40, clusters * clusterBytes);
  ntfsPut64(bytes, 48, size);
  ntfsPut64(bytes, 56, initialized < 0 ? size : initialized);
  if (sparse) ntfsPut64(bytes, 64, physical * clusterBytes);
  bytes.setRange(header, header + nameBytes.length, nameBytes);
  bytes.setRange(runOffset, runOffset + mappings.length, mappings);
  return bytes;
}

Uint8List ntfsFileName(
  String name, {
  int parent = 5,
  int parentSequence = 5,
  int namespace = 3,
  int size = 0,
  bool directory = false,
}) {
  final value = Uint8List(66 + name.length * 2);
  ntfsPut32(value, 0, parent);
  ntfsPut16(value, 6, parentSequence);
  ntfsPut64(value, 8, 133444736000000000);
  ntfsPut64(value, 16, 133444736000000000);
  ntfsPut64(value, 24, 133444736000000000);
  ntfsPut64(value, 32, 133444736000000000);
  ntfsPut64(value, 40, size);
  ntfsPut64(value, 48, size);
  ntfsPut32(value, 56, directory ? 0x10000000 : 0x20);
  value[64] = name.length;
  value[65] = namespace;
  value.setRange(66, value.length, _utf16(name));
  return value;
}

class NtfsFixtureEntry {
  const NtfsFixtureEntry(
    this.number,
    this.name, {
    this.sequence = 7,
    this.directory = false,
    this.namespace = 3,
    this.parent = 5,
    this.parentSequence = 5,
  });
  final int number, sequence, namespace, parent, parentSequence;
  final String name;
  final bool directory;
}

class NtfsFixture {
  NtfsFixture({
    String name = 'hello.txt',
    List<int>? payload,
    Uint8List? dataAttribute,
    List<Uint8List> extraAttributes = const [],
  }) : payload = Uint8List.fromList(payload ?? utf8.encode('hello NTFS\n')),
       fileName = name {
    _boot();
    final mftBits = Uint8List(8);
    mftBits[0] = 255;
    mftBits[1] = 255;
    mftBits[3] = 1;
    for (final n in [0, 1]) {
      allocate(n);
    }
    for (var n = 4; n < 36; n++) {
      allocate(n);
    }
    for (var n = 40; n < 44; n++) {
      allocate(n);
    }
    for (var n = 48; n < 52; n++) {
      allocate(n);
    }
    _record(0, r'$MFT', [
      ntfsMappedAttribute(
        0x80,
        size: 32 * recordBytes,
        runs: const [NtfsFixtureRun(32, 4)],
      ),
      ntfsResidentAttribute(0xb0, mftBits),
    ], sequence: 1);
    _record(1, r'$MFTMirr', [
      ntfsMappedAttribute(
        0x80,
        size: 4 * recordBytes,
        runs: const [NtfsFixtureRun(4, 40)],
      ),
    ], sequence: 1);
    _record(2, r'$LogFile', [ntfsResidentAttribute(0x80, [])]);
    final version = Uint8List(12)
      ..[8] = 3
      ..[9] = 1;
    _record(3, r'$Volume', [
      ntfsResidentAttribute(0x70, version),
      ntfsResidentAttribute(0x80, []),
    ]);
    _record(4, r'$AttrDef', [ntfsResidentAttribute(0x80, [])]);
    _record(5, '.', [
      ntfsResidentAttribute(0x90, _largeRoot(), name: r'$I30'),
      ntfsMappedAttribute(
        0xa0,
        name: r'$I30',
        size: 4096,
        runs: const [NtfsFixtureRun(4, 48)],
      ),
      ntfsResidentAttribute(0xb0, [1, 0, 0, 0, 0, 0, 0, 0], name: r'$I30'),
    ], directory: true);
    _record(6, r'$Bitmap', [ntfsResidentAttribute(0x80, volumeBitmap)]);
    _record(7, r'$Boot', [
      ntfsMappedAttribute(0x80, size: 2048, runs: const [NtfsFixtureRun(2, 0)]),
    ]);
    _record(8, r'$BadClus', [
      ntfsResidentAttribute(0x80, []),
      ntfsMappedAttribute(
        0x80,
        name: r'$Bad',
        size: 127 * clusterBytes,
        initialized: 0,
        runs: const [NtfsFixtureRun(127, null)],
      ),
    ]);
    _record(9, r'$Secure', [ntfsResidentAttribute(0x80, [])]);
    _record(10, r'$UpCase', [ntfsResidentAttribute(0x80, [])]);
    _record(11, r'$Extend', [
      ntfsResidentAttribute(0x90, _smallRoot(), name: r'$I30'),
    ], directory: true);
    for (var n = 12; n < 16; n++) {
      _record(n, null, [ntfsResidentAttribute(0x80, [])], links: 0);
    }
    setFile(
      dataAttribute ?? ntfsResidentAttribute(0x80, this.payload),
      extraAttributes: extraAttributes,
    );
    rootEntries.addAll([
      for (final entry in const {
        0: r'$MFT',
        1: r'$MFTMirr',
        2: r'$LogFile',
        3: r'$Volume',
        4: r'$AttrDef',
        6: r'$Bitmap',
        7: r'$Boot',
        8: r'$BadClus',
        9: r'$Secure',
        10: r'$UpCase',
        11: r'$Extend',
      }.entries)
        NtfsFixtureEntry(
          entry.key,
          entry.value,
          sequence: entry.key < 2 ? 1 : entry.key,
          directory: entry.key == 11,
        ),
      const NtfsFixtureEntry(5, '.', sequence: 5, directory: true),
      NtfsFixtureEntry(24, name),
    ]);
    rebuildIndex();
    syncBitmap();
    syncMirror();
  }

  static const clusterBytes = 1024, recordBytes = 1024, mftLcn = 4;
  final bytes = Uint8List(128 * 1024);
  final volumeBitmap = Uint8List(16);
  final Uint8List payload;
  final String fileName;
  final rootEntries = <NtfsFixtureEntry>[];
  int get indexOffset => 48 * clusterBytes;
  int recordOffset(int number) => mftLcn * clusterBytes + number * recordBytes;

  void _boot() {
    bytes[0] = 0xeb;
    bytes[1] = 0x52;
    bytes[2] = 0x90;
    bytes.setRange(3, 11, ascii.encode('NTFS    '));
    ntfsPut16(bytes, 11, 512);
    bytes[13] = 2;
    bytes[21] = 0xf8;
    ntfsPut64(bytes, 40, bytes.length ~/ 512 - 1);
    ntfsPut64(bytes, 48, mftLcn);
    ntfsPut64(bytes, 56, 40);
    bytes[64] = 246;
    bytes[68] = 244;
    bytes[510] = 0x55;
    bytes[511] = 0xaa;
    syncBackup();
  }

  void syncBackup() => bytes.setRange(
    bytes.length - 512,
    bytes.length,
    Uint8List.fromList(bytes.sublist(0, 512)),
  );
  void syncMirror() => bytes.setRange(
    40 * clusterBytes,
    44 * clusterBytes,
    Uint8List.fromList(bytes.sublist(recordOffset(0), recordOffset(4))),
  );

  void allocate(int cluster, {bool allocated = true}) {
    if (allocated) {
      volumeBitmap[cluster ~/ 8] |= 1 << (cluster % 8);
    } else {
      volumeBitmap[cluster ~/ 8] &= ~(1 << (cluster % 8));
    }
  }

  void syncBitmap() {
    _record(6, r'$Bitmap', [ntfsResidentAttribute(0x80, volumeBitmap)]);
  }

  void setMftAllocated(int record, bool allocated) {
    mutateRecord(0, (bytes) {
      final at = attributeOffset(bytes, 0xb0);
      final value = at + ntfsGet16(bytes, at + 20);
      if (allocated) {
        bytes[value + record ~/ 8] |= 1 << (record % 8);
      } else {
        bytes[value + record ~/ 8] &= ~(1 << (record % 8));
      }
    });
  }

  void setFile(
    Uint8List data, {
    List<Uint8List> extraAttributes = const [],
    int links = 1,
    List<Uint8List> extraNames = const [],
  }) {
    _record(
      24,
      fileName,
      [
        for (final name in extraNames) ntfsResidentAttribute(0x30, name),
        data,
        ...extraAttributes,
      ],
      sequence: 7,
      links: links,
    );
  }

  void addFile(
    int number,
    String name,
    Uint8List data, {
    int sequence = 7,
    int links = 1,
    List<Uint8List> extras = const [],
  }) {
    _record(number, name, [data, ...extras], sequence: sequence, links: links);
    setMftAllocated(number, true);
    rootEntries.add(NtfsFixtureEntry(number, name, sequence: sequence));
    rebuildIndex();
  }

  void addDirectory(
    int number,
    String name, {
    required int indexLcn,
    required List<NtfsFixtureEntry> entries,
    int parent = 5,
    int parentSequence = 5,
    int sequence = 7,
  }) {
    _record(
      number,
      name,
      [
        ntfsResidentAttribute(0x90, _largeRoot(), name: r'$I30'),
        ntfsMappedAttribute(
          0xa0,
          name: r'$I30',
          size: 4096,
          runs: [NtfsFixtureRun(4, indexLcn)],
        ),
        ntfsResidentAttribute(0xb0, [1, 0, 0, 0, 0, 0, 0, 0], name: r'$I30'),
      ],
      sequence: sequence,
      parent: parent,
      parentSequence: parentSequence,
      directory: true,
    );
    setMftAllocated(number, true);
    for (var cluster = indexLcn; cluster < indexLcn + 4; cluster++) {
      allocate(cluster);
    }
    writeIndex(indexLcn, entries);
    if (parent == 5) {
      rootEntries.add(
        NtfsFixtureEntry(number, name, sequence: sequence, directory: true),
      );
      rebuildIndex();
    }
    syncBitmap();
  }

  void extendMftTo36Records() {
    mutateRecord(0, (b) {
      final at = attributeOffset(b, 0x80);
      ntfsPut64(b, at + 24, 35);
      ntfsPut64(b, at + 40, 36 * recordBytes);
      ntfsPut64(b, at + 48, 36 * recordBytes);
      ntfsPut64(b, at + 56, 36 * recordBytes);
      b[at + ntfsGet16(b, at + 32) + 1] = 36;
    });
    for (var cluster = 36; cluster < 40; cluster++) {
      allocate(cluster);
    }
    syncBitmap();
  }

  void _record(
    int number,
    String? name,
    List<Uint8List> extras, {
    int? sequence,
    int links = 1,
    bool directory = false,
    int parent = 5,
    int parentSequence = 5,
  }) {
    final b = Uint8List(recordBytes);
    b.setRange(0, 4, ascii.encode('FILE'));
    ntfsPut16(b, 4, 48);
    ntfsPut16(b, 6, 3);
    ntfsPut16(b, 16, sequence ?? number);
    ntfsPut16(b, 18, links);
    ntfsPut16(b, 20, 56);
    ntfsPut16(b, 22, directory ? 3 : 1);
    ntfsPut32(b, 28, recordBytes);
    ntfsPut32(b, 44, number);
    final standard = Uint8List(48);
    for (var at = 0; at < 32; at += 8) {
      ntfsPut64(standard, at, 133444736000000000);
    }
    ntfsPut32(standard, 32, 0x20);
    final attrs = [
      ntfsResidentAttribute(0x10, standard),
      if (name != null)
        ntfsResidentAttribute(
          0x30,
          ntfsFileName(
            name,
            directory: directory,
            parent: parent,
            parentSequence: parentSequence,
          ),
        ),
      ...extras,
    ];
    attrs.sort((a, b) => ntfsGet32(a, 0).compareTo(ntfsGet32(b, 0)));
    var cursor = 56, instance = 0;
    for (final attr in attrs) {
      if (cursor + attr.length + 8 > b.length) {
        throw StateError('Fixture record full.');
      }
      final copy = Uint8List.fromList(attr);
      ntfsPut16(copy, 14, instance++);
      b.setRange(cursor, cursor + copy.length, copy);
      cursor += copy.length;
    }
    ntfsPut32(b, cursor, 0xffffffff);
    ntfsPut32(b, 24, cursor + 8);
    ntfsPut16(b, 40, instance);
    writeRecord(number, b);
  }

  Uint8List fixedRecord(int number) => undoFixups(
    Uint8List.fromList(
      bytes.sublist(recordOffset(number), recordOffset(number) + recordBytes),
    ),
  );
  void writeRecord(int number, Uint8List fixed) {
    final raw = applyFixups(fixed);
    bytes.setRange(
      recordOffset(number),
      recordOffset(number) + recordBytes,
      raw,
    );
    if (number < 4) syncMirror();
  }

  void mutateRecord(int number, void Function(Uint8List) change) {
    final b = fixedRecord(number);
    change(b);
    writeRecord(number, b);
  }

  static Uint8List undoFixups(Uint8List raw) {
    final fixed = Uint8List.fromList(raw);
    final offset = ntfsGet16(raw, 4), count = ntfsGet16(raw, 6);
    for (var i = 1; i < count; i++) {
      fixed[i * 512 - 2] = raw[offset + i * 2];
      fixed[i * 512 - 1] = raw[offset + i * 2 + 1];
    }
    return fixed;
  }

  static Uint8List applyFixups(Uint8List fixed) {
    final raw = Uint8List.fromList(fixed);
    final offset = ntfsGet16(raw, 4), count = ntfsGet16(raw, 6);
    ntfsPut16(raw, offset, 0xa55a);
    for (var i = 1; i < count; i++) {
      ntfsPut16(raw, offset + i * 2, ntfsGet16(raw, i * 512 - 2));
      ntfsPut16(raw, i * 512 - 2, 0xa55a);
    }
    return raw;
  }

  static int attributeOffset(Uint8List fixed, int type, {String name = ''}) {
    var at = ntfsGet16(fixed, 20);
    while (ntfsGet32(fixed, at) != 0xffffffff) {
      final count = fixed[at + 9], nameAt = ntfsGet16(fixed, at + 10);
      final foundName = String.fromCharCodes(
        List<int>.generate(count, (i) => ntfsGet16(fixed, at + nameAt + i * 2)),
      );
      if (ntfsGet32(fixed, at) == type && foundName == name) return at;
      at += ntfsGet32(fixed, at + 4);
    }
    throw StateError('Missing fixture attribute $type:$name.');
  }

  Uint8List _largeRoot() {
    final value = Uint8List(56);
    ntfsPut32(value, 0, 0x30);
    ntfsPut32(value, 4, 1);
    ntfsPut32(value, 8, 4096);
    value[12] = 4;
    ntfsPut32(value, 16, 16);
    ntfsPut32(value, 20, 40);
    ntfsPut32(value, 24, 40);
    value[28] = 1;
    ntfsPut16(value, 40, 24);
    ntfsPut16(value, 44, 3);
    return value;
  }

  Uint8List _smallRoot() {
    final value = Uint8List(48);
    ntfsPut32(value, 0, 0x30);
    ntfsPut32(value, 4, 1);
    ntfsPut32(value, 8, 4096);
    value[12] = 4;
    ntfsPut32(value, 16, 16);
    ntfsPut32(value, 20, 32);
    ntfsPut32(value, 24, 32);
    ntfsPut16(value, 40, 16);
    ntfsPut16(value, 44, 2);
    return value;
  }

  void rebuildIndex() => writeIndex(48, rootEntries);

  void writeIndex(int lcn, List<NtfsFixtureEntry> entries) {
    final b = Uint8List(4096);
    b.setRange(0, 4, ascii.encode('INDX'));
    ntfsPut16(b, 4, 40);
    ntfsPut16(b, 6, 9);
    ntfsPut32(b, 24, 40);
    ntfsPut32(b, 32, 4096 - 24);
    var at = 64;
    for (final entry in entries) {
      final key = ntfsFileName(
        entry.name,
        parent: entry.parent,
        parentSequence: entry.parentSequence,
        namespace: entry.namespace,
        directory: entry.directory,
      );
      final length = _align(16 + key.length);
      if (at + length + 16 > b.length) throw StateError('Fixture index full.');
      ntfsPut32(b, at, entry.number);
      ntfsPut16(b, at + 6, entry.sequence);
      ntfsPut16(b, at + 8, length);
      ntfsPut16(b, at + 10, key.length);
      b.setRange(at + 16, at + 16 + key.length, key);
      at += length;
    }
    ntfsPut16(b, at + 8, 16);
    ntfsPut16(b, at + 12, 2);
    ntfsPut32(b, 28, at + 16 - 24);
    bytes.setRange(
      lcn * clusterBytes,
      lcn * clusterBytes + 4096,
      applyFixups(b),
    );
  }

  void mutateIndex(void Function(Uint8List) change) {
    final fixed = undoFixups(
      Uint8List.fromList(bytes.sublist(indexOffset, indexOffset + 4096)),
    );
    change(fixed);
    bytes.setRange(indexOffset, indexOffset + 4096, applyFixups(fixed));
  }

  NtfsFixtureSource source({bool borrowedReads = false}) =>
      NtfsFixtureSource(bytes, borrowedReads: borrowedReads);
}

class NtfsFixtureSource implements koni.ByteSource {
  NtfsFixtureSource(this.bytes, {this.borrowedReads = false});
  final Uint8List bytes;
  final bool borrowedReads;
  final reads = <(int, int)>[];
  int closeCount = 0;
  int? reportedLength;
  Object? readFailure, closeFailure;
  bool Function(int offset, int length)? failWhen;
  void Function(int offset, int length)? afterRead;
  bool shortRead = false;
  @override
  int get length => reportedLength ?? bytes.length;
  @override
  String get name => 'fixture.ntfs';
  @override
  Future<Uint8List> read(int offset, int length) async {
    reads.add((offset, length));
    if (readFailure != null && (failWhen?.call(offset, length) ?? true)) {
      throw readFailure!;
    }
    if (offset < 0 ||
        length < 0 ||
        offset > bytes.length ||
        length > bytes.length - offset) {
      throw RangeError('Fixture source read bounds.');
    }
    final result = borrowedReads
        ? Uint8List.sublistView(bytes, offset, offset + length)
        : Uint8List.fromList(bytes.sublist(offset, offset + length));
    afterRead?.call(offset, length);
    return shortRead && result.isNotEmpty
        ? result.sublist(0, result.length - 1)
        : result;
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (closeFailure != null) throw closeFailure!;
  }
}
