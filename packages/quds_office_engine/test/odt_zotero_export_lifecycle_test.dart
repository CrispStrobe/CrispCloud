import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// These are model/format acceptance tests, not installed LibreOffice or Zotero
// captures. The assertions follow field identity through independently owned
// paragraphs and subsequent edits, rather than comparing two writer outputs.
const _sessionId = 'editable-odt-lifecycle';
const _same = '(Same)';
const _biblMetadata = <String, Object?>{
  'uncited': <Object?>[],
  'omitted': <Object?>[],
  'custom': <Object?>[],
  'futureBibliography': <String, Object?>{
    'keep': <Object?>['العربية 😀', true, null, 7],
  },
};

Map<String, Object?> _citationJson(String id, {String text = _same}) => {
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
        'title': 'Über العربية 😀 & <quoted>',
        'futureItemData': {'keep': true},
      },
      'futureItem': ['preserve', 3],
    },
  ],
  'properties': {
    'plainCitation': text,
    'formattedCitation': text,
    'noteIndex': 0,
    'futureProperty': {'enabled': false},
  },
  'futureCitation': {
    'ordered': [true, null, '😀'],
  },
};

ZoteroCitation _citation(String id, {String text = _same}) =>
    ZoteroCitation.fromJson(_citationJson(id, text: text));

String _preferences({String payload = 'preserve 😀'}) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'session-unchanged',
  'style': {
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
    'futureStyle': {'localeHint': 'العربية'},
  },
  'prefs': {
    'fieldType': 'Field',
    'noteType': 0,
    'futurePreference': ['retain', false],
  },
  'futureDocument': {'payload': payload, 'nullable': null},
});

WmlParagraph _plain(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

WmlParagraph _cited(String id, String label) {
  final paragraph = _plain('$label  tail');
  WordZotero.insertCitation(paragraph, _citation(id), index: label.length + 1);
  return paragraph;
}

WmlDocument _bodyAndTable() => WmlDocument(
  zoteroDocumentData: _preferences(),
  sections: [
    WmlSection(
      blocks: [
        _cited('body', 'Body'),
        WmlTable(
          grid: [144, 144],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(width: 144, blocks: [_cited('left', 'Left')]),
                WmlTableCell(width: 144, blocks: [_cited('right', 'Right')]),
              ],
            ),
          ],
        ),
        _plain('After table'),
      ],
    ),
  ],
);

WmlZoteroField _field(WmlDocument document, String id) => WordZotero.fields(
  document,
).singleWhere((field) => field.citation?.citationId == id);

WmlZoteroField _bibliography(WmlDocument document) => WordZotero.fields(
  document,
).singleWhere((field) => field.kind == ZoteroFieldKind.bibliography);

WmlDocument _docx(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

Iterable<WmlParagraph> _allParagraphs(WmlDocument document) sync* {
  for (final section in document.sections) {
    yield* WordTree.paragraphs(section.blocks);
    yield* section.header;
    yield* section.footer;
    yield* section.firstHeader;
    yield* section.firstFooter;
    yield* section.evenHeader;
    yield* section.evenFooter;
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    yield* note.allParagraphs;
  }
}

Object _inlineState(WmlInline inline) => switch (inline) {
  WmlRun() => {
    'kind': 'run',
    'text': inline.text,
    'instruction': inline.fieldInstruction,
    'locked': inline.fieldLocked,
    'dirty': inline.fieldDirty,
    'note': inline.noteRefId,
    'endnote': inline.noteRefEndnote,
    'customMark': inline.noteRefCustomMark,
    'bold': inline.properties.bold,
    'italic': inline.properties.italic,
    'fontSize': inline.properties.fontSizeHalfPoints,
    'comments': inline.commentIds,
  },
  WmlFieldBoundary() => {
    'kind': inline.kind.name,
    'text': inline.text,
    'xml': inline.sourceXml,
    'propertiesXml': inline.runPropertiesXml,
  },
  WmlNoteMarker() => {'kind': 'noteMarker', 'endnote': inline.endnote},
  WmlOpaqueInline() => {'kind': 'opaque', 'xml': inline.content.xml},
  WmlBookmarkBoundary() => {
    'kind': 'bookmark',
    'id': inline.id,
    'start': inline.isStart,
    'name': inline.name,
    'xml': inline.sourceXml,
  },
  WmlContentControlBoundary() => {
    'kind': 'control',
    'start': inline.start,
    'xml': inline.control.xml,
  },
  WmlBreak() => {'kind': 'break', 'type': inline.type.name},
  WmlObject() => {
    'kind': 'object',
    'relationship': inline.relationshipId,
    'width': inline.width,
    'height': inline.height,
  },
};

String _snapshot(WmlDocument document) => jsonEncode({
  'preferences': document.zoteroDocumentData,
  'sourceName': document.sourceFileName,
  'paragraphs': [
    for (final paragraph in _allParagraphs(document))
      {
        'text': paragraph.text,
        'field': paragraph.properties.fieldInstruction,
        'begin': paragraph.properties.fieldBegin,
        'separate': paragraph.properties.fieldSeparate,
        'end': paragraph.properties.fieldEnd,
        'style': paragraph.properties.styleId,
        'sourceProperties': paragraph.properties.sourcePropertiesXml,
        'inlines': paragraph.inlines.map(_inlineState).toList(),
      },
  ],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      {'id': note.id, 'endnote': note.endnote, 'text': note.text},
  ],
  'preservedStories': [
    for (final section in document.sections)
      {
        for (final story in section.preservedStories.entries)
          story.key: story.value.xml,
      },
  ],
  'package': document.package == null
      ? null
      : {
          for (final part in document.package!.parts)
            // Loading an imported part is a read-cache change, not an edit.
            // Compare its actual payload, with compact failure diagnostics.
            part.uri: sha256
                .convert(document.package!.getPart(part.uri)!.readBytes())
                .toString(),
        },
});

Uint8List _exportUnchanged(WmlDocument document) {
  final before = _snapshot(document);
  final package = document.package;
  final paragraphs = _allParagraphs(document).toList();
  final inlines = [
    for (final paragraph in paragraphs) [...paragraph.inlines],
  ];
  final result = OdtDocumentWriter.writeEditableZoteroBytes(document);
  expect(_snapshot(document), before);
  expect(document.package, same(package));
  expect(_allParagraphs(document), orderedEquals(paragraphs));
  for (var i = 0; i < paragraphs.length; i++) {
    expect(paragraphs[i].inlines, orderedEquals(inlines[i]));
  }
  return result;
}

void _refusesUnchanged(WmlDocument document) {
  final before = _snapshot(document);
  final paragraphs = _allParagraphs(document).toList();
  expect(
    () => OdtDocumentWriter.writeEditableZoteroBytes(document),
    throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
  );
  expect(_snapshot(document), before);
  expect(_allParagraphs(document), orderedEquals(paragraphs));
}

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _sessionId,
      insertionParagraph: document.paragraphs.first,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_sessionId, ...args]);

List<Map<String, Object>> _wireFields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
        .cast<Map<String, Object>>();

void _complete(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.prepareReview();
  session.apply();
}

String _wireId(Map<String, Object> field) =>
    (jsonDecode(
              (field['code'] as String).substring('ITEM CSL_CITATION '.length),
            )
            as Map<String, Object?>)['citationID']
        as String;

void _expectBodyOwners(WmlDocument document) {
  final blocks = document.sections.single.blocks;
  final table = blocks.whereType<WmlTable>().single;
  expect(table.rows, hasLength(1));
  expect(table.rows.single.cells, hasLength(2));
  final owners = {
    'body': blocks.first as WmlParagraph,
    'left': table.rows.single.cells[0].blocks.single as WmlParagraph,
    'right': table.rows.single.cells[1].blocks.single as WmlParagraph,
  };
  expect(WordZotero.fields(document), hasLength(3));
  for (final entry in owners.entries) {
    final field = _field(document, entry.key);
    expect(field.paragraph, same(entry.value));
    expect(field.cachedText, _same);
    expect(field.metadata, _citationJson(entry.key));
    expect(field.canEdit, isTrue);
  }
  expect(owners['body']!.text, 'Body (Same) tail');
  expect(owners['left']!.text, 'Left (Same) tail');
  expect(owners['right']!.text, 'Right (Same) tail');
  expect((blocks.last as WmlParagraph).text, 'After table');
}

void main() {
  test(
    'equal-looking body and cell fields retain owners across ODT and DOCX',
    () async {
      var document = _bodyAndTable();
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectBodyOwners(document);
        final bytes = _exportUnchanged(document);
        final inventory = await OdfZotero.inspect(bytes);
        expect(inventory.issues, isEmpty);
        expect(inventory.fields, hasLength(3));
        expect(inventory.fields.map((field) => field.metadata!['citationID']), [
          'body',
          'left',
          'right',
        ]);
        expect(
          inventory.fields.map((field) => field.cachedText),
          List.filled(3, _same),
        );
        expect(
          inventory.fields.every((field) => field.isImportCandidate),
          isTrue,
        );
        final left = inventory.fields[1].starts.single;
        final right = inventory.fields[2].starts.single;
        expect(
          left.owners
              .singleWhere((owner) => owner.localName == 'table-cell')
              .path,
          isNot(
            right.owners
                .singleWhere((owner) => owner.localName == 'table-cell')
                .path,
          ),
        );
        document = _docx(await OdtDocumentReader.readBytes(bytes));
        _expectBodyOwners(document);
      }
      final selected = _field(document, 'right');
      final changed = ZoteroCitationItem.fromJson({
        ...selected.citation!.items.single.toJson(),
        'locator': '99',
      });
      WordZotero.updateCitation(
        selected,
        selected.citation!.withItems([changed], plainCitation: _same),
      );
      document = await OdtDocumentReader.readBytes(_exportUnchanged(document));
      expect(_field(document, 'right').citation!.items.single.locator, '99');
      expect(_field(document, 'left').citation!.items.single.locator, '12–14');
      expect(_field(document, 'body').citation!.items.single.locator, '12–14');
    },
  );

  test(
    'duplicate complete citation payloads remain separately editable',
    () async {
      final paragraph = _plain('A  B  C');
      WordZotero.insertCitation(paragraph, _citation('copied'), index: 2);
      WordZotero.insertCitation(
        paragraph,
        _citation('copied'),
        index: paragraph.text.lastIndexOf(' C'),
      );
      var document = WmlDocument(
        zoteroDocumentData: _preferences(),
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      final bytes = _exportUnchanged(document);
      final inventory = await OdfZotero.inspect(bytes);
      expect(inventory.fields, hasLength(2));
      expect(inventory.fields.map((field) => field.name).toSet(), hasLength(2));
      expect(inventory.fields[0].metadata, inventory.fields[1].metadata);
      document = _docx(await OdtDocumentReader.readBytes(bytes));
      final fields = WordZotero.fields(document);
      expect(fields, hasLength(2));
      expect(fields.map((field) => field.start), [2, 11]);
      WordZotero.updateCitation(
        fields.last,
        fields.last.citation!.withItems(
          fields.last.citation!.items,
          plainCitation: '(Only second changed)',
        ),
      );
      expect(
        document.paragraphs.single.text,
        'A (Same) B (Only second changed) C',
      );
      WordZotero.unlink(WordZotero.fields(document).first);
      document = _docx(
        await OdtDocumentReader.readBytes(_exportUnchanged(document)),
      );
      expect(WordZotero.fields(document), hasLength(1));
      expect(
        WordZotero.fields(document).single.cachedText,
        '(Only second changed)',
      );
      expect(
        document.paragraphs.single.text,
        'A (Same) B (Only second changed) C',
      );
    },
  );

  test(
    'same numeric footnote and endnote IDs never exchange field ownership',
    () async {
      final body = _cited('body', 'Body');
      final footAnchor = _plain('Footnote anchor');
      final endAnchor = _plain('Endnote anchor');
      var document = WmlDocument(
        zoteroDocumentData: _preferences(),
        sections: [
          WmlSection(
            blocks: [body, footAnchor, endAnchor],
            sourceProperties: WmlSectionSource(
              xml:
                  '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                  '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
                  '</w:sectPr>',
              values: const {},
            ),
          ),
        ],
      );
      final foot = WordNotes.insert(
        document,
        footAnchor,
        endnote: false,
        text: 'Foot ',
      );
      final end = WordNotes.insert(
        document,
        endAnchor,
        endnote: true,
        text: 'End ',
      );
      WordZotero.insertCitation(foot.paragraphs.single, _citation('foot'));
      WordZotero.insertCitation(end.paragraphs.single, _citation('end'));
      expect(foot.id, end.id);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = _exportUnchanged(document);
        final styles = XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/styles.xml')!.readText(),
        ).root!.firstChild('styles')!;
        final numberingStyles = styles.childrenNamed('notes-configuration');
        expect(
          {
            for (final configuration in numberingStyles)
              configuration.getAttribute('note-class'): configuration
                  .getAttribute('num-format'),
          },
          {'footnote': '1', 'endnote': '1'},
          reason:
              'Automatic note labels need an explicit decimal format; '
              'Writer otherwise changes the endnote label to Roman.',
        );
        final inventory = await OdfZotero.inspect(bytes);
        final stories = {
          for (final field in inventory.fields)
            field.metadata!['citationID']: field.starts.single.story,
        };
        expect(stories, {
          'body': OdfZoteroStory.body,
          'foot': OdfZoteroStory.footnote,
          'end': OdfZoteroStory.endnote,
        });
        document = _docx(await OdtDocumentReader.readBytes(bytes));
        expect(document.footnotes, hasLength(1));
        expect(document.endnotes, hasLength(1));
        final numbering = WordNoteNumbering(document);
        expect(numbering.labelFor(document.footnotes.single), '1');
        expect(numbering.labelFor(document.endnotes.single), '1');
        expect(
          _field(document, 'foot').paragraph,
          same(document.footnotes.single.paragraphs.single),
        );
        expect(
          _field(document, 'end').paragraph,
          same(document.endnotes.single.paragraphs.single),
        );
        expect(document.footnotes.single.text, contains('Foot (Same)'));
        expect(document.endnotes.single.text, contains('End (Same)'));
        final session = _session(document);
        final wire = _wireFields(session);
        expect(wire.map(_wireId), ['body', 'foot', 'end']);
        expect(wire.map((field) => field['noteIndex']), [0, 1, 1]);
        session.assertUnchanged();
      }
      WordZotero.unlink(_field(document, 'foot'));
      document = _docx(
        await OdtDocumentReader.readBytes(_exportUnchanged(document)),
      );
      expect(
        WordZotero.fields(document).map((field) => field.citation!.citationId),
        unorderedEquals(['body', 'end']),
      );
      expect(document.footnotes.single.text, contains('Foot (Same)'));
      expect(_field(document, 'end').cachedText, _same);
    },
  );

  for (final uppercase in [false, true]) {
    test(
      'Roman endnote lifecycle preserves ownership, uppercase=$uppercase',
      () async {
        final document = WmlDocument.empty(text: 'Body');
        document.zoteroDocumentData = _preferences();
        if (uppercase) {
          document.sections.single.sourceProperties = WmlSectionSource(
            xml:
                '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:endnotePr><w:numFmt w:val="upperRoman"/></w:endnotePr>'
                '</w:sectPr>',
            values: const {},
          );
        }
        WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: true,
          text: 'Uncited',
        );
        final cited = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: true,
          text: 'Cited ',
        );
        WordZotero.insertCitation(cited.paragraphs.single, _citation('roman'));
        var current = document;
        for (var cycle = 0; cycle < 2; cycle++) {
          final bytes = _exportUnchanged(current);
          final styles = XmlDocument.parse(
            OpcPackage.openBytes(bytes).getPart('/styles.xml')!.readText(),
          ).root!.firstChild('styles')!;
          final configuration = styles
              .childrenNamed('notes-configuration')
              .singleWhere(
                (item) => item.getAttribute('note-class') == 'endnote',
              );
          expect(
            configuration.getAttribute('num-format'),
            uppercase ? 'I' : 'i',
          );
          current = _docx(await OdtDocumentReader.readBytes(bytes));
          final numbering = WordNoteNumbering(current);
          expect(
            current.endnotes.map(numbering.labelFor),
            uppercase ? ['I', 'II'] : ['i', 'ii'],
          );
          expect(
            _field(current, 'roman').paragraph,
            same(current.endnotes[1].paragraphs.single),
          );
          expect(_field(current, 'roman').cachedText, _same);
          expect(WordZotero.fields(current), hasLength(1));
        }
      },
    );
  }

  test('a fixed earlier note cannot silently renumber a later cited note', () {
    final firstAnchor = _plain('Roman endnote');
    final secondAnchor = _plain('Decimal endnote');
    final document = WmlDocument(
      zoteroDocumentData: _preferences(),
      sections: [
        WmlSection(blocks: [firstAnchor]),
        WmlSection(
          blocks: [secondAnchor],
          sourceProperties: WmlSectionSource(
            xml:
                '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
                '</w:sectPr>',
            values: const {},
          ),
        ),
      ],
    );
    WordNotes.insert(document, firstAnchor, endnote: true, text: 'Uncited');
    final cited = WordNotes.insert(
      document,
      secondAnchor,
      endnote: true,
      text: 'Cited ',
    );
    WordZotero.insertCitation(cited.paragraphs.single, _citation('mixed'));
    final numbering = WordNoteNumbering(document);
    expect(document.endnotes.map(numbering.labelFor), ['i', '2']);
    _refusesUnchanged(document);
  });

  test(
    'native bibliography remains refreshable and unlinkable after export',
    () async {
      final first = _cited('source', 'Body');
      final entries = WordZotero.nativeBibliographyParagraphs(
        instruction:
            ' ADDIN ZOTERO_BIBL ${jsonEncode(_biblMetadata)} '
            'CSL_BIBLIOGRAPHY ',
        text: 'Alpha Book.\nBeta Book.',
        formattedText: ZoteroFormattedText.fromHtml(
          '<div class="csl-entry">Alpha <i>Book</i>.</div>'
          '<div class="csl-entry">Beta <b>Book</b>.</div>',
        ),
        paragraphProperties: WmlParagraphProps(),
      );
      var document = WmlDocument(
        zoteroDocumentData: _preferences(),
        sections: [
          WmlSection(
            blocks: [
              first,
              _plain('Before references'),
              ...entries,
              _plain('After references'),
            ],
          ),
        ],
      );
      final initialBytes = _exportUnchanged(document);
      final inventory = await OdfZotero.inspect(initialBytes);
      final nativeBibliography = inventory.fields.singleWhere(
        (field) => field.kind == ZoteroFieldKind.bibliography,
      );
      expect(nativeBibliography.storage, OdfZoteroStorage.section);
      expect(nativeBibliography.cachedText, 'Alpha Book.\nBeta Book.');
      expect(nativeBibliography.metadata, _biblMetadata);
      document = _docx(await OdtDocumentReader.readBytes(initialBytes));
      expect(_bibliography(document).paragraphs, hasLength(2));
      expect(
        WordZotero.canReplaceNativeBibliography(
          document,
          _bibliography(document),
        ),
        isTrue,
      );

      final before = _snapshot(document);
      final session = _session(document);
      final wire = _wireFields(session);
      final citation = wire.singleWhere(
        (field) => (field['code'] as String).startsWith('ITEM '),
      );
      final bib = wire.singleWhere(
        (field) => (field['code'] as String).startsWith('BIBL '),
      );
      final updated = _field(document, 'source').citation!.withItems(
        _field(document, 'source').citation!.items,
        plainCitation: '(Refreshed)',
        formattedCitation: '<i>(Refreshed)</i>',
      );
      _call(session, 'Field.setCode', [
        citation['id'],
        'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
      ]);
      _call(session, 'Field.setText', [
        citation['id'],
        '<i>(Refreshed)</i>',
        true,
      ]);
      _call(session, 'Field.setText', [
        bib['id'],
        '<div class="csl-entry">Gamma <i>Book</i>.</div>'
            '<div class="csl-entry">Delta.</div><div class="csl-entry">Epsilon.</div>',
        true,
      ]);
      expect(_snapshot(document), before);
      _complete(session);
      expect(_bibliography(document).paragraphs, hasLength(3));
      expect(
        _bibliography(document).cachedText,
        'Gamma Book.\nDelta.\nEpsilon.',
      );
      expect(_field(document, 'source').cachedText, '(Refreshed)');
      document = _docx(
        await OdtDocumentReader.readBytes(_exportUnchanged(document)),
      );
      expect(_bibliography(document).paragraphs, hasLength(3));
      expect(_bibliography(document).metadata, _biblMetadata);
      expect(
        _bibliography(document).paragraphs.first.inlines
            .whereType<WmlRun>()
            .where((run) => run.properties.italic)
            .map((run) => run.text)
            .join()
            .trim(),
        'Book',
      );
      expect(document.paragraphs.map((p) => p.text), [
        'Body (Refreshed) tail',
        'Before references',
        'Gamma Book.',
        'Delta.',
        'Epsilon.',
        'After references',
      ]);

      final unlinkedText = document.paragraphs.map((p) => p.text).toList();
      final unlink = _session(document);
      for (final field in _wireFields(unlink)) {
        _call(unlink, 'Field.removeCode', [field['id']]);
      }
      _complete(unlink);
      expect(WordZotero.fields(document), isEmpty);
      expect(document.paragraphs.map((p) => p.text), unlinkedText);
      final finalBytes = _exportUnchanged(document);
      expect((await OdfZotero.inspect(finalBytes)).fields, isEmpty);
      document = _docx(await OdtDocumentReader.readBytes(finalBytes));
      expect(WordZotero.fields(document), isEmpty);
      expect(document.paragraphs.map((p) => p.text), unlinkedText);
    },
  );

  for (final xml in [false, true]) {
    test(
      'long ${xml ? 'XML' : 'JSON'} preferences preserve Unicode and extensions',
      () async {
        final payload = '${'x' * 239}😀 العربية & <future> ${'ß😀' * 350}';
        final preferences = xml
            ? '<data data-version="3" future="keep"><session id="unchanged"/>'
                  '<style id="http://www.zotero.org/styles/apa" locale="de-DE"/>'
                  '<prefs><pref name="fieldType" value="Field"/>'
                  '<pref name="noteType" value="0"/>'
                  '<pref name="future" value="yes"/></prefs>'
                  '<extra xmlns="urn:quds:future" keep="true">'
                  '${encodeXmlText(payload)}</extra></data>'
            : _preferences(payload: payload);
        var document = WmlDocument(
          zoteroDocumentData: preferences,
          sections: [
            WmlSection(blocks: [_cited('unicode', 'Unicode')]),
          ],
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = _exportUnchanged(document);
          final inventory = await OdfZotero.inspect(bytes);
          final data = inventory.preferences;
          expect(data.issues, isEmpty);
          expect(data.fieldType, 'ReferenceMark');
          expect(data.chunks.length, greaterThan(5));
          for (final chunk in data.chunks) {
            expect(chunk.value!.length, lessThanOrEqualTo(255));
            expect(utf8.decode(utf8.encode(chunk.value!)), chunk.value);
          }
          if (xml) {
            final root = XmlDocument.parse(data.rawData!).root!;
            expect(root.getAttribute('future'), 'keep');
            expect(
              root.firstChild('extra', namespaceUri: 'urn:quds:future')!.text,
              payload,
            );
          } else {
            final odfData = jsonDecode(data.rawData!) as Map<String, Object?>;
            final expected = jsonDecode(preferences) as Map<String, Object?>;
            (expected['prefs'] as Map<String, Object?>)['fieldType'] =
                'ReferenceMark';
            expect(odfData, expected);
          }
          document = _docx(await OdtDocumentReader.readBytes(bytes));
          final nativeData = WordZoteroDocumentData.read(document);
          if (xml) {
            final root = XmlDocument.parse(nativeData).root!;
            expect(
              root.firstChild('extra', namespaceUri: 'urn:quds:future')!.text,
              payload,
            );
            expect(
              root
                  .firstChild('prefs')!
                  .childrenNamed('pref')
                  .singleWhere(
                    (pref) => pref.getAttribute('name') == 'fieldType',
                  )
                  .getAttribute('value'),
              'Field',
            );
          } else {
            expect(jsonDecode(nativeData), jsonDecode(preferences));
          }
          expect(
            _field(document, 'unicode').metadata,
            _citationJson('unicode'),
          );
        }
      },
    );
  }

  for (final location in [
    'header',
    'hidden-first-header',
    'preserved-header',
    'orphan-footnote',
    'note-table',
    'duplicate-note-anchor',
    'alphabetic-endnote',
  ]) {
    test('refuses $location citations without changing the source', () {
      final paragraph = _cited('unsupported', 'Keep');
      final document = WmlDocument.empty(text: 'Body');
      document.zoteroDocumentData = _preferences();
      switch (location) {
        case 'header':
          document.sections.single.header.add(paragraph);
        case 'hidden-first-header':
          document.sections.single.firstHeader.add(paragraph);
          expect(document.sections.single.differentFirstPage, isFalse);
        case 'preserved-header':
          document.sections.single.preservedStories['header'] = WmlOpaqueBlock(
            xml:
                '<w:hdr xmlns:w="${OfficeNamespaces.w}"><w:p>'
                '<w:fldSimple w:instr="${encodeXmlAttribute(_citation('hidden').fieldInstruction)}">'
                '<w:r><w:t>Hidden citation</w:t></w:r>'
                '</w:fldSimple></w:p></w:hdr>',
            sourcePartUri: '/word/header1.xml',
            relationships: const [],
          );
          expect(WordZotero.fields(document), isEmpty);
        case 'orphan-footnote':
          document.footnotes.add(
            WmlNote(id: 9, endnote: false, paragraphs: [paragraph]),
          );
        case 'note-table':
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: false,
            text: 'Note',
          );
          note.blocks.add(
            WmlTable(
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [paragraph]),
                  ],
                ),
              ],
            ),
          );
        case 'duplicate-note-anchor':
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: false,
            text: 'Note',
          );
          WordZotero.insertCitation(note.paragraphs.single, _citation('note'));
          document.paragraphs.single.inlines.add(
            WmlRun(text: '1', noteRefId: note.id),
          );
        case 'alphabetic-endnote':
          document.sections.single.sourceProperties = WmlSectionSource(
            xml:
                '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                '<w:endnotePr><w:numFmt w:val="lowerLetter"/></w:endnotePr>'
                '</w:sectPr>',
            values: const {},
          );
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: true,
          );
          WordZotero.insertCitation(
            note.paragraphs.single,
            _citation('alphabetic'),
          );
      }
      _refusesUnchanged(document);
    });
  }

  for (final invalid in ['locked', 'incomplete', 'invalid-json', 'opaque']) {
    test('refuses $invalid native packets without editing or unlinking them', () {
      final citation = _citation('guarded');
      final instruction = encodeXmlAttribute(citation.fieldInstruction);
      final field = switch (invalid) {
        'locked' =>
          '<w:fldSimple w:instr="$instruction" w:fldLock="true">'
              '<w:r><w:t>(Same)</w:t></w:r></w:fldSimple>',
        'incomplete' =>
          '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
              '<w:r><w:instrText>${encodeXmlText(citation.fieldInstruction)}'
              '</w:instrText></w:r>'
              '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
              '<w:r><w:t>(Same)</w:t></w:r>',
        'invalid-json' =>
          '<w:fldSimple w:instr="ADDIN ZOTERO_ITEM '
              'CSL_CITATION {broken}"><w:r><w:t>Keep</w:t></w:r></w:fldSimple>',
        _ =>
          '<w:fldSimple w:instr="$instruction" future:keep="yes">'
              '<w:r><w:t>(Same)</w:t></w:r></w:fldSimple>',
      };
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:future="urn:future">'
            '<w:body><w:p><w:r><w:t>Before </w:t></w:r>$field'
            '<w:r><w:t> after</w:t></w:r></w:p></w:body></w:document>',
          );
      final document = WordDeserializer().read(package)
        ..zoteroDocumentData = _preferences();
      _refusesUnchanged(document);
    });
  }

  test(
    'refuses a partially owned bibliography without flattening its neighbors',
    () {
      final bibliography = WordZotero.nativeBibliographyParagraphs(
        instruction:
            ' ADDIN ZOTERO_BIBL ${jsonEncode(_biblMetadata)} '
            'CSL_BIBLIOGRAPHY ',
        text: 'First.\nSecond.',
      );
      bibliography.first.inlines.insert(0, WmlRun(text: 'Authored prefix '));
      final document = WmlDocument(
        zoteroDocumentData: _preferences(),
        sections: [WmlSection(blocks: bibliography)],
      );
      expect(
        WordZotero.canReplaceNativeBibliography(
          document,
          _bibliography(document),
        ),
        isFalse,
      );
      _refusesUnchanged(document);
    },
  );
}
