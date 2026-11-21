import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Portable acceptance of a synthetic native ODT, not a captured Office file.
///
/// Native names, bibliography TextSections and numbered preference chunks use
/// the contract documented at Zotero LibreOffice integration commit
/// 0a31b434371eb21a1297c5bce8ca4978cb9ab425:
/// https://github.com/zotero/zotero-libreoffice-integration/tree/0a31b434371eb21a1297c5bce8ca4978cb9ab425
///
/// Run directly on Dart VM or compile this same source to JavaScript. No file,
/// network, GUI, installed Zotero or installed word-processor access is needed.
const nativePluginCommit = '0a31b434371eb21a1297c5bce8ca4978cb9ab425';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _citationText = '(أحمد، 2026) 😀';
const _noteText = 'Authored note citation 😀';
const _cellText = 'Table citation العربية';
const _bibliographyText = 'أحمد. عنوان عربي 😀.\nExample. Second reference.';
const _bibliographyCode =
    'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY';
const _bibliographyName = 'ZOTERO_$_bibliographyCode RND0123456789';
const _untouched = <int>[0, 1, 2, 127, 255];

Map<String, Object?> _citationData(String identity, {int noteIndex = 0}) => {
  'citationID': identity,
  'citationItems': [
    {
      'id': 'https://zotero.org/users/1/items/ABCDEFGH',
      'uris': ['https://zotero.org/users/1/items/ABCDEFGH'],
      'locator': '12–14',
      'label': 'page',
      'prefix': 'انظر ',
      'suffix': ' RNDinsideText',
      'suppress-author': true,
      'itemData': {'type': 'book', 'title': 'عنوان عربي 😀 & <quoted>'},
    },
    {
      'id': 'https://zotero.org/groups/2/items/JKLMNPQR',
      'locator': '4',
      'label': 'chapter',
      'itemData': {'type': 'book', 'title': 'Second source'},
    },
  ],
  'properties': {'plainCitation': _citationText, 'noteIndex': noteIndex},
  'extension': {
    'preserve': [true, null, 3, 'العربية 😀'],
  },
};

String _citationName(String identity, String suffix, {int noteIndex = 0}) =>
    'ZOTERO_ITEM CSL_CITATION '
    '${jsonEncode(_citationData(identity, noteIndex: noteIndex))} RND$suffix';

String _start(String name) =>
    '<text:reference-mark-start text:name="${encodeXmlAttribute(name)}"/>';

String _end(String name) =>
    '<text:reference-mark-end text:name="${encodeXmlAttribute(name)}"/>';

String _mark(String name, String content) =>
    '${_start(name)}$content${_end(name)}';

String _preferences() =>
    ' ${jsonEncode(<String, Object?>{
      'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
      'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'ar'},
      'extension': {'retained': 'العربية 😀 & <preserve> ' * 35},
    })} ';

List<String> _preferenceChunks(String data) {
  final chunks = <String>[];
  var offset = 0;
  while (offset < data.length) {
    var end = (offset + 255).clamp(0, data.length);
    if (end < data.length &&
        data.codeUnitAt(end - 1) >= 0xd800 &&
        data.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    chunks.add(data.substring(offset, end));
    offset = end;
  }
  // Native Zotero retains empty cleanup slots from a formerly longer value.
  return [...chunks, ''];
}

String _metadata() {
  final chunks = _preferenceChunks(_preferences());
  return '<office:document-meta xmlns:office="$_office" xmlns:meta="$_meta">'
      '<office:meta><meta:user-defined meta:name="Unrelated">'
      'untouched &amp; 😀</meta:user-defined>'
      // Source order is deliberately different from numeric chunk order.
      '${[for (var index = chunks.length; index > 0; index--) '<meta:user-defined meta:name="ZOTERO_PREF_$index" meta:value-type="string">${encodeXmlText(chunks[index - 1])}</meta:user-defined>'].join()}'
      '</office:meta></office:document-meta>';
}

Uint8List _package(String body) {
  final zip = ZipWriter();
  zip.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content xmlns:office="$_office" '
      'xmlns:text="$_text" xmlns:table="$_table" office:version="1.3">'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>',
    ),
  );
  zip.addFile('meta.xml', utf8.encode(_metadata()));
  zip.addFile('Pictures/unrelated.bin', _untouched, store: true);
  zip.addFile(
    'META-INF/manifest.xml',
    utf8.encode(
      '<manifest:manifest '
      'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
      'manifest:version="1.3">'
      '<manifest:file-entry manifest:full-path="/" '
      'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
      '<manifest:file-entry manifest:full-path="content.xml" '
      'manifest:media-type="text/xml"/>'
      '<manifest:file-entry manifest:full-path="meta.xml" '
      'manifest:media-type="text/xml"/>'
      '<manifest:file-entry manifest:full-path="Pictures/unrelated.bin" '
      'manifest:media-type="application/octet-stream"/>'
      '</manifest:manifest>',
    ),
  );
  return zip.close();
}

/// Deterministic fixture bytes shared by VM, JavaScript and CLI acceptance.
Uint8List nativeInventoryFixture() => _package(
  '<text:p>😀 '
  '${_mark(_citationName('body-citation', 'abcdefghij'), '<text:span>(أحمد، 2026)</text:span><text:s/>😀')}'
  ' after</text:p>'
  '<text:p>Authored note '
  '<text:note text:id="note1" text:note-class="footnote">'
  '<text:note-citation>1</text:note-citation><text:note-body><text:p>'
  '${_mark(_citationName('note-citation', 'klmnopqrst', noteIndex: 1), _noteText)}'
  '</text:p></text:note-body></text:note></text:p>'
  '<table:table table:name="Research"><table:table-row>'
  '<table:table-cell><text:p>Cell '
  '${_mark(_citationName('cell-citation', 'uvwxyzABCD'), _cellText)}'
  '</text:p></table:table-cell>'
  '<table:table-cell><text:p>Unrelated cell</text:p></table:table-cell>'
  '</table:table-row></table:table>'
  '<text:section text:name="${encodeXmlAttribute(_bibliographyName)}">'
  '<text:p>أحمد. عنوان عربي 😀.</text:p>'
  '<text:p>Example. Second reference.</text:p></text:section>',
);

/// Structurally invalid package for the diagnostic command's nonzero exit.
Uint8List malformedInventoryFixture() => _package('<text:p>Unclosed paragraph');

Uint8List _crossCellFixture() {
  final name = _citationName('cross-cell', 'ABCDEFGHIJ');
  return _package(
    '<table:table><table:table-row>'
    '<table:table-cell><text:p>${_start(name)}A</text:p></table:table-cell>'
    '<table:table-cell><text:p>B${_end(name)}</text:p></table:table-cell>'
    '</table:table-row></table:table>',
  );
}

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _immutable(void Function() mutation) {
  try {
    mutation();
  } on UnsupportedError {
    return;
  }
  throw StateError('Inventory exposed mutable evidence.');
}

Future<Map<String, Object?>> runOdtInventoryAcceptance() async {
  final bytes = nativeInventoryFixture();
  final original = Uint8List.fromList(bytes);
  final inventory = await OdfZotero.inspect(bytes);
  final repeated = await OdfZotero.inspect(bytes);
  _check(_sameBytes(bytes, original), 'Inspection mutated the ODT bytes.');
  _check(
    jsonEncode(inventory.toJson()) == jsonEncode(repeated.toJson()),
    'Repeated inspection changed the inventory.',
  );
  _check(
    inventory.fields.length == 4,
    'Expected three citations and a bibliography.',
  );
  _check(inventory.paragraphCount == 7, 'Paragraph ownership/count changed.');
  _check(inventory.issues.isEmpty, 'Canonical fixture has document findings.');
  _check(
    inventory.toJson()['editable'] == false,
    'Inventory claims editability.',
  );
  _check(
    inventory.fields.every((field) => field.isImportCandidate),
    'Canonical native fields acquired guards.',
  );

  final body = inventory.fields[0];
  final note = inventory.fields[1];
  final cell = inventory.fields[2];
  final bibliography = inventory.fields[3];
  _check(
    body.name == _citationName('body-citation', 'abcdefghij'),
    'Native citation identity changed.',
  );
  _check(body.randomSuffix == 'abcdefghij', 'Suffix identity was lost.');
  _check(
    body.logicalCode ==
        'ITEM CSL_CITATION ${jsonEncode(_citationData('body-citation'))}',
    'Logical code changed.',
  );
  _check(
    jsonEncode(body.metadata) == jsonEncode(_citationData('body-citation')),
    'Multi-item metadata or extension data changed.',
  );
  _check(
    body.kind == ZoteroFieldKind.citation &&
        body.storage == OdfZoteroStorage.referenceMark,
    'Wrong citation storage.',
  );
  _check(
    body.cachedText == _citationText,
    'Arabic/astral cached text changed.',
  );
  _check(
    body.starts.single.offset == 3 &&
        body.ends.single.offset == 3 + _citationText.length,
    'Wrong UTF-16 offsets.',
  );
  _check(
    body.starts.single.paragraphIndex == 0 &&
        body.starts.single.story == OdfZoteroStory.body,
    'Wrong body ownership.',
  );

  _check(
    note.cachedText == _noteText &&
        note.starts.single.story == OdfZoteroStory.footnote,
    'Lost authored note.',
  );
  _check(
    note.starts.single.storyPath != body.starts.single.storyPath,
    'Note and body share a physical story identity.',
  );
  _check(
    note.starts.single.owners.last.localName == 'note-body',
    'Note-body owner is missing.',
  );
  _check(
    note.starts.single.paragraphIndex == 2,
    'Note paragraph identity changed.',
  );
  _check(
    cell.cachedText == _cellText && cell.starts.single.offset == 5,
    'Table citation text/offset changed.',
  );
  _check(
    cell.starts.single.owners.last.localName == 'table-cell',
    'Table-cell owner is missing.',
  );
  _check(
    cell.starts.single.paragraphIndex == 3,
    'Table paragraph identity changed.',
  );

  _check(
    bibliography.name == _bibliographyName &&
        bibliography.logicalCode == _bibliographyCode &&
        bibliography.storage == OdfZoteroStorage.section &&
        bibliography.kind == ZoteroFieldKind.bibliography,
    'Native bibliography TextSection changed.',
  );
  _check(
    bibliography.cachedText == _bibliographyText &&
        bibliography.ranges.length == 2,
    'Bibliography paragraphs were flattened.',
  );
  _check(
    bibliography.starts.single.offset == null &&
        bibliography.ranges.first.location.owners.last.localName == 'section',
    'Bibliography section boundaries were invented.',
  );

  final preferences = inventory.preferences;
  _check(
    preferences.isValid && preferences.usesReferenceMarks,
    'Native preferences were rejected or converted.',
  );
  _check(preferences.rawData == _preferences(), 'Preference bytes changed.');
  _check(
    preferences.chunks.length == _preferenceChunks(_preferences()).length &&
        preferences.chunks.length > 2,
    'Numbered preference chunks were lost.',
  );
  _check(
    preferences.properties.first.name == 'Unrelated' &&
        preferences.properties.first.value == 'untouched & 😀',
    'Unrelated metadata was discarded.',
  );
  _check(
    preferences.chunks.first.index == preferences.chunks.length &&
        preferences.chunks.last.index == 1,
    'Source property order was changed.',
  );
  final package = ZipReader.fromBytes(bytes);
  _check(
    _sameBytes(package.read('Pictures/unrelated.bin'), _untouched),
    'Unrelated ZIP part changed.',
  );
  _check(
    utf8.decode(package.read('meta.xml')) == _metadata(),
    'Native metadata XML changed.',
  );
  _immutable(inventory.fields.clear);
  _immutable(body.starts.single.owners.clear);
  _immutable(() => body.metadata!['extension'] = null);
  _immutable((body.metadata!['citationItems']! as List<Object?>).clear);

  final guardedBytes = _crossCellFixture();
  final guardedBefore = Uint8List.fromList(guardedBytes);
  final guarded = (await OdfZotero.inspect(guardedBytes)).fields.single;
  _check(
    guarded.isValid && !guarded.isImportCandidate && guarded.ranges.isEmpty,
    'A cross-cell range became an import candidate.',
  );
  _check(
    guarded.issues.any((issue) => issue.code == OdfZoteroIssueCode.crossOwner),
    'A cross-cell range lost its diagnostic.',
  );
  _check(_sameBytes(guardedBytes, guardedBefore), 'Guarded input was mutated.');
  var malformedRejected = false;
  try {
    await OdfZotero.inspect(malformedInventoryFixture());
  } on FormatException {
    malformedRejected = true;
  }
  _check(malformedRejected, 'Malformed XML was accepted.');
  var budgetRejected = false;
  try {
    await OdfZotero.inspect(bytes, limits: const OdfZoteroLimits(maxFields: 1));
  } on OdfZoteroLimitException {
    budgetRejected = true;
  }
  _check(
    budgetRejected,
    'The field budget did not reject the entire inventory.',
  );
  return {
    'fixtureKind': 'synthetic-native-odt',
    'nativePluginCommit': nativePluginCommit,
    'sourceBytesPreserved': true,
    'stableRepeatInventory': true,
    'malformedPackageRejected': malformedRejected,
    'fieldBudgetRejected': budgetRejected,
    'guardedCrossCell': guarded.toJson(),
    'inventory': inventory.toJson(),
  };
}

Future<void> main() async =>
    print(jsonEncode(await runOdtInventoryAcceptance()));
