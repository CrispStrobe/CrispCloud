import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _Provider extends OfficeProofingProvider {
  _Provider(this.id);

  @override
  final String id;
  final requests = <OfficeProofingRequest>[];

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final match in RegExp('Feler').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'text-options.spelling',
            start: match.start,
            end: match.end,
            category: OfficeProofingCategory.spelling,
            message: 'Check this spelling.',
            replacements: const ['Fehler'],
          ),
      ],
    );
  }
}

WmlDocument _document({List<WmlInline>? inlines}) => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 620),
      margins: const WmlPageMargins(top: 50, bottom: 50, left: 48, right: 48),
      blocks: [
        WmlParagraph(inlines: inlines ?? [WmlRun(text: 'Feler and Feler')]),
        WmlParagraph(inlines: [WmlRun(text: 'Another paragraph.')]),
      ],
    ),
  ],
);

final class _Harness {
  _Harness({
    WmlDocument? document,
    bool viewing = false,
    bool arabic = false,
    this.size = const Size(1120, 920),
    this.textScale = 1,
  }) {
    controller = WordEditorController(
      document: document ?? _document(),
      config: OfficeSurfaceConfig(
        showRulers: false,
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        mode: viewing
            ? OfficeInteractionMode.viewing
            : OfficeInteractionMode.editing,
      ),
      proofingService: OfficeProofingService(providers: [ordinary]),
    );
    controller.proofing.configureManual(
      OfficeProofingService(providers: [manual]),
    );
  }

  final ordinary = _Provider('text-options-ordinary');
  final manual = _Provider('text-options-manual');
  late final WordEditorController controller;
  final focus = FocusNode(debugLabel: 'text-options-document');
  final Size size;
  final double textScale;

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
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
          body: QudsWordEditor(controller: controller, focusNode: focus),
        ),
      ),
    );
    await _flush(tester);
  }

  Future<void> select(WidgetTester tester, int start, int end) async {
    controller.caret
      ..paragraphIndex = 0
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = start
      ..logicalIndex = end;
    controller.refreshView();
    await tester.pump();
  }

  Future<void> openOptions(WidgetTester tester) async {
    await tester.tap(_key('word-review-language-status'));
    await _flush(tester);
    expect(
      _key('live-proofing-text-language').hitTestable(),
      findsOneWidget,
      reason: 'The language status action must reveal its controls directly.',
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(
        of: _key('word-review-pane'),
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, _key(key));
  await tester.tap(_key(key));
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _chooseLanguage(WidgetTester tester, String label) async {
  await _tap(tester, 'live-proofing-text-language');
  await tester.tap(find.text(label).last);
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'language status opens paragraph options without a dialog or document edit',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.controller.caret
        ..logicalIndex = 4
        ..collapseSelection();
      h.controller.refreshView();
      await tester.pump();
      final revision = h.controller.contentRevision;
      await h.openOptions(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(h.controller.reviewPaneVisible, isTrue);
      expect(h.controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(h.controller.reviewTextProofingOptionsVisible, isTrue);
      expect(_text(tester, 'live-proofing-text-scope'), contains('paragraph'));
      expect(h.controller.caret.logicalIndex, 4);
      expect(h.controller.caret.isCollapsed, isTrue);
      expect(h.controller.contentRevision, revision);
      expect(h.controller.canUndo, isFalse);
      expect(h.manual.requests, isEmpty);
    },
  );

  testWidgets(
    'selection language updates live checking and preserves the selection with Undo',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.select(tester, 0, 5);
      await h.openOptions(tester);
      expect(
        _text(tester, 'live-proofing-text-scope'),
        contains('selected text'),
      );
      await _chooseLanguage(tester, 'English (United States)');
      final paragraph = h.controller.document.paragraphs.first;
      expect(WmlRunEdit.propsAt(paragraph, 1).proofingLanguage, 'en-US');
      expect(WmlRunEdit.propsAt(paragraph, 11).proofingLanguage, isNull);
      expect(h.controller.document.proofingLanguage, 'de-DE');
      expect(h.controller.caret.selectionAnchor, 0);
      expect(h.controller.caret.logicalIndex, 5);
      expect(
        h.ordinary.requests.any((request) => request.language == 'en-US'),
        isTrue,
      );
      expect(h.manual.requests, isEmpty);
      expect(_text(tester, 'live-review-notice'), contains('updated'));
      h.controller.undo();
      await _flush(tester);
      expect(WmlRunEdit.propsAt(paragraph, 1).proofingLanguage, isNull);
      expect(h.controller.canUndo, isFalse);
      expect(h.controller.textProofingTarget!.language, 'de-DE');
      h.controller.redo();
      await _flush(tester);
      expect(h.controller.textProofingTarget!.language, 'en-US');
    },
  );

  testWidgets(
    'text checking toggle excludes only the selected text and can restore it',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      expect(h.controller.proofing.summary.issues, hasLength(2));
      await h.select(tester, 0, 5);
      await h.openOptions(tester);
      await _tap(tester, 'live-proofing-text-enabled');
      final paragraph = h.controller.document.paragraphs.first;
      expect(WmlRunEdit.propsAt(paragraph, 1).noProof, isTrue);
      expect(WmlRunEdit.propsAt(paragraph, 11).noProof, isNot(isTrue));
      expect(h.controller.proofing.summary.issues, hasLength(1));
      expect(h.controller.proofing.summary.issues.single.finding.start, 10);
      expect(h.controller.proofing.summary.complete, isFalse);
      expect(h.controller.textProofingTarget!.checkingEnabled, isFalse);
      expect(h.manual.requests, isEmpty);
      await _tap(tester, 'live-proofing-text-enabled');
      expect(h.controller.proofing.summary.issues, hasLength(2));
      expect(h.controller.textProofingTarget!.checkingEnabled, isTrue);
      expect(h.manual.requests, isEmpty);
    },
  );

  testWidgets(
    'mixed text settings display and enable the full selected range',
    (tester) async {
      final h = _Harness(
        document: _document(
          inlines: [
            WmlRun(text: 'Feler ', properties: WmlRunProps(noProof: true)),
            WmlRun(
              text: 'Feler',
              properties: WmlRunProps(proofingLanguage: 'en-US'),
            ),
          ],
        ),
      );
      await h.mount(tester);
      await h.select(tester, 0, 11);
      await h.openOptions(tester);
      expect(
        _text(tester, 'live-proofing-text-summary'),
        contains('Mixed languages'),
      );
      await _reveal(tester, _key('live-proofing-text-enabled'));
      expect(
        tester
            .widget<CheckboxListTile>(_key('live-proofing-text-enabled'))
            .value,
        isNull,
      );
      await _tap(tester, 'live-proofing-text-enabled');
      expect(h.controller.textProofingTarget!.checkingEnabled, isTrue);
      expect(h.controller.textProofingTarget!.language, isNull);
      expect(h.controller.proofing.summary.issues, hasLength(2));
    },
  );

  testWidgets(
    'inherited language follows paragraph defaults and supports Undo',
    (tester) async {
      final document = _document(
        inlines: [
          WmlRun(
            text: 'Feler',
            properties: WmlRunProps(proofingLanguage: 'en-US'),
          ),
        ],
      );
      document.paragraphs.first.properties.proofingLanguage = 'de-AT';
      final h = _Harness(document: document);
      await h.mount(tester);
      await h.openOptions(tester);
      await _tap(tester, 'live-proofing-text-inherit');
      expect(h.controller.textProofingTarget!.language, 'de-AT');
      expect(document.proofingLanguage, 'de-DE');
      h.controller.undo();
      await _flush(tester);
      expect(h.controller.textProofingTarget!.language, 'en-US');
      expect(h.manual.requests, isEmpty);
    },
  );

  testWidgets('unchanged inherited language does not promise an Undo entry', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await h.openOptions(tester);
    await _tap(tester, 'live-proofing-text-inherit');
    expect(h.controller.canUndo, isFalse);
    expect(_text(tester, 'live-review-notice'), contains('already up to date'));
    expect(_text(tester, 'live-review-notice'), isNot(contains('Undo')));
  });

  testWidgets('old dropdown action refuses a different selection', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await h.select(tester, 0, 5);
    await h.openOptions(tester);
    final change = tester
        .widget<DropdownButton<String>>(_key('live-proofing-text-language'))
        .onChanged!;
    await h.select(tester, 10, 15);
    change('en-US');
    await _flush(tester);
    expect(h.controller.canUndo, isFalse);
    expect(h.controller.textProofingTarget!.language, 'de-DE');
    expect(_text(tester, 'live-review-notice'), contains('changed'));
  });

  testWidgets('text options cannot mutate through a covering modal', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await h.openOptions(tester);
    final change = tester
        .widget<DropdownButton<String>>(_key('live-proofing-text-language'))
        .onChanged!;
    final context = tester.element(_key('word-review-pane'));
    final closed = showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(title: Text('Covering dialog')),
    );
    await _flush(tester);
    change('en-US');
    await _flush(tester);
    expect(h.controller.canUndo, isFalse);
    expect(h.controller.textProofingTarget!.language, 'de-DE');
    Navigator.of(context, rootNavigator: true).pop();
    await closed;
    await _flush(tester);
  });

  testWidgets('viewing mode keeps inspection and disables text changes', (
    tester,
  ) async {
    final h = _Harness(viewing: true);
    await h.mount(tester);
    await h.openOptions(tester);
    expect(
      tester
          .widget<DropdownButton<String>>(_key('live-proofing-text-language'))
          .onChanged,
      isNull,
    );
    await _reveal(tester, _key('live-proofing-text-enabled'));
    expect(
      tester
          .widget<CheckboxListTile>(_key('live-proofing-text-enabled'))
          .onChanged,
      isNull,
    );
    expect(h.controller.canUndo, isFalse);
  });

  testWidgets(
    'pane follows caret context and keeps its open section across hiding',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.select(tester, 0, 5);
      await h.openOptions(tester);
      expect(
        _text(tester, 'live-proofing-text-scope'),
        contains('selected text'),
      );
      h.controller.caret
        ..paragraphIndex = 1
        ..logicalIndex = 3
        ..collapseSelection();
      h.controller.refreshView();
      await _flush(tester);
      await _reveal(tester, _key('live-proofing-text-scope'));
      expect(
        _text(tester, 'live-proofing-text-scope'),
        contains('current paragraph'),
      );
      h.controller.closeReviewPane();
      await _flush(tester);
      await h.openOptions(tester);
      expect(
        _text(tester, 'live-proofing-text-scope'),
        contains('current paragraph'),
      );
      expect(h.controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'language status reveals expanded settings again after scrolling',
    (tester) async {
      final h = _Harness(size: const Size(900, 760));
      await h.mount(tester);
      await h.openOptions(tester);
      final list = tester.widget<ListView>(
        _key('live-review-proofing-content'),
      );
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await _flush(tester);
      expect(_key('live-proofing-text-language').hitTestable(), findsNothing);
      await h.openOptions(tester);
      expect(h.controller.canUndo, isFalse);
    },
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'narrow ${arabic ? 'RTL' : 'English'} text options remain usable with large text',
      (tester) async {
        final h = _Harness(
          arabic: arabic,
          size: const Size(390, 1000),
          textScale: 1.6,
        );
        await h.mount(tester);
        await h.openOptions(tester);
        await _reveal(tester, _key('live-proofing-text-enabled'));
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(_key('word-review-status')).width,
          lessThanOrEqualTo(390),
        );
        expect(
          _key('live-proofing-text-enabled').hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(Dialog), findsNothing);
      },
    );
  }
}
