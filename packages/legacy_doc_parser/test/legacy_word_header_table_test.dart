// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/header_table_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  for (var slot = 0; slot < 6; slot++) {
    test('header/footer slot $slot recovers only the bounded closed table', () {
      final bytes = headerTableFixture(slot: slot, followingStory: slot < 5);
      final document = parseLegacyWordDocument(bytes);
      final story = document.stories.first;
      expect(story.plainText, 'STORY\nCELL');
      expect(story.blocks, hasLength(2));
      expect(story.blocks.last, isA<LegacyWordTable>());
      expect(story.blocks.last.endCp, story.endCp);
      expect(story.endCp - story.startCp, 'STORY\rCELL\x07\x07'.length);
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredTableStoryBoundary),
      );
      if (slot < 5) {
        expect(document.stories.last.plainText, 'NEIGHBOR');
        expect(document.stories.last.startCp, story.endCp + 1);
      }
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(document).bytes,
      );
      final header = slot == 0 || slot == 1 || slot == 4;
      final xml = XmlDocument.parse(
        utf8.decode(
          archive
              .findFile('word/${header ? 'header' : 'footer'}1.xml')!
              .content,
        ),
      );
      expect(xml.findAllElements('tbl', namespace: _w), hasLength(1));
      expect(
        xml.findAllElements('t', namespace: _w).map((node) => node.innerText),
        ['STORY', 'CELL'],
      );
      expect(xml.rootElement.childElements.last.localName, 'p');
    });
  }

  test('an actual trailing content paragraph remains outside the table', () {
    final document = parseLegacyWordDocument(
      headerTableFixture(trailingParagraph: true),
    );
    final story = document.stories.single;
    expect(story.plainText, 'STORY\nCELL\nAFTER');
    expect(story.blocks, hasLength(3));
    expect(story.blocks.last, isA<LegacyWordParagraph>());
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.recoveredTableStoryBoundary)),
    );
  });

  for (final (name, bytes) in [
    (
      'stray cell marks without table properties',
      headerTableFixture(tableProperties: false),
    ),
    ('unclosed final table row', headerTableFixture(closeRow: false)),
    ('wrong guard character', headerTableFixture(guard: 'X')),
    ('missing guard paragraph', headerTableFixture(guard: '')),
    (
      'unterminated text before the guard',
      headerTableFixture(finalContent: 'X'),
    ),
  ]) {
    test('rejects $name instead of extending the header range', () {
      expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
    });
  }

  for (final role in ['header', 'footer']) {
    for (final ending in ['table', 'paragraph']) {
      test('native $role ending in $ending retains the complete story', () {
        final file = File('test/fixtures/word_native/$role-ending-$ending.doc');
        final source = file.readAsBytesSync();
        final document = parseLegacyWordDocument(source);
        final kind = role == 'header'
            ? LegacyWordStoryKind.header
            : LegacyWordStoryKind.footer;
        final story = document.stories.singleWhere(
          (s) =>
              s.kind == kind &&
              s.headerFooterType == LegacyWordHeaderFooterType.normal,
        );
        expect(
          story.plainText,
          ending == 'table' ? 'STORY\nCELL' : 'STORY\nCELL\nAFTER',
        );
        expect(story.blocks.whereType<LegacyWordTable>(), hasLength(1));
        expect(
          document.warnings.contains(
            LegacyWordWarning.recoveredTableStoryBoundary,
          ),
          ending == 'table',
        );
        final archive = ZipDecoder().decodeBytes(
          convertLegacyWordDocument(document).bytes,
        );
        final stories = archive.files.where(
          (part) =>
              part.name.startsWith('word/$role') && part.name.endsWith('.xml'),
        );
        expect(stories, isNotEmpty);
        for (final part in stories) {
          final xml = XmlDocument.parse(utf8.decode(part.content));
          if (xml.findAllElements('tbl', namespace: _w).isEmpty) continue;
          expect(
            xml
                .findAllElements('t', namespace: _w)
                .map((node) => node.innerText),
            ['STORY', 'CELL', if (ending == 'paragraph') 'AFTER'],
          );
        }
        expect(file.readAsBytesSync(), source);
      });
    }
  }
}
