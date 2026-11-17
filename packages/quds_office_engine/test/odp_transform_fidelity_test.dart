import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svgNs = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

final _stripedPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAHgAAAAoCAIAAAC6iKlyAAAAdElEQVR4nO3QQQ0AIBDAMMC/Z3AxHtcaWLJ91x97WPh8qQ5kdMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI48pJMDT5SKBXEAAAAASUVORK5CYII=',
);

Iterable<XmlElement> _elements(XmlElement root, String localName) sync* {
  if (root.localName == localName) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, localName);
  }
}

XmlElement _export(List<PmlShape> shapes) {
  final bytes = OdpPresentationWriter.writeBytes(
    PmlPresentation(slides: [PmlSlide(id: 1, shapes: shapes)]),
  );
  return XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
  ).root!;
}

PmlTransform _transform(int rotation) => PmlTransform(
  x: 60 * 12700,
  y: 80 * 12700,
  cx: 120 * 12700,
  cy: 40 * 12700,
  rot: rotation,
);

PmlShape _shape(int rotation) => PmlShape(
  id: 2,
  name: 'Rotation',
  transform: _transform(rotation),
  fillColor: 'FF0000',
  text: 'Rotation',
  textColor: '000000',
  fontSizePt: 12,
);

double _length(XmlElement frame, String name) {
  final raw = frame.getAttribute(name, namespaceUri: _svgNs)!;
  expect(raw, endsWith('pt'));
  return double.parse(raw.substring(0, raw.length - 2));
}

// Interpret the exported ODF affine operations independently of the writer's
// center/angle calculations. Expectations below are fixed geometric corners.
List<List<double>> _corners(XmlElement frame) {
  final x = _length(frame, 'x');
  final y = _length(frame, 'y');
  final width = _length(frame, 'width');
  final height = _length(frame, 'height');
  var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
  final transform = frame.getAttribute('transform', namespaceUri: _drawNs);
  if (transform != null) {
    final match = RegExp(
      r'^matrix\(([^)]+)\) translate\(([-\d.]+)pt ([-\d.]+)pt\)$',
    ).firstMatch(transform);
    expect(match, isNotNull, reason: 'An explicit unit-safe affine transform');
    final matrix = match!.group(1)!.split(' ').map(double.parse).toList();
    expect(matrix, hasLength(6));
    expect(matrix.every((value) => value.isFinite), isTrue);
    a = matrix[0];
    b = matrix[1];
    c = matrix[2];
    d = matrix[3];
    e = matrix[4] + double.parse(match.group(2)!);
    f = matrix[5] + double.parse(match.group(3)!);
  }
  return [
    for (final point in [
      [x, y],
      [x + width, y],
      [x + width, y + height],
      [x, y + height],
    ])
      [a * point[0] + c * point[1] + e, b * point[0] + d * point[1] + f],
  ];
}

void _expectCorners(XmlElement frame, List<List<double>> expected) {
  final actual = _corners(frame);
  for (var index = 0; index < expected.length; index++) {
    expect(actual[index][0], closeTo(expected[index][0], 0.00001));
    expect(actual[index][1], closeTo(expected[index][1], 0.00001));
  }
}

void main() {
  final quadrants = <int, List<List<double>>>{
    90: [
      [140, 40],
      [140, 160],
      [100, 160],
      [100, 40],
    ],
    180: [
      [180, 120],
      [60, 120],
      [60, 80],
      [180, 80],
    ],
    270: [
      [100, 160],
      [100, 40],
      [140, 40],
      [140, 160],
    ],
    -90: [
      [100, 160],
      [100, 40],
      [140, 40],
      [140, 160],
    ],
  };
  for (final entry in quadrants.entries) {
    test('rotates ${entry.key} degrees clockwise about a nonzero center', () {
      final root = _export([_shape(entry.key * 60000)]);
      _expectCorners(_elements(root, 'frame').single, entry.value);
    });
  }

  test('arbitrary positive rotation preserves the authored center', () {
    final root = _export([_shape(45 * 60000)]);
    _expectCorners(_elements(root, 'frame').single, [
      [91.7157287525381, 43.4314575050762],
      [176.568542494924, 128.284271247462],
      [148.284271247462, 156.568542494924],
      [63.4314575050762, 71.7157287525381],
    ]);
  });

  test('arbitrary negative rotation retains sign and center', () {
    final root = _export([_shape(-30 * 60000)]);
    _expectCorners(_elements(root, 'frame').single, [
      [58.0384757729337, 112.679491924311],
      [161.961524227066, 52.6794919243112],
      [181.961524227066, 87.3205080756888],
      [78.0384757729337, 147.320508075689],
    ]);
  });

  for (final degrees in [0, 360, -360, 720]) {
    test(
      '$degrees degrees keeps ordinary frame position without a transform',
      () {
        final frame = _elements(
          _export([_shape(degrees * 60000)]),
          'frame',
        ).single;
        expect(frame.getAttribute('transform', namespaceUri: _drawNs), isNull);
        _expectCorners(frame, [
          [60, 80],
          [180, 80],
          [180, 120],
          [60, 120],
        ]);
      },
    );
  }

  test(
    'equivalent large and wrapped angles share bounded transform values',
    () {
      final root = _export([
        _shape(30 * 60000),
        _shape(750 * 60000),
        _shape(-330 * 60000),
        _shape(1000000 * 360 * 60000 + 30 * 60000),
      ]);
      final frames = _elements(root, 'frame').toList();
      final value = frames.first.getAttribute(
        'transform',
        namespaceUri: _drawNs,
      );
      for (final frame in frames) {
        expect(frame.getAttribute('transform', namespaceUri: _drawNs), value);
        expect(
          _corners(frame).expand((point) => point).every((v) => v.isFinite),
          isTrue,
        );
      }
    },
  );

  test(
    'the smallest modeled rotation is retained instead of rounded to zero',
    () {
      final frame = _elements(_export([_shape(1)]), 'frame').single;
      final corners = _corners(frame);
      expect(corners.first[0], greaterThan(60));
      expect(corners.first[1], lessThan(80));
      expect(corners[2][0], lessThan(180));
      expect(corners[2][1], greaterThan(120));
    },
  );

  test(
    'negative origins and zero dimensions still produce finite geometry',
    () {
      final root = _export([
        PmlShape(
          id: 2,
          name: 'Edge',
          transform: const PmlTransform(
            x: -127000,
            y: 254000,
            cx: 0,
            cy: 0,
            rot: 2700000,
          ),
        ),
      ]);
      _expectCorners(_elements(root, 'frame').single, [
        [-10, 20],
        [-10, 20],
        [-10, 20],
        [-10, 20],
      ]);
    },
  );

  test(
    'picture frame uses the same transform without modifying embedded bytes',
    () {
      final image = _shape(90 * 60000)
        ..visual = OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: 'RGB direction',
          imageBytes: _stripedPng,
          width: 120,
          height: 40,
        );
      final before = List<int>.of(_stripedPng);
      final root = _export([image]);
      _expectCorners(_elements(root, 'frame').single, quadrants[90]!);
      expect(_elements(root, 'image'), hasLength(1));
      expect(_stripedPng, before);
      expect(image.transform.rot, 90 * 60000);
    },
  );

  test(
    'rotated table exports grouped cell frames without changing source cells',
    () {
      final cells = [
        PmlTableCell(text: 'R', fillColor: 'FF0000'),
        PmlTableCell(text: 'G', fillColor: '00FF00'),
        PmlTableCell(text: 'B', fillColor: '0000FF'),
      ];
      final table = PmlTable(rows: [cells], headerRow: false);
      final shape = _shape(90 * 60000)..table = table;
      final root = _export([shape]);
      final group = _elements(root, 'g').single;
      expect(group.getAttribute('name', namespaceUri: _drawNs), shape.name);
      expect(_elements(root, 'table'), isEmpty);
      final frames = _elements(root, 'frame').toList();
      expect(frames, hasLength(4));
      _expectCorners(frames.first, quadrants[90]!);
      expect(frames.skip(1).map((frame) => frame.text), ['R', 'G', 'B']);
      for (var index = 0; index < 3; index++) {
        final top = 40.0 + 40 * index;
        _expectCorners(frames[index + 1], [
          [140, top],
          [140, top + 40],
          [100, top + 40],
          [100, top],
        ]);
      }
      expect(identical(table.rows.single, cells), isTrue);
      expect(table.rows.single.map((cell) => cell.text), ['R', 'G', 'B']);
      expect(shape.transform.widthPoints, 120);
      expect(shape.transform.heightPoints, 40);
    },
  );

  test('rotated RTL table puts first logical cell at the physical right', () {
    final table = PmlTable(
      rightToLeft: true,
      rows: [
        [
          PmlTableCell(text: 'R', fillColor: 'FF0000', textColor: '123456'),
          PmlTableCell(text: 'G', fillColor: '00FF00', textColor: '654321'),
          PmlTableCell(text: 'B', fillColor: '0000FF'),
        ],
        [PmlTableCell(text: '  Tail\nLine\tEnd  ')],
      ],
    );
    final root = _export([_shape(90 * 60000)..table = table]);
    final frames = _elements(root, 'frame').toList();
    expect(frames, hasLength(5));
    _expectCorners(frames[1], [
      [140, 120],
      [140, 160],
      [120, 160],
      [120, 120],
    ]);
    _expectCorners(frames[4], [
      [120, 120],
      [120, 160],
      [100, 160],
      [100, 120],
    ]);
    final paragraphStyles = _elements(root, 'paragraph-properties').toList();
    expect(paragraphStyles, isNotEmpty);
    for (final properties in paragraphStyles) {
      expect(
        properties.getAttribute('writing-mode', namespaceUri: _styleNs),
        'rl-tb',
      );
    }
    expect(
      _elements(root, 'text-properties').map(
        (properties) => properties.getAttribute('color', namespaceUri: _foNs),
      ),
      containsAll(['#123456', '#654321', '#1a1a1a']),
    );
    expect(_elements(frames[4], 's'), hasLength(2));
    expect(_elements(frames[4], 'tab'), hasLength(1));
    expect(_elements(frames[4], 'p'), hasLength(2));
    expect(table.rows[0].map((cell) => cell.text), ['R', 'G', 'B']);
  });

  for (final degrees in [0, 360]) {
    test('table at $degrees degrees retains native editable structure', () {
      final root = _export([
        _shape(degrees * 60000)
          ..table = PmlTable(
            rows: [
              [PmlTableCell(text: 'Native')],
            ],
          ),
      ]);
      expect(_elements(root, 'table'), hasLength(1));
      expect(_elements(root, 'g'), isEmpty);
      expect(_elements(root, 'table-cell').single.text, 'Native');
    });
  }

  test('rotated table retains its authored outline above cell fills', () {
    final shape = _shape(90 * 60000)
      ..strokeColor = 'AA00CC'
      ..strokeWidth = 2.5
      ..table = PmlTable(
        rows: [
          [PmlTableCell(text: 'Cell', fillColor: 'FF0000')],
        ],
      );
    final root = _export([shape]);
    final frames = _elements(root, 'frame').toList();
    expect(frames, hasLength(3));
    final outline = frames.last;
    expect(
      outline.getAttribute('name', namespaceUri: _drawNs),
      '${shape.name} outline',
    );
    _expectCorners(outline, quadrants[90]!);
    final styleName = outline.getAttribute('style-name', namespaceUri: _drawNs);
    final properties = _elements(root, 'style')
        .singleWhere(
          (style) =>
              style.getAttribute('name', namespaceUri: _styleNs) == styleName,
        )
        .firstChild('graphic-properties', namespaceUri: _styleNs)!;
    expect(properties.getAttribute('fill', namespaceUri: _drawNs), 'none');
    expect(properties.getAttribute('stroke', namespaceUri: _drawNs), 'solid');
    expect(
      properties.getAttribute('stroke-color', namespaceUri: _svgNs),
      '#aa00cc',
    );
    expect(
      properties.getAttribute('stroke-width', namespaceUri: _svgNs),
      '2.50pt',
    );
    expect(
      properties.getAttribute('auto-grow-height', namespaceUri: _drawNs),
      'false',
    );
    expect(shape.strokeColor, 'AA00CC');
    expect(shape.strokeWidth, 2.5);
  });

  test(
    'empty rotated table exports one background and leaves the model empty',
    () {
      final table = PmlTable();
      final root = _export([_shape(90 * 60000)..table = table]);
      expect(_elements(root, 'frame'), hasLength(1));
      _expectCorners(_elements(root, 'frame').single, quadrants[90]!);
      expect(table.rows, isEmpty);
    },
  );

  test(
    'ragged rotated grids emit physical cells without expanding blank rows',
    () {
      final table = PmlTable(
        rows: [
          [
            for (var column = 0; column < 100; column++)
              PmlTableCell(text: '$column'),
          ],
          for (var row = 0; row < 50; row++) <PmlTableCell>[],
        ],
      );
      final root = _export([_shape(45 * 60000)..table = table]);
      expect(_elements(root, 'frame'), hasLength(101));
      expect(table.rows.length, 51);
      expect(table.rows.skip(1).every((row) => row.isEmpty), isTrue);
    },
  );

  test('fractional rotated cell sizes meet at their shared boundaries', () {
    final shape = _shape(90 * 60000)
      ..transform = const PmlTransform(
        x: 762000,
        y: 1016000,
        cx: 1282700,
        cy: 508000,
        rot: 5400000,
      )
      ..table = PmlTable(
        rows: [
          [
            PmlTableCell(text: 'A'),
            PmlTableCell(text: 'B'),
            PmlTableCell(text: 'C'),
          ],
        ],
      );
    final frames = _elements(_export([shape]), 'frame').skip(1).toList();
    for (var index = 0; index < 2; index++) {
      final left = _corners(frames[index]);
      final right = _corners(frames[index + 1]);
      expect(left[1][0], closeTo(right[0][0], 0.00001));
      expect(left[1][1], closeTo(right[0][1], 0.00001));
      expect(left[2][0], closeTo(right[3][0], 0.00001));
      expect(left[2][1], closeTo(right[3][1], 0.00001));
    }
  });

  test(
    'grouped model shapes keep independent authored centers and source values',
    () {
      final first = _shape(90 * 60000)..groupId = 17;
      final second = _shape(-90 * 60000)
        ..id = 3
        ..groupId = 17;
      final firstTransform = first.transform;
      final secondTransform = second.transform;
      final shapes = [first, second];
      final root = _export(shapes);
      final frames = _elements(root, 'frame').toList();
      _expectCorners(frames[0], quadrants[90]!);
      _expectCorners(frames[1], quadrants[-90]!);
      expect(identical(first.transform, firstTransform), isTrue);
      expect(identical(second.transform, secondTransform), isTrue);
      expect(shapes, [first, second]);
      expect(first.groupId, 17);
      expect(second.groupId, 17);
    },
  );
}
