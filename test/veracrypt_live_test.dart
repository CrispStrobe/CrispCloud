@Tags(['live'])
// test/veracrypt_live_test.dart
//
// Live integration test for VeraCrypt container support.
// Creates a real VeraCrypt-format header with AES-256-XTS encryption,
// writes it to a temp file, then tests detection → parsing → decryption
// round-trip.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:crisp_cloud/services/veracrypt_service.dart';

/// Build a valid 512-byte VeraCrypt header encrypted with AES-256-XTS.
///
/// - [password]: the volume password
/// - [hashAlgorithm]: KDF hash ('SHA-512', 'SHA-256', 'Whirlpool')
/// - [iterations]: PBKDF2 iterations (low for test speed)
/// - [volumeSize]: logical volume size stored in the header
Uint8List _buildVeraCryptHeader({
  required String password,
  String hashAlgorithm = 'SHA-512',
  int iterations = 10,
  int volumeSize = 10 * 1024 * 1024, // 10 MB
}) {
  // 1. Generate random 64-byte salt
  final rng = FortunaRandom();
  rng.seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 42))));
  final salt = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    salt[i] = rng.nextUint8();
  }

  // 2. Build the cleartext header area (448 bytes)
  final clearHeader = Uint8List(448);
  final bd = ByteData.sublistView(clearHeader);

  // Magic "VERA" at offset 0
  clearHeader[0] = 0x56; // V
  clearHeader[1] = 0x45; // E
  clearHeader[2] = 0x52; // R
  clearHeader[3] = 0x41; // A

  // Header format version (offset 4, uint16 big-endian)
  bd.setUint16(4, 5, Endian.big);

  // Minimum program version (offset 6)
  bd.setUint16(6, 0x0700, Endian.big);

  // Sector size (offset 68, uint32 big-endian)
  bd.setUint32(68, 512, Endian.big);

  // Encrypted area offset (offset 100, int64 big-endian) — after header
  bd.setInt64(100, 131072, Endian.big); // 128 KB typical

  // Encrypted area size (offset 108, int64 big-endian)
  bd.setInt64(108, volumeSize, Endian.big);

  // Volume size (offset 252, int64 big-endian)
  bd.setInt64(252, volumeSize, Endian.big);

  // Encryption algorithm: AES-256-XTS = 1 (offset 260, uint32 big-endian)
  bd.setUint32(260, 1, Endian.big);

  // Hash algorithm: SHA-512 = 1, Whirlpool = 2, SHA-256 = 3
  final hashId = hashAlgorithm == 'SHA-256'
      ? 3
      : hashAlgorithm == 'Whirlpool'
          ? 2
          : 1;
  bd.setUint32(268, hashId, Endian.big);

  // 3. Derive key (64 bytes = two 32-byte keys for XTS)
  final keyMaterial = VeraCryptService.deriveKey(
    password,
    salt,
    hashAlgorithm: hashAlgorithm,
    iterations: iterations,
  );
  final key1 = keyMaterial.sublist(0, 32);
  final key2 = keyMaterial.sublist(32, 64);

  // 4. Encrypt header with AES-256-XTS (sector 0)
  final encryptedHeader = _aesXtsEncrypt(clearHeader, key1, key2, sectorIndex: 0);

  // 5. Combine: salt (64) + encrypted header (448) = 512 bytes
  final header = Uint8List(512);
  header.setRange(0, 64, salt);
  header.setRange(64, 512, encryptedHeader);
  return header;
}

/// AES-256-XTS encryption (mirrors VeraCryptService._aesXtsDecrypt).
Uint8List _aesXtsEncrypt(
  Uint8List plaintext,
  Uint8List key1,
  Uint8List key2, {
  int sectorIndex = 0,
}) {
  // XTS tweak
  final tweak = Uint8List(16);
  ByteData.sublistView(tweak).setUint64(0, sectorIndex, Endian.little);
  final aes2 = AESEngine()..init(true, KeyParameter(key2));
  final encTweak = Uint8List(16);
  aes2.processBlock(tweak, 0, encTweak, 0);

  // Encrypt
  final aes1 = AESEngine()..init(true, KeyParameter(key1));
  final ciphertext = Uint8List(plaintext.length);
  var tweakArr = Uint8List.fromList(encTweak);

  for (var i = 0; i < plaintext.length; i += 16) {
    final block = Uint8List(16);
    for (var k = 0; k < 16; k++) {
      block[k] = plaintext[i + k] ^ tweakArr[k];
    }
    final encBlock = Uint8List(16);
    aes1.processBlock(block, 0, encBlock, 0);
    for (var k = 0; k < 16; k++) {
      ciphertext[i + k] = encBlock[k] ^ tweakArr[k];
    }
    tweakArr = _gf128Multiply2(tweakArr);
  }
  return ciphertext;
}

/// GF(2^128) multiplication by 2 (same as in VeraCryptService).
Uint8List _gf128Multiply2(Uint8List input) {
  final result = Uint8List(16);
  var carry = 0;
  for (var i = 0; i < 16; i++) {
    final next = (input[i] >> 7) & 1;
    result[i] = ((input[i] << 1) | carry) & 0xFF;
    carry = next;
  }
  if (carry != 0) {
    result[0] ^= 0x87; // GF reduction polynomial
  }
  return result;
}

void main() {
  group('VeraCrypt live integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vc_live_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detect → parse → decrypt round-trip with SHA-512', () {
      const password = 'test-password-123!';
      final header = _buildVeraCryptHeader(
        password: password,
        hashAlgorithm: 'SHA-512',
        iterations: 10,
      );

      // Write to .vc file
      final file = File('${tempDir.path}/test_volume.vc');
      // Pad to look like a real container (header + some data)
      final container = Uint8List(1024 * 1024); // 1 MB
      container.setRange(0, 512, header);
      file.writeAsBytesSync(container);

      // Detection
      expect(VeraCryptService.detectContainer(file.path), isTrue);
      expect(
          VeraCryptService.detectContainerStrict(file.path, container.length),
          isTrue);

      // Parse raw header
      final parsed = VeraCryptService.parseHeader(header);
      expect(parsed.salt.length, equals(64));

      // Decrypt header with correct password
      final decrypted = VeraCryptService.tryDecryptHeader(
        header,
        password,
        testIterations: 10,
      );
      expect(decrypted, isNotNull, reason: 'Header decryption should succeed');
      expect(decrypted!.version, equals(5));
      expect(decrypted.sectorSize, equals(512));
      expect(decrypted.volumeSize, equals(10 * 1024 * 1024));
      expect(decrypted.encryptedAreaOffset, equals(131072));
      expect(decrypted.encryptedAreaSize, equals(10 * 1024 * 1024));
      expect(decrypted.encryptionAlgorithmId, equals(1)); // AES-256-XTS
      expect(decrypted.hashAlgorithmId, equals(1)); // SHA-512 = 1
    });

    test('wrong password fails to decrypt', () {
      final header = _buildVeraCryptHeader(
        password: 'correct-password',
        iterations: 10,
      );

      final result = VeraCryptService.tryDecryptHeader(
        header,
        'wrong-password',
        testIterations: 10,
      );
      expect(result, isNull, reason: 'Wrong password should not decrypt');
    });

    test('SHA-256 KDF round-trip', () {
      const password = 'sha256-test-pw';
      final header = _buildVeraCryptHeader(
        password: password,
        hashAlgorithm: 'SHA-256',
        iterations: 10,
        volumeSize: 50 * 1024 * 1024,
      );

      final decrypted = VeraCryptService.tryDecryptHeader(
        header,
        password,
        testIterations: 10,
      );
      expect(decrypted, isNotNull);
      expect(decrypted!.volumeSize, equals(50 * 1024 * 1024));
      expect(decrypted.hashAlgorithmId, equals(3)); // SHA-256 = 3
    });

    test('Whirlpool KDF round-trip', () {
      const password = 'whirlpool-pw!@#';
      final header = _buildVeraCryptHeader(
        password: password,
        hashAlgorithm: 'Whirlpool',
        iterations: 10,
        volumeSize: 100 * 1024 * 1024,
      );

      final decrypted = VeraCryptService.tryDecryptHeader(
        header,
        password,
        testIterations: 10,
      );
      expect(decrypted, isNotNull);
      expect(decrypted!.volumeSize, equals(100 * 1024 * 1024));
      expect(decrypted.hashAlgorithmId, equals(2)); // Whirlpool = 2
    });

    test('.hc extension also detected', () {
      final file = File('${tempDir.path}/hidden.hc');
      file.writeAsBytesSync(Uint8List(1024));
      expect(VeraCryptService.detectContainer(file.path), isTrue);
    });

    test('non-.vc file with valid header is still parseable', () {
      const password = 'sneaky';
      final header = _buildVeraCryptHeader(password: password, iterations: 10);

      // Write as .dat (not .vc)
      final file = File('${tempDir.path}/data.dat');
      final container = Uint8List(2048);
      container.setRange(0, 512, header);
      file.writeAsBytesSync(container);

      // Detection by extension fails
      expect(VeraCryptService.detectContainer(file.path), isFalse);
      // But detection by size works
      expect(VeraCryptService.detectContainer(file.path, fileSize: 2048), isTrue);

      // Direct header decryption still works
      final decrypted = VeraCryptService.tryDecryptHeader(
        header,
        password,
        testIterations: 10,
      );
      expect(decrypted, isNotNull);
    });

    test('corrupted header returns null', () {
      final header = _buildVeraCryptHeader(password: 'test', iterations: 10);
      // Corrupt the salt — this changes the derived key, so magic won't match
      for (var i = 0; i < 64; i++) {
        header[i] ^= 0xFF;
      }

      final result = VeraCryptService.tryDecryptHeader(
        header,
        'test',
        testIterations: 10,
      );
      expect(result, isNull);
    });

    test('truncated header throws FormatException', () {
      expect(
        () => VeraCryptService.parseHeader(Uint8List(256)),
        throwsFormatException,
      );
    });

    test('encryption algorithm name mapping', () {
      expect(VeraCryptService.encryptionAlgorithmName(1), equals('AES-256-XTS'));
    });

    test('hash algorithm name mapping', () {
      expect(VeraCryptService.hashAlgorithmName(1), equals('SHA-512'));
      expect(VeraCryptService.hashAlgorithmName(3), equals('SHA-256'));
      expect(VeraCryptService.hashAlgorithmName(2), equals('Whirlpool'));
    });
  });
}
