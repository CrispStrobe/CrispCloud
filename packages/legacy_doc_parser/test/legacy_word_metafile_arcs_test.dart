// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/metafile_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _emr(int type, List<int> operands) =>
    emfRecord(type, [for (final value in operands) ...wordU32(value)]);
Uint8List _meta(int type, List<int> operands) =>
    wmfRecord(type, [for (final value in operands) ...wordU16(value)]);

LegacyWordMetafileInfo _emf(List<Uint8List> records) => parseLegacyWordMetafile(
  emfFixture(records: records),
  format: LegacyWordImageFormat.emf,
);
LegacyWordMetafileInfo _wmf(List<Uint8List> records) => parseLegacyWordMetafile(
  wmfFixture(records: records, placeable: true),
  format: LegacyWordImageFormat.wmf,
);

List<XmlElement> _paths(LegacyWordMetafileInfo value) =>
    XmlDocument.parse(value.previewSvg!).findAllElements('path').toList();

void main() {
  test('EMF and WMF project radials onto the eccentric ellipse', () {
    // Radius 80 horizontally, 40 vertically. The radial endpoints are well
    // outside the ellipse, so treating source inputs as arc endpoints fails.
    for (final info in [
      _emf([
        _emr(45, [20, 10, 180, 90, 420, 50, 100, -110]),
      ]),
      _wmf([
        _meta(0x0817, [-110, 100, 50, 420, 90, 180, 10, 20]),
      ]),
    ]) {
      expect(info.hasCompletePreview, isTrue);
      expect(info.nativeEmbeddingAllowed, isTrue);
      final path = _paths(info).single;
      expect(path.getAttribute('d'), 'M180 50A80 40 0 0 0 100 10');
      expect(path.getAttribute('fill'), 'none');
      expect(path.getAttribute('stroke'), '#000000');
    }
  });

  test('oblique radial projection uses both ellipse radii', () {
    final path = _paths(
      _emf([
        _emr(45, [-80, -40, 80, 40, 60, 20, -60, -20]),
      ]),
    ).single;
    // (60,20) maps to (66.564024,22.188008), not the angle-only circular
    // approximation (75.894664,12.649111).
    expect(
      path.getAttribute('d'),
      'M66.564024 22.188008A80 40 0 0 0 -66.564024 -22.188008',
    );
  });

  test('arc direction survives SaveDC and RestoreDC', () {
    final info = _emf([
      _emr(57, [2]),
      emfRecord(33, []),
      _emr(57, [1]),
      _emr(45, [20, 10, 180, 90, 420, 50, 100, -110]),
      _emr(34, [-1]),
      _emr(45, [20, 10, 180, 90, 420, 50, 100, -110]),
    ]);
    expect(_paths(info).map((path) => path.getAttribute('d')), [
      'M180 50A80 40 0 0 0 100 10',
      'M180 50A80 40 0 1 1 100 10',
    ]);
  });

  test('direction distinguishes small and large sweeps across angle wrap', () {
    for (final (direction, expected) in [
      (1, 'M100 10A80 40 0 1 0 180 50'),
      (2, 'M100 10A80 40 0 0 1 180 50'),
    ]) {
      final info = _emf([
        _emr(57, [direction]),
        _emr(45, [20, 10, 180, 90, 100, -110, 420, 50]),
      ]);
      expect(_paths(info).single.getAttribute('d'), expected);
    }
  });

  test('closed chords and pies retain different closure and brush paint', () {
    for (final (emr, meta, suffix) in [
      (46, 0x0830, 'Z'),
      (47, 0x081a, 'L100 50Z'),
    ]) {
      final results = [
        _emf([
          _emr(39, [1, 0, 0x00332211, 0]),
          _emr(37, [1]),
          _emr(emr, [20, 10, 180, 90, 420, 50, 100, -110]),
        ]),
        _wmf([
          wmfRecord(0x02fc, [
            ...wordU16(0),
            ...wordU32(0x00332211),
            ...wordU16(0),
          ]),
          _meta(0x012d, [0]),
          _meta(meta, [-110, 100, 50, 420, 90, 180, 10, 20]),
        ]),
      ];
      for (final result in results) {
        final path = _paths(result).single;
        expect(path.getAttribute('d'), 'M180 50A80 40 0 0 0 100 10$suffix');
        expect(path.getAttribute('fill'), '#112233');
      }
    }
  });

  test('identical arc/chord radials produce a full ellipse with two arcs', () {
    for (final (emr, meta, suffix) in [(45, 0x0817, ''), (46, 0x0830, 'Z')]) {
      for (final result in [
        _emf([
          _emr(emr, [20, 10, 180, 90, 420, 50, 420, 50]),
        ]),
        _wmf([
          _meta(meta, [50, 420, 50, 420, 90, 180, 10, 20]),
        ]),
      ]) {
        expect(
          _paths(result).single.getAttribute('d'),
          'M180 50A80 40 0 0 0 20 50A80 40 0 0 0 180 50$suffix',
        );
      }
    }
  });

  test('ordinary arcs and closed curves never change the current point', () {
    for (final type in [45, 46, 47]) {
      final result = _emf([
        _emr(27, [3, 4]),
        _emr(type, [20, 10, 180, 90, 420, 50, 100, -110]),
        _emr(54, [6, 7]),
      ]);
      expect(_paths(result).last.getAttribute('d'), 'M3 4L6 7');
    }
    for (final type in [0x0817, 0x081a, 0x0830]) {
      final result = _wmf([
        _meta(0x0214, [4, 3]),
        _meta(type, [-110, 100, 50, 420, 90, 180, 10, 20]),
        _meta(0x0213, [7, 6]),
      ]);
      expect(_paths(result).last.getAttribute('d'), 'M3 4L6 7');
    }
  });

  test('ArcTo joins from current point and retains the projected endpoint', () {
    final result = _emf([
      _emr(27, [3, 4]),
      _emr(55, [20, 10, 180, 90, 420, 50, 100, -110]),
      _emr(54, [6, 7]),
    ]);
    expect(_paths(result).map((path) => path.getAttribute('d')), [
      'M3 4L180 50A80 40 0 0 0 100 10',
      'M100 10L6 7',
    ]);
    expect(_paths(result).first.getAttribute('fill'), 'none');
  });

  test('arcs retain affine transforms and selected null paint', () {
    final transform = Uint8List(24);
    final data = ByteData.sublistView(transform);
    const matrix = [2.0, 0.5, 1.0, -3.0, 7.0, 8.0];
    for (var i = 0; i < matrix.length; i++) {
      data.setFloat32(4 * i, matrix[i], Endian.little);
    }
    final result = _emf([
      emfRecord(35, transform),
      _emr(37, [0x80000005]),
      _emr(37, [0x80000008]),
      _emr(47, [20, 10, 180, 90, 420, 50, 100, -110]),
    ]);
    final path = _paths(result).single;
    expect(path.getAttribute('d'), 'M180 50A80 40 0 0 0 100 10L100 50Z');
    expect(path.getAttribute('transform'), 'matrix(2 0.5 1 -3 7 8)');
    expect(path.getAttribute('fill'), 'none');
    expect(path.getAttribute('stroke'), 'none');
  });

  test('invalid arc directions and truncated records fail their extents', () {
    for (final direction in [0, 3, 0xffffffff]) {
      expect(
        () => _emf([
          _emr(57, [direction]),
        ]),
        throwsFormatException,
      );
    }
    expect(() => _emf([emfRecord(57, [])]), throwsFormatException);
    for (final type in [45, 46, 47, 55]) {
      for (var length = 0; length < 8; length++) {
        expect(
          () => _emf([_emr(type, List.filled(length, 0))]),
          throwsFormatException,
        );
      }
    }
    for (final type in [0x0817, 0x081a, 0x0830]) {
      for (var length = 0; length < 8; length++) {
        expect(
          () => _wmf([_meta(type, List.filled(length, 0))]),
          throwsFormatException,
        );
      }
    }
  });

  test('ambiguous arc geometry does not produce a partial preview', () {
    for (final geometry in [
      [20, 10, 20, 90, 420, 50, 100, -110],
      [20, 90, 180, 10, 420, 50, 100, -110],
      [20, 10, 180, 90, 100, 50, 100, -110],
      [20, 10, 180, 90, 420, 50, 100, 50],
      [20, 10, 180, 90, 420, 50, 740, 50],
    ]) {
      final result = _emf([
        _emr(43, [0, 0, 10, 10]),
        _emr(45, geometry),
      ]);
      expect(result.previewSvg, isNull);
      expect(result.unsupportedPreviewRecords, [45]);
      expect(result.nativeEmbeddingAllowed, isTrue);
    }
  });

  test(
    'coincident pie radials retain native bytes without guessing outlines',
    () {
      for (final result in [
        _emf([
          _emr(47, [20, 10, 180, 90, 420, 50, 420, 50]),
        ]),
        _wmf([
          _meta(0x081a, [50, 420, 50, 420, 90, 180, 10, 20]),
        ]),
      ]) {
        expect(result.previewSvg, isNull);
        expect(result.nativeEmbeddingAllowed, isTrue);
      }
    },
  );

  test('arcs obey the generated SVG output budget', () {
    final source = emfFixture(
      records: [
        _emr(45, [20, 10, 180, 90, 420, 50, 100, -110]),
      ],
    );
    final complete = parseLegacyWordMetafile(
      source,
      format: LegacyWordImageFormat.emf,
    );
    expect(
      () => parseLegacyWordMetafile(
        source,
        format: LegacyWordImageFormat.emf,
        maxPreviewCharacters: complete.previewSvg!.length - 1,
      ),
      throwsFormatException,
    );
  });

  test('arc support does not authorize path brackets or unknown effects', () {
    final result = _emf([
      _emr(45, [20, 10, 180, 90, 420, 50, 100, -110]),
      emfRecord(59, []),
    ]);
    expect(result.previewSvg, isNull);
    expect(result.unsupportedPreviewRecords, [59]);
  });
}
