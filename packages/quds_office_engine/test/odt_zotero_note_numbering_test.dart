import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _ns =
    'xmlns:office="$_office" xmlns:text="$_text" '
    'xmlns:style="$_style" xmlns:meta="$_meta"';
const _lower = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x'];
const _offsetGenerator = 'CrispOffice Zotero ODT note-offsets/1';
const _libreOfficeGenerator =
    'LibreOfficeDev/26.8.0.0.alpha0\$Linux_X86_64 '
    'LibreOffice_project/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5';

ZoteroCitation _citation(String id) => ZoteroCitation.fromJson({
  'citationID': id,
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '17–19',
      'label': 'page',
      'prefix': 'see ',
      'suffix': ' retained',
      'suppress-author': true,
      'itemData': {'id': 7, 'type': 'book', 'title': 'Über العربية 😀'},
    },
  ],
  'properties': {'plainCitation': '(Author, 17–19)'},
});

String _preferences({String fieldType = 'Field'}) => jsonEncode({
  'dataVersion': 4,
  'style': {
    'styleID': 'http://www.zotero.org/styles/chicago-fullnote-bibliography',
  },
  'prefs': {'fieldType': fieldType, 'noteType': 2},
  'futureData': {'retained': true},
});

WmlSectionSource _options(bool endnote, String properties) => WmlSectionSource(
  xml:
      '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
      '<w:${endnote ? 'endnotePr' : 'footnotePr'}>$properties'
      '</w:${endnote ? 'endnotePr' : 'footnotePr'}></w:sectPr>',
  values: const {},
);

WmlDocument _native({
  bool endnote = true,
  String? format,
  int count = 10,
  int? citedIndex,
  int? start,
  String extraProperties = '',
}) {
  final anchors = <WmlBlock>[];
  final notes = <WmlNote>[];
  for (var index = 0; index < count; index++) {
    final id = 17 + index * 7;
    anchors.add(
      WmlParagraph(
        inlines: [
          WmlRun(text: 'Before $index '),
          WmlRun(
            text: '$id',
            noteRefId: id,
            noteRefEndnote: endnote,
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
          WmlRun(text: ' after'),
        ],
      ),
    );
    final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Note $index ')]);
    if (index == (citedIndex ?? count - 1)) {
      WordZotero.insertCitation(paragraph, _citation('citation-$index'));
    }
    notes.add(WmlNote(id: id, endnote: endnote, paragraphs: [paragraph]));
  }
  return WmlDocument(
    zoteroDocumentData: _preferences(),
    sections: [
      WmlSection(
        blocks: anchors,
        sourceProperties:
            format == null && start == null && extraProperties.isEmpty
            ? null
            : _options(
                endnote,
                '${format == null ? '' : '<w:numFmt w:val="$format"/>'}'
                '${start == null ? '' : '<w:numStart w:val="$start"/>'}'
                '$extraProperties',
              ),
      ),
    ],
    footnotes: endnote ? [] : notes,
    endnotes: endnote ? notes : [],
  );
}

XmlElement _xml(Uint8List bytes, String part) =>
    XmlDocument.parse(utf8.decode(ZipReader.fromBytes(bytes).read(part))).root!;

Iterable<XmlElement> _elements(XmlElement root, String local, String ns) sync* {
  if (root.localName == local && root.namespaceUri == ns) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, local, ns);
  }
}

WmlDocument _docx(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _state(WmlDocument document) => jsonEncode({
  'preferences': WordZoteroDocumentData.read(document),
  'sectionProperties': document.sections
      .map((section) => section.sourceProperties?.xml)
      .toList(),
  'paragraphs': [
    for (final paragraph in [
      ...document.paragraphs,
      for (final note in [...document.footnotes, ...document.endnotes])
        ...note.allParagraphs,
    ])
      {
        'text': paragraph.text,
        'field': paragraph.properties.fieldInstruction,
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'text': run.text,
              'noteId': run.noteRefId,
              'endnote': run.noteRefEndnote,
              'custom': run.noteRefCustomMark,
              'field': run.fieldInstruction,
            },
        ],
      },
  ],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      {'id': note.id, 'endnote': note.endnote, 'text': note.text},
  ],
  'fields': WordZotero.fields(
    document,
  ).map((field) => field.instruction).toList(),
  'package': document.package == null
      ? null
      : {
          for (final part in document.package!.parts)
            part.uri: sha256
                .convert(document.package!.getPart(part.uri)!.readBytes())
                .toString(),
        },
});

void _unchangedAfterRefusal(WmlDocument document) {
  final before = _state(document);
  final package = document.package;
  final references = [
    for (final paragraph in document.paragraphs)
      ...paragraph.inlines.whereType<WmlRun>(),
  ];
  final cached = references.map((run) => run.text).toList();
  expect(
    () => OdtDocumentWriter.writeEditableZoteroBytes(document),
    throwsUnsupportedError,
  );
  expect(references.map((run) => run.text), cached);
  expect(_state(document), before);
  expect(document.package, same(package));
}

// Independently authored native ODF; this does not use Quds' ODT exporter.
Uint8List _odf({
  String format = 'i',
  List<String> labels = _lower,
  bool endnote = true,
  String extraConfiguration = '',
  String? generator,
  String? generatorMarkup,
  String? configurations,
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final mark = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citation('odf-note').toJson())} '
    'RNDabcdefghij',
  );
  final notes = StringBuffer();
  for (var index = 0; index < labels.length; index++) {
    notes.write(
      '<text:p>Anchor $index '
      '<text:note text:id="source-$index" text:note-class="$kind">'
      '<text:note-citation>${encodeXmlText(labels[index])}</text:note-citation>'
      '<text:note-body><text:p>Note $index ',
    );
    if (index == labels.length - 1) {
      notes.write(
        '<text:reference-mark-start text:name="$mark"/>'
        '(Author, 17–19)<text:reference-mark-end text:name="$mark"/>',
      );
    }
    notes.write('</text:p></text:note-body></text:note> after</text:p>');
  }
  final archive = ZipWriter();
  archive.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  archive.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_ns><office:body><office:text>'
      '$notes</office:text></office:body></office:document-content>',
    ),
  );
  archive.addFile(
    'styles.xml',
    utf8.encode(
      '<office:document-styles $_ns><office:styles>'
      '${configurations ?? '<text:notes-configuration text:note-class="$kind" style:num-format="$format" $extraConfiguration/>'}'
      '</office:styles></office:document-styles>',
    ),
  );
  archive.addFile(
    'meta.xml',
    utf8.encode(
      '<office:document-meta $_ns><office:meta>'
      '${generatorMarkup ?? (generator == null ? '' : '<meta:generator>${encodeXmlText(generator)}</meta:generator>')}'
      '<meta:user-defined meta:name="ZOTERO_PREF_1">'
      '${encodeXmlText(_preferences(fieldType: 'ReferenceMark'))}'
      '</meta:user-defined></office:meta></office:document-meta>',
    ),
  );
  return archive.close();
}

void main() {
  for (final endnote in [false, true]) {
    for (final format in ['decimal', 'lowerRoman', 'upperRoman']) {
      test(
        '$format ${endnote ? 'endnotes' : 'footnotes'} stay editable',
        () async {
          final source = _native(endnote: endnote, format: format);
          final before = _state(source);
          final expected = switch (format) {
            'lowerRoman' => _lower,
            'upperRoman' => _lower.map((value) => value.toUpperCase()).toList(),
            _ => List.generate(10, (index) => '${index + 1}'),
          };
          var document = source;
          for (var cycle = 0; cycle < 2; cycle++) {
            final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
            final configuration = _elements(
              _xml(bytes, 'styles.xml'),
              'notes-configuration',
              _text,
            ).single;
            expect(
              configuration.getAttribute('num-format', namespaceUri: _style),
              switch (format) {
                'lowerRoman' => 'i',
                'upperRoman' => 'I',
                _ => '1',
              },
            );
            final labels = _elements(
              _xml(bytes, 'content.xml'),
              'note-citation',
              _text,
            );
            expect(labels.map((element) => element.text), expected);
            expect(
              labels.every(
                (element) =>
                    element.getAttribute('label', namespaceUri: _text) == null,
              ),
              isTrue,
            );
            final inventory = await OdfZotero.inspect(bytes);
            expect(inventory.fields.single.isImportCandidate, isTrue);
            document = _docx(await OdtDocumentReader.readBytes(bytes));
            final numbering = WordNoteNumbering(document);
            final notes = endnote ? document.endnotes : document.footnotes;
            expect(notes.map(numbering.labelFor), expected);
            expect(
              notes.map((note) => numbering.automaticNumberFor(note)?.format),
              everyElement(format),
            );
            final field = WordZotero.fields(document).single;
            expect(field.citation!.toJson(), _citation('citation-9').toJson());
            expect(field.cachedText, '(Author, 17–19)');
            final preferences =
                jsonDecode(WordZoteroDocumentData.read(document))
                    as Map<String, Object?>;
            expect(preferences['futureData'], {'retained': true});
            final session = WordZoteroCitingSession(
              document: document,
              documentId: 'notes',
            );
            final fields =
                session.handle('Document.getFields', ['notes', 'Http'])!
                    as List<Object?>;
            expect((fields.single! as Map<String, Object>)['noteIndex'], 10);
            session.assertUnchanged();
          }
          expect(_state(source), before);
        },
      );
    }
  }

  for (final endnote in [false, true]) {
    for (final sample in [
      ('decimal', ['8', '9', '10', '11']),
      ('lowerRoman', ['viii', 'ix', 'x', 'xi']),
      ('upperRoman', ['VIII', 'IX', 'X', 'XI']),
    ]) {
      test(
        '${sample.$1} ${endnote ? 'endnotes' : 'footnotes'} starting at eight survive native exchange',
        () async {
          final source = _native(
            endnote: endnote,
            format: sample.$1,
            start: 8,
            count: 4,
          );
          final before = _state(source);
          var document = source;
          for (var cycle = 0; cycle < 2; cycle++) {
            final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
            expect(
              _elements(
                _xml(bytes, 'meta.xml'),
                'generator',
                _meta,
              ).single.text,
              _offsetGenerator,
            );
            final configuration = _elements(
              _xml(bytes, 'styles.xml'),
              'notes-configuration',
              _text,
            ).single;
            expect(
              configuration.getAttribute('start-value', namespaceUri: _text),
              '7',
            );
            final labels = _elements(
              _xml(bytes, 'content.xml'),
              'note-citation',
              _text,
            ).toList();
            expect(labels.map((label) => label.text), sample.$2);
            expect(
              labels.every(
                (label) =>
                    label.getAttribute('label', namespaceUri: _text) == null,
              ),
              isTrue,
            );
            document = _docx(await OdtDocumentReader.readBytes(bytes));
            final notes = endnote ? document.endnotes : document.footnotes;
            final numbering = WordNoteNumbering(document);
            expect(notes.map(numbering.labelFor), sample.$2);
            expect(
              notes.map((note) => numbering.automaticNumberFor(note)?.start),
              everyElement(8),
            );
            expect(
              notes.map((note) => numbering.automaticNumberFor(note)?.number),
              [8, 9, 10, 11],
            );
            final session = WordZoteroCitingSession(
              document: document,
              documentId: 'started-notes',
            );
            final fields =
                session.handle('Document.getFields', ['started-notes', 'Http'])!
                    as List<Object?>;
            expect((fields.single! as Map<String, Object>)['noteIndex'], 4);
            expect(
              WordZotero.fields(document).single.citation!.toJson(),
              _citation('citation-3').toJson(),
            );
            session.assertUnchanged();
          }
          expect(_state(source), before);
        },
      );
    }
  }

  for (final source in [
    (null, '8'),
    ('CrispOffice', '8'),
    (_libreOfficeGenerator, '7'),
    (_offsetGenerator, '7'),
  ]) {
    test(
      'independent ODF honors the exact start convention of ${source.$1}',
      () async {
        final bytes = _odf(
          generator: source.$1,
          labels: ['viii', 'ix', 'x'],
          extraConfiguration: 'text:start-value="${source.$2}"',
        );
        final original = Uint8List.fromList(bytes);
        final document = _docx(await OdtDocumentReader.readBytes(bytes));
        final numbering = WordNoteNumbering(document);
        expect(document.endnotes.map(numbering.labelFor), ['viii', 'ix', 'x']);
        expect(
          document.endnotes.map(
            (note) => numbering.automaticNumberFor(note)?.start,
          ),
          everyElement(8),
        );
        expect(
          WordZotero.fields(document).single.citation!.citationId,
          'odf-note',
        );
        expect(bytes, original);
        final preserved = document.package!.getPart(
          '/customXml/qudsOdtMetadata.xml',
        )!;
        expect(
          preserved.readBytes(),
          ZipReader.fromBytes(bytes).read('meta.xml'),
        );
      },
    );
  }

  for (final endStart in [1, 99]) {
    test(
      'interleaved foot/endnote starts eight and $endStart stay independent',
      () async {
        final foot = _native(
          endnote: false,
          format: 'upperRoman',
          start: 8,
          count: 2,
        );
        final end = _native(format: 'decimal', start: endStart, count: 2);
        final document = WmlDocument(
          zoteroDocumentData: _preferences(),
          footnotes: foot.footnotes,
          endnotes: end.endnotes,
          sections: [
            WmlSection(
              sourceProperties: WmlSectionSource(
                xml:
                    '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                    '<w:footnotePr><w:numFmt w:val="upperRoman"/><w:numStart w:val="8"/></w:footnotePr>'
                    '<w:endnotePr><w:numFmt w:val="decimal"/><w:numStart w:val="$endStart"/></w:endnotePr>'
                    '</w:sectPr>',
                values: const {},
              ),
              blocks: [
                foot.sections.single.blocks[0],
                end.sections.single.blocks[0],
                foot.sections.single.blocks[1],
                end.sections.single.blocks[1],
              ],
            ),
          ],
        );
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
        final configurations = _elements(
          _xml(bytes, 'styles.xml'),
          'notes-configuration',
          _text,
        );
        expect(
          {
            for (final configuration in configurations)
              configuration.getAttribute(
                'note-class',
                namespaceUri: _text,
              ): configuration.getAttribute(
                'start-value',
                namespaceUri: _text,
              ),
          },
          {'footnote': '7', 'endnote': '${endStart - 1}'},
        );
        final restored = _docx(await OdtDocumentReader.readBytes(bytes));
        final numbering = WordNoteNumbering(restored);
        expect(numbering.notes.map(numbering.labelFor), [
          'VIII',
          '$endStart',
          'IX',
          '${endStart + 1}',
        ]);
        final session = WordZoteroCitingSession(
          document: restored,
          documentId: 'mixed',
        );
        final fields =
            session.handle('Document.getFields', ['mixed', 'Http'])! as List;
        expect(fields.map((field) => (field as Map)['noteIndex']), [2, 2]);
      },
    );
  }

  test(
    'equal explicit starts remain continuous across native sections',
    () async {
      final source = _native(format: 'lowerRoman', start: 8, count: 2);
      final second = source.sections.single.blocks.removeLast();
      source.sections.add(
        WmlSection(
          blocks: [second],
          sourceProperties: _options(
            true,
            '<w:numFmt w:val="lowerRoman"/><w:numStart w:val="8"/>',
          ),
        ),
      );
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(source);
      expect(
        _elements(
          _xml(bytes, 'content.xml'),
          'note-citation',
          _text,
        ).map((note) => note.text),
        ['viii', 'ix'],
      );
      final restored = _docx(await OdtDocumentReader.readBytes(bytes));
      expect(restored.endnotes.map(WordNoteNumbering(restored).labelFor), [
        'viii',
        'ix',
      ]);
    },
  );

  test(
    'different dormant section starts keep the existing mixed-settings guard',
    () {
      final source = _native(format: 'lowerRoman', start: 8, count: 2);
      final second = source.sections.single.blocks.removeLast();
      source.sections.add(
        WmlSection(
          blocks: [second],
          sourceProperties: _options(
            true,
            '<w:numFmt w:val="lowerRoman"/><w:numStart w:val="9"/>',
          ),
        ),
      );
      _unchangedAfterRefusal(source);
    },
  );

  for (final sample in [
    ('decimal', 32768, ['32768', '32769']),
    ('lowerRoman', 3998, ['mmmcmxcviii', 'mmmcmxcix']),
    ('upperRoman', 3999, ['MMMCMXCIX']),
  ]) {
    test(
      '${sample.$1} maximum supported start/ordinal survives exchange',
      () async {
        final source = _native(
          format: sample.$1,
          start: sample.$2,
          count: sample.$3.length,
        );
        final restored = _docx(
          await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeEditableZoteroBytes(source),
          ),
        );
        final numbering = WordNoteNumbering(restored);
        expect(restored.endnotes.map(numbering.labelFor), sample.$3);
        expect(
          numbering.automaticNumberFor(restored.endnotes.first)?.start,
          sample.$2,
        );
      },
    );
  }

  for (final start in [0, -1, 32769, 1000000000]) {
    test('native start $start cannot exceed the exchange envelope', () {
      _unchangedAfterRefusal(
        _native(format: 'decimal', start: start, count: 1),
      );
    });
  }

  test('a valid Roman start cannot hide a later out-of-range note', () {
    _unchangedAfterRefusal(
      _native(format: 'lowerRoman', start: 3999, count: 2),
    );
  });

  for (final generator in [null, _libreOfficeGenerator, _offsetGenerator]) {
    for (final raw in [
      '-1',
      '+7',
      '07',
      '7 ',
      ' 7',
      '7.0',
      '7e0',
      '32769',
      '1000000000000000000',
    ]) {
      test(
        'invalid start $raw for $generator refuses before publishing',
        () async {
          await expectLater(
            OdtDocumentReader.readBytes(
              _odf(
                generator: generator,
                labels: ['viii'],
                extraConfiguration: 'text:start-value="$raw"',
              ),
            ),
            throwsUnsupportedError,
          );
        },
      );
    }
  }

  for (final generator in [_libreOfficeGenerator, _offsetGenerator]) {
    test(
      'offset 32768 is beyond the supported producer range for $generator',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: generator,
              format: '1',
              labels: ['32769'],
              extraConfiguration: 'text:start-value="32768"',
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );
  }

  for (final label in ['', 'vii', 'viii ', ' viii', 'VIII']) {
    test('non-one starts require their exact cached label $label', () async {
      for (final source in [
        (null, '8'),
        (_libreOfficeGenerator, '7'),
        (_offsetGenerator, '7'),
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: source.$1,
              labels: [label],
              extraConfiguration: 'text:start-value="${source.$2}"',
            ),
          ),
          throwsUnsupportedError,
        );
      }
    });
  }

  for (final configuration in [
    '',
    '<text:notes-configuration text:note-class="endnote" style:num-format="i"/>',
    '<text:notes-configuration text:note-class="endnote" text:start-value="0"/>',
  ]) {
    test(
      'Quds offset producer requires explicit configuration $configuration',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: _offsetGenerator,
              labels: ['i'],
              configurations: configuration,
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );
  }

  for (final generator in [
    '$_offsetGenerator ',
    ' $_offsetGenerator',
    'CrispOffice Zotero ODT note-offsets/2',
    'CrispOffice Zotero ODT note-offsets/10',
    '$_offsetGenerator extra',
  ]) {
    test(
      'approximate producer identity cannot enable offset semantics: $generator',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: generator,
              labels: ['viii'],
              extraConfiguration: 'text:start-value="7"',
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );
  }

  for (final markup in [
    '<meta:generator>$_offsetGenerator</meta:generator><meta:generator>$_offsetGenerator</meta:generator>',
    '<meta:generator meta:name="qualified">$_offsetGenerator</meta:generator>',
    '<meta:generator><meta:span>$_offsetGenerator</meta:span></meta:generator>',
    '<meta:generator xmlns:meta="urn:unrelated">$_offsetGenerator</meta:generator>',
    '<meta:wrapper><meta:generator>$_offsetGenerator</meta:generator></meta:wrapper>',
    '<meta:generator>$_offsetGenerator</meta:generator><meta:wrapper><meta:generator>$_offsetGenerator</meta:generator></meta:wrapper>',
  ]) {
    test(
      'ambiguous or wrapped producer metadata cannot enable offsets: $markup',
      () async {
        for (final sample in [('7', 'viii'), ('1', '')]) {
          await expectLater(
            OdtDocumentReader.readBytes(
              _odf(
                generatorMarkup: markup,
                labels: [sample.$2],
                extraConfiguration: 'text:start-value="${sample.$1}"',
              ),
            ),
            throwsUnsupportedError,
          );
        }
      },
    );
  }

  for (final markup in [
    '<meta:generator>$_libreOfficeGenerator</meta:generator>',
    '<meta:generator>$_libreOfficeGenerator</meta:generator><meta:generator>$_libreOfficeGenerator</meta:generator>',
    '<meta:generator meta:name="qualified">$_libreOfficeGenerator</meta:generator>',
    '<meta:generator><meta:span>$_libreOfficeGenerator</meta:span></meta:generator>',
    '<meta:generator xmlns:meta="urn:unrelated">$_libreOfficeGenerator</meta:generator>',
    '<meta:wrapper><meta:generator>$_libreOfficeGenerator</meta:generator></meta:wrapper>',
    '<meta:generator>$_libreOfficeGenerator</meta:generator><meta:wrapper><meta:generator>$_libreOfficeGenerator</meta:generator></meta:wrapper>',
  ]) {
    test(
      'LibreOffice producer metadata cannot fall back through an empty cache: $markup',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generatorMarkup: markup,
              labels: [''],
              extraConfiguration: 'text:start-value="1"',
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'an unknown normative producer still uses a literal initial number',
    () async {
      final restored = await OdtDocumentReader.readBytes(
        _odf(
          generator: 'Independent ODF producer/1.0',
          labels: [''],
          extraConfiguration: 'text:start-value="1"',
        ),
      );
      expect(
        WordNoteNumbering(restored).labelFor(restored.endnotes.single),
        'i',
      );
    },
  );

  test(
    'ordinary uncited notes cannot push the exchange counter past 65535',
    () {
      final source = _native(format: 'decimal', start: 32768, count: 32769);
      final last = source.endnotes.last;
      final originalText = last.text;
      final originalReference = source.paragraphs.last.inlines
          .whereType<WmlRun>()
          .singleWhere((run) => run.noteRefId != null);
      final originalCached = originalReference.text;
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(source),
        throwsUnsupportedError,
      );
      expect(last.text, originalText);
      expect(originalReference.text, originalCached);
      expect(
        WordZotero.fields(source).single.citation!.citationId,
        'citation-32768',
      );
    },
  );

  test(
    'start-one editable and ordinary cached exports retain their existing generator',
    () async {
      for (final bytes in [
        OdtDocumentWriter.writeEditableZoteroBytes(_native(count: 1)),
        OdtDocumentWriter.writeBytes(
          _native(format: 'lowerRoman', start: 8, count: 1),
        ),
      ]) {
        expect(
          _elements(_xml(bytes, 'meta.xml'), 'generator', _meta).single.text,
          'CrispOffice',
        );
        expect(
          _elements(
            _xml(bytes, 'styles.xml'),
            'notes-configuration',
            _text,
          ).map(
            (configuration) =>
                configuration.getAttribute('start-value', namespaceUri: _text),
          ),
          everyElement(isNull),
        );
      }
    },
  );

  test(
    'Word default Roman endnotes need no fabricated native preference',
    () async {
      final document = _native(count: 4);
      expect(document.sections.single.sourceProperties, isNull);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      expect(
        _elements(
          _xml(bytes, 'styles.xml'),
          'notes-configuration',
          _text,
        ).single.getAttribute('num-format', namespaceUri: _style),
        'i',
      );
      final restored = _docx(await OdtDocumentReader.readBytes(bytes));
      expect(restored.endnotes.map(WordNoteNumbering(restored).labelFor), [
        'i',
        'ii',
        'iii',
        'iv',
      ]);
    },
  );

  test(
    'footnote and endnote formats use independent interleaved counters',
    () async {
      final foot = _native(endnote: false, format: 'upperRoman', count: 4);
      final end = _native(count: 4);
      final document = WmlDocument(
        zoteroDocumentData: _preferences(),
        footnotes: foot.footnotes,
        endnotes: end.endnotes,
        sections: [
          WmlSection(
            sourceProperties: _options(false, '<w:numFmt w:val="upperRoman"/>'),
            blocks: [
              for (var index = 0; index < 4; index++) ...[
                foot.sections.single.blocks[index],
                end.sections.single.blocks[index],
              ],
            ],
          ),
        ],
      );
      final restored = _docx(
        await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        ),
      );
      final numbering = WordNoteNumbering(restored);
      expect(numbering.notes.map(numbering.labelFor), [
        'I',
        'i',
        'II',
        'ii',
        'III',
        'iii',
        'IV',
        'iv',
      ]);
      expect(WordZotero.fields(restored), hasLength(2));
    },
  );

  for (final format in ['i', 'I']) {
    for (final endnote in [false, true]) {
      test(
        'independent ODF $format ${endnote ? 'endnotes' : 'footnotes'} import',
        () async {
          final labels = format == 'i'
              ? _lower
              : _lower.map((value) => value.toUpperCase()).toList();
          final source = _odf(format: format, labels: labels, endnote: endnote);
          final before = Uint8List.fromList(source);
          final document = _docx(await OdtDocumentReader.readBytes(source));
          final notes = endnote ? document.endnotes : document.footnotes;
          expect(notes.map(WordNoteNumbering(document).labelFor), labels);
          expect(
            WordZotero.fields(document).single.citation!.citationId,
            'odf-note',
          );
          expect(source, before);
        },
      );
    }
  }

  test(
    'qualified LibreOffice zero offset requires exact Roman cached labels',
    () async {
      const generator =
          'LibreOfficeDev/26.8.0.0.alpha0\$Linux_X86_64 LibreOffice_project/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5';
      final source = _odf(
        generator: generator,
        extraConfiguration: 'text:start-value="0"',
      );
      final document = await OdtDocumentReader.readBytes(source);
      expect(
        document.endnotes.map(WordNoteNumbering(document).labelFor),
        _lower,
      );
      for (final label in ['', ' i', '1', 'I']) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: generator,
              labels: [label],
              extraConfiguration: 'text:start-value="0"',
            ),
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  for (final configuration in [
    '<w:numRestart w:val="eachSect"/>',
    '<w:numRestart w:val="eachPage"/>',
    '<w:numStart w:val="invalid"/>',
    '<w:numStart w:val="1"/><w:numStart w:val="1"/>',
    '<w:numFmt w:val="lowerRoman"/>',
  ]) {
    test(
      'native numbering refuses noncanonical or duplicate $configuration',
      () {
        _unchangedAfterRefusal(
          _native(
            format: 'lowerRoman',
            extraProperties: configuration,
            count: 1,
          ),
        );
      },
    );
  }

  for (final format in [
    'lowerLetter',
    'upperLetter',
    'decimalZero',
    'none',
    'bullet',
  ]) {
    test('native $format format is never inferred from a cached label', () {
      _unchangedAfterRefusal(_native(format: format, count: 1));
    });
  }

  for (final index in [0, 1]) {
    test(
      'custom mark at ${index == 0 ? 'uncited' : 'cited'} note keeps source',
      () {
        final document = _native(count: 2);
        final paragraph =
            document.sections.single.blocks[index] as WmlParagraph;
        paragraph.inlines
                .whereType<WmlRun>()
                .singleWhere((run) => run.noteRefId != null)
                .noteRefCustomMark =
            true;
        _unchangedAfterRefusal(document);
      },
    );
  }

  test(
    'uncited notes after the citation cannot change the per-class format',
    () {
      final document = _native(count: 2, citedIndex: 0);
      final second = document.sections.single.blocks.removeLast();
      document.sections.add(
        WmlSection(
          blocks: [second],
          sourceProperties: _options(true, '<w:numFmt w:val="upperRoman"/>'),
        ),
      );
      _unchangedAfterRefusal(document);
    },
  );

  test(
    'duplicate class configurations are not silently assigned first value',
    () {
      final document = _native(count: 1);
      document.sections.single.sourceProperties = WmlSectionSource(
        xml:
            '<w:sectPr xmlns:w="${OfficeNamespaces.w}"><w:endnotePr/><w:endnotePr/></w:sectPr>',
        values: const {},
      );
      _unchangedAfterRefusal(document);
    },
  );

  test('a cached Roman reference is not an automatic native reference', () {
    final document = _native(count: 1);
    document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.noteRefId != null)
            .text =
        'i';
    expect(WordNoteNumbering(document).labelFor(document.endnotes.single), 'i');
    _unchangedAfterRefusal(document);
  });

  for (final attributes in [
    'style:num-prefix="["',
    'style:num-suffix="]"',
    'style:num-letter-sync="true"',
    'text:start-value="0"',
    'text:start-value="2"',
    'text:start-numbering-at="chapter"',
    'text:start-numbering-at="page"',
  ]) {
    test('Roman ODF keeps configuration guard $attributes', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odf(labels: ['i'], extraConfiguration: attributes),
        ),
        throwsUnsupportedError,
      );
    });
  }

  for (final format in ['a', 'A', '01', '']) {
    test('ambiguous or unsupported ODF format $format refuses', () async {
      await expectLater(
        OdtDocumentReader.readBytes(_odf(format: format, labels: ['i'])),
        throwsUnsupportedError,
      );
    });
  }

  for (final labels in [
    <String>['1'],
    <String>['I'],
    <String>['ii'],
    <String>['i', 'iii'],
  ]) {
    test('Roman ODF cache mismatch ${labels.join(',')} refuses', () async {
      await expectLater(
        OdtDocumentReader.readBytes(_odf(labels: labels)),
        throwsUnsupportedError,
      );
    });
  }

  test('duplicate Roman ODF configurations refuse', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _odf(
          labels: ['i'],
          configurations:
              '<text:notes-configuration text:note-class="endnote" style:num-format="i"/><text:notes-configuration text:note-class="endnote" style:num-format="i"/>',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'generic present configuration must declare its number sequence',
    () async {
      for (final declaration in ['', ' style:num-format=""']) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              labels: ['1'],
              configurations:
                  '<text:notes-configuration text:note-class="endnote"$declaration/>',
            ),
          ),
          throwsUnsupportedError,
        );
      }
      final absent = await OdtDocumentReader.readBytes(
        _odf(labels: ['1'], configurations: ''),
      );
      expect(WordNoteNumbering(absent).labelFor(absent.endnotes.single), '1');
    },
  );

  test(
    'qualified LibreOffice absent and missing-format defaults differ',
    () async {
      const generator =
          'LibreOfficeDev/26.8.0.0.alpha0\$Linux_X86_64 LibreOffice_project/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5';
      final absent = await OdtDocumentReader.readBytes(
        _odf(generator: generator, labels: ['i'], configurations: ''),
      );
      final present = await OdtDocumentReader.readBytes(
        _odf(
          generator: generator,
          labels: ['1'],
          configurations:
              '<text:notes-configuration text:note-class="endnote"/>',
        ),
      );
      expect(
        WordNoteNumbering(
          absent,
        ).automaticNumberFor(absent.endnotes.single)?.format,
        'lowerRoman',
      );
      expect(
        WordNoteNumbering(
          present,
        ).automaticNumberFor(present.endnotes.single)?.format,
        'decimal',
      );
      for (final pair in [
        ('', '1'),
        ('<text:notes-configuration text:note-class="endnote"/>', 'i'),
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odf(
              generator: generator,
              labels: [pair.$2],
              configurations: pair.$1,
            ),
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  test(
    'native document-level numbering settings survive active ODT exchange',
    () async {
      final package = WordSerializer().write(_native(count: 2));
      final settings =
          package.getPart('/word/settings.xml') ??
          package.createPart(
            '/word/settings.xml',
            OfficeContentTypes.wordSettings,
            [],
          );
      settings.writeText(
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr><w:numFmt w:val="upperRoman"/></w:endnotePr></w:settings>',
      );
      final source = WordDeserializer().read(package);
      final before = _state(source);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(source);
      final restored = _docx(await OdtDocumentReader.readBytes(bytes));
      expect(restored.endnotes.map(WordNoteNumbering(restored).labelFor), [
        'I',
        'II',
      ]);
      expect(_state(source), before);
    },
  );

  for (final entry in <String, String>{
    'duplicate note configurations':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr/><w:endnotePr/></w:settings>',
    'invalid ordinal':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr><w:numStart w:val="broken"/></w:endnotePr></w:settings>',
    'authored configuration text':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr><w:numFmt w:val="lowerRoman">authored</w:numFmt></w:endnotePr></w:settings>',
    'unclosed root': '<w:settings xmlns:w="${OfficeNamespaces.w}">',
    'mismatched closing tag':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr></w:settings>',
    'unterminated child tag': '<w:settings xmlns:w="${OfficeNamespaces.w}"><',
    'wrong root': '<w:wrong xmlns:w="${OfficeNamespaces.w}"/>',
    'multiple roots':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"/><w:settings xmlns:w="${OfficeNamespaces.w}"/>',
    'duplicate value attributes':
        '<w:settings xmlns:w="${OfficeNamespaces.w}"><w:endnotePr><w:numFmt w:val="lowerRoman" w:val="upperRoman"/></w:endnotePr></w:settings>',
    'aliased duplicate value attributes':
        '<w:settings xmlns:w="${OfficeNamespaces.w}" xmlns:also="${OfficeNamespaces.w}"><w:endnotePr><w:numFmt w:val="lowerRoman" also:val="upperRoman"/></w:endnotePr></w:settings>',
    'wrapped format':
        '<w:settings xmlns:w="${OfficeNamespaces.w}" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><w:endnotePr><mc:AlternateContent><mc:Fallback><w:numFmt w:val="upperRoman"/></mc:Fallback></mc:AlternateContent></w:endnotePr></w:settings>',
    'wrapped note configuration':
        '<w:settings xmlns:w="${OfficeNamespaces.w}" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:AlternateContent><mc:Fallback><w:endnotePr><w:numFmt w:val="upperRoman"/></w:endnotePr></mc:Fallback></mc:AlternateContent></w:settings>',
  }.entries) {
    final settingsXml = entry.value;
    test('native ${entry.key} cannot acquire automatic metadata', () {
      final source = _docx(_native(count: 1));
      final package = source.package!;
      final settings =
          package.getPart('/word/settings.xml') ??
          package.createPart(
            '/word/settings.xml',
            OfficeContentTypes.wordSettings,
            [],
          );
      settings.writeText(settingsXml);
      final numbering = WordNoteNumbering(source);
      expect(numbering.labelFor(source.endnotes.single), 'i');
      expect(numbering.automaticNumberFor(source.endnotes.single), isNull);
      _unchangedAfterRefusal(source);
    });
  }

  test(
    'exact metadata retains ordinal identity instead of native note IDs',
    () {
      final document = _native(count: 4);
      final snapshot = WordNoteNumbering(document);
      expect(
        document.endnotes.map(
          (note) => snapshot.automaticNumberFor(note)?.number,
        ),
        [1, 2, 3, 4],
      );
      expect(document.endnotes.map((note) => note.id), [17, 24, 31, 38]);
      expect(
        document.endnotes.map(
          (note) => snapshot.automaticNumberFor(note)?.start,
        ),
        everyElement(1),
      );
      expect(
        document.endnotes.map(
          (note) => snapshot.automaticNumberFor(note)?.restart,
        ),
        everyElement('continuous'),
      );
    },
  );

  test('Roman exact labels are bounded at 3999', () {
    expect(WordNoteNumbering.formatLabel(4, 'lowerRoman'), 'iv');
    expect(WordNoteNumbering.formatLabel(9, 'upperRoman'), 'IX');
    expect(WordNoteNumbering.formatLabel(3999, 'upperRoman'), 'MMMCMXCIX');
    expect(WordNoteNumbering.formatLabel(4000, 'lowerRoman'), isNull);
    expect(WordNoteNumbering.formatLabel(0, 'lowerRoman'), isNull);
    _unchangedAfterRefusal(
      _native(
        format: 'lowerRoman',
        count: 1,
        extraProperties: '<w:numStart w:val="4000"/>',
      ),
    );
  });
}
