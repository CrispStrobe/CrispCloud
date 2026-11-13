/// Decode one already-parsed CSS font-family string into plain text.
///
/// The result is used only as a Flutter TextStyle family, never reinserted into
/// HTML or CSS. This preserves the parser's injection-safe serialization while
/// compensating for csslib's literal hexadecimal escapes. Bounds match the
/// native Office model's 256-character font names.
String? decodeOfficeCssFont(String value) {
  if (value.isEmpty || value.length > 2048) return null;
  final result = StringBuffer();
  var index = 0;
  while (index < value.length) {
    var code = value.codeUnitAt(index++);
    if (code == 0x5c) {
      if (index == value.length) return null;
      code = value.codeUnitAt(index);
      if (code == 0x0a || code == 0x0d || code == 0x0c) {
        index++;
        if (code == 0x0d &&
            index < value.length &&
            value.codeUnitAt(index) == 0x0a) {
          index++;
        }
        continue;
      }
      var scalar = 0;
      var digits = 0;
      while (index < value.length && digits < 6) {
        final next = value.codeUnitAt(index);
        final digit = next >= 48 && next <= 57
            ? next - 48
            : next >= 65 && next <= 70
            ? next - 55
            : next >= 97 && next <= 102
            ? next - 87
            : -1;
        if (digit < 0) break;
        scalar = scalar * 16 + digit;
        digits++;
        index++;
      }
      if (digits > 0) {
        if (scalar == 0 ||
            scalar > 0x10ffff ||
            (scalar >= 0xd800 && scalar <= 0xdfff)) {
          return null;
        }
        code = scalar;
        if (index < value.length) {
          final next = value.codeUnitAt(index);
          if (next == 32 ||
              next == 9 ||
              next == 10 ||
              next == 12 ||
              next == 13) {
            index++;
            if (next == 13 &&
                index < value.length &&
                value.codeUnitAt(index) == 10) {
              index++;
            }
          }
        }
      } else {
        index++;
      }
    }
    if (code < 32 || code == 127) return null;
    result.writeCharCode(code);
    if (result.length > 256) return null;
  }
  final decoded = result.toString().trim();
  return decoded.isEmpty ? null : decoded;
}
