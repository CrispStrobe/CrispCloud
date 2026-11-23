// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/metafile_fixture.dart';
import 'support/structured_word_fixture.dart';

LegacyWordMetafileInfo _emf(List<Uint8List> records) => parseLegacyWordMetafile(
  emfFixture(records: records),
  format: LegacyWordImageFormat.emf,
);
LegacyWordMetafileInfo _wmf(List<Uint8List> records) => parseLegacyWordMetafile(
  wmfFixture(records: records),
  format: LegacyWordImageFormat.wmf,
  bounds: const LegacyWordVectorBounds(0, 0, 200, 100),
);
Uint8List _emfInts(int type, List<int> values) =>
    emfRecord(type, [for (final n in values) ...wordU32(n)]);
Uint8List _wmfInts(int type, List<int> values) =>
    wmfRecord(type, [for (final n in values) ...wordU16(n)]);

Uint8List _emfPlusRecord(int type, int flags, List<int> data) =>
    Uint8List.fromList([
      ...wordU16(type),
      ...wordU16(flags),
      ...wordU32(12 + data.length * 4),
      ...wordU32(data.length * 4),
      for (final n in data) ...wordU32(n),
    ]);

Uint8List _emfPlusComment(List<Uint8List> records) => emfRecord(70, [
  ...wordU32(4 + records.fold(0, (size, record) => size + record.length)),
  ...wordU32(0x2b464d45),
  for (final record in records) ...record,
]);

Uint8List _emfTestFont(String name, {int handle = 1}) => emfRecord(82, [
  ...wordU32(handle),
  ...wordU32(-24),
  ...List.filled(12, 0),
  ...wordU32(700),
  ...List.filled(8, 0),
  for (final code in name.codeUnits) ...wordU16(code),
  ...List.filled(64 - name.length * 2, 0),
]);

Uint8List _emfTestText(
  String text, {
  int flags = 0,
  int advanceOffsetDelta = 0,
}) {
  final count = text.length;
  final padding = count.isOdd ? 2 : 0;
  return emfRecord(84, [
    ...List.filled(16, 0),
    ...wordU32(1),
    ...List.filled(8, 0),
    ...wordU32(10),
    ...wordU32(20),
    ...wordU32(count),
    ...wordU32(76),
    ...wordU32(flags),
    ...List.filled(16, 0),
    ...wordU32(76 + count * 2 + padding + advanceOffsetDelta),
    for (final code in text.codeUnits) ...wordU16(code),
    ...List.filled(padding, 0),
    for (var index = 0; index < count; index++) ...wordU32(17),
  ]);
}

Uint8List _transform(int type, List<double> values, [int? mode]) {
  final bytes = Uint8List(24);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return emfRecord(type, [...bytes, if (mode != null) ...wordU32(mode)]);
}

Uint8List _emfMultiPoly(int type, List<List<(int, int)>> figures) =>
    emfRecord(type, [
      ...List.filled(16, 0),
      ...wordU32(figures.length),
      ...wordU32(figures.fold<int>(0, (sum, points) => sum + points.length)),
      for (final points in figures) ...wordU32(points.length),
      for (final points in figures)
        for (final (x, y) in points)
          if (type >= 90) ...[
            ...wordU16(x),
            ...wordU16(y),
          ] else ...[
            ...wordU32(x),
            ...wordU32(y),
          ],
    ]);

Uint8List _wmfMultiPoly(List<List<(int, int)>> figures) => wmfRecord(0x0538, [
  ...wordU16(figures.length),
  for (final points in figures) ...wordU16(points.length),
  for (final points in figures)
    for (final (x, y) in points) ...[...wordU16(x), ...wordU16(y)],
]);

List<XmlElement> _elements(LegacyWordMetafileInfo result, String name) =>
    XmlDocument.parse(result.previewSvg!).findAllElements(name).toList();

Uint8List _enhancedWmf({
  bool placeable = false,
  bool windowsChecksum = false,
  bool badRemaining = false,
  bool extraEscape = false,
}) {
  final emf = emfFixture(
    records: [
      _emfInts(43, [5, 10, 25, 35]),
    ],
  );
  final data = ByteData.sublistView(emf);
  var checksum = 0xffff;
  for (var offset = 0; offset < emf.length; offset += 2) {
    checksum ^= data.getUint16(offset, Endian.little);
  }
  const split = 90; // The comments can divide an EMF record.
  final parts = [emf.sublist(0, split), emf.sublist(split)];
  final remaining = emf.length - split;
  final wrapped = wmfFixture(
    placeable: placeable,
    records: [
      for (var index = 0; index < parts.length; index++)
        wmfRecord(0x0626, [
          ...wordU16(15),
          ...wordU16(34 + parts[index].length),
          ...wordU32(0x43464d57),
          ...wordU32(1),
          ...wordU32(0x00010000),
          ...wordU16(windowsChecksum ? 0 : checksum),
          ...wordU32(0),
          ...wordU32(parts.length),
          ...wordU32(parts[index].length),
          ...wordU32(index == 0 ? remaining + (badRemaining ? 2 : 0) : 0),
          ...wordU32(emf.length),
          ...parts[index],
        ]),
      if (extraEscape) _wmfInts(0x0626, [9, 0]),
    ],
  );
  if (windowsChecksum) {
    final stream = ByteData.sublistView(wrapped, placeable ? 22 : 0);
    var sum = 0;
    for (var offset = 0; offset < stream.lengthInBytes; offset += 2) {
      sum = (sum + stream.getUint16(offset, Endian.little)) & 0xffff;
    }
    stream.setUint16(18 + 22, (-sum) & 0xffff, Endian.little);
  }
  return wrapped;
}

void main() {
  test('EMF rectangular clipping preserves exclusion, transform and save', () {
    final result = _emf([
      _emfInts(30, [5, 6, 50, 60]),
      _emfInts(33, []),
      _emfInts(29, [10, 20, 30, 40]),
      _emfInts(30, [7, 8, 45, 50]),
      _transform(35, [1, 0, 0, 1, 1, 2]),
      _emfInts(43, [0, 0, 80, 90]),
      _emfInts(34, [-1]),
      _emfInts(43, [0, 0, 70, 80]),
      _emfInts(29, [0, 0, 90, 90]),
      _emfInts(43, [0, 0, 60, 70]),
      _emfInts(75, [0, 5]),
      _emfInts(43, [0, 0, 50, 60]),
    ]);
    expect(result.hasCompletePreview, isTrue);
    final clip = _elements(result, 'clipPath').last;
    expect(
      clip
          .findElements('rect')
          .map(
            (element) => [
              for (final field in ['x', 'y', 'width', 'height'])
                element.getAttribute(field),
            ],
          ),
      [
        ['7', '8', '38', '12'],
        ['7', '40', '38', '10'],
        ['7', '20', '3', '20'],
        ['30', '20', '15', '20'],
      ],
    );
    final groups = _elements(result, 'g');
    expect(groups.map((g) => g.getAttribute('clip-path')), [
      'url(#emfClip3)',
      'url(#emfClip1)',
    ]);
    expect(
      groups.first.findElements('rect').single.getAttribute('transform'),
      'matrix(1 0 0 1 1 2)',
    );
    final painted = _elements(
      result,
      'rect',
    ).where((rect) => rect.getAttribute('fill') != null);
    expect(painted.length, 3);
  });

  test(
    'dual EMF+ replays its classical Latin text and private data stays opaque',
    () {
      final dual = _emfPlusComment([
        _emfPlusRecord(0x4001, 1, [0xdbc01002, 1, 96, 96]),
        _emfPlusRecord(0x4004, 0, []),
      ]);
      final tail = _emfPlusComment([_emfPlusRecord(0x4002, 0, [])]);
      final drawing = [
        _emfInts(70, [8, 0x5247534d, 0x3c746167]),
        _emfInts(18, [1]),
        _emfTestFont('Calibri'),
        _emfInts(37, [1]),
        _emfInts(24, [0x332211]),
        _emfTestText('<ö &'),
        _emfInts(22, [24]),
        _emfTestText('ü'),
        _emfInts(37, [0x8000000d]),
        _emfInts(40, [1]),
      ];
      final result = _emf([dual, ...drawing, tail]);
      expect(result.hasCompletePreview, isTrue);
      expect(result.previewSvg, isNot(contains('tag')));
      final glyphs = _elements(result, 'text');
      expect(glyphs.map((glyph) => glyph.innerText), ['<', 'ö', '&', 'ü']);
      expect(glyphs.map((glyph) => glyph.getAttribute('x')), [
        '10',
        '27',
        '61',
        '10',
      ]);
      expect(glyphs.map((glyph) => glyph.getAttribute('y')), [
        '43',
        '43',
        '43',
        '20',
      ]);
      expect(glyphs.first.parentElement!.getAttribute('fill'), '#112233');
      expect(_emf([dual, ...drawing]).unsupportedPreviewRecords, [70]);
      expect(_emf([dual, tail]).unsupportedPreviewRecords, [70]);
      final plusOnly = _emfPlusComment([
        _emfPlusRecord(0x4001, 0, [0xdbc01002, 1, 96, 96]),
      ]);
      expect(_emf([plusOnly, ...drawing, tail]).unsupportedPreviewRecords, [
        70,
      ]);
      final unsupportedDrawing = _emfPlusComment([
        _emfPlusRecord(0x400e, 0, []),
      ]);
      expect(
        _emf([
          dual,
          ...drawing,
          unsupportedDrawing,
          tail,
        ]).unsupportedPreviewRecords,
        [70],
      );
    },
  );

  test('EMF declines glyph indices and overlapping text and advance data', () {
    for (final text in [
      _emfTestText('x', flags: 16),
      _emfTestText('xy', advanceOffsetDelta: -4),
      _emfTestText('🙂'),
    ]) {
      expect(
        _emf([
          _emfInts(18, [1]),
          _emfTestFont('Arial'),
          _emfInts(37, [1]),
          text,
        ]).unsupportedPreviewRecords,
        [84],
      );
    }
  });

  test(
    'dual EMF+ canvas uses its physical frame and preserves explicit bounds',
    () {
      final original = emfFixture(
        records: [
          _emfPlusComment([
            _emfPlusRecord(0x4001, 1, [0xdbc01002, 1, 96, 96]),
            _emfPlusRecord(0x4004, 0, []),
          ]),
          _emfInts(43, [0, 0, 200, 100]),
          _emfPlusComment([_emfPlusRecord(0x4002, 0, [])]),
        ],
      );
      final extended = Uint8List.fromList([
        ...original.sublist(0, 88),
        ...List.filled(20, 0),
        ...original.sublist(88),
      ]);
      ByteData.sublistView(extended)
        ..setUint32(4, 108, Endian.little)
        ..setUint32(32, 2500, Endian.little)
        ..setUint32(36, 1600, Endian.little)
        ..setUint32(48, extended.length, Endian.little)
        ..setUint32(100, 100000, Endian.little)
        ..setUint32(104, 100000, Endian.little);
      final result = parseLegacyWordMetafile(
        extended,
        format: LegacyWordImageFormat.emf,
      );
      expect(
        _elements(result, 'svg').single.getAttribute('viewBox'),
        '0 0 250 160',
      );
      expect(result.bounds.width, 250);
      final explicit = parseLegacyWordMetafile(
        extended,
        format: LegacyWordImageFormat.emf,
        bounds: const LegacyWordVectorBounds(10, 20, 30, 50),
      );
      expect(
        _elements(explicit, 'svg').single.getAttribute('viewBox'),
        '10 20 20 30',
      );
    },
  );

  test('WMF text honors baseline, advances, clipping and escaped glyphs', () {
    final font = wmfRecord(0x02fb, [
      ...wordU16(-16),
      ...List.filled(6, 0),
      ...wordU16(700),
      ...List.filled(8, 0),
      ...'Calibri'.codeUnits,
      0,
    ]);
    final text = wmfRecord(0x0a32, [
      for (final field in [20, 3, 3, 4, 0, 0, 50, 30]) ...wordU16(field),
      ...'< &'.codeUnits,
      0,
      for (final advance in [8, 6, 9]) ...wordU16(advance),
    ]);
    final textColor = wmfRecord(0x0209, wordU32(0x02332211));
    final mapping = [
      _wmfInts(0x012e, [24]),
      _wmfInts(0x0102, [1]),
      font,
      _wmfInts(0x012d, [0]),
      textColor,
    ];
    final result = _wmf([...mapping, text]);
    final glyphs = _elements(result, 'text');
    expect(glyphs.map((glyph) => glyph.innerText), ['<', '&']);
    expect(glyphs.map((glyph) => glyph.getAttribute('x')), ['3', '17']);
    expect(glyphs.map((glyph) => glyph.getAttribute('y')), ['20', '20']);
    final group = glyphs.first.parentElement!;
    expect(group.getAttribute('fill'), '#112233');
    expect(group.getAttribute('font-family'), 'Calibri');
    expect(group.getAttribute('font-weight'), '700');
    expect(group.getAttribute('clip-path'), 'url(#wmfTextClip1)');
    expect(_elements(result, 'rect').single.getAttribute('height'), '30');
    expect(
      _wmf([
        ...mapping,
        wmfRecord(0x0a32, text.sublist(6, text.length - 2)),
      ]).unsupportedPreviewRecords,
      [0x0a32],
    );
  });

  test('bounded WMFC comments expose embedded EMF only in generated SVG', () {
    for (final bytes in [
      _enhancedWmf(),
      _enhancedWmf(placeable: true, windowsChecksum: true),
    ]) {
      final result = parseLegacyWordMetafile(
        bytes,
        format: LegacyWordImageFormat.wmf,
      );
      expect(result.recordCount, 3);
      expect(_elements(result, 'rect').single.getAttribute('x'), '5');
      expect(result.nativeEmbeddingAllowed, isFalse);
    }
    final badChecksum = _enhancedWmf(windowsChecksum: true);
    badChecksum[18 + 22] ^= 1;
    for (final bytes in [
      _enhancedWmf(badRemaining: true, windowsChecksum: true),
      _enhancedWmf(extraEscape: true),
      badChecksum,
    ]) {
      final result = parseLegacyWordMetafile(
        bytes,
        format: LegacyWordImageFormat.wmf,
      );
      expect(result.hasCompletePreview, isFalse);
      expect(result.nativeEmbeddingAllowed, isFalse);
    }
  });

  test(
    'StretchDIBits replays bottom-up BGR and ignores the padding column',
    () {
      final bytes = Uint8List(144);
      final data = ByteData.sublistView(bytes);
      final fields = {
        40: 2,
        44: 2,
        48: 80,
        52: 40,
        56: 120,
        60: 24,
        68: 0x00cc0020,
        72: 200,
        76: 100,
        80: 40,
        84: 3,
        88: 2,
      };
      for (final entry in fields.entries) {
        data.setUint32(entry.key, entry.value, Endian.little);
      }
      data
        ..setUint16(92, 1, Endian.little)
        ..setUint16(94, 32, Endian.little);
      bytes.setAll(120, const [
        255,
        0,
        0,
        0,
        0,
        255,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        0,
        255,
        0,
        0,
        255,
        0,
        0,
        255,
        0,
        255,
        0,
      ]);
      LegacyWordMetafileInfo parse() =>
          _emf([emfRecord(81, Uint8List.sublistView(bytes, 8))]);
      final svg = XmlDocument.parse(parse().previewSvg!);
      final image = svg.findAllElements('image').single;
      expect(image.getAttribute('width'), '200');
      final dataUri = image.getAttribute('href')!;
      final png = base64Decode(dataUri.substring(dataUri.indexOf(',') + 1));
      final header = ByteData.sublistView(png);
      expect((header.getUint32(16), header.getUint32(20)), (2, 2));
      final compressed = Uint8List.sublistView(
        png,
        41,
        41 + header.getUint32(33),
      );
      expect(
        const ZLibDecoder().decodeBytes(compressed),
        orderedEquals([0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 0]),
      );
      data.setUint32(68, 0x008800c6, Endian.little);
      expect(parse().unsupportedPreviewRecords, [81]);
    },
  );

  test(
    'EMF path clip and Bezier fill replay the safe multiformat fallback',
    () {
      final payload = '<script/>'.codeUnits;
      final comment = _emfInts(70, [
        44 + payload.length,
        0x43494447,
        0x40000004,
        0,
        0,
        200,
        100,
        1,
        0x50444620,
        1,
        payload.length,
        44,
      ]);
      // Supply the opaque alternate format bytes and align the outer record.
      final withPayload = emfRecord(70, [
        ...comment.sublist(8),
        ...payload,
        ...List.filled((4 - payload.length % 4) % 4, 0),
      ]);
      final bounds = [0, 0, 200, 100];
      final result = _emf([
        withPayload,
        _emfInts(59, []),
        _emfInts(27, [0, 0]),
        _emfInts(54, [200, 0]),
        _emfInts(54, [200, 100]),
        _emfInts(54, [0, 100]),
        _emfInts(61, []),
        _emfInts(60, []),
        _emfInts(67, [5]),
        _emfInts(39, [1, 0, 0x996633, 0]),
        _emfInts(37, [1]),
        _emfInts(59, []),
        _emfInts(27, [15, 10]),
        emfRecord(88, [
          ...List.filled(16, 0),
          ...wordU32(3),
          for (final coordinate in [15, 80, 160, 80, 160, 10])
            ...wordU16(coordinate),
        ]),
        _emfInts(61, []),
        _emfInts(60, []),
        _emfInts(62, bounds),
        _emfInts(75, [0, 5]),
        _emfInts(43, [0, 0, 10, 10]),
      ]);
      expect(result.hasCompletePreview, isTrue);
      expect(result.previewSvg, isNot(contains('<script')));
      final group = _elements(result, 'g').single;
      expect(group.getAttribute('clip-path'), 'url(#emfClip1)');
      final config = _elements(result, 'clipPath').single;
      expect(config.getAttribute('id'), 'emfClip1');
      final fill = group.findElements('path').single;
      expect(fill.getAttribute('d'), 'M15 10C15 80 160 80 160 10 Z');
      expect(fill.getAttribute('fill'), '#336699');
      expect(fill.getAttribute('stroke'), 'none');
      expect(_elements(result, 'rect').single.parentElement!.name.local, 'svg');
      expect(_emf([withPayload]).hasCompletePreview, isFalse);
    },
  );

  test(
    'EMF rejects unsupported clipping combinations and invalid alternates',
    () {
      expect(
        _emf([
          _emfInts(75, [0, 1]),
        ]).unsupportedPreviewRecords,
        [75],
      );
      final malformed = _emfInts(70, [
        44,
        0x43494447,
        0x40000004,
        0,
        0,
        200,
        100,
        1,
        0x50444620,
        1,
        8,
        44,
      ]);
      expect(
        _emf([
          malformed,
          _emfInts(43, [0, 0, 50, 50]),
        ]).unsupportedPreviewRecords,
        [70],
      );
    },
  );

  test('EMF and WMF compound polygons preserve holes and fill rules', () {
    final polygons = [
      [(-10, -10), (100, -10), (100, 90), (-10, 90)],
      [(20, 20), (70, 20), (70, 60), (20, 60)],
    ];
    for (final mode in [1, 2]) {
      final results = [
        for (final type in [8, 91])
          _emf([
            _emfInts(19, [mode]),
            _emfMultiPoly(type, polygons),
          ]),
        _wmf([
          _wmfInts(0x0106, [mode]),
          _wmfMultiPoly(polygons),
        ]),
      ];
      for (final result in results) {
        final path = _elements(result, 'path').single;
        expect(result.hasCompletePreview, isTrue);
        expect(
          path.getAttribute('d'),
          'M-10 -10L100 -10L100 90L-10 90ZM20 20L70 20L70 60L20 60Z',
        );
        expect(
          path.getAttribute('fill-rule'),
          mode == 1 ? 'evenodd' : 'nonzero',
        );
        expect(path.getAttribute('fill'), '#FFFFFF');
      }
    }
  });

  test(
    'EMF multi-polylines stay separate and preserve the drawing position',
    () {
      for (final type in [7, 90]) {
        final result = _emf([
          _emfInts(27, [3, 4]),
          _emfMultiPoly(type, [
            [(-5, -6), (10, 20)],
            [(30, 40), (50, 60), (70, 80)],
          ]),
          _emfInts(54, [9, 10]),
        ]);
        final paths = _elements(result, 'path');
        expect(paths.map((path) => path.getAttribute('d')), [
          'M-5 -6L10 20M30 40L50 60L70 80',
          'M3 4L9 10',
        ]);
        expect(paths.first.getAttribute('fill'), 'none');
      }
    },
  );

  test('compound polygon counts validate every extent and total', () {
    for (final record in [
      _emfInts(8, [0, 0, 0, 0, 0xffffffff, 0]),
      _emfInts(91, [0, 0, 0, 0, 2, 4, 4]),
      _emfInts(7, [0, 0, 0, 0, 1, 3, 2, 0, 0, 10, 10]),
      _emfInts(8, [0, 0, 0, 0, 1, 2, 2, 0, 0]),
      _emfMultiPoly(90, [
        [(0, 0)],
      ]),
    ]) {
      expect(() => _emf([record]), throwsFormatException);
    }
    for (final record in [
      _wmfInts(0x0538, [65535]),
      _wmfInts(0x0538, [1, 65535]),
      _wmfMultiPoly([
        [(0, 0)],
      ]),
      _wmfInts(0x0538, [1, 2, 0, 0]),
    ]) {
      expect(() => _wmf([record]), throwsFormatException);
    }
  });

  test('compound points share the global preview budget', () {
    final record = _emfMultiPoly(91, [List.filled(50000, (1, 1))]);
    expect(
      () => _emf([
        record,
        record,
        _emfMultiPoly(91, [
          [(0, 0), (1, 1)],
        ]),
      ]),
      throwsFormatException,
    );
    final constrained = _emf([
      _emfMultiPoly(8, [List.filled(16385, (1, 1))]),
    ]);
    expect(constrained.previewSvg, isNull);
    expect(constrained.unsupportedPreviewRecords, [8]);
    expect(constrained.nativeEmbeddingAllowed, isTrue);
  });

  test(
    'EMF emits generated rectangles, ellipses, polygons and cubic curves',
    () {
      final result = _emf([
        _emfInts(38, [1, 0, 2, 0, 0x000000ff]),
        _emfInts(39, [2, 0, 0x00ff0000, 0]),
        _emfInts(37, [1]),
        _emfInts(37, [2]),
        _emfInts(43, [10, 20, 70, 60]),
        _emfInts(42, [20, 30, 100, 70]),
        _emfInts(3, [0, 0, 100, 100, 3, 0, 0, 100, 0, 50, 100]),
        _emfInts(2, [0, 0, 100, 100, 4, 0, 0, 10, 20, 30, 40, 50, 60]),
      ]);
      expect(result.hasCompletePreview, isTrue);
      final rect = _elements(result, 'rect').single;
      expect(rect.getAttribute('x'), '10');
      expect(rect.getAttribute('width'), '60');
      expect(rect.getAttribute('stroke'), '#FF0000');
      expect(rect.getAttribute('fill'), '#0000FF');
      expect(_elements(result, 'ellipse').single.getAttribute('rx'), '40');
      expect(
        _elements(result, 'path').first.getAttribute('d'),
        'M0 0L100 0L50 100Z',
      );
      expect(
        _elements(result, 'path').last.getAttribute('d'),
        'M0 0C10 20 30 40 50 60 ',
      );
      expect(result.previewSvg, isNot(contains('href=')));
    },
  );

  test('WMF follows parameter order and lowest free object handles', () {
    final result = _wmf([
      wmfRecord(0x2fa, [
        ...wordU16(0),
        ...wordU16(3),
        ...wordU16(0),
        ...wordU32(0x0000ff00),
      ]),
      wmfRecord(0x2fc, [...wordU16(0), ...wordU32(0x000000ff), ...wordU16(0)]),
      _wmfInts(0x12d, [0]),
      _wmfInts(0x12d, [1]),
      _wmfInts(0x61c, [12, 16, 90, 180, 10, 20]),
      _wmfInts(0x214, [5, 7]),
      _wmfInts(0x213, [40, 80]),
      _wmfInts(0x324, [3, 0, 0, 80, 0, 40, 80]),
    ]);
    final rect = _elements(result, 'rect').single;
    expect(rect.getAttribute('x'), '20');
    expect(rect.getAttribute('y'), '10');
    expect(rect.getAttribute('width'), '160');
    expect(rect.getAttribute('rx'), '8');
    expect(rect.getAttribute('ry'), '6');
    expect(rect.getAttribute('stroke'), '#00FF00');
    expect(rect.getAttribute('fill'), '#FF0000');
    expect(_elements(result, 'path').first.getAttribute('d'), 'M7 5L80 40');
    expect(
      _elements(result, 'path').last.getAttribute('d'),
      'M0 0L80 0L40 80Z',
    );
  });

  test('WMF selection does not invent EMF-style stock-object handles', () {
    for (final value in [0x8000, 0x8004, 0x8008]) {
      expect(
        () => _wmf([
          _wmfInts(0x012d, [value]),
        ]),
        throwsFormatException,
      );
    }
  });

  test(
    'EMF preserves signed 16-bit paths and current position for poly-to',
    () {
      final result = _emf([
        _emfInts(27, [10, 20]),
        emfRecord(89, [
          ...List.filled(16, 0),
          ...wordU32(2),
          ...wordU16(-2),
          ...wordU16(-3),
          ...wordU16(40),
          ...wordU16(50),
        ]),
        _emfInts(54, [60, 70]),
      ]);
      expect(_elements(result, 'path').map((p) => p.getAttribute('d')), [
        'M10 20L-2 -3L40 50',
        'M40 50L60 70',
      ]);
    },
  );

  test('window/viewport mapping and SaveDC/RestoreDC preserve state', () {
    final result = _emf([
      _emfInts(17, [8]),
      _emfInts(9, [100, 50]),
      _emfInts(11, [200, -100]),
      _emfInts(10, [10, 20]),
      _emfInts(12, [5, 6]),
      emfRecord(33, []),
      _emfInts(12, [50, 60]),
      _emfInts(43, [0, 0, 10, 20]),
      _emfInts(34, [-1]),
      _emfInts(43, [0, 0, 10, 20]),
    ]);
    expect(_elements(result, 'rect').map((r) => r.getAttribute('transform')), [
      'matrix(2 0 0 -2 30 100)',
      'matrix(2 0 0 -2 -15 46)',
    ]);
  });

  test('affine multiplication follows the documented column matrix', () {
    for (final (mode, expected) in [
      (1, 'matrix(1 0 0 1 0 0)'),
      (2, 'matrix(2 0 0 3 20 60)'),
      (3, 'matrix(2 0 0 3 10 20)'),
      (4, 'matrix(2 0 0 3 0 0)'),
    ]) {
      final result = _emf([
        _transform(35, [1, 0, 0, 1, 10, 20]),
        _transform(36, [2, 0, 0, 3, 0, 0], mode),
        _emfInts(43, [0, 0, 10, 10]),
      ]);
      expect(
        _elements(result, 'rect').single.getAttribute('transform'),
        expected,
      );
    }
  });

  test(
    'unknown/state-dependent records never become a misleading partial SVG',
    () {
      for (final type in [30, 70, 84, 105]) {
        final result = _emf([
          _emfInts(43, [0, 0, 20, 20]),
          emfRecord(type, [60, 115, 118, 103]),
        ]);
        expect(result.previewSvg, isNull);
        expect(result.unsupportedPreviewRecords, [type]);
        expect(result.nativeEmbeddingAllowed, type != 105);
      }
      expect(
        _emf([
          _emfInts(39, [1, 2, 0, 0]),
        ]).previewSvg,
        isNull,
      );
      expect(
        _emf([
          _emfInts(37, [0x80000001]),
        ]).previewSvg,
        isNull,
      );
      expect(
        _emf([
          _emfInts(20, [6]),
        ]).previewSvg,
        isNull,
      );
      expect(
        _wmf([
          _wmfInts(0x103, [7]),
        ]).previewSvg,
        isNull,
      );
    },
  );

  test(
    'rejects malformed point arrays before allocating their claimed count',
    () {
      for (final type in [2, 3, 4, 85, 86, 89]) {
        expect(
          () => _emf([
            _emfInts(type, [0, 0, 0, 0, 0xffffffff]),
          ]),
          throwsFormatException,
        );
      }
      expect(
        () => _wmf([
          _wmfInts(0x324, [65535, 0, 0]),
        ]),
        throwsFormatException,
      );
    },
  );

  test('bounds state stack, handles, affine values and generated SVG', () {
    expect(
      () => _emf(List.generate(65, (_) => emfRecord(33, []))),
      throwsFormatException,
    );
    expect(
      () => _emf([
        _emfInts(34, [-1]),
      ]),
      throwsFormatException,
    );
    expect(
      () => _emf([
        _emfInts(37, [15]),
      ]),
      throwsFormatException,
    );
    expect(
      () => _emf([
        _emfInts(38, [16, 0, 1, 0, 0]),
      ]),
      throwsFormatException,
    );
    expect(
      () => _emf([
        _transform(35, [double.nan, 0, 0, 1, 0, 0]),
      ]),
      throwsFormatException,
    );
    expect(
      () => parseLegacyWordMetafile(
        emfFixture(),
        format: LegacyWordImageFormat.emf,
        maxPreviewCharacters: 5,
      ),
      throwsFormatException,
    );
  });

  test('object deletion and recreation keep handle identity', () {
    final result = _emf([
      _emfInts(38, [1, 0, 1, 0, 0xff]),
      _emfInts(37, [1]),
      _emfInts(43, [0, 0, 10, 10]),
      _emfInts(37, [0x80000007]),
      _emfInts(40, [1]),
      _emfInts(38, [1, 0, 1, 0, 0xff0000]),
      _emfInts(43, [0, 0, 10, 10]),
      _emfInts(37, [1]),
      _emfInts(43, [0, 0, 10, 10]),
    ]);
    expect(_elements(result, 'rect').map((r) => r.getAttribute('stroke')), [
      '#FF0000',
      '#000000',
      '#0000FF',
    ]);
    expect(
      () => _emf([
        _emfInts(38, [1, 0, 1, 0, 0]),
        _emfInts(37, [1]),
        _emfInts(40, [1]),
      ]),
      throwsFormatException,
    );
    expect(
      () => _emf([
        _emfInts(38, [1, 0, 1, 0, 0]),
        _emfInts(38, [1, 0, 1, 0, 0]),
      ]),
      throwsFormatException,
    );
  });

  test(
    'unframed standalone WMF needs caller bounds, placeable WMF carries them',
    () {
      expect(
        parseLegacyWordMetafile(
          wmfFixture(),
          format: LegacyWordImageFormat.wmf,
        ).previewSvg,
        isNull,
      );
      final info = parseLegacyWordMetafile(
        wmfFixture(placeable: true),
        format: LegacyWordImageFormat.wmf,
      );
      expect(info.previewSvg, contains('viewBox="0 0 200 100"'));
    },
  );
}
