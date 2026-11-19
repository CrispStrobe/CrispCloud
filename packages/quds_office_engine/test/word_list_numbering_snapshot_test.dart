import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final existingDefinition in [false, true]) {
    test(
      'new numbering precedes cleanup metadata, existing $existingDefinition',
      () {
        final document = WmlDocument.empty();
        final package = document.package = OpcPackage.create(
          OpcPackageKind.word,
        );
        final definition = existingDefinition
            ? '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
                  '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
                  '<w:lvlText w:val="•"/></w:lvl></w:abstractNum>'
                  '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>'
            : '';
        package.createPart(
          '/word/numbering.xml',
          OfficeContentTypes.wordNumbering,
          utf8.encode(
            '<w:numbering xmlns:w="${OfficeNamespaces.w}">$definition'
            '<w:numIdMacAtCleanup w:val="99"/></w:numbering>',
          ),
        );
        package
            .relationshipsFor('/word/document.xml')
            .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
        WordLists.numberingId(document, numbered: true, independent: true);
        final root = XmlDocument.parse(
          package.getPart('/word/numbering.xml')!.readText(),
        ).root!;
        expect(
          root.childElements.map((element) => element.localName),
          existingDefinition
              ? [
                  'abstractNum',
                  'abstractNum',
                  'num',
                  'num',
                  'numIdMacAtCleanup',
                ]
              : ['abstractNum', 'num', 'numIdMacAtCleanup'],
        );
        expect(root.firstChild('numIdMacAtCleanup')!.getAttribute('val'), '99');
      },
    );
  }

  test('independent lists share definitions while isolating counters', () {
    final document = WmlDocument.empty();
    final shared = WordLists.numberingId(document, numbered: true);
    final first = WordLists.numberingId(
      document,
      numbered: true,
      independent: true,
    );
    final second = WordLists.numberingId(
      document,
      numbered: true,
      independent: true,
    );
    expect({shared, first, second}, hasLength(3));
    expect(WordLists.numberingId(document, numbered: true), shared);
    final root = XmlDocument.parse(
      document.package!.getPart('/word/numbering.xml')!.readText(),
    ).root!;
    expect(root.childrenNamed('abstractNum'), hasLength(2));
    expect(root.childrenNamed('num'), hasLength(3));
  });

  test(
    'absent numbering restore preserves media and unrelated relationships',
    () {
      final document = WmlDocument.empty();
      final before = WordListNumberingSnapshot.capture(document);
      WordLists.numberingId(document, numbered: true, independent: true);
      final after = WordListNumberingSnapshot.capture(document);
      final package = document.package!;
      final relationships = package.relationshipsFor('/word/document.xml');
      final previousId = relationships
          .firstByType(RelationshipTypes.numbering)!
          .id;
      final expectedNumbering = package
          .getPart('/word/numbering.xml')!
          .readText();
      package.createPart('/word/media/test.bin', 'application/octet-stream', [
        1,
        2,
        3,
      ]);
      final image = relationships.add(
        type: RelationshipTypes.image,
        target: 'media/test.bin',
      );
      before.restore(document);
      expect(package.getPart('/word/numbering.xml'), isNull);
      expect(
        package.contentTypes.overrides.containsKey('/word/numbering.xml'),
        isFalse,
      );
      expect(relationships.firstByType(RelationshipTypes.numbering), isNull);
      expect(relationships.byId(image.id), same(image));
      final occupied = relationships.add(
        type: RelationshipTypes.hyperlink,
        target: 'https://example.org',
        targetMode: RelationshipTargetMode.external,
        id: previousId,
      );
      after.restore(document);
      expect(
        package.getPart('/word/numbering.xml')!.readText(),
        expectedNumbering,
      );
      expect(
        relationships.firstByType(RelationshipTypes.numbering)!.id,
        isNot(previousId),
      );
      expect(relationships.byId(previousId), same(occupied));
      expect(relationships.byId(image.id), same(image));
      expect(package.getPart('/word/media/test.bin')!.readBytes(), [1, 2, 3]);
      before.restore(document);
      expect(package.getPart('/word/numbering.xml'), isNull);
      expect(relationships.byId(previousId), same(occupied));
      expect(package.getPart('/word/media/test.bin')!.readBytes(), [1, 2, 3]);
    },
  );

  test('existing custom-path numbering bytes and override restore exactly', () {
    final document = WmlDocument.empty();
    final package = document.package = OpcPackage.create(OpcPackageKind.word);
    const uri = '/word/custom-lists.xml';
    const xml =
        '<w:numbering xmlns:w="${OfficeNamespaces.w}">'
        '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
        '<w:start w:val="7"/><w:numFmt w:val="upperRoman"/>'
        '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num></w:numbering>';
    package.createPart(uri, OfficeContentTypes.wordNumbering, utf8.encode(xml));
    final relationship = package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.numbering, target: 'custom-lists.xml');
    final before = WordListNumberingSnapshot.capture(document);
    final added = WordLists.numberingId(
      document,
      numbered: false,
      independent: true,
    );
    expect(added, isNot(1));
    final changed = package.getPart(uri)!.readText();
    expect(changed, isNot(xml));
    final after = WordListNumberingSnapshot.capture(document);
    before.restore(document);
    expect(package.getPart(uri)!.readText(), xml);
    expect(
      package.contentTypes.overrides[uri],
      OfficeContentTypes.wordNumbering,
    );
    expect(
      package
          .relationshipsFor('/word/document.xml')
          .firstByType(RelationshipTypes.numbering)!
          .id,
      relationship.id,
    );
    after.restore(document);
    expect(package.getPart(uri)!.readText(), changed);
    expect(package.getPart('/word/numbering.xml'), isNull);
  });
}
