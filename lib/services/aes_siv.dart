import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-SIV as specified in RFC 5297, sections 2.4–2.7.
///
/// The two equal-sized keys are separate to match Cryptomator's master keys:
/// [macKey] is RFC 5297's first key half (CMAC/S2V) and [encKey] is the second
/// half (CTR). Associated-data strings remain separate S2V inputs. The result
/// is the 16-byte synthetic IV followed by the ciphertext.
///
/// CMAC follows NIST SP 800-38B using PointyCastle's AES block/CBC primitives;
/// CTR also uses PointyCastle. The CBC IV is always one 16-byte AES block,
/// independent of key size.
/// RFC 5297 appendix A vectors are in test/aes_siv_test.dart.
class AesSiv {
  static Uint8List encrypt(
    Uint8List plaintext,
    Uint8List encKey,
    Uint8List macKey, {
    List<Uint8List> associatedData = const [],
  }) {
    _validate(encKey, macKey, associatedData);
    final siv = _s2v(plaintext, macKey, associatedData);
    final ciphertext = _ctr(plaintext, encKey, siv);
    return Uint8List(16 + ciphertext.length)
      ..setRange(0, 16, siv)
      ..setRange(16, 16 + ciphertext.length, ciphertext);
  }

  static Uint8List decrypt(
    Uint8List encrypted,
    Uint8List encKey,
    Uint8List macKey, {
    List<Uint8List> associatedData = const [],
  }) {
    _validate(encKey, macKey, associatedData);
    if (encrypted.length < 16) {
      throw const FormatException('AES-SIV ciphertext is too short');
    }
    final siv = encrypted.sublist(0, 16);
    final plaintext = _ctr(encrypted.sublist(16), encKey, siv);
    final expected = _s2v(plaintext, macKey, associatedData);
    var difference = 0;
    for (var i = 0; i < 16; i++) {
      difference |= siv[i] ^ expected[i];
    }
    if (difference != 0) {
      plaintext.fillRange(0, plaintext.length, 0);
      throw const FormatException('AES-SIV authentication failed');
    }
    return plaintext;
  }

  static void _validate(
    Uint8List encKey,
    Uint8List macKey,
    List<Uint8List> associatedData,
  ) {
    if (encKey.length != macKey.length ||
        !const [16, 24, 32].contains(encKey.length)) {
      throw ArgumentError('AES-SIV requires two equal 16, 24 or 32 byte keys');
    }
    // RFC 5297 section 7: at most 127 S2V inputs, including the plaintext.
    if (associatedData.length > 126) {
      throw ArgumentError(
        'AES-SIV accepts at most 126 associated-data strings',
      );
    }
  }

  static Uint8List _cmac(Uint8List key, Uint8List input) {
    // PointyCastle 4.0.0 CMac.init incorrectly sizes its CBC IV using the key
    // length, rejecting AES-192/256. Its API cannot accept an explicit IV.
    // Use SP 800-38B sections 6.1–6.2 directly with a block-sized zero IV.
    final aes = AESEngine()..init(true, KeyParameter(key));
    final l = Uint8List(16);
    aes.processBlock(Uint8List(16), 0, l, 0);
    final k1 = _double(l);
    final complete = input.isNotEmpty && input.length % 16 == 0;
    final lastOffset = complete
        ? input.length - 16
        : input.length - input.length % 16;
    final last = Uint8List(16);
    final tailLength = input.length - lastOffset;
    last.setRange(0, tailLength, input, lastOffset);
    if (!complete) {
      last[tailLength] = 0x80;
    }
    final subkey = complete ? k1 : _double(k1);
    for (var i = 0; i < 16; i++) {
      last[i] ^= subkey[i];
    }
    final cbc = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), Uint8List(16)));
    final tag = Uint8List(16);
    for (var offset = 0; offset < lastOffset; offset += 16) {
      cbc.processBlock(input, offset, tag, 0);
    }
    cbc.processBlock(last, 0, tag, 0);
    return tag;
  }

  static Uint8List _s2v(
    Uint8List plaintext,
    Uint8List macKey,
    List<Uint8List> associatedData,
  ) {
    var d = _cmac(macKey, Uint8List(16));
    for (final ad in associatedData) {
      final adMac = _cmac(macKey, ad);
      d = _double(d);
      for (var i = 0; i < 16; i++) {
        d[i] ^= adMac[i];
      }
    }

    final Uint8List finalInput;
    if (plaintext.length >= 16) {
      finalInput = Uint8List.fromList(plaintext);
      final offset = plaintext.length - 16;
      for (var i = 0; i < 16; i++) {
        finalInput[offset + i] ^= d[i];
      }
    } else {
      finalInput = _double(d);
      for (var i = 0; i < plaintext.length; i++) {
        finalInput[i] ^= plaintext[i];
      }
      finalInput[plaintext.length] ^= 0x80;
    }
    return _cmac(macKey, finalInput);
  }

  static Uint8List _double(Uint8List input) {
    final result = Uint8List(16);
    var carry = 0;
    for (var i = 15; i >= 0; i--) {
      result[i] = ((input[i] << 1) | carry) & 0xff;
      carry = input[i] >> 7;
    }
    result[15] ^= 0x87 & -carry;
    return result;
  }

  static Uint8List _ctr(Uint8List input, Uint8List key, Uint8List siv) {
    final counter = Uint8List.fromList(siv);
    // Clear bits 63 and 31 as required by RFC 5297 section 2.5. Do not
    // modify the authenticated SIV that is included in the output.
    counter[8] &= 0x7f;
    counter[12] &= 0x7f;
    final cipher = StreamCipher('AES/CTR')
      ..init(true, ParametersWithIV(KeyParameter(key), counter));
    return cipher.process(input);
  }
}
