// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/note_boundary_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    for (final entry in noteBoundaryCases.entries) {
      test('$kind ${entry.key} retains its exact content blocks', () {
        final (text, expected) = entry.value;
        final source = noteBoundaryFixture(text, endnote: endnote);
        final document = parseLegacyWordDocument(source);
        final story = document.stories.singleWhere((s) => s.kind.name == kind);
        expect(story.endCp - story.startCp, text.length);
        expect(
          story.blocks.map((b) => b is LegacyWordTable ? 'tbl' : 'p'),
          expected,
        );
        expect(story.blocks.last.endCp, story.endCp);
        expect(
          document.warnings.contains(
            LegacyWordWarning.recoveredTableStoryBoundary,
          ),
          entry.key == 'table',
        );
        final result = convertLegacyWordDocument(document);
        final xml = XmlDocument.parse(
          utf8.decode(
            ZipDecoder()
                .decodeBytes(result.bytes)
                .findFile('word/${kind}s.xml')!
                .content,
          ),
        );
        final note = xml
            .findAllElements(kind, namespace: _w)
            .singleWhere((e) => e.getAttribute('type', namespace: _w) == null);
        expect(note.childElements.map((e) => e.name.local), expected);
        expect(note.findAllElements('${kind}Ref', namespace: _w), hasLength(1));
        final paragraphs = note.childElements
            .where((e) => e.name.local == 'p')
            .toList();
        expect(
          paragraphs.map(
            (p) => p
                .findAllElements('t', namespace: _w)
                .map((t) => t.innerText)
                .join(),
          ),
          story.blocks.whereType<LegacyWordParagraph>().map(
            (p) => p.runs.map((r) => r.text).join(),
          ),
        );
      });
    }
    test('$kind final-table recovery remains bounded and diagnosed', () {
      final table = noteBoundaryCases['table']!.$1;
      for (final source in [
        noteBoundaryFixture(table, endnote: endnote, closeRow: false),
        noteBoundaryFixture(table, endnote: endnote, storyGuard: 'X'),
        noteBoundaryFixture('\x02Unterminated', endnote: endnote),
      ]) {
        expect(() => parseLegacyWordDocument(source), throwsFormatException);
      }
    });
  }
}
