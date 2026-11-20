import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'adding a language to styleless imports preserves the kerning fallback',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>AVATAR To</w:t></w:r></w:p></w:body></w:document>',
          );
      final doc = WordDeserializer().read(package);
      expect(
        doc.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .kerningHalfPoints,
        1,
      );
      doc.proofingLanguage = 'en-GB';
      final reread = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(
        reread.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .kerningHalfPoints,
        1,
      );
    },
  );

  test('inherited threshold stays sparse and direct edits survive save', () {
    final doc = WordDeserializer().readBytes(
      File(
        'test/fixtures/word-kerning/wl2-wrap-calibri-kern-1.docx',
      ).readAsBytesSync(),
    );
    final package = doc.package!;
    final part = package.getPart('/word/document.xml')!;
    part.writeText(part.readText().replaceAll('<w:kern w:val="1"/>', ''));
    final inherited = WordDeserializer().read(package);
    final props = inherited.paragraphs.first.inlines
        .whereType<WmlRun>()
        .first
        .properties;
    expect(props.kerningHalfPoints, 1);
    expect(WordSerializer().runPropertiesXml(props), isNot(contains('kern')));
    props.kerningHalfPoints = 28;
    expect(WordSerializer().runPropertiesXml(props), contains('w:kern'));
    final reread = WordDeserializer().readBytes(
      WordSerializer().writeBytes(inherited),
    );
    expect(
      reread.paragraphs.first.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .kerningHalfPoints,
      28,
    );
  });

  test('new documents retain explicit kerning across save and reopen', () {
    final doc = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'AVATAR To')]),
          ],
        ),
      ],
    );
    final reread = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(
      reread.paragraphs.first.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .kerningHalfPoints,
      1,
    );
  });

  test('native kerning thresholds resolve, clone, and round-trip sparsely', () {
    for (final threshold in [1, 28]) {
      final source = File(
        'test/fixtures/word-kerning/wl2-wrap-calibri-kern-$threshold.docx',
      );
      final document = WordDeserializer().readBytes(source.readAsBytesSync());
      final run = (document.sections.single.blocks.first as WmlParagraph)
          .inlines
          .whereType<WmlRun>()
          .first;
      expect(run.properties.kerningHalfPoints, threshold);
      expect(run.properties.copy().kerningHalfPoints, threshold);
      final output = WordSerializer().writeBytes(document);
      final reread = WordDeserializer().readBytes(output);
      final restored = (reread.sections.single.blocks.first as WmlParagraph)
          .inlines
          .whereType<WmlRun>()
          .first;
      expect(restored.properties.kerningHalfPoints, threshold);
    }
  });
}
