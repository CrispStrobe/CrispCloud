import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import 'archive_viewer_service.dart';
import 'office_package_parts.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _strictW = 'http://purl.oclc.org/ooxml/wordprocessingml/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _strictR = 'http://purl.oclc.org/ooxml/officeDocument/relationships';

bool _isWord(XmlElement element) =>
    element.namespaceUri == _w || element.namespaceUri == _strictW;
Iterable<XmlElement> _wordElements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: '*').where(_isWord);
String? _wordAttribute(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w) ??
    element.getAttribute(name, namespace: _strictW);
String? _relationshipId(XmlElement element) =>
    element.getAttribute('id', namespace: _r) ??
    element.getAttribute('id', namespace: _strictR);

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

/// Extract referenced Office text without activating macros or external parts.
/// XML reads and emitted UTF-8 text each have the cumulative byte limit.
Future<String> officeSearchText(
  Uint8List bytes,
  String name,
  int maxBytes,
) async {
  final archive = await openViewerArchive(
    bytes,
    name: name,
    maxMemberBytes: maxBytes,
  );
  try {
    final parts = _SearchParts(archive, maxBytes);
    final extension = path.posix.extension(name).toLowerCase();
    final blocks = switch (extension) {
      '.docx' || '.docm' => await _word(parts),
      '.xlsx' || '.xlsm' => await _spreadsheet(parts),
      '.pptx' || '.pptm' => await _presentation(parts),
      '.odt' || '.ods' || '.odp' => [
        if (await parts.xml('content.xml') case final XmlDocument document)
          parts.output(_allText(document)),
      ],
      _ => <String>[],
    };
    return blocks.where((text) => text.isNotEmpty).join('\n');
  } finally {
    await archive.close();
  }
}

class _SearchParts {
  _SearchParts(this.archive, this.maxBytes);
  final ViewerArchive archive;
  final int maxBytes;
  final _cache = <String, String?>{};
  var _used = 0;
  var _outputBytes = 0;
  var _outputParts = 0;
  late final package = OfficePackageParts(read);

  String output(String text) {
    if (text.isEmpty) return text;
    final length = utf8.encode(text).length + (_outputParts > 0 ? 1 : 0);
    if (length > maxBytes - _outputBytes) {
      throw const ArchiveViewException(
        'Office text exceeds the content limit.',
      );
    }
    _outputBytes += length;
    _outputParts++;
    return text;
  }

  Iterable<ViewerArchiveMember> get members => archive.members.where(
    (member) => member.isFile && !member.isSpecial && !member.pathEscapedRoot,
  );

  Future<String?> read(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    final member = members.where((entry) => entry.name == name).firstOrNull;
    if (member == null) return _cache[name] = null;
    if (_used >= maxBytes) {
      throw const ArchiveViewException(
        'Office text exceeds the content limit.',
      );
    }
    final content = await archive.readMember(
      member,
      maxBytes: maxBytes - _used,
    );
    _used += content.length;
    if (_used > maxBytes) {
      throw const ArchiveViewException(
        'Office text exceeds the content limit.',
      );
    }
    return _cache[name] = utf8.decode(content);
  }

  Future<XmlDocument?> xml(String name) async {
    final text = await read(name);
    return text == null ? null : XmlDocument.parse(text);
  }

  Future<String?> mainPart(String fallback) async {
    // A declared package graph is authoritative. Only absent metadata permits
    // the canonical fallback used by minimal/legacy extraction fixtures.
    if (await read('_rels/.rels') == null) return fallback;
    return (await package.relationships(''))
        .where((relationship) => relationship.isType('officeDocument'))
        .firstOrNull
        ?.path;
  }

  Future<bool> hasRelationships(String owner) async =>
      await read(OfficePackageParts.relationshipPath(owner)) != null;

  List<String> numberedParts(String pattern) {
    final expression = RegExp(pattern);
    return members
        .map((entry) => entry.name)
        .where(expression.hasMatch)
        .toList()
      ..sort(
        (a, b) =>
            int.parse(expression.firstMatch(a)!.group(1)!)
                .compareTo(int.parse(expression.firstMatch(b)!.group(1)!)),
      );
  }
}

String _allText(XmlNode node) => node.descendants
    .whereType<XmlText>()
    .map((text) => text.value)
    .join(' ')
    .trim();

String _wordText(XmlNode node) {
  if (_wordElements(node, 't').isEmpty) return _allText(node);
  final buffer = StringBuffer();
  void visit(XmlNode item) {
    if (item is! XmlElement) return;
    if (_isWord(item)) {
      switch (item.localName) {
        case 't':
          buffer.write(item.innerText);
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

  if (node is XmlElement) {
    visit(node);
  } else {
    for (final child in node.children) {
      visit(child);
    }
  }
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
  final stories = <XmlNode>[document];
  final seen = <String>{main};
  for (final reference in document.descendants.whereType<XmlElement>()) {
    final kind = switch (reference.localName) {
      'headerReference' => 'header',
      'footerReference' => 'footer',
      _ => null,
    };
    if (!_isWord(reference) ||
        kind == null ||
        reference.ancestors.whereType<XmlElement>().any(
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
      notePath = path.posix.normalize(
        path.posix.join(path.posix.dirname(main), '${kind}s.xml'),
      );
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
    for (final sheet in workbook.findAllElements('sheet', namespace: '*')) {
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
    sharedPath = path.posix.normalize(
      path.posix.join(path.posix.dirname(main), 'sharedStrings.xml'),
    );
  }
  List<String>? shared;
  final result = <String>[];
  for (final sheet in sheets) {
    final document = await parts.xml(sheet.part);
    if (document == null) continue;
    if (sheet.name case final String name) result.add(parts.output(name));
    final cells = document.findAllElements('c', namespace: '*').toList();
    if (cells.any((cell) => cell.getAttribute('t') == 's') && shared == null) {
      final strings = sharedPath == null ? null : await parts.xml(sharedPath);
      shared = [
        if (strings != null)
          for (final item in strings.findAllElements('si', namespace: '*'))
            item
                .findAllElements('t', namespace: '*')
                .map((text) => text.innerText)
                .join(),
      ];
    }
    if (cells.isEmpty) {
      result.add(parts.output(_allText(document)));
      continue;
    }
    for (final cell in cells) {
      final value =
          cell.findElements('v', namespace: '*').firstOrNull?.innerText ?? '';
      switch (cell.getAttribute('t')) {
        case 's':
          final index = int.tryParse(value);
          if (index != null && index >= 0 && index < (shared?.length ?? 0)) {
            result.add(parts.output(shared![index]));
          }
        case 'inlineStr':
          result.add(
            parts.output(
              cell
                  .findAllElements('t', namespace: '*')
                  .map((text) => text.innerText)
                  .join(),
            ),
          );
        default:
          result.add(parts.output(value));
      }
    }
  }
  return result;
}

String _slideText(XmlNode document) {
  final paragraphs = document.findAllElements('p', namespace: '*').toList();
  return paragraphs.isEmpty
      ? _allText(document)
      : paragraphs
            .map(
              (paragraph) => paragraph
                  .findAllElements('t', namespace: '*')
                  .map((text) => text.innerText)
                  .join(),
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
    for (final slide in presentation.findAllElements('sldId', namespace: '*')) {
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
