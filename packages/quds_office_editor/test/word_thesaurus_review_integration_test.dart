import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'support/thesaurus_fixture.dart';

final class _ReviewProvider extends OfficeProofingProvider {
  _ReviewProvider(this.id);

  @override
  final String id;
  final List<OfficeProofingRequest> requests = <OfficeProofingRequest>[];

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: <OfficeProofingFinding>[
        for (final match in RegExp('bank').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'review-thesaurus.fixture',
            start: match.start,
            end: match.end,
            category: OfficeProofingCategory.spelling,
            message: 'Synthetic finding for keyboard navigation.',
            replacements: const <String>['depository'],
          ),
      ],
    );
  }
}

final class _Harness {
  _Harness({
    bool arabic = false,
    this.size = const Size(390, 1000),
    this.textScale = 1.5,
  }) {
    controller = WordEditorController(
      document: WmlDocument(
        proofingLanguage: 'en-US',
        sections: <WmlSection>[
          WmlSection(
            pageSize: const WmlPageSize(width: 500, height: 620),
            margins: const WmlPageMargins(
              top: 50,
              bottom: 50,
              left: 48,
              right: 48,
            ),
            blocks: <WmlBlock>[
              WmlParagraph(
                inlines: <WmlInline>[WmlRun(text: 'bank bank bank')],
              ),
            ],
          ),
        ],
      ),
      config: OfficeSurfaceConfig(
        showRulers: false,
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      ),
      proofingService: OfficeProofingService(
        providers: <OfficeProofingProvider>[ordinary],
      ),
    );
    controller.proofing.configureManual(
      OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
    );
  }

  final _ReviewProvider ordinary = _ReviewProvider('integration-ordinary');
  final _ReviewProvider manual = _ReviewProvider('integration-manual');
  late final WordEditorController controller;
  final FocusNode focus = FocusNode(debugLabel: 'review-thesaurus-document');
  final Size size;
  final double textScale;

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() async {
      // Unmount the canvas and its caret ticker before disposing its owners.
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
      await tester.pump();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Liberation Sans'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: QudsWordEditor(
            controller: controller,
            focusNode: focus,
            thesaurusService: testThesaurusService(
              assets: <String, String>{
                ...thesaurusFixtureAssets(),
                ...thesaurusFixtureAssets(locale: 'de'),
              },
            ),
          ),
        ),
      ),
    );
    await _flush(tester);
  }

  Future<void> selectFirstWord(WidgetTester tester) async {
    controller.caret
      ..paragraphIndex = 0
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 0
      ..logicalIndex = 4;
    controller.refreshView();
    await tester.pump();
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _flush(WidgetTester tester) async {
  // A Word canvas keeps a caret ticker alive, so pumpAndSettle is unsuitable.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await _frames(tester);
}

void _expectReachable(WidgetTester tester, String key, Rect bounds) {
  final finder = _key(key);
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: '$key must be reachable',
  );
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
  expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
  expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
  final button = tester.widget<Widget>(finder);
  if (button is IconButton) {
    expect(button.onPressed, isNotNull);
  } else if (button is ButtonStyleButton) {
    expect(button.onPressed, isNotNull);
  } else {
    fail('$key must identify an enabled review action');
  }
}

void _expectStatusActions(WidgetTester tester) {
  final bounds = tester.getRect(_key('word-review-status'));
  for (final key in <String>[
    'word-review-writing-status',
    'word-review-language-status',
    'word-review-changes-status',
    'word-review-thesaurus',
  ]) {
    _expectReachable(tester, key, bounds);
  }
  expect(tester.takeException(), isNull);
}

void _expectPaneActions(WidgetTester tester) {
  final bounds = tester.getRect(_key('word-review-pane'));
  for (final key in <String>[
    'live-review-thesaurus',
    'live-review-more',
    'live-review-close',
  ]) {
    _expectReachable(tester, key, bounds);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, String key) async {
  expect(_key(key).hitTestable(), findsOneWidget);
  await tester.tap(_key(key));
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

void _expectLookup(WidgetTester tester, String language) {
  expect(find.byType(WordThesaurusDialog), findsOneWidget);
  expect(tester.widget<SelectableText>(_key('thesaurus-query')).data, 'bank');
  expect(
    tester.widget<DropdownButton<String>>(_key('thesaurus-language')).value,
    language,
  );
  expect(_key('thesaurus-summary'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _closeLookup(WidgetTester tester) async {
  final close = find.byTooltip('Close thesaurus');
  expect(close.hitTestable(), findsOneWidget);
  await tester.tap(close);
  await _flush(tester);
  expect(find.byType(WordThesaurusDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _f7(
  WidgetTester tester, {
  bool alt = false,
  bool shift = false,
}) async {
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  await _flush(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final arabic in <bool>[false, true]) {
    testWidgets(
      '390px ${arabic ? 'Arabic RTL' : 'English'} review keeps language and '
      'thesaurus actions usable at 1.5x text',
      (tester) async {
        final h = _Harness(arabic: arabic);
        await h.mount(tester);
        await h.selectFirstWord(tester);
        final initialRevision = h.controller.contentRevision;
        _expectStatusActions(tester);
        expect(tester.getRect(_key('word-review-status')).width, 390);

        await _tap(tester, 'word-review-writing-status');
        expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
        _expectStatusActions(tester);
        _expectPaneActions(tester);

        await _tap(tester, 'live-review-thesaurus');
        _expectLookup(tester, 'en-US');
        expect(h.controller.contentRevision, initialRevision);
        expect(h.controller.canUndo, isFalse);
        await _closeLookup(tester);

        await _tap(tester, 'word-review-language-status');
        expect(h.controller.reviewTextProofingOptionsVisible, isTrue);
        expect(
          _key('live-proofing-text-language').hitTestable(),
          findsOneWidget,
        );
        _expectStatusActions(tester);
        _expectPaneActions(tester);
        await _tap(tester, 'live-proofing-text-language');
        final german = find.text('Deutsch (Deutschland)').last;
        await tester.ensureVisible(german);
        await tester.pump();
        await tester.tap(german);
        await _flush(tester);
        expect(tester.takeException(), isNull);
        expect(
          WmlRunEdit.propsAt(
            h.controller.document.paragraphs.single,
            1,
          ).proofingLanguage,
          'de-DE',
        );
        expect(h.controller.document.proofingLanguage, 'en-US');
        expect(h.controller.caret.selectionAnchor, 0);
        expect(h.controller.caret.logicalIndex, 4);
        expect(h.controller.canUndo, isTrue);

        // The status entry point must capture the newly chosen text language.
        await _tap(tester, 'word-review-thesaurus');
        _expectLookup(tester, 'de-DE');
        await _closeLookup(tester);
        _expectStatusActions(tester);
        _expectPaneActions(tester);

        await _tap(tester, 'word-review-changes-status');
        expect(h.controller.reviewPaneTab, WordReviewPaneTab.changes);
        _expectStatusActions(tester);
        _expectPaneActions(tester);
        await _tap(tester, 'word-review-writing-status');
        expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
        await _tap(tester, 'live-review-close');
        expect(_key('word-review-pane'), findsNothing);
        _expectStatusActions(tester);

        h.controller.undo();
        await _flush(tester);
        expect(h.controller.canUndo, isFalse);
        expect(h.controller.document.paragraphs.single.text, 'bank bank bank');
        expect(h.controller.textProofingTarget?.language, 'en-US');
        expect(h.manual.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Alt Shift F7 keeps reverse review navigation while Shift F7 opens thesaurus',
    (tester) async {
      final h = _Harness(size: const Size(1120, 960), textScale: 1);
      await h.mount(tester);
      final issues = h.controller.proofing.summary.issues;
      expect(issues, hasLength(3));
      final initialRevision = h.controller.contentRevision;
      var spellCheckRequests = 0;
      h.controller.onSpellCheckRequested = () {
        spellCheckRequests++;
      };
      h.controller.selectProofingIssue(issues.first);
      h.focus.requestFocus();
      await _frames(tester);

      await _f7(tester, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(issues.last));
      expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(find.byType(WordThesaurusDialog), findsNothing);
      expect(spellCheckRequests, 0);

      // Exercise the retained Focus wrapper as well as the document shortcut.
      final paneFocus = Focus.of(tester.element(_key('live-review-thesaurus')));
      paneFocus.requestFocus();
      await _frames(tester);
      expect(h.focus.hasPrimaryFocus, isFalse);
      await _f7(tester, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(issues[1]));
      expect(find.byType(WordThesaurusDialog), findsNothing);
      expect(spellCheckRequests, 0);

      await _f7(tester, shift: true);
      _expectLookup(tester, 'en-US');
      expect(h.controller.selectedProofingIssue, same(issues[1]));
      expect(h.controller.caret.selectionAnchor, issues[1].finding.start);
      expect(h.controller.caret.logicalIndex, issues[1].finding.end);
      await _f7(tester, alt: true, shift: true);
      expect(h.controller.selectedProofingIssue, same(issues[1]));
      expect(find.byType(WordThesaurusDialog), findsOneWidget);
      expect(spellCheckRequests, 0);

      await _closeLookup(tester);
      h.focus.requestFocus();
      await _frames(tester);
      await _f7(tester);
      expect(spellCheckRequests, 1);
      expect(find.byType(WordThesaurusDialog), findsNothing);
      expect(h.controller.contentRevision, initialRevision);
      expect(h.controller.canUndo, isFalse);
      expect(h.manual.requests, isEmpty);
      expect(h.controller.document.paragraphs.single.text, 'bank bank bank');
      expect(tester.takeException(), isNull);
    },
  );
}
