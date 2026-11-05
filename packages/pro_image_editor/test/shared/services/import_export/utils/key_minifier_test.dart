import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/services/import_export/constants/minified_keys.dart';
import 'package:pro_image_editor/shared/services/import_export/utils/key_minifier.dart';

void main() {
  group('EditorKeyMinifier', () {
    late EditorKeyMinifier minifier;
    late EditorKeyMinifier noMinifier;

    setUp(() {
      minifier = EditorKeyMinifier(enableMinify: true);
      noMinifier = EditorKeyMinifier(enableMinify: false);
    });

    bool deepEquals(dynamic a, dynamic b) {
      if (a is Map && b is Map) {
        if (a.length != b.length) return false;
        for (final key in a.keys) {
          if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
        }
        return true;
      } else if (a is List && b is List) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (!deepEquals(a[i], b[i])) return false;
        }
        return true;
      }
      return a == b;
    }

    test('convertMainKey returns minified key when enabled', () {
      final key = kMinifiedMainKeys.keys.first;
      final minified = kMinifiedMainKeys[key];
      expect(minifier.convertMainKey(key), minified);
    });

    test('convertMainKey returns original key when disabled', () {
      expect(noMinifier.convertMainKey('someKey'), 'someKey');
    });

    test('convertSizeKey returns minified key when enabled', () {
      final key = kMinifiedSizeKeys.keys.first;
      final minified = kMinifiedSizeKeys[key];
      expect(minifier.convertSizeKey(key), minified);
    });

    test('convertSizeKey returns original key when disabled', () {
      expect(noMinifier.convertSizeKey('sizeKey'), 'sizeKey');
    });

    test('convertHistoryKey returns minified key when enabled', () {
      final key = kMinifiedHistoryKeys.keys.first;
      final minified = kMinifiedHistoryKeys[key];
      expect(minifier.convertHistoryKey(key), minified);
    });

    test('convertHistoryKey returns original key when disabled', () {
      expect(noMinifier.convertHistoryKey('historyKey'), 'historyKey');
    });

    test('convertPaintKey returns minified key when enabled', () {
      final key = kMinifiedPaintKeys.keys.first;
      final minified = kMinifiedPaintKeys[key];
      expect(minifier.convertPaintKey(key), minified);
    });

    test('convertPaintKey returns original key when disabled', () {
      expect(noMinifier.convertPaintKey('paintKey'), 'paintKey');
    });

    test('convertLayerKey returns minified key when enabled', () {
      final key = kMinifiedLayerKeys.keys.first;
      final minified = kMinifiedLayerKeys[key];
      expect(minifier.convertLayerKey(key), minified);
    });

    test('convertLayerKey returns original key when disabled', () {
      expect(noMinifier.convertLayerKey('layerKey'), 'layerKey');
    });

    test('convertLayerInteractionKey returns minified key when enabled', () {
      final key = kMinifiedLayerInteractionKeys.keys.first;
      final minified = kMinifiedLayerInteractionKeys[key];
      expect(minifier.convertLayerInteractionKey(key), minified);
    });

    test('convertLayerInteractionKey returns original key when disabled', () {
      expect(
        noMinifier.convertLayerInteractionKey('interactionKey'),
        'interactionKey',
      );
    });

    test('convertListOfLayerKeys returns original when minify disabled', () {
      final layers = [
        {
          'id': 'layer1',
          'interaction': {'hover': true},
          'item': {'color': 'red'},
        },
      ];
      final result = noMinifier.convertListOfLayerKeys(layers);
      expect(deepEquals(result, layers), isTrue);
    });

    test('convertReferenceKeys returns original when minify disabled', () {
      final references = {
        'ref1': {
          'interaction': {'hover': true},
          'item': {'color': 'blue'},
        },
      };
      final result = noMinifier.convertReferenceKeys(references);
      expect(deepEquals(result, references), isTrue);
    });

    test('_generateAlphabeticalKey generates correct keys', () {
      expect(minifier.generateAlphabeticalKey(0), 'A');
      expect(minifier.generateAlphabeticalKey(25), 'Z');
      expect(minifier.generateAlphabeticalKey(26), 'AA');
      expect(minifier.generateAlphabeticalKey(27), 'AB');
      expect(minifier.generateAlphabeticalKey(51), 'AZ');
      expect(minifier.generateAlphabeticalKey(52), 'BA');
    });

    test('convertLayerId minifies layer ids in history and references', () {
      final history = [
        {
          'l': [
            {'id': 'layer1'},
            {'id': 'layer2'},
          ],
        },
      ];
      final references = {
        'layer1': {'data': 1},
        'layer2': {'data': 2},
      };
      final response = minifier.convertLayerId(history, references);

      expect(response.references.containsKey('A'), isTrue);
      expect(response.references.containsKey('B'), isTrue);
      expect(response.references.length, 2);

      final updatedHistory = response.history;
      final ids = updatedHistory.first['l'].map((e) => e['id']).toList();
      expect(ids, containsAll(['A', 'B']));
    });

    test('convertLayerId returns original when minify disabled', () {
      final history = [
        {
          'l': [
            {'id': 'layer1'},
          ],
        },
      ];
      final references = {
        'layer1': {'data': 1},
      };
      final response = noMinifier.convertLayerId(history, references);
      expect(deepEquals(response.history, history), isTrue);
      expect(deepEquals(response.references, references), isTrue);
    });
  });
}
