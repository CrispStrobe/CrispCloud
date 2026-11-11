import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument importedLists() {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Imported bullet</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>Imported roman</w:t></w:r></w:p>
<w:p><w:r><w:t>New list</w:t></w:r></w:p></w:body></w:document>''');
  package.createPart(
    '/word/numbering.xml',
    OfficeContentTypes.wordNumbering,
    utf8.encode('''<w:numbering xmlns:w="${OfficeNamespaces.w}">
<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="◆"/></w:lvl></w:abstractNum>
<w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:start w:val="7"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num></w:numbering>'''),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
  return WordDeserializer().read(package);
}

void main() {
  for (final (String, int, String) sample in <(String, int, String)>[
    ('lowerRoman', 14, 'xiv. '),
    ('upperLetter', 27, 'AA. '),
    ('lowerLetter', 52, 'az. '),
    ('decimalZero', 3, '03. '),
    ('decimal', 0, '0. '),
  ]) {
    test('imported ${sample.$1} numbering honors start ${sample.$2}', () {
      final WmlDocument doc = importedLists();
      final part = doc.package!.getPart('/word/numbering.xml')!;
      part.writeText(
        part
            .readText()
            .replaceAll('upperRoman', sample.$1)
            .replaceAll('w:val="7"', 'w:val="${sample.$2}"'),
      );
      final WmlDocument reopened = WordDeserializer().read(doc.package!);
      expect(reopened.paragraphs.elementAt(1).properties.listLabel, sample.$3);
    });
  }
  for (final bool numbered in <bool>[false, true]) {
    test(
      'new ${numbered ? 'numbered' : 'bullet'} list avoids imported IDs',
      () async {
        WmlDocument doc = importedLists();
        final List<String?> original = doc.paragraphs
            .take(2)
            .map((WmlParagraph p) => p.properties.listLabel)
            .toList();
        expect(original, <String>['◆ ', 'VII. ']);
        WordLists.applyLevel(
          doc.paragraphs.last,
          numbered: numbered,
          document: doc,
        );
        final int id = doc.paragraphs.last.properties.numId!;
        expect(id, greaterThan(2));
        for (var cycle = 0; cycle < 3; cycle++) {
          doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
          expect(
            doc.paragraphs
                .take(2)
                .map((WmlParagraph p) => p.properties.listLabel),
            original,
          );
          expect(
            doc.paragraphs.last.properties.listLabel,
            numbered ? '1. ' : '• ',
          );
          expect(WordLists.numberingId(doc, numbered: numbered), id);
          WordLists.changeLevel(doc.paragraphs.last, 1);
          expect(doc.paragraphs.last.properties.numId, id);
          WordLists.changeLevel(doc.paragraphs.last, -1);
        }
      },
    );
  }
  test('generated list kinds use separate IDs and reuse definitions', () {
    final WmlDocument doc = importedLists();
    final int numbers = WordLists.numberingId(doc, numbered: true);
    final int bullets = WordLists.numberingId(doc, numbered: false);
    expect(numbers, isNot(bullets));
    for (var i = 0; i < 10; i++) {
      expect(WordLists.numberingId(doc, numbered: true), numbers);
      expect(WordLists.numberingId(doc, numbered: false), bullets);
    }
    final XmlElement root = XmlDocument.parse(
      doc.package!.getPart('/word/numbering.xml')!.readText(),
    ).root!;
    expect(root.childrenNamed('num'), hasLength(4));
    expect(root.childrenNamed('abstractNum'), hasLength(4));
  });
}
