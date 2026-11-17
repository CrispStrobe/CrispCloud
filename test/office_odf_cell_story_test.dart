import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';

String _document(String cell, String extension) =>
    '<o:document-content xmlns:o="$_office" xmlns:t="$_text" '
    'xmlns:tbl="$_table" xmlns:d="$_draw" xmlns:foreign="urn:foreign" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<o:body><o:${extension == 'ods' ? 'spreadsheet' : 'text'}>'
    '<tbl:table tbl:name="Cells"><tbl:table-row>'
    '<tbl:table-cell o:value-type="string">$cell</tbl:table-cell>'
    '</tbl:table-row></tbl:table>'
    '</o:${extension == 'ods' ? 'spreadsheet' : 'text'}></o:body>'
    '</o:document-content>';

Uint8List _package(String xml) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()..addFile(ArchiveFile.bytes('content.xml', utf8.encode(xml))),
  ),
);

String _frame(String content) =>
    '<d:frame><d:text-box>$content</d:text-box></d:frame>';

void _expectCell(
  OfficeDocument document,
  String expected,
  String source,
  String extension,
) {
  expect(document.fallback, isNull);
  final readable = expected.replaceAll('\n', ' ');
  expect(document.markdown, contains('| $readable |'));
  final rows = document.markdown
      .split('\n')
      .where((line) => line.startsWith('|'));
  expect(rows, hasLength(2));
  expect(document.markdown, isNot(contains('HIDDEN')));
  expect(document.plainText, isNot(contains('HIDDEN')));
  for (final line in expected.split('\n')) {
    expect(document.plainText, contains(line));
  }
  if (extension == 'ods') {
    expect(document.kind, OfficeDocumentKind.spreadsheet);
    expect(document.csv, expected.contains('\n') ? '"$expected"' : expected);
  } else {
    expect(document.kind, OfficeDocumentKind.document);
    expect(document.csv, isNull);
  }
  expect(document.rawXml, '<!-- content.xml -->\n$source');
}

void main() {
  for (final extension in ['odt', 'ods']) {
    test('$extension cell frame stories appear exactly once', () async {
      final xml = _document(
        '<t:p>Cell${_frame('<t:p>Outer${_frame('<t:p>Inner</t:p>')}end</t:p>')}'
        'tail</t:p><t:p>After</t:p>',
        extension,
      );
      final document = await parseOfficeDocument(
        _package(xml),
        'nested-cell.$extension',
      );
      // Keep each anchor's own inline text together, then visit its separate
      // text-box story. Preview cell paragraphs use spaces as separators.
      _expectCell(document, 'Celltail Outerend Inner After', xml, extension);
      final row = document.markdown
          .split('\n')
          .firstWhere((line) => line.startsWith('| '));
      for (final word in ['Cell', 'Outer', 'Inner', 'After']) {
        expect(RegExp(word).allMatches(row), hasLength(1));
      }
    });

    test(
      '$extension cell hidden stories cannot inject text or frames',
      () async {
        final hiddenFrame = _frame('<t:p>HIDDEN FRAME</t:p>');
        final xml = _document(
          '<t:p>A<t:note t:id="n1" t:note-class="footnote">'
          '<t:note-citation>HIDDEN CITE</t:note-citation><t:note-body>'
          '<t:p>HIDDEN NOTE</t:p>$hiddenFrame</t:note-body></t:note>'
          '<t:ruby><t:ruby-base>B</t:ruby-base>'
          '<t:ruby-text>HIDDEN RUBY$hiddenFrame</t:ruby-text></t:ruby>'
          '<o:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
          '<t:p>HIDDEN REVIEW</t:p>$hiddenFrame</o:annotation>C</t:p>'
          '<t:p><foreign:note>Visible note</foreign:note><t:s/>'
          '<foreign:ruby-text>Visible ruby</foreign:ruby-text><t:s/>'
          '<foreign:annotation>Visible review</foreign:annotation></t:p>',
          extension,
        );
        final document = await parseOfficeDocument(
          _package(xml),
          'hidden-cell.$extension',
        );
        _expectCell(
          document,
          'ABC Visible note Visible ruby Visible review',
          xml,
          extension,
        );
      },
    );

    test('$extension cells decode explicit whitespace and CDATA', () async {
      final xml = _document(
        '<t:p>A<t:s t:c="3"/>B<t:tab/>C<t:line-break/>'
        'D<![CDATA[ & E]]></t:p><t:p>Tail</t:p>',
        extension,
      );
      final document = await parseOfficeDocument(
        _package(xml),
        'spaces-cell.$extension',
      );
      _expectCell(document, 'A   B\tC\nD & E Tail', xml, extension);
    });
  }
}
