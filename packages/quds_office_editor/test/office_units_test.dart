import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('physical units accept decimal commas and explicit suffixes', () {
    for (final unit in OfficeLengthUnit.values) {
      for (final value in ['2.54 cm', '25,4 mm', '1 inch', '72 pt', '1"']) {
        expect(unit.parsePoints(value), closeTo(72, 1e-10));
      }
      expect(
        unit.toPoints(unit.fromPoints(123.456789)),
        closeTo(123.456789, 1e-10),
      );
      for (final invalid in ['NaN', 'Infinity', '', '12 parsecs', '1,2,3']) {
        expect(unit.parsePoints(invalid), isNull);
      }
    }
    expect(
      OfficeLengthUnit.centimeters.parsePoints('2,54'),
      closeTo(72, 1e-10),
    );
    expect(
      OfficeLengthUnit.millimeters.parsePoints('25.4'),
      closeTo(72, 1e-10),
    );
  });
  test('surface config preserves units across unrelated changes', () {
    const config = OfficeSurfaceConfig(
      lengthUnit: OfficeLengthUnit.millimeters,
    );
    expect(
      config.copyWith(autofocus: true).lengthUnit,
      OfficeLengthUnit.millimeters,
    );
    expect(
      config.copyWith(lengthUnit: OfficeLengthUnit.centimeters).lengthUnit,
      OfficeLengthUnit.centimeters,
    );
    expect(OfficeLengthUnit.millimeters.rulerLabelMultiplier, 10);
    expect(OfficeLengthUnit.centimeters.snapPoints, closeTo(72 / 25.4, 1e-10));
  });
}
