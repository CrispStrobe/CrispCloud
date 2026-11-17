import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _paragraph(String text, [WmlParagraphProps? properties]) =>
    WmlParagraph(
      properties: properties,
      inlines: [WmlRun(text: text)],
    );

XmlElement _export(List<WmlSection> sections) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(WmlDocument(sections: sections)),
  );
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

XmlElement _body(XmlElement content) => content
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

XmlElement _properties(XmlElement content, XmlElement element, String family) {
  final name = element.getAttribute('style-name', namespaceUri: _textNs);
  return content
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      )
      .firstChild('$family-properties', namespaceUri: _styleNs)!;
}

void main() {
  test('column sections use ODF column children and retain their own gaps', () {
    const counts = [2, 3, 2];
    const gaps = [18.0, 24.0, 0.0];
    final sections = [
      for (var i = 0; i < counts.length; i++)
        WmlSection(
          columnCount: counts[i],
          columnSpace: gaps[i],
          blocks: [_paragraph('Section $i')],
        ),
    ];
    final content = _export(sections);
    final emitted = _body(
      content,
    ).childrenNamed('section', namespaceUri: _textNs).toList();
    expect(emitted, hasLength(sections.length));
    for (var i = 0; i < emitted.length; i++) {
      final properties = _properties(content, emitted[i], 'section');
      expect(
        properties.getAttribute('column-count', namespaceUri: _foNs),
        isNull,
      );
      expect(
        properties.getAttribute('column-gap', namespaceUri: _foNs),
        isNull,
      );
      final columns = properties.childrenNamed(
        'columns',
        namespaceUri: _styleNs,
      );
      expect(
        columns,
        hasLength(1),
        reason: 'ODF requires a style:columns child',
      );
      expect(
        columns.single.getAttribute('column-count', namespaceUri: _foNs),
        '${counts[i]}',
      );
      expect(
        columns.single.getAttribute('column-gap', namespaceUri: _foNs),
        '${gaps[i].toStringAsFixed(2)}pt',
      );
      expect(emitted[i].text, 'Section $i');
      expect(sections[i].columnSpace, gaps[i]);
      expect(sections[i].columnCount, counts[i]);
    }
  });

  test(
    'invalid column gaps preserve columns and text without invalid lengths',
    () {
      const gaps = [double.nan, double.infinity, -double.infinity, 1e21];
      final sections = [
        for (var i = 0; i < gaps.length; i++)
          WmlSection(
            columnCount: 2,
            columnSpace: gaps[i],
            blocks: [_paragraph('Retained $i')],
          ),
      ];
      final content = _export(sections);
      final emitted = _body(
        content,
      ).childrenNamed('section', namespaceUri: _textNs).toList();
      expect(emitted, hasLength(gaps.length));
      for (var i = 0; i < emitted.length; i++) {
        final properties = _properties(content, emitted[i], 'section');
        expect(
          properties.getAttribute('column-gap', namespaceUri: _foNs),
          isNull,
        );
        final columns = properties.childrenNamed(
          'columns',
          namespaceUri: _styleNs,
        );
        expect(columns, hasLength(1));
        expect(
          columns.single.getAttribute('column-count', namespaceUri: _foNs),
          '2',
        );
        expect(
          columns.single.getAttribute('column-gap', namespaceUri: _foNs),
          isNull,
        );
        expect(emitted[i].text, 'Retained $i');
        if (gaps[i].isNaN) {
          expect(sections[i].columnSpace.isNaN, isTrue);
        } else {
          expect(sections[i].columnSpace, gaps[i]);
        }
      }
    },
  );

  for (final plainFirst in [true, false]) {
    for (final columnBreak in [true, false]) {
      test(
        '${columnBreak ? 'column break' : 'keep together'} stays local with plainFirst=$plainFirst',
        () {
          final flags = plainFirst ? [false, true, false] : [true, false, true];
          final properties = [
            for (final flag in flags)
              WmlParagraphProps(
                columnBreakBefore: columnBreak && flag,
                keepTogether: !columnBreak && flag,
              ),
          ];
          final content = _export([
            WmlSection(
              blocks: [
                _paragraph('Section anchor'),
                for (var i = 0; i < properties.length; i++)
                  _paragraph('Paragraph $i', properties[i]),
              ],
            ),
          ]);
          final paragraphs = _body(
            content,
          ).childrenNamed('p', namespaceUri: _textNs).skip(1).toList();
          expect(paragraphs, hasLength(flags.length));
          for (var i = 0; i < paragraphs.length; i++) {
            final emitted = _properties(content, paragraphs[i], 'paragraph');
            expect(
              emitted.getAttribute('break-before', namespaceUri: _foNs),
              columnBreak && flags[i] ? 'column' : null,
            );
            expect(
              emitted.getAttribute('keep-together', namespaceUri: _foNs),
              !columnBreak && flags[i] ? 'always' : null,
            );
            expect(paragraphs[i].text, 'Paragraph $i');
            expect(properties[i].columnBreakBefore, columnBreak && flags[i]);
            expect(properties[i].keepTogether, !columnBreak && flags[i]);
          }
        },
      );
    }
  }

  test('page break keeps precedence while retaining keep-together', () {
    final content = _export([
      WmlSection(
        blocks: [
          _paragraph('Section anchor'),
          _paragraph(
            'Next page',
            WmlParagraphProps(
              pageBreakBefore: true,
              columnBreakBefore: true,
              keepTogether: true,
            ),
          ),
        ],
      ),
    ]);
    final paragraph = _body(
      content,
    ).childrenNamed('p', namespaceUri: _textNs).last;
    final properties = _properties(content, paragraph, 'paragraph');
    expect(
      properties.getAttribute('break-before', namespaceUri: _foNs),
      'page',
    );
    expect(
      properties.getAttribute('keep-together', namespaceUri: _foNs),
      'always',
    );
    expect(paragraph.text, 'Next page');
  });
}
