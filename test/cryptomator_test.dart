// test/cryptomator_test.dart
//
// Unit tests for CryptomatorService, CryptomatorVault, VaultConfig,
// MasterkeyFile, and UnlockedVault.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:crisp_cloud/services/cryptomator_service.dart';

void main() {
  String signedConfig(
    Uint8List encKey,
    Uint8List macKey, {
    String algorithm = 'HS256',
    int format = 8,
    String cipherCombo = 'SIV_GCM',
    int threshold = 220,
  }) {
    String segment(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final header = segment({
      'alg': algorithm,
      'typ': 'JWT',
      'kid': 'masterkeyfile:masterkey.cryptomator',
    });
    final payload = segment({
      'format': format,
      'cipherCombo': cipherCombo,
      'shorteningThreshold': threshold,
    });
    final hash = algorithm == 'HS384'
        ? crypto.sha384
        : algorithm == 'HS512'
        ? crypto.sha512
        : crypto.sha256;
    final signature = base64Url
        .encode(
          crypto.Hmac(hash, [
            ...encKey,
            ...macKey,
          ]).convert(ascii.encode('$header.$payload')).bytes,
        )
        .replaceAll('=', '');
    return '$header.$payload.$signature';
  }

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
      final mf = makeMasterkeyFile(
        Uint8List(32),
        Uint8List(32),
        'pw',
        version: 8,
      );
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

    test(
      'primaryMasterKey is wrapped: 40 bytes (32 + 8 RFC 3394 overhead)',
      () {
        final mf = makeMasterkeyFile(
          Uint8List.fromList(List.generate(32, (i) => i)),
          Uint8List(32),
          'test',
        );
        final parsed = MasterkeyFile.fromJson(jsonEncode(mf.toJson()));
        expect(parsed.primaryMasterKey.length, 40);
      },
    );

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
      const bad =
          '{"version":8,"scryptCostParam":32768,"scryptBlockSize":8,'
          '"primaryMasterKey":"AAAA","hmacMasterKey":"AAAA","versionMac":"AAAA"}';
      expect(() => MasterkeyFile.fromJson(bad), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------------------
  // VaultConfig (JWT base64 payload parsing)
  // ---------------------------------------------------------------------------

  group('VaultConfig JWT parsing', () {
    String makeJwt(Map<String, dynamic> payload, {String? keyId}) {
      // JWT segments are base64url without padding
      final header = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'alg': 'HS256',
                'typ': 'JWT',
                if (keyId != null) 'kid': keyId,
              }),
            ),
          )
          .replaceAll('=', '');
      final body = base64Url
          .encode(utf8.encode(jsonEncode(payload)))
          .replaceAll('=', '');
      return '$header.$body.fakesig';
    }

    test('parses format version', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }),
      );
      expect(config.version, 8);
    });

    test('parses cipherCombo', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }),
      );
      expect(config.cipherCombo, 'SIV_GCM');
    });

    test('parses shorteningThreshold', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }),
      );
      expect(config.shorteningThreshold, 220);
    });

    test('parses optional keyId', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }, keyId: 'key123'),
      );
      expect(config.keyId, 'key123');
    });

    test('keyId is null when not present', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }),
      );
      expect(config.keyId, isNull);
    });

    test('rejects missing format instead of assuming compatibility', () {
      expect(
        () => VaultConfig.fromJwt(
          makeJwt({'cipherCombo': 'SIV_GCM', 'shorteningThreshold': 220}),
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException on non-JWT string (no dots)', () {
      expect(
        () => VaultConfig.fromJwt('notajwt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('toString contains version and cipher combo', () {
      final config = VaultConfig.fromJwt(
        makeJwt({
          'format': 8,
          'cipherCombo': 'SIV_GCM',
          'shorteningThreshold': 220,
        }),
      );
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
        isFalse,
      );
    });

    test('returns false when masterkey.cryptomator is missing', () {
      expect(
        CryptomatorService.detectVault('/p', ['vault.cryptomator', 'd']),
        isFalse,
      );
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
      final unlocked = CryptomatorService.unlockVault(
        vaultMeta,
        mf,
        'correct-password',
        vaultConfigJwt: signedConfig(encKey, macKey),
      );
      expect(unlocked.encKey, equals(encKey));
    });

    // Independent fixture: Python unicodedata.normalize('NFC', password),
    // hashlib.scrypt(n=16, r=1, p=1, dklen=32), cryptography.aes_key_wrap,
    // and hmac.digest with SHA-256. Salt is bytes 0..31; encKey is 1..32;
    // macKey is 33..64. NFC UTF-8 is c3a42dc3852de285a0 and the KEK is
    // 8deef1058bb68fcfd9ebffead71d028ac0d7ed83f660db5781f1280b2f27cdde.
    // Cryptomator has required NFC passwords since vault format 6:
    // https://docs.cryptomator.org/misc/vault-format-history/#format-6
    const nfcMasterkeyJson = '''{
      "version": 999,
      "scryptSalt": "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
      "scryptCostParam": 16,
      "scryptBlockSize": 1,
      "primaryMasterKey": "9dn6SEdDc8JseB4roUE7G5kQpM6UPe5nBxiAOtBUuTxanFORzgJ2PQ==",
      "hmacMasterKey": "dp6AlLdAnaaZCl6l1JqEUr2oCKrWQefmQAu1ru25iw3lcbAsi1IS1g==",
      "versionMac": "2YWeJKrYJPlk4eHzUcof0MWu1Rd33T4rG4q6uzIBX5c="
    }''';
    const nfcConfig =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im1hc3RlcmtleWZpbGU6bWFzdGVya2V5LmNyeXB0b21hdG9yIn0.'
        'eyJmb3JtYXQiOjgsImNpcGhlckNvbWJvIjoiU0lWX0dDTSIsInNob3J0ZW5pbmdUaHJlc2hvbGQiOjIyMCwianRpIjoiaW5kZXBlbmRlbnQtbmZjLWZpeHR1cmUifQ.'
        'jaHK1YMACL-tCbddWAax-5nc6T0cOrE4HkCeWadfM7M';

    test('independent masterkey fixture accepts both NFC password forms', () {
      final mf = MasterkeyFile.fromJson(nfcMasterkeyJson);
      for (final password in [
        '\u00e4-\u00c5-\u2160',
        'a\u0308-A\u030a-\u2160',
      ]) {
        final unlocked = CryptomatorService.unlockVault(
          vaultMeta,
          mf,
          password,
          vaultConfigJwt: nfcConfig,
        );
        expect(
          unlocked.encKey,
          Uint8List.fromList(List.generate(32, (i) => i + 1)),
        );
        expect(
          unlocked.macKey,
          Uint8List.fromList(List.generate(32, (i) => i + 33)),
        );
        expect(unlocked.vault.shorteningThreshold, 220);
      }
    });

    test(
      'password normalization preserves compatibility-distinct characters',
      () {
        // U+2160 ROMAN NUMERAL ONE becomes ASCII I under NFKC, but not NFC.
        expect(
          () => CryptomatorService.unlockVault(
            vaultMeta,
            MasterkeyFile.fromJson(nfcMasterkeyJson),
            '\u00e4-\u00c5-I',
            vaultConfigJwt: nfcConfig,
          ),
          throwsFormatException,
        );
      },
    );

    test('independent JWT fixture requires encryption key before MAC key', () {
      final reversedKeyConfig = nfcConfig.replaceFirst(
        'jaHK1YMACL-tCbddWAax-5nc6T0cOrE4HkCeWadfM7M',
        'MNnLfIJe1nObZr8ZSDgCV61bPxhzUcG00xgQ6TCaR3I',
      );
      expect(
        () => CryptomatorService.unlockVault(
          vaultMeta,
          MasterkeyFile.fromJson(nfcMasterkeyJson),
          '\u00e4-\u00c5-\u2160',
          vaultConfigJwt: reversedKeyConfig,
        ),
        throwsFormatException,
      );
    });

    test(
      'masterkey creation normalizes decomposed passwords before wrapping',
      () {
        final encKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
        final macKey = Uint8List.fromList(List.generate(32, (i) => i + 33));
        final mf = makeMasterkeyFile(encKey, macKey, 'a\u0308-A\u030a-\u2160');
        final unlocked = CryptomatorService.unlockVault(
          vaultMeta,
          mf,
          '\u00e4-\u00c5-\u2160',
          vaultConfigJwt: nfcConfig,
        );
        expect(unlocked.encKey, encKey);
        expect(unlocked.macKey, macKey);
      },
    );

    test('unlocks vault and returns original mac key', () {
      final encKey = Uint8List(32);
      final macKey = Uint8List.fromList(List.generate(32, (i) => i + 80));
      final mf = makeMasterkeyFile(encKey, macKey, 'pass');
      final unlocked = CryptomatorService.unlockVault(
        vaultMeta,
        mf,
        'pass',
        vaultConfigJwt: signedConfig(encKey, macKey),
      );
      expect(unlocked.macKey, equals(macKey));
    });

    test('throws FormatException on wrong password', () {
      final mf = makeMasterkeyFile(
        CryptomatorService.generateMasterKey(),
        CryptomatorService.generateMasterKey(),
        'correct',
      );
      expect(
        () => CryptomatorService.unlockVault(
          vaultMeta,
          mf,
          'wrong',
          vaultConfigJwt: signedConfig(Uint8List(32), Uint8List(32)),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('unlocked vault references the vault metadata', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final vault = CryptomatorVault(
        vaultPath: '/my/vault',
        masterkeyFilePath: '/my/vault/masterkey.cryptomator',
      );
      final unlocked = CryptomatorService.unlockVault(
        vault,
        mf,
        'pw',
        vaultConfigJwt: signedConfig(Uint8List(32), Uint8List(32)),
      );
      expect(unlocked.vault.vaultPath, '/my/vault');
    });

    test('returned keys are 32 bytes each', () {
      final mf = makeMasterkeyFile(Uint8List(32), Uint8List(32), 'pw');
      final unlocked = CryptomatorService.unlockVault(
        vaultMeta,
        mf,
        'pw',
        vaultConfigJwt: signedConfig(Uint8List(32), Uint8List(32)),
      );
      expect(unlocked.encKey.length, 32);
      expect(unlocked.macKey.length, 32);
    });

    test(
      'rejects unsigned or modified vault configuration before unlocking',
      () {
        final key = Uint8List(32);
        final mf = makeMasterkeyFile(key, key, 'pw');
        final jwt = signedConfig(key, key);
        final parts = jwt.split('.');
        final changedPayload = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'format': 8,
                  'cipherCombo': 'SIV_GCM',
                  'shorteningThreshold': 50,
                }),
              ),
            )
            .replaceAll('=', '');
        for (final token in [
          '${parts[0]}.$changedPayload.${parts[2]}',
          signedConfig(key, key, algorithm: 'none'),
        ]) {
          expect(
            () => CryptomatorService.unlockVault(
              vaultMeta,
              mf,
              'pw',
              vaultConfigJwt: token,
            ),
            throwsFormatException,
          );
        }
      },
    );

    test('authenticates supported JWT algorithms and uses signed metadata', () {
      final key = Uint8List(32);
      final mf = makeMasterkeyFile(key, key, 'pw');
      for (final algorithm in ['HS256', 'HS384', 'HS512']) {
        final unlocked = CryptomatorService.unlockVault(
          vaultMeta,
          mf,
          'pw',
          vaultConfigJwt: signedConfig(
            key,
            key,
            algorithm: algorithm,
            threshold: 50,
          ),
        );
        expect(unlocked.vault.shorteningThreshold, 50);
      }
    });

    test('does not reinterpret an authenticated unsupported cipher combo', () {
      final key = Uint8List(32);
      final mf = makeMasterkeyFile(key, key, 'pw');
      expect(
        () => CryptomatorService.unlockVault(
          vaultMeta,
          mf,
          'pw',
          vaultConfigJwt: signedConfig(key, key, cipherCombo: 'SIV_CTRMAC'),
        ),
        throwsUnsupportedError,
      );
    });

    test(
      'rejects attacker-controlled excessive scrypt work before allocation',
      () {
        final key = Uint8List(32);
        final original = makeMasterkeyFile(key, key, 'pw').toJson();
        final excessive = MasterkeyFile.fromJson(
          jsonEncode({...original, 'scryptCostParam': 1073741824}),
        );
        expect(
          () => CryptomatorService.unlockVault(
            vaultMeta,
            excessive,
            'pw',
            vaultConfigJwt: signedConfig(key, key),
          ),
          throwsFormatException,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // scrypt parameter validation
  // ---------------------------------------------------------------------------

  group('scrypt parameter validation', () {
    test('N=0 throws when creating masterkey file', () {
      expect(
        () => CryptomatorService.createMasterkeyFile(
          Uint8List(32),
          Uint8List(32),
          'pw',
          scryptCostParam: 0,
          scryptBlockSize: 8,
        ),
        throwsA(anything),
      );
    });

    test('low N (16) works fine for testing speed', () {
      final mf = CryptomatorService.createMasterkeyFile(
        Uint8List(32),
        Uint8List(32),
        'pw',
        scryptCostParam: 16,
        scryptBlockSize: 1,
      );
      expect(mf.scryptCostParam, 16);
      expect(mf.scryptBlockSize, 1);
    });

    test('recommended N (32768) is stored correctly', () {
      final mf = CryptomatorService.createMasterkeyFile(
        Uint8List(32),
        Uint8List(32),
        'pw',
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
      expect(
        CryptomatorService.aesKeyWrap(k1, kek),
        isNot(equals(CryptomatorService.aesKeyWrap(k2, kek))),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Directory ID hashing (SHA-1 → base32)
  // ---------------------------------------------------------------------------

  group('hashDirectoryId', () {
    test('matches an independent AES-256-SIV/SHA-1 reference vector', () {
      // Python cryptography AESSIV(macKey || encKey), no associated data;
      // SHA-1 and base32 as in Cryptomator's documented format.
      final vault = makeUnlockedVault();
      expect(
        CryptomatorService.hashDirectoryId('', vault),
        'KQ2C44Z5KIYRKXJ5PBVHKV5YV6HJUS7I',
      );
      expect(
        CryptomatorService.hashDirectoryId('dirA', vault),
        'TDFLGE7DK63RSGCDQ7MYMM4O4DVBDP4A',
      );
    });

    test('returns 32 upper-case base32 characters', () {
      final macKey = Uint8List(32);
      final hash = CryptomatorService.hashDirectoryId(
        '',
        makeUnlockedVault(macKey: macKey),
      );
      expect(hash.length, 32);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(hash), isTrue);
    });

    test('is deterministic for the same inputs', () {
      final macKey = Uint8List.fromList(List.generate(32, (i) => i));
      final h1 = CryptomatorService.hashDirectoryId(
        'dirA',
        makeUnlockedVault(macKey: macKey),
      );
      final h2 = CryptomatorService.hashDirectoryId(
        'dirA',
        makeUnlockedVault(macKey: macKey),
      );
      expect(h1, h2);
    });

    test('differs for different directory IDs', () {
      final macKey = Uint8List(32);
      expect(
        CryptomatorService.hashDirectoryId(
          'dir1',
          makeUnlockedVault(macKey: macKey),
        ),
        isNot(
          CryptomatorService.hashDirectoryId(
            'dir2',
            makeUnlockedVault(macKey: macKey),
          ),
        ),
      );
    });

    test('root directory ID (empty string) produces valid 32-char hash', () {
      final macKey = Uint8List(32);
      final hash = CryptomatorService.hashDirectoryId(
        '',
        makeUnlockedVault(macKey: macKey),
      );
      expect(hash.length, 32);
    });

    test('hash changes when macKey changes', () {
      final k1 = Uint8List.fromList(List.filled(32, 1));
      final k2 = Uint8List.fromList(List.filled(32, 2));
      expect(
        CryptomatorService.hashDirectoryId(
          'same',
          makeUnlockedVault(macKey: k1),
        ),
        isNot(
          CryptomatorService.hashDirectoryId(
            'same',
            makeUnlockedVault(macKey: k2),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Filename encryption / decryption round-trip
  // ---------------------------------------------------------------------------

  group('filename encryption / decryption', () {
    late UnlockedVault vault;

    setUp(() => vault = makeUnlockedVault());

    test('matches independent AES-256-SIV filename vectors', () {
      // Generated independently with Python cryptography's AESSIV, whose
      // combined key order is macKey || encKey (RFC 5297).
      const encrypted = 'dJygEFc8egW-YczF1CDvs4lwMSq_q6254w==.c9r';
      expect(
        CryptomatorService.encryptFilename('hello.txt', 'root', vault),
        encrypted,
      );
      expect(
        CryptomatorService.decryptFilename(encrypted, 'root', vault),
        'hello.txt',
      );
      expect(
        CryptomatorService.encryptFilename('aaaabbbbccccdddd', '', vault),
        'BOzextyFmaBLU__VgdatZtPBVrF2ALBjjsKC-lPIYSw=.c9r',
      );
    });

    test('normalizes canonically equivalent Unicode names to NFC', () {
      expect(
        CryptomatorService.encryptFilename('a\u0308.txt', '', vault),
        'QqUemGxhuaB8HfSB81RdnOxDpSZALw==.c9r',
      );
      expect(
        CryptomatorService.encryptFilename('ä.txt', '', vault),
        'QqUemGxhuaB8HfSB81RdnOxDpSZALw==.c9r',
      );
    });

    test('rejects malformed base64url instead of ignoring characters', () {
      expect(
        () => CryptomatorService.decryptFilename('!!invalid!!.c9r', '', vault),
        throwsFormatException,
      );
    });

    test('round-trip returns original filename', () {
      const name = 'hello.txt';
      const dirId = 'root';
      final enc = CryptomatorService.encryptFilename(name, dirId, vault);
      final dec = CryptomatorService.decryptFilename(enc, dirId, vault);
      expect(dec, name);
    });

    test('encrypted name differs from original', () {
      final enc = CryptomatorService.encryptFilename(
        'secret.doc',
        'dir1',
        vault,
      );
      expect(enc, isNot('secret.doc'));
    });

    test('normal-length filename ends with .c9r', () {
      final enc = CryptomatorService.encryptFilename('short.txt', 'dir', vault);
      expect(enc.endsWith('.c9r'), isTrue);
    });

    test(
      'different dirIds produce different encrypted names for same file',
      () {
        final enc1 = CryptomatorService.encryptFilename(
          'file.txt',
          'dir1',
          vault,
        );
        final enc2 = CryptomatorService.encryptFilename(
          'file.txt',
          'dir2',
          vault,
        );
        expect(enc1, isNot(enc2));
      },
    );

    test('same filename and dirId always produce the same encrypted name', () {
      final enc1 = CryptomatorService.encryptFilename(
        'same.txt',
        'sameDir',
        vault,
      );
      final enc2 = CryptomatorService.encryptFilename(
        'same.txt',
        'sameDir',
        vault,
      );
      expect(enc1, enc2);
    });

    test('different filenames produce different encrypted names', () {
      final enc1 = CryptomatorService.encryptFilename(
        'file1.txt',
        'dir',
        vault,
      );
      final enc2 = CryptomatorService.encryptFilename(
        'file2.txt',
        'dir',
        vault,
      );
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
        () =>
            CryptomatorService.decryptFilename('ABCDEFGHIJ.c9s', 'dir', vault),
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

    test('returns the required reversible metadata for shortened entries', () {
      final name = CryptomatorService.encryptFilenameMetadata(
        'x' * 200,
        'dir',
        vault,
      );
      expect(name.entryName, 'odmgEOsk7EwE_dEG_9bAaI1moo0=.c9s');
      expect(name.isShortened, isTrue);
      expect(
        CryptomatorService.decryptFilename(name.fullName, 'dir', vault),
        'x' * 200,
      );
    });

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
        expect(
          enc.endsWith('.c9r') || enc.endsWith('.c9s'),
          isTrue,
          reason: 'Unexpected extension for length $len',
        );
      }
    });

    test(
      'custom threshold respected: vault with threshold=50 shortens earlier',
      () {
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
        final enc = CryptomatorService.encryptFilename(
          'a' * 30,
          'dir',
          shortThresholdVault,
        );
        expect(enc.endsWith('.c9s'), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Path encryption / decryption
  // ---------------------------------------------------------------------------

  group('path encryption / decryption', () {
    late UnlockedVault vault;

    setUp(() => vault = makeUnlockedVault());

    test('encrypted path starts with d/', () {
      final enc = CryptomatorService.encryptPath('report.pdf', vault);
      expect(enc.startsWith('d/'), isTrue);
    });

    test('decrypt reverses encrypt for single-component path', () {
      final enc = CryptomatorService.encryptPath('notes.txt', vault);
      final dec = CryptomatorService.decryptPath(enc, vault);
      expect(dec, 'notes.txt');
    });

    test('nested paths require real dir.c9r metadata', () {
      expect(
        () => CryptomatorService.encryptPath('folder/file.txt', vault),
        throwsUnsupportedError,
      );
    });

    test('rejects a path claiming a different root directory', () {
      final encrypted = CryptomatorService.encryptPath('notes.txt', vault);
      final differentRoot = encrypted.replaceFirst('d/KQ/', 'd/AA/');
      expect(
        () => CryptomatorService.decryptPath(differentRoot, vault),
        throwsFormatException,
      );
    });

    test('different paths produce different encrypted paths', () {
      final enc1 = CryptomatorService.encryptPath('b.txt', vault);
      final enc2 = CryptomatorService.encryptPath('c.txt', vault);
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
    // Cryptomator cryptolib v2 FileHeaderCryptorImplTest's published fixture.
    // https://github.com/cryptomator/cryptolib/blob/fa549035bc6729ba550afee1da23d5829fc160fb/src/test/java/org/cryptomator/cryptolib/v2/FileHeaderCryptorImplTest.java
    const encoded =
        'AAAAAAAAAAAAAAAAMVi/wrKflJEHTsXTuvOdGHJgA8o3pip00aL1jnUGNY7dSrEoTUrhey+maVG6P0F2RBmZR74SjU0=';

    test(
      'extracts the real random key from an authenticated upstream header',
      () {
        final vault = makeUnlockedVault(
          encKey: Uint8List(32),
          macKey: Uint8List(32),
        );
        expect(
          CryptomatorService.getContentKey(base64.decode(encoded), vault),
          Uint8List(32),
        );
      },
    );

    test('rejects changed GCM tag and wrong master key', () {
      final vault = makeUnlockedVault(
        encKey: Uint8List(32),
        macKey: Uint8List(32),
      );
      final tampered = base64.decode(encoded)..[67] ^= 1;
      expect(
        () => CryptomatorService.getContentKey(tampered, vault),
        throwsFormatException,
      );
      expect(
        () => CryptomatorService.getContentKey(
          base64.decode(encoded),
          makeUnlockedVault(),
        ),
        throwsFormatException,
      );
    });

    test('a nonce alone cannot recover the file content key', () {
      expect(
        () => CryptomatorService.getContentKey(
          Uint8List(12),
          makeUnlockedVault(),
        ),
        throwsFormatException,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Vault version and model defaults
  // ---------------------------------------------------------------------------

  group('vault version detection', () {
    test('CryptomatorVault defaults to version 8', () {
      final v = CryptomatorVault(vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.version, 8);
    });

    test('CryptomatorVault accepts custom version', () {
      final v = CryptomatorVault(
        vaultPath: '/v',
        masterkeyFilePath: '/v/mk',
        version: 7,
      );
      expect(v.version, 7);
    });

    test('CryptomatorVault defaults cipherCombo to SIV_GCM', () {
      final v = CryptomatorVault(vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.cipherCombo, 'SIV_GCM');
    });

    test('CryptomatorVault defaults shorteningThreshold to 220', () {
      final v = CryptomatorVault(vaultPath: '/v', masterkeyFilePath: '/v/mk');
      expect(v.shorteningThreshold, 220);
    });

    test('MasterkeyFile stores vault version correctly', () {
      final mf = makeMasterkeyFile(
        Uint8List(32),
        Uint8List(32),
        'pw',
        version: 8,
      );
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
