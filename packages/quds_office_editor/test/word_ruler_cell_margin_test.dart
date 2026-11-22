import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  const margins = WmlPageMargins(left: 20, right: 20);
  for (final margin in [0.0, 4.0, 12.0]) {
    test('ruler uses configured cell margin $margin without a text line', () {
      expect(
        WordRuler.paragraphContentBox(
          margins: margins,
          pageWidth: 400,
          cellX: 35,
          cellWidth: 100,
          cellMargin: margin,
        ),
        (left: 35 + margin, right: 135 - margin),
      );
    });
  }

  test('zero-margin narrow empty cells retain their own ruler box', () {
    expect(
      WordRuler.paragraphContentBox(
        margins: margins,
        pageWidth: 400,
        cellX: 35,
        cellWidth: 8,
        cellMargin: 0,
      ),
      (left: 35, right: 43),
    );
  });

  test('actual line box takes precedence over fallback cell padding', () {
    expect(
      WordRuler.paragraphContentBox(
        margins: margins,
        pageWidth: 400,
        lineBoxX: 70,
        lineBoxWidth: 100,
        cellX: 35,
        cellWidth: 200,
        cellMargin: 12,
      ),
      (left: 70, right: 170),
    );
  });

  for (final margin in [-1.0, double.nan, double.infinity, 50.0]) {
    test('invalid cell ruler margin $margin fails explicitly', () {
      expect(
        () => WordRuler.paragraphContentBox(
          margins: margins,
          pageWidth: 400,
          cellX: 35,
          cellWidth: 100,
          cellMargin: margin,
        ),
        throwsArgumentError,
      );
    });
  }
}
