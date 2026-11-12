import 'dart:typed_data';

/// Explicit legacy text encodings shared by viewing, editing and searching.
/// Auto detection intentionally does not guess a code page from ambiguous bytes.
bool isLegacyTextEncoding(String encoding) =>
    encoding == 'cp437' || encoding == 'windows1252';

/// Maps DOS CP437 and Windows-1252 bytes to Unicode. ASCII controls keep their
/// text meaning (including CR, LF and TAB); they are not screen-font pictograms.
/// The five undefined Windows-1252 slots retain their matching C1 controls so
/// an unchanged file can be saved without losing any original byte.
int decodeLegacyTextByte(int byte, String encoding) {
  if (byte < 0 || byte > 255) {
    throw RangeError.range(byte, 0, 255, 'byte');
  }
  return switch (encoding) {
    'cp437' => byte < 0x80 ? byte : _cp437HighBytes[byte - 0x80],
    'windows1252' =>
      byte >= 0x80 && byte <= 0x9f ? _windows1252Extensions[byte - 0x80] : byte,
    _ => throw FormatException('Unsupported legacy encoding: $encoding'),
  };
}

String decodeLegacyText(List<int> bytes, String encoding) {
  if (!isLegacyTextEncoding(encoding)) {
    throw FormatException('Unsupported legacy encoding: $encoding');
  }
  return String.fromCharCodes(
    bytes.map((byte) => decodeLegacyTextByte(byte, encoding)),
  );
}

/// Strict conversion: characters absent from the selected code page cause an
/// error, never a replacement question mark or silently truncated byte.
Uint8List encodeLegacyText(String text, String encoding) {
  final mapping = _encodeTables[encoding];
  if (mapping == null) {
    throw FormatException('Unsupported legacy encoding: $encoding');
  }
  final bytes = BytesBuilder(copy: false);
  for (final rune in text.runes) {
    final byte = mapping[rune];
    if (byte == null) {
      throw FormatException(
        '$encoding cannot represent U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}.',
      );
    }
    bytes.addByte(byte);
  }
  return bytes.takeBytes();
}

final Map<String, Map<int, int>> _encodeTables = {
  for (final encoding in ['cp437', 'windows1252'])
    encoding: {
      for (var byte = 0; byte < 256; byte++)
        decodeLegacyTextByte(byte, encoding): byte,
    },
};

// Character assignments follow the published Unicode code-page mappings:
// https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/PC/CP437.TXT
// https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP1252.TXT
const _cp437HighBytes = <int>[
  0x00c7,
  0x00fc,
  0x00e9,
  0x00e2,
  0x00e4,
  0x00e0,
  0x00e5,
  0x00e7,
  0x00ea,
  0x00eb,
  0x00e8,
  0x00ef,
  0x00ee,
  0x00ec,
  0x00c4,
  0x00c5,
  0x00c9,
  0x00e6,
  0x00c6,
  0x00f4,
  0x00f6,
  0x00f2,
  0x00fb,
  0x00f9,
  0x00ff,
  0x00d6,
  0x00dc,
  0x00a2,
  0x00a3,
  0x00a5,
  0x20a7,
  0x0192,
  0x00e1,
  0x00ed,
  0x00f3,
  0x00fa,
  0x00f1,
  0x00d1,
  0x00aa,
  0x00ba,
  0x00bf,
  0x2310,
  0x00ac,
  0x00bd,
  0x00bc,
  0x00a1,
  0x00ab,
  0x00bb,
  0x2591,
  0x2592,
  0x2593,
  0x2502,
  0x2524,
  0x2561,
  0x2562,
  0x2556,
  0x2555,
  0x2563,
  0x2551,
  0x2557,
  0x255d,
  0x255c,
  0x255b,
  0x2510,
  0x2514,
  0x2534,
  0x252c,
  0x251c,
  0x2500,
  0x253c,
  0x255e,
  0x255f,
  0x255a,
  0x2554,
  0x2569,
  0x2566,
  0x2560,
  0x2550,
  0x256c,
  0x2567,
  0x2568,
  0x2564,
  0x2565,
  0x2559,
  0x2558,
  0x2552,
  0x2553,
  0x256b,
  0x256a,
  0x2518,
  0x250c,
  0x2588,
  0x2584,
  0x258c,
  0x2590,
  0x2580,
  0x03b1,
  0x00df,
  0x0393,
  0x03c0,
  0x03a3,
  0x03c3,
  0x00b5,
  0x03c4,
  0x03a6,
  0x0398,
  0x03a9,
  0x03b4,
  0x221e,
  0x03c6,
  0x03b5,
  0x2229,
  0x2261,
  0x00b1,
  0x2265,
  0x2264,
  0x2320,
  0x2321,
  0x00f7,
  0x2248,
  0x00b0,
  0x2219,
  0x00b7,
  0x221a,
  0x207f,
  0x00b2,
  0x25a0,
  0x00a0,
];

const _windows1252Extensions = <int>[
  0x20ac,
  0x0081,
  0x201a,
  0x0192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x02c6,
  0x2030,
  0x0160,
  0x2039,
  0x0152,
  0x008d,
  0x017d,
  0x008f,
  0x0090,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x02dc,
  0x2122,
  0x0161,
  0x203a,
  0x0153,
  0x009d,
  0x017e,
  0x0178,
];
