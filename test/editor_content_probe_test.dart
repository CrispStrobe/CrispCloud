import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/utils/editor_content_probe.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  group('shouldEditAsText', () {
    test('known text names stay text even without a probe', () {
      expect(shouldEditAsText('notes.txt', null), isTrue);
      expect(shouldEditAsText('README', null), isTrue);
      expect(shouldEditAsText('config.json', null), isTrue);
    });

    test('unknown text extensions follow their content like F3', () {
      expect(
        shouldEditAsText(
          'Wallabag_catchup_20260918.recipe',
          _utf8('webpage:\n  name: Wallabag\n  url: https://example.test\n'),
        ),
        isTrue,
      );
      expect(
        shouldEditAsText('saved.markup', _utf8('<html><body>Hello</body></html>')),
        isTrue,
      );
      expect(
        shouldEditAsText(
          'unicode.blob',
          _utf8('Résumé notes: the café keeps one menu for Grüße.'),
        ),
        isTrue,
      );
    });

    test('UTF BOMs are text', () {
      expect(
        shouldEditAsText(
          'capture.recipe',
          Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('alpha')]),
        ),
        isTrue,
      );
      expect(
        shouldEditAsText(
          'capture.recipe',
          Uint8List.fromList(<int>[0xFF, 0xFE, 0x61, 0x00, 0x62, 0x00]),
        ),
        isTrue,
      );
    });

    test('binary content stays binary', () {
      expect(
        shouldEditAsText(
          'capture.recipe',
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
        ),
        isFalse,
      );
      expect(
        shouldEditAsText(
          'capture.dat',
          _utf8('this extension is mapped to the binary viewer'),
        ),
        isFalse,
      );
    });

    test('a failed probe keeps the safer Hex default', () {
      expect(shouldEditAsText('capture.recipe', null), isFalse);
    });

    test('an empty unknown file opens as text', () {
      expect(shouldEditAsText('capture.recipe', Uint8List(0)), isTrue);
    });
  });
}
