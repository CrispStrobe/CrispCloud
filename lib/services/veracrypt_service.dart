// lib/services/veracrypt_service.dart
//
// VeraCrypt container detection and header parsing.
//
// NOTE: Full volume mount is an OS-level operation via the `veracrypt` CLI.
// This service handles header parsing, detection, and key derivation only.
//
// VeraCrypt volume header layout (512 bytes):
//   [0..63]    Salt (64 bytes) — passed to PBKDF2 key derivation
//   [64..511]  Encrypted area (448 bytes) — decrypted with derived key
//
// Inside the decrypted area (offsets relative to start of decrypted block):
//   [0..3]     Magic "VERA" (0x56455241)
//   [4..5]     Header format version
//   [6..7]     Minimum program version
//   [8..11]    CRC-32 of header bytes [188..511]
//   [64..67]   Volume flags
//   [68..71]   Volume sector size
//   [100..107] Encrypted area offset (bytes from start of volume)
//   [108..115] Encrypted area size (bytes)
//   [252..259] Volume size (bytes)
//   [260..267] Encryption algorithm ID
//   [268..271] Hash algorithm ID

import 'dart:convert';
import 'dart:typed_data';

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
  }) =>
      VeraCryptContainer(
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

  /// Encryption algorithm identifier.
  final int encryptionAlgorithmId;

  /// Hash algorithm identifier.
  final int hashAlgorithmId;

  /// Total volume size in bytes.
  final int volumeSize;

  const VeraCryptVolumeHeader({
    required this.salt,
    required this.encryptedAreaOffset,
    required this.encryptedAreaSize,
    required this.sectorSize,
    required this.version,
    required this.encryptionAlgorithmId,
    required this.hashAlgorithmId,
    required this.volumeSize,
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
      };

  @override
  String toString() =>
      'VeraCryptVolumeHeader(version=$version, sectorSize=$sectorSize, '
      'encAlgo=$encryptionAlgorithmId, hashAlgo=$hashAlgorithmId)';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// VeraCrypt container detection, header parsing, and key derivation.
///
/// Supported encryption algorithms: AES-256-XTS (and cascade variants).
/// Supported KDF algorithms: SHA-512, SHA-256, Whirlpool.
///
/// Full mount operations are delegated to the OS-level `veracrypt` CLI.
class VeraCryptService {
  static const int _headerSize = 512;
  static const int _saltSize = 64;
  static const int _encryptedHeaderOffset = 64;

  // Magic "VERA" at offset 0 inside decrypted area
  static const List<int> _magic = [0x56, 0x45, 0x52, 0x41];

  // VeraCrypt default PBKDF2 iterations per hash algorithm
  static const Map<String, int> _defaultIterations = {
    'SHA-512': 500000,
    'SHA-256': 500000,
    'Whirlpool': 500000,
    'RIPEMD-160': 655331,
  };

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  /// Returns true if [path] looks like a VeraCrypt container.
  ///
  /// Detection criteria:
  /// 1. File extension is `.vc` or `.hc` (case-insensitive), OR
  /// 2. [fileSize] is at least 512 bytes (enough for the header).
  ///
  /// Both criteria must hold when [fileSize] is provided.
  static bool detectContainer(String path, {int? fileSize}) {
    final ext = _extension(path).toLowerCase();
    final hasVeraCryptExt = ext == '.vc' || ext == '.hc';

    if (fileSize != null && fileSize < _headerSize) return false;
    return hasVeraCryptExt || (fileSize != null && fileSize >= _headerSize);
  }

  /// Strict detection: requires known extension AND minimum file size.
  static bool detectContainerStrict(String path, int fileSize) {
    final ext = _extension(path).toLowerCase();
    return (ext == '.vc' || ext == '.hc') && fileSize >= _headerSize;
  }

  // ---------------------------------------------------------------------------
  // Header parsing
  // ---------------------------------------------------------------------------

  /// Parse the first 512 bytes of a VeraCrypt volume.
  ///
  /// [headerBytes] must be exactly 512 bytes (the raw/unencrypted area).
  /// Returns a [VeraCryptVolumeHeader] with the salt extracted.
  /// The encrypted portion (bytes 64–511) is returned as-is; use
  /// [tryDecryptHeader] to parse the full header after decryption.
  ///
  /// Throws [FormatException] if [headerBytes] is shorter than 512 bytes.
  static VeraCryptVolumeHeader parseHeader(Uint8List headerBytes) {
    if (headerBytes.length < _headerSize) {
      throw FormatException(
          'VeraCrypt header must be at least $_headerSize bytes, '
          'got ${headerBytes.length}');
    }

    final salt = headerBytes.sublist(0, _saltSize);

    // Return a partial header — the encrypted area is opaque until decrypted
    return VeraCryptVolumeHeader(
      salt: salt,
      encryptedAreaOffset: 0,
      encryptedAreaSize: 0,
      sectorSize: 512,
      version: 0,
      encryptionAlgorithmId: 0,
      hashAlgorithmId: 0,
      volumeSize: 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Key derivation
  // ---------------------------------------------------------------------------

  /// Derive the header decryption key from [password] and [salt] using
  /// PBKDF2 with the specified [hashAlgorithm] and [iterations].
  ///
  /// Supported hash algorithms: 'SHA-512', 'SHA-256', 'Whirlpool'.
  /// Returns 64 bytes (512 bits) suitable for AES-256-XTS (two 256-bit keys).
  static Uint8List deriveKey(
    String password,
    Uint8List salt, {
    String hashAlgorithm = 'SHA-512',
    int? iterations,
  }) {
    final iters = iterations ?? (_defaultIterations[hashAlgorithm] ?? 500000);
    final passwordBytes = Uint8List.fromList(utf8.encode(password));

    final Digest digest;
    final int blockLength;
    switch (hashAlgorithm) {
      case 'SHA-256':
        digest = SHA256Digest();
        blockLength = 64;
        break;
      case 'Whirlpool':
        digest = WhirlpoolDigest();
        blockLength = 64;
        break;
      case 'SHA-512':
      default:
        digest = SHA512Digest();
        blockLength = 128;
        break;
    }

    final params = Pbkdf2Parameters(salt, iters, 64); // 512 bits output
    final kdf = PBKDF2KeyDerivator(HMac(digest, blockLength));
    kdf.init(params);
    return kdf.process(passwordBytes);
  }

  // ---------------------------------------------------------------------------
  // Header decryption
  // ---------------------------------------------------------------------------

  /// Attempt to decrypt the VeraCrypt volume header with [password].
  ///
  /// Tries all supported hash algorithms and returns the first successfully
  /// parsed [VeraCryptVolumeHeader], or null if no combination works.
  ///
  /// A header is considered valid when the decrypted magic bytes are "VERA".
  ///
  /// [testIterations] may be provided to override the PBKDF2 iteration count
  /// for each hash algorithm — useful only for unit tests where full iteration
  /// counts would make tests impractically slow.
  static VeraCryptVolumeHeader? tryDecryptHeader(
    Uint8List headerBytes,
    String password, {
    int? testIterations,
  }) {
    if (headerBytes.length < _headerSize) return null;

    for (final hashAlgo in getSupportedHashAlgorithms()) {
      final result =
          _tryDecryptWithAlgo(headerBytes, password, hashAlgo, testIterations);
      if (result != null) return result;
    }
    return null;
  }

  /// Try decrypting with a specific hash algorithm.
  static VeraCryptVolumeHeader? _tryDecryptWithAlgo(
    Uint8List headerBytes,
    String password,
    String hashAlgorithm,
    int? testIterations,
  ) {
    try {
      final salt = headerBytes.sublist(0, _saltSize);
      final encryptedArea =
          headerBytes.sublist(_encryptedHeaderOffset, _headerSize);

      // Derive 64-byte key: first 32 = primary key, next 32 = tweak key (XTS)
      final keyMaterial = deriveKey(password, salt,
          hashAlgorithm: hashAlgorithm, iterations: testIterations);
      final key1 = keyMaterial.sublist(0, 32);
      final key2 = keyMaterial.sublist(32, 64);

      // Decrypt with AES-256-XTS (sector 0)
      final decrypted = _aesXtsDecrypt(encryptedArea, key1, key2, sectorIndex: 0);

      // Verify magic "VERA"
      if (!_checkMagic(decrypted)) return null;

      return _parseDecryptedHeader(decrypted, salt, hashAlgorithm);
    } catch (_) {
      return null;
    }
  }

  /// Parse the decrypted header area into a [VeraCryptVolumeHeader].
  static VeraCryptVolumeHeader _parseDecryptedHeader(
    Uint8List decrypted,
    Uint8List salt,
    String hashAlgorithm,
  ) {
    final bd = ByteData.sublistView(decrypted);

    // Offsets relative to decrypted area start
    final version = bd.getUint16(4, Endian.big);
    final sectorSize = bd.getUint32(68, Endian.big);
    final encryptedAreaOffset = bd.getInt64(100, Endian.big);
    final encryptedAreaSize = bd.getInt64(108, Endian.big);
    final volumeSize = bd.getInt64(252, Endian.big);
    final encAlgoId = bd.getUint32(260, Endian.big);
    final hashAlgoId = bd.getUint32(268, Endian.big);

    return VeraCryptVolumeHeader(
      salt: salt,
      encryptedAreaOffset: encryptedAreaOffset,
      encryptedAreaSize: encryptedAreaSize,
      sectorSize: sectorSize > 0 ? sectorSize : 512,
      version: version,
      encryptionAlgorithmId: encAlgoId,
      hashAlgorithmId: hashAlgoId,
      volumeSize: volumeSize,
    );
  }

  // ---------------------------------------------------------------------------
  // AES-256-XTS decryption
  // ---------------------------------------------------------------------------

  /// Decrypt a 512-byte sector using AES-256-XTS.
  static Uint8List _aesXtsDecrypt(
    Uint8List ciphertext,
    Uint8List key1,
    Uint8List key2, {
    int sectorIndex = 0,
  }) {
    // XTS tweak: sector index as 128-bit little-endian integer
    final tweak = Uint8List(16);
    final tweakBd = ByteData.sublistView(tweak);
    tweakBd.setUint64(0, sectorIndex, Endian.little);

    // Encrypt tweak with key2
    final aes2 = AESEngine()..init(true, KeyParameter(key2));
    final encTweak = Uint8List(16);
    aes2.processBlock(tweak, 0, encTweak, 0);

    // AES decrypt each 16-byte block with XTS
    final aes1 = AESEngine()..init(false, KeyParameter(key1));
    final plaintext = Uint8List(ciphertext.length);
    var tweakArr = encTweak;

    for (var i = 0; i < ciphertext.length; i += 16) {
      final block = Uint8List(16);
      for (var k = 0; k < 16; k++) {
        block[k] = ciphertext[i + k] ^ tweakArr[k];
      }
      final decBlock = Uint8List(16);
      aes1.processBlock(block, 0, decBlock, 0);
      for (var k = 0; k < 16; k++) {
        plaintext[i + k] = decBlock[k] ^ tweakArr[k];
      }
      // Multiply tweak by 2 in GF(2^128)
      tweakArr = _gf128Multiply2(tweakArr);
    }
    return plaintext;
  }

  /// Multiply a 128-bit GF(2^128) element by 2 (polynomial x mod x^128 + x^7 + x^2 + x + 1).
  static Uint8List _gf128Multiply2(Uint8List input) {
    final output = Uint8List(16);
    var carry = 0;
    for (var i = 0; i < 16; i++) {
      final b = input[i];
      output[i] = ((b << 1) | carry) & 0xFF;
      carry = (b >> 7) & 1;
    }
    if (carry != 0) {
      output[0] ^= 0x87; // irreducible polynomial constant
    }
    return output;
  }

  static bool _checkMagic(Uint8List decrypted) {
    if (decrypted.length < 4) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (decrypted[i] != _magic[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Supported algorithms
  // ---------------------------------------------------------------------------

  /// Returns list of supported encryption algorithm names.
  static List<String> getSupportedAlgorithms() => const [
        'AES-256-XTS',
        'Serpent-256-XTS',
        'Twofish-256-XTS',
        'AES-Twofish',
        'AES-Twofish-Serpent',
        'Serpent-AES',
        'Serpent-Twofish-AES',
        'Twofish-Serpent',
      ];

  /// Returns list of supported hash/KDF algorithm names.
  static List<String> getSupportedHashAlgorithms() => const [
        'SHA-512',
        'SHA-256',
        'Whirlpool',
        'RIPEMD-160',
      ];

  /// Map an encryption algorithm ID (from the volume header) to a human-readable name.
  static String encryptionAlgorithmName(int id) {
    const names = <int, String>{
      1: 'AES-256-XTS',
      2: 'Serpent-256-XTS',
      3: 'Twofish-256-XTS',
      4: 'AES-Twofish',
      5: 'AES-Twofish-Serpent',
      6: 'Serpent-AES',
      7: 'Serpent-Twofish-AES',
      8: 'Twofish-Serpent',
    };
    return names[id] ?? 'Unknown ($id)';
  }

  /// Map a hash algorithm ID (from the volume header) to a human-readable name.
  static String hashAlgorithmName(int id) {
    const names = <int, String>{
      1: 'SHA-512',
      2: 'Whirlpool',
      3: 'SHA-256',
      4: 'RIPEMD-160',
    };
    return names[id] ?? 'Unknown ($id)';
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return name.substring(dot);
  }
}
