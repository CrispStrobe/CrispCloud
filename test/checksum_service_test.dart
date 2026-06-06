// test/checksum_service_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/checksum_service.dart';

void main() {
  group('ChecksumService', () {
    // Known test vectors from RFC 1321 (MD5) and FIPS 180-4 (SHA-256).

    test('md5Hash of empty input', () {
      final result = ChecksumService.md5Hash(Uint8List(0));
      expect(result, equals('d41d8cd98f00b204e9800998ecf8427e'));
    });

    test('md5Hash of "abc"', () {
      final data = Uint8List.fromList('abc'.codeUnits);
      final result = ChecksumService.md5Hash(data);
      expect(result, equals('900150983cd24fb0d6963f7d28e17f72'));
    });

    test('md5Hash of "The quick brown fox jumps over the lazy dog"', () {
      final data = Uint8List.fromList(
        'The quick brown fox jumps over the lazy dog'.codeUnits,
      );
      final result = ChecksumService.md5Hash(data);
      expect(result, equals('9e107d9d372bb6826bd81d3542a419d6'));
    });

    test('sha256Hash of empty input', () {
      final result = ChecksumService.sha256Hash(Uint8List(0));
      expect(
        result,
        equals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
      );
    });

    test('sha256Hash of "abc"', () {
      final data = Uint8List.fromList('abc'.codeUnits);
      final result = ChecksumService.sha256Hash(data);
      expect(
        result,
        equals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
      );
    });

    test('sha256Hash of "The quick brown fox jumps over the lazy dog"', () {
      final data = Uint8List.fromList(
        'The quick brown fox jumps over the lazy dog'.codeUnits,
      );
      final result = ChecksumService.sha256Hash(data);
      expect(
        result,
        equals('d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592'),
      );
    });

    group('Checksum file generate/verify', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('checksum_test_');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('generateMd5File creates .md5 sidecar file', () async {
        // Create a test file
        final testFile = File('${tempDir.path}/hello.txt');
        await testFile.writeAsString('hello world');

        final outPath = await ChecksumService.generateMd5File(
          [testFile.path],
          tempDir.path,
          outputName: 'test.md5',
        );

        expect(await File(outPath).exists(), isTrue);
        final content = await File(outPath).readAsString();
        // Should contain "hash  hello.txt" format
        expect(content, contains('hello.txt'));
        expect(content.trim().split('  ').length, greaterThanOrEqualTo(2));
      });

      test('verifyChecksumFile returns OK for matching hashes', () async {
        final testFile = File('${tempDir.path}/verify.txt');
        await testFile.writeAsString('test content');

        // Generate the md5 file
        final md5Path = await ChecksumService.generateMd5File(
          [testFile.path],
          tempDir.path,
          outputName: 'verify.md5',
        );

        // Verify it
        final results = await ChecksumService.verifyChecksumFile(md5Path);
        expect(results.length, 1);
        expect(results.first.ok, isTrue);
        expect(results.first.filename, 'verify.txt');
      });

      test('verifyChecksumFile returns fail for modified file', () async {
        final testFile = File('${tempDir.path}/modified.txt');
        await testFile.writeAsString('original content');

        final md5Path = await ChecksumService.generateMd5File(
          [testFile.path],
          tempDir.path,
          outputName: 'modified.md5',
        );

        // Modify the file after generating checksums
        await testFile.writeAsString('modified content');

        final results = await ChecksumService.verifyChecksumFile(md5Path);
        expect(results.length, 1);
        expect(results.first.ok, isFalse);
      });

      test('generateSha256File creates .sha256 sidecar file', () async {
        final testFile = File('${tempDir.path}/sha256test.txt');
        await testFile.writeAsString('sha256 test');

        final outPath = await ChecksumService.generateSha256File(
          [testFile.path],
          tempDir.path,
          outputName: 'test.sha256',
        );

        expect(await File(outPath).exists(), isTrue);
      });

      test('ChecksumVerifyResult.ok is true when hashes match', () {
        const result = ChecksumVerifyResult(
          filename: 'test.txt',
          expected: 'abc123DEF',
          actual: 'abc123def', // case-insensitive
        );
        expect(result.ok, isTrue);
      });

      test('ChecksumVerifyResult.ok is false when hashes differ', () {
        const result = ChecksumVerifyResult(
          filename: 'test.txt',
          expected: 'aaa',
          actual: 'bbb',
        );
        expect(result.ok, isFalse);
      });
    });
  });
}
