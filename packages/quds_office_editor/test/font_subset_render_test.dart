import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Tests always run. Files are written only when this optional directory is set:
// flutter test --no-pub test/font_subset_render_test.dart \
//   --dart-define=QUDS_SUBSET_RENDER_OUTPUT=/absolute/output/directory
const _output = String.fromEnvironment('QUDS_SUBSET_RENDER_OUTPUT');
const _size = 64.0;
const _originalFamily = 'Quds subset original outlines';
const _bmpFamily = 'Quds subset BMP PDF';
const _bmpReferenceFamily = 'Quds subset BMP reference';
const _referenceFamily = 'Quds subset Latin PDF reference';
const _directFamily = 'Quds subset direct Unicode reference';
const _supplementaryFamily = 'Quds subset supplementary PDF';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SfntFont source;

  setUpAll(() async {
    final bytes = await rootBundle.load(
      'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
    );
    source = SfntFont.parse(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    await _loadFont(_originalFamily, source.bytes);
  });

  test('BMP PDF subset remains loadable with exact glyph advances', () async {
    const text = 'ABZ';
    final exported = _export(source, text);
    await _loadFont(_bmpFamily, exported.fontBytes);
    await _loadFont(
      _bmpReferenceFamily,
      FontSubsetter(source).subset(text.runes).bytes,
    );
    final reference = await _raster(text, _bmpReferenceFamily);
    final actual = await _raster(text, _bmpFamily);
    _expectSamePainting(actual, reference);
    _expectSourceOutlines(source, text, text, exported.fontBytes);
    expect(actual.width, _advance(source, text));
  });

  test(
    'supplementary PDF mappings survive real Flutter font loading and painting',
    () async {
      // Synthetic aliases reuse bundled Latin glyph outlines. This verifies
      // Unicode/font/PDF transport, not emoji or CJK glyph coverage. Compare
      // the reopened font against a directly generated identical Unicode
      // subset. Different cmap encodings can produce different native rasters
      // even when outline bytes and advances are identical; do not assume
      // bitmap equality with the Latin reference or full original font.
      const text = 'A\u{1f600}\u{20000}Z';
      const referenceText = 'ABCZ';
      final unicode = _withCmap(source, {
        0x41: source.glyphIdFor(0x41),
        0x1f600: source.glyphIdFor(0x42),
        0x20000: source.glyphIdFor(0x43),
        0x5a: source.glyphIdFor(0x5a),
      });
      final exported = _export(unicode, text);
      final latin = _export(source, referenceText);
      await _loadFont(_supplementaryFamily, exported.fontBytes);
      await _loadFont(_referenceFamily, latin.fontBytes);
      await _loadFont(
        _directFamily,
        FontSubsetter(unicode).subset(text.runes).bytes,
      );
      final direct = await _raster(text, _directFamily);
      final reference = await _raster(referenceText, _referenceFamily);
      final actual = await _raster(text, _supplementaryFamily);
      _expectSamePainting(actual, direct);
      _expectSourceOutlines(source, referenceText, text, exported.fontBytes);
      expect(actual.width, _advance(source, referenceText));

      for (final alias in const [(0x1f600, 0x42), (0x20000, 0x43)]) {
        final expectedGlyph = await _raster(
          String.fromCharCode(alias.$1),
          _directFamily,
        );
        final actualGlyph = await _raster(
          String.fromCharCode(alias.$1),
          _supplementaryFamily,
        );
        _expectSamePainting(actualGlyph, expectedGlyph);
        expect(
          actualGlyph.width,
          _advance(source, String.fromCharCode(alias.$2)),
        );
      }

      if (_output.isNotEmpty) {
        final output = Directory(_output)..createSync(recursive: true);
        File(
          '${output.path}/unicode-subset.pdf',
        ).writeAsBytesSync(exported.pdf);
        await _writeDiagnostic(output, actual, reference);
        final metrics = <String, Object>{
          'scope':
              'Synthetic Unicode aliases of Liberation Sans Latin outlines; '
              'compares PDF-reopened and directly generated identical Unicode subsets. '
              'No original-font or cross-cmap bitmap parity or emoji/CJK coverage claim.',
          'renderer':
              'Actual Flutter test engine, FontLoader, TextPainter '
              'and Canvas; font bytes reopened from exported Word PDFs.',
          'source_code_points': _codePoints(text),
          'extracted_code_points': _codePoints(exported.extractedText),
          'reference_text': referenceText,
          'font_size': _size,
          'reference_width': reference.width,
          'subset_width': actual.width,
          'reference_ink_pixels': reference.inkPixels,
          'subset_ink_pixels': actual.inkPixels,
          'direct_subset_differing_pixels': _differentPixels(
            actual.rgba,
            direct.rgba,
          ),
          'latin_reference_differing_pixels': _differentPixels(
            actual.rgba,
            reference.rgba,
          ),
          'pdf_bytes': exported.pdf.length,
          'embedded_font_bytes': exported.fontBytes.length,
          'dart_runtime': Platform.version,
        };
        File('${output.path}/metrics.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(metrics)}\n',
        );
      }
    },
  );
}

typedef _Export = ({Uint8List pdf, Uint8List fontBytes, String extractedText});

_Export _export(SfntFont font, String text) {
  final diagnostics = OfficeFontDiagnostics();
  final bytes = OfficePdfExport.word(
    WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: text)]),
          ],
        ),
      ],
    ),
    fonts: OfficeFontSet(primary: font, diagnostics: diagnostics),
  );
  expect(diagnostics.missingCodePoints, isEmpty);
  final pdf = PdfFile.open(bytes);
  final extracted = PdfExtract.pageText(pdf, 0);
  expect(extracted, text);
  final ops = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
  expect(ops, isNotEmpty);
  expect(ops.map((op) => op.text).join(), text);
  final embedded = ops.first.fontBytes;
  expect(embedded, isNotNull);
  for (final op in ops) {
    expect(listEquals(op.fontBytes, embedded), isTrue);
  }
  final parsed = SfntFont.parse(embedded!);
  for (final cp in text.runes) {
    expect(parsed.glyphIdFor(cp), isNonZero);
  }
  return (pdf: bytes, fontBytes: embedded, extractedText: extracted);
}

Future<void> _loadFont(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

typedef _Raster = ({double width, int inkPixels, Uint8List rgba});

Future<_Raster> _raster(String text, String family) async {
  final painter = _painter(text, family, _size)..layout();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final width = painter.width;
  try {
    painter.paint(
      canvas,
      Offset(
        16,
        88 - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
  } finally {
    painter.dispose();
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(320, 112);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final rgba = data!.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      var ink = 0;
      for (var i = 3; i < rgba.length; i += 4) {
        if (rgba[i] != 0) ink++;
      }
      return (width: width, inkPixels: ink, rgba: rgba);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void _expectSamePainting(_Raster actual, _Raster reference) {
  expect(reference.inkPixels, greaterThan(100));
  expect(actual.inkPixels, reference.inkPixels);
  expect(actual.width, reference.width);
  expect(_differentPixels(actual.rgba, reference.rgba), 0);
}

void _expectSourceOutlines(
  SfntFont source,
  String referenceText,
  String subsetText,
  Uint8List subsetBytes,
) {
  final subset = SfntFont.parse(subsetBytes);
  final originals = referenceText.runes.toList();
  final aliases = subsetText.runes.toList();
  expect(aliases, hasLength(originals.length));
  for (var i = 0; i < aliases.length; i++) {
    final oldId = source.glyphIdFor(originals[i]);
    final newId = subset.glyphIdFor(aliases[i]);
    expect(newId, isNonZero);
    expect(subset.advanceWidth(newId), source.advanceWidth(oldId));
    final originalOutline = Uint8List.sublistView(
      source.tableBytes('glyf'),
      source.glyphOffsets[oldId],
      source.glyphOffsets[oldId + 1],
    );
    final subsetOutline = Uint8List.sublistView(
      subset.tableBytes('glyf'),
      subset.glyphOffsets[newId],
      subset.glyphOffsets[newId + 1],
    );
    expect(listEquals(subsetOutline, originalOutline), isTrue);
  }
}

int _differentPixels(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var different = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      different++;
    }
  }
  return different;
}

TextPainter _painter(String text, String family, double size) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: family,
      fontSize: size,
      color: const Color(0xff172c3e),
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
);

double _advance(SfntFont font, String text) =>
    text.runes.fold<int>(
      0,
      (sum, cp) => sum + font.advanceWidth(font.glyphIdFor(cp)),
    ) *
    _size /
    font.unitsPerEm;

List<String> _codePoints(String text) => text.runes
    .map((cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}')
    .toList();

Future<void> _writeDiagnostic(
  Directory output,
  _Raster actual,
  _Raster reference,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xfff3f6f8), BlendMode.src);
  void label(String text, double y, {double size = 18}) {
    final painter = _painter(text, _originalFamily, size)..layout();
    try {
      painter.paint(canvas, Offset(40, y));
    } finally {
      painter.dispose();
    }
  }

  label('Supplementary Unicode survives PDF font subsetting', 30, size: 30);
  label('Latin reference PDF subset: U+0041 U+0042 U+0043 U+005A', 88);
  final referencePainter = _painter('ABCZ', _referenceFamily, _size)..layout();
  final subsetPainter = _painter(
    'A\u{1f600}\u{20000}Z',
    _supplementaryFamily,
    _size,
  )..layout();
  try {
    referencePainter.paint(canvas, const Offset(40, 120));
    label('Reopened PDF subset: U+0041 U+1F600 U+20000 U+005A', 225);
    subsetPainter.paint(canvas, const Offset(40, 255));
  } finally {
    referencePainter.dispose();
    subsetPainter.dispose();
  }
  label(
    'Widths: ${reference.width.toStringAsFixed(4)} / '
    '${actual.width.toStringAsFixed(4)} px    Latin-reference pixel differences: '
    '${_differentPixels(actual.rgba, reference.rgba)}',
    365,
  );
  label(
    'PDF / direct Unicode subset: identical raster pixels; source glyph advances and outlines match.',
    405,
    size: 17,
  );
  label(
    'Synthetic Latin outlines; no cross-cmap bitmap parity or emoji/CJK glyph coverage claim.',
    440,
    size: 17,
  );
  label(
    'Actual Flutter Canvas / TextPainter diagnostic, with font bytes extracted from a generated PDF.',
    478,
    size: 16,
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(1100, 520);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      File('${output.path}/unicode-subset-preview.png').writeAsBytesSync(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

SfntFont _withCmap(SfntFont source, Map<int, int> mappings) => SfntFont(
  bytes: source.bytes,
  tables: source.tables,
  unitsPerEm: source.unitsPerEm,
  indexToLocFormat: source.indexToLocFormat,
  numGlyphs: source.numGlyphs,
  numberOfHMetrics: source.numberOfHMetrics,
  ascender: source.ascender,
  descender: source.descender,
  lineGap: source.lineGap,
  capHeight: source.capHeight,
  winAscent: source.winAscent,
  winDescent: source.winDescent,
  xMin: source.xMin,
  yMin: source.yMin,
  xMax: source.xMax,
  yMax: source.yMax,
  advanceWidths: source.advanceWidths,
  leftSideBearings: source.leftSideBearings,
  glyphOffsets: source.glyphOffsets,
  cmap: CmapTable(mappings),
  familyName: source.familyName,
);
