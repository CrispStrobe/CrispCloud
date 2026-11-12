import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'archive_viewer_service.dart';

import 'package:quds_office_engine/quds_office_engine.dart'
    show BoundedCfbReader, CfbfDirectoryEntry;

enum WordConversionInspectionIssue {
  invalidInput,
  encrypted,
  invalidOutput,
  tooLarge,
}

class WordConversionInspectionException implements Exception {
  const WordConversionInspectionException(this.issue);
  final WordConversionInspectionIssue issue;
}

enum WordConversionLoss {
  vbaMissing,
  vbaChanged,
  objectsMissing,
  headersMissing,
  footnotesMissing,
  endnotesMissing,
  commentsMissing,
}

/// Evidence from the binary source, without attempting to reconstruct layout.
class LegacyWordSourceInspection {
  const LegacyWordSourceInspection({
    this.vbaStreams = const {},
    this.hasVba = false,
    this.hasSignatureMarkers = false,
    this.hasObjects = false,
    this.hasHeaders = false,
    this.hasFootnotes = false,
    this.hasEndnotes = false,
    this.hasComments = false,
  });

  final Map<String, String> vbaStreams;
  final bool hasVba;
  final bool hasSignatureMarkers;
  final bool hasObjects;
  final bool hasHeaders;
  final bool hasFootnotes;
  final bool hasEndnotes;
  final bool hasComments;
}

/// Counts describe what the converter emitted. They are not proof of visual
/// equivalence, complete semantic preservation, or a valid digital signature.
/// Loss checks additionally require matching document anchors and relationships;
/// an unused package part or relationship cannot establish preservation. These
/// presence checks do not compare source/output feature counts or contents.
class WordConversionInspection {
  const WordConversionInspection({required this.counts, required this.losses});
  final Map<String, int> counts;
  final List<WordConversionLoss> losses;
}

const _maxPackage = 64 * 1024 * 1024;
const _maxExpanded = 128 * 1024 * 1024;
const _maxXml = 16 * 1024 * 1024;
const _wordNamespaces = {
  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  'http://purl.oclc.org/ooxml/wordprocessingml/main',
};
const _officeRelationshipNamespaces = {
  'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
  'http://purl.oclc.org/ooxml/officeDocument/relationships',
};
const _wordPartType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml';
const _storyPartTypes = {
  '$_wordPartType.header+xml': (kind: 'header', root: 'hdr'),
  '$_wordPartType.footer+xml': (kind: 'footer', root: 'ftr'),
  '$_wordPartType.footnotes+xml': (kind: 'footnotes', root: 'footnotes'),
  '$_wordPartType.endnotes+xml': (kind: 'endnotes', root: 'endnotes'),
  '$_wordPartType.comments+xml': (kind: 'comments', root: 'comments'),
};
const _documentType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
const _macroDocumentType =
    'application/vnd.ms-word.document.macroEnabled.main+xml';

LegacyWordSourceInspection inspectLegacyWordSource(Uint8List bytes) {
  if (bytes.length > _maxPackage) {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.tooLarge,
    );
  }
  try {
    final cfb = BoundedCfbReader(bytes, maxStreamBytes: _maxPackage);
    final word = cfb.readPath('WordDocument');
    if (word == null || word.length < 32) throw const FormatException();
    final fib = ByteData.sublistView(word);
    if (fib.getUint16(0, Endian.little) != 0xa5ec) {
      throw const FormatException();
    }
    if ((fib.getUint16(10, Endian.little) & 0x8100) != 0) {
      throw const WordConversionInspectionException(
        WordConversionInspectionIssue.encrypted,
      );
    }
    var headers = false;
    var footnotes = false;
    var endnotes = false;
    var comments = false;
    // [MS-DOC] FibRgLw97 story character counts; no fixed CLX offsets or
    // unreferenced byte scanning. These counts establish presence only.
    if (word.length >= 154 &&
        fib.getUint16(32, Endian.little) == 14 &&
        fib.getUint16(62, Endian.little) == 22) {
      bool story(int index) {
        final count = fib.getInt32(64 + index * 4, Endian.little);
        if (count < 0) throw const FormatException();
        return count > 0;
      }

      footnotes = story(4);
      if (story(5)) {
        // ccpHdd includes footnote/endnote separators. Only the stories after
        // those first six PlcfHdd entries establish actual headers/footers.
        headers = _hasHeaders(cfb, fib);
      }
      comments = story(7);
      endnotes = story(8);
    }
    final macroRoot =
        cfb.child(cfb.root, 'Macros') ??
        cfb.child(cfb.root, '_VBA_PROJECT_CUR');
    final directVba = cfb.child(cfb.root, 'VBA');
    final streams = <String, String>{};
    if (macroRoot?.isStorage == true) {
      _hashStreams(cfb, macroRoot!, '', streams);
    } else if (directVba?.isStorage == true) {
      _hashStreams(cfb, directVba!, 'VBA/', streams);
      for (final name in ['PROJECT', 'PROJECTwm']) {
        final entry = cfb.child(cfb.root, name);
        if (entry?.isStream == true) {
          streams[name.toUpperCase()] = sha256
              .convert(cfb.readEntry(entry!))
              .toString();
        }
      }
    }
    var signature = false;
    final pending = [cfb.root];
    while (pending.isNotEmpty) {
      for (final child in cfb.childrenOf(pending.removeLast())) {
        final name = child.name.toLowerCase();
        if (name.contains('digitalsignature') ||
            name.contains('vbasignature')) {
          signature = true;
        }
        if (child.isStorage) pending.add(child);
      }
    }
    final objects = cfb.child(cfb.root, 'ObjectPool');
    return LegacyWordSourceInspection(
      hasVba: macroRoot?.isStorage == true || directVba?.isStorage == true,
      vbaStreams: Map.unmodifiable(streams),
      hasSignatureMarkers: signature,
      hasObjects: objects != null && cfb.childrenOf(objects).isNotEmpty,
      hasHeaders: headers,
      hasFootnotes: footnotes,
      hasEndnotes: endnotes,
      hasComments: comments,
    );
  } on WordConversionInspectionException {
    rethrow;
  } catch (_) {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.invalidInput,
    );
  }
}

bool _hasHeaders(BoundedCfbReader cfb, ByteData fib) {
  const pair = 154 + 11 * 8; // FibRgFcLcb97.fcPlcfHdd/lcbPlcfHdd.
  if (fib.lengthInBytes < pair + 8 || fib.getUint16(152, Endian.little) < 12) {
    throw const FormatException();
  }
  final offset = fib.getUint32(pair, Endian.little);
  final length = fib.getUint32(pair + 4, Endian.little);
  final table = cfb.readPath(
    (fib.getUint16(10, Endian.little) & 0x0200) != 0 ? '1Table' : '0Table',
  );
  if (table == null ||
      length < 32 ||
      length % 4 != 0 ||
      offset > table.length ||
      length > table.length - offset) {
    throw const FormatException();
  }
  final cp = ByteData.sublistView(table, offset, offset + length);
  final count = length ~/ 4;
  final characters = fib.getInt32(64 + 5 * 4, Endian.little);
  var previous = -1;
  var hasHeader = false;
  // The final CP is undefined; the preceding CP ends the final story.
  for (var i = 0; i < count - 1; i++) {
    final current = cp.getInt32(i * 4, Endian.little);
    if (current < 0 || current < previous || current >= characters) {
      throw const FormatException();
    }
    if (i > 6 && current > previous) hasHeader = true;
    previous = current;
  }
  if (previous != characters - 1) throw const FormatException();
  return hasHeader;
}

void _hashStreams(
  BoundedCfbReader cfb,
  CfbfDirectoryEntry storage,
  String prefix,
  Map<String, String> output, [
  int depth = 0,
]) {
  if (depth > 64) {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.tooLarge,
    );
  }
  for (final entry in cfb.childrenOf(storage)) {
    final name = '$prefix${entry.name}'.toUpperCase();
    if (entry.isStorage) {
      _hashStreams(cfb, entry, '$name/', output, depth + 1);
    } else if (entry.isStream) {
      if (output.length >= 4096) {
        throw const WordConversionInspectionException(
          WordConversionInspectionIssue.tooLarge,
        );
      }
      if (output.containsKey(name)) throw const FormatException();
      output[name] = sha256.convert(cfb.readEntry(entry)).toString();
    }
  }
}

/// Validates the produced OPC package and inventories its existing parts.
/// Does not rewrite, normalize, execute or fetch any package content.
Future<WordConversionInspection> inspectConvertedWord(
  Uint8List bytes, {
  required String extension,
  required LegacyWordSourceInspection source,
}) async {
  if (bytes.length > _maxPackage) {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.tooLarge,
    );
  }
  if (extension != 'docx' && extension != 'docm') {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.invalidOutput,
    );
  }
  ViewerArchive? archive;
  try {
    archive = await openViewerArchive(bytes, name: 'converted.$extension');
    if (archive.formatName.toLowerCase() != 'zip' ||
        archive.members.length > 4096) {
      throw const FormatException();
    }
    final members = <String, ViewerArchiveMember>{};
    var expanded = 0;
    for (final member in archive.members) {
      if (member.pathEscapedRoot || member.isSpecial || member.isEncrypted) {
        throw const FormatException();
      }
      if (!member.isFile) continue;
      if (members.containsKey(member.name)) throw const FormatException();
      expanded += member.size;
      if (member.size > _maxPackage || expanded > _maxExpanded) {
        throw const WordConversionInspectionException(
          WordConversionInspectionIssue.tooLarge,
        );
      }
      members[member.name] = member;
    }
    final read = <String, Uint8List>{};
    Future<Uint8List> part(String name) async {
      if (read.containsKey(name)) return read[name]!;
      final entry = members[name];
      if (entry == null) throw const FormatException();
      final data = await archive!.readMember(entry, maxBytes: _maxPackage);
      if (data.length != entry.size) throw const FormatException();
      read[name] = data;
      return data;
    }

    var xmlEvents = 0;
    XmlDocument xml(Uint8List data) {
      if (data.length > _maxXml) {
        throw const WordConversionInspectionException(
          WordConversionInspectionIssue.tooLarge,
        );
      }
      final text = utf8.decode(data);
      var depth = 0;
      for (final event in parseEvents(text)) {
        if (++xmlEvents > 800000) {
          throw const WordConversionInspectionException(
            WordConversionInspectionIssue.tooLarge,
          );
        }
        if (event is XmlDoctypeEvent) throw const FormatException();
        if (event is XmlStartElementEvent && !event.isSelfClosing) {
          if (++depth > 128) {
            throw const WordConversionInspectionException(
              WordConversionInspectionIssue.tooLarge,
            );
          }
        } else if (event is XmlEndElementEvent) {
          depth--;
        }
      }
      return XmlDocument.parse(text);
    }

    final types = xml(await part('[Content_Types].xml'));
    if (types.rootElement.name.local != 'Types' ||
        types.rootElement.namespaceUri !=
            'http://schemas.openxmlformats.org/package/2006/content-types') {
      throw const FormatException();
    }
    final overrides = <String, String>{};
    final defaults = <String, String>{};
    for (final element in types.rootElement.childElements) {
      if (element.namespaceUri != types.rootElement.namespaceUri) {
        throw const FormatException();
      }
      final type = element.getAttribute('ContentType');
      if (type == null || type.isEmpty) throw const FormatException();
      if (element.name.local == 'Override') {
        final name = element.getAttribute('PartName');
        if (name == null ||
            !name.startsWith('/') ||
            overrides.containsKey(name.substring(1))) {
          throw const FormatException();
        }
        overrides[name.substring(1)] = type;
      } else if (element.name.local == 'Default') {
        final ext = element.getAttribute('Extension')?.toLowerCase();
        if (ext == null || ext.isEmpty || defaults.containsKey(ext)) {
          throw const FormatException();
        }
        defaults[ext] = type;
      } else {
        throw const FormatException();
      }
    }
    String typeOf(String name) =>
        overrides[name] ?? defaults[name.split('.').last.toLowerCase()] ?? '';
    final rootRels = xml(await part('_rels/.rels'));
    final mainRels = rootRels.rootElement.childElements
        .where(
          (element) => const {
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument',
          }.contains(element.getAttribute('Type')),
        )
        .toList();
    if (mainRels.length != 1 ||
        mainRels.single.getAttribute('TargetMode') == 'External') {
      throw const FormatException();
    }
    final main = _relationshipTarget(
      '',
      mainRels.single.getAttribute('Target') ?? '',
    );
    final expected = extension == 'docm' ? _macroDocumentType : _documentType;
    if (typeOf(main) != expected) throw const FormatException();
    final document = xml(await part(main));
    if (document.rootElement.name.local != 'document' ||
        !_wordNamespaces.contains(document.rootElement.namespaceUri) ||
        document.rootElement.childElements
                .where(
                  (e) =>
                      e.name.local == 'body' &&
                      e.namespaceUri == document.rootElement.namespaceUri,
                )
                .length !=
            1) {
      throw const FormatException();
    }
    final counts = <String, int>{
      for (final key in [
        'paragraphs',
        'sections',
        'tables',
        'cells',
        'images',
        'objects',
        'headers',
        'footers',
        'footnotes',
        'endnotes',
        'comments',
        'revisions',
        'vba',
        'signatures',
      ])
        key: 0,
    };
    final vbaProjects = <String, Map<String, String>>{};
    final internalRelationships =
        <String, Map<String, ({String kind, String target})>>{};
    final storyParts = <String, _WordInspectionStory>{};
    String? documentVba;
    const revisions = {
      'ins',
      'del',
      'moveFrom',
      'moveTo',
      'pPrChange',
      'rPrChange',
      'tblPrChange',
      'trPrChange',
      'tcPrChange',
      'sectPrChange',
      'cellIns',
      'cellDel',
      'cellMerge',
      'numberingChange',
    };
    for (final name in members.keys) {
      final data = await part(name); // Every member is bounded and CRC-checked.
      final lower = name.toLowerCase();
      final type = typeOf(name).toLowerCase();
      if (type.startsWith('image/')) counts['images'] = counts['images']! + 1;
      if (lower.contains('/embeddings/') || type.contains('oleobject')) {
        counts['objects'] = counts['objects']! + 1;
      }
      if (lower.startsWith('_xmlsignatures/') ||
          type.contains('digital-signature') ||
          lower.contains('vbaprojectsignature')) {
        counts['signatures'] = counts['signatures']! + 1;
      }
      if (type == 'application/vnd.ms-office.vbaproject') {
        counts['vba'] = counts['vba']! + 1;
        final cfb = BoundedCfbReader(data);
        final streams = <String, String>{};
        _hashStreams(cfb, cfb.root, '', streams);
        vbaProjects[name] = streams;
      }
      if (name.endsWith('.rels')) {
        final relationships = name == '_rels/.rels' ? rootRels : xml(data);
        if (relationships.rootElement.name.local != 'Relationships' ||
            relationships.rootElement.namespaceUri !=
                'http://schemas.openxmlformats.org/package/2006/relationships') {
          throw const FormatException();
        }
        final ids = <String>{};
        final owner = _relationshipOwner(name);
        if (owner.isNotEmpty && !members.containsKey(owner)) {
          throw const FormatException();
        }
        for (final rel in relationships.rootElement.childElements) {
          final id = rel.getAttribute('Id');
          if (rel.name.local != 'Relationship' ||
              rel.namespaceUri != relationships.rootElement.namespaceUri ||
              id == null ||
              id.isEmpty ||
              !ids.add(id) ||
              (rel.getAttribute('Type') ?? '').isEmpty) {
            throw const FormatException();
          }
          final mode = rel.getAttribute('TargetMode');
          final isDocumentVba =
              owner == main &&
              rel.getAttribute('Type') ==
                  'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
          if (isDocumentVba && mode == 'External') {
            throw const FormatException();
          }
          if (mode == 'External') continue; // Retain the link; never fetch it.
          if (mode != null && mode != 'Internal') throw const FormatException();
          final target = _relationshipTarget(
            owner,
            rel.getAttribute('Target') ?? '',
          );
          if (!members.containsKey(target)) throw const FormatException();
          final kind = _officeRelationshipKind(rel.getAttribute('Type')!);
          if (kind != null) {
            internalRelationships.putIfAbsent(owner, () => {})[id] = (
              kind: kind,
              target: target,
            );
          }
          if (isDocumentVba) {
            if (documentVba != null) throw const FormatException();
            documentVba = target;
          }
        }
      }
      final story =
          name == main ||
          type.contains('wordprocessingml.header') ||
          type.contains('wordprocessingml.footer') ||
          type.contains('wordprocessingml.footnotes') ||
          type.contains('wordprocessingml.endnotes') ||
          type.contains('wordprocessingml.comments');
      if (!story) continue;
      final dom = name == main ? document : xml(data);
      if (!_wordNamespaces.contains(dom.rootElement.namespaceUri)) {
        throw const FormatException();
      }
      final storyType = _storyPartTypes[type];
      if (storyType != null) {
        if (dom.rootElement.name.local != storyType.root) {
          throw const FormatException();
        }
        final itemName = switch (storyType.kind) {
          'footnotes' => 'footnote',
          'endnotes' => 'endnote',
          'comments' => 'comment',
          _ => null,
        };
        final items = <String, XmlElement?>{};
        if (itemName != null) {
          for (final element in dom.rootElement.childElements) {
            if (element.namespaceUri != dom.rootElement.namespaceUri ||
                element.name.local != itemName ||
                (itemName != 'comment' && _isNoteSeparator(element))) {
              continue;
            }
            final id = _wordInspectionId(element);
            if (id != null) {
              // Ambiguous duplicate identifiers cannot establish which content
              // an anchor preserves, even if a renderer chooses one definition.
              items[id] = items.containsKey(id) ? null : element;
            }
          }
        }
        storyParts[name] = _WordInspectionStory(
          storyType.kind,
          dom.rootElement,
          items,
        );
      }
      if (dom.rootElement.name.local == 'hdr') {
        counts['headers'] = counts['headers']! + 1;
      }
      if (dom.rootElement.name.local == 'ftr') {
        counts['footers'] = counts['footers']! + 1;
      }
      for (final node in dom.descendants.whereType<XmlElement>()) {
        if (!_wordNamespaces.contains(node.namespaceUri)) continue;
        final local = node.name.local;
        final key = switch (local) {
          'p' => 'paragraphs',
          'sectPr' => 'sections',
          'tbl' => 'tables',
          'tc' => 'cells',
          'comment' => 'comments',
          _ => null,
        };
        if (key != null) counts[key] = counts[key]! + 1;
        if (revisions.contains(local)) {
          counts['revisions'] = counts['revisions']! + 1;
        }
        if (local == 'footnote' || local == 'endnote') {
          if (!_isNoteSeparator(node)) {
            final key = local == 'footnote' ? 'footnotes' : 'endnotes';
            counts[key] = counts[key]! + 1;
          }
        }
      }
    }
    if (extension == 'docx' && counts['vba']! > 0) {
      throw const FormatException();
    }
    if (documentVba != null && !vbaProjects.containsKey(documentVba)) {
      throw const FormatException();
    }
    // ECMA-376 Part 1, 11.3.2/.4/.6/.7/.9: document stories belong to the
    // Main Document part. Glossary-owned copies are separate content, even
    // when the glossary itself is reachable. 15.2.9/.10 allow objects/packages
    // to belong to main, comments, endnotes, footnotes, headers or footers.
    // https://download.microsoft.com/download/e/1/4/e14fb96f-83b8-4a2a-84db-7fa8acbe061a/Office%20Open%20XML%20Part%201%20-%20Fundamentals.pdf
    // References, not relationships alone, attach these parts to content.
    // ECMA-376 17.10.5/.2, 17.11.14/.3 and 17.13.4.5 define the header/footer,
    // note and comment anchors. Unreferenced definitions remain inventory only.
    final documentStories = <String, String>{};
    for (final relationship
        in internalRelationships[main]?.values ??
            const <({String kind, String target})>[]) {
      if (!const {
        'header',
        'footer',
        'footnotes',
        'endnotes',
        'comments',
      }.contains(relationship.kind)) {
        continue;
      }
      final story = storyParts[relationship.target];
      if (story == null || story.kind != relationship.kind) {
        throw const FormatException();
      }
      if (const {'footnotes', 'endnotes', 'comments'}.contains(story.kind)) {
        final previous = documentStories[story.kind];
        if (previous != null && previous != relationship.target) {
          throw const FormatException();
        }
        documentStories[story.kind] = relationship.target;
      }
    }
    final reachableFeatures = <String>{};
    final pending = <({String owner, XmlElement content})>[
      (
        owner: main,
        content: document.rootElement.childElements.singleWhere(
          (element) =>
              element.name.local == 'body' &&
              element.namespaceUri == document.rootElement.namespaceUri,
        ),
      ),
    ];
    final visited = {pending.single.content};
    void attach(String owner, XmlElement content) {
      if (visited.add(content)) pending.add((owner: owner, content: content));
    }

    var hasReachableObjects = false;
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final node in _wordInspectionContent(current.content)) {
        final local = node.name.local;
        final isWord = _wordNamespaces.contains(node.namespaceUri);
        final relationshipId = _wordInspectionRelationshipId(node);
        final relationship =
            internalRelationships[current.owner]?[relationshipId];
        if (isWord &&
            current.owner == main &&
            const {'headerReference', 'footerReference'}.contains(local) &&
            _wordInspectionParent(node, 'sectPr')) {
          final kind = local == 'headerReference' ? 'header' : 'footer';
          if (relationship?.kind == kind) {
            final story = storyParts[relationship!.target]!;
            reachableFeatures.add(kind);
            attach(relationship.target, story.root);
          }
        }
        final itemKind = isWord && _wordInspectionRunParent(node)
            ? switch (local) {
                'footnoteReference' => 'footnotes',
                'endnoteReference' => 'endnotes',
                'commentReference' => 'comments',
                _ => null,
              }
            : null;
        if (itemKind != null) {
          final id = _wordInspectionId(node);
          final target = documentStories[itemKind];
          final item = storyParts[target]?.items[id];
          if (target != null && item != null) {
            reachableFeatures.add(itemKind);
            attach(target, item);
          }
        }
        // Embedded-object relationships are explicit: the referenced data
        // belongs to w:objectEmbed or o:OLEObject, not any arbitrary r:id.
        final object =
            (isWord &&
                local == 'objectEmbed' &&
                _wordInspectionParent(node, 'object')) ||
            (node.namespaceUri == 'urn:schemas-microsoft-com:office:office' &&
                local == 'OLEObject' &&
                node.getAttribute('Type') != 'Link' &&
                (_wordInspectionParent(node, 'object') ||
                    _wordInspectionParent(node, 'pict')));
        if (!object || relationship == null) continue;
        final target = relationship.target;
        final type = typeOf(target).toLowerCase();
        if (target == main ||
            target == '[Content_Types].xml' ||
            target.endsWith('.rels') ||
            storyParts.containsKey(target) ||
            _isOfficeStructuralPartType(type)) {
          continue;
        }
        hasReachableObjects |= switch (relationship.kind) {
          'oleObject' =>
            type == 'application/vnd.openxmlformats-officedocument.oleobject',
          // Later ECMA editions allow arbitrary package MIME types.
          // MS-OI29500 3.10 describes the content-type-specific handling:
          // https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/32be961f-d71a-4812-913f-b675c79aa88a
          'package' => type.isNotEmpty,
          _ => false,
        };
      }
    }
    final vbaStreams = vbaProjects[documentVba];
    final losses = <WordConversionLoss>[];
    if (source.hasVba) {
      if (vbaStreams == null) {
        losses.add(WordConversionLoss.vbaMissing);
      } else if (vbaStreams.length != source.vbaStreams.length ||
          source.vbaStreams.entries.any(
            (entry) => vbaStreams[entry.key] != entry.value,
          )) {
        losses.add(WordConversionLoss.vbaChanged);
      }
    }
    if (source.hasObjects && !hasReachableObjects) {
      losses.add(WordConversionLoss.objectsMissing);
    }
    if (source.hasHeaders &&
        !reachableFeatures.contains('header') &&
        !reachableFeatures.contains('footer')) {
      losses.add(WordConversionLoss.headersMissing);
    }
    if (source.hasFootnotes && !reachableFeatures.contains('footnotes')) {
      losses.add(WordConversionLoss.footnotesMissing);
    }
    if (source.hasEndnotes && !reachableFeatures.contains('endnotes')) {
      losses.add(WordConversionLoss.endnotesMissing);
    }
    if (source.hasComments && !reachableFeatures.contains('comments')) {
      losses.add(WordConversionLoss.commentsMissing);
    }
    return WordConversionInspection(
      counts: Map.unmodifiable(counts),
      losses: List.unmodifiable(losses),
    );
  } on WordConversionInspectionException {
    rethrow;
  } catch (_) {
    throw const WordConversionInspectionException(
      WordConversionInspectionIssue.invalidOutput,
    );
  } finally {
    await archive?.close();
  }
}

class _WordInspectionStory {
  const _WordInspectionStory(this.kind, this.root, this.items);

  final String kind;
  final XmlElement root;
  final Map<String, XmlElement?> items;
}

bool _wordInspectionParent(XmlElement element, String local) {
  final parent = element.parent;
  return parent is XmlElement &&
      parent.name.local == local &&
      _wordNamespaces.contains(parent.namespaceUri);
}

bool _wordInspectionRunParent(XmlElement element) {
  final parent = element.parent;
  return parent is XmlElement &&
      parent.name.local == 'r' &&
      (_wordNamespaces.contains(parent.namespaceUri) ||
          const {
            'http://schemas.openxmlformats.org/officeDocument/2006/math',
            'http://purl.oclc.org/ooxml/officeDocument/math',
          }.contains(parent.namespaceUri));
}

String? _wordInspectionRelationshipId(XmlElement element) {
  final attributes = element.attributes.where(
    (attribute) =>
        attribute.name.local == 'id' &&
        _officeRelationshipNamespaces.contains(attribute.namespaceUri),
  );
  return attributes.length == 1 ? attributes.single.value : null;
}

String? _wordInspectionId(XmlElement element) {
  final value = element
      .getAttribute('id', namespace: element.namespaceUri)
      ?.trim();
  if (value == null || !RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final digits = value
      .replaceFirst(RegExp(r'^[+-]'), '')
      .replaceFirst(RegExp(r'^0+(?=.)'), '');
  return value.startsWith('-') && digits != '0' ? '-$digits' : digits;
}

Iterable<XmlElement> _wordInspectionContent(XmlElement root) sync* {
  final pending = [root];
  while (pending.isNotEmpty) {
    final element = pending.removeLast();
    // Old property snapshots do not attach a header to the current section.
    if (_wordNamespaces.contains(element.namespaceUri) &&
        const {
          'sectPrChange',
          'pPrChange',
          'rPrChange',
          'tblPrChange',
          'tblPrExChange',
          'trPrChange',
          'tcPrChange',
        }.contains(element.name.local)) {
      continue;
    }
    yield element;
    pending.addAll(element.childElements);
  }
}

String? _officeRelationshipKind(String type) {
  for (final namespace in _officeRelationshipNamespaces) {
    if (type.startsWith('$namespace/')) {
      return type.substring(namespace.length + 1);
    }
  }
  return null;
}

bool _isNoteSeparator(XmlElement element) => element.attributes.any(
  (attribute) =>
      _wordNamespaces.contains(attribute.namespaceUri) &&
      attribute.name.local == 'type' &&
      const {
        'separator',
        'continuationSeparator',
        'continuationNotice',
      }.contains(attribute.value),
);

bool _isOfficeStructuralPartType(String type) =>
    type.endsWith('+xml') &&
    (type.startsWith('application/vnd.openxmlformats-officedocument.') ||
        type.startsWith('application/vnd.openxmlformats-package.') ||
        type.startsWith('application/vnd.ms-word.'));

String _relationshipOwner(String name) {
  if (name == '_rels/.rels') return '';
  if (!name.endsWith('.rels') ||
      p.posix.basename(p.posix.dirname(name)) != '_rels') {
    throw const FormatException();
  }
  return p.posix.join(
    p.posix.dirname(p.posix.dirname(name)),
    p.posix.basename(name).substring(0, p.posix.basename(name).length - 5),
  );
}

String _relationshipTarget(String owner, String target) {
  final uri = Uri.tryParse(target);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      target.contains('\\')) {
    throw const FormatException();
  }
  final decoded = Uri.decodeComponent(uri.path);
  if (decoded.contains('\\')) throw const FormatException();
  final result = decoded.isEmpty
      ? owner
      : p.posix.normalize(
          decoded.startsWith('/')
              ? decoded.substring(1)
              : p.posix.join(
                  owner.isEmpty ? '' : p.posix.dirname(owner),
                  decoded,
                ),
        );
  if (result.isEmpty ||
      result == '.' ||
      result == '..' ||
      result.startsWith('../') ||
      result.startsWith('/')) {
    throw const FormatException();
  }
  return result;
}
