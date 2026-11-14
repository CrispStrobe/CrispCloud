// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Portable acceptance over externally mastered complete NTFS images.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_ntfs_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'archive_disk_image_fixture.dart';
import 'archive_ntfs_disk_fixture.dart';
import 'archive_ntfs_reference_data.dart';

class _Checks {
  var count = 0;
  void call(bool condition, String message) {
    count++;
    if (!condition) throw StateError(message);
  }
}

/// Fault injection over complete external bytes, not a filesystem producer.
class NtfsReviewSource implements koni.ByteSource {
  NtfsReviewSource(this.bytes, {this.borrowedReads = false});
  final Uint8List bytes;
  final bool borrowedReads;
  final ranges = <(int, int)>[];
  Object? failure;
  bool shortRead = false;
  int closeCount = 0;
  int? reportedLength;

  @override
  int get length => reportedLength ?? bytes.length;
  @override
  String get name => 'derived-ntfs-reference.img';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closeCount != 0) throw StateError('Read after source close');
    ranges.add((offset, count));
    if (failure case final error?) throw error;
    if (offset < 0 || count < 0 || offset > bytes.length - count) {
      throw RangeError('Read outside independent reference image');
    }
    final n = shortRead && count > 0 ? count - 1 : count;
    return borrowedReads
        ? Uint8List.sublistView(bytes, offset, offset + n)
        : Uint8List.fromList(bytes.sublist(offset, offset + n));
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

int _u16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int _u32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);
int _u64(Uint8List bytes, int at) =>
    _u32(bytes, at) + _u32(bytes, at + 4) * 4294967296;
void _put16(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint16(at, value, Endian.little);
void _put32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);

// Independent, test-only targeting of documented FILE/attribute/run fields.
// Success fixtures are never constructed or repaired by these helpers.
int _clusterBytes(Uint8List bytes) => _u16(bytes, 11) * bytes[13];
int _recordBytes(Uint8List bytes) {
  final encoded = bytes[64] < 128 ? bytes[64] : bytes[64] - 256;
  return encoded < 0 ? 1 << -encoded : encoded * _clusterBytes(bytes);
}

Uint8List _restore(Uint8List raw) {
  final result = Uint8List.fromList(raw);
  final usa = _u16(result, 4), count = _u16(result, 6);
  for (var i = 1; i < count; i++) {
    if (_u16(result, i * 512 - 2) != _u16(result, usa)) {
      throw StateError('External reference has a damaged update sequence');
    }
    _put16(result, i * 512 - 2, _u16(result, usa + i * 2));
  }
  return result;
}

List<int> _attributes(Uint8List record) {
  final result = <int>[];
  var at = _u16(record, 20);
  while (_u32(record, at) != 0xffffffff) {
    result.add(at);
    final length = _u32(record, at + 4);
    if (length < 24 || length > record.length - at) {
      throw StateError('Unexpected external attribute bounds');
    }
    at += length;
  }
  return result;
}

int _attribute(Uint8List record, int type, {String name = ''}) =>
    _attributes(record).singleWhere((at) {
      final actual = String.fromCharCodes([
        for (var i = 0; i < record[at + 9]; i++)
          _u16(record, at + _u16(record, at + 10) + i * 2),
      ]);
      return _u32(record, at) == type && actual == name;
    });

List<(int, int?, int)> _runs(Uint8List record, int attribute) {
  final result = <(int, int?, int)>[];
  var at = attribute + _u16(record, attribute + 32);
  var vcn = 0, lcn = 0;
  while (record[at] != 0) {
    final header = record[at++];
    final lengthBytes = header & 15, offsetBytes = header >> 4;
    var length = 0, factor = 1;
    for (var i = 0; i < lengthBytes; i++) {
      length += record[at++] * factor;
      factor *= 256;
    }
    var delta = 0;
    factor = 1;
    for (var i = 0; i < offsetBytes; i++) {
      delta += record[at++] * factor;
      factor *= 256;
    }
    if (offsetBytes > 0 && record[at - 1] & 128 != 0) delta -= factor;
    if (offsetBytes > 0) lcn += delta;
    result.add((vcn, offsetBytes == 0 ? null : lcn, length));
    vcn += length;
  }
  return result;
}

int _recordOffset(Uint8List image, int number) {
  final cluster = _clusterBytes(image), size = _recordBytes(image);
  final first = _u64(image, 48) * cluster;
  if (number == 0) return first;
  final mft = _restore(Uint8List.sublistView(image, first, first + size));
  final position = number * size;
  for (final (vcn, lcn, count) in _runs(mft, _attribute(mft, 0x80))) {
    final within = position - vcn * cluster;
    if (within >= 0 && within + size <= count * cluster && lcn != null) {
      return lcn * cluster + within;
    }
  }
  throw StateError('External record crosses a fixture mutation boundary');
}

Uint8List _record(Uint8List image, int number) {
  final at = _recordOffset(image, number);
  return _restore(Uint8List.sublistView(image, at, at + _recordBytes(image)));
}

void _editRecord(
  Uint8List image,
  int number,
  void Function(Uint8List) edit, {
  bool mirror = false,
}) {
  final record = _record(image, number);
  edit(record);
  final usa = _u16(record, 4), count = _u16(record, 6);
  for (var i = 1; i < count; i++) {
    _put16(record, usa + i * 2, _u16(record, i * 512 - 2));
    _put16(record, i * 512 - 2, _u16(record, usa));
  }
  image.setAll(_recordOffset(image, number), record);
  if (mirror) {
    image.setAll(
      _u64(image, 56) * _clusterBytes(image) + number * record.length,
      record,
    );
  }
}

int _firstDataCluster(Uint8List image, int record) {
  final bytes = _record(image, record);
  return _runs(bytes, _attribute(bytes, 0x80)).first.$2!;
}

void _replaceFirstLcn(Uint8List record, int value) {
  final attr = _attribute(record, 0x80);
  final at = attr + _u16(record, attr + 32);
  final lengthBytes = record[at] & 15, offsetBytes = record[at] >> 4;
  for (var i = 0; i < offsetBytes; i++) {
    record[at + 1 + lengthBytes + i] = value & 255;
    value ~/= 256;
  }
  if (value != 0) throw StateError('Mutation does not fit original run width');
}

Future<void> _reject(
  Uint8List bytes,
  String label,
  _Checks check, {
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
}) async {
  final source = NtfsReviewSource(bytes);
  ArchiveViewException? failure;
  try {
    final archive = await openNtfsArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
    );
    await archive.close();
  } on ArchiveViewException catch (error) {
    failure = error;
  }
  check(failure?.code == code, 'Expected $code refusal: $label ($failure)');
  check(source.closeCount == 1, 'Failed open closes exactly once: $label');
}

Future<void> _payloads(
  ViewerArchive archive,
  Map<String, (int, String)> expected,
  _Checks check, {
  String prefix = '',
}) async {
  final files = archive.members
      .where((m) => m.isFile && !m.isSpecial && m.name.startsWith(prefix))
      .toList();
  check(files.length == expected.length, 'Regular unnamed file inventory');
  for (final member in files) {
    final reference = expected[member.name.substring(prefix.length)];
    check(reference != null, 'Unexpected file: ${member.name}');
    check(member.size == reference!.$1, 'Member length: ${member.name}');
    check(
      sha256.convert(await archive.readMember(member)).toString() ==
          reference.$2,
      'Buffered external payload: ${member.name}',
    );
    final streamed = BytesBuilder(copy: false);
    await for (final chunk in archive.openMember(member, chunkSize: 4093)) {
      check(chunk.length <= 4093, 'Stream chunk bound: ${member.name}');
      streamed.add(chunk);
    }
    check(
      sha256.convert(streamed.takeBytes()).toString() == reference.$2,
      'Streamed external payload: ${member.name}',
    );
  }
}

void _streamNotices(ViewerArchive archive, _Checks check) {
  for (final path in ['hello.txt', 'hello-hardlink.txt']) {
    for (final entry in ntfsReferenceStreams['hello.txt']!.entries) {
      check(
        archive.notices.any(
          (notice) =>
              notice.contains(jsonEncode(entry.key)) &&
              notice.contains(jsonEncode(path)) &&
              notice.contains('${entry.value.$1} bytes'),
        ),
        'Exact alternate stream name and size remain metadata: $path/${entry.key}',
      );
      check(
        !archive.members.any((member) => member.name.contains(entry.key)),
        'Alternate stream was not flattened into an ordinary path',
      );
    }
  }
}

/// Runs directly on the VM and after actual dart2js compilation under Node.
Future<Map<String, Object>> runNtfsReferenceAcceptance() async {
  final check = _Checks();
  final groups = <String>[];
  final references = <String, Object>{};
  for (final entry in ntfsReferenceImages.entries) {
    final name = entry.key, reference = entry.value;
    final complete = ntfsReferenceBytes(name);
    check(
      sha256.convert(complete).toString() == reference.sha256,
      'Complete external image hash: $name',
    );
    final source = NtfsReferenceSource(name);
    check(await hasNtfsVolumeRecognition(source), 'NTFS recognition: $name');
    check(!source.closed, 'Recognition does not own source: $name');
    final archive = await openNtfsArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
    );
    check(archive.formatName == 'ntfs', 'NTFS format: $name');
    final directories = archive.members
        .where((m) => !m.isFile)
        .map((m) => m.name)
        .toSet();
    check(
      directories.length == ntfsReferenceDirectories.length &&
          directories.containsAll(ntfsReferenceDirectories),
      'Exact external directory inventory: $name',
    );
    check(
      archive.members.every((m) => !m.isSpecial),
      'No invented special files',
    );
    check(source.requestedBytes < 2 * 1024 * 1024, 'Listing stays lazy: $name');
    final listingBytes = source.requestedBytes;
    final namedRecord = _record(complete, reference.records['hello.txt']!);
    final namedData = _attribute(namedRecord, 0x80, name: 'binary-😀');
    final namedRun = _runs(namedRecord, namedData).first;
    final namedStart = namedRun.$2! * reference.clusterBytes;
    final namedEnd = namedStart + namedRun.$3 * reference.clusterBytes;
    check(
      source.rangesRead.every(
        (range) => range.$1 >= namedEnd || range.$1 + range.$2 <= namedStart,
      ),
      'Nonresident alternate stream payload stays unread during listing',
    );
    _streamNotices(archive, check);
    await _payloads(archive, reference.files, check);
    check(source.largestRequest <= 64 * 1024, 'Bounded source windows: $name');
    check(
      archive.members
              .singleWhere((m) => m.name == 'hello.txt')
              .modified
              ?.millisecondsSinceEpoch ==
          946684800000,
      'External fixed NTFS timestamp: $name',
    );
    await archive.close();
    await archive.close();
    check(source.closeCount == 1, 'Idempotent source close: $name');
    references[name] = {
      'image_bytes': reference.length,
      'image_sha256': reference.sha256,
      'sector_bytes': reference.sectorBytes,
      'cluster_bytes': reference.clusterBytes,
      'record_bytes': reference.recordBytes,
      'regular_files': reference.files.length,
      'directories': directories.length,
      'listing_source_bytes': listingBytes,
    };
    groups.add('external-$name');
  }
  final unsupported = ntfsUnsupportedReferenceImages.entries.single;
  check(
    sha256.convert(ntfsReferenceBytes(unsupported.key)).toString() ==
        unsupported.value.sha256,
    'Complete external unsupported image hash',
  );
  await _reject(
    ntfsReferenceBytes(unsupported.key),
    'authentic directory ATTRIBUTE_LIST',
    check,
    code: ArchiveMessageCode.unsupported,
  );
  groups.add('external-attribute-list-refusal');

  final reference = ntfsReferenceImages['ntfs31']!;
  final hello = reference.records['hello.txt']!;
  final large = reference.records['nonresident.bin']!;
  final tornFile = ntfsReferenceBytes('ntfs31');
  tornFile[_recordOffset(tornFile, hello) + 510] ^= 1;
  await _reject(tornFile, 'FILE update sequence mismatch', check);
  final tornIndex = ntfsReferenceBytes('ntfs31');
  final root = _record(tornIndex, 5);
  final indexCluster = _runs(
    root,
    _attribute(root, 0xa0, name: r'$I30'),
  ).first.$2!;
  tornIndex[indexCluster * _clusterBytes(tornIndex) + 510] ^= 1;
  await _reject(tornIndex, 'INDX update sequence mismatch', check);
  final mirror = ntfsReferenceBytes('ntfs31');
  mirror[_u64(mirror, 56) * _clusterBytes(mirror) + 510] ^= 1;
  await _reject(mirror, 'MFT mirror update sequence mismatch', check);
  groups.add('derived-record-and-index-fixups');

  final badSequence = ntfsReferenceBytes('ntfs31');
  _editRecord(badSequence, hello, (r) => _put16(r, 16, _u16(r, 16) + 1));
  await _reject(badSequence, 'directory/MFT sequence mismatch', check);
  final badAttribute = ntfsReferenceBytes('ntfs31');
  _editRecord(
    badAttribute,
    large,
    (r) => _put32(r, _attribute(r, 0x80) + 4, r.length * 2),
  );
  await _reject(badAttribute, 'attribute leaves FILE record', check);
  final badRecordNumber = ntfsReferenceBytes('ntfs31');
  _editRecord(badRecordNumber, hello, (r) => _put32(r, 44, hello + 1));
  await _reject(badRecordNumber, 'FILE record number mismatch', check);
  groups.add('derived-record-metadata-corruptions');

  final zeroRun = ntfsReferenceBytes('ntfs31');
  _editRecord(zeroRun, large, (r) {
    final attr = _attribute(r, 0x80), run = attr + _u16(r, attr + 32);
    for (var i = 0; i < (r[run] & 15); i++) {
      r[run + 1 + i] = 0;
    }
  });
  await _reject(zeroRun, 'zero-length mapping run', check);
  final outsideRun = ntfsReferenceBytes('ntfs31');
  _editRecord(outsideRun, large, (r) => _replaceFirstLcn(r, 32767));
  await _reject(outsideRun, 'physical mapping outside volume', check);
  final alias = ntfsReferenceBytes('ntfs31');
  _editRecord(alias, large, (r) => _replaceFirstLcn(r, _u64(alias, 48)));
  await _reject(alias, 'payload aliases reserved MFT allocations', check);
  groups.add('derived-runlist-bounds-and-crosslinks');

  final bitmap = ntfsReferenceBytes('ntfs31');
  final dataCluster = _firstDataCluster(bitmap, large);
  final bitmapCluster = _firstDataCluster(bitmap, 6);
  bitmap[bitmapCluster * _clusterBytes(bitmap) + dataCluster ~/ 8] &=
      255 ^ (1 << (dataCluster % 8));
  await _reject(bitmap, 'allocated data absent from volume bitmap', check);
  groups.add('derived-allocation-bitmap');

  final dirty = ntfsReferenceBytes('ntfs31');
  _editRecord(dirty, 3, (r) {
    final attr = _attribute(r, 0x70), value = attr + _u16(r, attr + 20);
    _put16(r, value + 10, 1);
  }, mirror: true);
  await _reject(
    dirty,
    'dirty volume needs replay',
    check,
    code: ArchiveMessageCode.unsupported,
  );
  for (final (flag, label) in [
    (1, 'compressed DATA'),
    (0x4000, 'encrypted DATA'),
  ]) {
    final bytes = ntfsReferenceBytes('ntfs31');
    _editRecord(bytes, large, (r) => _put16(r, _attribute(r, 0x80) + 12, flag));
    await _reject(bytes, label, check, code: ArchiveMessageCode.unsupported);
  }
  final reparse = ntfsReferenceBytes('ntfs31');
  _editRecord(reparse, hello, (r) {
    final attr = _attribute(r, 0x10), value = attr + _u16(r, attr + 20);
    _put32(r, value + 32, _u32(r, value + 32) | 0x400);
  });
  await _reject(
    reparse,
    'reparse file metadata',
    check,
    code: ArchiveMessageCode.unsupported,
  );
  groups.add('derived-unsupported-profiles');

  final surrogate = ntfsReferenceBytes('ntfs31');
  _editRecord(surrogate, hello, (r) {
    final attr = _attributes(r).firstWhere((a) => _u32(r, a) == 0x30);
    _put16(r, attr + _u16(r, attr + 20) + 66, 0xd800);
  });
  await _reject(surrogate, 'unpaired filename surrogate', check);
  groups.add('derived-strict-utf16');

  const futureMillis = 16700000000987;
  final timestamp = ntfsReferenceBytes('ntfs31');
  _editRecord(timestamp, hello, (r) {
    final attr = _attribute(r, 0x10), at = attr + _u16(r, attr + 20) + 8;
    final ticks =
        (BigInt.from(futureMillis) + BigInt.from(11644473600000)) *
        BigInt.from(10000);
    _put32(r, at, (ticks & BigInt.from(0xffffffff)).toInt());
    _put32(r, at + 4, (ticks >> 32).toInt());
  });
  final futureArchive = await openNtfsArchive(
    NtfsReviewSource(timestamp),
    maxMemberBytes: 2 * 1024 * 1024,
  );
  check(
    futureArchive.members
            .singleWhere((m) => m.name == 'hello.txt')
            .modified
            ?.millisecondsSinceEpoch ==
        futureMillis,
    'FILETIME beyond exact-double ticks retains exact milliseconds',
  );
  await futureArchive.close();
  groups.add('derived-future-filetime');

  final failure = StateError('External NTFS source was revoked');
  final unavailable = NtfsReviewSource(ntfsReferenceBytes('ntfs31'))
    ..failure = failure;
  Object? caught;
  try {
    await openNtfsArchive(unavailable, maxMemberBytes: 2 * 1024 * 1024);
  } catch (error) {
    caught = error;
  }
  check(identical(caught, failure), 'Provider error identity during open');
  check(unavailable.closeCount == 1, 'Failed source closed once');
  final short = NtfsReviewSource(ntfsReferenceBytes('ntfs31'))
    ..shortRead = true;
  caught = null;
  try {
    await openNtfsArchive(short, maxMemberBytes: 2 * 1024 * 1024);
  } catch (error) {
    caught = error;
  }
  check(
    caught is ArchiveViewException && short.closeCount == 1,
    'Short source read refused',
  );
  final cancelled = NtfsReferenceSource('ntfs31');
  caught = null;
  try {
    await openNtfsArchive(
      cancelled,
      maxMemberBytes: 2 * 1024 * 1024,
      isCancelled: () => true,
    );
  } catch (error) {
    caught = error;
  }
  check(
    caught is ArchiveNtfsCancelledException,
    'Cancellation has a distinct outcome',
  );
  check(cancelled.closeCount == 1, 'Cancelled source closed once');
  groups.add('source-failure-short-read-and-cancellation');

  final live = NtfsReviewSource(ntfsReferenceBytes('ntfs31'));
  final lazyArchive = await openNtfsArchive(
    live,
    maxMemberBytes: 2 * 1024 * 1024,
  );
  final lazyMember = lazyArchive.members.singleWhere(
    (m) => m.name == 'nonresident.bin',
  );
  live.failure = failure;
  caught = null;
  try {
    await lazyArchive.readMember(lazyMember);
  } catch (error) {
    caught = error;
  }
  check(identical(caught, failure), 'Lazy payload preserves provider failure');
  live.failure = null;
  live.reportedLength = live.bytes.length - 1;
  caught = null;
  try {
    await lazyArchive.readMember(lazyMember);
  } catch (error) {
    caught = error;
  }
  check(
    caught is ArchiveViewException,
    'Length mutation during lazy read refused',
  );
  await lazyArchive.close();
  check(live.closeCount == 1, 'Lazy failure closes source once');
  groups.add('lazy-source-failure-and-length-mutation');

  final borrowed = NtfsReviewSource(
    ntfsReferenceBytes('ntfs31'),
    borrowedReads: true,
  );
  final cachedArchive = await openNtfsArchive(
    borrowed,
    maxMemberBytes: 2 * 1024 * 1024,
  );
  check(
    sha256.convert(borrowed.bytes).toString() == reference.sha256,
    'Reading borrowed metadata never modifies the external source',
  );
  final at = _recordOffset(borrowed.bytes, large);
  borrowed.bytes.fillRange(at, at + _recordBytes(borrowed.bytes), 0);
  final cachedMember = cachedArchive.members.singleWhere(
    (m) => m.name == 'nonresident.bin',
  );
  check(
    sha256.convert(await cachedArchive.readMember(cachedMember)).toString() ==
        reference.files['nonresident.bin']!.$2,
    'Validated mappings survive mutation of borrowed record buffers',
  );
  await cachedArchive.close();
  groups.add('borrowed-metadata-mutation');

  final limits = <String, Future<ViewerArchive> Function(NtfsReferenceSource)>{
    'entries': (s) =>
        openNtfsArchive(s, maxMemberBytes: 2 * 1024 * 1024, maxEntries: 2),
    'metadata': (s) => openNtfsArchive(
      s,
      maxMemberBytes: 2 * 1024 * 1024,
      maxMetadataBytes: 512,
    ),
    'directories': (s) => openNtfsArchive(
      s,
      maxMemberBytes: 2 * 1024 * 1024,
      maxDirectoryBytes: 512,
    ),
    'paths and notices': (s) => openNtfsArchive(
      s,
      maxMemberBytes: 2 * 1024 * 1024,
      maxRetainedPathBytes: 16,
    ),
    'clusters': (s) =>
        openNtfsArchive(s, maxMemberBytes: 2 * 1024 * 1024, maxClusters: 2),
    'extents': (s) =>
        openNtfsArchive(s, maxMemberBytes: 2 * 1024 * 1024, maxExtents: 1),
    'depth': (s) =>
        openNtfsArchive(s, maxMemberBytes: 2 * 1024 * 1024, maxDepth: 1),
  };
  for (final entry in limits.entries) {
    final source = NtfsReferenceSource('ntfs31');
    caught = null;
    try {
      await entry.value(source);
    } catch (error) {
      caught = error;
    }
    check(
      caught is ArchiveViewException &&
          caught.code == ArchiveMessageCode.archiveLimit,
      'Resource limit: ${entry.key}',
    );
    check(source.closeCount == 1, 'Limit owns source: ${entry.key}');
  }
  final ceilingSource = NtfsReferenceSource('ntfs31');
  final ceilingArchive = await openNtfsArchive(
    ceilingSource,
    maxMemberBytes: 1024,
  );
  final ceilingMember = ceilingArchive.members.singleWhere(
    (m) => m.name == 'nonresident.bin',
  );
  final reads = ceilingSource.rangesRead.length;
  caught = null;
  try {
    await ceilingArchive.readMember(ceilingMember);
  } catch (error) {
    caught = error;
  }
  check(caught is ArchiveViewException, 'Member ceiling refused buffered read');
  caught = null;
  try {
    await ceilingArchive.openMember(ceilingMember).toList();
  } catch (error) {
    caught = error;
  }
  check(caught is ArchiveViewException, 'Member ceiling refused streamed read');
  check(
    ceilingSource.rangesRead.length == reads,
    'Member ceiling precedes payload I/O',
  );
  await ceilingArchive.close();
  groups.add('resource-and-member-limits');

  final wrappers = <(String, String, DiskImageFixture, int?)>[
    (
      'derived-ntfs-mbr',
      'ntfs31',
      DiskImageFixture.mbr(
        volumes: [NtfsReferenceSource('ntfs31')],
        types: [0x07],
      ),
      null,
    ),
    (
      'derived-ntfs-gpt-4096',
      'ntfs31-4k',
      ntfsGptFixture(
        volumes: [NtfsReferenceSource('ntfs31-4k')],
        sectorBytes: 4096,
      ),
      4096,
    ),
    (
      'derived-ntfs-gpt-above-2tib',
      'ntfs31-small',
      ntfsGptFixture(
        volumes: [NtfsReferenceSource('ntfs31-small')],
        firstPartitionLba: 4294967317,
      ),
      null,
    ),
  ];
  final wrapperResults = <String, Object>{};
  for (final (label, fixture, disk, sector) in wrappers) {
    check(
      await hasDiskImagePartitionRecognition(disk),
      'Partition recognition: $label',
    );
    check(!disk.closed, 'Partition recognition remains non-owning');
    final opened = await openDiskImageArchive(
      disk,
      maxMemberBytes: kArchiveStreamingLimit,
      logicalSectorBytes: sector,
    );
    check(opened.formatName == 'disk-image', 'Disk adapter format: $label');
    await _payloads(
      opened,
      ntfsReferenceImages[fixture]!.files,
      check,
      prefix: 'partition-001/files/',
    );
    _streamNotices(opened, check);
    final raw = opened.members.singleWhere(
      (m) => m.name == 'partition-001/raw.img',
    );
    check(
      raw.size == ntfsReferenceImages[fixture]!.length,
      'Raw partition length',
    );
    final rawPrefix = await opened
        .openMember(raw, chunkSize: 512)
        .take(1)
        .toList();
    check(
      sha256.convert(rawPrefix.single).toString() ==
          sha256.convert(await disk.volumes.single.$3.read(0, 512)).toString(),
      'Raw partition bytes are preserved',
    );
    if (label.endsWith('-mbr')) {
      check(
        sha256.convert(await opened.readMember(raw)).toString() ==
            reference.sha256,
        'Complete raw NTFS image hash',
      );
    }
    final start = disk.volumes.single.$1;
    if (label.endsWith('above-2tib')) {
      check(
        start > 2 * 1024 * 1024 * 1024 * 1024,
        'Derived partition lies beyond 2TiB',
      );
      check(
        disk.reads.any((range) => range.$1 > start + 4096),
        'Real payload reads retain exact large offsets',
      );
    }
    await opened.close();
    await opened.close();
    check(disk.closeCount == 1, 'One root close for partitioned source');
    wrapperResults[label] = {
      'complete_external_image': fixture,
      'partition_offset_bytes': start,
      'regular_files': ntfsReferenceImages[fixture]!.files.length,
      'raw_partition_bytes': raw.size,
    };
    groups.add(label);
  }
  return {
    'schema': 1,
    'groups': groups,
    'checks': check.count,
    'independent_reference_images': references,
    'independent_unsupported_reference_image': {
      'name': unsupported.key,
      'sha256': unsupported.value.sha256,
      'reason': 'directory ATTRIBUTE_LIST',
    },
    'derived_partition_wrappers': wrapperResults,
    'all_payload_and_complete_image_hashes_match': true,
    'named_streams_are_metadata_only': true,
  };
}

Future<void> main() async {
  // Structured stdout is the standalone VM/JavaScript acceptance contract.
  // ignore: avoid_print
  print(jsonEncode(await runNtfsReferenceAcceptance()));
}
