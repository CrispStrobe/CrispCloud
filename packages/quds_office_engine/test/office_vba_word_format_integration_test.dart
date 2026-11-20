import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: source,
  ),
);

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._elements(child, name),
  ],
];

void main() {
  test(
    'Word underline/strike/indent/pagination save with exact native units',
    () async {
      final bytes = (DocxDocumentBuilder()..paragraph('Preserve this text'))
          .build();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      final plan = _compile('''
Sub Main()
    With ThisDocument.Paragraphs(1).Range
        .Font.Underline = wdUnderlineDotDashHeavy
        .Font.StrikeThrough = True
        With .ParagraphFormat
            .LeftIndent = -2.5
            .RightIndent = 18.25
            .FirstLineIndent = -12.5
            .KeepTogether = True
            .PageBreakBefore = True
        End With
    End With
End Sub
''');
      await session.validate(plan);
      expect(session.bytes, bytes);
      await session.run(plan);
      final paragraph = WordDeserializer()
          .readBytes(session.bytes)
          .paragraphs
          .single;
      expect(paragraph.text, 'Preserve this text');
      expect(paragraph.properties.indent.left, -2.5);
      expect(paragraph.properties.indent.right, 18.25);
      expect(paragraph.properties.indent.hanging, 12.5);
      expect(paragraph.properties.indent.firstLine, 0);
      expect(paragraph.properties.keepTogether, isTrue);
      expect(paragraph.properties.pageBreakBefore, isTrue);
      final root = XmlDocument.parse(
        OpcPackage.openBytes(
          session.bytes,
        ).getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(
        _elements(
          root,
          'u',
        ).single.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        'dashDotHeavy',
      );
      final indent = _elements(root, 'ind').single;
      expect(
        indent.getAttribute('left', namespaceUri: OfficeNamespaces.w),
        '-50',
      );
      expect(
        indent.getAttribute('right', namespaceUri: OfficeNamespaces.w),
        '365',
      );
      expect(
        indent.getAttribute('hanging', namespaceUri: OfficeNamespaces.w),
        '250',
      );

      // Explicit false/none and a positive first line must remove the previous
      // inherited/direct effect, including the mutually exclusive hanging indent.
      await session.run(
        _compile('''
Sub Main()
    With ThisDocument.Paragraphs(1).Range
        .Font.Underline = wdUnderlineNone
        .Font.StrikeThrough = False
        .ParagraphFormat.FirstLineIndent = 18
        .ParagraphFormat.KeepTogether = False
        .ParagraphFormat.PageBreakBefore = False
    End With
End Sub
'''),
      );
      final reset = WordDeserializer()
          .readBytes(session.bytes)
          .paragraphs
          .single;
      expect(reset.text, 'Preserve this text');
      expect(reset.properties.indent.firstLine, 18);
      expect(reset.properties.indent.hanging, 0);
      expect(reset.properties.keepTogether, isFalse);
      expect(reset.properties.pageBreakBefore, isFalse);
      for (final run in reset.inlines.whereType<WmlRun>()) {
        expect(run.properties.underline, WmlUnderline.none);
        expect(run.properties.strike, isFalse);
      }
    },
  );

  test(
    'new Word formatting is rolled back when a later paragraph is absent',
    () async {
      final bytes = (DocxDocumentBuilder()..paragraph('Original')).build();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      final plan = _compile('''
Sub Main()
    ThisDocument.Paragraphs(1).Range.Font.Underline = wdUnderlineDouble
    ThisDocument.Paragraphs(99).Range.ParagraphFormat.FirstLineIndent = -12
End Sub
''');
      final failure = isA<OfficeMacroException>().having(
        (error) => error.stepIndex,
        'step',
        1,
      );
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
    },
  );
}
