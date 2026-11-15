// lib/services/veracrypt_service.dart
//
// Portable, read-only VeraCrypt / TrueCrypt AES-XTS container cryptography.
// Passwords and volume keys belong to an ephemeral unlock session; metadata
// models never contain key material. Native OS mounts remain a separate API.
//
// VeraCrypt volume header layout (512 bytes):
//   [0..63]    Salt (64 bytes) — passed to PBKDF2 key derivation
//   [64..511]  Encrypted area (448 bytes) — decrypted with derived key
//
// Inside the decrypted area (offsets relative to start of decrypted block):
//   [0..3]     Magic "VERA" (0x56455241)
//   [4..5]     Header format version
//   [6..7]     Minimum program version
//   [8..11]    CRC-32 of decrypted key material [192..447]
//   [36..43]   Volume size (bytes)
//   [44..51]   Encrypted area offset (bytes from start of volume)
//   [52..59]   Encrypted area size (bytes)
//   [60..63]   Volume flags
//   [64..67]   Volume sector size
//   [188..191] CRC-32 of decrypted header [0..187]
//   [192..447] Volume key material (NOT algorithm identifiers)
//
// https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:pointycastle/export.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Represents a VeraCrypt container file (not yet unlocked).
class VeraCryptContainer {
  final String path;
  final int sizeBytes;
  final String? encryptionAlgorithm;
  final String? hashAlgorithm;
  final bool mounted;

  const VeraCryptContainer({
    required this.path,
    required this.sizeBytes,
    this.encryptionAlgorithm,
    this.hashAlgorithm,
    this.mounted = false,
  });

  VeraCryptContainer copyWith({
    String? path,
    int? sizeBytes,
    String? encryptionAlgorithm,
    String? hashAlgorithm,
    bool? mounted,
  }) => VeraCryptContainer(
    path: path ?? this.path,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
    hashAlgorithm: hashAlgorithm ?? this.hashAlgorithm,
    mounted: mounted ?? this.mounted,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'sizeBytes': sizeBytes,
    'encryptionAlgorithm': encryptionAlgorithm,
    'hashAlgorithm': hashAlgorithm,
    'mounted': mounted,
  };

  factory VeraCryptContainer.fromJson(Map<String, dynamic> map) =>
      VeraCryptContainer(
        path: map['path'] as String,
        sizeBytes: (map['sizeBytes'] as num).toInt(),
        encryptionAlgorithm: map['encryptionAlgorithm'] as String?,
        hashAlgorithm: map['hashAlgorithm'] as String?,
        mounted: map['mounted'] as bool? ?? false,
      );

  @override
  String toString() =>
      'VeraCryptContainer(path=$path, size=$sizeBytes, algo=$encryptionAlgorithm, hash=$hashAlgorithm, mounted=$mounted)';
}

/// Parsed VeraCrypt volume header (after successful decryption).
class VeraCryptVolumeHeader {
  static const List<int> magicBytes = [0x56, 0x45, 0x52, 0x41]; // "VERA"

  /// The 64-byte salt from the raw header (bytes 0–63).
  final Uint8List salt;

  /// Byte offset of the encrypted area from the start of the volume.
  final int encryptedAreaOffset;

  /// Size of the encrypted area in bytes.
  final int encryptedAreaSize;

  /// Volume sector size in bytes (typically 512).
  final int sectorSize;

  /// Header format version.
  final int version;

  /// Locally resolved algorithm identifier (not a field stored in the header).
  final int encryptionAlgorithmId;

  /// Locally resolved KDF identifier (not a field stored in the header).
  final int hashAlgorithmId;

  /// Total volume size in bytes.
  final int volumeSize;

  /// True for a native TrueCrypt header, not a converted VeraCrypt header.
  final bool trueCryptMode;

  /// Zero for an ordinary volume; otherwise the hidden volume's byte length.
  final int hiddenVolumeSize;

  final int requiredVersion;
  final int flags;

  const VeraCryptVolumeHeader({
    required this.salt,
    required this.encryptedAreaOffset,
    required this.encryptedAreaSize,
    required this.sectorSize,
    required this.version,
    required this.encryptionAlgorithmId,
    required this.hashAlgorithmId,
    required this.volumeSize,
    this.trueCryptMode = false,
    this.hiddenVolumeSize = 0,
    this.requiredVersion = 0,
    this.flags = 0,
  });

  Map<String, dynamic> toJson() => {
    'salt': base64.encode(salt),
    'encryptedAreaOffset': encryptedAreaOffset,
    'encryptedAreaSize': encryptedAreaSize,
    'sectorSize': sectorSize,
    'version': version,
    'encryptionAlgorithmId': encryptionAlgorithmId,
    'hashAlgorithmId': hashAlgorithmId,
    'volumeSize': volumeSize,
    'trueCryptMode': trueCryptMode,
    'hiddenVolumeSize': hiddenVolumeSize,
    'requiredVersion': requiredVersion,
    'flags': flags,
  };

  @override
  String toString() =>
      'VeraCryptVolumeHeader(version=$version, sectorSize=$sectorSize, '
      'encAlgo=$encryptionAlgorithmId, hashAlgo=$hashAlgorithmId)';
}

/// Supported derivations for the bundled AES-XTS reader. Auto deliberately
/// excludes Argon2id: selecting it explicitly avoids surprise 416 MiB work on
/// every wrong PBKDF2 password. No PIM or KDF is discoverable from the salt.
enum VeraCryptKdf {
  auto,
  sha512,
  sha256,
  whirlpool,
  ripemd160,
  argon2id;

  String get displayName => switch (this) {
    auto => 'Automatic (PBKDF2)',
    sha512 => 'SHA-512',
    sha256 => 'SHA-256',
    whirlpool => 'Whirlpool',
    ripemd160 => 'RIPEMD-160',
    argon2id => 'Argon2id',
  };
}

/// Per-attempt credentials and resource policy. These must never be persisted
/// or logged. The caller owns [keyfiles]; this service never modifies them.
///
/// The default Argon2 budget permits PIM 0/12 (416 MiB, six passes), and PIMs
/// through 82 (at most 1 GiB / 64 passes). A higher pass budget is explicit,
/// with an absolute 1024-pass ceiling. Budgets never alter derived parameters:
/// an over-budget volume is refused, not retried with weaker settings.
/// PBKDF2 defaults to at most five million iterations per candidate on native
/// builds, with a configurable ceiling of twenty million. Browser attempts
/// have an additional hard limit of one million iterations per candidate.
class VeraCryptUnlockOptions {
  final VeraCryptKdf kdf;
  final int pim;
  final List<Uint8List> keyfiles;
  final bool trueCryptMode;
  final int maxPbkdf2Iterations;
  final int maxArgon2MemoryKiB;
  final int maxArgon2Iterations;

  const VeraCryptUnlockOptions({
    this.kdf = VeraCryptKdf.auto,
    this.pim = 0,
    this.keyfiles = const [],
    this.trueCryptMode = false,
    this.maxPbkdf2Iterations = 5000000,
    this.maxArgon2MemoryKiB = 1048576,
    this.maxArgon2Iterations = 64,
  });

  @override
  String toString() => 'VeraCryptUnlockOptions(credentials redacted)';
}

/// An explicit resource failure, distinguishable from incorrect credentials.
class VeraCryptResourceLimitException implements Exception {
  final String message;
  const VeraCryptResourceLimitException(this.message);

  @override
  String toString() => 'VeraCryptResourceLimitException: $message';
}

class VeraCryptArgon2Parameters {
  final int memoryKiB;
  final int iterations;
  const VeraCryptArgon2Parameters({
    required this.memoryKiB,
    required this.iterations,
  });

  int get memoryMiB => memoryKiB ~/ 1024;
  int get parallelism => 1;
  int get outputLength => 192;
}

/// An ephemeral, read-only AES-XTS key owner. It exposes no keys, password,
/// keyfiles or serialization API. Call [dispose] when locking the container.
///
/// Owned key byte buffers are overwritten on disposal. Dart strings, VM
/// copies, and PointyCastle's internal expanded keys cannot be guaranteed to
/// disappear immediately from managed memory; this is best-effort erasure.
class VeraCryptUnlockedVolume {
  final VeraCryptVolumeHeader header;
  final Uint8List _primaryKey;
  final Uint8List _secondaryKey;
  bool _closed = false;

  VeraCryptUnlockedVolume._(this.header, Uint8List decryptedHeader)
    : _primaryKey = Uint8List.fromList(
        Uint8List.sublistView(decryptedHeader, 192, 224),
      ),
      _secondaryKey = Uint8List.fromList(
        Uint8List.sublistView(decryptedHeader, 224, 256),
      );

  bool get isClosed => _closed;

  /// Decrypt whole 512-byte data units at an absolute container byte offset.
  /// The volume's logical sector size does not change XTS's 512-byte units.
  /// Callers handle unaligned file reads by widening and slicing the result.
  Uint8List decryptDataUnits(
    Uint8List ciphertext, {
    required int absoluteByteOffset,
  }) {
    if (_closed) throw StateError('The encrypted container is locked.');
    if (absoluteByteOffset < header.encryptedAreaOffset ||
        absoluteByteOffset > VeraCryptService.maxExactOffset ||
        absoluteByteOffset % 512 != 0 ||
        ciphertext.length % 512 != 0) {
      throw ArgumentError('Data reads must use aligned 512-byte units.');
    }
    final relativeOffset = absoluteByteOffset - header.encryptedAreaOffset;
    if (relativeOffset > header.encryptedAreaSize ||
        ciphertext.length > header.encryptedAreaSize - relativeOffset) {
      throw RangeError('Data read exceeds the encrypted volume.');
    }
    final plaintext = Uint8List(ciphertext.length);
    final engine = _AesXtsDecryptor(_primaryKey, _secondaryKey);
    try {
      for (var offset = 0; offset < ciphertext.length; offset += 512) {
        engine.decryptUnit(
          ciphertext,
          offset,
          512,
          plaintext,
          offset,
          (absoluteByteOffset + offset) ~/ 512,
        );
      }
      return plaintext;
    } catch (_) {
      _wipe(plaintext);
      rethrow;
    } finally {
      engine.dispose();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _wipe(_primaryKey);
    _wipe(_secondaryKey);
  }

  void close() => dispose();

  @override
  String toString() =>
      'VeraCryptUnlockedVolume(${_closed ? 'locked' : 'open'})';
}

/// AES-XTS file-container support with PointyCastle's MIT crypto primitives.
/// This does not support cascades, system encryption, or in-place encryption.
/// Current BLAKE2s/Streebog headers require another implementation.
class VeraCryptService {
  static const int _headerSize = 512;
  static const int _saltSize = 64;
  // PointyCastle's web Argon2 implementation represents each 64-bit word as
  // a separate Register64 object: the default needs over 54 million objects.
  // Enable a browser backend only once it has bounded memory and a worker.
  static const bool supportsArgon2id = bool.fromEnvironment('dart.library.io');

  /// A work ceiling per candidate, independent of the optional tighter budget.
  /// Browser KDFs run synchronously until a worker backend is available.
  static const int maximumPbkdf2Iterations = supportsArgon2id
      ? 20000000
      : 1000000;
  static const int maxPim = 2147468;
  static const int maxKeyfiles = 64;
  static const int maxKeyfileBytes = 1048576;

  /// Largest integer represented exactly by every supported Dart backend.
  static const int maxExactOffset = 9007199254740991;

  static const _legacyKdfs = {
    'SHA-512': VeraCryptKdf.sha512,
    'SHA-256': VeraCryptKdf.sha256,
    'Whirlpool': VeraCryptKdf.whirlpool,
  };

  /// A filename/size hint only: encrypted containers have no visible magic.
  static bool detectContainer(String path, {int? fileSize}) {
    if (fileSize != null && fileSize < _headerSize) return false;
    return _hasContainerExtension(path) ||
        (fileSize != null && fileSize >= _headerSize);
  }

  static bool detectContainerStrict(String path, int fileSize) =>
      _hasContainerExtension(path) && fileSize >= _headerSize;

  static bool _hasContainerExtension(String path) =>
      const ['.vc', '.hc', '.tc'].contains(_extension(path).toLowerCase());

  /// Extract salt only. None of the returned zero-valued metadata is trusted
  /// volume geometry until [unlockHeader] has successfully checked a header.
  static VeraCryptVolumeHeader parseHeader(Uint8List headerBytes) {
    if (headerBytes.length < _headerSize) {
      throw const FormatException('A container header needs 512 bytes.');
    }
    return VeraCryptVolumeHeader(
      salt: Uint8List.fromList(headerBytes.sublist(0, _saltSize)),
      encryptedAreaOffset: 0,
      encryptedAreaSize: 0,
      sectorSize: 512,
      version: 0,
      encryptionAlgorithmId: 0,
      hashAlgorithmId: 0,
      volumeSize: 0,
    );
  }

  /// Legacy PBKDF2 API, retained for callers that explicitly provide an
  /// iteration count. New credentials use [deriveHeaderKey] and a KDF/PIM.
  static Uint8List deriveKey(
    String password,
    Uint8List salt, {
    String hashAlgorithm = 'SHA-512',
    int? iterations,
  }) {
    final kdf = _legacyKdfs[hashAlgorithm];
    if (kdf == null) {
      throw ArgumentError('Unsupported legacy PBKDF2 algorithm.');
    }
    return deriveHeaderKey(
      password,
      salt,
      options: VeraCryptUnlockOptions(kdf: kdf),
      testIterations: iterations,
    );
  }

  /// Header keys for AES-XTS (64 bytes). Argon2 always derives 192 bytes first,
  /// then takes the prefix: requesting 64 bytes directly is incompatible.
  ///
  /// [testIterations] is a legacy test seam for PBKDF2 only. It cannot be
  /// combined with a PIM or Argon2id, and application unlock paths omit it.
  static Uint8List deriveHeaderKey(
    String password,
    Uint8List salt, {
    VeraCryptUnlockOptions options = const VeraCryptUnlockOptions(
      kdf: VeraCryptKdf.sha512,
    ),
    int? testIterations,
  }) {
    _validateOptions(options, testIterations: testIterations);
    if (options.kdf == VeraCryptKdf.auto) {
      throw ArgumentError('Choose one KDF when deriving a header key.');
    }
    if (salt.length != _saltSize) {
      throw ArgumentError('Container header salt must be 64 bytes.');
    }
    final effectivePassword = applyKeyfiles(
      password,
      options.keyfiles,
      trueCryptMode: options.trueCryptMode,
    );
    try {
      return _deriveBytes(
        effectivePassword,
        salt,
        options.kdf,
        options,
        testIterations: testIterations,
      );
    } finally {
      _wipe(effectivePassword);
    }
  }

  static VeraCryptArgon2Parameters argon2Parameters(int pim) {
    _validatePim(pim);
    final effective = pim == 0 ? 12 : pim;
    final memoryMiB = effective >= 31 ? 1024 : 64 + (effective - 1) * 32;
    final passes = effective <= 31
        ? 3 + (effective - 1) ~/ 3
        : 13 + effective - 31;
    return VeraCryptArgon2Parameters(
      memoryKiB: memoryMiB * 1024,
      iterations: passes,
    );
  }

  static int pbkdf2Iterations(
    VeraCryptKdf kdf, {
    int pim = 0,
    bool trueCryptMode = false,
  }) {
    _validatePim(pim);
    if (kdf == VeraCryptKdf.auto || kdf == VeraCryptKdf.argon2id) {
      throw ArgumentError('Choose a PBKDF2 hash.');
    }
    if (trueCryptMode) {
      if (pim != 0) throw ArgumentError('TrueCrypt does not use a PIM.');
      if (kdf == VeraCryptKdf.sha256) {
        throw ArgumentError('TrueCrypt does not support SHA-256.');
      }
      return kdf == VeraCryptKdf.ripemd160 ? 2000 : 1000;
    }
    if (pim != 0) return 15000 + 1000 * pim;
    return kdf == VeraCryptKdf.ripemd160 ? 655331 : 500000;
  }

  static void _validatePim(int pim) {
    if (pim < 0 || pim > maxPim) {
      throw ArgumentError('PIM must be between zero and 2147468.');
    }
  }

  static void _validateOptions(
    VeraCryptUnlockOptions options, {
    int? testIterations,
  }) {
    _validatePim(options.pim);
    if (options.keyfiles.length > maxKeyfiles) {
      throw ArgumentError('At most 64 keyfiles are supported per unlock.');
    }
    if (options.keyfiles.any((bytes) => bytes.isEmpty)) {
      throw ArgumentError('A keyfile must contain at least one byte.');
    }
    if (options.trueCryptMode &&
        (options.pim != 0 ||
            options.kdf == VeraCryptKdf.sha256 ||
            options.kdf == VeraCryptKdf.argon2id)) {
      throw ArgumentError('TrueCrypt requires its legacy hashes and no PIM.');
    }
    if (testIterations != null &&
        (testIterations < 1 ||
            testIterations > 2147483647 ||
            options.pim != 0 ||
            options.kdf == VeraCryptKdf.argon2id)) {
      throw ArgumentError(
        'A test iteration override requires PBKDF2, a positive count and no PIM.',
      );
    }
    if (options.maxPbkdf2Iterations < 1 ||
        options.maxPbkdf2Iterations > 20000000) {
      throw ArgumentError('Invalid PBKDF2 resource budget.');
    }
    if (options.maxArgon2MemoryKiB < 65536 ||
        options.maxArgon2MemoryKiB > 1048576 ||
        options.maxArgon2Iterations < 1 ||
        options.maxArgon2Iterations > 1024) {
      throw ArgumentError('Invalid Argon2 resource budget.');
    }
    if (options.kdf == VeraCryptKdf.argon2id) {
      if (!supportsArgon2id) {
        throw UnsupportedError(
          'Argon2id container unlocking requires native CrispCloud; '
          'the browser backend is not enabled.',
        );
      }
      final cost = argon2Parameters(options.pim);
      if (cost.memoryKiB > options.maxArgon2MemoryKiB ||
          cost.iterations > options.maxArgon2Iterations) {
        throw const VeraCryptResourceLimitException(
          'The selected Argon2 settings exceed the unlock resource budget.',
        );
      }
    } else {
      // Check every candidate before doing password/keyfile or KDF work, so
      // automatic selection cannot partially run an over-budget attempt.
      final budget = options.maxPbkdf2Iterations < maximumPbkdf2Iterations
          ? options.maxPbkdf2Iterations
          : maximumPbkdf2Iterations;
      for (final candidate in _candidates(options)) {
        final iterations =
            testIterations ??
            pbkdf2Iterations(
              candidate,
              pim: options.pim,
              trueCryptMode: options.trueCryptMode,
            );
        if (iterations > budget) {
          throw const VeraCryptResourceLimitException(
            'The selected PBKDF2 settings exceed the unlock resource budget.',
          );
        }
      }
    }
  }

  static List<VeraCryptKdf> _candidates(VeraCryptUnlockOptions options) =>
      options.kdf != VeraCryptKdf.auto
      ? [options.kdf]
      : options.trueCryptMode
      ? const [
          VeraCryptKdf.sha512,
          VeraCryptKdf.ripemd160,
          VeraCryptKdf.whirlpool,
        ]
      : const [
          VeraCryptKdf.sha512,
          VeraCryptKdf.sha256,
          VeraCryptKdf.whirlpool,
          VeraCryptKdf.ripemd160,
        ];

  /// VeraCrypt's binary keyfile mix. No normalization is applied to passwords.
  /// CRC state is raw (no final XOR); both pool and password mixing use byte
  /// addition modulo 256. Only the first MiB of each keyfile contributes.
  /// Returned bytes are owned by the caller and should be wiped after use.
  static Uint8List applyKeyfiles(
    String password,
    List<Uint8List> keyfiles, {
    bool trueCryptMode = false,
  }) {
    if (keyfiles.length > maxKeyfiles || keyfiles.any((k) => k.isEmpty)) {
      throw ArgumentError('Supply between one and 64 nonempty keyfiles.');
    }
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final maxLength = trueCryptMode ? 64 : 128;
    if (passwordBytes.length > maxLength) {
      _wipe(passwordBytes);
      throw ArgumentError('The password exceeds the format byte-length limit.');
    }
    if (keyfiles.isEmpty) return passwordBytes;
    final poolSize = passwordBytes.length <= 64 ? 64 : 128;
    final pool = Uint8List(poolSize);
    try {
      for (final keyfile in keyfiles) {
        var crc = 0xffffffff;
        var cursor = 0;
        final length = keyfile.length < maxKeyfileBytes
            ? keyfile.length
            : maxKeyfileBytes;
        for (var i = 0; i < length; i++) {
          crc = _crcTable[(crc ^ keyfile[i]) & 0xff] ^ (crc >>> 8);
          for (final shift in const [24, 16, 8, 0]) {
            pool[cursor] = (pool[cursor] + ((crc >>> shift) & 0xff)) & 0xff;
            cursor = (cursor + 1) % poolSize;
          }
        }
      }
      final mixed = Uint8List(poolSize)
        ..setRange(0, passwordBytes.length, passwordBytes);
      for (var i = 0; i < poolSize; i++) {
        mixed[i] = (mixed[i] + pool[i]) & 0xff;
      }
      return mixed;
    } finally {
      _wipe(pool);
      _wipe(passwordBytes);
    }
  }

  static final List<int> _crcTable = List<int>.generate(256, (index) {
    var crc = index;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
    }
    return crc;
  }, growable: false);

  static Uint8List _deriveBytes(
    Uint8List password,
    Uint8List salt,
    VeraCryptKdf kdf,
    VeraCryptUnlockOptions options, {
    int? testIterations,
  }) {
    if (kdf == VeraCryptKdf.argon2id) {
      final cost = argon2Parameters(options.pim);
      final generator = Argon2BytesGenerator();
      Uint8List? fullKey;
      try {
        generator.init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            salt,
            desiredKeyLength: 192,
            memory: cost.memoryKiB,
            iterations: cost.iterations,
            lanes: 1,
            version: Argon2Parameters.ARGON2_VERSION_13,
          ),
        );
        fullKey = generator.process(password);
        return Uint8List.fromList(Uint8List.sublistView(fullKey, 0, 64));
      } on OutOfMemoryError {
        throw const VeraCryptResourceLimitException(
          'There is not enough memory for the selected Argon2 settings.',
        );
      } finally {
        if (fullKey != null) _wipe(fullKey);
        // PointyCastle clears its working blocks on a completed derivation.
        // Its API has no public reset for a failure during allocation/work.
      }
    }
    final (digest, blockLength) = switch (kdf) {
      VeraCryptKdf.sha512 => (SHA512Digest(), 128),
      VeraCryptKdf.sha256 => (SHA256Digest(), 64),
      VeraCryptKdf.whirlpool => (WhirlpoolDigest(), 64),
      VeraCryptKdf.ripemd160 => (RIPEMD160Digest(), 64),
      _ => throw ArgumentError('Choose an explicit header KDF.'),
    };
    final iterations =
        testIterations ??
        pbkdf2Iterations(
          kdf,
          pim: options.pim,
          trueCryptMode: options.trueCryptMode,
        );
    final generator = PBKDF2KeyDerivator(HMac(digest, blockLength))
      ..init(Pbkdf2Parameters(salt, iterations, 64));
    return generator.process(password);
  }

  /// Unlock one selected header slot. The reader chooses primary/backup/hidden
  /// positions and supplies the full host length. The header XTS tweak is zero
  /// at every slot; data tweaks use absolute container offsets instead.
  ///
  /// Returns null for wrong credentials, corrupt headers or unsupported header
  /// geometry. Invalid options and resource failures propagate to the caller.
  /// Auto tries supported PBKDF2 hashes only; Argon2id must be selected.
  static VeraCryptUnlockedVolume? unlockHeader(
    Uint8List headerBytes,
    String password, {
    VeraCryptUnlockOptions options = const VeraCryptUnlockOptions(),
    int? containerSizeBytes,
    int? testIterations,
  }) {
    _validateOptions(options, testIterations: testIterations);
    if (containerSizeBytes != null &&
        (containerSizeBytes < 262656 || containerSizeBytes > maxExactOffset)) {
      throw ArgumentError('Invalid file-container size.');
    }
    if (headerBytes.length < _headerSize) return null;
    final effectivePassword = applyKeyfiles(
      password,
      options.keyfiles,
      trueCryptMode: options.trueCryptMode,
    );
    final salt = Uint8List.fromList(headerBytes.sublist(0, _saltSize));
    final candidates = _candidates(options);
    try {
      for (final candidate in candidates) {
        final key = _deriveBytes(
          effectivePassword,
          salt,
          candidate,
          options,
          testIterations: testIterations,
        );
        final clear = Uint8List(448);
        final engine = _AesXtsDecryptor(
          Uint8List.sublistView(key, 0, 32),
          Uint8List.sublistView(key, 32, 64),
        );
        try {
          engine.decryptUnit(headerBytes, 64, 448, clear, 0, 0);
          final metadata = _parseDecryptedHeader(
            clear,
            salt,
            candidate,
            trueCryptMode: options.trueCryptMode,
            containerSizeBytes: containerSizeBytes,
          );
          if (metadata != null) {
            return VeraCryptUnlockedVolume._(metadata, clear);
          }
        } finally {
          engine.dispose();
          _wipe(clear);
          _wipe(key);
        }
      }
      return null;
    } finally {
      _wipe(effectivePassword);
      _wipe(salt);
    }
  }

  /// Backwards-compatible metadata-only API. Any successfully decrypted keys
  /// are immediately disposed; use [unlockHeader] to own a read session.
  static VeraCryptVolumeHeader? tryDecryptHeader(
    Uint8List headerBytes,
    String password, {
    int? testIterations,
    VeraCryptUnlockOptions options = const VeraCryptUnlockOptions(),
    int? containerSizeBytes,
  }) {
    final volume = unlockHeader(
      headerBytes,
      password,
      options: options,
      containerSizeBytes: containerSizeBytes,
      testIterations: testIterations,
    );
    if (volume == null) return null;
    try {
      return volume.header;
    } finally {
      volume.dispose();
    }
  }

  static VeraCryptVolumeHeader? _parseDecryptedHeader(
    Uint8List clear,
    Uint8List salt,
    VeraCryptKdf kdf, {
    required bool trueCryptMode,
    int? containerSizeBytes,
  }) {
    final magic = trueCryptMode
        ? const [84, 82, 85, 69]
        : const [86, 69, 82, 65];
    for (var i = 0; i < 4; i++) {
      if (clear[i] != magic[i]) return null;
    }
    final data = ByteData.sublistView(clear);
    if (data.getUint32(8, Endian.big) !=
            getCrc32(Uint8List.sublistView(clear, 192, 448)) ||
        data.getUint32(188, Endian.big) !=
            getCrc32(Uint8List.sublistView(clear, 0, 188))) {
      return null;
    }
    final version = data.getUint16(4, Endian.big);
    final requiredVersion = data.getUint16(6, Endian.big);
    if (trueCryptMode) {
      if ((version != 4 && version != 5) ||
          requiredVersion < 0x0600 ||
          requiredVersion > 0x071a) {
        return null;
      }
    } else if (version != 5 || requiredVersion > 0x0126) {
      return null;
    }
    final flags = data.getUint32(60, Endian.big);
    // Neither system, partially/in-place encrypted nor future flag layouts
    // have the data geometry implemented by this read-only file reader.
    if (flags != 0) return null;
    final sectorSize = version == 4 ? 512 : data.getUint32(64, Endian.big);
    if (sectorSize != 512 && sectorSize != 4096) return null;
    final volumeSize = _readExactUint64(data, 36);
    final dataOffset = _readExactUint64(data, 44);
    final dataSize = _readExactUint64(data, 52);
    final hiddenSize = _readExactUint64(data, 28);
    if (volumeSize == null ||
        dataOffset == null ||
        dataSize == null ||
        hiddenSize == null ||
        volumeSize <= 0 ||
        dataSize <= 0 ||
        dataSize != volumeSize ||
        dataOffset < 131072 ||
        dataSize > maxExactOffset - dataOffset ||
        volumeSize % sectorSize != 0 ||
        dataOffset % sectorSize != 0 ||
        dataSize % sectorSize != 0 ||
        (hiddenSize != 0 && hiddenSize != volumeSize)) {
      return null;
    }
    if (containerSizeBytes != null) {
      final dataLimit = containerSizeBytes - 131072;
      if (dataOffset > dataLimit || dataSize > dataLimit - dataOffset) {
        return null;
      }
    }
    return VeraCryptVolumeHeader(
      salt: Uint8List.fromList(salt),
      encryptedAreaOffset: dataOffset,
      encryptedAreaSize: dataSize,
      sectorSize: sectorSize,
      version: version,
      encryptionAlgorithmId: 1,
      hashAlgorithmId: switch (kdf) {
        VeraCryptKdf.sha512 => 1,
        VeraCryptKdf.whirlpool => 2,
        VeraCryptKdf.sha256 => 3,
        VeraCryptKdf.ripemd160 => 4,
        VeraCryptKdf.argon2id => 5,
        VeraCryptKdf.auto => throw StateError('KDF was not resolved.'),
      },
      volumeSize: volumeSize,
      trueCryptMode: trueCryptMode,
      hiddenVolumeSize: hiddenSize,
      requiredVersion: requiredVersion,
      flags: flags,
    );
  }

  /// Do not call getInt64/getUint64 on web and then check: by that point an
  /// unsafe value may already have been rounded by the JavaScript backend.
  static int? _readExactUint64(ByteData data, int offset) {
    final high = data.getUint32(offset, Endian.big);
    if (high > 0x1fffff) return null;
    return high * 0x100000000 + data.getUint32(offset + 4, Endian.big);
  }

  static List<String> getSupportedAlgorithms() => const ['AES-256-XTS'];

  static List<String> getSupportedHashAlgorithms() => const [
    'SHA-512',
    'SHA-256',
    'Whirlpool',
    'RIPEMD-160',
    'Argon2id',
  ];

  static String encryptionAlgorithmName(int id) =>
      const <int, String>{
        1: 'AES-256-XTS',
        2: 'Serpent-256-XTS',
        3: 'Twofish-256-XTS',
        4: 'AES-Twofish',
        5: 'AES-Twofish-Serpent',
        6: 'Serpent-AES',
        7: 'Serpent-Twofish-AES',
        8: 'Twofish-Serpent',
      }[id] ??
      'Unknown ($id)';

  static String hashAlgorithmName(int id) =>
      const <int, String>{
        1: 'SHA-512',
        2: 'Whirlpool',
        3: 'SHA-256',
        4: 'RIPEMD-160',
        5: 'Argon2id',
      }[id] ??
      'Unknown ($id)';

  static String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }
}

void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

/// One read's temporary AES schedules and block scratch. No ciphertext
/// stealing is needed: headers (448 bytes) and data units (512) are aligned.
class _AesXtsDecryptor {
  final AESEngine _data = AESEngine();
  final AESEngine _tweaks = AESEngine();
  final Uint8List _index = Uint8List(16);
  final Uint8List _tweak = Uint8List(16);
  final Uint8List _block = Uint8List(16);
  final Uint8List _decoded = Uint8List(16);

  _AesXtsDecryptor(Uint8List primary, Uint8List secondary) {
    _data.init(false, KeyParameter(primary));
    _tweaks.init(true, KeyParameter(secondary));
  }

  void decryptUnit(
    Uint8List input,
    int inputOffset,
    int length,
    Uint8List output,
    int outputOffset,
    int unitNumber,
  ) {
    _wipe(_index);
    // Encode without 64-bit shifts, which JavaScript cannot represent.
    var remaining = unitNumber;
    for (var i = 0; i < 8; i++) {
      _index[i] = remaining % 256;
      remaining ~/= 256;
    }
    _tweaks.processBlock(_index, 0, _tweak, 0);
    for (var offset = 0; offset < length; offset += 16) {
      for (var i = 0; i < 16; i++) {
        _block[i] = input[inputOffset + offset + i] ^ _tweak[i];
      }
      _data.processBlock(_block, 0, _decoded, 0);
      for (var i = 0; i < 16; i++) {
        output[outputOffset + offset + i] = _decoded[i] ^ _tweak[i];
      }
      var carry = 0;
      for (var i = 0; i < 16; i++) {
        final byte = _tweak[i];
        _tweak[i] = ((byte << 1) | carry) & 0xff;
        carry = byte >>> 7;
      }
      if (carry != 0) _tweak[0] ^= 0x87;
    }
  }

  void dispose() {
    _wipe(_index);
    _wipe(_tweak);
    _wipe(_block);
    _wipe(_decoded);
    // Replace reachable schedules. The VM may retain their old allocations.
    final zeroKey = KeyParameter(Uint8List(32));
    _data.init(false, zeroKey);
    _tweaks.init(true, zeroKey);
    _data.reset();
    _tweaks.reset();
  }
}
