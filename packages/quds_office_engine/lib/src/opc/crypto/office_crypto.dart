import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../crypto/aes.dart';
import '../../io/byte_source.dart';
import '../../xml/xml_reader.dart';
import '../ole/cfbf_reader.dart';
import '../ole/cfbf_writer.dart';

/// File-level Office password encryption (MS-OFFCRYPTO Agile + Standard).
abstract final class OfficeCrypto {
  /// isEncrypted API.
  static bool isEncrypted(Uint8List bytes) {
    if (!CfbfFile.isCfbf(bytes)) {
      return false;
    }
    try {
      final CfbfFile file = CfbfFile.fromBytes(bytes);
      return file.readStream('EncryptionInfo') != null &&
          file.readStream('EncryptedPackage') != null;
    } on Object {
      return false;
    }
  }

  /// Returns [bytes] unchanged when the package is a plain ZIP.
  ///
  /// Encrypted CFBF packages require [password].
  static Uint8List unlock(Uint8List bytes, {String? password}) {
    if (!isEncrypted(bytes)) {
      return bytes;
    }
    if (password == null || password.isEmpty) {
      throw const OfficePasswordRequiredException();
    }
    return decrypt(bytes, password);
  }

  /// decrypt API.
  static Uint8List decrypt(Uint8List bytes, String password) {
    if (!CfbfFile.isCfbf(bytes)) {
      throw const OfficePasswordException('Not an encrypted Office package');
    }
    final CfbfFile file = CfbfFile.fromBytes(bytes);
    final Uint8List? info = file.readStream('EncryptionInfo');
    final Uint8List? pack = file.readStream('EncryptedPackage');
    if (info == null || pack == null) {
      throw const OfficePasswordException(
        'Missing EncryptionInfo/EncryptedPackage',
      );
    }
    if (info.length < 8) {
      throw const OfficePasswordException('Truncated EncryptionInfo');
    }
    final int major = info[0] | (info[1] << 8);
    final int minor = info[2] | (info[3] << 8);
    if (major == 4 && minor == 4) {
      return _Agile.decrypt(info, pack, password);
    }
    if (minor == 2 || minor == 3) {
      return _Standard.decrypt(info, pack, password);
    }
    throw OfficePasswordException(
      'Unsupported encryption version $major.$minor',
    );
  }

  /// Wraps a clear OPC ZIP in an Agile-encrypted CFBF (Office 2013+ default).
  static Uint8List encrypt(
    Uint8List clearOpc,
    String password, {
    int spinCount = 100000,
  }) {
    if (password.isEmpty) {
      throw const OfficePasswordException('Password must not be empty');
    }
    return _Agile.encrypt(clearOpc, password, spinCount: spinCount);
  }
}

/// Class OfficePasswordException.
class OfficePasswordException implements Exception {
  /// OfficePasswordException API.
  const OfficePasswordException(this.message);

  /// message API.
  final String message;
  @override
  /// toString API.
  String toString() => 'OfficePasswordException: $message';
}

/// Class OfficePasswordRequiredException.
class OfficePasswordRequiredException extends OfficePasswordException {
  /// OfficePasswordRequiredException API.
  const OfficePasswordRequiredException()
    : super('This Office file is password-protected');
}

abstract final class _Hash {
  /// digest API.
  static List<int> digest(String name, List<int> data) {
    return switch (name.toUpperCase().replaceAll('-', '')) {
      'SHA1' => sha1.convert(data).bytes,
      'SHA256' => sha256.convert(data).bytes,
      'SHA384' => sha384.convert(data).bytes,
      'SHA512' => sha512.convert(data).bytes,
      _ => throw OfficePasswordException('Unsupported hash $name'),
    };
  }

  /// hmacDigest API.
  static List<int> hmacDigest(String name, List<int> key, List<int> data) {
    final Hash h = switch (name.toUpperCase().replaceAll('-', '')) {
      'SHA1' => sha1,
      'SHA256' => sha256,
      'SHA384' => sha384,
      'SHA512' => sha512,
      _ => throw OfficePasswordException('Unsupported HMAC $name'),
    };
    return Hmac(h, key).convert(data).bytes;
  }
}

Uint8List _utf16le(String text) {
  /// out API.
  final Uint8List out = Uint8List(text.length * 2);
  for (int i = 0; i < text.length; i++) {
    final int c = text.codeUnitAt(i);
    out[i * 2] = c & 0xFF;
    out[i * 2 + 1] = (c >> 8) & 0xFF;
  }
  return out;
}

Uint8List _fit(List<int> data, int size) {
  /// out API.
  final Uint8List out = Uint8List(size);
  if (data.length >= size) {
    out.setRange(0, size, data);
  } else {
    out.setRange(0, data.length, data);
    out.fillRange(data.length, size, 0x36);
  }
  return out;
}

Uint8List _u32(int value) {
  return Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;
}

Uint8List _concat(List<List<int>> parts) {
  /// n API.
  final int n = parts.fold<int>(0, (int a, List<int> b) => a + b.length);

  /// out API.
  final Uint8List out = Uint8List(n);

  /// o API.
  var o = 0;
  for (final List<int> p in parts) {
    out.setRange(o, o + p.length, p);
    o += p.length;
  }
  return out;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }

  /// diff API.
  var diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final Random _rng = Random.secure();

Uint8List _random(int n) {
  return Uint8List.fromList(<int>[
    for (int i = 0; i < n; i++) _rng.nextInt(256),
  ]);
}

abstract final class _Agile {
  static const List<int> _verifierInputKey = <int>[
    0xFE,
    0xA7,
    0xD2,
    0x76,
    0x3B,
    0x4B,
    0x9E,
    0x79,
  ];
  static const List<int> _verifierValueKey = <int>[
    0xD7,
    0xAA,
    0x0F,
    0x6D,
    0x30,
    0x61,
    0x34,
    0x4E,
  ];
  static const List<int> _secretKeyBlock = <int>[
    0x14,
    0x6E,
    0x0B,
    0xE7,
    0xAC,
    0xCA,
    0xD1,
    0xD6,
  ];
  static const List<int> _hmacKeyBlock = <int>[
    0x5F,
    0xB2,
    0xAD,
    0x01,
    0x0C,
    0xB9,
    0xE1,
    0xF6,
  ];
  static const List<int> _hmacValueBlock = <int>[
    0xA0,
    0x67,
    0x7F,
    0x02,
    0xB2,
    0x2C,
    0x84,
    0x33,
  ];

  /// decrypt API.
  static Uint8List decrypt(Uint8List info, Uint8List pack, String password) {
    final _AgileParams p = _parse(info);
    final Uint8List hn = _spin(
      p.hashName,
      p.encryptedSalt,
      password,
      p.spinCount,
    );
    final Uint8List verifierIn = _cryptValue(
      p,
      hn,
      _verifierInputKey,
      p.encryptedVerifierHashInput,
      decrypt: true,
    );
    final Uint8List verifierHash = _cryptValue(
      p,
      hn,
      _verifierValueKey,
      p.encryptedVerifierHashValue,
      decrypt: true,
    );
    final List<int> expected = _Hash.digest(p.hashName, verifierIn);
    if (!_equal(_fit(expected, p.hashSize), _fit(verifierHash, p.hashSize))) {
      throw const OfficePasswordException('Incorrect password');
    }
    final Uint8List secret = _fit(
      _cryptValue(p, hn, _secretKeyBlock, p.encryptedKeyValue, decrypt: true),
      p.keyBytes,
    );
    return _decryptPackage(p, secret, pack);
  }

  /// encrypt API.
  static Uint8List encrypt(
    Uint8List clear,
    String password, {
    required int spinCount,
  }) {
    const String hashName = 'SHA512';
    const int hashSize = 64;
    const int keyBits = 256;
    const int blockSize = 16;
    const int saltSize = 16;
    final Uint8List keySalt = _random(saltSize);
    final Uint8List encSalt = _random(saltSize);
    final Uint8List secret = _random(keyBits ~/ 8);
    final Uint8List verifier = _random(saltSize);
    final _AgileParams p = _AgileParams(
      hashName: hashName,
      hashSize: hashSize,
      keyBits: keyBits,
      blockSize: blockSize,
      saltSize: saltSize,
      spinCount: spinCount,
      keyDataSalt: keySalt,
      encryptedSalt: encSalt,
      encryptedVerifierHashInput: Uint8List(0),
      encryptedVerifierHashValue: Uint8List(0),
      encryptedKeyValue: Uint8List(0),
      encryptedHmacKey: Uint8List(0),
      encryptedHmacValue: Uint8List(0),
    );
    final Uint8List hn = _spin(hashName, encSalt, password, spinCount);
    final Uint8List encVerifier = _cryptValue(
      p,
      hn,
      _verifierInputKey,
      verifier,
      decrypt: false,
    );
    final Uint8List encVerifierHash = _cryptValue(
      p,
      hn,
      _verifierValueKey,
      Uint8List.fromList(_Hash.digest(hashName, verifier)),
      decrypt: false,
    );
    final Uint8List encKey = _cryptValue(
      p,
      hn,
      _secretKeyBlock,
      secret,
      decrypt: false,
    );
    final Uint8List pack = _encryptPackage(p, secret, clear);
    final Uint8List hmacKey = _random(hashSize);
    final Uint8List hmacValue = Uint8List.fromList(
      _Hash.hmacDigest(hashName, hmacKey, pack),
    );
    final Uint8List encHmacKey = Aes.cbcEncrypt(
      secret,
      _iv(hashName, keySalt, _hmacKeyBlock, blockSize),
      hmacKey,
    );
    final Uint8List encHmacValue = Aes.cbcEncrypt(
      secret,
      _iv(hashName, keySalt, _hmacValueBlock, blockSize),
      hmacValue,
    );
    final String xml = _infoXml(
      keySalt: keySalt,
      encSalt: encSalt,
      spinCount: spinCount,
      encryptedVerifier: encVerifier,
      encryptedVerifierHash: encVerifierHash,
      encryptedKey: encKey,
      encryptedHmacKey: encHmacKey,
      encryptedHmacValue: encHmacValue,
    );
    final Uint8List info = Uint8List(8 + xml.length);
    info[0] = 4;
    info[2] = 4;
    info[4] = 0x40;
    info.setRange(8, info.length, utf8.encode(xml));
    final CfbfWriter writer = CfbfWriter();
    writer.addStream('EncryptionInfo', info);
    writer.addStream('EncryptedPackage', pack);
    return writer.build();
  }

  static Uint8List _spin(
    String hash,
    Uint8List salt,
    String password,
    int spins,
  ) {
    List<int> h = _Hash.digest(
      hash,
      _concat(<List<int>>[salt, _utf16le(password)]),
    );
    for (int i = 0; i < spins; i++) {
      h = _Hash.digest(hash, _concat(<List<int>>[_u32(i), h]));
    }
    return Uint8List.fromList(h);
  }

  static Uint8List _deriveKey(
    _AgileParams p,
    Uint8List hn,
    List<int> blockKey,
  ) {
    return _fit(
      _Hash.digest(p.hashName, _concat(<List<int>>[hn, blockKey])),
      p.keyBytes,
    );
  }

  static Uint8List _iv(
    String hash,
    Uint8List salt,
    List<int> blockKey,
    int block,
  ) {
    return _fit(
      _Hash.digest(hash, _concat(<List<int>>[salt, blockKey])),
      block,
    );
  }

  static Uint8List _cryptValue(
    _AgileParams p,
    Uint8List hn,
    List<int> blockKey,
    Uint8List data, {
    required bool decrypt,
  }) {
    final Uint8List key = _deriveKey(p, hn, blockKey);
    final Uint8List iv = _iv(
      p.hashName,
      p.encryptedSalt,
      blockKey,
      p.blockSize,
    );
    if (decrypt) {
      return Aes.cbcDecrypt(key, iv, data, unpad: true);
    }
    return Aes.cbcEncrypt(key, iv, data);
  }

  static Uint8List _decryptPackage(
    _AgileParams p,
    Uint8List secret,
    Uint8List pack,
  ) {
    if (pack.length < 8) {
      throw const OfficePasswordException('Truncated EncryptedPackage');
    }
    final int size = ByteCursor(pack).u64le();
    var offset = 8;
    final BytesBuilder out = BytesBuilder(copy: false);
    var remaining = size;
    var i = 0;
    while (remaining > 0 && offset < pack.length) {
      final int clearChunk = remaining < 4096 ? remaining : 4096;
      final int encChunk =
          ((clearChunk + p.blockSize - 1) ~/ p.blockSize) * p.blockSize;
      final int take = offset + encChunk <= pack.length
          ? encChunk
          : pack.length - offset;
      final Uint8List iv = _iv(p.hashName, p.keyDataSalt, _u32(i), p.blockSize);
      final Uint8List dec = Aes.cbcDecrypt(
        secret,
        iv,
        Uint8List.sublistView(pack, offset, offset + take),
        unpad: false,
        keep: clearChunk,
      );
      out.add(dec);
      offset += take;
      remaining -= clearChunk;
      i++;
    }
    final Uint8List result = out.toBytes();
    if (result.length > size) {
      return Uint8List.sublistView(result, 0, size);
    }
    return result;
  }

  static Uint8List _encryptPackage(
    _AgileParams p,
    Uint8List secret,
    Uint8List clear,
  ) {
    final BytesBuilder out = BytesBuilder(copy: false);
    final ByteData len = ByteData(8)..setUint64(0, clear.length, Endian.little);
    out.add(len.buffer.asUint8List());
    var i = 0;
    for (int o = 0; o < clear.length; o += 4096) {
      final int end = o + 4096 < clear.length ? o + 4096 : clear.length;
      final Uint8List chunk = Uint8List.sublistView(clear, o, end);
      final Uint8List iv = _iv(p.hashName, p.keyDataSalt, _u32(i), p.blockSize);
      out.add(
        Aes.cbcEncrypt(secret, iv, chunk, pad: chunk.length % p.blockSize != 0),
      );
      i++;
    }
    return out.toBytes();
  }

  static _AgileParams _parse(Uint8List info) {
    final String xml = utf8.decode(Uint8List.sublistView(info, 8));
    final XmlPullReader reader = XmlPullReader(xml);
    String hashName = 'SHA512';
    var hashSize = 64;
    var keyBits = 256;
    var blockSize = 16;
    var saltSize = 16;
    var spinCount = 100000;
    Uint8List keySalt = Uint8List(16);
    Uint8List encSalt = Uint8List(16);
    Uint8List encVerifier = Uint8List(0);
    Uint8List encVerifierHash = Uint8List(0);
    Uint8List encKey = Uint8List(0);
    Uint8List encHmacKey = Uint8List(0);
    Uint8List encHmacValue = Uint8List(0);
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'keyData') {
        hashName = reader.getAttribute('hashAlgorithm') ?? hashName;
        hashSize = int.parse(reader.getAttribute('hashSize') ?? '$hashSize');
        keyBits = int.parse(reader.getAttribute('keyBits') ?? '$keyBits');
        blockSize = int.parse(reader.getAttribute('blockSize') ?? '$blockSize');
        saltSize = int.parse(reader.getAttribute('saltSize') ?? '$saltSize');
        final String? salt = reader.getAttribute('saltValue');
        if (salt != null) {
          keySalt = Uint8List.fromList(base64.decode(salt));
        }
      } else if (reader.localName == 'dataIntegrity') {
        final String? hk = reader.getAttribute('encryptedHmacKey');
        final String? hv = reader.getAttribute('encryptedHmacValue');
        if (hk != null) {
          encHmacKey = Uint8List.fromList(base64.decode(hk));
        }
        if (hv != null) {
          encHmacValue = Uint8List.fromList(base64.decode(hv));
        }
      } else if (reader.localName == 'encryptedKey') {
        spinCount = int.parse(reader.getAttribute('spinCount') ?? '$spinCount');
        hashName = reader.getAttribute('hashAlgorithm') ?? hashName;
        hashSize = int.parse(reader.getAttribute('hashSize') ?? '$hashSize');
        keyBits = int.parse(reader.getAttribute('keyBits') ?? '$keyBits');
        blockSize = int.parse(reader.getAttribute('blockSize') ?? '$blockSize');
        saltSize = int.parse(reader.getAttribute('saltSize') ?? '$saltSize');
        encSalt = Uint8List.fromList(
          base64.decode(reader.getAttribute('saltValue') ?? ''),
        );
        encVerifier = Uint8List.fromList(
          base64.decode(
            reader.getAttribute('encryptedVerifierHashInput') ?? '',
          ),
        );
        encVerifierHash = Uint8List.fromList(
          base64.decode(
            reader.getAttribute('encryptedVerifierHashValue') ?? '',
          ),
        );
        encKey = Uint8List.fromList(
          base64.decode(reader.getAttribute('encryptedKeyValue') ?? ''),
        );
      }
    }
    return _AgileParams(
      hashName: hashName,
      hashSize: hashSize,
      keyBits: keyBits,
      blockSize: blockSize,
      saltSize: saltSize,
      spinCount: spinCount,
      keyDataSalt: keySalt,
      encryptedSalt: encSalt,
      encryptedVerifierHashInput: encVerifier,
      encryptedVerifierHashValue: encVerifierHash,
      encryptedKeyValue: encKey,
      encryptedHmacKey: encHmacKey,
      encryptedHmacValue: encHmacValue,
    );
  }

  static String _infoXml({
    required Uint8List keySalt,
    required Uint8List encSalt,
    required int spinCount,
    required Uint8List encryptedVerifier,
    required Uint8List encryptedVerifierHash,
    required Uint8List encryptedKey,
    required Uint8List encryptedHmacKey,
    required Uint8List encryptedHmacValue,
  }) {
    String b64(Uint8List b) => base64.encode(b);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<encryption xmlns="http://schemas.microsoft.com/office/2006/encryption" '
        'xmlns:p="http://schemas.microsoft.com/office/2006/keyEncryptor/password">'
        '<keyData saltSize="16" blockSize="16" keyBits="256" hashSize="64" '
        'cipherAlgorithm="AES" cipherChaining="ChainingModeCBC" '
        'hashAlgorithm="SHA512" saltValue="${b64(keySalt)}"/>'
        '<dataIntegrity encryptedHmacKey="${b64(encryptedHmacKey)}" '
        'encryptedHmacValue="${b64(encryptedHmacValue)}"/>'
        '<keyEncryptors><keyEncryptor '
        'uri="http://schemas.microsoft.com/office/2006/keyEncryptor/password">'
        '<p:encryptedKey spinCount="$spinCount" saltSize="16" blockSize="16" '
        'keyBits="256" hashSize="64" cipherAlgorithm="AES" '
        'cipherChaining="ChainingModeCBC" hashAlgorithm="SHA512" '
        'saltValue="${b64(encSalt)}" '
        'encryptedVerifierHashInput="${b64(encryptedVerifier)}" '
        'encryptedVerifierHashValue="${b64(encryptedVerifierHash)}" '
        'encryptedKeyValue="${b64(encryptedKey)}"/>'
        '</keyEncryptor></keyEncryptors></encryption>';
  }
}

class _AgileParams {
  _AgileParams({
    required this.hashName,
    required this.hashSize,
    required this.keyBits,
    required this.blockSize,
    required this.saltSize,
    required this.spinCount,
    required this.keyDataSalt,
    required this.encryptedSalt,
    required this.encryptedVerifierHashInput,
    required this.encryptedVerifierHashValue,
    required this.encryptedKeyValue,
    required this.encryptedHmacKey,
    required this.encryptedHmacValue,
  });

  /// hashName API.
  final String hashName;

  /// hashSize API.
  final int hashSize;

  /// keyBits API.
  final int keyBits;

  /// blockSize API.
  final int blockSize;

  /// saltSize API.
  final int saltSize;

  /// spinCount API.
  final int spinCount;

  /// keyDataSalt API.
  final Uint8List keyDataSalt;

  /// encryptedSalt API.
  final Uint8List encryptedSalt;

  /// encryptedVerifierHashInput API.
  final Uint8List encryptedVerifierHashInput;

  /// encryptedVerifierHashValue API.
  final Uint8List encryptedVerifierHashValue;

  /// encryptedKeyValue API.
  final Uint8List encryptedKeyValue;

  /// encryptedHmacKey API.
  final Uint8List encryptedHmacKey;

  /// encryptedHmacValue API.
  final Uint8List encryptedHmacValue;

  /// keyBytes API.
  int get keyBytes => keyBits ~/ 8;
}

abstract final class _Standard {
  /// decrypt API.
  static Uint8List decrypt(Uint8List info, Uint8List pack, String password) {
    final ByteCursor c = ByteCursor(info);
    c.skip(4);
    final int flags = c.u32le();
    if ((flags & 0x0004) == 0 && info.length > 8) {
      // HeaderSize is next when fCryptoAPI
    }
    final int headerSize = c.u32le();
    final int headerStart = c.offset;
    c.u32le(); // flags again
    c.u32le(); // sizeExtra
    final int algId = c.u32le();
    c.u32le(); // algIdHash
    var keyBits = c.u32le();
    if (keyBits == 0) {
      keyBits = switch (algId) {
        0x660E => 128,
        0x660F => 192,
        0x6610 => 256,
        _ => 128,
      };
    }
    c.seek(headerStart + headerSize);
    final int saltSize = c.u32le();
    final Uint8List salt = c.bytes(saltSize);
    final Uint8List encVerifier = c.bytes(16);
    final int hashSize = c.u32le();
    final int encHashLen = ((hashSize + 15) ~/ 16) * 16;
    final Uint8List encHash = c.bytes(encHashLen.clamp(0, c.remaining));

    List<int> h = sha1
        .convert(_concat(<List<int>>[salt, _utf16le(password)]))
        .bytes;
    for (int i = 0; i < 50000; i++) {
      h = sha1.convert(_concat(<List<int>>[_u32(i), h])).bytes;
    }
    h = sha1.convert(_concat(<List<int>>[h, _u32(0)])).bytes;
    final Uint8List key = _fit(h, keyBits ~/ 8);
    final Uint8List iv = Uint8List(16);
    final Uint8List verifier = Aes.cbcDecrypt(
      key,
      iv,
      encVerifier,
      unpad: false,
    );
    final Uint8List hash = Aes.cbcDecrypt(key, iv, encHash, unpad: false);
    final List<int> expected = sha1.convert(verifier).bytes;
    if (!_equal(expected, hash.sublist(0, hashSize.clamp(0, hash.length)))) {
      throw const OfficePasswordException('Incorrect password');
    }
    if (pack.length < 8) {
      throw const OfficePasswordException('Truncated EncryptedPackage');
    }
    final int size = ByteCursor(pack).u64le();
    final Uint8List clear = Aes.cbcDecrypt(
      key,
      iv,
      Uint8List.sublistView(pack, 8),
      unpad: true,
    );
    return clear.length > size ? Uint8List.sublistView(clear, 0, size) : clear;
  }
}
