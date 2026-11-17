import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

void main() {
  for (final shading in [false, true]) {
    test(
      'paragraph ${shading ? 'shading' : 'border'} colors stay independent',
      () {
        const colors = <String?>['FF0000', '00ff00', 'ff0000', null, ''];
        final properties = [
          for (final color in colors)
            WmlParagraphProps(
              shadingFill: shading ? color : null,
              borderColor: shading ? null : color,
            ),
        ];
        final document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Leading paragraph')]),
                for (var index = 0; index < properties.length; index++)
                  WmlParagraph(
                    properties: properties[index],
                    inlines: [WmlRun(text: 'Paragraph $index')],
                  ),
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
        final automaticStyles = content.firstChild(
          'automatic-styles',
          namespaceUri: _officeNs,
        )!;
        final allParagraphs = content
            .firstChild('body', namespaceUri: _officeNs)!
            .firstChild('text', namespaceUri: _officeNs)!
            .childrenNamed('p', namespaceUri: _textNs)
            .toList();
        expect(allParagraphs, hasLength(colors.length + 1));
        expect(allParagraphs.first.text, 'Leading paragraph');
        final paragraphs = allParagraphs.skip(1).toList();
        final styleNames = [
          for (final paragraph in paragraphs)
            paragraph.getAttribute('style-name', namespaceUri: _textNs),
        ];
        expect(paragraphs, hasLength(colors.length));
        for (var index = 0; index < colors.length; index++) {
          final style = automaticStyles
              .childrenNamed('style', namespaceUri: _styleNs)
              .singleWhere(
                (style) =>
                    style.getAttribute('name', namespaceUri: _styleNs) ==
                    styleNames[index],
              );
          final emitted = style.firstChild(
            'paragraph-properties',
            namespaceUri: _styleNs,
          )!;
          final color = colors[index]?.toLowerCase() ?? '';
          expect(
            emitted.getAttribute(
              shading ? 'background-color' : 'border',
              namespaceUri: _foNs,
            ),
            color.isEmpty ? null : '${shading ? '' : '0.5pt solid '}#$color',
          );
          expect(
            emitted.getAttribute(
              shading ? 'border' : 'background-color',
              namespaceUri: _foNs,
            ),
            isNull,
          );
          expect(paragraphs[index].text, 'Paragraph $index');
        }
        expect(styleNames[0], isNot(styleNames[1]));
        expect(styleNames[0], styleNames[2]);
        expect(styleNames[3], styleNames[4]);
        expect(
          properties.map(
            (props) => shading ? props.shadingFill : props.borderColor,
          ),
          colors,
        );
      },
    );
  }
}
