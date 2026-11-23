import 'dart:convert';

import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_link.dart';
import 'word_notes.dart';
import 'word_styles.dart';
import 'word_tree.dart';
import 'word_zotero.dart';
import 'word_zotero_data.dart';

/// Zotero's interoperable, hyperlink-based transfer document representation.
///
/// The target URL is constant; the visible link text carries the original
/// field code. The temporary representation remains inactive until Zotero
/// imports and reformats its fields. Preparing either direction never edits
/// the source model or serializes its package.
abstract final class WordZoteroTransfer {
  static const marker = 'ZOTERO_TRANSFER_DOCUMENT';
  static const legacyMarker = 'ZOTERO_EXPORTED_DOCUMENT';
  static const linkUrl = 'https://www.zotero.org/';
  static const _googleDocsUrl = 'https://www.zotero.org/google-docs/?';
  static final _googleDocsFieldUrl = RegExp(
    r'^https://www\.zotero\.org/google-docs/\?[A-Za-z0-9]{6}$',
  );
  static const preferencesPrefix = 'DOCUMENT_PREFERENCES ';
  static const maxFields = 10000;
  static const maxPayloadBytes = 8 * 1024 * 1024;
  static const _citationPrefix = 'ITEM CSL_CITATION ';
  static const _bibliographyPrefix = 'BIBL ';

  /// Checks the first actual body block, before looking at stored preferences.
  /// A marker inside a table, header or later paragraph is ordinary content.
  static bool isTransferDocument(WmlDocument document) {
    final first = document.sections.firstOrNull?.blocks.firstOrNull;
    return first is WmlParagraph &&
        (first.text == marker || first.text == legacyMarker);
  }

  static WordZoteroTransferPlan prepareExport(
    WmlDocument source, {
    required String instructions,
    required String documentData,
  }) {
    if (isTransferDocument(source)) {
      throw StateError(
        'This document is already prepared for Zotero transfer.',
      );
    }
    if (instructions.trim().isEmpty ||
        instructions.contains(RegExp(r'[\r\n\u0000-\u0008\u000b-\u001f]'))) {
      throw const FormatException(
        'Zotero transfer instructions need one paragraph.',
      );
    }
    if (documentData.isEmpty) {
      throw const FormatException(
        'Zotero transfer needs document preferences.',
      );
    }
    WordZoteroDocumentData.fromTransfer(documentData);
    final plan = WordZoteroTransferPlan._(source);
    final document = plan.document;
    final fields = WordZotero.fields(document);
    final owners = _TransferModelGuard(document);
    if (fields.length > maxFields) {
      throw const FormatException('Too many Zotero fields for one transfer.');
    }
    final packets =
        <({WmlZoteroField field, String code, int first, int last})>[];
    var bytes =
        utf8.encode(instructions).length + utf8.encode(documentData).length;
    for (final field in fields) {
      if (!owners.supported.contains(field.paragraph) ||
          field.paragraphs.any((p) => !owners.supported.contains(p)) ||
          field.paragraph.contentControlWrappers.isNotEmpty ||
          field.paragraph.inlines.any((i) => i is WmlContentControlBoundary) ||
          field.run?.commentIds.isNotEmpty == true ||
          !(field.canEdit ||
              WordZotero.canReplaceNativeBibliography(document, field))) {
        throw UnsupportedError(
          'Transfer needs complete editable Zotero fields in the body, tables or uniquely anchored notes.',
        );
      }
      final code = _codeOf(field);
      bytes += utf8.encode(code).length;
      if (bytes > maxPayloadBytes) {
        throw const FormatException('Zotero transfer data exceeds the limit.');
      }
      final packet = field.paragraphs.length > 1
          ? (first: 0, last: 0)
          : _packet(field);
      packets.add((
        field: field,
        code: code,
        first: packet.first,
        last: packet.last,
      ));
    }
    // Existing carrier-looking links would make the result ambiguous to the
    // receiving plugin. Ordinary links to the Zotero homepage remain prose.
    for (final paragraph in owners.paragraphs) {
      for (final link in _links(paragraph)) {
        if (_isCode(link.text) || _hasCode(link.text)) {
          throw UnsupportedError(
            'Import the existing Zotero transfer links first.',
          );
        }
      }
    }
    if (bytes > maxPayloadBytes) {
      throw const FormatException('Zotero transfer data exceeds the limit.');
    }
    for (final packet in packets.reversed) {
      final field = packet.field;
      final properties = WmlRunEdit.propsAt(
        field.paragraph,
        field.start,
      ).copy();
      final link = WmlRun(
        text: packet.code,
        properties: properties,
        hyperlink: const WmlHyperlink(url: linkUrl),
      );
      if (field.paragraphs.length > 1) {
        WordZotero.deleteNativeBibliography(document, field);
        field.paragraph.inlines.add(link);
      } else {
        field.paragraph.inlines.replaceRange(packet.first, packet.last + 1, [
          link,
        ]);
        if (field.wholeParagraph) _clearField(field.paragraph);
      }
    }
    // Native writers may merge adjacent hyperlinks with the same target.
    // Their combined text must remain an unambiguous sequence of field codes.
    for (final paragraph in owners.paragraphs) {
      for (final link in _links(paragraph)) {
        if (_isCode(link.text)) {
          _splitCodes(link.text);
        } else if (_hasCode(link.text)) {
          throw UnsupportedError(
            'A Zotero field is adjacent to an ordinary link with the transfer target.',
          );
        }
      }
    }
    document.sections.first.blocks.insertAll(0, [
      _paragraph(marker),
      _paragraph(''),
      _paragraph(instructions),
      _paragraph(''),
    ]);
    document.sections.last.blocks.add(
      WmlParagraph(
        inlines: [
          WmlRun(
            text: '$preferencesPrefix$documentData',
            hyperlink: const WmlHyperlink(url: linkUrl),
          ),
        ],
      ),
    );
    // The marker is authoritative, but retaining valid native preferences is
    // useful when the carrier is inspected in an editor without the plugin.
    document.zoteroDocumentData = WordZoteroDocumentData.fromTransfer(
      documentData,
    );
    return plan;
  }

  static WordZoteroTransferPlan prepareImport(WmlDocument source) {
    if (!isTransferDocument(source)) {
      throw const FormatException('No Zotero transfer marker was found.');
    }
    final plan = WordZoteroTransferPlan._(source);
    final document = plan.document;
    final owners = _TransferModelGuard(document);
    final body = document.sections.first.blocks;
    if (body.length < 4 ||
        body.take(4).any((b) => b is! WmlParagraph) ||
        body.take(4).cast<WmlParagraph>().any((p) => !_plainFraming(p)) ||
        (body[1] as WmlParagraph).text.isNotEmpty ||
        (body[2] as WmlParagraph).text.trim().isEmpty ||
        (body[2] as WmlParagraph).text.contains(RegExp(r'[\r\n]')) ||
        (body[3] as WmlParagraph).text.isNotEmpty) {
      throw const FormatException(
        'The Zotero transfer introduction is incomplete or protected.',
      );
    }
    if (WordZotero.fields(document).isNotEmpty) {
      throw UnsupportedError(
        'Active fields and Zotero transfer links cannot be mixed.',
      );
    }
    final imports =
        <({WmlParagraph paragraph, _TransferLink link, List<String> codes})>[];
    WmlParagraph? preferencesParagraph;
    String? preferences;
    var fieldCount = 0;
    var bytes = 0;
    for (final paragraph in owners.paragraphs) {
      final links = _links(paragraph);
      for (final link in links) {
        if (!_isCode(link.text)) {
          if (_hasCode(link.text)) {
            throw const FormatException(
              'A Zotero transfer link mixes field codes with ordinary text.',
            );
          }
          continue;
        }
        if (!owners.supported.contains(paragraph)) {
          throw UnsupportedError(
            'A Zotero transfer link has unsupported or ambiguous ownership.',
          );
        }
        _assertLinkOwnership(paragraph, link);
        bytes += utf8.encode(link.text).length;
        if (bytes > maxPayloadBytes) {
          throw const FormatException(
            'Zotero transfer data exceeds the limit.',
          );
        }
        if (link.text.startsWith(preferencesPrefix)) {
          if ((link.url != linkUrl && link.url != _googleDocsUrl) ||
              preferences != null ||
              !identical(paragraph, document.sections.last.blocks.lastOrNull) ||
              link.first != 0 ||
              link.last != paragraph.inlines.length - 1 ||
              !_plainFraming(paragraph, links: true)) {
            throw const FormatException(
              'Zotero transfer preferences must occur exactly once at the end.',
            );
          }
          preferences = link.text.substring(preferencesPrefix.length);
          if (preferences.isEmpty) {
            throw const FormatException(
              'Zotero transfer preferences are empty.',
            );
          }
          WordZoteroDocumentData.fromTransfer(preferences);
          preferencesParagraph = paragraph;
        } else {
          if (link.url == _googleDocsUrl) {
            throw const FormatException(
              'A Google Docs transfer field has no field key.',
            );
          }
          final codes = _splitCodes(link.text);
          fieldCount += codes.length;
          if (fieldCount > maxFields) {
            throw const FormatException(
              'Too many Zotero fields for one transfer.',
            );
          }
          imports.add((paragraph: paragraph, link: link, codes: codes));
        }
      }
      // A lost or redirected carrier link must not silently become detached
      // plain citation text while the surrounding transfer markers disappear.
      final outside = [
        for (final inline in paragraph.inlines)
          inline is WmlRun && !_canonicalLink(inline.hyperlink)
              ? inline.text
              : '\ufffc',
      ].join();
      if (_hasCode(outside)) {
        throw const FormatException(
          'A Zotero transfer code lost its required hyperlink.',
        );
      }
    }
    if (preferences == null || preferencesParagraph == null) {
      throw const FormatException(
        'The Zotero transfer preferences link is missing.',
      );
    }
    for (final entry in imports.reversed) {
      final run = entry.paragraph.inlines[entry.link.first] as WmlRun;
      entry.paragraph.inlines
          .replaceRange(entry.link.first, entry.link.last + 1, [
            for (final code in entry.codes)
              WmlRun(
                text: code.startsWith(_citationPrefix)
                    ? '{Citation}'
                    : '{Bibliography}',
                properties: _importRunProperties(
                  document,
                  entry.paragraph,
                  run.properties,
                ),
                fieldInstruction: ' ADDIN ZOTERO_$code ',
              ),
          ]);
    }
    document.sections.last.blocks.remove(preferencesParagraph);
    body.removeRange(0, 4);
    if (document.sections.every((section) => section.blocks.isEmpty)) {
      document.sections.first.blocks.add(_paragraph(''));
    }
    document.zoteroDocumentData = WordZoteroDocumentData.fromTransfer(
      preferences,
    );
    return plan;
  }

  static WmlParagraph _paragraph(String text) =>
      WmlParagraph(inlines: [WmlRun(text: text)]);

  /// A native plugin removes the carrier hyperlink's character style before
  /// refreshing the field. Keep that cleanup local to validated carriers:
  /// surrounding links and authored fonts, colors and source XML stay intact.
  static WmlRunProps _importRunProperties(
    WmlDocument document,
    WmlParagraph paragraph,
    WmlRunProps source,
  ) {
    final result = source.copy();
    final linkStyle = const {
      'Hyperlink',
      'FollowedHyperlink',
    }.contains(source.styleId);
    final xml = source.sourcePropertiesXml;
    final direct = xml == null || xml.isEmpty
        ? null
        : XmlDocument.parse(xml).root;
    XmlElement? property(String name) => direct?.childElements
        .where(
          (element) =>
              element.localName == name &&
              (element.namespaceUri == OfficeNamespaces.w ||
                  element.namespaceUri.isEmpty && element.prefix == 'w'),
        )
        .firstOrNull;
    String? value(XmlElement? element) => element?.attributes
        .where(
          (attribute) =>
              attribute.localName == 'val' &&
              (attribute.namespaceUri == OfficeNamespaces.w ||
                  attribute.namespaceUri.isEmpty && attribute.prefix == 'w'),
        )
        .firstOrNull
        ?.value;
    final directColor = property('color');
    final color = source.color.toUpperCase();
    final originalColor = value(directColor)?.toUpperCase();
    final inheritedLinkColor =
        linkStyle &&
        xml != null &&
        directColor == null &&
        (source.importedValues?['color'] ?? source.color) == source.color;
    // The DOCX reader applies WordLink's default look to black linked runs,
    // even when their native direct properties explicitly say black. The
    // untouched rPr distinguishes this from an authored direct blue color.
    final defaultLinkLook =
        color == WordLink.color &&
        source.underline == WmlUnderline.single &&
        (originalColor == '000000' ||
            directColor == null && source.styleId == null);
    final styledLinkColor =
        linkStyle &&
        const {
          '0563C1',
          '0000FF',
          '000080',
          '954F72',
          '800080',
        }.contains(color);
    if (linkStyle) {
      result.styleId = null;
      result.explicitProperties.remove('rStyle');
    }
    if (defaultLinkLook && originalColor == '000000') {
      result.color = '000000';
    } else if (inheritedLinkColor || styledLinkColor || defaultLinkLook) {
      result.color =
          paragraph.properties.importedParagraphMark?.color ??
          WordStyles.ofParagraph(paragraph, document: document).color;
    }
    if (linkStyle && source.underline == WmlUnderline.single) {
      result.underline = WmlUnderline.none;
    } else if (defaultLinkLook) {
      final underline = property('u');
      result.underline = underline == null
          ? WmlUnderline.none
          : WmlUnderline.fromXml(value(underline));
    }
    return result;
  }

  static bool _plainFraming(WmlParagraph p, {bool links = false}) =>
      p.contentControlWrappers.isEmpty &&
      p.properties.fieldInstruction == null &&
      !p.properties.fieldBegin &&
      !p.properties.fieldSeparate &&
      !p.properties.fieldEnd &&
      !p.properties.pageNumberField &&
      p.properties.bookmarkName == null &&
      p.properties.noteId == null &&
      p.inlines.every(
        (i) =>
            i is WmlRun &&
            !i.isAtomic &&
            i.commentIds.isEmpty &&
            (links ? _canonicalLink(i.hyperlink) : i.hyperlink == null),
      );

  static bool _canonicalLink(WmlHyperlink? link) =>
      link != null &&
      link.anchor == null &&
      link.file == null &&
      (link.url == linkUrl ||
          link.url == _googleDocsUrl ||
          _googleDocsFieldUrl.hasMatch(link.url ?? ''));

  static bool _isCode(String text) =>
      text.startsWith(_citationPrefix) ||
      text.startsWith(_bibliographyPrefix) ||
      text.startsWith(preferencesPrefix);

  static bool _hasCode(String text) =>
      text.contains('$_citationPrefix{') ||
      text.contains('$_bibliographyPrefix{') ||
      text.contains(preferencesPrefix);

  static List<_TransferLink> _links(WmlParagraph paragraph) {
    final result = <_TransferLink>[];
    for (var i = 0; i < paragraph.inlines.length; i++) {
      final first = paragraph.inlines[i];
      if (first is! WmlRun || !_canonicalLink(first.hyperlink)) continue;
      final start = i;
      final text = StringBuffer(first.text);
      while (i + 1 < paragraph.inlines.length) {
        final next = paragraph.inlines[i + 1];
        if (next is! WmlRun ||
            !_canonicalLink(next.hyperlink) ||
            next.hyperlink!.url != first.hyperlink!.url) {
          break;
        }
        text.write(next.text);
        i++;
      }
      result.add(
        _TransferLink(start, i, text.toString(), first.hyperlink!.url!),
      );
    }
    return result;
  }

  static void _assertLinkOwnership(WmlParagraph paragraph, _TransferLink link) {
    if (paragraph.contentControlWrappers.isNotEmpty ||
        paragraph.properties.fieldInstruction != null ||
        paragraph.properties.fieldBegin ||
        paragraph.properties.fieldSeparate ||
        paragraph.properties.fieldEnd ||
        paragraph.properties.pageNumberField) {
      throw UnsupportedError(
        'A Zotero transfer link is inside protected field content.',
      );
    }
    var fieldDepth = 0;
    var controlDepth = 0;
    for (var i = 0; i <= link.last; i++) {
      final inline = paragraph.inlines[i];
      if (inline is WmlFieldBoundary) {
        if (inline.kind == WmlFieldBoundaryKind.begin) fieldDepth++;
        if (inline.kind == WmlFieldBoundaryKind.end) fieldDepth--;
      }
      if (inline is WmlContentControlBoundary) {
        controlDepth += inline.start ? 1 : -1;
      }
      if (fieldDepth < 0 || controlDepth < 0) {
        throw UnsupportedError(
          'A Zotero transfer link has unbalanced native boundaries.',
        );
      }
      if (i >= link.first &&
          (fieldDepth != 0 ||
              controlDepth != 0 ||
              inline is! WmlRun ||
              inline.isAtomic ||
              inline.commentIds.isNotEmpty)) {
        throw UnsupportedError(
          'A Zotero transfer link overlaps protected or atomic content.',
        );
      }
    }
  }

  /// Adjacent links to the same URL can merge during an Office round trip.
  /// Split only after a complete JSON object; prefix-like text inside quoted
  /// titles, locators and unknown metadata is never treated as another field.
  static List<String> _splitCodes(String text) {
    final result = <String>[];
    var at = 0;
    while (at < text.length) {
      while (at < text.length && _space(text.codeUnitAt(at))) {
        at++;
      }
      if (at == text.length) break;
      final start = at;
      final citation = text.startsWith(_citationPrefix, at);
      if (!citation && !text.startsWith(_bibliographyPrefix, at)) {
        throw const FormatException('Malformed Zotero transfer field code.');
      }
      at += citation ? _citationPrefix.length : _bibliographyPrefix.length;
      while (at < text.length && _space(text.codeUnitAt(at))) {
        at++;
      }
      if (at == text.length || text.codeUnitAt(at) != 0x7b) {
        throw const FormatException('Missing Zotero transfer field metadata.');
      }
      final stack = <int>[];
      var quoted = false;
      var escaped = false;
      do {
        final unit = text.codeUnitAt(at++);
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (unit == 0x5c) {
            escaped = true;
          } else if (unit == 0x22) {
            quoted = false;
          }
        } else if (unit == 0x22) {
          quoted = true;
        } else if (unit == 0x7b || unit == 0x5b) {
          stack.add(unit == 0x7b ? 0x7d : 0x5d);
          if (stack.length > 64) {
            throw const FormatException('Excessive Zotero field nesting.');
          }
        } else if (unit == 0x7d || unit == 0x5d) {
          if (stack.isEmpty || stack.removeLast() != unit) {
            throw const FormatException(
              'Malformed Zotero transfer field metadata.',
            );
          }
        }
      } while (at < text.length && (quoted || stack.isNotEmpty));
      if (quoted || stack.isNotEmpty) {
        throw const FormatException(
          'Incomplete Zotero transfer field metadata.',
        );
      }
      if (!citation) {
        final suffixAt = at;
        while (at < text.length && _space(text.codeUnitAt(at))) {
          at++;
        }
        if (text.startsWith('CSL_BIBLIOGRAPHY', at)) {
          at += 'CSL_BIBLIOGRAPHY'.length;
        } else {
          at = suffixAt;
        }
      }
      final code = text.substring(start, at);
      final native = ' ADDIN ZOTERO_$code ';
      final metadata = WordZotero.metadataOf(native);
      if (metadata == null) {
        throw const FormatException(
          'Malformed Zotero transfer field metadata.',
        );
      }
      if (citation) ZoteroCitation.fromJson(metadata);
      result.add(code);
    }
    if (result.isEmpty) {
      throw const FormatException('Empty Zotero transfer field.');
    }
    return result;
  }

  static bool _space(int unit) =>
      unit == 0x20 || unit == 9 || unit == 10 || unit == 13;

  static String _codeOf(WmlZoteroField field) {
    final native = field.instruction.trim();
    final pattern = field.kind == ZoteroFieldKind.citation
        ? RegExp(
            r'^(?:ADDIN\s+(?:ZOTERO_ITEM\s+)?)?CSL_CITATION\s+',
            caseSensitive: false,
          )
        : RegExp(
            r'^(?:ADDIN\s+ZOTERO_BIBL|CSL_BIBLIOGRAPHY)(?:\s+|$)',
            caseSensitive: false,
          );
    final match = pattern.firstMatch(native);
    if (match == null || !field.isValid) {
      throw const FormatException('Invalid Zotero native field.');
    }
    return '${field.kind == ZoteroFieldKind.citation ? _citationPrefix : _bibliographyPrefix}${native.substring(match.end).trim()}';
  }

  static ({int first, int last}) _packet(WmlZoteroField field) {
    final inlines = field.paragraph.inlines;
    if (field.run != null) {
      final index = inlines.indexOf(field.run!);
      return (first: index, last: index);
    }
    if (field.wholeParagraph) return (first: 0, last: inlines.length - 1);
    final stack = <({int first, int start, StringBuffer code})>[];
    var offset = 0;
    for (var i = 0; i < inlines.length; i++) {
      final inline = inlines[i];
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is! WmlFieldBoundary) continue;
      if (inline.kind == WmlFieldBoundaryKind.begin) {
        stack.add((first: i, start: offset, code: StringBuffer()));
      } else if (inline.kind == WmlFieldBoundaryKind.instruction &&
          stack.isNotEmpty) {
        stack.last.code.write(inline.text);
      } else if (inline.kind == WmlFieldBoundaryKind.end && stack.isNotEmpty) {
        final open = stack.removeLast();
        if (open.start == field.start &&
            open.code.toString() == field.instruction) {
          return (first: open.first, last: i);
        }
      }
    }
    throw UnsupportedError('A Zotero field has split or ambiguous boundaries.');
  }

  static void _clearField(WmlParagraph paragraph) => paragraph.properties
    ..fieldInstruction = null
    ..fieldBegin = false
    ..fieldSeparate = false
    ..fieldEnd = false
    ..pageNumberField = false;
}

final class _TransferLink {
  const _TransferLink(this.first, this.last, this.text, this.url);
  final int first;
  final int last;
  final String text;
  final String url;
}

/// An isolated transfer edit, committed only after the host accepts a complete
/// Zotero operation. Existing sections, block lists, notes and paragraphs keep
/// their identity so the editor can restore them through its usual undo state.
final class WordZoteroTransferPlan {
  WordZoteroTransferPlan._(this._source)
    : _guard = _TransferModelGuard(_source) {
    if (_source.sections.isEmpty) {
      throw const FormatException('The document has no body section.');
    }
    final sections = [
      for (final section in _source.sections) WmlClone.section(section),
    ];
    for (var i = 0; i < sections.length; i++) {
      sections[i].preservedStories.addAll(_source.sections[i].preservedStories);
      _pairBlocks(_source.sections[i].blocks, sections[i].blocks);
    }
    WmlNote copyNote(WmlNote note) {
      final copy = WmlNote(
        id: note.id,
        endnote: note.endnote,
        addReference: note.addReference,
        addReferenceSpace: note.addReferenceSpace,
        referencePropertiesXml: note.referencePropertiesXml,
        blocks: [for (final block in note.blocks) WmlClone.block(block)],
      );
      _notes[copy] = note;
      _pairBlocks(note.blocks, copy.blocks);
      return copy;
    }

    document =
        WmlDocument(
            sections: sections,
            footnotes: [for (final note in _source.footnotes) copyNote(note)],
            endnotes: [for (final note in _source.endnotes) copyNote(note)],
            comments: [for (final comment in _source.comments) comment.copy()],
            styles: List.of(_source.styles),
            properties: _source.properties.copy(),
            // The package is provenance for unchanged opaque content. Transfer and
            // the delegated citing edit never write it; serialization is a later
            // host save, after application to the original model.
            package: _source.package,
            sourceFootnoteSeparatorsPresent:
                _source.sourceFootnoteSeparatorsPresent,
            footnoteSeparator: _source.footnoteSeparator,
            zoteroDocumentData: _source.zoteroDocumentData,
            proofingLanguage: _source.proofingLanguage,
            autoHyphenation: _source.autoHyphenation,
            watermark: _source.watermark,
            sourceFileName: _source.sourceFileName,
            sourceByteLength: _source.sourceByteLength,
          )
          ..complexScriptLanguage = _source.complexScriptLanguage
          ..sourceBlankFootnoteSeparators =
              _source.sourceBlankFootnoteSeparators
          ..sourceDuplicateControlIds = Map.of(
            _source.sourceDuplicateControlIds,
          )
          ..importedStyles.addAll(_source.importedStyles);
  }

  final WmlDocument _source;
  final _TransferModelGuard _guard;

  /// Detached editable stories for the citing transaction. Its package is
  /// retained only as read-only provenance for opaque parts and relationships.
  /// Serialize the original source after [apply]; serializing this staging
  /// model before acceptance would write that shared package prematurely.
  late final WmlDocument document;
  final _paragraphs = Map<WmlParagraph, WmlParagraph>.identity();
  final _originals = Map<WmlBlock, WmlBlock>.identity();
  final _notes = Map<WmlNote, WmlNote>.identity();
  final _published = Map<WmlParagraph, WmlParagraph>.identity();
  final _visuals = Map<WmlVisual, WmlVisual>.identity();
  var _applied = false;

  WmlParagraph? paragraphFor(WmlParagraph original) => _paragraphs[original];
  WmlParagraph? originalParagraphFor(WmlParagraph staged) =>
      _published[staged] ?? (_originals[staged] as WmlParagraph?);

  List<WmlParagraph> get affectedParagraphs =>
      List.unmodifiable(_paragraphs.keys);

  void assertUnchanged() {
    if (_applied || !_guard.matches()) {
      throw StateError('The document changed while Zotero transfer was open.');
    }
  }

  void apply() {
    assertUnchanged();
    if (document.sections.length != _source.sections.length) {
      throw StateError('A transfer changed the document section structure.');
    }
    // Validate before touching the source, including cycles/duplicate owners
    // introduced by an unsupported caller of the detached model.
    _TransferModelGuard(document);
    final publication = _TransferPublication();
    for (var i = 0; i < document.sections.length; i++) {
      _prepareList(
        _source.sections[i].blocks,
        document.sections[i].blocks,
        publication,
      );
    }
    _prepareNotes(_source.footnotes, document.footnotes, publication);
    _prepareNotes(_source.endnotes, document.endnotes, publication);
    publication.apply();
    _published.addAll(publication.paragraphs);
    _source.zoteroDocumentData = document.zoteroDocumentData;
    _applied = true;
  }

  void _pairBlocks(List<WmlBlock> originals, List<WmlBlock> copies) {
    for (var i = 0; i < originals.length; i++) {
      final original = originals[i];
      final copy = copies[i];
      _originals[copy] = original;
      if (original is WmlParagraph && copy is WmlParagraph) {
        _paragraphs[original] = copy;
        for (var r = 0; r < original.inlines.length; r++) {
          final old = original.inlines[r];
          final next = copy.inlines[r];
          if (old is WmlRun && next is WmlRun && old.inlineVisual != null) {
            _visuals[next.inlineVisual!] = old.inlineVisual!;
          }
        }
      }
      final from = WordTree.childLists(original).toList();
      final to = WordTree.childLists(copy).toList();
      for (var c = 0; c < from.length; c++) {
        _pairBlocks(from[c], to[c]);
      }
    }
  }

  void _prepareList(
    List<WmlBlock> target,
    List<WmlBlock> staged,
    _TransferPublication publication,
  ) {
    publication.replace(target, [
      for (final block in staged) _prepareBlock(block, publication),
    ]);
  }

  WmlBlock _prepareBlock(WmlBlock staged, _TransferPublication publication) {
    final original = _originals[staged];
    if (staged is WmlParagraph) {
      final target = original is WmlParagraph ? original : WmlParagraph();
      final properties = staged.properties.copy();
      final inlines = WmlClone.inlines(staged.inlines);
      for (var i = 0; i < inlines.length; i++) {
        final run = inlines[i];
        final source = staged.inlines[i];
        if (run is WmlRun && source is WmlRun && source.inlineVisual != null) {
          run.inlineVisual = _visuals[source.inlineVisual] ?? run.inlineVisual;
        }
      }
      publication.replace(target.inlines, inlines);
      publication.changes.add(() => target.properties = properties);
      publication.paragraphs[staged] = target;
      return target;
    }
    if (original != null) {
      final from = WordTree.childLists(staged).toList();
      final to = WordTree.childLists(original).toList();
      if (from.length != to.length) {
        throw StateError('A transfer changed an existing container structure.');
      }
      for (var i = 0; i < from.length; i++) {
        _prepareList(to[i], from[i], publication);
      }
      return original;
    }
    return WmlClone.block(staged);
  }

  void _prepareNotes(
    List<WmlNote> target,
    List<WmlNote> staged,
    _TransferPublication publication,
  ) {
    final notes = <WmlNote>[];
    for (final note in staged) {
      final original = _notes[note];
      if (original != null) {
        _prepareList(original.blocks, note.blocks, publication);
        notes.add(original);
      } else {
        final added = WmlNote(
          id: note.id,
          endnote: note.endnote,
          addReference: note.addReference,
          addReferenceSpace: note.addReferenceSpace,
          referencePropertiesXml: note.referencePropertiesXml,
          blocks: [],
        );
        _prepareList(added.blocks, note.blocks, publication);
        notes.add(added);
      }
    }
    publication.replace(target, notes);
  }
}

/// Prepares every source write before publication. Public model constructors
/// retain caller-owned lists, which can have narrower runtime element types
/// (for example `List<WmlParagraph>` used as section blocks).
final class _TransferPublication {
  final changes = <void Function()>[];
  final paragraphs = Map<WmlParagraph, WmlParagraph>.identity();

  void replace<T>(List<T> target, List<T> values) {
    if (target.length == values.length &&
        values.indexed.every(
          (entry) => identical(target[entry.$1], entry.$2),
        )) {
      return;
    }
    try {
      // A sublist keeps the owner's runtime element type without changing its
      // contents. Check actual outgoing objects, including reused identities.
      final probe = target.sublist(0, 0);
      for (final value in values) {
        probe.add(value);
      }
      // Standard fixed-length and unmodifiable lists reject even this no-op.
      // Refuse them before any previously prepared paragraph/list is changed.
      target.length = target.length;
    } on Object {
      throw UnsupportedError(
        'Zotero transfer needs growable containers that accept the updated content.',
      );
    }
    changes.add(() {
      target.clear();
      // addAll checks the iterable's runtime type before checking its values;
      // individual writes also support valid covariant paragraph/run lists.
      for (final value in values) {
        target.add(value);
      }
    });
  }

  void apply() {
    for (final change in changes) {
      change();
    }
  }
}

/// Bounded ownership validation and an exact guard for mutable paragraph
/// content/formatting, links, field packets and the containing list identities.
final class _TransferModelGuard {
  _TransferModelGuard(this.document) {
    if (document.trackRevisions ||
        document.restrictEditing ||
        document.protectionFormattingRestricted ||
        document.revisions.any((revision) => revision.accepted == null)) {
      throw UnsupportedError(
        'Use an editable document without pending tracked changes for Zotero transfer.',
      );
    }
    final data = document.zoteroDocumentData;
    final separator = document.footnoteSeparator;
    final package = document.package;
    _checks.add(
      () =>
          !document.trackRevisions &&
          !document.restrictEditing &&
          !document.protectionFormattingRestricted &&
          !document.revisions.any((r) => r.accepted == null) &&
          document.zoteroDocumentData == data &&
          identical(document.footnoteSeparator, separator) &&
          identical(document.package, package),
    );
    _list(() => document.sections);
    _list(() => document.footnotes);
    _list(() => document.endnotes);
    _list(() => document.comments);
    for (final section in document.sections) {
      _blocks(() => section.blocks, true, 0);
      for (final read in <List<WmlParagraph> Function()>[
        () => section.header,
        () => section.footer,
        () => section.firstHeader,
        () => section.firstFooter,
        () => section.evenHeader,
        () => section.evenFooter,
      ]) {
        _list(read);
        for (final paragraph in read()) {
          _paragraph(paragraph, false);
        }
      }
      for (final opaque in section.preservedStories.values) {
        _opaque(opaque.xml);
      }
    }
    final body = Set<WmlParagraph>.identity()..addAll(supported);
    final anchors = <(bool, int), int>{};
    for (final paragraph in body) {
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        if (run.noteRefId == null) continue;
        final key = (run.noteRefEndnote, run.noteRefId!);
        anchors.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final bucket in [document.footnotes, document.endnotes]) {
      final ids = <int, int>{};
      for (final note in bucket) {
        ids.update(note.id, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final note in bucket) {
        final id = note.id;
        final referenceProperties = note.referencePropertiesXml;
        _checks.add(
          () =>
              note.id == id &&
              note.referencePropertiesXml == referenceProperties,
        );
        _blocks(
          () => note.blocks,
          id > 0 &&
              note.endnote == identical(bucket, document.endnotes) &&
              ids[id] == 1 &&
              anchors[(note.endnote, id)] == 1,
          0,
        );
      }
    }
    for (final comment in document.comments) {
      _list(() => comment.paragraphs);
      for (final paragraph in comment.paragraphs) {
        _paragraph(paragraph, false);
      }
    }
  }

  final WmlDocument document;
  final paragraphs = <WmlParagraph>[];
  final supported = Set<WmlParagraph>.identity();
  final _seen = Set<WmlBlock>.identity();
  final _checks = <bool Function()>[];

  bool matches() => _checks.every((check) => check());

  void _list<T>(List<T> Function() read) {
    final original = read();
    final contents = List<T>.of(original);
    _checks.add(() {
      final current = read();
      return identical(current, original) &&
          current.length == contents.length &&
          Iterable<int>.generate(
            current.length,
          ).every((i) => identical(current[i], contents[i]));
    });
  }

  void _blocks(List<WmlBlock> Function() read, bool allowed, int depth) {
    if (depth > 64) {
      throw const FormatException(
        'The Word story nesting exceeds the transfer limit.',
      );
    }
    _list(read);
    for (final block in read()) {
      if (!_seen.add(block)) {
        throw UnsupportedError(
          'A Word block has repeated or cyclic ownership.',
        );
      }
      if (block is WmlParagraph) {
        _paragraph(block, allowed, registered: true);
      } else if (block is WmlTable) {
        _list(() => block.rows);
        for (final row in block.rows) {
          _list(() => row.cells);
          for (final cell in row.cells) {
            _blocks(() => cell.blocks, allowed, depth + 1);
          }
        }
      } else if (block is WmlContentControlBlock) {
        _opaque(block.control.xml);
        _blocks(() => block.blocks, false, depth + 1);
      } else if (block is WmlFrame) {
        _blocks(() => block.blocks, false, depth + 1);
      } else if (block is WmlToc) {
        _paragraph(block.titleParagraph, false);
        for (final paragraph in block.itemParagraphs) {
          _paragraph(paragraph, false);
        }
      } else if (block is WmlOpaqueBlock) {
        _opaque(block.xml);
      }
    }
  }

  void _paragraph(
    WmlParagraph paragraph,
    bool allowed, {
    bool registered = false,
  }) {
    if (!registered && !_seen.add(paragraph)) {
      throw UnsupportedError(
        'A Word paragraph has repeated or cyclic ownership.',
      );
    }
    if (paragraphs.length >= 100000) {
      throw const FormatException('Too many paragraphs for Zotero transfer.');
    }
    paragraphs.add(paragraph);
    if (allowed) supported.add(paragraph);
    _list(() => paragraph.inlines);
    _list(() => paragraph.contentControlWrappers);
    final signature = _paragraphSignature(paragraph);
    _checks.add(() => _paragraphSignature(paragraph) == signature);
    for (final inline in paragraph.inlines) {
      if (inline is WmlOpaqueInline) _opaque(inline.content.xml);
    }
  }

  void _opaque(String xml) {
    if (RegExp(
      r'ZOTERO_|CSL_CITATION|CSL_BIBLIOGRAPHY|DOCUMENT_PREFERENCES',
      caseSensitive: false,
    ).hasMatch(xml)) {
      throw UnsupportedError(
        'Opaque Word content may contain Zotero data and cannot be transferred safely.',
      );
    }
  }
}

String _paragraphSignature(WmlParagraph paragraph) => jsonEncode([
  _paragraphProperties(paragraph.properties),
  for (final inline in paragraph.inlines)
    switch (inline) {
      WmlRun() => [
        'run',
        inline.text,
        _runProperties(inline.properties),
        inline.hyperlink?.url,
        inline.hyperlink?.anchor,
        inline.hyperlink?.file,
        inline.commentIds,
        inline.noteRefId,
        inline.noteRefEndnote,
        inline.noteRefCustomMark,
        inline.fieldInstruction,
        inline.fieldLocked,
        inline.fieldDirty,
        identityHashCode(inline.inlineVisual),
      ],
      WmlNoteMarker() => [
        'note-marker',
        inline.endnote,
        _runProperties(inline.properties),
      ],
      _ => [inline.runtimeType.toString(), identityHashCode(inline)],
    },
]);

List<Object?> _paragraphProperties(WmlParagraphProps p) => [
  p.sourcePropertiesXml,
  p.importedValues,
  if (p.importedParagraphMark != null) _runProperties(p.importedParagraphMark!),
  p.justification.name,
  p.lineSpacing,
  p.lineSpacingRule.name,
  p.spacingBefore,
  p.spacingAfter,
  p.explicitLineSpacing,
  p.explicitSpacingBefore,
  p.explicitSpacingAfter,
  p.explicitJustification,
  p.explicitIndent,
  p.indent.left,
  p.indent.right,
  p.indent.firstLine,
  p.indent.hanging,
  [
    for (final tab in p.tabs)
      [tab.position, tab.alignment.name, tab.leader.name],
  ],
  p.keepTogether,
  p.pageBreakBefore,
  p.columnBreakBefore,
  p.numId,
  p.numberingSuppressed,
  p.ilvl,
  p.listLabel,
  p.listRestart,
  p.pageNumberField,
  p.headingLevel,
  p.styleId,
  p.fieldInstruction,
  p.fieldBegin,
  p.fieldSeparate,
  p.fieldEnd,
  p.bookmarkName,
  p.sourceBookmarkName,
  p.rightToLeft,
  p.proofingLanguage,
  p.suppressAutoHyphens,
  p.dropCapLines,
  p.shadingFill,
  p.borderColor,
  p.noteId,
  p.endnoteRef,
];

List<Object?> _runProperties(WmlRunProps p) => [
  p.sourcePropertiesXml,
  p.importedValues,
  p.explicitProperties.toList()..sort(),
  p.styleId,
  p.bold,
  p.italic,
  p.underline.name,
  p.strike,
  p.smallCaps,
  p.allCaps,
  p.color,
  p.highlight,
  p.fontSizeHalfPoints,
  p.kerningHalfPoints,
  p.asciiFont,
  p.csFont,
  p.vertAlign.name,
  p.positionHalfPoints,
  p.proofingLanguage,
  p.noProof,
  p.complexScriptLanguage,
  p.complexScript,
];
