import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

/// An internal OPC relationship. External and escaping targets are excluded.
class OfficePartRelationship {
  const OfficePartRelationship(this.id, this.type, this.path);
  final String id;
  final String type;
  final String path;

  bool isType(String kind) =>
      type ==
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/$kind' ||
      type == 'http://purl.oclc.org/ooxml/officeDocument/relationships/$kind';
}

/// Resolves Office parts through a caller-owned, bounded archive reader.
class OfficePackageParts {
  const OfficePackageParts(this.readPart);
  final Future<String?> Function(String name) readPart;

  static String relationshipPath(String owner) => owner.isEmpty
      ? '_rels/.rels'
      : path.posix.normalize(
          path.posix.join(
            path.posix.dirname(owner),
            '_rels',
            '${path.posix.basename(owner)}.rels',
          ),
        );

  Future<List<OfficePartRelationship>> relationships(String owner) async {
    final text = await readPart(relationshipPath(owner));
    if (text == null) return const [];
    final result = <OfficePartRelationship>[];
    for (final rel in XmlDocument.parse(
      text,
    ).findAllElements('Relationship', namespace: '*')) {
      final id = rel.getAttribute('Id');
      final type = rel.getAttribute('Type');
      final target = rel.getAttribute('Target');
      if (id == null ||
          type == null ||
          target == null ||
          rel.getAttribute('TargetMode')?.toLowerCase() == 'external') {
        continue;
      }
      final uri = Uri.tryParse(target);
      if (uri == null ||
          uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasQuery ||
          uri.hasFragment ||
          target.contains('\\')) {
        continue;
      }
      final decoded = Uri.decodeComponent(uri.path);
      if (decoded.contains('\\')) continue;
      final resolved = path.posix.normalize(
        decoded.startsWith('/')
            ? decoded.substring(1)
            : path.posix.join(
                owner.isEmpty ? '' : path.posix.dirname(owner),
                decoded,
              ),
      );
      if (resolved == '.' ||
          resolved == '..' ||
          resolved.startsWith('../') ||
          resolved.startsWith('/')) {
        continue;
      }
      result.add(OfficePartRelationship(id, type, resolved));
    }
    return result;
  }

  Future<String> mainPart(String fallback) async =>
      (await relationships(''))
          .where((relationship) => relationship.isType('officeDocument'))
          .firstOrNull
          ?.path ??
      fallback;
}
