import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/services/import_export/constants/minified_keys.dart';

void main() {
  group('Map key-value validation', () {
    test('No duplicate values in kMinifiedMainKeys', () {
      final values = kMinifiedMainKeys.values.toList();
      final uniqueValues = values.toSet();
      expect(
        values.length,
        uniqueValues.length,
        reason: 'kMinifiedMainKeys contains duplicate values',
      );
    });

    test('No duplicate values in kMinifiedHistoryKeys', () {
      final values = kMinifiedHistoryKeys.values.toList();
      final uniqueValues = values.toSet();
      expect(
        values.length,
        uniqueValues.length,
        reason: 'kMinifiedHistoryKeys contains duplicate values',
      );
    });

    test('No duplicate values in kMinifiedLayerKeys', () {
      final values = kMinifiedLayerKeys.values.toList();
      final uniqueValues = values.toSet();
      expect(
        values.length,
        uniqueValues.length,
        reason: 'kMinifiedLayerKeys contains duplicate values',
      );
    });

    test('No duplicate values in kMinifiedLayerInteractionKeys', () {
      final values = kMinifiedLayerInteractionKeys.values.toList();
      final uniqueValues = values.toSet();
      expect(
        values.length,
        uniqueValues.length,
        reason: 'kMinifiedLayerInteractionKeys contains duplicate values',
      );
    });

    test('No duplicate values in kMinifiedPaintKeys', () {
      final values = kMinifiedPaintKeys.values.toList();
      final uniqueValues = values.toSet();
      expect(
        values.length,
        uniqueValues.length,
        reason: 'kMinifiedPaintKeys contains duplicate values',
      );
    });
  });
}
