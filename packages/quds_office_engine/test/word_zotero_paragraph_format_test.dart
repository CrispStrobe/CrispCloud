import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _id = 'research-paragraph-layout';

String _placeholder(String id) =>
    '<a href="https://www.zotero.org/?$id">old $id</a>';

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

WordZoteroCitingSession _stage(
  WmlDocument document,
  String html, {
  int start = 0,
  int? end,
  List<String> citations = const [],
}) {
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _id,
    insertionParagraph: document.paragraphs.first,
    insertionOffset: start,
    insertionEndOffset: end,
  );
  _call(session, 'Document.setDocumentData', [
    jsonEncode({
      'dataVersion': 4,
      'sessionID': _id,
      'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'ar'},
      'prefs': {'fieldType': 'Http', 'noteType': 0},
    }),
  ]);
  final temp = _call(session, 'Document.insertField', ['Http', 0]) as Map;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
  if (citations.isNotEmpty) {
    final fields =
        _call(session, 'Document.convertPlaceholdersToFields', [
              citations,
              0,
              'Http',
            ])
            as List;
    for (var i = 0; i < citations.length; i++) {
      final id = citations[i];
      final field = fields[i] as Map;
      final citation = ZoteroCitation(
        citationId: id,
        plainCitation: '($id)',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
          ),
        ],
      );
      _call(session, 'Field.setCode', [
        field['id'],
        'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
      ]);
      _call(session, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
    }
  }
  _call(session, 'Document.complete');
  return session;
}

WmlDocument _insert(String html, {List<String> citations = const []}) {
  final document = WmlDocument.empty();
  _stage(document, html, citations: citations).apply();
  return document;
}

void main() {
  test('canonical direction, alignment and indent stay paragraph metadata', () {
    final parsed = WordZoteroNoteText.fromHtml(
      '<p dir="rtl" data-indent="2" '
      'style="text-align: justify; padding-right: 80px">أول 😀 '
      '${_placeholder('FIRST1')}</p>'
      '<h3 dir="ltr" style="text-align:center">Heading</h3>'
      '<p data-indent="1" style="padding-right:40px">Implicit side</p>'
      '<p>Ordinary</p>',
    );
    expect(
      parsed.plainText,
      'أول 😀 old FIRST1\nHeading\nImplicit side\nOrdinary',
    );
    expect(parsed.paragraphFormats.keys, [0, 1, 2]);
    final rtl = parsed.paragraphFormats[0]!;
    expect(rtl.rightToLeft, isTrue);
    expect(rtl.justification, WmlJustification.justify);
    expect(rtl.indentPoints, 60);
    expect(rtl.indentOnRight, isTrue);
    expect(parsed.paragraphFormats[1]!.rightToLeft, isFalse);
    expect(parsed.paragraphFormats[1]!.justification, WmlJustification.center);
    expect(parsed.paragraphFormats[2]!.rightToLeft, isNull);
    expect(parsed.paragraphFormats[2]!.indentOnRight, isTrue);
    expect(parsed.placeholders['FIRST1']!.start, 'أول 😀 '.length);
    expect(parsed.plainText, isNot(contains(RegExp('[\uE000-\uE002]'))));
  });

  test('empty paragraphs and headings keep one layout owner each', () {
    final document = _insert(
      '<p dir="rtl" data-indent="1"></p>'
      '<h2 dir="ltr" data-indent="2" style="text-align:right"></h2>'
      '<p>After</p>',
    );
    final paragraphs = document.paragraphs.toList();
    expect(paragraphs.map((p) => p.text), ['', '', 'After']);
    expect(paragraphs[0].properties.rightToLeft, isTrue);
    expect(paragraphs[0].properties.indent.right, 30);
    expect(paragraphs[1].properties.headingLevel, 2);
    expect(paragraphs[1].properties.rightToLeft, isFalse);
    expect(paragraphs[1].properties.justification, WmlJustification.right);
    expect(paragraphs[1].properties.indent.left, 60);
  });

  test(
    'every supported alignment is explicit after native heading styling',
    () {
      for (final entry in {
        'left': WmlJustification.left,
        'right': WmlJustification.right,
        'center': WmlJustification.center,
        'justify': WmlJustification.justify,
      }.entries) {
        final document = _insert(
          '<h1 dir="ltr" style="text-align:${entry.key}">Title</h1>',
        );
        final props = document.paragraphs.single.properties;
        expect(props.justification, entry.value);
        expect(props.explicitJustification, isTrue);
        expect(props.rightToLeft, isFalse);
      }
    },
  );

  test(
    'compatibility padding is counted once and follows its physical side',
    () {
      final document = _insert(
        '<p data-indent="7" style="padding-left:280px">Maximum</p>'
        '<p data-indent="2" style="padding-right:80px">Implicit RTL editor</p>'
        '<p dir="rtl" data-indent="1">RTL fallback</p>'
        '<p dir="ltr" data-indent="1">LTR fallback</p>',
      );
      final paragraphs = document.paragraphs.toList();
      expect(paragraphs[0].properties.indent.left, 210);
      expect(paragraphs[0].properties.indent.right, 0);
      expect(paragraphs[1].properties.indent.left, 0);
      expect(paragraphs[1].properties.indent.right, 60);
      expect(paragraphs[1].properties.rightToLeft, isNull);
      expect(paragraphs[2].properties.justification, WmlJustification.right);
      expect(paragraphs[2].properties.indent.right, 30);
      expect(paragraphs[3].properties.justification, WmlJustification.left);
      expect(paragraphs[3].properties.indent.left, 30);
    },
  );

  test('right alignment leaves unspecified reading direction automatic', () {
    final document = _insert('<p style="text-align:right">ABC (123) مرحبا</p>');
    final paragraph = document.paragraphs.single;
    expect(paragraph.properties.rightToLeft, isNull);
    expect(paragraph.properties.explicitJustification, isTrue);
    expect(paragraph.properties.bidiBaseLevel, isNull);
    List<int> glyphs() => [
      for (final page in WordLayoutEngine(font: null).layout(document).pages)
        for (final line in page.lines)
          for (final glyph in line.glyphs) glyph.glyph.codePoint,
    ];
    final automatic = glyphs();
    paragraph.properties.rightToLeft = false;
    expect(
      glyphs(),
      automatic,
      reason: 'The first strong Latin text chooses LTR',
    );
    paragraph.properties.rightToLeft = true;
    expect(glyphs(), isNot(automatic));
    // Existing implicit-right direction hints retain their legacy behavior.
    expect(
      WmlParagraphProps(justification: WmlJustification.right).bidiBaseLevel,
      1,
    );
  });

  test('layout composes once with quotes and numbered item continuations', () {
    final document = _insert(
      '<blockquote><p dir="rtl" data-indent="2" '
      'style="padding-right:80px">Quote</p>'
      '<ol start="3"><li><p dir="ltr" data-indent="1">Item</p>'
      '<p data-indent="2" style="padding-left:80px">Continuation</p>'
      '</li></ol></blockquote>',
    );
    final paragraphs = document.paragraphs.toList();
    expect(paragraphs[0].properties.indent.left, 18);
    expect(paragraphs[0].properties.indent.right, 60);
    expect(paragraphs[1].properties.indent.left, 66);
    expect(paragraphs[1].properties.indent.hanging, 9);
    expect(paragraphs[1].properties.listLabel, '3. ');
    expect(paragraphs[2].properties.indent.left, 96);
    expect(paragraphs[2].properties.listLabel, isNull);
    expect(paragraphs[2].properties.numberingSuppressed, isTrue);
  });

  test('merged table continuation cells cannot steal paragraph formatting', () {
    final parsed = WordZoteroNoteText.fromHtml(
      '<table><tr><td rowspan="2"><p>Spanning</p></td>'
      '<td><p dir="rtl" data-indent="1">أول ${_placeholder('FIRST1')}</p>'
      '</td></tr><tr><td><p dir="ltr" data-indent="2" '
      'style="text-align:center">Second ${_placeholder('SECOND2')}</p>'
      '</td></tr></table><p>Tail</p>',
    );
    expect(parsed.paragraphs.map((p) => p.text), [
      'Spanning',
      'أول old FIRST1',
      '',
      'Second old SECOND2',
      'Tail',
    ]);
    expect(parsed.paragraphFormats.keys, [1, 3]);
    expect(parsed.paragraphFormats[1]!.rightToLeft, isTrue);
    expect(parsed.paragraphFormats[3]!.rightToLeft, isFalse);
    expect(parsed.placeholders['SECOND2']!.paragraphIndex, 3);
    final native = WordTree.paragraphs(parsed.blocks).toList();
    for (var i = 0; i < native.length; i++) {
      expect(parsed.paragraphs[i], same(native[i]));
    }
  });

  test('format-only paragraphs split styled host prose at the insertion', () {
    final document = WmlDocument.empty(text: 'BeforechosenAfter');
    final original = document.paragraphs.single;
    original.properties
      ..rightToLeft = true
      ..justification = WmlJustification.center
      ..explicitJustification = true
      ..indent = const WmlIndent(left: 7, right: 11, firstLine: 3)
      ..explicitIndent = true;
    final session = _stage(
      document,
      '<p dir="ltr" data-indent="1">Imported</p>',
      start: 6,
      end: 12,
    );
    expect(document.paragraphs.single.text, 'BeforechosenAfter');
    session.apply();
    final paragraphs = document.paragraphs.toList();
    expect(paragraphs.map((p) => p.text), ['Before', 'Imported', 'After']);
    for (final p in [paragraphs.first, paragraphs.last]) {
      expect(p.properties.rightToLeft, isTrue);
      expect(p.properties.justification, WmlJustification.center);
      expect(p.properties.indent.left, 7);
      expect(p.properties.indent.right, 11);
      expect(p.properties.indent.firstLine, 3);
    }
    expect(paragraphs[1].properties.rightToLeft, isFalse);
    expect(paragraphs[1].properties.justification, WmlJustification.left);
    expect(paragraphs[1].properties.indent.left, 30);
    expect(paragraphs[1].properties.indent.right, 0);
  });

  test(
    'active fields and paragraph layout survive repeated DOCX and ODT',
    () async {
      var document = _insert(
        '<p dir="rtl" data-indent="2" '
        'style="padding-right:80px;text-align:justify">أول ${_placeholder('FIRST1')}</p>'
        '<p dir="ltr" data-indent="1" '
        'style="padding-left:40px;text-align:center">Second ${_placeholder('SECOND2')}</p>',
        citations: ['SECOND2', 'FIRST1'],
      );
      void verify() {
        final paragraphs = document.paragraphs.toList();
        expect(paragraphs.map((p) => p.text), [
          'أول (FIRST1)',
          'Second (SECOND2)',
        ]);
        expect(paragraphs[0].properties.rightToLeft, isTrue);
        expect(
          paragraphs[0].properties.justification,
          WmlJustification.justify,
        );
        expect(paragraphs[0].properties.indent.right, 60);
        expect(paragraphs[0].properties.indent.left, 0);
        expect(paragraphs[1].properties.rightToLeft, isFalse);
        expect(paragraphs[1].properties.justification, WmlJustification.center);
        expect(paragraphs[1].properties.indent.left, 30);
        expect(WordZotero.fields(document).map((f) => f.citation!.citationId), [
          'FIRST1',
          'SECOND2',
        ]);
        expect(WordZotero.fields(document).every((f) => f.canEdit), isTrue);
        expect(WordFieldSpans.unbalanced(document), isEmpty);
        expect(
          WordZoteroDocumentData.read(document),
          contains('http://www.zotero.org/styles/apa'),
        );
      }

      verify();
      for (var cycle = 0; cycle < 2; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        verify();
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        verify();
      }
    },
  );

  for (final html in [
    '<p dir="auto">Unsupported direction</p>',
    '<p data-indent="0">Zero</p>',
    '<p data-indent="8">Historical large indent</p>',
    '<p data-indent="-1">Negative</p>',
    '<p data-indent="1.5">Fraction</p>',
    '<p data-indent="2junk">Permissive integer</p>',
    '<p data-indent="2" style="padding-left:40px">Mismatch</p>',
    '<p data-indent="1" style="padding-left:40px;padding-right:40px">Both</p>',
    '<p data-indent="1" style="padding-left:40px;padding-left:40px">Duplicate</p>',
    '<p dir="rtl" data-indent="1" style="padding-left:40px">Wrong side</p>',
    '<p style="padding-left:40px">Unspecified level</p>',
    '<p style="text-align:start">Unsupported CSS</p>',
    '<p style="text-align:left;text-align:right">Duplicate alignment</p>',
    '<p dir="rtl" style="margin-right:40px">Unmodeled layout</p>',
    '<span dir="rtl">Wrong element</span>',
    '<ul dir="rtl"><li>Directional marker</li></ul>',
    '<ul><li><p dir="rtl">Independent text direction</p></li></ul>',
  ]) {
    test('unrepresented layout refuses complete note: $html', () {
      final document = WmlDocument.empty(text: 'Original');
      final preferences = WordZoteroDocumentData.read(document);
      expect(
        () => _stage(document, '<p dir="ltr">Supported</p>$html'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(document.paragraphs.single.text, 'Original');
      expect(WordZotero.fields(document), isEmpty);
      expect(WordZoteroDocumentData.read(document), preferences);
    });
  }
}
