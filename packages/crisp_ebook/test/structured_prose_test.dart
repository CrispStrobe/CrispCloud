import 'dart:convert';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'document_test.dart'
    show bytes, fixtureFiles, prefixedVocabulary, zipFiles;

const _chapter = 'Books/Edition/Text/one.xhtml';
const _xhtml = 'http://www.w3.org/1999/xhtml';

EpubDocument _book(String body, {bool prefixed = false, EpubLimits? limits}) {
  final files = fixtureFiles();
  var source =
      '<html xmlns="$_xhtml" xmlns:epub="http://www.idpf.org/2007/ops" '
      'xmlns:custom="urn:custom"><head><title>Prose</title></head><body>$body</body></html>';
  if (prefixed) source = prefixedVocabulary(source, _xhtml, 'x');
  files[_chapter] = bytes(source);
  return EpubDocument.open(
    zipFiles(files),
    limits: limits ?? const EpubLimits(),
  );
}

EpubStructuredProseBlock _block(EpubDocument book, String id) =>
    book.readStructuredProse(_chapter).firstWhere((block) => block.id == id);

int _segment(EpubStructuredProseBlock block, String text) =>
    block.segments.firstWhere((segment) => segment.text == text).index;

Matcher _error(String code) =>
    throwsA(isA<EpubException>().having((error) => error.code, 'code', code));

void main() {
  test(
    'corrects nested formatting and links without changing their XML structure',
    () {
      final book = _book(
        '<p id="p" class="publisher" xml:lang="de" dir="rtl">'
        'Before <em class="voice"><strong id="bold">tyop</strong></em> '
        '<a href="chapter%20two.xhtml#two" id="link" epub:type="noteref" custom:flag="keep">lable</a>'
        '<span style="letter-spacing: .1em" data-extra="keep"> tail</span></p>',
      );
      final block = _block(book, 'p');
      expect(block.editable, isTrue);
      final bold = block.segments.firstWhere(
        (segment) => segment.text == 'tyop',
      );
      expect(
        bold.marks,
        containsAll([EpubProseMark.bold, EpubProseMark.italic]),
      );
      final link = block.segments.firstWhere(
        (segment) => segment.text == 'lable',
      );
      expect(link.href, 'chapter%20two.xhtml#two');
      expect(link.marks, contains(EpubProseMark.link));
      final before = XmlDocument.parse(book.readText(_chapter));
      before.descendants
              .whereType<XmlElement>()
              .firstWhere((e) => e.getAttribute('id') == 'bold')
              .children
              .whereType<XmlText>()
              .single
              .value =
          'typo';
      before.descendants
              .whereType<XmlElement>()
              .firstWhere((e) => e.getAttribute('id') == 'link')
              .children
              .whereType<XmlText>()
              .single
              .value =
          'label';
      book.updateStructuredProseBlock(block, {
        bold.index: 'typo',
        link.index: 'label',
      });
      expect(book.readText(_chapter), before.toXmlString());
      expect(_block(book, 'p').text, 'Before typo label tail');
      final reopened = EpubDocument.open(book.toBytes());
      expect(_block(reopened, 'p').text, 'Before typo label tail');
    },
  );

  test(
    'keeps unknown and embedded subtrees, comments, CDATA and attributed breaks opaque',
    () {
      final book = _book(
        '<p id="p">before <img id="image" src="../Images/cover.png" alt="cover"/>'
        '<svg xmlns="http://www.w3.org/2000/svg"><title>drawing</title><text>SVG</text></svg>'
        '<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>'
        '<ruby>漢<rt>kan</rt></ruby><custom:opaque value="keep"><custom:inner>secret</custom:inner></custom:opaque>'
        '<!--keep comment--><![CDATA[keep <raw>]]><br id="line" class="keep"/>after</p>',
      );
      final block = _block(book, 'p');
      final protected = block.segments
          .where((segment) => !segment.editable)
          .toList();
      expect(protected, hasLength(8));
      expect(protected.last.kind, EpubProseSegmentKind.lineBreak);
      final before = XmlDocument.parse(book.readText(_chapter));
      final paragraph = before.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.getAttribute('id') == 'p',
      );
      paragraph.children.whereType<XmlText>().first.value = 'changed ';
      paragraph.children.whereType<XmlText>().last.value = 'ending';
      book.updateStructuredProseBlock(block, {
        _segment(block, 'before '): 'changed ',
        _segment(block, 'after'): 'ending',
      });
      expect(book.readText(_chapter), before.toXmlString());
      final current = _block(book, 'p');
      final bytesBefore = book.readBytes(_chapter);
      expect(
        () => book.updateStructuredProseBlock(current, {
          protected.first.index: 'replace image',
        }),
        _error('protected_prose'),
      );
      expect(book.readBytes(_chapter), orderedEquals(bytesBefore));
    },
  );

  test('a mixed valid and protected batch has no partial effects', () {
    final book = _book(
      '<p id="p">original<img src="../Images/cover.png" alt="image"/>tail</p>',
    );
    final original = book.toBytes();
    final block = _block(book, 'p');
    expect(
      () =>
          book.updateStructuredProseBlock(block, {0: 'changed', 1: 'flatten'}),
      _error('protected_prose'),
    );
    expect(book.dirty, isFalse);
    expect(book.toBytes(), orderedEquals(original));
    expect(
      () => book.updateStructuredProseBlock(block, {
        0: 'changed',
        999: 'missing',
      }),
      throwsRangeError,
    );
    expect(book.toBytes(), orderedEquals(original));
  });

  test(
    'whole-resource guard rejects markup-only changes and relocated identical paragraphs',
    () {
      final book = _book('<p id="a">same</p><p id="b">same</p>');
      final block = _block(book, 'a');
      book.updateText(
        _chapter,
        book.readText(_chapter).replaceFirst('id="a"', 'id="a" class="new"'),
      );
      expect(
        () => book.updateStructuredProseBlock(block, {0: 'wrong paragraph'}),
        _error('stale_edit'),
      );
      final fresh = _block(book, 'a');
      book.updateText(
        _chapter,
        book
            .readText(_chapter)
            .replaceFirst('<p id="a"', '<p id="inserted">same</p><p id="a"'),
      );
      expect(
        () => book.updateStructuredProseBlock(fresh, {0: 'wrong paragraph'}),
        _error('stale_edit'),
      );
      expect(_block(book, 'a').text, 'same');
      expect(_block(book, 'inserted').text, 'same');
    },
  );

  test('empty and unchanged batches keep original bytes and revision', () {
    final book = _book('<p id="p" class="keep">A &amp; <em>B</em></p>');
    final original = book.toBytes();
    final revision = book.revision;
    final block = _block(book, 'p');
    book.updateStructuredProseBlock(block, {});
    book.updateStructuredProseBlock(block, {
      for (final run in block.segments) run.index: run.text,
    });
    expect(book.revision, revision);
    expect(book.dirty, isFalse);
    expect(book.toBytes(), orderedEquals(original));
  });

  test(
    'empty replacements keep ID-bearing wrappers and Unicode remains intact',
    () {
      final book = _book(
        '<p id="p"><em id="anchor">remove</em><span>old</span></p>',
      );
      final block = _block(book, 'p');
      book.updateStructuredProseBlock(block, {
        0: '',
        1: 'Grüße\u00a0世界 🐦 & < >\nnext',
      });
      final xml = XmlDocument.parse(book.readText(_chapter));
      final anchor = xml.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.getAttribute('id') == 'anchor',
      );
      expect(anchor.name.local, 'em');
      expect(anchor.innerText, '');
      final reopened = EpubDocument.open(book.toBytes());
      expect(_block(reopened, 'p').text, 'Grüße\u00a0世界 🐦 & < >\nnext');
    },
  );

  test(
    'rejects invalid XML characters and lone surrogate code units atomically',
    () {
      final book = _book('<p id="p">first<em>second</em></p>');
      final block = _block(book, 'p');
      final original = book.toBytes();
      for (final invalid in [
        'bad\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        'bad\uffff',
      ]) {
        expect(
          () =>
              book.updateStructuredProseBlock(block, {0: 'valid', 1: invalid}),
          _error('invalid_prose_text'),
        );
        expect(book.toBytes(), orderedEquals(original));
      }
    },
  );

  test('recognizes prefixed XHTML and keeps inherited prefixes', () {
    final book = _book(
      '<p id="p" class="keep">Before <em>word</em><br id="break"/>After</p>',
      prefixed: true,
    );
    final block = _block(book, 'p');
    book.updateStructuredProseBlock(block, {
      _segment(block, 'word'): 'correction',
    });
    expect(book.readText(_chapter), contains('<x:em>correction</x:em>'));
    expect(book.readText(_chapter), contains('<x:br id="break"/>'));
    expect(book.readText(_chapter), contains('<x:p id="p" class="keep">'));
  });

  test('does not expose foreign, unknown or overlapping prose blocks', () {
    final book = _book(
      '<blockquote id="outer"><p id="inner">Inner <em>word</em></p></blockquote>'
      '<custom:opaque><p id="hidden">Protected</p></custom:opaque>'
      '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><p xmlns="$_xhtml" id="foreign">Protected</p></foreignObject></svg>'
      '<p id="after">After</p>',
    );
    final blocks = book.readStructuredProse(_chapter);
    expect(blocks.map((block) => block.id), ['inner', 'after']);
    final inner = blocks.first;
    book.updateStructuredProseBlock(inner, {0: 'Changed '});
    expect(
      book.readText(_chapter),
      contains(
        '<blockquote id="outer"><p id="inner">Changed <em>word</em></p></blockquote>',
      ),
    );
    expect(book.readText(_chapter), contains('id="hidden">Protected'));
    expect(book.readText(_chapter), contains('id="foreign">Protected'));
  });

  test('fixed-layout books and non-XHTML resources remain source-only', () {
    final book = _book('<p id="p">Text</p>');
    final block = _block(book, 'p');
    expect(
      () => book.readStructuredProse(book.packagePath),
      _error('prose_resource'),
    );
    book.updateText(
      book.packagePath,
      book
          .readText(book.packagePath)
          .replaceFirst(
            '</metadata>',
            '<meta property="rendition:layout">pre-paginated</meta></metadata>',
          ),
    );
    expect(book.fixedLayout, isTrue);
    expect(() => book.readStructuredProse(_chapter), _error('fixed_layout'));
    expect(
      () => book.updateStructuredProseBlock(block, {0: 'Changed'}),
      _error('fixed_layout'),
    );
  });

  test(
    'serialized size and segment-count limits do not publish partial edits',
    () {
      final book = _book(
        '<p id="p">first<em>second</em></p>',
        limits: const EpubLimits(maxTextBytes: 2048),
      );
      final block = _block(book, 'p');
      final original = book.toBytes();
      expect(
        () =>
            book.updateStructuredProseBlock(block, {0: 'valid', 1: 'x' * 2049}),
        _error('text_limit'),
      );
      expect(book.toBytes(), orderedEquals(original));
      expect(
        () => book.updateStructuredProseBlock(block, {
          0: '&' * 700,
          1: '<' * 700,
        }),
        _error('text_limit'),
      );
      expect(book.toBytes(), orderedEquals(original));
      final fragmented = _book('<p id="p">${'<span>word</span>' * 1025}</p>');
      expect(
        () => fragmented.readStructuredProse(_chapter),
        _error('prose_limit'),
      );
      expect(fragmented.dirty, isFalse);
    },
  );

  test('save and reopen preserve all unaffected archive resource bytes', () {
    final book = _book('<p id="p">Before <em>tyop</em> after</p>');
    final originals = {
      for (final resource in book.resources)
        resource.path: book.readBytes(resource.path),
    };
    final block = _block(book, 'p');
    book.updateStructuredProseBlock(block, {_segment(block, 'tyop'): 'typo'});
    final reopened = EpubDocument.open(book.toBytes());
    expect(reopened.validate().where((issue) => issue.isError), isEmpty);
    for (final entry in originals.entries) {
      if (entry.key == _chapter || entry.key == book.packagePath) continue;
      expect(
        reopened.readBytes(entry.key),
        orderedEquals(entry.value),
        reason: entry.key,
      );
    }
    expect(
      utf8.decode(reopened.readBytes(_chapter)),
      contains('<em>typo</em>'),
    );
  });
}
