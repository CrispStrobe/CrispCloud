import 'dart:math' as math;
import 'dart:typed_data';

import '../fonts/font_subsetter.dart';
import '../fonts/sfnt_parser.dart';

/// Type 0 / CIDFontType2 + Identity-H + ToUnicode CMap for a subset TTF.
class PdfCidFont {
  /// PdfCidFont API.
  PdfCidFont({
    required this.fontFile,
    required this.toUnicodeCmap,
    required this.baseName,
    required this.ascent,
    required this.descent,
    required this.capHeight,
    required this.flags,
    required this.bbox,
    required this.italicAngle,
    required this.stemV,
    required this.widths,
    required this.dw,
  });

  /// fontFile API.
  final Uint8List fontFile;

  /// toUnicodeCmap API.
  final String toUnicodeCmap;

  /// baseName API.
  final String baseName;

  /// ascent API.
  final int ascent;

  /// descent API.
  final int descent;

  /// capHeight API.
  final int capHeight;

  /// flags API.
  final int flags;

  /// bbox API.
  final List<int> bbox;

  /// italicAngle API.
  final int italicAngle;

  /// stemV API.
  final int stemV;

  /// widths API.
  final List<int> widths;

  /// dw API.
  final int dw;

  /// build API.
  factory PdfCidFont.build(FontSubset subset, SfntFont source) {
    final SfntFont parsed = SfntFont.parse(subset.bytes);
    final List<int> widths = <int>[
      for (int i = 0; i < parsed.numGlyphs; i++)
        _toPdfWidth(parsed.advanceWidth(i), parsed.unitsPerEm),
    ];
    return PdfCidFont(
      fontFile: subset.bytes,
      toUnicodeCmap: _toUnicode(subset.unicodeToNewGlyph),
      baseName: _sanitize(
        parsed.familyName.isEmpty ? 'QudsSubset' : parsed.familyName,
      ),
      ascent: _toPdfWidth(parsed.ascender, parsed.unitsPerEm),
      descent: _toPdfWidth(parsed.descender, parsed.unitsPerEm),
      capHeight: _toPdfWidth(parsed.capHeight, parsed.unitsPerEm),
      flags: 4, // symbolic
      bbox: <int>[
        _toPdfWidth(parsed.xMin, parsed.unitsPerEm),
        _toPdfWidth(parsed.yMin, parsed.unitsPerEm),
        _toPdfWidth(parsed.xMax, parsed.unitsPerEm),
        _toPdfWidth(parsed.yMax, parsed.unitsPerEm),
      ],
      italicAngle: 0,
      stemV: 80,
      widths: widths,
      dw: 500,
    );
  }

  /// type0Dict API.
  String type0Dict(int cidId, int toUnicodeId) =>
      '<</Type /Font/Subtype /Type0/BaseFont /$baseName/Encoding /Identity-H'
      '/DescendantFonts [$cidId 0 R]/ToUnicode $toUnicodeId 0 R>>';

  /// cidFontDict API.
  String cidFontDict(int descId) {
    final String w = _widthsArray();
    return '<</Type /Font/Subtype /CIDFontType2/BaseFont /$baseName'
        '/CIDSystemInfo <</Registry (Adobe)/Ordering (Identity)/Supplement 0>>'
        '/FontDescriptor $descId 0 R/DW $dw/W $w/CIDToGIDMap /Identity>>';
  }

  /// descriptorDict API.
  String descriptorDict(int fileId) =>
      '<</Type /FontDescriptor/FontName /$baseName/Flags $flags'
      '/FontBBox [${bbox.join(' ')}]/ItalicAngle $italicAngle'
      '/Ascent $ascent/Descent $descent/CapHeight $capHeight/StemV $stemV'
      '/FontFile2 $fileId 0 R>>';

  String _widthsArray() {
    if (widths.isEmpty) {
      return '[]';
    }
    final StringBuffer buffer = StringBuffer('[ 0 [');
    buffer.write(widths.join(' '));
    buffer.write('] ]');
    return buffer.toString();
  }

  /// When a subset glyph is reachable from both a nominal letter and a
  /// presentation form, paint/extract the presentation form so Yeh is not
  /// redrawn as the isolated nominal at a joining position.
  static bool _preferUnicode(int candidate, int current) {
    final bool candForm = candidate >= 0xFB50 && candidate <= 0xFEFF;
    final bool currForm = current >= 0xFB50 && current <= 0xFEFF;
    if (candForm != currForm) {
      return candForm;
    }
    return candidate > current;
  }

  static int _toPdfWidth(int units, int upem) {
    if (upem == 0) {
      return 0;
    }
    return (units * 1000 / upem).round();
  }

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

  static String _toUnicode(Map<int, int> unicodeToGid) {
    final Map<int, int> gidToUnicode = <int, int>{};
    for (final MapEntry<int, int> entry in unicodeToGid.entries) {
      final int? existing = gidToUnicode[entry.value];
      if (existing == null || _preferUnicode(entry.key, existing)) {
        gidToUnicode[entry.value] = entry.key;
      }
    }
    final List<MapEntry<int, int>> entries = gidToUnicode.entries.toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) => a.key - b.key);
    final StringBuffer bf = StringBuffer();
    const int chunk = 100;
    for (int i = 0; i < entries.length; i += chunk) {
      final int end = math.min(i + chunk, entries.length);
      bf.writeln('${end - i} beginbfchar');
      for (int j = i; j < end; j++) {
        final MapEntry<int, int> e = entries[j];
        bf.write('<${e.key.toRadixString(16).padLeft(4, '0')}>');
        bf.writeln('<${e.value.toRadixString(16).padLeft(4, '0')}>');
      }
      bf.writeln('endbfchar');
    }
    return '''
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
/CMapName /Adobe-Identity-UCS def
/CMapType 2 def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
$bf
endcmap
CMapName currentdict /CMap defineresource pop
end
end
''';
  }
}
