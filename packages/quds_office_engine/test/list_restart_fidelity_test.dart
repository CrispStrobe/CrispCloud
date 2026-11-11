import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _listDocument() {
  final document = WmlDocument.empty(text: 'One');
  document.sections.first.blocks.addAll([
    for (final text in ['Two', 'Three', 'Four', 'Five', 'Six'])
      WmlParagraph(inlines: [WmlRun(text: text)]),
  ]);
  for (final paragraph in document.paragraphs) {
    WordLists.applyLevel(paragraph, numbered: true, document: document);
  }
  return document;
}

List<String?> _labels(WmlDocument document) => [
  for (final paragraph in document.paragraphs) paragraph.properties.listLabel,
];

XmlElement _numbering(WmlDocument document) => XmlDocument.parse(
  document.package!.getPart('/word/numbering.xml')!.readText(),
).root!;

void main() {
  test('label recomputation retains restart intent and is repeatable', () {
    final document = _listDocument();
    WordLists.restart(document.paragraphs.elementAt(2), at: 5);
    for (var pass = 0; pass < 3; pass++) {
      WordLists.resolveLabels(document.paragraphs);
      expect(_labels(document), ['1. ', '2. ', '5. ', '6. ', '7. ', '8. ']);
      expect(document.paragraphs.elementAt(2).properties.listRestart, 5);
    }
  });

  test(
    'restart and continuation survive three asynchronous save cycles',
    () async {
      var document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(_listDocument()),
      );
      final originalIds = document.paragraphs
          .map((p) => p.properties.numId)
          .toList();
      WordLists.restart(document.paragraphs.elementAt(2), at: 5);
      WordLists.restart(document.paragraphs.elementAt(4), at: 5);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        if (cycle == 0) {
          // Serializing must not overwrite the model IDs used by undo snapshots.
          expect(
            document.paragraphs.map((p) => p.properties.numId),
            originalIds,
          );
          expect(document.paragraphs.elementAt(2).properties.listRestart, 5);
        }
        final file = File('build/fidelity-lists/restarted-$cycle.docx');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        document = WordDeserializer().readBytes(bytes);
        expect(_labels(document), ['1. ', '2. ', '5. ', '6. ', '5. ', '6. ']);
        final ids = document.paragraphs.map((p) => p.properties.numId).toList();
        expect(ids[0], ids[1]);
        expect(ids[2], ids[3]);
        expect(ids[4], ids[5]);
        expect({ids[0], ids[2], ids[4]}, hasLength(3));
        final restarted = _numbering(document)
            .childrenNamed('num')
            .where((node) => node.childrenNamed('lvlOverride').isNotEmpty);
        expect(restarted, hasLength(2));
        for (final node in restarted) {
          expect(node.firstChild('lvlOverride')!.getAttribute('ilvl'), '0');
          expect(
            node
                .firstChild('lvlOverride')!
                .firstChild('startOverride')!
                .getAttribute('val'),
            '5',
          );
        }
      }
    },
  );

  test(
    'repeated synchronous save reuses instances without consuming undo state',
    () {
      final document = _listDocument();
      final paragraph = document.paragraphs.elementAt(2);
      final before = paragraph.properties.copy();
      WordLists.restart(paragraph, at: 0);
      final after = paragraph.properties.copy();
      for (var cycle = 0; cycle < 3; cycle++) {
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(_labels(reopened), ['1. ', '2. ', '0. ', '1. ', '2. ', '3. ']);
        expect(_numbering(reopened).childrenNamed('num'), hasLength(3));
        expect(paragraph.properties.numId, before.numId);
        expect(paragraph.properties.listRestart, 0);
      }
      paragraph.properties = before.copy();
      expect(
        _labels(
          WordDeserializer().readBytes(WordSerializer().writeBytes(document)),
        ),
        ['1. ', '2. ', '3. ', '4. ', '5. ', '6. '],
      );
      paragraph.properties = after.copy();
      expect(
        _labels(
          WordDeserializer().readBytes(WordSerializer().writeBytes(document)),
        ),
        ['1. ', '2. ', '0. ', '1. ', '2. ', '3. '],
      );
    },
  );

  test(
    'nested restart preserves the current ancestor and later continuation',
    () async {
      var document = _listDocument();
      final paragraphs = document.paragraphs.toList();
      for (final index in [3, 4]) {
        WordLists.changeLevel(paragraphs[index], 1);
      }
      WordLists.restart(paragraphs[3], at: 5);
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(_labels(document), ['1. ', '2. ', '3. ', '3.5 ', '3.6 ', '4. ']);
      }
    },
  );

  test(
    'imported per-instance level overrides do not alter the abstract definition',
    () async {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
${[7, 8, 7, 8].map((id) => '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="$id"/></w:numPr></w:pPr><w:r><w:t>Item</w:t></w:r></w:p>').join()}
</w:body></w:document>''');
      package.createPart(
        '/word/numbering.xml',
        OfficeContentTypes.wordNumbering,
        utf8.encode('''
<w:numbering xmlns:w="${OfficeNamespaces.w}">
<w:abstractNum w:abstractNumId="4"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
<w:num w:numId="7"><w:abstractNumId w:val="4"/></w:num>
<w:num w:numId="8"><w:abstractNumId w:val="4"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="7"/><w:lvl w:ilvl="0"><w:start w:val="4"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1)"/></w:lvl></w:lvlOverride></w:num>
</w:numbering>'''),
      );
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
      var document = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_labels(document), ['1. ', 'VII) ', '2. ', 'VIII) ']);
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
      }
      expect(_labels(document), ['1. ', 'VII) ', '2. ', 'VIII) ']);
    },
  );
}
