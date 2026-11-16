import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'bibliography-layout-test';
const _code =
    'BIBL {"uncited":[],"omitted":[],"custom":[],"future":"keep"} CSL_BIBLIOGRAPHY';
const _html =
    '<div class="csl-bib-body">'
    '<div class="csl-entry">Alpha <i>Book</i>.<br/>Second line.</div>'
    '<div class="csl-entry"><b>Beta</b> Book.</div></div>';

String _prefs({bool applied = true}) => jsonEncode({
  'dataVersion': 4,
  'style': {
    'styleID': 'http://www.zotero.org/styles/chicago-notes-bibliography',
    'locale': 'de-DE',
    'bibliographyStyleHasBeenSet': applied,
    'future': 'retain-style',
  },
  'prefs': {'fieldType': 'Http', 'noteType': 0, 'future': 'retain-prefs'},
});

WordZoteroCitingSession _session(WmlDocument document, {WmlParagraph? at}) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: at ?? document.paragraphs.first,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

void _style(
  WordZoteroCitingSession session, [
  List<Object?> values = const [
    -720,
    720,
    480,
    240,
    <int>[720],
    1,
  ],
]) => _call(session, 'Document.setBibliographyStyle', values);

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.prepareReview();
  session.apply();
}

String _fieldId(WordZoteroCitingSession session) =>
    ((_call(session, 'Document.getFields', ['Http']) as List).single
            as Map)['id']
        as String;

WmlDocument _insert({String html = _html, bool style = true}) {
  final document = WmlDocument.empty(text: 'Body stays');
  final session = _session(document);
  final field = _call(session, 'Document.insertField', ['Http', 0]) as Map;
  if (style) _style(session);
  _call(session, 'Field.setCode', [field['id'], _code]);
  _call(session, 'Field.setText', [field['id'], html, true]);
  _call(session, 'Document.setDocumentData', [_prefs()]);
  _finish(session);
  expect(session.formattingWarnings, isEmpty);
  return document;
}

void _expectLayout(
  WmlZoteroField field, {
  double line = 2,
  double gap = 12,
  double left = 36,
  double hanging = 36,
  List<double> tabs = const [36],
}) {
  for (final paragraph in field.paragraphs) {
    final props = paragraph.properties;
    expect(props.indent.left, left);
    expect(props.indent.firstLine, 0);
    expect(props.indent.hanging, hanging);
    expect(props.lineSpacing, line);
    expect(props.lineSpacingRule, WmlLineSpacingRule.auto);
    expect(props.spacingBefore, 0);
    expect(props.spacingAfter, gap);
    expect(props.tabs.map((tab) => tab.position), tabs);
  }
}

void main() {
  test(
    'entry paragraphs, soft breaks and twip layout survive repeated DOCX saves',
    () {
      var document = _insert();
      for (var cycle = 0; cycle < 3; cycle++) {
        final field = WordZotero.fields(document).single;
        expect(field.paragraphs.length, 2);
        expect(field.cachedText, 'Alpha Book.\nSecond line.\nBeta Book.');
        expect(field.paragraphs.first.text, 'Alpha Book.\nSecond line.');
        expect(field.metadata!['future'], 'keep');
        expect(field.canEdit, isFalse);
        expect(
          WordZotero.canReplaceNativeBibliography(document, field),
          isTrue,
        );
        _expectLayout(field);
        expect(document.paragraphs.first.text, 'Body stays');
        final bytes = WordSerializer().writeBytes(document);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/word/document.xml')!.readText();
        expect(RegExp('w:fldCharType="begin"').allMatches(xml).length, 1);
        expect(RegExp('w:fldCharType="end"').allMatches(xml).length, 1);
        expect(xml, contains('w:hanging="720"'));
        expect(xml, contains('w:line="480"'));
        expect(xml, contains('w:after="240"'));
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'second native refresh preserves layout without another style callback',
    () {
      var document = _insert();
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final before = WordZotero.fields(document).single;
      final first = before.paragraph;
      final session = _session(document);
      final data =
          jsonDecode(_call(session, 'Document.getDocumentData') as String)
              as Map;
      expect((data['style'] as Map)['bibliographyStyleHasBeenSet'], isTrue);
      _call(session, 'Field.setText', [
        _fieldId(session),
        '<div class="csl-entry">Gamma <i>Title</i>.</div>'
            '<div class="csl-entry">Delta.</div><div class="csl-entry">Epsilon.</div>',
        true,
      ]);
      _finish(session);
      final result = WordZotero.fields(document).single;
      expect(result.paragraph, same(first));
      expect(result.paragraphs.length, 3);
      expect(result.cachedText, 'Gamma Title.\nDelta.\nEpsilon.');
      _expectLayout(result);
      expect(
        result.paragraphs.first.inlines.whereType<WmlRun>().any(
              (run) => run.text.trim() == 'Title' && run.properties.italic,
        ),
        isTrue,
      );
    },
  );

  test(
    'style-only change is staged and resets old indent, spacing and tabs',
    () {
      final document = _insert();
      final session = _session(document);
      _style(session, [0, 0, 240, 0, <int>[], 0]);
      expect(session.hasChanges, isTrue);
      _expectLayout(WordZotero.fields(document).single);
      _finish(session);
      _expectLayout(
        WordZotero.fields(document).single,
        line: 1,
        gap: 0,
        left: 0,
        hanging: 0,
        tabs: [],
      );
      expect(
        WordZotero.fields(document).single.cachedText,
        'Alpha Book.\nSecond line.\nBeta Book.',
      );
    },
  );

  test(
    'refresh can shrink entries and keep neighboring paragraphs and identity',
    () {
      final document = _insert();
      final original = WordZotero.fields(document).single;
      final first = original.paragraph;
      final after = WmlParagraph(inlines: [WmlRun(text: 'After')]);
      document.sections.single.blocks.add(after);
      final session = _session(document);
      _call(session, 'Field.setText', [
        _fieldId(session),
        '<i>Only entry</i>',
        true,
      ]);
      _finish(session);
      expect(document.paragraphs.map((p) => p.text), [
        'Body stays',
        'Only entry',
        'After',
      ]);
      expect(WordZotero.fields(document).single.paragraph, same(first));
      expect(document.paragraphs.last, same(after));
      _expectLayout(WordZotero.fields(document).single);
    },
  );

  test(
    'complete bibliography can be unlinked or deleted without losing neighbors',
    () {
      for (final command in ['Field.removeCode', 'Field.delete']) {
        final document = _insert();
        final field = WordZotero.fields(document).single;
        final first = field.paragraph;
        final session = _session(document);
        _call(session, command, [_fieldId(session)]);
        _finish(session);
        expect(WordZotero.fields(document), isEmpty);
        expect(document.paragraphs.first.text, 'Body stays');
        expect(document.paragraphs.elementAt(1), same(first));
        if (command == 'Field.removeCode') {
          expect(document.paragraphs.length, 3);
          expect(first.text, 'Alpha Book.\nSecond line.');
          expect(
            first.inlines.whereType<WmlRun>().any((r) => r.properties.italic),
            isTrue,
          );
        } else {
          expect(document.paragraphs.length, 2);
          expect(first.text, isEmpty);
        }
      }
    },
  );

  test('changed result can be unlinked in the same native transaction', () {
    final document = _insert();
    final session = _session(document);
    final id = _fieldId(session);
    _call(session, 'Field.setText', [
      id,
      '<div class="csl-entry"><i>New</i></div><div class="csl-entry">Other</div>',
      true,
    ]);
    _call(session, 'Field.removeCode', [id]);
    _finish(session);
    expect(WordZotero.fields(document), isEmpty);
    expect(document.paragraphs.map((p) => p.text), [
      'Body stays',
      'New',
      'Other',
    ]);
  });

  test('no citation insertion is permitted inside any bibliography entry', () {
    final document = _insert();
    final entries = WordZotero.fields(document).single.paragraphs;
    for (final entry in entries) {
      final session = _session(document, at: entry);
      expect(
        () => _call(session, 'Document.insertField', ['Http', 0]),
        throwsUnsupportedError,
      );
    }
    expect(WordZotero.fields(document).single.paragraphs.length, 2);
  });

  test('mixed, locked, nested and cross-container ranges remain refused', () {
    for (final kind in [
      'outside-run',
      'bookmark',
      'locked',
      'cross-cell',
      'intervening-block',
    ]) {
      final document = _insert();
      final field = WordZotero.fields(document).single;
      switch (kind) {
        case 'outside-run':
          field.paragraph.inlines.insert(0, WmlRun(text: 'Outside'));
        case 'bookmark':
          field.paragraph.properties.bookmarkName = 'outside-bookmark';
        case 'locked':
          field.paragraph.inlines[0] = WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.begin,
            sourceXml:
                '<w:fldChar xmlns:w="${OfficeNamespaces.w}" w:fldCharType="begin" w:fldLock="true"/>',
          );
        case 'cross-cell':
          document.sections.single.blocks
            ..removeRange(1, 3)
            ..add(
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: [field.paragraphs.first]),
                      WmlTableCell(blocks: [field.paragraphs.last]),
                    ],
                  ),
                ],
              ),
            );
        case 'intervening-block':
          document.sections.single.blocks.insert(2, WmlTable(rows: []));
      }
      final current = WordZotero.fields(document).single;
      expect(
        WordZotero.canReplaceNativeBibliography(document, current),
        isFalse,
        reason: kind,
      );
      expect(() => _session(document), throwsUnsupportedError, reason: kind);
    }
  });

  test(
    'legacy flattened layout is requested again and never falsely marked applied',
    () {
      final document = WmlDocument.empty(text: 'Body');
      document.zoteroDocumentData = WordZoteroDocumentData.toNative(_prefs());
      document.sections.single.blocks.add(
        WordZotero.bibliography(text: 'Alpha\nBeta'),
      );
      final session = _session(document);
      final sent =
          jsonDecode(_call(session, 'Document.getDocumentData') as String)
              as Map;
      expect((sent['style'] as Map)['bibliographyStyleHasBeenSet'], isFalse);
      expect((sent['style'] as Map)['future'], 'retain-style');
      _style(session);
      _finish(session);
      expect(
        session.formattingWarnings.single,
        contains('ambiguous legacy line breaks'),
      );
      final saved = jsonDecode(WordZoteroDocumentData.read(document)) as Map;
      expect((saved['style'] as Map)['bibliographyStyleHasBeenSet'], isFalse);
      expect(
        WordZotero.fields(document).single.paragraph.properties.explicitIndent,
        isFalse,
      );
    },
  );

  test(
    'native refresh upgrades flattened legacy bibliography with real entry boundaries',
    () {
      final document = WmlDocument.empty(text: 'Body');
      document.sections.single.blocks.add(
        WordZotero.bibliography(text: 'Alpha\nBeta'),
      );
      final session = _session(document);
      _style(session);
      _call(session, 'Field.setText', [_fieldId(session), _html, true]);
      _call(session, 'Document.setDocumentData', [_prefs()]);
      _finish(session);
      expect(session.formattingWarnings, isEmpty);
      expect(WordZotero.fields(document).single.paragraphs.length, 2);
      _expectLayout(WordZotero.fields(document).single);
    },
  );

  test('XML bibliography flag reset preserves unrelated native attributes', () {
    const input =
        '<data data-version="3"><style id="style" bibliographyStyleHasBeenSet="1" future="keep"/>'
        '<prefs><pref name="fieldType" value="Field"/><pref name="future" value="keep"/></prefs></data>';
    final result = WordZoteroDocumentData.requestBibliographyStyle(input);
    expect(result, contains('bibliographyStyleHasBeenSet="0"'));
    expect(result, contains('future="keep"'));
    expect(result, contains('name="future" value="keep"'));
    expect(WordZoteroDocumentData.requestBibliographyStyle(result), result);
  });

  test(
    'new entries do not repeat first-paragraph page breaks or drop caps',
    () {
      final props = WmlParagraphProps(
        pageBreakBefore: true,
        columnBreakBefore: true,
        numId: 1,
        headingLevel: 1,
        dropCapLines: 3,
      );
      final rich = ZoteroFormattedText.fromHtml(
        '<div class="csl-entry">A</div><div class="csl-entry">B</div>',
      );
      final entries = WordZotero.nativeBibliographyParagraphs(
        instruction: ' ADDIN ZOTERO_$_code ',
        text: rich.plainText,
        formattedText: rich,
        paragraphProperties: props,
      );
      expect(entries.first.properties.pageBreakBefore, isTrue);
      expect(entries.last.properties.pageBreakBefore, isFalse);
      expect(entries.last.properties.columnBreakBefore, isFalse);
      expect(entries.last.properties.numId, isNull);
      expect(entries.last.properties.headingLevel, isNull);
      expect(entries.last.properties.dropCapLines, 0);
    },
  );

  test('invalid layout values are rejected before any document mutation', () {
    final document = _insert();
    final before = WordZotero.fields(document).single.cachedText;
    for (final values in <List<Object?>>[
      [-720, 720, 0, 0, <int>[], 0],
      [-720, 720, -240, 0, <int>[], 0],
      [-720, 720, 240, -1, <int>[], 0],
      [
        -720,
        720,
        240,
        0,
        [-1],
        1,
      ],
      [-720, double.infinity, 240, 0, <int>[], 0],
      [
        -720,
        720,
        240,
        0,
        [720],
        2,
      ],
      [
        -720,
        720,
        240,
        0,
        [double.nan],
        1,
      ],
    ]) {
      final session = _session(document);
      expect(() => _style(session, values), throwsFormatException);
      expect(session.hasChanges, isFalse);
      expect(WordZotero.fields(document).single.cachedText, before);
      _expectLayout(WordZotero.fields(document).single);
    }
  });
}
