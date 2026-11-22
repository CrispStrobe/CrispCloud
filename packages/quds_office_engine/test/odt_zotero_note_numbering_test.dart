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
        sourceProperties: format == null && extraProperties.isEmpty
            ? null
            : _options(
                endnote,
                '${format == null ? '' : '<w:numFmt w:val="$format"/>'}'
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
      '${generator == null ? '' : '<meta:generator>${encodeXmlText(generator)}</meta:generator>'}'
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
    '<w:numStart w:val="2"/>',
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
      expect(
        WordNoteNumbering(source).automaticNumberFor(source.endnotes.single),
        isNull,
      );
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
