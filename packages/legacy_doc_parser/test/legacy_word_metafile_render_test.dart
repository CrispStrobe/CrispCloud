// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

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
Uint8List _transform(int type, List<double> values, [int? mode]) {
  final bytes = Uint8List(24);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return emfRecord(type, [...bytes, if (mode != null) ...wordU32(mode)]);
}

List<XmlElement> _elements(LegacyWordMetafileInfo result, String name) =>
    XmlDocument.parse(result.previewSvg!).findAllElements(name).toList();

void main() {
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
