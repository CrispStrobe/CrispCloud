import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

String _text(XmlNode node) => switch (node) {
  XmlText() => node.text,
  XmlElement() => node.children.map(_text).join(),
  _ => '',
};

Iterable<XmlElement> _elements(
  XmlElement root,
  String name,
  String namespace,
) sync* {
  if (root.localName == name && root.namespaceUri == namespace) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespace);
  }
}

String? _masterFor(XmlElement content, String text) {
  final paragraph = _elements(
    content.firstChild('body')!.firstChild('text')!,
    'p',
    _textNs,
  ).singleWhere((paragraph) => _text(paragraph) == text);
  final name = paragraph.getAttribute('style-name', namespaceUri: _textNs);
  final style = content
      .firstChild('automatic-styles')!
      .childrenNamed('style')
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
  return style.getAttribute('master-page-name', namespaceUri: _styleNs);
}

WmlSection _section(
  String body,
  String variant,
  WmlRun run, {
  WmlSectionBreakKind kind = WmlSectionBreakKind.nextPage,
}) {
  final story = [
    WmlParagraph(inlines: [run]),
  ];
  return WmlSection(
    blocks: [_paragraph(body)],
    breakKind: kind,
    differentFirstPage: variant.startsWith('first'),
    differentOddEven: variant.startsWith('even'),
    firstHeader: variant == 'firstHeader' ? story : [],
    firstFooter: variant == 'firstFooter' ? story : [],
    evenHeader: variant == 'evenHeader' ? story : [],
    evenFooter: variant == 'evenFooter' ? story : [],
  );
}

void main() {
  for (final variant in [
    'firstHeader',
    'firstFooter',
    'evenHeader',
    'evenFooter',
  ]) {
    test('$variant master reuse respects authored comment references', () {
      for (final distinct in [false, true]) {
        final firstRun = WmlRun(text: 'Same visible story', commentIds: [1]);
        final secondId = distinct ? 2 : 1;
        final secondRun = WmlRun(
          text: 'Same visible story',
          commentIds: [secondId],
        );
        final document = WmlDocument(
          sections: [
            _section('First', variant, firstRun),
            _section(
              'Continuous',
              variant,
              secondRun,
              kind: WmlSectionBreakKind.continuous,
            ),
          ],
        );
        document.comments.addAll([
          WmlComment(id: 1, text: 'First review'),
          if (distinct) WmlComment(id: 2, text: 'Second review'),
        ]);
        final package = OpcPackage.openBytes(
          OdtDocumentWriter.writeBytes(document),
        );
        final content = XmlDocument.parse(
          package.getPart('/content.xml')!.readText(),
        ).root!;
        final styles = XmlDocument.parse(
          package.getPart('/styles.xml')!.readText(),
        ).root!;

        // Annotation bodies are stripped from the page-style comparison.
        // Equal authored references should still reuse the master, while a
        // different reference needs its own master despite equal visible text.
        expect(
          _masterFor(content, 'Continuous'),
          distinct ? equals('mp1') : isNull,
          reason: '$variant; distinct authored reference: $distinct',
        );
        expect(
          _elements(styles, 'annotation', _officeNs),
          hasLength(distinct ? 2 : 1),
        );
        expect(firstRun.commentIds, [1]);
        expect(secondRun.commentIds, [secondId]);
      }
    });
  }
}
