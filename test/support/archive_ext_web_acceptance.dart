// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Portable acceptance over externally mastered complete ext images.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_ext_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'archive_disk_image_fixture.dart';
import 'archive_ext_disk_fixture.dart';
import 'archive_ext_reference_data.dart';

class _Checks {
  var count = 0;

  void call(bool condition, String message) {
    count++;
    if (!condition) throw StateError(message);
  }
}

/// Fault injection over complete external bytes; never an image generator.
class ExtReviewSource implements koni.ByteSource {
  ExtReviewSource(this.bytes, {this.borrowedReads = false});
  final Uint8List bytes;
  final bool borrowedReads;
  final ranges = <(int, int)>[];
  Object? failure;
  bool shortRead = false;
  int closeCount = 0;

  @override
  int get length => bytes.length;
  @override
  String get name => 'derived-ext-reference.img';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closeCount != 0) throw StateError('Read after source close.');
    ranges.add((offset, count));
    if (failure case final error?) throw error;
    if (offset < 0 || count < 0 || offset > length - count) {
      throw RangeError('Read outside independent reference image.');
    }
    final readCount = shortRead && count > 0 ? count - 1 : count;
    return borrowedReads
        ? Uint8List.sublistView(bytes, offset, offset + readCount)
        : Uint8List.fromList(bytes.sublist(offset, offset + readCount));
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
void _put32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);

// Locate targeted corruptions in a fixed externally mastered inode. This
// independently reads documented ext fields; it does not call reader helpers.
int _inodeOffset(Uint8List bytes, int inode) {
  final blockBytes = 1024 * (1 << _u32(bytes, 1024 + 24));
  final perGroup = _u32(bytes, 1024 + 40);
  final descriptorBytes = _u32(bytes, 1024 + 96) & 0x80 != 0
      ? _u16(bytes, 1024 + 254)
      : 32;
  final descriptor =
      (_u32(bytes, 1024 + 20) + 1) * blockBytes +
      ((inode - 1) ~/ perGroup) * descriptorBytes;
  final table =
      _u32(bytes, descriptor + 8) +
      (descriptorBytes >= 64 ? _u32(bytes, descriptor + 40) * 4294967296 : 0);
  return table * blockBytes + ((inode - 1) % perGroup) * _u16(bytes, 1024 + 88);
}

Future<void> _reject(
  Uint8List bytes,
  String label,
  _Checks check, {
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
}) async {
  final source = ExtReviewSource(bytes);
  ArchiveViewException? failure;
  try {
    final archive = await openExtArchive(
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
  check(files.length == expected.length, 'Regular file inventory');
  for (final member in files) {
    final reference = expected[member.name.substring(prefix.length)];
    check(reference != null, 'Unexpected file: ${member.name}');
    check(member.size == reference!.$1, 'Member length: ${member.name}');
    final bytes = await archive.readMember(member);
    check(
      sha256.convert(bytes).toString() == reference.$2,
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

/// Executes directly on the VM and after real dart2js compilation under Node.
Future<Map<String, Object>> runExtReferenceAcceptance() async {
  final check = _Checks();
  final groups = <String>[];
  final references = <String, Object>{};
  for (final entry in extReferenceImages.entries) {
    final name = entry.key;
    final reference = entry.value;
    check(
      sha256.convert(extReferenceBytes(name)).toString() == reference.sha256,
      'Lossless complete external image: $name',
    );
    final source = ExtReferenceSource(name);
    check(await hasExtVolumeRecognition(source), 'Ext recognition: $name');
    check(!source.closed, 'Recognition owns no source: $name');
    final archive = await openExtArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
    );
    check(archive.formatName == 'ext', 'Ext format name: $name');
    final directories = archive.members
        .where((member) => !member.isFile)
        .map((member) => member.name)
        .toSet();
    check(
      directories.length == extReferenceDirectories.length &&
          directories.containsAll(extReferenceDirectories),
      'External directory inventory: $name',
    );
    final specials = archive.members
        .where((member) => member.isSpecial)
        .map((member) => member.name)
        .toSet();
    check(
      specials.length == extReferenceSpecials.length &&
          specials.containsAll(extReferenceSpecials),
      'Special entries remain metadata: $name',
    );
    check(source.requestedBytes < 1024 * 1024, 'Metadata stays lazy: $name');
    final listingBytes = source.requestedBytes;
    await _payloads(archive, reference.files, check);
    for (final member in archive.members.where((m) => m.isSpecial)) {
      var refused = false;
      final readsBefore = source.rangesRead.length;
      try {
        await archive.readMember(member);
      } on ArchiveViewException {
        refused = true;
      }
      check(refused, 'Special read blocked: ${member.name}');
      check(
        source.rangesRead.length == readsBefore,
        'Special read does no I/O',
      );
    }
    check(source.largestRequest <= 64 * 1024, 'Bounded source windows: $name');
    await archive.close();
    await archive.close();
    check(source.closeCount == 1, 'Idempotent source ownership: $name');
    references[name] = {
      'image_bytes': reference.length,
      'image_sha256': reference.sha256,
      'block_bytes': reference.blockBytes,
      'regular_files': reference.files.length,
      'special_entries': specials.length,
      'directories': directories.length,
      'listing_source_bytes': listingBytes,
    };
    groups.add('external-$name');
  }

  // Each mutation below starts from the exact independent image. No synthetic
  // successful filesystem is constructed by this acceptance driver.
  for (final name in ['ext4', 'ext4-uuid']) {
    final superblock = extReferenceBytes(name)..[1024 + 120] ^= 1;
    await _reject(superblock, '$name superblock checksum', check);
    final descriptor = extReferenceBytes(name);
    final blockBytes = extReferenceImages[name]!.blockBytes;
    final tableAt = (_u32(descriptor, 1024 + 20) + 1) * blockBytes;
    descriptor[tableAt + 12] ^= 1;
    await _reject(descriptor, '$name group descriptor checksum', check);
    final inode = extReferenceBytes(name);
    inode[_inodeOffset(inode, 2) + 100] ^= 1;
    await _reject(inode, '$name root inode checksum', check);
    final directory = extReferenceBytes(name);
    final root = _inodeOffset(directory, 2);
    final firstDirectoryBlock = _u32(directory, root + 60);
    directory[firstDirectoryBlock * blockBytes + 8] ^= 1;
    await _reject(directory, '$name directory checksum', check);
    final blockBitmap = extReferenceBytes(name);
    blockBitmap[_u32(blockBitmap, tableAt) * blockBytes + 100] ^= 1;
    await _reject(blockBitmap, '$name block allocation bitmap checksum', check);
    final inodeBitmap = extReferenceBytes(name);
    inodeBitmap[_u32(inodeBitmap, tableAt + 4) * blockBytes] ^= 1;
    await _reject(inodeBitmap, '$name inode allocation bitmap checksum', check);
    final extents = extReferenceBytes(name);
    // debugfs independently records sparse.bin as inode 21 in every reference.
    // Its root has depth one; the first index points to the checksummed leaf.
    final sparseInode = _inodeOffset(extents, 21);
    check(_u16(extents, sparseInode + 46) == 1, 'External extent-tree depth');
    final leaf = _u32(extents, sparseInode + 56) * blockBytes;
    extents[leaf + blockBytes - 4] ^= 1;
    await _reject(extents, '$name extent leaf checksum', check);
    groups.add('derived-checksum-corruptions-$name');
  }
  final legacyDescriptor = extReferenceBytes('ext4-gdt');
  legacyDescriptor[2048 + 12] ^= 1;
  await _reject(legacyDescriptor, 'legacy group descriptor CRC16', check);
  groups.add('derived-legacy-group-checksum-corruption');

  for (final (flag, label) in [
    (0x4, 'needs journal replay'),
    (0x8000, 'inline data'),
    (0x10000, 'encryption'),
  ]) {
    final bytes = extReferenceBytes('ext2');
    _put32(bytes, 1024 + 96, _u32(bytes, 1024 + 96) | flag);
    await _reject(bytes, label, check, code: ArchiveMessageCode.unsupported);
  }
  final dirty = extReferenceBytes('ext2');
  ByteData.sublistView(dirty).setUint16(1024 + 58, 0, Endian.little);
  await _reject(
    dirty,
    'unclean filesystem',
    check,
    code: ArchiveMessageCode.unsupported,
  );
  groups.add('derived-unsupported-profiles');

  final futureTimestamp = extReferenceBytes('ext3');
  // debugfs records hello.txt as inode 14; ext3 has no inode checksum.
  final helloInode = _inodeOffset(futureTimestamp, 14);
  _put32(futureTimestamp, helloInode + 16, 1700000000);
  ByteData.sublistView(futureTimestamp)
      .setUint16(helloInode + 128, 32, Endian.little);
  _put32(futureTimestamp, helloInode + 136, 987654321 * 4 + 3);
  final futureArchive = await openExtArchive(
    ExtReviewSource(futureTimestamp),
    maxMemberBytes: 2 * 1024 * 1024,
  );
  final futureMember = futureArchive.members.singleWhere(
    (m) => m.name == 'hello.txt',
  );
  check(
    futureMember.modified?.millisecondsSinceEpoch ==
        (1700000000 + 3 * 4294967296) * 1000 + 987,
    'Extended-epoch modification time stays exact on JavaScript',
  );
  await futureArchive.close();
  groups.add('derived-future-timestamp');

  final resizeAlias = extReferenceBytes('ext2');
  final resizeInode = _inodeOffset(resizeAlias, 7);
  final resizeIndex = _u32(resizeAlias, resizeInode + 40 + 13 * 4);
  check(resizeIndex != 0, 'External resize inode has a double-indirect index');
  _put32(resizeAlias, _inodeOffset(resizeAlias, 14) + 40, resizeIndex);
  await _reject(
    resizeAlias,
    'regular data aliases the reserved resize index',
    check,
  );
  groups.add('derived-resize-allocation-alias');

  final failure = StateError('External image provider was revoked.');
  final unavailable = ExtReviewSource(extReferenceBytes('ext2'))
    ..failure = failure;
  Object? caught;
  try {
    await openExtArchive(unavailable, maxMemberBytes: 2 * 1024 * 1024);
  } catch (error) {
    caught = error;
  }
  check(identical(caught, failure), 'Provider error identity during opening');
  check(unavailable.closeCount == 1, 'Provider failure closes owned source');
  final short = ExtReviewSource(extReferenceBytes('ext2'))..shortRead = true;
  var shortRejected = false;
  try {
    await openExtArchive(short, maxMemberBytes: 2 * 1024 * 1024);
  } on ArchiveViewException {
    shortRejected = true;
  }
  check(shortRejected && short.closeCount == 1, 'Short metadata read refused');
  final cancelled = ExtReferenceSource('ext2');
  var cancellationPreserved = false;
  try {
    await openExtArchive(
      cancelled,
      maxMemberBytes: 2 * 1024 * 1024,
      isCancelled: () => true,
    );
  } on ArchiveExtCancelledException {
    cancellationPreserved = true;
  }
  check(cancellationPreserved, 'Cancellation remains a distinct outcome');
  check(cancelled.closeCount == 1, 'Cancellation closes owned source');
  groups.add('source-failure-short-read-and-cancellation');

  final live = ExtReviewSource(extReferenceBytes('ext2'));
  final archive = await openExtArchive(live, maxMemberBytes: 2 * 1024 * 1024);
  final member = archive.members.singleWhere((m) => m.name == 'hello.txt');
  live.failure = failure;
  caught = null;
  try {
    await archive.readMember(member);
  } catch (error) {
    caught = error;
  }
  check(identical(caught, failure), 'Lazy payload provider error identity');
  await archive.close();
  check(live.closeCount == 1, 'Lazy failure source ownership');
  groups.add('lazy-payload-failure');

  final nameCollision = extGptFixture(volumes: [ExtReferenceSource('ext2')]);
  final collisionLayout = nameCollision.gpt!;
  collisionLayout.primaryTable.setRange(56, 58, [0x53, 0xef]);
  collisionLayout.backupTable.setAll(0, collisionLayout.primaryTable);
  collisionLayout.updateTableCrc();
  collisionLayout.updateTableCrc(backup: true);
  check(
    await hasExtVolumeRecognition(nameCollision),
    'GPT name creates the coincidental short ext marker',
  );
  final wrappers = <(String, String, DiskImageFixture, int?)>[
    (
      'derived-linux-mbr',
      'ext2',
      DiskImageFixture.mbr(
        volumes: [ExtReferenceSource('ext2')],
        types: [0x83],
      ),
      null,
    ),
    (
      'derived-linux-gpt-4096',
      'ext4',
      extGptFixture(volumes: [ExtReferenceSource('ext4')], sectorBytes: 4096),
      4096,
    ),
    (
      'derived-linux-gpt-above-2tib',
      'ext4-gdt',
      extGptFixture(
        volumes: [ExtReferenceSource('ext4-gdt')],
        firstPartitionLba: 4294967317,
      ),
      null,
    ),
    ('derived-linux-gpt-ext-marker-name', 'ext2', nameCollision, null),
  ];
  final wrapperResults = <String, Object>{};
  for (final (label, fixture, disk, sector) in wrappers) {
    check(
      await hasDiskImagePartitionRecognition(disk),
      'Disk recognition: $label',
    );
    check(!disk.closed, 'Disk recognition remains non-owning: $label');
    final opened = await openDiskImageArchive(
      disk,
      maxMemberBytes: kArchiveStreamingLimit,
      logicalSectorBytes: sector,
    );
    check(opened.formatName == 'disk-image', 'Disk adapter format: $label');
    await _payloads(
      opened,
      extReferenceImages[fixture]!.files,
      check,
      prefix: 'partition-001/files/',
    );
    final raw = opened.members.singleWhere(
      (m) => m.name == 'partition-001/raw.img',
    );
    check(
      raw.size == extReferenceImages[fixture]!.length,
      'Raw partition size: $label',
    );
    final rawPrefix = await opened
        .openMember(raw, chunkSize: 512)
        .take(1)
        .toList();
    final volume = disk.volumes.single.$3;
    check(
      sha256.convert(rawPrefix.single).toString() ==
          sha256.convert(await volume.read(0, 512)).toString(),
      'Raw partition prefix: $label',
    );
    if (label == 'derived-linux-mbr') {
      check(
        sha256.convert(await opened.readMember(raw)).toString() ==
            extReferenceImages[fixture]!.sha256,
        'Complete raw ext2 image hash',
      );
    }
    final partitionStart = disk.volumes.single.$1;
    if (label == 'derived-linux-gpt-above-2tib') {
      check(partitionStart > 2199023255552, 'Partition starts beyond 2 TiB');
      check(
        disk.reads.any(
          (range) =>
              range.$1 >= partitionStart &&
              range.$1 < partitionStart + volume.length,
        ),
        'Exact large child range reads occurred',
      );
    }
    check(
      disk.reads.every((range) => range.$2 <= 64 * 1024),
      'Disk window bound: $label',
    );
    await opened.close();
    await opened.close();
    check(disk.closeCount == 1, 'Disk source ownership: $label');
    wrapperResults[label] = {
      'classification': 'Synthetic Linux partition table around an unchanged external ext volume.',
      'logical_disk_bytes': disk.length,
      'partition_start_bytes': partitionStart,
      'regular_files': extReferenceImages[fixture]!.files.length,
      'raw_verification': label == 'derived-linux-mbr'
          ? 'complete-image-sha256'
          : '512-byte-prefix',
    };
    groups.add(label);
  }

  final damagedGpt = extGptFixture(volumes: [ExtReferenceSource('ext2')]);
  final damagedLayout = damagedGpt.gpt!;
  damagedLayout.primaryTable.setRange(56, 58, [0x53, 0xef]);
  damagedLayout.backupTable.setAll(0, damagedLayout.primaryTable);
  damagedLayout.updateTableCrc();
  damagedLayout.updateTableCrc(backup: true);
  damagedLayout.primaryHeader[16] ^= 1;
  check(
    await hasDiskImagePartitionRecognition(damagedGpt),
    'Corrupt GPT remains recognized ahead of an incidental ext marker',
  );
  ArchiveViewException? gptError;
  try {
    final opened = await openDiskImageArchive(
      damagedGpt,
      maxMemberBytes: kArchiveStreamingLimit,
    );
    await opened.close();
  } on ArchiveViewException catch (error) {
    gptError = error;
  }
  check(
    gptError?.code == ArchiveMessageCode.corrupt,
    'Damaged GPT cannot fall through to the ext marker',
  );
  check(damagedGpt.closeCount == 1, 'Damaged GPT source ownership');
  groups.add('derived-corrupt-gpt-ext-marker-name');

  final bootRecords = extReferenceBytes('ext2');
  bootRecords.setRange(510, 512, [0x55, 0xaa]);
  bootRecords[450] = 0x83;
  _put32(bootRecords, 454, 128);
  _put32(bootRecords, 458, 512);
  final standalone = ExtReviewSource(bootRecords);
  check(
    !await hasDiskImagePartitionRecognition(standalone),
    'Standalone ext precedes incidental MBR boot records',
  );
  final standaloneArchive = await openExtArchive(
    standalone,
    maxMemberBytes: 2 * 1024 * 1024,
  );
  final standaloneHello = standaloneArchive.members.singleWhere(
    (m) => m.name == 'hello.txt',
  );
  check(
    sha256
            .convert(await standaloneArchive.readMember(standaloneHello))
            .toString() ==
        extReferencePayloads['hello.txt'],
    'Standalone ext with boot code retains its original payload',
  );
  await standaloneArchive.close();
  check(
    standalone.closeCount == 1,
    'Standalone boot-area case source ownership',
  );
  groups.add('derived-ext-with-mbr-boot-records');

  return {
    'groups': groups,
    'checks': check.count,
    'independent_reference_images': references,
    'derived_partition_wrappers': wrapperResults,
    'all_payload_and_complete_image_hashes_match': true,
    'synthetic_successful_filesystems': 0,
    'large_offset_scope': 'Sparse positional addressing to the original small reference image, not complete multi-terabyte physical extraction.',
  };
}

Future<void> main() async {
  // ignore: avoid_print -- portable command-line acceptance emits one JSON result.
  print(jsonEncode(await runExtReferenceAcceptance()));
}
