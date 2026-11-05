import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/extensions/box_constraints_extension.dart';

void main() {
  group('BoxConstraintsExtension', () {
    test('toMap returns correct map for finite constraints', () {
      const constraints = BoxConstraints(
        minWidth: 10,
        maxWidth: 100,
        minHeight: 20,
        maxHeight: 200,
      );
      final map = constraints.toMap();

      expect(map, {
        'minWidth': 10,
        'maxWidth': 100,
        'minHeight': 20,
        'maxHeight': 200,
      });
    });

    test('toMap returns correct map for unbounded constraints', () {
      const constraints = BoxConstraints(
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
      );
      final map = constraints.toMap();

      expect(map, {
        'minWidth': 0,
        'maxWidth': double.infinity,
        'minHeight': 0,
        'maxHeight': double.infinity,
      });
    });

    test('toMap returns correct map for tight constraints', () {
      const constraints = BoxConstraints.tightFor(width: 50, height: 75);
      final map = constraints.toMap();

      expect(map, {
        'minWidth': 50,
        'maxWidth': 50,
        'minHeight': 75,
        'maxHeight': 75,
      });
    });

    test('toMap returns correct map for loose constraints', () {
      final constraints = BoxConstraints.loose(const Size(30, 40));
      final map = constraints.toMap();

      expect(map, {
        'minWidth': 0,
        'maxWidth': 30,
        'minHeight': 0,
        'maxHeight': 40,
      });
    });
  });
}
