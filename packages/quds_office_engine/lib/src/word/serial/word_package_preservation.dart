import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../opc/content_types.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../opc/zip/deflate_codec.dart';
import '../../opc/zip/zip_reader.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';

/// Bounds for inspecting macro/template metadata and opaque payloads.
///
/// Unrelated document/media parts remain lazy. Both declared and actual
/// expanded sizes are checked before growing a part's output buffer.
class WordPackagePreservationLimits {
  const WordPackagePreservationLimits({
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxPartBytes = 32 * 1024 * 1024,
    this.maxTotalReadBytes = 64 * 1024 * 1024,
    this.maxEntries = 200000,
  });

  final int maxFileBytes;
  final int maxPartBytes;
  final int maxTotalReadBytes;
  final int maxEntries;
}

/// Checks the additional invariants for editing Word macro documents/templates.
///
/// The Word serializer retains imported OPC parts. Capture a guard before
/// editing and validate serialized bytes before replacing the original. The
/// guard checks the original main part and MIME type, opaque binary/VBA payloads
/// and their relationships. It never runs macros or rewrites package contents.
///
/// A host remains responsible for presenting errors, retaining unsaved edits
/// and uploading only bytes that passed [validateSaved].
class WordPackagePreservation {
  WordPackagePreservation._(this._snapshot, this._limits);

  final _WordSnapshot _snapshot;
  final WordPackagePreservationLimits _limits;

  static const contentTypesByExtension = <String, String>{
    'docm': 'application/vnd.ms-word.document.macroEnabled.main+xml',
    'dotm': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
    'dotx': OfficeContentTypes.wordTemplate,
  };

  /// Returns null for formats that do not require the macro/template guard.
  ///
  /// The asynchronous signature permits callers to retain one save boundary
  /// across synchronous and asynchronous Office serializers.
  static Future<WordPackagePreservation?> capture(
    Uint8List bytes,
    String filename, {
    WordPackagePreservationLimits limits =
        const WordPackagePreservationLimits(),
  }) async {
    final expected =
        contentTypesByExtension[filename.split('.').last.toLowerCase()];
    if (expected == null) return null;
    _validateLimits(limits);
    final snapshot = _readSnapshot(bytes, limits);
    if (snapshot.mainType != expected) {
      throw const FormatException(
        'The Word package type does not match its filename. Open it in Word and save with the correct extension.',
      );
    }
    return WordPackagePreservation._(snapshot, limits);
  }

  Future<void> validateSaved(Uint8List bytes) async {
    final current = _readSnapshot(bytes, _limits);
    if (current.mainPath != _snapshot.mainPath ||
        current.mainType != _snapshot.mainType) {
      throw const FormatException(
        'Saving would change the Word macro/template type. The original was not changed.',
      );
    }
    for (final part in _snapshot.protectedParts.entries) {
      if (current.protectedParts[part.key] != part.value) {
        throw const FormatException(
          'Saving would change a preserved Word binary or macro part. The original was not changed.',
        );
      }
    }
    for (final relationship in _snapshot.protectedRelationships) {
      if (!current.protectedRelationships.contains(relationship)) {
        throw const FormatException(
          'Saving would remove a Word macro relationship. The original was not changed.',
        );
      }
    }
  }
}

class _WordSnapshot {
  const _WordSnapshot(
    this.mainPath,
    this.mainType,
    this.protectedParts,
    this.protectedRelationships,
  );

  final String mainPath;
  final String mainType;
  final Map<String, String> protectedParts;
  final Set<String> protectedRelationships;
}

const _limitMessage = 'Word package exceeds the safe editing limit.';

void _validateLimits(WordPackagePreservationLimits limits) {
  if (limits.maxFileBytes < 0 ||
      limits.maxPartBytes < 0 ||
      limits.maxTotalReadBytes < 0 ||
      limits.maxEntries < 0) {
    throw ArgumentError('Word package limits must be nonnegative');
  }
}

_WordSnapshot _readSnapshot(
  Uint8List bytes,
  WordPackagePreservationLimits limits,
) {
  if (bytes.length > limits.maxFileBytes) {
    throw const FormatException(_limitMessage);
  }
  try {
    final zip = ZipReader.fromBytes(
      bytes,
      maxEntries: limits.maxEntries,
      rejectDuplicateNames: true,
    );
    final members = <String, ZipEntry>{};
    for (final member in zip.entries.where((entry) => !entry.isDirectory)) {
      final path = member.fileName;
      // OPC names have one canonical, package-relative representation. Reject
      // aliases rather than hashing one part while the serializer opens another.
      if (path.isEmpty ||
          path.contains('\\') ||
          path.startsWith('/') ||
          OpcUris.toZipName(path) != path) {
        throw const FormatException('Invalid Word package part path.');
      }
      if (path.toLowerCase().startsWith('_xmlsignatures/')) {
        throw const FormatException(
          'This Word package is digitally signed. Save an unsigned copy in Word before editing it here.',
        );
      }
      members[path] = member;
    }

    var total = 0;
    Uint8List? read(String path) {
      final member = members[path];
      if (member == null) return null;
      final remaining = limits.maxTotalReadBytes - total;
      final cap = remaining < limits.maxPartBytes
          ? remaining
          : limits.maxPartBytes;
      if (cap < 0 || member.uncompressedSize > cap) {
        throw const FormatException(_limitMessage);
      }
      final value = zip.read(path, maxBytes: cap);
      total += value.length;
      return value;
    }

    String? readText(String path) {
      final value = read(path);
      return value == null ? null : utf8.decode(value);
    }

    final typesText = readText('[Content_Types].xml');
    if (typesText == null) {
      throw const FormatException('Word package content types are missing.');
    }
    _checkMetadata(typesText, 'Types', OfficeNamespaces.contentTypes);
    final types = ContentTypes.parse(typesText);
    String typeOf(String path) => types.contentTypeFor('/$path');

    final relationshipParts = <String, RelationshipCollection>{};
    for (final path in members.keys.where((path) => path.endsWith('.rels'))) {
      final text = readText(path)!;
      _checkMetadata(text, 'Relationships', OfficeNamespaces.relationships);
      relationshipParts[path] = RelationshipCollection.parse(
        text,
        OpcUris.sourcePartForRelationships('/$path') ?? '/',
      );
    }
    final main = _mainPart(relationshipParts['_rels/.rels']);
    if (!members.containsKey(main)) {
      throw const FormatException('The Word main document part is missing.');
    }
    bool opaque(String path) {
      final lower = path.toLowerCase();
      return lower.endsWith('.bin') ||
          lower.contains('vba') ||
          lower.startsWith('customui/') ||
          typeOf(path).toLowerCase().contains('vba');
    }

    final protectedParts = <String, String>{};
    final relationships = <String>{};
    for (final path in members.keys) {
      final partRelationships = relationshipParts[path];
      if (partRelationships != null) {
        final owner = OpcUris.sourcePartForRelationships('/$path');
        final opaqueOwner = owner != null && opaque(OpcUris.toZipName(owner));
        for (final rel in partRelationships.items) {
          final opaqueTarget =
              rel.targetMode == RelationshipTargetMode.internal &&
              opaque(OpcUris.toZipName(partRelationships.resolve(rel)));
          if (!opaque(path) &&
              !opaqueOwner &&
              !opaqueTarget &&
              !rel.type.toLowerCase().contains('vba') &&
              !rel.target.toLowerCase().contains('vba')) {
            continue;
          }
          relationships.add(
            jsonEncode([
              path,
              rel.id,
              rel.type,
              rel.target,
              rel.targetMode.name,
            ]),
          );
        }
      } else if (opaque(path)) {
        protectedParts[path] = '${typeOf(path)}:${sha256.convert(read(path)!)}';
      }
    }
    return _WordSnapshot(main, typeOf(main), protectedParts, relationships);
  } on ZipDuplicateEntryException {
    throw const FormatException('Duplicate Word package part.');
  } on ZipLimitException {
    throw const FormatException(_limitMessage);
  } on ZipException catch (error) {
    throw FormatException('Invalid Word package ZIP: ${error.message}');
  } on ZipDeflateException catch (error) {
    throw FormatException('Invalid Word package compression: ${error.message}');
  } on XmlParseException catch (error) {
    throw FormatException('Invalid Word package XML: ${error.message}');
  } on RangeError {
    throw const FormatException('Invalid Word package ZIP bounds.');
  }
}

String _mainPart(RelationshipCollection? relationships) {
  final candidates = relationships?.items.where(
    (relationship) =>
        relationship.type == RelationshipTypes.officeDocument ||
        relationship.type ==
            'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument',
  );
  if (candidates == null || candidates.isEmpty) return 'word/document.xml';
  if (candidates.length != 1) {
    throw const FormatException('Ambiguous Word main document relationship.');
  }
  final relationship = candidates.single;
  final uri = Uri.tryParse(relationship.target);
  if (relationship.targetMode == RelationshipTargetMode.external ||
      uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      relationship.target.contains('\\')) {
    throw const FormatException('Invalid Word main document relationship.');
  }
  final decoded = Uri.decodeComponent(uri.path);
  var depth = 0;
  for (final segment in decoded.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    depth += segment == '..' ? -1 : 1;
    if (depth < 0) {
      throw const FormatException('Invalid Word main document relationship.');
    }
  }
  if (depth == 0 || decoded.contains('\\')) {
    throw const FormatException('Invalid Word main document relationship.');
  }
  // Validate decoded traversal above, but use the same OPC part key as the
  // deserializer/serializer. Decoding a second, different lookup here could
  // validate one native part while the editor opens another.
  return OpcUris.toZipName(OpcUris.resolve('/', relationship.target));
}

void _checkMetadata(String xml, String rootName, String namespace) {
  final reader = XmlPullReader(xml);
  var roots = 0;
  var depth = 0;
  while (reader.next()) {
    switch (reader.eventType) {
      case XmlEventType.startElement:
        if (depth == 0) {
          roots++;
          if (roots != 1 ||
              reader.localName != rootName ||
              reader.namespaceUri != namespace) {
            throw const FormatException('Invalid Word package metadata XML.');
          }
        }
        depth++;
      case XmlEventType.endElement:
        depth--;
        if (depth < 0) {
          throw const FormatException('Invalid Word package metadata XML.');
        }
      case XmlEventType.dtd:
        throw const FormatException('Invalid Word package metadata XML.');
      case XmlEventType.characters:
        if (depth == 0 && !reader.isWhitespace) {
          throw const FormatException('Invalid Word package metadata XML.');
        }
      default:
        break;
    }
  }
  if (roots != 1 || depth != 0) {
    throw const FormatException('Invalid Word package metadata XML.');
  }
}
