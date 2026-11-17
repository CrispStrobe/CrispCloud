import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _linkNs = 'http://www.w3.org/1999/xlink';

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

XmlElement _xml(OpcPackage package, String name) =>
    XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;

List<String?> _names(XmlElement root, String kind) =>
    _elements(root, 'bookmark-$kind', _textNs)
        .map((element) => element.getAttribute('name', namespaceUri: _textNs))
        .toList();

WmlParagraph _range(String name) => WmlParagraph(
  inlines: [
    WmlBookmarkBoundary(id: '7', isStart: true, name: name),
    WmlRun(text: '$name text'),
    WmlBookmarkBoundary(id: '7', isStart: false),
  ],
);

void main() {
  test(
    'imported DOCX overlapping ranges retain unnamed ends on ODT export',
    () {
      final source = OpcPackage.create(OpcPackageKind.word);
      source.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:bookmarkStart w:id="+01" w:name="Range"/><w:r><w:t>Alpha</w:t></w:r><w:bookmarkStart w:id="2" w:name="Overlap"/><w:r><w:t>Beta</w:t></w:r></w:p>
<w:p><w:r><w:t>Gamma</w:t></w:r><w:bookmarkEnd w:id="1"/><w:r><w:t>Delta</w:t></w:r><w:bookmarkEnd w:id="2"/><w:hyperlink w:anchor="Range"><w:r><w:t>Jump</w:t></w:r></w:hyperlink></w:p>
</w:body></w:document>''');
      final document = WordDeserializer().read(source);
      final markers = document.paragraphs
          .expand((paragraph) => paragraph.inlines)
          .whereType<WmlBookmarkBoundary>()
          .toList();
      expect(markers.map((marker) => marker.id), ['+01', '2', '1', '2']);
      expect(
        markers.where((marker) => !marker.isStart).map((marker) => marker.name),
        [null, null],
      );
      final native = markers.map((marker) => marker.sourceXml).toList();
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      final content = _xml(package, 'content');
      final paragraphs = content
          .firstChild('body', namespaceUri: _officeNs)!
          .firstChild('text', namespaceUri: _officeNs)!
          .childrenNamed('p', namespaceUri: _textNs)
          .toList();
      expect(paragraphs, hasLength(2));
      expect(_names(paragraphs.first, 'start'), ['Range', 'Overlap']);
      expect(_names(paragraphs.first, 'end'), isEmpty);
      expect(_names(paragraphs.last, 'end'), ['Range', 'Overlap']);
      expect(
        paragraphs.last.childElements.map((element) => element.localName),
        ['span', 'bookmark-end', 'span', 'bookmark-end', 'a'],
      );
      expect(
        _elements(
          content,
          'a',
          _textNs,
        ).single.getAttribute('href', namespaceUri: _linkNs),
        '#Range',
      );
      expect(markers.map((marker) => marker.sourceXml), native);
      expect(
        markers.where((marker) => !marker.isStart).map((marker) => marker.name),
        [null, null],
      );
    },
  );

  test('bookmark ranges remain owned by body and nested stories', () {
    final start = WmlBookmarkBoundary(id: '7', isStart: true, name: 'Body');
    final end = WmlBookmarkBoundary(id: '7', isStart: false);
    final document = WmlDocument(
      sections: [
        WmlSection(
          header: [_range('Header')],
          footer: [_range('Footer')],
          blocks: [
            WmlParagraph(
              inlines: [
                start,
                WmlRun(text: 'Body text', commentIds: [3]),
                WmlRun(text: '1', noteRefId: 2),
              ],
            ),
            WmlFrame(blocks: [_range('Frame')]),
            WmlTable(
              rows: [
                WmlTableRow(cells: [WmlTableCell(vMerge: WmlVMerge.restart)]),
                WmlTableRow(
                  cells: [
                    WmlTableCell(
                      vMerge: WmlVMerge.cont,
                      blocks: [_range('Covered')],
                    ),
                  ],
                ),
              ],
            ),
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Tail'),
                end,
              ],
            ),
          ],
        ),
      ],
      comments: [
        WmlComment(id: 3, paragraphs: [_range('Comment')]),
      ],
      footnotes: [
        WmlNote(id: 2, endnote: false, blocks: [_range('Note')]),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = _xml(package, 'content');
    final styles = _xml(package, 'styles');
    for (final item in [
      (_elements(content, 'annotation', _officeNs).single, 'Comment'),
      (_elements(content, 'note-body', _textNs).single, 'Note'),
      (_elements(content, 'text-box', _drawNs).single, 'Frame'),
      (_elements(content, 'covered-table-cell', _tableNs).single, 'Covered'),
      (_elements(styles, 'header', _styleNs).single, 'Header'),
      (_elements(styles, 'footer', _styleNs).single, 'Footer'),
    ]) {
      expect(_names(item.$1, 'start'), [item.$2]);
      expect(_names(item.$1, 'end'), [item.$2]);
    }
    final paragraphs = content
        .firstChild('body', namespaceUri: _officeNs)!
        .firstChild('text', namespaceUri: _officeNs)!
        .childrenNamed('p', namespaceUri: _textNs)
        .toList();
    expect(_names(paragraphs.last, 'end'), ['Body']);
    expect(
      identical(
        document.sections.single.blocks.first,
        document.paragraphs.first,
      ),
      isTrue,
    );
    expect(
      identical(
        (document.sections.single.blocks.last as WmlParagraph).inlines.last,
        end,
      ),
      isTrue,
    );
    expect(end.name, isNull);
  });

  test('an unmatched end never borrows a bookmark from another story', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          header: [
            WmlParagraph(
              inlines: [
                WmlBookmarkBoundary(id: '7', isStart: true, name: 'Header'),
              ],
            ),
          ],
          footer: [
            WmlParagraph(
              inlines: [WmlBookmarkBoundary(id: '7', isStart: false)],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final styles = _xml(package, 'styles');
    expect(_names(_elements(styles, 'header', _styleNs).single, 'start'), [
      'Header',
    ]);
    expect(
      _names(_elements(styles, 'footer', _styleNs).single, 'end'),
      isEmpty,
    );
  });
}
