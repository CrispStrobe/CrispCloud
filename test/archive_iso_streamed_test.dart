import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';

class _SparseIsoSource implements koni.ByteSource {
  _SparseIsoSource(this.header, this.length, {this.payloads = const []});
  final Uint8List header;
  @override
  final int length;
  final List<(int, int)> payloads;
  final reads = <(int, int)>[];
  bool closed = false;
  bool truncateReads = false;
  int? poisonOffset;

  @override
  String get name => 'fixture.iso';

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closed) throw StateError('Closed test source.');
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw RangeError('Read leaves the test source.');
    }
    if (count > 256 * 1024) throw StateError('Unbounded inspection read.');
    for (final payload in payloads) {
      if (offset < payload.$1 + payload.$2 && offset + count > payload.$1) {
        throw StateError('Inspection read file payload data.');
      }
    }
    reads.add((offset, count));
    final result = Uint8List(truncateReads && count > 0 ? count - 1 : count);
    if (offset < header.length) {
      final available = header.length - offset;
      final take = available < result.length ? available : result.length;
      result.setRange(0, take, header, offset);
    }
    final poison = poisonOffset;
    if (poison != null && poison >= offset && poison - offset < result.length) {
      result[poison - offset] = 1;
    }
    return result;
  }

  @override
  Future<void> close() async => closed = true;
}

_SparseIsoSource _largeIso() {
  final fixture = IsoFixture();
  const payloadBytes = 2 * 1024 * 1024 * 1024 + 17;
  const payloadOffset = 40 * 2048;
  const imageBytes = ((payloadOffset + payloadBytes + 2047) ~/ 2048) * 2048;
  isoBoth32(fixture.bytes, 16 * 2048 + 80, imageBytes ~/ 2048);
  isoBoth32(fixture.bytes, fixture.fileRecordOffset + 2, payloadOffset ~/ 2048);
  isoBoth32(fixture.bytes, fixture.fileRecordOffset + 10, payloadBytes);
  fixture.bytes.fillRange(
    IsoFixture.fileSector * 2048,
    IsoFixture.fileSector * 2048 + 9,
    0,
  );
  return _SparseIsoSource(
    fixture.bytes,
    imageBytes,
    payloads: [
      (payloadOffset, payloadBytes),
      (IsoFixture.nestedFileSector * 2048, 10),
    ],
  );
}

void main() {
  test('read-only ISO viewing indexes metadata without scanning unclaimed image data', () async {
    final fixture = IsoFixture();
    const imageBytes = 80 * 1024 * 1024;
    isoBoth32(fixture.bytes, 16 * 2048 + 80, imageBytes ~/ 2048);
    final source = _SparseIsoSource(fixture.bytes, imageBytes)
      ..poisonOffset = imageBytes - 1;
    final opened = await openStreamedArchiveSource(
      source,
      name: 'large.iso',
      inspectIsoForRewrite: false,
    );
    addTearDown(opened.archive.close);
    expect(opened.policy.reason, isNotNull);
    expect(opened.policy.inspection, isNull);
    expect(opened.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
    expect(
      source.reads.every((read) => read.$1 + read.$2 <= fixture.bytes.length),
      isTrue,
    );
    expect(source.closed, isFalse);
    final member = opened.archive.members.singleWhere(
      (member) => member.name == 'HELLO.TXT',
    );
    expect(utf8.decode(await opened.archive.readMember(member)), 'hello iso');
    await opened.archive.close();
    expect(source.closed, isTrue);
  });

  test(
    'source ISO inspection matches buffered policy without reading payloads',
    () async {
      final fixture = IsoFixture(
        rockRidgeName: 'héllo.txt',
        rockRidgeContinuation: true,
      );
      final archive = await openIsoArchive(
        koni.MemoryByteSource(fixture.bytes),
        maxMemberBytes: kArchiveStreamingLimit,
      );
      addTearDown(archive.close);
      final buffered = await inspectIsoRewrite(fixture.bytes, archive);
      final source = _SparseIsoSource(
        fixture.bytes,
        fixture.bytes.length,
        payloads: [
          (IsoFixture.fileSector * 2048, 9),
          (IsoFixture.nestedFileSector * 2048, 10),
        ],
      );
      final streamed = await inspectIsoRewriteSource(source, archive);
      expect(streamed.reason, isNull);
      expect(streamed.container, buffered.container);
      expect(streamed.attributes, buffered.attributes);
      expect(source.closed, isFalse);
      expect(source.reads.every((read) => read.$2 <= 256 * 1024), isTrue);
      await source.close();
    },
  );

  test('a source and member above 2 GiB are inspected using only metadata and padding', () async {
    final source = _largeIso();
    final archive = await openIsoArchive(
      source,
      maxMemberBytes: kArchiveStreamingLimit,
    );
    addTearDown(archive.close);
    expect(archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
    expect(
      archive.members.singleWhere((member) => member.name == 'HELLO.TXT').size,
      2 * 1024 * 1024 * 1024 + 17,
    );
    source.reads.clear();
    final inspection = await inspectIsoRewriteSource(source, archive);
    expect(inspection.reason, isNull);
    expect(inspection.container['iso.profile'], 1);
    expect(
      source.reads.fold<int>(0, (sum, read) => sum + read.$2),
      lessThan(128 * 1024),
    );
    expect(
      source.reads.any((read) => read.$1 > 2 * 1024 * 1024 * 1024),
      isTrue,
    );
    expect(source.closed, isFalse);

    source.reads.clear();
    final bounded = await inspectIsoRewriteSource(
      source,
      archive,
      maxBytes: 2 * 1024 * 1024 * 1024,
    );
    expect(bounded.reason, contains('inspection limit'));
    expect(source.reads, isEmpty);
    await expectLater(
      archive.readMember(
        archive.members.firstWhere((member) => member.name == 'HELLO.TXT'),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'unmodeled nonzero data after a large payload keeps the image read-only',
    () async {
      final source = _largeIso();
      source.poisonOffset = source.length - 1;
      final archive = await openIsoArchive(
        source,
        maxMemberBytes: kArchiveStreamingLimit,
      );
      addTearDown(archive.close);
      final inspection = await inspectIsoRewriteSource(source, archive);
      expect(inspection.reason, contains('unmodeled data'));
      expect(
        inspection.reason,
        contains((source.length - 1).toRadixString(16)),
      );
    },
  );

  for (final variant in ['hybrid', 'boot', 'udf', 'application']) {
    test('streaming inspection retains the $variant image guard', () async {
      final fixture = IsoFixture();
      if (variant == 'hybrid') {
        fixture.bytes[0] = 0xeb;
      } else if (variant == 'boot' || variant == 'udf') {
        fixture.bytes.setRange(18 * 2048, 19 * 2048, fixture.bytes, 17 * 2048);
        fixture.bytes[17 * 2048] = 0;
        if (variant == 'udf') {
          fixture.bytes.setAll(17 * 2048 + 1, [0x42, 0x45, 0x41, 0x30, 0x31]);
        }
      } else {
        fixture.bytes[16 * 2048 + 900] = 1;
      }
      // Supply the independently readable original tree when an unsupported
      // descriptor also prevents the browsing reader from opening the image.
      final archive = await openIsoArchive(
        koni.MemoryByteSource(IsoFixture().bytes),
        maxMemberBytes: kArchiveStreamingLimit,
      );
      addTearDown(archive.close);
      final source = _SparseIsoSource(fixture.bytes, fixture.bytes.length);
      final inspection = await inspectIsoRewriteSource(source, archive);
      expect(inspection.supported, isFalse);
      expect(source.closed, isFalse);
      await source.close();
    });
  }

  test('inspection cancellation throws and retains caller ownership', () async {
    final source = _largeIso();
    final archive = await openIsoArchive(
      source,
      maxMemberBytes: kArchiveStreamingLimit,
    );
    addTearDown(archive.close);
    var checks = 0;
    await expectLater(
      inspectIsoRewriteSource(
        source,
        archive,
        isCancelled: () => ++checks >= 5,
      ),
      throwsA(
        isA<ArchiveViewException>().having(
          (error) => error.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
    expect(source.closed, isFalse);
    expect((await inspectIsoRewriteSource(source, archive)).supported, isTrue);
  });

  test(
    'short metadata reads are refused without closing the borrowed source',
    () async {
      final fixture = IsoFixture();
      final archive = await openIsoArchive(
        koni.MemoryByteSource(fixture.bytes),
        maxMemberBytes: kArchiveStreamingLimit,
      );
      addTearDown(archive.close);
      final source = _SparseIsoSource(fixture.bytes, fixture.bytes.length)
        ..truncateReads = true;
      expect(
        (await inspectIsoRewriteSource(source, archive)).reason,
        contains('truncated'),
      );
      expect(source.closed, isFalse);
      await source.close();
    },
  );

  test(
    'the ISO writer plans a member above 2 GiB without collecting its bytes',
    () async {
      const marker = 'payload stream reached';
      var metadataBytes = 0;
      await expectLater(
        writeIsoArchive(
          [
            ArchiveWriteEntry(
              path: 'large.bin',
              isDirectory: false,
              size: 2 * 1024 * 1024 * 1024 + 17,
              readChunks: () async* {
                throw StateError(marker);
              },
            ),
          ],
          maxOutputBytes: kArchiveStreamingLimit,
          sink: (chunk) async {
            metadataBytes += chunk.length;
          },
        ),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', marker),
        ),
      );
      expect(metadataBytes, greaterThan(16 * 2048));
      expect(metadataBytes, lessThan(128 * 1024));
    },
  );

  test('single-extent member and total output bounds still preflight before writes', () async {
    var writes = 0, reads = 0;
    ArchiveWriteEntry entry(String path, int size) => ArchiveWriteEntry(
      path: path,
      isDirectory: false,
      size: size,
      readChunks: () {
        reads++;
        return const Stream.empty();
      },
    );
    for (final entries in [
      [entry('over-4g.bin', kArchiveIsoSingleExtentLimit + 1)],
      [
        for (var index = 0; index < 3; index++)
          entry('three-g-$index.bin', 3 * 1024 * 1024 * 1024),
      ],
    ]) {
      await expectLater(
        writeIsoArchive(
          entries,
          maxOutputBytes: kArchiveStreamingLimit,
          sink: (_) async {
            writes++;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    }
    expect(writes, 0);
    expect(reads, 0);
  });

  test('candidate proof retains auxiliary metadata while allowing intentional edits', () async {
    final fixture = IsoFixture(
      rockRidgeName: 'retained.txt',
      rockRidgeContinuation: true,
    );
    final original = await openIsoArchive(
      koni.MemoryByteSource(fixture.bytes),
      maxMemberBytes: kArchiveStreamingLimit,
    );
    addTearDown(original.close);
    final source = await inspectIsoRewrite(fixture.bytes, original);
    expect(source.supported, isTrue);
    final renamed = 'renamed-${'é' * 190}-🌍.txt';
    final changedTime = DateTime.utc(2026, 11, 13, 4, 5, 6);
    final entries = [
      for (final member in original.members)
        ArchiveWriteEntry(
          path: member.name == 'retained.txt' ? renamed : member.name,
          isDirectory: !member.isFile,
          size: member.size,
          modified: member.name == 'retained.txt'
              ? changedTime
              : member.modified,
          mode: member.name == 'retained.txt' ? 0x8180 : member.posixMode,
          attributes: source.attributes[member.name]!,
          readChunks: member.isFile ? () => original.openMember(member) : null,
        ),
    ];
    final candidate = await collectArchiveWrite(
      (sink) => writeIsoArchive(entries, source: source, sink: sink),
    );
    final opened = await openIsoArchive(
      koni.MemoryByteSource(candidate),
      maxMemberBytes: kArchiveStreamingLimit,
    );
    addTearDown(opened.close);
    final actual = await inspectIsoRewrite(candidate, opened);
    expect(actual.supported, isTrue);
    expect(actual.attributes[renamed]?['iso.uid'], 1000);
    expect(actual.attributes[renamed]?['iso.gid'], 1000);
    expect(
      opened.members.singleWhere((member) => member.name == renamed).modified,
      changedTime,
    );
    var reads = 0;
    final metadataOnly = [
      for (final entry in entries)
        ArchiveWriteEntry(
          path: entry.path,
          isDirectory: entry.isDirectory,
          size: entry.size,
          modified: entry.modified,
          mode: entry.mode,
          attributes: entry.attributes,
          readChunks: entry.isDirectory
              ? null
              : () {
                  reads++;
                  throw StateError('Metadata proof must not read payloads.');
                },
        ),
    ];
    expect(
      () => verifyIsoRewritePreservation(metadataOnly, actual, source: source),
      returnsNormally,
    );
    expect(reads, 0);

    for (final key in [
      'iso.uid',
      'iso.gid',
      'iso.flags',
      'iso.serial',
      'iso.tf',
      'iso.jolietMetadata',
    ]) {
      final attributes = {
        for (final item in actual.attributes.entries)
          item.key: Map<String, Object?>.of(item.value),
      };
      final target = attributes[renamed]!;
      if (key == 'iso.tf') {
        final time = base64.decode(target[key] as String);
        time[10] = (time[10] + 1) % 60;
        target[key] = base64.encode(time);
      } else if (key == 'iso.jolietMetadata') {
        final alternate = Map<String, Object?>.from(target[key] as Map);
        alternate['iso.flags'] = ((alternate['iso.flags'] as int) ^ 1);
        target[key] = alternate;
      } else {
        target[key] = (target[key] as int) + 1;
      }
      final changed = ArchiveRewriteInspection(
        container: actual.container,
        attributes: attributes,
      );
      expect(
        () =>
            verifyIsoRewritePreservation(metadataOnly, changed, source: source),
        throwsA(isA<ArchiveViewException>()),
        reason: '$key must not be silently altered',
      );
    }
    final changedRoot = Map<String, Object?>.from(
      actual.container['iso.root'] as Map,
    );
    changedRoot['iso.uid'] = (changedRoot['iso.uid'] as int) + 1;
    expect(
      () => verifyIsoRewritePreservation(
        metadataOnly,
        ArchiveRewriteInspection(
          container: {...actual.container, 'iso.root': changedRoot},
          attributes: actual.attributes,
        ),
        source: source,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final changedVolume = base64.decode(
      actual.container['iso.volume'] as String,
    );
    changedVolume[40] = changedVolume[40] == 0x41 ? 0x42 : 0x41;
    expect(
      () => verifyIsoRewritePreservation(
        metadataOnly,
        ArchiveRewriteInspection(
          container: {
            ...actual.container,
            'iso.volume': base64.encode(changedVolume),
          },
          attributes: actual.attributes,
        ),
        source: source,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(reads, 0);
  });
}
