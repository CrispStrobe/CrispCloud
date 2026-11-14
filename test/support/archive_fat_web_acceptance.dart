// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrispCloud contributors
// Original acceptance over independent physical volumes and synthetic wrappers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_fat_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'archive_disk_image_fixture.dart';
import 'archive_fat_reference_data.dart';
import 'dmg_fixture.dart';

class _Checks {
  var count = 0;
  void call(bool condition, String message) {
    count++;
    if (!condition) throw StateError(message);
  }
}

class FatReviewSource implements koni.ByteSource {
  FatReviewSource(this.bytes, {this.borrowedReads = false});
  final Uint8List bytes;
  final bool borrowedReads;
  final ranges = <(int, int)>[];
  Object? failure;
  bool Function(int offset, int count)? failWhen;
  bool shortNextRead = false;
  int closeCount = 0;
  @override
  int get length => bytes.length;
  @override
  String get name => 'derived-reference.img';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closeCount != 0) throw StateError('Read after source close.');
    ranges.add((offset, count));
    if (failure != null && (failWhen?.call(offset, count) ?? true)) {
      throw failure!;
    }
    if (offset < 0 || count < 0 || offset > length - count) {
      throw RangeError('Read beyond the independent reference image.');
    }
    final result = borrowedReads
        ? Uint8List.sublistView(bytes, offset, offset + count)
        : Uint8List.fromList(bytes.sublist(offset, offset + count));
    if (shortNextRead && result.isNotEmpty) {
      shortNextRead = false;
      return result.sublist(0, result.length - 1);
    }
    return result;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

Future<void> _checkPayloads(
  ViewerArchive archive,
  _Checks check, {
  String prefix = '',
}) async {
  final files = archive.members
      .where((member) => member.isFile && member.name.startsWith(prefix))
      .toList();
  check(files.length == fatReferencePayloads.length, 'File inventory: $prefix');
  for (final member in files) {
    final name = member.name.substring(prefix.length);
    final expected = fatReferencePayloads[name];
    check(expected != null, 'Unexpected reference member: $name');
    final bytes = await archive.readMember(member);
    check(
      sha256.convert(bytes).toString() == expected,
      'Buffered payload differs: $name',
    );
    check(bytes.length == member.size, 'Incorrect member size: $name');
    final streamed = <int>[];
    await for (final chunk in archive.openMember(member, chunkSize: 257)) {
      check(chunk.length <= 257, 'Requested stream chunk bound was exceeded.');
      streamed.addAll(chunk);
    }
    check(
      sha256.convert(streamed).toString() == expected,
      'Streamed payload differs: $name',
    );
  }
}

Future<void> _reject(
  Uint8List bytes,
  String label,
  _Checks check, {
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
}) async {
  final source = FatReviewSource(bytes);
  ArchiveViewException? failure;
  try {
    final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
    await archive.close();
  } on ArchiveViewException catch (error) {
    failure = error;
  }
  check(failure?.code == code, 'Expected $code rejection: $label');
  check(source.closeCount == 1, 'Opening failure source ownership: $label');
}

/// Run without Flutter on the Dart VM and on actual dart2js output under Node.
Future<Map<String, Object>> runFatReferenceAcceptance() async {
  final check = _Checks();
  final groups = <String>[];
  final referenceResults = <String, Object>{};
  for (final name in fatReferenceImages.keys) {
    final source = FatReferenceSource(name);
    check(await hasFatVolumeRecognition(source), 'FAT recognition: $name');
    check(!source.closed, 'Recognition closed its borrowed source: $name');
    check(
      !await hasDiskImagePartitionRecognition(source),
      'FAT superfloppy mistaken for a partitioned disk: $name',
    );
    final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
    check(archive.formatName == 'fat', 'Incorrect format: $name');
    final directories = archive.members
        .where((member) => !member.isFile)
        .map((member) => member.name)
        .toSet();
    check(
      directories.length == fatReferenceDirectories.length &&
          directories.containsAll(fatReferenceDirectories),
      'Directory inventory: $name',
    );
    check(
      source.requestedBytes < 192 * 1024,
      'Opening eagerly read the volume.',
    );
    final metadataBytes = source.requestedBytes;
    await _checkPayloads(archive, check);
    check(
      source.largestRequest <= 64 * 1024,
      'Source request exceeded 64 KiB.',
    );
    await archive.close();
    await archive.close();
    check(source.closeCount == 1, 'Archive source must close exactly once.');
    referenceResults[name] = <String, Object>{
      'image_bytes': source.length,
      'image_sha256': fatReferenceImages[name]!.sha256,
      'payloads_verified_buffered_and_streamed': fatReferencePayloads.length,
      'metadata_requested_bytes_including_probes': metadataBytes,
      'largest_source_request': source.largestRequest,
    };
    groups.add('external-$name');
  }

  final original = fatReferenceBytes('fat12');
  check(
    sha256.convert(original).toString() == fatReferenceImages['fat12']!.sha256,
    'Dart reconstruction differs from the pinned full physical image.',
  );
  final backing = Uint8List(original.length + 23)
    ..fillRange(0, original.length + 23, 0xa5);
  backing.setRange(11, original.length + 11, original);
  final before = sha256.convert(backing).toString();
  final view = Uint8List.sublistView(backing, 11, original.length + 11);
  final source = FatReviewSource(view, borrowedReads: true);
  final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
  final member = archive.members.singleWhere(
    (row) => row.name == 'fragmented.bin',
  );
  final readsBefore = source.ranges.length;
  final prefix = await archive
      .openMember(member, chunkSize: 127)
      .take(1)
      .toList();
  check(
    prefix.length == 1 && prefix.single.length == 127,
    'Cancelled prefix size.',
  );
  check(
    source.ranges.length == readsBefore + 1,
    'Cancelled stream read ahead.',
  );
  check(source.closeCount == 0, 'Cancelling a stream closed the archive.');
  check(
    sha256.convert(await archive.readMember(member)).toString() ==
        fatReferencePayloads[member.name],
    'Cancelled stream prevented later complete extraction.',
  );
  await archive.close();
  check(
    sha256.convert(backing).toString() == before,
    'Reader modified caller bytes.',
  );
  check(source.closeCount == 1, 'Typed-view source leaked.');
  groups.add('offset-view-input-preservation-and-stream-cancellation');

  final boot = Uint8List.fromList(original)..[510] = 0;
  await _reject(boot, 'boot signature', check);
  final geometry = Uint8List.fromList(original)..[11] = 1;
  await _reject(
    geometry,
    'non-power-of-two sector size',
    check,
    code: ArchiveMessageCode.unsupported,
  );
  final mirror = Uint8List.fromList(original)..[5120 + 39] ^= 1;
  await _reject(mirror, 'FAT12 traversed-chain mirror mismatch', check);
  final badLfn = Uint8List.fromList(original);
  final lfnAt = List<int>.generate(
    16,
    (index) => 9728 + index * 32,
  ).firstWhere((at) => badLfn[at + 11] == 0x0f);
  badLfn[lfnAt + 13] ^= 1;
  await _reject(badLfn, 'long-name checksum', check);
  await _reject(
    Uint8List.sublistView(original, 0, original.length - 512),
    'physically truncated volume',
    check,
  );
  groups.add('five-derived-corruption-controls');

  final transport = StateError('Controlled external provider failure.');
  final failedSource = FatReviewSource(original)..failure = transport;
  Object? received;
  try {
    await openFatArchive(failedSource, maxMemberBytes: 1024 * 1024);
  } catch (error) {
    received = error;
  }
  check(identical(received, transport), 'Transport failure was reclassified.');
  check(failedSource.closeCount == 1, 'Transport failure leaked source.');
  final cancelledSource = FatReviewSource(original);
  var cancelled = false;
  try {
    await openFatArchive(
      cancelledSource,
      maxMemberBytes: 1024 * 1024,
      isCancelled: () => true,
    );
  } on ArchiveFatCancelledException {
    cancelled = true;
  }
  check(cancelled, 'Cancellation was reclassified.');
  check(cancelledSource.closeCount == 1, 'Cancellation leaked source.');
  groups.add('transport-and-open-cancellation');

  var cancelEmpty = false;
  final emptySource = FatReferenceSource('fat12');
  final emptyArchive = await openFatArchive(
    emptySource,
    maxMemberBytes: 1024 * 1024,
    isCancelled: () => cancelEmpty,
  );
  final emptyMember = emptyArchive.members.singleWhere(
    (row) => row.name == 'empty.bin',
  );
  cancelEmpty = true;
  for (final operation in <Future<void> Function()>[
    () => emptyArchive.readMember(emptyMember).then<void>((_) {}),
    () => emptyArchive.openMember(emptyMember).drain<void>(),
  ]) {
    var stopped = false;
    try {
      await operation();
    } on ArchiveFatCancelledException {
      stopped = true;
    }
    check(stopped, 'An empty member bypassed cancellation.');
  }
  await emptyArchive.close();
  check(
    emptySource.closeCount == 1,
    'Empty-member cancellation leaked source.',
  );
  groups.add('empty-member-cancellation');

  final wrappers = <(String, DiskImageFixture, int?)>[
    (
      'synthetic-mbr-fat12',
      DiskImageFixture.mbr(volumes: [FatReferenceSource('fat12')]),
      null,
    ),
    (
      'synthetic-mbr-4096-fat16',
      DiskImageFixture.mbr(
        volumes: [FatReferenceSource('fat16-sector4096')],
        sectorBytes: 4096,
        types: [0x06],
      ),
      4096,
    ),
    (
      'synthetic-gpt-fat32',
      DiskImageFixture.gpt(volumes: [FatReferenceSource('fat32')]),
      null,
    ),
    (
      'synthetic-gpt-large-offset-fat12',
      DiskImageFixture.gpt(
        volumes: [FatReferenceSource('fat12')],
        firstPartitionLba: 4294967317,
      ),
      null,
    ),
  ];
  final wrapperResults = <String, Object>{};
  for (final (label, disk, sectorBytes) in wrappers) {
    check(
      await hasDiskImagePartitionRecognition(disk),
      'Disk recognition: $label',
    );
    check(!disk.closed, 'Disk recognition took ownership: $label');
    final opened = await openDiskImageArchive(
      disk,
      maxMemberBytes: kArchiveStreamingLimit,
      logicalSectorBytes: sectorBytes,
    );
    check(opened.formatName == 'disk-image', 'Disk format: $label');
    await _checkPayloads(opened, check, prefix: 'partition-001/files/');
    final raw = opened.members.singleWhere(
      (row) => row.name == 'partition-001/raw.img',
    );
    final rawPrefix = await opened
        .openMember(raw, chunkSize: 512)
        .take(1)
        .toList();
    final volume = disk.volumes.single.$3;
    check(
      sha256.convert(rawPrefix.single).toString() ==
          sha256.convert(await volume.read(0, 512)).toString(),
      'Raw partition prefix differs: $label',
    );
    if (label == 'synthetic-mbr-fat12') {
      check(
        sha256.convert(await opened.readMember(raw)).toString() ==
            fatReferenceImages['fat12']!.sha256,
        'Complete raw FAT12 partition differs from independent image.',
      );
    }
    check(
      disk.reads.every((range) => range.$2 <= 64 * 1024),
      'Disk source read cap.',
    );
    await opened.close();
    await opened.close();
    check(disk.closeCount == 1, 'Disk source close count: $label');
    wrapperResults[label] = <String, Object>{
      'classification':
          'Synthetic partition table around an unchanged external FAT volume.',
      'logical_disk_bytes': disk.length,
      'partition_start_bytes': disk.volumes.single.$1,
      'payloads_verified_buffered_and_streamed': fatReferencePayloads.length,
      'raw_verification': label == 'synthetic-mbr-fat12'
          ? 'complete-image-sha256'
          : '512-byte-prefix',
    };
    groups.add(label);
  }
  final dmgResults = <String, Object>{};
  for (final (label, method) in <(String, int)>[
    ('synthetic-udif-raw', 1),
    ('synthetic-udif-zlib', 0x80000005),
    ('synthetic-udif-lzfse-raw-blocks', 0x80000007),
  ]) {
    final wrapper = DmgFixture(original, method: method, chunkBytes: 32768);
    final wrappedSource = FatReviewSource(wrapper.bytes, borrowedReads: true);
    final before = sha256.convert(wrapper.bytes).toString();
    final opened = await openDmgArchive(
      wrappedSource,
      maxMemberBytes: 2 * 1024 * 1024,
    );
    check(opened.formatName == 'dmg', 'UDIF format: $label');
    final hello = opened.members.singleWhere(
      (row) => row.name.endsWith('/HELLO.TXT'),
    );
    final prefix = hello.name.substring(
      0,
      hello.name.length - 'HELLO.TXT'.length,
    );
    await _checkPayloads(opened, check, prefix: prefix);
    final raw = opened.members.singleWhere(
      (row) => row.name.startsWith('partitions/'),
    );
    check(raw.name.endsWith('.fat'), 'UDIF raw FAT identity was lost.');
    check(
      sha256.convert(await opened.readMember(raw)).toString() ==
          fatReferenceImages['fat12']!.sha256,
      'UDIF raw FAT bytes differ from the independently mastered image.',
    );
    check(
      opened.notices.any((notice) => notice.contains('FAT12;')),
      'UDIF did not retain the child FAT geometry notice.',
    );
    await opened.close();
    check(wrappedSource.closeCount == 1, 'UDIF source close count: $label');
    check(
      sha256.convert(wrapper.bytes).toString() == before,
      'UDIF input changed.',
    );
    dmgResults[label] = <String, Object>{
      'classification':
          'Synthetic UDIF wrapper around an unchanged external FAT12 volume.',
      'udif_bytes': wrapper.bytes.length,
      'payloads_verified_buffered_and_streamed': fatReferencePayloads.length,
      'complete_raw_volume_sha256': fatReferenceImages['fat12']!.sha256,
      'codec_scope': method == 0x80000007
          ? 'LZFSE raw block framing; compressed FSE/LZVN blocks are covered by separate existing codec references.'
          : label,
    };
    groups.add(label);
  }
  return <String, Object>{
    'checks': check.count,
    'groups': groups,
    'independent_reference_images': referenceResults,
    'derived_partition_wrappers': wrapperResults,
    'derived_udif_wrappers': dmgResults,
    'large_offset_scope': 'Sparse positional access to original small payloads; no complete large physical disk extraction.',
  };
}

Future<void> main() async {
  // ignore: avoid_print -- portable command-line acceptance emits one JSON result.
  print(jsonEncode(await runFatReferenceAcceptance()));
}
