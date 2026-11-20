import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

final class _LanguageProvider extends OfficeProofingProvider {
  _LanguageProvider(this.id, this.language);

  @override
  final String id;
  final String language;
  final List<OfficeProofingRequest> requests = [];
  Completer<void>? gate;

  @override
  bool supportsLanguage(String value) => value == language;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    await gate?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        if (request.text.isNotEmpty)
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: 0,
            end: request.text.length,
            ruleId: 'fixture',
            message: 'Review this text.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Corrected'],
          ),
      ],
    );
  }
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _controller({
  WmlDocument? document,
  List<WmlParagraph>? paragraphs,
  OfficeSurfaceConfig? config,
}) {
  final controller = WordEditorController(
    document:
        document ??
        WmlDocument(
          proofingLanguage: 'de-DE',
          sections: [
            WmlSection(blocks: paragraphs ?? [_paragraph('Text')]),
          ],
        ),
    config: config,
  );
  addTearDown(controller.dispose);
  return controller;
}

List<({String text, String? language, bool? noProof})> _runs(
  WmlParagraph paragraph,
) => [
  for (final run in paragraph.inlines.whereType<WmlRun>())
    (
      text: run.text,
      language: run.properties.proofingLanguage,
      noProof: run.properties.noProof,
    ),
];

WmlContentControlData _control({
  bool bound = false,
  String lock = 'contentLocked',
}) => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:id w:val="42"/><w:lock w:val="$lock"/>'
      '${bound ? '<w:dataBinding w:storeItemID="{OWNER}" w:xpath="/text"/>' : ''}'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: const [],
);

void _refuse(WordEditorController controller, WordTextProofingTarget target) {
  final before = controller.document.paragraphs.map(_runs).toList();
  expect(controller.setTextProofingLanguage('en-US', target: target), isFalse);
  expect(controller.setTextProofingEnabled(false, target: target), isFalse);
  expect(controller.document.paragraphs.map(_runs).toList(), before);
  expect(controller.canUndo, isFalse);
}

WmlDocument _styledDocument() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:pStyle w:val="ParagraphChild"/></w:pPr>
<w:r><w:t>Paragraph </w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="CharacterChild"/></w:rPr><w:t>Character </w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="CharacterChild"/><w:lang w:val="en-GB" w:eastAsia="ja-JP" w:bidi="ar-SA"/><w:i/></w:rPr><w:t>Override</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="ParagraphBase"><w:rPr><w:lang w:val="de-AT"/><w:b/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ParagraphChild"><w:basedOn w:val="ParagraphBase"/></w:style>
<w:style w:type="character" w:styleId="CharacterBase"><w:rPr><w:lang w:val="de-CH"/><w:noProof w:val="0"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="CharacterChild"><w:basedOn w:val="CharacterBase"/></w:style>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

WmlDocument _complexScriptDocument({
  String text = 'عربي',
  bool complexScript = true,
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
<w:r><w:rPr><w:lang w:val="de-DE" w:bidi="ar-SA" w:eastAsia="ja-JP"/>${complexScript ? '<w:rtl/>' : ''}<w:b/></w:rPr><w:t>$text</w:t></w:r>
<w:r><w:rPr><w:lang w:val="fr-FR" w:bidi="he-IL"/></w:rPr><w:t xml:space="preserve"> text</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText(
        '''
<w:styles xmlns:w="${OfficeNamespaces.w}"><w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="en-US" w:bidi="ar-EG"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>''',
      );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inspection and options chrome never create text or history', () {
    final controller = _controller();
    final initialRevision = controller.contentRevision;
    expect(controller.reviewTextProofingOptionsVisible, isFalse);
    expect(controller.textProofingOptionsRequest, 0);
    controller.showTextProofingOptions();
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
    expect(controller.reviewTextProofingOptionsVisible, isTrue);
    expect(controller.textProofingOptionsRequest, 1);
    controller.showTextProofingOptions();
    expect(controller.textProofingOptionsRequest, 2);
    controller.setTextProofingOptionsVisible(false);
    expect(controller.reviewTextProofingOptionsVisible, isFalse);
    expect(controller.contentRevision, initialRevision);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);

    final comment = WmlComment(id: 8, text: 'Comment');
    controller.document.comments.add(comment);
    controller.beginCommentEdit(8);
    comment.paragraphs.clear();
    expect(controller.textProofingTarget, isNull);
    expect(comment.paragraphs, isEmpty);
    controller.endCommentEdit();
    controller.beginHeaderFooterEdit(0, footer: false);
    controller.document.sections.single.header.clear();
    expect(controller.textProofingTarget, isNull);
    expect(controller.document.sections.single.header, isEmpty);
    controller.endHeaderFooterEdit();
    controller.document.sections.clear();
    expect(controller.textProofingTarget, isNull);
    expect(controller.document.sections, isEmpty);
    expect(controller.contentRevision, initialRevision);
    expect(controller.canUndo, isFalse);
  });

  test(
    'collapsed caret changes the whole paragraph and preserves rich runs',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(
            text: 'Bold ',
            properties: WmlRunProps(bold: true, color: 'AA1122'),
            hyperlink: const WmlHyperlink(url: 'https://example.org'),
            commentIds: [4],
          ),
          WmlBookmarkBoundary(id: '9', isStart: true, name: 'target'),
          WmlRun(text: 'italic', properties: WmlRunProps(italic: true)),
          WmlBookmarkBoundary(id: '9', isStart: false),
        ],
      );
      final controller = _controller(
        paragraphs: [paragraph, _paragraph('Other')],
      );
      controller.caret
        ..logicalIndex = 2
        ..collapseSelection();
      final target = controller.textProofingTarget!;
      expect(target.isSelection, isFalse);
      expect(target.language, 'de-DE');
      expect(target.checkingEnabled, isTrue);
      expect(
        controller.setTextProofingLanguage('en_us', target: target),
        isTrue,
      );
      expect(paragraph.text, 'Bold italic');
      final runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs.map((run) => run.properties.proofingLanguage), [
        'en-US',
        'en-US',
      ]);
      expect(runs.first.properties.bold, isTrue);
      expect(runs.first.properties.color, 'AA1122');
      expect(runs.first.hyperlink?.url, 'https://example.org');
      expect(runs.first.commentIds, [4]);
      expect(runs.last.properties.italic, isTrue);
      expect(paragraph.inlines.whereType<WmlBookmarkBoundary>().length, 2);
      expect(
        controller.document.paragraphs.last.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .proofingLanguage,
        isNull,
      );
      expect(controller.caret.logicalIndex, 2);
      controller.undo();
      expect(
        paragraph.inlines.whereType<WmlRun>().every(
          (run) => run.properties.proofingLanguage == null,
        ),
        isTrue,
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.textProofingTarget!.language, 'en-US');
    },
  );

  test(
    'multiline reversed selection formats complete emoji and combining clusters only',
    () {
      final first = _paragraph('AB😀CD');
      final second = WmlParagraph(
        inlines: [
          WmlRun(text: 'e'),
          WmlRun(text: '\u0301XYZ', properties: WmlRunProps(italic: true)),
        ],
      );
      final controller = _controller(paragraphs: [first, second]);
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = 3
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 1;
      final target = controller.textProofingTarget!;
      expect(target.isSelection, isTrue);
      expect(
        controller.setTextProofingLanguage('en-GB', target: target),
        isTrue,
      );
      expect(_runs(first), [
        (text: 'AB', language: null, noProof: null),
        (text: '😀CD', language: 'en-GB', noProof: null),
      ]);
      expect(_runs(second), [
        (text: 'e', language: 'en-GB', noProof: null),
        (text: '\u0301', language: 'en-GB', noProof: null),
        (text: 'XYZ', language: null, noProof: null),
      ]);
      expect(controller.caret.logicalIndex, 3);
      expect(controller.caret.selectionAnchor, 1);
      controller.undo();
      expect(first.text, 'AB😀CD');
      expect(second.text, 'e\u0301XYZ');
      expect(_runs(first).single.language, isNull);
      expect(_runs(second).every((run) => run.language == null), isTrue);
      expect(controller.caret.isCollapsed, isFalse);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_runs(first).last.language, 'en-GB');
      expect(controller.caret.isCollapsed, isFalse);
    },
  );

  test(
    'effective mixed states, inherited languages and no-op history are distinct',
    () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(proofingLanguage: 'en-US'),
        inlines: [
          WmlRun(text: 'Inherited '),
          WmlRun(
            text: 'German',
            properties: WmlRunProps(proofingLanguage: 'de-DE', noProof: true),
          ),
        ],
      );
      final controller = _controller(paragraphs: [paragraph]);
      expect(controller.textProofingTarget!.language, isNull);
      expect(controller.textProofingTarget!.checkingEnabled, isNull);
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'en-US');
      controller.undo();
      expect(controller.textProofingTarget!.language, isNull);
      expect(
        controller.setTextProofingEnabled(
          true,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.checkingEnabled, isTrue);
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingEnabled(
          true,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(controller.textProofingTarget!.checkingEnabled, isNull);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'live changes recheck language, suppress findings and reject late results without manual inference',
    (tester) async {
      final controller = _controller();
      final german = _LanguageProvider('german', 'de-DE');
      final english = _LanguageProvider('english', 'en-US');
      final manual = _LanguageProvider('manual', 'en-US');
      controller.proofing
        ..configure(OfficeProofingService(providers: [german, english]))
        ..configureManual(OfficeProofingService(providers: [manual]))
        ..enabled = true;
      await tester.pump(_debounce);
      await tester.pump();
      expect(controller.proofing.summary.issues.single.language, 'de-DE');
      final obsolete = controller.proofing.summary.issues.single;
      english.gate = Completer<void>();
      expect(
        controller.setTextProofingLanguage(
          'en-US',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.proofing.isCurrent(obsolete), isFalse);
      expect(controller.proofing.summary.issues, isEmpty);
      await tester.pump(_debounce);
      expect(english.requests.single.language, 'en-US');
      expect(
        controller.setTextProofingEnabled(
          false,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      english.gate!.complete();
      await tester.pump();
      await tester.pump(_debounce);
      expect(controller.proofing.summary.issues, isEmpty);
      expect(manual.requests, isEmpty);
      controller.undo();
      english.gate = null;
      await tester.pump(_debounce);
      await tester.pump();
      expect(controller.proofing.summary.issues.single.language, 'en-US');
      expect(manual.requests, isEmpty);
      controller.proofing.enabled = false;
    },
  );

  for (final change in [
    'caret',
    'text',
    'language',
    'complex-script language',
    'run language',
    'run complex-script language',
    'suppression',
    'run replacement',
    'document',
    'paragraph order',
  ]) {
    test('a captured target refuses stale $change without history', () {
      final controller = _controller(
        paragraphs: [_paragraph('First'), _paragraph('Other')],
      );
      final target = controller.textProofingTarget!;
      final paragraph = controller.document.paragraphs.first;
      switch (change) {
        case 'caret':
          controller.caret
            ..logicalIndex = 1
            ..collapseSelection();
        case 'text':
          paragraph.inlines.whereType<WmlRun>().single.text = 'Other';
        case 'language':
          controller.document.proofingLanguage = 'en-GB';
        case 'complex-script language':
          controller.document.complexScriptLanguage = 'ar-EG';
        case 'run language':
          paragraph.inlines
                  .whereType<WmlRun>()
                  .single
                  .properties
                  .proofingLanguage =
              'en-GB';
        case 'run complex-script language':
          paragraph.inlines
                  .whereType<WmlRun>()
                  .single
                  .properties
                  .complexScriptLanguage =
              'ar-EG';
        case 'suppression':
          paragraph.inlines.whereType<WmlRun>().single.properties.noProof =
              true;
        case 'run replacement':
          paragraph.inlines = [WmlRun(text: 'First')];
        case 'document':
          controller.document = WmlDocument.empty(text: 'First');
        case 'paragraph order':
          controller.document.sections.single.blocks = controller
              .document
              .sections
              .single
              .blocks
              .reversed
              .toList();
      }
      _refuse(controller, target);
    });
  }

  for (final item in [
    'field',
    'note',
    'complex field',
    'generated paragraph',
  ]) {
    test('a $item in a multiline target refuses the entire change', () {
      final first = _paragraph('Ordinary');
      final second = _paragraph('Generated');
      if (item == 'field') {
        second.inlines.whereType<WmlRun>().single.fieldInstruction = ' PAGE ';
      }
      if (item == 'note') {
        second.inlines.whereType<WmlRun>().single.noteRefId = 3;
      }
      if (item == 'generated paragraph') {
        second.properties.fieldInstruction = ' DATE ';
      }
      if (item == 'complex field') {
        second.inlines.insert(
          0,
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        );
        second.inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
      }
      final controller = _controller(paragraphs: [first, second]);
      controller.caret
        ..paragraphIndex = 1
        ..logicalIndex = second.text.length;
      final target = controller.textProofingTarget!;
      expect(target.canEdit, isFalse);
      expect(target.unavailableReason, isNotEmpty);
      _refuse(controller, target);
      expect(_runs(first).single.language, isNull);
    });
  }

  test('a complex field opened in a prior paragraph remains protected', () {
    final first = WmlParagraph(
      inlines: [
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlRun(text: 'Field'),
      ],
    );
    final second = WmlParagraph(
      inlines: [
        WmlRun(text: 'Result'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        WmlRun(text: ' Ordinary'),
      ],
    );
    final controller = _controller(paragraphs: [first, second]);
    controller.caret
      ..paragraphIndex = 1
      ..logicalIndex = 2
      ..collapseSelection();
    expect(controller.textProofingTarget!.canEdit, isFalse);
    _refuse(controller, controller.textProofingTarget!);
    controller.caret
      ..selectionAnchor = 7
      ..logicalIndex = second.text.length;
    expect(
      controller.setTextProofingLanguage(
        'en-US',
        target: controller.textProofingTarget!,
      ),
      isTrue,
    );
    expect(_runs(second).first.language, isNull);
    expect(_runs(second).last.language, 'en-US');
    expect(
      second.inlines.whereType<WmlFieldBoundary>().single.kind,
      WmlFieldBoundaryKind.end,
    );
  });

  for (final owner in ['block', 'inline', 'wrapper', 'binding']) {
    test('protected $owner controls refuse both proofing operations', () {
      final paragraph = _paragraph('Locked');
      final control = _control(
        bound: owner == 'binding',
        lock: owner == 'binding' ? 'unlocked' : 'contentLocked',
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      if (owner == 'block' || owner == 'binding') {
        document.sections.single.blocks = [
          WmlContentControlBlock(control: control, blocks: [paragraph]),
        ];
      } else if (owner == 'wrapper') {
        paragraph.contentControlWrappers.add(control);
      } else {
        paragraph.inlines.insert(
          0,
          WmlContentControlBoundary(control: control, start: true),
        );
        paragraph.inlines.add(
          WmlContentControlBoundary(control: control, start: false),
        );
      }
      final controller = _controller(document: document);
      expect(controller.textProofingTarget!.canEdit, isFalse);
      _refuse(controller, controller.textProofingTarget!);
    });
  }

  test('unlocked control boundaries survive selected formatting and Undo', () {
    final control = _control(lock: 'unlocked');
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Before '),
        WmlContentControlBoundary(control: control, start: true),
        WmlRun(text: 'Inside'),
        WmlContentControlBoundary(control: control, start: false),
        WmlRun(text: ' after'),
      ],
    );
    final controller = _controller(paragraphs: [paragraph]);
    controller.caret
      ..selectionAnchor = 5
      ..logicalIndex = 10;
    expect(
      controller.setTextProofingEnabled(
        false,
        target: controller.textProofingTarget!,
      ),
      isTrue,
    );
    expect(paragraph.text, 'Before Inside after');
    expect(WordContentControls.spans(paragraph).single.start, 7);
    expect(WordContentControls.spans(paragraph).single.end, 13);
    controller.undo();
    expect(_runs(paragraph).every((run) => run.noProof == null), isTrue);
    expect(WordContentControls.spans(paragraph).single.control, same(control));
  });

  test(
    'formatting leaves tracked insertion/deletion ranges and authors intact',
    () {
      final paragraph = _paragraph('Old New');
      final controller = _controller(paragraphs: [paragraph]);
      controller.document
        ..trackRevisions = true
        ..revisions.addAll([
          WmlRevision(
            id: 1,
            kind: WmlRevisionKind.delete,
            paragraphIndex: 0,
            start: 0,
            end: 3,
            text: 'Old',
            author: 'First',
            targetParagraph: paragraph,
          ),
          WmlRevision(
            id: 2,
            kind: WmlRevisionKind.insert,
            paragraphIndex: 0,
            start: 4,
            end: 7,
            text: 'New',
            author: 'Second',
            targetParagraph: paragraph,
          ),
        ]);
      final revisions = WordRevisions.capture(controller.document);
      expect(
        controller.setTextProofingLanguage(
          'en-US',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(revisions.matches(controller.document), isTrue);
      controller.undo();
      expect(revisions.matches(controller.document), isTrue);
      controller.redo();
      expect(revisions.matches(controller.document), isTrue);
      expect(paragraph.text, 'Old New');
    },
  );

  for (final story in ['comment', 'header']) {
    test(
      '$story target follows exact ownership and history preserves other story selections',
      () {
        final edited = _paragraph('Edited story');
        final other = _paragraph('Other story');
        final document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [_paragraph('Body')],
              header: story == 'header' ? [edited] : [],
              footer: story == 'header' ? [other] : [],
            ),
          ],
          comments: story == 'comment'
              ? [
                  WmlComment(id: 1, paragraphs: [edited]),
                  WmlComment(id: 2, paragraphs: [other]),
                ]
              : [],
        );
        final controller = _controller(document: document);
        void select(bool first) {
          if (story == 'comment') {
            controller.beginCommentEdit(first ? 1 : 2);
          } else {
            controller.beginHeaderFooterEdit(0, footer: !first);
          }
        }

        select(true);
        controller.caret
          ..selectionAnchor = 0
          ..logicalIndex = 6;
        final target = controller.textProofingTarget!;
        select(false);
        _refuse(controller, target);
        select(true);
        expect(
          controller.setTextProofingLanguage(
            'en-US',
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(_runs(edited).first.language, 'en-US');
        expect(_runs(document.paragraphs.single).single.language, isNull);
        select(false);
        controller.caret
          ..selectionAnchor = 1
          ..logicalIndex = 4;
        controller.undo();
        expect(_runs(edited).every((run) => run.language == null), isTrue);
        expect(controller.caret.selectionAnchor, 1);
        expect(controller.caret.logicalIndex, 4);
        controller.redo();
        expect(_runs(edited).first.language, 'en-US');
        expect(_runs(other).single.language, isNull);
        expect(controller.caret.selectionAnchor, 1);
        expect(controller.caret.logicalIndex, 4);
      },
    );
  }

  test(
    'viewing mode, late protection and IME never mutate displayed targets',
    () {
      final controller = _controller();
      final target = controller.textProofingTarget!;
      controller.setMode(OfficeInteractionMode.viewing);
      expect(controller.textProofingTarget!.canEdit, isFalse);
      _refuse(controller, target);
      controller.setMode(OfficeInteractionMode.editing);
      controller.document
        ..restrictEditing = true
        ..restrictMode = WmlRestrictMode.readOnly;
      expect(controller.textProofingTarget!.canEdit, isFalse);
      _refuse(controller, target);
      controller.document
        ..restrictEditing = false
        ..restrictMode = WmlRestrictMode.none;
      controller.input.composing = const TextRange(start: 0, end: 2);
      expect(controller.textProofingTarget!.canEdit, isFalse);
      _refuse(controller, target);
      final language = controller.document.proofingLanguage;
      controller.setProofingLanguage('en-US');
      expect(controller.document.proofingLanguage, language);
      expect(controller.input.composing, const TextRange(start: 0, end: 2));
    },
  );

  test(
    'explicit both-slot language editing replaces stale metadata and resets both overrides through history and save',
    () {
      final controller = _controller(document: _complexScriptDocument());
      final paragraph = controller.document.paragraphs.single;
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(controller.textProofingTarget!.language, 'ar-SA');
      expect(
        controller.setTextProofingLanguage(
          'de-DE',
          target: controller.textProofingTarget!,
          activeLanguageOnly: false,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'de-DE');
      var runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs.first.properties.proofingLanguage, 'de-DE');
      expect(runs.first.properties.complexScriptLanguage, 'de-DE');
      expect(runs.last.properties.proofingLanguage, 'fr-FR');
      expect(runs.last.properties.complexScriptLanguage, 'he-IL');
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingLanguage(
          'de-DE',
          target: controller.textProofingTarget!,
          activeLanguageOnly: false,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(controller.textProofingTarget!.language, 'ar-SA');
      controller.redo();
      expect(controller.textProofingTarget!.language, 'de-DE');
      var loaded = WordDeserializer().readBytes(controller.saveBytes());
      var props = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .first
          .properties;
      expect(props.proofingLanguage, 'de-DE');
      expect(props.complexScriptLanguage, 'de-DE');
      expect(props.sourcePropertiesXml, contains('eastAsia="ja-JP"'));
      expect(props.complexScript, isTrue);
      expect(props.bold, isTrue);
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
          activeLanguageOnly: false,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'ar-EG');
      runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs.first.properties.proofingLanguage, isNull);
      expect(runs.first.properties.complexScriptLanguage, isNull);
      expect(runs.last.properties.complexScriptLanguage, 'he-IL');
      controller.undo();
      expect(controller.textProofingTarget!.language, 'de-DE');
      controller.redo();
      expect(controller.textProofingTarget!.language, 'ar-EG');
      loaded = WordDeserializer().readBytes(controller.saveBytes());
      props = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .first
          .properties;
      expect(props.proofingLanguage, isNull);
      expect(props.complexScriptLanguage, isNull);
      expect(props.sourcePropertiesXml, contains('eastAsia="ja-JP"'));
      expect(props.sourcePropertiesXml, isNot(contains('de-DE')));
      expect(props.sourcePropertiesXml, isNot(contains('ar-SA')));
      final reopened = _controller(document: loaded);
      reopened.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(reopened.textProofingTarget!.language, 'ar-EG');
    },
  );

  for (final language in ['he-IL', 'de-AT', 'en-US']) {
    test(
      'default selection language $language preserves inactive slots through history and save',
      () {
        final controller = _controller(document: _complexScriptDocument());
        final paragraph = controller.document.paragraphs.single;
        void expectInactiveSlots(WmlParagraph value) {
          final runs = value.inlines.whereType<WmlRun>().toList();
          expect(runs.map((run) => run.text), ['عربي', ' text']);
          expect(runs.first.properties.proofingLanguage, 'de-DE');
          expect(runs.first.properties.complexScript, isTrue);
          expect(runs.first.properties.bold, isTrue);
          expect(
            runs.first.properties.sourcePropertiesXml,
            contains('eastAsia="ja-JP"'),
          );
          expect(runs.last.properties.proofingLanguage, 'fr-FR');
          expect(runs.last.properties.complexScriptLanguage, 'he-IL');
        }

        controller.caret
          ..selectionAnchor = 0
          ..logicalIndex = 4;
        expect(controller.textProofingTarget!.language, 'ar-SA');
        expectInactiveSlots(paragraph);
        expect(
          controller.setTextProofingLanguage(
            language,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.textProofingTarget!.language, language);
        var runs = paragraph.inlines.whereType<WmlRun>().toList();
        expect(runs.first.properties.complexScriptLanguage, language);
        expectInactiveSlots(paragraph);
        final revision = controller.contentRevision;
        expect(
          controller.setTextProofingLanguage(
            language,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.contentRevision, revision);
        controller.undo();
        expect(controller.textProofingTarget!.language, 'ar-SA');
        expect(
          paragraph.inlines
              .whereType<WmlRun>()
              .first
              .properties
              .complexScriptLanguage,
          'ar-SA',
        );
        expectInactiveSlots(paragraph);
        controller.redo();
        expect(controller.textProofingTarget!.language, language);
        expectInactiveSlots(paragraph);
        var loaded = WordDeserializer().readBytes(controller.saveBytes());
        var props = loaded.paragraphs.single.inlines
            .whereType<WmlRun>()
            .first
            .properties;
        expect(props.proofingLanguage, 'de-DE');
        expect(props.complexScriptLanguage, language);
        expectInactiveSlots(loaded.paragraphs.single);
        expect(
          controller.setTextProofingLanguage(
            null,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.textProofingTarget!.language, 'ar-EG');
        runs = paragraph.inlines.whereType<WmlRun>().toList();
        expect(runs.first.properties.proofingLanguage, 'de-DE');
        expect(runs.first.properties.complexScriptLanguage, isNull);
        expectInactiveSlots(paragraph);
        controller.undo();
        expect(controller.textProofingTarget!.language, language);
        expect(
          paragraph.inlines
              .whereType<WmlRun>()
              .first
              .properties
              .complexScriptLanguage,
          language,
        );
        expectInactiveSlots(paragraph);
        controller.redo();
        expect(controller.textProofingTarget!.language, 'ar-EG');
        expectInactiveSlots(paragraph);
        loaded = WordDeserializer().readBytes(controller.saveBytes());
        props = loaded.paragraphs.single.inlines
            .whereType<WmlRun>()
            .first
            .properties;
        expect(props.proofingLanguage, 'de-DE');
        expect(props.complexScriptLanguage, isNull);
        expect(props.sourcePropertiesXml, contains('val="de-DE"'));
        expect(props.sourcePropertiesXml, isNot(contains('bidi=')));
        expect(props.sourcePropertiesXml, isNot(contains(language)));
        expect(props.sourcePropertiesXml, isNot(contains('ar-SA')));
        expectInactiveSlots(loaded.paragraphs.single);
        final reopened = _controller(document: loaded);
        reopened.caret
          ..selectionAnchor = 0
          ..logicalIndex = 4;
        expect(reopened.textProofingTarget!.language, 'ar-EG');
      },
    );
  }

  for (final complex in [false, true]) {
    test(
      'partial ${complex ? 'Arabic' : 'Latin'} selection routes its own language slot and preserves the other',
      () {
        final document = _complexScriptDocument();
        final paragraph = document.paragraphs.single;
        // Both scripts begin in one run without an explicit complex-script
        // marker. Routing must use the selected fragment after splitting.
        paragraph.inlines = [
          WmlRun(
            text: 'Latin عربي',
            properties: WmlRunProps(
              proofingLanguage: 'de-DE',
              complexScriptLanguage: 'ar-SA',
            ),
          ),
        ];
        final controller = _controller(document: document);
        final start = complex ? 6 : 0;
        final end = complex ? 10 : 5;
        final selectedLanguage = complex ? 'he-IL' : 'fr-FR';
        controller.caret
          ..selectionAnchor = start
          ..logicalIndex = end;
        expect(
          controller.textProofingTarget!.language,
          complex ? 'ar-SA' : 'de-DE',
        );
        expect(controller.canUndo, isFalse);
        expect(
          controller.setTextProofingLanguage(
            selectedLanguage,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        final selected = paragraph.inlines
            .whereType<WmlRun>()
            .toList()[complex ? 1 : 0];
        expect(selected.text, complex ? 'عربي' : 'Latin');
        expect(
          selected.properties.proofingLanguage,
          complex ? 'de-DE' : 'fr-FR',
        );
        expect(
          selected.properties.complexScriptLanguage,
          complex ? 'he-IL' : 'ar-SA',
        );
        expect(controller.textProofingTarget!.language, selectedLanguage);
        controller.undo();
        expect(paragraph.inlines.whereType<WmlRun>().single.text, 'Latin عربي');
        controller.redo();
        expect(controller.textProofingTarget!.language, selectedLanguage);
        expect(
          controller.setTextProofingLanguage(
            null,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        final inherited = complex ? 'ar-EG' : 'en-US';
        expect(controller.textProofingTarget!.language, inherited);
        final loaded = WordDeserializer().readBytes(controller.saveBytes());
        final saved = loaded.paragraphs.single.inlines
            .whereType<WmlRun>()
            .toList();
        final changed = saved[complex ? 1 : 0].properties;
        final unchanged = saved[complex ? 0 : 1].properties;
        expect(changed.proofingLanguage, complex ? 'de-DE' : null);
        expect(changed.complexScriptLanguage, complex ? null : 'ar-SA');
        expect(unchanged.proofingLanguage, 'de-DE');
        expect(unchanged.complexScriptLanguage, 'ar-SA');
        final reopened = _controller(document: loaded);
        reopened.caret
          ..selectionAnchor = start
          ..logicalIndex = end;
        expect(reopened.textProofingTarget!.language, inherited);
      },
    );
  }

  test(
    'default whole mixed selection changes and resets both active slots through history and save',
    () {
      const text = 'Latin عربي';
      final controller = _controller(
        document: _complexScriptDocument(text: text, complexScript: false),
      );
      final paragraph = controller.document.paragraphs.single;
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = text.length;
      expect(controller.textProofingTarget!.language, isNull);
      expect(controller.canUndo, isFalse);
      expect(
        controller.setTextProofingLanguage(
          'fr-CA',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'fr-CA');
      var props = paragraph.inlines.whereType<WmlRun>().first.properties;
      expect(props.proofingLanguage, 'fr-CA');
      expect(props.complexScriptLanguage, 'fr-CA');
      controller.undo();
      expect(controller.textProofingTarget!.language, isNull);
      controller.redo();
      expect(controller.textProofingTarget!.language, 'fr-CA');
      var loaded = WordDeserializer().readBytes(controller.saveBytes());
      props = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .first
          .properties;
      expect(props.proofingLanguage, 'fr-CA');
      expect(props.complexScriptLanguage, 'fr-CA');
      expect(props.sourcePropertiesXml, contains('eastAsia="ja-JP"'));
      expect(props.bold, isTrue);

      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, isNull);
      props = paragraph.inlines.whereType<WmlRun>().first.properties;
      expect(props.proofingLanguage, isNull);
      expect(props.complexScriptLanguage, isNull);
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(controller.textProofingTarget!.language, 'fr-CA');
      controller.redo();
      loaded = WordDeserializer().readBytes(controller.saveBytes());
      final runs = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.first.properties.proofingLanguage, isNull);
      expect(runs.first.properties.complexScriptLanguage, isNull);
      expect(runs.first.properties.sourcePropertiesXml, contains('ja-JP'));
      expect(
        runs.first.properties.sourcePropertiesXml,
        isNot(contains('fr-CA')),
      );
      expect(runs.last.properties.proofingLanguage, 'fr-FR');
      expect(runs.last.properties.complexScriptLanguage, 'he-IL');
      final reopened = _controller(document: loaded);
      reopened.caret
        ..selectionAnchor = 0
        ..logicalIndex = text.length;
      expect(reopened.textProofingTarget!.language, isNull);
    },
  );

  test(
    'language inheritance and explicit checking permission survive DOCX save',
    () {
      final controller = _controller();
      expect(
        controller.setTextProofingLanguage(
          'en-US',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(
        controller.setTextProofingEnabled(
          false,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      var loaded = WordDeserializer().readBytes(controller.saveBytes());
      var props = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .properties;
      expect(props.proofingLanguage, 'en-US');
      expect(props.noProof, isTrue);
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(
        controller.setTextProofingEnabled(
          true,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      loaded = WordDeserializer().readBytes(controller.saveBytes());
      props = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .properties;
      // Removing the run override retains live document-language inheritance;
      // the importer must not stamp the current default onto the run.
      expect(props.proofingLanguage, isNull);
      expect(loaded.proofingLanguage, 'de-DE');
      expect(
        props.proofingLanguage ??
            loaded.paragraphs.single.properties.proofingLanguage ??
            loaded.proofingLanguage,
        'de-DE',
      );
      expect(props.noProof, isFalse);
      final reopened = _controller(document: loaded);
      expect(reopened.textProofingTarget!.language, 'de-DE');
      expect(reopened.textProofingTarget!.checkingEnabled, isTrue);
      reopened.setProofingLanguage('fr-FR');
      expect(reopened.textProofingTarget!.language, 'fr-FR');
      expect(props.proofingLanguage, isNull);
    },
  );

  test(
    'resetting imported language preserves inactive metadata and style inheritance through history and save',
    () async {
      final controller = _controller(document: _styledDocument());
      final paragraph = controller.document.paragraphs.single;
      final before = _runs(paragraph);
      expect(before.map((run) => run.language), ['de-AT', 'de-CH', 'en-GB']);
      controller.caret
        ..selectionAnchor = 'Paragraph Character '.length
        ..logicalIndex = paragraph.text.length;
      final provider = _LanguageProvider('swiss', 'de-CH');
      controller.proofing.configure(
        OfficeProofingService(providers: [provider]),
      );
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'de-CH');
      final props = paragraph.inlines.whereType<WmlRun>().last.properties;
      expect(props.bold, isTrue);
      expect(props.italic, isTrue);
      expect(props.noProof, isFalse);
      expect(props.sourcePropertiesXml, contains('ja-JP'));
      expect(props.complexScriptLanguage, 'ar-SA');
      expect(props.styleId, 'CharacterChild');
      expect(props.sourcePropertiesXml, contains('ar-SA'));
      final report = await controller.proofing.checkNow(
        includeManualProviders: false,
      );
      expect(report.issues.last.language, 'de-CH');
      expect(provider.requests.last.text, contains('Override'));
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(_runs(paragraph), before);
      expect(controller.textProofingTarget!.language, 'en-GB');
      expect(
        paragraph.inlines
            .whereType<WmlRun>()
            .last
            .properties
            .complexScriptLanguage,
        'ar-SA',
      );
      controller.redo();
      expect(controller.textProofingTarget!.language, 'de-CH');
      expect(
        paragraph.inlines
            .whereType<WmlRun>()
            .last
            .properties
            .complexScriptLanguage,
        'ar-SA',
      );
      final loaded = WordDeserializer().readBytes(controller.saveBytes());
      expect(_runs(loaded.paragraphs.single).map((run) => run.language), [
        'de-AT',
        'de-CH',
        'de-CH',
      ]);
      final loadedProps = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .last
          .properties;
      expect(loadedProps.bold, isTrue);
      expect(loadedProps.italic, isTrue);
      expect(loadedProps.noProof, isFalse);
      expect(loadedProps.styleId, 'CharacterChild');
      expect(loadedProps.complexScriptLanguage, 'ar-SA');
      expect(loadedProps.sourcePropertiesXml, contains('ja-JP'));
      expect(loadedProps.sourcePropertiesXml, contains('ar-SA'));
      expect(loadedProps.sourcePropertiesXml, isNot(contains('en-GB')));
    },
  );

  test(
    'a style part replacement makes an already displayed language target stale',
    () {
      final controller = _controller(document: _styledDocument());
      final target = controller.textProofingTarget!;
      final part = controller.document.package!.getPart('/word/styles.xml')!;
      part.writeText(part.readText().replaceAll('de-CH', 'de-DE'));
      _refuse(controller, target);
    },
  );

  test(
    'aliased paragraph ownership cannot modify another story indirectly',
    () {
      final paragraph = _paragraph('Shared');
      final controller = _controller(
        document: WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph], evenHeader: [paragraph]),
          ],
        ),
      );
      _refuse(controller, controller.textProofingTarget!);
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isFalse,
      );
      expect(
        controller.document.sections.single.evenHeader.single,
        same(paragraph),
      );
    },
  );
}
