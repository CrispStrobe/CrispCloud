import 'dart:convert';
import 'dart:typed_data';

/// Decodes a PDF text string after its literal/hex syntax has been removed.
///
/// ISO 32000-1:2008 §7.9.2.2 and Annex D, Table D.2 define PDFDocEncoding and
/// BOM-prefixed UTF-16BE:
/// https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
/// PDF 2.0 also defines UTF-8 text strings beginning with EF BB BF:
/// https://pdfa.org/understanding-utf-8-in-pdf-2-0/
///
/// Recovery is deliberately the same for COS metadata and inline ActualText:
/// unassigned PDFDocEncoding bytes 7F, 9F and AD, unpaired UTF-16 surrogates,
/// an odd trailing UTF-16 byte, and malformed UTF-8 produce U+FFFD. Existing
/// handling of C0 bytes 00–17 is retained, including controls that Annex D marks
/// undefined. Only a complete leading BOM selects a Unicode encoding; otherwise
/// bytes use PDFDocEncoding. UTF-16LE and BOM-less UTF-8 are not guessed.
///
/// This is not the decoder for font character codes in Tj/TJ operands. It does
/// not interpret Unicode language escape sequences or modify the input bytes.
String pdfDecodeTextString(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return _utf16be(bytes);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    // The UTF-8 decoder consumes the first BOM and preserves any later BOM.
    return utf8.decode(bytes, allowMalformed: true);
  }
  return String.fromCharCodes(bytes.map(_pdfDocCodePoint));
}

String _utf16be(Uint8List bytes) {
  final out = StringBuffer();
  for (var i = 2; i < bytes.length; i += 2) {
    if (i + 1 >= bytes.length) {
      out.writeCharCode(0xfffd);
      break;
    }
    final unit = (bytes[i] << 8) | bytes[i + 1];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 3 < bytes.length) {
        final next = (bytes[i + 2] << 8) | bytes[i + 3];
        if (next >= 0xdc00 && next <= 0xdfff) {
          out.writeCharCode(0x10000 + ((unit - 0xd800) << 10) + next - 0xdc00);
          i += 2;
          continue;
        }
      }
      out.writeCharCode(0xfffd);
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      out.writeCharCode(0xfffd);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

int _pdfDocCodePoint(int byte) {
  if (byte >= 0x18 && byte <= 0x1f) {
    return _accents[byte - 0x18];
  }
  if (byte >= 0x80 && byte <= 0x9e) {
    return _typography[byte - 0x80];
  }
  return switch (byte) {
    0x7f || 0x9f || 0xad => 0xfffd,
    0xa0 => 0x20ac,
    _ => byte,
  };
}

const _accents = <int>[
  0x02d8,
  0x02c7,
  0x02c6,
  0x02d9,
  0x02dd,
  0x02db,
  0x02da,
  0x02dc,
];

const _typography = <int>[
  0x2022,
  0x2020,
  0x2021,
  0x2026,
  0x2014,
  0x2013,
  0x0192,
  0x2044,
  0x2039,
  0x203a,
  0x2212,
  0x2030,
  0x201e,
  0x201c,
  0x201d,
  0x2018,
  0x2019,
  0x201a,
  0x2122,
  0xfb01,
  0xfb02,
  0x0141,
  0x0152,
  0x0160,
  0x0178,
  0x017d,
  0x0131,
  0x0142,
  0x0153,
  0x0161,
  0x017e,
];
