import 'dart:convert';

import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_content_controls.dart';
import 'word_tree.dart';

/// A CSL item in a Zotero citation cluster, including per-citation locators.
///
/// Unknown JSON members are retained. The CSL item data is embedded in the
/// document so a citation remains identifiable without a Zotero account.
final class ZoteroCitationItem {
  ZoteroCitationItem.fromJson(Map<String, dynamic> json)
    : _json = _freezeObject(json) {
    if (_json['id'] is! String && _json['id'] is! num) {
      throw const FormatException('A Zotero citation item needs an id.');
    }
    final uris = _json['uris'];
    if (uris != null && (uris is! List || uris.any((uri) => uri is! String))) {
      throw const FormatException('Zotero item URIs must be strings.');
    }
    if (_json['itemData'] != null && _json['itemData'] is! Map) {
      throw const FormatException('Embedded CSL item data must be an object.');
    }
  }

  factory ZoteroCitationItem.fromCsl({
    required Map<String, dynamic> itemData,
    required List<String> uris,
    String? locator,
    String? label,
    String? prefix,
    String? suffix,
    bool suppressAuthor = false,
    bool authorOnly = false,
  }) {
    if (uris.isEmpty || uris.any((uri) => !_isItemUri(uri))) {
      throw ArgumentError.value(
        uris,
        'uris',
        'Use canonical Zotero item URIs.',
      );
    }
    if (suppressAuthor && authorOnly) {
      throw ArgumentError('Author-only and suppress-author are incompatible.');
    }
    // CSL export IDs may be library-local integers. A canonical item URI keeps
    // simultaneous personal/group libraries distinct in a new document.
    final id = uris.first;
    return ZoteroCitationItem.fromJson(<String, dynamic>{
      'id': id,
      'uris': uris,
      'itemData': <String, dynamic>{...itemData, 'id': id},
      if (locator != null && locator.isNotEmpty) 'locator': locator,
      if (label != null && label.isNotEmpty) 'label': label,
      if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
      if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
      if (suppressAuthor) 'suppress-author': true,
      if (authorOnly) 'author-only': true,
    });
  }

  final Map<String, dynamic> _json;

  Object get id => _json['id'] as Object;
  List<String> get uris => List<String>.unmodifiable(
    (_json['uris'] as List? ?? const <dynamic>[]).cast<String>(),
  );
  Map<String, dynamic>? get itemData =>
      _json['itemData'] as Map<String, dynamic>?;
  String get locator =>
      _json['locator'] is String ? _json['locator'] as String : '';
  String get label => _json['label'] is String ? _json['label'] as String : '';
  String get prefix =>
      _json['prefix'] is String ? _json['prefix'] as String : '';
  String get suffix =>
      _json['suffix'] is String ? _json['suffix'] as String : '';
  bool get suppressAuthor => _json['suppress-author'] == true;
  bool get authorOnly => _json['author-only'] == true;

  /// A deep immutable snapshot, including unrecognized Zotero/CSL members.
  Map<String, dynamic> toJson() => _json;

  static bool _isItemUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'zotero.org' || uri.host == 'www.zotero.org') &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(
          r'^/(?:users/(?:[0-9]+|local/[A-Za-z0-9]+)|groups/[0-9]+)/items/[A-Z0-9]{8}$',
        ).hasMatch(uri.path);
  }
}

/// Zotero's CSL_CITATION JSON, with caller-supplied cached display text.
///
/// This is a metadata codec, not a CSL style processor. Hosts must obtain or
/// explicitly compose the display text. Automatic document-wide CSL numbering,
/// ibid rules, disambiguation, and bibliography formatting are not inferred.
final class ZoteroCitation {
  factory ZoteroCitation({
    required String citationId,
    required List<ZoteroCitationItem> items,
    required String plainCitation,
    String? formattedCitation,
    int noteIndex = 0,
  }) => ZoteroCitation.fromJson(<String, dynamic>{
    'citationID': citationId,
    'properties': <String, dynamic>{
      'formattedCitation': formattedCitation ?? plainCitation,
      'plainCitation': plainCitation,
      'noteIndex': noteIndex,
    },
    'citationItems': <Map<String, dynamic>>[
      for (final item in items) item.toJson(),
    ],
    'schema':
        'https://github.com/citation-style-language/schema/raw/master/csl-citation.json',
  });

  ZoteroCitation.fromJson(Map<String, dynamic> json)
    : _json = _freezeObject(json) {
    if (_json['citationID'] is! String ||
        (_json['citationID'] as String).trim().isEmpty) {
      throw const FormatException('A Zotero citation needs a citationID.');
    }
    final entries = _json['citationItems'];
    if (entries is! List || entries.isEmpty || entries.length > 1000) {
      throw const FormatException('A Zotero citation needs 1–1000 items.');
    }
    items = List<ZoteroCitationItem>.unmodifiable(<ZoteroCitationItem>[
      for (final entry in entries)
        if (entry is Map<String, dynamic>)
          ZoteroCitationItem.fromJson(entry)
        else
          throw const FormatException(
            'A Zotero citation item must be an object.',
          ),
    ]);
    if (_json['properties'] != null && _json['properties'] is! Map) {
      throw const FormatException(
        'Zotero citation properties must be an object.',
      );
    }
  }

  final Map<String, dynamic> _json;
  late final List<ZoteroCitationItem> items;
  String get citationId => _json['citationID'] as String;
  Map<String, dynamic> get properties =>
      (_json['properties'] as Map<String, dynamic>?) ??
      const <String, dynamic>{};
  String get plainCitation => properties['plainCitation'] is String
      ? properties['plainCitation'] as String
      : '';
  String get formattedCitation => properties['formattedCitation'] is String
      ? properties['formattedCitation'] as String
      : plainCitation;
  int get noteIndex =>
      properties['noteIndex'] is int ? properties['noteIndex'] as int : 0;
  Map<String, dynamic> toJson() => _json;

  /// Replaces a cluster while retaining its identity and unknown metadata.
  ZoteroCitation withItems(
    List<ZoteroCitationItem> items, {
    required String plainCitation,
    String? formattedCitation,
    int? noteIndex,
  }) => ZoteroCitation.fromJson(<String, dynamic>{
    ..._json,
    'citationItems': <Map<String, dynamic>>[
      for (final item in items) item.toJson(),
    ],
    'properties': <String, dynamic>{
      ...properties,
      'plainCitation': plainCitation,
      'formattedCitation': formattedCitation ?? plainCitation,
      if (noteIndex != null) 'noteIndex': noteIndex,
    },
  });

  String get fieldInstruction =>
      ' ADDIN ZOTERO_ITEM CSL_CITATION ${jsonEncode(_json)} ';
}

enum ZoteroFieldKind { citation, bibliography }

/// A live located Zotero field. Reinspect after edits or undo/redo.
///
/// Rich imported fields and fields spanning paragraphs are inspectable and
/// preservable. Editing never flattens nested fields or unmodeled markup.
final class WmlZoteroField {
  WmlZoteroField._({
    required this.kind,
    required this.instruction,
    required this.paragraph,
    required this.paragraphs,
    required this.start,
    required this.end,
    required this.cachedText,
    required this.metadata,
    required this.citation,
    this.run,
    this.wholeParagraph = false,
    this.locked = false,
    this.nested = false,
    this.opaqueMetadata = false,
    List<WmlInline> contents = const <WmlInline>[],
    Map<WmlParagraph, List<WmlFieldBoundary>>? boundaries,
  }) : _contents = contents,
       _boundaries = boundaries ?? <WmlParagraph, List<WmlFieldBoundary>>{};

  final ZoteroFieldKind kind;
  final String instruction;
  final WmlParagraph paragraph;
  final List<WmlParagraph> paragraphs;
  final int start;
  final int end;
  final String cachedText;
  final Map<String, dynamic>? metadata;
  final ZoteroCitation? citation;
  final WmlRun? run;
  final bool wholeParagraph;
  final bool locked;
  final bool nested;
  final bool opaqueMetadata;
  final List<WmlInline> _contents;
  final Map<WmlParagraph, List<WmlFieldBoundary>> _boundaries;

  bool get isValid =>
      kind == ZoteroFieldKind.citation ? citation != null : metadata != null;

  /// Safe cache replacement is limited to one paragraph of ordinary runs.
  bool get canEdit =>
      isValid &&
      !locked &&
      !nested &&
      !opaqueMetadata &&
      paragraphs.length == 1 &&
      _contents.every(
        (inline) =>
            inline is WmlRun &&
            inline.inlineVisual == null &&
            inline.noteRefId == null &&
            inline.hyperlink == null &&
            (identical(inline, run) || inline.commentIds.isEmpty) &&
            (identical(inline, run) || inline.fieldInstruction == null),
      );
}

/// Word field support for Zotero citations and bibliographies.
abstract final class WordZotero {
  static final _citationPrefix = RegExp(
    r'^\s*(?:ADDIN\s+(?:ZOTERO_ITEM\s+)?)?CSL_CITATION\s+',
    caseSensitive: false,
  );
  static final _bibliographyPrefix = RegExp(
    r'^\s*(?:ADDIN\s+ZOTERO_BIBL|CSL_BIBLIOGRAPHY)(?:\s+|$)',
    caseSensitive: false,
  );

  static ZoteroFieldKind? kindOfInstruction(String? instruction) {
    if (instruction == null) return null;
    if (_citationPrefix.hasMatch(instruction)) return ZoteroFieldKind.citation;
    if (_bibliographyPrefix.hasMatch(instruction))
      return ZoteroFieldKind.bibliography;
    return null;
  }

  static Map<String, dynamic>? metadataOf(String instruction) {
    final kind = kindOfInstruction(instruction);
    if (kind == null || instruction.length > _maxJsonLength) return null;
    final prefix =
        (kind == ZoteroFieldKind.citation
                ? _citationPrefix
                : _bibliographyPrefix)
            .firstMatch(instruction)!;
    final payload = instruction.substring(prefix.end).trim();
    final end = payload.lastIndexOf('}');
    if (!payload.startsWith('{') || end < 0) return null;
    final tail = payload.substring(end + 1).trim();
    if (tail.isNotEmpty &&
        !(kind == ZoteroFieldKind.bibliography && tail == 'CSL_BIBLIOGRAPHY')) {
      return null;
    }
    try {
      final value = jsonDecode(payload.substring(0, end + 1));
      return value is Map<String, dynamic> ? _freezeObject(value) : null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Inserts an atomic citation at a caret, preserving surrounding rich text.
  static void insertCitation(
    WmlParagraph paragraph,
    ZoteroCitation citation, {
    int? index,
  }) {
    if (paragraph.properties.fieldInstruction?.trim().isNotEmpty == true ||
        paragraph.properties.pageNumberField) {
      throw UnsupportedError(
        'Insert a Zotero citation in an ordinary paragraph.',
      );
    }
    final at = WmlRunEdit.normalizeRange(
      paragraph,
      index ?? paragraph.text.length,
      index ?? paragraph.text.length,
    ).start;
    final boundaryIndex = _complexInsertionIndex(paragraph, at);
    final run = WmlRun(
      text: citation.plainCitation,
      properties: WmlRunEdit.propsAt(paragraph, at == 0 ? 0 : at - 1).copy(),
      fieldInstruction: citation.fieldInstruction,
    );
    if (boundaryIndex == null) {
      WmlRunEdit.insertRuns(paragraph, at, <WmlRun>[run]);
    } else {
      WordContentControls.assertCanEdit(paragraph, at, at);
      paragraph.inlines.insert(boundaryIndex, run);
    }
  }

  static int? _complexInsertionIndex(WmlParagraph paragraph, int at) {
    final spans = <({int first, int last, int start, int end})>[];
    var depth = 0;
    var start = 0;
    var first = 0;
    var offset = 0;
    for (var index = 0; index < paragraph.inlines.length; index++) {
      final inline = paragraph.inlines[index];
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is! WmlFieldBoundary) continue;
      if (inline.kind == WmlFieldBoundaryKind.begin) {
        if (depth == 0) {
          first = index;
          start = offset;
        }
        depth++;
      } else if (inline.kind == WmlFieldBoundaryKind.end) {
        if (depth == 0) {
          if (at <= offset)
            throw UnsupportedError(
              'Move the caret outside the cross-paragraph field.',
            );
        } else if (--depth == 0) {
          spans.add((first: first, last: index, start: start, end: offset));
        }
      }
    }
    if (depth > 0 && at >= start) {
      throw UnsupportedError(
        'Move the caret outside the cross-paragraph field.',
      );
    }
    for (final span in spans) {
      if (at > span.start && at < span.end) {
        throw UnsupportedError('Move the caret outside the existing field.');
      }
      if (at == span.end) return span.last + 1;
      if (at == span.start) return span.first;
    }
    return null;
  }

  /// A bibliography with explicitly formatted cached text and Zotero metadata.
  static WmlParagraph bibliography({
    required String text,
    Map<String, dynamic>? metadata,
  }) => WmlParagraph(
    properties: WmlParagraphProps(styleId: 'Bibliography'),
    inlines: <WmlInline>[
      WmlRun(
        text: text,
        fieldInstruction: _bibliographyInstruction(
          metadata ??
              <String, dynamic>{
                'uncited': <dynamic>[],
                'omitted': <dynamic>[],
                'custom': <dynamic>[],
              },
        ),
      ),
    ],
  );

  static String _bibliographyInstruction(Map<String, dynamic> metadata) =>
      ' ADDIN ZOTERO_BIBL ${jsonEncode(_freezeObject(metadata))} CSL_BIBLIOGRAPHY ';

  /// Inspects modeled document stories without interpreting or executing HTML.
  static List<WmlZoteroField> fields(WmlDocument document) => <WmlZoteroField>[
    for (final story in _stories(document)) ..._storyFields(story),
  ];

  /// Distinct embedded CSL items, with their full original JSON preserved.
  static List<Map<String, dynamic>> embeddedItems(WmlDocument document) {
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final field in fields(document)) {
      for (final item
          in field.citation?.items ?? const <ZoteroCitationItem>[]) {
        if (item.itemData == null) continue;
        final identities = item.uris.isEmpty
            ? <String>['id:${item.id}']
            : <String>[for (final uri in item.uris) _itemIdentity(uri)];
        final duplicate = identities.any(seen.contains);
        seen.addAll(identities);
        if (!duplicate) items.add(item.itemData!);
      }
    }
    return items;
  }

  static String _itemIdentity(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && ZoteroCitationItem._isItemUri(value)) {
      return 'zotero:${uri.path}';
    }
    return value;
  }

  /// Explicitly replaces a citation and its cache; unknown metadata can be
  /// retained by creating [citation] with [ZoteroCitation.withItems].
  static void updateCitation(WmlZoteroField field, ZoteroCitation citation) {
    if (field.kind != ZoteroFieldKind.citation) {
      throw ArgumentError('The selected field is not a citation.');
    }
    _replace(field, citation.fieldInstruction, citation.plainCitation);
  }

  static void updateBibliography(
    WmlZoteroField field, {
    required String text,
    Map<String, dynamic>? metadata,
  }) {
    if (field.kind != ZoteroFieldKind.bibliography) {
      throw ArgumentError('The selected field is not a bibliography.');
    }
    _replace(
      field,
      _bibliographyInstruction(
        metadata ?? field.metadata ?? <String, dynamic>{},
      ),
      text,
    );
  }

  static void _replace(WmlZoteroField field, String instruction, String text) {
    if (!field.canEdit) {
      throw UnsupportedError(
        'This Zotero field has locked, nested, malformed, or cross-paragraph content.',
      );
    }
    _assertCurrent(field);
    WordContentControls.assertCanEdit(field.paragraph, field.start, field.end);
    if (field.run != null) {
      field.run!
        ..fieldInstruction = instruction
        ..fieldDirty = null
        ..text = text;
      return;
    }
    final paragraph = field.paragraph;
    final properties = WmlRunEdit.propsAt(paragraph, field.start).copy();
    final replacement = WmlRun(
      text: text,
      properties: properties,
      fieldInstruction: instruction,
    );
    if (field.wholeParagraph) {
      paragraph.inlines
        ..clear()
        ..add(replacement);
      _clearParagraphField(paragraph);
    } else {
      final boundaries = field._boundaries[paragraph]!;
      final first = paragraph.inlines.indexOf(boundaries.first);
      final last = paragraph.inlines.indexOf(boundaries.last);
      paragraph.inlines.replaceRange(first, last + 1, <WmlInline>[replacement]);
    }
  }

  /// Removes only this field's instructions while preserving its visible runs.
  /// This is intentionally explicit: normal saves never unlink Zotero fields.
  static void unlink(WmlZoteroField field) {
    if (field.locked || field.nested || !field.isValid) {
      throw UnsupportedError(
        'Cannot unlink a locked, nested, or malformed Zotero field.',
      );
    }
    _assertCurrent(field);
    for (final paragraph in field.paragraphs) {
      WordContentControls.assertCanEdit(paragraph, 0, paragraph.text.length);
    }
    if (field.run != null) {
      field.run!
        ..fieldInstruction = null
        ..fieldDirty = null
        ..fieldLocked = false;
    } else if (field.wholeParagraph) {
      _clearParagraphField(field.paragraph);
    } else {
      for (final entry in field._boundaries.entries) {
        entry.key.inlines.removeWhere(entry.value.contains);
      }
    }
  }

  static void _clearParagraphField(WmlParagraph paragraph) =>
      paragraph.properties
        ..fieldInstruction = null
        ..fieldBegin = false
        ..fieldSeparate = false
        ..fieldEnd = false
        ..pageNumberField = false;

  static void _assertCurrent(WmlZoteroField field) {
    for (final current in _storyFields(field.paragraphs)) {
      final sameIdentity = field.run != null
          ? identical(current.run, field.run)
          : field.wholeParagraph
          ? current.wholeParagraph &&
                identical(current.paragraph, field.paragraph)
          : current._boundaries[field.paragraph]?.first ==
                field._boundaries[field.paragraph]?.first;
      if (sameIdentity &&
          current.instruction == field.instruction &&
          current.cachedText == field.cachedText &&
          current.start == field.start &&
          current.end == field.end &&
          current.locked == field.locked &&
          current.nested == field.nested)
        return;
    }
    throw StateError(
      'The Zotero field changed. Inspect it again before editing.',
    );
  }

  static Iterable<List<WmlParagraph>> _stories(WmlDocument document) sync* {
    yield document.paragraphs.toList();
    for (final section in document.sections) {
      yield section.header;
      yield section.footer;
      yield section.firstHeader;
      yield section.firstFooter;
      yield section.evenHeader;
      yield section.evenFooter;
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      yield WordTree.paragraphs(note.blocks).toList();
    }
    for (final comment in document.comments) {
      yield comment.paragraphs;
    }
  }

  static List<WmlZoteroField> _storyFields(List<WmlParagraph> story) {
    final found = <WmlZoteroField>[];
    final stack = <_OpenField>[];
    for (final paragraph in story) {
      for (final field in stack) field.addParagraph(paragraph);
      final paragraphInstruction = paragraph.properties.fieldInstruction;
      if (paragraphInstruction != null &&
          kindOfInstruction(paragraphInstruction) != null) {
        found.add(
          _located(
            instruction: paragraphInstruction,
            paragraph: paragraph,
            paragraphs: <WmlParagraph>[paragraph],
            start: 0,
            end: paragraph.text.length,
            text: paragraph.text,
            contents: List<WmlInline>.of(paragraph.inlines),
            wholeParagraph: true,
          ),
        );
      }
      var offset = 0;
      for (final inline in paragraph.inlines) {
        if (inline is WmlFieldBoundary) {
          switch (inline.kind) {
            case WmlFieldBoundaryKind.begin:
              for (final field in stack) field.nested = true;
              final field = _OpenField(paragraph, offset)
                ..nested = stack.isNotEmpty;
              field.addBoundary(paragraph, inline);
              stack.add(field);
            case WmlFieldBoundaryKind.instruction:
              if (stack.isNotEmpty) {
                stack.last.instruction.write(inline.text);
                stack.last.addBoundary(paragraph, inline);
              }
            case WmlFieldBoundaryKind.separate:
              if (stack.isNotEmpty) {
                stack.last.separated = true;
                stack.last.addBoundary(paragraph, inline);
              }
            case WmlFieldBoundaryKind.end:
              if (stack.isNotEmpty) {
                final field = stack.removeLast();
                field.addBoundary(paragraph, inline);
                final instruction = field.instruction.toString();
                if (kindOfInstruction(instruction) != null && field.separated) {
                  found.add(
                    _located(
                      instruction: instruction,
                      paragraph: field.paragraphs.first,
                      paragraphs: field.paragraphs,
                      start: field.start,
                      end: offset,
                      text: field.cache.toString(),
                      contents: field.contents,
                      boundaries: field.boundaries,
                      nested: field.nested,
                      locked: field.locked,
                      opaqueMetadata: field.opaqueMetadata,
                    ),
                  );
                }
              }
          }
        } else {
          for (final field in stack) {
            if (field.separated) {
              field.contents.add(inline);
              if (inline is WmlRun) field.cache.write(inline.text);
            }
          }
          if (inline is WmlRun) {
            if (kindOfInstruction(inline.fieldInstruction) != null) {
              found.add(
                _located(
                  instruction: inline.fieldInstruction!,
                  paragraph: paragraph,
                  paragraphs: <WmlParagraph>[paragraph],
                  start: offset,
                  end: offset + inline.text.length,
                  text: inline.text,
                  contents: <WmlInline>[inline],
                  run: inline,
                  locked: inline.fieldLocked,
                  nested: stack.isNotEmpty,
                ),
              );
            }
            offset += inline.text.length;
          }
        }
      }
    }
    return found;
  }

  static WmlZoteroField _located({
    required String instruction,
    required WmlParagraph paragraph,
    required List<WmlParagraph> paragraphs,
    required int start,
    required int end,
    required String text,
    required List<WmlInline> contents,
    Map<WmlParagraph, List<WmlFieldBoundary>>? boundaries,
    WmlRun? run,
    bool wholeParagraph = false,
    bool nested = false,
    bool locked = false,
    bool opaqueMetadata = false,
  }) {
    final metadata = metadataOf(instruction);
    final kind = kindOfInstruction(instruction)!;
    ZoteroCitation? citation;
    if (kind == ZoteroFieldKind.citation && metadata != null) {
      try {
        citation = ZoteroCitation.fromJson(metadata);
      } on FormatException {
        // Preserve and expose unsupported payloads; never manufacture a repair.
      }
    }
    return WmlZoteroField._(
      kind: kind,
      instruction: instruction,
      paragraph: paragraph,
      paragraphs: List<WmlParagraph>.unmodifiable(paragraphs),
      start: start,
      end: end,
      cachedText: text,
      metadata: metadata,
      citation: citation,
      run: run,
      wholeParagraph: wholeParagraph,
      nested: nested,
      locked: locked,
      opaqueMetadata: opaqueMetadata,
      contents: contents,
      boundaries: boundaries,
    );
  }
}

final class _OpenField {
  _OpenField(WmlParagraph paragraph, this.start)
    : paragraphs = <WmlParagraph>[paragraph];
  final int start;
  final List<WmlParagraph> paragraphs;
  final instruction = StringBuffer();
  final cache = StringBuffer();
  final contents = <WmlInline>[];
  final boundaries = <WmlParagraph, List<WmlFieldBoundary>>{};
  bool separated = false;
  bool nested = false;
  bool locked = false;
  bool opaqueMetadata = false;

  void addParagraph(WmlParagraph paragraph) {
    if (!identical(paragraphs.last, paragraph)) {
      paragraphs.add(paragraph);
      if (separated) cache.writeln();
    }
  }

  void addBoundary(WmlParagraph paragraph, WmlFieldBoundary boundary) {
    boundaries.putIfAbsent(paragraph, () => <WmlFieldBoundary>[]).add(boundary);
    if (boundary.kind == WmlFieldBoundaryKind.begin) {
      locked = RegExp(
        r'fldLock\s*=\s*["\x27](?:1|true|on)["\x27]',
      ).hasMatch(boundary.sourceXml ?? '');
    }
    if (boundary.runPropertiesXml?.trim().isNotEmpty == true) {
      opaqueMetadata = true;
    }
    if (boundary.sourceXml != null) {
      try {
        final source = XmlDocument.parse(boundary.sourceXml!).root;
        if (source != null &&
            (source.children.isNotEmpty ||
                source.attributes.any(
                  (attribute) =>
                      attribute.prefix != 'xmlns' &&
                      attribute.qualifiedName != 'xmlns' &&
                      (attribute.namespaceUri != OfficeNamespaces.w ||
                          !<String>{
                            'fldCharType',
                            'fldLock',
                            'dirty',
                          }.contains(attribute.localName)),
                ))) {
          opaqueMetadata = true;
        }
      } on XmlParseException {
        opaqueMetadata = true;
      }
    }
  }
}

const _maxJsonLength = 1024 * 1024;

Map<String, dynamic> _freezeObject(Map<String, dynamic> json) {
  dynamic freeze(dynamic value, int depth) {
    if (depth > 64)
      throw const FormatException('Zotero metadata is too deeply nested.');
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        for (final entry in value.entries)
          entry.key: freeze(entry.value, depth + 1),
      });
    }
    if (value is List) {
      return List<dynamic>.unmodifiable(<dynamic>[
        for (final entry in value) freeze(entry, depth + 1),
      ]);
    }
    if (value == null ||
        value is String ||
        value is bool ||
        (value is num && value.isFinite))
      return value;
    throw const FormatException('Zotero metadata must contain JSON values.');
  }

  final frozen = freeze(json, 0) as Map<String, dynamic>;
  if (utf8.encode(jsonEncode(frozen)).length > _maxJsonLength) {
    throw const FormatException('Zotero metadata exceeds the 1 MiB limit.');
  }
  return frozen;
}
