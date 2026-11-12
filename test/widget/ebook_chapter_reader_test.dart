import 'dart:convert';

import 'package:crisp_cloud/widgets/ebook_chapter_reader.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EbookChapterReader(
          document: document,
          initialSection: initialSection,
          onLocationChanged: onLocationChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int? _selectedChapter(WidgetTester tester) =>
    tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).value;

void main() {
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
      expect(locations.single.sectionIndex, 1);
      expect(locations.single.chapterTitle, 'Second');
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
    expect(locations, isEmpty);
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
}
