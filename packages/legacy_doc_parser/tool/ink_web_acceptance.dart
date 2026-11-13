// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Executes the real decoder in compiled JavaScript against independently
/// captured WPF bytes and decoded JSON. The host only supplies fixture data.
Map<String, Object> verifyInkWebAcceptance(
  List<dynamic> cases, {
  bool headerCases = false,
}) {
  void require(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  var strokes = 0, points = 0, metricDifferences = 0;
  require(cases.length == (headerCases ? 32 : 24), 'Missing WPF source cases');
  final seenPaths = <String>{};
  for (final dynamic source in cases) {
    final path = source['path'] as String;
    require(seenPaths.add(path), 'Duplicate WPF source case');
    final bytes = base64Decode(source['base64'] as String);
    final decoded = decodeLegacyWordInk(bytes);
    final compactPressure =
        headerCases &&
        path ==
            'test/fixtures/ink_wpf_headers/pressure-explicit-0-2047/roundtrip.isf';
    if (compactPressure) {
      // Retain the observed WPF JSON unchanged. Its compact metric reader
      // drops the final present field; the ISF specification preserves it.
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      require(hex.contains('1905380300fe1f'), 'Missing literal 0..2047 metric');
      metricDifferences++;
    }
    require(
      decoded.status == LegacyWordInkDecodeStatus.decoded,
      '${source['path']}: ${decoded.reason}',
    );
    final expected = source['expected']['strokes'] as List;
    require(decoded.strokes.length == expected.length, 'Stroke count differs');
    strokes += decoded.strokes.length;
    for (var i = 0; i < expected.length; i++) {
      final actual = decoded.strokes[i];
      if (headerCases) {
        final metric = expected[i]['pressureMetric'] as Map;
        require(
          actual.pressureMetric.minimum == metric['minimum'] &&
              actual.pressureMetric.maximum ==
                  (compactPressure ? 2047 : metric['maximum']) &&
              actual.pressureMetric.unit == 0 &&
              metric['unit'] == 'None' &&
              actual.pressureMetric.resolution == metric['resolution'],
          'Ink pressure metric differs',
        );
        if (compactPressure) {
          require(
            metric['maximum'] == 1023,
            'Native metric observation changed',
          );
        }
      }
      final attributes = expected[i]['attributes'] as Map;
      final color = attributes['colorArgb'] as String;
      require(
        actual.colorRgb == color.substring(3) &&
            actual.alpha == int.parse(color.substring(1, 3), radix: 16),
        'Ink color differs',
      );
      require(
        (actual.widthHimetric - (attributes['widthHimetric'] as num)).abs() <
                1e-9 &&
            (actual.heightHimetric - (attributes['heightHimetric'] as num))
                    .abs() <
                1e-9,
        'Pen dimensions differ',
      );
      require(
        actual.rectangleTip == (attributes['stylusTip'] == 'Rectangle') &&
            actual.fitToCurve == attributes['fitToCurve'] &&
            actual.ignorePressure == attributes['ignorePressure'] &&
            actual.isHighlighter == attributes['isHighlighter'],
        'Ink flags differ',
      );
      final expectedPoints = expected[i]['points'] as List;
      require(
        actual.points.length == expectedPoints.length,
        'Point count differs',
      );
      points += actual.points.length;
      for (var j = 0; j < expectedPoints.length; j++) {
        final point = actual.points[j],
            expectedPoint = expectedPoints[j] as Map;
        require(
          (point.xHimetric - (expectedPoint['himetricX'] as num)).abs() <
                  1e-9 &&
              (point.yHimetric - (expectedPoint['himetricY'] as num)).abs() <
                  1e-9,
          'Signed ink coordinate differs',
        );
        require(
          (point.pressureFactor -
                      (compactPressure
                          ? (expectedPoint['pressurePropertyValue'] as num) /
                                2047
                          : (expectedPoint['pressureFactor'] as num)))
                  .abs() <
              1e-7,
          'Ink pressure differs',
        );
        if (point.normalPressure != null) {
          require(
            point.normalPressure == expectedPoint['pressurePropertyValue'],
            'Pressure packet differs',
          );
        }
      }
    }
  }
  if (headerCases) {
    require(
      metricDifferences == 1,
      'Missing compact metric discrepancy control',
    );
  }
  return {
    'cases': cases.length,
    'strokes': strokes,
    'points': points,
    if (headerCases) 'specifiedMetricDifferences': metricDifferences,
  };
}
