import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _example = 'example/macros/word_report.bas';
const _reportSteps = 46;
const _reportText = <String>[
  'Weekly supply report',
  'Paper: 5',
  'Ink: 3',
  'Labels: 6',
  'Total units: 14',
  'Source values supplied by the macro. 😀',
];

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordReport',
    source: source,
  ),
);

Uint8List _template(List<String> paragraphs) {
  final builder = DocxDocumentBuilder();
  for (final text in paragraphs) {
    builder.paragraph(text);
  }
  return builder.build();
}

Uint8List _rawBody(String body) {
  // Retain ordinary application settings, including tracking disabled.
  final package = OpcPackage.openBytes(_template(<String>['Template']));
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr/></w:body></w:document>',
      );
  return package.save();
}

OfficeMacroSession _session(Uint8List bytes, {OfficeMacroPolicy? policy}) =>
    OfficeMacroSession(bytes, format: OfficeMacroFormat.docx, policy: policy);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

WmlDocument _read(OfficeMacroSession session) =>
    WordDeserializer().readBytes(session.bytes);

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String text) => <String, Object?>{
  'source': <String, Object?>{
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordReport',
    'source': text,
  },
};

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._elements(child, name),
  ],
];

XmlElement _documentXml(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
).root!;

void _expectReport(OfficeMacroSession session) {
  final paragraphs = _read(session).paragraphs.toList();
  expect(paragraphs.map((paragraph) => paragraph.text), _reportText);
  for (final (index, paragraph) in paragraphs.indexed) {
    final runs = paragraph.inlines.whereType<WmlRun>().where(
      (run) => run.text.isNotEmpty,
    );
    expect(runs, isNotEmpty);
    for (final run in runs) {
      expect(run.properties.asciiFont, 'Arial');
      expect(run.properties.fontSizeHalfPoints, index == 0 ? 36 : 22);
      expect(run.properties.bold, index == 0 || index == 4);
      expect(run.properties.italic, isFalse);
      if (index == 0) expect(run.properties.color, '1F4E79');
    }
    expect(paragraph.properties.spacingAfter, 6);
    expect(
      paragraph.properties.justification,
      index == 0 ? WmlJustification.center : WmlJustification.left,
    );
  }
  expect(paragraphs.first.properties.spacingBefore, 0);
  expect(
    paragraphs.last.text.codeUnits.sublist(paragraphs.last.text.length - 2),
    <int>[0xD83D, 0xDE00],
  );
}

Uint8List _nestedBody() {
  final document = WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[
          _paragraph('Body one'),
          WmlContentControlBlock(
            control: WmlContentControlData(
              xml:
                  '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
                  '<w:alias w:val="Body container"/></w:sdtPr>'
                  '<w:sdtContent/></w:sdt>',
              sourcePartUri: '/word/document.xml',
              relationships: const <WmlOpaqueRelationship>[],
            ),
            blocks: <WmlBlock>[
              WmlTable(
                rows: <WmlTableRow>[
                  WmlTableRow(
                    cells: <WmlTableCell>[
                      WmlTableCell(
                        blocks: <WmlBlock>[
                          _paragraph('Cell one'),
                          WmlTable(
                            rows: <WmlTableRow>[
                              WmlTableRow(
                                cells: <WmlTableCell>[
                                  WmlTableCell(
                                    blocks: <WmlBlock>[
                                      _paragraph('Nested cell'),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          _paragraph('Cell after nested table'),
                        ],
                      ),
                      WmlTableCell(blocks: <WmlBlock>[_paragraph('Cell two')]),
                    ],
                  ),
                ],
              ),
            ],
          ),
          WmlFrame(blocks: <WmlBlock>[_paragraph('Frame one')]),
          _paragraph('Body tail'),
        ],
        header: <WmlParagraph>[_paragraph('Header untouched')],
        footer: <WmlParagraph>[_paragraph('Footer untouched')],
      ),
      WmlSection(
        blocks: <WmlBlock>[_paragraph('Next section')],
        linkToPrevious: false,
      ),
    ],
    footnotes: <WmlNote>[
      WmlNote(
        id: 1,
        endnote: false,
        addReference: false,
        addReferenceSpace: false,
        paragraphs: <WmlParagraph>[_paragraph('Footnote untouched')],
      ),
    ],
    endnotes: <WmlNote>[
      WmlNote(
        id: 2,
        endnote: true,
        addReference: false,
        addReferenceSpace: false,
        paragraphs: <WmlParagraph>[_paragraph('Endnote untouched')],
      ),
    ],
    comments: <WmlComment>[WmlComment(id: 3, text: 'Comment untouched')],
  );
  return WordSerializer().writeBytes(document);
}

void main() {
  group('Word VBA plans through the document runtime', () {
    test('report validates, round-trips and publishes one revision', () async {
      final plan = _compile(File(_example).readAsStringSync());
      expect(plan.steps, hasLength(_reportSteps));
      expect(plan.format, OfficeMacroFormat.docx);
      expect(plan.steps.map((step) => step.tool).toSet(), <String>{
        'docx.replaceText',
        'docx.runFormat',
        'docx.paragraphFormat',
      });
      final saved = OfficeMacro.parse(plan.encode());
      expect(saved.toJson(), plan.toJson());
      final original = _template(List<String>.filled(6, ''));
      final session = _session(original);
      session.startRecording('Playback does not become a recorded call');
      final validation = await session.validate(saved);
      expect(validation.validatedOnly, isTrue);
      expect(validation.completedSteps, _reportSteps);
      expect(session.bytes, original);
      expect(session.revision, 0);
      final result = await session.run(saved);
      expect(result.completedSteps, _reportSteps);
      expect(result.validatedOnly, isFalse);
      expect(session.revision, 1);
      _expectReport(session);
      expect(session.stopRecording().steps, isEmpty);
    });

    test('range aliases prepend in native operation order', () async {
      final session = _session(_template(<String>['tail']));
      await session.run(
        _compile(r'''Sub Main()
  Dim original As Range, copyRange As Range
  Set original = ThisDocument.Paragraphs(1).Range
  Set copyRange = original
  original.InsertBefore "A"
  Call Prefix(copyRange, "B")
  copyRange.Font.Bold = True
End Sub
Sub Prefix(ByVal target As Range, ByVal text As String)
  Call target.InsertBefore(text)
End Sub'''),
      );
      final paragraph = _read(session).paragraphs.single;
      expect(paragraph.text, 'BAtail');
      expect(
        paragraph.inlines.whereType<WmlRun>().map((run) => run.properties.bold),
        everyElement(isTrue),
      );
    });

    test(
      'insertion and one font change preserve unrelated run properties',
      () async {
        final session = _session(
          _rawBody(
            '<w:p><w:r><w:rPr><w:i/><w:color w:val="127A43"/>'
            '<w:lang w:val="en-GB"/><w:rFonts w:ascii="Source Serif" '
            'w:cs="Noto Naskh Arabic"/></w:rPr><w:t>Alpha</w:t></w:r>'
            '<w:r><w:rPr><w:b/><w:u w:val="double"/>'
            '<w:color w:val="A03050"/></w:rPr><w:t>Beta</w:t></w:r></w:p>',
          ),
        );
        await session.run(
          _compile(r'''Sub Main()
  With ThisDocument.Paragraphs(1).Range
    .InsertBefore "Prefix: "
    .Font.Bold = False
  End With
End Sub'''),
        );
        final paragraph = _read(session).paragraphs.single;
        expect(paragraph.text, 'Prefix: AlphaBeta');
        for (final offset in <int>[0, 8]) {
          final properties = WmlRunEdit.propsAt(paragraph, offset);
          expect(properties.bold, isFalse);
          expect(properties.italic, isTrue);
          expect(properties.color, '127A43');
          expect(properties.proofingLanguage, 'en-GB');
          expect(properties.asciiFont, 'Source Serif');
          expect(properties.csFont, 'Noto Naskh Arabic');
        }
        final suffix = WmlRunEdit.propsAt(paragraph, 13);
        expect(suffix.bold, isFalse);
        expect(suffix.underline, WmlUnderline.double);
        expect(suffix.color, 'A03050');
      },
    );

    test(
      'body indices traverse containers and exclude auxiliary stories',
      () async {
        const expected = <String>[
          'Body one',
          'Cell one',
          'Nested cell',
          'Cell after nested table',
          'Cell two',
          'Frame one',
          'Body tail',
          'Next section',
        ];
        final session = _session(_nestedBody());
        expect(_read(session).paragraphs.map((p) => p.text), expected);
        final inspected = session.inspect()['paragraphs']! as List<Object?>;
        expect(
          inspected.map((value) => (value! as Map<String, Object?>)['text']),
          expected,
        );
        final plan = _compile(r'''Sub Main()
  Dim index As Long
  For index = 1 To 8
    ThisDocument.Paragraphs(index).Range.InsertBefore CStr(index) & ": "
  Next index
End Sub''');
        expect(
          plan.steps.map((step) => step.arguments['paragraph']),
          List<int>.generate(8, (index) => index),
        );
        expect(
          plan.steps.every((step) => !step.arguments.containsKey('story')),
          isTrue,
        );
        await session.run(plan);
        final saved = _read(session);
        expect(saved.paragraphs.map((paragraph) => paragraph.text), <String>[
          for (final (index, text) in expected.indexed) '${index + 1}: $text',
        ]);
        expect(saved.sections.first.header.single.text, 'Header untouched');
        expect(saved.sections.first.footer.single.text, 'Footer untouched');
        expect(saved.footnotes.single.text, 'Footnote untouched');
        expect(saved.endnotes.single.text, 'Endnote untouched');
        expect(saved.comments.single.text, 'Comment untouched');
        expect(
          WordTree.descendants(
            saved.sections.first.blocks,
          ).whereType<WmlContentControlBlock>().single.control.alias,
          'Body container',
        );
      },
    );

    test(
      'font and paragraph precision persists as exact native units',
      () async {
        final session = _session(_template(<String>['Precise formatting']));
        await session.run(
          _compile(r'''Sub Main()
  With ThisDocument.Paragraphs(1).Range
    .Font.Size = 10.5
    .Font.Name = "A&B <Sample>"
    .Font.Color = RGB(1, 2, 3)
    .ParagraphFormat.Alignment = wdAlignParagraphJustify
    .ParagraphFormat.SpaceBefore = 1.05
    .ParagraphFormat.SpaceAfter = 6.15
  End With
End Sub'''),
        );
        final paragraph = _read(session).paragraphs.single;
        final properties = WmlRunEdit.propsAt(paragraph, 0);
        expect(properties.fontSizeHalfPoints, 21);
        expect(properties.asciiFont, 'A&B <Sample>');
        expect(properties.color, '010203');
        expect(paragraph.properties.justification, WmlJustification.justify);
        expect(paragraph.properties.spacingBefore, 1.05);
        expect(paragraph.properties.spacingAfter, 6.15);
        final root = _documentXml(session.bytes);
        expect(_elements(root, 'sz').single.getAttribute('val'), '21');
        expect(_elements(root, 'spacing').single.getAttribute('before'), '21');
        expect(_elements(root, 'spacing').single.getAttribute('after'), '123');
        expect(_elements(root, 'jc').single.getAttribute('val'), 'both');
        expect(_elements(root, 'color').single.getAttribute('val'), '010203');
      },
    );

    test(
      'valid surrogate recombination and tabs survive native publication',
      () async {
        final source =
            'Sub Main()\n'
            '  Dim high As String, low As String\n'
            '  high = Left\$("😀", 1)\n'
            '  low = Right\$("😀", 1)\n'
            '  ThisDocument.Paragraphs(1).Range.InsertBefore '
            '"A\t" & high & low & "B"\n'
            'End Sub';
        final session = _session(_template(<String>['']));
        await session.run(_compile(source));
        expect(_read(session).paragraphs.single.text.codeUnits, <int>[
          65,
          9,
          0xD83D,
          0xDE00,
          66,
        ]);
      },
    );

    test(
      'late missing paragraph rolls back bytes, revision and recording',
      () async {
        final original = _template(<String>['Original']);
        final session = _session(original);
        session.startRecording('Unpublished Word source');
        final plan = _compile(r'''Sub Main()
  ThisDocument.Paragraphs(1).Range.InsertBefore "Pending: "
  ThisDocument.Paragraphs(2).Range.InsertBefore "Missing: "
End Sub''');
        final failure = _error('operation_failed')
            .having((error) => error.stepIndex, 'stepIndex', 1)
            .having((error) => error.tool, 'tool', 'docx.replaceText');
        for (final validate in <bool>[true, false]) {
          await expectLater(
            validate ? session.validate(plan) : session.run(plan),
            throwsA(failure),
          );
          expect(session.bytes, original);
          expect(session.revision, 0);
          expect(session.isRecording, isTrue);
        }
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'empty range formatting fails atomically; insertion then formatting succeeds',
      () async {
        final original = _template(<String>['']);
        final session = _session(original);
        final invalid = _compile(r'''Sub Main()
  With ThisDocument.Paragraphs(1).Range
    .ParagraphFormat.SpaceAfter = 6
    .InsertBefore ""
    .Font.Bold = True
  End With
End Sub''');
        await expectLater(
          session.run(invalid),
          throwsA(
            _error('operation_failed')
                .having((error) => error.stepIndex, 'stepIndex', 2)
                .having((error) => error.tool, 'tool', 'docx.runFormat'),
          ),
        );
        expect(session.bytes, original);
        expect(session.revision, 0);
        await session.run(
          _compile(r'''Sub Main()
  With ThisDocument.Paragraphs(1).Range
    .ParagraphFormat.SpaceAfter = 6
    .InsertBefore("Ready")
    .Font.Bold = True
  End With
End Sub'''),
        );
        final paragraph = _read(session).paragraphs.single;
        expect(paragraph.text, 'Ready');
        expect(WmlRunEdit.propsAt(paragraph, 0).bold, isTrue);
        expect(paragraph.properties.spacingAfter, 6);
      },
    );

    test(
      'compiled Word plan retains native permission and step limits',
      () async {
        final plan = _compile(File(_example).readAsStringSync());
        for (final (policy, code) in <(OfficeMacroPolicy, String)>[
          (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
          (
            OfficeMacroPolicy(allowedTools: <String>{'docx.replaceText'}),
            'permission_denied',
          ),
          (OfficeMacroPolicy(maxSteps: _reportSteps - 1), 'limit_exceeded'),
        ]) {
          final original = _template(List<String>.filled(6, ''));
          final session = _session(original, policy: policy);
          await expectLater(session.run(plan), throwsA(_error(code)));
          expect(session.bytes, original);
          expect(session.revision, 0);
        }
      },
    );

    test(
      'an existing revision shifts with prefixed text and survives saving',
      () async {
        final original = _rawBody(
          '<w:p><w:r><w:t>ab</w:t></w:r>'
          '<w:ins w:id="17" w:author="Original reviewer" '
          'w:date="2026-11-19T10:00:00Z">'
          '<w:r><w:t>XYZ</w:t></w:r></w:ins>'
          '<w:r><w:t>cd</w:t></w:r></w:p>',
        );
        final session = _session(original);
        expect(_read(session).trackRevisions, isFalse);
        final admittedRevision = _read(session).revisions.single;
        expect(admittedRevision.start, 2);
        final plan = _compile(r'''Sub Main()
  ThisDocument.Paragraphs(1).Range.InsertBefore "Header: "
End Sub''');
        await session.validate(plan);
        expect(session.bytes, original);
        await session.run(plan);
        final saved = _read(session);
        expect(saved.paragraphs.single.text, 'Header: abXYZcd');
        final revision = saved.revisions.single;
        expect(revision.kind, WmlRevisionKind.insert);
        expect(revision.author, 'Original reviewer');
        expect((revision.start, revision.end, revision.text), (10, 13, 'XYZ'));
        expect(revision.accepted, isNull);
        final nativeRevision = _elements(
          _documentXml(session.bytes),
          'ins',
        ).single;
        // Import canonicalizes native revision IDs; saving must retain the
        // admitted model's identity together with its author and shifted span.
        expect(revision.id, admittedRevision.id);
        expect(nativeRevision.getAttribute('id'), '${admittedRevision.id}');
        expect(nativeRevision.getAttribute('author'), 'Original reviewer');
        expect(nativeRevision.text, 'XYZ');
      },
    );

    test(
      'revision serializer failure does not publish preceding Word edits',
      () async {
        final original = _rawBody(
          '<w:p>'
          '<w:r><w:rPr><w:b/><w:rPrChange w:id="13" w:author="Original">'
          '<w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr><w:t/></w:r>'
          '<w:r><w:rPr><w:b/><w:rPrChange w:id="14" w:author="Original">'
          '<w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr><w:t/></w:r>'
          '</w:p><w:p><w:r><w:t>Original heading</w:t></w:r></w:p>',
        );
        final session = _session(original);
        session.startRecording('Failed Word source save');
        final plan = _compile(r'''Sub Main()
  ThisDocument.Paragraphs(2).Range.InsertBefore "Pending: "
  ThisDocument.Paragraphs(2).Range.Font.Bold = True
End Sub''');
        final failure = _error('document_error')
            .having((error) => error.stepIndex, 'stepIndex', isNull)
            .having((error) => error.tool, 'tool', isNull)
            .having(
              (error) => error.message,
              'message',
              contains(
                'The empty formatting run no longer has an unambiguous target.',
              ),
            );
        await expectLater(session.validate(plan), throwsA(failure));
        await expectLater(session.run(plan), throwsA(failure));
        expect(session.bytes, original);
        expect(session.revision, 0);
        expect(_read(session).revisions, hasLength(2));
        expect(_read(session).paragraphs.last.text, 'Original heading');
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'DOCM project bytes, native types and relationships remain inert and intact',
      () async {
        const documentType =
            'application/vnd.ms-word.document.macroEnabled.main+xml';
        const projectType = 'application/vnd.ms-office.vbaProject';
        const projectRelationship =
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
        final package = OpcPackage.openBytes(
          _template(<String>['Template body']),
        );
        package.getPart('/word/document.xml')!.contentType = documentType;
        package.contentTypes.setOverride('/word/document.xml', documentType);
        final projectBytes = Uint8List.fromList(<int>[
          0,
          1,
          127,
          128,
          254,
          255,
        ]);
        final signatureBytes = Uint8List.fromList(<int>[9, 8, 7, 6]);
        package.createPart('/word/vbaProject.bin', projectType, projectBytes);
        package.createPart(
          '/word/vbaProjectSignature.bin',
          'application/octet-stream',
          signatureBytes,
        );
        final project = package
            .relationshipsFor('/word/document.xml')
            .add(type: projectRelationship, target: 'vbaProject.bin');
        final signature = package
            .relationshipsFor('/word/vbaProject.bin')
            .add(
              type: '${projectRelationship}Signature',
              target: 'vbaProjectSignature.bin',
            );
        final original = package.save();
        final guard = (await WordPackagePreservation.capture(
          original,
          'template.docm',
        ))!;
        final session = _session(original);
        final plan = _compile(r'''Sub Main()
  ThisDocument.Paragraphs(1).Range.InsertBefore "Explicit source. "
End Sub''');
        for (var cycle = 1; cycle <= 3; cycle++) {
          final before = session.bytes;
          await session.validate(plan);
          expect(session.bytes, before);
          await session.run(plan);
          await guard.validateSaved(session.bytes);
          final saved = OpcPackage.openBytes(session.bytes);
          expect(
            saved.getPart('/word/document.xml')!.contentType,
            documentType,
          );
          expect(
            saved.contentTypes.contentTypeFor('/word/document.xml'),
            documentType,
          );
          expect(
            saved.getPart('/word/vbaProject.bin')!.contentType,
            projectType,
          );
          expect(
            saved.getPart('/word/vbaProject.bin')!.readBytes(),
            projectBytes,
          );
          expect(
            saved.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
            signatureBytes,
          );
          final documentRelationships = saved.relationshipsFor(
            '/word/document.xml',
          );
          final retainedProject = documentRelationships.items.singleWhere(
            (relationship) => relationship.type == projectRelationship,
          );
          expect(retainedProject.id, project.id);
          expect(retainedProject.target, project.target);
          expect(
            documentRelationships.resolve(retainedProject),
            '/word/vbaProject.bin',
          );
          final retainedSignature = saved
              .relationshipsFor('/word/vbaProject.bin')
              .items
              .single;
          expect(retainedSignature.id, signature.id);
          expect(retainedSignature.type, signature.type);
          expect(retainedSignature.target, signature.target);
          expect(
            _read(session).paragraphs.single.text,
            '${'Explicit source. ' * cycle}Template body',
          );
          expect(session.revision, cycle);
        }
      },
    );
  });

  group('Word source through MCP', () {
    test(
      'compile, detached validation and execution share one Word session',
      () async {
        final original = _template(List<String>.filled(6, ''));
        final session = _session(original);
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          _source(File(_example).readAsStringSync()),
        );
        expect(compiled['isError'], isFalse, reason: '$compiled');
        expect(session.bytes, original);
        final arguments = <String, Object?>{
          'macro': _structured(compiled)['macro'],
        };
        final validated = await adapter.callTool(
          'office_macro_validate',
          arguments,
        );
        expect(validated['isError'], isFalse, reason: '$validated');
        expect(_structured(validated)['validatedOnly'], isTrue);
        expect(session.bytes, original);
        expect(session.revision, 0);
        final result = await adapter.callTool('office_macro_run', arguments);
        expect(result['isError'], isFalse, reason: '$result');
        expect(_structured(result)['completedSteps'], _reportSteps);
        expect(session.revision, 1);
        _expectReport(session);
      },
    );

    test(
      'invalid Word text never returns a partial plan or changes the session',
      () async {
        final original = _template(<String>['Original']);
        final session = _session(original);
        final adapter = OfficeMacroMcp(session);
        for (final value in <String>[
          '\u0000',
          '\u000b',
          '\ufffe',
          '\uffff',
          '\r',
          '\n',
        ]) {
          final source =
              'Sub Main()\n'
              '  ThisDocument.Paragraphs(1).Range.InsertBefore "Pending: "\n'
              '  ThisDocument.Paragraphs(1).Range.InsertBefore "$value"\n'
              'End Sub';
          final result = await adapter.callTool(
            'office_macro_compile',
            _source(source),
          );
          expect(result['isError'], isTrue, reason: value.codeUnits.toString());
          final content = _structured(result);
          expect(content.containsKey('macro'), isFalse);
          final error = content['error']! as Map<String, Object?>;
          expect(error['moduleName'], 'WordReport');
          expect(error['line'], 3);
          expect(error['column'], greaterThan(0));
          expect(session.bytes, original);
          expect(session.revision, 0);
        }
        final result = await adapter.callTool(
          'office_macro_compile',
          _source(r'''Sub Main()
  ThisDocument.Paragraphs(1).Range.InsertBefore "Pending: "
  ThisDocument.Paragraphs(1).Range.InsertBefore Left$("😀", 1)
End Sub'''),
        );
        expect(result['isError'], isTrue);
        expect(_structured(result).containsKey('macro'), isFalse);
        expect(
          (_structured(result)['error']! as Map<String, Object?>)['code'],
          'vba_type_error',
        );
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });
}
