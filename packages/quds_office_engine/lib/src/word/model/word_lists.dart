import 'dart:convert';

import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// Multilevel list scheme (1 / 1.1 / أ).
abstract final class WordLists {
  /// Applies outline numbering at [level] (0–8). Pass [document] when editing
  /// imported content so new definitions cannot collide with imported IDs.
  static void applyLevel(
    WmlParagraph paragraph, {
    required bool numbered,
    int level = 0,
    WmlDocument? document,
  }) {
    final int safe = level.clamp(0, 8);
    paragraph.properties
      ..numId = document == null
          ? (numbered ? 2 : 1)
          : numberingId(document, numbered: numbered)
      ..numberingSuppressed = false
      ..ilvl = safe
      ..listLabel = numbered ? _numberLabel(safe) : _bulletLabel(safe)
      ..indent = WmlIndent(left: 18.0 + safe * 18);
  }

  /// Returns a reusable document-local list definition without replacing any
  /// imported numbering. Definitions live in the package, so IDs survive save,
  /// reopen, isolate transfer, and paragraph undo/redo.
  static int numberingId(WmlDocument document, {required bool numbered}) {
    final OpcPackage package = document.package ??= OpcPackage.create(
      OpcPackageKind.word,
    );
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    final PackageRelationship? relationship = rels.firstByType(
      RelationshipTypes.numbering,
    );
    final String uri = relationship == null
        ? '/word/numbering.xml'
        : rels.resolve(relationship);
    final PackagePart? part = package.getPart(uri);
    final XmlDocument xml = XmlDocument.parse(
      part?.readText() ?? '<w:numbering xmlns:w="${OfficeNamespaces.w}"/>',
    );
    final XmlElement root = xml.root!;
    final String name = 'Quds-${numbered ? 'decimal' : 'bullet'}-v1';
    for (final XmlElement definition in root.childrenNamed('abstractNum')) {
      if (definition.firstChild('name')?.getAttribute('val') != name) continue;
      final String? abstractId = definition.getAttribute('abstractNumId');
      for (final XmlElement instance in root.childrenNamed('num')) {
        if (instance.firstChild('abstractNumId')?.getAttribute('val') ==
            abstractId) {
          final int? id = int.tryParse(instance.getAttribute('numId') ?? '');
          if (id != null && id > 0) return id;
        }
      }
    }
    final Set<int> used = <int>{
      for (final XmlElement node in root.childElements)
        if (int.tryParse(
              node.getAttribute('numId') ??
                  node.getAttribute('abstractNumId') ??
                  '',
            )
            case final int id)
          id,
      for (final WmlParagraph p in document.paragraphs)
        if (p.properties.numId case final int id) id,
      for (final style in document.styles)
        if (style.numId case final int id) id,
    };
    var id = numbered ? 2 : 1;
    while (used.contains(id)) {
      id++;
    }
    final StringBuffer levels = StringBuffer();
    for (var level = 0; level < 9; level++) {
      final String label = numbered
          ? (level == 0
                ? '%1.'
                : List<String>.generate(
                    level + 1,
                    (int i) => '%${i + 1}',
                  ).join('.'))
          : _bulletLabel(level).trim();
      levels.write(
        '<w:lvl w:ilvl="$level"><w:start w:val="1"/>'
        '<w:numFmt w:val="${numbered ? 'decimal' : 'bullet'}"/>'
        '<w:lvlText w:val="$label"/><w:pPr><w:ind w:left="${(level + 1) * 360}"'
        ' w:hanging="180"/></w:pPr></w:lvl>',
      );
    }
    final XmlElement definition = XmlDocument.parse(
      '<w:abstractNum xmlns:w="${OfficeNamespaces.w}" w:abstractNumId="$id">'
      '<w:multiLevelType w:val="hybridMultilevel"/><w:name w:val="$name"/>'
      '$levels</w:abstractNum>',
    ).root!;
    final int firstInstance = root.children.indexWhere(
      (XmlNode node) => node is XmlElement && node.localName == 'num',
    );
    if (firstInstance >= 0) {
      root.children.insert(firstInstance, definition..parent = root);
    } else {
      root.addChild(definition);
    }
    root.addChild(
      XmlDocument.parse(
        '<w:num xmlns:w="${OfficeNamespaces.w}" w:numId="$id">'
        '<w:abstractNumId w:val="$id"/></w:num>',
      ).root!,
    );
    if (part == null) {
      package.createPart(
        uri,
        OfficeContentTypes.wordNumbering,
        utf8.encode(xml.toXmlString()),
      );
    } else {
      part.writeText(xml.toXmlString());
    }
    if (relationship == null) {
      rels.add(type: RelationshipTypes.numbering, target: 'numbering.xml');
    }
    return id;
  }

  /// Restarts numbering for [paragraph]'s list at the current level.
  ///
  /// Keeps a pending restart on the paragraph. Label resolution is repeatable;
  /// serialization emits a separate numbering instance without changing the
  /// paragraph's list identity (and therefore without altering undo snapshots).
  static void restart(WmlParagraph paragraph, {int? at}) {
    if (paragraph.properties.numId == null) {
      return;
    }
    paragraph.properties.listRestart = at ?? 1;
  }

  /// clear API.
  static void clear(WmlParagraph paragraph) {
    paragraph.properties
      ..numId = null
      ..numberingSuppressed = true
      ..ilvl = 0
      ..listLabel = null
      ..listRestart = null;
  }

  /// increment API.
  static void changeLevel(WmlParagraph paragraph, int delta) {
    if (paragraph.properties.numId == null) {
      return;
    }
    final int level = (paragraph.properties.ilvl + delta).clamp(0, 8);
    paragraph.properties
      ..ilvl = level
      ..listLabel = _looksBullet(paragraph)
          ? _bulletLabel(level)
          : _numberLabel(level)
      ..indent = WmlIndent(left: 18.0 + level * 18);
  }

  /// Recomputes `listLabel` for consecutive numbered paragraphs in [story].
  ///
  /// Higher-level increments reset deeper levels (Word multilevel behaviour).
  static void resolveLabels(Iterable<WmlParagraph> story) {
    final Map<int, List<int>> counters = <int, List<int>>{};
    for (final WmlParagraph paragraph in story) {
      final int? numId = paragraph.properties.numId;
      if (numId == null) {
        continue;
      }
      final int ilvl = paragraph.properties.ilvl.clamp(0, 8);
      final bool numbered = !_looksBullet(paragraph);
      if (!numbered) {
        paragraph.properties.listLabel = _bulletLabel(ilvl);
        continue;
      }
      final List<int> stack = counters.putIfAbsent(
        numId,
        () => List<int>.filled(9, 0),
      );
      final int? restart = paragraph.properties.listRestart;
      if (restart != null) {
        stack[ilvl] = restart - 1;
        for (int i = ilvl + 1; i < stack.length; i++) {
          stack[i] = 0;
        }
      }
      stack[ilvl] = stack[ilvl] + 1;
      for (int i = ilvl + 1; i < stack.length; i++) {
        stack[i] = 0;
      }
      paragraph.properties.listLabel = _formatOutline(stack, ilvl);
    }
  }

  static bool _looksBullet(WmlParagraph paragraph) {
    final String? label = paragraph.properties.listLabel;
    if (label == null || label.isEmpty) {
      return paragraph.properties.numId == 1;
    }
    final String t = label.trim();
    return t == '•' || t == '◦' || t == '▪' || t == 'o';
  }

  static String _formatOutline(List<int> stack, int ilvl) {
    if (ilvl == 0) {
      return '${stack[0]}. ';
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i <= ilvl; i++) {
      if (i > 0) {
        buffer.write('.');
      }
      buffer.write(stack[i] == 0 ? 1 : stack[i]);
    }
    buffer.write(' ');
    return buffer.toString();
  }

  static String _numberLabel(int level) {
    return switch (level) {
      0 => '1. ',
      1 => '1.1 ',
      2 => '1.1.1 ',
      _ => '${List<String>.filled(level + 1, '1').join('.')}. ',
    };
  }

  static String _bulletLabel(int level) {
    return switch (level) {
      0 => '• ',
      1 => '◦ ',
      _ => '▪ ',
    };
  }
}
