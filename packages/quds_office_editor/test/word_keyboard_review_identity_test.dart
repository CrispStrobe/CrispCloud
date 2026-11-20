import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

const _menuKey = Key('office-context-menu');

final class _KeyboardProvider extends OfficeProofingProvider {
  _KeyboardProvider(
    this.id, {
    this.tokens = const {
      'Feler': (OfficeProofingCategory.spelling, 'Fehler'),
      'Gramar': (OfficeProofingCategory.grammar, 'Grammar'),
    },
  });

  @override
  final String id;
  final Map<String, (OfficeProofingCategory, String)> tokens;
  final requests = <OfficeProofingRequest>[];
  final gates = <int, Completer<void>>{};

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    await gates[requests.length]?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final entry in tokens.entries)
          for (final match in RegExp(entry.key).allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: '$id-${entry.value.$1.name}',
              message: 'Review ${entry.key}.',
              category: entry.value.$1,
              replacements: [entry.value.$2],
            ),
      ],
    );
  }

  void release() {
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

WmlDocument _document(String text) => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 620),
      margins: const WmlPageMargins(top: 50, bottom: 50, left: 48, right: 48),
      blocks: [
        WmlParagraph(inlines: [WmlRun(text: text)]),
      ],
    ),
  ],
);

final class _Harness {
  _Harness({
    String text = 'Feler Feler Feler',
    WmlDocument? document,
    _KeyboardProvider? ordinary,
    this.manual,
    bool viewing = false,
  }) : ordinary = ordinary ?? _KeyboardProvider('keyboard-ordinary') {
    controller = WordEditorController(
      document: document ?? _document(text),
      config: OfficeSurfaceConfig(
        showRulers: false,
        mode: viewing
            ? OfficeInteractionMode.viewing
            : OfficeInteractionMode.editing,
      ),
      proofingService: OfficeProofingService(providers: [this.ordinary]),
    );
    if (manual != null) {
      controller.proofing.configureManual(
        OfficeProofingService(providers: [manual!]),
      );
    }
  }

  final _KeyboardProvider ordinary;
  final _KeyboardProvider? manual;
  late final WordEditorController controller;
  final focus = FocusNode(debugLabel: 'keyboard-review-document');

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1120, 960);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Liberation Sans'),
        home: Scaffold(
          body: QudsWordEditor(controller: controller, focusNode: focus),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(_debounce);
    await _frames(tester);
  }

  Future<void> focusDocument(WidgetTester tester, {int? offset}) async {
    if (offset != null) {
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = offset
        ..collapseSelection();
      controller.refreshView();
    }
    focus.requestFocus();
    await _frames(tester);
  }

  Future<void> close(WidgetTester tester) async {
    ordinary.release();
    manual?.release();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool alt = false,
  bool shift = false,
  bool control = false,
}) async {
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  await _frames(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await _frames(tester);
}

({int paragraph, int offset, int? anchor, int? anchorParagraph}) _selection(
  WordEditorController controller,
) => (
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchor: controller.caret.selectionAnchor,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
);

Finder _menuText(String text) =>
    find.descendant(of: find.byKey(_menuKey), matching: find.text(text));

Future<void> _closeModal(WidgetTester tester, Future<void>? closed) async {
  if (closed == null) return;
  // A failed assertion may run cleanup before the just-pushed dialog builds.
  await tester.pump();
  if (find.byType(AlertDialog).evaluate().isNotEmpty) {
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await closed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'keyboard correction preserves an explicitly selected overlapping finding',
    (tester) async {
      final h = _Harness(
        text: 'Feler',
        ordinary: _KeyboardProvider(
          'overlap',
          tokens: const {
            'Feler': (OfficeProofingCategory.spelling, 'Spelling choice'),
            'F.ler': (OfficeProofingCategory.grammar, 'Grammar choice'),
          },
        ),
      );
      try {
        await h.mount(tester);
        final issues = h.controller.proofing.summary.issues;
        expect(issues, hasLength(2));
        final selected = issues.last;
        final replacement = selected.finding.replacements.single;
        h.controller.selectProofingIssue(selected);
        await h.focusDocument(tester);
        expect(h.controller.selectedProofingIssue, same(selected));
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.f10, shift: true);
        expect(_menuText(replacement), findsOneWidget);
        expect(
          _menuText(issues.first.finding.replacements.single),
          findsNothing,
        );
        expect(_selection(h.controller), before);
        await _chord(tester, LogicalKeyboardKey.enter);
        expect(h.controller.document.paragraphs.single.text, replacement);
        expect(h.controller.canUndo, isTrue);
        expect(h.focus.hasPrimaryFocus, isTrue);
        h.controller.undo();
        await _frames(tester);
        expect(h.controller.document.paragraphs.single.text, 'Feler');
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'keyboard change decisions preserve the selected adjacent revision',
    (tester) async {
      final document = _document('AAABBB');
      for (final (start, end, text, author) in [
        (0, 3, 'AAA', 'Mira'),
        (3, 6, 'BBB', 'Noor'),
      ]) {
        WordRevisions.record(
          document,
          kind: WmlRevisionKind.insert,
          paragraph: document.paragraphs.single,
          paragraphIndex: 0,
          start: start,
          end: end,
          text: text,
          author: author,
        );
      }
      final h = _Harness(document: document);
      try {
        await h.mount(tester);
        expect(document.revisions, hasLength(2));
        final next = document.revisions.last;
        h.controller.selectRevision(document.revisions.first);
        await h.focusDocument(tester);
        expect(h.controller.caret.selectionAnchor, 0);
        expect(h.controller.caret.logicalIndex, 3);
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.f10, shift: true);
        expect(_menuText('Inserted by Mira'), findsOneWidget);
        expect(_menuText('Inserted by Noor'), findsNothing);
        expect(_selection(h.controller), before);
        await _chord(tester, LogicalKeyboardKey.enter);
        expect(document.revisions, [same(next)]);
        expect(document.revisions.single.author, 'Noor');
        expect(document.paragraphs.single.text, 'AAABBB');
        expect(h.controller.canUndo, isTrue);
        h.controller.undo();
        await _frames(tester);
        expect(document.revisions.map((revision) => revision.author), [
          'Mira',
          'Noor',
        ]);
        expect(
          document.revisions.every((revision) => revision.accepted == null),
          isTrue,
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('covered pane shortcuts cannot navigate, check or close review', (
    tester,
  ) async {
    final manual = _KeyboardProvider('identity-manual');
    final h = _Harness(text: 'Feler Gramar Feler Gramar', manual: manual);
    Future<void>? closed;
    try {
      await h.mount(tester);
      h.controller.openReviewPane();
      await _frames(tester);
      await _tap(tester, _key('live-proofing-filter'));
      await _tap(tester, find.text('Grammar').last);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      final before = h.controller.selectedProofingIssue;
      final beforeCaret = _selection(h.controller);
      final paneFocus = FocusManager.instance.primaryFocus!;
      closed = showDialog<void>(
        context: tester.element(find.byType(QudsWordEditor)),
        requestFocus: false,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(content: Text('Covered route')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(paneFocus.hasPrimaryFocus, isTrue);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      expect(h.controller.selectedProofingIssue, same(before));
      expect(_selection(h.controller), beforeCaret);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(before));
      expect(_selection(h.controller), beforeCaret);
      await _chord(tester, LogicalKeyboardKey.f7);
      expect(manual.requests, isEmpty);
      await _chord(tester, LogicalKeyboardKey.escape);
      expect(h.controller.selectedProofingIssue, same(before));
      expect(_selection(h.controller), beforeCaret);
      expect(manual.requests, isEmpty);
      expect(h.controller.reviewPaneVisible, isTrue);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        h.controller.document.paragraphs.single.text,
        'Feler Gramar Feler Gramar',
      );
      expect(h.controller.canUndo, isFalse);
    } finally {
      await _closeModal(tester, closed);
      await h.close(tester);
    }
  });

  testWidgets(
    'an open keyboard menu cannot act after its origin route is covered',
    (tester) async {
      final h = _Harness(text: 'Feler');
      Future<void>? closed;
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 2);
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.contextMenu);
        expect(_menuText('Fehler'), findsOneWidget);
        expect(h.focus.hasPrimaryFocus, isFalse);
        closed = showDialog<void>(
          context: tester.element(find.byType(QudsWordEditor)),
          requestFocus: false,
          barrierDismissible: false,
          builder: (context) =>
              const AlertDialog(content: Text('Covered menu')),
        );
        // The previous overlay may still own focus before the route-change
        // frame dismisses it. Its command must reject that inactive origin.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(h.controller.document.paragraphs.single.text, 'Feler');
        expect(h.controller.canUndo, isFalse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(_menuKey), findsNothing);
        await _chord(tester, LogicalKeyboardKey.enter);
        await _chord(tester, LogicalKeyboardKey.escape);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(h.controller.document.paragraphs.single.text, 'Feler');
        expect(_selection(h.controller), before);
        expect(h.controller.canUndo, isFalse);
      } finally {
        await _closeModal(tester, closed);
        await h.close(tester);
      }
    },
  );
}
