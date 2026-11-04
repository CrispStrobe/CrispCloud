import 'dart:typed_data';

/// RC4 (ARC4) used by the PDF Standard security handler (Rev 2–3).
abstract final class PdfRc4 {
  /// crypt API.
  static Uint8List crypt(Uint8List key, Uint8List data) {
    final Uint8List s = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      s[i] = i;
    }
    var j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final int t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final Uint8List out = Uint8List(data.length);
    var x = 0;
    var y = 0;
    for (int n = 0; n < data.length; n++) {
      x = (x + 1) & 0xFF;
      y = (y + s[x]) & 0xFF;
      final int t = s[x];
      s[x] = s[y];
      s[y] = t;
      out[n] = data[n] ^ s[(s[x] + s[y]) & 0xFF];
    }
    return out;
  }
}
