// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/legacy_word_ink.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('test/fixtures/ink_wpf');
  final sources =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.isf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('independent WPF nonempty source inventory is complete', () {
    expect(sources, hasLength(24));
  });
  for (final source in sources) {
    test('WPF stroke semantics: ${source.path}', () {
      final bytes = source.readAsBytesSync(), before = source.readAsBytesSync();
      final result = decodeLegacyWordInk(bytes);
      expect(
        result.status,
        LegacyWordInkDecodeStatus.decoded,
        reason: result.reason,
      );
      final snapshotPath = source.path.endsWith('.roundtrip.isf')
          ? source.path.replaceFirst('.roundtrip.isf', '.second-reloaded.json')
          : source.path.replaceFirst('.isf', '.reloaded.json');
      final expected =
          jsonDecode(File(snapshotPath).readAsStringSync())
              as Map<String, dynamic>;
      final strokes = expected['strokes'] as List;
      expect(result.strokes, hasLength(strokes.length));
      for (var i = 0; i < strokes.length; i++) {
        final actual = result.strokes[i], oracle = strokes[i] as Map;
        final attributes = oracle['attributes'] as Map;
        expect(
          actual.colorRgb,
          (attributes['colorArgb'] as String).substring(3),
        );
        expect(
          actual.alpha,
          int.parse(
            (attributes['colorArgb'] as String).substring(1, 3),
            radix: 16,
          ),
        );
        expect(
          actual.widthHimetric,
          closeTo(attributes['widthHimetric'] as num, 1e-9),
        );
        expect(
          actual.heightHimetric,
          closeTo(attributes['heightHimetric'] as num, 1e-9),
        );
        expect(actual.fitToCurve, attributes['fitToCurve']);
        expect(actual.ignorePressure, attributes['ignorePressure']);
        expect(actual.isHighlighter, attributes['isHighlighter']);
        expect(actual.rectangleTip, attributes['stylusTip'] == 'Rectangle');
        final points = oracle['points'] as List;
        expect(actual.points, hasLength(points.length));
        for (var j = 0; j < points.length; j++) {
          final point = actual.points[j], expectedPoint = points[j] as Map;
          expect(
            point.xHimetric,
            closeTo(expectedPoint['himetricX'] as num, 1e-9),
          );
          expect(
            point.yHimetric,
            closeTo(expectedPoint['himetricY'] as num, 1e-9),
          );
          expect(
            point.pressureFactor,
            closeTo(expectedPoint['pressureFactor'] as num, 1e-7),
          );
          if (point.normalPressure != null) {
            expect(
              point.normalPressure,
              expectedPoint['pressurePropertyValue'],
            );
          }
        }
      }
      expect(bytes, orderedEquals(before));
    });
  }
  test('valid empty ISF is distinct from a nonempty stroke', () {
    final result = decodeLegacyWordInk(Uint8List.fromList([0, 0]));
    expect(result.status, LegacyWordInkDecodeStatus.decoded);
    expect(result.strokes, isEmpty);
  });

  test('every truncated original fails before exposing partial strokes', () {
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
  test('unknown trailing record cannot turn partial strokes into success', () {
    final bytes = File(
      'test/fixtures/ink_wpf/single-dot/uncompressed.isf',
    ).readAsBytesSync();
    final result = decodeLegacyWordInk(_frame([...bytes.skip(2), 49]));
    expect(result.status, LegacyWordInkDecodeStatus.unsupported);
    expect(result.strokes, isEmpty);
    expect(result.pointCount, 0);
  });
  test(
    'unsupported transform and compression retain distinct inert status',
    () {
      expect(
        decodeLegacyWordInk(_frame([17, 0, 0, 0, 64])).status,
        LegacyWordInkDecodeStatus.unsupported,
      );
      expect(
        decodeLegacyWordInk(_frame([10, 5, 1, 0x40, 0, 1, 0])).status,
        LegacyWordInkDecodeStatus.unsupported,
      );
    },
  );
  test(
    'bounded integer, block, empty stroke and table references fail closed',
    () {
      final cases = <List<int>>[
        [0, 0, 1],
        [0, 0xff, 0xff, 0xff, 0xff, 0x10],
        [0, 0x80, 0x80, 0x80, 0x80, 0x80, 0],
        _frame([10, 1, 0]),
        _frame([2, 0]),
        _frame([4, 0]),
        _frame([5, 0]),
        _frame([9, 0]),
        _frame([13, 0]),
        _frame([31, 0]),
        _frame([10, 5, 1, 32, 0, 1, 0]),
      ];
      for (final bytes in cases) {
        final result = decodeLegacyWordInk(Uint8List.fromList(bytes));
        expect(
          result.status,
          LegacyWordInkDecodeStatus.invalid,
          reason: '$bytes: ${result.reason}',
        );
        expect(result.strokes, isEmpty);
      }
    },
  );
  test('declared point/byte budgets are checked before allocation', () {
    final count = _varint(100001);
    final result = decodeLegacyWordInk(_frame([10, count.length, ...count]));
    expect(result.status, LegacyWordInkDecodeStatus.limitExceeded);
    expect(result.strokes, isEmpty);
    expect(
      decodeLegacyWordInk(Uint8List(16 * 1024 * 1024 + 1)).status,
      LegacyWordInkDecodeStatus.limitExceeded,
    );
  });
  test('all eight specified Huffman tables decode a signed first delta', () {
    // A unary prefix 10 selects category1; its zero offset/sign means +1.
    // This independently written tiny code exercises every fixed table's
    // category width, while the WPF files cover real multi-packet encodings.
    for (var index = 0; index < 8; index++) {
      final width = [1, 1, 1, 2, 3, 4, 6, 7][index];
      final x = _pack('10${'0' * width}');
      final payload = [1, 0x80 + index, ...x, 0x80 + index, 0];
      final result = decodeLegacyWordInk(
        _frame([10, payload.length, ...payload]),
      );
      expect(
        result.status,
        LegacyWordInkDecodeStatus.decoded,
        reason: result.reason,
      );
      expect(result.strokes.single.points.single.xHimetric, 1);
      expect(result.strokes.single.points.single.yHimetric, 0);
    }
  });
  test(
    'Gorilla sign extension and delta-delta have exact channel boundaries',
    () {
      // x: initial signed deltas -1,+3; then +1 => coordinates -1,+1,+4.
      // y: three independent signed four-bit values -8,0,+7.
      final payload = [3, 0x24, 3, 6, 0x10, 4, 0x80, 0x70];
      final result = decodeLegacyWordInk(
        _frame([10, payload.length, ...payload]),
      );
      expect(
        result.status,
        LegacyWordInkDecodeStatus.decoded,
        reason: result.reason,
      );
      expect(result.strokes.single.points.map((point) => point.xHimetric), [
        -1,
        1,
        4,
      ]);
      expect(result.strokes.single.points.map((point) => point.yHimetric), [
        -8,
        0,
        7,
      ]);
    },
  );
  test('a hostile Huffman prefix cannot recurse or read outside its block', () {
    final result = decodeLegacyWordInk(_frame([10, 5, 1, 0x80, 255, 255, 255]));
    expect(result.status, LegacyWordInkDecodeStatus.invalid);
    expect(result.strokes, isEmpty);
  });
  test('decoded collections and source snapshots stay immutable', () {
    final bytes = File(
      'test/fixtures/ink_wpf/single-dot/uncompressed.isf',
    ).readAsBytesSync();
    final result = decodeLegacyWordInk(bytes);
    expect(() => result.strokes.clear(), throwsUnsupportedError);
    expect(() => result.strokes.single.points.clear(), throwsUnsupportedError);
    bytes.fillRange(0, bytes.length, 0);
    expect(result.strokes.single.points.single.xHimetric, 1270);
  });
  test('single-byte damage always yields a bounded result', () {
    for (final source in sources.where(
      (file) => !file.path.contains('roundtrip'),
    )) {
      final original = source.readAsBytesSync();
      for (var index = 0; index < original.length; index++) {
        for (final value in [0, 127, 128, 255]) {
          final bytes = Uint8List.fromList(original)..[index] = value;
          final result = decodeLegacyWordInk(bytes);
          expect(result.status, isIn(LegacyWordInkDecodeStatus.values));
          if (result.status != LegacyWordInkDecodeStatus.decoded) {
            expect(result.strokes, isEmpty);
          }
          expect(result.pointCount, lessThanOrEqualTo(100000));
        }
      }
    }
  });
}

List<int> _varint(int value) {
  final result = <int>[];
  while (value > 127) {
    result.add((value & 127) | 128);
    value ~/= 128;
  }
  return [...result, value];
}

Uint8List _frame(List<int> body) =>
    Uint8List.fromList([0, ..._varint(body.length), ...body]);

List<int> _pack(String bits) {
  bits = bits.padRight((bits.length + 7) ~/ 8 * 8, '0');
  return [
    for (var i = 0; i < bits.length; i += 8)
      int.parse(bits.substring(i, i + 8), radix: 2),
  ];
}
