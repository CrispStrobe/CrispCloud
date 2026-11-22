import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _namespaces =
    'xmlns:office="$_office" xmlns:text="$_text" '
    'xmlns:style="$_style" xmlns:meta="$_meta"';
const _revision = '2c87e51eeaa2b413ff4ae097b2705eea1995d8e5';
const _generator =
    'LibreOfficeDev/26.8.0.0.alpha0\$Linux_X86_64 LibreOffice_project/$_revision';

String _generatorElement(String value) =>
    '<meta:generator>${encodeXmlText(value)}</meta:generator>';

String _citation(String id) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION '
    '${jsonEncode({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '17',
          'label': 'page',
        },
      ],
      'properties': {'plainCitation': '(Author, 17)'},
    })} RND0123456789',
  );
  return '<text:reference-mark-start text:name="$name"/>'
      '(Author, 17)<text:reference-mark-end text:name="$name"/>';
}

String _note(
  String id,
  String label, {
  bool endnote = false,
  bool citation = false,
}) =>
    '<text:note text:id="$id" '
    'text:note-class="${endnote ? 'endnote' : 'footnote'}">'
    '<text:note-citation>${encodeXmlText(label)}</text:note-citation>'
    '<text:note-body><text:p>Note $id '
    '${citation ? _citation(id) : 'prose'}'
    '</text:p></text:note-body></text:note>';

Uint8List _package(
  String notes, {
  String? generator = _generator,
  String? generatorXml,
  String? metadataXml,
  String configuration =
      '<text:notes-configuration text:note-class="footnote" '
      'style:num-format="1" text:start-value="0" '
      'text:start-numbering-at="document" text:footnotes-position="page"/>'
      '<text:notes-configuration text:note-class="endnote" '
      'style:num-format="1" text:start-value="0"/>',
}) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_namespaces><office:body><office:text>'
      '<text:p>Anchors $notes</text:p>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  writer.addFile(
    'styles.xml',
    utf8.encode(
      '<office:document-styles $_namespaces><office:styles>'
      '$configuration</office:styles></office:document-styles>',
    ),
  );
  writer.addFile(
    'meta.xml',
    utf8.encode(
      metadataXml ??
          '<office:document-meta $_namespaces><office:meta>'
              '${generatorXml ?? (generator == null ? '' : _generatorElement(generator))}'
              '<meta:user-defined meta:name="ZOTERO_PREF_1">'
              '${encodeXmlText(jsonEncode({
                'dataVersion': 4,
                'style': {'styleID': 'http://www.zotero.org/styles/apa'},
                'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
              }))}</meta:user-defined>'
              '</office:meta></office:document-meta>',
    ),
  );
  return writer.close();
}

void main() {
  test(
    'qualified LibreOffice offsets keep independent decimal note sequences',
    () async {
      final bytes = _package(
        _note('foot-one', '1', citation: true) +
            _note('end-one', '1', endnote: true, citation: true) +
            _note('foot-two', '2', citation: true) +
            _note('end-two', '2', endnote: true, citation: true),
      );
      final original = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        final numbering = WordNoteNumbering(document);
        expect(document.footnotes.map(numbering.labelFor), ['1', '2']);
        expect(document.endnotes.map(numbering.labelFor), ['1', '2']);
        expect(numbering.notes.every(numbering.hasExactLabel), isTrue);
        expect(numbering.notes.map((note) => (note.endnote, note.id)), [
          (false, 1),
          (true, 1),
          (false, 2),
          (true, 2),
        ]);
        final fields = WordZotero.fields(document);
        expect(fields.map((field) => field.citation!.citationId), [
          'foot-one',
          'foot-two',
          'end-one',
          'end-two',
        ]);
        expect(fields.every((field) => field.canEdit), isTrue);
        expect(
          fields.map((field) => field.cachedText),
          List.filled(4, '(Author, 17)'),
        );
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
      expect(bytes, original);
    },
  );

  for (final generator in [
    _generator,
    'LibreOffice/25.8.3.2\$Windows_X86_64 LibreOffice_project/$_revision',
    'LibreOffice/7.6.7.2\$MacOSX_X86_64 LibreOffice_project/$_revision',
  ]) {
    test('recognizes stock producer declaration $generator', () async {
      final document = await OdtDocumentReader.readBytes(
        _package(_note('one', '1'), generator: generator),
      );
      expect(
        WordNoteNumbering(document).labelFor(document.footnotes.single),
        '1',
      );
    });
  }

  for (final generator in <String?>[
    null,
    'Unknown/1.0',
    'LibreOffice',
    'LibreOffice/26.8.0',
    'Fake$_generator',
    '$_generator trailing',
    '$_generator\n',
    ' $_generator',
    _generator.replaceFirst('LibreOffice_project/', 'Other_project/'),
    _generator.replaceFirst(_revision, 'short'),
  ]) {
    test(
      'does not infer offset semantics from unqualified generator $generator',
      () async {
        final bytes = _package(_note('one', '1'), generator: generator);
        final original = Uint8List.fromList(bytes);
        await expectLater(
          OdtDocumentReader.readBytes(bytes),
          throwsUnsupportedError,
        );
        expect(bytes, original);
      },
    );
  }

  for (final generatorXml in [
    _generatorElement(_generator) + _generatorElement(_generator),
    '<meta:generator><meta:generator>${encodeXmlText(_generator)}'
        '</meta:generator></meta:generator>',
    '<meta:generator xmlns:meta="urn:unrelated">${encodeXmlText(_generator)}</meta:generator>',
    '<meta:generator text:id="claimed">${encodeXmlText(_generator)}</meta:generator>',
    '<meta:user-defined meta:name="generator">${encodeXmlText(_generator)}</meta:user-defined>',
  ]) {
    test(
      'ambiguous or indirect generator does not qualify zero offset $generatorXml',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _package(_note('one', '1'), generatorXml: generatorXml),
          ),
          throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
        );
      },
    );
  }

  for (final label in ['', ' ', ' 1 ', '1\n', '0', '2', '01', 'i', '١']) {
    test(
      'zero-offset compatibility requires exact cached first ordinal "$label"',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(_package(_note('one', label))),
          throwsUnsupportedError,
        );
      },
    );
  }

  test('all notes must confirm the independent ordinal sequence', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(_note('one', '1') + _note('two', '1')),
      ),
      throwsUnsupportedError,
    );
  });

  for (final attribute in [
    'text:start-value="1"',
    'text:start-value="2"',
    'text:start-value="-1"',
    'text:start-value="00"',
    'text:start-value="0" style:num-format="i"',
    'text:start-value="0" text:start-numbering-at="page"',
    'text:start-value="0" style:num-prefix="["',
    'text:start-value="0" text:citation-style-name="Custom"',
  ]) {
    test(
      'producer qualification does not relax note guards for $attribute',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _package(
              _note('one', '1'),
              configuration:
                  '<text:notes-configuration text:note-class="footnote" $attribute/>',
            ),
          ),
          attribute.contains('citation-style-name')
              ? throwsA(isA<FormatException>())
              : throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'generic ODF still uses canonical start one and permits an empty cache',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          _note('one', ''),
          generator: 'Other/1.0',
          configuration:
              '<text:notes-configuration text:note-class="footnote" style:num-format="1" text:start-value="1"/>',
        ),
      );
      expect(
        WordNoteNumbering(document).labelFor(document.footnotes.single),
        '1',
      );
    },
  );
}
