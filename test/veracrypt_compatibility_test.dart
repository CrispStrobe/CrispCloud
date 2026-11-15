import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Production-cost fixtures from independent Python/OpenSSL implementations.
// The generator and provenance sit beside the corpus; no production Dart
// encryptor or reduced Argon2 cost is used to generate these expected bytes.
final _corpus = jsonDecode(
  File('test/fixtures/veracrypt/compatibility_vectors.json').readAsStringSync(),
) as Map<String, dynamic>;
final _vectors = (_corpus['vectors'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _vector(String name) =>
    _vectors.singleWhere((entry) => entry['name'] == name);

VeraCryptKdf _kdf(Map<String, dynamic> vector) =>
    VeraCryptKdf.values.byName(vector['kdf'] as String);

VeraCryptUnlockOptions _options(Map<String, dynamic> vector) =>
    VeraCryptUnlockOptions(
      kdf: _kdf(vector),
      pim: vector['pim'] as int,
      trueCryptMode: vector['trueCryptMode'] as bool,
      keyfiles: (vector['keyfiles'] as List)
          .map((value) => base64Decode(value as String))
          .toList(),
    );

Uint8List _header(Map<String, dynamic> vector) =>
    base64Decode(vector['header'] as String);

String _hex(Uint8List data) =>
    data.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

VeraCryptUnlockedVolume? _unlock(Map<String, dynamic> vector) =>
    VeraCryptService.unlockHeader(
      _header(vector),
      vector['password'] as String,
      options: _options(vector),
      containerSizeBytes: vector['containerSize'] as int,
    );

void main() {
  group('independent current and legacy format vectors', () {
    for (final vector in _vectors) {
      test(vector['name'] as String, () {
        final options = _options(vector);
        // Argon2 is exercised by the unlock itself. Avoid doing its complete
        // 64 MiB / 3-pass production derivation twice in the same test.
        if (options.kdf != VeraCryptKdf.argon2id) {
          final key = VeraCryptService.deriveHeaderKey(
            vector['password'] as String,
            Uint8List.sublistView(_header(vector), 0, 64),
            options: options,
          );
          expect(_hex(key), vector['headerKeyHex']);
          key.fillRange(0, key.length, 0);
        }
        final volume = _unlock(vector);
        expect(volume, isNotNull);
        try {
          final header = volume!.header;
          expect(header.trueCryptMode, vector['trueCryptMode']);
          expect(header.version, vector['version']);
          expect(header.sectorSize, vector['sectorSize']);
          expect(header.hiddenVolumeSize, vector['hiddenVolumeSize']);
          expect(header.encryptedAreaOffset, vector['dataOffset']);
          expect(header.encryptedAreaSize, vector['dataSize']);
          expect(header.volumeSize, vector['dataSize']);
          expect(
            VeraCryptService.hashAlgorithmName(header.hashAlgorithmId),
            options.kdf.displayName,
          );
          final cipher = base64Decode(vector['dataCiphertext'] as String);
          final expected = base64Decode(vector['dataPlaintext'] as String);
          final plain = volume.decryptDataUnits(
            cipher,
            absoluteByteOffset: vector['dataOffset'] as int,
          );
          expect(
            plain,
            expected,
            reason: 'XTS units use absolute offsets and reset every 512 bytes',
          );
          expect(
            volume.decryptDataUnits(
              Uint8List.sublistView(cipher, 512),
              absoluteByteOffset: (vector['dataOffset'] as int) + 512,
            ),
            Uint8List.sublistView(expected, 512),
          );
          // Data remains scoped to the selected volume, including hidden ones.
          expect(
            () => volume.decryptDataUnits(cipher, absoluteByteOffset: 0),
            throwsArgumentError,
          );
        } finally {
          volume?.dispose();
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  group('KDF and resource policy', () {
    test('PBKDF2 schedules include legacy VeraCrypt and native TrueCrypt', () {
      for (final kdf in [
        VeraCryptKdf.sha512,
        VeraCryptKdf.sha256,
        VeraCryptKdf.whirlpool,
      ]) {
        expect(VeraCryptService.pbkdf2Iterations(kdf), 500000);
        expect(VeraCryptService.pbkdf2Iterations(kdf, pim: 1), 16000);
        expect(VeraCryptService.pbkdf2Iterations(kdf, pim: 485), 500000);
      }
      expect(VeraCryptService.pbkdf2Iterations(VeraCryptKdf.ripemd160), 655331);
      expect(
        VeraCryptService.pbkdf2Iterations(VeraCryptKdf.ripemd160, pim: 1),
        16000,
      );
      expect(
        VeraCryptService.pbkdf2Iterations(
          VeraCryptKdf.sha512,
          trueCryptMode: true,
        ),
        1000,
      );
      expect(
        VeraCryptService.pbkdf2Iterations(
          VeraCryptKdf.whirlpool,
          trueCryptMode: true,
        ),
        1000,
      );
      expect(
        VeraCryptService.pbkdf2Iterations(
          VeraCryptKdf.ripemd160,
          trueCryptMode: true,
        ),
        2000,
      );
      expect(
        VeraCryptService.pbkdf2Iterations(
          VeraCryptKdf.sha512,
          pim: VeraCryptService.maxPim,
        ),
        2147483000,
      );
    });

    test('Argon2 default and both sides of the cost boundary', () {
      for (final (pim, mib, passes) in [
        (0, 416, 6),
        (1, 64, 3),
        (2, 96, 3),
        (4, 160, 4),
        (12, 416, 6),
        (31, 1024, 13),
        (32, 1024, 14),
        (82, 1024, 64),
      ]) {
        final cost = VeraCryptService.argon2Parameters(pim);
        expect(cost.memoryMiB, mib);
        expect(cost.memoryKiB, mib * 1024);
        expect(cost.iterations, passes);
        expect(cost.parallelism, 1);
        expect(cost.outputLength, 192);
      }
    });

    test('invalid options and resource limits fail before derivation', () {
      for (final options in [
        const VeraCryptUnlockOptions(pim: -1),
        const VeraCryptUnlockOptions(pim: 2147469),
        const VeraCryptUnlockOptions(trueCryptMode: true, pim: 1),
        const VeraCryptUnlockOptions(
          trueCryptMode: true,
          kdf: VeraCryptKdf.sha256,
        ),
        const VeraCryptUnlockOptions(
          trueCryptMode: true,
          kdf: VeraCryptKdf.argon2id,
        ),
        const VeraCryptUnlockOptions(maxArgon2MemoryKiB: 1),
        const VeraCryptUnlockOptions(maxArgon2Iterations: 1025),
        VeraCryptUnlockOptions(keyfiles: [Uint8List(0)]),
        VeraCryptUnlockOptions(
          keyfiles: List.generate(65, (_) => Uint8List(1)),
        ),
      ]) {
        expect(
          () => VeraCryptService.unlockHeader(
            Uint8List(512),
            'pw',
            options: options,
          ),
          throwsArgumentError,
        );
      }
      for (final options in [
        const VeraCryptUnlockOptions(
          kdf: VeraCryptKdf.argon2id,
          pim: 31,
          maxArgon2MemoryKiB: 524288,
        ),
        const VeraCryptUnlockOptions(kdf: VeraCryptKdf.argon2id, pim: 83),
      ]) {
        expect(
          () => VeraCryptService.unlockHeader(
            Uint8List(512),
            'pw',
            options: options,
          ),
          throwsA(isA<VeraCryptResourceLimitException>()),
        );
      }
      expect(
        () => VeraCryptService.unlockHeader(
          Uint8List(512),
          'pw',
          options: const VeraCryptUnlockOptions(kdf: VeraCryptKdf.argon2id),
          testIterations: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => VeraCryptService.unlockHeader(
          Uint8List(512),
          'pw',
          options: const VeraCryptUnlockOptions(pim: 1),
          testIterations: 1,
        ),
        throwsArgumentError,
      );
    });

    test('auto detects legacy hashes without Argon2 allocation', () {
      final vector = _vector('truecrypt_v5_ripemd160');
      final volume = VeraCryptService.unlockHeader(
        _header(vector),
        vector['password'] as String,
        options: const VeraCryptUnlockOptions(trueCryptMode: true),
      );
      expect(volume?.header.hashAlgorithmId, 4);
      volume?.dispose();
      // A deliberately too-small-for-default Argon2 budget is irrelevant to
      // automatic PBKDF2 probing, including an incorrect password.
      expect(
        VeraCryptService.tryDecryptHeader(
          Uint8List(512),
          'pw',
          options: const VeraCryptUnlockOptions(maxArgon2MemoryKiB: 65536),
          testIterations: 1,
        ),
        isNull,
      );
    });
  });

  group('keyfiles and UTF-8 password bytes', () {
    test('independent short, long and keyfile-only mixes', () {
      for (final name in [
        'veracrypt_sha512_keyfiles',
        'veracrypt_sha512_long_keyfiles',
        'veracrypt_sha512_keyfiles_only',
        'truecrypt_v5_keyfiles',
      ]) {
        final vector = _vector(name);
        final options = _options(vector);
        final original = options.keyfiles.map(Uint8List.fromList).toList();
        final mixed = VeraCryptService.applyKeyfiles(
          vector['password'] as String,
          options.keyfiles,
          trueCryptMode: options.trueCryptMode,
        );
        expect(_hex(mixed), vector['mixedPasswordHex']);
        expect(
          options.keyfiles,
          original,
          reason: 'caller retains keyfile ownership',
        );
        expect(
          VeraCryptService.applyKeyfiles(
            vector['password'] as String,
            options.keyfiles.reversed.toList(),
            trueCryptMode: options.trueCryptMode,
          ),
          mixed,
          reason: 'each keyfile resets the cursor and raw CRC state',
        );
      }
    });

    test('only the first MiB of each keyfile contributes', () {
      final vector = _corpus['keyfileTruncation'] as Map<String, dynamic>;
      final bytes = Uint8List.fromList(List.generate(1048576, (i) => i % 256));
      final longer = Uint8List(1048600)..setRange(0, bytes.length, bytes);
      longer.fillRange(bytes.length, longer.length, 0xab);
      for (final keyfile in [bytes, longer]) {
        final mixed = VeraCryptService.applyKeyfiles(
          vector['password'] as String,
          [keyfile],
        );
        expect(_hex(mixed), vector['mixedPasswordHex']);
      }
    });

    test(
      'byte lengths and empty keyfiles are checked without logging secrets',
      () {
        for (final password in ['a' * 129, 'ä' * 65]) {
          expect(
            () => VeraCryptService.applyKeyfiles(password, []),
            throwsArgumentError,
          );
        }
        expect(
          () =>
              VeraCryptService.applyKeyfiles('ä' * 33, [], trueCryptMode: true),
          throwsArgumentError,
        );
        expect(
          () => VeraCryptService.applyKeyfiles('pw', [Uint8List(0)]),
          throwsArgumentError,
        );
        expect(VeraCryptService.applyKeyfiles('ä' * 64, []).length, 128);
        expect(
          VeraCryptService.applyKeyfiles('', [
            Uint8List.fromList([1]),
          ]).length,
          64,
        );
        final options = VeraCryptUnlockOptions(
          pim: 123456,
          keyfiles: [
            Uint8List.fromList([12, 34, 56]),
          ],
        );
        expect(options.toString(), isNot(contains('123456')));
        expect(options.toString(), isNot(contains('[12, 34, 56]')));
      },
    );
  });

  group('wrong credentials and invalid headers', () {
    test('wrong password, PIM and keyfile do not unlock', () {
      final vector = _vector('veracrypt_sha512_keyfiles');
      final options = _options(vector);
      expect(
        VeraCryptService.unlockHeader(
          _header(vector),
          'wrong',
          options: options,
        ),
        isNull,
      );
      expect(
        VeraCryptService.unlockHeader(
          _header(vector),
          vector['password'] as String,
          options: VeraCryptUnlockOptions(
            kdf: options.kdf,
            pim: 2,
            keyfiles: options.keyfiles,
          ),
        ),
        isNull,
      );
      final changed = options.keyfiles.map(Uint8List.fromList).toList();
      changed.first[0] ^= 1;
      expect(
        VeraCryptService.unlockHeader(
          _header(vector),
          vector['password'] as String,
          options: VeraCryptUnlockOptions(
            kdf: options.kdf,
            pim: 1,
            keyfiles: changed,
          ),
        ),
        isNull,
      );
    });

    test('native TRUE headers require native TrueCrypt mode', () {
      final vector = _vector('truecrypt_v5_sha512');
      expect(
        VeraCryptService.tryDecryptHeader(
          _header(vector),
          vector['password'] as String,
          options: const VeraCryptUnlockOptions(kdf: VeraCryptKdf.sha512),
          testIterations: 1000,
        ),
        isNull,
      );
    });

    test(
      'CRC, versions, flags, bounds and web-unsafe integers are rejected',
      () {
        final base = _vector('truecrypt_v5_sha512');
        for (final invalid
            in (_corpus['invalidHeaders'] as List)
                .cast<Map<String, dynamic>>()) {
          final volume = VeraCryptService.unlockHeader(
            base64Decode(invalid['header'] as String),
            base['password'] as String,
            options: _options(base),
            containerSizeBytes: base['containerSize'] as int,
          );
          try {
            expect(volume, isNull, reason: invalid['name'] as String);
          } finally {
            volume?.dispose();
          }
        }
        final vc = _vector('veracrypt_sha512_pim1');
        expect(
          VeraCryptService.unlockHeader(
            base64Decode(_corpus['futureVeraCryptHeader'] as String),
            vc['password'] as String,
            options: _options(vc),
          ),
          isNull,
        );
      },
    );
  });

  test('session disposal, read bounds and metadata keep keys private', () {
    final vector = _vector('truecrypt_v5_sha512');
    final volume = _unlock(vector)!;
    final cipher = base64Decode(vector['dataCiphertext'] as String);
    final offset = vector['dataOffset'] as int;
    expect(volume.isClosed, isFalse);
    expect(
      () => volume.decryptDataUnits(cipher, absoluteByteOffset: offset + 1),
      throwsArgumentError,
    );
    expect(
      () => volume.decryptDataUnits(Uint8List(17), absoluteByteOffset: offset),
      throwsArgumentError,
    );
    expect(
      () => volume.decryptDataUnits(
        cipher,
        absoluteByteOffset: offset + (vector['dataSize'] as int),
      ),
      throwsRangeError,
    );
    final metadata = jsonEncode(volume.header.toJson());
    expect(metadata, isNot(contains(vector['headerKeyHex'] as String)));
    expect(metadata, isNot(contains(vector['password'] as String)));
    expect(volume.toString(), 'VeraCryptUnlockedVolume(open)');
    volume.close();
    volume.dispose();
    expect(volume.isClosed, isTrue);
    expect(
      () => volume.decryptDataUnits(cipher, absoluteByteOffset: offset),
      throwsStateError,
    );
    expect(volume.toString(), 'VeraCryptUnlockedVolume(locked)');
  });
}
