import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

Iterable<XmlElement> _elements(XmlElement node, String name) sync* {
  if (node.localName == name) yield node;
  for (final child in node.childElements) {
    yield* _elements(child, name);
  }
}

XmlElement _content(WmlDocument document, {String? fixture}) {
  final bytes = OdtDocumentWriter.writeBytes(document);
  final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
  if (fixture != null && output != null && output.isNotEmpty) {
    Directory(output).createSync(recursive: true);
    File('$output/$fixture').writeAsBytesSync(bytes);
  }
  return XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
  ).root!;
}

void main() {
  test(
    'hanging indent overrides first-line indent without duplicate attributes',
    () {
      final root = _content(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(
                  properties: WmlParagraphProps(
                    indent: const WmlIndent(
                      left: 36,
                      firstLine: 12,
                      hanging: 18,
                    ),
                  ),
                  inlines: [WmlRun(text: 'Body')],
                ),
              ],
            ),
          ],
        ),
        fixture: 'word-indents.odt',
      );
      final properties = _elements(root, 'paragraph-properties').single;
      final indents = properties.attributes
          .where((a) => a.localName == 'text-indent' && a.namespaceUri == _foNs)
          .toList();
      expect(indents, hasLength(1));
      expect(indents.single.value, '-18.00pt');
    },
  );

  test('negative hanging indent produces a valid signed length', () {
    final root = _content(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                properties: WmlParagraphProps(
                  indent: const WmlIndent(hanging: -5),
                ),
                inlines: [WmlRun(text: 'Body')],
              ),
            ],
          ),
        ],
      ),
    );
    final properties = _elements(root, 'paragraph-properties').single;
    expect(
      properties.getAttribute('text-indent', namespaceUri: _foNs),
      '5.00pt',
    );
  });

  test('inline visual fallback stays inline and keeps surrounding text', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Before '),
                WmlRun(
                  inlineVisual: WmlVisual(
                    visual: OfficeVisual(
                      kind: OfficeVisualKind.chartColumn,
                      title: ' Chart\tlabel ',
                    ),
                  ),
                ),
                WmlRun(text: 'after'),
              ],
            ),
          ],
        ),
      ],
    );
    final root = _content(document);
    final paragraphs = _elements(
      root,
      'p',
    ).where((e) => e.namespaceUri == _textNs).toList();
    expect(paragraphs, hasLength(1));
    expect(
      OfficeTextExtractor.extract(
        OdtDocumentWriter.writeBytes(document),
        name: 'inline.odt',
      ).paragraphs,
      ['Before  Chart\tlabel after'],
    );
  });

  test('block visual fallback remains a standalone paragraph', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartColumn,
                title: ' Chart\tlabel ',
              ),
            ),
            WmlParagraph(inlines: [WmlRun(text: 'After')]),
          ],
        ),
      ],
    );
    final root = _content(document);
    expect(_elements(root, 'p'), hasLength(2));
    expect(
      OfficeTextExtractor.extract(
        OdtDocumentWriter.writeBytes(document),
        name: 'block.odt',
      ).paragraphs,
      [' Chart\tlabel ', 'After'],
    );
  });
}
