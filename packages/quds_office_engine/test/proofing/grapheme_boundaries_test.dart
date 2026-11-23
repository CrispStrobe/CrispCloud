import 'package:characters/characters.dart';
import 'package:quds_office_engine/src/bidi/grapheme_clusters.dart';
import 'package:test/test.dart';

void main() {
  test('Latin fast path agrees with Unicode segmentation for every pair', () {
    final units = [
      for (var code = 0; code <= 0xff; code++) code,
      for (var code = 0x2010; code <= 0x201f; code++) code,
      0x2026,
    ];
    for (final left in units) {
      for (final right in units) {
        final text = String.fromCharCodes([left, right]);
        final expected = text.characters.length == 2;
        if (GraphemeBoundaries(text).contains(1) != expected) {
          fail(
            'Boundary mismatch between U+${left.toRadixString(16)} '
            'and U+${right.toRadixString(16)}.',
          );
        }
      }
    }
  });

  test('mixed text retains exact UTF-16 endpoints', () {
    for (final text in [
      '',
      'A\r\nB',
      'Cafe\u0301 und \u0600١\u0651',
      '👨‍👩‍👧‍👦 🇩🇪 🧑🏾‍💻',
      'مُحَمَّدٌ',
      'संस्कृतम्',
      String.fromCharCodes([0x61, 0xd83d, 0x61, 0xde00]),
    ]) {
      final expected = <int>{0};
      var end = 0;
      for (final cluster in text.characters) {
        end += cluster.length;
        expected.add(end);
      }
      final boundaries = GraphemeBoundaries(text);
      for (var offset = -1; offset <= text.length + 1; offset++) {
        expect(boundaries.contains(offset), expected.contains(offset));
      }
    }
  });
}
