import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

Uint8List _odt(String body, {String styles = '', String? metadata}) {
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
        'xmlns:table="$_table" xmlns:style="$_style">'
        '<office:automatic-styles>$styles</office:automatic-styles>'
        '<office:body><office:text>$body</office:text></office:body>'
        '</office:document-content>',
      ),
    );
  if (metadata != null) zip.addFile('meta.xml', utf8.encode(metadata));
  return zip.close();
}

void main() {
  test(
    'large prose remains compact instead of allocating one run per word',
    () async {
      final text = List.filled(25000, 'word').join(' ');
      final document = await OdtDocumentReader.readBytes(
        _odt('<text:p>$text</text:p>'),
      );
      expect(document.paragraphs.single.text, text);
      expect(document.paragraphs.single.inlines.length, lessThanOrEqualTo(4));
    },
  );

  test('many equal field codes keep independent native ranges', () async {
    final body = StringBuffer('<text:p>');
    for (var i = 0; i < 512; i++) {
      final name = encodeXmlAttribute(
        'ZOTERO_ITEM CSL_CITATION '
        '{"citationID":"copied","citationItems":[{"id":1}],"properties":{}} '
        'RND${i.toRadixString(36).padLeft(10, '0')}',
      );
      body.write(
        '<text:reference-mark-start text:name="$name"/>X'
        '<text:reference-mark-end text:name="$name"/><text:s/>',
      );
    }
    body.write('</text:p>');
    final document = await OdtDocumentReader.readBytes(_odt(body.toString()));
    final fields = WordZotero.fields(document);
    expect(fields.length, 512);
    expect(fields.last.start, 1022);
    expect(
      fields.every((field) => field.cachedText == 'X' && field.canEdit),
      isTrue,
    );
    final reopened = WordDeserializer().read(
      OpcPackage.openBytes(WordSerializer().writeBytes(document)),
    );
    expect(WordZotero.fields(reopened).length, 512);
  });

  test('original unrelated metadata remains verbatim through DOCX saves', () async {
    const metadata =
        '<office:document-meta xmlns:office="$_office" xmlns:meta="$_meta" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<office:meta><dc:title>Research title</dc:title>'
        '<meta:user-defined meta:name="Project">Keep &amp; retain</meta:user-defined>'
        '<meta:user-defined meta:name="Review" meta:value-type="boolean">true</meta:user-defined>'
        '</office:meta></office:document-meta>';
    var document = await OdtDocumentReader.readBytes(
      _odt('<text:p>Research</text:p>', metadata: metadata),
    );
    expect(document.properties.title, 'Research title');
    for (var cycle = 0; cycle < 3; cycle++) {
      final package = OpcPackage.openBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        package.getPart('/customXml/qudsOdtMetadata.xml')!.readText(),
        metadata,
      );
      expect(
        package
            .relationshipsFor('/word/document.xml')
            .items
            .where((relation) => relation.type.endsWith('/customXml'))
            .length,
        1,
      );
      document = WordDeserializer().read(package);
      expect(document.properties.title, 'Research title');
      expect(WordZoteroDocumentData.read(document), isEmpty);
    }
  });

  test('absent office meta owner is an empty optional metadata part', () async {
    final document = await OdtDocumentReader.readBytes(
      _odt(
        '<text:p>Text</text:p>',
        metadata: '<office:document-meta xmlns:office="$_office"/>',
      ),
    );
    expect(document.paragraphs.single.text, 'Text');
  });

  test(
    'generated empty cell paragraphs count against native paragraph limit',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt(
            '<table:table><table:table-row><table:table-cell/></table:table-row></table:table>'
            '<text:p>One authored paragraph</text:p>',
          ),
          limits: const OdfZoteroLimits(maxParagraphs: 1),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  test('native ODT preference conversion accepts only native mark storage', () {
    String data(String type) => jsonEncode({
      'prefs': {'fieldType': type},
      'future': [1, true],
    });
    final native = WordZoteroDocumentData.fromOdt(data('ReferenceMark'));
    expect(jsonDecode(native), {
      'prefs': {'fieldType': 'Field'},
      'future': [1, true],
    });
    for (final type in ['Bookmark', 'Field', 'Http']) {
      expect(
        () => WordZoteroDocumentData.fromOdt(data(type)),
        throwsFormatException,
      );
    }
    expect(
      () => WordZoteroDocumentData.toNative(data('ReferenceMark')),
      throwsFormatException,
    );
    expect(
      () => WordZoteroDocumentData.toHttp(data('ReferenceMark')),
      throwsFormatException,
    );
  });

  test(
    'table width supplies unresolved columns without adding borders',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          '<table:table table:style-name="T"><table:table-row>'
          '<table:table-cell><text:p>A</text:p></table:table-cell>'
          '<table:table-cell><text:p>B</text:p></table:table-cell>'
          '</table:table-row></table:table>',
          styles:
              '<style:style style:name="T" style:family="table">'
              '<style:table-properties style:width="6in"/></style:style>',
        ),
      );
      final table = document.sections.single.blocks.single as WmlTable;
      expect(table.grid, [216, 216]);
      expect(table.rows.single.cells.map((cell) => cell.width), [216, 216]);
      expect(table.properties.borders, isFalse);
      expect(table.properties.cellMargin, 0);
    },
  );

  test('inconsistent explicit table and column widths refuse', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _odt(
          '<table:table table:style-name="T"><table:table-column table:style-name="C"/>'
          '<table:table-row><table:table-cell><text:p>A</text:p></table:table-cell>'
          '</table:table-row></table:table>',
          styles:
              '<style:style style:name="T" style:family="table">'
              '<style:table-properties style:width="6in"/></style:style>'
              '<style:style style:name="C" style:family="table-column">'
              '<style:table-column-properties style:column-width="2in"/></style:style>',
        ),
      ),
      throwsFormatException,
    );
  });

  for (final body in [
    '<table:table>lost<table:table-row><table:table-cell><text:p>A</text:p></table:table-cell></table:table-row></table:table>',
    '<table:table><table:table-row>lost<table:table-cell><text:p>A</text:p></table:table-cell></table:table-row></table:table>',
  ]) {
    test(
      'structural text is never silently discarded: ${body.substring(0, 35)}',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(_odt(body)),
          throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'nested objects in table properties cannot bypass content refusal',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt(
            '<table:table table:style-name="T"><table:table-row>'
            '<table:table-cell><text:p>A</text:p></table:table-cell></table:table-row></table:table>',
            styles:
                '<style:style style:name="T" style:family="table">'
                '<style:table-properties><style:background-image/></style:table-properties></style:style>',
          ),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'ODF-looking archive without mimetype is routed to strict refusal',
    () async {
      final zip = ZipWriter()
        ..addFile('content.xml', utf8.encode('<content/>'));
      final bytes = zip.close();
      expect(OdtDocumentReader.isOdt(bytes), isTrue);
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsFormatException,
      );
    },
  );
}
