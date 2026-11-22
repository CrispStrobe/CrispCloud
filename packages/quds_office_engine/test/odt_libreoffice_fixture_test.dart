import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// The ODT is untouched output of the recorded LibreOfficeDev converter.
// Only the explicitly synthetic Zotero case injects fields/preferences.
// Neither case claims acceptance by an installed Zotero plugin.
const _fixture = 'test/fixtures/zotero/odt/native-prose.odt';
const _fixtureSha256 =
    '9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd';
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _firstParagraph = 'Research bold and italic prose.';
const _prefix = 'Second paragraph ';
const _cache = 'العربية 😀';
const _secondParagraph = '$_prefix$_cache.';
const _bibliographyData = <String, Object?>{
  'uncited': <Object?>[],
  'omitted': <Object?>[],
  'custom': <Object?>[],
  'futureBibliography': <String, Object?>{'retain': true},
};
const _citationData = <String, Object?>{
  'citationID': 'libreoffice-style-synthetic',
  'citationItems': <Object?>[
    <String, Object?>{
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': <Object?>['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '12',
      'label': 'page',
      'prefix': 'see ',
      'itemData': <String, Object?>{
        'id': 17,
        'type': 'book',
        'title': 'Source العربية 😀',
        'futureItemData': <Object?>[true, null, 7],
      },
      'futureItem': 'preserve item extension',
    },
  ],
  'properties': <String, Object?>{
    'plainCitation': _cache,
    'noteIndex': 0,
    'futureProperty': <String, Object?>{'preserve': true},
  },
  'futureRoot': <Object?>['preserve', 9],
};

Uint8List _nativeBytes() {
  final bytes = File(_fixture).readAsBytesSync();
  expect(sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

String _replaceOnce(String input, String from, String to) {
  expect(from.allMatches(input), hasLength(1), reason: from);
  return input.replaceFirst(from, to);
}

Uint8List _rewriteNative({
  String Function(String)? content,
  String Function(String)? styles,
  String Function(String)? metadata,
}) {
  final zip = ZipReader.fromBytes(_nativeBytes());
  final writer = ZipWriter();
  for (final entry in zip.entries) {
    var data = zip.read(entry.fileName);
    final transform = switch (entry.fileName) {
      'content.xml' => content,
      'styles.xml' => styles,
      'meta.xml' => metadata,
      _ => null,
    };
    if (transform != null) data = utf8.encode(transform(utf8.decode(data)));
    writer.addFile(
      entry.fileName,
      data,
      store: entry.compressionMethod == zipMethodStore,
    );
  }
  return writer.close();
}

String _mark(String name, String contents) =>
    '<text:reference-mark-start text:name="${encodeXmlAttribute(name)}"/>'
    '$contents'
    '<text:reference-mark-end text:name="${encodeXmlAttribute(name)}"/>';

String _preferenceProperties() {
  final data = jsonEncode(<String, Object?>{
    'dataVersion': 4,
    'style': <String, Object?>{
      'styleID': 'http://www.zotero.org/styles/apa',
      'locale': 'de-DE',
    },
    'prefs': <String, Object?>{'fieldType': 'ReferenceMark', 'noteType': 0},
    'futurePreferences': <String, Object?>{'retain': 'source settings'},
  });
  final result = StringBuffer();
  for (var start = 0, index = 1; start < data.length; index++, start += 255) {
    final end = (start + 255).clamp(0, data.length);
    result.write(
      '<meta:user-defined meta:name="ZOTERO_PREF_$index">'
      '${encodeXmlText(data.substring(start, end))}</meta:user-defined>',
    );
  }
  return result.toString();
}

Uint8List _syntheticZoteroVariant() {
  final citationName =
      'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citationData)} RND0123456789';
  final bibliographyName =
      'ZOTERO_BIBL ${jsonEncode(_bibliographyData)}'
      ' CSL_BIBLIOGRAPHY RNDabcdefghij';
  final bytes = _rewriteNative(
    content: (xml) => _replaceOnce(
      _replaceOnce(
        xml,
        _secondParagraph,
        '$_prefix${_mark(citationName, _cache)}.',
      ),
      '</office:text>',
      '<text:section text:name="${encodeXmlAttribute(bibliographyName)}">'
          '<text:p text:style-name="P1">First '
          '<text:span text:style-name="T3">Book</text:span>.</text:p>'
          '<text:p text:style-name="P1">Second '
          '<text:span text:style-name="T2">Book</text:span>.</text:p>'
          '</text:section></office:text>',
    ),
    metadata: (xml) => _replaceOnce(
      xml,
      '</office:meta>',
      '${_preferenceProperties()}</office:meta>',
    ),
  );
  final original = ZipReader.fromBytes(_nativeBytes());
  final changed = ZipReader.fromBytes(bytes);
  expect(changed.read('styles.xml'), original.read('styles.xml'));
  final originalContent = utf8.decode(original.read('content.xml'));
  final changedContent = utf8.decode(changed.read('content.xml'));
  expect(
    changedContent.substring(0, changedContent.indexOf('<office:body>')),
    originalContent.substring(0, originalContent.indexOf('<office:body>')),
  );
  for (final name in original.fileNames) {
    if (name != 'content.xml' && name != 'meta.xml') {
      expect(changed.read(name), original.read(name), reason: name);
    }
  }
  return bytes;
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void _expectTextProperties(
  WmlParagraph paragraph,
  String text,
  void Function(WmlRunProps) check,
) {
  final start = paragraph.text.indexOf(text);
  expect(start, greaterThanOrEqualTo(0), reason: text);
  final end = start + text.length;
  var offset = 0;
  var covered = 0;
  for (final run in paragraph.inlines.whereType<WmlRun>()) {
    final runEnd = offset + run.text.length;
    if (offset < end && runEnd > start) {
      check(run.properties);
      covered += runEnd.clamp(start, end) - offset.clamp(start, end);
    }
    offset = runEnd;
  }
  expect(covered, text.length, reason: 'All UTF-16 units of $text are styled');
}

void _expectFirstParagraph(WmlParagraph paragraph) {
  expect(paragraph.text, _firstParagraph);
  _expectTextProperties(paragraph, 'Research ', (properties) {
    expect(properties.fontSizeHalfPoints, 22);
    expect(properties.asciiFont, 'Arial');
    expect(properties.bold, isFalse);
    expect(properties.italic, isFalse);
  });
  _expectTextProperties(paragraph, 'bold', (properties) {
    expect(properties.fontSizeHalfPoints, 22);
    expect(properties.bold, isTrue);
    expect(properties.italic, isFalse);
  });
  _expectTextProperties(paragraph, 'italic', (properties) {
    expect(properties.fontSizeHalfPoints, 22);
    expect(properties.italic, isTrue);
    expect(properties.bold, isFalse);
  });
}

void _expectOriginalProse(WmlDocument document) {
  final paragraphs = document.paragraphs.toList();
  _expectFirstParagraph(paragraphs.first);
  expect(paragraphs[1].text, _secondParagraph);
  _expectTextProperties(paragraphs[1], _prefix, (properties) {
    expect(properties.fontSizeHalfPoints, 22);
    expect(properties.proofingLanguage, 'en-US');
  });
  _expectTextProperties(paragraphs[1], 'العربية', (properties) {
    expect(properties.fontSizeHalfPoints, 20);
    expect(properties.csFont, 'Arial');
    // Preserve the authored language slot independently of glyph detection.
    expect(properties.complexScriptLanguage, 'hi-IN');
  });
}

Iterable<XmlElement> _elements(XmlElement node, String localName) sync* {
  if (node.localName == localName && node.namespaceUri == _w) yield node;
  for (final child in node.childElements) {
    yield* _elements(child, localName);
  }
}

void _expectNativeScriptSizes(WmlDocument document) {
  final bytes = WordSerializer().writeBytes(document);
  final xml = XmlDocument.parse(
    utf8.decode(ZipReader.fromBytes(bytes).read('word/document.xml')),
  ).root!;
  final runs = _elements(xml, 'r').toList();
  String visible(XmlElement run) => run
      .childrenNamed('t', namespaceUri: _w)
      .map((element) => element.text)
      .join();
  final latin = runs.where((run) => visible(run).contains('Second paragraph'));
  final arabic = runs.where((run) => visible(run).contains('العربية'));
  expect(latin, isNotEmpty);
  expect(arabic, isNotEmpty);
  for (final run in latin) {
    final sizes = run
        .firstChild('rPr', namespaceUri: _w)!
        .childrenNamed('sz', namespaceUri: _w);
    expect(sizes, hasLength(1));
    expect(sizes.single.getAttribute('val', namespaceUri: _w), '22');
  }
  for (final run in arabic) {
    for (final slot in ['sz', 'szCs']) {
      final sizes = run
          .firstChild('rPr', namespaceUri: _w)!
          .childrenNamed(slot, namespaceUri: _w);
      expect(
        sizes,
        hasLength(1),
        reason: 'No duplicate native $slot properties',
      );
      expect(
        sizes.single.getAttribute('val', namespaceUri: _w),
        '20',
        reason: 'Arabic $slot retains its effective native font size',
      );
    }
  }
}

void _expectArchivedMetadata(WmlDocument document, Uint8List source) {
  final output = ZipReader.fromBytes(WordSerializer().writeBytes(document));
  expect(
    output.read('customXml/qudsOdtMetadata.xml'),
    ZipReader.fromBytes(source).read('meta.xml'),
  );
}

void _expectPreferences(WmlDocument document) {
  final data =
      jsonDecode(WordZoteroDocumentData.read(document)) as Map<String, Object?>;
  expect(data['futurePreferences'], <String, Object?>{
    'retain': 'source settings',
  });
  expect(data['prefs'], <String, Object?>{'fieldType': 'Field', 'noteType': 0});
  expect(WordZoteroDocumentData.stylePreferences(jsonEncode(data)), (
    id: 'http://www.zotero.org/styles/apa',
    locale: 'de-DE',
    noteType: 0,
  ));
}

void _expectFields(
  WmlDocument document, {
  String citationText = _cache,
  String locator = '12',
  String bibliographyText = 'First Book.\nSecond Book.',
}) {
  final paragraphs = document.paragraphs.toList();
  final fields = WordZotero.fields(document);
  expect(fields, hasLength(2));
  final citation = fields.first;
  expect(citation.kind, ZoteroFieldKind.citation);
  expect(citation.isValid, isTrue);
  expect(citation.canEdit, isTrue);
  expect(citation.paragraph, same(paragraphs[1]));
  expect(citation.start, _prefix.length);
  expect(citation.end, _prefix.length + citationText.length);
  expect(citation.cachedText, citationText);
  expect(paragraphs[1].text, '$_prefix$citationText.');
  expect(citation.citation!.citationId, 'libreoffice-style-synthetic');
  expect(citation.citation!.items.single.locator, locator);
  expect(citation.citation!.items.single.prefix, 'see ');
  expect(
    citation.citation!.toJson()['futureRoot'],
    _citationData['futureRoot'],
  );
  expect(citation.citation!.properties['futureProperty'], <String, Object?>{
    'preserve': true,
  });
  expect(
    citation.citation!.items.single.toJson()['futureItem'],
    'preserve item extension',
  );
  expect(citation.citation!.items.single.itemData!['futureItemData'], <Object?>[
    true,
    null,
    7,
  ]);
  final bibliography = fields.last;
  expect(bibliography.kind, ZoteroFieldKind.bibliography);
  expect(bibliography.isValid, isTrue);
  expect(bibliography.locked, isFalse);
  expect(bibliography.nested, isFalse);
  expect(bibliography.opaqueMetadata, isFalse);
  expect(bibliography.metadata, _bibliographyData);
  expect(bibliography.cachedText, bibliographyText);
  expect(bibliography.paragraphs, hasLength(2));
  expect(bibliography.paragraphs.first, same(paragraphs[2]));
  expect(bibliography.paragraphs.last, same(paragraphs[3]));
  _expectPreferences(document);
}

void main() {
  test(
    'untouched LibreOffice prose preserves script sizes through DOCX',
    () async {
      final bytes = _nativeBytes();
      final original = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs, hasLength(2));
        expect(WordZotero.fields(document), isEmpty);
        _expectOriginalProse(document);
        _expectNativeScriptSizes(document);
        _expectArchivedMetadata(document, bytes);
        if (cycle < 2) document = _reopen(document);
      }
      expect(bytes, original);
      expect(File(_fixture).readAsBytesSync(), original);
    },
  );

  test(
    'synthetic Zotero fields on untouched LibreOffice styles edit and refresh',
    () async {
      final bytes = _syntheticZoteroVariant();
      final original = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectOriginalProse(document);
        _expectFields(document);
        _expectNativeScriptSizes(document);
        _expectArchivedMetadata(document, bytes);
        final bibliography = WordZotero.fields(document).last;
        _expectTextProperties(bibliography.paragraphs.first, 'Book', (p) {
          expect(p.italic, isTrue);
        });
        _expectTextProperties(bibliography.paragraphs.last, 'Book', (p) {
          expect(p.bold, isTrue);
        });
        if (cycle < 2) document = _reopen(document);
      }

      final field = WordZotero.fields(document).first;
      final citation = field.citation!;
      final editedItem = ZoteroCitationItem.fromJson(<String, Object?>{
        ...citation.items.single.toJson(),
        'locator': '14',
      });
      WordZotero.updateCitation(
        field,
        citation.withItems([editedItem], plainCitation: '(Edited, 14)'),
      );
      _expectFields(document, citationText: '(Edited, 14)', locator: '14');
      document = _reopen(document);
      _expectFields(document, citationText: '(Edited, 14)', locator: '14');

      final beforeRefresh = document.paragraphs.map((p) => p.text).toList();
      const id = 'libreoffice-native-style-refresh';
      final session = WordZoteroCitingSession(
        document: document,
        documentId: id,
        insertionParagraph: document.paragraphs.first,
      );
      Object? call(String command, [List<Object?> args = const []]) =>
          session.handle(command, [id, ...args]);
      final fields = (call('Document.getFields', ['Http']) as List<Object?>)
          .cast<Map<String, Object>>();
      expect(fields, hasLength(2));
      final wireCitation = fields.singleWhere(
        (f) => (f['code']! as String).startsWith('ITEM CSL_CITATION '),
      );
      final wireBibliography = fields.singleWhere(
        (f) => (f['code']! as String).startsWith('BIBL '),
      );
      const refreshedText = '(Refreshed العربية, 14)';
      const refreshedHtml = '(<b>Refreshed</b> <i>العربية</i>, 14)';
      final currentCitation = WordZotero.fields(document).first.citation!;
      final refreshed = currentCitation.withItems(
        currentCitation.items,
        plainCitation: refreshedText,
        formattedCitation: refreshedHtml,
      );
      call('Field.setCode', [
        wireCitation['id'],
        'ITEM CSL_CITATION ${jsonEncode(refreshed.toJson())}',
      ]);
      call('Field.setText', [wireCitation['id'], refreshedHtml, true]);
      call('Field.setText', [
        wireBibliography['id'],
        '<div class="csl-entry">Refreshed <i>Book</i>.</div>'
            '<div class="csl-entry">Another <b>Book</b>.</div>',
        true,
      ]);
      call('Document.setDocumentData', [call('Document.getDocumentData')]);
      expect(document.paragraphs.map((p) => p.text), beforeRefresh);
      call('Document.complete');
      session.prepareReview();
      session.apply();

      for (var cycle = 0; cycle < 3; cycle++) {
        _expectFirstParagraph(document.paragraphs.first);
        _expectFields(
          document,
          citationText: refreshedText,
          locator: '14',
          bibliographyText: 'Refreshed Book.\nAnother Book.',
        );
        _expectArchivedMetadata(document, bytes);
        final citation = WordZotero.fields(document).first;
        _expectTextProperties(citation.paragraph, 'Refreshed', (p) {
          expect(p.bold, isTrue);
        });
        _expectTextProperties(citation.paragraph, 'العربية', (p) {
          expect(p.italic, isTrue);
        });
        if (cycle < 2) document = _reopen(document);
      }
      expect(bytes, original);
      expect(
        sha256.convert(File(_fixture).readAsBytesSync()).toString(),
        _fixtureSha256,
      );
    },
  );

  final refusals = <({String name, Uint8List Function() bytes, String reason})>[
    (
      name: 'CJK text activates unsupported native typography',
      bytes: () => _rewriteNative(
        content: (xml) => _replaceOnce(xml, 'Research ', 'Research 漢 '),
      ),
      reason: 'CJK|Asian|ideograph|autospace|punctuation|line-break',
    ),
    (
      name: 'tab activates the native default tab grid',
      bytes: () => _rewriteNative(
        content: (xml) => _replaceOnce(xml, 'Research ', 'Research<text:tab/>'),
      ),
      reason: 'tab',
    ),
    (
      name: 'active page grid is refused',
      bytes: () => _rewriteNative(
        styles: (xml) => _replaceOnce(
          xml,
          'style:layout-grid-mode="none"',
          'style:layout-grid-mode="line"',
        ),
      ),
      reason: 'grid',
    ),
  ];
  for (final control in refusals) {
    test(control.name, () async {
      final bytes = control.bytes();
      final before = Uint8List.fromList(bytes);
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.toString(),
            'relevant refusal reason',
            matches(RegExp(control.reason, caseSensitive: false)),
          ),
        ),
      );
      expect(bytes, before);
    });
  }
}
