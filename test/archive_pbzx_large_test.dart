import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_pbzx_source.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

typedef _Segment = ({int offset, Uint8List bytes});
typedef _Range = ({int offset, int length});

/// Stores only headers and the small file; all missing ranges are sparse zeros.
/// It refuses oversized reads before allocating, so a full-container fallback
/// fails the test instead of allocating the synthetic large payload.
class _SparseSource implements koni.ByteSource {
  _SparseSource(this.length, this.segments);

  @override
  final int length;
  final List<_Segment> segments;
  final reads = <_Range>[];
  var closes = 0;

  @override
  String get name => 'Payload';

  int get retainedFixtureBytes =>
      segments.fold(0, (sum, segment) => sum + segment.bytes.length);

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closes != 0) throw StateError('Read after close');
    if (offset < 0 ||
        length < 0 ||
        offset > this.length ||
        length > this.length - offset) {
      throw StateError('Read outside the sparse source');
    }
    if (length > kPbzxChunkLimit) {
      throw StateError('Attempted a read larger than one 16 MiB PBZX chunk');
    }
    reads.add((offset: offset, length: length));
    final output = Uint8List(length);
    for (final segment in segments) {
      final start = math.max(offset, segment.offset);
      final end = math.min(
        offset + length,
        segment.offset + segment.bytes.length,
      );
      if (start < end) {
        output.setRange(
          start - offset,
          end - offset,
          segment.bytes,
          start - segment.offset,
        );
      }
    }
    return output;
  }

  @override
  Future<void> close() async {
    // Intentionally count every call: the returned archive must own this
    // source once even when the consumer closes its handle repeatedly.
    closes++;
  }
}

Uint8List _newcHeader(String name, int size, {int inode = 1}) {
  final encodedName = [...utf8.encode(name), 0];
  final fields = [
    inode,
    name == 'TRAILER!!!' ? 0 : 0x81a4,
    0,
    0,
    1,
    1700000000,
    size,
    0,
    0,
    0,
    0,
    encodedName.length,
    0,
  ];
  final header = BytesBuilder()
    ..add(
      ascii.encode(
        '070701${fields.map((f) => f.toRadixString(16).padLeft(8, '0')).join()}',
      ),
    )
    ..add(encodedName);
  while (header.length % 4 != 0) {
    header.addByte(0);
  }
  return header.takeBytes();
}

int _align4(int value) => (value + 3) ~/ 4 * 4;

({_SparseSource source, List<_Range> payloadChunks}) _storedPbzx(
  int decodedLength,
  List<_Segment> decodedSegments,
) {
  final header = ByteData(12)
    ..setUint32(0, 0x70627a78)
    ..setUint64(4, kPbzxChunkLimit);
  final segments = <_Segment>[(offset: 0, bytes: header.buffer.asUint8List())];
  final payloadChunks = <_Range>[];
  var packedOffset = 12;
  for (
    var decodedOffset = 0;
    decodedOffset < decodedLength;
    decodedOffset += kPbzxChunkLimit
  ) {
    final count = math.min(kPbzxChunkLimit, decodedLength - decodedOffset);
    final record = ByteData(16)
      ..setUint64(0, count)
      ..setUint64(8, count);
    segments.add((offset: packedOffset, bytes: record.buffer.asUint8List()));
    final payloadOffset = packedOffset + 16;
    payloadChunks.add((offset: payloadOffset, length: count));
    for (final segment in decodedSegments) {
      final start = math.max(decodedOffset, segment.offset);
      final end = math.min(
        decodedOffset + count,
        segment.offset + segment.bytes.length,
      );
      if (start < end) {
        segments.add((
          offset: payloadOffset + start - decodedOffset,
          bytes: Uint8List.sublistView(
            segment.bytes,
            start - segment.offset,
            end - segment.offset,
          ),
        ));
      }
    }
    packedOffset = payloadOffset + count;
  }
  return (
    source: _SparseSource(packedOffset, segments),
    payloadChunks: payloadChunks,
  );
}

bool _overlap(_Range a, _Range b) =>
    a.length > 0 &&
    b.length > 0 &&
    a.offset < b.offset + b.length &&
    b.offset < a.offset + a.length;

void main() {
  test('PBZX lists a 65 MiB member and reads a later file without scanning its body', () async {
    const largeSize = 65 * 1024 * 1024 + 333;
    final largeHeader = _newcHeader('huge.bin', largeSize);
    final smallBytes = Uint8List.fromList(
      utf8.encode('Readable after a large member.\n'),
    );
    final smallOffset = _align4(largeHeader.length + largeSize);
    final smallHeader = _newcHeader('after.txt', smallBytes.length, inode: 2);
    final smallDataOffset = smallOffset + smallHeader.length;
    final trailerOffset = _align4(smallDataOffset + smallBytes.length);
    final trailer = _newcHeader('TRAILER!!!', 0, inode: 3);
    final fixture = _storedPbzx(trailerOffset + trailer.length, [
      (offset: 0, bytes: largeHeader),
      (offset: smallOffset, bytes: smallHeader),
      (offset: smallDataOffset, bytes: smallBytes),
      (offset: trailerOffset, bytes: trailer),
    ]);
    final source = fixture.source;
    expect(source.length, greaterThan(kArchiveReadLimit));
    expect(source.retainedFixtureBytes, lessThan(1024));
    expect(fixture.payloadChunks.length, 5);

    final archive = await openViewerArchiveSource(
      source,
      name: 'Payload',
      maxBufferedContainerBytes: 1024 * 1024,
    );
    addTearDown(archive.close);
    expect(archive.formatName, 'pbzx/cpio');
    expect(archive.members.map((member) => member.name), [
      'huge.bin',
      'after.txt',
    ]);
    final large = archive.members.first;
    final small = archive.members.last;
    expect(large.size, largeSize);
    expect(large.isFile, isTrue);
    expect(small.size, smallBytes.length);

    final readsAfterListing = source.reads.length;
    await expectLater(
      archive.readMember(large),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(
      source.reads.length,
      readsAfterListing,
      reason: 'the normal 64 MiB member limit applies before a body read',
    );
    expect(await archive.readMember(small), smallBytes);
    final readsAfterSmall = source.reads.length;
    expect(await archive.readMember(small), smallBytes);
    expect(
      source.reads.length,
      readsAfterSmall,
      reason: 'repeated small reads reuse the final chunk cache',
    );

    // Chunks 1 through 3 contain only the middle of huge.bin. Opening,
    // listing and the later member read may touch the first/last chunk,
    // but must not even fetch a byte of those intervening payload ranges.
    for (final interior in fixture.payloadChunks.skip(1).take(3)) {
      expect(
        source.reads.any((read) => _overlap(read, interior)),
        isFalse,
        reason: 'interior large-member chunks must remain unread',
      );
    }
    expect(
      source.reads.every((read) => read.length <= kPbzxChunkLimit),
      isTrue,
    );
    expect(source.closes, 0);
    await archive.close();
    await archive.close();
    expect(source.closes, 1);
  });

  test(
    'PBZX rejects a decoded total above 2 GiB before reading data',
    () async {
      final header = ByteData(12)
        ..setUint32(0, 0x70627a78)
        ..setUint64(4, kPbzxChunkLimit);
      final segments = <_Segment>[
        (offset: 0, bytes: header.buffer.asUint8List()),
      ];
      final payloads = <_Range>[];
      // This deliberately hostile framing declares 129 full decoded chunks.
      // One-byte stored bodies must never reach an XZ decoder: the aggregate
      // declaration alone exceeds the safety limit while indexing the stream.
      const chunkCount = 129;
      for (var index = 0; index < chunkCount; index++) {
        final offset = 12 + index * 17;
        final record = ByteData(16)
          ..setUint64(0, kPbzxChunkLimit)
          ..setUint64(8, 1);
        segments.add((offset: offset, bytes: record.buffer.asUint8List()));
        payloads.add((offset: offset + 16, length: 1));
      }
      final source = _SparseSource(12 + chunkCount * 17, segments);
      await expectLater(
        ArchivePbzxSource.open(source),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.message,
            'message',
            contains('decoded-size safety limit'),
          ),
        ),
      );
      expect(source.closes, 1);
      expect(source.reads.every((read) => read.length <= 16), isTrue);
      expect(
        payloads.any(
          (payload) => source.reads.any((read) => _overlap(read, payload)),
        ),
        isFalse,
      );
    },
  );
}
