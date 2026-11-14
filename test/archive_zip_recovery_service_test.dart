import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_zip_recovery_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_zip_recovery_fixture.dart';

void main() {
  Future<ArchiveZipRecoveryReport> scan(Uint8List bytes) =>
      scanArchiveZipRecovery(koni.MemoryByteSource(bytes, name: 'broken.zip'));

  test(
    'recovers stored, deflated, empty and directory local records',
    () async {
      final input = zipRecoveryRecords([
        zipRecoveryLocalRecord('folder/', []),
        zipRecoveryLocalRecord('folder/one.txt', utf8.encode('first')),
        zipRecoveryLocalRecord(
          'two.bin',
          List.generate(5000, (i) => i % 251),
          method: 8,
        ),
        zipRecoveryLocalRecord('empty', [], method: 8),
      ]);
      final original = Uint8List.fromList(input);
      final report = await scan(input);
      expect(report.stopReason, ArchiveZipRecoveryStopReason.endOfInput);
      expect(report.scannedBytes, input.length);
      expect(report.recoverableEntries, hasLength(4));
      expect(report.sourceSha256, sha256.convert(input).toString());
      final result = await recoverArchiveZip(report);
      final archive = codecs.ZipDecoder().decodeBytes(
        result.bytes,
        verify: true,
      );
      expect(archive.length, 4);
      expect(archive.find('folder/')?.isDirectory, isTrue);
      expect(archive.find('folder/one.txt')?.readBytes(), utf8.encode('first'));
      expect(archive.find('empty')?.readBytes(), isEmpty);
      expect(result.sha256, sha256.convert(result.bytes).toString());
      expect(input, original);
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
    },
  );

  for (final signed in [true, false]) {
    test(
      'measures ${signed ? 'signed' : 'unsigned'} deflate descriptor boundary',
      () async {
        final payload = utf8.encode(
          'contains PK\x03\x04 and PK\x07\x08 signatures ' * 100,
        );
        final input = zipRecoveryRecords([
          zipRecoveryLocalRecord(
            'descriptor.bin',
            payload,
            method: 8,
            flags: 0x808,
            signedDescriptor: signed,
          ),
          zipRecoveryLocalRecord('after.txt', [7, 8, 9]),
        ]);
        final report = await scan(input);
        expect(report.recoverableEntries.map((e) => e.name), [
          'descriptor.bin',
          'after.txt',
        ]);
        expect(report.entries.first.usesDataDescriptor, isTrue);
        final result = await recoverArchiveZip(report);
        final reopened = codecs.ZipDecoder().decodeBytes(
          result.bytes,
          verify: true,
        );
        expect(reopened.find('descriptor.bin')?.readBytes(), payload);
      },
    );
  }

  test('snapshot survives caller mutation after scanning', () async {
    final input = zipRecoveryLocalRecord('copy.txt', [1, 2, 3]);
    final report = await scan(input);
    input.fillRange(0, input.length, 0);
    final result = await recoverArchiveZip(report);
    expect(codecs.ZipDecoder().decodeBytes(result.bytes).first.readBytes(), [
      1,
      2,
      3,
    ]);
  });

  test(
    'selection uses offsets and refuses empty, rejected or unknown offsets',
    () async {
      final input = zipRecoveryRecords([
        zipRecoveryLocalRecord('one', [1]),
        zipRecoveryLocalRecord('../bad', [2]),
        zipRecoveryLocalRecord('two', [3]),
      ]);
      final report = await scan(input);
      final result = await recoverArchiveZip(
        report,
        selectedOffsets: {report.entries.last.offset},
      );
      expect(result.entries.map((e) => e.name), ['two']);
      for (final selected in <Set<int>>[
        {},
        {-1},
        {report.entries[1].offset},
      ]) {
        await expectLater(
          recoverArchiveZip(report, selectedOffsets: selected),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    },
  );

  test('unsafe names are excluded without sanitizing their spelling', () async {
    final unsafe = [
      '../out',
      '/absolute',
      'a/../b',
      'a\\b',
      'C:drive',
      'x//y',
      'dot/.',
      'a\u0000b',
    ];
    final report = await scan(
      zipRecoveryRecords([
        for (final name in unsafe) zipRecoveryLocalRecord(name, [1]),
        zipRecoveryLocalRecord('safe.txt', [2]),
      ]),
    );
    expect(report.recoverableEntries.map((e) => e.name), ['safe.txt']);
    expect(
      report.entries.take(unsafe.length).map((e) => e.reason),
      everyElement(ArchiveZipRecoveryReason.invalidName),
    );
  });

  test('all case-colliding duplicate records are excluded', () async {
    final report = await scan(
      zipRecoveryRecords([
        zipRecoveryLocalRecord('A.txt', [1]),
        zipRecoveryLocalRecord('a.txt', [2]),
        zipRecoveryLocalRecord('good', [3]),
      ]),
    );
    expect(report.recoverableEntries.map((e) => e.name), ['good']);
    expect(
      report.entries.take(2).map((e) => e.reason),
      everyElement(ArchiveZipRecoveryReason.duplicateName),
    );
  });

  test('file and descendant conflicts exclude both sides', () async {
    final report = await scan(
      zipRecoveryRecords([
        zipRecoveryLocalRecord('parent', [1]),
        zipRecoveryLocalRecord('parent/child', [2]),
        zipRecoveryLocalRecord('okay', [3]),
      ]),
    );
    expect(report.recoverableEntries.map((e) => e.name), ['okay']);
    expect(
      report.entries.take(2).map((e) => e.reason),
      everyElement(ArchiveZipRecoveryReason.pathConflict),
    );
  });

  test(
    'valid UTF-8 and ASCII names recover; unmarked high bytes are rejected',
    () async {
      final report = await scan(
        zipRecoveryRecords([
          zipRecoveryLocalRecord('雪/café', [1]),
          zipRecoveryLocalRecord('ascii', [2], flags: 0),
          zipRecoveryLocalRecord('', [3], flags: 0, encodedName: [0x82]),
          zipRecoveryLocalRecord('', [4], encodedName: [0xc3]),
        ]),
      );
      expect(report.recoverableEntries.map((e) => e.name), ['雪/café', 'ascii']);
      expect(
        report.entries[2].reason,
        ArchiveZipRecoveryReason.unsupportedEncoding,
      );
      expect(report.entries[3].reason, ArchiveZipRecoveryReason.invalidName);
    },
  );

  test('truncated second member keeps a verified prefix and stops', () async {
    final good = zipRecoveryLocalRecord('good', [1]);
    final bad = zipRecoveryLocalRecord('bad', [2, 3, 4]);
    final report = await scan(
      zipRecoveryRecords([good, bad.sublist(0, bad.length - 1)]),
    );
    expect(report.recoverableEntries.map((e) => e.name), ['good']);
    expect(report.entries.last.reason, ArchiveZipRecoveryReason.truncated);
    expect(report.scannedBytes, good.length);
    expect(report.stopReason, ArchiveZipRecoveryStopReason.truncatedRecord);
  });

  test('CRC failure stops before later apparent local signatures', () async {
    final report = await scan(
      zipRecoveryRecords([
        zipRecoveryLocalRecord('good', [1]),
        zipRecoveryLocalRecord('bad', [2], declaredCrc: 0),
        zipRecoveryLocalRecord('unproven', [3]),
      ]),
    );
    expect(report.entries, hasLength(2));
    expect(
      report.entries.last.reason,
      ArchiveZipRecoveryReason.checksumMismatch,
    );
    expect(report.recoverableEntries.map((e) => e.name), ['good']);
  });

  test('a nested local header inside stored payload remains payload', () async {
    final nested = zipRecoveryLocalRecord('nested', [1]);
    final report = await scan(zipRecoveryLocalRecord('outer', nested));
    expect(report.entries.map((e) => e.name), ['outer']);
  });

  test('overlapping declared length cannot steal a later record', () async {
    final first = zipRecoveryLocalRecord('one', [1], declaredPacked: 100);
    final second = zipRecoveryLocalRecord('two', [2]);
    final report = await scan(zipRecoveryRecords([first, second]));
    expect(report.recoverableEntries, isEmpty);
    expect(report.entries, hasLength(1));
  });

  for (final (label, reason, record)
      in <(String, ArchiveZipRecoveryReason, Uint8List)>[
        (
          'encrypted',
          ArchiveZipRecoveryReason.encrypted,
          zipRecoveryLocalRecord('x', [1], flags: 0x801),
        ),
        (
          'strong encrypted',
          ArchiveZipRecoveryReason.encrypted,
          zipRecoveryLocalRecord('x', [1], flags: 0x840),
        ),
        (
          'ZIP64',
          ArchiveZipRecoveryReason.zip64,
          zipRecoveryLocalRecord('x', [1], version: 45),
        ),
        (
          'ZIP64 extra',
          ArchiveZipRecoveryReason.zip64,
          zipRecoveryLocalRecord('x', [1], extra: [1, 0, 0, 0]),
        ),
        (
          'unknown method',
          ArchiveZipRecoveryReason.unsupportedMethod,
          zipRecoveryLocalRecord('x', [1], method: 12),
        ),
        (
          'unknown flags',
          ArchiveZipRecoveryReason.unsupportedFlags,
          zipRecoveryLocalRecord('x', [1], flags: 0x810),
        ),
        (
          'stored descriptor',
          ArchiveZipRecoveryReason.storedDataDescriptor,
          zipRecoveryLocalRecord('x', [1], flags: 0x808),
        ),
        (
          'malformed extra',
          ArchiveZipRecoveryReason.invalidExtra,
          zipRecoveryLocalRecord('x', [1], extra: [0xff, 0xff, 5, 0]),
        ),
        (
          'stored sizes',
          ArchiveZipRecoveryReason.sizeMismatch,
          zipRecoveryLocalRecord('x', [1], declaredSize: 2),
        ),
      ]) {
    test(
      '$label is explicit and does not guess the following boundary',
      () async {
        final report = await scan(
          zipRecoveryRecords([
            record,
            zipRecoveryLocalRecord('later', [2]),
          ]),
        );
        expect(report.entries.single.reason, reason);
        expect(report.recoverableEntries, isEmpty);
      },
    );
  }

  test('split marker and executable prefix are not signature carved', () async {
    for (final prefix in [
      [0x50, 0x4b, 7, 8],
      [0x4d, 0x5a, 0, 0],
    ]) {
      final report = await scan(
        zipRecoveryRecords([
          prefix,
          zipRecoveryLocalRecord('x', [1]),
        ]),
      );
      expect(report.entries, isEmpty);
      expect(report.scannedBytes, 0);
    }
  });

  test(
    'deflate with excess trailing bytes or incomplete EOS is excluded',
    () async {
      final valid = zipRecoveryLocalRecord(
        'x',
        List.filled(500, 65),
        method: 8,
      );
      final bd = ByteData.sublistView(valid);
      final packed = bd.getUint32(18, Endian.little);
      final payload = valid.sublist(31);
      for (final input in [
        zipRecoveryLocalRecord(
          'x',
          List.filled(500, 65),
          method: 8,
          encodedPayload: [...payload, 0, 0],
        ),
        zipRecoveryLocalRecord(
          'x',
          List.filled(500, 65),
          method: 8,
          encodedPayload: payload.sublist(0, packed - 1),
        ),
      ]) {
        expect((await scan(input)).recoverableEntries, isEmpty);
      }
    },
  );

  test('descriptor fields must match measured CRC and both sizes', () async {
    final good = zipRecoveryLocalRecord(
      'x',
      List.filled(400, 65),
      method: 8,
      flags: 0x808,
    );
    for (final at in [good.length - 12, good.length - 8, good.length - 4]) {
      final bad = Uint8List.fromList(good)..[at] ^= 1;
      final report = await scan(bad);
      expect(
        report.entries.single.reason,
        ArchiveZipRecoveryReason.invalidDataDescriptor,
      );
    }
  });

  test(
    'resource limits stop before accepting an oversized expansion',
    () async {
      final source = koni.MemoryByteSource(
        zipRecoveryLocalRecord('bomb', List.filled(100000, 65), method: 8),
      );
      final report = await scanArchiveZipRecovery(source, maxMemberBytes: 1024);
      expect(
        report.entries.single.reason,
        ArchiveZipRecoveryReason.limitExceeded,
      );
      final descriptorSource = koni.MemoryByteSource(
        zipRecoveryLocalRecord(
          'bomb',
          List.filled(100000, 65),
          method: 8,
          flags: 0x808,
        ),
      );
      final descriptorReport = await scanArchiveZipRecovery(
        descriptorSource,
        maxExpandedBytes: 1024,
      );
      expect(
        descriptorReport.entries.single.reason,
        ArchiveZipRecoveryReason.limitExceeded,
      );
    },
  );

  test(
    'entry, aggregate-name, aggregate-content and output budgets are enforced',
    () async {
      final bytes = zipRecoveryRecords([
        zipRecoveryLocalRecord('one', [1, 2]),
        zipRecoveryLocalRecord('two', [3, 4]),
      ]);
      final entries = await scanArchiveZipRecovery(
        koni.MemoryByteSource(bytes),
        maxEntries: 1,
      );
      expect(entries.entries, hasLength(1));
      expect(entries.stopReason, ArchiveZipRecoveryStopReason.limitReached);
      final names = await scanArchiveZipRecovery(
        koni.MemoryByteSource(bytes),
        maxNameBytes: 4,
      );
      expect(names.entries.last.reason, ArchiveZipRecoveryReason.limitExceeded);
      final content = await scanArchiveZipRecovery(
        koni.MemoryByteSource(bytes),
        maxExpandedBytes: 3,
      );
      expect(
        content.entries.last.reason,
        ArchiveZipRecoveryReason.limitExceeded,
      );
      final report = await scan(bytes);
      await expectLater(
        recoverArchiveZip(report, maxOutputBytes: 20),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'capture uses bounded reads, validation and retains caller ownership',
    () async {
      final source = _RecordingSource(
        zipRecoveryLocalRecord('large', List.filled(150000, 1)),
      );
      var validations = 0;
      final report = await scanArchiveZipRecovery(
        source,
        validateUnchanged: () => validations++,
      );
      expect(source.reads, greaterThan(2));
      expect(source.largestRead, lessThanOrEqualTo(65536));
      expect(source.closed, isFalse);
      expect(validations, 2);
      expect(report.recoverableEntries.single.name, 'large');
    },
  );

  test('cancellation is typed during capture, decode and recovery', () async {
    final input = zipRecoveryLocalRecord(
      'many',
      List.filled(300000, 65),
      method: 8,
    );
    var cancelled = false;
    await expectLater(
      scanArchiveZipRecovery(
        koni.MemoryByteSource(input),
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<ArchiveZipRecoveryCancelled>()),
    );
    var checkpoints = 0;
    await expectLater(
      scanArchiveZipRecovery(
        koni.MemoryByteSource(input),
        isCancelled: () => checkpoints >= 4,
        checkpoint: () async {
          checkpoints++;
        },
      ),
      throwsA(isA<ArchiveZipRecoveryCancelled>()),
    );
    final report = await scan(input);
    cancelled = false;
    await expectLater(
      recoverArchiveZip(
        report,
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<ArchiveZipRecoveryCancelled>()),
    );
  });

  test('source validation failures propagate without closing input', () async {
    final source = _RecordingSource(zipRecoveryLocalRecord('x', [1]));
    var validations = 0;
    await expectLater(
      scanArchiveZipRecovery(
        source,
        validateUnchanged: () {
          if (++validations == 2) throw StateError('changed');
        },
      ),
      throwsStateError,
    );
    expect(source.closed, isFalse);
  });

  test('invalid options are rejected before reading input', () async {
    final source = _RecordingSource(Uint8List(0));
    for (final future in [
      scanArchiveZipRecovery(source, maxSourceBytes: 0),
      scanArchiveZipRecovery(source, maxMemberBytes: kArchiveReadLimit + 1),
      scanArchiveZipRecovery(source, maxEntries: 4097),
      scanArchiveZipRecovery(source, maxNameBytes: 0),
    ]) {
      await expectLater(future, throwsArgumentError);
    }
    expect(source.reads, 0);
  });
}

class _RecordingSource implements koni.ByteSource {
  _RecordingSource(this.bytes);
  final Uint8List bytes;
  int reads = 0;
  int largestRead = 0;
  bool closed = false;
  @override
  int get length => bytes.length;
  @override
  String? get name => 'recorded.zip';
  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    if (length > largestRead) largestRead = length;
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async => closed = true;
}
