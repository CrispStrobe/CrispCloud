// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/legacy_word_ink.dart';
import 'package:test/test.dart';

import '../tool/ink_web_acceptance.dart';

void main() {
  final root = Directory('test/fixtures/ink_wpf_headers');
  final sources =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.isf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('32 independent Windows header cases retain native observations', () {
    final cases = [
      for (final source in sources)
        {
          'path': source.path,
          'base64': base64Encode(source.readAsBytesSync()),
          'expected': jsonDecode(
            File(
              '${source.parent.path}/${source.path.endsWith('/roundtrip.isf') ? 'second-reloaded.json' : 'reloaded.json'}',
            ).readAsStringSync(),
          ),
        },
    ];
    expect(verifyInkWebAcceptance(cases, headerCases: true), {
      'cases': 32,
      'strokes': 32,
      'points': 160,
      'specifiedMetricDifferences': 1,
    });
  });
  final controls =
      jsonDecode(File('${root.path}/controls.json').readAsStringSync()) as Map;
  for (final dynamic control in controls['cases'] as List) {
    test(
      'preserves original packets and source metrics: ${control['name']}',
      () {
        final bytes = File(
          '${root.path}/${control['inputPath']}',
        ).readAsBytesSync();
        final before = Uint8List.fromList(bytes);
        final result = decodeLegacyWordInk(bytes);
        expect(
          result.status,
          LegacyWordInkDecodeStatus.decoded,
          reason: result.reason,
        );
        final stroke = result.strokes.single;
        final packets = control['sourcePacketCoordinatesHimetric'] as List;
        expect(stroke.points.map((p) => [p.packetX, p.packetY]), packets);
        final pressure = control['rawPressurePackets'] as List?;
        expect(
          stroke.points.map((p) => p.normalPressure),
          pressure ?? List.filled(packets.length, null),
        );
        expect(
          stroke.pressureMetric.maximum,
          control['pressureMetric']['maximum'],
        );
        final transform = control['transform'] as Map?;
        expect(
          stroke.transform.doublePrecision,
          transform == null || transform['mode'] == 'float-and-double',
        );
        if (transform != null) {
          expect(stroke.transform.recordTag, transform['tag']);
          if (transform['tag'] == 20) {
            // The original conventional-translation hypothesis remains in the
            // fixture. ISF p12/p31 and actual WPF define a zero linear matrix.
            expect(
              stroke.points.map((p) => [p.xHimetric, p.yHimetric]),
              List.filled(packets.length, [100.0, -50.0]),
            );
          } else {
            expect(
              stroke.points.map((p) => [p.xHimetric, p.yHimetric]),
              control['sourceFormula']['points'],
            );
          }
        }
        expect(bytes, orderedEquals(before));
      },
    );
  }
  test(
    'compact metric retains its final present field despite native reload',
    () {
      final path = '${root.path}/pressure-explicit-0-2047';
      final before = decodeLegacyWordInk(
        File('$path/input.isf').readAsBytesSync(),
      );
      final after = decodeLegacyWordInk(
        File('$path/roundtrip.isf').readAsBytesSync(),
      );
      expect(after.status, LegacyWordInkDecodeStatus.decoded);
      expect(after.strokes.single.pressureMetric.maximum, 2047);
      expect(
        after.strokes.single.points.map((p) => p.pressureFactor),
        before.strokes.single.points.map((p) => p.pressureFactor),
      );
      final native = jsonDecode(
        File('$path/second-reloaded.json').readAsStringSync(),
      );
      expect(native['strokes'][0]['pressureMetric']['maximum'], 1023);
      expect(native['strokes'][0]['points'].last['pressureFactor'], 1);
      expect(after.strokes.single.points.last.pressureFactor, 1023 / 2047);
    },
  );
  test('transform and metric indices select immutable per-stroke state', () {
    final transformTable = [
      ..._transform(17, [2]),
      ..._transform(16, [1, 3, -2, 1, 7, -5]),
    ];
    final metricTable = [
      ..._sized(_metricEntry(2047)),
      ..._sized(_metricEntry(7)),
    ];
    final result = decodeLegacyWordInk(
      _frame([
        5,
        1,
        56,
        15,
        ..._sized(transformTable),
        24,
        ..._sized(metricTable),
        ..._stroke(3, 4, 6),
        23,
        1,
        26,
        1,
        ..._stroke(3, 4, 6),
        23,
        0,
        26,
        0,
        ..._stroke(3, 4, 6),
      ]),
    );
    expect(
      result.status,
      LegacyWordInkDecodeStatus.decoded,
      reason: result.reason,
    );
    expect(
      result.strokes.map(
        (s) => [s.points.single.xHimetric, s.points.single.yHimetric],
      ),
      [
        [6.0, 8.0],
        [2.0, 8.0],
        [6.0, 8.0],
      ],
    );
    expect(result.strokes.map((s) => s.points.single.pressureFactor), [
      6 / 2047,
      6 / 7,
      6 / 2047,
    ]);
  });
  test('matching doubles retain source precision beyond float rounding', () {
    final value = 1.0000000001;
    final result = decodeLegacyWordInk(
      _frame([
        ..._transform(17, [value]),
        31,
        ..._sized(_transform(17, [value], wide: true)),
        ..._stroke(3, 4),
      ]),
    );
    expect(
      result.status,
      LegacyWordInkDecodeStatus.decoded,
      reason: result.reason,
    );
    expect(result.strokes.single.transform.m11, value);
    expect(result.strokes.single.points.single.xHimetric, 3 * value);
  });
  test('pressure prefixes inherit only omitted fields', () {
    for (final entry in [
      <int>[],
      [0],
      [0, ..._signed(2047)],
      [0, ..._signed(2047), 0],
      [
        0,
        ..._signed(2047),
        0,
        ..._reals([1]),
      ],
    ]) {
      final result = decodeLegacyWordInk(
        _frame([
          5,
          1,
          56,
          25,
          ..._sized([56, ..._sized(entry)]),
          ..._stroke(1, 2, 7),
        ]),
      );
      expect(
        result.status,
        LegacyWordInkDecodeStatus.decoded,
        reason: result.reason,
      );
      expect(
        result.strokes.single.pressureMetric.maximum,
        entry.length < 2 ? 1023 : 2047,
      );
    }
  });
  test('bad extents, indices, values and incomplete overrides fail closed', () {
    final invalid = <List<int>>[
      [15, 0],
      [24, 0],
      [23, 0],
      [26, 0],
      [
        ..._transform(17, [0]),
      ],
      [
        ..._transform(18, [2, 0]),
      ],
      [
        ..._transform(17, [double.nan]),
      ],
      [25, ..._sized(_metricEntry(0))],
      [
        25,
        ..._sized([
          56,
          ..._sized([0, 2, 0, 0]),
        ]),
      ],
      [
        ..._transform(17, [1]),
        31,
        0,
      ],
      [
        ..._transform(17, [1]),
        31,
        ..._sized([
          ..._transform(17, [1], wide: true),
          0,
        ]),
      ],
      [5, 1, 56, 25, ..._sized(_metricEntry(7)), ..._stroke(1, 2, 8)],
    ];
    for (final body in invalid) {
      final result = decodeLegacyWordInk(_frame(body));
      expect(
        result.status,
        LegacyWordInkDecodeStatus.invalid,
        reason: '${result.reason}: $body',
      );
      expect(result.strokes, isEmpty);
    }
  });
  test('unqualified transforms, metrics and late mutations remain inert', () {
    final unsupported = <List<int>>[
      [19, 0],
      [
        ..._transform(17, [1]),
        31,
        ..._sized(_transform(17, [2], wide: true)),
      ],
      [
        25,
        ..._sized([50, 0]),
      ],
      [
        25,
        ..._sized([
          56,
          ..._sized([2, ..._signed(2047)]),
        ]),
      ],
      [
        25,
        ..._sized([
          56,
          ..._sized([0, ..._signed(2047), 1]),
        ]),
      ],
      [
        25,
        ..._sized([
          56,
          ..._sized([
            0,
            ..._signed(2047),
            0,
            ..._reals([2]),
          ]),
        ]),
      ],
      [
        25,
        ..._sized([..._metricEntry(2047), ..._metricEntry(7)]),
      ],
      [
        ..._stroke(1, 2),
        ..._transform(17, [1]),
      ],
      [..._stroke(1, 2), 25, 0],
      [
        ..._transform(17, [1]),
        ..._stroke(1, 2),
        31,
        ..._sized(_transform(17, [1], wide: true)),
      ],
    ];
    for (final body in unsupported) {
      final result = decodeLegacyWordInk(_frame(body));
      expect(
        result.status,
        LegacyWordInkDecodeStatus.unsupported,
        reason: '${result.reason}: $body',
      );
      expect(result.strokes, isEmpty);
    }
  });
  test('transform and metric budgets are checked before growing tables', () {
    for (final body in [
      _transform(17, [1000001]),
      [
        15,
        ..._sized([
          for (var i = 0; i < 513; i++) ..._transform(17, [1]),
        ]),
      ],
      [24, ..._sized(List.filled(513, 0))],
    ]) {
      final result = decodeLegacyWordInk(_frame(body));
      expect(
        result.status,
        LegacyWordInkDecodeStatus.limitExceeded,
        reason: result.reason,
      );
      expect(result.strokes, isEmpty);
    }
  });
  test('all header corpus truncations reject before exposing strokes', () {
    for (final source in sources) {
      final bytes = source.readAsBytesSync();
      for (var end = 0; end < bytes.length; end++) {
        final result = decodeLegacyWordInk(
          Uint8List.sublistView(bytes, 0, end),
        );
        expect(
          result.status,
          LegacyWordInkDecodeStatus.invalid,
          reason: '${source.path}: $end',
        );
        expect(result.strokes, isEmpty);
      }
    }
  });
}

List<int> _varint(int value) {
  final result = <int>[];
  while (value >= 128) {
    result.add(value % 128 + 128);
    value ~/= 128;
  }
  return [...result, value];
}

List<int> _signed(int value) => _varint(value.abs() * 2 + (value < 0 ? 1 : 0));
List<int> _sized(List<int> value) => [..._varint(value.length), ...value];
Uint8List _frame(List<int> value) => Uint8List.fromList([0, ..._sized(value)]);
List<int> _reals(List<double> values, {bool wide = false}) {
  final bytes = ByteData(values.length * (wide ? 8 : 4));
  for (var i = 0; i < values.length; i++) {
    if (wide) {
      bytes.setFloat64(i * 8, values[i], Endian.little);
    } else {
      bytes.setFloat32(i * 4, values[i], Endian.little);
    }
  }
  return bytes.buffer.asUint8List();
}

List<int> _transform(int tag, List<double> values, {bool wide = false}) => [
  tag,
  ..._reals(values, wide: wide),
];
List<int> _metricEntry(int maximum) => [
  56,
  ..._sized([0, ..._signed(maximum)]),
];
List<int> _stroke(int x, int y, [int? pressure]) => [
  10,
  ..._sized([
    1,
    8,
    x & 255,
    8,
    y & 255,
    if (pressure != null) ...[8, pressure & 255],
  ]),
];
