import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _commentStyles() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:commentRangeStart w:id="0"/><w:r><w:t>Body</w:t></w:r><w:commentRangeEnd w:id="0"/><w:r><w:commentReference w:id="0"/></w:r></w:p>
<w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE"/><w:noProof/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="CommentBase"><w:name w:val="Comment base"/><w:rPr><w:lang w:val="de-AT"/><w:noProof/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="CommentChild"><w:basedOn w:val="CommentBase"/></w:style>
<w:style w:type="character" w:styleId="CheckedCommentBase"><w:rPr><w:lang w:val="de-CH"/><w:noProof w:val="0"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="CheckedComment"><w:basedOn w:val="CheckedCommentBase"/></w:style>
</w:styles>''');
  package
      .createPart('/word/comments.xml', OfficeContentTypes.wordComments)
      .writeText('''
<w:comments xmlns:w="${OfficeNamespaces.w}"><w:comment w:id="0" w:author="Reviewer">
<w:p><w:r><w:t>Document default</w:t></w:r></w:p>
<w:p><w:pPr><w:rPr><w:lang w:val="de-AT"/></w:rPr></w:pPr><w:r><w:rPr><w:noProof w:val="0"/></w:rPr><w:t>Paragraph language</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="CommentChild"/></w:pPr>
<w:r><w:t>Paragraph style</w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="CheckedComment"/></w:rPr><w:t>Character style</w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="CheckedComment"/><w:lang w:val="en-GB"/><w:noProof/></w:rPr><w:t>Direct override</w:t></w:r>
</w:p></w:comment></w:comments>''');
  package.relationshipsFor('/word/document.xml')
    ..add(type: RelationshipTypes.styles, target: 'styles.xml')
    ..add(type: RelationshipTypes.comments, target: 'comments.xml');
  return package;
}

void _check(WmlDocument document, {String defaultLanguage = 'de-DE'}) {
  expect(document.proofingLanguage, defaultLanguage);
  final paragraphs = document.comments.single.paragraphs;
  expect(paragraphs, hasLength(3));
  final plain = paragraphs[0].inlines.whereType<WmlRun>().single.properties;
  expect(plain.proofingLanguage, isNull);
  expect(plain.noProof, isTrue);
  expect(paragraphs[1].properties.proofingLanguage, 'de-AT');
  final paragraphDefault = paragraphs[1].inlines
      .whereType<WmlRun>()
      .single
      .properties;
  expect(paragraphDefault.proofingLanguage, isNull);
  expect(paragraphDefault.noProof, isFalse);
  final runs = paragraphs[2].inlines.whereType<WmlRun>().toList();
  expect(runs.map((run) => run.properties.proofingLanguage), [
    'de-AT',
    'de-CH',
    'en-GB',
  ]);
  expect(runs.map((run) => run.properties.noProof), [true, false, true]);
}

void main() {
  test(
    'comments inherit document, paragraph and character proofing settings on import',
    () {
      _check(WordDeserializer().read(_commentStyles()));
    },
  );

  test(
    'inherited and explicit comment proofing values survive three DOCX saves',
    () {
      var document = WordDeserializer().read(_commentStyles());
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        _check(document);
      }
    },
  );

  test(
    'document language changes remain live for comments without overrides',
    () {
      var document = WordDeserializer().read(_commentStyles());
      document.proofingLanguage = 'de-CH';
      WordDeserializer().refreshStyles(document);
      _check(document, defaultLanguage: 'de-CH');
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      _check(document, defaultLanguage: 'de-CH');
    },
  );

  test(
    'style refresh updates comments while retaining explicit run settings',
    () {
      final document = WordDeserializer().read(_commentStyles());
      final styles = document.package!.getPart('/word/styles.xml')!;
      styles.writeText(
        styles.readText().replaceFirst(
          '<w:lang w:val="de-CH"/><w:noProof w:val="0"/>',
          '<w:lang w:val="de-DE"/><w:noProof/>',
        ),
      );
      WordDeserializer().refreshStyles(document);
      void check(WmlDocument value) {
        final runs = value.comments.single.paragraphs[2].inlines
            .whereType<WmlRun>()
            .toList();
        expect(runs.map((run) => run.properties.proofingLanguage), [
          'de-AT',
          'de-DE',
          'en-GB',
        ]);
        expect(runs.map((run) => run.properties.noProof), [true, true, true]);
      }

      check(document);
      check(
        WordDeserializer().readBytes(WordSerializer().writeBytes(document)),
      );
    },
  );
}
