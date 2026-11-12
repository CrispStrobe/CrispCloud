import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'archive_viewer_service.dart';
import 'office_package_parts.dart';

/// Checks the additional invariants for editing Word macro documents/templates.
///
/// The existing Word serializer retains imported OPC parts. Before upload we
/// additionally verify the original main MIME type, binary/VBA payloads and
/// their relationships. Macros are opaque data; CrispCloud never executes them.
/// A failed check leaves the original untouched and the editor dirty.
class WordPackagePreservation {
  WordPackagePreservation._(this._snapshot);
  final _WordSnapshot _snapshot;

  static const contentTypesByExtension = <String, String>{
    'docm': 'application/vnd.ms-word.document.macroEnabled.main+xml',
    'dotm': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
    'dotx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml',
  };

  static Future<WordPackagePreservation?> capture(
    Uint8List bytes,
    String filename,
  ) async {
    final expected =
        contentTypesByExtension[filename.split('.').last.toLowerCase()];
    if (expected == null) return null;
    final snapshot = await _readSnapshot(bytes, filename);
    if (snapshot.mainType != expected) {
      throw const FormatException(
        'The Word package type does not match its filename. Open it in Word and save with the correct extension.',
      );
    }
    return WordPackagePreservation._(snapshot);
  }

  Future<void> validateSaved(Uint8List bytes) async {
    final current = await _readSnapshot(bytes, 'saved.docx');
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

Future<_WordSnapshot> _readSnapshot(Uint8List bytes, String name) async {
  const cap = 32 * 1024 * 1024;
  final archive = await openViewerArchive(bytes, name: name);
  try {
    final members = <String, ViewerArchiveMember>{};
    for (final member in archive.members.where((member) => member.isFile)) {
      if (members.containsKey(member.name)) {
        throw const FormatException('Duplicate Word package part.');
      }
      if (member.name.toLowerCase().startsWith('_xmlsignatures/')) {
        throw const FormatException(
          'This Word package is digitally signed. Save an unsigned copy in Word before editing it here.',
        );
      }
      members[member.name] = member;
    }
    var total = 0;
    Future<Uint8List?> read(String path) async {
      final member = members[path];
      if (member == null) return null;
      if (member.size > cap || total + member.size > 64 * 1024 * 1024) {
        throw const FormatException(
          'Word package exceeds the safe editing limit.',
        );
      }
      final value = await archive.readMember(member, maxBytes: cap);
      total += value.length;
      return value;
    }

    Future<String?> readText(String path) async {
      final value = await read(path);
      return value == null ? null : utf8.decode(value);
    }

    final typesText = await readText('[Content_Types].xml');
    if (typesText == null) {
      throw const FormatException('Word package content types are missing.');
    }
    final types = XmlDocument.parse(typesText);
    final overrides = <String, String>{};
    final defaults = <String, String>{};
    for (final element in types.rootElement.childElements) {
      final type = element.getAttribute('ContentType');
      if (type == null) continue;
      if (element.name.local == 'Override') {
        final part = element.getAttribute('PartName');
        if (part != null)
          overrides[part.startsWith('/') ? part.substring(1) : part] = type;
      } else if (element.name.local == 'Default') {
        final extension = element.getAttribute('Extension');
        if (extension != null) defaults[extension.toLowerCase()] = type;
      }
    }
    String typeOf(String path) =>
        overrides[path] ?? defaults[path.split('.').last.toLowerCase()] ?? '';
    final main = await OfficePackageParts(readText)
        .mainPart('word/document.xml');
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
      if (path.endsWith('.rels')) {
        final xml = XmlDocument.parse((await readText(path))!);
        for (final rel in xml.rootElement.childElements) {
          if (rel.name.local != 'Relationship') continue;
          final type = rel.getAttribute('Type') ?? '';
          final target = rel.getAttribute('Target') ?? '';
          if (!opaque(path) &&
              !type.toLowerCase().contains('vba') &&
              !target.toLowerCase().contains('vba')) {
            continue;
          }
          relationships.add(
            jsonEncode([
              path,
              rel.getAttribute('Id'),
              type,
              target,
              rel.getAttribute('TargetMode') ?? 'Internal',
            ]),
          );
        }
      } else if (opaque(path)) {
        final data = (await read(path))!;
        protectedParts[path] = '${typeOf(path)}:${sha256.convert(data)}';
      }
    }
    return _WordSnapshot(main, typeOf(main), protectedParts, relationships);
  } finally {
    await archive.close();
  }
}
