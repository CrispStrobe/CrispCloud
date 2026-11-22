import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:quds:test:note-colors';
const _id = 'note-colors';

ZoteroFormattedText _rich(String html) =>
    ZoteroFormattedText.fromHtml(html, allowNoteColors: true);

WmlRun _run(Iterable<WmlParagraph> paragraphs, String text) => paragraphs
    .expand((paragraph) => paragraph.inlines)
    .whereType<WmlRun>()
    .firstWhere((run) => run.text.contains(text));

Uint8List _fixture(String direct, {String styles = ''}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x"><w:body><w:p><w:r>'
        '<w:rPr>$direct</w:rPr><w:t>Source</w:t></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w">$styles</w:styles>');
  }
  return package.save();
}

String _documentXml(WmlDocument document) => OpcPackage.openBytes(
  WordSerializer().writeBytes(document),
).getPart('/word/document.xml')!.readText();

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

void main() {
  test('CSL parsing retains its existing unsupported-color boundary', () {
    final result = ZoteroFormattedText.fromHtml(
      '<span style="color:#ff2020;background-color:rgb(255,212,0)">CSL</span>',
    );
    expect(result.unsupportedFormatting, contains('unsupported inline style'));
    expect(result.spans.single.color, isNull);
    expect(result.spans.single.highlight, isNull);
    expect(
      result
          .toRuns(baseProperties: WmlRunProps(color: '123456'))
          .single
          .properties
          .color,
      '123456',
    );
  });

  test('note colors retain emphasis, scoped inheritance and host properties', () {
    final result = _rich(
      '<span style="color:#f20;background-color:rgb(255, 212, 0)">'
      '<i>outer</i><span style="color:rgb(0,128,255)"><b>inner</b></span>'
      '<span style="color:currentColor;background-color:transparent">clear</span>'
      '<span style="color:inherit;background:inherit">inherit</span>again</span>'
      '<span style="background-color:transparent">host-clear</span>host',
    );
    expect(result.unsupportedFormatting, isEmpty);
    expect(result.hasUniformCharacterFormatting, isFalse);
    final base = WmlRunProps(
      color: '223344',
      highlight: 'DDEEFF',
      asciiFont: 'Host Font',
      fontSizeHalfPoints: 28,
    );
    final paragraph = WmlParagraph(
      inlines: result.toRuns(baseProperties: base),
    );
    for (final text in ['outer', 'clear', 'inherit', 'again']) {
      final run = _run([paragraph], text);
      expect(run.properties.color, 'FF2200');
      expect(run.properties.highlight, 'FFD400');
      expect(
        run.properties.explicitProperties,
        containsAll(['color', 'highlight']),
      );
    }
    expect(_run([paragraph], 'outer').properties.italic, isTrue);
    final inner = _run([paragraph], 'inner');
    expect(inner.properties.color, '0080FF');
    expect(inner.properties.highlight, 'FFD400');
    expect(inner.properties.bold, isTrue);
    final cleared = _run([paragraph], 'host-clear');
    expect(cleared.properties.color, '223344');
    expect(cleared.properties.highlight, isNull);
    expect(cleared.properties.explicitProperties, contains('highlight'));
    final host = paragraph.inlines.whereType<WmlRun>().last;
    expect(host.text, 'host');
    expect(host.properties.color, '223344');
    expect(host.properties.highlight, 'DDEEFF');
    expect(host.properties.asciiFont, 'Host Font');
    expect(host.properties.fontSizeHalfPoints, 28);
    expect(base.color, '223344');
    expect(base.highlight, 'DDEEFF');
  });

  test(
    'colors distinguish uniform spans and survive structural paragraph split',
    () {
      final result = _rich(
        '<p><span style="color:#123">one<br/>soft</span></p>'
        '<p><span style="color:#456;background:#abc">two</span></p>',
      );
      final paragraphs = result.toParagraphRuns();
      expect(result.plainText, 'one\nsoft\ntwo');
      expect(result.hasUniformCharacterFormatting, isFalse);
      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.single.text, 'one\nsoft');
      expect(paragraphs.first.single.properties.color, '112233');
      expect(paragraphs.last.single.properties.color, '445566');
      expect(paragraphs.last.single.properties.highlight, 'AABBCC');
      expect(
        _rich(
          '<span style="color:#abc">a</span>'
          '<span style="color:rgb(170,187,204)">b</span>',
        ).hasUniformCharacterFormatting,
        isTrue,
      );
    },
  );

  for (final css in [
    'color:red',
    'color:transparent',
    'color:initial',
    'color:var(--foreground)',
    'color:#1234',
    'color:#11223344',
    'color:rgb(256,0,0)',
    'color:rgb(-1,0,0)',
    'color:rgb(100%,0%,0%)',
    'color:rgba(255,0,0,1)',
    'color:#abcdef !important',
    'color:#fff;color:#000',
    'background:#fff;background-color:#000',
    'background:linear-gradient(#fff,#000)',
    'background-color:rgba(255,212,0,0.5)',
    'background-color:#ffd40080',
    'background-color:currentColor',
    'background-color:',
  ]) {
    test('unsupported note color refuses the whole note: $css', () {
      final html = '<p><span style="$css">Keep all formatting</span></p>';
      expect(
        _rich(html).unsupportedFormatting,
        contains('unsupported inline style'),
      );
      expect(() => WordZoteroNoteText.fromHtml(html), throwsUnsupportedError);
    });
  }

  test(
    'RGB background uses valid native shading across DOCX and ODT cycles',
    () async {
      var document = WmlDocument.empty();
      document.paragraphs.single.inlines = _rich(
        '<span style="color:#7953e3;background-color:rgb(255,212,0)">Palette</span>'
        '<span style="background:#ff0000">Named</span>'
        '<span style="background:transparent">Clear</span>',
      ).toRuns();
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/word/document.xml')!.readText();
        expect(xml, contains('w:fill="FFD400"'));
        expect(xml, isNot(contains('w:highlight w:val="FFD400"')));
        document = WordDeserializer().readBytes(bytes);
        expect(_run(document.paragraphs, 'Palette').properties.color, '7953E3');
        expect(
          _run(document.paragraphs, 'Palette').properties.highlight,
          'FFD400',
        );
        expect(
          _run(document.paragraphs, 'Named').properties.highlight,
          'FF0000',
        );
        expect(_run(document.paragraphs, 'Clear').properties.highlight, isNull);
        final odt = OdtDocumentWriter.writeEditableZoteroBytes(document);
        document = await OdtDocumentReader.readBytes(odt);
        expect(_run(document.paragraphs, 'Palette').properties.color, '7953E3');
        expect(
          _run(document.paragraphs, 'Palette').properties.highlight,
          'FFD400',
        );
        expect(document.paragraphs.single.text, 'PaletteNamedClear');
      }
    },
  );

  test('native highlight wins over shading; none reveals its opaque fill', () {
    for (final (highlight, expected) in [
      ('yellow', 'FFFF00'),
      ('none', 'AABBCC'),
    ]) {
      final document = WordDeserializer().readBytes(
        _fixture(
          '<w:highlight w:val="$highlight"/>'
          '<w:shd w:val="clear" w:fill="AABBCC"/>',
        ),
      );
      expect(
        _run(document.paragraphs, 'Source').properties.highlight,
        expected,
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        _run(reopened.paragraphs, 'Source').properties.highlight,
        expected,
      );
    }
  });

  test('opaque foreign patterned and themed shading remains unprojected', () {
    for (final source in [
      '<x:shd w:val="clear" w:fill="AABBCC"/>',
      '<x:wrapper><w:shd w:val="clear" w:fill="AABBCC"/></x:wrapper>',
      '<w:shd w:val="pct25" w:fill="AABBCC" w:color="112233"/>',
      '<w:shd w:val="clear" w:fill="AABBCC" w:themeFill="accent1"/>',
    ]) {
      final document = WordDeserializer().readBytes(_fixture(source));
      final run = _run(document.paragraphs, 'Source');
      expect(run.properties.highlight, isNull);
      run.properties.italic = true;
      expect(_documentXml(document), contains(source));
    }
  });

  test(
    'explicit note colors replace themes and shading while preserving extensions',
    () {
      final document = WordDeserializer().readBytes(
        _fixture(
          '<w:color w:val="111111" w:themeColor="accent1" x:keep="foreground"/>'
          '<w:highlight w:val="none"/>'
          '<w:shd w:val="clear" w:fill="FFD400" x:keep="background"><x:child/></w:shd>',
        ),
      );
      final base = _run(document.paragraphs, 'Source').properties;
      document.paragraphs.single.inlines = _rich(
        '<span style="color:#000;background:#5fb236">Changed</span>'
        '<span style="background:transparent">Clear</span>',
      ).toRuns(baseProperties: base);
      final xml = _documentXml(document);
      expect(xml, contains('x:keep="foreground"'));
      expect(xml, contains('x:keep="background"'));
      expect(xml, contains('<x:child/>'));
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(_run(reopened.paragraphs, 'Changed').properties.color, '000000');
      expect(
        _run(reopened.paragraphs, 'Changed').properties.highlight,
        '5FB236',
      );
      expect(_run(reopened.paragraphs, 'Clear').properties.highlight, isNull);
    },
  );

  test(
    'inherited shading stays live until a note color explicitly overrides it',
    () {
      final document = WordDeserializer().readBytes(
        _fixture(
          '<w:rStyle w:val="Host"/>',
          styles:
              '<w:style w:type="character" w:styleId="Host"><w:rPr>'
              '<w:color w:val="334455"/><w:shd w:val="clear" w:fill="FFD400"/>'
              '</w:rPr></w:style>',
        ),
      );
      final base = _run(document.paragraphs, 'Source').properties;
      expect(base.highlight, 'FFD400');
      document.paragraphs.single.inlines = _rich(
        'Inherited<span style="color:#000;background-color:transparent">Reset</span>',
      ).toRuns(baseProperties: base);
      final package = OpcPackage.openBytes(
        WordSerializer().writeBytes(document),
      );
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles
            .readText()
            .replaceAll('FFD400', 'A28AE5')
            .replaceAll('334455', '998877'),
      );
      final reopened = WordDeserializer().read(package);
      expect(_run(reopened.paragraphs, 'Inherited').properties.color, '998877');
      expect(
        _run(reopened.paragraphs, 'Inherited').properties.highlight,
        'A28AE5',
      );
      expect(_run(reopened.paragraphs, 'Reset').properties.color, '000000');
      expect(_run(reopened.paragraphs, 'Reset').properties.highlight, isNull);
    },
  );

  test(
    'colored heading note image and citation retain color through native exchange',
    () async {
      var document = WmlDocument.empty(text: 'Host');
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _id,
        insertionParagraph: document.paragraphs.single,
        insertionOffset: 0,
      );
      _call(session, 'Document.setDocumentData', [
        jsonEncode({
          'dataVersion': 4,
          'sessionID': _id,
          'style': {
            'styleID': 'http://www.zotero.org/styles/apa',
            'locale': 'en-US',
          },
          'prefs': {'fieldType': 'Http', 'noteType': 0},
        }),
      ]);
      final temporary =
          _call(session, 'Document.insertField', ['Http', 0])! as Map;
      _call(session, 'Field.delete', [temporary['id']]);
      final png = image.encodePng(image.Image(width: 2, height: 2));
      _call(session, 'Document.insertText', [
        '<div data-schema-version="9"><h2><span style="color:#000">Black heading</span></h2>'
            '<p><span style="color:#05a2ef;background-color:rgb(255,212,0)">'
            '<i>Quote</i> <a href="https://www.zotero.org/?ABC123">(Old)</a>'
            '<img src="data:image/png;base64,${base64Encode(png)}" width="2" height="2"/>'
            '</span></p></div>',
      ]);
      final fields =
          _call(session, 'Document.convertPlaceholdersToFields', [
                ['ABC123'],
                0,
                'Http',
              ])!
              as List;
      final fieldId = (fields.single as Map)['id'];
      final citation = ZoteroCitation(
        citationId: 'color-citation',
        plainCitation: '(Author, 2026)',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {
              'id': 'source',
              'type': 'book',
              'title': 'Colored research',
            },
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
          ),
        ],
      );
      _call(session, 'Field.setCode', [
        fieldId,
        'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
      ]);
      _call(session, 'Field.setText', [fieldId, '<b>(Author, 2026)</b>', true]);
      _call(session, 'Document.complete');
      session.apply();
      for (var cycle = 0; cycle < 2; cycle++) {
        expect(
          _run(document.paragraphs, 'Black heading').properties.color,
          '000000',
        );
        expect(_run(document.paragraphs, 'Quote').properties.color, '05A2EF');
        expect(
          _run(document.paragraphs, 'Quote').properties.highlight,
          'FFD400',
        );
        final field = WordZotero.fields(document).single;
        expect(field.citation!.citationId, 'color-citation');
        expect(field.canEdit, isTrue);
        expect(
          _run(document.paragraphs, 'Author').properties.highlight,
          'FFD400',
        );
        expect(
          document.paragraphs
              .expand((p) => p.inlines)
              .whereType<WmlRun>()
              .where((run) => run.inlineVisual != null),
          hasLength(1),
        );
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
      }
    },
  );
}
