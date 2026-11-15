import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_png_carving_service.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/png_carving_fixture.dart';

void main() {
  Future<ArchivePngCarvingReport> scan(Uint8List bytes) =>
      scanArchivePngCarving(koni.MemoryByteSource(bytes, name: 'disk.img'));

  test(
    'finds embedded images and preserves exact source ranges and hashes',
    () async {
      final bytes = pngCarvingWorkflowFixture();
      final original = Uint8List.fromList(bytes);
      final report = await scan(bytes);
      expect(report.stopReason, ArchivePngCarvingStopReason.endOfInput);
      expect(report.scannedBytes, bytes.length);
      expect(report.sourceSha256, sha256.convert(bytes).toString());
      expect(report.recoverableCandidates, hasLength(2));
      expect(report.candidates.first.offset, 17);
      for (final candidate in report.candidates) {
        expect(
          candidate.sha256,
          sha256
              .convert(bytes.sublist(candidate.offset, candidate.endOffset))
              .toString(),
        );
        expect(candidate.reason, isNull);
      }
      expect(bytes, original);
      expect(() => report.candidates.clear(), throwsUnsupportedError);
    },
  );

  for (final color in [0, 2, 4, 6]) {
    test(
      'validates all five filter codes for 8-bit color type $color',
      () async {
        final channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]!;
        final input = pngCarvingPng(
          width: 1,
          height: 5,
          colorType: color,
          rawScanlines: [
            for (var filter = 0; filter <= 4; filter++) ...[
              filter,
              ...List.filled(channels, 23),
            ],
          ],
        );
        final report = await scan(input);
        expect(report.recoverableCandidates, hasLength(1));
      },
    );
  }

  for (final split in [0, 1, 2, 3, 5, 8]) {
    test(
      'accepts consecutive IDAT chunks split at compressed offset $split',
      () async {
        final report = await scan(pngCarvingPng(splitIdatAt: split));
        expect(report.recoverableCandidates, hasLength(1));
      },
    );
  }

  test('signature crossing a 64 KiB source-read boundary is found', () async {
    final input = pngCarvingJoin([
      List.filled(65533, 4),
      pngCarvingPng(),
      [7],
    ]);
    final report = await scan(input);
    expect(report.recoverableCandidates.single.offset, 65533);
  });

  test(
    'valid candidate after bad CRC and truncated candidates remains available',
    () async {
      final broken = pngCarvingPng()..[29] ^= 1;
      final truncated = pngCarvingPng().sublist(0, 42);
      final last = pngCarvingPng(colorType: 0);
      final report = await scan(
        pngCarvingJoin([
          broken,
          [5, 6],
          truncated,
          [8, 9],
          last,
        ]),
      );
      expect(report.candidates, hasLength(3));
      expect(
        report.candidates.first.reason,
        ArchivePngCarvingReason.checksumMismatch,
      );
      expect(report.candidates[1].isRecoverable, isFalse);
      expect(report.recoverableCandidates, hasLength(1));
      expect(report.candidates.last.size, last.length);
    },
  );

  test(
    'nested PNG signature inside validated PNG is excluded from selection',
    () async {
      // tEXt itself cannot contain NUL; a nested signature can still occur in
      // stored IDAT data. Filter/pixel bytes hold a complete smaller PNG.
      final nested = pngCarvingPng(width: 1, height: 1, colorType: 0);
      final raw = [0, ...nested];
      final outer = pngCarvingPng(
        width: nested.length,
        height: 1,
        colorType: 0,
        compressed: _storedZlib(raw),
      );
      final report = await scan(outer);
      expect(report.recoverableCandidates, hasLength(1));
      expect(report.candidates, hasLength(2));
      expect(
        report.candidates.last.reason,
        ArchivePngCarvingReason.overlappingCandidate,
      );
      await expectLater(
        recoverArchivePngCarving(
          report,
          selectedOffsets: {report.candidates.last.offset},
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  for (final (name, bytes, reason)
      in <(String, Uint8List, ArchivePngCarvingReason)>[
        (
          'indexed',
          pngCarvingPng(colorType: 3),
          ArchivePngCarvingReason.indexedColor,
        ),
        (
          'interlaced',
          pngCarvingPng(interlace: 1),
          ArchivePngCarvingReason.interlaced,
        ),
        (
          '16-bit',
          pngCarvingPng(bitDepth: 16),
          ArchivePngCarvingReason.bitDepth,
        ),
        (
          'animation',
          pngCarvingPng(
            beforeData: [pngCarvingChunk('acTL', List.filled(8, 0))],
          ),
          ArchivePngCarvingReason.animation,
        ),
        (
          'unknown ancillary',
          pngCarvingPng(
            beforeData: [
              pngCarvingChunk('vpAg', [1]),
            ],
          ),
          ArchivePngCarvingReason.unsupportedChunk,
        ),
        (
          'unknown critical',
          pngCarvingPng(
            beforeData: [
              pngCarvingChunk('ABCD', [1]),
            ],
          ),
          ArchivePngCarvingReason.unsupportedChunk,
        ),
        (
          'compressed text',
          pngCarvingPng(
            beforeData: [
              pngCarvingChunk('zTXt', [1]),
            ],
          ),
          ArchivePngCarvingReason.unsupportedChunk,
        ),
      ]) {
    test(
      'classifies $name as unsupported and keeps later supported images',
      () async {
        final report = await scan(pngCarvingJoin([bytes, pngCarvingPng()]));
        expect(
          report.candidates.first.status,
          ArchivePngCarvingStatus.unsupported,
        );
        expect(report.candidates.first.reason, reason);
        expect(report.recoverableCandidates, hasLength(1));
      },
    );
  }

  for (final (name, chunks, reason)
      in <(String, List<List<int>>, ArchivePngCarvingReason)>[
        (
          'IDAT first',
          [pngCarvingChunk('IDAT', [])],
          ArchivePngCarvingReason.chunkOrder,
        ),
        (
          'duplicate IHDR',
          [
            pngCarvingChunk('IHDR', pngCarvingHeader()),
            pngCarvingChunk('IHDR', pngCarvingHeader()),
          ],
          ArchivePngCarvingReason.chunkOrder,
        ),
        (
          'IEND without data',
          [
            pngCarvingChunk('IHDR', pngCarvingHeader()),
            pngCarvingChunk('IEND', []),
          ],
          ArchivePngCarvingReason.chunkOrder,
        ),
        (
          'invalid reserved bit',
          [
            pngCarvingChunk('IHDR', pngCarvingHeader()),
            pngCarvingChunk('abca', []),
          ],
          ArchivePngCarvingReason.invalidChunk,
        ),
        (
          'zero dimension',
          [pngCarvingChunk('IHDR', pngCarvingHeader(width: 0))],
          ArchivePngCarvingReason.invalidHeader,
        ),
        (
          'invalid color type',
          [pngCarvingChunk('IHDR', pngCarvingHeader(colorType: 5))],
          ArchivePngCarvingReason.invalidHeader,
        ),
        (
          'invalid bit depth',
          [pngCarvingChunk('IHDR', pngCarvingHeader(bitDepth: 4))],
          ArchivePngCarvingReason.invalidHeader,
        ),
        (
          'huge dimensions',
          [pngCarvingChunk('IHDR', pngCarvingHeader(width: 0x7fffffff))],
          ArchivePngCarvingReason.limitExceeded,
        ),
        (
          'bad CRC',
          [pngCarvingChunk('IHDR', pngCarvingHeader(), crc: 0)],
          ArchivePngCarvingReason.checksumMismatch,
        ),
      ]) {
    test('rejects $name', () async {
      final report = await scan(
        pngCarvingJoin([pngCarvingSignature, ...chunks]),
      );
      expect(report.candidates.single.status, ArchivePngCarvingStatus.rejected);
      expect(report.candidates.single.reason, reason);
    });
  }

  test('declared chunk length cannot read outside source', () async {
    final chunk = pngCarvingChunk('IDAT', [1]);
    ByteData.sublistView(chunk).setUint32(0, 0x7fffffff, Endian.big);
    final report = await scan(
      pngCarvingJoin([
        pngCarvingSignature,
        pngCarvingChunk('IHDR', pngCarvingHeader()),
        chunk,
      ]),
    );
    expect(report.candidates.single.reason, ArchivePngCarvingReason.truncated);
  });

  test('nonconsecutive IDAT chunks are rejected', () async {
    final report = await scan(
      pngCarvingJoin([
        pngCarvingSignature,
        pngCarvingChunk('IHDR', pngCarvingHeader()),
        pngCarvingChunk('IDAT', [0x78]),
        pngCarvingChunk('tEXt', [65, 0, 66]),
        pngCarvingChunk('IDAT', [1]),
        pngCarvingChunk('IEND', []),
      ]),
    );
    expect(report.candidates.single.reason, ArchivePngCarvingReason.chunkOrder);
  });

  test('valid standard ancillary structures retain original bytes', () async {
    final input = pngCarvingPng(
      beforeData: [
        pngCarvingChunk('gAMA', [0, 0, 177, 143]),
        pngCarvingChunk(
          'cHRM',
          _be32([31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000]),
        ),
        pngCarvingChunk('sRGB', [0]),
        pngCarvingChunk('sBIT', [8, 8, 8]),
        pngCarvingChunk('PLTE', [255, 0, 0]),
        pngCarvingChunk('bKGD', [0, 255, 0, 0, 0, 0]),
        pngCarvingChunk('tRNS', [0, 255, 0, 0, 0, 0]),
        pngCarvingChunk('pHYs', [
          ..._be32([3780, 3780]),
          1,
        ]),
      ],
      afterData: [
        pngCarvingChunk('tIME', [7, 234, 11, 15, 7, 15, 59]),
        pngCarvingChunk('tEXt', [65, 0, 66]),
        pngCarvingChunk('tEXt', [67, 0, 68]),
      ],
    );
    expect((await scan(input)).recoverableCandidates, hasLength(1));
  });

  for (final (name, chunk, after) in <(String, Uint8List, bool)>[
    ('gamma after IDAT', pngCarvingChunk('gAMA', [0, 0, 177, 143]), true),
    (
      'bad pHYs unit',
      pngCarvingChunk('pHYs', [...List.filled(8, 0), 2]),
      false,
    ),
    ('invalid time', pngCarvingChunk('tIME', [7, 234, 2, 30, 0, 0, 0]), false),
    ('invalid text keyword', pngCarvingChunk('tEXt', [32, 65, 0, 66]), false),
    ('embedded text NUL', pngCarvingChunk('tEXt', [65, 0, 66, 0]), false),
    ('invalid significant bits', pngCarvingChunk('sBIT', [8, 0, 8]), false),
  ]) {
    test('rejects $name', () async {
      final report = await scan(
        pngCarvingPng(
          beforeData: after ? [] : [chunk],
          afterData: after ? [chunk] : [],
        ),
      );
      expect(report.recoverableCandidates, isEmpty);
    });
  }

  final raw = [0, 1, 2, 3];
  final compressed = Uint8List.fromList(const codecs.ZLibEncoder().encode(raw));
  for (final (name, packed, reason)
      in <(String, List<int>, ArchivePngCarvingReason)>[
        (
          'bad header',
          [0, ...compressed.sublist(1)],
          ArchivePngCarvingReason.invalidZlib,
        ),
        (
          'bad Adler',
          [
            ...compressed.sublist(0, compressed.length - 1),
            compressed.last ^ 1,
          ],
          ArchivePngCarvingReason.invalidZlib,
        ),
        (
          'truncated deflate',
          [
            ...compressed.sublist(0, 3),
            ...compressed.sublist(compressed.length - 4),
          ],
          ArchivePngCarvingReason.invalidZlib,
        ),
        (
          'trailing deflate bytes',
          [
            ...compressed.sublist(0, compressed.length - 4),
            0,
            0,
            ...compressed.sublist(compressed.length - 4),
          ],
          ArchivePngCarvingReason.invalidZlib,
        ),
        (
          'concatenated zlib streams',
          [...compressed, ...compressed],
          ArchivePngCarvingReason.invalidZlib,
        ),
        (
          'too little decoded data',
          const codecs.ZLibEncoder().encode([0, 1]),
          ArchivePngCarvingReason.scanlineSize,
        ),
        (
          'too much decoded data',
          const codecs.ZLibEncoder().encode([0, 1, 2, 3, 4]),
          ArchivePngCarvingReason.scanlineSize,
        ),
        (
          'invalid filter',
          const codecs.ZLibEncoder().encode([5, 1, 2, 3]),
          ArchivePngCarvingReason.invalidFilter,
        ),
      ]) {
    test('rejects $name even with valid chunk CRC and IEND', () async {
      final report = await scan(
        pngCarvingPng(width: 1, height: 1, compressed: packed),
      );
      expect(report.candidates.single.reason, reason);
      expect(report.recoverableCandidates, isEmpty);
    });
  }

  test('smaller declared zlib window is explicit unsupported', () async {
    final packed = Uint8List.fromList(compressed);
    packed[0] = 0x68;
    packed[1] = 0;
    while ((packed[0] * 256 + packed[1]) % 31 != 0) {
      packed[1]++;
    }
    final report = await scan(
      pngCarvingPng(width: 1, height: 1, compressed: packed),
    );
    expect(
      report.candidates.single.status,
      ArchivePngCarvingStatus.unsupported,
    );
    expect(
      report.candidates.single.reason,
      ArchivePngCarvingReason.unsupportedCompression,
    );
  });

  test('caps candidates and reports exact unscanned suffix', () async {
    final bytes = pngCarvingWorkflowFixture();
    final report = await scanArchivePngCarving(
      koni.MemoryByteSource(bytes),
      maxCandidates: 1,
    );
    expect(report.candidates, hasLength(1));
    expect(report.stopReason, ArchivePngCarvingStopReason.candidateLimit);
    expect(report.scannedBytes, greaterThan(report.candidates.first.endOffset));
    expect(report.scannedBytes, lessThan(bytes.length));
    final result = await recoverArchivePngCarving(
      report,
      selectedOffsets: {report.candidates.first.offset},
    );
    final archive = codecs.ZipDecoder().decodeBytes(result.bytes, verify: true);
    final json = jsonDecode(
      utf8.decode(archive.find('recovery-report.json')!.readBytes()!),
    ) as Map;
    expect((json['unscannedRanges'] as List).single, {
      'start': report.scannedBytes,
      'endExclusive': bytes.length,
    });
  });

  test(
    'caps global parsing work and preserves earlier verified candidates',
    () async {
      final first = pngCarvingPng();
      final report = await scanArchivePngCarving(
        koni.MemoryByteSource(pngCarvingJoin([first, first])),
        maxChunks: 3,
      );
      expect(report.stopReason, ArchivePngCarvingStopReason.workLimit);
      expect(report.recoverableCandidates, hasLength(1));
      expect(
        report.candidates.last.reason,
        ArchivePngCarvingReason.limitExceeded,
      );
    },
  );

  test('caps expanded bytes across all candidates', () async {
    final first = pngCarvingPng();
    final report = await scanArchivePngCarving(
      koni.MemoryByteSource(pngCarvingJoin([first, first])),
      maxExpandedBytes: 14,
    );
    expect(report.stopReason, ArchivePngCarvingStopReason.workLimit);
    expect(report.recoverableCandidates, hasLength(1));
  });

  test('caps validation bytes independently of source length', () async {
    final report = await scanArchivePngCarving(
      koni.MemoryByteSource(pngCarvingPng()),
      maxValidationBytes: 1,
    );
    expect(report.stopReason, ArchivePngCarvingStopReason.workLimit);
    expect(report.recoverableCandidates, isEmpty);
  });

  test('source and image allocation limits cannot be raised', () async {
    for (final sourceLimit in [0, -1, kArchiveReadLimit + 1]) {
      await expectLater(
        scanArchivePngCarving(
          koni.MemoryByteSource(Uint8List(0)),
          maxSourceBytes: sourceLimit,
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      scanArchivePngCarving(
        koni.MemoryByteSource(pngCarvingPng()),
        maxSourceBytes: 8,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final report = await scanArchivePngCarving(
      koni.MemoryByteSource(pngCarvingPng()),
      maxImageBytes: 40,
    );
    expect(
      report.candidates.single.reason,
      ArchivePngCarvingReason.limitExceeded,
    );
  });

  test(
    'copies source, freezes selection, and independently verifies ZIP report',
    () async {
      final input = pngCarvingWorkflowFixture();
      final report = await scan(input);
      final chosen = report.recoverableCandidates.last;
      final png = input.sublist(chosen.offset, chosen.endOffset);
      input.fillRange(0, input.length, 0);
      final selected = {chosen.offset};
      var checkpoints = 0;
      final result = await recoverArchivePngCarving(
        report,
        selectedOffsets: selected,
        checkpoint: () async {
          if (checkpoints++ == 0) {
            selected.clear();
          }
        },
      );
      final archive = codecs.ZipDecoder().decodeBytes(
        result.bytes,
        verify: true,
      );
      expect(archive.map((f) => f.name), [chosen.name, 'recovery-report.json']);
      expect(archive.first.readBytes(), png);
      final json = jsonDecode(utf8.decode(archive.last.readBytes()!)) as Map;
      expect(json['sourceSha256'], report.sourceSha256);
      expect(
        (json['candidates'] as List).where((c) => c['selected'] == true).length,
        1,
      );
      expect(json['unreadableRanges'], isEmpty);
      expect(result.sha256, sha256.convert(result.bytes).toString());
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
      expect(() => result.candidates.clear(), throwsUnsupportedError);
    },
  );

  test('rejects empty, unknown and unvalidated selections', () async {
    final report = await scan(
      pngCarvingJoin([pngCarvingPng(interlace: 1), pngCarvingPng()]),
    );
    for (final selected in <Set<int>>[
      {},
      {-1},
      {0},
    ]) {
      await expectLater(
        recoverArchivePngCarving(report, selectedOffsets: selected),
        throwsA(isA<ArchiveViewException>()),
      );
    }
  });

  test('bounds ZIP output including machine-readable report', () async {
    final report = await scan(pngCarvingPng());
    await expectLater(
      recoverArchivePngCarving(
        report,
        selectedOffsets: {0},
        maxOutputBytes: report.sourceBytes + 100,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'empty input and ordinary bytes yield an empty complete report',
    () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List(100),
      ]) {
        final report = await scan(bytes);
        expect(report.candidates, isEmpty);
        expect(report.scannedBytes, bytes.length);
        expect(report.stopReason, ArchivePngCarvingStopReason.endOfInput);
      }
    },
  );

  test(
    'propagates unreadable sources without returning a partial report',
    () async {
      final source = _FaultSource(
        pngCarvingJoin([List.filled(65533, 4), pngCarvingPng()]),
        failRead: 2,
      );
      await expectLater(
        scanArchivePngCarving(source),
        throwsA(isA<StateError>()),
      );
      expect(source.closed, isFalse);
    },
  );

  test('rejects short reads and source-length changes', () async {
    for (final source in [
      _FaultSource(pngCarvingPng(), shortRead: true),
      _FaultSource(pngCarvingPng(), changeLength: true),
    ]) {
      await expectLater(
        scanArchivePngCarving(source),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closed, isFalse);
    }
  });

  test('source validation failures do not publish a report', () async {
    var checks = 0;
    await expectLater(
      scanArchivePngCarving(
        koni.MemoryByteSource(pngCarvingPng()),
        validateUnchanged: () {
          if (++checks == 2) throw StateError('source replaced');
        },
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('cancels between capture reads', () async {
    var cancelled = false;
    await expectLater(
      scanArchivePngCarving(
        koni.MemoryByteSource(
          pngCarvingJoin([List.filled(70000, 4), pngCarvingPng()]),
        ),
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<ArchivePngCarvingCancelled>()),
    );
  });

  test('cancels during PNG validation and during ZIP verification', () async {
    var cancelled = false;
    final bytes = pngCarvingPng();
    var validationCheckpoints = 0;
    await expectLater(
      scanArchivePngCarving(
        koni.MemoryByteSource(bytes),
        isCancelled: () => cancelled,
        checkpoint: () async {
          if (++validationCheckpoints == 5) cancelled = true;
        },
      ),
      throwsA(isA<ArchivePngCarvingCancelled>()),
    );
    final report = await scan(bytes);
    cancelled = false;
    await expectLater(
      recoverArchivePngCarving(
        report,
        selectedOffsets: {0},
        isCancelled: () => cancelled,
        onProgress: (p) {
          if (p.phase == ArchivePngCarvingPhase.verifying) cancelled = true;
        },
      ),
      throwsA(isA<ArchivePngCarvingCancelled>()),
    );
  });

  test(
    'checkpoints await a paused scan instead of returning an authorized result',
    () async {
      final gate = Completer<void>();
      var completed = false;
      final pending =
          scanArchivePngCarving(
            koni.MemoryByteSource(pngCarvingPng()),
            checkpoint: () => gate.future,
          ).then((report) {
            completed = true;
            return report;
          });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      gate.complete();
      expect((await pending).recoverableCandidates, hasLength(1));
    },
  );
}

Uint8List _be32(List<int> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    data.setUint32(i * 4, values[i], Endian.big);
  }
  return bytes;
}

Uint8List _storedZlib(List<int> raw) {
  final result = Uint8List(2 + 5 + raw.length + 4);
  result.setRange(0, 3, [0x78, 0x01, 0x01]);
  final data = ByteData.sublistView(result);
  data.setUint16(3, raw.length, Endian.little);
  data.setUint16(5, raw.length ^ 0xffff, Endian.little);
  result.setRange(7, 7 + raw.length, raw);
  var a = 1;
  var b = 0;
  for (final byte in raw) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  data.setUint32(result.length - 4, b * 65536 + a, Endian.big);
  return result;
}

class _FaultSource implements koni.ByteSource {
  _FaultSource(
    this.bytes, {
    this.failRead,
    this.shortRead = false,
    this.changeLength = false,
  });
  final Uint8List bytes;
  final int? failRead;
  final bool shortRead;
  final bool changeLength;
  int reads = 0;
  bool closed = false;
  @override
  int get length => bytes.length + (changeLength && reads > 0 ? 1 : 0);
  @override
  String? get name => 'fault.img';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (++reads == failRead) throw StateError('unreadable range');
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + count - (shortRead ? 1 : 0),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
