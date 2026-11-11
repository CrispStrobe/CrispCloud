import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _fixture() {
  final OpcPackage package = OpcPackage.openBytes(
    File('test/fixtures/fidelity/word-compatibility.docx').readAsBytesSync(),
  );
  // A second, independently authored history ID must stay reserved even when
  // the new clone is serialized before it. The original first history uses 7.
  final PackagePart main = package.getPart('/word/document.xml')!;
  main.writeText(
    main.readText().replaceFirst(
      '</n:sectPr>',
      '<n:sectPrChange n:id="1" n:author="Second history" n:date="2026-01-02T00:00:00Z">'
          '<n:sectPr><n:pgNumType n:start="12"/></n:sectPr>'
          '</n:sectPrChange></n:sectPr>',
    ),
  );
  return WordDeserializer().read(package);
}

List<XmlElement> _sections(Uint8List bytes) {
  final XmlElement body = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
  ).root!.firstChild('body')!;
  return <XmlElement>[
    for (final XmlElement child in body.childElements)
      if (child.localName == 'sectPr')
        child
      else if (child.localName == 'p' &&
          child.firstChild('pPr')?.firstChild('sectPr') != null)
        child.firstChild('pPr')!.firstChild('sectPr')!,
  ];
}

List<String> _ids(Uint8List bytes) => <String>[
  for (final XmlElement section in _sections(bytes))
    section.firstChild('sectPrChange')!.getAttribute('id')!,
];

void main() {
  test(
    'cloned section histories receive distinct stable IDs over three saves',
    () async {
      WmlDocument document = _fixture();
      final WmlSection original = document.sections.first;
      final WmlSection clone = WmlClone.section(original)
        ..blocks = <WmlBlock>[
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Cloned section')]),
        ]
        ..breakKind = WmlSectionBreakKind.nextPage;
      document.sections.insert(1, clone);
      expect(clone.sourceProperties, same(original.sourceProperties));
      for (int cycle = 1; cycle <= 3; cycle++) {
        final Uint8List bytes = await OfficeIsolateSave.word(document);
        expect(_ids(bytes), <String>['7', '2', '1']);
        final List<XmlElement> sections = _sections(bytes);
        expect(sections[1].firstChild('type')!.getAttribute('val'), 'nextPage');
        for (final XmlElement section in sections.take(2)) {
          final XmlElement history = section.firstChild('sectPrChange')!;
          expect(history.getAttribute('author'), 'Independent Fixture');
          expect(
            history
                .firstChild('sectPr')!
                .firstChild('pgNumType')!
                .getAttribute('start'),
            '99',
          );
          expect(section.firstChild('pgNumType')!.getAttribute('start'), '17');
          expect(
            section.firstChild('docGrid')!.getAttribute('linePitch'),
            '360',
          );
        }
        final File output = File(
          'build/fidelity-section-clones/section-clone-$cycle.docx',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'repeated synchronous saves do not consume or mutate source history IDs',
    () {
      final WmlDocument document = _fixture();
      final WmlSection clone = WmlClone.section(document.sections.first)
        ..blocks = <WmlBlock>[
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Clone')]),
        ];
      document.sections.insert(1, clone);
      final String snapshot = clone.sourceProperties!.xml;
      final WordSerializer serializer = WordSerializer();
      expect(_ids(serializer.writeBytes(document)), <String>['7', '2', '1']);
      expect(_ids(serializer.writeBytes(document)), <String>['7', '2', '1']);
      expect(clone.sourceProperties!.xml, snapshot);
    },
  );
}
