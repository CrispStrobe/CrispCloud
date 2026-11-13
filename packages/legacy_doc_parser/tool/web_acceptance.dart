// SPDX-License-Identifier: MPL-2.0
// Run with tool/verify_web.py. No dart:io, browser, Flutter, or network API is
// imported: the same package parser and ZIP/CFB writers execute under Node.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart'
    show CfbfException, CfbfFile;
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:xml/xml.dart';

import '../test/support/compound_size_fixture.dart';
import '../test/support/media_word_fixture.dart';
import '../test/support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

XmlDocument _xml(Map<String, Uint8List> parts, String name) =>
    XmlDocument.parse(utf8.decode(parts[name]!));

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);

Map<String, Uint8List> _package(Uint8List bytes) {
  final parts = <String, Uint8List>{};
  for (final file in ZipDecoder().decodeBytes(bytes)) {
    if (!file.isFile) continue;
    _check(!parts.containsKey(file.name), 'duplicate package part');
    _check(!file.name.split('/').contains('..'), 'package path traversal');
    parts[file.name] = file.content;
  }
  final types = _xml(parts, '[Content_Types].xml').rootElement.childElements
      .where((element) => element.name.local == 'Override')
      .map((element) => element.getAttribute('PartName'))
      .toSet();
  for (final entry in parts.entries) {
    if (entry.key.endsWith('.xml') || entry.key.endsWith('.rels')) {
      XmlDocument.parse(utf8.decode(entry.value));
    }
    if (entry.key != '[Content_Types].xml' && !entry.key.endsWith('.rels')) {
      _check(types.contains('/${entry.key}'), 'undeclared package part');
    }
    if (!entry.key.endsWith('.rels')) continue;
    final directory = entry.key.substring(0, entry.key.indexOf('_rels/'));
    for (final relationship in _xml(
      parts,
      entry.key,
    ).rootElement.childElements) {
      _check(
        relationship.getAttribute('TargetMode') == null,
        'external relationship',
      );
      _check(
        parts.containsKey('$directory${relationship.getAttribute('Target')}'),
        'unresolved package relationship',
      );
    }
  }
  return parts;
}

Map<String, Object?> verifyWebConversion(Uint8List fixture) {
  final original = Uint8List.fromList(fixture);
  final document = parseLegacyWordDocument(fixture);
  _check(
    document.plainText.contains('Unicode café — 東京 😀.'),
    'DOC Unicode text',
  );
  _check(document.safeHtml.contains('東京 😀'), 'DOC Unicode HTML');
  final table = document.blocks.whereType<LegacyWordTable>().single;
  _check(
    table.rows.length == 2 && table.rows.every((row) => row.cells.length == 2),
    'DOC table structure',
  );
  final formatted = document.blocks
      .whereType<LegacyWordParagraph>()
      .expand((paragraph) => paragraph.runs)
      .firstWhere((run) => run.text == 'Bold red text');
  _check(
    formatted.style.bold &&
        formatted.style.fontSizeHalfPoints == 36 &&
        formatted.style.colorHex?.toUpperCase() == 'C02030',
    'DOC resolved formatting',
  );
  _check(document.media.assets.isNotEmpty, 'DOC referenced image catalog');
  for (final kind in [
    LegacyWordStoryKind.header,
    LegacyWordStoryKind.footer,
    LegacyWordStoryKind.footnote,
  ]) {
    _check(
      document.stories.any((story) => story.kind == kind),
      'DOC auxiliary story',
    );
  }

  final result = convertLegacyWordDocument(document);
  final parts = _package(result.bytes), main = _xml(parts, 'word/document.xml');
  _check(
    _elements(main, 'tbl').length == 1 && _elements(main, 'tc').length == 4,
    'DOCX real table/cell elements',
  );
  _check(
    _elements(
      main,
      't',
    ).map((node) => node.innerText).join().contains('café — 東京 😀'),
    'DOCX Unicode text',
  );
  final images = parts.entries
      .where((entry) => entry.key.startsWith('word/media/'))
      .toList();
  _check(
    images.isNotEmpty &&
        document.media.assets.any(
          (asset) => images.any((entry) => _equal(asset.bytes, entry.value)),
        ),
    'DOCX exact referenced image',
  );
  _check(
    _elements(main, 'drawing').isNotEmpty,
    'DOCX image drawing relationship',
  );
  _check(
    _elements(main, 'headerReference').isNotEmpty &&
        parts.keys.any(
          (path) => path.startsWith('word/header') && path.endsWith('.xml'),
        ),
    'DOCX header part and reference',
  );
  _check(
    _elements(main, 'footerReference').isNotEmpty &&
        parts.keys.any(
          (path) => path.startsWith('word/footer') && path.endsWith('.xml'),
        ),
    'DOCX footer part and reference',
  );
  _check(
    parts.containsKey('word/footnotes.xml') &&
        _elements(main, 'footnoteReference').isNotEmpty &&
        _elements(_xml(parts, 'word/footnotes.xml'), 'footnoteRef').isNotEmpty,
    'DOCX footnote part and markers',
  );
  _check(_equal(fixture, original), 'real DOC source changed');

  final oleSource = oleWordFixture();
  final oleBefore = Uint8List.fromList(oleSource);
  final oleModel = parseLegacyWordDocument(oleSource);
  final oleParts = _package(convertLegacyWordDocument(oleModel).bytes);
  final embedded = oleParts['word/embeddings/oleObject1.bin'];
  _check(
    embedded != null &&
        _equal(embedded, oleModel.media.embeddedObjects.single.storage.bytes),
    'OLE reconstructed payload changed in ZIP',
  );
  final object = BoundedCfbReader(embedded!);
  _check(
    _equal(object.root.clsid, List.generate(16, (index) => index + 1)) &&
        object.root.stateBits == 0x1234,
    'OLE root class and state',
  );
  _check(
    _equal(object.root.createdFiletime, [1, 2, 3, 4, 5, 6, 7, 0]),
    'OLE raw FILETIME',
  );
  _check(
    _equal(object.readPath('Nested/extra')!, [5, 6, 7]),
    'OLE nested bytes',
  );
  _check(_equal(oleSource, oleBefore), 'OLE source changed');

  final vba = _vbaMetadataCase();
  return {
    'unicode': true,
    'tables': result.preservedCounts['tables'],
    'images': result.preservedCounts['images'],
    'headers': result.preservedCounts['headers'],
    'footers': result.preservedCounts['footers'],
    'footnotes': result.preservedCounts['footnotes'],
    'internalRelationships': true,
    'sourceUnchanged': true,
    'oleMetadata': true,
    'vbaMetadata': vba,
    'cfbSimpleNames': _cfbNamesCase(),
    'cfbVersionedStreamSizes': _cfbStreamSizeCase(),
    'boundedTextExtraction': _textExtractionCase(),
    'signatureValidityClaimed': false,
  };
}

bool _cfbStreamSizeCase() {
  final expected = List.generate(4096, (index) => index & 255);
  for (final highWord in [1, 0x80000000, 0xffffffff]) {
    final source = compoundSizeFixture(highWord: highWord);
    final before = Uint8List.fromList(source);
    final bounded = BoundedCfbReader(source), raw = CfbfFile.fromBytes(source);
    _check(
      bounded.root.streamSize == 64 && raw.root.streamSize == 64,
      'version-3 root ignores high DWORD',
    );
    _check(
      _equal(bounded.readPath('Small')!, [1, 2, 3]) &&
          _equal(raw.readPath('Small')!, [1, 2, 3]),
      'version-3 mini-stream',
    );
    _check(
      _equal(bounded.readPath('Large')!, expected) &&
          _equal(raw.readPath('Large')!, expected),
      'version-3 regular stream',
    );
    _check(_equal(source, before), 'version-3 source unchanged');
  }
  _check(
    _equal(
      BoundedCfbReader(compoundSizeFixture(version4: true)).readPath('Large')!,
      expected,
    ),
    'independent version-4 bounded stream',
  );
  for (final source in [
    compoundSizeFixture(version4: true, highWord: 1, root: false),
    compoundSizeFixture(version4: true, highWord: 1, streams: false),
    compoundSizeFixture(highWord: 0xffffffff, oversizedLowWord: true),
    compoundSizeFixture(version4: true, oversizedLowWord: true),
  ]) {
    var rejected = false;
    try {
      BoundedCfbReader(source);
    } on FormatException {
      rejected = true;
    }
    _check(rejected, 'CFB version-specific physical size bounds');
  }
  for (final (high, low, expectedSize) in [
    (1, 4096, 4294971392),
    (0, 0x80000000, 2147483648),
    (0, 0xffffffff, 4294967295),
    (0x1fffff, 0xffffffff, 9007199254740991),
  ]) {
    final raw = CfbfFile.fromBytes(
      compoundSizeFixture(
        version4: true,
        root: false,
        highWord: high,
        lowWord: low,
      ),
    );
    _check(
      raw.entryByName('Large')!.streamSize == expectedSize,
      'raw version-4 portable unsigned stream metadata',
    );
    var rejected = false;
    try {
      raw.readPath('Large');
    } on CfbfException {
      rejected = true;
    }
    _check(rejected, 'raw version-4 stream rejected before allocation');
  }
  for (final highWord in [0x200000, 0x80000000, 0xffffffff]) {
    var rejected = false;
    try {
      CfbfFile.fromBytes(
        compoundSizeFixture(
          version4: true,
          root: false,
          highWord: highWord,
          lowWord: 0,
        ),
      );
    } on CfbfException {
      rejected = true;
    }
    _check(rejected, 'raw version-4 inexact metadata rejected');
  }
  final badRoot = CfbfFile.fromBytes(
    compoundSizeFixture(streams: false, oversizedLowWord: true),
  );
  var rejectedRoot = false;
  try {
    badRoot.readPath('Small');
  } on CfbfException {
    rejectedRoot = true;
  }
  _check(rejectedRoot, 'raw mini-stream bounds root before allocation');
  return true;
}

bool _cfbNamesCase() {
  // Full uppercase expands these BMP names in JavaScript. Supplementary
  // case pairs must remain distinct in CFB on both the VM and JavaScript.
  const names = [
    'ß',
    'SS',
    'ßs',
    'sß',
    'ﬃ',
    '\u{10400}',
    '\u{10428}',
    '\u1f80',
    '\u1f90',
    '\u1fa0',
    '\u1fb3',
    '\u1fc3',
    '\u1ff3',
  ];
  final writer = CfbfWriter();
  for (var index = 0; index < names.length; index++) {
    writer.addStream(names[index], [index]);
  }
  final source = writer.build(), before = Uint8List.fromList(source);
  final bounded = BoundedCfbReader(source), raw = CfbfFile.fromBytes(source);
  _check(bounded.childrenOf(bounded.root).length == names.length, 'CFB names');
  for (var index = 0; index < names.length; index++) {
    _check(
      bounded.readPath(names[index])!.single == index &&
          raw.readPath(names[index])!.single == index,
      'CFB stream identity ${names[index]}',
    );
  }
  const upperGreek = [
    '\u1f88',
    '\u1f98',
    '\u1fa8',
    '\u1fbc',
    '\u1fcc',
    '\u1ffc',
  ];
  for (var index = 0; index < upperGreek.length; index++) {
    _check(
      bounded.readPath(upperGreek[index])!.single == index + 7 &&
          raw.readPath(upperGreek[index])!.single == index + 7,
      'CFB Greek simple uppercase',
    );
  }
  _check(
    bounded.readPath('ss')!.single == 1 &&
        bounded.readPath('ßS')!.single == 2 &&
        bounded.readPath('Sß')!.single == 3 &&
        bounded.readPath('FFI') == null &&
        raw.readPath('FFI') == null,
    'CFB casing preserves name boundaries',
  );
  var rejectedDuplicate = false;
  try {
    writer.addStream('ss', [99]);
  } on ArgumentError {
    rejectedDuplicate = true;
  }
  _check(rejectedDuplicate, 'CFB true case collision');
  _check(_equal(source, before), 'CFB named source changed');
  return true;
}

bool _textExtractionCase() {
  void rejects(Uint8List bytes, String description) {
    var rejected = false;
    try {
      extractLegacyWordText(bytes);
    } on FormatException {
      rejected = true;
    }
    _check(rejected, description);
  }

  for (final compressed in [false, true]) {
    final fixture = StructuredWordFixture(
      pieces: [WordFixturePiece('Text\r', compressed: compressed)],
    );
    rejects(
      fixture.build(
        mutate: (word, _) => word.setUint32(
          64,
          8192 + 5 * (compressed ? 1 : 2) - 1,
          Endian.little,
        ),
      ),
      'text-only declared extent',
    );
    rejects(
      fixture.build(
        mutate: (word, table) {
          final clx = word.getUint32(154 + 33 * 8, Endian.little);
          final data = ByteData.sublistView(table);
          data.setUint32(
            clx + 15,
            data.getUint32(clx + 15, Endian.little) | 0x80000000,
            Endian.little,
          );
        },
      ),
      'text-only reserved offset bit',
    );
  }
  final source = StructuredWordFixture(
    pieces: const [WordFixturePiece('Left\x0eRight\r')],
  ).build();
  _check(extractLegacyWordText(source) == 'Left\nRight', 'text column break');
  final parts = _package(convertLegacyWordToDocx(source));
  _check(
    _elements(
          _xml(parts, 'word/document.xml'),
          'p',
        ).map((paragraph) => paragraph.innerText).join('|') ==
        'Left|Right',
    'text-only DOCX column separation',
  );
  return true;
}

bool _vbaMetadataCase() {
  final template = BoundedCfbReader(
    StructuredWordFixture(
      pieces: const [WordFixturePiece('VBA metadata 世界\r', compressed: false)],
    ).build(),
  );
  final clsid = Uint8List.fromList(List.generate(16, (index) => 255 - index));
  // This FILETIME is above JavaScript's exact integer range and includes a
  // sub-microsecond tick. Preserve raw bytes instead of round-tripping DateTime.
  final filetime = Uint8List.fromList([
    1,
    0x88,
    0xf9,
    0x12,
    0x4b,
    0xb4,
    0xba,
    1,
  ]);
  final writer = CfbfWriter();
  for (final entry in template.childrenOf(template.root)) {
    _check(entry.isStream, 'unexpected synthetic source storage');
    writer.addStream(entry.name, template.readEntry(entry));
  }
  writer.addStorage(
    'Macros',
    clsid: clsid,
    stateBits: 0xfedcba98,
    createdFiletime: filetime,
    modifiedFiletime: filetime,
  );
  writer.addStorage(
    'Macros/VBA',
    clsid: Uint8List.fromList(List.filled(16, 7)),
    stateBits: 0x87654321,
    createdFiletime: filetime,
    modifiedFiletime: filetime,
  );
  writer.addStorage('Macros/Empty', stateBits: 73, modifiedFiletime: filetime);
  writer.addStream('Macros/PROJECT', 'Name="WebFixture"'.codeUnits);
  writer.addStream('Macros/VBA/dir', [1, 2, 3]);
  writer.addStream('Macros/VBA/_VBA_PROJECT', [0xcc, 0x61, 0, 0, 0, 0, 0]);
  final payload = List.generate(5000, (index) => index % 251);
  writer.addStream('Macros/VBA/Module1', payload);
  writer.addStream('_signatures', [9, 8, 7]);
  final source = writer.build(), before = Uint8List.fromList(source);
  final parsed = parseLegacyWordDocument(source);
  _check(
    parsed.media.vbaProjects.single.hasRequiredStreams,
    'VBA required streams',
  );
  final macroFree = _package(convertLegacyWordDocument(parsed).bytes);
  _check(
    !macroFree.containsKey('word/vbaProject.bin') &&
        !utf8
            .decode(macroFree['[Content_Types].xml']!)
            .contains('macroEnabled'),
    'DOCX active VBA',
  );
  final result = convertLegacyWordDocument(
    parsed,
    format: LegacyWordOutputFormat.docm,
  );
  final parts = _package(result.bytes), bytes = parts['word/vbaProject.bin'];
  _check(
    bytes != null &&
        _equal(bytes, parsed.media.vbaProjects.single.storage.bytes),
    'DOCM VBA bytes differ',
  );
  final project = BoundedCfbReader(bytes!);
  _check(
    _equal(project.root.clsid, clsid) && project.root.stateBits == 0xfedcba98,
    'VBA root class/state',
  );
  _check(
    _equal(project.root.createdFiletime, filetime) &&
        _equal(project.root.modifiedFiletime, filetime),
    'VBA root exact FILETIME',
  );
  final nested = project.child(project.root, 'VBA')!;
  _check(
    _equal(nested.clsid, List.filled(16, 7)) && nested.stateBits == 0x87654321,
    'VBA nested class/state',
  );
  _check(
    _equal(nested.createdFiletime, filetime) &&
        _equal(nested.modifiedFiletime, filetime),
    'VBA nested exact FILETIME',
  );
  final empty = project.child(project.root, 'Empty')!;
  _check(
    empty.stateBits == 73 && _equal(empty.modifiedFiletime, filetime),
    'VBA empty storage',
  );
  _check(
    _equal(project.readPath('VBA/Module1')!, payload),
    'VBA regular-sector payload',
  );
  _check(
    _equal(project.readPath('VBA/dir')!, [1, 2, 3]),
    'VBA mini-stream payload',
  );
  _check(
    !result.signatureValidityClaimed &&
        result.signatureEvidenceParts.length == 1,
    'signature evidence policy',
  );
  _check(
    _equal(parts[result.signatureEvidenceParts.single]!, [9, 8, 7]),
    'signature evidence bytes',
  );
  final relationships = parts.entries
      .where((entry) => entry.key.endsWith('.rels'))
      .map((entry) => utf8.decode(entry.value))
      .join();
  _check(
    !relationships.contains('digital-signature') &&
        !relationships.contains('vbaProjectSignature'),
    'active copied signature',
  );
  _check(_equal(source, before), 'VBA source changed');
  return true;
}
