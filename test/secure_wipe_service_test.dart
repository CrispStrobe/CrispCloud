// test/secure_wipe_service_test.dart
//
// Tests for secure wipe (Phase 4.2).

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/secure_wipe_service.dart';

void main() {
  group('SecureWipeService', () {
    late String tempDir;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('wipe_test_')).path;
    });

    tearDown(() async {
      if (await Directory(tempDir).exists()) {
        await Directory(tempDir).delete(recursive: true);
      }
    });

    test('wipe deletes the file', () async {
      final filePath = p.join(tempDir, 'secret.txt');
      await File(filePath).writeAsString('sensitive data');
      expect(await File(filePath).exists(), isTrue);

      await SecureWipeService.secureWipe(filePath, passes: 1);
      expect(await File(filePath).exists(), isFalse);
    });

    test('wipe handles empty files', () async {
      final filePath = p.join(tempDir, 'empty.txt');
      await File(filePath).create();
      expect(await File(filePath).exists(), isTrue);

      await SecureWipeService.secureWipe(filePath, passes: 1);
      expect(await File(filePath).exists(), isFalse);
    });

    test('wipe reports progress', () async {
      final filePath = p.join(tempDir, 'progress.bin');
      await File(filePath).writeAsBytes(Uint8List(1000));

      final calls = <int>[];
      await SecureWipeService.secureWipe(
        filePath,
        passes: 3,
        onProgress: (pass, total) => calls.add(pass),
      );

      expect(calls, [1, 2, 3]);
    });

    test('wipe with multiple passes', () async {
      final filePath = p.join(tempDir, 'multi.bin');
      await File(filePath).writeAsBytes(Uint8List(500));

      await SecureWipeService.secureWipe(filePath, passes: 7);
      expect(await File(filePath).exists(), isFalse);
    });

    test('wipe handles non-existent file gracefully', () async {
      final filePath = p.join(tempDir, 'nonexistent.txt');
      // Should not throw
      await SecureWipeService.secureWipe(filePath);
    });

    test('throws on invalid passes', () {
      expect(
        () => SecureWipeService.secureWipe('/tmp/x', passes: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('secureWipeDirectory removes all files and directory', () async {
      final subDir = p.join(tempDir, 'subdir');
      await Directory(subDir).create();
      await File(p.join(subDir, 'a.txt')).writeAsString('aaa');
      await File(p.join(subDir, 'b.txt')).writeAsString('bbb');

      await SecureWipeService.secureWipeDirectory(subDir, passes: 1);
      expect(await Directory(subDir).exists(), isFalse);
    });
  });
}
