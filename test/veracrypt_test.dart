// test/veracrypt_test.dart
//
// Unit tests for VeraCryptService, VeraCryptContainer, and VeraCryptVolumeHeader.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/veracrypt_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Build a minimal 512-byte header buffer where the first 64 bytes are the
  /// salt. The rest is zeroed (so header decryption will fail, but salt
  /// extraction tests will pass).
  Uint8List makeRawHeader({Uint8List? salt}) {
    final buf = Uint8List(512);
    if (salt != null) {
      buf.setRange(0, salt.length.clamp(0, 64), salt);
    }
    return buf;
  }

  /// Build a 512-byte header with "VERA" magic at offset 0 of the encrypted
  /// area (bytes 64–67) — useful for magic-check tests.
  Uint8List makeHeaderWithMagic() {
    final buf = Uint8List(512);
    // Bytes 64-67 = "VERA"
    buf[64] = 0x56; // V
    buf[65] = 0x45; // E
    buf[66] = 0x52; // R
    buf[67] = 0x41; // A
    return buf;
  }

  // ---------------------------------------------------------------------------
  // Container detection by extension
  // ---------------------------------------------------------------------------

  group('detectContainer — extension detection', () {
    test('detects .vc extension as container', () {
      expect(VeraCryptService.detectContainer('/path/volume.vc'), isTrue);
    });

    test('detects .hc extension as container', () {
      expect(VeraCryptService.detectContainer('/path/volume.hc'), isTrue);
    });

    test('rejects .zip extension', () {
      expect(VeraCryptService.detectContainer('/path/archive.zip'), isFalse);
    });

    test('rejects no extension', () {
      expect(VeraCryptService.detectContainer('/path/noextension'), isFalse);
    });

    test('rejects .VC (upper-case) — detection is case-insensitive', () {
      // Extension check is lowercased internally
      expect(VeraCryptService.detectContainer('/path/VOL.VC'), isTrue);
    });

    test('rejects .HC (upper-case) — case-insensitive', () {
      expect(VeraCryptService.detectContainer('/path/vol.HC'), isTrue);
    });

    test('.vc with file too small returns false when fileSize provided', () {
      expect(
        VeraCryptService.detectContainer('/p/v.vc', fileSize: 100),
        isFalse,
      );
    });

    test('.vc with adequate file size returns true', () {
      expect(
        VeraCryptService.detectContainer('/p/v.vc', fileSize: 1024),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Strict container detection
  // ---------------------------------------------------------------------------

  group('detectContainerStrict', () {
    test('returns true for .vc with size >= 512', () {
      expect(VeraCryptService.detectContainerStrict('/v.vc', 512), isTrue);
    });

    test('returns true for .hc with size >= 512', () {
      expect(VeraCryptService.detectContainerStrict('/v.hc', 1024 * 1024), isTrue);
    });

    test('returns false for .vc with size < 512', () {
      expect(VeraCryptService.detectContainerStrict('/v.vc', 511), isFalse);
    });

    test('returns false for unknown extension even with large size', () {
      expect(VeraCryptService.detectContainerStrict('/v.bin', 10 * 1024 * 1024),
          isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Header size validation
  // ---------------------------------------------------------------------------

  group('parseHeader — size validation', () {
    test('accepts exactly 512-byte buffer', () {
      final header = makeRawHeader();
      expect(() => VeraCryptService.parseHeader(header), returnsNormally);
    });

    test('accepts buffers larger than 512 bytes', () {
      final bigBuf = Uint8List(1024);
      expect(() => VeraCryptService.parseHeader(bigBuf), returnsNormally);
    });

    test('throws FormatException for buffer < 512 bytes', () {
      expect(
        () => VeraCryptService.parseHeader(Uint8List(511)),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for empty buffer', () {
      expect(
        () => VeraCryptService.parseHeader(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for 100-byte buffer', () {
      expect(
        () => VeraCryptService.parseHeader(Uint8List(100)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Salt extraction (first 64 bytes)
  // ---------------------------------------------------------------------------

  group('parseHeader — salt extraction', () {
    test('extracts first 64 bytes as salt', () {
      final salt = Uint8List.fromList(List.generate(64, (i) => i + 1));
      final header = makeRawHeader(salt: salt);
      final parsed = VeraCryptService.parseHeader(header);
      expect(parsed.salt, equals(salt));
    });

    test('salt is exactly 64 bytes', () {
      final header = makeRawHeader();
      final parsed = VeraCryptService.parseHeader(header);
      expect(parsed.salt.length, 64);
    });

    test('salt from zeroed header is all zeros', () {
      final header = Uint8List(512);
      final parsed = VeraCryptService.parseHeader(header);
      expect(parsed.salt, equals(Uint8List(64)));
    });

    test('different headers produce different salts', () {
      final salt1 = Uint8List.fromList(List.filled(64, 0xAA));
      final salt2 = Uint8List.fromList(List.filled(64, 0xBB));
      final h1 = VeraCryptService.parseHeader(makeRawHeader(salt: salt1));
      final h2 = VeraCryptService.parseHeader(makeRawHeader(salt: salt2));
      expect(h1.salt, isNot(equals(h2.salt)));
    });
  });

  // ---------------------------------------------------------------------------
  // VERA magic bytes verification
  // ---------------------------------------------------------------------------

  group('VERA magic bytes', () {
    test('VeraCryptVolumeHeader.magicBytes is [0x56, 0x45, 0x52, 0x41]', () {
      expect(VeraCryptVolumeHeader.magicBytes, [0x56, 0x45, 0x52, 0x41]);
    });

    test('magic bytes decode to "VERA" in ASCII', () {
      final s = String.fromCharCodes(VeraCryptVolumeHeader.magicBytes);
      expect(s, 'VERA');
    });

    test('tryDecryptHeader returns null for all-zero header (no VERA magic)', () {
      final header = Uint8List(512);
      // Use testIterations: 1 to avoid 500K-iteration PBKDF2 per algorithm
      expect(
        VeraCryptService.tryDecryptHeader(header, 'anypassword', testIterations: 1),
        isNull,
      );
    });

    test('tryDecryptHeader returns null for random-looking bytes', () {
      final header = Uint8List.fromList(
          List.generate(512, (i) => (i * 37 + 13) & 0xFF));
      expect(
        VeraCryptService.tryDecryptHeader(header, 'pw', testIterations: 1),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Supported algorithms
  // ---------------------------------------------------------------------------

  group('getSupportedAlgorithms', () {
    test('returns a non-empty list', () {
      expect(VeraCryptService.getSupportedAlgorithms(), isNotEmpty);
    });

    test('includes AES-256-XTS', () {
      expect(VeraCryptService.getSupportedAlgorithms(), contains('AES-256-XTS'));
    });

    test('returns at least 3 algorithms', () {
      expect(VeraCryptService.getSupportedAlgorithms().length, greaterThanOrEqualTo(3));
    });

    test('all entries are non-empty strings', () {
      for (final algo in VeraCryptService.getSupportedAlgorithms()) {
        expect(algo, isNotEmpty);
      }
    });
  });

  group('getSupportedHashAlgorithms', () {
    test('returns a non-empty list', () {
      expect(VeraCryptService.getSupportedHashAlgorithms(), isNotEmpty);
    });

    test('includes SHA-512', () {
      expect(VeraCryptService.getSupportedHashAlgorithms(), contains('SHA-512'));
    });

    test('includes SHA-256', () {
      expect(VeraCryptService.getSupportedHashAlgorithms(), contains('SHA-256'));
    });

    test('includes Whirlpool', () {
      expect(VeraCryptService.getSupportedHashAlgorithms(), contains('Whirlpool'));
    });

    test('all entries are non-empty strings', () {
      for (final h in VeraCryptService.getSupportedHashAlgorithms()) {
        expect(h, isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Key derivation parameter validation
  // ---------------------------------------------------------------------------

  group('deriveKey', () {
    test('returns 64 bytes (512 bits)', () {
      final salt = Uint8List(64);
      final key = VeraCryptService.deriveKey('password', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      expect(key.length, 64);
    });

    test('returns 64 bytes with SHA-256', () {
      final salt = Uint8List(64);
      final key = VeraCryptService.deriveKey('password', salt,
          hashAlgorithm: 'SHA-256', iterations: 1);
      expect(key.length, 64);
    });

    test('returns 64 bytes with Whirlpool', () {
      final salt = Uint8List(64);
      final key = VeraCryptService.deriveKey('password', salt,
          hashAlgorithm: 'Whirlpool', iterations: 1);
      expect(key.length, 64);
    });

    test('same inputs produce same key (deterministic)', () {
      final salt = Uint8List.fromList(List.generate(64, (i) => i));
      final k1 = VeraCryptService.deriveKey('same', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      final k2 = VeraCryptService.deriveKey('same', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      expect(k1, equals(k2));
    });

    test('different passwords produce different keys', () {
      final salt = Uint8List(64);
      final k1 = VeraCryptService.deriveKey('password1', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      final k2 = VeraCryptService.deriveKey('password2', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      expect(k1, isNot(equals(k2)));
    });

    test('different salts produce different keys', () {
      final s1 = Uint8List.fromList(List.filled(64, 0x01));
      final s2 = Uint8List.fromList(List.filled(64, 0x02));
      final k1 = VeraCryptService.deriveKey('pw', s1,
          hashAlgorithm: 'SHA-512', iterations: 1);
      final k2 = VeraCryptService.deriveKey('pw', s2,
          hashAlgorithm: 'SHA-512', iterations: 1);
      expect(k1, isNot(equals(k2)));
    });

    test('SHA-512 and SHA-256 produce different keys for same inputs', () {
      final salt = Uint8List(64);
      final k1 = VeraCryptService.deriveKey('pw', salt,
          hashAlgorithm: 'SHA-512', iterations: 1);
      final k2 = VeraCryptService.deriveKey('pw', salt,
          hashAlgorithm: 'SHA-256', iterations: 1);
      expect(k1, isNot(equals(k2)));
    });
  });

  // ---------------------------------------------------------------------------
  // Invalid / corrupted header handling
  // ---------------------------------------------------------------------------

  group('invalid / corrupted headers', () {
    test('tryDecryptHeader with empty header returns null', () {
      // Short headers are rejected before any KDF work
      expect(VeraCryptService.tryDecryptHeader(Uint8List(0), 'pw'), isNull);
    });

    test('tryDecryptHeader with 511-byte header returns null', () {
      expect(VeraCryptService.tryDecryptHeader(Uint8List(511), 'pw'), isNull);
    });

    test('parseHeader throws FormatException on 0-byte input', () {
      expect(
        () => VeraCryptService.parseHeader(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('tryDecryptHeader with corrupted magic returns null', () {
      final bad = Uint8List(512);
      bad[64] = 0xFF; // not 'V'
      expect(
        VeraCryptService.tryDecryptHeader(bad, 'pw', testIterations: 1),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Non-container file rejection
  // ---------------------------------------------------------------------------

  group('non-container file rejection', () {
    test('rejects .txt file', () {
      expect(VeraCryptService.detectContainer('/doc/notes.txt'), isFalse);
    });

    test('rejects .iso file', () {
      expect(VeraCryptService.detectContainer('/images/ubuntu.iso'), isFalse);
    });

    test('rejects .dmg file', () {
      expect(VeraCryptService.detectContainer('/mac/disk.dmg'), isFalse);
    });

    test('rejects path with no extension', () {
      expect(VeraCryptService.detectContainer('/data/myfile'), isFalse);
    });

    test('rejects directory path without extension', () {
      expect(VeraCryptService.detectContainer('/mnt/data/'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Header model serialization
  // ---------------------------------------------------------------------------

  group('VeraCryptVolumeHeader serialization', () {
    test('toJson round-trips salt', () {
      final salt = Uint8List.fromList(List.generate(64, (i) => i * 2));
      final header = VeraCryptVolumeHeader(
        salt: salt,
        encryptedAreaOffset: 131072,
        encryptedAreaSize: 1024 * 1024,
        sectorSize: 512,
        version: 5,
        encryptionAlgorithmId: 1,
        hashAlgorithmId: 1,
        volumeSize: 10 * 1024 * 1024,
      );
      final map = header.toJson();
      final decodedSalt = base64.decode(map['salt'] as String);
      expect(Uint8List.fromList(decodedSalt), equals(salt));
    });

    test('toJson includes all expected fields', () {
      final header = VeraCryptVolumeHeader(
        salt: Uint8List(64),
        encryptedAreaOffset: 0,
        encryptedAreaSize: 0,
        sectorSize: 512,
        version: 5,
        encryptionAlgorithmId: 1,
        hashAlgorithmId: 2,
        volumeSize: 1024,
      );
      final map = header.toJson();
      expect(map.keys, containsAll([
        'salt', 'encryptedAreaOffset', 'encryptedAreaSize',
        'sectorSize', 'version', 'encryptionAlgorithmId',
        'hashAlgorithmId', 'volumeSize',
      ]));
    });

    test('sectorSize defaults to 512 from parseHeader', () {
      final header = VeraCryptService.parseHeader(Uint8List(512));
      expect(header.sectorSize, 512);
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptContainer model
  // ---------------------------------------------------------------------------

  group('VeraCryptContainer model', () {
    test('toJson / fromJson round-trip', () {
      const c = VeraCryptContainer(
        path: '/data/vault.vc',
        sizeBytes: 104857600,
        encryptionAlgorithm: 'AES-256-XTS',
        hashAlgorithm: 'SHA-512',
        mounted: false,
      );
      final map = c.toJson();
      final c2 = VeraCryptContainer.fromJson(map);
      expect(c2.path, c.path);
      expect(c2.sizeBytes, c.sizeBytes);
      expect(c2.encryptionAlgorithm, c.encryptionAlgorithm);
      expect(c2.hashAlgorithm, c.hashAlgorithm);
      expect(c2.mounted, c.mounted);
    });

    test('copyWith changes mounted flag', () {
      const c = VeraCryptContainer(path: '/v.vc', sizeBytes: 1024);
      final mounted = c.copyWith(mounted: true);
      expect(mounted.mounted, isTrue);
      expect(mounted.path, c.path);
    });

    test('toString includes path', () {
      const c = VeraCryptContainer(path: '/data/vault.hc', sizeBytes: 512);
      expect(c.toString(), contains('/data/vault.hc'));
    });

    test('defaults mounted to false', () {
      const c = VeraCryptContainer(path: '/v.vc', sizeBytes: 512);
      expect(c.mounted, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Algorithm name mapping
  // ---------------------------------------------------------------------------

  group('algorithm name mapping', () {
    test('encryptionAlgorithmName(1) returns AES-256-XTS', () {
      expect(VeraCryptService.encryptionAlgorithmName(1), 'AES-256-XTS');
    });

    test('encryptionAlgorithmName(unknown) returns Unknown prefix', () {
      expect(VeraCryptService.encryptionAlgorithmName(99), contains('Unknown'));
    });

    test('hashAlgorithmName(1) returns SHA-512', () {
      expect(VeraCryptService.hashAlgorithmName(1), 'SHA-512');
    });

    test('hashAlgorithmName(2) returns Whirlpool', () {
      expect(VeraCryptService.hashAlgorithmName(2), 'Whirlpool');
    });

    test('hashAlgorithmName(3) returns SHA-256', () {
      expect(VeraCryptService.hashAlgorithmName(3), 'SHA-256');
    });

    test('hashAlgorithmName(unknown) returns Unknown prefix', () {
      expect(VeraCryptService.hashAlgorithmName(99), contains('Unknown'));
    });
  });
}
