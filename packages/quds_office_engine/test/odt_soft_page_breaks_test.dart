import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

Uint8List _fixture(String flag, {String soft = '<text:soft-page-break/>'}) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION '
    '{"citationID":"page-hint","citationItems":[{"id":1}],'
    '"properties":{"plainCitation":"(Source)"}} RND0123456789',
  );
  final zip = ZipWriter();
  zip.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
      'xmlns:style="$_style" xmlns:fo="$_fo">'
      '<office:automatic-styles><style:style style:name="Break" style:family="paragraph">'
      '<style:paragraph-properties fo:break-before="page"/>'
      '</style:style></office:automatic-styles>'
      '<office:body><office:text text:use-soft-page-breaks="${encodeXmlAttribute(flag)}">'
      '<text:p>Before<text:s/>'
      '<text:reference-mark-start text:name="$name"/>(Sou${soft}rce)'
      '<text:reference-mark-end text:name="$name"/>.</text:p>'
      '<text:p text:style-name="Break">Authored next page</text:p>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  final preferences = jsonEncode({
    'dataVersion': 4,
    'style': {'styleID': 'http://www.zotero.org/styles/apa'},
    'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
  });
  zip.addFile(
    'meta.xml',
    utf8.encode(
      '<office:document-meta xmlns:office="$_office" xmlns:meta="$_meta"><office:meta>'
      '<meta:user-defined meta:name="ZOTERO_PREF_1">${encodeXmlText(preferences)}</meta:user-defined>'
      '</office:meta></office:document-meta>',
    ),
  );
  return zip.close();
}

void main() {
  for (final flag in ['true', 'false', '1', '0', '  true  ']) {
    test(
      'soft pagination hint $flag keeps citation offsets and hard breaks',
      () async {
        var document = await OdtDocumentReader.readBytes(_fixture(flag));
        for (var cycle = 0; cycle < 2; cycle++) {
          final field = WordZotero.fields(document).single;
          expect(field.citation!.citationId, 'page-hint');
          expect(field.cachedText, '(Source)');
          expect(field.start, 7);
          expect(field.end, 15);
          expect(document.paragraphs.first.text, 'Before (Source).');
          expect(document.paragraphs.last.properties.pageBreakBefore, isTrue);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final copy = OdtDocumentWriter.writeEditableZoteroBytes(document);
        final content = utf8.decode(
          ZipReader.fromBytes(copy).read('content.xml'),
        );
        expect(content, isNot(contains('soft-page-break')));
        document = await OdtDocumentReader.readBytes(copy);
        expect(WordZotero.fields(document).single.cachedText, '(Source)');
        expect(document.paragraphs.last.properties.pageBreakBefore, isTrue);
      },
    );
  }
  test('true hint with no cached soft breaks remains valid', () async {
    final document = await OdtDocumentReader.readBytes(
      _fixture('true', soft: ''),
    );
    expect(WordZotero.fields(document).single.cachedText, '(Source)');
  });
  for (final flag in ['', 'TRUE', '2', 'yes', '\u00a0true\u00a0']) {
    test('malformed soft-page hint $flag refuses', () async {
      await expectLater(
        OdtDocumentReader.readBytes(_fixture(flag)),
        throwsFormatException,
      );
    });
  }
  for (final soft in [
    '<text:soft-page-break text:style-name="lost"/>',
    '<text:soft-page-break>lost</text:soft-page-break>',
  ]) {
    test('soft-page markup cannot hide content: $soft', () async {
      await expectLater(
        OdtDocumentReader.readBytes(_fixture('true', soft: soft)),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
      );
    });
  }
}
