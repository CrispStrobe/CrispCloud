import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'support/review_fonts.dart';

WmlParagraph _paragraph(String text, {bool newPage = false}) => WmlParagraph(
  properties: WmlParagraphProps(pageBreakBefore: newPage),
  inlines: [WmlRun(text: text)],
);

final class _Provider extends OfficeProofingProvider {
  @override
  String get id => 'header-footer-navigation';

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
            ruleId: 'spelling',
            start: match.start,
            end: match.end,
            message: 'Use Fehler.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
      ],
    );
  }
}

List<WmlParagraph> _story(
  WmlSection section,
  bool footer,
  WordHeaderFooterVariant variant,
) => switch (variant) {
  WordHeaderFooterVariant.standard => footer ? section.footer : section.header,
  WordHeaderFooterVariant.firstPage =>
    footer ? section.firstFooter : section.firstHeader,
  WordHeaderFooterVariant.evenPage =>
    footer ? section.evenFooter : section.evenHeader,
};

WmlDocument _document() {
  final section = WmlSection(
    pageSize: const WmlPageSize(width: 420, height: 360),
    margins: const WmlPageMargins(
      top: 90,
      bottom: 80,
      left: 48,
      right: 48,
      header: 24,
      footer: 24,
    ),
    differentFirstPage: true,
    differentOddEven: true,
    blocks: [
      _paragraph('Body one'),
      _paragraph('Body two', newPage: true),
      _paragraph('Body three', newPage: true),
    ],
  );
  for (final footer in [false, true]) {
    for (final variant in WordHeaderFooterVariant.values) {
      _story(section, footer, variant).addAll([
        _paragraph('${variant.name} context'),
        _paragraph('  Feler ${variant.name} ${footer ? 'footer' : 'header'}'),
      ]);
    }
  }
  return WmlDocument(proofingLanguage: 'de-DE', sections: [section]);
}

WordEditorController _controller(WmlDocument document, {_Provider? provider}) {
  final controller = WordEditorController(
    document: document,
    config: const OfficeSurfaceConfig(showRulers: false),
    proofingService: OfficeProofingService(
      providers: [provider ?? _Provider()],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

int _pageFor(WordHeaderFooterVariant variant) => switch (variant) {
  WordHeaderFooterVariant.firstPage => 0,
  WordHeaderFooterVariant.evenPage => 1,
  WordHeaderFooterVariant.standard => 2,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final footer in [false, true]) {
    for (final variant in WordHeaderFooterVariant.values) {
      test(
        '${variant.name} ${footer ? 'footer' : 'header'} reveals, edits and undoes its exact source',
        () async {
          final document = _document();
          final controller = _controller(document);
          final paragraphs = _story(document.sections.single, footer, variant);
          final paragraph = paragraphs[1];
          final original = paragraph.text;
          final summary = await controller.checkDocumentProofing();
          final issue = summary.issues.singleWhere(
            (issue) => identical(issue.paragraph, paragraph),
          );

          expect(controller.documentLaidOut.pages, hasLength(3));
          expect(controller.revealProofingIssue(issue), isTrue);
          expect(controller.editingHeaderFooterVariant, variant);
          expect(controller.isEditingFooter, footer);
          expect(controller.headerFooterParagraphs, same(paragraphs));
          expect(controller.caret.paragraphIndex, 1);
          expect(controller.input.value.text, original);
          expect(
            controller.input.value.selection,
            const TextSelection(baseOffset: 2, extentOffset: 7),
          );
          expect(controller.isDirty, isFalse);
          expect(controller.canUndo, isFalse);

          expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
          expect(paragraph.text, original.replaceFirst('Feler', 'Fehler'));
          expect(document.paragraphs.map((paragraph) => paragraph.text), [
            'Body one',
            'Body two',
            'Body three',
          ]);
          for (final other in WordHeaderFooterVariant.values) {
            if (other == variant) continue;
            expect(
              _story(document.sections.single, footer, other)[1].text,
              contains('Feler'),
            );
          }
          controller.undo();
          expect(paragraph.text, original);
          expect(controller.headerFooterParagraphs, same(paragraphs));
          expect(controller.input.value.text, original);
        },
      );
    }
  }

  for (final variant in [
    WordHeaderFooterVariant.firstPage,
    WordHeaderFooterVariant.evenPage,
  ]) {
    test(
      '${variant.name} typing and language controls stay in that story',
      () async {
        final document = _document();
        final provider = _Provider();
        final controller = _controller(document, provider: provider);
        final paragraphs = _story(document.sections.single, false, variant);
        controller.beginHeaderFooterEdit(_pageFor(variant), footer: false);
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 2
          ..selectionAnchorParagraph = 1
          ..selectionAnchor = 2;
        await controller.proofing.checkNow(includeManualProviders: false);
        expect(provider.requests.first.text, paragraphs[1].text);
        final target = controller.textProofingTarget!;
        expect(
          controller.setTextProofingLanguage('en-US', target: target),
          isTrue,
        );
        expect(
          paragraphs[1].inlines
              .whereType<WmlRun>()
              .first
              .properties
              .proofingLanguage,
          'en-US',
        );
        expect(
          document.sections.single.header[1].inlines
              .whereType<WmlRun>()
              .first
              .properties
              .proofingLanguage,
          isNull,
        );
        controller.undo();
        final original = paragraphs[1].text;
        controller.applyImeText(original.replaceFirst('Feler', 'Fehler'));
        expect(paragraphs[1].text, original.replaceFirst('Feler', 'Fehler'));
        expect(document.sections.single.header[1].text, contains('Feler'));
        controller.undo();
        expect(paragraphs[1].text, original);
      },
    );
  }

  test(
    'first-page selection takes precedence in a later even-numbered section',
    () {
      final document = _document();
      final preceding = WmlSection(blocks: [_paragraph('Preceding section')]);
      document.sections.insert(0, preceding);
      final controller = _controller(document);
      expect(controller.documentLaidOut.pages[1].sectionIndex, 1);
      controller.beginHeaderFooterEdit(1, footer: true);
      expect(controller.editingSectionIndex, 1);
      expect(
        controller.editingHeaderFooterVariant,
        WordHeaderFooterVariant.firstPage,
      );
      expect(
        controller.headerFooterParagraphs,
        same(document.sections[1].firstFooter),
      );
    },
  );

  test(
    'hidden variants do not change page settings or redirect to the default story',
    () async {
      final document = _document();
      document.sections.single
        ..differentFirstPage = false
        ..differentOddEven = false;
      final controller = _controller(document);
      final summary = await controller.checkDocumentProofing();
      controller.beginHeaderFooterEdit(0, footer: false);
      final before = controller.input.value;
      for (final variant in [
        WordHeaderFooterVariant.firstPage,
        WordHeaderFooterVariant.evenPage,
      ]) {
        final paragraph = _story(document.sections.single, false, variant)[1];
        final issue = summary.issues.singleWhere(
          (issue) => identical(issue.paragraph, paragraph),
        );
        expect(controller.revealProofingIssue(issue), isFalse);
        expect(
          controller.editingHeaderFooterVariant,
          WordHeaderFooterVariant.standard,
        );
        expect(controller.input.value, before);
      }
      expect(document.sections.single.differentFirstPage, isFalse);
      expect(document.sections.single.differentOddEven, isFalse);
      expect(controller.canUndo, isFalse);
    },
  );

  for (final protected in [false, true]) {
    test(
      '${protected ? 'protected' : 'select-only'} variant navigation preserves source',
      () async {
        final document = _document();
        if (protected) {
          document
            ..restrictEditing = true
            ..restrictMode = WmlRestrictMode.readOnly;
        }
        final controller = _controller(document);
        // A protected document can explicitly allow selecting/copying text.
        // Its default viewing mode remains nonselectable.
        controller.setMode(OfficeInteractionMode.selecting);
        final summary = await controller.checkDocumentProofing();
        final paragraph = document.sections.single.evenFooter[1];
        final issue = summary.issues.singleWhere(
          (issue) => identical(issue.paragraph, paragraph),
        );
        expect(controller.revealProofingIssue(issue), isTrue);
        expect(controller.headerFooterParagraphs[1], same(paragraph));
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
        controller.applyImeText('Changed');
        expect(paragraph.text, contains('Feler'));
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test(
    'inspecting an empty header in select-only mode creates no paragraph',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final controller = _controller(document);
      controller.setMode(OfficeInteractionMode.selecting);
      controller.beginHeaderFooterEdit(0, footer: false);
      expect(controller.headerFooterParagraphs.single.text, isEmpty);
      expect(document.sections.single.header, isEmpty);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'a captured language action expires after switching variants at the same offsets',
    () {
      final document = _document();
      final controller = _controller(document);
      controller.beginHeaderFooterEdit(0, footer: false);
      final target = controller.textProofingTarget!;
      controller.beginHeaderFooterEdit(1, footer: false);
      expect(
        controller.setTextProofingLanguage('en-US', target: target),
        isFalse,
      );
      expect(
        document.sections.single.firstHeader.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .proofingLanguage,
        isNull,
      );
      expect(
        document.sections.single.evenHeader.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .proofingLanguage,
        isNull,
      );
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'tracked changes reveal the exact alternate story and survive DOCX save',
    () {
      final document = _document();
      final controller = _controller(document);
      document.trackRevisions = true;
      controller.beginHeaderFooterEdit(1, footer: true);
      controller.caret
        ..paragraphIndex = 1
        ..logicalIndex = 2
        ..collapseSelection();
      controller.insertText('New ');
      final revision = document.revisions.single;
      controller.endHeaderFooterEdit();
      expect(controller.revealRevision(revision), isTrue);
      expect(
        controller.editingHeaderFooterVariant,
        WordHeaderFooterVariant.evenPage,
      );
      expect(controller.isEditingFooter, isTrue);
      expect(controller.caret.selectionAnchor, 2);
      expect(controller.caret.logicalIndex, 6);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(
        reopened.sections.single.evenFooter[1].text,
        contains('New Feler'),
      );
      expect(reopened.sections.single.footer[1].text, isNot(contains('New ')));
    },
  );

  testWidgets(
    'pointer switches first/even stories and keyboard hit uses actual text geometry',
    (tester) async {
      final document = _document();
      final controller = _controller(document);
      final focus = FocusNode();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1100);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        focus.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: const ['Noto Naskh Arabic'],
          ),
          home: Scaffold(
            body: QudsWordEditor(controller: controller, focusNode: focus),
          ),
        ),
      );
      controller.proofing.enabled = false;
      controller.beginHeaderFooterEdit(0, footer: false);
      await tester.pump();
      final canvas = tester.renderObject<RenderWordCanvas>(
        find.byType(WordCanvas),
      );
      final line = controller.documentLaidOut.pages[1].header.last;
      final painter = PaintRunText.plain(
        text: line.overlayText!,
        fontSize: line.overlaySize,
        color: Colors.black,
        themeFamily: controller.config.theme.fontFamily,
      )..layout();
      final box = painter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 2),
          )
          .single;
      final point = canvas.localToGlobal(
        canvas.windowForPagePoint(
          1,
          Offset(
            line.x + box.left + (box.right - box.left) * .2,
            line.y + painter.height / 2,
          ),
        ),
      );
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.up();
      await tester.pump();
      expect(
        controller.editingHeaderFooterVariant,
        WordHeaderFooterVariant.evenPage,
      );
      expect(
        controller.headerFooterParagraphs,
        same(document.sections.single.evenHeader),
      );
      expect(controller.caret.paragraphIndex, 1);
      expect(controller.caret.logicalIndex, 3);
      final hit = canvas.contextHitForCaret();
      expect(hit, isNotNull);
      expect(hit!.paragraph, same(document.sections.single.evenHeader[1]));
      expect(hit.proofingOffset, 3);
      expect(tester.takeException(), isNull);
      painter.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final footer in [false, true]) {
    testWidgets(
      'selecting ${footer ? 'footer' : 'header'} paragraphs leaves body table cells unselected',
      (tester) async {
        final section = WmlSection(
          pageSize: const WmlPageSize(width: 420, height: 360),
          margins: const WmlPageMargins(
            top: 90,
            bottom: 80,
            left: 48,
            right: 48,
            header: 24,
            footer: 24,
          ),
          header: [_paragraph('First header'), _paragraph('Second header')],
          footer: [_paragraph('First footer'), _paragraph('Second footer')],
          blocks: [
            WmlTable(
              grid: [140, 140],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [_paragraph('Left body cell')]),
                    WmlTableCell(blocks: [_paragraph('Right body cell')]),
                  ],
                ),
              ],
            ),
          ],
        );
        final controller = _controller(WmlDocument(sections: [section]));
        controller.proofing.enabled = false;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 700);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        const pictureKey = Key('header-body-table-picture');
        await tester.pumpWidget(
          RepaintBoundary(
            key: pictureKey,
            child: MaterialApp(
              theme: ThemeData(
                fontFamily: 'Liberation Sans',
                fontFamilyFallback: const ['Noto Naskh Arabic'],
              ),
              home: Scaffold(body: QudsWordEditor(controller: controller)),
            ),
          ),
        );
        controller.beginHeaderFooterEdit(0, footer: footer);
        await tester.pump();
        final canvas = tester.renderObject<RenderWordCanvas>(
          find.byType(WordCanvas),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(pictureKey),
        );
        final cells = controller.documentLaidOut.pages.single.frames
            .where((box) => box.kind == LaidOutBoxKind.tableCell)
            .toList();
        expect(cells, hasLength(2));

        Future<List<int>> bodyTablePixels() async {
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final data = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          final pixels = data.buffer.asUint8List();
          final sampled = <int>[];
          for (final cell in cells) {
            final start = boundary.globalToLocal(
              canvas.localToGlobal(
                canvas.windowForPagePoint(0, Offset(cell.x + 2, cell.y + 2)),
              ),
            );
            final end = boundary.globalToLocal(
              canvas.localToGlobal(
                canvas.windowForPagePoint(
                  0,
                  Offset(cell.x + cell.width - 2, cell.y + cell.height - 2),
                ),
              ),
            );
            expect(start.dx.ceil(), greaterThanOrEqualTo(0));
            expect(start.dy.ceil(), greaterThanOrEqualTo(0));
            expect(end.dx.floor(), lessThanOrEqualTo(image.width));
            expect(end.dy.floor(), lessThanOrEqualTo(image.height));
            for (var y = start.dy.ceil(); y < end.dy.floor(); y++) {
              for (var x = start.dx.ceil(); x < end.dx.floor(); x++) {
                final index = (y * image.width + x) * 4;
                sampled.addAll(pixels.sublist(index, index + 4));
              }
            }
          }
          image.dispose();
          expect(sampled, isNotEmpty);
          return sampled;
        }

        final before = await bodyTablePixels();
        controller.headerFooterCaret
          ..paragraphIndex = 1
          ..logicalIndex = 6
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 0;
        controller.refreshView();
        await tester.pump();
        expect(controller.headerFooterCaret.isCollapsed, isFalse);
        expect(await bodyTablePixels(), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('alternate header selection remains visible below its text', (
    tester,
  ) async {
    final document = _document();
    final controller = _controller(document);
    controller.syncConfig(
      controller.config.copyWith(
        theme: OfficeTheme.light.copyWith(
          textSelectionFill: const Color(0xFFB3D7FF),
        ),
      ),
    );
    controller.proofing.enabled = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const pictureKey = Key('alternate-header-picture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: pictureKey,
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: const ['Noto Naskh Arabic'],
          ),
          home: Scaffold(body: QudsWordEditor(controller: controller)),
        ),
      ),
    );
    final summary = (await tester.runAsync(controller.checkDocumentProofing))!;
    final paragraph = document.sections.single.evenHeader[1];
    final issue = summary.issues.singleWhere(
      (issue) => identical(issue.paragraph, paragraph),
    );
    expect(controller.revealProofingIssue(issue), isTrue);
    await tester.pump();
    final canvas = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(pictureKey),
    );
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final pixels = data!.buffer.asUint8List();

    ({int highlight, int ink}) countInk(int pageIndex) {
      final line = controller.documentLaidOut.pages[pageIndex].header.last;
      final painter = PaintRunText.plain(
        text: line.overlayText!,
        fontSize: line.overlaySize,
        color: Colors.black,
        themeFamily: controller.config.theme.fontFamily,
      )..layout();
      final box = painter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 5),
          )
          .single;
      final origin = boundary.globalToLocal(
        canvas.localToGlobal(
          canvas.windowForPagePoint(
            pageIndex,
            Offset(line.x + box.left, line.y + box.top),
          ),
        ),
      );
      final end = boundary.globalToLocal(
        canvas.localToGlobal(
          canvas.windowForPagePoint(
            pageIndex,
            Offset(line.x + box.right, line.y + box.bottom),
          ),
        ),
      );
      painter.dispose();
      var highlight = 0;
      var ink = 0;
      for (var y = origin.dy.ceil(); y < end.dy.floor(); y++) {
        for (var x = origin.dx.ceil(); x < end.dx.floor(); x++) {
          if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
          final index = (y * image.width + x) * 4;
          final red = pixels[index];
          final green = pixels[index + 1];
          final blue = pixels[index + 2];
          if (red == 179 && green == 215 && blue == 255) highlight++;
          if (red < 150 && green < 150 && blue < 150) ink++;
        }
      }
      return (highlight: highlight, ink: ink);
    }

    final selected = countInk(1);
    expect(selected.highlight, greaterThan(20));
    expect(selected.ink, greaterThan(10));
    expect(countInk(2).highlight, 0);
    final screenshot = Platform.environment['QUDS_HEADER_REVIEW_SCREENSHOT'];
    if (screenshot != null && screenshot.isNotEmpty) {
      final png = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      await tester.runAsync(
        () => File(screenshot).writeAsBytes(png!.buffer.asUint8List()),
      );
    }
    image.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
