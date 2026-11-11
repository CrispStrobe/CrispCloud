import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _package() => OpcPackage.openBytes(
  File('test/fixtures/fidelity/comment-threads.docx').readAsBytesSync(),
);

XmlElement _body(OpcPackage package) => XmlDocument.parse(
  package.getPart('/custom/document-main.xml')!.readText(),
).root!.firstChild('body')!;

void _expectNoDirectFormatting(XmlElement paragraph) {
  expect(paragraph.firstChild('pPr')?.childElements ?? <XmlElement>[], isEmpty);
  for (final run in paragraph.childrenNamed('r')) {
    expect(run.firstChild('rPr')?.childElements ?? <XmlElement>[], isEmpty);
  }
}

void main() {
  test(
    'missing styles and direct properties remain absent after unrelated edits',
    () async {
      WmlDocument document = WordDeserializer().read(_package());
      expect(document.paragraphs.first.properties.spacingAfter, 0);
      expect(document.paragraphs.first.properties.lineSpacing, 1);
      document.comments.first.resolved = true;
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = OpcPackage.openBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(
          saved
              .relationshipsFor('/custom/document-main.xml')
              .firstByType(RelationshipTypes.styles),
          isNull,
        );
        expect(saved.getPart('/custom/styles.xml'), isNull);
        for (final paragraph in _body(saved).childrenNamed('p')) {
          _expectNoDirectFormatting(paragraph);
        }
        document = WordDeserializer().read(saved);
      }
    },
  );

  test(
    'deliberate formatting writes without introducing unrelated defaults',
    () {
      final document = WordDeserializer().read(_package());
      final paragraph = document.paragraphs.first;
      paragraph.properties.spacingAfter = 12;
      paragraph.inlines.whereType<WmlRun>().first.properties
        ..bold = true
        ..color = '112233';
      final saved = WordSerializer().write(document);
      final paragraphs = _body(saved).childrenNamed('p');
      expect(
        paragraphs.first
            .firstChild('pPr')!
            .firstChild('spacing')!
            .getAttribute('after'),
        '240',
      );
      final props = paragraphs.first
          .childrenNamed('r')
          .first
          .firstChild('rPr')!;
      expect(props.firstChild('b')!.getAttribute('val'), '1');
      expect(props.firstChild('color')!.getAttribute('val'), '112233');
      _expectNoDirectFormatting(paragraphs.last);
      expect(saved.getPart('/custom/styles.xml'), isNull);
      final reopened = WordDeserializer().readBytes(saved.save());
      expect(reopened.paragraphs.first.properties.spacingAfter, 12);
      expect(
        reopened.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .bold,
        isTrue,
      );
    },
  );

  test(
    'an empty imported style catalog does not acquire the global Normal defaults',
    () {
      final package = _package();
      package
          .createPart('/custom/styles.xml', OfficeContentTypes.wordStyles)
          .writeText('<w:styles xmlns:w="${OfficeNamespaces.w}"/>');
      package
          .relationshipsFor('/custom/document-main.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      final document = WordDeserializer().read(package);
      final saved = WordSerializer().write(document);
      final styles = XmlDocument.parse(
        saved.getPart('/custom/styles.xml')!.readText(),
      ).root!;
      expect(styles.childrenNamed('style'), isEmpty);
      expect(styles.firstChild('docDefaults'), isNull);
      for (final paragraph in _body(saved).childrenNamed('p')) {
        _expectNoDirectFormatting(paragraph);
      }
    },
  );

  test(
    'explicit missing Heading1 still resolves and exports only the referenced style',
    () {
      final package = _package();
      final main = package.getPart('/custom/document-main.xml')!;
      main.writeText(
        main.readText().replaceFirst(
          '<w:p>',
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>',
        ),
      );
      final document = WordDeserializer().read(package);
      expect(document.paragraphs.first.properties.headingLevel, 1);
      expect(
        document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .fontSizePoints,
        16,
      );
      final saved = WordSerializer().write(document);
      final styles = XmlDocument.parse(
        saved.getPart('/custom/styles.xml')!.readText(),
      ).root!;
      expect(
        styles
            .childrenNamed('style')
            .map((style) => style.getAttribute('styleId')),
        <String>['Heading1'],
      );
      expect(styles.firstChild('docDefaults'), isNull);
      _expectNoDirectFormatting(_body(saved).childrenNamed('p').last);
    },
  );

  test('new documents retain their intentional default style catalog', () {
    final document = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'New document')]),
          ],
        ),
      ],
    );
    final saved = WordSerializer().write(document);
    final styles = XmlDocument.parse(
      saved.getPart('/word/styles.xml')!.readText(),
    ).root!;
    expect(
      styles
          .childrenNamed('style')
          .map((style) => style.getAttribute('styleId')),
      contains('Normal'),
    );
    expect(styles.firstChild('docDefaults'), isNotNull);
  });
}
