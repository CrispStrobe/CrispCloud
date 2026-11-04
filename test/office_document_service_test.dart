// test/office_document_service_test.dart
//
// Tests for structured Office/EPUB extraction: formatted Markdown, plain
// text, spreadsheet CSV and raw XML.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/office_document_service.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('DOCX produces Markdown with headings, bold runs and tables', () async {
    const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Report Title</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r><w:r><w:t> and normal text</w:t></w:r></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Value</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>Alpha</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
  </w:body>
</w:document>
''';
    final bytes = _zip({'word/document.xml': xml});
    final doc = await parseOfficeDocument(bytes, 'report.docx');

    expect(doc.kind, OfficeDocumentKind.document);
    expect(doc.markdown, contains('# Report Title'));
    expect(doc.markdown, contains('**Bold** and normal text'));
    expect(doc.markdown, contains('| Name | Value |'));
    expect(doc.plainText, contains('Report Title'));
    expect(doc.plainText, isNot(contains('**')));
    expect(doc.rawXml, contains('<w:document'));
  });

  test('XLSX produces CSV from shared strings and cell references', () async {
    const shared = '''
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Name</t></si><si><t>Alice</t></si><si><t>Bob</t></si>
</sst>
''';
    const sheet = '''
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c></row>
    <row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>42</v></c></row>
    <row r="3"><c r="A3" t="s"><v>2</v></c></row>
  </sheetData>
</worksheet>
''';
    final bytes = _zip({
      'xl/sharedStrings.xml': shared,
      'xl/worksheets/sheet1.xml': sheet,
    });
    final doc = await parseOfficeDocument(bytes, 'data.xlsx');

    expect(doc.kind, OfficeDocumentKind.spreadsheet);
    expect(doc.csv, contains('Name'));
    expect(doc.csv, contains('Alice,42'));
    expect(doc.csv, contains('Bob'));
    expect(doc.markdown, contains('## Sheet 1'));
    expect(doc.plainText, contains('Alice'));
  });

  test('PPTX produces one section per slide', () async {
    const slide = '''
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld><p:spTree><p:sp><p:txBody>
    <a:p><a:r><a:t>Quarterly Results</a:t></a:r></a:p>
    <a:p><a:r><a:t>Revenue up 20%</a:t></a:r></a:p>
  </p:txBody></p:sp></p:spTree></p:cSld>
</p:sld>
''';
    final bytes = _zip({'ppt/slides/slide1.xml': slide});
    final doc = await parseOfficeDocument(bytes, 'deck.pptx');

    expect(doc.kind, OfficeDocumentKind.presentation);
    expect(doc.markdown, contains('## Slide 1'));
    expect(doc.markdown, contains('Quarterly Results'));
    expect(doc.markdown, contains('- Revenue up 20%'));
  });

  test('PPTX exposes slide geometry, text and fills', () async {
    const presentation = '''
<p:presentation
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldSz cx="12192000" cy="6858000"/>
</p:presentation>
''';
    const slide = '''
<p:sld
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld><p:spTree>
    <p:sp>
      <p:spPr>
        <a:xfrm>
          <a:off x="914400" y="914400"/>
          <a:ext cx="9144000" cy="1828800"/>
        </a:xfrm>
        <a:solidFill><a:srgbClr val="1F4E79"/></a:solidFill>
      </p:spPr>
      <p:txBody>
        <a:p><a:r><a:rPr sz="3200" b="1"/><a:t>Hello slide</a:t></a:r></a:p>
      </p:txBody>
    </p:sp>
  </p:spTree></p:cSld>
</p:sld>
''';
    final bytes = _zip({
      'ppt/presentation.xml': presentation,
      'ppt/slides/slide1.xml': slide,
    });
    final doc = await parseOfficeDocument(bytes, 'deck.pptx');

    expect(doc.kind, OfficeDocumentKind.presentation);
    expect(doc.deck, isNotNull);
    expect(doc.deck!.widthEmu, 12192000);
    expect(doc.deck!.heightEmu, 6858000);
    expect(doc.deck!.slides.length, 1);
    final shape = doc.deck!.slides.first.shapes.first;
    expect(shape.text, 'Hello slide');
    expect(shape.fontSizePt, 32);
    expect(shape.bold, isTrue);
    expect(shape.fillColorHex, '1F4E79');
    expect(shape.x, 914400);
  });

  test('legacy PPT returns a conversion hint instead of failing', () async {
    final doc = await parseOfficeDocument(
      Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]),
      'legacy.ppt',
    );
    expect(doc.plainText, contains('Legacy PowerPoint'));
    expect(doc.note, isNotNull);
  });

  test('ODT content.xml produces headings and paragraphs', () async {
    const xml = '''
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body><office:text>
    <text:h text:outline-level="1">Intro</text:h>
    <text:p>First paragraph.</text:p>
  </office:text></office:body>
</office:document-content>
''';
    final bytes = _zip({'content.xml': xml});
    final doc = await parseOfficeDocument(bytes, 'notes.odt');

    expect(doc.markdown, contains('# Intro'));
    expect(doc.markdown, contains('First paragraph.'));
  });

  test('EPUB chapters become Markdown', () async {
    const xhtml = '''
<html><body>
  <h1>Chapter One</h1>
  <p>Hello epub reader.</p>
  <ul><li>Point one</li></ul>
</body></html>
''';
    final bytes = _zip({'OEBPS/chapter1.xhtml': xhtml});
    final doc = await parseOfficeDocument(bytes, 'book.epub');

    expect(doc.kind, OfficeDocumentKind.ebook);
    expect(doc.markdown, contains('# Chapter One'));
    expect(doc.markdown, contains('Hello epub reader.'));
    expect(doc.markdown, contains('- Point one'));
  });

  test('malformed documents fail gracefully', () async {
    final doc = await parseOfficeDocument(
      Uint8List.fromList(utf8.encode('not a zip')),
      'broken.docx',
    );
    expect(doc.plainText, contains('Could not extract'));
    expect(doc.note, isNotNull);
  });
}
