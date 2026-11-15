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
  odfTests();
  odtRichTests();
  odpTests();
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

  test('truncated legacy PPT has a structured extraction failure', () async {
    final doc = await parseOfficeDocument(
      Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]),
      'legacy.ppt',
    );
    expect(doc.fallback, OfficePreviewFallback.extractionFailed);
    expect(doc.notice, OfficePreviewNotice.powerPointMalformed);
    expect(doc.kind, OfficeDocumentKind.presentation);
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

  test(
    'EPUB extraction follows relocated OPF spine and excludes navigation',
    () async {
      final bytes = _zip({
        'META-INF/container.xml': '<container><rootfiles><rootfile full-path="Book/package.opf"/></rootfiles></container>',
        'Book/package.opf':
            '<package><manifest>'
            '<item id="first" href="Text/z.xhtml"/>'
            '<item id="second" href="Text/a.xhtml"/>'
            '<item id="toc" href="nav.xhtml" properties="nav"/>'
            '</manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>',
        'Book/Text/z.xhtml': '<html><body><p>FIRST CHAPTER</p></body></html>',
        'Book/Text/a.xhtml': '<html><body><p>SECOND CHAPTER</p></body></html>',
        'Book/nav.xhtml': '<html><body><p>NOT A CHAPTER</p></body></html>',
      });
      final doc = await parseOfficeDocument(bytes, 'ordered.epub');
      expect(
        doc.plainText.indexOf('FIRST CHAPTER'),
        lessThan(doc.plainText.indexOf('SECOND CHAPTER')),
      );
      expect(doc.plainText, isNot(contains('NOT A CHAPTER')));
    },
  );

  test('malformed documents fail gracefully', () async {
    final doc = await parseOfficeDocument(
      Uint8List.fromList(utf8.encode('not a zip')),
      'broken.docx',
    );
    expect(doc.plainText, contains('Could not extract'));
    expect(doc.note, isNotNull);
  });

  test('an RTF file named .doc is read as RTF', () async {
    final bytes = Uint8List.fromList(
      utf8.encode(r'{\rtf1\ansi Hello from RTF\par}'),
    );
    final doc = await parseOfficeDocument(bytes, 'misnamed.doc');
    expect(doc.plainText, contains('Hello from RTF'));
    expect(doc.notice, OfficePreviewNotice.rtfFormatting);
  });
}

void odfTests() {
  const namespaces =
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"';

  Future<OfficeDocument> parseTables(String tables, {String ext = 'ods'}) {
    final body = ext == 'ods' ? 'spreadsheet' : 'text';
    final xml =
        '''
<office:document-content $namespaces>
  <office:body><office:$body>$tables</office:$body></office:body>
</office:document-content>
''';
    return parseOfficeDocument(_zip({'content.xml': xml}), 'positions.$ext');
  }

  test('ODS keeps typed values, repeats and the real sheet name', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table table:name="Data">
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Name</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>Qty</text:p></table:table-cell>
        <table:table-cell office:value-type="string"><text:p>Flag</text:p></table:table-cell>
      </table:table-row>
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>A</text:p></table:table-cell>
        <table:table-cell office:value-type="float" office:value="2"><text:p>2</text:p></table:table-cell>
        <table:table-cell office:value-type="boolean" office:boolean-value="true"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2">
        <table:table-cell office:value-type="string"><text:p>B</text:p></table:table-cell>
        <table:table-cell office:value-type="currency" office:value="3.5"/>
        <table:table-cell table:number-columns-repeated="2"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1048570"/>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'data.ods',
    );
    expect(doc.kind, OfficeDocumentKind.spreadsheet);
    expect(doc.markdown, contains('## Data'));
    final rows = doc.csv!.split('\n').where((line) => line.isNotEmpty).toList();
    expect(rows.first, 'Name,Qty,Flag');
    expect(rows, contains('A,2,TRUE'));
    expect(rows.where((row) => row.startsWith('B,3.5')), hasLength(2));
    expect(rows.length, lessThan(10));
  });

  test('ODS merged and covered cells each retain one grid position', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table>
      <table:table-row>
        <table:table-cell table:number-columns-spanned="2" table:number-rows-spanned="2"><text:p>Wide</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
      <table:table-row>
        <table:covered-table-cell table:number-columns-repeated="2"/>
        <table:table-cell office:value-type="float" office:value="9"/>
      </table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'merged.ods',
    );
    expect(doc.csv, 'Wide,,7\n,,9');
  });

  test(
    'ODS keeps leading and interior repeated gaps through row groups',
    () async {
      final doc = await parseTables('''
<table:table table:name="Positions">
  <table:table-row table:number-rows-repeated="2"/>
  <table:table-header-rows>
    <table:table-row>
      <table:table-cell><text:p>Header</text:p></table:table-cell>
    </table:table-row>
  </table:table-header-rows>
  <table:table-row-group>
    <table:table-rows>
      <table:table-row table:number-rows-repeated="2">
        <table:table-cell table:number-columns-repeated="16384"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2">
        <table:table-cell table:number-columns-repeated="2"/>
        <table:table-cell office:value-type="float" office:value="7"/>
        <table:table-cell table:number-columns-repeated="16381"/>
      </table:table-row>
    </table:table-rows>
  </table:table-row-group>
  <table:table-row table:number-rows-repeated="1048570"/>
</table:table>
''');
      expect(doc.fallback, isNull);
      expect(doc.csv!.split('\n'), ['', '', 'Header', '', '', ',,7', ',,7']);
      expect(doc.markdown, contains('## Positions'));
    },
  );

  test('ODF row positions do not depend on namespace prefixes', () async {
    const xml = '''
<o:document-content
 xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:t="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:p="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:foreign="urn:unrelated">
  <o:body><o:spreadsheet><t:table t:name="Typed">
    <t:table-header-rows><t:table-row>
      <t:table-cell o:value-type="string"><p:p>Label</p:p></t:table-cell>
    </t:table-row></t:table-header-rows>
    <foreign:table-row><foreign:table-cell>Ignore</foreign:table-cell></foreign:table-row>
    <t:table-row>
      <foreign:table-cell>Ignore</foreign:table-cell>
      <t:table-cell o:value-type="float" o:value="3.5" t:number-columns-repeated="2"/>
      <t:table-cell o:value-type="boolean" o:boolean-value="1"/>
    </t:table-row>
  </t:table></o:spreadsheet></o:body>
</o:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'typed.ods',
    );
    expect(doc.fallback, isNull);
    expect(doc.csv, 'Label\n3.5,3.5,TRUE');
    expect(doc.markdown, contains('## Typed'));
  });

  test('ODT tables retain covered cells and interior blank rows', () async {
    final doc = await parseTables('''
<table:table>
  <table:table-header-rows><table:table-row>
    <table:table-cell table:number-columns-spanned="2"><text:p>Wide</text:p></table:table-cell>
    <table:covered-table-cell/>
    <table:table-cell><text:p>End</text:p></table:table-cell>
  </table:table-row></table:table-header-rows>
  <table:table-row-group>
    <table:table-row table:number-rows-repeated="2"/>
    <table:table-row>
      <table:table-cell table:number-columns-repeated="2"/>
      <table:table-cell><text:p>Tail</text:p></table:table-cell>
    </table:table-row>
  </table:table-row-group>
</table:table>
''', ext: 'odt');
    expect(doc.fallback, isNull);
    expect(doc.markdown.split('\n'), [
      '| Wide |  | End |',
      '| --- | --- | --- |',
      '|  |  |  |',
      '|  |  |  |',
      '|  |  | Tail |',
    ]);
  });

  final excessiveTables = <String, String>{
    'data after an oversized row gap': '''
      <table:table-row table:number-rows-repeated="100001"/>
      <table:table-row><table:table-cell office:value-type="float" office:value="1"/></table:table-row>
''',
    'data after an oversized column gap': '''
      <table:table-row>
        <table:table-cell table:number-columns-repeated="4096"/>
        <table:table-cell office:value-type="float" office:value="1"/>
      </table:table-row>
''',
    'repeated data beyond the row limit': '''
      <table:table-row table:number-rows-repeated="100001">
        <table:table-cell office:value-type="float" office:value="1"/>
      </table:table-row>
''',
    'repeated data beyond the column limit': '''
      <table:table-row>
        <table:table-cell table:number-columns-repeated="4097" office:value-type="float" office:value="1"/>
      </table:table-row>
''',
    'a small XML Cartesian expansion': '''
      <table:table-row table:number-rows-repeated="1000">
        <table:table-cell table:number-columns-repeated="201" office:value-type="float" office:value="1"/>
      </table:table-row>
''',
    'padding earlier rows to a later wide row': '''
      <table:table-row table:number-rows-repeated="1000">
        <table:table-cell office:value-type="float" office:value="1"/>
      </table:table-row>
      <table:table-row>
        <table:table-cell table:number-columns-repeated="199"/>
        <table:table-cell office:value-type="float" office:value="2"/>
      </table:table-row>
''',
  };
  for (final entry in excessiveTables.entries) {
    test('ODF preview refuses ${entry.key} without a partial table', () async {
      final doc = await parseTables(
        '<table:table>${entry.value}</table:table>',
      );
      expect(doc.fallback, OfficePreviewFallback.extractionFailed);
      expect(doc.note, contains('ODF preview exceeds'));
      expect(doc.csv, isNull);
      expect(doc.markdown, isEmpty);
    });
  }

  test('ODF preview shares expansion limits across tables', () async {
    const table = '''
<table:table><table:table-row table:number-rows-repeated="1000">
  <table:table-cell table:number-columns-repeated="101" office:value-type="float" office:value="1"/>
</table:table-row></table:table>
''';
    final doc = await parseTables('$table$table');
    expect(doc.fallback, OfficePreviewFallback.extractionFailed);
    expect(doc.note, contains('rendered-cell limit'));
    expect(doc.csv, isNull);
  });

  test('ODF preview bounds repeated text before rendering', () async {
    final value = 'x' * 1024;
    final doc = await parseTables('''
<table:table><table:table-row table:number-rows-repeated="3">
  <table:table-cell table:number-columns-repeated="4096"><text:p>$value</text:p></table:table-cell>
</table:table-row></table:table>
''');
    expect(doc.fallback, OfficePreviewFallback.extractionFailed);
    expect(doc.note, contains('expanded-text limit'));
    expect(doc.csv, isNull);
  });

  test('ODF preview rejects invalid repeat counts', () async {
    final doc = await parseTables('''
<table:table><table:table-row table:number-rows-repeated="0">
  <table:table-cell><text:p>Invalid</text:p></table:table-cell>
</table:table-row></table:table>
''');
    expect(doc.fallback, OfficePreviewFallback.extractionFailed);
    expect(doc.note, contains('Invalid ODF number-rows-repeated'));
  });

  test('ODS with a merged cell keeps following columns aligned', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table>
      <table:table-row>
        <table:table-cell table:number-columns-spanned="2"><text:p>Wide</text:p></table:table-cell>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'merged.ods',
    );
    expect(doc.csv!.split('\n').first, 'Wide,,7');
  });

  test(
    'ODS preserves internal blank runs and trims trailing padding',
    () async {
      const xml =
          '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table table:name="Data">
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Start</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2">
        <table:table-cell/>
      </table:table-row>
      <table:table-row>
        <table:table-cell office:value-type="float" office:value="42"/>
        <table:table-cell table:formula="of:=[.A4]" office:value-type="float" office:value="42"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1048570"/>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
      final doc = await parseOfficeDocument(
        _zip({'content.xml': xml}),
        'gaps.ods',
      );
      expect(doc.fallback, isNull);
      expect(doc.csv!.split('\n'), ['Start', '', '', '42,42']);
      expect(
        doc.markdown,
        contains(
          '| Start |  |\n| --- | --- |\n'
          '|  |  |\n|  |  |\n| 42 | 42 |',
        ),
      );
    },
  );

  test('ODS CSV preserves leading blank rows and cell whitespace', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table>
      <table:table-row table:number-rows-repeated="2"/>
      <table:table-row>
        <table:table-cell office:value-type="string" office:string-value="  First  "/>
      </table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'leading.ods',
    );
    expect(doc.fallback, isNull);
    expect(doc.csv, '\n\n  First  ');
  });

  test('ODS counts explicit and repeated covered cells only once', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table>
      <table:table-row>
        <table:table-cell table:number-columns-spanned="2"><text:p>Wide</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
      <table:table-row>
        <table:table-cell table:number-columns-spanned="3"><text:p>Wider</text:p></table:table-cell>
        <table:covered-table-cell table:number-columns-repeated="2"/>
        <table:table-cell office:value-type="float" office:value="8"/>
      </table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'spans.ods',
    );
    expect(doc.fallback, isNull);
    expect(doc.csv!.split('\n'), ['Wide,,7', 'Wider,,,8']);
  });

  test(
    'ODS refuses later data when empty padding exceeds the row limit',
    () async {
      const xml =
          '''
<office:document-content $namespaces>
  <office:body><office:spreadsheet>
    <table:table>
      <table:table-row>
        <table:table-cell><text:p>Inside</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1000000"/>
      <table:table-row>
        <table:table-cell><text:p>Outside</text:p></table:table-cell>
      </table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
      final doc = await parseOfficeDocument(
        _zip({'content.xml': xml}),
        'limit.ods',
      );
      expect(doc.fallback, OfficePreviewFallback.extractionFailed);
      expect(doc.note, contains('ODF preview exceeds the row limit'));
      expect(doc.csv, isNull);
      expect(doc.markdown, isEmpty);
    },
  );

  test('ODT renders lists and ODF table cells', () async {
    const xml =
        '''
<office:document-content $namespaces>
  <office:body><office:text>
    <text:h text:outline-level="1">Title</text:h>
    <text:list>
      <text:list-item><text:p>One</text:p></text:list-item>
      <text:list-item><text:p>Two</text:p></text:list-item>
    </text:list>
    <table:table>
      <table:table-row>
        <table:table-cell><text:p>Alpha</text:p></table:table-cell>
        <table:table-cell table:number-columns-repeated="2"><text:p>x</text:p></table:table-cell>
      </table:table-row>
    </table:table>
  </office:text></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'notes.odt',
    );
    expect(doc.markdown, contains('# Title'));
    expect(doc.markdown, contains('- One'));
    expect(doc.markdown, contains('- Two'));
    expect(doc.markdown, contains('Alpha'));
    expect(doc.markdown, contains('| Alpha | x | x |'));
  });
}

void odtRichTests() {
  test('ODT renders inline styles, links, notes and ordered lists', () async {
    const xml = '''
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:xlink="http://www.w3.org/1999/xlink">
  <office:automatic-styles>
    <style:style style:name="T1" style:family="text">
      <style:text-properties fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="T2" style:family="text">
      <style:text-properties fo:font-style="italic"/>
    </style:style>
    <text:list-style style:name="L1">
      <text:list-level-style-number text:level="1"/>
    </text:list-style>
    <text:list-style style:name="L2">
      <text:list-level-style-bullet text:level="1"/>
    </text:list-style>
  </office:automatic-styles>
  <office:body><office:text>
    <text:h text:outline-level="1">Title</text:h>
    <text:p>Hello <text:span text:style-name="T1">bold</text:span> and
      <text:span text:style-name="T2">italic</text:span>
      <text:a xlink:href="https://example.com">link</text:a><text:note
        text:note-class="footnote" text:id="fn1"><text:note-citation>1</text:note-citation><text:note-body><text:p>Footnote text.</text:p></text:note-body></text:note>
    </text:p>
    <text:list text:style-name="L1">
      <text:list-item><text:p>First</text:p></text:list-item>
      <text:list-item><text:p>Second</text:p></text:list-item>
    </text:list>
    <text:list text:style-name="L2">
      <text:list-item><text:p>Bullet</text:p>
        <text:list text:style-name="L2">
          <text:list-item><text:p>Nested</text:p></text:list-item>
        </text:list>
      </text:list-item>
    </text:list>
  </office:text></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'rich.odt',
    );
    expect(doc.markdown, contains('# Title'));
    expect(doc.markdown, contains('**bold**'));
    expect(doc.markdown, contains('*italic*'));
    expect(doc.markdown, contains('[link](https://example.com)'));
    expect(doc.markdown, contains('[1]'));
    expect(doc.markdown, contains('1. First'));
    expect(doc.markdown, contains('2. Second'));
    expect(doc.markdown, contains('- Bullet'));
    expect(doc.markdown, contains('  - Nested'));
    expect(doc.markdown, contains('1. Footnote text.'));
  });
}

void odpTests() {
  test('ODP exposes slide size, positioned text, fills and notes', () async {
    const xml = '''
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  xmlns:xlink="http://www.w3.org/1999/xlink">
  <office:automatic-styles>
    <style:page-layout style:name="PM1">
      <style:page-layout-properties fo:page-width="20cm" fo:page-height="15cm"/>
    </style:page-layout>
    <style:style style:name="gr1" style:family="graphic">
      <style:graphic-properties draw:fill-color="#ffeeaa"/>
    </style:style>
    <style:style style:name="P1" style:family="paragraph">
      <style:text-properties fo:font-size="24pt" fo:font-weight="bold" fo:color="#112233"/>
    </style:style>
  </office:automatic-styles>
  <office:body><office:presentation>
    <draw:page draw:name="Slide1">
      <draw:frame draw:style-name="gr1" svg:x="1cm" svg:y="2cm"
        svg:width="10cm" svg:height="3cm">
        <draw:text-box>
          <text:p text:style-name="P1">Hello</text:p>
          <text:p>World</text:p>
        </draw:text-box>
      </draw:frame>
      <presentation:notes>
        <draw:frame svg:x="0cm" svg:y="0cm" svg:width="2cm" svg:height="2cm">
          <draw:text-box><text:p>Speaker note</text:p></draw:text-box>
        </draw:frame>
      </presentation:notes>
    </draw:page>
  </office:presentation></office:body>
</office:document-content>
''';
    final doc = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'deck.odp',
    );
    expect(doc.kind, OfficeDocumentKind.presentation);
    expect(doc.deck, isNotNull);
    expect(doc.deck!.widthEmu, 7200000);
    expect(doc.deck!.heightEmu, 5400000);
    final shape = doc.deck!.slides.single.shapes.single;
    expect(shape.x, 360000);
    expect(shape.y, 720000);
    expect(shape.width, 3600000);
    expect(shape.height, 1080000);
    expect(shape.text, 'Hello\nWorld');
    expect(shape.fontSizePt, 24);
    expect(shape.bold, isTrue);
    expect(shape.textColorHex, '112233');
    expect(shape.fillColorHex, 'FFEEAA');
    expect(doc.markdown, contains('*Notes: Speaker note*'));
  });
}
