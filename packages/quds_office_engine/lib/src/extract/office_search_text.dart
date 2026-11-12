import 'dart:convert';
import 'dart:typed_data';

import '../opc/office_package_parts.dart';
import '../opc/package_part.dart';
import '../opc/zip/deflate_codec.dart';
import '../opc/zip/zip_reader.dart';
import '../xml/xml_node.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _strictW = 'http://purl.oclc.org/ooxml/wordprocessingml/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _strictR = 'http://purl.oclc.org/ooxml/officeDocument/relationships';

bool _isWord(XmlElement element) =>
    element.namespaceUri == _w || element.namespaceUri == _strictW;
Iterable<XmlElement> _wordElements(XmlElement node, String name) =>
    _elements(node, name).where(_isWord);
String? _wordAttribute(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _w) ??
    element.getAttribute(name, namespaceUri: _strictW);
String? _relationshipId(XmlElement element) =>
    element.getAttribute('id', namespaceUri: _r) ??
    element.getAttribute('id', namespaceUri: _strictR);

/// Whether [name] selects a supported OOXML or OpenDocument search reader.
bool isSearchableOfficeDocument(String name) => const [
  '.docx',
  '.docm',
  '.xlsx',
  '.xlsm',
  '.pptx',
  '.pptm',
  '.odt',
  '.ods',
  '.odp',
].any((extension) => name.toLowerCase().endsWith(extension));

/// A selected XML or emitted UTF-8 text budget was exceeded.
class OfficeSearchLimitException extends FormatException {
  /// Creates a content-budget failure without host UI dependencies.
  const OfficeSearchLimitException()
    : super('Office text exceeds the content limit.');

  @override
  String toString() => message;
}

/// Extracts referenced Office text without activating macros or external parts.
///
/// Selected XML reads and emitted UTF-8 text have independent cumulative
/// [maxBytes] limits. Repeated reads are cached. ZIP metadata is limited by
/// [maxEntries], duplicate member names reject, and inflation is bounded by the
/// remaining XML budget before allocation. Only referenced stories, sheets,
/// slides and notes are read; unused members do not consume the XML budget.
///
/// Malformed selected ZIP/XML input and ambiguous package graphs throw
/// [FormatException]. Unsupported extensions return empty text.
Future<String> officeSearchText(
  Uint8List bytes,
  String name,
  int maxBytes, {
  int maxEntries = 200000,
  int maxXmlDepth = 256,
}) async {
  if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  if (maxEntries < 0) throw ArgumentError.value(maxEntries, 'maxEntries');
  if (maxXmlDepth < 1) throw ArgumentError.value(maxXmlDepth, 'maxXmlDepth');
  if (!isSearchableOfficeDocument(name)) return '';
  try {
    final zip = ZipReader.fromBytes(
      bytes,
      maxEntries: maxEntries,
      rejectDuplicateNames: true,
    );
    final parts = _SearchParts(zip, maxBytes, maxXmlDepth);
    final extension = name.substring(name.lastIndexOf('.')).toLowerCase();
    final blocks = switch (extension) {
      '.docx' || '.docm' => await _word(parts),
      '.xlsx' || '.xlsm' => await _spreadsheet(parts),
      '.pptx' || '.pptm' => await _presentation(parts),
      '.odt' || '.ods' || '.odp' => [
        if (await parts.xml('content.xml') case final XmlElement document)
          parts.output(_allText(document)),
      ],
      _ => <String>[],
    };
    return blocks.where((text) => text.isNotEmpty).join('\n');
  } on ZipLimitException {
    throw const OfficeSearchLimitException();
  } on ZipException catch (error) {
    throw FormatException('Invalid Office ZIP package: ${error.message}');
  } on ZipDeflateException catch (error) {
    throw FormatException('Invalid Office ZIP compression: ${error.message}');
  } on RangeError {
    throw const FormatException('Invalid Office ZIP bounds.');
  }
}

class _SearchParts {
  _SearchParts(this.zip, this.maxBytes, int maxXmlDepth) {
    package = OfficePackageParts(read, maxXmlDepth: maxXmlDepth);
  }
  final ZipReader zip;
  final int maxBytes;
  final _cache = <String, String?>{};
  var _used = 0;
  var _outputBytes = 0;
  var _outputParts = 0;
  late final OfficePackageParts package;

  String output(String text) {
    if (text.isEmpty) return text;
    final length = utf8.encode(text).length + (_outputParts > 0 ? 1 : 0);
    if (length > maxBytes - _outputBytes) {
      throw const OfficeSearchLimitException();
    }
    _outputBytes += length;
    _outputParts++;
    return text;
  }

  Iterable<String> get members => zip.entries
      .where((entry) => !entry.isDirectory && _safeMember(entry.fileName))
      .map((entry) => entry.fileName);

  Future<String?> read(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    if (!_safeMember(name) || zip[name] == null || zip[name]!.isDirectory) {
      return _cache[name] = null;
    }
    if (_used >= maxBytes) throw const OfficeSearchLimitException();
    final content = zip.read(name, maxBytes: maxBytes - _used);
    _used += content.length;
    return _cache[name] = utf8.decode(content);
  }

  Future<XmlElement?> xml(String name) async => (await package.xml(name))?.root;

  Future<String?> mainPart(String fallback) =>
      package.mainPartOrNull(fallback: fallback);

  Future<bool> hasRelationships(String owner) async =>
      await read(OfficePackageParts.relationshipPath(owner)) != null;

  List<String> numberedParts(String pattern) {
    final expression = RegExp(pattern);
    return members.where(expression.hasMatch).toList()..sort(
      (a, b) => int.parse(
        expression.firstMatch(a)!.group(1)!,
      ).compareTo(int.parse(expression.firstMatch(b)!.group(1)!)),
    );
  }
}

bool _safeMember(String name) =>
    name.isNotEmpty &&
    !name.startsWith('/') &&
    !name.contains('\\') &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) &&
    OpcUris.toZipName(name) == name;

Iterable<XmlNode> _descendants(XmlElement node) sync* {
  for (final child in node.children) {
    yield child;
    if (child is XmlElement) yield* _descendants(child);
  }
}

Iterable<XmlElement> _elements(XmlElement node, String name) => _descendants(
  node,
).whereType<XmlElement>().where((element) => element.localName == name);

Iterable<XmlElement> _ancestors(XmlElement node) sync* {
  var parent = node.parent;
  while (parent != null) {
    yield parent;
    parent = parent.parent;
  }
}

String _sibling(String owner, String name) =>
    OpcUris.toZipName(OpcUris.resolve('/$owner', name));

String _allText(XmlElement node) => _descendants(node)
    .where((item) => item is XmlText || item is XmlCdata)
    .map(
      (item) => switch (item) {
        XmlText(:final text) || XmlCdata(:final text) => text,
        _ => '',
      },
    )
    .join(' ')
    .trim();

String _wordText(XmlElement node) {
  if (_wordElements(node, 't').isEmpty) return _allText(node);
  final buffer = StringBuffer();
  void visit(XmlNode item) {
    if (item is! XmlElement) return;
    if (_isWord(item)) {
      switch (item.localName) {
        case 't':
          buffer.write(item.text);
          return;
        case 'tab':
          buffer.write('\t');
          return;
        case 'br':
        case 'cr':
          buffer.write('\n');
          return;
      }
    }
    for (final child in item.children) {
      visit(child);
    }
    if (_isWord(item) && item.localName == 'p') buffer.writeln();
  }

  visit(node);
  return buffer.toString().trim();
}

Future<List<String>> _word(_SearchParts parts) async {
  final main = await parts.mainPart('word/document.xml');
  if (main == null) return [];
  final document = await parts.xml(main);
  if (document == null) return [];
  final relations = await parts.package.relationships(main);
  final byId = {
    for (final relationship in relations) relationship.id: relationship,
  };
  final stories = <XmlElement>[document];
  final seen = <String>{main};
  for (final reference in _descendants(document).whereType<XmlElement>()) {
    final kind = switch (reference.localName) {
      'headerReference' => 'header',
      'footerReference' => 'footer',
      _ => null,
    };
    if (!_isWord(reference) ||
        kind == null ||
        _ancestors(reference).any(
          (element) => element.localName == 'sectPrChange' && _isWord(element),
        )) {
      continue;
    }
    final relation = byId[_relationshipId(reference)];
    if (relation == null ||
        !relation.isType(kind) ||
        !seen.add(relation.path)) {
      continue;
    }
    final story = await parts.xml(relation.path);
    if (story != null) stories.add(story);
  }
  final blocks = [for (final story in stories) parts.output(_wordText(story))];
  for (final kind in ['footnote', 'endnote']) {
    final ids = {
      for (final story in stories)
        for (final reference in _wordElements(story, '${kind}Reference'))
          if (_wordAttribute(reference, 'id') case final String id) id,
    };
    if (ids.isEmpty) continue;
    var notePath = relations
        .where((relationship) => relationship.isType('${kind}s'))
        .firstOrNull
        ?.path;
    if (notePath == null && !await parts.hasRelationships(main)) {
      notePath = _sibling(main, '${kind}s.xml');
    }
    if (notePath == null) continue;
    final notes = await parts.xml(notePath);
    if (notes == null) continue;
    for (final note in _wordElements(notes, kind)) {
      final type = _wordAttribute(note, 'type');
      if (ids.contains(_wordAttribute(note, 'id')) &&
          (type == null || type == 'normal')) {
        blocks.add(parts.output(_wordText(note)));
      }
    }
  }
  return blocks;
}

Future<List<String>> _spreadsheet(_SearchParts parts) async {
  final main = await parts.mainPart('xl/workbook.xml');
  if (main == null) return [];
  final workbook = await parts.xml(main);
  final relations = await parts.package.relationships(main);
  final byId = {for (final relation in relations) relation.id: relation};
  final sheets = <({String part, String? name})>[];
  if (workbook == null) {
    if (await parts.read('_rels/.rels') != null) return [];
    sheets.addAll(
      parts
          .numberedParts(r'^xl/worksheets/sheet(\d+)\.xml$')
          .map((part) => (part: part, name: null)),
    );
  } else {
    for (final sheet in _elements(workbook, 'sheet')) {
      final relation = byId[_relationshipId(sheet)];
      if (relation != null && relation.isType('worksheet')) {
        sheets.add((part: relation.path, name: sheet.getAttribute('name')));
      }
    }
  }
  var sharedPath = relations
      .where((relation) => relation.isType('sharedStrings'))
      .firstOrNull
      ?.path;
  if (sharedPath == null && !await parts.hasRelationships(main)) {
    sharedPath = _sibling(main, 'sharedStrings.xml');
  }
  List<String>? shared;
  final result = <String>[];
  for (final sheet in sheets) {
    final document = await parts.xml(sheet.part);
    if (document == null) continue;
    if (sheet.name case final String name) result.add(parts.output(name));
    final cells = _elements(document, 'c').toList();
    if (cells.any((cell) => cell.getAttribute('t') == 's') && shared == null) {
      final strings = sharedPath == null ? null : await parts.xml(sharedPath);
      shared = [
        if (strings != null)
          for (final item in _elements(strings, 'si'))
            _elements(item, 't').map((text) => text.text).join(),
      ];
    }
    if (cells.isEmpty) {
      result.add(parts.output(_allText(document)));
      continue;
    }
    for (final cell in cells) {
      final value = cell.firstChild('v')?.text ?? '';
      switch (cell.getAttribute('t')) {
        case 's':
          final index = int.tryParse(value);
          if (index != null && index >= 0 && index < (shared?.length ?? 0)) {
            result.add(parts.output(shared![index]));
          }
        case 'inlineStr':
          result.add(
            parts.output(_elements(cell, 't').map((text) => text.text).join()),
          );
        default:
          result.add(parts.output(value));
      }
    }
  }
  return result;
}

String _slideText(XmlElement document) {
  final paragraphs = _elements(document, 'p').toList();
  return paragraphs.isEmpty
      ? _allText(document)
      : paragraphs
            .map(
              (paragraph) =>
                  _elements(paragraph, 't').map((text) => text.text).join(),
            )
            .where((text) => text.isNotEmpty)
            .join('\n');
}

Future<List<String>> _presentation(_SearchParts parts) async {
  final main = await parts.mainPart('ppt/presentation.xml');
  if (main == null) return [];
  final presentation = await parts.xml(main);
  final slides = <String>[];
  if (presentation == null) {
    if (await parts.read('_rels/.rels') != null) return [];
    slides.addAll(parts.numberedParts(r'^ppt/slides/slide(\d+)\.xml$'));
  } else {
    final relations = await parts.package.relationships(main);
    final byId = {for (final relation in relations) relation.id: relation};
    for (final slide in _elements(presentation, 'sldId')) {
      final relation = byId[_relationshipId(slide)];
      if (relation != null && relation.isType('slide')) {
        slides.add(relation.path);
      }
    }
  }
  final result = <String>[];
  final notesSeen = <String>{};
  for (final slide in slides) {
    final document = await parts.xml(slide);
    if (document == null) continue;
    result.add(parts.output(_slideText(document)));
    for (final relation in await parts.package.relationships(slide)) {
      if (!relation.isType('notesSlide') || !notesSeen.add(relation.path)) {
        continue;
      }
      final notes = await parts.xml(relation.path);
      if (notes != null) result.add(parts.output(_slideText(notes)));
    }
  }
  return result;
}
