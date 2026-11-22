import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

ZoteroCitation _citation(String id, [String text = '(Same)']) =>
    ZoteroCitation.fromJson({
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
          'itemData': {'id': 1, 'type': 'book', 'title': 'العربية 😀 & <Book>'},
          'futureItem': {'preserve': true},
        },
      ],
      'properties': {'plainCitation': text, 'noteIndex': 0},
      'futureRoot': [true, null, 42],
    });

String _data({String extra = ''}) => jsonEncode({
  'dataVersion': 4,
  'style': {
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'bibliographyStyleHasBeenSet': true,
  },
  'prefs': {'fieldType': 'Field', 'noteType': 0},
  'future': {'retain': extra},
});

WmlDocument _document(List<WmlBlock> blocks, {String? data}) => WmlDocument(
  sections: [WmlSection(blocks: blocks)],
  zoteroDocumentData: data ?? _data(),
);

WmlParagraph _simple(String id, [String text = '(Same)']) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Before '),
    WmlRun(text: text, fieldInstruction: _citation(id, text).fieldInstruction),
    WmlRun(text: ' after'),
  ],
);

List<WmlInline> _complex(String id, String text) {
  final code = _citation(id, text).fieldInstruction;
  return [
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
    WmlFieldBoundary(
      kind: WmlFieldBoundaryKind.instruction,
      text: code.substring(0, 12),
    ),
    WmlFieldBoundary(
      kind: WmlFieldBoundaryKind.instruction,
      text: code.substring(12),
    ),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
    WmlRun(text: text, properties: WmlRunProps(italic: true)),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
  ];
}

List<XmlElement> _elements(XmlElement root, String name) => [
  if (root.namespaceUri == _text && root.localName == name) root,
  for (final child in root.childElements) ..._elements(child, name),
];

void main() {
  test(
    'explicit export preserves native field codes, identities and rich caches',
    () async {
      final simple = _simple('simple', 'عربي 😀');
      final complex = WmlParagraph(
        inlines: [
          WmlRun(text: 'prefix '),
          ..._complex('complex-one', '(Same)'),
          ..._complex('complex-two', '(Same)'),
          WmlRun(text: ' suffix'),
        ],
      );
      final whole = WmlParagraph(
        properties: WmlParagraphProps(
          fieldInstruction: _citation('whole', 'Whole').fieldInstruction,
        ),
        inlines: [WmlRun(text: 'Whole', properties: WmlRunProps(bold: true))],
      );
      final empty = _simple('empty', '');
      final document = _document([simple, complex, whole, empty]);
      final sourceInlines = List<WmlInline>.of(complex.inlines);
      final sourceFields = WordZotero.fields(
        document,
      ).map((f) => f.instruction).toList();
      final sourceData = document.zoteroDocumentData;
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      final inventory = await OdfZotero.inspect(bytes);
      expect(inventory.fields, hasLength(5));
      expect(inventory.fields.every((f) => f.isImportCandidate), isTrue);
      expect(inventory.preferences.usesReferenceMarks, isTrue);
      expect(inventory.fields.map((f) => f.cachedText), [
        'عربي 😀',
        '(Same)',
        '(Same)',
        'Whole',
        '',
      ]);
      expect(inventory.fields.map((f) => f.metadata!['citationID']), [
        'simple',
        'complex-one',
        'complex-two',
        'whole',
        'empty',
      ]);
      expect(inventory.fields.map((f) => f.name).toSet(), hasLength(5));
      for (final field in inventory.fields) {
        expect(
          field.name,
          matches(r'^ZOTERO_ITEM CSL_CITATION .* RND[A-Za-z0-9]{10}$'),
        );
        expect(field.metadata!['futureRoot'], [true, null, 42]);
      }
      final reopened = await OdtDocumentReader.readBytes(bytes);
      expect(
        reopened.paragraphs.map((p) => p.text),
        document.paragraphs.map((p) => p.text),
      );
      expect(
        WordZotero.fields(reopened).map((f) => f.citation!.toJson()),
        WordZotero.fields(document).map((f) => f.citation!.toJson()),
      );
      expect(
        reopened.paragraphs
            .elementAt(1)
            .inlines
            .whereType<WmlRun>()
            .where((r) => r.text == '(Same)')
            .every((r) => r.properties.italic),
        isTrue,
      );
      final docx = WordDeserializer().readBytes(
        WordSerializer().writeBytes(reopened),
      );
      expect(WordZotero.fields(docx), hasLength(5));
      expect(complex.inlines, orderedEquals(sourceInlines));
      expect(
        WordZotero.fields(document).map((f) => f.instruction),
        sourceFields,
      );
      expect(document.zoteroDocumentData, sourceData);
      expect(document.package, isNull);
    },
  );

  test(
    'bibliography is one native section with empty and rich entry paragraphs',
    () async {
      final metadata = {
        'uncited': [
          ['http://zotero.org/users/42/items/EFGH5678'],
        ],
        'omitted': <Object?>[],
        'custom': <Object?>[],
        'futureBibliography': {'retain': true},
      };
      final paragraphs = WordZotero.nativeBibliographyParagraphs(
        instruction:
            ' ADDIN ZOTERO_BIBL ${jsonEncode(metadata)} CSL_BIBLIOGRAPHY ',
        text: 'First entry\n\nThird entry',
        paragraphProperties: WmlParagraphProps(
          indent: WmlIndent(left: 36, hanging: 36),
          spacingAfter: 6,
          lineSpacing: 1.5,
        ),
      );
      final firstRun = paragraphs.first.inlines.whereType<WmlRun>().first;
      firstRun.properties.italic = true;
      final document = _document([
        _simple('body'),
        ...paragraphs,
        WmlParagraph(inlines: [WmlRun(text: 'Tail')]),
      ]);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      final package = OpcPackage.openBytes(bytes);
      final root = XmlDocument.parse(
        package.getPart('/content.xml')!.readText(),
      ).root!;
      final sections = _elements(root, 'section');
      expect(sections, hasLength(1));
      expect(
        sections.single.getAttribute('name'),
        matches(r'^ZOTERO_BIBL .* CSL_BIBLIOGRAPHY RND[A-Za-z0-9]{10}$'),
      );
      expect(sections.single.childElements.map((p) => p.localName), [
        'p',
        'p',
        'p',
      ]);
      final inventory = await OdfZotero.inspect(bytes);
      final bibliography = inventory.fields.singleWhere(
        (f) => f.kind == ZoteroFieldKind.bibliography,
      );
      expect(bibliography.storage, OdfZoteroStorage.section);
      expect(bibliography.isImportCandidate, isTrue);
      expect(bibliography.metadata, metadata);
      final restored = await OdtDocumentReader.readBytes(bytes);
      final native = WordZotero.fields(
        restored,
      ).singleWhere((f) => f.kind == ZoteroFieldKind.bibliography);
      expect(native.paragraphs, hasLength(3));
      expect(native.cachedText, 'First entry\n\nThird entry');
      expect(WordZotero.canReplaceNativeBibliography(restored, native), isTrue);
      expect(native.paragraphs.first.properties.indent.left, 36);
      expect(native.paragraphs.first.properties.indent.hanging, 36);
      expect(native.paragraphs.first.properties.spacingAfter, 6);
    },
  );

  test(
    'preference chunks preserve XML, supplementary Unicode and unknown data',
    () async {
      for (final data in [
        _data(extra: '${'x' * 400}😀&<>${'y' * 400}'),
        '<data data-version="4" future="retained"><style id="http://www.zotero.org/styles/apa" locale="ar"/><prefs><pref name="fieldType" value="Field"/><pref name="noteType" value="0"/><pref name="future" value="${'a' * 230}😀&amp;${'b' * 300}"/></prefs><future keep="yes"/></data>',
      ]) {
        final document = _document([_simple('unicode')], data: data);
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
        final inventory = await OdfZotero.inspect(bytes);
        expect(inventory.preferences.isValid, isTrue);
        expect(inventory.preferences.usesReferenceMarks, isTrue);
        expect(
          inventory.preferences.properties
              .where((p) => p.family != null)
              .length,
          greaterThan(1),
        );
        for (final property in inventory.preferences.properties.where(
          (p) => p.family != null,
        )) {
          expect(property.value!.length, lessThanOrEqualTo(255));
          expect(utf8.decode(utf8.encode(property.value!)), property.value);
        }
        expect(
          WordZoteroDocumentData.fromOdt(inventory.preferences.rawData!),
          WordZoteroDocumentData.toNative(data),
        );
        expect(document.zoteroDocumentData, data);
      }
      expect(
        () => WordZoteroDocumentData.toNative(
          '{"prefs":{"fieldType":"ReferenceMark"}}',
        ),
        throwsFormatException,
      );
      expect(
        () =>
            WordZoteroDocumentData.toOdt('{"prefs":{"fieldType":"Bookmark"}}'),
        throwsFormatException,
      );
    },
  );

  test(
    'ordinary export remains cached-only and editable exports use fresh names',
    () async {
      final document = _document([_simple('same')]);
      final cached = await OdfZotero.inspect(
        OdtDocumentWriter.writeBytes(document),
      );
      expect(cached.fields, isEmpty);
      expect(cached.preferences.isPresent, isFalse);
      final first = await OdfZotero.inspect(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      final second = await OdfZotero.inspect(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      expect(first.fields.single.name, isNot(second.fields.single.name));
      expect(first.fields.single.metadata, second.fields.single.metadata);
    },
  );

  test(
    'invalid, locked, incomplete and unknown fields refuse without mutation',
    () {
      final malformed = _simple('invalid');
      (malformed.inlines[1] as WmlRun).fieldInstruction =
          ' ADDIN ZOTERO_ITEM CSL_CITATION {broken}';
      final locked = _simple('locked');
      (locked.inlines[1] as WmlRun).fieldLocked = true;
      final unknown = _simple('unknown');
      (unknown.inlines[1] as WmlRun).fieldInstruction =
          ' ADDIN ZOTERO_UNKNOWN {"retain":true}';
      final incomplete = WmlParagraph(
        inlines: _complex('incomplete', '(Same)')..removeLast(),
      );
      for (final paragraph in [malformed, locked, unknown, incomplete]) {
        final document = _document([paragraph]);
        final original = List<WmlInline>.of(paragraph.inlines);
        expect(
          () => OdtDocumentWriter.writeEditableZoteroBytes(document),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines, orderedEquals(original));
      }
      final noData = _document([_simple('missing')], data: '');
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(noData),
        throwsFormatException,
      );
    },
  );

  test(
    'headers, content controls, hidden cells and orphan notes refuse active data',
    () {
      final header = _document([WmlParagraph()]);
      header.sections.single.header.add(_simple('header'));
      final orphan = _document([WmlParagraph()]);
      orphan.footnotes.add(
        WmlNote(id: 1, endnote: false, blocks: [_simple('orphan')]),
      );
      final control = _document([
        WmlContentControlBlock(
          control: WmlContentControlData(
            xml: '<w:sdt/>',
            sourcePartUri: '/word/document.xml',
            relationships: [],
          ),
          blocks: [_simple('control')],
        ),
      ]);
      final hidden = _document([
        WmlTable(
          grid: [120],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  vMerge: WmlVMerge.restart,
                  blocks: [WmlParagraph()],
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  vMerge: WmlVMerge.cont,
                  blocks: [_simple('hidden')],
                ),
              ],
            ),
          ],
        ),
      ]);
      for (final document in [header, orphan, control, hidden]) {
        expect(
          () => OdtDocumentWriter.writeEditableZoteroBytes(document),
          throwsUnsupportedError,
        );
      }
    },
  );

  test('opaque entity-encoded Zotero data and repeated owners refuse', () {
    final opaque = _document([
      WmlOpaqueBlock(
        xml: '<w:p><w:instrText>CSL_&#67;ITATION {}</w:instrText></w:p>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
      ),
    ]);
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(opaque),
      throwsUnsupportedError,
    );
    final paragraph = _simple('aliased');
    final repeated = _document([paragraph, paragraph]);
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(repeated),
      throwsUnsupportedError,
    );
  });

  test(
    'retained native note definitions and bookmark storage are not flattened',
    () {
      final document = _document([_simple('body')]);
      final package = OpcPackage.create(OpcPackageKind.word);
      package.createPart(
        '/word/footnotes.xml',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml',
        utf8.encode(
          '<w:footnotes xmlns:w="${OfficeNamespaces.w}"><w:footnote w:id="-1" w:type="separator"><w:p><w:r><w:instrText>CSL_CITATION {"preserve":true}</w:instrText></w:r></w:p></w:footnote></w:footnotes>',
        ),
      );
      document.package = package;
      final original = package.getPart('/word/footnotes.xml')!.readText();
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsUnsupportedError,
      );
      expect(package.getPart('/word/footnotes.xml')!.readText(), original);
      final bookmark = _document([
        WmlParagraph(
          inlines: [
            WmlBookmarkBoundary(
              id: '1',
              isStart: true,
              name: 'ZOTERO_BREF_abc',
            ),
            WmlRun(text: 'Stored citation'),
            WmlBookmarkBoundary(id: '1', isStart: false),
          ],
        ),
      ]);
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(bookmark),
        throwsUnsupportedError,
      );
    },
  );

  test('opaque nesting is bounded before recursive allocation', () {
    final document = _document([
      WmlOpaqueBlock(
        xml: '${'<node>' * 130}ordinary${'</node>' * 130}',
        sourcePartUri: '/word/document.xml',
        relationships: [],
      ),
    ]);
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(document),
      throwsFormatException,
    );
  });

  test(
    'combined span-three table emits exact covered positions and reopens',
    () async {
      var document = _document([
        WmlTable(
          grid: [90, 120, 150],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  gridSpan: 3,
                  vMerge: WmlVMerge.restart,
                  blocks: [_simple('origin')],
                  fillColor: 'FFEEDD',
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  gridSpan: 3,
                  vMerge: WmlVMerge.cont,
                  blocks: [WmlParagraph()],
                  fillColor: 'FFEEDD',
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [_simple('lower')]),
                WmlTableCell(blocks: [WmlParagraph()]),
                WmlTableCell(blocks: [WmlParagraph()]),
              ],
            ),
          ],
        ),
      ]);
      for (var cycle = 0; cycle < 2; cycle++) {
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
        final content = OpcPackage.openBytes(
          bytes,
        ).getPart('/content.xml')!.readText();
        expect(content, contains('style:width="360.00pt"'));
        expect(content, isNot(contains('table:number-columns-repeated')));
        final inventory = await OdfZotero.inspect(bytes);
        expect(inventory.fields.every((f) => f.isImportCandidate), isTrue);
        document = await OdtDocumentReader.readBytes(bytes);
        final table = document.sections.single.blocks.single as WmlTable;
        expect(table.rows[0].cells.single.gridSpan, 3);
        expect(table.rows[0].cells.single.vMerge, WmlVMerge.restart);
        expect(table.rows[1].cells.single.vMerge, WmlVMerge.cont);
        expect(WordZotero.fields(document).map((f) => f.citation!.citationId), [
          'origin',
          'lower',
        ]);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test(
    'editable cache styles retain small caps and complex-script fonts',
    () async {
      final paragraph = _simple('styled', 'Latin العربية');
      final run = paragraph.inlines[1] as WmlRun;
      run.properties
        ..smallCaps = true
        ..csFont = 'Amiri';
      final document = _document([paragraph]);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      final content = OpcPackage.openBytes(
        bytes,
      ).getPart('/content.xml')!.readText();
      expect(content, contains('fo:font-variant="small-caps"'));
      expect(content, contains('style:font-family-complex="Amiri"'));
      final imported = await OdtDocumentReader.readBytes(bytes);
      final field = WordZotero.fields(imported).single;
      expect(field.cachedText, 'Latin العربية');
      expect(
        imported.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.text.contains('العربية'))
            .single
            .properties
            .csFont,
        'Amiri',
      );
      expect(
        imported.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.text.contains('Latin'))
            .single
            .properties
            .smallCaps,
        isTrue,
      );

      // Full uppercase stays display formatting through native ODT import;
      // citation metadata and authored text keep their original casing.
      run.properties
        ..smallCaps = false
        ..allCaps = true;
      final caps = OdtDocumentWriter.writeEditableZoteroBytes(document);
      expect(
        OpcPackage.openBytes(caps).getPart('/content.xml')!.readText(),
        contains('fo:text-transform="uppercase"'),
      );
      expect(
        (await OdfZotero.inspect(caps)).fields.single.cachedText,
        'Latin العربية',
      );
      final capsImported = await OdtDocumentReader.readBytes(caps);
      expect(
        WordZotero.fields(capsImported).single.cachedText,
        'Latin العربية',
      );
      expect(
        capsImported.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.text.contains('Latin'))
            .single
            .properties
            .allCaps,
        isTrue,
      );
      expect(run.text, 'Latin العربية');
    },
  );
}
