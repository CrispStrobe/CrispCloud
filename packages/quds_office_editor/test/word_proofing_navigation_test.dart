import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

final class _NavigationProvider extends OfficeProofingProvider {
  _NavigationProvider({this.insertAtEnd = false});
  final bool insertAtEnd;
  @override
  String get id => 'navigation-test';
  @override
  bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          if (insertAtEnd)
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: request.text.length,
              end: request.text.length,
              ruleId: 'punctuation',
              message: 'Add punctuation.',
              category: OfficeProofingCategory.style,
              replacements: const ['.'],
            )
          else
            for (final match in RegExp('Feler').allMatches(request.text))
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                start: match.start,
                end: match.end,
                ruleId: 'spelling',
                message: 'Use Fehler.',
                category: OfficeProofingCategory.spelling,
                replacements: const ['Fehler'],
              ),
        ],
      );
}

WordEditorController _controller(
  WmlDocument document, {
  bool insertAtEnd = false,
}) {
  final controller = WordEditorController(
    document: document,
    proofingService: OfficeProofingService(
      providers: [_NavigationProvider(insertAtEnd: insertAtEnd)],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('caret lookup leaves an empty read-only document unchanged', () {
    final document = WmlDocument(sections: [WmlSection(blocks: [])]);
    final controller = _controller(document);
    controller.setMode(OfficeInteractionMode.viewing);
    expect(document.paragraphs, isEmpty);
    expect(controller.proofingIssuesAtCaret, isEmpty);
    expect(document.sections.single.blocks, isEmpty);
    expect(controller.canUndo, isFalse);
  });

  test(
    'caret lookup uses half-open findings and exact insertion positions',
    () async {
      final controller = _controller(WmlDocument.empty(text: 'Feler Feler'));
      await controller.checkDocumentProofing();
      controller.caret.logicalIndex = 4;
      expect(controller.proofingIssuesAtCaret.single.finding.start, 0);
      controller.caret.logicalIndex = 5;
      expect(controller.proofingIssuesAtCaret, isEmpty);
      controller.caret.logicalIndex = 6;
      expect(controller.proofingIssuesAtCaret.single.finding.start, 6);
      controller.caret.logicalIndex = 11;
      expect(controller.proofingIssuesAtCaret, isEmpty);

      final insertion = _controller(
        WmlDocument.empty(text: 'Text'),
        insertAtEnd: true,
      );
      await insertion.checkDocumentProofing();
      insertion.caret.logicalIndex = 3;
      expect(insertion.proofingIssuesAtCaret, isEmpty);
      insertion.caret.logicalIndex = 4;
      expect(insertion.proofingIssuesAtCaret.single.finding.start, 4);
    },
  );

  test(
    'header and footer navigation synchronizes the exact IME paragraph',
    () async {
      final document = WmlDocument.empty(text: 'Body');
      final header = _paragraph('Feler header');
      final footer = _paragraph('Feler footer');
      final alternate = _paragraph('Feler alternate');
      document.sections.single.header.addAll([
        _paragraph('Header context'),
        header,
      ]);
      document.sections.single.footer.addAll([
        _paragraph('Footer context'),
        footer,
      ]);
      document.sections.single.firstHeader.add(alternate);
      final controller = _controller(document);
      final summary = await controller.checkDocumentProofing();
      for (final (paragraph, isFooter) in [(header, false), (footer, true)]) {
        final issue = summary.issues.singleWhere(
          (issue) => identical(issue.paragraph, paragraph),
        );
        expect(controller.revealProofingIssue(issue), isTrue);
        expect(controller.isEditingHeaderFooter, isTrue);
        expect(controller.isEditingFooter, isFooter);
        expect(controller.headerFooterParagraphs[1], same(paragraph));
        expect(controller.headerFooterCaret.paragraphIndex, 1);
        expect(controller.headerFooterCaret.selectionAnchor, 0);
        expect(controller.headerFooterCaret.logicalIndex, 5);
        expect(controller.input.value.text, paragraph.text);
        expect(
          controller.input.value.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
      }
      final unsupported = summary.issues.singleWhere(
        (issue) => identical(issue.paragraph, alternate),
      );
      expect(controller.revealProofingIssue(unsupported), isFalse);
      expect(controller.headerFooterParagraphs[1], same(footer));
    },
  );

  test(
    'body navigation leaves equation editing and routes subsequent IME text',
    () async {
      final body = _paragraph('Feler body');
      final equation = WmlEquation(math: OmmlGallery.byId('quadratic').build());
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [body, equation]),
        ],
      );
      final controller = _controller(document);
      controller.selectEquation(equation, caret: 1);
      expect(controller.selectedEquation, same(equation));
      expect(controller.input.isAttached, isTrue);
      final equationBefore = OmmlLinear.write(equation.math.root);
      final summary = await controller.checkDocumentProofing();
      final issue = summary.issues.singleWhere(
        (issue) => identical(issue.paragraph, body),
      );

      expect(controller.revealProofingIssue(issue), isTrue);
      expect(controller.selectedEquation, isNull);
      expect(controller.equationSlot, 0);
      expect(controller.equationCaret, 0);
      expect(controller.input.value.text, 'Feler body');
      expect(
        controller.input.value.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      controller.applyImeText('Fehler body');
      expect(body.text, 'Fehler body');
      expect(OmmlLinear.write(equation.math.root), equationBefore);
    },
  );

  test(
    'body navigation clears picture cropping and frame editing states',
    () async {
      final body = _paragraph('Feler body');
      final picture = WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: 'Picture',
          width: 20,
          height: 20,
        ),
      );
      final frame = WmlFrame(blocks: [_paragraph('Frame context')]);
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [body, picture, frame]),
        ],
      );
      final controller = _controller(document);
      final summary = await controller.checkDocumentProofing();
      final issue = summary.issues.singleWhere(
        (issue) => identical(issue.paragraph, body),
      );

      controller.selectVisual(picture);
      controller.togglePictureCropMode();
      expect(controller.selectedVisual, same(picture));
      expect(controller.pictureCropMode, isTrue);
      expect(controller.revealProofingIssue(issue), isTrue);
      expect(controller.selectedVisual, isNull);
      expect(controller.pictureCropMode, isFalse);

      for (final editing in [false, true]) {
        controller.selectFrame(frame, editing: editing);
        expect(controller.selectedFrame, same(frame));
        expect(controller.editingFrame, editing);
        expect(controller.revealProofingIssue(issue), isTrue);
        expect(controller.selectedFrame, isNull);
        expect(controller.editingFrame, isFalse);
        expect(controller.caret.paragraphIndex, 0);
        expect(controller.caret.selectionAnchor, 0);
        expect(controller.caret.logicalIndex, 5);
      }
      expect(body.text, 'Feler body');
      expect(controller.canUndo, isFalse);
    },
  );

  test('body navigation replaces a prior header IME selection', () async {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [_paragraph('Body context'), _paragraph('Feler body')],
        ),
      ],
    );
    document.sections.single.header.add(_paragraph('Feler header'));
    final controller = _controller(document);
    final summary = await controller.checkDocumentProofing();
    final header = summary.issues.singleWhere(
      (issue) => issue.story.startsWith('Header'),
    );
    final body = summary.issues.singleWhere((issue) => issue.story == 'Body');
    expect(controller.revealProofingIssue(header), isTrue);
    expect(controller.revealProofingIssue(body), isTrue);
    expect(controller.isEditingHeaderFooter, isFalse);
    expect(controller.caret.paragraphIndex, 1);
    expect(controller.input.value.text, 'Feler body');
    expect(
      controller.input.value.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });
}
