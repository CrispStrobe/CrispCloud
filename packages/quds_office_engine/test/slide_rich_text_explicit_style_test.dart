import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

PmlPresentation _deck() {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.slide);
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
        '<p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="Text"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
        '<a:off x="381000" y="508000"/><a:ext cx="3810000" cy="1270000"/>'
        '</a:xfrm><a:noFill/></p:spPr><p:txBody><a:bodyPr/><a:p>'
        '<a:r><a:rPr b="0" i="0"/><a:t>Plain </a:t></a:r>'
        '<a:r><a:rPr b="1" i="0"/><a:t>Bold </a:t></a:r>'
        '<a:r><a:rPr b="0" i="1"/><a:t>Italic </a:t></a:r>'
        '<a:r><a:t>Fallback</a:t></a:r>'
        '<a:endParaRPr b="1" i="1"/></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:sld>',
      );
  return SlideDeserializer().read(package);
}

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final XmlElement child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

void main() {
  test(
    'explicit plain run styles survive paragraph defaults and PPTX saves',
    () {
      PmlPresentation deck = _deck();
      for (int cycle = 0; cycle < 2; cycle++) {
        final PmlShape shape = deck.slides.single.shapes.single;
        final String sourceXml = shape.textSource!.xml;
        final PmlTextParagraph paragraph = shape.richText.single;
        expect(paragraph.defaultBold, isTrue);
        expect(paragraph.defaultItalic, isTrue);
        expect(paragraph.runs.map((PmlTextRun run) => run.bold), <bool>[
          false,
          true,
          false,
          true,
        ]);
        expect(paragraph.runs.map((PmlTextRun run) => run.italic), <bool>[
          false,
          false,
          true,
          true,
        ]);

        final bytes = SlideSerializer().writeBytes(deck);
        expect(shape.textSource!.xml, sourceXml);
        final XmlElement saved = XmlDocument.parse(
          OpcPackage.openBytes(
            bytes,
          ).getPart('/ppt/slides/slide1.xml')!.readText(),
        ).root!;
        final List<XmlElement> runs = _descendants(saved, 'r').toList();
        expect(
          runs.map(
            (XmlElement run) => run.firstChild('rPr')?.getAttribute('b'),
          ),
          <String?>['0', '1', '0', null],
        );
        expect(
          runs.map(
            (XmlElement run) => run.firstChild('rPr')?.getAttribute('i'),
          ),
          <String?>['0', '0', '1', null],
        );
        deck = SlideDeserializer().readBytes(bytes);
      }
    },
  );
}
