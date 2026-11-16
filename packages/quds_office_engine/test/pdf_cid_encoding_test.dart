import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_tounicode.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

final _output = Platform.environment['QUDS_ALIAS_RENDER_OUTPUT'] ?? '';

void main() {
  final source = aliasTestFont();
  final aliases = withSharedGlyphAliases(source);
  const text = 'A\u{1f600}\u{20000}AZ';
  final subset = FontSubsetter(aliases).subset(text.runes);

  test('distinct CIDs share glyphs without losing text or advances', () {
    final encoding = PdfCidEncoding.fromSubset(subset);
    final font = PdfCidFont.build(subset, aliases, encoding: encoding);
    final cmap = PdfToUnicode.parse(
      Uint8List.fromList(font.toUnicodeCmap.codeUnits),
    );
    final data = ByteData.sublistView(font.cidToGidMap!);
    final expectedGlyphs = SfntFont.parse(subset.bytes);
    expect(encoding.unicodeToCid.values.toSet(), hasLength(4));
    expect(data.getUint16(0), 0);
    for (final cp in text.runes) {
      final cid = encoding.unicodeToCid[cp]!;
      expect(cmap.mapCid(cid), String.fromCharCode(cp));
      final gid = data.getUint16(cid * 2);
      expect(gid, expectedGlyphs.glyphIdFor(cp));
      expect(
        font.widths[cid],
        (expectedGlyphs.advanceWidth(gid) * 1000 / source.unitsPerEm).round(),
      );
    }
    final cids = [
      for (final cp in [0x41, 0x1f600, 0x20000]) encoding.unicodeToCid[cp]!,
    ];
    expect(cids.toSet(), hasLength(3));
    expect(cids.map((cid) => data.getUint16(cid * 2)).toSet(), hasLength(1));
    expect(() => font.cidFontDict(1), throwsArgumentError);
    expect(
      font.cidFontDict(1, cidToGidMapId: 2),
      contains('/CIDToGIDMap 2 0 R'),
    );
  });

  test('encoding is deterministic and owns its maps', () {
    final mutable = Map<int, int>.fromEntries(
      subset.unicodeToNewGlyph.entries.toList().reversed,
    );
    final reordered = FontSubset(
      bytes: subset.bytes,
      oldToNewGlyph: subset.oldToNewGlyph,
      unicodeToNewGlyph: mutable,
      numGlyphs: subset.numGlyphs,
    );
    final encoding = PdfCidEncoding.fromSubset(reordered);
    final expected = PdfCidEncoding.fromSubset(subset);
    mutable.clear();
    expect(encoding.unicodeToCid, expected.unicodeToCid);
    expect(encoding.cidToGidMap, expected.cidToGidMap);
    expect(() => encoding.unicodeToCid.clear(), throwsUnsupportedError);
    expect(() => encoding.glyphIds[0] = 1, throwsUnsupportedError);
    expect(() => encoding.cidToUnicode.clear(), throwsUnsupportedError);
  });

  test(
    'invalid scalar and missing/out-of-range glyph mappings are excluded',
    () {
      final gid = subset.unicodeToNewGlyph[0x41]!;
      final malformed = FontSubset(
        bytes: subset.bytes,
        oldToNewGlyph: subset.oldToNewGlyph,
        unicodeToNewGlyph: {
          0x41: gid,
          -1: gid,
          0xd800: gid,
          0x110000: gid,
          0x42: 0,
          0x43: -1,
          0x44: subset.numGlyphs,
        },
        numGlyphs: subset.numGlyphs,
      );
      expect(PdfCidEncoding.fromSubset(malformed).unicodeToCid.keys, [0x41]);
    },
  );

  test('an encoding from a different subset cannot mislabel its glyphs', () {
    final ab = FontSubsetter(source).subset('AB'.runes);
    final b = FontSubsetter(source).subset('B'.runes);
    expect(
      () =>
          PdfCidFont.build(b, source, encoding: PdfCidEncoding.fromSubset(ab)),
      throwsArgumentError,
      reason: 'An absent glyph and a different cmap must not be serialized',
    );
    expect(
      () =>
          PdfCidFont.build(ab, source, encoding: PdfCidEncoding.fromSubset(b)),
      throwsArgumentError,
      reason: 'Even an in-range glyph ID can refer to another outline',
    );
  });

  test('a font resource cannot overflow its 16-bit character codes', () {
    final mappings = <int, int>{
      for (var i = 0; i <= PdfCidEncoding.maxCharacters; i++)
        0x10000 + i: subset.unicodeToNewGlyph[0x41]!,
    };
    FontSubset request() => FontSubset(
      bytes: subset.bytes,
      oldToNewGlyph: subset.oldToNewGlyph,
      unicodeToNewGlyph: mappings,
      numGlyphs: subset.numGlyphs,
    );
    expect(() => PdfCidEncoding.fromSubset(request()), throwsArgumentError);
    mappings.remove(mappings.keys.last);
    final encoding = PdfCidEncoding.fromSubset(request());
    expect(encoding.unicodeToCid.values.last, 0xffff);
    expect(encoding.cidToGidMap.length, 0x10000 * 2);
  });

  test(
    'writer emits a real CIDToGIDMap stream and keeps legacy identity mode',
    () {
      final encoding = PdfCidEncoding.fromSubset(subset);
      final encodedBytes = _paint(subset, aliases, text, encoding: encoding);
      final legacyBytes = _paint(subset, aliases, text);
      final file = PdfFile.open(encodedBytes);
      expect(PdfExtract.pageText(file, 0), text);
      final resources = file.store.asDict(file.pageRec(0).dict['Resources'])!;
      final fonts = file.store.asDict(resources['Font'])!;
      final type0 = file.store.asDict(fonts['F1'])!;
      final descendants =
          file.store.deref(type0['DescendantFonts']) as PdfCosArray;
      final cid = file.store.asDict(descendants.items.single)!;
      expect(file.store.streamBytes(cid['CIDToGIDMap']), encoding.cidToGidMap);
      final legacy = PdfCidFont.build(subset, aliases);
      expect(legacy.cidToGidMap, isNull);
      expect(legacy.cidFontDict(1), contains('/CIDToGIDMap /Identity'));
      if (_output.isNotEmpty) {
        Directory(_output).createSync(recursive: true);
        File('$_output/encoded-aliases.pdf').writeAsBytesSync(encodedBytes);
        File(
          '$_output/identity-glyph-reference.pdf',
        ).writeAsBytesSync(legacyBytes);
        File('$_output/authored-text.txt').writeAsStringSync(text);
      }
    },
  );
}

Uint8List _paint(
  FontSubset subset,
  SfntFont source,
  String text, {
  PdfCidEncoding? encoding,
}) {
  final canvas = PdfCanvas(320, 112);
  var x = 16.0;
  for (final cp in text.runes) {
    canvas.showGlyph(
      x: x,
      y: 88,
      fontSize: 48,
      glyphId: encoding?.unicodeToCid[cp] ?? subset.unicodeToNewGlyph[cp]!,
      color: '172C3E',
    );
    x += source.advanceWidth(source.glyphIdFor(cp)) * 48 / source.unitsPerEm;
  }
  canvas.endText();
  final doc = PdfDocument()
    ..addPage(PdfPage(width: 320, height: 112, content: canvas.toStream()));
  return doc.save(
    faces: [
      PdfEmbeddedFace(
        subset: subset,
        source: source,
        resourceName: 'F1',
        encoding: encoding,
      ),
    ],
  );
}
