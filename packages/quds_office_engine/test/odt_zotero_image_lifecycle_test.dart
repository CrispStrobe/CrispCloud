import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Independent PNG pixels: red/green/blue above yellow/cyan/magenta. These
// lifecycle assertions do not use the importer as the expected-result oracle.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
final _png = base64Decode(_pngBase64);
const _id = 'odt-picture-lifecycle';
const _link = 'https://example.org/research?figure=1&view=full';

String _preferences() => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'picture-session',
  'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'de-DE'},
  'prefs': {'fieldType': 'Field', 'noteType': 0},
  'futureDocument': {'keep': 'العربية 😀'},
});

ZoteroCitation _citation(String id, [String cache = '(Same)']) =>
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '9–11',
          'label': 'page',
          'prefix': 'see ',
          'suffix': ' et seq.',
          'suppress-author': true,
          'itemData': {'id': 17, 'type': 'book', 'title': 'Figure sources'},
          'futureItem': {'keep': true},
        },
      ],
      'properties': {'plainCitation': cache, 'noteIndex': 0},
      'futureCitation': [null, true, '😀'],
    });

WmlRun _picture() => WmlRun(
  text: '\uFFFC',
  hyperlink: const WmlHyperlink(url: _link),
  inlineVisual: WmlVisual(
    visual: OfficeVisual(
      kind: OfficeVisualKind.picture,
      title: 'Object name',
      width: 72,
      height: 48,
      imageBytes: Uint8List.fromList(_png),
      picture: PictureAdjust(
        altTitle: 'Research figure',
        altDescription: 'Six samples & العربية 😀',
      ),
    ),
  ),
);

WmlParagraph _paragraph(String id) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Lead 😀 '),
    _picture(),
    WmlRun(text: ' '),
    WmlRun(text: '(Same)', fieldInstruction: _citation(id).fieldInstruction),
    _picture(),
    WmlRun(text: ' tail'),
  ],
);

WmlDocument _document(String owner) {
  final paragraph = _paragraph(owner);
  final section = WmlSection(
    sourceProperties: WmlSectionSource(
      xml:
          '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
          '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
          '</w:sectPr>',
      values: const {},
    ),
  );
  final document = WmlDocument(
    sections: [section],
    zoteroDocumentData: _preferences(),
  );
  if (owner == 'body') {
    section.blocks.add(paragraph);
  } else if (owner == 'cell') {
    section.blocks.add(
      WmlTable(
        grid: [144, 144],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(width: 288, gridSpan: 2, blocks: [paragraph]),
            ],
          ),
        ],
      ),
    );
    section.blocks.add(WmlParagraph(inlines: [WmlRun(text: 'After table')]));
  } else {
    final endnote = owner == 'endnote';
    section.blocks.add(
      WmlParagraph(
        inlines: [
          WmlRun(text: 'Anchor '),
          WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
        ],
      ),
    );
    (endnote ? document.endnotes : document.footnotes).add(
      WmlNote(
        id: 1,
        endnote: endnote,
        addReference: false,
        addReferenceSpace: false,
        paragraphs: [paragraph],
      ),
    );
  }
  return document;
}

Iterable<WmlParagraph> _paragraphs(WmlDocument document) sync* {
  yield* document.paragraphs;
  for (final note in [...document.footnotes, ...document.endnotes]) {
    yield* note.allParagraphs;
  }
}

List<WmlRun> _pictures(WmlDocument document) => [
  for (final paragraph in _paragraphs(document))
    ...paragraph.inlines.whereType<WmlRun>().where(
      (run) => run.inlineVisual != null,
    ),
];

void _expectPictures(WmlDocument document, {int count = 2}) {
  final pictures = _pictures(document);
  expect(pictures, hasLength(count));
  for (final run in pictures) {
    expect(run.text, '\uFFFC');
    expect(run.isAtomic, isTrue);
    expect(run.hyperlink?.url, _link);
    final visual = run.inlineVisual!.visual;
    expect(visual.imageBytes, orderedEquals(_png));
    expect(visual.width, closeTo(72, 0.01));
    expect(visual.height, closeTo(48, 0.01));
    expect(visual.picture.altTitle, 'Research figure');
    expect(visual.picture.altDescription, 'Six samples & العربية 😀');
  }
}

void _expectCitation(
  WmlDocument document,
  String id,
  String cache, {
  bool refreshed = false,
}) {
  final field = WordZotero.fields(document).single;
  expect(field.canEdit, isTrue);
  expect(field.citation!.citationId, id);
  final expected = Map<String, Object?>.of(_citation(id, cache).toJson());
  if (refreshed) {
    expected['properties'] = {
      ...expected['properties']! as Map<String, Object?>,
      'qudsFormat': 'zotero-desktop',
    };
  }
  expect(field.metadata, expected);
  expect(field.start, 'Lead 😀 \uFFFC '.length);
  expect(field.end, field.start + cache.length);
  expect(field.cachedText, cache);
  expect(field.paragraph.text, 'Lead 😀 \uFFFC $cache\uFFFC tail');
}

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

void _refresh(WmlDocument document, String id, String cache) {
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _id,
    insertionParagraph: document.paragraphs.first,
  );
  final wire = (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
      .cast<Map<String, Object?>>()
      .single;
  _call(session, 'Field.setCode', [
    wire['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, cache).toJson())}',
  ]);
  _call(session, 'Field.setText', [wire['id'], '<i>$cache</i>', true]);
  _call(session, 'Document.complete');
  session.prepareReview();
  session.apply();
}

void main() {
  for (final owner in ['body', 'cell', 'footnote', 'endnote']) {
    test(
      '$owner images and exact fields survive three ODT/DOCX cycles',
      () async {
        var document = _document(owner);
        final originalData = document.zoteroDocumentData;
        for (var cycle = 0; cycle < 3; cycle++) {
          final sourceParagraphs = _paragraphs(document).toList();
          final sourceTexts = sourceParagraphs.map((p) => p.text).toList();
          final exported = OdtDocumentWriter.writeEditableZoteroBytes(document);
          expect(_paragraphs(document), orderedEquals(sourceParagraphs));
          expect(_paragraphs(document).map((p) => p.text), sourceTexts);
          final source = Uint8List.fromList(exported);
          document = await OdtDocumentReader.readBytes(exported);
          expect(exported, source);
          _expectPictures(document);
          _expectCitation(document, owner, '(Same)');
          expect(document.zoteroDocumentData, originalData);
          if (owner == 'cell') {
            final table = document.sections.single.blocks.first as WmlTable;
            expect(table.rows.single.cells.single.gridSpan, 2);
            expect(
              WordZotero.fields(document).single.paragraph,
              same(table.rows.single.cells.single.blocks.single),
            );
          } else if (owner == 'footnote' || owner == 'endnote') {
            final note =
                (owner == 'footnote' ? document.footnotes : document.endnotes)
                    .single;
            expect(
              WordZotero.fields(document).single.paragraph,
              same(note.paragraphs.single),
            );
          }
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          _expectPictures(document);
          _expectCitation(document, owner, '(Same)');
        }
      },
    );

    test(
      '$owner imported citation refresh preserves both picture boundaries',
      () async {
        var document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(_document(owner)),
        );
        _refresh(document, owner, '(Long updated source, pp. 9–11)');
        _expectPictures(document);
        _expectCitation(
          document,
          owner,
          '(Long updated source, pp. 9–11)',
          refreshed: true,
        );
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        _expectPictures(document);
        _expectCitation(
          document,
          owner,
          '(Long updated source, pp. 9–11)',
          refreshed: true,
        );
        final session = WordZoteroCitingSession(
          document: document,
          documentId: _id,
          insertionParagraph: document.paragraphs.first,
        );
        final wire =
            (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
                .cast<Map<String, Object?>>()
                .single;
        _call(session, 'Field.removeCode', [wire['id']]);
        _call(session, 'Document.complete');
        session.prepareReview();
        session.apply();
        expect(WordZotero.fields(document), isEmpty);
        _expectPictures(document);
        expect(
          _paragraphs(document).any(
            (p) =>
                p.text ==
                'Lead 😀 \uFFFC (Long updated source, pp. 9–11)\uFFFC tail',
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'Zotero note image insertion continues through native ODT and DOCX',
    () async {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _id,
        insertionParagraph: document.paragraphs.first,
        insertionOffset: 6,
      );
      _call(session, 'Document.setDocumentData', [
        WordZoteroDocumentData.toHttp(_preferences()),
      ]);
      final temporary =
          _call(session, 'Document.insertField', ['Http', 0])
              as Map<String, Object?>;
      _call(session, 'Field.delete', [temporary['id']]);
      _call(session, 'Document.insertText', [
        '<p>Lead 😀 <a href="https://example.org/research?figure=1&amp;view=full">'
            '<img src="data:image/png;base64,$_pngBase64" width="96" height="64" '
            'title="Research figure" alt="Six samples &amp; العربية 😀"></a> '
            '<a href="https://www.zotero.org/?FIG123">(old)</a></p>',
      ]);
      final wire =
          (_call(session, 'Document.convertPlaceholdersToFields', [
                    ['FIG123'],
                    0,
                    'Http',
                  ])
                  as List<Object?>)
              .cast<Map<String, Object?>>()
              .single;
      _call(session, 'Field.setCode', [
        wire['id'],
        'ITEM CSL_CITATION ${jsonEncode(_citation('inserted').toJson())}',
      ]);
      _call(session, 'Field.setText', [wire['id'], '(Same)', false]);
      _call(session, 'Document.complete');
      session.prepareReview();
      session.apply();
      var reopened = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectPictures(reopened, count: 1);
        final field = WordZotero.fields(reopened).single;
        expect(field.citation!.citationId, 'inserted');
        expect(field.start, 'BeforeLead 😀 \uFFFC '.length);
        expect(field.cachedText, '(Same)');
        expect(
          reopened.paragraphs.single.text,
          'BeforeLead 😀 \uFFFC (Same)After',
        );
        reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(reopened),
        );
      }
    },
  );
}
