import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/word_proofing_geometry.dart';

class _Checker extends OfficeProofingProvider {
  _Checker([this.status = OfficeProofingStatus.success]);
  final OfficeProofingStatus status;
  @override
  String get id => 'test-checker';
  @override
  bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: status,
        message: status == OfficeProofingStatus.success
            ? null
            : 'Test provider status',
        findings: status == OfficeProofingStatus.success
            ? <OfficeProofingFinding>[
                for (final RegExpMatch match in RegExp(
                  'Feler',
                ).allMatches(request.text))
                  OfficeProofingFinding.forRequest(
                    request,
                    providerId: id,
                    start: match.start,
                    end: match.end,
                    ruleId: 'spelling.test',
                    message: 'Check this spelling.',
                    category: OfficeProofingCategory.spelling,
                    replacements: const <String>['Fehler'],
                  ),
              ]
            : const <OfficeProofingFinding>[],
      );
}

WordEditorController _controller({
  String text = 'Ein Feler.',
  List<OfficeProofingProvider>? providers,
  OfficeSurfaceConfig config = const OfficeSurfaceConfig(),
}) => WordEditorController(
  document: WmlDocument.empty(text: text),
  config: config,
  proofingService: OfficeProofingService(
    providers: providers ?? <OfficeProofingProvider>[_Checker()],
  ),
);

Future<void> _dialog(
  WidgetTester tester,
  WordEditorController controller, {
  Size size = const Size(1100, 850),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: WordProofingDialog(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

OfficeProofingFinding _finding(String text, int start, int end) =>
    OfficeProofingFinding.forRequest(
      OfficeProofingRequest(
        documentId: 'document',
        blockId: 'paragraph',
        revision: 1,
        text: text,
      ),
      providerId: 'test',
      start: start,
      end: end,
      ruleId: 'test',
      message: 'Test',
      category: OfficeProofingCategory.spelling,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final OfficeProofingStatus status in <OfficeProofingStatus>[
    OfficeProofingStatus.unavailable,
    OfficeProofingStatus.unsupported,
    OfficeProofingStatus.failed,
  ]) {
    testWidgets('${status.name} is shown without claiming clean text', (
      tester,
    ) async {
      final controller = _controller(
        providers: <OfficeProofingProvider>[_Checker(status)],
      );
      await _dialog(tester, controller);
      expect(
        find.text('The check is incomplete. Review provider status below.'),
        findsOneWidget,
      );
      expect(find.text('No findings in checked text.'), findsNothing);
      expect(find.textContaining('test-checker · de-DE:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('no configured provider is explicitly unavailable', (
    tester,
  ) async {
    final controller = _controller(providers: const <OfficeProofingProvider>[]);
    await _dialog(tester, controller);
    expect(
      find.textContaining('proofing · de-DE: Unavailable'),
      findsOneWidget,
    );
    expect(find.text('No findings in checked text.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('suggestion applies to source and remains undoable', (
    tester,
  ) async {
    final controller = _controller(text: '😀 Ein Feler.');
    await _dialog(tester, controller);
    expect(find.text('1 findings to review.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Fehler'));
    await tester.pumpAndSettle();
    expect(controller.document.paragraphs.single.text, '😀 Ein Fehler.');
    expect(find.text('Correction applied. You can undo it.'), findsOneWidget);
    controller.undo();
    expect(controller.document.paragraphs.single.text, '😀 Ein Feler.');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('read-only review exposes findings but disables replacements', (
    tester,
  ) async {
    final controller = _controller(
      config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
    );
    await _dialog(tester, controller);
    final ActionChip chip = tester.widget(
      find.widgetWithText(ActionChip, 'Fehler'),
    );
    expect(chip.onPressed, isNull);
    expect(controller.document.paragraphs.single.text, 'Ein Feler.');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'language and hyphenation controls save an undoable document setting',
    (tester) async {
      final controller = _controller(text: 'Text.');
      await _dialog(tester, controller);
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Automatic German hyphenation'),
      );
      await tester.pumpAndSettle();
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, 'de-DE');
      controller.undo();
      expect(controller.document.autoHyphenation, isFalse);
      expect(controller.document.proofingLanguage, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('review fits a narrow viewport', (tester) async {
    final controller = _controller();
    await _dialog(tester, controller, size: const Size(360, 740));
    expect(find.text('Spelling and writing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'standalone editor handles F7 and releases background timers on detach',
    (tester) async {
      final controller = _controller();
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QudsWordEditor(controller: controller, focusNode: focus),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WordProofingDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // Keep the host controller alive until after widget detachment. The test
      // binding will reject leaked debounce timers at the end of this test.
      focus.dispose();
      addTearDown(controller.dispose);
    },
  );

  test(
    'underline wraps at discretionary hyphen without owning the following letter',
    () {
      const source = 'Silben';
      final doc = WmlDocument.empty(text: source)
        ..proofingLanguage = 'de-DE'
        ..autoHyphenation = true;
      doc.sections.single
        ..pageSize = const WmlPageSize(width: 42, height: 200)
        ..margins = const WmlPageMargins(
          left: 10,
          right: 10,
          top: 10,
          bottom: 10,
        );
      final lines = WordLayoutEngine(
        font: null,
        measure: (cp, size, props) => cp == 0x2d ? 3 : 6,
      ).layout(doc).pages.expand((page) => page.lines).toList();
      expect(lines, hasLength(2));
      expect(proofingRectsOnLine(lines.first, _finding(source, 3, 6)), isEmpty);
      final first = proofingRectsOnLine(
        lines.first,
        _finding(source, 0, 3),
      ).single;
      expect(
        first.right,
        lines.first.glyphs.last.x + lines.first.glyphs.last.advance,
      );
      final second = proofingRectsOnLine(
        lines.last,
        _finding(source, 2, 5),
      ).single;
      expect(second.right, lines.last.glyphs.last.x);
    },
  );

  test(
    'bidi underline follows the visual Hebrew run after a non-BMP prefix',
    () {
      const source = '😀 abc אבג xyz';
      final doc = WmlDocument.empty(text: source);
      final line = WordLayoutEngine(
        font: null,
        measure: (cp, size, props) => 6,
      ).layout(doc).pages.first.lines.single;
      final start = source.indexOf('אבג');
      final rect = proofingRectsOnLine(
        line,
        _finding(source, start, start + 3),
      ).single;
      final glyphs = line.glyphs
          .where(
            (g) => g.glyph.codePoint >= 0x5d0 && g.glyph.codePoint <= 0x5ea,
          )
          .toList();
      final left = glyphs.map((g) => g.x).reduce((a, b) => a < b ? a : b);
      final right = glyphs
          .map((g) => g.x + g.advance)
          .reduce((a, b) => a > b ? a : b);
      expect(rect.left, left);
      expect(rect.right, right);
    },
  );

  test(
    'repeated header tab text maps a finding only to its actual fragment',
    () {
      const source = '  😀 Feler\tFeler  ';
      final header = WmlParagraph(inlines: <WmlInline>[WmlRun(text: source)]);
      final doc = WmlDocument.empty(text: 'Body');
      doc.sections.single.header.add(header);
      final lines = WordLayoutEngine(font: null).layout(doc).pages.first.header;
      final start = source.lastIndexOf('Feler');
      expect(proofingLayoutRanges(lines.first, start, start + 5), isEmpty);
      expect(proofingLayoutRanges(lines.last, start, start + 5), <(int, int)>[
        (0, 5),
      ]);
    },
  );
}
