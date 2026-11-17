import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';

Uint8List _package(String content, {String? styles}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(content)));
  if (styles != null) {
    archive.addFile(ArchiveFile.bytes('styles.xml', utf8.encode(styles)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
    'ODT preview uses namespace identity for body, styles, lists and notes',
    () async {
      const xml =
          '''
<o:document-content xmlns:o="$_office" xmlns:t="$_text"
 xmlns:tbl="$_table" xmlns:s="$_style" xmlns:f="$_fo"
 xmlns:link="$_xlink" xmlns:foreign="urn:foreign">
 <o:automatic-styles>
  <s:style s:name="Bold" s:family="text"><s:text-properties f:font-weight="bold"/></s:style>
  <t:list-style s:name="Numbers"><t:list-level-style-number t:level="1" s:num-format="1"/></t:list-style>
 </o:automatic-styles>
 <o:body><o:text>
  <t:h t:outline-level="2">Grüße</t:h>
  <t:p><t:span t:style-name="Bold">Fett</t:span><t:s t:c="3"/>Danach<![CDATA[ & sichtbar]]></t:p>
  <t:p><t:a link:href="https://example.invalid/document">Link</t:a></t:p>
  <t:list t:style-name="Numbers"><t:list-item><t:p>Erstens</t:p></t:list-item></t:list>
  <tbl:table><tbl:table-row><tbl:table-cell><t:p>Zelle</t:p></tbl:table-cell></tbl:table-row></tbl:table>
  <t:p>Referenz<t:note t:id="n1" t:note-class="footnote"><t:note-citation>1</t:note-citation><t:note-body><t:p>Fußnote</t:p></t:note-body></t:note></t:p>
  <foreign:p><t:p>Foreign wrapper text</t:p></foreign:p>
 </o:text></o:body>
</o:document-content>''';
      const styles =
          '''
<o:document-styles xmlns:o="$_office" xmlns:t="$_text" xmlns:s="$_style">
 <o:master-styles><s:master-page s:name="Standard">
  <s:header><t:p>Kopfzeile</t:p></s:header>
  <s:footer><t:p>Fußzeile</t:p></s:footer>
 </s:master-page></o:master-styles>
</o:document-styles>''';
      final document = await parseOfficeDocument(
        _package(xml, styles: styles),
        'aliased.odt',
      );
      expect(document.fallback, isNull);
      expect(document.markdown, contains('## Grüße'));
      expect(document.markdown, contains('**Fett**   Danach & sichtbar'));
      expect(
        document.markdown,
        contains('[Link](https://example.invalid/document)'),
      );
      expect(document.markdown, contains('1. Erstens'));
      expect(document.markdown, contains('| Zelle |'));
      expect(document.markdown, contains('Referenz[1]'));
      expect(document.markdown, contains('1. Fußnote'));
      expect(document.markdown, contains('Foreign wrapper text'));
      expect(document.markdown, contains('> **Header:** Kopfzeile'));
      expect(document.markdown, contains('> **Footer:** Fußzeile'));
      expect(document.rawXml, '<!-- content.xml -->\n$xml');
    },
  );

  for (final historyOnly in [false, true]) {
    test(
      'ODT preview excludes stored revisions (history only: $historyOnly)',
      () async {
        final visible = historyOnly
            ? ''
            : '<text:p>Before<text:change text:change-id="d1"/>'
                  '<text:change-start text:change-id="i1"/> inserted'
                  '<text:change-end text:change-id="i1"/> after</text:p>'
                  '<foreign:tracked-changes><text:p>Foreign visible</text:p>'
                  '</foreign:tracked-changes>';
        final xml =
            '''
<office:document-content xmlns:office="$_office" xmlns:text="$_text"
 xmlns:t="$_text" xmlns:table="$_table" xmlns:foreign="urn:foreign"
 xmlns:dc="http://purl.org/dc/elements/1.1/">
 <office:body><office:text>
  <t:tracked-changes><t:changed-region t:id="d1"><t:deletion>
   <office:change-info><dc:creator>HIDDEN AUTHOR</dc:creator>
    <dc:date>2026-11-17T00:00:00</dc:date><text:p>HIDDEN COMMENT</text:p>
   </office:change-info>
   <text:p>HIDDEN DELETED TEXT</text:p>
   <table:table><table:table-row><table:table-cell><text:p>HIDDEN CELL</text:p></table:table-cell></table:table-row></table:table>
  </t:deletion></t:changed-region>
  <t:changed-region t:id="i1"><t:insertion><office:change-info>
   <dc:creator>HIDDEN INSERT AUTHOR</dc:creator><dc:date>2026-11-17T00:00:00</dc:date>
  </office:change-info></t:insertion></t:changed-region></t:tracked-changes>
  $visible
 </office:text></office:body>
</office:document-content>''';
        final document = await parseOfficeDocument(
          _package(xml),
          'revisions.odt',
        );
        expect(document.fallback, isNull);
        expect(document.markdown, isNot(contains('HIDDEN')));
        expect(document.plainText, isNot(contains('HIDDEN')));
        if (historyOnly) {
          expect(document.markdown, isEmpty);
          expect(document.plainText, isEmpty);
        } else {
          expect(document.markdown, 'Before inserted after\n\nForeign visible');
        }
        expect(document.rawXml, '<!-- content.xml -->\n$xml');
      },
    );
  }
}
