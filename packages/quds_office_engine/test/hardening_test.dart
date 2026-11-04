import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('mismatched XML tags throw XmlParseException', () {
    final XmlPullReader reader = XmlPullReader('<w:p><w:r></w:p>');
    expect(() {
      while (reader.next()) {}
    }, throwsA(isA<XmlParseException>()));
  });

  test('shapes Arabic with stacked tashkeel and Lam-Alef', () {
    final List<ShapedChar> shaped = ArabicShaper.shape('لَا');
    expect(shaped.any((ShapedChar s) => s.advanceFactor == 0), isTrue);
    expect(
      shaped.any(
        (ShapedChar s) => s.codePoint == 0xFEFB || s.codePoint == 0xFEFC,
      ),
      isTrue,
    );
    final BidiParagraph bidi = Uax9Bidi.reorder('Hello لَا world');
    expect(bidi.runs.any((BidiRun r) => r.isRtl), isTrue);
    final List<GraphemeCluster> clusters = GraphemeClusters.segment('لَا');
    expect(clusters.first.text, 'لَ');
  });

  test('deep OLE nesting: sheet inside word packed as oleObject.bin', () {
    final IsolatedEmbeddedPackage sheet = EmbeddedPart.create(
      OpcPackageKind.sheet,
    );
    final IsolatedEmbeddedPackage inner = IsolatedEmbeddedPackage(
      kind: OpcPackageKind.word,
      package: WordSerializer().write(WmlDocument.empty(text: 'inner')),
    );
    final Uint8List innerBin = inner.pack();
    expect(CfbfFile.isCfbf(innerBin), isTrue);
    expect(EmbeddedPart.unpack(innerBin).kind, OpcPackageKind.word);

    final WmlDocument outer = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(text: 'outer'),
                WmlObject(relationshipId: 'rId1', embedded: sheet),
              ],
            ),
          ],
        ),
      ],
    );
    final OpcPackage packed = WordSerializer().write(outer);
    expect(
      packed.partNames.any((String n) => n.contains('embeddings')),
      isTrue,
    );
    final Uint8List docx = packed.save();
    final WmlDocument opened = WordDeserializer().readBytes(docx);
    expect(opened.paragraphs.first.text, contains('outer'));
    final WmlObject ole = opened.paragraphs.first.inlines
        .whereType<WmlObject>()
        .single;
    expect(ole.embedded, isNotNull);
    expect(ole.embedded!.kind, OpcPackageKind.sheet);
    expect(
      ole.embedded!.package.getPart('/xl/worksheets/sheet1.xml'),
      isNotNull,
    );
    final OpcPackage reopened = OpcPackage.openBytes(docx);
    expect(
      reopened.partNames.any((String n) => n.contains('embeddings')),
      isTrue,
    );
  });
}
