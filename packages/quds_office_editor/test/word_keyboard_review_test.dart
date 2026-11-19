import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

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
    await tester.pump(const Duration(milliseconds: 450));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('Alt F7 opens writing and wraps without invoking manual tools', (
    tester,
  ) async {
    final manual = _KeyboardProvider('keyboard-manual');
    final h = _Harness(manual: manual);
    try {
      await h.mount(tester);
      final issues = h.controller.proofing.summary.issues;
      expect(issues, hasLength(3));
      await h.focusDocument(tester, offset: 1);
      for (final index in [1, 2, 0]) {
        await _chord(tester, LogicalKeyboardKey.f7, alt: true);
        expect(h.controller.selectedProofingIssue, same(issues[index]));
        expect(h.controller.caret.selectionAnchor, issues[index].finding.start);
        expect(h.controller.caret.logicalIndex, issues[index].finding.end);
      }
      expect(_key('word-review-pane'), findsOneWidget);
      expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(find.byType(Dialog), findsNothing);
      expect(manual.requests, isEmpty);
      expect(h.focus.hasPrimaryFocus, isTrue);
      expect(h.controller.input.isAttached, isTrue);
      expect(h.controller.canUndo, isFalse);
      expect(h.controller.document.paragraphs.single.text, 'Feler Feler Feler');
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('Alt Shift F7 navigates backwards and wraps at the first issue', (
    tester,
  ) async {
    final manual = _KeyboardProvider('keyboard-manual');
    final h = _Harness(manual: manual);
    try {
      await h.mount(tester);
      final issues = h.controller.proofing.summary.issues;
      await h.focusDocument(tester, offset: 1);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(issues.last));
      await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(issues[1]));
      expect(manual.requests, isEmpty);
      expect(h.controller.canUndo, isFalse);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('issue navigation with no findings opens a usable writing pane', (
    tester,
  ) async {
    final manual = _KeyboardProvider('keyboard-manual');
    final h = _Harness(text: 'Clear text.', manual: manual);
    try {
      await h.mount(tester);
      await h.focusDocument(tester, offset: 4);
      final before = _selection(h.controller);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(h.controller.selectedProofingIssue, isNull);
      expect(_selection(h.controller), before);
      expect(manual.requests, isEmpty);
      expect(h.controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'review navigation and context shortcuts preserve active IME composition',
    (tester) async {
      final manual = _KeyboardProvider('keyboard-manual');
      final h = _Harness(manual: manual);
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 3);
        const composing = TextEditingValue(
          text: 'Feler Feler Feler',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 5),
        );
        h.controller.input.setValue(composing);
        final before = _selection(h.controller);
        final selected = h.controller.selectedProofingIssue;
        await _chord(tester, LogicalKeyboardKey.f7, alt: true);
        await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
        await _chord(tester, LogicalKeyboardKey.f10, shift: true);
        await _chord(tester, LogicalKeyboardKey.contextMenu);
        expect(h.controller.input.value, composing);
        expect(_selection(h.controller), before);
        expect(h.controller.selectedProofingIssue, same(selected));
        expect(find.byKey(_menuKey), findsNothing);
        expect(h.focus.hasPrimaryFocus, isTrue);
        expect(h.controller.input.isAttached, isTrue);
        expect(manual.requests, isEmpty);
        expect(h.controller.canUndo, isFalse);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('focused Writing filter limits both issue navigation shortcuts', (
    tester,
  ) async {
    final manual = _KeyboardProvider('keyboard-manual');
    final h = _Harness(text: 'Feler Gramar Feler Gramar', manual: manual);
    try {
      await h.mount(tester);
      h.controller.openReviewPane();
      await _frames(tester);
      await _tap(tester, _key('live-proofing-filter'));
      await _tap(tester, find.text('Grammar').last);
      expect(h.focus.hasPrimaryFocus, isFalse);
      final paneFocus = FocusManager.instance.primaryFocus!;
      final grammar = h.controller.proofing.summary.issues
          .where(
            (issue) => issue.finding.category == OfficeProofingCategory.grammar,
          )
          .toList();
      expect(grammar, hasLength(2));
      h.controller.selectProofingIssue(grammar.first);
      paneFocus.requestFocus();
      await _frames(tester);
      expect(paneFocus.hasPrimaryFocus, isTrue);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      expect(h.controller.selectedProofingIssue, same(grammar.last));
      expect(h.focus.hasPrimaryFocus, isFalse);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      expect(h.controller.selectedProofingIssue, same(grammar.first));
      expect(h.focus.hasPrimaryFocus, isFalse);
      await _chord(tester, LogicalKeyboardKey.f7, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(grammar.last));
      expect(h.focus.hasPrimaryFocus, isFalse);
      expect(manual.requests, isEmpty);
      expect(h.controller.canUndo, isFalse);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('issue navigation from a Changes search field opens Writing', (
    tester,
  ) async {
    final manual = _KeyboardProvider('keyboard-manual');
    final h = _Harness(manual: manual);
    try {
      await h.mount(tester);
      h.controller.openReviewPane(tab: WordReviewPaneTab.changes);
      await _frames(tester);
      await _tap(tester, _key('live-review-filters'));
      await tester.enterText(_key('live-review-search'), 'Reviewer text');
      await _frames(tester);
      expect(h.focus.hasPrimaryFocus, isFalse);
      final before = h.controller.document.paragraphs.single.text;
      await _chord(tester, LogicalKeyboardKey.f7, alt: true);
      expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(_key('live-review-proofing-content'), findsOneWidget);
      expect(h.controller.selectedProofingIssue, isNotNull);
      expect(h.controller.document.paragraphs.single.text, before);
      expect(manual.requests, isEmpty);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'ordinary shortcuts in a focused reviewer field edit only the field',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 2);
        final before = _selection(h.controller);
        h.controller.openReviewPane(tab: WordReviewPaneTab.changes);
        await _frames(tester);
        await tester.enterText(_key('live-review-author'), 'Original reviewer');
        await _chord(tester, LogicalKeyboardKey.keyA, control: true);
        final field = tester.widget<TextField>(_key('live-review-author'));
        expect(
          field.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 17),
        );
        await tester.enterText(_key('live-review-author'), 'New reviewer');
        expect(_selection(h.controller), before);
        expect(
          h.controller.document.paragraphs.single.text,
          'Feler Feler Feler',
        );
        expect(h.controller.canUndo, isFalse);
        expect(find.byKey(_menuKey), findsNothing);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'Shift F10 opens suggestions without moving the caret and Enter corrects',
    (tester) async {
      final h = _Harness(text: 'Ein Feler bleibt.');
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 6);
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.f10, shift: true);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(_menuText('Fehler'), findsOneWidget);
        expect(_selection(h.controller), before);
        expect(h.controller.canUndo, isFalse);
        expect(h.focus.hasPrimaryFocus, isFalse);
        await _chord(tester, LogicalKeyboardKey.arrowDown);
        await _chord(tester, LogicalKeyboardKey.arrowUp);
        await _chord(tester, LogicalKeyboardKey.end);
        await _chord(tester, LogicalKeyboardKey.home);
        expect(_selection(h.controller), before);
        await _chord(tester, LogicalKeyboardKey.numpadEnter);
        expect(
          h.controller.document.paragraphs.single.text,
          'Ein Fehler bleibt.',
        );
        expect(find.byKey(_menuKey), findsNothing);
        expect(h.focus.hasPrimaryFocus, isTrue);
        expect(h.controller.input.isAttached, isTrue);
        expect(h.controller.canUndo, isTrue);
        h.controller.undo();
        await _frames(tester);
        expect(
          h.controller.document.paragraphs.single.text,
          'Ein Feler bleibt.',
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'Context Menu key and Escape restore canvas focus and text input',
    (tester) async {
      final h = _Harness(text: 'Feler');
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 2);
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.contextMenu);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(_menuText('Fehler'), findsOneWidget);
        await _chord(tester, LogicalKeyboardKey.escape);
        expect(find.byKey(_menuKey), findsNothing);
        expect(_selection(h.controller), before);
        expect(h.focus.hasPrimaryFocus, isTrue);
        expect(h.controller.input.isAttached, isTrue);
        await _chord(tester, LogicalKeyboardKey.contextMenu);
        expect(find.byKey(_menuKey), findsOneWidget);
        await _chord(tester, LogicalKeyboardKey.tab);
        expect(find.byKey(_menuKey), findsNothing);
        expect(_selection(h.controller), before);
        expect(h.focus.hasPrimaryFocus, isTrue);
        expect(h.controller.input.isAttached, isTrue);
        tester.testTextInput.enterText('Typing still works.');
        await _frames(tester);
        expect(
          h.controller.document.paragraphs.single.text,
          'Typing still works.',
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'selected issue ending at the next issue uses its own keyboard correction',
    (tester) async {
      final h = _Harness(text: 'FelerFeler');
      try {
        await h.mount(tester);
        final issues = h.controller.proofing.summary.issues;
        expect(issues, hasLength(2));
        h.controller.selectProofingIssue(issues.first);
        await h.focusDocument(tester);
        final before = _selection(h.controller);
        expect(before.anchor, 0);
        expect(before.offset, 5);
        await _chord(tester, LogicalKeyboardKey.f10, shift: true);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(_selection(h.controller), before);
        await _chord(tester, LogicalKeyboardKey.enter);
        expect(h.controller.document.paragraphs.single.text, 'FehlerFeler');
        h.controller.undo();
        await _frames(tester);
        expect(h.controller.document.paragraphs.single.text, 'FelerFeler');
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('a short unfiltered context menu supports arrows and Enter', (
    tester,
  ) async {
    final h = _Harness(text: 'Clear text.');
    try {
      await h.mount(tester);
      await h.focusDocument(tester, offset: 3);
      final before = _selection(h.controller);
      await _chord(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byKey(_menuKey), findsOneWidget);
      expect(_menuText('Type to search'), findsNothing);
      expect(h.focus.hasPrimaryFocus, isFalse);
      await _chord(tester, LogicalKeyboardKey.arrowDown);
      await _chord(tester, LogicalKeyboardKey.arrowUp);
      await _chord(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(_menuKey), findsNothing);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(_selection(h.controller), before);
      expect(h.focus.hasPrimaryFocus, isTrue);
      expect(h.controller.input.isAttached, isTrue);
      expect(h.controller.canUndo, isFalse);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('source edits dismiss a keyboard suggestion before it can act', (
    tester,
  ) async {
    final h = _Harness(text: 'Feler');
    try {
      await h.mount(tester);
      await h.focusDocument(tester, offset: 2);
      await _chord(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byKey(_menuKey), findsOneWidget);
      h.controller.applyImeText('Current text');
      await _frames(tester);
      expect(find.byKey(_menuKey), findsNothing);
      expect(h.focus.hasPrimaryFocus, isTrue);
      expect(h.controller.input.isAttached, isTrue);
      expect(h.controller.document.paragraphs.single.text, 'Current text');
      expect(h.controller.proofing.summary.issues, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  });

  for (final protection in ['viewing', 'document protection']) {
    testWidgets(
      '$protection keeps keyboard findings inspectable without correction',
      (tester) async {
        final document = _document('Feler');
        if (protection == 'document protection') {
          document
            ..restrictEditing = true
            ..restrictMode = WmlRestrictMode.readOnly;
        }
        final h = _Harness(
          document: document,
          viewing: protection == 'viewing',
        );
        try {
          await h.mount(tester);
          await h.focusDocument(tester, offset: 2);
          expect(h.controller.proofing.summary.issues, hasLength(1));
          expect(
            h.controller.canApplyProofingIssue(
              h.controller.proofing.summary.issues.single,
            ),
            isFalse,
          );
          await _chord(tester, LogicalKeyboardKey.contextMenu);
          expect(find.byKey(_menuKey), findsOneWidget);
          expect(_menuText('Fehler'), findsOneWidget);
          // The first enabled command is Ignore once, after the disabled
          // correction. Keyboard activation must skip the disabled action.
          await _chord(tester, LogicalKeyboardKey.enter);
          expect(h.controller.proofing.hasIgnoredOccurrences, isTrue);
          expect(document.paragraphs.single.text, 'Feler');
          expect(h.controller.canUndo, isFalse);
          expect(find.byKey(_menuKey), findsNothing);
          expect(h.focus.hasPrimaryFocus, isTrue);
        } finally {
          await h.close(tester);
        }
      },
    );
  }

  testWidgets(
    'keyboard context resolves the current tracked change with Undo',
    (tester) async {
      final document = _document('A fresh addition.');
      WordRevisions.record(
        document,
        kind: WmlRevisionKind.insert,
        paragraph: document.paragraphs.single,
        paragraphIndex: 0,
        start: 2,
        end: 7,
        text: 'fresh',
        author: 'Mira',
      );
      final h = _Harness(document: document);
      try {
        await h.mount(tester);
        await h.focusDocument(tester, offset: 4);
        final before = _selection(h.controller);
        await _chord(tester, LogicalKeyboardKey.contextMenu);
        expect(_menuText('Inserted by Mira'), findsOneWidget);
        expect(_menuText('Accept change'), findsOneWidget);
        expect(_selection(h.controller), before);
        await _chord(tester, LogicalKeyboardKey.enter);
        expect(document.revisions, isEmpty);
        expect(document.paragraphs.single.text, 'A fresh addition.');
        expect(h.controller.canUndo, isTrue);
        expect(h.focus.hasPrimaryFocus, isTrue);
        h.controller.undo();
        await _frames(tester);
        expect(document.revisions, hasLength(1));
        expect(document.revisions.single.accepted, isNull);
        expect(document.revisions.single.author, 'Mira');
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'Check document upgrades a held background check and shares its full result',
    (tester) async {
      final backgroundGate = Completer<void>();
      final manualGate = Completer<void>();
      final ordinary = _KeyboardProvider('keyboard-ordinary')
        ..gates[1] = backgroundGate;
      final manual = _KeyboardProvider(
        'keyboard-manual',
        tokens: const {'Manual': (OfficeProofingCategory.style, 'Reviewed')},
      )..gates[1] = manualGate;
      final h = _Harness(
        text: 'Feler Manual',
        ordinary: ordinary,
        manual: manual,
      );
      try {
        await h.mount(tester);
        expect(ordinary.requests, hasLength(1));
        expect(h.controller.proofing.checking, isTrue);
        h.controller.openReviewPane();
        await _frames(tester);
        final button = _key('live-proofing-check');
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        await _tap(tester, button);
        expect(ordinary.requests, hasLength(2));
        expect(manual.requests, hasLength(1));
        expect(h.controller.proofing.checking, isTrue);
        expect(backgroundGate.isCompleted, isFalse);
        await _tap(tester, button);
        await _tap(tester, button);
        expect(ordinary.requests, hasLength(2));
        expect(manual.requests, hasLength(1));
        manualGate.complete();
        await _frames(tester);
        final full = h.controller.proofing.summary;
        expect(full.complete, isTrue);
        expect(full.manualProvidersSkipped, isFalse);
        expect(full.issues.map((issue) => issue.finding.providerId).toSet(), {
          ordinary.id,
          manual.id,
        });
        backgroundGate.complete();
        await _frames(tester);
        expect(h.controller.proofing.summary, same(full));
        expect(h.controller.proofing.summary.manualProvidersSkipped, isFalse);
        expect(h.controller.document.paragraphs.single.text, 'Feler Manual');
        expect(h.controller.canUndo, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );
}
