import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'styles and the default tab interval survive a Word template save',
    () async {
      final package = OpcPackage.empty();
      package.packageRelationships.add(
        type: RelationshipTypes.officeDocument,
        target: 'word/document.xml',
      );
      package
          .createPart('/word/document.xml', OfficeContentTypes.wordTemplate)
          .writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
  <w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr>
    <w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r>
  </w:p>
</w:body></w:document>
''');
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      package
          .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
          .writeText('''
<x:styles xmlns:x="${OfficeNamespaces.w}" xmlns:ext="urn:test">
  <x:style x:type="paragraph" x:styleId="Base">
    <x:name x:val="Base"/>
    <x:pPr><x:tabs><x:tab x:val="right" x:pos="1000"/></x:tabs>
      <x:ind x:left="200" x:hanging="160"/>
    </x:pPr>
  </x:style>
  <x:style x:type="paragraph" x:styleId="Child">
    <x:name x:val="Child"/><x:basedOn x:val="Base"/>
    <x:pPr><x:ind x:right="90" ext:keep="yes"/></x:pPr>
    <x:rPr><x:i/></x:rPr>
  </x:style>
</x:styles>
''');
      final model = WordDeserializer().read(package);
      final old = WordDeserializer().paragraphStyleProperties(model, 'Child')!;
      expect(old.tabs.single.position, 50);
      expect(old.indent.left, 10);
      final modification = WordHeadingIo.prepareStyleGeometry(
        model,
        'Child',
        indent: old.indent.copyWith(hanging: 0),
        tabs: const [],
      )!;
      modification.part.writeText(modification.after);
      WordDeserializer().refreshStyles(model);
      expect(model.paragraphs.single.properties.indent.hanging, 0);
      expect(model.paragraphs.single.properties.tabs, isEmpty);
      model.defaultTabStop = 54;
      final bytes = WordSerializer().writeBytes(model);
      final guard = await WordPackagePreservation.capture(
        bytes,
        'example.dotx',
      );
      expect(guard, isNotNull);
      final reopened = WordDeserializer().read(OfficeRepair.open(bytes));
      expect(reopened.defaultTabStop, 54);
      final properties = reopened.paragraphs.single.properties;
      expect(properties.indent.left, 10);
      expect(properties.indent.right, 4.5);
      expect(properties.indent.hanging, 0);
      expect(properties.tabs, isEmpty);
      expect(
        reopened.package!.getPart('/word/styles.xml')!.readText(),
        contains('ext:keep="yes"'),
      );
      final layout = WordLayoutEngine(font: null).layout(reopened);
      final glyphs = layout.pages.first.lines.first.glyphs;
      expect(
        glyphs.last.x,
        closeTo(reopened.sections.first.margins.left + 54, .01),
      );
    },
  );

  test(
    'opening publishes a stable first page and keeps final pagination',
    () async {
      WmlParagraph paragraph(String text) =>
          WmlParagraph(inlines: [WmlRun(text: text)]);
      final section = WmlSection(
        blocks: [for (var i = 0; i < 150; i++) paragraph('Body paragraph $i')],
      );
      final model = WmlDocument(sections: [section]);
      LaidOutDocument? first;
      final result = await WordLayoutEngine(font: null).layoutProgressively(
        model,
        onFirstPage: (page) => first = page,
        isCurrent: () => true,
      );
      final synchronous = WordLayoutEngine(font: null).layout(model);
      Iterable<Iterable<int>> indices(LaidOutDocument layout) => layout.pages
          .map((page) => page.lines.map((line) => line.paragraphIndex));
      expect(first?.isPreview, isTrue);
      expect(indices(first!).single, indices(synchronous).first);
      expect(indices(result), indices(synchronous));
      expect(result.supportsIncrementalReuse, isTrue);
      expect(result.pageIndexAtContentY(result.pageStackTop(2, 1.35), 1.35), 2);
    },
  );

  test('superseding a preview cancels the rest of pagination', () async {
    final model = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            for (var i = 0; i < 150; i++)
              WmlParagraph(inlines: [WmlRun(text: 'Line $i')]),
          ],
        ),
      ],
    );
    var current = true;
    await expectLater(
      WordLayoutEngine(font: null).layoutProgressively(
        model,
        onFirstPage: (_) => current = false,
        isCurrent: () => current,
      ),
      throwsStateError,
    );
  });
}
