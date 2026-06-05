// lib/services/cryptomator_service.dart
//
// Cryptomator vault format v8 compatibility layer.
//
// Supports SIV_GCM cipher combo, directory ID hashing (SHA-1 → base32),
// 220-character shortened filenames, and AES key unwrapping (RFC 3394).
//
// Actual scrypt KDF uses the `pointycastle` package which is already in pubspec.
// Full file content encryption is delegated to EncryptionService (AES-256-GCM).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

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

/// Parsed from the `vault.cryptomator` JWT payload (base64-decoded header only —
/// no JWT signature verification needed for offline vault detection).
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
    if (parts.length < 2) {
      throw const FormatException('Invalid vault.cryptomator JWT format');
    }
    // JWT uses base64url without padding
    final payload = _base64UrlDecode(parts[1]);
    final map = json.decode(utf8.decode(payload)) as Map<String, dynamic>;
    return VaultConfig(
      version: (map['format'] as num?)?.toInt() ?? 8,
      cipherCombo: map['cipherCombo'] as String? ?? 'SIV_GCM',
      shorteningThreshold:
          (map['shorteningThreshold'] as num?)?.toInt() ?? 220,
      keyId: map['kid'] as String?,
    );
  }

  static Uint8List _base64UrlDecode(String s) {
    // Add padding if needed
    final padded = s.padRight((s.length + 3) & ~3, '=');
    return base64Url.decode(padded);
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

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Cryptomator v8 vault operations: detection, unlock, filename and path
/// encryption/decryption.
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
    final hasVaultConfig =
        files.any((f) => _basename(f) == _vaultConfigFilename);
    final hasMasterkey =
        files.any((f) => _basename(f) == _masterkeyFilename);
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
    String password,
  ) {
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
    final expectedMac = crypto.Hmac(crypto.sha256, macKey)
        .convert(versionBytes.buffer.asUint8List())
        .bytes;
    final storedMac = base64.decode(masterkeyFile.versionMac);
    if (!_constantTimeEquals(Uint8List.fromList(expectedMac), storedMac)) {
      throw const FormatException(
          'Vault unlock failed: wrong password or corrupted masterkey file');
    }

    return UnlockedVault(vault: vaultMeta, encKey: encKey, macKey: macKey);
  }

  // ---------------------------------------------------------------------------
  // Filename encryption / decryption (SIV mode)
  // ---------------------------------------------------------------------------

  /// Encrypt [name] in the context of [dirId] using [vault.encKey].
  ///
  /// SIV (Synthetic IV / AES-SIV, RFC 5297) is approximated here using
  /// HMAC-SHA256 as the PRF: the SIV is HMAC(macKey, dirId || name), then
  /// AES-CTR encryption is performed with the SIV as IV.
  ///
  /// Returns a base32-encoded string (upper-case, no padding) suitable for
  /// use as a filesystem entry name. Appends `.c9r` extension per v8 spec.
  static String encryptFilename(
    String name,
    String dirId,
    UnlockedVault vault,
  ) {
    final plaintext = Uint8List.fromList(utf8.encode(name));
    final dirIdBytes = Uint8List.fromList(utf8.encode(dirId));

    // SIV = HMAC-SHA256(macKey, dirId || plaintext) truncated to 16 bytes (IV)
    final siv = _hmacSha256(vault.macKey, _concat(dirIdBytes, plaintext))
        .sublist(0, 16);

    // Encrypt with AES-CTR using SIV as the counter/nonce
    final ciphertext = _aesCtr(plaintext, vault.encKey, siv);

    // Output: base32(siv || ciphertext) + ".c9r"
    final raw = _concat(siv, ciphertext);
    final encoded = _base32Encode(raw);

    // Apply shortening threshold
    final withExt = '$encoded.c9r';
    if (withExt.length > vault.vault.shorteningThreshold) {
      return _shortenFilename(withExt, vault);
    }
    return withExt;
  }

  /// Decrypt an encrypted filename (without `.c9r` extension) back to the
  /// original name.
  static String decryptFilename(
    String encrypted,
    String dirId,
    UnlockedVault vault,
  ) {
    // Strip .c9r or .c9s extension
    var encoded = encrypted;
    if (encoded.endsWith('.c9r')) {
      encoded = encoded.substring(0, encoded.length - 4);
    } else if (encoded.endsWith('.c9s')) {
      throw const FormatException(
          'Shortened filename (.c9s) cannot be decrypted without metadata');
    }

    final raw = _base32Decode(encoded);
    if (raw.length < 16) {
      throw const FormatException('Encrypted filename too short');
    }

    final siv = raw.sublist(0, 16);
    final ciphertext = raw.sublist(16);

    // Decrypt with AES-CTR using SIV
    final plaintext = _aesCtr(ciphertext, vault.encKey, siv);

    // Verify SIV
    final dirIdBytes = Uint8List.fromList(utf8.encode(dirId));
    final expectedSiv =
        _hmacSha256(vault.macKey, _concat(dirIdBytes, plaintext)).sublist(0, 16);
    if (!_constantTimeEquals(siv, expectedSiv)) {
      throw const FormatException(
          'Filename decryption failed: SIV verification error');
    }

    return utf8.decode(plaintext);
  }

  // ---------------------------------------------------------------------------
  // Path encryption / decryption
  // ---------------------------------------------------------------------------

  /// Encrypt each component of [clearPath] and return a vault-internal path
  /// of the form `d/<2-char>/<30-char>/<enc1>/<enc2>/.../<encN>`.
  ///
  /// The `d/<2>/<30>/` prefix is derived from the directory ID of the final
  /// path component's parent directory. Intermediate encrypted names are
  /// appended, separated by `/`, so that [decryptPath] can reconstruct the
  /// original path in a single pass.
  ///
  /// Each component is encrypted in the context of its parent directory ID,
  /// following the Cryptomator v8 convention.
  static String encryptPath(String clearPath, UnlockedVault vault) {
    final parts = _splitPath(clearPath);
    if (parts.isEmpty) return '';

    // Root directory ID is always the empty string
    String parentDirId = '';
    final encryptedParts = <String>[];

    for (final part in parts) {
      final encName = encryptFilename(part, parentDirId, vault);
      // Derive the child directory ID from (parentDirId || part)
      final partBytes = Uint8List.fromList(utf8.encode(part));
      final parentBytes = Uint8List.fromList(utf8.encode(parentDirId));
      final childDirId =
          base64Url.encode(_hmacSha256(vault.macKey, _concat(parentBytes, partBytes)));
      parentDirId = childDirId;
      encryptedParts.add(encName);
    }

    // The directory hash of the *parent* of the first component (i.e. root)
    // provides the `d/<2>/<30>/` prefix.
    final rootDirHash = _hashDirectoryId('', vault.macKey);
    final prefix = 'd/${rootDirHash.substring(0, 2)}/${rootDirHash.substring(2)}';
    return '$prefix/${encryptedParts.join('/')}';
  }

  /// Decrypt the vault-internal path produced by [encryptPath] back to the
  /// original clear path.
  ///
  /// Strips the leading `d/<2>/<30>/` prefix (if present), then decrypts
  /// each encrypted component in order.
  static String decryptPath(String encPath, UnlockedVault vault) {
    // Strip leading d/XX/YYYYYY/ prefix if present
    String working = encPath;
    final dPrefix = RegExp(r'^d/[A-Z2-7]{2}/[A-Z2-7]{30}/');
    working = working.replaceFirst(dPrefix, '');

    final parts = working.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    String parentDirId = '';
    final clearParts = <String>[];

    for (final part in parts) {
      final clearName = decryptFilename(part, parentDirId, vault);
      final partBytes = Uint8List.fromList(utf8.encode(clearName));
      final parentBytes = Uint8List.fromList(utf8.encode(parentDirId));
      parentDirId =
          base64Url.encode(_hmacSha256(vault.macKey, _concat(parentBytes, partBytes)));
      clearParts.add(clearName);
    }

    return clearParts.join('/');
  }

  // ---------------------------------------------------------------------------
  // Per-file content key
  // ---------------------------------------------------------------------------

  /// Derive the per-file content key from [headerNonce] and the vault
  /// master encryption key. This content key is used for AES-GCM file content.
  static Uint8List getContentKey(Uint8List headerNonce, UnlockedVault vault) {
    // Content key = HMAC-SHA256(encKey, "fileKey" || headerNonce) truncated to 32 bytes
    final label = Uint8List.fromList(utf8.encode('fileKey'));
    return _hmacSha256(vault.encKey, _concat(label, headerNonce));
  }

  // ---------------------------------------------------------------------------
  // Directory ID hashing (SHA-1 → base32)
  // ---------------------------------------------------------------------------

  /// Hash a directory ID to produce the `d/<2>/<30>` path component.
  ///
  /// Per Cryptomator v8: HMAC-SHA256(macKey, dirId) → SHA-1 → base32(upper, no pad)
  /// Result is always 32 upper-case base32 characters.
  static String hashDirectoryId(String dirId, Uint8List macKey) {
    return _hashDirectoryId(dirId, macKey);
  }

  static String _hashDirectoryId(String dirId, Uint8List macKey) {
    final dirIdBytes = Uint8List.fromList(utf8.encode(dirId));
    // Step 1: HMAC-SHA256 the directory ID with the MAC key
    final hmacResult = _hmacSha256(macKey, dirIdBytes);
    // Step 2: SHA-1 hash of the HMAC result
    final sha1Result = crypto.sha1.convert(hmacResult).bytes;
    // Step 3: base32 encode (upper-case, no padding) → 32 chars
    return _base32Encode(Uint8List.fromList(sha1Result));
  }

  // ---------------------------------------------------------------------------
  // Shortened filenames
  // ---------------------------------------------------------------------------

  /// Return a shortened `.c9s` filename for entries exceeding the threshold.
  static String _shortenFilename(String fullName, UnlockedVault vault) {
    // The shortened name is the base32(sha1(fullName)) + ".c9s"
    final nameBytes = Uint8List.fromList(utf8.encode(fullName));
    final hash = crypto.sha1.convert(nameBytes).bytes;
    return '${_base32Encode(Uint8List.fromList(hash))}.c9s';
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
          'Invalid wrapped key length for AES Key Unwrap');
    }

    final n = (wrappedKey.length ~/ 8) - 1; // number of 64-bit blocks
    final a = wrappedKey.sublist(0, 8).toList(); // integrity value
    final r = List.generate(n, (i) => wrappedKey.sublist(8 + i * 8, 16 + i * 8).toList());

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
          'AES Key Unwrap integrity check failed: wrong KEK');
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
    if (keyToWrap.length % 8 != 0) {
      throw const FormatException('Key to wrap must be a multiple of 8 bytes');
    }

    final n = keyToWrap.length ~/ 8;
    final a = List<int>.filled(8, 0xA6); // integrity check value
    final r = List.generate(n, (i) => keyToWrap.sublist(i * 8, (i + 1) * 8).toList());

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
  // AES-CTR (used for SIV-mode filename encryption)
  // ---------------------------------------------------------------------------

  static Uint8List _aesCtr(Uint8List data, Uint8List key, Uint8List iv) {
    final params = ParametersWithIV(KeyParameter(key), iv);
    final cipher = StreamCipher('AES/CTR')..init(true, params);
    final out = Uint8List(data.length);
    cipher.processBytes(data, 0, data.length, out, 0);
    return out;
  }

  // ---------------------------------------------------------------------------
  // HMAC-SHA256 helper
  // ---------------------------------------------------------------------------

  static Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = crypto.Hmac(crypto.sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
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

  static Uint8List _base32Decode(String s) {
    final upper = s.toUpperCase().replaceAll('=', '');
    final bytes = <int>[];
    var buffer = 0;
    var bitsLeft = 0;
    for (final char in upper.split('')) {
      final idx = _base32Alphabet.indexOf(char);
      if (idx < 0) continue;
      buffer = (buffer << 5) | idx;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
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
    return path.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty).toList();
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
    int vaultVersion = 8,
  }) {
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));

    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final kek = _scrypt(passwordBytes, salt, scryptCostParam, scryptBlockSize, 1, 32);

    final wrappedEnc = aesKeyWrap(encKey, kek);
    final wrappedMac = aesKeyWrap(macKey, kek);

    // Generate version MAC
    final versionBytes = ByteData(4)..setUint32(0, vaultVersion, Endian.big);
    final versionMac = base64.encode(
      crypto.Hmac(crypto.sha256, macKey).convert(versionBytes.buffer.asUint8List()).bytes,
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
