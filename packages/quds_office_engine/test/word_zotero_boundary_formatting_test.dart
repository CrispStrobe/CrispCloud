import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/zotero_converter_fixtures.dart';

const _documentId = 'converted-field-formatting';
const _fixtureRoot = 'test/fixtures/zotero/converter';
const _properties =
    '<w:rPr xmlns:w="${OfficeNamespaces.w}">'
    '<w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
    '<w:b w:val="false"/><w:b w:val="false"/>'
    '<w:i w:val="false"/><w:caps w:val="false"/>'
    '<w:smallCaps w:val="false"/><w:color w:val="000000"/>'
    '<w:kern w:val="2"/><w:sz w:val="22"/><w:rtl w:val="true"/>'
    '</w:rPr>';

ZoteroCitation _citation([String text = '(Original)']) => ZoteroCitation(
  citationId: 'formatted-boundary',
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'A retained source'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12–14',
      label: 'page',
    ),
  ],
);

WmlDocument _synthetic({String properties = _properties, String? instruction}) {
  final code = instruction ?? _citation().fieldInstruction;
  return WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Before '),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: code.substring(0, 10),
                runPropertiesXml: properties,
              ),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: code.substring(10),
                runPropertiesXml: properties,
              ),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.separate,
                runPropertiesXml: properties,
              ),
              WmlRun(text: '(Original)', properties: WmlRunProps(italic: true)),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.end,
                runPropertiesXml: properties,
              ),
              WmlRun(text: ' After', properties: WmlRunProps(bold: true)),
            ],
          ),
        ],
      ),
    ],
  );
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlDocument _converted(String story, int cycle) => WordDeserializer().readBytes(
  File('$_fixtureRoot/docx-cycle-$cycle/$story.docx').readAsBytesSync(),
);

WmlDocument _emptyCodeRevision() {
  final package = WordSerializer().write(_synthetic());
  final part = package.getPart('/word/document.xml')!;
  part.writeText(
    part.readText().replaceFirst(
      '</w:instrText></w:r>',
      '</w:instrText></w:r><w:r><w:rPr><w:b/>'
          '<w:rPrChange w:id="17" w:author="Reviewer">'
          '<w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr></w:r>',
    ),
  );
  return WordDeserializer().read(package);
}

List<WmlParagraph> _paragraphs(WmlDocument document) => [
  ...document.paragraphs,
  for (final note in [...document.footnotes, ...document.endnotes])
    ...note.allParagraphs,
];

List<String?> _boundaryProperties(WmlDocument document) => [
  for (final paragraph in _paragraphs(document))
    for (final boundary in paragraph.inlines.whereType<WmlFieldBoundary>())
      _propertyFingerprint(boundary.runPropertiesXml),
];

List<WmlRun> _codeRuns(WmlDocument document) => [
  for (final field in WordZotero.fields(document))
    ...field.paragraph.inlines
        .skipWhile((inline) => inline is! WmlFieldBoundary)
        .takeWhile(
          (inline) =>
              inline is! WmlFieldBoundary ||
              inline.kind != WmlFieldBoundaryKind.separate,
        )
        .whereType<WmlRun>(),
];

List<String?> _codeProperties(WmlDocument document) => [
  for (final run in _codeRuns(document))
    _propertyFingerprint(run.properties.sourcePropertiesXml),
];

String? _propertyFingerprint(String? xml) {
  if (xml == null || xml.isEmpty) return null;
  final root = XmlDocument.parse(xml).root!;
  void removeDeclarations(XmlElement element) {
    element.attributes.removeWhere(
      (attribute) =>
          attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns',
    );
    for (final child in element.childElements) {
      removeDeclarations(child);
    }
  }

  removeDeclarations(root);
  return XmlDocument(root: root).toXmlString(declaration: false);
}

String _snapshot(WmlDocument document) => jsonEncode({
  'text': [for (final paragraph in _paragraphs(document)) paragraph.text],
  'preferences': WordZoteroDocumentData.read(document),
  'code-run-properties': _codeProperties(document),
  'fields': [
    for (final field in WordZotero.fields(document))
      {
        'instruction': field.instruction,
        'cache': field.cachedText,
        'editable': field.canEdit,
        'start': field.start,
        'end': field.end,
      },
  ],
  'boundaries': [
    for (final paragraph in _paragraphs(document))
      for (final boundary in paragraph.inlines.whereType<WmlFieldBoundary>())
        {
          'kind': boundary.kind.name,
          'text': boundary.text,
          'source': boundary.sourceXml,
          'properties': boundary.runPropertiesXml,
        },
  ],
});

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _documentId,
      insertionParagraph: document.paragraphs.first,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
        .cast<Map<String, Object>>();

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

void _assertFields(WmlDocument document) {
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  for (final field in WordZotero.fields(document)) {
    expect(field.isValid, isTrue);
    expect(field.canEdit, isTrue);
    expect(field.opaqueMetadata, isFalse);
    expect(field.run, isNull, reason: 'Formatted boundaries stay explicit.');
  }
}

void main() {
  _emptyCodeFormattingTests();
  test('a split Zotero instruction is recognized after a reference field', () {
    final code = _citation().fieldInstruction;
    final document = _synthetic(properties: '', instruction: code);
    document.paragraphs.single.inlines.insertAll(0, [
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: ' REF example ',
      ),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      WmlRun(text: 'Reference '),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ]);

    final reopened = _reopen(document).paragraphs.single;
    expect(
      reopened.inlines
          .whereType<WmlRun>()
          .singleWhere((run) => run.text == '(Original)')
          .fieldInstruction,
      code,
    );
    expect(
      reopened.inlines
          .whereType<WmlFieldBoundary>()
          .where(
            (boundary) => boundary.kind == WmlFieldBoundaryKind.instruction,
          )
          .map((boundary) => boundary.text),
      [' REF example '],
    );
  });

  for (final story in ['body', 'footnote', 'cell']) {
    for (final cycle in [1, 2]) {
      test(
        '$story actual DOCX save $cycle keeps editable formatted packets',
        () {
          var document = _converted(story, cycle);
          final fields = WordZotero.fields(document);
          expect(fields, hasLength(2));
          final data = fields.map((field) => field.citation!.toJson()).toList();
          final text = _paragraphs(document).map((p) => p.text).toList();
          final properties = _boundaryProperties(document);
          final codeProperties = _codeProperties(document);
          expect(properties.whereType<String>(), hasLength(6));
          expect(codeProperties, hasLength(2));
          for (var nativeCycle = 0; nativeCycle < 3; nativeCycle++) {
            _assertFields(document);
            expectConverterSnapshot(document, story);
            expect(
              WordZotero.fields(
                document,
              ).map((field) => field.citation!.toJson()),
              data,
            );
            expect(_paragraphs(document).map((p) => p.text), text);
            expect(_boundaryProperties(document), properties);
            expect(_codeProperties(document), codeProperties);
            document = _reopen(document);
          }
        },
      );

      test('$story actual DOCX save $cycle supports transactional Refresh', () {
        var document = _converted(story, cycle);
        expectConverterSnapshot(document, story);
        final before = _snapshot(document);
        final properties = _boundaryProperties(document);
        final codeProperties = _codeProperties(document);
        final sourceFields = WordZotero.fields(document);
        final beforeText = _paragraphs(document).map((p) => p.text).toList();
        final session = _session(document);
        final fields = _fields(session);
        expect(fields, hasLength(2));
        final newText = ['Refreshed first', 'Refreshed second'];
        for (var i = 0; i < fields.length; i++) {
          final citation = sourceFields[i].citation!;
          final revised = citation.withItems(
            citation.items,
            plainCitation: newText[i],
            noteIndex: fields[i]['noteIndex'] as int,
          );
          _call(session, 'Field.setCode', [
            fields[i]['id'],
            'ITEM CSL_CITATION ${jsonEncode(revised.toJson())}',
          ]);
          _call(session, 'Field.setText', [
            fields[i]['id'],
            i == 0
                ? '<i>Refreshed</i> <b>first</b>'
                : '<b>Refreshed second</b>',
            true,
          ]);
        }
        expect(_snapshot(document), before);
        _finish(session);
        final expectedText = [
          for (final text in beforeText)
            text
                .replaceAll(sourceFields[0].cachedText, newText[0])
                .replaceAll(sourceFields[1].cachedText, newText[1]),
        ];
        for (var nativeCycle = 0; nativeCycle < 3; nativeCycle++) {
          _assertFields(document);
          expectConverterSnapshot(
            document,
            story,
            refreshedCitations: const {
              'FIRST1': 'Refreshed first',
              'SECOND2': 'Refreshed second',
            },
          );
          final updated = WordZotero.fields(document);
          expect(updated.map((field) => field.cachedText), newText);
          expect(_paragraphs(document).map((p) => p.text), expectedText);
          expect(_boundaryProperties(document), properties);
          expect(_codeProperties(document), codeProperties);
          for (var i = 0; i < updated.length; i++) {
            expect(
              updated[i].citation!.items.single.toJson(),
              sourceFields[i].citation!.items.single.toJson(),
            );
            expect(updated[i].citation!.noteIndex, story == 'footnote' ? 1 : 0);
          }
          expect(
            WmlRunEdit.propsAt(
              updated.first.paragraph,
              updated.first.start,
            ).italic,
            isTrue,
          );
          expect(
            WmlRunEdit.propsAt(
              updated.first.paragraph,
              updated.first.end - 1,
            ).bold,
            isTrue,
          );
          expect(
            WmlRunEdit.propsAt(updated.last.paragraph, updated.last.start).bold,
            isTrue,
          );
          document = _reopen(document);
        }
      });

      test(
        '$story actual DOCX save $cycle distinguishes unlink and delete',
        () {
          final document = _converted(story, cycle);
          final source = WordZotero.fields(document);
          final before = _snapshot(document);
          final expected = _paragraphs(
            document,
          ).map((p) => p.text.replaceAll(source.last.cachedText, '')).toList();
          final session = _session(document);
          final fields = _fields(session);
          _call(session, 'Field.removeCode', [fields.first['id']]);
          _call(session, 'Field.delete', [fields.last['id']]);
          expect(_snapshot(document), before);
          _finish(session);
          for (final saved in [document, _reopen(document)]) {
            expect(WordZotero.fields(saved), isEmpty);
            expect(_paragraphs(saved).map((p) => p.text), expected);
            expect(
              _paragraphs(saved).map((p) => p.text).join('\n'),
              contains(source.first.cachedText),
            );
            expect(WordFieldSpans.unbalanced(saved), isEmpty);
          }
        },
      );
    }
  }

  test('code-only metadata edit retains split instructions and cache runs', () {
    final document = _synthetic();
    final field = WordZotero.fields(document).single;
    final properties = _boundaryProperties(document);
    final beforeRun = field.paragraph.inlines.whereType<WmlRun>().elementAt(1);
    final revised = field.citation!.withItems([
      ZoteroCitationItem.fromJson({
        ...field.citation!.items.single.toJson(),
        'locator': '99',
      }),
    ], plainCitation: field.cachedText);
    WordZotero.updateCitation(field, revised);
    expect(_boundaryProperties(document), properties);
    expect(
      field.paragraph.inlines.whereType<WmlRun>().elementAt(1),
      same(beforeRun),
    );
    final current = WordZotero.fields(_reopen(document)).single;
    expect(current.citation!.items.single.locator, '99');
    expect(current.cachedText, '(Original)');
    expect(current.canEdit, isTrue);
    expect(
      current.paragraph.inlines.whereType<WmlFieldBoundary>(),
      hasLength(5),
    );
  });

  test('plain cache update retains the field boundary formatting', () {
    final document = _synthetic();
    final properties = _boundaryProperties(document);
    WordZotero.updateCitation(
      WordZotero.fields(document).single,
      _citation('(New cache)'),
    );
    expect(document.paragraphs.single.text, 'Before (New cache) After');
    expect(_boundaryProperties(document), properties);
    _assertFields(_reopen(document));
  });

  test(
    'benign boundary formatting can accompany damaged metadata recovery',
    () {
      final document = _synthetic(
        instruction: ' ADDIN ZOTERO_ITEM CSL_CITATION {bad} ',
      );
      final properties = _boundaryProperties(document);
      final source = WordZotero.fields(document).single;
      expect(source.canEdit, isFalse);
      expect(source.canEditNativeResult, isTrue);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.setCode', [
        field['id'],
        'ITEM CSL_CITATION ${jsonEncode(_citation('(Repaired)').toJson())}',
      ]);
      _call(session, 'Field.setText', [field['id'], '(Repaired)', false]);
      _finish(session);
      expect(_boundaryProperties(document), properties);
      expect(
        WordZotero.fields(_reopen(document)).single.cachedText,
        '(Repaired)',
      );
    },
  );

  test('a replaced formatted boundary invalidates an earlier field handle', () {
    final document = _synthetic();
    final field = WordZotero.fields(document).single;
    final paragraph = field.paragraph;
    final old = paragraph.inlines[2] as WmlFieldBoundary;
    paragraph.inlines[2] = WmlFieldBoundary(
      kind: old.kind,
      text: old.text,
      runPropertiesXml: _properties.replaceFirst('Arial', 'Calibri'),
    );
    final before = _snapshot(document);
    expect(
      () => WordZotero.updateCitation(field, _citation('(Changed)')),
      throwsStateError,
    );
    expect(_snapshot(document), before);
  });

  for (final entryCount in [1, 3]) {
    test(
      'native bibliography keeps boundary formatting with $entryCount entries',
      () {
        const instruction =
            ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';
        final paragraphs = WordZotero.nativeBibliographyParagraphs(
          instruction: instruction,
          text: 'Original first.\nOriginal second.',
        );
        for (final paragraph in paragraphs) {
          for (var i = 0; i < paragraph.inlines.length; i++) {
            final inline = paragraph.inlines[i];
            if (inline is WmlFieldBoundary) {
              paragraph.inlines[i] = WmlFieldBoundary(
                kind: inline.kind,
                text: inline.text,
                sourceXml: inline.sourceXml,
                runPropertiesXml: _properties,
              );
            }
          }
        }
        final document = WmlDocument(
          sections: [WmlSection(blocks: paragraphs)],
        );
        final properties = _boundaryProperties(document);
        final first = document.paragraphs.first;
        final session = _session(document);
        final field = _fields(session).single;
        _call(session, 'Field.setText', [
          field['id'],
          '<div class="csl-bib-body">${[for (var i = 1; i <= entryCount; i++) '<div class="csl-entry"><i>Entry $i</i>.</div>'].join()}</div>',
          true,
        ]);
        _finish(session);
        expect(document.paragraphs.first, same(first));
        for (final current in [document, _reopen(document)]) {
          final result = WordZotero.fields(current).single;
          expect(result.paragraphs, hasLength(entryCount));
          expect(
            result.cachedText,
            [for (var i = 1; i <= entryCount; i++) 'Entry $i.'].join('\n'),
          );
          expect(
            WordZotero.canRecoverNativeBibliography(current, result),
            isTrue,
          );
          expect(_boundaryProperties(current), properties);
          expect(WordFieldSpans.unbalanced(current), isEmpty);
        }
      },
    );
  }

  for (final properties in [
    '<w:b/>',
    '<w:bCs w:val="on"/><w:iCs w:val="0"/><w:szCs w:val="24"/>',
    '<w:lang w:val="en-US" w:bidi="ar" w:eastAsia="zh-Hans"/>',
  ]) {
    test(
      'accepts and preserves explicit supported code-run properties $properties',
      () {
        final document = _synthetic(
          properties:
              '<w:rPr xmlns:w="${OfficeNamespaces.w}">$properties</w:rPr>',
        );
        final before = _boundaryProperties(document);
        _assertFields(document);
        WordZotero.replaceNativeResult(
          WordZotero.fields(document).single,
          instruction: _citation('(New)').fieldInstruction,
          text: '(New)',
        );
        expect(_boundaryProperties(document), before);
        _assertFields(_reopen(document));
      },
    );
  }

  final malformedMarkers = <String, String>{
    'wrong element': '<w:bookmarkStart w:fldCharType="begin"/>',
    'wrong namespace':
        '<f:fldChar xmlns:f="urn:future" w:fldCharType="begin"/>',
    'mismatched kind': '<w:fldChar w:fldCharType="end"/>',
    'missing kind': '<w:fldChar/>',
    'invalid lock': '<w:fldChar w:fldCharType="begin" w:fldLock="unknown"/>',
    'invalid dirty': '<w:fldChar w:fldCharType="begin" w:dirty="unknown"/>',
    'form state': '<w:fldChar w:fldCharType="begin"><w:ffData/></w:fldChar>',
    'EOF attribute': '<w:fldChar w:fldCharType=',
  };
  for (final entry in malformedMarkers.entries) {
    test('refuses ${entry.key} on a formatted field boundary', () {
      final document = _synthetic();
      final paragraph = document.paragraphs.single;
      paragraph.inlines[1] = WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.begin,
        runPropertiesXml: _properties,
        sourceXml: entry.value
            .replaceFirst(' ', ' xmlns:w="${OfficeNamespaces.w}" ')
            .replaceFirst(
              '<w:fldChar/>',
              '<w:fldChar xmlns:w="${OfficeNamespaces.w}"/>',
            ),
      );
      final before = _snapshot(document);
      expect(WordZotero.fields(document).single.opaqueMetadata, isTrue);
      expect(() => _session(document), throwsUnsupportedError);
      expect(_snapshot(document), before);
    });
  }

  final malformedFragments = <String, String>{
    'multiple roots':
        '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:vanish/></w:rPr>$_properties',
    'unterminated root': _properties.replaceFirst('</w:rPr>', ''),
    'EOF attribute': '<w:rPr xmlns:w=',
    'processing instruction': '<?state preserve="yes"?>$_properties',
    'DTD': '<!DOCTYPE w:rPr [<!ENTITY x "state">]>$_properties',
    'prefix text': 'unmodeled$_properties',
    'trailing CDATA': '$_properties<![CDATA[state]]>',
    'duplicate attribute':
        '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:b w:val="false" w:val="true"/></w:rPr>',
  };
  for (final entry in malformedFragments.entries) {
    test('malformed property fragment ${entry.key} remains uneditable', () {
      final document = _synthetic(properties: entry.value);
      final field = WordZotero.fields(document).single;
      final source = field.paragraph.inlines.toList();
      expect(field.opaqueMetadata, isTrue);
      expect(() => _session(document), throwsUnsupportedError);
      expect(
        () => WordZotero.updateCitation(field, _citation('(Changed)')),
        throwsUnsupportedError,
      );
      expect(field.paragraph.inlines, orderedEquals(source));
    });
  }
  test('multiple field-marker roots cannot hide a locked first marker', () {
    final document = _synthetic();
    document.paragraphs.single.inlines[1] = WmlFieldBoundary(
      kind: WmlFieldBoundaryKind.begin,
      sourceXml:
          '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
          'w:fldCharType="begin" w:fldLock="true"/>'
          '<w:fldChar xmlns:w="${OfficeNamespaces.w}" w:fldCharType="begin"/>',
    );
    expect(WordZotero.fields(document).single.opaqueMetadata, isTrue);
    expect(() => _session(document), throwsUnsupportedError);
  });

  final unsafeCode = <String, WmlInline Function()>{
    'unknown formatting': () => WmlRun(
      properties: WmlRunProps()
        ..sourcePropertiesXml =
            '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:vanish/></w:rPr>',
    ),
    'formatting revision': () => WmlRun(
      properties: WmlRunProps()
        ..sourcePropertiesXml =
            '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:rPrChange/></w:rPr>',
    ),
    'modeled style inheritance': () =>
        WmlRun(properties: WmlRunProps(styleId: 'HiddenStyle')),
    'comment anchor': () => WmlRun(commentIds: [17]),
    'locked run': () => WmlRun(fieldLocked: true),
    'native field': () => WmlRun(fieldInstruction: ' DATE '),
    'note reference': () => WmlRun(noteRefId: 7),
    'hyperlink': () =>
        WmlRun(hyperlink: WmlHyperlink(url: 'https://example.org')),
    'bookmark': () => WmlBookmarkBoundary(id: '17', isStart: true),
    'content control': () => WmlContentControlBoundary(
      control: WmlContentControlData(
        xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
      ),
      start: true,
    ),
  };
  for (final entry in unsafeCode.entries) {
    test('empty code envelope refuses ${entry.key}', () {
      final document = _synthetic();
      document.paragraphs.single.inlines.insert(3, entry.value());
      final field = WordZotero.fields(document).first;
      expect(field.canEditNativeResult, isFalse);
      expect(
        WordFieldSpans.zoteroCitations(field.paragraph).first.canEdit,
        isFalse,
      );
      expect(() => _session(document), throwsUnsupportedError);
      expect(
        () => WordZotero.updateCitation(field, _citation('(Changed)')),
        throwsUnsupportedError,
      );
    });
  }

  test('an aliased empty code run has no unambiguous document owner', () {
    final document = _synthetic();
    final run = WmlRun();
    document.paragraphs.single.inlines.insert(3, run);
    document.sections.single.blocks.add(WmlParagraph(inlines: [run]));
    expect(() => _session(document), throwsUnsupportedError);
  });

  test('replacing an empty code run invalidates an earlier field handle', () {
    final document = _synthetic();
    document.paragraphs.single.inlines.insert(3, WmlRun());
    final field = WordZotero.fields(document).single;
    document.paragraphs.single.inlines[3] = WmlRun();
    expect(
      () => WordZotero.updateCitation(field, _citation('(Changed)')),
      throwsStateError,
    );
  });

  test(
    'imported empty-code-run revisions retain history and block all field edits',
    () {
      var document = _emptyCodeRevision();
      for (var cycle = 0; cycle < 3; cycle++) {
        final field = WordZotero.fields(document).single;
        final before = _snapshot(document);
        final inlines = field.paragraph.inlines.toList();
        final revisions = WordRevisions.capture(document);
        expect(field.opaqueMetadata, isTrue);
        expect(
          WordFieldSpans.zoteroCitations(field.paragraph).single.canEdit,
          isFalse,
        );
        expect(
          WordFieldSpans.zoteroCitations(
            WmlClone.paragraph(field.paragraph),
          ).single.canEdit,
          isFalse,
        );
        expect(document.revisions, hasLength(1));
        expect(document.revisions.single.author, 'Reviewer');
        expect(
          document.revisions.single.previousPropertiesXml,
          contains('<w:i'),
        );
        expect(() => _session(document), throwsUnsupportedError);
        expect(
          () => WordZotero.updateCitation(field, _citation('(Changed)')),
          throwsUnsupportedError,
        );
        expect(
          () => WmlRunEdit.replaceRange(
            field.paragraph,
            field.start + 1,
            field.end - 1,
            'changed',
          ),
          throwsUnsupportedError,
        );
        expect(
          () => WmlRunEdit.replaceRange(
            field.paragraph,
            field.start,
            field.end,
            '',
          ),
          throwsUnsupportedError,
        );
        expect(_snapshot(document), before);
        expect(field.paragraph.inlines, orderedEquals(inlines));
        expect(revisions.matches(document), isTrue);
        final saved = WordSerializer().write(document);
        expect(
          saved.getPart('/word/document.xml')!.readText(),
          contains('rPrChange'),
        );
        document = WordDeserializer().read(saved);
      }
    },
  );

  for (final accept in [true, false]) {
    test(
      '${accept ? 'accepting' : 'rejecting'} an empty-code formatting revision clears its guard without resurrecting history',
      () {
        var document = _emptyCodeRevision();
        final originalText = document.paragraphs.single.text;
        final revision = document.revisions.single;
        if (accept) {
          WordRevisions.accept(document, revision);
        } else {
          WordRevisions.reject(document, revision);
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(document.revisions, isEmpty);
          expect(document.paragraphs.single.text, originalText);
          final field = WordZotero.fields(document).single;
          expect(field.canEdit, isTrue);
          expect(
            WordFieldSpans.zoteroCitations(field.paragraph).single.canEdit,
            isTrue,
          );
          final run = _codeRuns(document).single;
          expect(run.properties.hasEmptyFormattingRevision, isFalse);
          expect(run.properties.bold, accept);
          expect(run.properties.italic, !accept);
          final saved = WordSerializer().write(document);
          expect(
            saved.getPart('/word/document.xml')!.readText(),
            isNot(contains('rPrChange')),
          );
          document = WordDeserializer().read(saved);
        }
      },
    );
  }

  test('restoring an accepted revision restores its copied code-run guard', () {
    final document = _emptyCodeRevision();
    final paragraph = document.paragraphs.single;
    final inlines = WmlClone.inlines(paragraph.inlines);
    final history = WordRevisions.capture(document);
    WordRevisions.accept(document, document.revisions.single);
    expect(WordFieldSpans.zoteroCitations(paragraph).single.canEdit, isTrue);
    paragraph.inlines
      ..clear()
      ..addAll(WmlClone.inlines(inlines));
    history.restore(document);
    for (final current in [document, _reopen(document)]) {
      expect(current.revisions, hasLength(1));
      expect(current.revisions.single.author, 'Reviewer');
      expect(WordZotero.fields(current).single.canEdit, isFalse);
      expect(
        WordFieldSpans.zoteroCitations(
          current.paragraphs.single,
        ).single.canEdit,
        isFalse,
      );
    }
  });

  final unsupported = <String, String>{
    'run style inheritance': '<w:rStyle w:val="HiddenStyle"/>',
    'revision state': '<w:rPrChange w:id="1"/>',
    'hidden text': '<w:vanish/>',
    'foreign extension': '<f:state xmlns:f="urn:future"/>',
    'foreign formatting attribute': '<w:b xmlns:f="urn:future" f:val="true"/>',
    'invalid toggle': '<w:b w:val="perhaps"/>',
    'contradictory duplicate': '<w:b/><w:b w:val="false"/>',
    'themed font': '<w:rFonts w:asciiTheme="minorHAnsi"/>',
    'themed color': '<w:color w:val="000000" w:themeColor="accent1"/>',
    'invalid color': '<w:color w:val="red"/>',
    'invalid size': '<w:sz w:val="-1"/>',
    'excessive size': '<w:sz w:val="65535"/>',
    'unmodeled attribute': '<w:sz w:val="22" w:extra="true"/>',
    'nested state': '<w:b><w:color w:val="000000"/></w:b>',
    'unexpected text': 'Authored state<w:b/>',
    'font state': '<w:rFonts w:ascii=""/>',
    'invalid language': '<w:lang w:val="ar; color:red"/>',
  };
  for (final entry in unsupported.entries) {
    test('refuses ${entry.key} without losing opaque source', () {
      final document = _synthetic(
        properties:
            '<w:rPr xmlns:w="${OfficeNamespaces.w}">${entry.value}</w:rPr>',
      );
      final field = WordZotero.fields(document).single;
      expect(field.opaqueMetadata, isTrue);
      expect(field.canEditNativeResult, isFalse);
      final before = _snapshot(document);
      expect(() => _session(document), throwsUnsupportedError);
      expect(
        () => WordZotero.updateCitation(field, _citation('(Changed)')),
        throwsUnsupportedError,
      );
      expect(_snapshot(document), before);
      var reopened = document;
      for (var cycle = 0; cycle < 3; cycle++) {
        reopened = _reopen(reopened);
        expect(_boundaryProperties(reopened), _boundaryProperties(document));
        expect(WordZotero.fields(reopened).single.canEdit, isFalse);
      }
    });
  }

  const revisionProperties =
      '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:b/>'
      '<w:rPrChange w:id="13" w:author="Original reviewer" '
      'w:date="2026-11-19T10:00:00Z"><w:rPr><w:i/></w:rPr>'
      '</w:rPrChange></w:rPr>';
  for (final kind in WmlFieldBoundaryKind.values) {
    test(
      '${kind.name} formatting history remains opaque after repeated saves',
      () {
        var document = _synthetic();
        final paragraph = document.paragraphs.single;
        for (var i = 0; i < paragraph.inlines.length; i++) {
          final inline = paragraph.inlines[i];
          if (inline is! WmlFieldBoundary || inline.kind != kind) continue;
          paragraph.inlines[i] = WmlFieldBoundary(
            kind: inline.kind,
            text: inline.text,
            sourceXml: inline.sourceXml,
            runPropertiesXml: revisionProperties,
          );
        }
        final properties = _boundaryProperties(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          document = _reopen(document);
          expect(_boundaryProperties(document), properties);
          expect(document.revisions, isEmpty);
          expect(WordFieldSpans.unbalanced(document), isEmpty);
          expect(WordZotero.fields(document).single.opaqueMetadata, isTrue);
          expect(WordZotero.fields(document).single.canEdit, isFalse);
          expect(() => _session(document), throwsUnsupportedError);
        }
      },
    );
  }

  test('a mixed text and marker run retains both formatting histories', () {
    final package = OpcPackage.create(OpcPackageKind.word);
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
          '<w:r>$revisionProperties<w:t xml:space="preserve">Before </w:t>'
          '<w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText xml:space="preserve">${_citation().fieldInstruction}'
          '</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>'
          '<w:r><w:t>(Original)</w:t></w:r>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
          '<w:r><w:t xml:space="preserve"> After</w:t></w:r>'
          '</w:p><w:sectPr/></w:body></w:document>',
        );
    var document = WordDeserializer().read(package);
    final properties = _boundaryProperties(document);
    for (var cycle = 0; cycle < 3; cycle++) {
      final revision = document.revisions.single;
      expect(revision.kind, WmlRevisionKind.runFormat);
      expect(revision.author, 'Original reviewer');
      expect(revision.displayText, 'Before ');
      expect(_boundaryProperties(document), properties);
      expect(document.paragraphs.single.text, 'Before (Original) After');
      expect(WordZotero.fields(document).single.canEdit, isFalse);
      document = _reopen(document);
    }
    WordRevisions.reject(document, document.revisions.single);
    final firstRun = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .first;
    expect(firstRun.properties.bold, isFalse);
    expect(firstRun.properties.italic, isTrue);
    document = _reopen(document);
    expect(document.revisions, isEmpty);
    expect(_boundaryProperties(document), properties);
    expect(WordZotero.fields(document).single.canEdit, isFalse);
  });

  for (final kind in [
    WmlFieldBoundaryKind.begin,
    WmlFieldBoundaryKind.separate,
    WmlFieldBoundaryKind.end,
  ]) {
    test('field lock on ${kind.name} remains guarded', () {
      final document = _synthetic();
      final paragraph = document.paragraphs.single;
      final index = paragraph.inlines.indexWhere(
        (inline) => inline is WmlFieldBoundary && inline.kind == kind,
      );
      final old = paragraph.inlines[index] as WmlFieldBoundary;
      paragraph.inlines[index] = WmlFieldBoundary(
        kind: kind,
        runPropertiesXml: old.runPropertiesXml,
        sourceXml:
            '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
            'w:fldCharType="${kind.name}" w:fldLock="true"/>',
      );
      expect(WordZotero.fields(document).single.locked, isTrue);
      expect(() => _session(document), throwsUnsupportedError);
      expect(WordZotero.fields(_reopen(document)).single.canEdit, isFalse);
    });
  }
}

WmlDocument _emptyCodeDocument({
  bool bibliography = false,
  String cache = '',
  bool trailingContext = false,
}) {
  const bibliographyInstruction =
      ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';
  return _reopen(
    WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                if (!bibliography)
                  WmlRun(
                    text: 'Before ',
                    properties: WmlRunProps(
                      color: '123456',
                      fontSizeHalfPoints: 24,
                    ),
                  ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: bibliography
                      ? bibliographyInstruction
                      : _citation(cache).fieldInstruction,
                ),
                WmlRun(
                  properties: WmlRunProps(
                    bold: true,
                    color: 'FF0000',
                    fontSizeHalfPoints: 56,
                  ),
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                if (cache.isNotEmpty)
                  WmlRun(
                    text: cache,
                    properties: WmlRunProps(
                      italic: true,
                      color: '345678',
                      fontSizeHalfPoints: 30,
                    ),
                  ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
                if (trailingContext)
                  WmlRun(
                    text: ' After',
                    properties: WmlRunProps(
                      color: '234567',
                      fontSizeHalfPoints: 26,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

void _expectVisibleResult(
  WmlDocument document,
  String text, {
  required String color,
  required int halfPoints,
  bool italic = false,
}) {
  final run = document.paragraphs
      .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
      .singleWhere((run) => run.text == text);
  expect(run.properties.color, color);
  expect(run.properties.fontSizeHalfPoints, halfPoints);
  expect(run.properties.bold, isFalse);
  expect(run.properties.italic, italic);
}

void _emptyCodeFormattingTests() {
  for (final action in ['metadata', 'native plain', 'native rich', 'unlink']) {
    test('empty code formatting stays outside citation $action results', () {
      final document = _emptyCodeDocument();
      final field = WordZotero.fields(document).single;
      expect(field.canEdit, isTrue);
      expect(field.cachedText, isEmpty);
      final code = field.paragraph.inlines.whereType<WmlRun>().singleWhere(
        (run) => run.text.isEmpty,
      );
      expect(code.properties.color, 'FF0000');
      final codeProperties = code.properties.sourcePropertiesXml;
      switch (action) {
        case 'metadata':
          WordZotero.updateCitation(field, _citation('Refreshed'));
        case 'native plain':
        case 'native rich':
          WordZotero.replaceNativeResult(
            field,
            instruction: _citation('Refreshed').fieldInstruction,
            text: 'Refreshed',
            formattedText: action == 'native rich'
                ? ZoteroFormattedText.fromHtml('<i>Refreshed</i>')
                : null,
          );
        case 'unlink':
          WordZotero.replaceNativeUnlinkedResult(
            document,
            field,
            text: 'Refreshed',
          );
      }
      for (final current in [document, _reopen(document)]) {
        expect(current.paragraphs.single.text, 'Before Refreshed');
        _expectVisibleResult(
          current,
          'Refreshed',
          color: '123456',
          halfPoints: 24,
          italic: action == 'native rich',
        );
        if (action == 'unlink') {
          expect(WordZotero.fields(current), isEmpty);
          expect(
            current.paragraphs.single.inlines.whereType<WmlRun>().any(
              (run) => run.text.isEmpty,
            ),
            isFalse,
          );
        } else {
          expect(WordZotero.fields(current).single.cachedText, 'Refreshed');
          final preserved = current.paragraphs.single.inlines
              .whereType<WmlRun>()
              .singleWhere((run) => run.text.isEmpty);
          expect(preserved.properties.color, 'FF0000');
          expect(
            _propertyFingerprint(preserved.properties.sourcePropertiesXml),
            _propertyFingerprint(codeProperties),
          );
        }
      }
    });
  }

  for (final unlink in [false, true]) {
    test('empty code formatting stays outside bibliography unlink=$unlink', () {
      final document = _emptyCodeDocument(bibliography: true);
      final field = WordZotero.fields(document).single;
      expect(WordZotero.canRecoverNativeBibliography(document, field), isTrue);
      if (unlink) {
        WordZotero.replaceNativeUnlinkedResult(
          document,
          field,
          text: 'Entry one\nEntry two',
        );
      } else {
        WordZotero.replaceNativeBibliography(
          document,
          field,
          instruction: field.instruction,
          text: 'Entry one\nEntry two',
        );
      }
      for (final current in [document, _reopen(document)]) {
        expect(current.paragraphs.map((p) => p.text), [
          'Entry one',
          'Entry two',
        ]);
        for (final entry in ['Entry one', 'Entry two']) {
          _expectVisibleResult(current, entry, color: '000000', halfPoints: 22);
        }
        expect(WordZotero.fields(current), hasLength(unlink ? 0 : 1));
      }
    });
  }

  test('empty code formatting preserves existing cached result style', () {
    final document = _emptyCodeDocument(cache: 'Old cache');
    WordZotero.updateCitation(
      WordZotero.fields(document).single,
      _citation('Refreshed'),
    );
    for (final current in [document, _reopen(document)]) {
      _expectVisibleResult(
        current,
        'Refreshed',
        color: '345678',
        halfPoints: 30,
        italic: true,
      );
    }
  });

  test('empty code formatting preserves following context fallback', () {
    final document = _emptyCodeDocument(trailingContext: true);
    WordZotero.updateCitation(
      WordZotero.fields(document).single,
      _citation('Refreshed'),
    );
    for (final current in [document, _reopen(document)]) {
      expect(current.paragraphs.single.text, 'Before Refreshed After');
      _expectVisibleResult(
        current,
        'Refreshed',
        color: '234567',
        halfPoints: 26,
      );
    }
  });

  test('empty code formatting ignores adjacent empty citation code', () {
    final document = _emptyCodeDocument();
    final following = _emptyCodeDocument();
    document.paragraphs.single.inlines.addAll(
      following.paragraphs.single.inlines.skip(1),
    );
    final source = WordZotero.fields(document);
    expect(source, hasLength(2));
    WordZotero.updateCitation(source.first, _citation('Refreshed'));
    for (final current in [document, _reopen(document)]) {
      expect(WordZotero.fields(current), hasLength(2));
      expect(WordZotero.fields(current).last.cachedText, isEmpty);
      _expectVisibleResult(
        current,
        'Refreshed',
        color: '123456',
        halfPoints: 24,
      );
    }
  });
}
