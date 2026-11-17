import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

typedef _Export = ({XmlElement content, XmlElement body});

_Export _export(List<WmlSection> sections) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(WmlDocument(sections: sections)),
  );
  final content = XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!;
  return (
    content: content,
    body: content
        .firstChild('body', namespaceUri: _officeNs)!
        .firstChild('text', namespaceUri: _officeNs)!,
  );
}

XmlElement _style(_Export output, XmlElement owner) {
  final name = owner.getAttribute('style-name', namespaceUri: _textNs)!;
  return output.content
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

XmlElement _columns(_Export output, XmlElement section) {
  final style = _style(output, section);
  expect(style.getAttribute('family', namespaceUri: _styleNs), 'section');
  final properties = style.firstChild(
    'section-properties',
    namespaceUri: _styleNs,
  )!;
  // ODF 1.3 sections 17.11 and 17.12 place column attributes on this child,
  // not on the section-properties element itself.
  expect(properties.getAttribute('column-count', namespaceUri: _foNs), isNull);
  expect(properties.getAttribute('column-gap', namespaceUri: _foNs), isNull);
  return properties.childrenNamed('columns', namespaceUri: _styleNs).single;
}

void main() {
  test('column properties use the ODF columns child and retain body text', () {
    final paragraph = _paragraph('Two columns');
    final section = WmlSection(
      columnCount: 2,
      columnSpace: 18,
      blocks: [paragraph],
    );
    final output = _export([section]);
    final wrapper = output.body
        .childrenNamed('section', namespaceUri: _textNs)
        .single;
    final columns = _columns(output, wrapper);
    expect(columns.getAttribute('column-count', namespaceUri: _foNs), '2');
    expect(columns.getAttribute('column-gap', namespaceUri: _foNs), '18.00pt');
    expect(wrapper.firstChild('p', namespaceUri: _textNs)!.text, 'Two columns');
    expect(output.body.childElements, hasLength(1));
    expect(section.columnCount, 2);
    expect(section.columnSpace, 18);
    expect(section.blocks.single, same(paragraph));
  });

  for (final count in [-1, 0, 1]) {
    test('resolved single-column section $count retains an ordinary body', () {
      final section = WmlSection(
        columnCount: count,
        blocks: [_paragraph('Single column')],
      );
      final output = _export([section]);
      expect(
        output.body.childrenNamed('section', namespaceUri: _textNs),
        isEmpty,
      );
      expect(
        output.body.childrenNamed('p', namespaceUri: _textNs).single.text,
        'Single column',
      );
      expect(section.columnCount, count);
    });
  }

  test(
    'empty multicolumn section keeps its page anchor inside its section',
    () {
      final output = _export([
        WmlSection(blocks: [_paragraph('Before')]),
        WmlSection(columnCount: 3, columnSpace: 12),
        WmlSection(blocks: [_paragraph('After')]),
      ]);
      final body = output.body.childElements.toList();
      expect(body, hasLength(3));
      expect(body.first.text, 'Before');
      expect(body.last.text, 'After');
      final wrapper = body[1];
      expect(wrapper.localName, 'section');
      expect(wrapper.namespaceUri, _textNs);
      final anchor = wrapper.childrenNamed('p', namespaceUri: _textNs).single;
      expect(anchor.text, isEmpty);
      final anchorStyle = _style(output, anchor);
      expect(
        anchorStyle.getAttribute('master-page-name', namespaceUri: _styleNs),
        'mp1',
      );
      expect(
        anchorStyle
            .firstChild('paragraph-properties', namespaceUri: _styleNs)!
            .getAttribute('break-before', namespaceUri: _foNs),
        'page',
      );
      expect(
        _columns(
          output,
          wrapper,
        ).getAttribute('column-count', namespaceUri: _foNs),
        '3',
      );
    },
  );

  test('table-first section stays inside columns without an extra anchor', () {
    final paragraph = _paragraph('Cell text');
    final table = WmlTable(
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [paragraph]),
          ],
        ),
      ],
    );
    final output = _export([
      WmlSection(columnCount: 2, blocks: [table]),
    ]);
    final wrapper = output.body
        .childrenNamed('section', namespaceUri: _textNs)
        .single;
    _columns(output, wrapper);
    expect(wrapper.childrenNamed('p', namespaceUri: _textNs), isEmpty);
    expect(wrapper.childElements, hasLength(1));
    expect(
      wrapper.childrenNamed('table', namespaceUri: _tableNs).single.text,
      'Cell text',
    );
    expect(output.body.childElements, hasLength(1));
    expect(table.rows.single.cells.single.blocks.single, same(paragraph));
    expect(paragraph.text, 'Cell text');
  });

  test('column styles distinguish count and normalized gap', () {
    final output = _export([
      for (final (count, gap) in [
        (2, 18.001),
        (2, 18.004),
        (2, 24.0),
        (3, 18.0),
      ])
        WmlSection(
          columnCount: count,
          columnSpace: gap,
          blocks: [_paragraph('$count/$gap')],
        ),
    ]);
    final sections = output.body
        .childrenNamed('section', namespaceUri: _textNs)
        .toList();
    final names = sections
        .map(
          (section) =>
              section.getAttribute('style-name', namespaceUri: _textNs),
        )
        .toList();
    expect(names[0], names[1]);
    expect(names.toSet(), hasLength(3));
    final columnProperties = [
      for (final section in sections) _columns(output, section),
    ];
    expect(
      columnProperties.map(
        (columns) => columns.getAttribute('column-gap', namespaceUri: _foNs),
      ),
      ['18.00pt', '18.00pt', '24.00pt', '18.00pt'],
    );
    expect(
      columnProperties.map(
        (columns) => columns.getAttribute('column-count', namespaceUri: _foNs),
      ),
      ['2', '2', '2', '3'],
    );
  });

  test('zero and negative zero gaps share a valid zero-length style', () {
    final source = [
      for (final gap in [0.0, -0.0])
        WmlSection(
          columnCount: 2,
          columnSpace: gap,
          blocks: [_paragraph('Zero gap')],
        ),
    ];
    final output = _export(source);
    final sections = output.body
        .childrenNamed('section', namespaceUri: _textNs)
        .toList();
    expect(
      sections
          .map(
            (section) =>
                section.getAttribute('style-name', namespaceUri: _textNs),
          )
          .toSet(),
      hasLength(1),
    );
    for (final section in sections) {
      expect(
        _columns(
          output,
          section,
        ).getAttribute('column-gap', namespaceUri: _foNs),
        '0.00pt',
      );
    }
    expect(source[0].columnSpace.isNegative, isFalse);
    expect(source[1].columnSpace.isNegative, isTrue);
  });

  for (final gap in [
    -1.0,
    -0.001,
    double.nan,
    double.infinity,
    double.negativeInfinity,
    1e21,
  ]) {
    test('invalid gap $gap is omitted without losing columns or text', () {
      final section = WmlSection(
        columnCount: 2,
        columnSpace: gap,
        blocks: [_paragraph('Retained text')],
      );
      final output = _export([section]);
      final wrapper = output.body
          .childrenNamed('section', namespaceUri: _textNs)
          .single;
      final columns = _columns(output, wrapper);
      expect(columns.getAttribute('column-count', namespaceUri: _foNs), '2');
      expect(columns.getAttribute('column-gap', namespaceUri: _foNs), isNull);
      expect(wrapper.text, 'Retained text');
      if (gap.isNaN) {
        expect(section.columnSpace.isNaN, isTrue);
      } else {
        expect(section.columnSpace, gap);
      }
    });
  }
}
