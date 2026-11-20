import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

class _Provider extends OfficeProofingProvider {
  _Provider({this.providerId = 'live-changes-test', this.gate});

  final String providerId;
  final Future<void>? gate;
  final List<OfficeProofingRequest> requests = <OfficeProofingRequest>[];

  @override
  String get id => providerId;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (request.text.contains('Wait') && gate != null) await gate;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: <OfficeProofingFinding>[
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
      ],
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

WmlRevision _record(
  WmlDocument document,
  WmlParagraph paragraph,
  String text, {
  required WmlRevisionKind kind,
  required String author,
}) => WordRevisions.record(
  document,
  kind: kind,
  paragraph: paragraph,
  paragraphIndex: document.paragraphs.toList().indexOf(paragraph),
  start: paragraph.text.indexOf(text),
  end: paragraph.text.indexOf(text) + text.length,
  text: text,
  author: author,
);

WordEditorController _controller({
  bool viewing = false,
  bool arabic = false,
  WmlDocument? document,
  _Provider? provider,
}) => WordEditorController(
  document: document ?? _fixture(),
  config: OfficeSurfaceConfig(
    mode: viewing
        ? OfficeInteractionMode.viewing
        : OfficeInteractionMode.editing,
    textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
  ),
  proofingService: OfficeProofingService(
    providers: <OfficeProofingProvider>[provider ?? _Provider()],
  ),
);

WmlDocument _fixture() {
  final paragraphs = <WmlParagraph>[
    for (final text in <String>['Alpha', 'Beta', 'Gamma', 'Delta'])
      _paragraph(text),
  ];
  final document = WmlDocument(
    sections: <WmlSection>[WmlSection(blocks: paragraphs)],
  );
  for (var index = 0; index < paragraphs.length; index++) {
    _record(
      document,
      paragraphs[index],
      paragraphs[index].text,
      kind: index.isEven ? WmlRevisionKind.insert : WmlRevisionKind.delete,
      author: index == 1 ? 'Bob' : 'Alice',
    );
  }
  return document;
}

Future<void> _drain(WidgetTester tester) async {
  // Start newly scheduled expansion/menu animations before advancing their
  // elapsed time. A single long first pump starts them at elapsed zero.
  await tester.pump();
  await tester.pump(_debounce);
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _mount(
  WidgetTester tester,
  WordEditorController controller, {
  WordReviewPaneTab tab = WordReviewPaneTab.changes,
  Size size = const Size(400, 920),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
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
        body: WordReviewPane(
          controller: controller,
          initialTab: tab,
          onTabChanged: controller.setReviewPaneTab,
          onClose: () {},
        ),
      ),
    ),
  );
  await _drain(tester);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: _key('word-review-pane'),
        matching: find.byType(Scrollable),
      )
      .first;
  if (finder.evaluate().isEmpty) {
    final list = tester.widget<ListView>(
      find
          .descendant(
            of: _key('word-review-pane'),
            matching: find.byType(ListView),
          )
          .first,
    );
    list.controller!.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  expect(finder.hitTestable(), findsOneWidget, reason: '$finder');
  await tester.tap(finder);
  await _drain(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  if (key == 'live-review-author-filter' || key == 'live-review-kind-filter') {
    final filters = _key('live-review-filters');
    final header = find
        .descendant(of: filters, matching: find.byType(ListTile))
        .first;
    await _reveal(tester, header);
    // A collapsed maintainState tile keeps its children mounted. The public
    // controller distinguishes that state from an expanded off-screen child.
    final expansible = tester.widget<Expansible>(
      find.descendant(of: filters, matching: find.byType(Expansible)),
    );
    if (!expansible.controller.isExpanded) {
      await _tap(tester, header);
    }
  }
  await _tap(tester, _key(key));
  await _tap(tester, find.text(label).last);
}

String _text(WidgetTester tester, String key) {
  final text = tester.widget<Text>(_key(key));
  return text.data ?? text.textSpan!.toPlainText();
}

String _preview(WidgetTester tester) {
  final text = tester.widget<SelectableText>(_key('live-review-preview-text'));
  return text.data ?? text.textSpan!.toPlainText();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'author type and text filters combine without editing the document',
    (tester) async {
      final controller = _controller();
      await _mount(tester, controller);
      await _choose(tester, 'live-review-author-filter', 'Alice');
      expect(
        _text(tester, 'live-review-filter-count'),
        '3 of 4 pending changes',
      );
      await _choose(tester, 'live-review-kind-filter', 'Deletions');
      expect(
        _text(tester, 'live-review-filter-count'),
        '1 of 4 pending changes',
      );
      expect(_text(tester, 'live-review-selected-text'), 'Delta');
      await _reveal(tester, _key('live-review-search'));
      await tester.enterText(_key('live-review-search'), '  dEL  ');
      await _drain(tester);
      expect(
        _text(tester, 'live-review-filter-count'),
        '1 of 4 pending changes',
      );
      await tester.enterText(_key('live-review-search'), 'missing');
      await _drain(tester);
      expect(
        _text(tester, 'live-review-filter-count'),
        '0 of 4 pending changes',
      );
      expect(
        _text(tester, 'live-review-empty'),
        'No changes match these filters.',
      );
      await _tap(tester, _key('live-review-clear-filters'));
      expect(
        _text(tester, 'live-review-filter-count'),
        '4 of 4 pending changes',
      );
      expect(controller.document.revisions, hasLength(4));
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'filtered navigation and resolution continue with the next shown change',
    (tester) async {
      final controller = _controller();
      final revisions = List<WmlRevision>.of(controller.document.revisions);
      await _mount(tester, controller);
      await _choose(tester, 'live-review-author-filter', 'Alice');
      await _tap(tester, _key('live-review-next'));
      expect(controller.selectedRevision, same(revisions[2]));
      expect(_text(tester, 'live-review-selected-text'), 'Gamma');
      await _tap(tester, _key('live-review-accept'));
      expect(controller.selectedRevision, same(revisions[3]));
      expect(_text(tester, 'live-review-selected-text'), 'Delta');
      await _tap(tester, _key('live-review-undo'));
      expect(controller.selectedRevision, same(revisions[2]));
      expect(_text(tester, 'live-review-selected-text'), 'Gamma');
      await _tap(tester, _key('live-review-redo'));
      expect(controller.selectedRevision, same(revisions[3]));
      expect(_text(tester, 'live-review-selected-text'), 'Delta');
      await _tap(tester, _key('live-review-next'));
      expect(controller.selectedRevision, same(revisions[0]));
    },
  );

  for (final accept in <bool>[true, false]) {
    testWidgets(
      '${accept ? 'accept' : 'reject'} shown affects exactly the filtered batch with one undo',
      (tester) async {
        final controller = _controller();
        final document = controller.document;
        final revisions = List<WmlRevision>.of(document.revisions);
        await _mount(tester, controller);
        await _choose(tester, 'live-review-author-filter', 'Alice');
        await _tap(
          tester,
          _key(
            accept ? 'live-review-accept-shown' : 'live-review-reject-shown',
          ),
        );
        expect(document.revisions, <WmlRevision>[revisions[1]]);
        expect(
          document.paragraphs.map((paragraph) => paragraph.text),
          accept
              ? <String>['Alpha', 'Beta', 'Gamma', '']
              : <String>['', 'Beta', '', 'Delta'],
        );
        await _reveal(tester, _key('live-review-filter-count'));
        expect(
          _text(tester, 'live-review-filter-count'),
          '0 of 1 pending changes',
        );
        expect(
          _text(tester, 'live-review-empty'),
          'No changes match these filters.',
        );
        await _tap(tester, _key('live-review-undo'));
        expect(document.revisions, orderedEquals(revisions));
        expect(document.paragraphs.map((paragraph) => paragraph.text), <String>[
          'Alpha',
          'Beta',
          'Gamma',
          'Delta',
        ]);
        expect(controller.canUndo, isFalse);
        await _tap(tester, _key('live-review-redo'));
        expect(document.revisions, <WmlRevision>[revisions[1]]);
        expect(find.byType(Dialog), findsNothing);
      },
    );
  }

  testWidgets('one stale filtered change blocks the entire shown batch', (
    tester,
  ) async {
    final controller = _controller();
    final document = controller.document;
    final revisions = List<WmlRevision>.of(document.revisions);
    document.paragraphs.elementAt(2).inlines
      ..clear()
      ..add(WmlRun(text: 'Changed'));
    controller.refresh();
    await _mount(tester, controller);
    await _choose(tester, 'live-review-author-filter', 'Alice');
    await _tap(tester, _key('live-review-accept-shown'));
    expect(document.revisions, orderedEquals(revisions));
    expect(document.paragraphs.map((paragraph) => paragraph.text), <String>[
      'Alpha',
      'Beta',
      'Changed',
      'Delta',
    ]);
    expect(controller.canUndo, isFalse);
    await _reveal(tester, _key('live-review-notice'));
    expect(_text(tester, 'live-review-notice'), isNotEmpty);
  });

  testWidgets('paragraph previews project all changes without resolving them', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Keep old new.');
    final paragraph = document.paragraphs.single;
    _record(
      document,
      paragraph,
      'old',
      kind: WmlRevisionKind.delete,
      author: 'Alice',
    );
    _record(
      document,
      paragraph,
      'new',
      kind: WmlRevisionKind.insert,
      author: 'Bob',
    );
    final controller = _controller(document: document);
    await _mount(tester, controller);
    await _reveal(tester, _key('live-review-preview-text'));
    expect(_preview(tester), 'Keep old new.');
    await _choose(tester, 'live-review-preview-mode', 'Final text');
    expect(_preview(tester), 'Keep  new.');
    await _choose(tester, 'live-review-preview-mode', 'Original text');
    expect(_preview(tester), 'Keep old .');
    await _choose(tester, 'live-review-preview-mode', 'All markup text');
    expect(_preview(tester), 'Keep old new.');
    expect(paragraph.text, 'Keep old new.');
    expect(document.revisions, hasLength(2));
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  });

  testWidgets(
    'text previews remain available when native boundaries forbid resolving a valid span',
    (tester) async {
      final control = WmlContentControlData(
        xml:
            '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr/><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const <WmlOpaqueRelationship>[],
      );
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'ab'),
          WmlContentControlBoundary(control: control, start: true),
          WmlRun(text: 'cd'),
          WmlContentControlBoundary(control: control, start: false),
        ],
      );
      final document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(blocks: <WmlBlock>[paragraph]),
        ],
      );
      WordRevisions.record(
        document,
        paragraph: paragraph,
        paragraphIndex: 0,
        kind: WmlRevisionKind.delete,
        start: 1,
        end: 3,
        text: 'bc',
        preserveSourceRange: true,
      );
      final controller = _controller(document: document);
      await _mount(tester, controller);
      await _reveal(tester, _key('live-review-accept'));
      expect(_enabled(tester, 'live-review-accept'), isFalse);
      await _choose(tester, 'live-review-preview-mode', 'Final text');
      expect(_preview(tester), 'ad');
      expect(_key('live-review-preview-unavailable'), findsNothing);
      await _choose(tester, 'live-review-preview-mode', 'Original text');
      expect(_preview(tester), 'abcd');
      expect(paragraph.text, 'abcd');
      expect(document.revisions, hasLength(1));
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('stale preview shows stored text with an explicit warning', (
    tester,
  ) async {
    final controller = _controller();
    controller.document.paragraphs.elementAt(2).inlines
      ..clear()
      ..add(WmlRun(text: 'Changed'));
    controller.selectedRevisionIndex = 2;
    controller.refresh();
    await _mount(tester, controller);
    await _choose(tester, 'live-review-preview-mode', 'Final text');
    expect(_key('live-review-preview-unavailable'), findsOneWidget);
    expect(_preview(tester), 'Changed');
    await _reveal(tester, _key('live-review-accept'));
    expect(_enabled(tester, 'live-review-accept'), isFalse);
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'detached captured changes cannot become actionable through a cached target map',
    (tester) async {
      final controller = _controller();
      final document = controller.document;
      final revision = document.revisions.first;
      final detached = document.sections.single.blocks.removeAt(0);
      expect(detached, same(revision.targetParagraph));
      controller.selectedRevisionIndex = 0;
      await _mount(tester, controller);
      await _reveal(tester, _key('live-review-accept'));
      expect(_enabled(tester, 'live-review-accept'), isFalse);
      expect(_enabled(tester, 'live-review-reject'), isFalse);
      expect(
        _text(tester, 'live-review-conflict'),
        contains('no longer in the document'),
      );
      expect(_key('live-review-preview-text'), findsNothing);
      expect(document.revisions, hasLength(4));
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'viewing mode keeps filters and previews but disables decisions',
    (tester) async {
      final controller = _controller(viewing: true);
      await _mount(tester, controller);
      await _choose(tester, 'live-review-author-filter', 'Alice');
      await _reveal(tester, _key('live-review-accept'));
      expect(_enabled(tester, 'live-review-accept'), isFalse);
      expect(_enabled(tester, 'live-review-reject'), isFalse);
      await _choose(tester, 'live-review-preview-mode', 'Original text');
      expect(_preview(tester), '');
      await _reveal(tester, _key('live-review-accept-shown'));
      expect(_enabled(tester, 'live-review-accept-shown'), isFalse);
      expect(_enabled(tester, 'live-review-reject-shown'), isFalse);
      expect(controller.document.revisions, hasLength(4));
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('F7 checks writing from a focused Changes pane search field', (
    tester,
  ) async {
    final ordinary = _Provider();
    final manual = _Provider(providerId: 'manual-changes-test');
    final controller = _controller(provider: ordinary);
    controller.proofing.configureManual(
      OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
    );
    await _mount(tester, controller);
    await _tap(tester, _key('live-review-filters'));
    await tester.enterText(_key('live-review-search'), 'Alpha');
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await _drain(tester);
    expect(_key('live-review-proofing-content'), findsOneWidget);
    expect(manual.requests, isNotEmpty);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'document language changes in the pane are undoable and keep manual checks explicit',
    (tester) async {
      final ordinary = _Provider();
      final manual = _Provider(providerId: 'manual-language-test');
      final controller = _controller(
        document: WmlDocument.empty(text: 'Feler'),
        provider: ordinary,
      );
      controller.proofing.configureManual(
        OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
      );
      await _mount(tester, controller, tab: WordReviewPaneTab.proofing);
      await _choose(
        tester,
        'live-proofing-language',
        'English (United States)',
      );
      expect(controller.document.proofingLanguage, 'en-US');
      expect(ordinary.requests.last.language, 'en-US');
      expect(manual.requests, isEmpty);
      controller.undo();
      await _drain(tester);
      await _reveal(tester, _key('live-proofing-language'));
      expect(
        tester
            .widget<DropdownButton<String>>(_key('live-proofing-language'))
            .value,
        'de-DE',
      );
    },
  );

  testWidgets(
    'read-only writing inspection disables document language changes',
    (tester) async {
      final controller = _controller(
        viewing: true,
        document: WmlDocument.empty(text: 'Feler'),
      );
      await _mount(tester, controller, tab: WordReviewPaneTab.proofing);
      expect(
        tester
            .widget<DropdownButton<String>>(_key('live-proofing-language'))
            .onChanged,
        isNull,
      );
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'restoring ignored findings preserves personal words and avoids manual providers',
    (tester) async {
      final manual = _Provider(providerId: 'manual-ignored-test');
      final controller = _controller(
        document: WmlDocument.empty(text: 'Feler Feler'),
      );
      controller.proofing.configureManual(
        OfficeProofingService(providers: <OfficeProofingProvider>[manual]),
      );
      await _mount(tester, controller, tab: WordReviewPaneTab.proofing);
      await _tap(tester, _key('live-proofing-ignore-once'));
      expect(controller.proofing.hasIgnoredOccurrences, isTrue);
      await _tap(tester, _key('live-proofing-ignore-word'));
      expect(controller.proofing.summary.issues, isEmpty);
      controller.proofing.ignoreRule('test.other');
      controller.proofing.vocabulary.addWord('Kept', language: 'de-DE');
      await _drain(tester);
      await _tap(tester, _key('live-proofing-review-ignored'));
      expect(controller.proofing.summary.issues, hasLength(2));
      expect(controller.proofing.hasIgnoredOccurrences, isFalse);
      expect(controller.proofing.ignoredRuleIds, isEmpty);
      expect(controller.proofing.vocabulary.ignoredWordsFor('de-DE'), isEmpty);
      expect(
        controller.proofing.vocabulary.contains('Kept', language: 'de-DE'),
        isTrue,
      );
      expect(manual.requests, isEmpty);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'current findings can be corrected while a different paragraph checks',
    (tester) async {
      final gate = Completer<void>();
      final document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[_paragraph('Feler'), _paragraph('Wait')],
          ),
        ],
      );
      final controller = _controller(
        document: document,
        provider: _Provider(gate: gate.future),
      );
      await _mount(tester, controller, tab: WordReviewPaneTab.proofing);
      expect(controller.proofing.checking, isTrue);
      await _reveal(tester, _key('live-proofing-replace-0'));
      expect(_enabled(tester, 'live-proofing-replace-0'), isTrue);
      await _tap(tester, _key('live-proofing-replace-0'));
      expect(document.paragraphs.first.text, 'Fehler');
      gate.complete();
      await _drain(tester);
      expect(controller.proofing.summary.issues, isEmpty);
    },
  );

  for (final arabic in <bool>[false, true]) {
    testWidgets(
      'narrow scaled ${arabic ? 'Arabic' : 'English'} Changes pane supports filtering and review',
      (tester) async {
        final controller = _controller(arabic: arabic);
        await _mount(
          tester,
          controller,
          size: const Size(280, 320),
          textScale: 1.5,
        );
        await _choose(tester, 'live-review-author-filter', 'Alice');
        await _choose(
          tester,
          'live-review-kind-filter',
          arabic ? 'حذف' : 'Deletions',
        );
        await _choose(
          tester,
          'live-review-preview-mode',
          arabic ? 'النص النهائي' : 'Final text',
        );
        expect(_preview(tester), '');
        await _tap(tester, _key('live-review-accept'));
        expect(controller.document.revisions, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
