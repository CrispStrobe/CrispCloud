import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source(String body) {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

List<XmlElement> _descendants(XmlElement node, String name) => <XmlElement>[
  for (final XmlElement child in node.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._descendants(child, name),
  ],
];

void _save(String name, Uint8List bytes) {
  final File file = File('build/fidelity-word-edits/$name.docx');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  test(
    'referenced built-ins and ancestors join an imported sparse style catalog',
    () async {
      final OpcPackage package = _source(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Changed heading</w:t></w:r></w:p>',
      );
      // Prefix aliases and an unrelated w binding ensure generated definitions
      // are self-contained, without rewriting any source style or namespace.
      package.createPart(
        '/word/styles.xml',
        OfficeContentTypes.wordStyles,
        utf8.encode(
          '<n:styles xmlns:n="${OfficeNamespaces.w}" xmlns:w="urn:source-extension">'
          '<n:style n:type="paragraph" n:styleId="Heading1">'
          '<n:name n:val="Source heading"/><n:aliases n:val="Outline one"/>'
          '<n:basedOn n:val="Normal"/><n:pPr><n:keepNext/>'
          '<n:outlineLvl n:val="0"/></n:pPr><n:rPr><n:color n:val="008844"/>'
          '</n:rPr></n:style>'
          '<n:style n:type="paragraph" n:styleId="Article">'
          '<n:name n:val="Article"/><n:basedOn n:val="Heading2"/></n:style>'
          '</n:styles>',
        ),
      );
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      WmlDocument document = WordDeserializer().read(package);
      WordStyles.apply(
        document.paragraphs.first,
        'Heading3',
        document: document,
      );
      final WmlParagraph header = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: 'Header caption')],
      );
      WordStyles.apply(header, 'Caption', document: document);
      document.sections.first.header.add(header);
      final WmlParagraph note = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: 'Quoted note')],
      );
      WordStyles.apply(note, 'Quote', document: document);
      document.footnotes.add(
        WmlNote(id: 3, endnote: false, paragraphs: <WmlParagraph>[note]),
      );
      document.paragraphs.first.inlines.add(WmlRun(text: '3', noteRefId: 3));
      for (int cycle = 1; cycle <= 3; cycle++) {
        final Uint8List bytes = await OfficeIsolateSave.word(document);
        final OpcPackage saved = OpcPackage.openBytes(bytes);
        final XmlElement root = XmlDocument.parse(
          saved.getPart('/word/styles.xml')!.readText(),
        ).root!;
        final Map<String, XmlElement> styles = <String, XmlElement>{
          for (final XmlElement style in root.childrenNamed('style'))
            style.getAttribute('styleId')!: style,
        };
        expect(
          styles.keys,
          containsAll(<String>[
            'Heading1',
            'Heading2',
            'Heading3',
            'Normal',
            'Article',
            'Caption',
            'Quote',
          ]),
        );
        expect(styles['Heading3']!.namespaceUri, OfficeNamespaces.w);
        expect(
          styles['Heading3']!
              .firstChild('pPr')!
              .firstChild('outlineLvl')!
              .getAttribute('val'),
          '2',
        );
        expect(
          styles['Heading1']!.firstChild('aliases')!.getAttribute('val'),
          'Outline one',
        );
        expect(
          styles['Heading1']!.firstChild('pPr')!.firstChild('keepNext'),
          isNotNull,
        );
        expect(
          styles['Heading1']!
              .firstChild('rPr')!
              .firstChild('color')!
              .getAttribute('val'),
          '008844',
        );
        expect(root.getAttribute('w'), 'urn:source-extension');
        _save('styles-$cycle', bytes);
        document = WordDeserializer().read(saved);
        expect(document.paragraphs.first.properties.styleId, 'Heading3');
        expect(document.paragraphs.first.properties.headingLevel, 3);
        expect(
          document.sections.first.header.single.properties.styleId,
          'Caption',
        );
        expect(
          document.footnotes.single.paragraphs.single.properties.styleId,
          'Quote',
        );
      }
    },
  );

  test(
    'line feeds become Word breaks and imported break types survive three saves',
    () async {
      WmlDocument document = WordDeserializer().read(
        _source(
          '<w:p><w:r><w:rPr><w:color w:val="884422"/></w:rPr>'
          '<w:t>Original</w:t><w:br/><w:t>line</w:t><w:cr/><w:tab/>'
          '<w:t>end</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Before page</w:t><w:br w:type="page"/>'
          '<w:t>After page</w:t><w:br w:type="column"/>'
          '<w:t>After column</w:t></w:r></w:p>',
        ),
      );
      expect(document.paragraphs.first.text, 'Original\nline\n\tend');
      document.paragraphs.first.inlines.whereType<WmlRun>().first
        ..text = '\nFirst\tline\r\nSecond\rThird\n'
        ..commentIds.add(5);
      document.sections.first.header.add(
        WmlParagraph(
          inlines: <WmlInline>[WmlRun(text: 'Header1\nHeader2\tHeader3')],
        ),
      );
      document.footnotes.add(
        WmlNote(
          id: 3,
          endnote: false,
          paragraphs: <WmlParagraph>[
            WmlParagraph(
              inlines: <WmlInline>[WmlRun(text: 'Note1\rNote2\nNote3')],
            ),
          ],
        ),
      );
      document.paragraphs.first.inlines.add(WmlRun(text: '3', noteRefId: 3));
      document.comments.add(
        WmlComment(id: 5, author: 'Fixture', text: 'Comment1\r\nComment2'),
      );
      for (int cycle = 1; cycle <= 3; cycle++) {
        final Uint8List bytes = await OfficeIsolateSave.word(document);
        final OpcPackage saved = OpcPackage.openBytes(bytes);
        final XmlElement body = XmlDocument.parse(
          saved.getPart('/word/document.xml')!.readText(),
        ).root!.firstChild('body')!;
        final XmlElement first = body.childrenNamed('p').first;
        expect(_descendants(first, 'br'), hasLength(4));
        expect(_descendants(first, 'tab'), hasLength(1));
        for (final XmlElement text in _descendants(first, 't')) {
          expect(text.text.contains(RegExp(r'[\r\n\t]')), isFalse);
        }
        final XmlElement notes = XmlDocument.parse(
          saved.getPart('/word/footnotes.xml')!.readText(),
        ).root!;
        expect(_descendants(notes, 'br'), hasLength(2));
        final XmlElement comments = XmlDocument.parse(
          saved.getPart('/word/comments.xml')!.readText(),
        ).root!;
        expect(_descendants(comments, 'br'), hasLength(1));
        _save('breaks-$cycle', bytes);
        document = WordDeserializer().read(saved);
        final WmlRun run = document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first;
        expect(run.text, '\nFirst\tline\nSecond\nThird\n');
        expect(run.properties.color, '884422');
        expect(
          document.paragraphs
              .elementAt(1)
              .inlines
              .whereType<WmlBreak>()
              .map((WmlBreak b) => b.type),
          <WmlBreakType>[WmlBreakType.page, WmlBreakType.column],
        );
        expect(
          document.sections.first.header.single.text,
          'Header1\nHeader2\tHeader3',
        );
        expect(document.footnotes.single.text, 'Note1\nNote2\nNote3');
        expect(document.comments.single.text, 'Comment1\nComment2');
      }
    },
  );
}
