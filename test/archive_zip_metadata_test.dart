import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/services/archive_zip_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

Future<Uint8List> _written({String? password, DateTime? modified}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: const koni.ZipWriteFormat(),
    options: koni.ArchiveWriteOptions(password: password),
  );
  for (final name in ['first', 'répertoire/second']) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(
        path: name,
        modified: modified ?? DateTime.utc(2026, 11, 12, 1, 2, 13),
        posixMode: 0x1a0,
      ),
      Uint8List.fromList([1, 2, 3]),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

void main() {
  final time = DateTime.utc(2026, 11, 12, 1, 2, 13);
  for (final password in [null, 'archive-secret']) {
    test(
      'extended UTC seconds survive local/central metadata with ${password == null ? 'plain' : 'encrypted'} payloads',
      () async {
        final original = await _written(password: password);
        final result = preserveArchiveZipTimes(original, {
          'first': time,
          'répertoire/second': time,
        });
        final reader = await koni.builtInFormats.openReader(
          koni.MemoryByteSource(result),
          options: koni.ArchiveReadOptions(password: password),
        );
        addTearDown(reader.close);
        expect(reader.entries.length, 2);
        for (final entry in reader.entries) {
          expect(entry.modified, time);
          expect(entry.posixMode! & 0xfff, 0x1a0);
          expect(entry.isEncrypted, password != null);
          expect(
            await reader.openRead(entry).expand((chunk) => chunk).toList(),
            [1, 2, 3],
          );
        }
        final independent = codec.ZipDecoder().decodeBytes(
          result,
          verify: true,
          password: password,
        );
        expect(independent.files.length, 2);
        expect(
          independent.files.first.lastModTime,
          time.millisecondsSinceEpoch ~/ 1000,
        );
        for (final file in independent.files) {
          expect(file.content, [1, 2, 3]);
        }
      },
    );
  }
  test(
    'unrepresentable precision and unexpected footer refuse finalization',
    () async {
      final original = await _written();
      expect(
        () => preserveArchiveZipTimes(original, {
          'first': time.add(const Duration(microseconds: 1)),
          'répertoire/second': time,
        }),
        throwsStateError,
      );
      final changed = Uint8List.fromList(original);
      changed[changed.length - 22] = 0;
      expect(
        () => preserveArchiveZipTimes(changed, {
          'first': time,
          'répertoire/second': time,
        }),
        throwsStateError,
      );
      expect(
        () => preserveArchiveZipTimes(original, {
          'first': time,
          'répertoire/second': time,
        }, limit: original.length),
        throwsStateError,
      );
    },
  );
  test(
    'signed UTC timestamp boundary uses DOS fallback without unsigned overflow',
    () async {
      final boundary = DateTime.utc(2038, 1, 19, 3, 14, 7);
      for (final modified in [
        boundary,
        boundary.add(const Duration(seconds: 1)),
      ]) {
        final bytes = await _written(modified: modified);
        final result = preserveArchiveZipTimes(bytes, {
          'first': modified,
          'répertoire/second': modified,
        });
        final reader = await koni.builtInFormats.openReader(
          koni.MemoryByteSource(result),
        );
        addTearDown(reader.close);
        expect(reader.entries.first.modified, modified);
        final view = ByteData.sublistView(result);
        final localExtra = view.getUint16(28, Endian.little);
        expect(localExtra, modified == boundary ? 9 : 0);
        if (modified == boundary) {
          expect(
            view.getInt32(
              30 + view.getUint16(26, Endian.little) + 5,
              Endian.little,
            ),
            0x7fffffff,
          );
        }
      }
      final odd = boundary.add(const Duration(seconds: 2));
      final oddBytes = await _written(modified: odd);
      expect(
        () => preserveArchiveZipTimes(oddBytes, {
          'first': odd,
          'répertoire/second': odd,
        }),
        throwsStateError,
      );
      final different = DateTime.utc(2040, 1, 1);
      expect(
        () => preserveArchiveZipTimes(oddBytes, {
          'first': different,
          'répertoire/second': different,
        }),
        throwsStateError,
      );
    },
  );
  test('signed negative UT input is rejected before timestamp policy can be misread', () async {
    final bytes = preserveArchiveZipTimes(await _written(), {
      'first': time,
      'répertoire/second': time,
    });
    expect(archiveZipTimestampPolicyIssue(bytes), isNull);
    final changed = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(changed);
    final central = data.getUint32(changed.length - 22 + 16, Endian.little);
    final timestamp =
        central + 46 + data.getUint16(central + 28, Endian.little) + 5;
    data.setInt32(timestamp, -1, Endian.little);
    expect(archiveZipTimestampPolicyIssue(changed), isNotNull);
    final malformed = Uint8List.fromList(bytes);
    ByteData.sublistView(malformed).setUint16(
      central + 46 + data.getUint16(central + 28, Endian.little) + 2,
      1,
      Endian.little,
    );
    expect(archiveZipTimestampPolicyIssue(malformed), isNotNull);
  });
  for (final count in [65535, 65536]) {
    test(
      'UTC finalization preserves $count-entry ZIP footer and exact offsets',
      () async {
        final (bytes, times) = _manyEmptyFiles(count, time);
        final result = preserveArchiveZipTimes(bytes, times);
        final reader = await koni.builtInFormats.openReader(
          koni.MemoryByteSource(result),
          options: const koni.ArchiveReadOptions(maxEntryCount: 200000),
        );
        addTearDown(reader.close);
        expect(reader.entries.length, count);
        expect(reader.entries.first.modified, time);
        expect(reader.entries.last.modified, time);
        expect(
          await reader
              .openRead(reader.entries.last)
              .expand((chunk) => chunk)
              .toList(),
          isEmpty,
        );
      },
    );
  }
}

/// Independent stored-file layout exercises both the largest ordinary count
/// and the ZIP64 count transition without thousands of compressor instances.
(Uint8List, Map<String, DateTime?>) _manyEmptyFiles(int count, DateTime time) {
  final output = BytesBuilder(copy: false), central = BytesBuilder(copy: false);
  final times = <String, DateTime?>{};
  for (var i = 0; i < count; i++) {
    final name = 'file$i';
    times[name] = time;
    final encoded = utf8.encode(name);
    final offset = output.length;
    final local = Uint8List(30);
    ByteData.sublistView(local)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x800, Endian.little)
      ..setUint16(26, encoded.length, Endian.little);
    output.add(local);
    output.add(encoded);
    final record = Uint8List(46);
    ByteData.sublistView(record)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x800, Endian.little)
      ..setUint16(28, encoded.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central.add(record);
    central.add(encoded);
  }
  final start = output.length, size = central.length;
  output.add(central.takeBytes());
  if (count > 65535) {
    final footerOffset = output.length;
    final footer = Uint8List(56);
    ByteData.sublistView(footer)
      ..setUint32(0, 0x06064b50, Endian.little)
      ..setUint64(4, 44, Endian.little)
      ..setUint16(12, 45, Endian.little)
      ..setUint16(14, 45, Endian.little)
      ..setUint64(24, count, Endian.little)
      ..setUint64(32, count, Endian.little)
      ..setUint64(40, size, Endian.little)
      ..setUint64(48, start, Endian.little);
    output.add(footer);
    final locator = Uint8List(20);
    ByteData.sublistView(locator)
      ..setUint32(0, 0x07064b50, Endian.little)
      ..setUint64(8, footerOffset, Endian.little)
      ..setUint32(16, 1, Endian.little);
    output.add(locator);
  }
  final end = Uint8List(22);
  ByteData.sublistView(end)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count.clamp(0, 65535), Endian.little)
    ..setUint16(10, count.clamp(0, 65535), Endian.little)
    ..setUint32(12, size, Endian.little)
    ..setUint32(16, start, Endian.little);
  output.add(end);
  return (output.takeBytes(), times);
}
