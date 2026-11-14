// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/legacy_word_numbering.dart';

import '../tool/list_visibility_web_acceptance.dart';
import 'support/list_visibility_fixture.dart';

void main() {
  for (final name in listVisibilityCases) {
    test('numbered paragraph visibility: $name', () {
      verifyListVisibilityCase(name);
    });
  }
  test('suppressed labels do not masquerade as unsupported HTML numbering', () {
    for (final name in listVisibilityCases) {
      final document = parseLegacyWordDocument(listVisibilityFixture(name));
      expect(
        document.safeHtml,
        isNot(contains('data-word-numbering="unsupported"')),
        reason: name,
      );
    }
    final unsupported = renderLegacyWordHtml([
      const LegacyWordParagraph(
        startCp: 0,
        endCp: 5,
        runs: [LegacyWordRun(startCp: 0, endCp: 4, text: 'Body')],
        style: LegacyWordParagraphStyle(listId: 123, listLevel: 0),
      ),
    ]);
    expect(unsupported, contains('data-word-numbering="unsupported"'));
  });
  test('nested field prefix visibility includes closing marker boundaries', () {
    LegacyWordField field(
      int start,
      int end,
      int? separator, {
      bool private = false,
    }) => LegacyWordField(
      id: start,
      storyId: 'main',
      startCp: start,
      endCp: end,
      separatorCp: separator,
      instruction: 'QUOTE "value"',
      storedResult: '',
      type: 'QUOTE',
      privateResult: private,
    );
    final visibility = LegacyWordNumberingVisibility([
      field(30, 34, null),
      field(10, 18, 13, private: true),
      field(2, 20, 8),
    ]);
    for (final cp in [0, 2, 9, 10, 18, 19, 20, 30, 34]) {
      expect(visibility.visibleAt(cp), isTrue, reason: 'visible boundary $cp');
    }
    for (final cp in [3, 7, 8, 11, 13, 14, 17, 31, 32, 33]) {
      expect(visibility.visibleAt(cp), isFalse, reason: 'hidden boundary $cp');
    }
  });
  test('suppressed caller numbering revisions retain all typed evidence', () {
    for (final prefix in ['decimal', 'literal']) {
      final source = parseLegacyWordDocument(
        listVisibilityFixture('$prefix-private-blank-middle'),
      );
      final blocks = source.blocks.cast<LegacyWordParagraph>().toList();
      final old = blocks[1];
      final time = DateTime.utc(2020, 1, 2, 3, 4, 5, 6, 7);
      blocks[1] = LegacyWordParagraph(
        startCp: old.startCp,
        endCp: old.endCp,
        runs: old.runs,
        style: old.style,
        mark: old.mark,
        numberingRevision: LegacyWordNumberingRevision(
          original: '%1:42:0:.',
          previouslyNumbered: true,
          inserted: true,
          revision: LegacyWordRevisionInfo(
            author: 'Typed Author',
            time: time,
            authorIndex: 2,
            rawDate: 19,
            saveId: 5,
            reason: 37,
          ),
        ),
      );
      final model = LegacyWordDocument(
        blocks: blocks,
        sections: source.sections,
        plainText: source.plainText,
        safeHtml: source.safeHtml,
        fields: source.fields,
        numbering: source.numbering,
      );
      for (final mode in LegacyWordFieldMode.values) {
        final result = convertLegacyWordDocument(model, fieldMode: mode);
        final archive = ZipDecoder().decodeBytes(result.bytes);
        final records =
            (jsonDecode(
                      utf8.decode(
                        archive
                            .findFile('word/evidence/manifest.json')!
                            .content,
                      ),
                    )['records']
                    as List)
                .cast<Map<String, dynamic>>();
        final record = records.singleWhere(
          (record) => record['cp'] == old.startCp && record['marked'] == true,
        );
        expect(record['originalNumbering'], '%1:42:0:.');
        expect(record['previouslyNumbered'], true);
        expect(record['numberingInserted'], true);
        expect(record['kind'], 'suppressedFieldNumberingRevision');
        expect(record['revision'], {
          'author': 'Typed Author',
          'time': time.toIso8601String(),
          'authorIndex': 2,
          'rawDate': 19,
          'saveId': 5,
          'reason': 37,
        });
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.revisions),
        );
        expect(
          utf8.decode(archive.findFile('word/document.xml')!.content),
          isNot(contains('<w:numberingChange')),
        );
      }
    }
  });
}
