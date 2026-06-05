// test/cryptomator_test.dart
//
// Unit tests for CryptomatorService, CryptomatorVault, VaultConfig,
// MasterkeyFile, and UnlockedVault.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cryptomator_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Build a minimal but valid masterkey file for a given password.
  /// Uses low scrypt params to keep tests fast.
  MasterkeyFile makeMasterkeyFile(
    Uint8List encKey,
    Uint8List macKey,
    String password, {
    int version = 8,
  }) {
    return CryptomatorService.createMasterkeyFile(
      encKey,
      macKey,
      password,
      scryptCostParam: 16, // very low for test speed
      scryptBlockSize: 1,
      vaultVersion: version,
    );
  }

  UnlockedVault makeUnlockedVault({
    String vaultPath = '/test/vault',
    Uint8List? encKey,
    Uint8List? macKey,
  }) {
    final ek = encKey ?? Uint8List.fromList(List.generate(32, (i) => i + 1));
    final mk = macKey ?? Uint8List.fromList(List.generate(32, (i) => i + 33));
    return UnlockedVault(
      vault: CryptomatorVault(
        vaultPath: vaultPath,
        masterkeyFilePath: '$vaultPath/masterkey.cryptomator',
      ),
      encKey: ek,
      macKey: mk,
    );
  }

  // ---------------------------------------------------------------------------
  // MasterkeyFile JSON parsing
  // ---------------------------------------------------------------------------

  group('MasterkeyFile JSON parsing', () {
    test('parses version from JSON', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw', version: 8);
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.version, 8);
    });

    test('parses scryptSalt as non-empty bytes', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.scryptSalt, isNotEmpty);
    });

    test('parses scryptCostParam correctly', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.scryptCostParam, 16);
    });

    test('parses scryptBlockSize correctly', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.scryptBlockSize, 1);
    });

    test('primaryMasterKey is wrapped: 40 bytes (32 + 8 RFC 3394 overhead)', () {
      final mf = makeMasterkeyFile(
        Uint8List.fromList(List.generate(32, (i) => i)),
        Uint8List(32),
        'test',
      );
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.primaryMasterKey.length, 40);
    });

    test('hmacMasterKey is wrapped: 40 bytes', () {
      final mf = makeMasterkeyFile(
        Uint8List(32),
        Uint8List.fromList(List.generate(32, (i) => i + 1)),
        'test',
      );
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.hmacMasterKey.length, 40);
    });

    test('versionMac is a non-empty base64 string', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.versionMac, isNotEmpty);
      // Must be valid base64
      expect(() => base64.decode(parsed.versionMac), returnsNormally);
    });

    test('round-trip toJson / fromJson preserves all fields', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i * 3));
      final macKey = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));
      final mf = makeMasterkeyFile(encKey, macKey, 'round-trip-test');
      final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
      expect(parsed.version, mf.version);
      expect(parsed.scryptCostParam, mf.scryptCostParam);
      expect(parsed.scryptBlockSize, mf.scryptBlockSize);
      expect(parsed.versionMac, mf.versionMac);
      expect(parsed.scryptSalt, equals(mf.scryptSalt));
    });

    test('throws on malformed JSON string', () {
      expect(() => MasterkeyFile.fromJson('not-valid-json'), throwsA(anything));
    });

    test('throws when required field scryptSalt is missing', () {
      const bad = '{"version":8,"scryptCostParam":32768,"scryptBlockSize":8,'
          '"primaryMasterKey":"AAAA","hmacMasterKey":"AAAA","versionMac":"AAAA"}';
      expect(() => MasterkeyFile.fromJson(bad), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------------------
  // VaultConfig (JWT base64 payload parsing)
  // ---------------------------------------------------------------------------

  group('VaultConfig JWT parsing', () {
    String makeJwt(Map<String, dynamic> payload) {
      // JWT segments are base64url without padding
      final header =
          base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
      final body =
          base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
      return '$header.$body.fakesig';
    }

    test('parses format version', () {
      final config = VaultConfig.fromJwt(makeJwt(
          {'format': 8, 'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.version, 8);
    });

    test('parses cipherCombo', () {
      final config = VaultConfig.fromJwt(makeJwt(
          {'format': 8, 'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.cipherCombo, 'SIV_GCM');
    });

    test('parses shorteningThreshold', () {
      final config = VaultConfig.fromJwt(makeJwt(
          {'format': 8, 'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.shorteningThreshold, 220);
    });

    test('parses optional keyId', () {
      final config = VaultConfig.fromJwt(makeJwt({
        'format': 8,
        'cipherCombo': 'SIV_GCM',
        'shorteningThreshold': 220,
        'kid': 'key123'
      }));
      expect(config.keyId, 'key123');
    });

    test('keyId is null when not present', () {
      final config = VaultConfig.fromJwt(makeJwt(
          {'format': 8, 'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.keyId, isNull);
    });

    test('defaults version to 8 when format key is absent', () {
      final config = VaultConfig.fromJwt(
          makeJwt({'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.version, 8);
    });

    test('throws FormatException on non-JWT string (no dots)', () {
      expect(() => VaultConfig.fromJwt('notajwt'), throwsA(isA<FormatException>()));
    });

    test('toString contains version and cipher combo', () {
      final config = VaultConfig.fromJwt(makeJwt(
          {'format': 8, 'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}));
      expect(config.toString(), contains('8'));
      expect(config.toString(), contains('SIV_GCM'));
    });
  });

  // ---------------------------------------------------------------------------
  // Vault detection
  // ---------------------------------------------------------------------------

  group('CryptomatorService.detectVault', () {
    test('returns true when both marker files are present', () {
      final files = ['vault.cryptomator', 'masterkey.cryptomator', 'd'];
      expect(CryptomatorService.detectVault('/path/to/vault', files), isTrue);
    });

    test('returns false when vault.cryptomator is missing', () {
      expect(
          CryptomatorService.detectVault('/p', ['masterkey.cryptomator', 'd']),
          isFalse);
    });

    test('returns false when masterkey.cryptomator is missing', () {
      expect(
          CryptomatorService.detectVault('/p', ['vault.cryptomator', 'd']),
          isFalse);
    });

    test('returns false for empty directory listing', () {
      expect(CryptomatorService.detectVault('/p', []), isFalse);
    });

    test('handles full paths in the file listing', () {
      final files = [
        '/vault/vault.cryptomator',
        '/vault/masterkey.cryptomator',
      ];
      expect(CryptomatorService.detectVault('/vault', files), isTrue);
    });

    test('is case-sensitive for marker filenames', () {
      // Cryptomator filenames are exactly lowercase
      final files = ['Vault.cryptomator', 'Masterkey.cryptomator'];
      expect(CryptomatorService.detectVault('/p', files), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Vault unlock (scrypt + key unwrap + HMAC verify)
  // ---------------------------------------------------------------------------

  group('CryptomatorService.unlockVault', () {
    final vaultMeta = CryptomatorVault(
      vaultPath: '/v',
      masterkeyFilePath: '/v/masterkey.cryptomator',
    );

    test('unlocks vault and returns original enc key', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i + 10));
      final macKey = Uint8List.fromList(List.generate(32, (i) => i + 50));
      final mf = makeMasterkeyFile(encKey, macKey, 'correct-password');
      final unlocked = CryptomatorService.unlockVault(vaultMeta, mf, 'correct-password');
      expect(unlocked.encKey, equals(encKey));
    });

    test('unlocks vault and returns original mac key', () {
      final encKey = Uint8List(32);
      final macKey = Uint8List.fromList(List.generate(32, (i) => i + 80));
      final mf = makeMasterkeyFile(encKey, macKey, 'pass');
      final unlocked = CryptomatorService.unlockVault(vaultMeta, mf, 'pass');
      expect(unlocked.macKey, equals(macKey));
    });

    test('throws FormatException on wrong password', () {
      final mf = makeMasterkeyFile(
        CryptomatorService.generateMasterKey(),
        CryptomatorService.generateMasterKey(),
        'correct',
      );
      expect(
        () => CryptomatorService.unlockVault(vaultMeta, mf, 'wrong'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unlocked vault references the vault metadata', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final vault = CryptomatorVault(
          vaultPath: '/my/vault',
          masterkeyFilePath: '/my/vault/masterkey.cryptomator');
      final unlocked = CryptomatorService.unlockVault(vault, mf, 'pw');
      expect(unlocked.vault.vaultPath, '/my/vault');
    });

    test('returned keys are 32 bytes each', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final unlocked = CryptomatorService.unlockVault(vaultMeta, mf, 'pw');
      expect(unlocked.encKey.length, 32);
      expect(unlocked.macKey.length, 32);
    });
  });

  // ---------------------------------------------------------------------------
  // scrypt parameter validation
  // ---------------------------------------------------------------------------

  group('scrypt parameter validation', () {
    test('N=0 throws when creating masterkey file', () {
      expect(
        () => CryptomatorService.createMasterkeyFile(
          Uint8List(32), Uint8List(32), 'pw',
          scryptCostParam: 0,
          scryptBlockSize: 8,
        ),
        throwsA(anything),
      );
    });

    test('low N (16) works fine for testing speed', () {
      final mf = CryptomatorService.createMasterkeyFile(
        Uint8List(32), Uint8List(32), 'pw',
        scryptCostParam: 16,
        scryptBlockSize: 1,
      );
      expect(mf.scryptCostParam, 16);
      expect(mf.scryptBlockSize, 1);
    });

    test('recommended N (32768) is stored correctly', () {
      final mf = CryptomatorService.createMasterkeyFile(
        Uint8List(32), Uint8List(32), 'pw',
        scryptCostParam: 32768,
        scryptBlockSize: 8,
      );
      expect(mf.scryptCostParam, 32768);
      expect(mf.scryptBlockSize, 8);
    });
  });

  // ---------------------------------------------------------------------------
  // AES Key Wrap / Unwrap (RFC 3394)
  // ---------------------------------------------------------------------------

  group('AES Key Wrap / Unwrap (RFC 3394)', () {
    test('wrap then unwrap round-trips correctly', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final kek = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final wrapped = CryptomatorService.aesKeyWrap(key, kek);
      final unwrapped = CryptomatorService.aesKeyUnwrap(wrapped, kek);
      expect(unwrapped, equals(key));
    });

    test('wrong KEK fails integrity check with FormatException', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final kek = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final wrongKek = Uint8List.fromList(List.generate(32, (i) => i + 2));
      final wrapped = CryptomatorService.aesKeyWrap(key, kek);
      expect(
        () => CryptomatorService.aesKeyUnwrap(wrapped, wrongKek),
        throwsA(isA<FormatException>()),
      );
    });

    test('wrapped key is 8 bytes longer than original', () {
      final key = Uint8List(32);
      final kek = Uint8List(32);
      final wrapped = CryptomatorService.aesKeyWrap(key, kek);
      expect(wrapped.length, key.length + 8);
    });

    test('different keys wrap to different ciphertext', () {
      final kek = Uint8List(32);
      final k1 = Uint8List.fromList(List.generate(32, (i) => i));
      final k2 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      expect(CryptomatorService.aesKeyWrap(k1, kek),
          isNot(equals(CryptomatorService.aesKeyWrap(k2, kek))));
    });
  });

  // ---------------------------------------------------------------------------
  // Directory ID hashing (SHA-1 → base32)
  // ---------------------------------------------------------------------------

  group('hashDirectoryId', () {
    test('returns 32 upper-case base32 characters', () {
      final macKey = Uint8List(32);
      final hash = CryptomatorService.hashDirectoryId('', macKey);
      expect(hash.length, 32);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(hash), isTrue);
    });

    test('is deterministic for the same inputs', () {
      final macKey = Uint8List.fromList(List.generate(32, (i) => i));
      final h1 = CryptomatorService.hashDirectoryId('dirA', macKey);
      final h2 = CryptomatorService.hashDirectoryId('dirA', macKey);
      expect(h1, h2);
    });

    test('differs for different directory IDs', () {
      final macKey = Uint8List(32);
      expect(CryptomatorService.hashDirectoryId('dir1', macKey),
          isNot(CryptomatorService.hashDirectoryId('dir2', macKey)));
    });

    test('root directory ID (empty string) produces valid 32-char hash', () {
      final macKey = Uint8List(32);
      final hash = CryptomatorService.hashDirectoryId('', macKey);
      expect(hash.length, 32);
    });

    test('hash changes when macKey changes', () {
      final k1 = Uint8List.fromList(List.filled(32, 1));
      final k2 = Uint8List.fromList(List.filled(32, 2));
      expect(CryptomatorService.hashDirectoryId('same', k1),
          isNot(CryptomatorService.hashDirectoryId('same', k2)));
    });
  });

  // ---------------------------------------------------------------------------
  // Filename encryption / decryption round-trip
  // ---------------------------------------------------------------------------

  group('filename encryption / decryption', () {
    late UnlockedVault vault;

    setUp(() => vault = makeUnlockedVault());

    test('round-trip returns original filename', () {
      const name = 'hello.txt';
      const dirId = 'root';
      final enc = CryptomatorService.encryptFilename(name, dirId, vault);
      final dec = CryptomatorService.decryptFilename(enc, dirId, vault);
      expect(dec, name);
    });

    test('encrypted name differs from original', () {
      final enc = CryptomatorService.encryptFilename('secret.doc', 'dir1', vault);
      expect(enc, isNot('secret.doc'));
    });

    test('normal-length filename ends with .c9r', () {
      final enc = CryptomatorService.encryptFilename('short.txt', 'dir', vault);
      expect(enc.endsWith('.c9r'), isTrue);
    });

    test('different dirIds produce different encrypted names for same file', () {
      final enc1 = CryptomatorService.encryptFilename('file.txt', 'dir1', vault);
      final enc2 = CryptomatorService.encryptFilename('file.txt', 'dir2', vault);
      expect(enc1, isNot(enc2));
    });

    test('same filename and dirId always produce the same encrypted name', () {
      final enc1 = CryptomatorService.encryptFilename('same.txt', 'sameDir', vault);
      final enc2 = CryptomatorService.encryptFilename('same.txt', 'sameDir', vault);
      expect(enc1, enc2);
    });

    test('different filenames produce different encrypted names', () {
      final enc1 = CryptomatorService.encryptFilename('file1.txt', 'dir', vault);
      final enc2 = CryptomatorService.encryptFilename('file2.txt', 'dir', vault);
      expect(enc1, isNot(enc2));
    });

    test('decrypting with wrong dirId throws FormatException', () {
      final enc = CryptomatorService.encryptFilename('file.txt', 'dirA', vault);
      expect(
        () => CryptomatorService.decryptFilename(enc, 'dirB', vault),
        throwsA(isA<FormatException>()),
      );
    });

    test('decrypting a .c9s name throws FormatException', () {
      expect(
        () => CryptomatorService.decryptFilename('ABCDEFGHIJ.c9s', 'dir', vault),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Shortened filename threshold (>220 chars)
  // ---------------------------------------------------------------------------

  group('shortened filename threshold', () {
    late UnlockedVault vault;

    setUp(() => vault = makeUnlockedVault());

    test('very long name (200 chars) produces .c9s', () {
      final enc = CryptomatorService.encryptFilename('x' * 200, 'dir', vault);
      expect(enc.endsWith('.c9s'), isTrue);
    });

    test('short name stays .c9r', () {
      final enc = CryptomatorService.encryptFilename('short.txt', 'dir', vault);
      expect(enc.endsWith('.c9r'), isTrue);
    });

    test('output is always .c9r or .c9s regardless of input length', () {
      for (final len in [1, 10, 50, 100, 150, 200]) {
        final enc = CryptomatorService.encryptFilename('a' * len, 'dir', vault);
        expect(enc.endsWith('.c9r') || enc.endsWith('.c9s'), isTrue,
            reason: 'Unexpected extension for length $len');
      }
    });

    test('custom threshold respected: vault with threshold=50 shortens earlier', () {
      final shortThresholdVault = UnlockedVault(
        vault: CryptomatorVault(
          vaultPath: '/v',
          masterkeyFilePath: '/v/mk',
          shorteningThreshold: 50,
        ),
        encKey: vault.encKey,
        macKey: vault.macKey,
      );
      // A 30-char name encrypted will exceed 50-char threshold
      final enc = CryptomatorService.encryptFilename('a' * 30, 'dir', shortThresholdVault);
      expect(enc.endsWith('.c9s'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Path encryption / decryption
  // ---------------------------------------------------------------------------

  group('path encryption / decryption', () {
    late UnlockedVault vault;

    setUp(() => vault = makeUnlockedVault());

    test('encrypted path starts with d/', () {
      final enc = CryptomatorService.encryptPath('documents/report.pdf', vault);
      expect(enc.startsWith('d/'), isTrue);
    });

    test('decrypt reverses encrypt for single-component path', () {
      final enc = CryptomatorService.encryptPath('notes.txt', vault);
      final dec = CryptomatorService.decryptPath(enc, vault);
      expect(dec, 'notes.txt');
    });

    test('decrypt reverses encrypt for two-component path', () {
      final enc = CryptomatorService.encryptPath('folder/file.txt', vault);
      final dec = CryptomatorService.decryptPath(enc, vault);
      expect(dec, 'folder/file.txt');
    });

    test('different paths produce different encrypted paths', () {
      final enc1 = CryptomatorService.encryptPath('a/b.txt', vault);
      final enc2 = CryptomatorService.encryptPath('a/c.txt', vault);
      expect(enc1, isNot(enc2));
    });

    test('path encryption preserves depth (same number of segments before final component)', () {
      // Both single-component paths start with d/<2>/<30>/<filename>
      final enc = CryptomatorService.encryptPath('singlefile.txt', vault);
      final parts = enc.split('/');
      // d / XX / YYY...Y / encryptedName = 4 parts
      expect(parts.length, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // Per-file content key
  // ---------------------------------------------------------------------------

  group('getContentKey', () {
    test('returns 32 bytes', () {
      final vault = makeUnlockedVault();
      final key = CryptomatorService.getContentKey(Uint8List(12), vault);
      expect(key.length, 32);
    });

    test('same nonce produces same key (deterministic)', () {
      final vault = makeUnlockedVault();
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      expect(CryptomatorService.getContentKey(nonce, vault),
          equals(CryptomatorService.getContentKey(nonce, vault)));
    });

    test('different nonces produce different keys', () {
      final vault = makeUnlockedVault();
      final n1 = Uint8List.fromList(List.generate(12, (i) => i));
      final n2 = Uint8List.fromList(List.generate(12, (i) => i + 1));
      expect(CryptomatorService.getContentKey(n1, vault),
          isNot(equals(CryptomatorService.getContentKey(n2, vault))));
    });
  });

  // ---------------------------------------------------------------------------
  // Vault version and model defaults
  // ---------------------------------------------------------------------------

  group('vault version detection', () {
    test('CryptomatorVault defaults to version 8', () {
      final v = CryptomatorVault(
          vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.version, 8);
    });

    test('CryptomatorVault accepts custom version', () {
      final v = CryptomatorVault(
          vaultPath: '/v', masterkeyFilePath: '/v/mk', version: 7);
      expect(v.version, 7);
    });

    test('CryptomatorVault defaults cipherCombo to SIV_GCM', () {
      final v = CryptomatorVault(
          vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.cipherCombo, 'SIV_GCM');
    });

    test('CryptomatorVault defaults shorteningThreshold to 220', () {
      final v = CryptomatorVault(
          vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.shorteningThreshold, 220);
    });

    test('MasterkeyFile stores vault version correctly', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw', version: 8);
      expect(mf.version, 8);
    });
  });

  // ---------------------------------------------------------------------------
  // generateMasterKey
  // ---------------------------------------------------------------------------

  group('generateMasterKey', () {
    test('returns 32 bytes', () {
      expect(CryptomatorService.generateMasterKey().length, 32);
    });

    test('two calls produce different keys', () {
      final k1 = CryptomatorService.generateMasterKey();
      final k2 = CryptomatorService.generateMasterKey();
      expect(k1, isNot(equals(k2)));
    });
  });
}
