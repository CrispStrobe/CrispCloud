// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/story_unicode_fixture.dart';

void main() {
  for (final name in invalidStoryUnicodeCases) {
    test('rejects a surrogate pair split across story boundaries: $name', () {
      final source = storyUnicodeFixture(name);
      final before = source.toList();
      expect(
        () => parseLegacyWordDocument(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('story boundary'),
          ),
        ),
      );
      expect(source, before);
    });
  }

  test('valid supplementary characters stay inside their own stories', () {
    final source = storyUnicodeFixture('supplementary-stories');
    final before = source.toList();
    final document = parseLegacyWordDocument(source);
    expect(document.plainText, 'A\u{1f600}');
    expect(document.stories.single.plainText, 'B\u{1f680}');
    for (final paragraph in [
      ...document.blocks.whereType<LegacyWordParagraph>(),
      ...document.stories.single.blocks.whereType<LegacyWordParagraph>(),
    ]) {
      for (final run in paragraph.runs) {
        expect(run.startCp, greaterThanOrEqualTo(paragraph.startCp));
        expect(run.endCp, lessThanOrEqualTo(paragraph.endCp));
      }
    }
    expect(source, before);
    expect(convertLegacyWordDocument(document).bytes, isNotEmpty);
  });
}
