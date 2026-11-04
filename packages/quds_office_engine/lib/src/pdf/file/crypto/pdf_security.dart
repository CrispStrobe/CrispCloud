import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../crypto/aes.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';
import 'pdf_rc4.dart';

/// ISO 32000-1 §7.6 Standard security handler (Rev 2–4, plus Rev 5/6 AES-256).
class PdfSecurity {
  /// PdfSecurity API.
  PdfSecurity._({
    required this.revision,
    required this.key,
    required this.permissions,
    required this.encryptMetadata,
    required this.aes,
    required this.filter,
  });

  /// revision API.
  final int revision;

  /// File encryption key.
  final Uint8List key;

  /// /P permission bits.
  final int permissions;

  /// encryptMetadata API.
  final bool encryptMetadata;

  /// True when strings/streams use AES (Rev 4+).
  final bool aes;

  /// Security handler name.
  final String filter;

  /// canPrint API.
  bool get canPrint => permissions & 4 != 0;

  /// canModify API.
  bool get canModify => permissions & 8 != 0;

  /// canCopy API.
  bool get canCopy => permissions & 16 != 0;

  /// canAnnotate API.
  bool get canAnnotate => permissions & 32 != 0;

  /// None when the trailer has no /Encrypt.
  static PdfSecurity? open(
    PdfCosDict encrypt,
    PdfCos? id0, {
    String? password,
  }) {
    final String filter = pdfCosName(encrypt['Filter']) ?? '';
    if (filter.isNotEmpty && filter != 'Standard') {
      throw const PdfOpenException(PdfOpenError.unsupportedHandler);
    }
    final int rev = pdfCosInt(encrypt['R']) ?? 2;
    if (rev >= 5) {
      return _openAes256(encrypt, password: password, filter: filter);
    }
    if (password == null) {
      try {
        return _openLegacy(encrypt, id0, '');
      } on PdfOpenException {
        throw const PdfOpenException(PdfOpenError.encrypted);
      }
    }
    return _openLegacy(encrypt, id0, password);
  }

  static PdfSecurity _openLegacy(
    PdfCosDict encrypt,
    PdfCos? id0,
    String password,
  ) {
    final int rev = pdfCosInt(encrypt['R']) ?? 2;
    final int lengthBits = pdfCosInt(encrypt['Length']) ?? 40;
    final int keyLen = (lengthBits / 8).round().clamp(5, 16);
    final Uint8List o = _stringBytes(encrypt['O']);
    final Uint8List u = _stringBytes(encrypt['U']);
    final int p = pdfCosInt(encrypt['P']) ?? -1;
    final bool encryptMetadata = encrypt['EncryptMetadata'] is! PdfCosBool
        ? true
        : (encrypt['EncryptMetadata'] as PdfCosBool).value;
    final Uint8List id = id0 is PdfCosString ? id0.bytes : Uint8List(0);
    final Uint8List key = _fileKey(
      password,
      o,
      p,
      id,
      keyLen,
      rev,
      encryptMetadata,
    );
    if (!_userOk(key, u, id, rev)) {
      throw const PdfOpenException(PdfOpenError.wrongPassword);
    }
    final String cfm = _cfm(encrypt);
    return PdfSecurity._(
      revision: rev,
      key: key,
      permissions: p,
      encryptMetadata: encryptMetadata,
      aes: cfm == 'AESV2' || cfm == 'AESV3',
      filter: 'Standard',
    );
  }

  static PdfSecurity _openAes256(
    PdfCosDict encrypt, {
    String? password,
    required String filter,
  }) {
    final String pass = password ?? '';
    final Uint8List u = _stringBytes(encrypt['U']);
    final Uint8List ue = _stringBytes(encrypt['UE']);
    final Uint8List o = _stringBytes(encrypt['O']);
    final Uint8List oe = _stringBytes(encrypt['OE']);
    if (u.length < 48 || o.length < 48) {
      throw const PdfOpenException(PdfOpenError.unsupportedHandler);
    }
    final Uint8List passUtf = Uint8List.fromList(utf8.encode(pass));
    final Uint8List? key = _tryRev56(passUtf, u, ue) ?? _tryRev56(passUtf, o, oe);
    if (key == null) {
      if (password == null) {
        throw const PdfOpenException(PdfOpenError.encrypted);
      }
      throw const PdfOpenException(PdfOpenError.wrongPassword);
    }
    return PdfSecurity._(
      revision: pdfCosInt(encrypt['R']) ?? 6,
      key: key,
      permissions: pdfCosInt(encrypt['P']) ?? -1,
      encryptMetadata: true,
      aes: true,
      filter: filter.isEmpty ? 'Standard' : filter,
    );
  }

  static Uint8List? _tryRev56(Uint8List password, Uint8List uOrO, Uint8List ueOrOe) {
    if (ueOrOe.length < 32) {
      return null;
    }
    final Uint8List salt = uOrO.sublist(32, 40);
    final Uint8List hash = Uint8List.fromList(sha256.convert(<int>[...password, ...salt]).bytes);
    final Uint8List check = uOrO.sublist(0, 32);
    var ok = true;
    for (int i = 0; i < 32; i++) {
      if (hash[i] != check[i]) {
        ok = false;
        break;
      }
    }
    if (!ok) {
      return null;
    }
    final Uint8List keySalt = uOrO.sublist(40, 48);
    final Uint8List wrapKey = Uint8List.fromList(
      sha256.convert(<int>[...password, ...keySalt]).bytes,
    );
    return Aes.cbcDecrypt(wrapKey, Uint8List(16), ueOrOe, unpad: false).sublist(0, 32);
  }

  /// Decrypts a string or stream for [id]/[gen].
  Uint8List decrypt(Uint8List data, int id, int gen) {
    if (revision >= 5) {
      if (data.length < 16) {
        return data;
      }
      final Uint8List iv = data.sublist(0, 16);
      return Aes.cbcDecrypt(key, iv, data.sublist(16));
    }
    final Uint8List objKey = _objectKey(id, gen);
    if (aes) {
      if (data.length < 16) {
        return data;
      }
      final Uint8List iv = data.sublist(0, 16);
      return Aes.cbcDecrypt(objKey, iv, data.sublist(16));
    }
    return PdfRc4.crypt(objKey, data);
  }

  Uint8List _objectKey(int id, int gen) {
    final int extra = aes ? 4 : 0;
    final Uint8List buf = Uint8List(key.length + 5 + extra);
    buf.setAll(0, key);
    buf[key.length] = id & 0xFF;
    buf[key.length + 1] = (id >> 8) & 0xFF;
    buf[key.length + 2] = (id >> 16) & 0xFF;
    buf[key.length + 3] = gen & 0xFF;
    buf[key.length + 4] = (gen >> 8) & 0xFF;
    if (aes) {
      buf[key.length + 5] = 0x73;
      buf[key.length + 6] = 0x41;
      buf[key.length + 7] = 0x6C;
      buf[key.length + 8] = 0x54;
    }
    final Uint8List md = Uint8List.fromList(md5.convert(buf).bytes);
    final int n = (key.length + 5).clamp(0, 16);
    return md.sublist(0, n);
  }

  static const List<int> _pad = <int>[
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  static Uint8List _padPassword(String password) {
    final Uint8List raw = Uint8List.fromList(latin1.encode(password));
    final Uint8List out = Uint8List(32);
    final int n = raw.length < 32 ? raw.length : 32;
    out.setRange(0, n, raw);
    if (n < 32) {
      out.setRange(n, 32, _pad);
    }
    return out;
  }

  static Uint8List _fileKey(
    String password,
    Uint8List o,
    int p,
    Uint8List id,
    int keyLen,
    int rev,
    bool encryptMetadata,
  ) {
    final BytesBuilder buf = BytesBuilder(copy: false)
      ..add(_padPassword(password))
      ..add(o.length >= 32 ? o.sublist(0, 32) : o)
      ..addByte(p & 0xFF)
      ..addByte((p >> 8) & 0xFF)
      ..addByte((p >> 16) & 0xFF)
      ..addByte((p >> 24) & 0xFF)
      ..add(id);
    if (rev >= 4 && !encryptMetadata) {
      buf.add(<int>[0xFF, 0xFF, 0xFF, 0xFF]);
    }
    var hash = md5.convert(buf.takeBytes()).bytes;
    if (rev >= 3) {
      for (int i = 0; i < 50; i++) {
        hash = md5.convert(hash.sublist(0, keyLen)).bytes;
      }
    }
    return Uint8List.fromList(hash.sublist(0, keyLen));
  }

  static bool _userOk(Uint8List key, Uint8List u, Uint8List id, int rev) {
    if (rev == 2) {
      final Uint8List check = PdfRc4.crypt(key, Uint8List.fromList(_pad));
      return _prefixEq(check, u, 32);
    }
    final BytesBuilder buf = BytesBuilder(copy: false)
      ..add(_pad)
      ..add(id);
    final hash = Uint8List.fromList(md5.convert(buf.takeBytes()).bytes);
    var out = PdfRc4.crypt(key, hash);
    for (int i = 1; i <= 19; i++) {
      final Uint8List xorKey = Uint8List.fromList(<int>[
        for (final int b in key) b ^ i,
      ]);
      out = PdfRc4.crypt(xorKey, out);
    }
    return _prefixEq(out, u, 16);
  }

  static bool _prefixEq(Uint8List a, Uint8List b, int n) {
    if (a.length < n || b.length < n) {
      return false;
    }
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static Uint8List _stringBytes(PdfCos? value) {
    return value is PdfCosString ? value.bytes : Uint8List(0);
  }

  static String _cfm(PdfCosDict encrypt) {
    final PdfCos? stm = encrypt['StmF'] ?? encrypt['StrF'];
    final String name = pdfCosName(stm) ?? 'StdCF';
    final PdfCos? cf = encrypt['CF'];
    if (cf is PdfCosDict) {
      final PdfCos? entry = cf[name];
      if (entry is PdfCosDict) {
        return pdfCosName(entry['CFM']) ?? 'V2';
      }
    }
    return 'V2';
  }
}
