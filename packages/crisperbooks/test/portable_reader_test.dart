import 'dart:convert';

import 'package:crisperbooks/crisperbooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

EpubDocument _book({int chapters = 3}) {
  final book = EpubDocument.create(title: 'Reader fixture');
  for (var index = 2; index <= chapters; index++) {
    book.addChapter(title: 'Chapter $index', text: 'Chapter $index text.');
  }
  return book;
}

EpubDocument _percentPathBook() => EpubDocument.fromPublication({
  'metadata': {'title': 'Literal percent names', 'language': 'en'},
  'readingOrder': [
    {'href': 'chapters/percent%2520dir/one.xhtml', 'title': 'First'},
    {'href': 'chapters/percent%2520dir/two.xhtml', 'title': 'Second'},
  ],
  'resources': [
    for (final name in ['one', 'two'])
      {
        'href': 'chapters/percent%2520dir/$name.xhtml',
        'mediaType': 'application/xhtml+xml',
        'encoding': 'base64',
        'data': base64Encode(
          utf8.encode(
            '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$name</title></head><body><p>$name</p><a href="two.xhtml">Next chapter</a></body></html>',
          ),
        ),
      },
  ],
});

Future<void> _pumpReader(
  WidgetTester tester,
  EpubDocument document, {
  int initialSection = 0,
  ValueChanged<EbookLocation>? onLocationChanged,
  EbookChapterReaderController? controller,
  String? initialLocation,
  EbookAppearance appearance = const EbookAppearance(),
  ValueChanged<EbookAppearance>? onAppearanceChanged,
  ValueChanged<EbookBookInfo>? onReady,
  bool showControls = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EbookChapterReader(
          document: document,
          initialSection: initialSection,
          onLocationChanged: onLocationChanged ?? (_) {},
          controller: controller,
          initialLocation: initialLocation,
          appearance: appearance,
          onAppearanceChanged: onAppearanceChanged,
          onReady: onReady,
          showControls: showControls,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int? _selectedChapter(WidgetTester tester) =>
    tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).value;

String _xhtml(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head><body>$body</body></html>';

EpubDocument _htmlBook(List<String> chapters) {
  final book = _book(chapters: chapters.length);
  for (var index = 0; index < chapters.length; index++) {
    book.updateText(book.chapters[index].path, _xhtml(chapters[index]));
  }
  return book;
}

EbookChapterReaderController _boundController(EpubDocument book) {
  final controller = EbookChapterReaderController();
  controller.attach(
    owner: Object(),
    document: book,
    navigate: (_) async {},
    setAppearance: (_) {},
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('portable locators preserve decoded paths and Unicode fragments', () {
    final book = _percentPathBook();
    final expected = EbookChapterTarget(
      path: book.chapters.last.path,
      fragment: 'Ziel ü%25',
      progress: .25,
    );
    final decoded = EbookChapterTarget.resolve(
      expected.locator,
      book.chapters,
    )!;
    expect(decoded.path, expected.path);
    expect(decoded.fragment, expected.fragment);
    expect(decoded.progress, .25);
    expect(
      EbookChapterTarget.resolve('crisp-section:1', book.chapters)!.path,
      expected.path,
    );
    expect(
      EbookChapterTarget.resolve(
        'two.xhtml#Ziel%20%C3%BC%2525',
        book.chapters,
        basePath: book.chapters.first.path,
      )!.fragment,
      expected.fragment,
    );
    for (final value in [
      'crisp-reader:v1:not-valid!',
      'crisp-section:-1',
      'crisp-section:99',
      'epub://other/chapters/percent%2520dir/two.xhtml',
      'https://example.invalid/book.xhtml',
      '%FF.xhtml',
    ]) {
      expect(EbookChapterTarget.resolve(value, book.chapters), isNull);
    }
  });

  test(
    'whole-book search matches inline text and uses display-only anchors',
    () async {
      final book = _htmlBook([
        '<p>One <strong>Silver</strong> needle.</p><p hidden="hidden">needle hidden</p>',
        '<p>Another SILVER needle and a literal a+b.</p>',
      ]);
      final revision = book.revision;
      final originals = [
        for (final chapter in book.chapters) book.readText(chapter.path),
      ];
      final controller = _boundController(book);
      final hits = await controller.search('silver needle');
      expect(hits, hasLength(2));
      expect(hits.map((hit) => hit.sectionIndex), [0, 1]);
      expect(hits.first.excerpt, contains('Silver needle'));
      final target = EbookChapterTarget.resolve(hits.first.cfi, book.chapters)!;
      expect(target.fragment, startsWith('crisp-reader-block-'));
      final prepared = await controller.prepareChapter(target.path);
      expect(prepared.html, contains('id="${target.fragment}"'));
      expect(await controller.search('a+b'), hasLength(1));
      expect(await controller.search('needle', limit: 1), hasLength(1));
      expect(await controller.search('needle hidden'), isEmpty);
      expect(book.revision, revision);
      expect([
        for (final chapter in book.chapters) book.readText(chapter.path),
      ], originals);
    },
  );

  test('search invalidates changed chapters and can be cancelled', () async {
    final book = _htmlBook(['<p>Old phrase</p>']);
    final controller = _boundController(book);
    expect(await controller.search('old'), hasLength(1));
    book.updateText(book.chapters.single.path, _xhtml('<p>New phrase</p>'));
    expect(await controller.search('old'), isEmpty);
    expect(await controller.search('new'), hasLength(1));
    final pending = controller.search('new');
    controller.clearSearch();
    expect(await pending, isEmpty);
    await expectLater(controller.search('x' * 1001), throwsFormatException);
  });

  test('large chapters remain displayable but are skipped by bounded search', () async {
    final book = _htmlBook([
      '<p>A display-only needle ${'x' * EbookChapterReaderController.maximumSearchChapterBytes}</p>',
      '<p>The searchable needle</p>',
    ]);
    final controller = _boundController(book);
    final prepared = await controller.prepareChapter(book.chapters.first.path);
    expect(prepared.html, contains('A display-only needle'));
    final hits = await controller.search('needle');
    expect(hits, hasLength(1));
    expect(hits.single.sectionIndex, 1);
    expect(controller.searchWarnings, hasLength(1));
    expect(controller.searchWarnings.single, contains('2 MiB'));
  });

  test('portable preparation rejects deeply nested malformed content', () {
    expect(
      () => prepareEbookChapter('${'<div>' * 140}text${'</div>' * 140}'),
      throwsFormatException,
    );
  });

  testWidgets(
    'relative chapter links preserve literal percent directory names',
    (tester) async {
      final book = _percentPathBook();
      final locations = <EbookLocation>[];
      await _pumpReader(tester, book, onLocationChanged: locations.add);
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      expect(
        html.baseUrl.toString(),
        'epub:/chapters/percent%2520dir/one.xhtml',
      );
      expect(await html.onTapUrl!('two.xhtml'), isTrue);
      await tester.pumpAndSettle();
      expect(_selectedChapter(tester), 1);
      expect(locations.last.sectionIndex, 1);
      expect(locations.last.chapterTitle, 'Second');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('malformed and nonlocal links do not break chapter reading', (
    tester,
  ) async {
    final locations = <EbookLocation>[];
    await _pumpReader(
      tester,
      _percentPathBook(),
      onLocationChanged: locations.add,
    );
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    for (final link in [
      '%FF.xhtml',
      'https://example.invalid/two.xhtml',
      'epub://other/chapters/percent%2520dir/two.xhtml',
      'javascript:alert(1)',
    ]) {
      expect(await html.onTapUrl!(link), isFalse, reason: link);
    }
    await tester.pumpAndSettle();
    expect(_selectedChapter(tester), 0);
    expect(locations, hasLength(1));
    expect(locations.single.sectionIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('document replacement resets the selected chapter safely', (
    tester,
  ) async {
    await _pumpReader(tester, _book(), initialSection: 2);
    expect(_selectedChapter(tester), 2);
    await _pumpReader(tester, _book(chapters: 1));
    expect(_selectedChapter(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed chapter rendering does not overwrite a saved location', (
    tester,
  ) async {
    final book = _htmlBook([
      '${'<div>' * 140}Unrenderable chapter${'</div>' * 140}',
      '<p>A readable second chapter.</p>',
    ]);
    final controller = EbookChapterReaderController();
    addTearDown(controller.dispose);
    final locations = <EbookLocation>[];
    final ready = <EbookBookInfo>[];
    await _pumpReader(
      tester,
      book,
      controller: controller,
      initialLocation: EbookChapterTarget(
        path: book.chapters.first.path,
        progress: .75,
      ).locator,
      onLocationChanged: locations.add,
      onReady: ready.add,
    );
    expect(find.textContaining('too complex'), findsOneWidget);
    expect(locations, isEmpty);
    expect(controller.location, isNull);
    expect(ready, isEmpty);

    await controller.next();
    await tester.pumpAndSettle();
    expect(_selectedChapter(tester), 1);
    expect(locations.single.sectionIndex, 1);
    expect(ready, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter removal clamps the current section during rebuilds', (
    tester,
  ) async {
    final book = _book();
    await _pumpReader(tester, book, initialSection: 2);
    book.removeChapter(book.chapters.last.id);
    await _pumpReader(tester, book, initialSection: 2);
    expect(_selectedChapter(tester), 1);

    // A mutable document can also shrink before the reader rebuilds itself.
    book.removeChapter(book.chapters.last.id);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(_selectedChapter(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial position and metadata are immediately available for bookmarks',
    (tester) async {
      final controller = EbookChapterReaderController();
      addTearDown(controller.dispose);
      final locations = <EbookLocation>[];
      final ready = <EbookBookInfo>[];
      await _pumpReader(
        tester,
        _book(),
        controller: controller,
        initialSection: 1,
        onLocationChanged: locations.add,
        onReady: ready.add,
      );
      expect(controller.isReady, isTrue);
      expect(locations, hasLength(1));
      expect(locations.single.sectionIndex, 1);
      expect(locations.single.cfi, startsWith(EbookChapterTarget.prefix));
      expect(controller.location!.cfi, locations.single.cfi);
      expect(ready.single.sectionCount, 3);
      final bookmark = locations.single.cfi;
      await controller.next();
      await tester.pumpAndSettle();
      expect(_selectedChapter(tester), 2);
      await controller.goTo(bookmark);
      await tester.pumpAndSettle();
      expect(_selectedChapter(tester), 1);
    },
  );

  testWidgets(
    'same and cross-chapter Unicode fragments scroll to their target',
    (tester) async {
      final filler = List.generate(
        45,
        (index) => '<p>Paragraph $index before the destination.</p>',
      ).join();
      final book = _htmlBook([
        '$filler<p id="same ü%25">Same chapter destination</p>',
        '$filler<p id="other ü%25">Other chapter destination</p>',
      ]);
      final controller = EbookChapterReaderController();
      addTearDown(controller.dispose);
      await _pumpReader(tester, book, controller: controller);
      final first = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      expect(await first.onTapUrl!('#same%20%C3%BC%2525'), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!
            .offset,
        greaterThan(100),
      );
      expect(
        EbookChapterTarget.resolve(
          controller.location!.cfi,
          book.chapters,
        )!.fragment,
        'same ü%25',
      );
      final target = Uri(
        pathSegments: book.chapters.last.path.split('/'),
        // Uri preserves existing percent escapes in a fragment argument.
        // Encode the literal percent in this element ID before constructing
        // the href, just as the same-chapter link above does.
        fragment: Uri.encodeComponent('other ü%25'),
      ).toString();
      expect(
        EbookChapterTarget.resolve(target, book.chapters)!.fragment,
        'other ü%25',
      );
      await controller.goTo(target);
      await tester.pumpAndSettle();
      expect(_selectedChapter(tester), 1);
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!
            .offset,
        greaterThan(100),
      );
      expect(
        EbookChapterTarget.resolve(
          controller.location!.cfi,
          book.chapters,
        )!.fragment,
        'other ü%25',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a search hit navigates to its generated paragraph anchor', (
    tester,
  ) async {
    final filler = List.generate(
      45,
      (index) => '<p>Paragraph $index before the match.</p>',
    ).join();
    final book = _htmlBook([
      '<p>First chapter</p>',
      '$filler<p>The silver needle is here.</p>',
    ]);
    final controller = EbookChapterReaderController();
    addTearDown(controller.dispose);
    await _pumpReader(tester, book, controller: controller);
    final hits = await tester.runAsync(
      () => controller.search('silver needle'),
    );
    expect(hits, hasLength(1));
    await controller.goTo(hits!.single.cfi);
    await tester.pumpAndSettle();
    expect(_selectedChapter(tester), 1);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .offset,
      greaterThan(100),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appearance callbacks preserve settings and shared controls can replace local ones',
    (tester) async {
      final controller = EbookChapterReaderController();
      addTearDown(controller.dispose);
      final changes = <EbookAppearance>[];
      final book = _book();
      await _pumpReader(
        tester,
        book,
        controller: controller,
        appearance: const EbookAppearance(
          fontSize: 22,
          lineHeight: 1.8,
          theme: 'sepia',
          fontFamily: 'monospace',
        ),
        onAppearanceChanged: changes.add,
      );
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
      expect(changes.single.fontSize, 24);
      expect(changes.single.theme, 'sepia');
      expect(changes.single.lineHeight, 1.8);
      await controller.setAppearance(
        const EbookAppearance(fontSize: 100, theme: 'dark'),
      );
      await tester.pumpAndSettle();
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      expect(html.textStyle!.fontSize, 48);
      expect(html.textStyle!.color, const Color(0xffdce4ec));
      await _pumpReader(
        tester,
        book,
        controller: controller,
        showControls: false,
      );
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
