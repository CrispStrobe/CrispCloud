// Exercise cached ODF fields and conservative fallback through the actual host
// import, menu, writer and preview path. Storage/destination are test boundaries.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';

const _fields = <String, (String, String)>{
  'page-number': (' PAGE ', '7'),
  'page-count': (' NUMPAGES ', '12'),
  'date': (r' DATE \@ "yyyy-MM-dd" ', '2026-11-17'),
  'time': (r' TIME \@ "HH:mm" ', '09:30'),
  'title': (' TITLE ', 'Quarterly & review'),
};

String _field(
  String instruction,
  String cache, {
  bool styled = true,
  bool locked = false,
  bool linked = false,
}) =>
    '''
<w:r><w:fldChar w:fldCharType="begin"${locked ? ' w:fldLock="true"' : ''}/></w:r>
<w:r><w:instrText xml:space="preserve">${xml.XmlText(instruction).toXmlString()}</w:instrText></w:r>
<w:r><w:fldChar w:fldCharType="separate"/></w:r>
${linked ? '<w:hyperlink w:anchor="field-target">' : ''}
<w:r>${styled ? '<w:rPr><w:b/><w:color w:val="1255AA"/></w:rPr>' : ''}<w:t xml:space="preserve">${xml.XmlText(cache).toXmlString()}</w:t></w:r>
${linked ? '</w:hyperlink>' : ''}
<w:r><w:fldChar w:fldCharType="end"/></w:r>''';

Uint8List _source() {
  // The source field delimiters and values are authored directly as OOXML.
  // No serializer from the Office implementation creates this input.
  final native = _fields.entries
      .map(
        (field) => _field(
          field.value.$1,
          field.value.$2,
          styled: field.key != 'page-count',
        ),
      )
      .join('<w:r><w:t xml:space="preserve"> | </w:t></w:r>');
  final parts = <String, String>{
    '[Content_Types].xml': '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''',
    '_rels/.rels': '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="office" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''',
    'word/document.xml':
        '''
<w:document xmlns:w="$_w"><w:body>
<w:p><w:r><w:t xml:space="preserve">Outside start </w:t></w:r>
$native
<w:r><w:t xml:space="preserve"> Outside end</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Styled count </w:t></w:r>
${_field(' NUMPAGES ', '91')}
<w:r><w:t xml:space="preserve"> following styled count</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Locked page </w:t></w:r>
${_field(' PAGE ', '23', locked: true)}
<w:r><w:t xml:space="preserve"> stays authored</w:t></w:r></w:p>
<w:p><w:bookmarkStart w:id="77" w:name="field-target"/><w:r><w:t xml:space="preserve">Linked count </w:t></w:r>
${_field(' NUMPAGES ', '31', linked: true)}
<w:r><w:t xml:space="preserve"> stays linked</w:t></w:r><w:bookmarkEnd w:id="77"/></w:p>
<w:p>
<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>
<w:r><w:t xml:space="preserve">Nested outer </w:t></w:r>
<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> NUMPAGES </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>22</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
<w:r><w:t xml:space="preserve"> tail</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
<w:r><w:t xml:space="preserve"> Ordinary after nested</w:t></w:r></w:p>
<w:p>
<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> TITLE </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>
<w:r><w:t xml:space="preserve">Malformed cache kept  </w:t></w:r><w:r><w:t>ordinary tail</w:t></w:r></w:p>
<w:p><w:r><w:t>Following paragraph survives exactly.</w:t></w:r></w:p>
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr>
</w:body></w:document>''',
  };
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _expectBoldColor(xml.XmlDocument content, xml.XmlElement wrapper) {
  expect(wrapper.name.local, 'span');
  expect(wrapper.name.namespaceUri, _text);
  final name = wrapper.getAttribute('style-name', namespace: _text);
  expect(name, isNotNull);
  final properties = content
      .findAllElements('style', namespace: _style)
      .singleWhere(
        (style) => style.getAttribute('name', namespace: _style) == name,
      )
      .getElement('text-properties', namespace: _style)!;
  expect(properties.getAttribute('font-weight', namespace: _fo), 'bold');
  expect(properties.getAttribute('color', namespace: _fo), '#1255aa');
}

void main() {
  testWidgets(
    'ODT menu retains one cached display and unsafe-field fallback content',
    (tester) async {
      await tester.runAsync(() async {
        final original = _source();
        Uint8List? exported;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'fields.docx',
          initialBytes: original,
          copyExporter: (bytes, name, title, {initialDirectory}) async {
            expect(name, 'fields.odt');
            expect(title, 'Export as ODT');
            exported = bytes;
            return OfficeCopyOutcome.savedCopy;
          },
        );
        try {
          host.container
              .read(officeEditorMenuProvider)!
              .perform(OfficeEditorAction.exportOdt);
          await officePumpUntil(
            tester,
            () => exported != null && !host.ribbon.saving,
          );
          final package = ZipDecoder().decodeBytes(exported!);
          final content = xml.XmlDocument.parse(
            utf8.decode(package.findFile('content.xml')!.content),
          );
          for (final field in _fields.entries.where(
            (field) => field.key == 'page-number' || field.key == 'page-count',
          )) {
            final node = content
                .findAllElements(field.key, namespace: _text)
                .singleWhere((node) => node.innerText == field.value.$2);
            // Admitted PAGE/NUMPAGES fields keep exactly one authored display.
            // Readers may refresh that live value after opening the copy.
            expect(node.innerText, field.value.$2);
            expect(node.childElements, isEmpty);
            if (field.key == 'page-number') {
              _expectBoldColor(content, node.parentElement!);
            }
          }
          expect(
            content.findAllElements('page-number', namespace: _text),
            hasLength(1),
          );
          expect(
            content.findAllElements('page-count', namespace: _text),
            hasLength(3),
          );
          final styledCount = content
              .findAllElements('page-count', namespace: _text)
              .singleWhere((node) => node.innerText == '91');
          expect(styledCount.childElements, isEmpty);
          _expectBoldColor(content, styledCount.parentElement!);
          final linkedCount = content
              .findAllElements('page-count', namespace: _text)
              .singleWhere((node) => node.innerText == '31');
          _expectBoldColor(content, linkedCount.parentElement!);
          final link = linkedCount.parentElement!.parentElement!;
          expect(link.name.local, 'a');
          expect(link.name.namespaceUri, _text);
          expect(link.getAttribute('href', namespace: _xlink), '#field-target');
          expect(link.innerText, '31');
          for (final name in ['date', 'time', 'title']) {
            expect(content.findAllElements(name, namespace: _text), isEmpty);
            _expectBoldColor(
              content,
              content
                  .findAllElements('span', namespace: _text)
                  .singleWhere((span) => span.innerText == _fields[name]!.$2),
            );
          }
          _expectBoldColor(
            content,
            content
                .findAllElements('span', namespace: _text)
                .singleWhere((span) => span.innerText == '23'),
          );
          final preview = await parseOfficeDocument(exported!, 'fields.odt');
          expect(preview.fallback, isNull);
          expect(
            preview.plainText,
            contains(
              'Outside start 7 | 12 | 2026-11-17 | 09:30 | '
              'Quarterly & review Outside end',
            ),
          );
          expect(
            preview.plainText,
            contains('Styled count 91 following styled count'),
          );
          expect(preview.markdown, contains('91'));
          expect(preview.plainText, contains('Locked page 23 stays authored'));
          expect(
            preview.markdown,
            contains('Locked page **23** stays authored'),
          );
          // The host's searchable text keeps link destinations while removing
          // emphasis; preserve that existing preview contract for field text.
          expect(
            preview.plainText,
            contains('Linked count [31](#field-target) stays linked'),
          );
          expect(
            preview.markdown,
            contains('Linked count [**31**](#field-target) stays linked'),
          );
          for (final value in [
            'Nested outer 22 tail Ordinary after nested',
            'Malformed cache kept  ordinary tail',
            'Following paragraph survives exactly.',
          ]) {
            expect(preview.plainText, contains(value));
            expect(preview.markdown, contains(value));
          }
          for (final instruction in ['NUMPAGES', 'yyyy-MM-dd', 'HH:mm']) {
            expect(preview.plainText, isNot(contains(instruction)));
          }
          expect(host.controller.isDirty, isFalse);
          expect(host.ribbon.title, 'fields.docx');
          expect(host.savedBytes, orderedEquals(original));
          expect(host.cloud.uploadAttempts, 0);
          expect(host.cloud.writes, isEmpty);
        } finally {
          await host.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
