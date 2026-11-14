// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/legacy_word_structured_model.dart';
import 'package:legacy_doc_parser/src/legacy_word_structured_render.dart';
import 'package:test/test.dart';

LegacyWordParagraph _paragraph(
  String text, {
  int cp = 0,
  LegacyWordParagraphStyle style = const LegacyWordParagraphStyle(),
  LegacyWordCharacterStyle character = const LegacyWordCharacterStyle(),
}) => LegacyWordParagraph(
  startCp: cp,
  endCp: cp + text.length + 1,
  style: style,
  runs: [
    LegacyWordRun(
      startCp: cp,
      endCp: cp + text.length,
      text: text,
      style: character,
    ),
  ],
);

LegacyWordParagraph _item(
  int cp, {
  int id = 1,
  int level = 0,
  String text = 'x',
}) => _paragraph(
  text,
  cp: cp,
  style: LegacyWordParagraphStyle(listId: id, listLevel: level),
);

LegacyWordNumberingDefinition _list(
  String format, {
  int id = 1,
  int start = 1,
  String text = '%1.',
  LegacyWordCharacterStyle style = const LegacyWordCharacterStyle(),
}) => LegacyWordNumberingDefinition(
  id: id,
  levels: [
    LegacyWordNumberingLevel(
      level: 0,
      format: format,
      text: text,
      startAt: start,
      characterStyle: style,
      suffix: LegacyWordListSuffix.space,
    ),
  ],
);

List<String> _labels(String html) =>
    RegExp(r'<span data-word-list-label="true"[^>]*>(.*?)</span>', dotAll: true)
        .allMatches(html)
        .map((match) => match.group(1)!.replaceAll(RegExp('<[^>]*>'), ''))
        .toList();

void main() {
  test('renders underline variants independently of double strike', () {
    const variants = {
      'single': 'solid',
      'double': 'double',
      'dotted': 'dotted',
      'dottedHeavy': 'dotted',
      'dash': 'dashed',
      'dotDash': 'dashed',
      'dotDotDash': 'dashed',
      'dashLong': 'dashed',
      'wave': 'wavy',
      'wavyHeavy': 'wavy',
      'wavyDouble': 'wavy',
    };
    for (final variant in variants.entries) {
      final html = renderLegacyWordHtml([
        _paragraph(
          'visible',
          character: LegacyWordCharacterStyle(
            underline: true,
            underlineStyle: variant.key,
            doubleStrike: true,
          ),
        ),
      ]);
      expect(
        html,
        contains('text-decoration:line-through;text-decoration-style:double'),
      );
      expect(
        html,
        contains(
          'text-decoration:underline;text-decoration-style:${variant.value}',
        ),
      );
      expect(html, contains('visible</span></span>'));
      expect(
        html.contains('text-decoration-thickness:0.12em'),
        variant.key.endsWith('Heavy'),
      );
    }
    final words = renderLegacyWordHtml([
      _paragraph(
        'two words',
        character: const LegacyWordCharacterStyle(
          underline: true,
          underlineStyle: 'words',
        ),
      ),
    ]);
    expect(words, contains('data-word-underline="approximate"'));
    final hostile = renderLegacyWordHtml([
      _paragraph(
        'safe',
        character: const LegacyWordCharacterStyle(
          underline: true,
          underlineStyle: 'url(https://invalid.test/image)',
        ),
      ),
      _paragraph(
        'hidden',
        character: const LegacyWordCharacterStyle(
          hidden: true,
          underline: true,
          underlineStyle: 'wave',
        ),
      ),
    ]);
    expect(hostile, isNot(contains('invalid.test')));
    expect(hostile, isNot(contains('hidden')));
    expect(hostile, contains('data-word-underline="approximate"'));
  });

  test('renders supported list formats without changing paragraph text', () {
    final paragraphs = [for (var i = 0; i < 3; i++) _item(i * 2)];
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('decimal', start: 7)],
        ),
      ),
      ['7.', '8.', '9.'],
    );
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('decimalZero', start: 8)],
        ),
      ),
      ['08.', '09.', '10.'],
    );
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('upperRoman', start: 4)],
        ),
      ),
      ['IV.', 'V.', 'VI.'],
    );
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('lowerRoman', start: 9)],
        ),
      ),
      ['ix.', 'x.', 'xi.'],
    );
    // Word uses repeated letters after Z, not spreadsheet column labels.
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('upperLetter', start: 26)],
        ),
      ),
      ['Z.', 'AA.', 'BB.'],
    );
    expect(
      _labels(
        renderLegacyWordHtml(
          paragraphs,
          numberingDefinitions: [_list('lowerLetter', start: 52)],
        ),
      ),
      ['zz.', 'aaa.', 'bbb.'],
    );
    expect(paragraphs.map((p) => p.runs.single.text), ['x', 'x', 'x']);
  });

  test('applies multilevel restart and legal decimal placeholders', () {
    const definition = LegacyWordNumberingDefinition(
      id: 1,
      levels: [
        LegacyWordNumberingLevel(
          level: 0,
          format: 'upperRoman',
          text: '%1.',
          startAt: 4,
        ),
        LegacyWordNumberingLevel(
          level: 1,
          format: 'lowerLetter',
          text: '%1.%2)',
          legal: true,
        ),
      ],
    );
    final paragraphs = [
      _item(0),
      _item(2, level: 1),
      _item(4, level: 1),
      _item(6),
      _item(8, level: 1),
    ];
    expect(
      _labels(
        renderLegacyWordHtml(paragraphs, numberingDefinitions: [definition]),
      ),
      ['IV.', '4.1)', '4.2)', 'V.', '5.1)'],
    );
    const neverRestart = LegacyWordNumberingDefinition(
      id: 1,
      levels: [
        LegacyWordNumberingLevel(level: 0, format: 'decimal', text: '%1.'),
        LegacyWordNumberingLevel(
          level: 1,
          format: 'lowerLetter',
          text: '%2)',
          restartAfterLevel: 0,
        ),
      ],
    );
    expect(
      _labels(
        renderLegacyWordHtml(paragraphs, numberingDefinitions: [neverRestart]),
      ),
      ['1.', 'a)', 'b)', '2.', 'c)'],
    );
  });

  test(
    'numbers source CP order before vertical cell merging reorders markup',
    () {
      final table = LegacyWordTable(
        startCp: 0,
        endCp: 8,
        rows: [
          LegacyWordTableRow(
            cells: [
              LegacyWordTableCell(
                paragraphs: [_item(0)],
                verticalMergeStart: true,
              ),
              LegacyWordTableCell(paragraphs: [_item(2)]),
            ],
          ),
          LegacyWordTableRow(
            cells: [
              LegacyWordTableCell(
                paragraphs: [_item(4)],
                verticalMergeContinue: true,
              ),
              LegacyWordTableCell(paragraphs: [_item(6)]),
            ],
          ),
        ],
      );
      expect(
        _labels(
          renderLegacyWordHtml(
            [table],
            numberingDefinitions: [_list('decimal')],
          ),
        ),
        ['1.', '3.', '2.', '4.'],
      );
    },
  );

  test('keeps unsupported formats explicit and bullet markup escaped', () {
    final unsupported = renderLegacyWordHtml(
      [_item(0)],
      numberingDefinitions: [_list('chineseCounting')],
    );
    expect(_labels(unsupported), isEmpty);
    expect(unsupported, contains('data-word-numbering="unsupported"'));
    final bullet = renderLegacyWordHtml(
      [_item(0)],
      numberingDefinitions: [
        _list(
          'bullet',
          text: '<&>',
          style: const LegacyWordCharacterStyle(bold: true, colorHex: '123456'),
        ),
      ],
    );
    expect(_labels(bullet), ['&lt;&amp;&gt;']);
    expect(bullet, contains('color:#123456'));
    expect(bullet, isNot(contains('<&>')));
    expect(
      _labels(
        renderLegacyWordHtml([_item(0)], numberingDefinitions: [_list('none')]),
      ),
      ['.'],
    );
    expect(
      _labels(
        renderLegacyWordHtml(
          [_item(0)],
          numberingDefinitions: [_list('none', text: '%1')],
        ),
      ),
      isEmpty,
    );
  });

  test('body runs and list markers retain independent visibility', () {
    // A marker has its own character properties; hiding the body does not
    // make a separately visible marker hidden. Binary hidden-body/marker
    // fixtures exercise the same contract in both Word output modes.
    for (final hiddenBody in [false, true]) {
      for (final hiddenMarker in [false, true]) {
        final paragraph = _paragraph(
          'body-value',
          style: const LegacyWordParagraphStyle(listId: 1),
          character: LegacyWordCharacterStyle(hidden: hiddenBody),
        );
        final html = renderLegacyWordHtml(
          [paragraph],
          numberingDefinitions: [
            _list(
              'bullet',
              text: 'marker-value',
              style: LegacyWordCharacterStyle(hidden: hiddenMarker),
            ),
          ],
        );
        expect(html.contains('body-value'), !hiddenBody);
        expect(html.contains('marker-value'), !hiddenMarker);
        expect(_labels(html), hiddenMarker ? isEmpty : ['marker-value']);
      }
    }
  });

  test(
    'compatible instances share their source sequence without an override',
    () {
      final definitions = [
        for (final id in [1, 2])
          LegacyWordNumberingDefinition(
            id: id,
            sourceListId: 77,
            levels: const [
              LegacyWordNumberingLevel(
                level: 0,
                format: 'decimal',
                text: '%1.',
              ),
            ],
          ),
      ];
      final html = renderLegacyWordHtml([
        _item(0),
        _item(2, id: 2),
      ], numberingDefinitions: definitions);
      expect(_labels(html), ['1.', '2.']);
      expect(
        html,
        isNot(contains('data-word-numbering="instance-approximation"')),
      );
    },
  );

  test(
    'renders basic paragraph border color width spacing and ignores bar',
    () {
      final html = renderLegacyWordHtml([
        _paragraph(
          'border',
          style: const LegacyWordParagraphStyle(
            borders: {
              LegacyWordBorderSide.top: LegacyWordBorder(
                style: 'single',
                widthEighthPoints: 12,
                colorHex: '112233',
                spacingPoints: 3,
                shadow: true,
              ),
              LegacyWordBorderSide.right: LegacyWordBorder(
                style: 'double',
                widthEighthPoints: 16,
              ),
              LegacyWordBorderSide.bar: LegacyWordBorder(
                style: 'single',
                widthEighthPoints: 80,
                colorHex: 'FEAABB',
              ),
            },
          ),
        ),
      ]);
      expect(html, contains('border-top:1.5pt solid #112233'));
      expect(html, contains('padding-top:3pt'));
      expect(html, contains('border-right:2.0pt double currentColor'));
      expect(html, isNot(contains('FEAABB')));
      expect(html, isNot(contains('box-shadow')));
    },
  );

  test('uses between borders only for adjacent matching paragraph groups', () {
    const style = LegacyWordParagraphStyle(
      borders: {
        LegacyWordBorderSide.top: LegacyWordBorder(
          style: 'single',
          widthEighthPoints: 8,
        ),
        LegacyWordBorderSide.bottom: LegacyWordBorder(
          style: 'single',
          widthEighthPoints: 8,
        ),
        LegacyWordBorderSide.between: LegacyWordBorder(
          style: 'dotted',
          widthEighthPoints: 4,
          colorHex: 'ABCDEF',
        ),
      },
    );
    final html = renderLegacyWordHtml([
      _paragraph('a', style: style),
      _paragraph('b', cp: 2, style: style),
    ]);
    expect(
      RegExp('border-top:0.5pt dotted #ABCDEF').allMatches(html),
      hasLength(1),
    );
    expect(RegExp('border-top:1.0pt solid').allMatches(html), hasLength(1));
    final separated = renderLegacyWordHtml([
      _paragraph('a', style: style),
      _paragraph('b', cp: 4, style: style),
    ]);
    expect(separated, isNot(contains('border-top:0.5pt dotted')));
  });

  test(
    'keeps clear and solid shading color roles distinct in paragraphs and cells',
    () {
      const clear = LegacyWordShading(
        pattern: 'clear',
        foregroundHex: '010203',
        backgroundHex: 'AABBCC',
      );
      const solid = LegacyWordShading(
        pattern: 'solid',
        foregroundHex: '102030',
        backgroundHex: 'DDEEFF',
      );
      final html = renderLegacyWordHtml([
        _paragraph(
          'clear',
          style: const LegacyWordParagraphStyle(shading: clear),
        ),
        LegacyWordTable(
          startCp: 6,
          endCp: 12,
          rows: [
            LegacyWordTableRow(
              cells: [
                LegacyWordTableCell(
                  paragraphs: [_paragraph('solid', cp: 6)],
                  shading: solid,
                ),
              ],
            ),
          ],
        ),
      ]);
      expect(html, contains('background-color:#AABBCC'));
      expect(html, contains('background-color:#102030'));
      expect(html, isNot(contains('background-color:#010203')));
      expect(html, isNot(contains('background-color:#DDEEFF')));
    },
  );

  test(
    'labels patterned shading as approximate and never treats unknown as clear',
    () {
      final html = renderLegacyWordHtml([
        _paragraph(
          'percentage',
          style: const LegacyWordParagraphStyle(
            shading: LegacyWordShading(
              pattern: 'pct25',
              foregroundHex: '000000',
              backgroundHex: 'FFFFFF',
            ),
          ),
        ),
        _paragraph(
          'unknown',
          cp: 11,
          style: const LegacyWordParagraphStyle(
            shading: LegacyWordShading(
              pattern: null,
              rawPattern: 62,
              foregroundHex: '112233',
              backgroundHex: 'EEEEEE',
            ),
          ),
        ),
      ]);
      expect(html, contains('background-color:#bfbfbf'));
      expect(
        RegExp('data-word-shading="approximate"').allMatches(html),
        hasLength(2),
      );
    },
  );

  test(
    'renders default and uniform tab spacing while preserving source tab characters',
    () {
      final defaultHtml = renderLegacyWordHtml([
        _paragraph('a\tb'),
      ], defaultTabStopTwips: 720);
      expect(defaultHtml, contains('tab-size:36.0pt'));
      expect(defaultHtml, contains('a\tb'));
      final custom = renderLegacyWordHtml([
        _paragraph(
          'a\tb\tc',
          style: const LegacyWordParagraphStyle(
            tabs: [
              LegacyWordTabStop(positionTwips: 360),
              LegacyWordTabStop(positionTwips: 720),
            ],
          ),
        ),
      ]);
      expect(custom, contains('tab-size:18.0pt'));
      expect(custom, contains('data-word-tabs="uniform-approximation"'));
      final irregular = renderLegacyWordHtml([
        _paragraph(
          'a\tb',
          style: const LegacyWordParagraphStyle(
            tabs: [
              LegacyWordTabStop(
                positionTwips: 500,
                alignment: LegacyWordTabAlignment.decimal,
                leader: LegacyWordTabLeader.dot,
              ),
            ],
          ),
        ),
      ]);
      expect(irregular, contains('data-word-tabs="approximate"'));
      expect(irregular, isNot(contains('tab-size:25.0pt')));
      expect(irregular, contains('a\tb'));
    },
  );

  test(
    'rejects malformed or explosively expanded numbering and CSS dimensions',
    () {
      expect(
        () => renderLegacyWordHtml(
          [_item(0)],
          numberingDefinitions: [_list('decimal'), _list('decimal')],
        ),
        throwsFormatException,
      );
      expect(
        () => renderLegacyWordHtml(
          [_item(0)],
          numberingDefinitions: [
            _list('upperLetter', start: 26000, text: '%1' * 500),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => renderLegacyWordHtml([
          _paragraph(
            'x',
            style: const LegacyWordParagraphStyle(
              tabs: [
                LegacyWordTabStop(positionTwips: 100),
                LegacyWordTabStop(positionTwips: 100),
              ],
            ),
          ),
        ]),
        throwsFormatException,
      );
      final hostile = renderLegacyWordHtml([
        _paragraph(
          'safe',
          style: const LegacyWordParagraphStyle(
            borders: {
              LegacyWordBorderSide.left: LegacyWordBorder(
                style: 'url(https://invalid.test)',
                widthEighthPoints: 8,
                colorHex: 'red;display:none',
              ),
            },
            shading: LegacyWordShading(
              pattern: 'solid',
              foregroundHex: 'url(https://invalid.test)',
            ),
          ),
        ),
      ]);
      expect(hostile, isNot(contains('url(')));
      expect(hostile, isNot(contains('display:none')));
    },
  );
}
