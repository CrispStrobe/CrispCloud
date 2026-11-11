import 'package:crypto/crypto.dart' as crypto;

import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';

/// Retains unsupported Word blocks and their original relationship targets.
abstract final class WordOpaqueIo {
  static WmlOpaqueBlock read(
    XmlPullReader reader,
    OpcPackage package,
    String owner,
  ) {
    final XmlElement element = XmlDocument.readElement(reader);
    final RelationshipCollection ownerRelationships = package.relationshipsFor(
      owner,
    );
    final Map<String, WmlOpaqueRelationship> references =
        <String, WmlOpaqueRelationship>{};
    for (final XmlAttribute attribute in _relationshipAttributes(element)) {
      final PackageRelationship? relationship = ownerRelationships.byId(
        attribute.value,
      );
      if (relationship == null) {
        throw FormatException(
          'Preserved ${element.localName} in $owner refers to missing '
          'relationship ${attribute.value}',
        );
      }
      final String target = ownerRelationships.resolve(relationship);
      PackagePart? part;
      if (relationship.targetMode == RelationshipTargetMode.internal) {
        part = package.getPart(target);
        if (part == null) {
          throw FormatException(
            'Preserved ${element.localName} in $owner has missing payload $target',
          );
        }
      }
      references[relationship.id] = WmlOpaqueRelationship(
        id: relationship.id,
        type: relationship.type,
        target: target,
        targetMode: relationship.targetMode,
        contentType: part?.contentType,
        sha256: part == null
            ? null
            : crypto.sha256.convert(part.bytesView).toString(),
      );
    }
    return WmlOpaqueBlock(
      xml: XmlDocument(root: element).toXmlString(declaration: false),
      sourcePartUri: owner,
      relationships: references.values,
    );
  }

  static void write(
    XmlWriter writer,
    WmlOpaqueBlock block,
    OpcPackage package,
    String owner,
  ) {
    final XmlElement element = XmlDocument.parse(block.xml).root!;
    final RelationshipCollection relationships = package.relationshipsFor(
      owner,
    );
    // Fail before rewriting links if the destination package cannot represent
    // the original content. Unrelated bytes at the same URI are not a copy.
    for (final WmlOpaqueRelationship reference in block.relationships) {
      if (reference.targetMode == RelationshipTargetMode.external) continue;
      final PackagePart? target = package.getPart(reference.target);
      if (target == null ||
          target.contentType != reference.contentType ||
          package.contentTypes.contentTypeFor(reference.target) !=
              reference.contentType ||
          crypto.sha256.convert(target.bytesView).toString() !=
              reference.sha256) {
        throw StateError(
          'Cannot save preserved ${element.localName} from ${block.sourcePartUri}: '
          'payload ${reference.target} is missing or changed in the destination package',
        );
      }
    }
    final Map<String, String> ids = <String, String>{};
    for (final WmlOpaqueRelationship reference in block.relationships) {
      PackageRelationship? matching;
      for (final PackageRelationship candidate in relationships.items) {
        if (candidate.type == reference.type &&
            candidate.targetMode == reference.targetMode &&
            relationships.resolve(candidate) == reference.target) {
          matching = candidate;
          break;
        }
      }
      matching ??= relationships.add(
        type: reference.type,
        target: reference.targetMode == RelationshipTargetMode.external
            ? reference.target
            : OpcUris.relativize(owner, reference.target),
        targetMode: reference.targetMode,
      );
      ids[reference.id] = matching.id;
    }
    for (final XmlAttribute attribute in _relationshipAttributes(element)) {
      final String? id = ids[attribute.value];
      if (id == null) {
        throw StateError(
          'Preserved XML has no relationship provenance for ${attribute.value}',
        );
      }
      attribute.value = id;
    }
    element.writeTo(writer);
  }

  static Iterable<XmlAttribute> _relationshipAttributes(XmlElement node) sync* {
    for (final XmlAttribute attribute in node.attributes) {
      if (attribute.namespaceUri == OfficeNamespaces.r) yield attribute;
    }
    for (final XmlElement child in node.childElements) {
      yield* _relationshipAttributes(child);
    }
  }
}
