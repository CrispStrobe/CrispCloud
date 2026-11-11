import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'unmodeled body XML and its relationship survive edits copies and saves',
    () async {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText(
        '''<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}"><w:body><w:p><w:r><w:t>Before</w:t></w:r></w:p><w:altChunk r:id="chunk"><w:altChunkPr><w:matchSrc w:val="0"/></w:altChunkPr></w:altChunk><w:p><w:r><w:t>After</w:t></w:r></w:p><w:sectPr/></w:body></w:document>''',
      );
      final html = utf8.encode(
        '<html><body><p>Imported HTML payload</p></body></html>',
      );
      package.createPart('/word/embedded.html', 'text/html', html);
      package
          .relationshipsFor('/word/document.xml')
          .add(
            id: 'chunk',
            type: '${OfficeNamespaces.r}/aFChunk',
            target: 'embedded.html',
          );
      var doc = WordDeserializer().read(package);
      expect(doc.sections.first.blocks.map((b) => b.runtimeType), [
        WmlParagraph,
        WmlOpaqueBlock,
        WmlParagraph,
      ]);
      doc.sections.first.blocks = doc.sections.first.blocks
          .map(WmlClone.block)
          .toList();
      doc.paragraphs.first.inlines.whereType<WmlRun>().first.text =
          'Edited before';
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        Directory('build/fidelity-opaque').createSync(recursive: true);
        File(
          'build/fidelity-opaque/opaque-$cycle.docx',
        ).writeAsBytesSync(bytes);
        doc = WordDeserializer().readBytes(bytes);
        expect(doc.paragraphs.map((p) => p.text), ['Edited before', 'After']);
        final opaque = doc.sections.first.blocks[1] as WmlOpaqueBlock;
        final element = XmlDocument.parse(opaque.xml).root!;
        expect(element.localName, 'altChunk');
        expect(element.getAttribute('id'), 'chunk');
        expect(
          element
              .firstChild('altChunkPr')!
              .firstChild('matchSrc')!
              .getAttribute('val'),
          '0',
        );
        expect(doc.package!.getPart('/word/embedded.html')!.readBytes(), html);
        expect(
          doc.package!
              .relationshipsFor('/word/document.xml')
              .byId('chunk')!
              .target,
          'embedded.html',
        );
      }
    },
  );
}
