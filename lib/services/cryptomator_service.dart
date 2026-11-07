// lib/services/cryptomator_service.dart
//
// Cryptomator vault format v8 cryptographic primitives (SIV_GCM).
//
// This is not a complete vault filesystem. Traversal needs dir.c9r metadata;
// shortened names need name.c9s metadata; file data needs Cryptomator's chunk
// framing and AAD. EncryptionService's whole-file format is NOT that format.
// See https://docs.cryptomator.org/security/vault/.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'aes_siv.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Represents a Cryptomator vault directory on a storage backend.
class CryptomatorVault {
  final String vaultPath;
  final String masterkeyFilePath;
  final int version;
  final String cipherCombo;
  final int shorteningThreshold;

  const CryptomatorVault({
    required this.vaultPath,
    required this.masterkeyFilePath,
    this.version = 8,
    this.cipherCombo = 'SIV_GCM',
    this.shorteningThreshold = 220,
  });

  @override
  String toString() =>
      'CryptomatorVault(path=$vaultPath, version=$version, cipher=$cipherCombo)';
}

/// Unverified discovery metadata from `vault.cryptomator`.
/// [CryptomatorService.unlockVault] verifies the signature before using it.
class VaultConfig {
  final int version;
  final String cipherCombo;
  final int shorteningThreshold;
  final String? keyId;

  const VaultConfig({
    required this.version,
    required this.cipherCombo,
    required this.shorteningThreshold,
    this.keyId,
  });

  /// Parse from the raw JWT string by base64-decoding the payload segment only.
  /// Does NOT verify the JWT signature — for detection/info purposes only.
  factory VaultConfig.fromJwt(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const FormatException('Invalid vault.cryptomator JWT format');
    }
    final header = _decodeJwtObject(parts[0]);
    final map = _decodeJwtObject(parts[1]);
    if (map['format'] is! int ||
        map['cipherCombo'] is! String ||
        map['shorteningThreshold'] is! int ||
        (header['kid'] != null && header['kid'] is! String)) {
      throw const FormatException('Invalid vault.cryptomator configuration');
    }
    return VaultConfig(
      version: map['format'] as int,
      cipherCombo: map['cipherCombo'] as String,
      shorteningThreshold: map['shorteningThreshold'] as int,
      keyId: header['kid'] as String?,
    );
  }

  static Map<String, dynamic> _decodeJwtObject(String segment) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment)) {
      throw const FormatException('Invalid JWT base64url segment');
    }
    final decoded = json.decode(utf8.decode(base64Url.decode(segment)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JWT segment must be a JSON object');
    }
    return decoded;
  }

  @override
  String toString() =>
      'VaultConfig(version=$version, cipher=$cipherCombo, threshold=$shorteningThreshold)';
}

/// Parsed from `masterkey.cryptomator` JSON.
class MasterkeyFile {
  final int version;
  final Uint8List scryptSalt;
  final int scryptCostParam;
  final int scryptBlockSize;
  final Uint8List primaryMasterKey; // wrapped (encrypted) 32-byte key
  final Uint8List hmacMasterKey; // wrapped (encrypted) 32-byte key
  final String versionMac;

  const MasterkeyFile({
    required this.version,
    required this.scryptSalt,
    required this.scryptCostParam,
    required this.scryptBlockSize,
    required this.primaryMasterKey,
    required this.hmacMasterKey,
    required this.versionMac,
  });

  /// Parse from the raw JSON string of a masterkey.cryptomator file.
  factory MasterkeyFile.fromJson(String jsonString) {
    final map = json.decode(jsonString) as Map<String, dynamic>;
    return MasterkeyFile(
      version: (map['version'] as num?)?.toInt() ?? 999,
      scryptSalt: base64.decode(map['scryptSalt'] as String),
      scryptCostParam: (map['scryptCostParam'] as num).toInt(),
      scryptBlockSize: (map['scryptBlockSize'] as num).toInt(),
      primaryMasterKey: base64.decode(map['primaryMasterKey'] as String),
      hmacMasterKey: base64.decode(map['hmacMasterKey'] as String),
      versionMac: map['versionMac'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'scryptSalt': base64.encode(scryptSalt),
    'scryptCostParam': scryptCostParam,
    'scryptBlockSize': scryptBlockSize,
    'primaryMasterKey': base64.encode(primaryMasterKey),
    'hmacMasterKey': base64.encode(hmacMasterKey),
    'versionMac': versionMac,
  };
}

/// Represents an unlocked vault with derived master keys ready for use.
class UnlockedVault {
  final CryptomatorVault vault;
  final Uint8List encKey; // 32-byte AES encryption key
  final Uint8List macKey; // 32-byte HMAC key

  const UnlockedVault({
    required this.vault,
    required this.encKey,
    required this.macKey,
  });
}

/// A shortened entry must persist [fullName] as its `name.c9s` file before
/// writing content. Returning both names avoids losing the reverse mapping.
class CryptomatorEncryptedName {
  final String fullName;
  final String entryName;

  const CryptomatorEncryptedName(this.fullName, this.entryName);

  bool get isShortened => fullName != entryName;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Cryptomator v8 primitives: detection, authenticated unlock, filename and
/// directory-ID encryption, and authenticated file-header key extraction.
///
/// Key points of the v8 format:
/// - Masterkey file uses scrypt KDF to wrap two 256-bit AES keys via RFC 3394.
/// - Directory IDs are hashed with SHA-1 and encoded as base32 (upper-case).
/// - The encrypted directory structure is `d/<2-char>/<30-char>/` based on
///   the hashed directory ID.
/// - Filenames > shorteningThreshold chars become `.c9s` shortened entries.
/// - Cipher combo SIV_GCM: filenames use AES-SIV, file content uses AES-GCM.
class CryptomatorService {
  static const String _vaultConfigFilename = 'vault.cryptomator';
  static const String _masterkeyFilename = 'masterkey.cryptomator';

  // ---------------------------------------------------------------------------
  // Vault detection
  // ---------------------------------------------------------------------------

  /// Returns true if [path] appears to contain a Cryptomator vault
  /// (both `vault.cryptomator` and `masterkey.cryptomator` are present in
  /// the file listing [files]).
  static bool detectVault(String path, List<String> files) {
    final hasVaultConfig = files.any(
      (f) => _basename(f) == _vaultConfigFilename,
    );
    final hasMasterkey = files.any((f) => _basename(f) == _masterkeyFilename);
    return hasVaultConfig && hasMasterkey;
  }

  // ---------------------------------------------------------------------------
  // Vault unlock
  // ---------------------------------------------------------------------------

  /// Unlock a vault by deriving the wrapping key from [password] via scrypt,
  /// then unwrapping the primary and HMAC master keys (AES Key Wrap, RFC 3394).
  ///
  /// Throws [FormatException] if the password is wrong (HMAC verification fails)
  /// or if the masterkey file format is invalid.
  static UnlockedVault unlockVault(
    CryptomatorVault vaultMeta,
    MasterkeyFile masterkeyFile,
    String password, {
    required String vaultConfigJwt,
  }) {
    final config = VaultConfig.fromJwt(vaultConfigJwt);
    if (masterkeyFile.primaryMasterKey.length != 40 ||
        masterkeyFile.hmacMasterKey.length != 40 ||
        masterkeyFile.version < 0 ||
        masterkeyFile.version > 0xffffffff) {
      throw const FormatException('Invalid Cryptomator masterkey file');
    }
    // 1. Derive KEK from password via scrypt
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final kek = _scrypt(
      passwordBytes,
      masterkeyFile.scryptSalt,
      masterkeyFile.scryptCostParam,
      masterkeyFile.scryptBlockSize,
      1, // parallelisation factor
      32, // output length: 256 bits
    );

    // 2. Unwrap the primary (enc) and HMAC master keys with the KEK
    final encKey = _aesKeyUnwrap(masterkeyFile.primaryMasterKey, kek);
    final macKey = _aesKeyUnwrap(masterkeyFile.hmacMasterKey, kek);

    // 3. Verify the vault version HMAC
    //    versionMac = base64(HMAC-SHA256(macKey, versionBytes))
    //    where versionBytes = big-endian uint32 of the version number
    final versionBytes = ByteData(4)
      ..setUint32(0, masterkeyFile.version, Endian.big);
    final expectedMac = crypto.Hmac(
      crypto.sha256,
      macKey,
    ).convert(versionBytes.buffer.asUint8List()).bytes;
    final storedMac = base64.decode(masterkeyFile.versionMac);
    if (!_constantTimeEquals(Uint8List.fromList(expectedMac), storedMac)) {
      throw const FormatException(
        'Vault unlock failed: wrong password or corrupted masterkey file',
      );
    }

    _verifyVaultConfig(vaultConfigJwt, encKey, macKey);
    if (config.version != 8 || config.cipherCombo != 'SIV_GCM') {
      throw UnsupportedError('Only Cryptomator format 8 SIV_GCM is supported');
    }
    if (config.keyId != 'masterkeyfile:masterkey.cryptomator' ||
        config.shorteningThreshold < 32 ||
        config.shorteningThreshold > 255) {
      throw const FormatException(
        'Unsupported Cryptomator vault configuration',
      );
    }
    // Values obtained during detection are untrusted. Use only the values
    // authenticated by the vault's JWT after recovering the master keys.
    final authenticatedMeta = CryptomatorVault(
      vaultPath: vaultMeta.vaultPath,
      masterkeyFilePath: vaultMeta.masterkeyFilePath,
      version: config.version,
      cipherCombo: config.cipherCombo,
      shorteningThreshold: config.shorteningThreshold,
    );
    return UnlockedVault(
      vault: authenticatedMeta,
      encKey: encKey,
      macKey: macKey,
    );
  }

  static void _verifyVaultConfig(
    String jwt,
    Uint8List encKey,
    Uint8List macKey,
  ) {
    final parts = jwt.split('.');
    final header = VaultConfig._decodeJwtObject(parts[0]);
    final crypto.Hash hash;
    switch (header['alg']) {
      case 'HS256':
        hash = crypto.sha256;
        break;
      case 'HS384':
        hash = crypto.sha384;
        break;
      case 'HS512':
        hash = crypto.sha512;
        break;
      default:
        throw const FormatException(
          'Unsupported vault JWT signature algorithm',
        );
    }
    if (header.containsKey('crit') || header.containsKey('b64')) {
      throw const FormatException('Unsupported vault JWT extensions');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[2])) {
      throw const FormatException('Invalid vault JWT signature encoding');
    }
    final signature = base64Url.decode(parts[2]);
    final expected = crypto.Hmac(
      hash,
      _concat(encKey, macKey),
    ).convert(ascii.encode('${parts[0]}.${parts[1]}')).bytes;
    if (!_constantTimeEquals(Uint8List.fromList(expected), signature)) {
      throw const FormatException('Vault configuration signature is invalid');
    }
  }

  // ---------------------------------------------------------------------------
  // Filename encryption / decryption (SIV mode)
  // ---------------------------------------------------------------------------

  /// Encrypt a UTF-8/NFC filename with RFC 5297 AES-SIV and the parent
  /// directory ID as a distinct associated-data string.
  ///
  /// For a `.c9s` result, use [encryptFilenameMetadata] and persist its
  /// `fullName` in the entry's `name.c9s` reverse-mapping file.
  static String encryptFilename(
    String name,
    String dirId,
    UnlockedVault vault,
  ) => encryptFilenameMetadata(name, dirId, vault).entryName;

  static CryptomatorEncryptedName encryptFilenameMetadata(
    String name,
    String dirId,
    UnlockedVault vault,
  ) {
    _validateKeys(vault);
    final plaintext = Uint8List.fromList(utf8.encode(unorm.nfc(name)));
    final raw = AesSiv.encrypt(
      plaintext,
      vault.encKey,
      vault.macKey,
      associatedData: [Uint8List.fromList(utf8.encode(dirId))],
    );
    final fullName = '${base64Url.encode(raw)}.c9r';
    final entryName = fullName.length > vault.vault.shorteningThreshold
        ? '${base64Url.encode(crypto.sha1.convert(utf8.encode(fullName)).bytes)}.c9s'
        : fullName;
    return CryptomatorEncryptedName(fullName, entryName);
  }

  /// Decrypt a full `.c9r` name (or the bytes read from `name.c9s`).
  ///
  /// Legacy CrispCloud HMAC/CTR placeholders were not Cryptomator ciphertext.
  /// There is intentionally no fallback to that unaudited format.
  static String decryptFilename(
    String encrypted,
    String dirId,
    UnlockedVault vault,
  ) {
    _validateKeys(vault);
    var encoded = encrypted;
    if (encoded.endsWith('.c9r')) {
      encoded = encoded.substring(0, encoded.length - 4);
    } else if (encoded.endsWith('.c9s')) {
      throw const FormatException(
        'Shortened filename requires its name.c9s reverse-mapping file',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(encoded)) {
      throw const FormatException('Invalid base64url Cryptomator filename');
    }
    final plaintext = AesSiv.decrypt(
      base64Url.decode(encoded),
      vault.encKey,
      vault.macKey,
      associatedData: [Uint8List.fromList(utf8.encode(dirId))],
    );
    return utf8.decode(plaintext);
  }

  // ---------------------------------------------------------------------------
  // Root path convenience helpers
  // ---------------------------------------------------------------------------

  /// Resolve a single root filename to `d/<2>/<30>/<encrypted name>`.
  ///
  /// Nested paths cannot be resolved from a plaintext path alone: the random
  /// ID of each subdirectory must first be read from its `dir.c9r` file. The
  /// old deterministic path helper invented these IDs and was incompatible
  /// with Cryptomator. It is deliberately not used as a migration fallback.
  static String encryptPath(String clearPath, UnlockedVault vault) {
    final parts = _splitPath(clearPath);
    if (parts.isEmpty) return '';
    if (parts.length != 1) {
      throw UnsupportedError('Nested vault paths require dir.c9r metadata');
    }
    final name = encryptFilenameMetadata(parts.single, '', vault);
    if (name.isShortened) {
      throw UnsupportedError('Shortened vault paths require name.c9s metadata');
    }
    final hash = hashDirectoryId('', vault);
    return 'd/${hash.substring(0, 2)}/${hash.substring(2)}/${name.entryName}';
  }

  /// Reverse [encryptPath] for root files only, checking the root directory
  /// hash. Nested/shortened paths require vault filesystem metadata.
  static String decryptPath(String encPath, UnlockedVault vault) {
    if (encPath.isEmpty) return '';
    var working = encPath;
    if (working.startsWith('d/')) {
      final hash = hashDirectoryId('', vault);
      final prefix = 'd/${hash.substring(0, 2)}/${hash.substring(2)}/';
      if (!working.startsWith(prefix)) {
        throw const FormatException('Path does not belong to the vault root');
      }
      working = working.substring(prefix.length);
    }
    if (working.contains('/') || working.contains('\\')) {
      throw UnsupportedError('Nested vault paths require dir.c9r metadata');
    }
    return decryptFilename(working, '', vault);
  }

  // ---------------------------------------------------------------------------
  // File header and directory IDs
  // ---------------------------------------------------------------------------

  /// Authenticate a complete 68-byte SIV_GCM file header and extract its
  /// randomly generated content key. A nonce alone is not sufficient.
  ///
  /// Layout: 12-byte nonce || AES-GCM(8 reserved bytes || 32-byte key) || tag.
  /// The old HMAC("fileKey" || nonce) helper was not the Cryptomator format.
  /// Content chunks must separately authenticate their chunk index and the
  /// header nonce as AAD; EncryptionService is not a vault content codec.
  static Uint8List getContentKey(Uint8List fileHeader, UnlockedVault vault) {
    _validateKeys(vault);
    if (fileHeader.length != 68) {
      throw const FormatException(
        'A complete 68-byte Cryptomator header is required',
      );
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(vault.encKey),
          128,
          fileHeader.sublist(0, 12),
          Uint8List(0),
        ),
      );
    final Uint8List payload;
    try {
      payload = cipher.process(fileHeader.sublist(12));
    } on InvalidCipherTextException {
      throw const FormatException(
        'Cryptomator file header authentication failed',
      );
    }
    return payload.sublist(8, 40);
  }

  /// Cryptomator directory ID hash: base32(SHA-1(AES-SIV(dirId))).
  /// AES-SIV has NO associated-data inputs here (distinct from an empty AD
  /// string used for root filenames) and requires both master keys.
  static String hashDirectoryId(String dirId, UnlockedVault vault) {
    _validateKeys(vault);
    final encrypted = AesSiv.encrypt(
      Uint8List.fromList(utf8.encode(dirId)),
      vault.encKey,
      vault.macKey,
    );
    return _base32Encode(
      Uint8List.fromList(crypto.sha1.convert(encrypted).bytes),
    );
  }

  static void _validateKeys(UnlockedVault vault) {
    if (vault.encKey.length != 32 || vault.macKey.length != 32) {
      throw ArgumentError('Cryptomator requires two 32-byte master keys');
    }
    if (vault.vault.version != 8 || vault.vault.cipherCombo != 'SIV_GCM') {
      throw UnsupportedError('Only Cryptomator format 8 SIV_GCM is supported');
    }
  }

  // ---------------------------------------------------------------------------
  // scrypt KDF (via pointycastle)
  // ---------------------------------------------------------------------------

  static Uint8List _scrypt(
    Uint8List password,
    Uint8List salt,
    int N, // CPU/memory cost parameter
    int r, // block size
    int p, // parallelisation
    int dkLen, // derived key length
  ) {
    // Masterkey files are untrusted until after derivation. Bound their work
    // before allocating the scrypt table (the default N=32768, r=8 is 32 MiB).
    // This primitive supports at most 128 MiB of scrypt working memory.
    const maxWorkingBytes = 128 * 1024 * 1024;
    if (N < 2 ||
        N > 1048576 ||
        (N & (N - 1)) != 0 ||
        r < 1 ||
        r > 64 ||
        p != 1 ||
        128 * r * (N + 3) > maxWorkingBytes) {
      throw const FormatException(
        'scrypt parameters exceed supported resource limits',
      );
    }
    final params = ScryptParameters(N, r, p, dkLen, salt);
    final kdf = Scrypt();
    kdf.init(params);
    return kdf.process(password);
  }

  // ---------------------------------------------------------------------------
  // AES Key Wrap / Unwrap (RFC 3394)
  // ---------------------------------------------------------------------------

  /// Unwrap a key wrapped with AES Key Wrap (RFC 3394).
  ///
  /// [wrappedKey] must be [keyLen + 8] bytes (key + 8-byte integrity check).
  /// [kek] must be 16, 24, or 32 bytes.
  /// Returns the unwrapped key bytes.
  /// Throws [FormatException] if integrity check fails (wrong KEK).
  static Uint8List _aesKeyUnwrap(Uint8List wrappedKey, Uint8List kek) {
    if (wrappedKey.length < 24 || (wrappedKey.length - 8) % 8 != 0) {
      throw const FormatException(
        'Invalid wrapped key length for AES Key Unwrap',
      );
    }

    final n = (wrappedKey.length ~/ 8) - 1; // number of 64-bit blocks
    final a = wrappedKey.sublist(0, 8).toList(); // integrity value
    final r = List.generate(
      n,
      (i) => wrappedKey.sublist(8 + i * 8, 16 + i * 8).toList(),
    );

    final aes = AESEngine();
    aes.init(false, KeyParameter(kek)); // decrypt mode

    // RFC 3394 unwrap: 6n iterations in reverse
    for (var j = 5; j >= 0; j--) {
      for (var i = n; i >= 1; i--) {
        final t = n * j + i;
        // XOR A with t (big-endian 64-bit)
        final tBytes = ByteData(8)..setUint64(0, t, Endian.big);
        final aXor = List.generate(8, (k) => a[k] ^ tBytes.getUint8(k));
        // Decrypt block: B = AES-1(KEK, (A XOR t) | R[i])
        final block = Uint8List(16);
        block.setRange(0, 8, aXor);
        block.setRange(8, 16, r[i - 1]);
        final dec = Uint8List(16);
        aes.processBlock(block, 0, dec, 0);
        // Update A and R[i]
        for (var k = 0; k < 8; k++) {
          a[k] = dec[k];
        }
        for (var k = 0; k < 8; k++) {
          r[i - 1][k] = dec[8 + k];
        }
      }
    }

    // Verify integrity check value (should be 0xA6A6A6A6A6A6A6A6)
    const iv = [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6];
    if (!_constantTimeEquals(Uint8List.fromList(a), Uint8List.fromList(iv))) {
      throw const FormatException(
        'AES Key Unwrap integrity check failed: wrong KEK',
      );
    }

    // Reconstruct the key
    final key = Uint8List(n * 8);
    for (var i = 0; i < n; i++) {
      key.setRange(i * 8, (i + 1) * 8, r[i]);
    }
    return key;
  }

  /// Unwrap a key wrapped with AES Key Wrap (RFC 3394) — public test accessor.
  ///
  /// Delegates to [_aesKeyUnwrap]. Exposed so test code can verify round-trips.
  static Uint8List aesKeyUnwrap(Uint8List wrappedKey, Uint8List kek) {
    return _aesKeyUnwrap(wrappedKey, kek);
  }

  /// Wrap a key using AES Key Wrap (RFC 3394).
  ///
  /// Useful for creating test masterkey files without external tooling.
  static Uint8List aesKeyWrap(Uint8List keyToWrap, Uint8List kek) {
    if (keyToWrap.length < 16 || keyToWrap.length % 8 != 0) {
      throw const FormatException(
        'RFC 3394 requires at least two 8-byte key blocks',
      );
    }

    final n = keyToWrap.length ~/ 8;
    final a = List<int>.filled(8, 0xA6); // integrity check value
    final r = List.generate(
      n,
      (i) => keyToWrap.sublist(i * 8, (i + 1) * 8).toList(),
    );

    final aes = AESEngine();
    aes.init(true, KeyParameter(kek)); // encrypt mode

    // RFC 3394 wrap: 6n iterations
    for (var j = 0; j < 6; j++) {
      for (var i = 1; i <= n; i++) {
        // Encrypt block: B = AES(KEK, A | R[i])
        final block = Uint8List(16);
        block.setRange(0, 8, a);
        block.setRange(8, 16, r[i - 1]);
        final enc = Uint8List(16);
        aes.processBlock(block, 0, enc, 0);
        // Update A and R[i]
        final t = n * j + i;
        final tBytes = ByteData(8)..setUint64(0, t, Endian.big);
        for (var k = 0; k < 8; k++) {
          a[k] = enc[k] ^ tBytes.getUint8(k);
        }
        for (var k = 0; k < 8; k++) {
          r[i - 1][k] = enc[8 + k];
        }
      }
    }

    // Assemble output: A | R[1] | R[2] | ... | R[n]
    final output = Uint8List(8 + n * 8);
    output.setRange(0, 8, a);
    for (var i = 0; i < n; i++) {
      output.setRange(8 + i * 8, 16 + i * 8, r[i]);
    }
    return output;
  }

  // ---------------------------------------------------------------------------
  // Base32 (RFC 4648, upper-case, no padding)
  // ---------------------------------------------------------------------------

  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String _base32Encode(Uint8List data) {
    if (data.isEmpty) return '';
    final sb = StringBuffer();
    var buffer = 0;
    var bitsLeft = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        sb.write(_base32Alphabet[(buffer >> bitsLeft) & 0x1F]);
      }
    }
    if (bitsLeft > 0) {
      sb.write(_base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]);
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, out.length, b);
    return out;
  }

  static String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last;
  }

  static List<String> _splitPath(String path) {
    return path
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Masterkey file creation helpers (for testing / vault creation)
  // ---------------------------------------------------------------------------

  /// Create a new [MasterkeyFile] from raw master keys using the given password.
  /// Uses scrypt with recommended Cryptomator v8 parameters by default.
  static MasterkeyFile createMasterkeyFile(
    Uint8List encKey,
    Uint8List macKey,
    String password, {
    int scryptCostParam = 32768,
    int scryptBlockSize = 8,
    int vaultVersion = 999,
  }) {
    if (encKey.length != 32 || macKey.length != 32) {
      throw ArgumentError('Cryptomator requires two 32-byte master keys');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );

    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final kek = _scrypt(
      passwordBytes,
      salt,
      scryptCostParam,
      scryptBlockSize,
      1,
      32,
    );

    final wrappedEnc = aesKeyWrap(encKey, kek);
    final wrappedMac = aesKeyWrap(macKey, kek);

    // Generate version MAC
    final versionBytes = ByteData(4)..setUint32(0, vaultVersion, Endian.big);
    final versionMac = base64.encode(
      crypto.Hmac(
        crypto.sha256,
        macKey,
      ).convert(versionBytes.buffer.asUint8List()).bytes,
    );

    return MasterkeyFile(
      version: vaultVersion,
      scryptSalt: salt,
      scryptCostParam: scryptCostParam,
      scryptBlockSize: scryptBlockSize,
      primaryMasterKey: wrappedEnc,
      hmacMasterKey: wrappedMac,
      versionMac: versionMac,
    );
  }

  /// Generate a random 32-byte master key.
  static Uint8List generateMasterKey() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  }
}
