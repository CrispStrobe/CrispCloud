import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _fixture() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/word-altchunk.docx').readAsBytesSync(),
);

List<String> _sequence(
  OpcPackage package,
  String owner,
  XmlElement parent,
) => <String>[
  for (final XmlElement child in parent.childElements)
    if (child.localName == 'p')
      'p:${_text(child).trim()}'
    else if (child.localName == 'tbl')
      'table'
    else if (child.localName == 'altChunk')
      'chunk:${package.relationshipsFor(owner).resolve(package.relationshipsFor(owner).byId(child.getAttribute('id')!)!)}',
];

String _text(XmlElement parent) {
  final StringBuffer text = StringBuffer();
  void walk(XmlElement node) {
    if (node.namespaceUri == OfficeNamespaces.w && node.localName == 't') {
      text.write(node.text);
    } else {
      for (final XmlElement child in node.childElements) {
        walk(child);
      }
    }
  }

  walk(parent);
  return text.toString();
}

void _check(OpcPackage package, {required bool moved}) {
  const String main = '/word/document.xml';
  const String notes = '/word/footnotes.xml';
  final XmlElement body = XmlDocument.parse(
    package.getPart(main)!.readText(),
  ).root!.firstChild('body')!;
  final XmlElement note = XmlDocument.parse(package.getPart(notes)!.readText())
      .root!
      .childrenNamed('footnote')
      .singleWhere((XmlElement n) => n.getAttribute('id') == '3');
  expect(_sequence(package, main, body), <String>[
    'p:Edited before body',
    'chunk:/payload/${moved ? 'note' : 'body'}.html',
    'p:After opaque body',
    'table',
    'p:Reference note',
    if (moved) 'chunk:/payload/body.html',
  ]);
  final XmlElement cell = body
      .firstChild('tbl')!
      .firstChild('tr')!
      .firstChild('tc')!;
  expect(_sequence(package, main, cell), <String>[
    'p:Before opaque cell',
    'chunk:/payload/cell.html',
    'p:After opaque cell',
  ]);
  expect(_sequence(package, notes, note), <String>[
    'p:Before opaque note',
    'chunk:/payload/${moved ? 'body' : 'note'}.html',
    'p:Edited after note',
    if (moved) 'chunk:/payload/cell.html',
  ]);
  final OpcPackage original = OpcPackage.openBytes(
    File('test/fixtures/fidelity/word-altchunk.docx').readAsBytesSync(),
  );
  for (final String name in <String>['body', 'cell', 'note']) {
    final String uri = '/payload/$name.html';
    expect(
      package.getPart(uri)!.readBytes(),
      original.getPart(uri)!.readBytes(),
    );
    expect(package.getPart(uri)!.contentType, 'text/html');
  }
  if (moved) {
    final String bodyId = body
        .childrenNamed('altChunk')
        .first
        .getAttribute('id')!;
    final String noteId = note
        .childrenNamed('altChunk')
        .first
        .getAttribute('id')!;
    expect(bodyId, isNot('chunk'));
    expect(noteId, isNot('chunk'));
  }
}

void main() {
  test('import retains opaque positions and immutable resolved provenance', () {
    final WmlDocument document = _fixture();
    final WmlOpaqueBlock body = document.sections.single.blocks
        .whereType<WmlOpaqueBlock>()
        .single;
    final WmlOpaqueBlock note = document.footnotes.single.blocks
        .whereType<WmlOpaqueBlock>()
        .single;
    expect(body.sourcePartUri, '/word/document.xml');
    expect(note.sourcePartUri, '/word/footnotes.xml');
    expect(body.relationships.single.id, 'chunk');
    expect(note.relationships.single.id, 'chunk');
    expect(body.relationships.single.target, '/payload/body.html');
    expect(note.relationships.single.target, '/payload/note.html');
    expect(body.relationships.single.sha256, hasLength(64));
    final WmlOpaqueBlock clone = WmlClone.block(body) as WmlOpaqueBlock;
    expect(clone, isNot(same(body)));
    expect(clone.xml, body.xml);
    expect(() => clone.relationships.clear(), throwsUnsupportedError);
    // The external-format payload is deliberately not synthesized as rendered
    // paragraph text. Its original bytes remain available for native export.
    expect(
      document.paragraphs.map((WmlParagraph p) => p.text).join(),
      isNot(contains('ALT_BODY_PAYLOAD')),
    );
    final LaidOutDocument layout = WordLayoutEngine(
      font: null,
    ).layout(document);
    expect(layout.pages, isNotEmpty);
  });

  for (final bool moved in <bool>[false, true]) {
    test(
      '${moved ? 'moves and clones across colliding story IDs' : 'adjacent edits'} preserve chunks over three asynchronous saves',
      () async {
        WmlDocument document = _fixture();
        document.paragraphs.first.inlines.whereType<WmlRun>().first.text =
            'Edited before body';
        document.footnotes.single.paragraphs.last.inlines
                .whereType<WmlRun>()
                .last
                .text =
            'Edited after note';
        if (moved) {
          final WmlSection section = document.sections.single;
          final WmlNote note = document.footnotes.single;
          final WmlOpaqueBlock bodyChunk = section.blocks[1] as WmlOpaqueBlock;
          final WmlOpaqueBlock noteChunk = note.blocks[1] as WmlOpaqueBlock;
          final WmlTable table = section.blocks.whereType<WmlTable>().single;
          final WmlOpaqueBlock cellChunk = table.rows.single.cells.single.blocks
              .whereType<WmlOpaqueBlock>()
              .single;
          section.blocks[1] = noteChunk;
          note.blocks[1] = bodyChunk;
          section.blocks.add(WmlClone.block(bodyChunk));
          note.blocks.add(WmlClone.block(cellChunk));
        }
        int? relationshipCount;
        for (int cycle = 1; cycle <= 3; cycle++) {
          final Uint8List bytes = await OfficeIsolateSave.word(document);
          final OpcPackage package = OpcPackage.openBytes(bytes);
          _check(package, moved: moved);
          final int count =
              package.relationshipsFor('/word/document.xml').length +
              package.relationshipsFor('/word/footnotes.xml').length;
          relationshipCount ??= count;
          expect(
            count,
            relationshipCount,
            reason: 'Repeated saves must reuse rebound relationships',
          );
          final File output = File(
            'build/fidelity-altchunk/altchunk-${moved ? 'moved' : 'imported'}-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().read(package);
        }
      },
    );
  }

  test(
    'a copy without original payloads fails instead of producing a broken file',
    () {
      final WmlOpaqueBlock original = _fixture().sections.single.blocks
          .whereType<WmlOpaqueBlock>()
          .single;
      final WmlDocument copied = WmlDocument(
        sections: <WmlSection>[
          WmlSection(blocks: <WmlBlock>[WmlClone.block(original)]),
        ],
      );
      expect(
        () => WordSerializer().writeBytes(copied),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('missing or changed'),
          ),
        ),
      );
    },
  );

  test('a reused URI with changed opaque payload bytes is rejected', () {
    final WmlDocument document = _fixture();
    document.package!
        .getPart('/payload/body.html')!
        .writeText('<p>Unrelated content</p>');
    expect(
      () => WordSerializer().writeBytes(document),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('missing or changed'),
        ),
      ),
    );
  });

  test('a changed content-type override cannot hide behind a cached part', () {
    final WmlDocument document = _fixture();
    document.package!.contentTypes.setOverride(
      '/payload/body.html',
      'text/plain',
    );
    expect(
      () => WordSerializer().writeBytes(document),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('missing or changed'),
        ),
      ),
    );
  });

  test(
    'missing source relationship fails at import instead of silently dropping content',
    () {
      final OpcPackage package = OpcPackage.openBytes(
        File('test/fixtures/fidelity/word-altchunk.docx').readAsBytesSync(),
      );
      package.relationshipsFor('/word/document.xml').removeById('chunk');
      expect(
        () => WordDeserializer().read(package),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('missing relationship'),
          ),
        ),
      );
    },
  );
}
