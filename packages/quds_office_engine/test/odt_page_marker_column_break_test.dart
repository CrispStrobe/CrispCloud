import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

void main() {
  test('an empty bookmarked PAGE field precedes its trailing column break', () {
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
      inlines: [
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'EmptyPage'),
        WmlBookmarkBoundary(id: '1', isStart: false),
        WmlBreak(WmlBreakType.column),
      ],
    );
    final original = List<WmlInline>.of(paragraph.inlines);
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(
        WmlDocument(
          sections: [
            WmlSection(columnCount: 2, blocks: [paragraph]),
          ],
        ),
      ),
    );
    final content = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    final body = content
        .firstChild('body')!
        .firstChild('text')!
        .firstChild('section')!;
    final paragraphs = body.childrenNamed('p', namespaceUri: _textNs).toList();
    expect(paragraphs, hasLength(2));
    expect(paragraphs.first.childElements.map((element) => element.localName), [
      'bookmark-start',
      'page-number',
      'bookmark-end',
    ]);
    expect(paragraphs.last.childElements, isEmpty);
    String? breakBefore(XmlElement owner) {
      final name = owner.getAttribute('style-name', namespaceUri: _textNs);
      return content
          .firstChild('automatic-styles')!
          .childrenNamed('style', namespaceUri: _styleNs)
          .singleWhere(
            (style) =>
                style.getAttribute('name', namespaceUri: _styleNs) == name,
          )
          .firstChild('paragraph-properties')!
          .getAttribute('break-before', namespaceUri: _foNs);
    }

    expect(breakBefore(paragraphs.first), isNull);
    expect(breakBefore(paragraphs.last), 'column');
    expect(paragraph.inlines, orderedEquals(original));
    expect(paragraph.properties.columnBreakBefore, isFalse);
  });

  for (final pageField in [false, true]) {
    test(
      pageField
          ? 'a runless bookmarked PAGE stays after a leading column break'
          : 'a first-section leading column break retains its empty source fragment',
      () {
        final paragraph = WmlParagraph(
          properties: WmlParagraphProps(pageNumberField: pageField),
          inlines: [
            if (pageField)
              WmlBookmarkBoundary(id: '13', isStart: true, name: 'RunlessPage'),
            WmlBreak(WmlBreakType.column),
            if (pageField)
              WmlBookmarkBoundary(id: '13', isStart: false, name: 'RunlessPage')
            else
              WmlRun(text: 'AfterLeading'),
          ],
        );
        final properties = paragraph.properties;
        final original = List<WmlInline>.of(paragraph.inlines);
        final document = WmlDocument(
          sections: [
            WmlSection(
              columnCount: 2,
              columnSpace: 24,
              blocks: [
                paragraph,
                WmlParagraph(inlines: [WmlRun(text: 'First follower')]),
                WmlParagraph(inlines: [WmlRun(text: 'Second follower')]),
              ],
            ),
          ],
        );
        final package = OpcPackage.openBytes(
          OdtDocumentWriter.writeBytes(document),
        );
        final content = XmlDocument.parse(
          package.getPart('/content.xml')!.readText(),
        ).root!;
        final body = content
            .firstChild('body')!
            .firstChild('text')!
            .firstChild('section')!;
        final paragraphs = body
            .childrenNamed('p', namespaceUri: _textNs)
            .toList();
        // An empty prefix gives the authored break a real source column.
        // The two followers cannot rely on natural end-of-section balancing
        // to imitate the explicit break that precedes the first visible text.
        expect(paragraphs, hasLength(4));
        expect(paragraphs.first.text, isEmpty);
        expect(
          paragraphs.first.childElements.map((element) => element.localName),
          pageField ? ['bookmark-start'] : <String>[],
        );
        expect(
          paragraphs[1].childElements.map((element) => element.localName),
          pageField ? ['page-number', 'bookmark-end'] : ['span'],
        );
        expect(paragraphs[1].text, pageField ? '' : 'AfterLeading');
        expect(paragraphs.skip(2).map((p) => p.text), [
          'First follower',
          'Second follower',
        ]);
        String? breakBefore(XmlElement owner) {
          final name = owner.getAttribute('style-name', namespaceUri: _textNs);
          return content
              .firstChild('automatic-styles')!
              .childrenNamed('style', namespaceUri: _styleNs)
              .singleWhere(
                (style) =>
                    style.getAttribute('name', namespaceUri: _styleNs) == name,
              )
              .firstChild('paragraph-properties')!
              .getAttribute('break-before', namespaceUri: _foNs);
        }

        expect(paragraphs.map(breakBefore), [null, 'column', null, null]);
        expect(
          paragraphs.expand(
            (p) => p.childrenNamed('page-number', namespaceUri: _textNs),
          ),
          hasLength(pageField ? 1 : 0),
        );
        if (pageField) {
          expect(
            paragraphs.first.childElements.single.getAttribute(
              'name',
              namespaceUri: _textNs,
            ),
            'RunlessPage',
          );
          expect(
            paragraphs[1].childElements.last.getAttribute(
              'name',
              namespaceUri: _textNs,
            ),
            'RunlessPage',
          );
        }
        expect(identical(paragraph.properties, properties), isTrue);
        expect(paragraph.inlines, orderedEquals(original));
        expect(paragraph.properties.columnBreakBefore, isFalse);
        expect(paragraph.properties.pageNumberField, pageField);
      },
    );
  }

  for (final kind in WmlSectionBreakKind.values) {
    for (final explicitPage in [false, true]) {
      test('a leading column break remains separate from a later ${kind.name} '
          'section boundary with pageBreakBefore=$explicitPage', () {
        final paragraph = WmlParagraph(
          properties: WmlParagraphProps(pageBreakBefore: explicitPage),
          inlines: [
            WmlBookmarkBoundary(id: '17', isStart: true, name: 'LaterSection'),
            WmlBreak(WmlBreakType.column),
            WmlRun(text: 'After later section column break'),
            WmlBookmarkBoundary(id: '17', isStart: false),
          ],
        );
        final original = List<WmlInline>.of(paragraph.inlines);
        final package = OpcPackage.openBytes(
          OdtDocumentWriter.writeBytes(
            WmlDocument(
              sections: [
                WmlSection(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: 'Previous section')]),
                  ],
                ),
                WmlSection(
                  breakKind: kind,
                  columnCount: 2,
                  blocks: [paragraph],
                ),
              ],
            ),
          ),
        );
        final content = XmlDocument.parse(
          package.getPart('/content.xml')!.readText(),
        ).root!;
        final section = content
            .firstChild('body')!
            .firstChild('text')!
            .childrenNamed('section', namespaceUri: _textNs)
            .single;
        final paragraphs = section
            .childrenNamed('p', namespaceUri: _textNs)
            .toList();
        expect(paragraphs, hasLength(2));
        expect(paragraphs.first.text, isEmpty);
        expect(paragraphs.last.text, 'After later section column break');
        expect(paragraphs.first.childElements.map((node) => node.localName), [
          'bookmark-start',
        ]);
        expect(paragraphs.last.childElements.map((node) => node.localName), [
          'span',
          'bookmark-end',
        ]);
        String? breakBefore(XmlElement owner) {
          final name = owner.getAttribute('style-name', namespaceUri: _textNs);
          return content
              .firstChild('automatic-styles')!
              .childrenNamed('style', namespaceUri: _styleNs)
              .singleWhere(
                (style) =>
                    style.getAttribute('name', namespaceUri: _styleNs) == name,
              )
              .firstChild('paragraph-properties')!
              .getAttribute('break-before', namespaceUri: _foNs);
        }

        expect(
          breakBefore(paragraphs.first),
          kind == WmlSectionBreakKind.continuous && !explicitPage
              ? isNull
              : 'page',
        );
        expect(breakBefore(paragraphs.last), 'column');
        expect(paragraph.inlines, orderedEquals(original));
        expect(paragraph.properties.columnBreakBefore, isFalse);
        expect(paragraph.properties.pageBreakBefore, explicitPage);
      });
    }
  }

  test(
    'an explicit paragraph page break keeps precedence over its leading column break',
    () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(pageBreakBefore: true),
        inlines: [
          WmlBreak(WmlBreakType.column),
          WmlRun(text: 'After page and column'),
        ],
      );
      final originalInlines = List<WmlInline>.of(paragraph.inlines);
      final originalProperties = paragraph.properties;
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(
          WmlDocument(
            sections: [
              WmlSection(
                columnCount: 2,
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: 'Before page break')]),
                  paragraph,
                ],
              ),
            ],
          ),
        ),
      );
      final content = XmlDocument.parse(
        package.getPart('/content.xml')!.readText(),
      ).root!;
      final paragraphs = content
          .firstChild('body')!
          .firstChild('text')!
          .firstChild('section')!
          .childrenNamed('p', namespaceUri: _textNs)
          .toList();
      expect(paragraphs, hasLength(2));
      expect(paragraphs.map((node) => node.text), [
        'Before page break',
        'After page and column',
      ]);
      String? breakBefore(XmlElement owner) {
        final name = owner.getAttribute('style-name', namespaceUri: _textNs);
        return content
            .firstChild('automatic-styles')!
            .childrenNamed('style', namespaceUri: _styleNs)
            .singleWhere(
              (style) =>
                  style.getAttribute('name', namespaceUri: _styleNs) == name,
            )
            .firstChild('paragraph-properties')!
            .getAttribute('break-before', namespaceUri: _foNs);
      }

      expect(paragraphs.map(breakBefore), [null, 'page']);
      expect(paragraph.inlines, orderedEquals(originalInlines));
      expect(paragraph.properties, same(originalProperties));
      expect(paragraph.properties.pageBreakBefore, isTrue);
      expect(paragraph.properties.columnBreakBefore, isFalse);
    },
  );
}
