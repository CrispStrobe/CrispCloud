// test/checksum_service_test.dart

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
  });
}
