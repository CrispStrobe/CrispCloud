import 'dart:math' as math;
import 'dart:typed_data';

import '../fonts/font_subsetter.dart';
import '../fonts/sfnt_parser.dart';

/// Separates a PDF character code from the glyph that paints it.
///
/// A font can map several Unicode scalars to one glyph. Using that glyph ID
/// as the PDF character code loses all but one of those scalars in ToUnicode.
/// This encoding gives each scalar its own CID and maps those CIDs back to the
/// shared subset glyph through a CIDToGIDMap stream. CID zero remains .notdef.
/// Content streams using this encoding must emit [unicodeToCid] values, not
/// subset glyph IDs. Existing identity-encoded writer APIs remain available.
class PdfCidEncoding {
  PdfCidEncoding._(this.unicodeToCid, this.glyphIds, this.cidToUnicode);

  /// The maximum number of mapped characters in one Identity-H resource.
  static const int maxCharacters = 0xffff;

  /// Builds a deterministic encoding for valid, non-missing subset mappings.
  ///
  /// A larger character set must be split across multiple PDF font resources.
  /// The mapping owns its collections; subsequent subset-map edits cannot
  /// change the interpretation of character codes already emitted to PDF.
  factory PdfCidEncoding.fromSubset(FontSubset subset) {
    final entries =
        subset.unicodeToNewGlyph.entries
            .where(
              (entry) =>
                  entry.key >= 0 &&
                  entry.key <= 0x10ffff &&
                  !(entry.key >= 0xd800 && entry.key <= 0xdfff) &&
                  entry.value > 0 &&
                  entry.value < subset.numGlyphs &&
                  entry.value <= 0xffff,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.length > maxCharacters) {
      throw ArgumentError.value(
        entries.length,
        'subset',
        'Split more than $maxCharacters Unicode mappings into multiple fonts',
      );
    }
    final unicodeToCid = <int, int>{};
    final glyphIds = <int>[0];
    final cidToUnicode = <int, int>{};
    for (final entry in entries) {
      final cid = glyphIds.length;
      unicodeToCid[entry.key] = cid;
      glyphIds.add(entry.value);
      cidToUnicode[cid] = entry.key;
    }
    return PdfCidEncoding._(
      Map<int, int>.unmodifiable(unicodeToCid),
      List<int>.unmodifiable(glyphIds),
      Map<int, int>.unmodifiable(cidToUnicode),
    );
  }

  /// PDF character code for each mapped Unicode scalar.
  final Map<int, int> unicodeToCid;

  /// Subset glyph ID indexed by CID, including .notdef at CID zero.
  final List<int> glyphIds;

  /// Original Unicode scalar indexed by CID, for extraction and search.
  final Map<int, int> cidToUnicode;

  /// Big-endian 16-bit glyph indices required by ISO 32000-1 §9.7.4.2.
  Uint8List get cidToGidMap {
    final bytes = Uint8List(glyphIds.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var cid = 0; cid < glyphIds.length; cid++) {
      data.setUint16(cid * 2, glyphIds[cid]);
    }
    return bytes;
  }
}

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
    this.cidToGidMap,
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

  /// Null for the legacy identity mapping; otherwise one glyph index per CID.
  final Uint8List? cidToGidMap;

  /// build API.
  factory PdfCidFont.build(
    FontSubset subset,
    SfntFont source, {
    PdfCidEncoding? encoding,
  }) {
    final SfntFont parsed = SfntFont.parse(subset.bytes);
    if (encoding != null) {
      for (final entry in encoding.cidToUnicode.entries) {
        final gid = encoding.glyphIds[entry.key];
        if (gid >= parsed.numGlyphs || parsed.glyphIdFor(entry.value) != gid) {
          throw ArgumentError.value(
            encoding,
            'encoding',
            'CID ${entry.key} does not match the embedded subset cmap',
          );
        }
      }
    }
    final glyphIds =
        encoding?.glyphIds ?? Iterable<int>.generate(parsed.numGlyphs);
    final List<int> widths = <int>[
      for (final gid in glyphIds)
        _toPdfWidth(parsed.advanceWidth(gid), parsed.unitsPerEm),
    ];
    return PdfCidFont(
      fontFile: subset.bytes,
      toUnicodeCmap: encoding == null
          ? _toUnicode(subset.unicodeToNewGlyph)
          : _cidToUnicode(encoding.cidToUnicode),
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
      cidToGidMap: encoding?.cidToGidMap,
    );
  }

  /// type0Dict API.
  String type0Dict(int cidId, int toUnicodeId) =>
      '<</Type /Font/Subtype /Type0/BaseFont /$baseName/Encoding /Identity-H'
      '/DescendantFonts [$cidId 0 R]/ToUnicode $toUnicodeId 0 R>>';

  /// cidFontDict API.
  String cidFontDict(int descId, {int? cidToGidMapId}) {
    if (cidToGidMap != null && cidToGidMapId == null) {
      throw ArgumentError('A non-identity encoding needs a CIDToGIDMap stream');
    }
    final String w = _widthsArray();
    final mapping = cidToGidMapId == null ? '/Identity' : '$cidToGidMapId 0 R';
    return '<</Type /Font/Subtype /CIDFontType2/BaseFont /$baseName'
        '/CIDSystemInfo <</Registry (Adobe)/Ordering (Identity)/Supplement 0>>'
        '/FontDescriptor $descId 0 R/DW $dw/W $w/CIDToGIDMap $mapping>>';
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
      // The subsetter filters scalar requests, but FontSubset is also a public
      // value type. Invalid aliases must not replace an extractable character.
      if (entry.key < 0 ||
          entry.key > 0x10FFFF ||
          (entry.key >= 0xD800 && entry.key <= 0xDFFF)) {
        continue;
      }
      final int? existing = gidToUnicode[entry.value];
      if (existing == null || _preferUnicode(entry.key, existing)) {
        gidToUnicode[entry.value] = entry.key;
      }
    }
    return _cidToUnicode(gidToUnicode);
  }

  static String _cidToUnicode(Map<int, int> cidToUnicode) {
    final List<MapEntry<int, int>> entries = cidToUnicode.entries.toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) => a.key - b.key);
    final StringBuffer bf = StringBuffer();
    const int chunk = 100;
    for (int i = 0; i < entries.length; i += chunk) {
      final int end = math.min(i + chunk, entries.length);
      bf.writeln('${end - i} beginbfchar');
      for (int j = i; j < end; j++) {
        final MapEntry<int, int> e = entries[j];
        bf.write('<${e.key.toRadixString(16).padLeft(4, '0')}>');
        // ToUnicode destinations are UTF-16BE strings, not hexadecimal
        // Unicode scalar numbers. Supplementary values require two code units.
        final utf16 = String.fromCharCode(e.value).codeUnits;
        bf.writeln(
          '<${utf16.map((unit) => unit.toRadixString(16).padLeft(4, '0')).join()}>',
        );
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
