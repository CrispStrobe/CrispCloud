import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/legacy_word_conversion.dart';
import 'package:crisp_cloud/services/word_conversion_inspection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show OpcPackage;
import 'package:xml/xml.dart';

import 'support/legacy_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _main(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
);

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);

String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

void main() {
  test('structured DOCX retains Unicode, XML text and an untouched source', () {
    final source = legacyWordFixture(
      '  世界 😀 <tag> & data\r\rEnd\r',
      withOpaqueMacro: true,
    );
    final original = Uint8List.fromList(source);
    final result = convertLegacyWordToStructuredDocx(source);
    final package = OpcPackage.openBytes(result.bytes);
    final xml = _main(result.bytes);
    expect(_elements(xml, 't').map((text) => text.innerText), [
      '  世界 😀 <tag> & data',
      'End',
    ]);
    expect(_elements(xml, 'p'), hasLength(3));
    expect(source, orderedEquals(original));
    expect(package.partNames, isNot(contains('Macros/VBA/Module1')));
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.macrosSignatures),
    );
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.partialFormatting),
    );
    expect(() => result.bytes[0] = 0, throwsUnsupportedError);
    expect(() => result.limitations.clear(), throwsUnsupportedError);
  });

  test(
    'emits standard justification and keeps direct headings paragraph-local',
    () {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('Title\rBody\r')],
        paragraphRuns: [
          WordFixtureFkpRun(
            8192,
            8198,
            properties: [
              ...wordSprm(0x2403, [3]), // Justify.
              ...wordSprm(0x2640, [1]), // Direct outline level2.
              ...wordSprm(0x840f, wordU16(720)),
              ...wordSprm(0x8411, wordU16(-360)),
            ],
          ),
          const WordFixtureFkpRun(8198, 8203),
        ],
      ).build();
      final result = convertLegacyWordToStructuredDocx(source);
      final xml = _main(result.bytes);
      final paragraphs = _elements(xml, 'p').toList();
      expect(_attr(_elements(paragraphs[0], 'jc').single, 'val'), 'both');
      expect(_attr(_elements(paragraphs[0], 'outlineLvl').single, 'val'), '1');
      expect(_attr(_elements(paragraphs[1], 'outlineLvl').single, 'val'), '9');
      expect(_attr(_elements(paragraphs[0], 'ind').single, 'left'), '720');
      expect(_attr(_elements(paragraphs[0], 'ind').single, 'hanging'), '360');
      final styles = OpcPackage.openBytes(result.bytes)
          .getPart('/word/styles.xml')!;
      expect(
        _elements(XmlDocument.parse(styles.readText()), 'outlineLvl'),
        isEmpty,
      );
    },
  );

  test(
    'preserves supported insertion and deletion state as revision markup',
    () {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('AnewoldZ\r')],
        characterRuns: [
          const WordFixtureFkpRun(8192, 8193),
          WordFixtureFkpRun(8193, 8196, properties: wordSprm(0x0801, [1])),
          WordFixtureFkpRun(8196, 8199, properties: wordSprm(0x0800, [1])),
          const WordFixtureFkpRun(8199, 8201),
        ],
      ).build();
      final result = convertLegacyWordToStructuredDocx(source);
      final xml = _main(result.bytes);
      expect(_elements(xml, 'ins').single.innerText, 'new');
      expect(_elements(xml, 'del').single.innerText, 'old');
      expect(
        _elements(_elements(xml, 'del').single, 'delText').single.innerText,
        'old',
      );
      expect(_elements(_elements(xml, 'del').single, 't'), isEmpty);
      expect(
        _attr(_elements(xml, 'ins').single, 'id'),
        isNot(_attr(_elements(xml, 'del').single, 'id')),
      );
      expect(_elements(xml, 't').map((text) => text.innerText).join(), 'AnewZ');
    },
  );

  test(
    'distinguishes tabs, manual line breaks, page breaks and paragraph marks',
    () {
      final result = convertLegacyWordToStructuredDocx(
        legacyWordFixture('Alpha\tBeta\x0bGamma\x0cDelta\r'),
      );
      final xml = _main(result.bytes);
      expect(_elements(xml, 'p'), hasLength(1));
      expect(_elements(xml, 'tab'), hasLength(1));
      expect(_elements(xml, 'br'), hasLength(2));
      expect(_elements(xml, 'br').map((e) => _attr(e, 'type')), [null, 'page']);
    },
  );

  test(
    'places section layout at its original boundary without extra page breaks',
    () {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('First\x0cSecond\r')],
        sections: [
          WordFixtureSection(6, [
            ...wordSprm(0x3009, [0]), // Continuous break.
            ...wordSprm(0xb01f, wordU16(15840)),
            ...wordSprm(0xb020, wordU16(12240)),
            ...wordSprm(0x301d, [2]), // Landscape (SBOrientation).
            ...wordSprm(0xb021, wordU16(900)),
            ...wordSprm(0xb022, wordU16(1000)),
            ...wordSprm(0x9023, wordU16(1100)),
            ...wordSprm(0x9024, wordU16(1200)),
          ]),
          WordFixtureSection(13, [
            ...wordSprm(0xb01f, wordU16(12240)),
            ...wordSprm(0xb020, wordU16(15840)),
          ]),
        ],
      ).build();
      final xml = _main(convertLegacyWordToStructuredDocx(source).bytes);
      final sections = _elements(xml, 'sectPr').toList();
      expect(sections, hasLength(2));
      expect((sections.first.parent as XmlElement).name.local, 'pPr');
      expect((sections.last.parent as XmlElement).name.local, 'body');
      expect(
        _attr(_elements(sections.first, 'type').single, 'val'),
        'nextPage',
      );
      expect(
        _attr(_elements(sections.last, 'type').single, 'val'),
        'continuous',
      );
      expect(_attr(_elements(sections.first, 'pgSz').single, 'w'), '15840');
      expect(
        _attr(_elements(sections.first, 'pgSz').single, 'orient'),
        'landscape',
      );
      expect(_attr(_elements(sections.first, 'pgMar').single, 'left'), '900');
      expect(_attr(_elements(sections.last, 'pgSz').single, 'w'), '12240');
      expect(_elements(xml, 'br'), isEmpty);
    },
  );

  test('actual authored DOC converts formatting and tables with explicit omissions', () async {
    final source = File('test/fixtures/word_native/formatting.doc')
        .readAsBytesSync();
    final original = Uint8List.fromList(source);
    final result = convertLegacyWordToStructuredDocx(source);
    final xml = _main(result.bytes);
    expect(_elements(xml, 'tbl'), hasLength(1));
    expect(_elements(xml, 'tc'), hasLength(4));
    final boldRun = _elements(xml, 'r').singleWhere(
      (run) =>
          _elements(run, 't').any((text) => text.innerText == 'Bold red text'),
    );
    expect(_attr(_elements(boldRun, 'b').single, 'val'), '1');
    expect(_attr(_elements(boldRun, 'sz').single, 'val'), '36');
    expect(_attr(_elements(boldRun, 'color').single, 'val'), 'C02030');
    expect(_elements(xml, 'pgSz'), isNotEmpty);
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.headersFooters),
    );
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.notesComments),
    );
    expect(result.limitations, contains(LegacyWordConversionLimitation.images));
    final report = await inspectConvertedWord(
      result.bytes,
      extension: 'docx',
      source: inspectLegacyWordSource(source),
    );
    expect(report.counts['tables'], 1);
    expect(report.losses, contains(WordConversionLoss.headersMissing));
    expect(report.losses, contains(WordConversionLoss.footnotesMissing));
    expect(source, orderedEquals(original));
  });

  test(
    'bounds structural expansion and never silently uses the text converter',
    () {
      final source = legacyWordFixture(
        '${'A\t' * (kLegacyWordDocxBreakLimit + 1)}End\r',
      );
      expect(
        () => convertLegacyWordToStructuredDocx(source),
        throwsA(
          isA<LegacyWordConversionException>().having(
            (e) => e.issue,
            'issue',
            LegacyWordConversionIssue.tooComplex,
          ),
        ),
      );
      expect(
        () => convertLegacyWordToStructuredDocx(
          legacyWordFixture('Secret\r', encrypted: true),
        ),
        throwsFormatException,
      );
    },
  );
}
