// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  test(
    'native section directions, columns and source-defined numbering survive together',
    () {
      final source = File(
        'test/fixtures/word_native/word-compatibility.doc',
      ).readAsBytesSync();
      final document = parseLegacyWordDocument(source);
      expect(document.sections, hasLength(2));
      final first = document.sections.first.layout;
      final last = document.sections.last.layout;
      // Independently decoded SEPX: 0x3228=1, 0x322a=1 in section one;
      // 0x3228=0 and no 0x322a in section two. CP boundary is 196.
      expect(document.sections.map((s) => (s.startCp, s.endCp)), [
        (0, 196),
        (196, 217),
      ]);
      expect(first.rightToLeft, isTrue);
      expect(first.rightToLeftGutter, isTrue);
      expect(last.rightToLeft, isFalse);
      expect(last.rightToLeftGutter, isFalse);
      expect(first.columns.map((c) => (c.widthTwips, c.spaceAfterTwips)), [
        (5640, 600),
        (6719, 0),
      ]);
      expect(first.lineNumberStart, 4);
      expect(first.lineNumberInterval, 2);
      expect(first.lineNumberRestart, LegacyWordLineNumberRestart.newSection);
      expect(last.lineNumberRestart, LegacyWordLineNumberRestart.continuous);
      // Effective nFib is 0x0101: the old DOP start-four value is reserved.
      // Both SEPX records specify each-section restart and omit sprmSNFtn.
      for (final section in document.sections) {
        expect(section.layout.footnoteNumbering.start, 1);
        expect(section.layout.footnoteNumbering.format, 'lowerRoman');
        expect(
          section.layout.footnoteNumbering.restart,
          LegacyWordNoteRestart.eachSect,
        );
      }
      final converted = convertLegacyWordDocument(document);
      final zip = ZipDecoder().decodeBytes(converted.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content),
      );
      final sections = xml.findAllElements('sectPr', namespace: _w).toList();
      expect(sections.first.findElements('bidi', namespace: _w), hasLength(1));
      expect(
        sections.first.findElements('rtlGutter', namespace: _w),
        hasLength(1),
      );
      expect(sections.last.findElements('bidi', namespace: _w), isEmpty);
      expect(sections.last.findElements('rtlGutter', namespace: _w), isEmpty);
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        contains('Selected table fallback'),
      );
    },
  );
}
