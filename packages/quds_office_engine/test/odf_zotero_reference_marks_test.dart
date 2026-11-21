import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

String _citation({String suffix = '0123456789', String id = 'c1'}) =>
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(<String, Object?>{
      'citationID': id,
      'citationItems': [
        {
          'id': 'https://zotero.org/users/1/items/ABCDEFGH',
          'locator': '12–14',
          'label': 'page',
          'prefix': 'see ',
          'suffix': ' RNDabcdefghij',
          'suppress-author': true,
          'itemData': {'title': 'العربية 😀 & <quoted>', 'type': 'book'},
        },
        {'id': 2, 'locator': '4', 'label': 'chapter'},
      ],
      'properties': {'plainCitation': '(Example)', 'noteIndex': 0},
      'extension': {
        'keep': [true, null, 3],
      },
    })} RND$suffix';

String _bibliography() =>
    'ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]}'
    ' CSL_BIBLIOGRAPHY RNDabcdefghij';

String _mark(String name, String contents) {
  final escaped = encodeXmlAttribute(name);
  return '<text:reference-mark-start text:name="$escaped"/>'
      '$contents<text:reference-mark-end text:name="$escaped"/>';
}

String _content(String body) =>
    '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
    'xmlns:foreign="urn:foreign">'
    '<office:body><office:text>$body</office:text></office:body>'
    '</office:document-content>';

Uint8List _odt(String body, {String? metadata, String? styles}) =>
    _zip(_content(body), metadata: metadata, styles: styles);

Uint8List _zip(
  String content, {
  String? metadata,
  String? styles,
  String? mimetype = 'application/vnd.oasis.opendocument.text',
  bool duplicateContent = false,
}) {
  final zip = ZipWriter();
  if (mimetype != null) {
    zip.addFile('mimetype', utf8.encode(mimetype), store: true);
  }
  zip.addFile('content.xml', utf8.encode(content));
  if (duplicateContent) zip.addFile('content.xml', utf8.encode(content));
  if (metadata != null) zip.addFile('meta.xml', utf8.encode(metadata));
  if (styles != null) zip.addFile('styles.xml', utf8.encode(styles));
  zip.addFile('unrelated.bin', [0, 1, 255]);
  return zip.close();
}

void main() {
  test(
    'unmodeled ODF block owners do not become ordinary body candidates',
    () async {
      final name = _citation();
      for (final owner in ['text:alphabetical-index', 'office:forms']) {
        final result = await OdfZotero.inspect(
          _odt('<$owner><text:p>${_mark(name, 'retained')}</text:p></$owner>'),
        );
        expect(result.fields.single.cachedText, 'retained');
        expect(result.fields.single.isImportCandidate, isFalse);
        expect(
          result.fields.single.starts.single.owners.last.localName,
          owner.split(':').last,
        );
      }
    },
  );

  test(
    'duplicate qualified attributes reject before selecting a native name',
    () async {
      final name = encodeXmlAttribute(_citation());
      await expectLater(
        OdfZotero.inspect(
          _odt(
            '<text:p><text:reference-mark-start text:name="ordinary" text:name="$name"/>'
            'Text<text:reference-mark-end text:name="$name"/></text:p>',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'canonical multi-item citation retains exact identity and metadata',
    () async {
      final name = _citation();
      final result = await OdfZotero.inspect(
        _odt('<text:p>Before ${_mark(name, '(Example)')} after</text:p>'),
      );
      final field = result.fields.single;
      expect(field.name, name);
      expect(field.logicalCode, name.substring(7, name.length - 14));
      expect(field.randomSuffix, '0123456789');
      expect(field.kind, ZoteroFieldKind.citation);
      expect(field.storage, OdfZoteroStorage.referenceMark);
      expect(field.cachedText, '(Example)');
      expect(field.isValid, isTrue);
      expect(field.isImportCandidate, isTrue);
      expect(field.issues, isEmpty);
      expect(field.starts.single.offset, 7);
      expect(field.ends.single.offset, 16);
      expect(field.starts.single.paragraphIndex, 0);
      expect(field.starts.single.story, OdfZoteroStory.body);
      expect(field.starts.single.part, 'content.xml');
      final items = field.metadata!['citationItems']! as List<Object?>;
      final item = items.first! as Map<String, Object?>;
      expect(item['suffix'], ' RNDabcdefghij');
      expect(item['locator'], '12–14');
      expect(item['suppress-author'], true);
      expect(field.metadata!['extension'], {
        'keep': [true, null, 3],
      });
      expect(() => field.metadata!['extension'] = null, throwsUnsupportedError);
      expect(() => items.clear(), throwsUnsupportedError);
      expect(() => result.fields.clear(), throwsUnsupportedError);
      expect(() => field.starts.single.owners.clear(), throwsUnsupportedError);
      expect(result.toJson()['editable'], false);
    },
  );

  test(
    'identical text and payload with distinct random suffixes stays distinct',
    () async {
      final first = _citation();
      final second = _citation(suffix: 'abcdefghij');
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p>${_mark(first, 'same')} / ${_mark(second, 'same')}</text:p>',
        ),
      );
      expect(result.fields.map((field) => field.cachedText), ['same', 'same']);
      expect(result.fields.map((field) => field.starts.single.offset), [0, 7]);
      expect(result.fields.map((field) => field.ends.single.offset), [4, 11]);
      expect(result.fields.every((field) => field.isImportCandidate), isTrue);
      expect(
        result.fields.first.starts.single.path,
        isNot(result.fields.last.starts.single.path),
      );
    },
  );

  test(
    'namespace aliases preserve physical identity and text offsets',
    () async {
      final original = _content('<text:p>${_mark(_citation(), 'A')}</text:p>');
      final renamed = original
          .replaceAll('office:', 'o:')
          .replaceAll('xmlns:office=', 'xmlns:o=')
          .replaceAll('text:', 't:')
          .replaceAll('xmlns:text=', 'xmlns:t=');
      // Prefix changes must not rewrite the namespace URI itself.
      final restored = renamed
          .replaceAll('xmlns:t:1.0', 'xmlns:text:1.0')
          .replaceAll('xmlns:o:1.0', 'xmlns:office:1.0');
      final a = await OdfZotero.inspect(_zip(original));
      final b = await OdfZotero.inspect(_zip(restored));
      expect(b.toJson(), a.toJson());
    },
  );

  test(
    'ordinary marks and foreign namespace lookalikes never become fields',
    () async {
      final name = encodeXmlAttribute(_citation());
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p><text:reference-mark-start text:name="ordinary"/>ordinary'
          '<text:reference-mark-end text:name="ordinary"/>'
          '<foreign:reference-mark-start text:name="$name"/>foreign'
          '<foreign:reference-mark-end text:name="$name"/>'
          '<text:reference-mark-start foreign:name="$name"/>attribute'
          '<text:reference-mark-end foreign:name="$name"/></text:p>'
          '<text:section text:name="ordinary"><text:p>Normal</text:p></text:section>',
        ),
      );
      expect(result.fields, isEmpty);
    },
  );

  test(
    'reference-mark bibliography retains its multiple paragraph boundaries',
    () async {
      final name = encodeXmlAttribute(_bibliography());
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p>before <text:reference-mark-start text:name="$name"/>First</text:p>'
          '<text:p>Second<text:reference-mark-end text:name="$name"/> after</text:p>',
        ),
      );
      final field = result.fields.single;
      expect(field.kind, ZoteroFieldKind.bibliography);
      expect(field.isImportCandidate, isTrue);
      expect(field.cachedText, 'First\nSecond');
      expect(field.ranges.map((range) => range.start), [7, 0]);
      expect(field.ranges.map((range) => range.end), [12, 6]);
    },
  );

  test(
    'section bibliography retains original block endpoints and paragraphs',
    () async {
      final name = encodeXmlAttribute(_bibliography());
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p>Before</text:p><text:section text:name="$name">'
          '<text:p>First <text:span>entry</text:span></text:p><text:p/>'
          '<text:p>Second entry</text:p></text:section><text:p>After</text:p>',
        ),
      );
      final field = result.fields.single;
      expect(field.storage, OdfZoteroStorage.section);
      expect(field.isImportCandidate, isTrue);
      expect(field.starts.single.paragraphPath, isNull);
      expect(field.starts.single.offset, isNull);
      expect(field.cachedText, 'First entry\n\nSecond entry');
      expect(field.ranges.map((range) => range.location.paragraphIndex), [
        1,
        2,
        3,
      ]);
      expect(field.ranges.first.location.owners.last.localName, 'section');
    },
  );

  test(
    'raw metadata, unrelated ZIP parts and source bytes remain unchanged',
    () async {
      const data = ' {"prefs":{"fieldType":"ReferenceMark"},"unknown":[1,2]} ';
      final metadata =
          '<office:document-meta xmlns:office="$_office" xmlns:m="$_meta">'
          '<office:meta><m:user-defined m:name="Unrelated">keep</m:user-defined>'
          '<m:user-defined m:name="ZOTERO_PREF_1">${encodeXmlText(data)}</m:user-defined>'
          '</office:meta></office:document-meta>';
      final bytes = _odt(
        '<text:p>${_mark(_citation(), 'Text')}</text:p>',
        metadata: metadata,
      );
      final before = Uint8List.fromList(bytes);
      final first = await OdfZotero.inspect(bytes);
      final second = await OdfZotero.inspect(bytes);
      expect(bytes, before);
      expect(first.toJson(), second.toJson());
      expect(first.preferences.rawData, data);
      expect(first.preferences.properties.first.value, 'keep');
      expect(ZipReader.fromBytes(bytes).read('unrelated.bin'), [0, 1, 255]);
      expect(
        utf8.decode(ZipReader.fromBytes(bytes).read('meta.xml')),
        metadata,
      );
      expect(() => WordZoteroDocumentData.toHttp(data), throwsFormatException);
    },
  );

  test(
    'styles.xml header and footer marks are detected as unsupported stories',
    () async {
      final styles =
          '<office:document-styles xmlns:office="$_office" xmlns:text="$_text" '
          'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0">'
          '<office:master-styles><style:master-page style:name="Standard">'
          '<style:header><text:p>${_mark(_citation(), 'Header')}</text:p></style:header>'
          '<style:footer><text:p>${_mark(_citation(suffix: 'ABCDEFGHIJ'), 'Footer')}</text:p>'
          '</style:footer></style:master-page></office:master-styles></office:document-styles>';
      final result = await OdfZotero.inspect(
        _odt('<text:p>Body</text:p>', styles: styles),
      );
      expect(result.fields.map((field) => field.starts.single.story), [
        OdfZoteroStory.header,
        OdfZoteroStory.footer,
      ]);
      expect(result.fields.every((field) => !field.isImportCandidate), isTrue);
      expect(result.fields.map((field) => field.starts.single.part), [
        'styles.xml',
        'styles.xml',
      ]);
    },
  );

  test(
    'Unicode uses UTF16 positions, including spans and explicit whitespace',
    () async {
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p>😀 '
          '${_mark(_citation(), '<text:span>العربية</text:span><text:s text:c="2"/>'
          '<text:tab/>😀<text:line-break/>X')}'
          '</text:p>',
        ),
      );
      final field = result.fields.single;
      expect(field.starts.single.offset, 3);
      expect(field.cachedText, 'العربية  \t😀\nX');
      expect(field.ends.single.offset, 3 + field.cachedText.length);
    },
  );

  final whitespaceCases =
      <
        ({
          String prefix,
          String inside,
          String suffix,
          String expected,
          int start,
          int end,
        })
      >[
        (
          prefix: '  ',
          inside: '  A  ',
          suffix: '  ',
          expected: 'A',
          start: 0,
          end: 1,
        ),
        (
          prefix: 'X  ',
          inside: 'A',
          suffix: '',
          expected: 'A',
          start: 2,
          end: 3,
        ),
        (
          prefix: 'X',
          inside: ' A ',
          suffix: 'Y',
          expected: ' A ',
          start: 1,
          end: 4,
        ),
        (
          prefix: '',
          inside: 'A ',
          suffix: ' Y',
          expected: 'A ',
          start: 0,
          end: 2,
        ),
        (prefix: 'X ', inside: '', suffix: 'Y', expected: '', start: 2, end: 2),
        (prefix: 'X ', inside: '', suffix: '', expected: '', start: 1, end: 1),
        (
          prefix: '',
          inside: '<text:s text:c="2"/>A<text:s/>',
          suffix: '',
          expected: '  A ',
          start: 0,
          end: 4,
        ),
        (
          prefix: 'X ',
          inside: '<text:s text:c="0"/>A',
          suffix: '',
          expected: 'A',
          start: 2,
          end: 3,
        ),
        (
          prefix: '',
          inside: 'co<text:span>operate</text:span>',
          suffix: '',
          expected: 'cooperate',
          start: 0,
          end: 9,
        ),
      ];
  for (var index = 0; index < whitespaceCases.length; index++) {
    final sample = whitespaceCases[index];
    test('positioned ODF whitespace case $index', () async {
      final result = await OdfZotero.inspect(
        _odt(
          '<text:p>${sample.prefix}'
          '${_mark(_citation(), sample.inside)}${sample.suffix}</text:p>',
        ),
      );
      final field = result.fields.single;
      expect(field.cachedText, sample.expected);
      expect(field.starts.single.offset, sample.start);
      expect(field.ends.single.offset, sample.end);
    });
  }

  for (final code in [
    'ITEM CSL_CITATION {"citationItems":[{"id":1}]}',
    'ITEM CSL_CITATION {"citationID":"x","citationItems":[]}',
    'ITEM CSL_CITATION {"citationID":"x","citationItems":[{}]}',
    'ITEM CSL_CITATION {"citationID":"x","citationItems":[{"id":1}]} trailing',
    'ITEM CSL_CITATION {broken}',
    'BIBL {} CSL_CITATION',
  ]) {
    test(
      'malformed metadata remains a detected invalid field: $code',
      () async {
        final result = await OdfZotero.inspect(
          _odt(
            '<text:p>${_mark('ZOTERO_$code RND0123456789', 'cached')}</text:p>',
          ),
        );
        expect(result.fields.single.isValid, isFalse);
        expect(result.fields.single.cachedText, 'cached');
        expect(
          result.fields.single.issues.map((issue) => issue.code),
          contains(OdfZoteroIssueCode.invalidMetadata),
        );
      },
    );
  }

  for (final name in [
    'ZOTERO_ITEM CSL_CITATION {} RNDshort',
    'ZOTERO_ITEM CSL_CITATION {} RND0123456789 trailing',
    'ZOTERO_ITEM CSL_CITATION {}123456',
    'ZOTERO_TEMP RND0123456789',
    ' CSL_CITATION {}abcdef',
    ' ADDIN ZOTERO_ITEM CSL_CITATION {} RND0123456789',
    'embedded ZOTERO_ITEM CSL_CITATION {} RND0123456789',
  ]) {
    test('unqualified native name is detected: $name', () async {
      final result = await OdfZotero.inspect(
        _odt('<text:p>${_mark(name, 'cached')}</text:p>'),
      );
      expect(result.fields.single.name, name);
      expect(result.fields.single.isValid, isFalse);
      expect(result.fields.single.isImportCandidate, isFalse);
      expect(result.fields.single.issues, isNotEmpty);
    });
  }

  test(
    'non-ODT, missing mimetype, duplicate ZIP members and malformed XML fail',
    () async {
      for (final bytes in [
        Uint8List(0),
        _zip(_content(''), mimetype: null),
        _zip(
          _content(''),
          mimetype: 'application/vnd.oasis.opendocument.spreadsheet',
        ),
        _zip(_content(''), duplicateContent: true),
        _zip('<broken>'),
        _zip('<!DOCTYPE x><x/>'),
        _zip(_content('').replaceAll('</office:body>', '</foreign:body>')),
      ]) {
        await expectLater(OdfZotero.inspect(bytes), throwsA(isA<Exception>()));
      }
    },
  );

  test(
    'missing, duplicate and foreign body ownership rejects the package',
    () async {
      for (final body in [
        '',
        '<office:body/>',
        '<office:body><office:text/><office:text/></office:body>',
        '<office:body><office:text/></office:body><office:body><office:text/></office:body>',
        '<office:body><foreign:text xmlns:foreign="urn:foreign"/></office:body>',
      ]) {
        await expectLater(
          OdfZotero.inspect(
            _zip(
              '<office:document-content xmlns:office="$_office">$body</office:document-content>',
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'resource ceilings fail the whole inventory without partial fields',
    () async {
      final bytes = _odt(
        '<text:p>${_mark(_citation(), 'A')}</text:p>'
        '<text:p>${_mark(_citation(suffix: 'abcdefghij'), 'B')}</text:p>',
      );
      for (final limits in [
        const OdfZoteroLimits(maxArchiveBytes: 16),
        const OdfZoteroLimits(maxZipEntries: 1),
        const OdfZoteroLimits(maxPartBytes: 16),
        const OdfZoteroLimits(maxTotalXmlBytes: 16),
        const OdfZoteroLimits(maxXmlDepth: 2),
        const OdfZoteroLimits(maxXmlElements: 2),
        const OdfZoteroLimits(maxFields: 1),
        const OdfZoteroLimits(maxParagraphs: 1),
        const OdfZoteroLimits(maxNameLength: 16),
        const OdfZoteroLimits(maxTextBytes: 1),
      ]) {
        await expectLater(
          OdfZotero.inspect(bytes, limits: limits),
          throwsA(isA<Exception>()),
        );
      }
      await expectLater(
        OdfZotero.inspect(bytes, limits: const OdfZoteroLimits(maxFields: 0)),
        throwsArgumentError,
      );
    },
  );

  test(
    'whitespace expansion is bounded before allocating repeated spaces',
    () async {
      await expectLater(
        OdfZotero.inspect(
          _odt(
            '<text:p>'
            '${_mark(_citation(), '<text:s text:c="9999999999999999999999999"/>')}'
            '</text:p>',
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        OdfZotero.inspect(_odt('<text:p><text:s text:c="-1"/></text:p>')),
        throwsFormatException,
      );
    },
  );

  test(
    'ordinary Quds ODT export still contains no active Zotero fields',
    () async {
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WordZotero.bibliography(
                text: 'Cached bibliography',
                metadata: {'uncited': <Object?>[]},
              ),
            ],
          ),
        ],
      );
      final bytes = OdtDocumentWriter.writeBytes(document);
      final result = await OdfZotero.inspect(bytes);
      expect(result.fields, isEmpty);
      expect(
        OfficeTextExtractor.extract(bytes, name: 'output.odt').plainString,
        contains('Cached bibliography'),
      );
    },
  );
}
