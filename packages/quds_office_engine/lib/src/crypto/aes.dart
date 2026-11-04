import 'dart:typed_data';

/// AES-128/192/256 (FIPS-197) with CBC and optional PKCS#7 padding.
class Aes {
  /// Aes API.
  Aes(Uint8List key) {
    final int kn = key.length;
    if (kn != 16 && kn != 24 && kn != 32) {
      throw ArgumentError('AES key must be 16, 24, or 32 bytes');
    }
    _nr = kn == 16 ? 10 : (kn == 24 ? 12 : 14);
    _enc = _expand(key, _nr);
    _dec = _invert(_enc, _nr);
  }

  late final int _nr;
  late final Uint32List _enc;
  late final Uint32List _dec;

  /// encryptBlock API.
  void encryptBlock(Uint8List src, int si, Uint8List dst, int di) {
    _crypt(src, si, dst, di, _enc, _nr, encrypt: true);
  }

  /// decryptBlock API.
  void decryptBlock(Uint8List src, int si, Uint8List dst, int di) {
    _crypt(src, si, dst, di, _dec, _nr, encrypt: false);
  }

  /// cbcEncrypt API.
  static Uint8List cbcEncrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List plain, {
    bool pad = true,
  }) {
    final Uint8List data = pad ? _pkcs7(plain, 16) : _align(plain, 16);
    final Aes aes = Aes(key);
    final Uint8List out = Uint8List(data.length);
    final Uint8List prev = Uint8List.fromList(iv);
    final Uint8List block = Uint8List(16);
    for (int i = 0; i < data.length; i += 16) {
      for (int j = 0; j < 16; j++) {
        block[j] = data[i + j] ^ prev[j];
      }
      aes.encryptBlock(block, 0, out, i);
      prev.setRange(0, 16, out, i);
    }
    return out;
  }

  /// cbcDecrypt API.
  static Uint8List cbcDecrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List cipher, {
    bool unpad = true,
    int? keep,
  }) {
    if (cipher.length % 16 != 0) {
      throw const FormatException('AES-CBC ciphertext is not block-aligned');
    }
    final Aes aes = Aes(key);
    final Uint8List out = Uint8List(cipher.length);
    final Uint8List prev = Uint8List.fromList(iv);
    final Uint8List block = Uint8List(16);
    for (int i = 0; i < cipher.length; i += 16) {
      aes.decryptBlock(cipher, i, block, 0);
      for (int j = 0; j < 16; j++) {
        out[i + j] = block[j] ^ prev[j];
      }
      prev.setRange(0, 16, cipher, i);
    }
    if (keep != null) {
      return Uint8List.sublistView(out, 0, keep);
    }
    return unpad ? _unpkcs7(out) : out;
  }

  static Uint8List _pkcs7(Uint8List data, int block) {
    final int pad = block - (data.length % block);
    final Uint8List out = Uint8List(data.length + pad);
    out.setRange(0, data.length, data);
    out.fillRange(data.length, out.length, pad);
    return out;
  }

  static Uint8List _align(Uint8List data, int block) {
    if (data.length % block == 0) {
      return data;
    }
    final int pad = block - (data.length % block);
    final Uint8List out = Uint8List(data.length + pad);
    out.setRange(0, data.length, data);
    return out;
  }

  static Uint8List _unpkcs7(Uint8List data) {
    if (data.isEmpty) {
      return data;
    }
    final int pad = data.last;
    if (pad <= 0 || pad > 16 || pad > data.length) {
      return data;
    }
    for (int i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) {
        return data;
      }
    }
    return Uint8List.sublistView(data, 0, data.length - pad);
  }

  static void _crypt(
    Uint8List src,
    int si,
    Uint8List dst,
    int di,
    Uint32List rk,
    int nr, {
    required bool encrypt,
  }) {
    var s0 = _u32(src, si) ^ rk[0];
    var s1 = _u32(src, si + 4) ^ rk[1];
    var s2 = _u32(src, si + 8) ^ rk[2];
    var s3 = _u32(src, si + 12) ^ rk[3];
    if (encrypt) {
      for (int r = 1; r < nr; r++) {
        final int t0 =
            _te0[s0 >> 24] ^
            _te1[(s1 >> 16) & 0xFF] ^
            _te2[(s2 >> 8) & 0xFF] ^
            _te3[s3 & 0xFF] ^
            rk[r * 4];
        final int t1 =
            _te0[s1 >> 24] ^
            _te1[(s2 >> 16) & 0xFF] ^
            _te2[(s3 >> 8) & 0xFF] ^
            _te3[s0 & 0xFF] ^
            rk[r * 4 + 1];
        final int t2 =
            _te0[s2 >> 24] ^
            _te1[(s3 >> 16) & 0xFF] ^
            _te2[(s0 >> 8) & 0xFF] ^
            _te3[s1 & 0xFF] ^
            rk[r * 4 + 2];
        final int t3 =
            _te0[s3 >> 24] ^
            _te1[(s0 >> 16) & 0xFF] ^
            _te2[(s1 >> 8) & 0xFF] ^
            _te3[s2 & 0xFF] ^
            rk[r * 4 + 3];
        s0 = t0 & 0xFFFFFFFF;
        s1 = t1 & 0xFFFFFFFF;
        s2 = t2 & 0xFFFFFFFF;
        s3 = t3 & 0xFFFFFFFF;
      }
      _store(dst, di, _finalEnc(s0, s1, s2, s3, rk, nr * 4));
    } else {
      for (int r = 1; r < nr; r++) {
        final int t0 =
            _td0[s0 >> 24] ^
            _td1[(s3 >> 16) & 0xFF] ^
            _td2[(s2 >> 8) & 0xFF] ^
            _td3[s1 & 0xFF] ^
            rk[r * 4];
        final int t1 =
            _td0[s1 >> 24] ^
            _td1[(s0 >> 16) & 0xFF] ^
            _td2[(s3 >> 8) & 0xFF] ^
            _td3[s2 & 0xFF] ^
            rk[r * 4 + 1];
        final int t2 =
            _td0[s2 >> 24] ^
            _td1[(s1 >> 16) & 0xFF] ^
            _td2[(s0 >> 8) & 0xFF] ^
            _td3[s3 & 0xFF] ^
            rk[r * 4 + 2];
        final int t3 =
            _td0[s3 >> 24] ^
            _td1[(s2 >> 16) & 0xFF] ^
            _td2[(s1 >> 8) & 0xFF] ^
            _td3[s0 & 0xFF] ^
            rk[r * 4 + 3];
        s0 = t0 & 0xFFFFFFFF;
        s1 = t1 & 0xFFFFFFFF;
        s2 = t2 & 0xFFFFFFFF;
        s3 = t3 & 0xFFFFFFFF;
      }
      _store(dst, di, _finalDec(s0, s1, s2, s3, rk, nr * 4));
    }
  }

  static List<int> _finalEnc(
    int s0,
    int s1,
    int s2,
    int s3,
    Uint32List rk,
    int o,
  ) {
    return <int>[
      (((_sbox[s0 >> 24] << 24) |
                  (_sbox[(s1 >> 16) & 0xFF] << 16) |
                  (_sbox[(s2 >> 8) & 0xFF] << 8) |
                  _sbox[s3 & 0xFF]) ^
              rk[o]) &
          0xFFFFFFFF,
      (((_sbox[s1 >> 24] << 24) |
                  (_sbox[(s2 >> 16) & 0xFF] << 16) |
                  (_sbox[(s3 >> 8) & 0xFF] << 8) |
                  _sbox[s0 & 0xFF]) ^
              rk[o + 1]) &
          0xFFFFFFFF,
      (((_sbox[s2 >> 24] << 24) |
                  (_sbox[(s3 >> 16) & 0xFF] << 16) |
                  (_sbox[(s0 >> 8) & 0xFF] << 8) |
                  _sbox[s1 & 0xFF]) ^
              rk[o + 2]) &
          0xFFFFFFFF,
      (((_sbox[s3 >> 24] << 24) |
                  (_sbox[(s0 >> 16) & 0xFF] << 16) |
                  (_sbox[(s1 >> 8) & 0xFF] << 8) |
                  _sbox[s2 & 0xFF]) ^
              rk[o + 3]) &
          0xFFFFFFFF,
    ];
  }

  static List<int> _finalDec(
    int s0,
    int s1,
    int s2,
    int s3,
    Uint32List rk,
    int o,
  ) {
    return <int>[
      (((_invS[s0 >> 24] << 24) |
                  (_invS[(s3 >> 16) & 0xFF] << 16) |
                  (_invS[(s2 >> 8) & 0xFF] << 8) |
                  _invS[s1 & 0xFF]) ^
              rk[o]) &
          0xFFFFFFFF,
      (((_invS[s1 >> 24] << 24) |
                  (_invS[(s0 >> 16) & 0xFF] << 16) |
                  (_invS[(s3 >> 8) & 0xFF] << 8) |
                  _invS[s2 & 0xFF]) ^
              rk[o + 1]) &
          0xFFFFFFFF,
      (((_invS[s2 >> 24] << 24) |
                  (_invS[(s1 >> 16) & 0xFF] << 16) |
                  (_invS[(s0 >> 8) & 0xFF] << 8) |
                  _invS[s3 & 0xFF]) ^
              rk[o + 2]) &
          0xFFFFFFFF,
      (((_invS[s3 >> 24] << 24) |
                  (_invS[(s2 >> 16) & 0xFF] << 16) |
                  (_invS[(s1 >> 8) & 0xFF] << 8) |
                  _invS[s0 & 0xFF]) ^
              rk[o + 3]) &
          0xFFFFFFFF,
    ];
  }

  static void _store(Uint8List dst, int di, List<int> w) {
    for (int i = 0; i < 4; i++) {
      dst[di + i * 4] = (w[i] >> 24) & 0xFF;
      dst[di + i * 4 + 1] = (w[i] >> 16) & 0xFF;
      dst[di + i * 4 + 2] = (w[i] >> 8) & 0xFF;
      dst[di + i * 4 + 3] = w[i] & 0xFF;
    }
  }

  static int _u32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  static Uint32List _expand(Uint8List key, int nr) {
    final int nk = key.length ~/ 4;
    final int n = 4 * (nr + 1);
    final Uint32List w = Uint32List(n);
    for (int i = 0; i < nk; i++) {
      w[i] = _u32(key, i * 4);
    }
    for (int i = nk; i < n; i++) {
      var t = w[i - 1];
      if (i % nk == 0) {
        t = _subWord(_rot(t)) ^ _rcon[i ~/ nk];
      } else if (nk > 6 && i % nk == 4) {
        t = _subWord(t);
      }
      w[i] = w[i - nk] ^ t;
    }
    return w;
  }

  static Uint32List _invert(Uint32List enc, int nr) {
    final int n = 4 * (nr + 1);
    final Uint32List dec = Uint32List(n);
    for (int i = 0; i < n; i += 4) {
      final int j = n - 4 - i;
      if (i == 0 || i == n - 4) {
        dec[i] = enc[j];
        dec[i + 1] = enc[j + 1];
        dec[i + 2] = enc[j + 2];
        dec[i + 3] = enc[j + 3];
      } else {
        for (int k = 0; k < 4; k++) {
          final int e = enc[j + k];
          dec[i + k] =
              _td0[_sbox[e >> 24]] ^
              _td1[_sbox[(e >> 16) & 0xFF]] ^
              _td2[_sbox[(e >> 8) & 0xFF]] ^
              _td3[_sbox[e & 0xFF]];
        }
      }
    }
    return dec;
  }

  static int _rot(int w) => ((w << 8) | ((w >> 24) & 0xFF)) & 0xFFFFFFFF;

  static int _subWord(int w) =>
      (_sbox[w >> 24] << 24) |
      (_sbox[(w >> 16) & 0xFF] << 16) |
      (_sbox[(w >> 8) & 0xFF] << 8) |
      _sbox[w & 0xFF];
}

const List<int> _sbox = <int>[
  0x63,
  0x7c,
  0x77,
  0x7b,
  0xf2,
  0x6b,
  0x6f,
  0xc5,
  0x30,
  0x01,
  0x67,
  0x2b,
  0xfe,
  0xd7,
  0xab,
  0x76,
  0xca,
  0x82,
  0xc9,
  0x7d,
  0xfa,
  0x59,
  0x47,
  0xf0,
  0xad,
  0xd4,
  0xa2,
  0xaf,
  0x9c,
  0xa4,
  0x72,
  0xc0,
  0xb7,
  0xfd,
  0x93,
  0x26,
  0x36,
  0x3f,
  0xf7,
  0xcc,
  0x34,
  0xa5,
  0xe5,
  0xf1,
  0x71,
  0xd8,
  0x31,
  0x15,
  0x04,
  0xc7,
  0x23,
  0xc3,
  0x18,
  0x96,
  0x05,
  0x9a,
  0x07,
  0x12,
  0x80,
  0xe2,
  0xeb,
  0x27,
  0xb2,
  0x75,
  0x09,
  0x83,
  0x2c,
  0x1a,
  0x1b,
  0x6e,
  0x5a,
  0xa0,
  0x52,
  0x3b,
  0xd6,
  0xb3,
  0x29,
  0xe3,
  0x2f,
  0x84,
  0x53,
  0xd1,
  0x00,
  0xed,
  0x20,
  0xfc,
  0xb1,
  0x5b,
  0x6a,
  0xcb,
  0xbe,
  0x39,
  0x4a,
  0x4c,
  0x58,
  0xcf,
  0xd0,
  0xef,
  0xaa,
  0xfb,
  0x43,
  0x4d,
  0x33,
  0x85,
  0x45,
  0xf9,
  0x02,
  0x7f,
  0x50,
  0x3c,
  0x9f,
  0xa8,
  0x51,
  0xa3,
  0x40,
  0x8f,
  0x92,
  0x9d,
  0x38,
  0xf5,
  0xbc,
  0xb6,
  0xda,
  0x21,
  0x10,
  0xff,
  0xf3,
  0xd2,
  0xcd,
  0x0c,
  0x13,
  0xec,
  0x5f,
  0x97,
  0x44,
  0x17,
  0xc4,
  0xa7,
  0x7e,
  0x3d,
  0x64,
  0x5d,
  0x19,
  0x73,
  0x60,
  0x81,
  0x4f,
  0xdc,
  0x22,
  0x2a,
  0x90,
  0x88,
  0x46,
  0xee,
  0xb8,
  0x14,
  0xde,
  0x5e,
  0x0b,
  0xdb,
  0xe0,
  0x32,
  0x3a,
  0x0a,
  0x49,
  0x06,
  0x24,
  0x5c,
  0xc2,
  0xd3,
  0xac,
  0x62,
  0x91,
  0x95,
  0xe4,
  0x79,
  0xe7,
  0xc8,
  0x37,
  0x6d,
  0x8d,
  0xd5,
  0x4e,
  0xa9,
  0x6c,
  0x56,
  0xf4,
  0xea,
  0x65,
  0x7a,
  0xae,
  0x08,
  0xba,
  0x78,
  0x25,
  0x2e,
  0x1c,
  0xa6,
  0xb4,
  0xc6,
  0xe8,
  0xdd,
  0x74,
  0x1f,
  0x4b,
  0xbd,
  0x8b,
  0x8a,
  0x70,
  0x3e,
  0xb5,
  0x66,
  0x48,
  0x03,
  0xf6,
  0x0e,
  0x61,
  0x35,
  0x57,
  0xb9,
  0x86,
  0xc1,
  0x1d,
  0x9e,
  0xe1,
  0xf8,
  0x98,
  0x11,
  0x69,
  0xd9,
  0x8e,
  0x94,
  0x9b,
  0x1e,
  0x87,
  0xe9,
  0xce,
  0x55,
  0x28,
  0xdf,
  0x8c,
  0xa1,
  0x89,
  0x0d,
  0xbf,
  0xe6,
  0x42,
  0x68,
  0x41,
  0x99,
  0x2d,
  0x0f,
  0xb0,
  0x54,
  0xbb,
  0x16,
];

const List<int> _invS = <int>[
  0x52,
  0x09,
  0x6a,
  0xd5,
  0x30,
  0x36,
  0xa5,
  0x38,
  0xbf,
  0x40,
  0xa3,
  0x9e,
  0x81,
  0xf3,
  0xd7,
  0xfb,
  0x7c,
  0xe3,
  0x39,
  0x82,
  0x9b,
  0x2f,
  0xff,
  0x87,
  0x34,
  0x8e,
  0x43,
  0x44,
  0xc4,
  0xde,
  0xe9,
  0xcb,
  0x54,
  0x7b,
  0x94,
  0x32,
  0xa6,
  0xc2,
  0x23,
  0x3d,
  0xee,
  0x4c,
  0x95,
  0x0b,
  0x42,
  0xfa,
  0xc3,
  0x4e,
  0x08,
  0x2e,
  0xa1,
  0x66,
  0x28,
  0xd9,
  0x24,
  0xb2,
  0x76,
  0x5b,
  0xa2,
  0x49,
  0x6d,
  0x8b,
  0xd1,
  0x25,
  0x72,
  0xf8,
  0xf6,
  0x64,
  0x86,
  0x68,
  0x98,
  0x16,
  0xd4,
  0xa4,
  0x5c,
  0xcc,
  0x5d,
  0x65,
  0xb6,
  0x92,
  0x6c,
  0x70,
  0x48,
  0x50,
  0xfd,
  0xed,
  0xb9,
  0xda,
  0x5e,
  0x15,
  0x46,
  0x57,
  0xa7,
  0x8d,
  0x9d,
  0x84,
  0x90,
  0xd8,
  0xab,
  0x00,
  0x8c,
  0xbc,
  0xd3,
  0x0a,
  0xf7,
  0xe4,
  0x58,
  0x05,
  0xb8,
  0xb3,
  0x45,
  0x06,
  0xd0,
  0x2c,
  0x1e,
  0x8f,
  0xca,
  0x3f,
  0x0f,
  0x02,
  0xc1,
  0xaf,
  0xbd,
  0x03,
  0x01,
  0x13,
  0x8a,
  0x6b,
  0x3a,
  0x91,
  0x11,
  0x41,
  0x4f,
  0x67,
  0xdc,
  0xea,
  0x97,
  0xf2,
  0xcf,
  0xce,
  0xf0,
  0xb4,
  0xe6,
  0x73,
  0x96,
  0xac,
  0x74,
  0x22,
  0xe7,
  0xad,
  0x35,
  0x85,
  0xe2,
  0xf9,
  0x37,
  0xe8,
  0x1c,
  0x75,
  0xdf,
  0x6e,
  0x47,
  0xf1,
  0x1a,
  0x71,
  0x1d,
  0x29,
  0xc5,
  0x89,
  0x6f,
  0xb7,
  0x62,
  0x0e,
  0xaa,
  0x18,
  0xbe,
  0x1b,
  0xfc,
  0x56,
  0x3e,
  0x4b,
  0xc6,
  0xd2,
  0x79,
  0x20,
  0x9a,
  0xdb,
  0xc0,
  0xfe,
  0x78,
  0xcd,
  0x5a,
  0xf4,
  0x1f,
  0xdd,
  0xa8,
  0x33,
  0x88,
  0x07,
  0xc7,
  0x31,
  0xb1,
  0x12,
  0x10,
  0x59,
  0x27,
  0x80,
  0xec,
  0x5f,
  0x60,
  0x51,
  0x7f,
  0xa9,
  0x19,
  0xb5,
  0x4a,
  0x0d,
  0x2d,
  0xe5,
  0x7a,
  0x9f,
  0x93,
  0xc9,
  0x9c,
  0xef,
  0xa0,
  0xe0,
  0x3b,
  0x4d,
  0xae,
  0x2a,
  0xf5,
  0xb0,
  0xc8,
  0xeb,
  0xbb,
  0x3c,
  0x83,
  0x53,
  0x99,
  0x61,
  0x17,
  0x2b,
  0x04,
  0x7e,
  0xba,
  0x77,
  0xd6,
  0x26,
  0xe1,
  0x69,
  0x14,
  0x63,
  0x55,
  0x21,
  0x0c,
  0x7d,
];

const List<int> _rcon = <int>[
  0x00000000,
  0x01000000,
  0x02000000,
  0x04000000,
  0x08000000,
  0x10000000,
  0x20000000,
  0x40000000,
  0x80000000,
  0x1b000000,
  0x36000000,
];

final Uint32List _te0 = _buildTe(0);
final Uint32List _te1 = _buildTe(8);
final Uint32List _te2 = _buildTe(16);
final Uint32List _te3 = _buildTe(24);
final Uint32List _td0 = _buildTd(0);
final Uint32List _td1 = _buildTd(8);
final Uint32List _td2 = _buildTd(16);
final Uint32List _td3 = _buildTd(24);

Uint32List _buildTe(int rot) {
  /// t API.
  final Uint32List t = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    final int s = _sbox[i];
    final int v = (_xt(s, 2) << 24) | (s << 16) | (s << 8) | _xt(s, 3);
    t[i] = _rotr(v, rot);
  }
  return t;
}

Uint32List _buildTd(int rot) {
  /// t API.
  final Uint32List t = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    final int s = _invS[i];
    final int v =
        (_xt(s, 0xe) << 24) |
        (_xt(s, 0x9) << 16) |
        (_xt(s, 0xd) << 8) |
        _xt(s, 0xb);
    t[i] = _rotr(v, rot);
  }
  return t;
}

int _xt(int a, int b) {
  /// p API.
  var p = 0;

  /// x API.
  var x = a;

  /// y API.
  var y = b;
  for (int i = 0; i < 8; i++) {
    if ((y & 1) != 0) {
      p ^= x;
    }
    final bool hi = (x & 0x80) != 0;
    x = (x << 1) & 0xFF;
    if (hi) {
      x ^= 0x1b;
    }
    y >>= 1;
  }
  return p;
}

int _rotr(int v, int n) {
  if (n == 0) {
    return v;
  }
  return ((v >> n) | (v << (32 - n))) & 0xFFFFFFFF;
}
