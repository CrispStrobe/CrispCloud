import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

const _surfaceKey = ValueKey<String>('live-review-surface');
const _screenshotKey = ValueKey<String>('live-review-screenshot');
const _menuKey = Key('office-context-menu');

class _SurfaceProvider extends OfficeProofingProvider {
  _SurfaceProvider({
    this.providerId = 'surface-proofing',
    this.target = 'Feler',
    this.replacements = const <String>['Fehler'],
    this.gate,
  });

  final String providerId;
  final String target;
  final List<String> replacements;
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
      status: OfficeProofingStatus.success,
      findings: <OfficeProofingFinding>[
        for (final match in RegExp(
          RegExp.escape(target),
        ).allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'surface.spelling',
            start: match.start,
            end: match.end,
            message: 'Check this spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: replacements,
          ),
      ],
    );
  }
}

WmlDocument _document(String text) => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: <WmlSection>[
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 620),
      margins: const WmlPageMargins(top: 50, bottom: 50, left: 48, right: 48),
      blocks: <WmlBlock>[
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]),
      ],
    ),
  ],
);

class _SurfaceHarness {
  _SurfaceHarness({
    String text = 'Ein Feler steht hier. Weiter schreiben.',
    WmlDocument? document,
    _SurfaceProvider? provider,
    OfficeSurfaceConfig? config,
    this.size = const Size(1120, 760),
    this.textScale = 1,
  }) : provider = provider ?? _SurfaceProvider() {
    controller = WordEditorController(
      document: document ?? _document(text),
      config: config ?? const OfficeSurfaceConfig(showRulers: false),
      proofingService: OfficeProofingService(
        providers: <OfficeProofingProvider>[this.provider],
      ),
    );
  }

  final _SurfaceProvider provider;
  final Size size;
  final double textScale;
  late final WordEditorController controller;
  final FocusNode focus = FocusNode(debugLabel: 'live-review-document');

  Future<void> mount(WidgetTester tester, {bool waitForCheck = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: QudsWordEditor(
              key: _surfaceKey,
              controller: controller,
              focusNode: focus,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (waitForCheck) await _flush(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Future<void> focusDocument(WidgetTester tester) async {
    focus.requestFocus();
    await tester.pump();
  }

  Offset point(WidgetTester tester, int index, {int paragraphIndex = 0}) {
    final canvas = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    final lines = controller.documentLaidOut.pages.expand((page) => page.lines);
    final line = lines.firstWhere(
      (line) =>
          line.paragraphIndex == paragraphIndex &&
          line.glyphs.any(
            (glyph) =>
                glyph.glyph.logicalIndex <= index && index < glyph.logicalEnd,
          ),
    );
    final glyph = line.glyphs.firstWhere(
      (glyph) => glyph.glyph.logicalIndex <= index && index < glyph.logicalEnd,
    );
    return canvas.localToGlobal(
      canvas.windowForPagePoint(
        line.pageIndex,
        Offset(glyph.x + glyph.advance * .35, line.y + line.height * .5),
      ),
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(_debounce);
  await _frames(tester);
}

Future<void> _click(
  WidgetTester tester,
  Offset position, {
  bool waitForReview = true,
}) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  if (waitForReview) {
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await _frames(tester);
  }
}

Future<void> _tapPane(WidgetTester tester, String key) async {
  final finder = _key(key);
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
  await tester.tap(finder);
  await _flush(tester);
}

String _text(WidgetTester tester, String key) {
  final text = tester.widget<Text>(_key(key));
  return text.data ?? text.textSpan!.toPlainText();
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final output = Platform.environment['QUDS_REVIEW_SCREENSHOT_DIR'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) throw StateError('Could not capture review surface.');
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    if (bytes == null) throw StateError('Could not encode review surface.');
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

Future<void> _loadSurfaceFonts() async {
  await OfficeHostFonts.ensureRegistered();
  // The package deliberately does not ship MaterialIcons. Use the host SDK's
  // genuine icon font when available, without requiring a machine-local path
  // for ordinary test execution on other hosts.
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final configured = Platform.environment['QUDS_REVIEW_ICON_FONT'];
  final path =
      configured ??
      (sdk == null
          ? null
          : '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (path == null) return;
  final file = File(path);
  if (!await file.exists()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadSurfaceFonts);

  testWidgets(
    'automatic checks show waiting, slow checking and settled status without dialogs',
    (tester) async {
      final gate = Completer<void>();
      final harness = _SurfaceHarness(
        provider: _SurfaceProvider(gate: gate.future),
      );
      try {
        await harness.mount(tester, waitForCheck: false);
        expect(harness.controller.proofing.enabled, isTrue);
        expect(harness.controller.proofing.summary.scheduled, isTrue);
        expect(find.text('Waiting to check…'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        await _flush(tester);
        expect(harness.provider.requests, hasLength(1));
        // A pass shows "Checking…" only once it runs for a while.
        await tester.pump(WordProofingTiming.checkingIndicatorDelay);
        expect(find.text('Checking…'), findsOneWidget);
        gate.complete();
        await _frames(tester);
        expect(harness.controller.proofing.summary.issues, hasLength(1));
        expect(find.text('1 writing issue'), findsOneWidget);
        expect(_key('word-review-pane'), findsNothing);

        await harness.focusDocument(tester);
        tester.testTextInput.enterText('Ein Feler bleibt.');
        await tester.pump();
        expect(harness.controller.proofing.summary.scheduled, isTrue);
        // Typing keeps the settled result instead of flickering "waiting".
        expect(find.text('Waiting to check…'), findsNothing);
        expect(find.text('1 writing issue'), findsOneWidget);
        await _flush(tester);
        expect(harness.controller.proofing.summary.issues, hasLength(1));
        expect(find.byType(Dialog), findsNothing);
        expect(harness.provider.requests, hasLength(2));
      } finally {
        if (!gate.isCompleted) gate.complete();
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'single marked-text click opens inline correction after double-click interval',
    (tester) async {
      final harness = _SurfaceHarness();
      try {
        await harness.mount(tester);
        await _click(tester, harness.point(tester, 6), waitForReview: false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(_menuKey), findsNothing);
        await tester.pump(const Duration(milliseconds: 220));
        await _frames(tester);
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(find.text('Fehler'), findsOneWidget);
        expect(harness.focus.hasPrimaryFocus, isTrue);
        expect(harness.controller.input.isAttached, isTrue);
        expect(_key('word-review-pane'), findsNothing);
        await _screenshot(tester, 'live-review-inline-suggestion');

        await tester.tap(find.text('Fehler'));
        await _flush(tester);
        expect(
          harness.controller.document.paragraphs.single.text,
          'Ein Fehler steht hier. Weiter schreiben.',
        );
        expect(find.byKey(_menuKey), findsNothing);
        harness.controller.undo();
        await _flush(tester);
        expect(
          harness.controller.document.paragraphs.single.text,
          'Ein Feler steht hier. Weiter schreiben.',
        );
        expect(harness.controller.proofing.summary.issues, hasLength(1));
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'many inline suggestions retain editor focus and typing dismisses stale menu',
    (tester) async {
      final harness = _SurfaceHarness(
        provider: _SurfaceProvider(
          replacements: const <String>[
            'Fehler',
            'Falter',
            'Feder',
            'Feld',
            'Fell',
            'Feuer',
            'Feger',
            'Feier',
          ],
        ),
      );
      try {
        await harness.mount(tester);
        await _click(tester, harness.point(tester, 6));
        expect(find.byKey(_menuKey), findsOneWidget);
        expect(harness.focus.hasPrimaryFocus, isTrue);
        expect(harness.controller.input.isAttached, isTrue);
        expect(find.byType(TextField), findsNothing);
        tester.testTextInput.enterText('The document stays editable.');
        await _flush(tester);
        expect(
          harness.controller.document.paragraphs.single.text,
          'The document stays editable.',
        );
        expect(find.byKey(_menuKey), findsNothing);
        expect(harness.controller.proofing.summary.issues, isEmpty);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('F7 opens a nonmodal pane and shares one explicit manual check', (
    tester,
  ) async {
    final gate = Completer<void>();
    final manual = _SurfaceProvider(
      providerId: 'manual-surface',
      target: 'manual-only-marker',
      gate: gate.future,
    );
    final harness = _SurfaceHarness();
    harness.controller.proofing.configureManual(
      OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
    );
    try {
      await harness.mount(tester);
      expect(manual.requests, isEmpty);
      await harness.focusDocument(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await _frames(tester);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(manual.requests, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await _frames(tester);
      expect(manual.requests, hasLength(1));
      gate.complete();
      await _frames(tester);
      expect(
        harness.controller.proofing.summary.manualProvidersSkipped,
        isFalse,
      );
      expect(harness.focus.hasPrimaryFocus, isTrue);
      await _screenshot(tester, 'live-review-desktop');

      tester.testTextInput.enterText('Another Feler while the pane is open.');
      await _flush(tester);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(harness.controller.proofing.summary.issues, hasLength(1));
      expect(manual.requests, hasLength(1));
      expect(
        harness.controller.proofing.summary.manualProvidersSkipped,
        isTrue,
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      await harness.close(tester);
    }
  });

  testWidgets('scrolling retains only nearby page pictures and avoids editing events',
      (tester) async {
    final controller = WordEditorController(
      document: WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              for (var i = 0; i < 18; i++)
                WmlParagraph(
                  properties: WmlParagraphProps(pageBreakBefore: i != 0),
                  inlines: [WmlRun(text: 'Page ${i + 1}')],
                ),
            ],
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    var editNotifications = 0;
    var viewportNotifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WordCanvas(
          document: controller.document,
          laidOut: controller.documentLaidOut,
          caret: controller.caret,
          viewport: controller.viewport,
          onChanged: () => editNotifications++,
          onViewportChanged: () => viewportNotifications++,
        ),
      ),
    );
    final canvas = find.byType(WordCanvas);
    final render = tester.renderObject<RenderWordCanvas>(canvas);
    final position = tester.getCenter(canvas);
    Future<void> scroll(double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: position, scrollDelta: Offset(0, dy)),
      );
      await tester.pump();
    }

    final layout = controller.documentLaidOut;
    final scale = controller.viewport.scale * (96 / 72);
    const targets = [0, 3, 6, 9, 12];
    final pageHeight = layout.pages.first.height * scale;
    for (final index in targets) {
      // Show the end of this page and a sliver of the next page.
      controller.viewport.origin = Offset(
        0,
        layout.pageStackTop(index, scale) + pageHeight - render.size.height * .7,
      );
      render.markNeedsPaint();
      await tester.pump();
    }
    expect(render.debugCachedTextPageIndices, containsAll(targets));
    expect(render.debugCachedTextPageCount, inInclusiveRange(1, 8));

    controller.viewport.origin = Offset.zero;
    render.markNeedsPaint();
    await tester.pump();
    await scroll(5);
    final first = viewportNotifications;
    await scroll(5);
    expect(viewportNotifications, first);
    for (var page = 0; page < 12; page++) {
      await scroll(controller.documentLaidOut.pages.first.height * (96 / 72) + 24);
    }
    expect(viewportNotifications, greaterThan(8));
    expect(editNotifications, 0);
    expect(render.debugCachedTextPageCount, inInclusiveRange(1, 8));
  });

  testWidgets(
    'selection wheel scrolling and zoom preserve published findings',
    (tester) async {
      final harness = _SurfaceHarness();
      try {
        await harness.mount(tester);
        final checked = harness.controller.proofing.summary;
        final requests = harness.provider.requests.length;
        await harness.focusDocument(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _frames(tester);
        final position = tester.getCenter(find.byType(WordCanvas));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, 60),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, -40),
          ),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        harness.controller.refreshView();
        await _flush(tester);
        expect(harness.controller.viewport.scale, greaterThan(1));
        expect(identical(harness.controller.proofing.summary, checked), isTrue);
        expect(harness.provider.requests.length, requests);
        expect(
          harness.controller.proofing.isCurrent(checked.issues.single),
          isTrue,
        );
        expect(
          harness.controller.proofing.findingsByParagraph.values.single,
          hasLength(1),
        );
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'double and triple clicks select text without opening suggestions',
    (tester) async {
      final harness = _SurfaceHarness();
      try {
        await harness.mount(tester);
        final point = harness.point(tester, 6);
        await _click(tester, point, waitForReview: false);
        await tester.pump(const Duration(milliseconds: 40));
        await _click(tester, point, waitForReview: false);
        final word = harness.controller.caret.normalizedRange;
        expect(word.startIdx, 4);
        expect(word.endIdx, 9);
        expect(find.byKey(_menuKey), findsNothing);
        await tester.pump(const Duration(milliseconds: 40));
        await _click(tester, point, waitForReview: false);
        final paragraph = harness.controller.caret.normalizedRange;
        expect(paragraph.startIdx, 0);
        expect(
          paragraph.endIdx,
          harness.controller.document.paragraphs.single.text.length,
        );
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
        expect(find.byKey(_menuKey), findsNothing);
        expect(_key('word-review-pane'), findsNothing);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'dragging from marked text selects a range without opening suggestions',
    (tester) async {
      final harness = _SurfaceHarness();
      try {
        await harness.mount(tester);
        final gesture = await tester.startGesture(
          harness.point(tester, 5),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await gesture.moveTo(harness.point(tester, 20));
        await gesture.moveTo(harness.point(tester, 25));
        await gesture.up();
        await _flush(tester);
        expect(harness.controller.caret.isCollapsed, isFalse);
        expect(find.byKey(_menuKey), findsNothing);
        expect(_key('word-review-pane'), findsNothing);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'single click on a revision opens its Changes pane and preserves focus',
    (tester) async {
      final document = _document('A fresh addition is here.');
      WordRevisions.record(
        document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        paragraph: document.paragraphs.single,
        start: 2,
        end: 16,
        text: 'fresh addition',
        author: 'Mira',
      );
      final harness = _SurfaceHarness(document: document);
      try {
        await harness.mount(tester);
        await _click(tester, harness.point(tester, 5));
        expect(_key('word-review-pane'), findsOneWidget);
        expect(harness.controller.reviewPaneTab, WordReviewPaneTab.changes);
        expect(_text(tester, 'live-review-selected-text'), 'fresh addition');
        expect(harness.focus.hasPrimaryFocus, isTrue);
        expect(find.byType(Dialog), findsNothing);
        await _tapPane(tester, 'live-review-accept');
        expect(
          document.revisions.where((revision) => revision.accepted == null),
          isEmpty,
        );
        expect(document.paragraphs.single.text, 'A fresh addition is here.');
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'clicking a finding follows an open pane without stealing document focus',
    (tester) async {
      final harness = _SurfaceHarness(text: 'Ein Feler und noch ein Feler.');
      try {
        await harness.mount(tester);
        harness.controller.openReviewPane();
        await _frames(tester);
        final last = harness.controller.document.paragraphs.single.text
            .lastIndexOf('Feler');
        await _click(tester, harness.point(tester, last + 2));
        expect(harness.controller.selectedProofingIssue?.finding.start, last);
        expect(harness.focus.hasPrimaryFocus, isTrue);
        expect(harness.controller.input.isAttached, isTrue);
        expect(find.byKey(_menuKey), findsNothing);
        expect(find.text('2 of 2 findings'), findsOneWidget);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('Escape closes the pane from its focused reviewer field', (
    tester,
  ) async {
    final harness = _SurfaceHarness();
    try {
      await harness.mount(tester);
      harness.controller.openReviewPane(tab: WordReviewPaneTab.changes);
      await _frames(tester);
      await tester.enterText(_key('live-review-author'), 'New reviewer');
      expect(harness.focus.hasPrimaryFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(harness.controller.reviewPaneVisible, isFalse);
      expect(_key('word-review-pane'), findsNothing);
      expect(
        harness.controller.document.paragraphs.single.text,
        'Ein Feler steht hier. Weiter schreiben.',
      );
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'selecting mode shows inline findings but cannot apply their replacements',
    (tester) async {
      final harness = _SurfaceHarness(
        config: const OfficeSurfaceConfig(
          showRulers: false,
          mode: OfficeInteractionMode.selecting,
        ),
      );
      try {
        await harness.mount(tester);
        await _click(tester, harness.point(tester, 6));
        expect(find.byKey(_menuKey), findsOneWidget);
        final replacementTap = find
            .ancestor(
              of: find.text('Fehler'),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(tester.widget<GestureDetector>(replacementTap).onTap, isNull);
        await tester.tap(find.text('Fehler'));
        await _frames(tester);
        expect(
          harness.controller.document.paragraphs.single.text,
          'Ein Feler steht hier. Weiter schreiben.',
        );
        expect(harness.controller.canUndo, isFalse);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('viewing mode inspects through the pane without enabling edits', (
    tester,
  ) async {
    final harness = _SurfaceHarness(
      config: const OfficeSurfaceConfig(
        showRulers: false,
        mode: OfficeInteractionMode.viewing,
      ),
    );
    try {
      await harness.mount(tester);
      await _click(tester, harness.point(tester, 6));
      expect(find.byKey(_menuKey), findsNothing);
      await tester.tap(_key('word-review-writing-status'));
      await _frames(tester);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(_key('live-proofing-replace-0'))
            .onPressed,
        isNull,
      );
      expect(harness.controller.input.isAttached, isFalse);
      expect(
        harness.controller.document.paragraphs.single.text,
        'Ein Feler steht hier. Weiter schreiben.',
      );
      expect(harness.controller.canUndo, isFalse);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('German host strings show German review and status chrome', (
    tester,
  ) async {
    final harness = _SurfaceHarness(
      config: const OfficeSurfaceConfig(
        showRulers: false,
        strings: OfficeStrings.german,
      ),
    );
    try {
      await harness.mount(tester);
      expect(
        find.descendant(
          of: _key('word-review-writing-status'),
          matching: find.text('1 Schreibhinweis'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('word-review-changes-status'),
          matching: find.text('0 Änderungen'),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('word-review-writing-status'));
      await _frames(tester);
      expect(_key('word-review-pane'), findsOneWidget);
      expect(find.text('Überprüfen'), findsOneWidget);
      expect(find.text('Hinweis 1 von 1'), findsOneWidget);
      expect(find.text('Alle Hinweise'), findsWidgets);
      expect(
        find.descendant(
          of: _key('live-proofing-ignore-once'),
          matching: find.text('Einmal ignorieren'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ignore once'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  for (final arabic in <bool>[false, true]) {
    testWidgets(
      'narrow ${arabic ? 'Arabic' : 'English'} review retains a usable document canvas',
      (tester) async {
        final harness = _SurfaceHarness(
          size: const Size(320, 480),
          textScale: 1.5,
          config: OfficeSurfaceConfig(
            showRulers: false,
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          ),
        );
        try {
          await harness.mount(tester);
          await tester.tap(_key('word-review-writing-status'));
          await _frames(tester);
          expect(_key('word-review-pane'), findsOneWidget);
          final canvas = tester.getRect(find.byType(WordCanvas));
          final pane = tester.getRect(_key('word-review-pane'));
          expect(canvas.height, greaterThan(100));
          expect(canvas.width, 320);
          expect(pane.top, greaterThanOrEqualTo(canvas.bottom));
          expect(tester.takeException(), isNull);
          await _tapPane(tester, 'live-proofing-reveal');
          expect(harness.focus.hasPrimaryFocus, isTrue);
          expect(tester.takeException(), isNull);
          await Scrollable.ensureVisible(
            tester.element(_key('live-proofing-replace-0')),
            alignment: 1,
          );
          await tester.pump();
          await _screenshot(
            tester,
            arabic ? 'live-review-arabic-narrow' : 'live-review-english-narrow',
          );
          await _tapPane(tester, 'live-proofing-replace-0');
          expect(
            harness.controller.document.paragraphs.single.text,
            'Ein Fehler steht hier. Weiter schreiben.',
          );
          expect(_key('word-review-pane'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await harness.close(tester);
        }
      },
    );
  }
}
