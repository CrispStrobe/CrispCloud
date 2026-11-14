// SPDX-License-Identifier: MIT
// Original independent-reference and lifecycle acceptance, run on VM and JS.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_udf_reader.dart';

import 'archive_udf_fixture.dart';
import 'archive_udf_reference_data.dart';

var _checks = 0;
void check(bool condition, String message) {
  _checks++;
  if (!condition) {
    throw StateError(message);
  }
}

class UdfReferenceSource implements koni.ByteSource {
  UdfReferenceSource(this.bytes, {this.failAt});
  final Uint8List bytes;
  final int? failAt;
  var closed = false;
  var reads = 0;
  var requested = 0;
  var largestRequest = 0;
  final ranges = <(int, int)>[];

  @override
  int get length => bytes.length;
  @override
  String get name => 'independent.udf';
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed) {
      throw StateError('Read after close');
    }
    if (failAt != null && offset >= failAt!) {
      throw StateError('Controlled source failure');
    }
    check(
      offset >= 0 && length >= 0 && offset <= bytes.length - length,
      'Reader requested bytes outside the image',
    );
    reads++;
    requested += length;
    if (length > largestRequest) {
      largestRequest = length;
    }
    ranges.add((offset, length));
    return Uint8List.fromList(bytes.sublist(offset, offset + length));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<void> rejects(Uint8List bytes, String label) async {
  final source = UdfReferenceSource(bytes);
  var failed = false;
  try {
    final opened = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
    await opened.close();
  } on ArchiveViewException {
    failed = true;
  }
  check(failed, 'Malformed independent image accepted: $label');
  check(source.closed, 'Failure leaked source: $label');
}

Future<void> main() async {
  final results = <String, Object>{};
  for (final name in udfReferenceImages.keys) {
    final source = UdfReferenceSource(udfReferenceBytes(name));
    check(await hasUdfVolumeRecognition(source), 'UDF recognition: $name');
    check(!source.closed, 'Recognition must not close source');
    final archive = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
    check(archive.formatName == 'udf', 'Incorrect detected format');
    check(archive.members.length == 5, 'Expected four files and a directory');
    check(
      source.largestRequest <= 64 * 1024,
      'Metadata request exceeded bound',
    );
    check(
      source.ranges.every(
        (r) => r.$1 + r.$2 <= 279 * 2048 || r.$1 >= 286 * 2048,
      ),
      'Open eagerly fetched original file contents',
    );
    final hashes = <String, String>{};
    for (final member in archive.members.where((entry) => entry.isFile)) {
      final expected = udfReferencePayloads[member.name];
      check(expected != null, 'Unexpected file ${member.name}');
      final bytes = await archive.readMember(member);
      check(
        sha256.convert(bytes).toString() == expected,
        'Buffered payload mismatch $name/${member.name}',
      );
      final streamed = <int>[];
      await for (final chunk in archive.openMember(member, chunkSize: 257)) {
        check(chunk.length <= 257, 'Stream did not preserve requested bound');
        streamed.addAll(chunk);
      }
      check(
        sha256.convert(streamed).toString() == expected,
        'Streamed payload mismatch $name/${member.name}',
      );
      check(bytes.length == member.size, 'Incorrect member size');
      hashes[member.name] = expected!;
    }
    await archive.close();
    check(source.closed, 'Successful archive leaked source');
    results[name] = hashes;
  }

  final offsetBacking = Uint8List(
    udfReferenceBytes('derived-fragmented').length + 17,
  );
  offsetBacking.setRange(
    9,
    offsetBacking.length - 8,
    udfReferenceBytes('derived-fragmented'),
  );
  final view = Uint8List.sublistView(
    offsetBacking,
    9,
    offsetBacking.length - 8,
  );
  final before = sha256.convert(offsetBacking).toString();
  final viewArchive = await openUdfArchive(
    koni.MemoryByteSource(view),
    maxMemberBytes: 1024 * 1024,
  );
  final payload = viewArchive.members.singleWhere(
    (m) => m.name == 'nested/payload.bin',
  );
  check(
    sha256.convert(await viewArchive.readMember(payload)).toString() ==
        udfReferencePayloads[payload.name],
    'Offset typed-data view lost data',
  );
  await viewArchive.close();
  check(
    sha256.convert(offsetBacking).toString() == before,
    'Reader changed its input',
  );

  for (final (at, label) in <(int, String)>[
    (256 * 2048 + 4, 'anchor tag checksum'),
    (32 * 2048 + 400, 'primary descriptor CRC'),
    (257 * 2048 + 420, 'file-set CRC'),
    (266 * 2048 + 180, 'file entry CRC'),
  ]) {
    final bytes = udfReferenceBytes('mastered-bridge');
    bytes[at] ^= 1;
    await rejects(bytes, label);
  }
  await rejects(
    Uint8List.sublistView(udfReferenceBytes('mastered-bridge'), 0, 256 * 2048),
    'truncated anchor',
  );

  final source = UdfReferenceSource(udfReferenceBytes('derived-fragmented'));
  final archive = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
  final member = archive.members.singleWhere(
    (m) => m.name == 'nested/payload.bin',
  );
  final readsBefore = source.reads;
  final prefix = await archive
      .openMember(member, chunkSize: 128)
      .take(1)
      .toList();
  check(
    prefix.length == 1 && prefix.single.length == 128,
    'Cancelled prefix length',
  );
  check(
    source.reads == readsBefore + 1,
    'Cancellation read beyond first chunk',
  );
  check(!source.closed, 'Cancelling one stream should retain archive source');
  await archive.close();

  final failing = UdfReferenceSource(
    udfReferenceBytes('mastered-bridge'),
    failAt: 32 * 2048,
  );
  var failed = false;
  try {
    await openUdfArchive(failing, maxMemberBytes: 1024 * 1024);
  } on ArchiveViewException {
    failed = true;
  }
  check(failed && failing.closed, 'Source failure must close and report');

  for (final revision in [0x102, 0x150, 0x200, 0x201]) {
    for (final allocation in ['short', 'long', 'embedded']) {
      final fixture = UdfFixture(
        revision: revision,
        allocation: allocation,
        extended: revision >= 0x200,
        fileName: 'caf\u00e9-\u96ea.txt',
      );
      final archive = await openUdfArchive(
        fixture.source(),
        maxMemberBytes: 65536,
      );
      check(
        archive.members.single.name == fixture.fileName,
        'Synthetic CS0 name differs',
      );
      check(
        sha256.convert(await archive.readMember(archive.members.single)) ==
            sha256.convert(fixture.payload),
        'Synthetic revision/allocation payload differs',
      );
      await archive.close();
    }
  }
  final distant = UdfFixture(partitionStart: 3000000000);
  final distantSource = distant.source();
  final distantArchive = await openUdfArchive(
    distantSource,
    maxMemberBytes: 65536,
  );
  check(
    sha256.convert(
          await distantArchive.readMember(distantArchive.members.single),
        ) ==
        sha256.convert(distant.payload),
    'Large physical offset lost payload bytes',
  );
  check(
    distantSource.reads.contains((6144000040960, distant.payload.length)),
    'Large physical offset was not exact',
  );
  await distantArchive.close();

  const logical = 8 * 1024 * 1024 * 1024;
  final sparse = UdfFixture();
  final entry = sparse.fileEntry;
  entry.fillRange(176, entry.length, 0);
  udfPut64(entry, 56, logical);
  udfPut32(entry, 172, 9 * 8);
  for (var index = 0; index < 9; index++) {
    udfShort(
      entry,
      176 + index * 8,
      index == 8 ? 16384 : 1073739776,
      0,
      kind: 2,
    );
  }
  udfRetag(entry, length: 176 + 9 * 8);
  final sparseSource = sparse.source();
  final sparseArchive = await openUdfArchive(
    sparseSource,
    maxMemberBytes: logical,
  );
  final sparseMember = sparseArchive.members.single;
  check(
    sparseMember.size == logical,
    'Eight GiB logical length lost high bits',
  );
  sparseSource.reads.clear();
  final sparsePrefix = await sparseArchive
      .openMember(sparseMember, maxBytes: logical, chunkSize: 17)
      .first;
  check(
    sparsePrefix.length == 17 && sparsePrefix.every((byte) => byte == 0),
    'Sparse prefix does not contain expected zeros',
  );
  check(
    sparseSource.reads.isEmpty,
    'Unallocated sparse extent accessed physical data',
  );
  var bufferRejected = false;
  try {
    await sparseArchive.readMember(sparseMember, maxBytes: logical);
  } on ArchiveViewException {
    bufferRejected = true;
  }
  check(
    bufferRejected,
    'Large logical file allowed an unbounded buffered read',
  );
  await sparseArchive.close();

  final pathFixture = UdfFixture();
  final pathPrefix = '雪' * 48;
  udfPut16(pathFixture.fileEntry, 48, 3);
  udfRetag(pathFixture.fileEntry);
  final childIdentifiers = Uint8List.fromList([
    ...udfFid(directoryBlock: 11, childBlock: 1),
    for (final name in ['a', 'b', 'c'])
      ...udfFid(directoryBlock: 11, childBlock: 2, name: name),
  ]);
  pathFixture.makeFile(
    3,
    type: 4,
    size: childIdentifiers.length,
    data: childIdentifiers,
    dataBlock: 11,
  );
  final rootIdentifiers = Uint8List.fromList([
    ...udfFid(directoryBlock: 10, childBlock: 1),
    ...udfFid(
      directoryBlock: 10,
      childBlock: 3,
      name: pathPrefix,
      isDirectory: true,
    ),
  ]);
  pathFixture.makeFile(
    1,
    type: 4,
    size: rootIdentifiers.length,
    data: rootIdentifiers,
    dataBlock: 10,
  );
  // 48 code units for the directory, plus three 50-unit hard-link paths.
  const exactPathBudget = 396;
  final acceptedPaths = pathFixture.source();
  final pathArchive = await openUdfArchive(
    acceptedPaths,
    maxMemberBytes: 65536,
    maxRetainedPathBytes: exactPathBudget,
  );
  check(
    pathArchive.members.map((member) => member.name).join('|') ==
        '$pathPrefix|$pathPrefix/a|$pathPrefix/b|$pathPrefix/c',
    'Exact aggregate full-path budget lost hard-link paths',
  );
  for (final entry in pathArchive.members.where((member) => member.isFile)) {
    check(
      sha256.convert(await pathArchive.readMember(entry)) ==
          sha256.convert(pathFixture.payload),
      'Path-limited hard-link payload differs',
    );
  }
  await pathArchive.close();
  check(acceptedPaths.closed, 'Exact-budget success leaked its source');
  final rejectedPaths = pathFixture.source();
  var pathBudgetRejected = false;
  try {
    final unexpected = await openUdfArchive(
      rejectedPaths,
      maxMemberBytes: 65536,
      maxRetainedPathBytes: exactPathBudget - 1,
    );
    await unexpected.close();
  } on ArchiveViewException catch (error) {
    pathBudgetRejected = error.message.contains(
      'Retained full-path text limit exceeded',
    );
  }
  check(
    pathBudgetRejected,
    'Aggregate path budget did not charge repeated ancestor prefixes',
  );
  check(rejectedPaths.closed, 'Path-budget rejection leaked its source');

  // ignore: avoid_print
  print(
    jsonEncode({
      'groups': 26,
      'checks': _checks,
      'independentImages': results,
      'malformedIndependentImagesRejected': 5,
      'sourceOwnership': true,
      'offsetViewsAndInputPreservation': true,
      'cancelledStreamPrefixBytes': 128,
      'syntheticRevisionAllocationProfiles': 12,
      'syntheticPhysicalOffset': 6144000040960,
      'syntheticLogicalSize': logical,
      'syntheticSparsePrefixBytes': 17,
      'aggregateFullPathBudgetBytes': exactPathBudget,
      'aggregateFullPathBudgetRejectsOneByteShort': true,
    }),
  );
}
