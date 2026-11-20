import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

class _PaneProvider extends OfficeProofingProvider {
  _PaneProvider({
    this.providerId = 'pane-test',
    this.status = OfficeProofingStatus.success,
    this.gate,
  });

  final String providerId;
  final OfficeProofingStatus status;
  final Future<void>? gate;
  final List<OfficeProofingRequest> requests = <OfficeProofingRequest>[];

  @override
  String get id => providerId;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (gate != null) await gate;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : 'The local checker is unavailable.',
      findings: <OfficeProofingFinding>[
        if (status == OfficeProofingStatus.success)
          for (final match in RegExp('Feler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'test.spelling',
              message: 'Check this spelling.',
              category: OfficeProofingCategory.spelling,
              replacements: const <String>['Fehler'],
            ),
        if (status == OfficeProofingStatus.success &&
            request.text.contains('is are'))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: request.text.indexOf('is are'),
            end: request.text.indexOf('is are') + 6,
            ruleId: 'test.grammar',
            message: 'Use one verb.',
            category: OfficeProofingCategory.grammar,
            replacements: const <String>['is'],
          ),
      ],
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

WordEditorController _controller({
  String text = 'Ein Feler.',
  WmlDocument? document,
  _PaneProvider? provider,
  OfficeSurfaceConfig? config,
}) => WordEditorController(
  document: document ?? WmlDocument.empty(text: text),
  config: config,
  proofingService: OfficeProofingService(
    providers: <OfficeProofingProvider>[provider ?? _PaneProvider()],
  ),
);

Future<void> _mount(
  WidgetTester tester,
  WordEditorController controller, {
  WordReviewPaneTab tab = WordReviewPaneTab.proofing,
  Size size = const Size(380, 760),
  double textScale = 1,
  bool canvas = false,
  FocusNode? focus,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = canvas ? const Size(1200, 900) : size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus?.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: canvas
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: QudsWordEditor(
                      controller: controller,
                      focusNode: focus,
                    ),
                  ),
                  SizedBox(
                    width: size.width,
                    child: WordReviewPane(
                      controller: controller,
                      initialTab: tab,
                      onClose: () {},
                      onMoreOptions: () {},
                    ),
                  ),
                ],
              )
            : WordReviewPane(
                controller: controller,
                initialTab: tab,
                onClose: () {},
                onMoreOptions: () {},
              ),
      ),
    ),
  );
  await _drain(tester);
}

Future<void> _drain(WidgetTester tester) async {
  // An actual document canvas has an active caret ticker. Advance a bounded
  // number of frames rather than waiting for every animation to settle.
  await tester.pump(_debounce);
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find
          .descendant(
            of: _key('word-review-pane'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await _drain(tester);
  expect(tester.takeException(), isNull);
}

String _text(WidgetTester tester, String key) {
  final text = tester.widget<Text>(_key(key));
  return text.data ?? text.textSpan!.toPlainText();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'editing stays available while live findings update in the pane',
    (tester) async {
      final provider = _PaneProvider();
      final controller = _controller(provider: provider);
      controller.proofing.enabled = true;
      final focus = FocusNode(debugLabel: 'review-pane-document');
      await _mount(tester, controller, canvas: true, focus: focus);
      expect(_text(tester, 'live-proofing-message'), 'Check this spelling.');
      expect(find.byType(Dialog), findsNothing);

      focus.requestFocus();
      await tester.pump();
      expect(controller.input.isAttached, isTrue);
      tester.testTextInput.enterText('Ein Fehler. Noch ein Feler.');
      await _drain(tester);
      expect(
        controller.document.paragraphs.single.text,
        'Ein Fehler. Noch ein Feler.',
      );
      expect(controller.proofing.summary.issues.single.finding.start, 21);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await _tap(tester, _key('live-proofing-replace-0'));
      expect(
        controller.document.paragraphs.single.text,
        'Ein Fehler. Noch ein Fehler.',
      );
      expect(controller.proofing.summary.issues, isEmpty);
      await _tap(tester, _key('live-review-undo'));
      expect(
        controller.document.paragraphs.single.text,
        'Ein Fehler. Noch ein Feler.',
      );
      expect(controller.proofing.summary.issues, hasLength(1));
    },
  );

  testWidgets('opening and correcting do not implicitly run manual providers', (
    tester,
  ) async {
    final controller = _controller();
    final manual = _PaneProvider(providerId: 'manual-pane-test');
    controller.proofing.configureManual(
      OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
    );
    await _mount(tester, controller);
    expect(manual.requests, isEmpty);
    expect(controller.proofing.summary.manualProvidersSkipped, isTrue);
    expect(
      _text(tester, 'live-proofing-status'),
      contains('manual grammar check'),
    );
    await _tap(tester, _key('live-proofing-check'));
    expect(manual.requests, hasLength(1));
    await _tap(tester, _key('live-proofing-replace-0'));
    expect(controller.document.paragraphs.single.text, 'Ein Fehler.');
    expect(manual.requests, hasLength(1));
    expect(controller.proofing.summary.manualProvidersSkipped, isTrue);
  });

  testWidgets(
    'unavailable provider status is not presented as a clean document',
    (tester) async {
      final controller = _controller(
        provider: _PaneProvider(status: OfficeProofingStatus.unavailable),
      );
      await _mount(tester, controller);
      expect(
        _text(tester, 'live-proofing-provider-status'),
        contains('unavailable'),
      );
      expect(
        _text(tester, 'live-proofing-empty'),
        'No findings to display. Check coverage above.',
      );
      expect(
        find.text('No issues found by the configured providers.'),
        findsNothing,
      );
      expect(controller.proofing.summary.complete, isFalse);
    },
  );

  testWidgets('a suggestion captured before an edit cannot change newer text', (
    tester,
  ) async {
    final controller = _controller();
    await _mount(tester, controller);
    await tester.ensureVisible(_key('live-proofing-replace-0'));
    final staleAction = tester
        .widget<OutlinedButton>(_key('live-proofing-replace-0'))
        .onPressed!;
    controller.selectAll();
    controller.insertText('Already corrected.');
    staleAction();
    await _drain(tester);
    expect(controller.document.paragraphs.single.text, 'Already corrected.');
    expect(
      _text(tester, 'live-review-notice'),
      contains('text changed or is protected'),
    );
  });

  testWidgets('category filtering navigates only matching findings', (
    tester,
  ) async {
    final controller = _controller(text: 'Feler is are Feler.');
    await _mount(tester, controller);
    expect(controller.proofing.summary.issues, hasLength(3));
    await _tap(tester, _key('live-proofing-filter'));
    await _tap(tester, find.text('Grammar').last);
    expect(_text(tester, 'live-proofing-message'), 'Use one verb.');
    await _tap(tester, _key('live-proofing-next'));
    expect(
      controller.selectedProofingIssue!.finding.category,
      OfficeProofingCategory.grammar,
    );
    await _tap(tester, _key('live-proofing-ignore-rule'));
    expect(controller.proofing.ignoredRuleIds, contains('test.grammar'));
  });

  testWidgets('tracked changes resolve in place and undo restores them', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Keep obsolete');
    WordRevisions.record(
      document,
      kind: WmlRevisionKind.delete,
      paragraphIndex: 0,
      paragraph: document.paragraphs.single,
      start: 4,
      end: 13,
      text: ' obsolete',
      author: 'Alice',
    );
    final controller = _controller(document: document);
    await _mount(tester, controller, tab: WordReviewPaneTab.changes);
    expect(_text(tester, 'live-review-selected-text'), ' obsolete');
    await _tap(tester, _key('live-review-accept'));
    expect(document.paragraphs.single.text, 'Keep');
    expect(_key('live-review-empty'), findsOneWidget);
    await _tap(tester, _key('live-review-undo'));
    expect(document.paragraphs.single.text, 'Keep obsolete');
    expect(controller.selectedRevision?.accepted, isNull);
    await _tap(tester, _key('live-review-reject'));
    expect(document.paragraphs.single.text, 'Keep obsolete');
    expect(_key('live-review-empty'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'reviewer field affects future attribution and leaves document alone',
    (tester) async {
      final controller = _controller(text: 'Keep this document');
      final focus = FocusNode(debugLabel: 'review-pane-author-document');
      await _mount(
        tester,
        controller,
        tab: WordReviewPaneTab.changes,
        canvas: true,
        focus: focus,
      );
      focus.requestFocus();
      await tester.pump();
      await tester.enterText(_key('live-review-author'), 'Mira');
      await _tap(tester, _key('live-review-set-author'));
      expect(controller.revisionAuthor, 'Mira');
      expect(controller.document.paragraphs.single.text, 'Keep this document');
      await _tap(tester, _key('live-review-track'));
      focus.requestFocus();
      await tester.pump();
      controller.caret
        ..logicalIndex = 0
        ..collapseSelection();
      controller.insertText('New ');
      await _drain(tester);
      expect(controller.document.revisions.last.author, 'Mira');
      expect(_key('live-review-selected-text'), findsOneWidget);
    },
  );

  testWidgets(
    'viewing mode allows inspection while disabling document mutations',
    (tester) async {
      final controller = _controller(
        config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
      );
      await _mount(tester, controller);
      expect(_enabled(tester, 'live-proofing-replace-0'), isFalse);
      await _tap(tester, _key('live-review-changes-tab'));
      expect(
        tester.widget<SwitchListTile>(_key('live-review-track')).onChanged,
        isNull,
      );
      expect(
        tester.widget<TextField>(_key('live-review-author')).enabled,
        isFalse,
      );
      expect(controller.document.paragraphs.single.text, 'Ein Feler.');
    },
  );

  testWidgets(
    'stale checks stay pending until a current provider result arrives',
    (tester) async {
      final gate = Completer<void>();
      final provider = _PaneProvider(gate: gate.future);
      final controller = _controller(provider: provider);
      controller.proofing.enabled = true;
      await _mount(tester, controller);
      expect(_key('live-proofing-progress'), findsOneWidget);
      // An explicit full check remains available while background work runs.
      expect(_enabled(tester, 'live-proofing-check'), isTrue);
      controller.selectAll();
      controller.insertText('Current clean text');
      await _drain(tester);
      gate.complete();
      await _drain(tester);
      expect(controller.proofing.summary.issues, isEmpty);
      expect(_key('live-proofing-replace-0'), findsNothing);
      expect(
        _text(tester, 'live-proofing-status'),
        contains('No issues found'),
      );
    },
  );

  for (final arabic in <bool>[false, true]) {
    testWidgets(
      'narrow ${arabic ? 'Arabic' : 'English'} pane remains scrollable',
      (tester) async {
        final controller = _controller(
          config: OfficeSurfaceConfig(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          ),
        );
        await _mount(
          tester,
          controller,
          size: const Size(280, 240),
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, _key('live-proofing-replace-0'));
        expect(controller.document.paragraphs.single.text, 'Ein Fehler.');
        await _tap(tester, _key('live-review-changes-tab'));
        final paneScroll = tester
            .widget<ListView>(_key('live-review-changes-content'))
            .controller!;
        expect(paneScroll.offset, 0);
        await _reveal(tester, _key('live-review-author'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
