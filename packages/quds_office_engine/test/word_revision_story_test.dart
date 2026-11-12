import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _date = '2026-10-01T12:30:00Z';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

String _trackedParagraph(String name, {required bool deleted}) {
  final kind = deleted ? 'del' : 'ins';
  final text = deleted ? ' removed' : ' added';
  final node = deleted ? 'delText' : 't';
  return '<w:p><w:r><w:t>$name</w:t></w:r>'
      '<w:$kind w:id="${deleted ? 2 : 1}" w:author="Native reviewer" w:date="$_date">'
      '<w:r><w:rPr><w:b/></w:rPr><w:$node xml:space="preserve">$text</w:$node></w:r>'
      '</w:$kind><w:r><w:t xml:space="preserve"> tail</w:t></w:r></w:p>';
}

String _story(String name) =>
    _trackedParagraph(name, deleted: false) +
    _trackedParagraph(name, deleted: true);

OpcPackage _nativeSource({String? body}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final rels = package.relationshipsFor('/word/document.xml');
  final references = StringBuffer();
  for (final kind in <String>['header', 'footer']) {
    for (final variant in <String>['default', 'first', 'even']) {
      final uri = '/word/${kind}_$variant.xml';
      final root = kind == 'header' ? 'hdr' : 'ftr';
      final name = '${kind[0].toUpperCase()}${kind.substring(1)}-$variant';
      package.createPart(
        uri,
        kind == 'header'
            ? OfficeContentTypes.wordHeader
            : OfficeContentTypes.wordFooter,
        utf8.encode(
          '<w:$root xmlns:w="${OfficeNamespaces.w}">${_story(name)}</w:$root>',
        ),
      );
      final relationship = rels.add(
        type: kind == 'header'
            ? RelationshipTypes.header
            : RelationshipTypes.footer,
        target: uri.substring('/word/'.length),
      );
      references.write(
        '<w:${kind}Reference w:type="$variant" r:id="${relationship.id}"/>',
      );
    }
  }
  for (final endnote in <bool>[false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    final name = endnote ? 'Endnote' : 'Footnote';
    package.createPart(
      '/word/${kind}s.xml',
      endnote
          ? OfficeContentTypes.wordEndnotes
          : OfficeContentTypes.wordFootnotes,
      utf8.encode(
        '<w:${kind}s xmlns:w="${OfficeNamespaces.w}">'
        '<w:$kind w:id="1">${_story(name)}</w:$kind></w:${kind}s>',
      ),
    );
    rels.add(
      type: endnote ? RelationshipTypes.endnotes : RelationshipTypes.footnotes,
      target: '${kind}s.xml',
    );
  }
  package.createPart(
    '/word/comments.xml',
    OfficeContentTypes.wordComments,
    utf8.encode(
      '<w:comments xmlns:w="${OfficeNamespaces.w}">'
      '<w:comment w:id="7" w:author="Comment owner">${_story('Comment')}</w:comment>'
      '</w:comments>',
    ),
  );
  rels.add(type: RelationshipTypes.comments, target: 'comments.xml');
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}">'
        '<w:body>${body ?? '<w:p><w:r><w:t>UNCHANGED</w:t></w:r></w:p>${_story('Body')}'}'
        '<w:sectPr>$references<w:titlePg/></w:sectPr></w:body></w:document>',
      );
  return package;
}

Map<String, List<WmlParagraph>> _stories(WmlDocument document) {
  final section = document.sections.single;
  return <String, List<WmlParagraph>>{
    'Body': document.paragraphs.skip(1).toList(),
    'Header-default': section.header,
    'Header-first': section.firstHeader,
    'Header-even': section.evenHeader,
    'Footer-default': section.footer,
    'Footer-first': section.firstFooter,
    'Footer-even': section.evenFooter,
    'Footnote': document.footnotes.single.paragraphs,
    'Endnote': document.endnotes.single.paragraphs,
    'Comment': document.comments.single.paragraphs,
  };
}

List<XmlElement> _all(XmlElement node, String name) => <XmlElement>[
  for (final child in node.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._all(child, name),
  ],
];

void _assertPending(WmlDocument document) {
  expect(document.paragraphs.first.text, 'UNCHANGED');
  expect(document.revisions, hasLength(20));
  for (final entry in _stories(document).entries) {
    expect(entry.value.map((p) => p.text), <String>[
      '${entry.key} added tail',
      '${entry.key} removed tail',
    ]);
    for (var i = 0; i < 2; i++) {
      final paragraph = entry.value[i];
      final revision = document.revisions.singleWhere(
        (r) => identical(r.targetParagraph, paragraph),
      );
      expect(
        WordRevisions.resolveParagraph(document, revision),
        same(paragraph),
      );
      expect(revision.start, entry.key.length);
      expect(revision.end, entry.key.length + (i == 0 ? 6 : 8));
      expect(
        revision.kind,
        i == 0 ? WmlRevisionKind.insert : WmlRevisionKind.delete,
      );
      expect(revision.author, 'Native reviewer');
      expect(revision.dateIso, _date);
    }
  }
  expect(
    document.revisions
        .where((r) => r.paragraphIndex >= 0)
        .map((r) => r.paragraphIndex),
    <int>[1, 2],
  );
}

void main() {
  test(
    'record binds a body paragraph before index-changing structural edits',
    () {
      final document = WmlDocument.empty(text: 'Body added');
      final target = document.paragraphs.single;
      final revision = WordRevisions.record(
        document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 4,
        end: 10,
        text: ' added',
      );
      final preceding = _paragraph('Earlier body');
      document.sections.single.blocks.insert(0, preceding);
      WordRevisions.reject(document, revision);
      expect(target.text, 'Body');
      expect(preceding.text, 'Earlier body');
    },
  );

  test(
    'detached targets and invalid recorded indices never redirect into body',
    () {
      final document = WmlDocument.empty(text: 'Body content');
      final target = _paragraph('Header added');
      document.sections.single.header.add(target);
      final revision = WordRevisions.record(
        document,
        paragraph: target,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 6,
        end: 12,
        text: ' added',
      );
      document.sections.single.header.clear();
      expect(WordRevisions.resolveParagraph(document, revision), isNull);
      expect(() => WordRevisions.reject(document, revision), throwsStateError);
      expect(revision.accepted, isNull);
      expect(document.revisions, contains(same(revision)));
      expect(document.paragraphs.single.text, 'Body content');
      expect(target.text, 'Header added');

      final invalid = WordRevisions.record(
        document,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 1,
        start: 0,
        end: 3,
        text: 'New',
      );
      document.sections.single.blocks.add(_paragraph('New body'));
      expect(() => WordRevisions.accept(document, invalid), throwsStateError);
      expect(invalid.accepted, isNull);
      expect(document.paragraphs.last.text, 'New body');
    },
  );

  test(
    'legacy directly constructed revisions bind once and note tables resolve',
    () {
      final document = WmlDocument.empty(text: 'Body added');
      final target = document.paragraphs.single;
      final revision = WmlRevision(
        id: 99,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 4,
        end: 10,
        text: ' added',
      );
      expect(WordRevisions.resolveParagraph(document, revision), same(target));
      document.sections.single.blocks.insert(0, _paragraph('Earlier body'));
      WordRevisions.reject(document, revision);
      expect(target.text, 'Body');
      final cell = _paragraph('Cell removed');
      document.footnotes.add(
        WmlNote(
          id: 1,
          endnote: false,
          blocks: <WmlBlock>[
            WmlTable(
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(blocks: <WmlBlock>[cell]),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      WordRevisions.accept(
        document,
        WordRevisions.record(
          document,
          paragraph: cell,
          kind: WmlRevisionKind.delete,
          paragraphIndex: 0,
          start: 4,
          end: 12,
          text: ' removed',
        ),
      );
      expect(cell.text, 'Cell');
      expect(document.paragraphs.first.text, 'Earlier body');
    },
  );

  for (final isolate in <bool>[false, true]) {
    final mode = isolate ? 'isolate' : 'direct';
    test(
      '$mode preserves native revision ownership through three saves',
      () async {
        var document = WordDeserializer().read(_nativeSource());
        for (var cycle = 1; cycle <= 3; cycle++) {
          _assertPending(document);
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final package = OpcPackage.openBytes(bytes);
          final main = XmlDocument.parse(
            package.getPart('/word/document.xml')!.readText(),
          ).root!;
          final rels = package.relationshipsFor('/word/document.xml');
          final liveUris = <String>{
            '/word/document.xml',
            for (final kind in <String>['headerReference', 'footerReference'])
              for (final reference in _all(main, kind))
                rels.resolve(
                  rels.byId(
                    reference.getAttribute(
                      'id',
                      namespaceUri: OfficeNamespaces.r,
                    )!,
                  )!,
                ),
            for (final type in <String>[
              RelationshipTypes.footnotes,
              RelationshipTypes.endnotes,
              RelationshipTypes.comments,
            ])
              rels.resolve(rels.firstByType(type)!),
          };
          final tracked = <XmlElement>[
            for (final uri in liveUris)
              for (final kind in <String>['ins', 'del'])
                ..._all(
                  XmlDocument.parse(package.getPart(uri)!.readText()).root!,
                  kind,
                ),
          ];
          expect(tracked, hasLength(20));
          for (final element in tracked) {
            expect(element.childElements.single.localName, 'r');
            expect(
              element.text,
              element.localName == 'ins' ? ' added' : ' removed',
            );
            expect(
              element.firstChild('r')!.firstChild('rPr')!.firstChild('b'),
              isNotNull,
            );
          }
          final output = File(
            'build/fidelity-revision-stories/$mode-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
        }
        _assertPending(document);
      },
    );
  }

  for (final accept in <bool>[false, true]) {
    test(
      '${accept ? 'accept' : 'reject'} resolves all native story changes without touching other text',
      () {
        final document = WordDeserializer().read(_nativeSource());
        if (accept) {
          WordRevisions.acceptAll(document);
        } else {
          WordRevisions.rejectAll(document);
        }
        expect(document.revisions, isEmpty);
        expect(document.paragraphs.first.text, 'UNCHANGED');
        for (final entry in _stories(document).entries) {
          expect(entry.value.map((p) => p.text), <String>[
            '${entry.key}${accept ? ' added' : ''} tail',
            '${entry.key}${accept ? '' : ' removed'} tail',
          ]);
        }
      },
    );
  }

  test(
    'export cuts coalesced runs at exact tracked bounds without live mutation',
    () {
      const text = 'prefix ADD middle DROP suffix';
      final document = WmlDocument.empty(text: text);
      final paragraph = document.paragraphs.single;
      (paragraph.inlines.single as WmlRun).properties.bold = true;
      for (final item in <(String, WmlRevisionKind)>[
        ('ADD', WmlRevisionKind.insert),
        ('DROP', WmlRevisionKind.delete),
      ]) {
        WordRevisions.record(
          document,
          kind: item.$2,
          paragraphIndex: 0,
          start: text.indexOf(item.$1),
          end: text.indexOf(item.$1) + item.$1.length,
          text: item.$1,
        );
      }
      final bytes = WordSerializer().writeBytes(document);
      expect(paragraph.inlines, hasLength(1));
      expect(paragraph.text, text);
      final xml = XmlDocument.parse(
        OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(_all(xml, 'ins').single.text, 'ADD');
      expect(_all(xml, 'del').single.text, 'DROP');
      expect(
        _all(xml, 'p').single.childrenNamed('r').map((r) => r.text),
        <String>['prefix ', ' middle ', ' suffix'],
      );
      final reopened = WordDeserializer().readBytes(bytes);
      final added = reopened.revisions.singleWhere(
        (r) => r.kind == WmlRevisionKind.insert,
      );
      WordRevisions.reject(reopened, added);
      expect(reopened.paragraphs.single.text, 'prefix  middle DROP suffix');
    },
  );

  test(
    'native hyperlink changes retain real paragraph offsets and link metadata',
    () {
      final document = WordDeserializer().read(
        _nativeSource(
          body:
              '<w:p><w:r><w:t>Before </w:t></w:r><w:hyperlink w:anchor="topic">'
              '<w:r><w:t>Linked</w:t></w:r><w:ins w:id="1" w:author="Link reviewer">'
              '<w:r><w:t xml:space="preserve"> added</w:t></w:r></w:ins></w:hyperlink>'
              '<w:r><w:t> after</w:t></w:r></w:p>',
        ),
      );
      var copy = document;
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = copy.paragraphs.single;
        final revision = copy.revisions.singleWhere(
          (r) => identical(r.targetParagraph, paragraph),
        );
        expect(revision.start, 13);
        expect(revision.end, 19);
        expect(revision.text, ' added');
        expect(
          paragraph.inlines
              .whereType<WmlRun>()
              .where((r) => r.hyperlink?.anchor == 'topic')
              .map((r) => r.text)
              .join(),
          'Linked added',
        );
        copy = WordDeserializer().readBytes(WordSerializer().writeBytes(copy));
      }
      WordRevisions.reject(
        copy,
        copy.revisions.singleWhere(
          (r) => identical(r.targetParagraph, copy.paragraphs.single),
        ),
      );
      expect(copy.paragraphs.single.text, 'Before Linked after');
    },
  );

  test(
    'atomic fields retain schema-valid tracked result and full boundaries',
    () {
      final package = _nativeSource(
        body:
            '<w:p><w:r><w:t>Before </w:t></w:r>'
            '<w:fldSimple w:instr=" REF topic " w:fldLock="1" w:dirty="0">'
            '<w:ins w:id="4" w:author="Field reviewer"><w:r><w:t>Cached</w:t></w:r></w:ins>'
            '</w:fldSimple><w:r><w:t> after</w:t></w:r></w:p>',
      );
      var document = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = document.paragraphs.single;
        final revision = document.revisions.singleWhere(
          (r) => identical(r.targetParagraph, paragraph),
        );
        expect((revision.start, revision.end), (7, 13));
        final field = paragraph.inlines.whereType<WmlRun>().singleWhere(
          (r) => r.fieldInstruction != null,
        );
        expect(field.fieldInstruction, ' REF topic ');
        expect(field.fieldLocked, isTrue);
        expect(field.fieldDirty, isFalse);
        final saved = WordSerializer().write(document);
        final xml = XmlDocument.parse(
          saved.getPart('/word/document.xml')!.readText(),
        ).root!;
        final nativeField = _all(xml, 'fldSimple').single;
        expect(nativeField.childElements.single.localName, 'ins');
        expect(_all(xml, 'ins').single.firstChild('fldSimple'), isNull);
        document = WordDeserializer().readBytes(saved.save());
      }
      WordRevisions.reject(
        document,
        document.revisions.singleWhere(
          (r) => identical(r.targetParagraph, document.paragraphs.single),
        ),
      );
      expect(document.paragraphs.single.text, 'Before  after');
      expect(
        document.paragraphs.single.inlines.whereType<WmlRun>().where(
          (r) => r.isAtomic,
        ),
        isEmpty,
      );
    },
  );

  test(
    'partial tracked bounds never split atomic note marks or field results',
    () {
      final document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[
              for (final atomic in <WmlRun>[
                WmlRun(text: '12', noteRefId: 12),
                WmlRun(
                  text: 'Cached result',
                  fieldInstruction: ' REF target ',
                  fieldLocked: true,
                ),
              ])
                WmlParagraph(
                  inlines: <WmlInline>[
                    WmlRun(text: 'Before '),
                    atomic,
                    WmlRun(text: ' after'),
                  ],
                ),
            ],
          ),
        ],
      );
      document.footnotes.add(WmlNote(id: 12, endnote: false));
      for (final entry in document.paragraphs.indexed) {
        WordRevisions.record(
          document,
          kind: WmlRevisionKind.insert,
          paragraphIndex: entry.$1,
          start: 8,
          end: 9,
          text: entry.$2.text.substring(8, 9),
        );
      }
      final bytes = WordSerializer().writeBytes(document);
      final xml = XmlDocument.parse(
        OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(_all(xml, 'footnoteReference'), hasLength(1));
      expect(_all(xml, 'fldSimple'), hasLength(1));
      final copy = WordDeserializer().readBytes(bytes);
      expect(copy.revisions.map((r) => (r.start, r.end)), <(int, int)>[
        (7, 9),
        (7, 20),
      ]);
      WordRevisions.rejectAll(copy);
      expect(copy.paragraphs.map((p) => p.text), <String>[
        'Before  after',
        'Before  after',
      ]);
      expect(
        copy.paragraphs
            .expand((p) => p.inlines)
            .whereType<WmlRun>()
            .where((r) => r.isAtomic),
        isEmpty,
      );
    },
  );
}
