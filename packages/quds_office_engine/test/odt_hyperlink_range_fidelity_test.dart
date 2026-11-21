import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _xlinkNs = 'http://www.w3.org/1999/xlink';
const _url = 'https://www.zotero.org/';
const _first =
    'ITEM CSL_CITATION {"citationID":"first","title":"Übertragung العربية 😀 first"}';
const _second =
    'ITEM CSL_CITATION {"citationID":"second","title":"Übertragung العربية 😀 second"}';

WmlRun _link(String text, {String url = _url, bool italic = false}) => WmlRun(
  text: text,
  hyperlink: WmlHyperlink(url: url),
  properties: WmlRunProps(italic: italic),
);

XmlElement _body(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  return XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!.firstChild('body')!.firstChild('text')!;
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.namespaceUri == _textNs && root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

WmlDocument _document(List<WmlInline> inlines) => WmlDocument(
  sections: [
    WmlSection(blocks: [WmlParagraph(inlines: inlines)]),
  ],
);

void main() {
  test('adjacent equal targets retain complete script-rich carrier ranges', () {
    final first = _link(_first);
    final second = _link(_second, italic: true);
    final document = _document([first, second]);
    final root = _body(document);
    final link = _elements(root, 'a').single;
    expect(link.getAttribute('href', namespaceUri: _xlinkNs), _url);
    expect(link.text, '$_first$_second');
    final spans = link.childrenNamed('span', namespaceUri: _textNs).toList();
    expect(spans.map((span) => span.text), [_first, _second]);
    expect(
      spans[0].getAttribute('style-name'),
      isNot(spans[1].getAttribute('style-name')),
    );
    expect(document.paragraphs.single.inlines, [same(first), same(second)]);
    expect(first.text, _first);
    expect(second.properties.italic, isTrue);
  });

  test(
    'different URLs and authored plain text retain separate link ranges',
    () {
      final root = _body(
        _document([
          _link('one'),
          _link('two', url: 'https://www.zotero.org/google-docs/?ABC123'),
          _link('three', url: 'https://www.zotero.org/google-docs/?XYZ789'),
          WmlRun(text: ' prose '),
          _link('four'),
          _link('five'),
        ]),
      );
      final links = _elements(root, 'a').toList();
      expect(links.map((link) => link.text), [
        'one',
        'two',
        'three',
        'fourfive',
      ]);
      expect(
        links[1].getAttribute('href', namespaceUri: _xlinkNs),
        'https://www.zotero.org/google-docs/?ABC123',
      );
      expect(
        links[2].getAttribute('href', namespaceUri: _xlinkNs),
        'https://www.zotero.org/google-docs/?XYZ789',
      );
      expect(root.text, contains('prose'));
    },
  );

  test('bookmark and line break boundaries stay outside grouped links', () {
    final root = _body(
      _document([
        _link('before'),
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'AuthoredBookmark'),
        _link('inside'),
        WmlBookmarkBoundary(id: '1', isStart: false),
        _link('after'),
        WmlBreak(WmlBreakType.textWrapping),
        _link('next'),
      ]),
    );
    expect(_elements(root, 'a').map((link) => link.text), [
      'before',
      'inside',
      'after',
      'next',
    ]);
    final paragraph = _elements(root, 'p').single;
    expect(paragraph.childElements.map((element) => element.localName), [
      'a',
      'bookmark-start',
      'a',
      'bookmark-end',
      'a',
      'line-break',
      'a',
    ]);
  });

  test(
    'notes and comments never become children of an adjacent link range',
    () {
      final annotated = _link('annotated')..commentIds.add(1);
      final document = _document([
        _link('before'),
        annotated,
        _link('after comment'),
        WmlRun(noteRefId: 1),
        _link('after note'),
      ]);
      document.comments.add(
        WmlComment(
          id: 1,
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'Review')]),
          ],
        ),
      );
      document.footnotes.add(
        WmlNote(
          id: 1,
          endnote: false,
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Note body')]),
          ],
        ),
      );
      final root = _body(document);
      final links = _elements(root, 'a').toList();
      expect(links.map((link) => link.text), [
        'before',
        'annotated',
        'after comment',
        'after note',
      ]);
      for (final link in links) {
        expect(
          link.childElements.every((child) => child.localName == 'span'),
          isTrue,
        );
        expect(_elements(link, 'note'), isEmpty);
        expect(link.text, isNot(contains('Review')));
      }
      expect(_elements(root, 'note').single.text, contains('Note body'));
      expect(root.text, contains('Review'));
    },
  );

  test('paragraph and column boundaries close each hyperlink range', () {
    final document = _document([
      _link('first'),
      WmlBreak(WmlBreakType.column),
      _link('second'),
      _link('third'),
    ]);
    document.sections.single.blocks.add(WmlParagraph(inlines: [_link('last')]));
    final root = _body(document);
    final paragraphs = _elements(root, 'p').toList();
    expect(paragraphs, hasLength(3));
    expect(paragraphs.map((p) => _elements(p, 'a').single.text), [
      'first',
      'secondthird',
      'last',
    ]);
  });
}
