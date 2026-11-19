import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlSection _section(
  String text, {
  WmlSectionBreakKind start = WmlSectionBreakKind.nextPage,
}) => WmlSection(
  breakKind: start,
  blocks: <WmlBlock>[
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]),
  ],
);

WordEditorController _controller(List<WmlSection> sections) {
  final controller = WordEditorController(
    document: WmlDocument(sections: sections),
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _caretIn(WordEditorController controller, int paragraph) {
  controller.documentCaret
    ..paragraphIndex = paragraph
    ..logicalIndex = 0
    ..collapseSelection();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Page Layout applies every supported setting in one undo step', () {
    final first = _section('First');
    final second = _section('Second');
    second.header.add(
      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Keep header')]),
    );
    final header = second.header.single;
    final controller = _controller(<WmlSection>[first, second]);
    _caretIn(controller, 1);
    final target = controller.capturePageLayout();
    final firstBefore = WordPageLayoutSettings.fromSection(first);
    final next = target.settings.copyWith(
      pageSize: WmlPageSize.letter().landscape,
      margins: const WmlPageMargins(
        top: 40,
        bottom: 44,
        left: 48,
        right: 52,
        header: 18,
        footer: 20,
      ),
      columnCount: 2,
      columnSpace: 24,
      columnSeparator: true,
      sectionStart: WmlSectionBreakKind.oddPage,
      differentFirstPage: true,
      differentOddEven: true,
      lineNumbers: true,
    );

    expect(controller.applyPageLayout(next, target: target), isTrue);
    expect(WordPageLayoutSettings.fromSection(second).matches(next), isTrue);
    expect(first.differentOddEven, isTrue);
    expect(first.pageSize.width, firstBefore.pageSize.width);
    expect(second.header.single, same(header));
    expect(controller.isDirty, isTrue);
    expect(controller.contentRevision, target.contentRevision + 1);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.canUndo, isFalse);
    expect(
      WordPageLayoutSettings.fromSection(
        second,
      ).matches(target.sectionSettings[1]),
      isTrue,
    );
    expect(
      WordPageLayoutSettings.fromSection(first).matches(firstBefore),
      isTrue,
    );
    expect(second.header.single, same(header));
    controller.redo();
    expect(WordPageLayoutSettings.fromSection(second).matches(next), isTrue);
    expect(second.header.single, same(header));
  });

  test(
    'page geometry follows continuous siblings but section options do not',
    () {
      final heading = _section('Heading');
      final body = _section('Body', start: WmlSectionBreakKind.continuous);
      final later = _section('Later');
      final controller = _controller(<WmlSection>[heading, body, later]);
      _caretIn(controller, 1);
      final target = controller.capturePageLayout();
      final next = target.settings.copyWith(
        pageSize: target.settings.pageSize.landscape,
        margins: WmlPageMargins.narrow,
        columnCount: 3,
        columnSpace: 18,
        differentFirstPage: true,
      );

      expect(controller.applyPageLayout(next, target: target), isTrue);
      expect(heading.pageSize.isLandscape, isTrue);
      expect(heading.margins.top, 36);
      expect(heading.columnCount, 1);
      expect(heading.differentFirstPage, isFalse);
      expect(body.pageSize.isLandscape, isTrue);
      expect(body.columnCount, 3);
      expect(body.differentFirstPage, isTrue);
      expect(later.pageSize.isLandscape, isFalse);
      expect(later.margins.top, 72);
      controller.undo();
      expect(heading.pageSize.isLandscape, isFalse);
      expect(body.pageSize.isLandscape, isFalse);
      expect(body.columnCount, 1);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'whole document applies values while preserving existing section starts',
    () {
      final first = _section('First');
      final second = _section('Second', start: WmlSectionBreakKind.continuous)
        ..columnCount = 2;
      final third = _section('Third', start: WmlSectionBreakKind.evenPage)
        ..pageSize = WmlPageSize.legal();
      final controller = _controller(<WmlSection>[first, second, third]);
      final target = controller.capturePageLayout();
      final next = target.settings.copyWith(
        pageSize: WmlPageSize.a3(),
        margins: WmlPageMargins.moderate,
        columnCount: 3,
        columnSpace: 18,
        columnSeparator: true,
        differentFirstPage: true,
        lineNumbers: true,
        sectionStart: WmlSectionBreakKind.oddPage,
      );
      expect(
        controller.applyPageLayout(
          next,
          scope: WordPageLayoutScope.wholeDocument,
          target: target,
        ),
        isTrue,
      );
      for (final section in controller.document.sections) {
        expect(section.pageSize.matches(WmlPageSize.a3()), isTrue);
        expect(section.margins.matches(WmlPageMargins.moderate), isTrue);
        expect(section.columnCount, 3);
        expect(section.columnSpace, 18);
        expect(section.columnSep, isTrue);
        expect(section.differentFirstPage, isTrue);
        expect(section.lineNumbers, isTrue);
      }
      expect(first.breakKind, WmlSectionBreakKind.nextPage);
      expect(second.breakKind, WmlSectionBreakKind.continuous);
      expect(third.breakKind, WmlSectionBreakKind.evenPage);
      controller.undo();
      for (var index = 0; index < target.sections.length; index++) {
        expect(
          WordPageLayoutSettings.fromSection(
            target.sections[index],
          ).matches(target.sectionSettings[index]),
          isTrue,
        );
      }
      expect(controller.canUndo, isFalse);
    },
  );

  test('invalid drafts are atomic and do not mark the document dirty', () {
    final controller = _controller(<WmlSection>[_section('Keep me')]);
    final target = controller.capturePageLayout();
    final invalid = <WordPageLayoutSettings>[
      target.settings.copyWith(pageSize: const WmlPageSize(width: 0)),
      target.settings.copyWith(pageSize: const WmlPageSize(width: double.nan)),
      target.settings.copyWith(margins: const WmlPageMargins(left: -1)),
      target.settings.copyWith(
        margins: const WmlPageMargins(left: 500, right: 500),
      ),
      target.settings.copyWith(margins: const WmlPageMargins(header: 900)),
      target.settings.copyWith(columnCount: 5),
      target.settings.copyWith(columnSpace: -1),
      target.settings.copyWith(columnCount: 4, columnSpace: 200),
    ];
    for (final draft in invalid) {
      expect(draft.validationIssue, isNotNull);
      expect(controller.applyPageLayout(draft, target: target), isFalse);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, target.contentRevision);
      expect(
        WordPageLayoutSettings.fromSection(
          target.section,
        ).matches(target.settings),
        isTrue,
      );
    }
  });

  test('shared geometry rejects a change that cannot fit a sibling column', () {
    final heading = _section('Heading')
      ..columnCount = 4
      ..columnSpace = 100;
    final body = _section('Body', start: WmlSectionBreakKind.continuous);
    final controller = _controller(<WmlSection>[heading, body]);
    _caretIn(controller, 1);
    final target = controller.capturePageLayout();
    final next = target.settings.copyWith(
      margins: const WmlPageMargins(left: 200, right: 200),
    );
    expect(next.validationIssue, isNull);
    expect(controller.applyPageLayout(next, target: target), isFalse);
    expect(heading.margins.left, 72);
    expect(body.margins.left, 72);
    expect(controller.canUndo, isFalse);
  });

  test('unchanged exact measurements produce no history or rounding', () {
    final section = _section(
      'Original',
    )..margins = const WmlPageMargins(left: 71.123456789, header: 31.987654321);
    final controller = _controller(<WmlSection>[section]);
    final target = controller.capturePageLayout();
    expect(controller.applyPageLayout(target.settings, target: target), isTrue);
    expect(controller.contentRevision, target.contentRevision);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(section.margins.left, 71.123456789);
    expect(section.margins.header, 31.987654321);
  });

  test(
    'stale document, section, revision and direct layout edits are rejected',
    () {
      final controller = _controller(<WmlSection>[_section('Original')]);
      var target = controller.capturePageLayout();
      final next = target.settings.copyWith(margins: WmlPageMargins.narrow);
      controller.document = WmlDocument.empty(text: 'Replacement');
      expect(controller.applyPageLayout(next, target: target), isFalse);
      expect(controller.document.sections.single.margins.top, 72);

      target = controller.capturePageLayout();
      controller.document.sections[0] = _section('Replaced section');
      expect(controller.applyPageLayout(next, target: target), isFalse);

      target = controller.capturePageLayout();
      controller.insertText('Changed ');
      expect(controller.applyPageLayout(next, target: target), isFalse);
      expect(
        controller.document.paragraphs.single.text,
        startsWith('Changed '),
      );
      controller.undo();

      target = controller.capturePageLayout();
      controller.document.sections.single.margins = WmlPageMargins.wide;
      expect(controller.applyPageLayout(next, target: target), isFalse);
      expect(controller.pageMargins.left, 144);

      target = controller.capturePageLayout();
      controller.config = controller.config.copyWith(
        mode: OfficeInteractionMode.viewing,
      );
      expect(controller.applyPageLayout(next, target: target), isFalse);
      expect(controller.pageMargins.left, 144);
    },
  );

  test('captured section survives caret movement while the dialog is open', () {
    final first = _section('First');
    final second = _section('Second');
    final controller = _controller(<WmlSection>[first, second]);
    final target = controller.capturePageLayout();
    _caretIn(controller, 1);
    expect(
      controller.applyPageLayout(
        target.settings.copyWith(columnCount: 2),
        target: target,
      ),
      isTrue,
    );
    expect(first.columnCount, 2);
    expect(second.columnCount, 1);
  });

  test('DOCX roundtrip keeps all applied modeled values', () {
    final controller = _controller(<WmlSection>[_section('Export me')]);
    final target = controller.capturePageLayout();
    final next = target.settings.copyWith(
      pageSize: const WmlPageSize(width: 700, height: 900),
      margins: const WmlPageMargins(
        top: 44,
        bottom: 46,
        left: 48,
        right: 50,
        header: 22,
        footer: 24,
      ),
      columnCount: 2,
      columnSpace: 30,
      columnSeparator: true,
      differentFirstPage: true,
      differentOddEven: true,
      lineNumbers: true,
    );
    expect(controller.applyPageLayout(next, target: target), isTrue);
    final copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(controller.document),
    );
    expect(
      WordPageLayoutSettings.fromSection(copy.sections.single).matches(next),
      isTrue,
    );
    expect(copy.paragraphs.single.text, 'Export me');
  });

  test(
    'unrelated layout edits preserve imported section XML and custom columns',
    () {
      final package = WordSerializer().write(
        WmlDocument.empty(text: 'Imported'),
      );
      final part = package.getPart('/word/document.xml')!;
      final xml = part
          .readText()
          .replaceFirst(
            '</w:sectPr>',
            '<w:pgNumType w:start="7"/><w:docGrid w:type="lines" w:linePitch="360"/></w:sectPr>',
          )
          .replaceFirst(
            RegExp(r'<w:cols[^>]*/>'),
            '<w:cols w:num="2" w:space="720" w:equalWidth="0"><w:col w:w="2000" w:space="720"/><w:col w:w="4000"/></w:cols>',
          );
      part.writeText(xml);
      final imported = WordDeserializer().read(package);
      final controller = WordEditorController(document: imported);
      addTearDown(controller.dispose);
      final source = imported.sections.single.sourceProperties;
      final target = controller.capturePageLayout();
      expect(
        controller.applyPageLayout(
          target.settings.copyWith(pageSize: WmlPageSize.letter()),
          target: target,
        ),
        isTrue,
      );
      expect(imported.sections.single.sourceProperties, same(source));
      final saved = WordSerializer()
          .write(imported)
          .getPart('/word/document.xml')!
          .readText();
      final section = XmlDocument.parse(
        saved,
      ).root!.firstChild('body')!.firstChild('sectPr')!;
      expect(section.firstChild('pgNumType')!.getAttribute('start'), '7');
      expect(section.firstChild('docGrid')!.getAttribute('linePitch'), '360');
      expect(section.firstChild('cols')!.getAttribute('equalWidth'), '0');
      expect(section.firstChild('cols')!.childrenNamed('col'), hasLength(2));
      controller.undo();
      expect(imported.sections.single.sourceProperties, same(source));
      expect(controller.pageSize.matches(WmlPageSize.a4()), isTrue);
    },
  );
}
