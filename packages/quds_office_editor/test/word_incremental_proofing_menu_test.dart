import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _firstText = 'Ein Feler bleibt hier.';
const _secondText = 'The second paragraph completes later.';
const _thirdText = 'The third paragraph is still checking.';
const _menuKey = Key('office-context-menu');

final class _ProgressProvider extends OfficeProofingProvider {
  final secondGate = Completer<void>();
  final thirdGate = Completer<void>();
  final List<OfficeProofingRequest> requests = [];

  @override
  String get id => 'incremental-menu-proofing';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (request.text == _secondText) await secondGate.future;
    if (request.text == _thirdText) await thirdGate.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final match in RegExp('Feler').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'incremental-menu.spelling',
            start: match.start,
            end: match.end,
            message: 'Check this spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
      ],
    );
  }

  void release() {
    if (!secondGate.isCompleted) secondGate.complete();
    if (!thirdGate.isCompleted) thirdGate.complete();
  }
}

WmlDocument _document() => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 620),
      margins: const WmlPageMargins(top: 50, bottom: 50, left: 48, right: 48),
      blocks: [
        for (final text in [_firstText, _secondText, _thirdText])
          WmlParagraph(inlines: [WmlRun(text: text)]),
      ],
    ),
  ],
);

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Offset _markedPoint(WidgetTester tester, WordEditorController controller) {
  final canvas = tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
  final line = controller.documentLaidOut.pages
      .expand((page) => page.lines)
      .firstWhere(
        (line) =>
            line.paragraphIndex == 0 &&
            line.glyphs.any(
              (glyph) => glyph.glyph.logicalIndex <= 6 && 6 < glyph.logicalEnd,
            ),
      );
  final glyph = line.glyphs.firstWhere(
    (glyph) => glyph.glyph.logicalIndex <= 6 && 6 < glyph.logicalEnd,
  );
  return canvas.localToGlobal(
    canvas.windowForPagePoint(
      line.pageIndex,
      Offset(glyph.x + glyph.advance * .35, line.y + line.height * .5),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'inline correction stays open and undoable during unrelated paragraph progress',
    (tester) async {
      final provider = _ProgressProvider();
      final controller = WordEditorController(
        document: _document(),
        config: const OfficeSurfaceConfig(showRulers: false),
        proofingService: OfficeProofingService(providers: [provider]),
      );
      final focus = FocusNode(debugLabel: 'incremental-menu-document');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1120, 760);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Liberation Sans'),
            home: Scaffold(
              body: QudsWordEditor(controller: controller, focusNode: focus),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(controller.proofing.debounce);
        await _frames(tester);

        // The first paragraph is actionable before the second one finishes.
        final session = controller.proofing;
        expect(session.checking, isTrue);
        expect(session.summary.checkedParagraphCount, 1);
        expect(session.summary.complete, isFalse);
        expect(provider.requests.map((request) => request.text), [
          _firstText,
          _secondText,
        ]);
        final issue = session.summary.issues.single;
        expect(session.isCurrent(issue), isTrue);

        final gesture = await tester.startGesture(
          _markedPoint(tester, controller),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await gesture.up();
        await tester.pump();
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
        await _frames(tester);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(find.text('Fehler'), findsOneWidget);
        expect(focus.hasPrimaryFocus, isTrue);
        expect(controller.input.isAttached, isTrue);

        // A real publication replaces the summary while the final provider
        // request remains gated. The menu must keep its current issue.
        final beforeProgress = session.summary;
        provider.secondGate.complete();
        await _frames(tester);
        expect(provider.requests.map((request) => request.text), [
          _firstText,
          _secondText,
          _thirdText,
        ]);
        expect(provider.thirdGate.isCompleted, isFalse);
        expect(session.checking, isTrue);
        expect(session.summary, isNot(same(beforeProgress)));
        expect(session.summary.checkedParagraphCount, 2);
        expect(session.summary.issues.single, same(issue));
        expect(session.isCurrent(issue), isTrue);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(find.text('Fehler'), findsOneWidget);

        await tester.tap(find.text('Fehler'));
        await tester.pump();
        expect(
          controller.document.paragraphs.map((paragraph) => paragraph.text),
          ['Ein Fehler bleibt hier.', _secondText, _thirdText],
        );
        expect(find.byKey(_menuKey), findsNothing);
        expect(controller.canUndo, isTrue);
        expect(session.isCurrent(issue), isFalse);

        // The obsolete in-flight response cannot restore the corrected mark.
        provider.thirdGate.complete();
        await _frames(tester);
        expect(session.summary.issues, isEmpty);
        expect(
          controller.document.paragraphs.first.text,
          'Ein Fehler bleibt hier.',
        );

        controller.undo();
        await tester.pump(controller.proofing.debounce);
        await _frames(tester);
        // The third paragraph's check was interrupted by the correction; the
        // rest of the document is checked in idle time.
        await tester.pump(WordProofingTiming.backgroundIdle);
        await _frames(tester);
        expect(
          controller.document.paragraphs.map((paragraph) => paragraph.text),
          [_firstText, _secondText, _thirdText],
        );
        expect(session.summary.complete, isTrue);
        expect(session.summary.issues, hasLength(1));
        expect(session.isCurrent(session.summary.issues.single), isTrue);
        expect(session.isCurrent(issue), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        provider.release();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        focus.dispose();
        await tester.pump();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
