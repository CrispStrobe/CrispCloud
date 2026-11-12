import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/fictionbook_fixture.dart';

const namespace = 'http://www.gribuser.ru/xml/fictionbook/2.0';
const xlink = 'http://www.w3.org/1999/xlink';
final options = FictionBookExportOptions(createdAt: DateTime.utc(2026, 11, 12));

Iterable<XmlElement> elements(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == name);

Matcher errorCode(String code) => throwsA(
  isA<EpubException>().having((exception) => exception.code, 'code', code),
);

void main() {
  test(
    'exports metadata, formatted content, sections, tables, notes and image bytes',
    () {
      final book = fictionBookFixture();
      final original = book.toBytes();
      final revision = book.revision;
      final dirty = book.dirty;
      final result = book.exportFictionBook(options: options);
      expect(result.extension, 'fb2');
      expect(result.mediaType, 'application/x-fictionbook+xml');
      final output = XmlDocument.parse(utf8.decode(result.bytes));
      expect(output.rootElement.namespaceUri, namespace);
      expect(elements(output, 'book-title').single.innerText, book.title);
      final titleInfo = elements(output, 'title-info').single;
      expect(
        elements(titleInfo, 'nickname').map((element) => element.innerText),
        book.authors,
      );
      expect(elements(titleInfo, 'lang').single.innerText, 'en');
      expect(
        elements(output, 'strong').map((element) => element.innerText),
        contains('bold & exact'),
      );
      expect(
        elements(output, 'emphasis').map((element) => element.innerText),
        containsAll(['italic', 'before', 'after']),
      );
      expect(elements(output, 'strikethrough').single.innerText, 'old');
      expect(elements(output, 'table').single.findAllElements('tr').length, 2);
      expect(elements(output, 'td').single.getAttribute('colspan'), '2');
      final bodies = output.rootElement.findElements('body').toList();
      expect(bodies.length, 2);
      expect(bodies.last.getAttribute('name'), 'notes');
      expect(bodies.last.innerText, contains('Footnote body'));
      expect(bodies.first.innerText, isNot(contains('Footnote body')));
      expect(
        bodies.first.innerText.indexOf('Inside a nested section.'),
        lessThan(
          bodies.first.innerText.indexOf('Text after the nested section'),
        ),
      );
      expect(bodies.first.innerText, contains('3. Third item'));
      expect(bodies.first.innerText, contains('4. Fourth item'));
      final binary = elements(output, 'binary').single;
      expect(
        base64Decode(binary.innerText),
        orderedEquals(fictionBookFixtureImage),
      );
      final cover = elements(titleInfo, 'image').single;
      expect(
        cover.getAttribute('href', namespace: xlink),
        '#${binary.getAttribute('id')}',
      );
      final ids = output.descendants
          .whereType<XmlElement>()
          .map((element) => element.getAttribute('id'))
          .whereType<String>()
          .toList();
      expect(ids.toSet().length, ids.length);
      for (final link in elements(output, 'a')) {
        final href = link.getAttribute('href', namespace: xlink)!;
        if (href.startsWith('#')) expect(ids, contains(href.substring(1)));
      }
      final note = elements(
        output,
        'a',
      ).singleWhere((element) => element.getAttribute('type') == 'note');
      final target = note.getAttribute('href', namespace: xlink)!.substring(1);
      expect(
        bodies.last.descendants.whereType<XmlElement>().any(
          (element) => element.getAttribute('id') == target,
        ),
        isTrue,
      );
      expect(
        result.warnings.map((issue) => issue.code),
        containsAll([
          'fb2_contents',
          'fb2_presentation',
          'fb2_lists',
          'fb2_line_breaks',
        ]),
      );
      expect(book.toBytes(), orderedEquals(original));
      expect(book.revision, revision);
      expect(book.dirty, dirty);
    },
  );

  test('FBZ is a single safe member containing the same FB2 bytes', () {
    final book = fictionBookFixture();
    final plain = book.exportFictionBook(options: options);
    final zipped = book.exportFictionBook(zipped: true, options: options);
    final archive = ZipDecoder().decodeBytes(zipped.bytes, verify: true);
    expect(zipped.extension, 'fbz');
    expect(zipped.mediaType, 'application/zip');
    expect(archive.files.map((file) => file.name), ['book.fb2']);
    expect(archive.files.single.content, orderedEquals(plain.bytes));
  });

  test(
    'handles unknown authors and namespaced XHTML without guessing personal name parts',
    () {
      final book = EpubDocument.create(title: 'Nameless book');
      final chapter = book.chapters.single;
      book.updateText(
        chapter.path,
        '''<h:html xmlns:h="http://www.w3.org/1999/xhtml">
<h:head><h:title>Title</h:title></h:head><h:body><h:p xml:lang="ar">مرحبا <h:em>بك</h:em></h:p></h:body></h:html>''',
      );
      final result = book.exportFictionBook(options: options);
      final output = XmlDocument.parse(utf8.decode(result.bytes));
      expect(
        elements(
          elements(output, 'title-info').single,
          'nickname',
        ).single.innerText,
        'Unknown',
      );
      expect(elements(output, 'emphasis').single.innerText, 'بك');
      expect(
        elements(output, 'p')
            .singleWhere((p) => p.innerText.startsWith('مرحبا'))
            .getAttribute(
              'lang',
              namespace: 'http://www.w3.org/XML/1998/namespace',
            ),
        'ar',
      );
    },
  );

  test(
    'inline anchor references move to a real containing block with a warning',
    () {
      final book = EpubDocument.create();
      book.updateText(
        book.chapters.single.path,
        fictionBookXhtml(
          '<p>Some <span id="inline">inline target</span></p><p><a href="#inline">Go</a></p>',
        ),
      );
      final result = book.exportFictionBook(options: options);
      final output = XmlDocument.parse(utf8.decode(result.bytes));
      final href = elements(
        output,
        'a',
      ).single.getAttribute('href', namespace: xlink)!;
      final target = elements(
        output,
        'p',
      ).singleWhere((p) => p.getAttribute('id') == href.substring(1));
      expect(target.innerText, 'Some inline target');
      expect(
        result.warnings.any((warning) => warning.code == 'fb2_inline_anchor'),
        isTrue,
      );
    },
  );

  test('heading hierarchy remains nested and every exported link resolves', () {
    final book = EpubDocument.create();
    book.updateText(
      book.chapters.single.path,
      fictionBookXhtml(
        '<h1>Chapter 1</h1><p>Opening</p><h2 id="part">Part</h2><p>Inside</p>'
        '<h3>Deeper</h3><p>More</p><h2>Next part</h2><p><a href="#part">Back</a></p>',
      ),
    );
    final output = XmlDocument.parse(
      utf8.decode(book.exportFictionBook(options: options).bytes),
    );
    final deeper = elements(
      output,
      'title',
    ).singleWhere((title) => title.innerText == 'Deeper');
    final ancestorTitles = deeper.ancestors
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'section')
        .map((section) => section.findElements('title').firstOrNull?.innerText);
    expect(ancestorTitles, containsAll(['Part', 'Chapter 1']));
  });

  for (final entry in {
    'svg':
        '<svg xmlns="http://www.w3.org/2000/svg"><text>Vector text</text></svg>',
    'math':
        '<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>',
    'media': '<audio><p>Audio fallback</p></audio>',
    'ruby': '<ruby>漢<rt>かん</rt></ruby>',
    'script': '<script>window.x = 1;</script>',
  }.entries) {
    test('refuses unsupported ${entry.key} instead of dropping content', () {
      final book = EpubDocument.create();
      book.updateText(book.chapters.single.path, fictionBookXhtml(entry.value));
      expect(
        () => book.exportFictionBook(),
        errorCode('fb2_unsupported_content'),
      );
    });
  }

  test('refuses fixed layout', () {
    final book = EpubDocument.create();
    book.updateText(
      book.packagePath,
      book
          .readText(book.packagePath)
          .replaceFirst(
            '</metadata>',
            '<meta property="rendition:layout">pre-paginated</meta></metadata>',
          ),
    );
    expect(() => book.exportFictionBook(), errorCode('fb2_fixed_layout'));
  });

  test('refuses remote image, dangerous links, and active attributes', () {
    final book = EpubDocument.create();
    book.updateText(
      book.chapters.single.path,
      fictionBookXhtml('<p><img src="https://example.org/image.png"/></p>'),
    );
    expect(() => book.exportFictionBook(), errorCode('fb2_external_image'));
    book.updateText(
      book.chapters.single.path,
      fictionBookXhtml('<p><a href="javascript:evil()">Unsafe</a></p>'),
    );
    expect(() => book.exportFictionBook(), errorCode('fb2_link_scheme'));
    book.updateText(
      book.chapters.single.path,
      fictionBookXhtml('<p onclick="evil()">Unsafe</p>'),
    );
    expect(() => book.exportFictionBook(), errorCode('fb2_active_content'));
  });

  test('refuses a link to content outside the reading order', () {
    final book = EpubDocument.create();
    final other = book.addChapter(
      title: 'Removed',
      text: 'Retained EPUB resource',
    );
    book.removeChapter(other.id);
    book.updateText(
      book.chapters.single.path,
      fictionBookXhtml(
        '<p><a href="chapter.xhtml">Missing from reading order</a></p>',
      ),
    );
    expect(() => book.exportFictionBook(), errorCode('fb2_unresolved_link'));
  });

  test(
    'refuses unsupported images, bad image signatures and bounded output',
    () {
      final book = EpubDocument.create();
      book.replaceCover(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
        mediaType: 'image/svg+xml',
      );
      expect(() => book.exportFictionBook(), errorCode('fb2_image_format'));
      book.replaceCover(utf8.encode('not a PNG'), mediaType: 'image/png');
      expect(() => book.exportFictionBook(), errorCode('fb2_image_signature'));
      expect(
        () => fictionBookFixture().exportFictionBook(
          options: const FictionBookExportOptions(maxOutputBytes: 512),
        ),
        errorCode('fb2_output_limit'),
      );
      expect(
        () => book.exportFictionBook(
          options: const FictionBookExportOptions(maxImages: 0),
        ),
        errorCode('fb2_limits'),
      );
    },
  );
}
