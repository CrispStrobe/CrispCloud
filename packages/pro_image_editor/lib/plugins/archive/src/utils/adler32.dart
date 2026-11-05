// ignore_for_file: public_member_api_docs

import 'input_stream.dart';

int getAdler32Stream(InputStream stream, [int adler = 1]) {
  // largest prime smaller than 65536
  const base = 65521;

  var s1 = adler & 0xffff;
  var s2 = adler >> 16;
  var len = stream.length;
  while (len > 0) {
    var n = 3800;
    if (n > len) {
      n = len;
    }
    len -= n;
    while (--n >= 0) {
      s1 = s1 + stream.readByte();
      s2 = s2 + s1;
    }
    s1 %= base;
    s2 %= base;
  }

  return (s2 << 16) | s1;
}
