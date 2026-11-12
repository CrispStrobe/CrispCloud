import 'dart:async';

import '../xml/namespaces.dart';
import '../xml/xml_node.dart';
import '../xml/xml_reader.dart';
import 'package_part.dart';

/// An internal OPC relationship with a canonical, package-relative part path.
class OfficePartRelationship {
  /// Creates a relationship already resolved inside its owning package.
  const OfficePartRelationship(this.id, this.type, this.path);

  /// Relationship identifier within the owning part.
  final String id;

  /// Full transitional or Strict OOXML relationship type URI.
  final String type;

  /// Canonical ZIP member name, without a leading slash.
  final String path;

  /// Matches either standard OOXML spelling of [kind].
  bool isType(String kind) =>
      type == '${OfficeNamespaces.r}/$kind' ||
      type == 'http://purl.oclc.org/ooxml/officeDocument/relationships/$kind';
}

/// Navigates Office parts through a caller-owned, bounded text reader.
///
/// External targets and paths escaping the package are excluded. Namespace
/// decoys, duplicate relationship IDs and ambiguous main parts reject. No
/// network requests, macro execution or filesystem access are performed.
class OfficePackageParts {
  /// The reader returns null for absent parts and enforces its own byte budget.
  OfficePackageParts(this.readPart, {this.maxXmlDepth = 256}) {
    if (maxXmlDepth < 1) {
      throw ArgumentError.value(maxXmlDepth, 'maxXmlDepth');
    }
  }

  /// Reads a canonical ZIP member name, optionally asynchronously.
  final FutureOr<String?> Function(String name) readPart;

  /// Maximum selected XML element nesting before constructing a node tree.
  final int maxXmlDepth;

  /// Relationship member for an owner; the empty owner denotes package root.
  static String relationshipPath(String owner) =>
      OpcUris.toZipName(OpcUris.relationshipsUriFor(_owner(owner)));

  /// Reads one selected XML part after validating its complete structure.
  Future<XmlDocument?> xml(String name) async {
    final text = await readPart(name);
    if (text == null) return null;
    try {
      final reader = XmlPullReader(text);
      final stack = <String>[];
      var roots = 0;
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (stack.isEmpty && ++roots > 1) {
              throw const FormatException('Multiple Office XML roots.');
            }
            stack.add(reader.qualifiedName);
            if (stack.length > maxXmlDepth) {
              throw const FormatException(
                'Office XML exceeds the nesting limit.',
              );
            }
          case XmlEventType.endElement:
            if (stack.isEmpty || stack.removeLast() != reader.qualifiedName) {
              throw const FormatException('Mismatched Office XML tags.');
            }
          case XmlEventType.dtd:
            throw const FormatException(
              'Office XML document types are unsupported.',
            );
          case XmlEventType.characters:
          case XmlEventType.cdata:
            if (stack.isEmpty && !reader.isWhitespace) {
              throw const FormatException('Text outside the Office XML root.');
            }
          default:
            break;
        }
      }
      if (roots != 1 || stack.isNotEmpty) {
        throw const FormatException('Incomplete Office XML document.');
      }
      // readElement retains whitespace-only text runs, which can be visible
      // search text. It shares the existing engine XML reader and node model.
      final nodes = XmlPullReader(text);
      while (nodes.next()) {
        if (nodes.eventType == XmlEventType.startElement) {
          return XmlDocument(root: XmlDocument.readElement(nodes));
        }
      }
      throw const FormatException('Missing Office XML root.');
    } on XmlParseException catch (error) {
      throw FormatException('Invalid Office XML in $name: ${error.message}');
    } on RangeError {
      throw FormatException('Invalid Office XML bounds in $name.');
    }
  }

  /// Reads internal, nonescaping relationships of the exact native owner.
  Future<List<OfficePartRelationship>> relationships(String owner) async {
    final normalizedOwner = _owner(owner);
    final root = await _relationshipRoot(normalizedOwner);
    return root == null ? const [] : _relationships(root, normalizedOwner);
  }

  Future<XmlElement?> _relationshipRoot(String owner) async {
    final document = await xml(relationshipPath(owner));
    if (document == null) return null;
    final root = document.root!;
    if (root.localName != 'Relationships' ||
        root.namespaceUri != OfficeNamespaces.relationships) {
      throw const FormatException(
        'Invalid Office relationship root namespace.',
      );
    }
    return root;
  }

  List<OfficePartRelationship> _relationships(XmlElement root, String owner) {
    final result = <OfficePartRelationship>[];
    final ids = <String>{};
    for (final relation in root.childElements) {
      if (relation.localName != 'Relationship' ||
          relation.namespaceUri != OfficeNamespaces.relationships) {
        continue;
      }
      String? attribute(String name) =>
          relation.getAttribute(name, namespaceUri: '');
      final id = attribute('Id');
      final type = attribute('Type');
      final target = attribute('Target');
      if (id == null || id.isEmpty || type == null || target == null) continue;
      if (!ids.add(id)) {
        throw FormatException('Duplicate Office relationship ID: $id');
      }
      if (attribute('TargetMode')?.toLowerCase() == 'external') continue;
      final resolved = _resolveTarget(owner, target);
      if (resolved != null) {
        result.add(OfficePartRelationship(id, type, resolved));
      }
    }
    return List.unmodifiable(result);
  }

  /// Returns a declared internal main part, or [fallback] only when no package
  /// relationship metadata exists. A declared unusable graph returns null.
  Future<String?> mainPartOrNull({String? fallback}) async {
    final root = await _relationshipRoot('/');
    if (root == null) return fallback;
    final relationships = _relationships(root, '/');
    final declared = root.childElements.where(
      (element) =>
          element.localName == 'Relationship' &&
          element.namespaceUri == OfficeNamespaces.relationships &&
          OfficePartRelationship(
            '',
            element.getAttribute('Type', namespaceUri: '') ?? '',
            '',
          ).isType('officeDocument'),
    );
    if (declared.length > 1) {
      throw const FormatException(
        'Ambiguous Office main document relationship.',
      );
    }
    return relationships
        .where((relationship) => relationship.isType('officeDocument'))
        .firstOrNull
        ?.path;
  }

  /// Resolves a main part with an absent-metadata fallback. Declared unusable
  /// metadata rejects instead of selecting an unrelated canonical document.
  Future<String> mainPart(String fallback) async =>
      await mainPartOrNull(fallback: fallback) ??
      (throw const FormatException(
        'No internal Office main document relationship.',
      ));
}

String _owner(String owner) {
  if (owner.isEmpty || owner == '/') return '/';
  final relative = owner.startsWith('/') ? owner.substring(1) : owner;
  if (relative.isEmpty ||
      relative.contains('\\') ||
      OpcUris.toZipName(relative) != relative) {
    throw ArgumentError.value(owner, 'owner', 'Expected a canonical OPC owner');
  }
  return '/$relative';
}

String? _resolveTarget(String owner, String target) {
  final uri = Uri.tryParse(target);
  if (target.isEmpty ||
      uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      target.contains('\\')) {
    return null;
  }
  final String decoded;
  try {
    decoded = Uri.decodeComponent(uri.path);
  } on FormatException {
    return null;
  }
  if (decoded.contains('\\') ||
      decoded.startsWith('//') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(decoded)) {
    return null;
  }
  var depth = decoded.startsWith('/')
      ? 0
      : owner.split('/').where((segment) => segment.isNotEmpty).length -
            (owner == '/' ? 0 : 1);
  for (final segment in decoded.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    depth += segment == '..' ? -1 : 1;
    if (depth < 0) return null;
  }
  if (depth == 0) return null;
  // Validate decoded traversal, then retain the exact OPC key used by the
  // engine's package loader. An encoded alias must not select another part.
  return OpcUris.toZipName(OpcUris.resolve(owner, target));
}
