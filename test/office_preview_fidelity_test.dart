// Preview expectations come from independently authored ZIP/XML, never Quds
// exports. The app must show the stored text, relationships and workbook order.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _word(String body, {String prefix = 'w'}) =>
    '<$prefix:document xmlns:$prefix="$_w"><$prefix:body>'
    '${body.replaceAll('w:', '$prefix:')}'
    '</$prefix:body></$prefix:document>';

String _sheet(String text) =>
    '<s:worksheet xmlns:s="$_s"><s:sheetData>'
    '<s:row r="1"><s:c r="A1" t="inlineStr"><s:is><s:t>$text</s:t></s:is></s:c></s:row>'
    '</s:sheetData></s:worksheet>';

void main() {
  for (final falseValue in ['0', 'false', 'off']) {
    test('DOCX preview honors explicit false formatting $falseValue', () async {
      final document = await parseOfficeDocument(
        _zip({
          'word/document.xml': _word(
            '<w:p><w:r><w:rPr><w:b w:val="$falseValue"/><w:i w:val="$falseValue"/></w:rPr><w:t>Unformatted</w:t></w:r></w:p>',
          ),
        }),
        'false.docx',
      );
      expect(document.fallback, isNull);
      expect(document.markdown, 'Unformatted');
      expect(document.plainText, 'Unformatted');
    });
  }

  test(
    'DOCX preview retains tabs, line breaks and alternate namespace prefixes',
    () async {
      final document = await parseOfficeDocument(
        _zip({
          'word/document.xml': _word(
            '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Prefix heading</w:t></w:r></w:p>'
            '<w:p><w:r><w:t>First</w:t><w:tab/><w:t>Second</w:t><w:br/><w:t>Third</w:t><w:cr/><w:t>Fourth</w:t></w:r></w:p>',
            prefix: 'n',
          ),
        }),
        'tokens.docx',
      );
      expect(
        document.markdown,
        '## Prefix heading\n\nFirst\tSecond  \nThird  \nFourth',
      );
      expect(
        document.plainText,
        'Prefix heading\n\nFirst\tSecond\nThird\nFourth',
      );
    },
  );

  test(
    'formatting across hard breaks is readable in Markdown and plain text',
    () async {
      final document = await parseOfficeDocument(
        _zip({
          'word/document.xml': _word(
            '<w:p><w:r><w:rPr><w:b/><w:i w:val="1"/></w:rPr><w:t>First</w:t><w:br/><w:t>Second</w:t></w:r></w:p>',
          ),
        }),
        'format.docx',
      );
      expect(document.markdown, '***First***  \n***Second***');
      expect(document.plainText, 'First\nSecond');
    },
  );

  test('numId zero removes a preview paragraph from a list', () async {
    final document = await parseOfficeDocument(
      _zip({
        'word/document.xml': _word(
          '<w:p><w:pPr><w:numPr><w:numId w:val="0"/></w:numPr></w:pPr><w:r><w:t>Plain paragraph</w:t></w:r></w:p>',
        ),
      }),
      'list.docx',
    );
    expect(document.markdown, 'Plain paragraph');
  });

  test('DOCX notes follow owning-part relationships and stable reference order', () async {
    final document = await parseOfficeDocument(
      _zip({
        '_rels/.rels':
            '<Relationships xmlns="$_pr"><Relationship Id="main" Type="$_r/officeDocument" Target="office/text/main.xml"/></Relationships>',
        'office/text/main.xml': _word(
          '<w:p><w:r><w:t>Body</w:t><w:footnoteReference w:id="7"/><w:t> again</w:t><w:footnoteReference w:id="7"/><w:t> and</w:t><w:endnoteReference w:id="7"/></w:r></w:p>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t><w:footnoteReference w:id="9"/></w:r></w:p></w:tc></w:tr></w:tbl>',
          prefix: 'n',
        ),
        'office/text/_rels/main.xml.rels':
            '<Relationships xmlns="$_pr">'
            '<Relationship Id="foot" Type="$_r/footnotes" Target="../notes/foot.xml"/>'
            '<Relationship Id="end" Type="$_r/endnotes" Target="../notes/end.xml"/>'
            '</Relationships>',
        'office/notes/foot.xml':
            '<w:footnotes xmlns:w="$_w">'
            '<w:footnote w:id="-1" w:type="separator"><w:p><w:r><w:t>Hidden separator</w:t></w:r></w:p></w:footnote>'
            '<w:footnote w:id="7"><w:p><w:r><w:footnoteRef/><w:t>Footnote first</w:t></w:r></w:p><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Second paragraph</w:t></w:r></w:p></w:footnote>'
            '<w:footnote w:id="9"><w:p><w:r><w:t>Cell footnote</w:t></w:r></w:p></w:footnote>'
            '<w:footnote w:id="99"><w:p><w:r><w:t>Unreferenced body</w:t></w:r></w:p></w:footnote>'
            '</w:footnotes>',
        'office/notes/end.xml':
            '<w:endnotes xmlns:w="$_w"><w:endnote w:id="7"><w:p><w:r><w:endnoteRef/><w:t>Endnote body</w:t></w:r></w:p></w:endnote></w:endnotes>',
        'word/footnotes.xml':
            '<w:footnotes xmlns:w="$_w"><w:footnote w:id="7"><w:p><w:r><w:t>Wrong canonical part</w:t></w:r></w:p></w:footnote></w:footnotes>',
      }),
      'notes.docx',
    );
    expect(document.fallback, isNull);
    expect(document.markdown, contains('Body[1] again[1] and[2]'));
    expect(document.markdown, contains('| Cell[3] |'));
    expect(
      document.markdown,
      contains('[1] Footnote first\n\n**Second paragraph**'),
    );
    expect(document.plainText, contains('[2] Endnote body'));
    expect(document.plainText, contains('[3] Cell footnote'));
    expect(document.plainText, isNot(contains('Hidden separator')));
    expect(document.plainText, isNot(contains('Unreferenced body')));
    expect(document.plainText, isNot(contains('Wrong canonical part')));
    expect(
      document.plainText.indexOf('[1] Footnote'),
      lessThan(document.plainText.indexOf('[2] Endnote')),
    );
  });

  test('missing note bodies retain visible reference markers', () async {
    final document = await parseOfficeDocument(
      _zip({
        'word/document.xml': _word(
          '<w:p><w:r><w:t>Referenced</w:t><w:footnoteReference w:id="12"/></w:r></w:p>',
        ),
      }),
      'missing-note.docx',
    );
    expect(document.fallback, isNull);
    expect(document.plainText, 'Referenced[1]');
  });

  test('DOCX parts at package root resolve their sibling relationships', () async {
    final document = await parseOfficeDocument(
      _zip({
        '_rels/.rels':
            '<Relationships xmlns="$_pr"><Relationship Id="main" Type="$_r/officeDocument" Target="main.xml"/></Relationships>',
        'main.xml': _word(
          '<w:p><w:r><w:t>Root</w:t><w:footnoteReference w:id="1"/></w:r></w:p>',
        ),
        '_rels/main.xml.rels':
            '<Relationships xmlns="$_pr"><Relationship Id="notes" Type="$_r/footnotes" Target="notes.xml"/></Relationships>',
        'notes.xml':
            '<w:footnotes xmlns:w="$_w"><w:footnote w:id="1"><w:p><w:r><w:t>Root note</w:t></w:r></w:p></w:footnote></w:footnotes>',
      }),
      'root.docx',
    );
    expect(document.plainText, 'Root[1]\n\n[1] Root note');
  });

  test('XLSX preview follows workbook order, relationships, names and shared strings', () async {
    final document = await parseOfficeDocument(
      _zip({
        '_rels/.rels':
            '<Relationships xmlns="$_pr"><Relationship Id="main" Type="$_r/officeDocument" Target="book/catalog.xml"/></Relationships>',
        'book/catalog.xml':
            '<s:workbook xmlns:s="$_s" xmlns:link="$_r"><s:sheets>'
            '<s:sheet name="Forecast" sheetId="9" link:id="later"/>'
            '<s:sheet name="Sheet 1" sheetId="2" link:id="earlier"/>'
            '<s:sheet name="Empty" sheetId="5" link:id="empty"/>'
            '<s:sheet name="External" sheetId="6" link:id="network"/>'
            '</s:sheets></s:workbook>',
        'book/_rels/catalog.xml.rels':
            '<Relationships xmlns="$_pr">'
            '<Relationship Id="later" Type="$_r/worksheet" Target="../data/later.xml"/>'
            '<Relationship Id="earlier" Type="$_r/worksheet" Target="/data/earlier.xml"/>'
            '<Relationship Id="empty" Type="$_r/worksheet" Target="../data/empty.xml"/>'
            '<Relationship Id="strings" Type="$_r/sharedStrings" Target="../strings/custom.xml"/>'
            '<Relationship Id="network" Type="$_r/worksheet" Target="https://example.com/sheet.xml" TargetMode="External"/>'
            '</Relationships>',
        'strings/custom.xml':
            '<s:sst xmlns:s="$_s"><s:si><s:t>From shared strings</s:t></s:si></s:sst>',
        'data/later.xml':
            '<s:worksheet xmlns:s="$_s"><s:sheetData><s:row r="1"><s:c r="A1" t="s"><s:v>0</s:v></s:c></s:row></s:sheetData></s:worksheet>',
        'data/earlier.xml': _sheet('Earlier filename, later workbook position'),
        'data/empty.xml':
            '<s:worksheet xmlns:s="$_s"><s:sheetData/></s:worksheet>',
        'xl/worksheets/sheet1.xml': _sheet('ORPHAN must not appear'),
      }),
      'ordered.xlsx',
    );
    expect(document.fallback, isNull);
    expect(document.markdown, startsWith('## Forecast\n'));
    expect(
      document.markdown.indexOf('## Forecast'),
      lessThan(document.markdown.indexOf('## Sheet 1')),
    );
    expect(document.csv, startsWith('# Forecast\nFrom shared strings\n'));
    expect(document.markdown, contains('## Empty'));
    expect(document.plainText, contains('From shared strings'));
    expect(document.plainText, isNot(contains('ORPHAN')));
    expect(document.plainText, isNot(contains('External')));
    expect(document.markdownHeadings, isEmpty);
    expect(document.textHeadings, isEmpty);
    expect(document.csvHeadings, isEmpty);
    final strings = OfficePreviewStrings(const Locale('es'));
    expect(
      strings.headings(
        document.markdown,
        document.markdownHeadings,
        const Locale('es'),
      ),
      document.markdown,
    );
    expect(document.rawXml, contains('t="s"'));
  });

  test(
    'XLSX without a workbook retains fallback headings and natural order',
    () async {
      final document = await parseOfficeDocument(
        _zip({
          'xl/worksheets/sheet10.xml': _sheet('TEN'),
          'xl/worksheets/sheet2.xml': _sheet('TWO'),
        }),
        'minimal.xlsx',
      );
      expect(
        document.plainText.indexOf('TWO'),
        lessThan(document.plainText.indexOf('TEN')),
      );
      expect(document.markdownHeadings, hasLength(2));
      final strings = OfficePreviewStrings(const Locale('es'));
      expect(
        strings.headings(
          document.markdown,
          document.markdownHeadings,
          const Locale('es'),
        ),
        contains('## Hoja 1'),
      );
    },
  );

  test('declared workbooks do not guess missing or escaping sheet relationships', () async {
    final document = await parseOfficeDocument(
      _zip({
        'xl/workbook.xml':
            '<workbook xmlns="$_s" xmlns:r="$_r"><sheets><sheet name="Missing" sheetId="1" r:id="missing"/><sheet name="Escape" sheetId="2" r:id="escape"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships xmlns="$_pr"><Relationship Id="escape" Type="$_r/worksheet" Target="../../outside.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml': _sheet('UNLISTED'),
        'outside.xml': _sheet('WRONG TARGET'),
      }),
      'missing.xlsx',
    );
    expect(document.plainText, isEmpty);
    expect(document.csv, isEmpty);
  });
}
