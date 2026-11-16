import 'dart:convert';

import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../zotero/zotero_formatted_text.dart';
import '../properties/wml_properties.dart';
import 'wml_clone.dart';
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

  // New linked sources need durable identities. Imported field JSON is still
  // accepted by fromJson and retained verbatim, including unknown URI forms.
  static bool _isItemUri(String value) {
    final uri = Uri.tryParse(value);
    final authority = RegExp(r'^[^:]+://([^/?#]*)').firstMatch(value)?.group(1);
    return uri != null &&
        authority != null &&
        !authority.contains(':') &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'zotero.org' || uri.host == 'www.zotero.org') &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(
          r'^/(?:users/(?:[1-9][0-9]*|local/[A-Za-z0-9]{8})|groups/[1-9][0-9]*)/items/[A-Z0-9]{8}$',
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
      'noteIndex': ?noteIndex,
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
  }) : _contents = List<WmlInline>.unmodifiable(contents),
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
    if (_bibliographyPrefix.hasMatch(instruction)) {
      return ZoteroFieldKind.bibliography;
    }
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
  }) => insertNativeCitation(
    paragraph,
    instruction: citation.fieldInstruction,
    text: citation.plainCitation,
    index: index,
  );

  /// Inserts a validated native Zotero result as one protected inline field.
  /// Mixed character formatting uses a complex field packet whose complete
  /// result is protected by the paragraph editing primitives.
  static void insertNativeCitation(
    WmlParagraph paragraph, {
    required String instruction,
    required String text,
    int? index,
    ZoteroFormattedText? formattedText,
    List<WmlRun>? preservedResultRuns,
  }) {
    _validateNativeInstruction(instruction, ZoteroFieldKind.citation);
    _assertFormattedText(text, formattedText);
    if (preservedResultRuns != null && formattedText != null) {
      throw ArgumentError('Use one citation result representation.');
    }
    if (preservedResultRuns != null &&
        (preservedResultRuns.map((run) => run.text).join() != text ||
            preservedResultRuns.any(
              (run) =>
                  run.fieldInstruction != null ||
                  run.inlineVisual != null ||
                  run.noteRefId != null ||
                  run.hyperlink != null ||
                  (preservedResultRuns.length > 1 && run.commentIds.isNotEmpty),
            ))) {
      throw ArgumentError(
        'The preserved citation cache must contain only its result text.',
      );
    }
    if (paragraph.properties.fieldInstruction?.trim().isNotEmpty == true ||
        paragraph.properties.pageNumberField) {
      throw UnsupportedError(
        'Insert a Zotero citation in an ordinary paragraph.',
      );
    }
    final requested = index ?? paragraph.text.length;
    // Explicit citation insertion keeps its existing refusal inside a complex
    // field. Ordinary typing/pasting may snap after that complete field.
    final requestedBoundary = _complexInsertionIndex(paragraph, requested);
    final at = WmlRunEdit.normalizeRange(paragraph, requested, requested).start;
    final boundaryIndex = at == requested
        ? requestedBoundary
        : _complexInsertionIndex(paragraph, at);
    final base = WmlRunEdit.propsAt(paragraph, at == 0 ? 0 : at - 1).copy();
    final packet = preservedResultRuns == null
        ? _citationResult(instruction, text, formattedText, base)
        : _resultPacket(
            instruction,
            WmlClone.inlines(preservedResultRuns).cast<WmlRun>(),
          );
    if (boundaryIndex == null) {
      WmlRunEdit.insertInlines(paragraph, at, packet);
    } else {
      WordContentControls.assertCanEdit(paragraph, at, at);
      paragraph.inlines.insertAll(boundaryIndex, packet);
    }
  }

  /// Detached result runs for a native move that does not return new text.
  /// The processor's explicit setText result always takes precedence.
  static List<WmlRun> copyCitationResult(WmlZoteroField field) {
    if (field.kind != ZoteroFieldKind.citation || !field.canEdit) {
      throw UnsupportedError('This citation cache cannot be moved safely.');
    }
    _assertCurrent(field);
    return List<WmlRun>.unmodifiable([
      for (final run in WmlClone.inlines(field._contents).cast<WmlRun>())
        run
          ..fieldInstruction = null
          ..fieldLocked = false
          ..fieldDirty = null,
    ]);
  }

  /// Replaces the exact code and result supplied by Zotero's document processor.
  /// This does not invent a citation cache from embedded item metadata.
  static void replaceNativeResult(
    WmlZoteroField field, {
    required String instruction,
    required String text,
    ZoteroFormattedText? formattedText,
  }) {
    _validateNativeInstruction(instruction, field.kind);
    _assertFormattedText(text, formattedText);
    final base = WmlRunEdit.propsAt(field.paragraph, field.start).copy();
    if (field.kind == ZoteroFieldKind.citation &&
        formattedText != null &&
        !formattedText.hasUniformCharacterFormatting) {
      if (!field.canEdit || field.run?.commentIds.isNotEmpty == true) {
        throw UnsupportedError(
          'This citation has comments, locked, nested or unsupported field '
          'content that cannot be replaced with a formatted result safely.',
        );
      }
      _assertCurrent(field);
      final paragraph = field.paragraph;
      WordContentControls.assertCanEdit(paragraph, field.start, field.end);
      final packet = _citationResult(instruction, text, formattedText, base);
      if (field.wholeParagraph) {
        paragraph.inlines
          ..clear()
          ..addAll(packet);
        _clearParagraphField(paragraph);
      } else if (field.run != null) {
        final index = paragraph.inlines.indexOf(field.run!);
        paragraph.inlines.replaceRange(index, index + 1, packet);
      } else {
        final boundaries = field._boundaries[paragraph]!;
        final first = paragraph.inlines.indexOf(boundaries.first);
        final last = paragraph.inlines.indexOf(boundaries.last);
        paragraph.inlines.replaceRange(first, last + 1, packet);
      }
      return;
    }
    _replace(
      field,
      instruction,
      text,
      formattedText: field.kind == ZoteroFieldKind.bibliography
          ? formattedText
          : null,
      preserveSameText: formattedText == null,
    );
    if (field.kind == ZoteroFieldKind.citation && formattedText != null) {
      final current = _storyFields(<WmlParagraph>[field.paragraph]).firstWhere(
        (candidate) =>
            candidate.start == field.start &&
            candidate.instruction == instruction,
      );
      if (current.run != null) {
        current.run!.properties = _atomicProperties(formattedText, base);
      }
    }
  }

  static List<WmlInline> _citationResult(
    String instruction,
    String text,
    ZoteroFormattedText? formattedText,
    WmlRunProps base,
  ) {
    if (formattedText == null || formattedText.hasUniformCharacterFormatting) {
      return [
        WmlRun(
          text: text,
          properties: _atomicProperties(formattedText, base),
          fieldInstruction: instruction,
        ),
      ];
    }
    return _resultPacket(
      instruction,
      formattedText.toRuns(baseProperties: base),
    );
  }

  static List<WmlInline> _resultPacket(String instruction, List<WmlRun> runs) {
    if (runs.length < 2) {
      final run = runs.firstOrNull ?? WmlRun();
      return [run..fieldInstruction = instruction];
    }
    return [
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: instruction,
      ),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      ...runs,
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ];
  }

  static WmlRunProps _atomicProperties(
    ZoteroFormattedText? text,
    WmlRunProps base,
  ) =>
      text != null &&
          text.hasUniformCharacterFormatting &&
          text.spans.isNotEmpty
      ? text.toRuns(baseProperties: base).first.properties
      : base;

  static void _validateNativeInstruction(
    String instruction,
    ZoteroFieldKind kind,
  ) {
    if (kindOfInstruction(instruction) != kind ||
        metadataOf(instruction) == null) {
      throw const FormatException('Zotero returned an invalid native field.');
    }
    if (kind == ZoteroFieldKind.citation) {
      ZoteroCitation.fromJson(metadataOf(instruction)!);
    }
  }

  /// Deletes one editable field packet, including its cached result.
  static void delete(WmlZoteroField field) {
    if (!field.canEdit) {
      throw UnsupportedError('This Zotero field cannot be deleted safely.');
    }
    _assertCurrent(field);
    WordContentControls.assertCanEdit(field.paragraph, field.start, field.end);
    if (field.run != null) {
      field.paragraph.inlines.remove(field.run);
    } else if (field.wholeParagraph) {
      field.paragraph.inlines.clear();
      _clearParagraphField(field.paragraph);
    } else {
      final boundaries = field._boundaries[field.paragraph]!;
      final start = field.paragraph.inlines.indexOf(boundaries.first);
      final end = field.paragraph.inlines.indexOf(boundaries.last);
      field.paragraph.inlines.removeRange(start, end + 1);
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
          if (at <= offset) {
            throw UnsupportedError(
              'Move the caret outside the cross-paragraph field.',
            );
          }
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
    ZoteroFormattedText? formattedText,
  }) {
    _assertFormattedText(text, formattedText);
    final instruction = _bibliographyInstruction(
      metadata ??
          <String, dynamic>{
            'uncited': <dynamic>[],
            'omitted': <dynamic>[],
            'custom': <dynamic>[],
          },
    );
    return WmlParagraph(
      properties: WmlParagraphProps(
        styleId: 'Bibliography',
        fieldInstruction: formattedText == null ? null : instruction,
      ),
      inlines: <WmlInline>[
        if (formattedText != null)
          ...formattedText.toRuns()
        else
          WmlRun(text: text, fieldInstruction: instruction),
      ],
    );
  }

  static String _bibliographyInstruction(Map<String, dynamic> metadata) =>
      ' ADDIN ZOTERO_BIBL ${jsonEncode(_freezeObject(metadata))} CSL_BIBLIOGRAPHY ';

  /// Inspects modeled document stories without interpreting or executing HTML.
  static List<WmlZoteroField> fields(WmlDocument document) => <WmlZoteroField>[
    for (final story in _stories(document)) ..._storyFields(story),
  ];

  /// Exact citation packets for the paragraph editing primitives.
  ///
  /// This shares the native field parser's metadata, lock, nesting and opaque
  /// markup checks. It performs no edit and does not normalize text ranges.
  static List<
    ({
      int first,
      int last,
      int start,
      int end,
      bool canEdit,
      bool paragraphOwned,
    })
  >
  citationEditPackets(WmlParagraph paragraph) => [
    for (final field in _storyFields([paragraph]))
      if (field.kind == ZoteroFieldKind.citation)
        (
          first: field.wholeParagraph
              ? 0
              : field.run != null
              ? paragraph.inlines.indexOf(field.run!)
              : paragraph.inlines.indexOf(field._boundaries[paragraph]!.first),
          last: field.wholeParagraph
              ? paragraph.inlines.length - 1
              : field.run != null
              ? paragraph.inlines.indexOf(field.run!)
              : paragraph.inlines.indexOf(field._boundaries[paragraph]!.last),
          start: field.start,
          end: field.end,
          canEdit: field.canEdit,
          paragraphOwned: field.wholeParagraph,
        ),
  ];

  /// Distinct embedded CSL items, with their full original JSON preserved.
  static List<Map<String, dynamic>> embeddedItems(WmlDocument document) =>
      distinctEmbeddedItems(
        fields(document).expand(
          (field) => field.citation?.items ?? const <ZoteroCitationItem>[],
        ),
      );

  /// One original CSL snapshot per source, in first-available-snapshot order.
  ///
  /// All URIs on a citation item describe the same source. Resolve their full
  /// alias groups before choosing snapshots, so a later item can connect two
  /// earlier identities even when that connecting item has no embedded data.
  /// Only complete URI identities are compared; equal item keys or CSL IDs do
  /// not join linked sources from unrelated libraries. Unlinked sources retain
  /// the existing item-ID fallback, separate from every URI namespace.
  /// Neither citation metadata nor the chosen snapshot is rewritten.
  static List<Map<String, dynamic>> distinctEmbeddedItems(
    Iterable<ZoteroCitationItem> sources,
  ) {
    final items = sources.toList(growable: false);
    final parents = List<int>.generate(items.length, (index) => index);
    final ranks = List<int>.filled(items.length, 0);

    int root(int index) {
      while (parents[index] != index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    }

    final owners = <(String, String), int>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final uris = item.uris;
      final identities = uris.isEmpty
          ? <(String, String)>[('id', '${item.id}')]
          : uris.map(_itemIdentity);
      for (final identity in identities) {
        final previous = owners.putIfAbsent(identity, () => index);
        final currentRoot = root(index);
        final previousRoot = root(previous);
        if (currentRoot == previousRoot) continue;
        if (ranks[currentRoot] < ranks[previousRoot]) {
          parents[currentRoot] = previousRoot;
        } else {
          parents[previousRoot] = currentRoot;
          if (ranks[currentRoot] == ranks[previousRoot]) {
            ranks[currentRoot]++;
          }
        }
      }
    }
    final snapshots = <int, Map<String, dynamic>>{};
    for (var index = 0; index < items.length; index++) {
      final data = items[index].itemData;
      if (data != null) snapshots.putIfAbsent(root(index), () => data);
    }
    return snapshots.values.toList();
  }

  static final _itemUriOrigin = RegExp(
    r'^https?://(?:www\.)?zotero\.org/',
    caseSensitive: false,
  );
  static final _itemUriPath = RegExp(
    r'^/(?:users/(?:[1-9][0-9]*|local/[A-Za-z0-9]{8})|groups/[1-9][0-9]*)/items/[A-Z0-9]{8}$',
  );

  static (String, String) _itemIdentity(String value) {
    final origin = _itemUriOrigin.matchAsPrefix(value);
    if (origin != null) {
      // Check the original path: Uri normalization must not turn escapes,
      // dot segments, explicit ports or trailing characters into aliases.
      final path = value.substring(origin.end - 1);
      final match = _itemUriPath.matchAsPrefix(path);
      if (match != null && match.end == path.length) {
        return ('zotero', path);
      }
    }
    return ('uri', value);
  }

  /// Explicitly replaces a citation and its cache; unknown metadata can be
  /// retained by creating [citation] with [ZoteroCitation.withItems].
  static void updateCitation(WmlZoteroField field, ZoteroCitation citation) {
    if (field.kind != ZoteroFieldKind.citation) {
      throw ArgumentError('The selected field is not a citation.');
    }
    _replace(
      field,
      citation.fieldInstruction,
      citation.plainCitation,
      preserveSameText: true,
    );
  }

  static void updateBibliography(
    WmlZoteroField field, {
    required String text,
    Map<String, dynamic>? metadata,
    ZoteroFormattedText? formattedText,
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
      formattedText: formattedText,
    );
  }

  /// Whether rich bibliography runs can replace this complete paragraph while
  /// retaining all outside content and structural markers.
  static bool canReplaceFormattedBibliography(WmlZoteroField field) {
    if (field.kind != ZoteroFieldKind.bibliography || !field.canEdit) {
      return false;
    }
    final paragraph = field.paragraph;
    return field.wholeParagraph ||
        (field.run != null &&
            paragraph.inlines.length == 1 &&
            identical(paragraph.inlines.single, field.run) &&
            field.run!.commentIds.isEmpty &&
            paragraph.contentControlWrappers.isEmpty &&
            paragraph.properties.fieldInstruction == null &&
            !paragraph.properties.pageNumberField) ||
        _standaloneComplexField(field);
  }

  /// Native bibliography processing may replace a complete, contiguous range
  /// of entry paragraphs. Ordinary inline edits keep their narrower contract.
  /// Every inline and every paragraph must belong exclusively to this field,
  /// in one real block list; a flattened view across cells/sections is unsafe.
  static bool canReplaceNativeBibliography(
    WmlDocument document,
    WmlZoteroField field,
  ) {
    if (field.kind != ZoteroFieldKind.bibliography ||
        !field.isValid ||
        field.locked ||
        field.nested ||
        field.opaqueMetadata ||
        field.paragraphs.isEmpty ||
        field.paragraphs.length > 10000 ||
        field._contents.any(
          (inline) =>
              inline is! WmlRun ||
              inline.inlineVisual != null ||
              inline.noteRefId != null ||
              inline.hyperlink != null ||
              inline.commentIds.isNotEmpty ||
              (!identical(inline, field.run) &&
                  inline.fieldInstruction != null),
        )) {
      return false;
    }
    final slot = WordTree.locate(document, field.paragraph);
    if (slot == null ||
        slot.index + field.paragraphs.length > slot.parent.length) {
      return false;
    }
    for (var i = 0; i < field.paragraphs.length; i++) {
      final paragraph = field.paragraphs[i];
      if (!identical(slot.parent[slot.index + i], paragraph) ||
          paragraph.contentControlWrappers.isNotEmpty ||
          paragraph.properties.bookmarkName != null ||
          paragraph.properties.noteId != null ||
          paragraph.properties.pageNumberField) {
        return false;
      }
    }
    if (field.paragraphs.length == 1) {
      return canReplaceFormattedBibliography(field);
    }
    if (field.start != 0 ||
        field.end != field.paragraphs.last.text.length ||
        field.paragraphs.any(
          (paragraph) => paragraph.properties.fieldInstruction != null,
        )) {
      return false;
    }
    final boundaries = field._boundaries.values.expand((value) => value);
    final first = field._boundaries[field.paragraph];
    final last = field._boundaries[field.paragraphs.last];
    if (first == null ||
        first.length < 3 ||
        first.first.kind != WmlFieldBoundaryKind.begin ||
        first.last.kind != WmlFieldBoundaryKind.separate ||
        first
            .skip(1)
            .take(first.length - 2)
            .any(
              (boundary) => boundary.kind != WmlFieldBoundaryKind.instruction,
            ) ||
        last == null ||
        last.length != 1 ||
        last.single.kind != WmlFieldBoundaryKind.end ||
        !identical(field.paragraph.inlines.first, first.first) ||
        !identical(field.paragraphs.last.inlines.last, last.single) ||
        boundaries.length != first.length + 1) {
      return false;
    }
    final owned = Set<WmlInline>.identity()
      ..addAll(field._contents)
      ..addAll(boundaries);
    final inlines = field.paragraphs.expand((paragraph) => paragraph.inlines);
    return owned.length == inlines.length && inlines.every(owned.contains);
  }

  /// Builds one native bibliography field spanning its entry paragraphs.
  /// Structural XHTML breaks become paragraphs; soft breaks remain in runs.
  static List<WmlParagraph> nativeBibliographyParagraphs({
    required String instruction,
    required String text,
    ZoteroFormattedText? formattedText,
    WmlParagraphProps? paragraphProperties,
    WmlRunProps? runProperties,
  }) {
    _validateNativeInstruction(instruction, ZoteroFieldKind.bibliography);
    _assertFormattedText(text, formattedText);
    final entries =
        formattedText?.toParagraphRuns(baseProperties: runProperties) ??
        [
          for (final entry in text.split('\n'))
            <WmlRun>[WmlRun(text: entry, properties: runProperties?.copy())],
        ];
    if (entries.isEmpty || entries.length > 10000) {
      throw const FormatException(
        'The Zotero bibliography has too many entries.',
      );
    }
    final result = <WmlParagraph>[];
    for (final entry in entries) {
      final properties =
          paragraphProperties?.copy() ??
          WmlParagraphProps(styleId: 'Bibliography');
      // New entries inherit modeled formatting, never duplicate native opaque
      // paragraph XML or structural aliases from the first source paragraph.
      properties
        ..sourcePropertiesXml = null
        ..importedValues = null
        ..fieldInstruction = null
        ..fieldBegin = false
        ..fieldSeparate = false
        ..fieldEnd = false
        ..pageNumberField = false
        ..bookmarkName = null
        ..sourceBookmarkName = null;
      if (result.isNotEmpty) {
        properties
          ..pageBreakBefore = false
          ..columnBreakBefore = false
          ..numId = null
          ..listLabel = null
          ..listRestart = null
          ..headingLevel = null
          ..dropCapLines = 0;
      }
      result.add(
        WmlParagraph(properties: properties, inlines: <WmlInline>[...entry]),
      );
    }
    result.first.inlines.insertAll(0, [
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: instruction,
      ),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
    ]);
    result.last.inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
    return result;
  }

  /// Replaces a native bibliography without replacing its first paragraph
  /// identity. Existing entry paragraph properties are retained on refresh;
  /// Zotero's staged layout can then override their layout as one undo step.
  static void replaceNativeBibliography(
    WmlDocument document,
    WmlZoteroField field, {
    required String instruction,
    required String text,
    ZoteroFormattedText? formattedText,
  }) {
    if (!canReplaceNativeBibliography(document, field)) {
      throw UnsupportedError(
        'This bibliography does not own complete contiguous entry paragraphs.',
      );
    }
    _assertCurrent(field);
    _validateNativeInstruction(instruction, ZoteroFieldKind.bibliography);
    for (final paragraph in field.paragraphs) {
      WordContentControls.assertCanEdit(paragraph, 0, paragraph.text.length);
    }
    if (formattedText == null && text == field.cachedText) {
      _replaceInstruction(field, instruction);
      return;
    }
    final replacements = nativeBibliographyParagraphs(
      instruction: instruction,
      text: text,
      formattedText: formattedText,
      paragraphProperties: field.paragraph.properties,
      runProperties: WmlRunEdit.propsAt(field.paragraph, 0),
    );
    final slot = WordTree.locate(document, field.paragraph)!;
    for (
      var i = 0;
      i < replacements.length && i < field.paragraphs.length;
      i++
    ) {
      final original = field.paragraphs[i];
      original.inlines
        ..clear()
        ..addAll(replacements[i].inlines);
      _clearParagraphField(original);
      replacements[i] = original;
    }
    slot.parent.replaceRange(
      slot.index,
      slot.index + field.paragraphs.length,
      replacements,
    );
  }

  /// Removes a standalone native bibliography while retaining its first empty
  /// paragraph, matching ordinary field deletion and preserving a caret host.
  static void deleteNativeBibliography(
    WmlDocument document,
    WmlZoteroField field,
  ) {
    if (!canReplaceNativeBibliography(document, field)) {
      throw UnsupportedError('This bibliography cannot be removed safely.');
    }
    _assertCurrent(field);
    for (final paragraph in field.paragraphs) {
      WordContentControls.assertCanEdit(paragraph, 0, paragraph.text.length);
    }
    final slot = WordTree.locate(document, field.paragraph)!;
    field.paragraph.inlines.clear();
    _clearParagraphField(field.paragraph);
    slot.parent.removeRange(
      slot.index + 1,
      slot.index + field.paragraphs.length,
    );
  }

  static void _assertFormattedText(
    String text,
    ZoteroFormattedText? formattedText,
  ) {
    if (formattedText != null && formattedText.plainText != text) {
      throw ArgumentError(
        'The formatted Zotero result must match its visible text.',
      );
    }
  }

  static void _replace(
    WmlZoteroField field,
    String instruction,
    String text, {
    ZoteroFormattedText? formattedText,
    bool preserveSameText = false,
  }) {
    _assertFormattedText(text, formattedText);
    if (!field.canEdit) {
      throw UnsupportedError(
        'This Zotero field has locked, nested, malformed, or cross-paragraph content.',
      );
    }
    _assertCurrent(field);
    WordContentControls.assertCanEdit(field.paragraph, field.start, field.end);
    if (preserveSameText && text == field.cachedText) {
      _replaceInstruction(field, instruction);
      return;
    }
    if (formattedText != null) {
      final paragraph = field.paragraph;
      final soleRun =
          field.run != null &&
          paragraph.inlines.length == 1 &&
          identical(paragraph.inlines.single, field.run) &&
          field.run!.commentIds.isEmpty &&
          paragraph.contentControlWrappers.isEmpty &&
          paragraph.properties.fieldInstruction == null &&
          !paragraph.properties.pageNumberField;
      if (!field.wholeParagraph &&
          !soleRun &&
          !_standaloneComplexField(field)) {
        throw UnsupportedError(
          'This bibliography uses an inline field. Use plain text for this update, or insert a new formatted bibliography in its own paragraph.',
        );
      }
      final runs = formattedText.toRuns(
        baseProperties: WmlRunEdit.propsAt(paragraph, field.start),
      );
      paragraph.properties.fieldInstruction = instruction;
      paragraph.inlines
        ..clear()
        ..addAll(runs);
      return;
    }
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

  // A saved rich bibliography can reopen as a complex boundary packet. Its
  // offsets alone are insufficient: bookmarks and other zero-width markup
  // may sit outside the field while sharing those same offsets.
  static bool _standaloneComplexField(WmlZoteroField field) {
    final paragraph = field.paragraph;
    final boundaries = field._boundaries[paragraph];
    if (field.paragraphs.length != 1 ||
        field.start != 0 ||
        field.end != paragraph.text.length ||
        paragraph.contentControlWrappers.isNotEmpty ||
        paragraph.properties.fieldInstruction != null ||
        paragraph.properties.pageNumberField ||
        boundaries == null ||
        boundaries.isEmpty ||
        !identical(paragraph.inlines.first, boundaries.first) ||
        !identical(paragraph.inlines.last, boundaries.last)) {
      return false;
    }
    final owned = Set<WmlInline>.identity()
      ..addAll(boundaries)
      ..addAll(field._contents);
    return owned.length == paragraph.inlines.length &&
        paragraph.inlines.every(owned.contains);
  }

  // An unchanged display cache is not an instruction to flatten its runs.
  // Imported formattedCitation strings may contain RTF or another dialect;
  // only the explicitly supplied field code is changed here.
  static void _replaceInstruction(WmlZoteroField field, String instruction) {
    if (field.run != null) {
      field.run!
        ..fieldInstruction = instruction
        ..fieldDirty = null;
      return;
    }
    if (field.wholeParagraph) {
      field.paragraph.properties.fieldInstruction = instruction;
      return;
    }
    final boundaries = field._boundaries[field.paragraph]!;
    final firstInstruction = boundaries.firstWhere(
      (boundary) => boundary.kind == WmlFieldBoundaryKind.instruction,
    );
    final replacements = <WmlFieldBoundary, WmlFieldBoundary?>{};
    for (final boundary in boundaries) {
      if (boundary.kind == WmlFieldBoundaryKind.instruction) {
        replacements[boundary] = identical(boundary, firstInstruction)
            ? WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: instruction,
                sourceXml: boundary.sourceXml,
                runPropertiesXml: boundary.runPropertiesXml,
              )
            : null;
      } else if (boundary.kind == WmlFieldBoundaryKind.begin &&
          boundary.sourceXml != null) {
        final source = XmlDocument.parse(boundary.sourceXml!);
        source.root!.removeAttribute('dirty', namespaceUri: OfficeNamespaces.w);
        replacements[boundary] = WmlFieldBoundary(
          kind: boundary.kind,
          text: boundary.text,
          sourceXml: source.toXmlString(declaration: false),
          runPropertiesXml: boundary.runPropertiesXml,
        );
      }
    }
    final inlines = <WmlInline>[
      for (final inline in field.paragraph.inlines)
        if (inline is! WmlFieldBoundary || !replacements.containsKey(inline))
          inline
        else if (replacements[inline] != null)
          replacements[inline]!,
    ];
    field.paragraph.inlines
      ..clear()
      ..addAll(inlines);
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
          current.nested == field.nested &&
          current.opaqueMetadata == field.opaqueMetadata &&
          current.canEdit == field.canEdit) {
        return;
      }
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
      for (final field in stack) {
        field.addParagraph(paragraph);
      }
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
              for (final field in stack) {
                field.nested = true;
              }
              final field = _OpenField(paragraph, offset)
                ..nested = stack.isNotEmpty;
              field.addBoundary(paragraph, inline);
              stack.add(field);
            case WmlFieldBoundaryKind.instruction:
              if (stack.isNotEmpty) {
                if (stack.last.separated) stack.last.opaqueMetadata = true;
                stack.last.instruction.write(inline.text);
                stack.last.addBoundary(paragraph, inline);
              }
            case WmlFieldBoundaryKind.separate:
              if (stack.isNotEmpty) {
                if (stack.last.separated) stack.last.opaqueMetadata = true;
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
            } else {
              field.opaqueMetadata = true;
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
    if (depth > 64) {
      throw const FormatException('Zotero metadata is too deeply nested.');
    }
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
        (value is num && value.isFinite)) {
      return value;
    }
    throw const FormatException('Zotero metadata must contain JSON values.');
  }

  final frozen = freeze(json, 0) as Map<String, dynamic>;
  if (utf8.encode(jsonEncode(frozen)).length > _maxJsonLength) {
    throw const FormatException('Zotero metadata exceeds the 1 MiB limit.');
  }
  return frozen;
}
