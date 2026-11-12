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
          final separator = node.attributes.any(
            (a) =>
                a.name.local == 'type' &&
                {
                  'separator',
                  'continuationSeparator',
                  'continuationNotice',
                }.contains(a.value),
          );
          if (!separator) {
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
    if (source.hasObjects && counts['objects'] == 0) {
      losses.add(WordConversionLoss.objectsMissing);
    }
    if (source.hasHeaders && counts['headers']! + counts['footers']! == 0) {
      losses.add(WordConversionLoss.headersMissing);
    }
    if (source.hasFootnotes && counts['footnotes'] == 0) {
      losses.add(WordConversionLoss.footnotesMissing);
    }
    if (source.hasEndnotes && counts['endnotes'] == 0) {
      losses.add(WordConversionLoss.endnotesMissing);
    }
    if (source.hasComments && counts['comments'] == 0) {
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
