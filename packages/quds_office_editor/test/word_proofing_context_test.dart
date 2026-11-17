import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _ContextProvider extends OfficeProofingProvider {
  _ContextProvider(this.target, {this.insertion = false});

  final String target;
  final bool insertion;

  @override
  String get id => 'context-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    final int start = request.text.indexOf(target);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: <OfficeProofingFinding>[
        if (start >= 0)
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: start,
            end: insertion ? start : start + target.length,
            ruleId: 'context-rule',
            message: 'Review this passage.',
            category: OfficeProofingCategory.grammar,
            replacements: <String>[insertion ? ',' : 'correction'],
          ),
      ],
    );
  }
}

Future<WordEditorController> _open(
  WidgetTester tester,
  String source,
  _ContextProvider provider, {
  Size size = const Size(1000, 1100),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final WordEditorController controller = WordEditorController(
    document: WmlDocument.empty(text: source),
    proofingService: OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
    ),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: WordProofingDialog(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Text _excerpt(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey<String>('proofing-context')));

TextSpan _highlight(Text excerpt) => (excerpt.textSpan! as TextSpan).children!
    .whereType<TextSpan>()
    .singleWhere((TextSpan span) => span.style?.fontWeight == FontWeight.bold);

void main() {
  testWidgets('review centers a late finding and preserves Unicode clusters', (
    WidgetTester tester,
  ) async {
    final String source =
        'PARAGRAPH START ${List<String>.filled(70, '👩‍🔬 a\u0308 ').join()}'
        'Feler${List<String>.filled(60, ' e\u0301🎉').join()} PARAGRAPH END';
    final WordEditorController controller = await _open(
      tester,
      source,
      _ContextProvider('Feler'),
    );
    final Text excerpt = _excerpt(tester);
    final String text = excerpt.textSpan!.toPlainText();
    expect(text, contains('Feler'));
    expect(text, startsWith('…'));
    expect(text, endsWith('…'));
    expect(text, isNot(contains('PARAGRAPH START')));
    expect(text, isNot(contains('PARAGRAPH END')));
    expect(text, isNot(contains('\ufffd')));
    expect(_highlight(excerpt).text, 'Feler');
    expect(_highlight(excerpt).style!.decoration, TextDecoration.underline);
    final List<TextSpan> spans = (excerpt.textSpan! as TextSpan).children!
        .cast<TextSpan>();
    final String prefix = spans.first.text!.substring(1);
    final String suffix = spans.last.text!;
    final int excerptStart = source.indexOf('Feler') - prefix.length;
    final int excerptEnd = source.indexOf('Feler') + 5 + suffix.length - 1;
    final Set<int> boundaries = <int>{
      0,
      for (final GraphemeCluster cluster in GraphemeClusters.segment(source))
        cluster.end,
    };
    expect(boundaries, contains(excerptStart));
    expect(boundaries, contains(excerptEnd));
    expect(controller.document.paragraphs.first.text, source);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('an insertion has a visible and accessible context marker', (
    WidgetTester tester,
  ) async {
    const String source = 'Ich hoffe dass alles klappt.';
    await _open(tester, source, _ContextProvider(' dass', insertion: true));
    final Text excerpt = _excerpt(tester);
    expect(
      excerpt.textSpan!.toPlainText(includeSemanticsLabels: false),
      'Ich hoffe│ dass alles klappt.',
    );
    expect(_highlight(excerpt).semanticsLabel, 'insertion point');
    expect(excerpt.textSpan!.toPlainText(), contains('insertion point'));
  });

  testWidgets('short passages retain their complete context without ellipses', (
    WidgetTester tester,
  ) async {
    const String source = 'Start Feler Ende.';
    await _open(tester, source, _ContextProvider('Feler'));
    expect(_excerpt(tester).textSpan!.toPlainText(), source);
  });

  testWidgets('long findings remain bounded without splitting joined emoji', (
    WidgetTester tester,
  ) async {
    final String target = List<String>.filled(150, '👩‍🔬').join();
    final String source = 'Before $target after.';
    final WordEditorController controller = await _open(
      tester,
      source,
      _ContextProvider(target),
    );
    expect(
      _highlight(_excerpt(tester)).text,
      '${List<String>.filled(100, '👩‍🔬').join()}…',
    );
    expect(
      controller.proofing.summary.issues.single.finding.originalText,
      target,
    );
    expect(controller.document.paragraphs.first.text, source);
  });

  testWidgets('narrow review at large text scale does not hide its finding', (
    WidgetTester tester,
  ) async {
    final String source =
        '${List<String>.filled(30, 'Earlier prose. ').join()}Feler near the end.';
    await _open(
      tester,
      source,
      _ContextProvider('Feler'),
      size: const Size(360, 900),
      scale: 1.5,
    );
    final Finder context = find.byKey(
      const ValueKey<String>('proofing-context'),
    );
    await tester.scrollUntilVisible(
      context,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(_excerpt(tester).maxLines, isNull);
    expect(_highlight(_excerpt(tester)).text, 'Feler');
    expect(tester.takeException(), isNull);
  });
}
