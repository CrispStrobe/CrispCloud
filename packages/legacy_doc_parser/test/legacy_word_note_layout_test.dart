// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _one(int code, int value) => wordSprm(code, [value]);
List<int> _two(int code, int value) => wordSprm(code, wordU16(value));

Uint8List _source({
  List<int> section = const [],
  Uint8List? dop,
  bool sectionTable = true,
  int? newVersion,
}) =>
    StructuredWordFixture(
      pieces: [const WordFixturePiece('A\r')],
      sections: [if (sectionTable) WordFixtureSection(2, section)],
      extraTablePairs: {if (dop != null) 31: dop},
    ).build(
      mutate: (word, table) {
        if (newVersion != null) {
          word.setUint16(154 + 93 * 8, 2, Endian.little);
          word.setUint16(156 + 93 * 8, newVersion, Endian.little);
        }
      },
    );

Uint8List _dop({
  int size = 500,
  int footPosition = 2,
  int endPosition = 0,
  int footRestart = 1,
  int endRestart = 1,
  int footStart = 4,
  int endStart = 7,
  int footFormat = 2,
  int endFormat = 3,
}) {
  final result = Uint8List(size);
  final data = ByteData.sublistView(result);
  data.setUint16(0, footPosition << 5, Endian.little);
  data.setUint16(2, (footStart << 2) | footRestart, Endian.little);
  data.setUint16(52, (endStart << 2) | endRestart, Endian.little);
  data.setUint16(54, endPosition, Endian.little);
  if (size >= 500) {
    data.setUint16(492, footFormat, Endian.little);
    data.setUint16(494, endFormat, Endian.little);
  }
  return result;
}

XmlDocument _xml(LegacyWordDocument document) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

Iterable<XmlElement> _all(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);
String? _value(XmlNode node, String name) =>
    _all(node, name).single.getAttribute('val', namespace: _w);

void main() {
  test(
    'section note formats, placement, offsets and suppression stay native',
    () {
      final document = parseLegacyWordDocument(
        _source(
          section: [
            ..._one(0x303b, 2),
            ..._one(0x303c, 0),
            ..._two(0x503f, 4),
            ..._two(0x5040, 2),
            ..._one(0x303e, 1),
            ..._two(0x5041, 9),
            ..._two(0x5042, 3),
            ..._one(0x3012, 0),
          ],
        ),
      );
      final layout = document.sections.single.layout;
      expect(layout.footnoteNumbering.start, 4);
      expect(layout.endnoteNumbering.start, 1);
      expect(layout.endnoteNumbering.sourceContinuousOffset, 9);
      final xml = _xml(document),
          foot = _all(xml, 'footnotePr').single,
          end = _all(xml, 'endnotePr').single;
      expect(_value(foot, 'pos'), 'beneathText');
      expect(_value(foot, 'numFmt'), 'lowerRoman');
      expect(_value(foot, 'numStart'), '4');
      expect(_value(foot, 'numRestart'), 'continuous');
      expect(_value(end, 'numFmt'), 'upperLetter');
      expect(_value(end, 'numStart'), '1');
      expect(_value(end, 'numRestart'), 'eachSect');
      expect(_all(xml, 'noEndnote'), hasLength(1));
      final children = _all(
        xml,
        'sectPr',
      ).single.childElements.map((e) => e.name.local).toList();
      expect(
        children.indexOf('footnotePr'),
        lessThan(children.indexOf('type')),
      );
      expect(children.indexOf('endnotePr'), lessThan(children.indexOf('type')));
      expect(
        children.indexOf('noEndnote'),
        greaterThan(children.indexOf('cols')),
      );
    },
  );

  for (final table in [true, false]) {
    test('Word 97 DOP note defaults apply with section table=$table', () {
      final document = parseLegacyWordDocument(
        _source(dop: _dop(), sectionTable: table),
      );
      final layout = document.sections.single.layout;
      expect(layout.footnoteNumbering.start, 4);
      expect(layout.footnoteNumbering.format, 'lowerRoman');
      expect(layout.footnoteNumbering.restart, LegacyWordNoteRestart.eachSect);
      expect(layout.endnoteNumbering.start, 7);
      expect(layout.endnoteNumbering.format, 'upperLetter');
      expect(layout.endnotePosition, LegacyWordEndnotePosition.sectEnd);
      final xml = _xml(document);
      expect(_value(_all(xml, 'endnotePr').single, 'pos'), 'sectEnd');
      expect(_value(_all(xml, 'footnotePr').single, 'numStart'), '4');
    });
  }

  test(
    'later versions ignore old DOP numbering but retain global endnote placement',
    () {
      final document = parseLegacyWordDocument(
        _source(
          dop: _dop(size: 594, endPosition: 3),
          newVersion: 0x101,
          section: [..._two(0x5040, 4), ..._two(0x503f, 6)],
        ),
      );
      final layout = document.sections.single.layout;
      expect(layout.footnotePosition, LegacyWordFootnotePosition.pageBottom);
      expect(
        layout.footnoteNumbering.restart,
        LegacyWordNoteRestart.continuous,
      );
      expect(layout.footnoteNumbering.format, 'lowerLetter');
      expect(layout.footnoteNumbering.start, 6);
      expect(layout.endnoteNumbering.format, 'lowerRoman');
      expect(layout.endnoteNumbering.start, 1);
      expect(layout.endnotePosition, LegacyWordEndnotePosition.docEnd);
    },
  );

  test(
    'partial legacy DOP does not read format words beyond its declared bounds',
    () {
      final document = parseLegacyWordDocument(_source(dop: _dop(size: 84)));
      expect(document.sections.single.layout.footnoteNumbering.start, 4);
      expect(
        document.sections.single.layout.footnoteNumbering.format,
        'decimal',
      );
      expect(
        document.sections.single.layout.endnoteNumbering.format,
        'lowerRoman',
      );
    },
  );

  test('continuous offsets stay inactive for page or section restarts', () {
    final document = parseLegacyWordDocument(
      _source(
        dop: _dop(),
        section: [..._two(0x503f, 10), ..._one(0x303c, 2), ..._two(0x5041, 11)],
      ),
    );
    expect(document.sections.single.layout.footnoteNumbering.start, 4);
    expect(document.sections.single.layout.endnoteNumbering.start, 7);
    expect(
      document.sections.single.layout.footnoteNumbering.sourceContinuousOffset,
      10,
    );
  });

  test('unknown note formats retain source evidence and report loss', () {
    final document = parseLegacyWordDocument(
      _source(section: _two(0x5040, 65535)),
    );
    expect(document.sections.single.layout.footnoteNumbering.format, isNull);
    expect(
      document.sections.single.layout.footnoteNumbering.sourceFormatCode,
      65535,
    );
    expect(
      document.warnings,
      contains(LegacyWordWarning.unsupportedFormatting),
    );
    expect(
      convertLegacyWordDocument(document).limitations,
      contains(LegacyWordConversionLimitation.partialFormatting),
    );
    expect(_all(_all(_xml(document), 'footnotePr').single, 'numFmt'), isEmpty);
  });

  test(
    'default line numbers begin at one with the native Word skip count zero',
    () {
      final document = parseLegacyWordDocument(
        _source(section: _two(0x5015, 1)),
      );
      expect(document.sections.single.layout.lineNumberStart, 1);
      expect(
        _all(
          _xml(document),
          'lnNumType',
        ).single.getAttribute('start', namespace: _w),
        '0',
      );
    },
  );

  for (final (name, section) in [
    ('section footnote position', _one(0x303b, 0)),
    ('section endnote restart', _one(0x303e, 2)),
    ('section footnote restart', _one(0x303c, 3)),
    ('section note offset', _two(0x503f, 16384)),
  ]) {
    test('rejects invalid $name', () {
      expect(
        () => parseLegacyWordDocument(_source(section: section)),
        throwsFormatException,
      );
    });
  }
  for (final (name, dop) in [
    ('document footnote position', _dop(footPosition: 3)),
    ('document endnote position', _dop(endPosition: 1)),
    ('document footnote restart', _dop(footRestart: 3)),
  ]) {
    test('rejects invalid $name', () {
      expect(
        () => parseLegacyWordDocument(_source(dop: dop)),
        throwsFormatException,
      );
    });
  }
}
