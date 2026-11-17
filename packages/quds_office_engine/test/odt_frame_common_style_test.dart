import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

XmlElement _automaticFrameStyle(XmlElement root, XmlElement frame) {
  final name = frame.getAttribute('style-name', namespaceUri: _drawNs);
  return root
      .firstChild('automatic-styles')!
      .childrenNamed('style')
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

XmlElement _commonFrameParent(XmlElement styles, XmlElement automatic) {
  final parent = automatic.getAttribute(
    'parent-style-name',
    namespaceUri: _styleNs,
  );
  expect(parent, isNotNull);
  final common = styles
      .firstChild('styles')!
      .childrenNamed('style')
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == parent,
      );
  expect(common.getAttribute('family', namespaceUri: _styleNs), 'graphic');
  return common;
}

void main() {
  test('leading and later text frames share one common graphic parent', () {
    WmlFrame frame(String mark, double y) => WmlFrame(
      x: 36,
      y: y,
      width: 210,
      height: 35,
      blocks: [
        WmlParagraph(
          inlines: [
            WmlBookmarkBoundary(id: '1', isStart: true, name: mark),
            WmlRun(text: mark),
            WmlBookmarkBoundary(id: '1', isStart: false),
          ],
        ),
      ],
    );

    final leading = frame('LeadingFrame', 90);
    final later = frame('LaterFrame', 190);
    final output = _export(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              leading,
              _paragraph('Between'),
              later,
              _paragraph('After'),
            ],
          ),
        ],
      ),
    );
    final frames = _elements(output.content, 'frame').toList();
    expect(frames, hasLength(2));
    final names = frames
        .map((frame) => frame.getAttribute('style-name', namespaceUri: _drawNs))
        .toSet();
    expect(names, hasLength(1));
    expect(names.single, isNotNull);
    final automatic = _automaticFrameStyle(output.content, frames.first);
    final common = _commonFrameParent(output.styles, automatic);
    expect(
      _commonFrameParent(
        output.styles,
        _automaticFrameStyle(output.content, frames.last),
      ),
      same(common),
    );
    final properties = automatic.firstChild('graphic-properties')!;
    expect(
      properties.getAttribute('horizontal-rel', namespaceUri: _styleNs),
      'page',
    );
    expect(
      properties.getAttribute('vertical-rel', namespaceUri: _styleNs),
      'page',
    );
    expect(
      properties.getAttribute('horizontal-pos', namespaceUri: _styleNs),
      'from-left',
    );
    expect(
      properties.getAttribute('vertical-pos', namespaceUri: _styleNs),
      'from-top',
    );
    for (final root in [output.content, output.styles]) {
      expect(
        root
            .firstChild('automatic-styles')!
            .childrenNamed('style')
            .where(
              (style) =>
                  style.getAttribute('name', namespaceUri: _styleNs) ==
                  common.getAttribute('name', namespaceUri: _styleNs),
            ),
        isEmpty,
      );
    }
    for (final (index, mark) in ['LeadingFrame', 'LaterFrame'].indexed) {
      final frame = frames[index];
      expect(
        frame.getAttribute('anchor-type', namespaceUri: _textNs),
        'paragraph',
      );
      expect(
        _elements(frame, 'bookmark-start').single.getAttribute('name'),
        mark,
      );
      expect(
        _elements(frame, 'bookmark-end').single.getAttribute('name'),
        mark,
      );
    }
    expect(leading.y, 90);
    expect(later.y, 190);
    expect(later.width, 210);
    expect(later.height, 35);
  });

  test('documents without text frames do not add an unused graphic style', () {
    final output = _export(
      WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Plain body')]),
        ],
      ),
    );
    expect(
      _elements(output.styles, 'style').where(
        (style) =>
            style.getAttribute('family', namespaceUri: _styleNs) == 'graphic',
      ),
      isEmpty,
    );
  });
}
