import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Synthetic ODT packages, pinned to the canonical Zotero LibreOffice storage
// contract. These fixtures do not claim installed-host interoperability.
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _namespaces =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:style="$_style" '
    'xmlns:fo="$_fo" xmlns:meta="$_meta" xmlns:table="$_table" '
    'xmlns:draw="$_draw" xmlns:xlink="$_xlink" xmlns:foreign="urn:foreign"';

const _richStyles =
    '<style:style style:name="Italic" style:family="text">'
    '<style:text-properties fo:font-style="italic"/></style:style>'
    '<style:style style:name="Bold" style:family="text">'
    '<style:text-properties fo:font-weight="bold"/></style:style>'
    '<style:style style:name="Underline" style:family="text">'
    '<style:text-properties style:text-underline-style="solid" '
    'style:text-underline-type="single"/></style:style>'
    '<style:style style:name="Super" style:family="text">'
    '<style:text-properties style:text-position="super"/></style:style>';

Map<String, Object?> _citationData({String id = 'citation-one'}) => {
  'citationID': id,
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '12–14',
      'label': 'page',
      'prefix': 'see ',
      'suffix': ' RNDabcdefghij',
      'suppress-author': true,
      'itemData': {
        'id': 17,
        'type': 'book',
        'title': 'العربية 😀 & <quoted>',
        'customItem': {'keep': true},
      },
      'futureItem': ['retained', 9],
    },
    {
      'id': 'http://zotero.org/groups/12/items/EFGH5678',
      'uris': ['http://zotero.org/groups/12/items/EFGH5678'],
      'locator': '4',
      'label': 'chapter',
      'itemData': {'type': 'book', 'title': 'Second source'},
    },
  ],
  'properties': {
    'plainCitation': '(Smith, 2026)',
    'noteIndex': 0,
    'futureProperty': {'keep': 'yes'},
  },
  'futureRoot': {
    'retain': [true, null, 3],
  },
};

String _citation({String suffix = '0123456789', String id = 'citation-one'}) =>
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citationData(id: id))} RND$suffix';

const _bibliographyData = <String, Object?>{
  'uncited': <Object?>[],
  'omitted': <Object?>[],
  'custom': <Object?>[],
  'futureBibliography': <String, Object?>{'retain': true},
};

String _bibliography() =>
    'ZOTERO_BIBL ${jsonEncode(_bibliographyData)}'
    ' CSL_BIBLIOGRAPHY RNDabcdefghij';

String _start(String name) =>
    '<text:reference-mark-start text:name="${encodeXmlAttribute(name)}"/>';

String _end(String name) =>
    '<text:reference-mark-end text:name="${encodeXmlAttribute(name)}"/>';

String _mark(String name, String contents) =>
    '${_start(name)}$contents${_end(name)}';

String _section(String name, String contents, {String attributes = ''}) =>
    '<text:section text:name="${encodeXmlAttribute(name)}" $attributes>'
    '$contents</text:section>';

String _content(String body, {String automaticStyles = ''}) =>
    '<office:document-content $_namespaces>'
    '<office:automatic-styles>$automaticStyles</office:automatic-styles>'
    '<office:body><office:text>$body</office:text></office:body>'
    '</office:document-content>';

String _styles(String styles) =>
    '<office:document-styles $_namespaces>'
    '<office:styles>$styles</office:styles></office:document-styles>';

String _property(String name, String value) =>
    '<meta:user-defined meta:name="${encodeXmlAttribute(name)}">'
    '${encodeXmlText(value)}</meta:user-defined>';

String _metadata(String data, {bool reverseChunks = false}) {
  final chunks = <String>[];
  for (var offset = 0, index = 1; offset < data.length; index++) {
    var end = (offset + 255).clamp(0, data.length);
    if (end < data.length &&
        data.codeUnitAt(end - 1) >= 0xd800 &&
        data.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    chunks.add(_property('ZOTERO_PREF_$index', data.substring(offset, end)));
    offset = end;
  }
  return '<office:document-meta $_namespaces><office:meta>'
      '${_property('Customer', 'Unrelated & preserved')}'
      '${(reverseChunks ? chunks.reversed : chunks).join()}'
      '</office:meta></office:document-meta>';
}

Uint8List _package(
  String body, {
  String automaticStyles = '',
  String? styles,
  String? metadata,
  String? content,
  String mimetype = 'application/vnd.oasis.opendocument.text',
  bool duplicateContent = false,
}) {
  final writer = ZipWriter();
  writer.addFile('mimetype', utf8.encode(mimetype), store: true);
  final xml = content ?? _content(body, automaticStyles: automaticStyles);
  writer.addFile('content.xml', utf8.encode(xml));
  if (duplicateContent) writer.addFile('content.xml', utf8.encode(xml));
  if (styles != null) writer.addFile('styles.xml', utf8.encode(styles));
  if (metadata != null) writer.addFile('meta.xml', utf8.encode(metadata));
  return writer.close();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

List<WmlRun> _runs(WmlParagraph paragraph) =>
    paragraph.inlines.whereType<WmlRun>().toList();

WmlRun _runContaining(WmlParagraph paragraph, String text) =>
    _runs(paragraph).singleWhere((run) => run.text.contains(text));

Matcher get _refused =>
    throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>()));

void main() {
  test('imports paragraphs, headings, styled runs and links into DOCX', () async {
    var document = await OdtDocumentReader.readBytes(
      _package(
        '<text:h text:outline-level="2">Research</text:h>'
        '<text:p>Plain <text:span text:style-name="Italic">italic</text:span>'
        ' and <text:span text:style-name="Bold">bold</text:span> '
        '<text:a xlink:href="https://example.test/source">source</text:a></text:p>'
        '<text:p><text:span text:style-name="Underline">underlined</text:span>'
        '<text:span text:style-name="Super">2</text:span></text:p>',
        automaticStyles: _richStyles,
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final paragraphs = document.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), [
        'Research',
        'Plain italic and bold source',
        'underlined2',
      ]);
      expect(paragraphs.first.properties.headingLevel, 2);
      expect(_runContaining(paragraphs[1], 'italic').properties.italic, isTrue);
      expect(_runContaining(paragraphs[1], 'bold').properties.bold, isTrue);
      expect(
        _runContaining(paragraphs[1], 'source').hyperlink!.url,
        'https://example.test/source',
      );
      expect(
        _runContaining(paragraphs[2], 'underlined').properties.underline,
        WmlUnderline.single,
      );
      expect(
        _runs(paragraphs[2]).last.properties.vertAlign,
        WmlVertAlign.superscript,
      );
      if (cycle < 2) document = _reopen(document);
    }
  });

  test(
    'resolves named paragraph parents and automatic text formatting',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p text:style-name="Child">Inherited '
          '<text:span text:style-name="Blue">blue</text:span></text:p>',
          styles: _styles(
            '<style:style style:name="Base" style:family="paragraph">'
            '<style:paragraph-properties fo:text-align="center" '
            'fo:margin-bottom="6pt"/>'
            '<style:text-properties fo:font-size="14pt" fo:font-weight="bold"/>'
            '</style:style>'
            '<style:style style:name="Child" style:family="paragraph" '
            'style:parent-style-name="Base"/>',
          ),
          automaticStyles:
              '<style:style style:name="Blue" style:family="text">'
              '<style:text-properties fo:color="#123456" fo:font-style="italic"/>'
              '</style:style>',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final paragraph = current.paragraphs.single;
        expect(paragraph.properties.justification, WmlJustification.center);
        expect(paragraph.properties.spacingAfter, 6);
        expect(_runs(paragraph).every((r) => r.properties.bold), isTrue);
        expect(
          _runs(paragraph).every((r) => r.properties.fontSizeHalfPoints == 28),
          isTrue,
        );
        final blue = _runContaining(paragraph, 'blue');
        expect(blue.properties.color, '123456');
        expect(blue.properties.italic, isTrue);
      }
    },
  );

  test(
    'canonical rich citation keeps options, metadata and editable ownership',
    () async {
      final bytes = _package(
        '<text:p>Before ${_mark(_citation(), '(<text:span text:style-name="Italic">Smith</text:span>, 2026)')} after</text:p>',
        automaticStyles: _richStyles,
      );
      final before = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        final field = WordZotero.fields(document).single;
        expect(field.kind, ZoteroFieldKind.citation);
        expect(field.isValid, isTrue);
        expect(field.canEdit, isTrue);
        expect(field.start, 7);
        expect(field.end, 20);
        expect(field.cachedText, '(Smith, 2026)');
        expect(field.metadata, _citationData());
        expect(field.citation!.items, hasLength(2));
        expect(field.citation!.items.first.locator, '12–14');
        expect(field.citation!.items.first.suppressAuthor, isTrue);
        expect(field.citation!.items.first.suffix, ' RNDabcdefghij');
        expect(
          _runContaining(field.paragraph, 'Smith').properties.italic,
          isTrue,
        );
        expect(field.paragraph.text, 'Before (Smith, 2026) after');
        if (cycle < 2) document = _reopen(document);
      }
      expect(bytes, before);
    },
  );

  test(
    'same visible text and payload retains two independent citation ranges',
    () async {
      var document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>same ${_mark(_citation(), 'same')} / '
          '${_mark(_citation(suffix: 'abcdefghij'), 'same')} same</text:p>',
        ),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        final fields = WordZotero.fields(document);
        expect(fields, hasLength(2));
        expect(fields.map((f) => f.start), [5, 12]);
        expect(fields.map((f) => f.end), [9, 16]);
        expect(fields.map((f) => f.cachedText), ['same', 'same']);
        expect(fields.every((f) => f.canEdit), isTrue);
        expect(
          identical(fields.first.paragraph, fields.last.paragraph),
          isTrue,
        );
        document = _reopen(document);
      }
      final second = WordZotero.fields(document).last;
      WordZotero.updateCitation(
        second,
        second.citation!.withItems(
          second.citation!.items,
          plainCitation: '(Changed)',
        ),
      );
      expect(document.paragraphs.single.text, 'same same / (Changed) same');
      expect(WordZotero.fields(document).first.cachedText, 'same');
    },
  );

  test('adjacent citations keep distinct packets and HTTP identities', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<text:p>${_mark(_citation(id: 'first'), '(A)')}'
        '${_mark(_citation(id: 'second', suffix: 'abcdefghij'), '(B)')}</text:p>',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final fields = WordZotero.fields(current);
      expect(fields.map((f) => f.cachedText), ['(A)', '(B)']);
      expect(fields.map((f) => f.start), [0, 3]);
      expect(fields.map((f) => f.citation!.citationId), ['first', 'second']);
      final session = WordZoteroCitingSession(
        document: current,
        documentId: 'native-odt',
        insertionParagraph: current.paragraphs.single,
      );
      final wire =
          (session.handle('Document.getFields', ['native-odt', 'Http']) as List)
              .cast<Map<String, Object>>();
      expect(wire.map((f) => f['id']).toSet(), hasLength(2));
      expect(wire.map((f) => f['adjacent']), [true, false]);
      session.assertUnchanged();
    }
  });

  test('UTF16 offsets follow styled spans and explicit ODF whitespace', () async {
    const cache = 'العربية  \t😀\nX';
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<text:p>😀 ${_mark(_citation(), '<text:span text:style-name="Italic">العربية</text:span><text:s text:c="2"/><text:tab/>😀<text:line-break/>X')} tail</text:p>',
        automaticStyles: _richStyles,
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final field = WordZotero.fields(current).single;
      expect(field.start, 3);
      expect(field.end, 3 + cache.length);
      expect(field.cachedText, cache);
      expect(field.paragraph.text, '😀 $cache tail');
      expect(
        _runContaining(field.paragraph, 'العربية').properties.italic,
        isTrue,
      );
    }
  });

  for (final item in <(String, String, String, String, int, int)>[
    ('  ', '  A  ', '  ', 'A', 0, 1),
    ('X  ', 'A', '', 'A', 2, 3),
    ('X', ' A ', 'Y', ' A ', 1, 4),
    ('', 'A ', ' Y', 'A ', 0, 2),
    ('', '<text:s text:c="2"/>A<text:s/>', '', '  A ', 0, 4),
  ]) {
    test(
      'collapsed whitespace retains field range ${item.$1}/${item.$2}/${item.$3}',
      () async {
        final document = await OdtDocumentReader.readBytes(
          _package(
            '<text:p>${item.$1}${_mark(_citation(), item.$2)}${item.$3}</text:p>',
          ),
        );
        final field = WordZotero.fields(document).single;
        expect(field.cachedText, item.$4);
        expect(field.start, item.$5);
        expect(field.end, item.$6);
        expect(WordZotero.fields(_reopen(document)).single.cachedText, item.$4);
      },
    );
  }

  test(
    'section bibliography keeps rich and empty entry paragraphs through DOCX',
    () async {
      var document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>Before</text:p>'
          '${_section(_bibliography(), '<text:p>First <text:span text:style-name="Italic">Book</text:span>.</text:p><text:p/><text:p>Second <text:span text:style-name="Bold">Book</text:span>.</text:p>')}'
          '<text:p>After</text:p>',
          automaticStyles: _richStyles,
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final field = WordZotero.fields(document).single;
        expect(field.kind, ZoteroFieldKind.bibliography);
        expect(field.metadata, _bibliographyData);
        expect(field.cachedText, 'First Book.\n\nSecond Book.');
        expect(field.paragraphs.map((p) => p.text), [
          'First Book.',
          '',
          'Second Book.',
        ]);
        expect(
          _runContaining(field.paragraphs.first, 'Book').properties.italic,
          isTrue,
        );
        expect(
          _runContaining(field.paragraphs.last, 'Book').properties.bold,
          isTrue,
        );
        expect(document.paragraphs.first.text, 'Before');
        expect(document.paragraphs.last.text, 'After');
        if (cycle < 2) document = _reopen(document);
      }
    },
  );

  test('reference-mark bibliography also becomes an active field', () async {
    final document = await OdtDocumentReader.readBytes(
      _package('<text:p>${_mark(_bibliography(), 'Reference entry')}</text:p>'),
    );
    final field = WordZotero.fields(_reopen(document)).single;
    expect(field.kind, ZoteroFieldKind.bibliography);
    expect(field.metadata, _bibliographyData);
    expect(field.cachedText, 'Reference entry');
  });

  for (final kind in ['footnote', 'endnote']) {
    test(
      '$kind starting citation excludes its automatic note marker',
      () async {
        final document = await OdtDocumentReader.readBytes(
          _package(
            '<text:p>Body<text:note text:id="n1" text:note-class="$kind">'
            '<text:note-citation>1</text:note-citation><text:note-body>'
            '<text:p>${_mark(_citation(), '(First)')} tail</text:p>'
            '</text:note-body></text:note></text:p>',
          ),
        );
        for (final current in [document, _reopen(document)]) {
          final note =
              (kind == 'footnote' ? current.footnotes : current.endnotes)
                  .single;
          final field = WordZotero.fields(current).single;
          expect(identical(field.paragraph, note.paragraphs.single), isTrue);
          expect(field.start, 0);
          expect(field.end, 7);
          expect(field.cachedText, '(First)');
          expect(field.canEdit, isTrue);
          expect(note.paragraphs.single.text, '(First) tail');
          expect(WordNoteNumbering(current).labelFor(note), '1');
        }
      },
    );

    test(
      '$kind citation retains its authored story and live note anchor',
      () async {
        final document = await OdtDocumentReader.readBytes(
          _package(
            '<text:p>Body ${_mark(_citation(id: 'body'), '(Same)')} '
            '<text:note text:id="n1" text:note-class="$kind">'
            '<text:note-citation>1</text:note-citation><text:note-body>'
            '<text:p>Note ${_mark(_citation(id: 'note', suffix: 'abcdefghij'), '(<text:span text:style-name="Italic">Same</text:span>)')} tail</text:p>'
            '</text:note-body></text:note> after</text:p>',
            automaticStyles: _richStyles,
          ),
        );
        for (final current in [document, _reopen(document)]) {
          final notes = kind == 'footnote'
              ? current.footnotes
              : current.endnotes;
          expect(notes, hasLength(1));
          final note = notes.single;
          expect(note.endnote, kind == 'endnote');
          expect(note.paragraphs.single.text, 'Note (Same) tail');
          expect(WordNoteNumbering(current).labelFor(note), '1');
          final fields = WordZotero.fields(current);
          expect(fields, hasLength(2));
          final noteField = fields.singleWhere(
            (f) => f.citation!.citationId == 'note',
          );
          expect(
            identical(noteField.paragraph, note.paragraphs.single),
            isTrue,
          );
          expect(noteField.cachedText, '(Same)');
          expect(noteField.canEdit, isTrue);
          expect(
            _runContaining(noteField.paragraph, 'Same').properties.italic,
            isTrue,
          );
          final anchor = current.paragraphs.single.inlines
              .whereType<WmlRun>()
              .singleWhere((r) => r.noteRefId != null);
          expect(anchor.noteRefId, note.id);
          expect(anchor.noteRefEndnote, kind == 'endnote');
          final session = WordZoteroCitingSession(
            document: current,
            documentId: 'native-note',
            insertionParagraph: current.paragraphs.single,
          );
          final wire =
              (session.handle('Document.getFields', ['native-note', 'Http'])
                      as List)
                  .cast<Map<String, Object>>();
          expect(wire.map((f) => f['noteIndex']), [0, 1]);
          session.assertUnchanged();
        }
      },
    );
  }

  test(
    'table and nested-cell citations retain separate physical owners',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>Before</text:p><table:table>'
          '<table:table-row><table:table-cell>'
          '<text:p>${_mark(_citation(id: 'left'), '(Same)')}</text:p>'
          '</table:table-cell><table:table-cell><text:p>Nested</text:p>'
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>${_mark(_citation(id: 'right', suffix: 'abcdefghij'), '(Same)')}</text:p>'
          '</table:table-cell></table:table-row></table:table>'
          '</table:table-cell></table:table-row></table:table>'
          '<text:p>After</text:p>',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final table = current.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        expect(table.rows, hasLength(1));
        expect(table.rows.single.cells, hasLength(2));
        final left = table.rows.single.cells.first.blocks
            .whereType<WmlParagraph>()
            .single;
        final nested = table.rows.single.cells.last.blocks
            .whereType<WmlTable>()
            .single;
        final right = nested.rows.single.cells.single.blocks
            .whereType<WmlParagraph>()
            .single;
        final fields = WordZotero.fields(current);
        expect(fields.map((f) => f.citation!.citationId), ['left', 'right']);
        expect(identical(fields.first.paragraph, left), isTrue);
        expect(identical(fields.last.paragraph, right), isTrue);
        expect(fields.every((f) => f.canEdit), isTrue);
        expect(fields.map((f) => f.cachedText), ['(Same)', '(Same)']);
      }
    },
  );

  test(
    'authored note anchors retain whitespace on its original side',
    () async {
      for (final after in ['after', '']) {
        final document = await OdtDocumentReader.readBytes(
          _package(
            '<text:p>Before <text:note text:note-class="footnote">'
            '<text:note-citation>1</text:note-citation><text:note-body>'
            '<text:p>Authored note</text:p></text:note-body></text:note>'
            '$after</text:p>',
          ),
        );
        for (final current in [document, _reopen(document)]) {
          final runs = _runs(
            current.sections.single.blocks.whereType<WmlParagraph>().single,
          );
          final anchor = runs.indexWhere((run) => run.noteRefId != null);
          expect(anchor, greaterThanOrEqualTo(0));
          expect(runs.take(anchor).map((run) => run.text).join(), 'Before ');
          expect(runs.skip(anchor + 1).map((run) => run.text).join(), after);
          expect(current.footnotes.single.blocks.single, isA<WmlParagraph>());
        }
      }
    },
  );

  test('a citation after a note owns its exact rich range', () async {
    for (final spacing in [('Before ', ' '), ('Before', ''), ('', '')]) {
      final before = spacing.$1;
      final after = spacing.$2;
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>$before<text:note text:note-class="footnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>Authored note</text:p></text:note-body></text:note>'
          '$after${_mark(_citation(), '(Source)')}</text:p>',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final field = WordZotero.fields(current).single;
        final paragraph = field.paragraph;
        expect(paragraph.text, '${before}1$after(Source)');
        expect(field.start, before.length + 1 + after.length);
        expect(field.end, before.length + 1 + after.length + '(Source)'.length);
        expect(field.cachedText, '(Source)');
        expect(field.canEdit, isTrue);
        final anchor = paragraph.inlines.indexWhere(
          (inline) => inline is WmlRun && inline.noteRefId != null,
        );
        final begin = field.run != null
            ? paragraph.inlines.indexOf(field.run!)
            : paragraph.inlines.indexWhere(
                (inline) =>
                    inline is WmlFieldBoundary &&
                    inline.kind == WmlFieldBoundaryKind.begin,
              );
        expect(anchor, greaterThanOrEqualTo(0));
        expect(begin, greaterThanOrEqualTo(0));
        expect((paragraph.inlines[anchor] as WmlRun).text, '1');
        expect(anchor, lessThan(begin));
      }
    }
  });

  test('cross-cell and cross-note reference marks are refused', () async {
    final name = _citation();
    for (final body in [
      '<table:table><table:table-row><table:table-cell>'
          '<text:p>${_start(name)}Left</text:p></table:table-cell>'
          '<table:table-cell><text:p>Right${_end(name)}</text:p>'
          '</table:table-cell></table:table-row></table:table>',
      '<text:p>${_start(name)}Body<text:note text:note-class="footnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>Note${_end(name)}</text:p></text:note-body></text:note></text:p>',
      '<text:p>${_start(name)}Before<text:note text:note-class="footnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>Note</text:p></text:note-body></text:note>After${_end(name)}</text:p>',
      '<text:p>${_start(name)}(Source)<text:note text:note-class="footnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>Note</text:p></text:note-body></text:note>${_end(name)}</text:p>',
    ]) {
      await expectLater(OdtDocumentReader.readBytes(_package(body)), _refused);
    }
  });

  test(
    'table style inheritance keeps alignment, row keep and fill clearing',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<table:table table:style-name="TableChild">'
          '<table:table-row table:style-name="RowChild">'
          '<table:table-cell table:style-name="CellChild">'
          '<text:p>${_mark(_citation(), '(Source)')}</text:p>'
          '</table:table-cell><table:table-cell table:style-name="CellBase">'
          '<text:p>Shaded</text:p></table:table-cell>'
          '</table:table-row></table:table>',
          styles: _styles(
            '<style:style style:name="TableBase" style:family="table">'
            '<style:table-properties table:align="center"/></style:style>'
            '<style:style style:name="TableChild" style:family="table" '
            'style:parent-style-name="TableBase">'
            '<style:table-properties style:width="240pt"/></style:style>'
            '<style:style style:name="RowBase" style:family="table-row">'
            '<style:table-row-properties fo:keep-together="always"/></style:style>'
            '<style:style style:name="RowChild" style:family="table-row" '
            'style:parent-style-name="RowBase">'
            '<style:table-row-properties style:min-row-height="12pt"/>'
            '</style:style>'
            '<style:style style:name="CellBase" style:family="table-cell">'
            '<style:table-cell-properties fo:background-color="#AABBCC"/>'
            '</style:style>'
            '<style:style style:name="CellChild" style:family="table-cell" '
            'style:parent-style-name="CellBase">'
            '<style:table-cell-properties fo:background-color="transparent"/>'
            '</style:style>',
          ),
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final table = current.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        expect(table.properties.alignment, WmlJustification.center);
        final row = table.rows.single;
        expect(row.cantSplit, isTrue);
        expect(row.height, 12);
        expect(row.cells.first.fillColor, isNull);
        expect(row.cells.last.fillColor, 'AABBCC');
        expect(WordZotero.fields(current).single.cachedText, '(Source)');
        expect(WordZotero.fields(current).single.canEdit, isTrue);
      }
    },
  );

  test('unsupported used table style semantics are refused', () async {
    for (final attribute in [
      'style:auto-update="true"',
      'style:master-page-name="Alternate"',
      'foreign:rendering="required"',
    ]) {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(
            '<table:table table:style-name="Table"><table:table-row>'
            '<table:table-cell><text:p>Cell</text:p></table:table-cell>'
            '</table:table-row></table:table>',
            automaticStyles:
                '<style:style style:name="Table" style:family="table" $attribute>'
                '<style:table-properties/></style:style>',
          ),
        ),
        _refused,
      );
    }
  });

  test(
    'separate decimal lists preserve starts, sequence and citation packets',
    () async {
      var document = await OdtDocumentReader.readBytes(
        _package(
          '<text:list text:style-name="Numbers"><text:list-item>'
          '<text:p>First ${_mark(_citation(id: 'first'), '(A)')}</text:p>'
          '</text:list-item><text:list-item>'
          '<text:p>Second ${_mark(_citation(id: 'second', suffix: 'abcdefghij'), '(B)')}</text:p>'
          '</text:list-item><text:list-item text:start-value="9">'
          '<text:p>Restarted</text:p></text:list-item><text:list-item>'
          '<text:p>Following</text:p></text:list-item></text:list>'
          '<text:p>Between</text:p><text:list text:style-name="Numbers">'
          '<text:list-item><text:p>Independent</text:p></text:list-item></text:list>',
          automaticStyles:
              '<text:list-style style:name="Numbers">'
              '<text:list-level-style-number text:level="1" text:start-value="4" '
              'style:num-format="1" style:num-suffix="."/></text:list-style>',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraphs = document.paragraphs.toList();
        expect(paragraphs.map((p) => p.text), [
          'First (A)',
          'Second (B)',
          'Restarted',
          'Following',
          'Between',
          'Independent',
        ]);
        expect(paragraphs.map((p) => p.properties.listLabel?.trim()), [
          '4.',
          '5.',
          '9.',
          '10.',
          null,
          '4.',
        ]);
        expect(paragraphs.first.properties.numId, isNotNull);
        expect(
          paragraphs[1].properties.numId,
          paragraphs.first.properties.numId,
        );
        expect(
          paragraphs.last.properties.numId,
          isNot(paragraphs.first.properties.numId),
        );
        expect(WordZotero.fields(document).map((f) => f.citation!.citationId), [
          'first',
          'second',
        ]);
        if (cycle < 2) document = _reopen(document);
      }
    },
  );

  test('nested bullet list retains levels and default bullet semantics', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<text:list text:style-name="Bullets"><text:list-item><text:p>Outer</text:p>'
        '<text:list><text:list-item><text:p>Inner</text:p></text:list-item></text:list>'
        '</text:list-item><text:list-item><text:p>Next</text:p></text:list-item></text:list>',
        automaticStyles:
            '<text:list-style style:name="Bullets">'
            '<text:list-level-style-bullet text:level="1" text:bullet-char="•"/>'
            '<text:list-level-style-bullet text:level="2" text:bullet-char="◦"/>'
            '</text:list-style>',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final paragraphs = current.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), ['Outer', 'Inner', 'Next']);
      expect(paragraphs.map((p) => p.properties.ilvl), [0, 1, 0]);
      expect(paragraphs.map((p) => p.properties.listLabel?.trim()), [
        '•',
        '◦',
        '•',
      ]);
      expect(paragraphs.every((p) => p.properties.numId != null), isTrue);
    }
  });

  test('list label geometry retains authored paragraph margins', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<text:list text:style-name="Numbers"><text:list-item>'
        '<text:p text:style-name="Inset">First</text:p>'
        '<text:p text:style-name="Inset">Continuation</text:p>'
        '</text:list-item></text:list>',
        automaticStyles:
            '<style:style style:name="Inset" style:family="paragraph">'
            '<style:paragraph-properties fo:margin-left="36pt" '
            'fo:margin-right="12pt"/></style:style>'
            '<text:list-style style:name="Numbers">'
            '<text:list-level-style-number text:level="1" '
            'style:num-format="1" style:num-suffix=".">'
            '<style:list-level-properties text:space-before="9pt" '
            'text:min-label-width="9pt"/></text:list-level-style-number>'
            '</text:list-style>',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final paragraphs = current.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), ['First', 'Continuation']);
      expect(paragraphs.map((p) => p.properties.indent.left), [54, 54]);
      expect(paragraphs.map((p) => p.properties.indent.right), [12, 12]);
      expect(paragraphs.map((p) => p.properties.indent.hanging), [9, 0]);
      expect(paragraphs.first.properties.listLabel?.trim(), '1.');
      expect(paragraphs.last.properties.numberingSuppressed, isTrue);
    }
  });

  test('conflicting list paragraph first-line geometry is refused', () async {
    for (final indent in ['9pt', '-9pt']) {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(
            '<text:list text:style-name="Numbers"><text:list-item>'
            '<text:p text:style-name="Inset">First</text:p>'
            '</text:list-item></text:list>',
            automaticStyles:
                '<style:style style:name="Inset" style:family="paragraph">'
                '<style:paragraph-properties fo:text-indent="$indent"/>'
                '</style:style><text:list-style style:name="Numbers">'
                '<text:list-level-style-number text:level="1" '
                'style:num-format="1" style:num-suffix="."/></text:list-style>',
          ),
        ),
        _refused,
      );
    }
  });

  test('nested list continuation keeps its own level and field', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<text:list text:style-name="Bullets"><text:list-item>'
        '<text:p>Outer</text:p><text:list><text:list-item>'
        '<text:p>Inner</text:p><text:p>Inner continuation '
        '${_mark(_citation(), '(Source)')}</text:p></text:list-item></text:list>'
        '<text:p>Outer continuation</text:p></text:list-item>'
        '<text:list-item><text:p>Next</text:p></text:list-item></text:list>',
        automaticStyles:
            '<text:list-style style:name="Bullets">'
            '<text:list-level-style-bullet text:level="1" text:bullet-char="•"/>'
            '<text:list-level-style-bullet text:level="2" text:bullet-char="◦"/>'
            '</text:list-style>',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final paragraphs = current.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), [
        'Outer',
        'Inner',
        'Inner continuation (Source)',
        'Outer continuation',
        'Next',
      ]);
      expect(paragraphs.map((p) => p.properties.ilvl), [0, 1, 1, 0, 0]);
      expect(paragraphs.map((p) => p.properties.indent.left), [
        18,
        36,
        36,
        18,
        18,
      ]);
      expect(paragraphs.map((p) => p.properties.numberingSuppressed), [
        false,
        false,
        true,
        true,
        false,
      ]);
      expect(paragraphs.map((p) => p.properties.listLabel?.trim()), [
        '•',
        '◦',
        null,
        null,
        '•',
      ]);
      final field = WordZotero.fields(current).single;
      expect(identical(field.paragraph, paragraphs[2]), isTrue);
      expect(field.cachedText, '(Source)');
      expect(field.canEdit, isTrue);
    }
  });

  test('unsupported used list definition semantics are refused', () async {
    for (final attribute in [
      'text:consecutive-numbering="true"',
      'foreign:rendering="required"',
    ]) {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(
            '<text:list text:style-name="Numbers"><text:list-item>'
            '<text:p>First</text:p></text:list-item></text:list>',
            automaticStyles:
                '<text:list-style style:name="Numbers" $attribute>'
                '<text:list-level-style-number text:level="1" '
                'style:num-format="1" style:num-suffix="."/></text:list-style>',
          ),
        ),
        _refused,
      );
    }
  });

  test(
    'bullet label affixes are refused instead of silently omitted',
    () async {
      for (final attribute in [
        'style:num-prefix="("',
        'style:num-suffix=")"',
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _package(
              '<text:list text:style-name="Bullets"><text:list-item>'
              '<text:p>Item</text:p></text:list-item></text:list>',
              automaticStyles:
                  '<text:list-style style:name="Bullets">'
                  '<text:list-level-style-bullet text:level="1" '
                  'text:bullet-char="•" $attribute/></text:list-style>',
            ),
          ),
          _refused,
        );
      }
    },
  );

  test(
    'unqualified list continuation is refused instead of restarting silently',
    () async {
      const definition =
          '<text:list-style style:name="Numbers">'
          '<text:list-level-style-number text:level="1" '
          'style:num-format="1" style:num-suffix="."/></text:list-style>';
      for (final attribute in [
        'text:continue-numbering="true"',
        'text:continue-list="earlier"',
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _package(
              '<text:list text:style-name="Numbers" $attribute>'
              '<text:list-item><text:p>Continued</text:p></text:list-item></text:list>',
              automaticStyles: definition,
            ),
          ),
          _refused,
        );
      }
    },
  );

  test(
    'horizontal merged owner retains active citation and logical width',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<table:table><table:table-column table:number-columns-repeated="3"/>'
          '<table:table-row>'
          '<table:table-cell table:number-columns-spanned="+02">'
          '<text:p>${_mark(_citation(), '(Source)')}</text:p>'
          '</table:table-cell><table:covered-table-cell/>'
          '<table:table-cell><text:p>Neighbor</text:p></table:table-cell>'
          '</table:table-row></table:table>',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final table = current.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        expect(table.grid, [120, 120, 120]);
        expect(table.rows.single.cells.map((cell) => cell.gridSpan), [2, 1]);
        expect(table.rows.single.cells.map((cell) => cell.width), [240, 120]);
        expect(table.rows.single.cells.map((cell) => cell.vMerge), [
          WmlVMerge.none,
          WmlVMerge.none,
        ]);
        final field = WordZotero.fields(current).single;
        expect(field.cachedText, '(Source)');
        expect(field.canEdit, isTrue);
        expect(
          identical(
            field.paragraph,
            table.rows.single.cells.first.blocks.single,
          ),
          isTrue,
        );
        expect(
          (table.rows.single.cells.last.blocks.single as WmlParagraph).text,
          'Neighbor',
        );
      }
    },
  );

  test('combined spans inherit fill and emit empty native continuations', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '<table:table table:style-name="T">'
        '<table:table-column table:style-name="C"/>'
        '<table:table-column table:number-columns-repeated="2"/>'
        '<table:table-row table:style-name="R">'
        '<table:table-cell table:style-name="Child" '
        'table:number-columns-spanned="2" table:number-rows-spanned="2">'
        '<text:p>${_mark(_citation(), '(Merged)')}</text:p></table:table-cell>'
        '<table:covered-table-cell table:style-name="Base"/>'
        '<table:table-cell><text:p>Top</text:p></table:table-cell>'
        '</table:table-row><table:table-row>'
        '<table:covered-table-cell/><table:covered-table-cell/>'
        '<table:table-cell><text:p>Bottom</text:p></table:table-cell>'
        '</table:table-row></table:table>',
        automaticStyles:
            '<style:style style:name="T" style:family="table">'
            '<style:table-properties style:width="240pt"/></style:style>'
            '<style:style style:name="C" style:family="table-column">'
            '<style:table-column-properties style:column-width="80pt"/></style:style>'
            '<style:style style:name="R" style:family="table-row">'
            '<style:table-row-properties fo:keep-together="always" '
            'style:min-row-height="18pt"/></style:style>'
            '<style:style style:name="Base" style:family="table-cell">'
            '<style:table-cell-properties fo:background-color="#12AbCd"/></style:style>'
            '<style:style style:name="Child" style:family="table-cell" '
            'style:parent-style-name="Base"/>',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final table = current.sections.single.blocks.whereType<WmlTable>().single;
      expect(table.grid, [80, 80, 80]);
      expect(table.rows.first.cantSplit, isTrue);
      expect(table.rows.first.height, 18);
      expect(table.rows.map((row) => row.cells.length), [2, 2]);
      final origin = table.rows.first.cells.first;
      final continuation = table.rows.last.cells.first;
      expect(origin.vMerge, WmlVMerge.restart);
      expect(continuation.vMerge, WmlVMerge.cont);
      for (final cell in [origin, continuation]) {
        expect(cell.gridSpan, 2);
        expect(cell.width, 160);
        expect(cell.fillColor, '12ABCD');
      }
      expect(continuation.blocks, hasLength(1));
      expect((continuation.blocks.single as WmlParagraph).text, isEmpty);
      final field = WordZotero.fields(current).single;
      expect(field.cachedText, '(Merged)');
      expect(field.canEdit, isTrue);
      expect(identical(field.paragraph, origin.blocks.single), isTrue);
    }
  });

  test('repeated table ownership still refuses active citations', () async {
    final paragraph = '<text:p>${_mark(_citation(), 'Citation')}</text:p>';
    for (final body in [
      '<table:table><table:table-row table:number-rows-repeated="2">'
          '<table:table-cell>$paragraph</table:table-cell></table:table-row></table:table>',
      '<table:table><table:table-row><table:table-cell table:number-columns-repeated="2">'
          '$paragraph</table:table-cell></table:table-row></table:table>',
    ]) {
      await expectLater(OdtDocumentReader.readBytes(_package(body)), _refused);
    }
  });

  test(
    'malformed span values refuse instead of using Dart integer syntax',
    () async {
      for (final (name, invalid) in [
        ('number-columns-spanned', '0'),
        ('number-columns-spanned', '33'),
        ('number-columns-spanned', '0x2'),
        ('number-columns-spanned', '\u00a02'),
        ('number-columns-spanned', '2\u00a0'),
        ('number-columns-spanned', '1.0'),
        ('number-rows-spanned', '-1'),
        ('number-rows-spanned', '257'),
        ('number-rows-spanned', '1e0'),
        ('number-rows-spanned', ''),
      ]) {
        // Supply valid two-column coverage for numeric-looking values, so
        // refusal proves the lexical guard rather than a separate overhang.
        final covered =
            invalid == '0x2' || invalid == '\u00a02' || invalid == '2\u00a0'
            ? '<table:covered-table-cell/>'
            : '';
        await expectLater(
          OdtDocumentReader.readBytes(
            _package(
              '<table:table><table:table-row><table:table-cell table:$name="$invalid">'
              '<text:p>${_mark(_citation(), 'Citation')}</text:p>'
              '</table:table-cell>$covered</table:table-row></table:table>',
            ),
          ),
          _refused,
          reason: '$name=$invalid',
        );
      }
    },
  );

  test(
    'JSON preferences normalize at explicit import and preserve extensions',
    () async {
      final data = jsonEncode({
        'dataVersion': 4,
        'style': {
          'styleID': 'http://www.zotero.org/styles/apa',
          'locale': 'de-DE',
        },
        'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
        'extension': {'retained': 'x' * 3000, 'unicode': 'العربية 😀'},
      });
      final bytes = _package(
        '<text:p>${_mark(_citation(), '(Smith)')}</text:p>',
        metadata: _metadata(data, reverseChunks: true),
      );
      final before = Uint8List.fromList(bytes);
      expect(() => WordZoteroDocumentData.toHttp(data), throwsFormatException);
      final document = await OdtDocumentReader.readBytes(bytes);
      final expected = jsonDecode(data) as Map<String, dynamic>;
      (expected['prefs'] as Map<String, dynamic>)['fieldType'] = 'Field';
      for (final current in [document, _reopen(document)]) {
        final stored = WordZoteroDocumentData.read(current);
        expect(jsonDecode(stored), expected);
        expect(WordZoteroDocumentData.stylePreferences(stored), (
          id: 'http://www.zotero.org/styles/apa',
          locale: 'de-DE',
          noteType: 0,
        ));
        final http = jsonDecode(WordZoteroDocumentData.toHttp(stored)) as Map;
        expect((http['prefs'] as Map)['fieldType'], 'Http');
      }
      expect(bytes, before);
      final inventory = await OdfZotero.inspect(bytes);
      expect(inventory.preferences.rawData, data);
      expect(inventory.preferences.fieldType, 'ReferenceMark');
    },
  );

  test(
    'XML preferences retain style and namespace extensions during conversion',
    () async {
      const data =
          '<data data-version="3"><style id="http://www.zotero.org/styles/apa" '
          'locale="ar"/><prefs><pref name="fieldType" value="ReferenceMark"/>'
          '<pref name="noteType" value="0"/></prefs>'
          '<extension xmlns="urn:future">retain 😀</extension></data>';
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>${_mark(_citation(), 'Citation')}</text:p>',
          metadata: _metadata(data),
        ),
      );
      for (final current in [document, _reopen(document)]) {
        final stored = WordZoteroDocumentData.read(current);
        expect(stored, contains('value="Field"'));
        expect(stored, isNot(contains('ReferenceMark')));
        final root = XmlDocument.parse(stored).root!;
        expect(
          root
              .childrenNamed('extension', namespaceUri: 'urn:future')
              .single
              .text,
          'retain 😀',
        );
        expect(WordZoteroDocumentData.stylePreferences(stored), (
          id: 'http://www.zotero.org/styles/apa',
          locale: 'ar',
          noteType: 0,
        ));
      }
      expect(() => WordZoteroDocumentData.toHttp(data), throwsFormatException);
    },
  );

  test(
    'native citation remains updateable and unlink preserves rich cache',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>Before ${_mark(_citation(), '(<text:span text:style-name="Italic">Smith</text:span>, 2026)')} after</text:p>',
          automaticStyles: _richStyles,
        ),
      );
      final field = WordZotero.fields(document).single;
      final changed = ZoteroCitationItem.fromJson({
        ...field.citation!.items.first.toJson(),
        'locator': '99',
      });
      WordZotero.updateCitation(
        field,
        field.citation!.withItems([
          changed,
          field.citation!.items.last,
        ], plainCitation: field.cachedText),
      );
      final reopened = _reopen(document);
      final active = WordZotero.fields(reopened).single;
      expect(active.citation!.items.first.locator, '99');
      expect(
        active.citation!.toJson()['futureRoot'],
        _citationData()['futureRoot'],
      );
      expect(
        _runContaining(active.paragraph, 'Smith').properties.italic,
        isTrue,
      );
      WordZotero.unlink(active);
      expect(WordZotero.fields(reopened), isEmpty);
      expect(reopened.paragraphs.single.text, 'Before (Smith, 2026) after');
      expect(
        _runContaining(reopened.paragraphs.single, 'Smith').properties.italic,
        isTrue,
      );
      expect(WordZotero.fields(_reopen(reopened)), isEmpty);
    },
  );

  test(
    'imported DOCX fields accept a staged Zotero refresh transaction',
    () async {
      final imported = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>Lead ${_mark(_citation(), '(Old)')} tail</text:p>'
          '${_section(_bibliography(), '<text:p>Old first entry.</text:p><text:p>Old second entry.</text:p>')}'
          '<text:p>After</text:p>',
          metadata: _metadata(
            jsonEncode({
              'dataVersion': 4,
              'style': {
                'styleID': 'http://www.zotero.org/styles/apa',
                'locale': 'de-DE',
              },
              'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
              'futurePreferences': {'preserve': true},
            }),
          ),
        ),
      );
      final document = _reopen(imported);
      final originalText = document.paragraphs.map((p) => p.text).toList();
      final session = WordZoteroCitingSession(
        document: document,
        documentId: 'odt-refresh',
        insertionParagraph: document.paragraphs.first,
      );
      Object? call(String command, [List<Object?> args = const []]) =>
          session.handle(command, ['odt-refresh', ...args]);
      final fields = (call('Document.getFields', ['Http']) as List)
          .cast<Map<String, Object>>();
      expect(fields, hasLength(2));
      final citationField = fields.singleWhere(
        (f) => (f['code'] as String).startsWith('ITEM'),
      );
      final bibliographyField = fields.singleWhere(
        (f) => (f['code'] as String).startsWith('BIBL'),
      );
      final citation = WordZotero.fields(document).first.citation!;
      const citationHtml = '(<b>Updated</b>)';
      final updated = citation.withItems(
        citation.items,
        plainCitation: '(Updated)',
        formattedCitation: citationHtml,
      );
      call('Field.setCode', [
        citationField['id'],
        'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
      ]);
      call('Field.setText', [citationField['id'], citationHtml, true]);
      call('Document.setBibliographyStyle', [
        -720,
        720,
        480,
        240,
        <int>[720],
        1,
      ]);
      call('Field.setCode', [
        bibliographyField['id'],
        'BIBL ${jsonEncode(_bibliographyData)} CSL_BIBLIOGRAPHY',
      ]);
      call('Field.setText', [
        bibliographyField['id'],
        '<div class="csl-entry">Updated <i>Book</i>.</div>'
            '<div class="csl-entry">Second <b>Book</b>.</div>',
        true,
      ]);
      call('Document.setDocumentData', [call('Document.getDocumentData')]);
      expect(document.paragraphs.map((p) => p.text), originalText);
      call('Document.complete');
      session.prepareReview();
      session.apply();
      for (final current in [document, _reopen(document)]) {
        final refreshed = WordZotero.fields(current);
        expect(refreshed.map((f) => f.cachedText), [
          '(Updated)',
          'Updated Book.\nSecond Book.',
        ]);
        expect(
          refreshed.first.citation!.toJson()['futureRoot'],
          _citationData()['futureRoot'],
        );
        expect(
          _runContaining(refreshed.first.paragraph, 'Updated').properties.bold,
          isTrue,
        );
        expect(refreshed.last.metadata, _bibliographyData);
        expect(refreshed.last.paragraphs, hasLength(2));
        expect(
          _runContaining(
            refreshed.last.paragraphs.first,
            'Book',
          ).properties.italic,
          isTrue,
        );
        expect(
          refreshed.last.paragraphs.every(
            (p) => p.properties.indent.hanging == 36,
          ),
          isTrue,
        );
        expect(
          refreshed.last.paragraphs.every((p) => p.properties.lineSpacing == 2),
          isTrue,
        );
        expect(current.paragraphs.first.text, 'Lead (Updated) tail');
        expect(current.paragraphs.last.text, 'After');
        final preferences =
            jsonDecode(WordZoteroDocumentData.read(current)) as Map;
        expect(preferences['futurePreferences'], {'preserve': true});
      }
    },
  );

  test(
    'imported citation can convert through footnote, endnote and inline styles',
    () async {
      var document = await OdtDocumentReader.readBytes(
        _package(
          '<text:p>Before ${_mark(_citation(), '(Source)')} after</text:p>',
        ),
      );
      for (final noteType in [1, 2, 0]) {
        document = _reopen(document);
        final before = document.paragraphs.map((p) => p.text).toList();
        final session = WordZoteroCitingSession(
          document: document,
          documentId: 'odt-convert',
          insertionParagraph: document.paragraphs.first,
        );
        Object? call(String command, [List<Object?> args = const []]) =>
            session.handle(command, ['odt-convert', ...args]);
        final fields = (call('Document.getFields', ['Http']) as List)
            .cast<Map<String, Object>>();
        final fieldId = fields.single['id'];
        call('Document.convert', [
          [fieldId],
          'Http',
          [noteType],
        ]);
        final converted =
            (call('Document.getFields', ['Http']) as List).single as Map;
        expect(converted['noteIndex'], noteType == 0 ? 0 : 1);
        expect(document.paragraphs.map((p) => p.text), before);
        call('Document.complete');
        session.apply();
        final persisted = _reopen(document);
        expect(persisted.footnotes, hasLength(noteType == 1 ? 1 : 0));
        expect(persisted.endnotes, hasLength(noteType == 2 ? 1 : 0));
        final field = WordZotero.fields(persisted).single;
        expect(field.cachedText, '(Source)');
        expect(field.canEdit, isTrue);
        expect(
          field.citation!.toJson()['futureRoot'],
          _citationData()['futureRoot'],
        );
        if (noteType == 0) {
          expect(persisted.paragraphs.single.text, 'Before (Source) after');
        }
      }
    },
  );

  test(
    'malformed, incomplete, duplicate and crossed fields reject atomically',
    () async {
      final one = _citation();
      final two = _citation(id: 'second', suffix: 'abcdefghij');
      final invalid = 'ZOTERO_ITEM CSL_CITATION {broken} RND0123456789';
      for (final body in [
        '<text:p>${_mark(invalid, 'Malformed')}</text:p>',
        '<text:p>${_start(one)}Missing end</text:p>',
        '<text:p>${_end(one)}Missing start</text:p>',
        '<text:p>${_mark(one, 'First')}${_mark(one, 'Duplicate')}</text:p>',
        '<text:p>${_start(one)}A${_start(two)}B${_end(one)}C${_end(two)}</text:p>',
        '<text:p><text:reference-mark text:name="${encodeXmlAttribute(one)}"/></text:p>',
      ]) {
        final bytes = _package(body);
        final before = Uint8List.fromList(bytes);
        await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
        expect(bytes, before);
      }
    },
  );

  test(
    'protected, linked and unsupported structural content is not flattened',
    () async {
      for (final body in [
        _section(
          _bibliography(),
          '<text:p>Protected</text:p>',
          attributes: 'text:protected="true"',
        ),
        _section(
          _bibliography(),
          '<text:section-source xlink:href="other.odt"/><text:p>Linked</text:p>',
        ),
        '<draw:frame><draw:text-box><text:p>Hidden research</text:p></draw:text-box></draw:frame>',
        '<text:alphabetical-index><text:index-body><text:p>Index</text:p></text:index-body></text:alphabetical-index>',
        '<office:annotation><text:p>Annotation</text:p></office:annotation>',
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(_package(body)),
          _refused,
        );
      }
    },
  );

  test(
    'damaged preferences refuse instead of publishing fields with defaults',
    () async {
      final body = '<text:p>${_mark(_citation(), 'Citation')}</text:p>';
      final invalidMetadata = <String>[
        _metadata('{broken'),
        '<office:document-meta $_namespaces><office:meta>'
            '${_property('ZOTERO_PREF_1', '{"prefs":{"fieldType":"ReferenceMark"}}')}'
            '${_property('ZOTERO_PREF_1', '{"prefs":{"fieldType":"Field"}}')}'
            '</office:meta></office:document-meta>',
      ];
      for (final metadata in invalidMetadata) {
        await expectLater(
          OdtDocumentReader.readBytes(_package(body, metadata: metadata)),
          _refused,
        );
      }
    },
  );

  test('wrong package kind and duplicate content are refused', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(
          '<text:p>Text</text:p>',
          mimetype: 'application/vnd.oasis.opendocument.spreadsheet',
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      OdtDocumentReader.readBytes(
        _package('<text:p>Text</text:p>', duplicateContent: true),
      ),
      throwsA(isA<ZipDuplicateEntryException>()),
    );
  });

  test(
    'configured resource bounds fail without returning a partial document',
    () async {
      final cases = <(Uint8List, OdfZoteroLimits, String)>[
        (
          _package('<text:p>One</text:p><text:p>Two</text:p>'),
          const OdfZoteroLimits(maxParagraphs: 1),
          'paragraphs',
        ),
        (
          _package(
            '<text:p>${_mark(_citation(), 'A')}${_mark(_citation(suffix: 'abcdefghij'), 'B')}</text:p>',
          ),
          const OdfZoteroLimits(maxFields: 1),
          'fields',
        ),
        (
          _package('<text:p>abcdef</text:p><text:p>ghijkl</text:p>'),
          const OdfZoteroLimits(maxTextBytes: 10),
          'decoded text',
        ),
        (
          _package('<text:p><text:s text:c="1000"/></text:p>'),
          const OdfZoteroLimits(maxTextBytes: 20),
          'decoded text',
        ),
        (
          _package('<text:p>Text</text:p>'),
          const OdfZoteroLimits(maxArchiveBytes: 32),
          'archive bytes',
        ),
      ];
      for (final (bytes, limits, name) in cases) {
        await expectLater(
          OdtDocumentReader.readBytes(bytes, limits: limits),
          throwsA(
            name == 'decoded text'
                ? isA<FormatException>().having(
                    (e) => e.message,
                    'content limit',
                    anyOf(contains('content limit'), contains('decoded text')),
                  )
                : isA<OdfZoteroLimitException>().having(
                    (e) => e.limit,
                    'limit',
                    name,
                  ),
          ),
        );
      }
    },
  );
}
