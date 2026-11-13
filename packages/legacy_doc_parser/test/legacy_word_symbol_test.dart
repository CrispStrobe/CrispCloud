// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/symbol_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
XmlDocument _xml(LegacyWordDocument document) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

List<LegacyWordRun> _runs(LegacyWordDocument document) => document.blocks
    .whereType<LegacyWordParagraph>()
    .expand((p) => p.runs)
    .toList();

void main() {
  test(
    'CSymbol preserves font/code separately from ordinary run fonts and CPs',
    () {
      final source = symbolWordFixture();
      final document = parseLegacyWordDocument(source);
      final run = _runs(document).singleWhere((run) => run.symbol != null);
      expect(run.startCp, 1);
      expect(run.endCp, 2);
      expect(run.text, '\ufffc');
      expect(run.style.fontName, 'Ordinary Face');
      expect(
        run.symbol,
        const LegacyWordSymbol(
          fontName: 'Symbol',
          fontTableIndex: 1,
          characterCode: 0xf061,
        ),
      );
      expect(document.plainText, 'A\ufffcB');
      expect(extractLegacyWordText(source), 'A(B');
      final symbol = _xml(
        document,
      ).findAllElements('sym', namespace: _w).single;
      expect(symbol.getAttribute('font', namespace: _w), 'Symbol');
      expect(symbol.getAttribute('char', namespace: _w), 'F061');
      expect(document.safeHtml, contains('data-word-symbol="F061"'));
      expect(document.safeHtml, contains('\uf061'));
      expect(
        document.safeHtml,
        contains("font-family:'\\53 \\79 \\6d \\62 \\6f \\6c '"),
      );
    },
  );

  test(
    'designation overrides an earlier false; a later false stays qualified',
    () {
      for (final operations in [
        symbolOperands(),
        [
          ...wordSprm(0x0855, [1]),
          ...symbolOperands(),
        ],
        [
          ...wordSprm(0x0855, [0]),
          ...symbolOperands(),
        ],
      ]) {
        final document = parseLegacyWordDocument(
          symbolWordFixture(operations: operations),
        );
        expect(
          _runs(document).where((run) => run.symbol != null),
          hasLength(1),
        );
      }
      final cleared = parseLegacyWordDocument(
        symbolWordFixture(
          operations: [
            ...symbolOperands(),
            ...wordSprm(0x0855, [0]),
          ],
        ),
      );
      expect(_runs(cleared).every((run) => run.symbol == null), isTrue);
      expect(cleared.plainText, 'A(B');
      expect(
        cleared.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
      expect(
        convertLegacyWordDocument(cleared).limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final ordinary = parseLegacyWordDocument(
        symbolWordFixture(operations: []),
      );
      expect(ordinary.plainText, 'A(B');
      expect(_xml(ordinary).findAllElements('sym', namespace: _w), isEmpty);
    },
  );

  test(
    'inherited glyphs respect direct overrides and repeated run coalescing',
    () {
      final repeated = parseLegacyWordDocument(
        symbolWordFixture(text: 'A((B\r', end: 3),
      );
      final run = _runs(repeated).singleWhere((run) => run.symbol != null);
      expect((run.startCp, run.endCp, run.text), (1, 3, '\ufffc\ufffc'));
      expect(
        _xml(repeated).findAllElements('sym', namespace: _w),
        hasLength(2),
      );
      final inherited = parseLegacyWordDocument(
        symbolWordFixture(
          text: '(\r',
          start: 0,
          end: 1,
          inherited: symbolOperands(),
          operations: symbolOperands(font: 2, code: 0xf0fc),
        ),
      );
      expect(_runs(inherited).single.symbol!.fontName, 'Wingdings');
      expect(_runs(inherited).single.symbol!.characterCode, 0xf0fc);
      final cleared = parseLegacyWordDocument(
        symbolWordFixture(
          text: '(\r',
          start: 0,
          end: 1,
          inherited: symbolOperands(),
          operations: wordSprm(0x0855, [0]),
        ),
      );
      expect(_runs(cleared).single.symbol, isNull);
      expect(
        cleared.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
    },
  );

  test('a symbol cannot consume adjacent ordinary characters or PUA text', () {
    final ordinary = parseLegacyWordDocument(
      symbolWordFixture(text: 'A\uf061B\r', operations: []),
    );
    expect(ordinary.plainText, 'A\uf061B');
    expect(_xml(ordinary).findAllElements('sym', namespace: _w), isEmpty);
    final nonAnchor = parseLegacyWordDocument(symbolWordFixture(text: 'AXB\r'));
    expect(nonAnchor.plainText, 'AXB');
    expect(_runs(nonAnchor).every((run) => run.symbol == null), isTrue);
    expect(
      nonAnchor.warnings,
      contains(LegacyWordWarning.unsupportedFormatting),
    );
  });

  test(
    'hidden and tracked glyphs retain presentation and revision wrappers',
    () {
      final hidden = parseLegacyWordDocument(
        symbolWordFixture(
          operations: [
            ...symbolOperands(),
            ...wordSprm(0x083c, [1]),
          ],
        ),
      );
      expect(hidden.plainText, 'AB');
      expect(hidden.safeHtml, isNot(contains('\uf061')));
      expect(_xml(hidden).findAllElements('sym', namespace: _w), hasLength(1));
      for (final (sprm, wrapper) in [(0x0800, 'del'), (0x0801, 'ins')]) {
        final document = parseLegacyWordDocument(
          symbolWordFixture(
            operations: [
              ...symbolOperands(),
              ...wordSprm(sprm, [1]),
            ],
          ),
        );
        final revision = _xml(
          document,
        ).findAllElements(wrapper, namespace: _w).single;
        expect(revision.findAllElements('sym', namespace: _w), hasLength(1));
        expect(revision.findAllElements('t', namespace: _w), isEmpty);
        expect(revision.findAllElements('delText', namespace: _w), isEmpty);
      }
    },
  );

  test('malformed and unresolved source symbol operands fail closed', () {
    for (final operations in [
      symbolOperands(font: 3),
      symbolOperands(font: 0xffff),
      [0x09, 0x6a, 1, 0, 0x61],
    ]) {
      expect(
        () =>
            parseLegacyWordDocument(symbolWordFixture(operations: operations)),
        throwsFormatException,
      );
    }
    expect(
      () => parseLegacyWordDocument(symbolWordFixture(fonts: [])),
      throwsFormatException,
    );
    expect(
      () => parseLegacyWordDocument(
        symbolWordFixture(fonts: ['Ordinary Face', '']),
      ),
      throwsFormatException,
    );
  });

  test('public glyph runs validate operand and opaque text contracts', () {
    for (final symbol in [
      const LegacyWordSymbol(fontName: '', characterCode: 0xf061),
      const LegacyWordSymbol(fontName: 'Symbol', characterCode: -1),
      const LegacyWordSymbol(fontName: 'Symbol', characterCode: 0x10000),
      const LegacyWordSymbol(
        fontName: 'Symbol',
        characterCode: 0xf061,
        fontTableIndex: -1,
      ),
    ]) {
      expect(() => symbol.hexadecimalCode, throwsFormatException);
    }
    const glyph = LegacyWordSymbol(fontName: 'Symbol', characterCode: 0xf061);
    for (final text in ['(', '\uf061', '\ufffcX']) {
      final document = LegacyWordDocument(
        blocks: [
          LegacyWordParagraph(
            startCp: 0,
            endCp: text.length + 1,
            runs: [
              LegacyWordRun(
                startCp: 0,
                endCp: text.length,
                text: text,
                symbol: glyph,
              ),
            ],
          ),
        ],
        sections: const [],
        plainText: '',
        safeHtml: '',
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
      expect(
        () => renderLegacyWordHtml(document.blocks),
        throwsFormatException,
      );
    }
  });

  test('bookmark event splitting preserves repeated glyph metadata', () {
    final parsed = parseLegacyWordDocument(
      symbolWordFixture(text: 'A((B\r', end: 3),
    );
    final document = LegacyWordDocument(
      blocks: parsed.blocks,
      sections: parsed.sections,
      plainText: parsed.plainText,
      safeHtml: parsed.safeHtml,
      bookmarks: const [
        LegacyWordBookmark(name: 'BetweenGlyphs', startCp: 2, endCp: 3),
      ],
    );
    final xml = _xml(document);
    expect(xml.findAllElements('sym', namespace: _w), hasLength(2));
    final paragraph = xml.findAllElements('p', namespace: _w).first;
    expect(
      paragraph.children.whereType<XmlElement>().map((node) => node.name.local),
      ['pPr', 'r', 'r', 'bookmarkStart', 'r', 'bookmarkEnd', 'r'],
    );
  });

  test(
    'a changed prior glyph remains an explicit revision-history limitation',
    () {
      final document = parseLegacyWordDocument(
        symbolWordFixture(
          operations: [
            ...symbolOperands(),
            ...wordSprm(0x2a83, [1]),
            ...symbolOperands(code: 0xf062),
          ],
        ),
      );
      final run = _runs(document).singleWhere((run) => run.symbol != null);
      expect(run.symbol!.characterCode, 0xf062);
      expect(run.formattingRevision!.previousPropertiesComplete, isFalse);
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
    },
  );

  test(
    'native-export parent and independently authored CSymbol control stay distinct',
    () {
      final document = parseLegacyWordDocument(
        File(
          'test/fixtures/word_native/symbol-source-control.doc',
        ).readAsBytesSync(),
      );
      final run = _runs(document).singleWhere((run) => run.symbol != null);
      expect(run.symbol!.fontName, 'Symbol');
      expect(run.symbol!.characterCode, 0xf061);
      expect(document.plainText, startsWith('SYMBOL-1:[\ufffc]'));
      expect(
        _xml(document).findAllElements('sym', namespace: _w),
        hasLength(1),
      );
      expect(document.plainText, contains('SYMBOL-2:[\uf057]'));
    },
  );
}
