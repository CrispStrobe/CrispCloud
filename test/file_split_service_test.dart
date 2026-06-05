// test/file_split_service_test.dart
//
// Tests for file split/combine (Phase 4.1).

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/file_split_service.dart';

void main() {
  group('FileSplitService', () {
    late String tempDir;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('split_test_')).path;
    });

    tearDown(() async {
      await Directory(tempDir).delete(recursive: true);
    });

    test('split creates expected number of parts', () async {
      final sourcePath = p.join(tempDir, 'source.bin');
      final data = Uint8List(5 * 1024 * 1024); // 5 MB of zeros
      await File(sourcePath).writeAsBytes(data);

      final parts = await FileSplitService.splitFile(
        sourcePath,
        tempDir,
        chunkSizeBytes: 2 * 1024 * 1024, // 2 MB chunks
      );

      expect(parts.length, 3); // 2MB + 2MB + 1MB = 3 parts
      for (final part in parts) {
        expect(await File(part).exists(), isTrue);
      }
    });

    test('split and combine round-trip preserves content', () async {
      final sourcePath = p.join(tempDir, 'original.bin');
      // Create file with recognizable content
      final data = Uint8List(1000);
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }
      await File(sourcePath).writeAsBytes(data);
      final originalHash = md5.convert(data).toString();

      // Split
      final parts = await FileSplitService.splitFile(
        sourcePath,
        tempDir,
        chunkSizeBytes: 300,
      );
      expect(parts.length, 4); // ceil(1000/300)

      // Combine
      final outputPath = p.join(tempDir, 'combined.bin');
      await FileSplitService.combineFiles(parts, outputPath);

      final combinedData = await File(outputPath).readAsBytes();
      final combinedHash = md5.convert(combinedData).toString();
      expect(combinedHash, originalHash);
    });

    test('detectParts finds and orders correctly', () async {
      // Create part files
      final baseName = 'data.bin';
      for (var i = 1; i <= 3; i++) {
        final name = '$baseName.part${i.toString().padLeft(3, '0')}';
        await File(p.join(tempDir, name)).writeAsString('part $i');
      }
      // Add a decoy file
      await File(p.join(tempDir, 'other.txt')).writeAsString('not a part');

      final parts = FileSplitService.detectParts(tempDir, baseName);
      expect(parts.length, 3);
      expect(p.basename(parts[0]), 'data.bin.part001');
      expect(p.basename(parts[1]), 'data.bin.part002');
      expect(p.basename(parts[2]), 'data.bin.part003');
    });

    test('detectParts returns empty for no matches', () {
      final parts = FileSplitService.detectParts(tempDir, 'nonexistent.bin');
      expect(parts, isEmpty);
    });

    test('split reports progress', () async {
      final sourcePath = p.join(tempDir, 'progress.bin');
      await File(sourcePath).writeAsBytes(Uint8List(500));

      final progressCalls = <int>[];
      await FileSplitService.splitFile(
        sourcePath,
        tempDir,
        chunkSizeBytes: 200,
        onProgress: (written, total) => progressCalls.add(written),
      );

      expect(progressCalls, isNotEmpty);
      expect(progressCalls.last, 500);
    });

    test('throws on invalid chunk size', () async {
      final sourcePath = p.join(tempDir, 'bad.bin');
      await File(sourcePath).writeAsBytes(Uint8List(10));

      expect(
        () => FileSplitService.splitFile(sourcePath, tempDir, chunkSizeBytes: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
