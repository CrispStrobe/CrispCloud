import 'dart:convert';
import 'dart:math';

import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';
import '../model/word_zotero.dart';
import '../model/word_zotero_data.dart';
import '../model/word_zotero_transfer.dart';
import '../properties/wml_properties.dart';
import 'odt_reader_images.dart';

/// A read-only, bounded plan for the explicit editable Zotero ODT export.
///
/// The ordinary ODT writer is deliberately more permissive about displaying
/// cached text. This plan first proves that every Zotero packet has one native
/// owner, and subsequently requires every planned endpoint to be emitted once.
/// It never edits the Word model, its source package or its preferences.
final class OdtWriterZoteroPlan {
  OdtWriterZoteroPlan(WmlDocument document) {
    if (WordZoteroTransfer.isTransferDocument(document)) {
      throw UnsupportedError(
        'Import the prepared Zotero transfer document before exporting editable ODT.',
      );
    }
    final owners = _ZoteroOwners(document);
    final images = OdtInlineImageValidator();
    final seenVisuals = Set<Object>.identity();
    for (final paragraph in owners.paragraphs) {
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        final picture = run.inlineVisual;
        if (picture == null) continue;
        if (!owners.supported.contains(paragraph) ||
            run.text != '\uFFFC' ||
            run.noteRefId != null ||
            run.fieldInstruction != null ||
            !seenVisuals.add(picture) ||
            !seenVisuals.add(picture.visual)) {
          throw UnsupportedError(
            'Editable Zotero ODT requires independently owned inline picture runs.',
          );
        }
        _xmlText(picture.visual.title);
        _xmlText(picture.visual.picture.altTitle);
        _xmlText(picture.visual.picture.altDescription);
        images.validateVisual(picture.visual);
      }
    }
    final fields = WordZotero.fields(document);
    if (fields.length > 10000) {
      throw const FormatException('Too many Zotero fields for editable ODT.');
    }
    final nativeData = WordZoteroDocumentData.read(document);
    if (fields.isNotEmpty && nativeData.isEmpty) {
      throw const FormatException(
        'Editable Zotero ODT needs document preferences.',
      );
    }
    documentData = WordZoteroDocumentData.toOdt(nativeData);
    _xmlText(documentData);
    var payloadBytes = utf8.encode(documentData).length;
    final claimedParagraphs = Set<WmlParagraph>.identity();
    final claimedInlines = Set<WmlInline>.identity();
    final claimedInstructions = Set<WmlFieldBoundary>.identity();
    final random = Random();
    final suffixes = <String>{};

    for (final field in fields) {
      if (field.paragraphs.any((p) => !owners.supported.contains(p)) ||
          field.paragraphs.any(
            (p) =>
                p.contentControlWrappers.isNotEmpty ||
                p.inlines.any((i) => i is WmlContentControlBoundary),
          ) ||
          field.run?.commentIds.isNotEmpty == true ||
          !(field.kind == ZoteroFieldKind.citation
              ? field.canEdit
              : WordZotero.canReplaceNativeBibliography(document, field))) {
        throw UnsupportedError(
          'Editable Zotero ODT needs complete unlocked fields in body paragraphs, visible body table cells or uniquely anchored note paragraphs. Note-table fields and other stories are not supported.',
        );
      }
      final name = _name(field, _suffix(random, suffixes));
      _xmlText(name);
      payloadBytes += utf8.encode(name).length;
      if (payloadBytes > 16 * 1024 * 1024) {
        throw const FormatException('Zotero ODT metadata exceeds the limit.');
      }
      _expected.add(name);
      for (final paragraph in field.paragraphs) {
        if (owners.notes[paragraph] case final note?) _fieldNotes.add(note);
        if (paragraph.inlines.any(
          (inline) => inline is WmlBreak && inline.type == WmlBreakType.column,
        )) {
          throw UnsupportedError(
            'A Zotero field paragraph with a column break cannot be exported as one ODT range.',
          );
        }
      }

      if (field.kind == ZoteroFieldKind.bibliography) {
        for (final paragraph in field.paragraphs) {
          if (paragraph.inlines.whereType<WmlRun>().any(
            (run) => run.inlineVisual != null,
          )) {
            throw UnsupportedError(
              'Editable Zotero ODT bibliography entries cannot contain pictures.',
            );
          }
          if (!claimedParagraphs.add(paragraph) ||
              paragraph.properties.headingLevel != null ||
              (paragraph.properties.numId != null &&
                  paragraph.properties.numId != 0 &&
                  !paragraph.properties.numberingSuppressed)) {
            throw UnsupportedError(
              'An ODT bibliography needs exclusively owned ordinary entry paragraphs.',
            );
          }
          for (final inline in paragraph.inlines) {
            if (!claimedInlines.add(inline)) _overlap();
            if (inline is WmlFieldBoundary) claimedInstructions.add(inline);
          }
        }
        _sectionStarts[field.paragraphs.first] = name;
        _sectionEnds[field.paragraphs.last] = name;
      } else if (field.wholeParagraph) {
        if (!claimedParagraphs.add(field.paragraph)) _overlap();
        for (final inline in field.paragraph.inlines) {
          if (!claimedInlines.add(inline)) _overlap();
        }
        _paragraphStarts[field.paragraph] = name;
        _paragraphEnds[field.paragraph] = name;
      } else {
        if (claimedParagraphs.contains(field.paragraph)) _overlap();
        final packet = _packet(field);
        for (var i = packet.first; i <= packet.last; i++) {
          final inline = field.paragraph.inlines[i];
          if (!claimedInlines.add(inline)) _overlap();
          if (inline is WmlFieldBoundary) claimedInstructions.add(inline);
        }
        _inlineStarts[field.paragraph.inlines[packet.first]] = name;
        _inlineEnds[field.paragraph.inlines[packet.last]] = name;
      }
    }

    // An incomplete/unknown native packet is not returned by WordZotero.fields.
    // Inspect the original instructions too, including fragments split across
    // runs or paragraphs, so this export cannot silently turn it into text.
    final unclaimed = StringBuffer();
    for (final paragraph in owners.paragraphs) {
      if (_looksZotero(paragraph.properties.fieldInstruction) &&
          !claimedParagraphs.contains(paragraph)) {
        _unrecognized();
      }
      for (final inline in paragraph.inlines) {
        if (inline is WmlRun &&
            _looksZotero(inline.fieldInstruction) &&
            !claimedInlines.contains(inline)) {
          _unrecognized();
        } else if (inline is WmlFieldBoundary &&
            inline.kind == WmlFieldBoundaryKind.instruction &&
            !claimedInstructions.contains(inline)) {
          unclaimed.write(inline.text);
        }
      }
    }
    if (_looksZotero(unclaimed.toString())) _unrecognized();
  }

  late final String documentData;
  final _sectionStarts = Map<WmlParagraph, String>.identity();
  final _sectionEnds = Map<WmlParagraph, String>.identity();
  final _paragraphStarts = Map<WmlParagraph, String>.identity();
  final _paragraphEnds = Map<WmlParagraph, String>.identity();
  final _inlineStarts = Map<WmlInline, String>.identity();
  final _inlineEnds = Map<WmlInline, String>.identity();
  final _fieldNotes = Set<WmlNote>.identity();
  final _expected = <String>{};
  final _started = <String>{};
  final _ended = <String>{};

  bool hasFieldsInNote(WmlNote note) => _fieldNotes.contains(note);

  void beforeBlock(XmlWriter writer, WmlBlock block) {
    final name = block is WmlParagraph ? _sectionStarts[block] : null;
    if (name == null) return;
    _start(name);
    writer.writeStartElement('section', prefix: 'text');
    writer.writeAttribute('text:name', name);
  }

  void afterBlock(XmlWriter writer, WmlBlock block) {
    final name = block is WmlParagraph ? _sectionEnds[block] : null;
    if (name == null) return;
    _end(name);
    writer.writeEndElement();
  }

  void beforeParagraph(XmlWriter writer, WmlParagraph paragraph) =>
      _mark(writer, _paragraphStarts[paragraph], start: true);

  void afterParagraph(XmlWriter writer, WmlParagraph paragraph) =>
      _mark(writer, _paragraphEnds[paragraph], start: false);

  bool hasInlineBoundary(WmlInline inline) =>
      _inlineStarts.containsKey(inline) || _inlineEnds.containsKey(inline);

  void beforeInline(XmlWriter writer, WmlInline inline) =>
      _mark(writer, _inlineStarts[inline], start: true);

  void afterInline(XmlWriter writer, WmlInline inline) =>
      _mark(writer, _inlineEnds[inline], start: false);

  void _mark(XmlWriter writer, String? name, {required bool start}) {
    if (name == null) return;
    start ? _start(name) : _end(name);
    writer.writeEmptyElement(
      start ? 'reference-mark-start' : 'reference-mark-end',
      prefix: 'text',
      attributes: {'text:name': name},
    );
  }

  void _start(String name) {
    if (!_started.add(name)) {
      throw UnsupportedError('A Zotero ODT field would be exported twice.');
    }
  }

  void _end(String name) {
    if (!_started.contains(name) || !_ended.add(name)) {
      throw UnsupportedError('A Zotero ODT field has ambiguous endpoints.');
    }
  }

  void verifyComplete() {
    if (_expected.length != _started.length ||
        _expected.length != _ended.length) {
      throw UnsupportedError(
        'Some Zotero fields would be lost by this ODT export.',
      );
    }
  }

  void writePreferences(XmlWriter writer) {
    var index = 1;
    for (var offset = 0; offset < documentData.length; index++) {
      var end = min(offset + 255, documentData.length);
      if (end < documentData.length &&
          documentData.codeUnitAt(end - 1) >= 0xd800 &&
          documentData.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      writer.writeStartElement('user-defined', prefix: 'meta');
      writer.writeAttribute('meta:name', 'ZOTERO_PREF_$index');
      writer.writeAttribute('meta:value-type', 'string');
      writer.writeText(documentData.substring(offset, end));
      writer.writeEndElement();
      offset = end;
    }
  }

  static String _name(WmlZoteroField field, String suffix) {
    final native = field.instruction.trim();
    final citation = field.kind == ZoteroFieldKind.citation;
    final pattern = citation
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
      throw const FormatException('Invalid native Zotero field.');
    }
    var payload = native.substring(match.end).trim();
    if (!citation && !payload.endsWith('CSL_BIBLIOGRAPHY')) {
      payload = '$payload CSL_BIBLIOGRAPHY';
    }
    return 'ZOTERO_${citation ? 'ITEM CSL_CITATION' : 'BIBL'} $payload RND$suffix';
  }

  static String _suffix(Random random, Set<String> used) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    for (var attempt = 0; attempt < 100; attempt++) {
      final value = String.fromCharCodes([
        for (var index = 0; index < 10; index++)
          alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ]);
      if (used.add(value)) return value;
    }
    throw StateError('Could not allocate a unique Zotero ODT identity.');
  }

  static ({int first, int last}) _packet(WmlZoteroField field) {
    final inlines = field.paragraph.inlines;
    if (field.run case final run?) {
      final index = inlines.indexOf(run);
      if (index < 0) _unrecognized();
      return (first: index, last: index);
    }
    final stack = <({int index, int offset, StringBuffer code})>[];
    var offset = 0;
    for (var index = 0; index < inlines.length; index++) {
      final inline = inlines[index];
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is! WmlFieldBoundary) continue;
      switch (inline.kind) {
        case WmlFieldBoundaryKind.begin:
          stack.add((index: index, offset: offset, code: StringBuffer()));
        case WmlFieldBoundaryKind.instruction:
          if (stack.isNotEmpty) stack.last.code.write(inline.text);
        case WmlFieldBoundaryKind.separate:
          break;
        case WmlFieldBoundaryKind.end:
          if (stack.isEmpty) continue;
          final open = stack.removeLast();
          if (open.offset == field.start &&
              open.code.toString() == field.instruction) {
            return (first: open.index, last: index);
          }
      }
    }
    _unrecognized();
  }

  static Never _overlap() => throw UnsupportedError(
    'Overlapping Zotero packets cannot be exported to editable ODT.',
  );
}

final class _ZoteroOwners {
  _ZoteroOwners(WmlDocument document) {
    if (document.trackRevisions ||
        document.restrictEditing ||
        document.protectionFormattingRestricted ||
        document.revisions.any((revision) => revision.accepted == null)) {
      throw UnsupportedError(
        'Editable Zotero ODT requires an editable document without pending tracked changes.',
      );
    }
    for (final section in document.sections) {
      _blocks(section.blocks, allowed: true);
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        for (final paragraph in story) {
          _paragraph(paragraph, false);
        }
      }
      for (final story in section.preservedStories.values) {
        _opaque(story.xml);
      }
    }
    final anchors = <(bool, int), int>{};
    for (final paragraph in supported) {
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        if (run.noteRefId case final id?) {
          anchors.update(
            (run.noteRefEndnote, id),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    for (final bucket in [document.footnotes, document.endnotes]) {
      final ids = <int, int>{};
      for (final note in bucket) {
        ids.update(note.id, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final note in bucket) {
        _blocks(
          note.blocks,
          allowed:
              note.id > 0 &&
              note.endnote == identical(bucket, document.endnotes) &&
              ids[note.id] == 1 &&
              anchors[(note.endnote, note.id)] == 1,
          note: note,
        );
      }
    }
    for (final comment in document.comments) {
      for (final paragraph in comment.paragraphs) {
        _paragraph(paragraph, false);
      }
    }
    _retainedNoteMetadata(document);
  }

  final paragraphs = <WmlParagraph>[];
  final supported = Set<WmlParagraph>.identity();
  final notes = Map<WmlParagraph, WmlNote>.identity();
  final _seen = Set<Object>.identity();

  void _blocks(
    List<WmlBlock> blocks, {
    required bool allowed,
    WmlNote? note,
    int depth = 0,
  }) {
    if (depth > 64) {
      throw const FormatException('ODT story nesting exceeds the limit.');
    }
    for (final block in blocks) {
      if (!_seen.add(block)) _alias();
      switch (block) {
        case WmlParagraph():
          _paragraph(block, allowed, note: note, registered: true);
        case WmlTable():
          final valid = _supportedGrid(block);
          for (final row in block.rows) {
            if (!_seen.add(row)) _alias();
            for (final cell in row.cells) {
              if (!_seen.add(cell)) _alias();
              _blocks(
                cell.blocks,
                allowed:
                    allowed &&
                    valid &&
                    note == null &&
                    cell.vMerge != WmlVMerge.cont,
                note: note,
                depth: depth + 1,
              );
            }
          }
        case WmlContentControlBlock():
          _opaque(block.control.xml);
          _blocks(block.blocks, allowed: false, note: note, depth: depth + 1);
        case WmlFrame():
          _blocks(block.blocks, allowed: false, note: note, depth: depth + 1);
        case WmlToc():
          _paragraph(block.titleParagraph, false);
          for (final paragraph in block.itemParagraphs) {
            _paragraph(paragraph, false);
          }
        case WmlOpaqueBlock():
          _opaque(block.xml);
        case WmlEquation() || WmlVisual():
          break;
      }
    }
  }

  static bool _supportedGrid(WmlTable table) {
    if (table.rows.isEmpty ||
        table.rows.length > 256 ||
        table.grid.length > 32 ||
        table.grid.any((width) => !width.isFinite || width <= 0) ||
        table.grid.fold<double>(0, (sum, width) => sum + width) > 4000) {
      return false;
    }
    int? columns = table.grid.isEmpty ? null : table.grid.length;
    var previous = <(int, int)>{};
    for (final row in table.rows) {
      if (row.gridBefore != 0 || row.gridAfter != 0 || row.cells.isEmpty) {
        return false;
      }
      var column = 0;
      final current = <(int, int)>{};
      for (final cell in row.cells) {
        if (cell.gridSpan < 1 || cell.gridSpan > 32) return false;
        final key = (column, cell.gridSpan);
        if (cell.vMerge == WmlVMerge.cont) {
          if (!previous.contains(key)) return false;
          current.add(key);
        } else if (cell.vMerge == WmlVMerge.restart) {
          current.add(key);
        }
        column += cell.gridSpan;
        if (column > 32) return false;
      }
      columns ??= column;
      if (columns != column) return false;
      previous = current;
    }
    return true;
  }

  void _paragraph(
    WmlParagraph paragraph,
    bool allowed, {
    WmlNote? note,
    bool registered = false,
  }) {
    if (!registered && !_seen.add(paragraph)) _alias();
    if (paragraphs.length >= 100000) {
      throw const FormatException('Too many ODT paragraphs.');
    }
    paragraphs.add(paragraph);
    _runPosition(paragraph.properties.importedParagraphMark);
    if (allowed) supported.add(paragraph);
    if (note != null) notes[paragraph] = note;
    if (_looksZotero(paragraph.properties.bookmarkName)) _unrecognized();
    for (final control in paragraph.contentControlWrappers) {
      _opaque(control.xml);
    }
    for (final inline in paragraph.inlines) {
      if (!_seen.add(inline)) _alias();
      if (inline is WmlRun) _runPosition(inline.properties);
      if (inline is WmlNoteMarker) _runPosition(inline.properties);
      if (inline is WmlOpaqueInline) _opaque(inline.content.xml);
      if (inline is WmlContentControlBoundary) _opaque(inline.control.xml);
      if (inline is WmlBookmarkBoundary) {
        if (_looksZotero(inline.name)) _unrecognized();
        _opaque(inline.sourceXml);
      }
      if (inline is WmlFieldBoundary) {
        _opaque(inline.sourceXml);
        _opaque(inline.runPropertiesXml);
      }
    }
  }

  static void _runPosition(WmlRunProps? properties) {
    // Native DOCX import already resolves defaults and style inheritance into
    // these properties. Check the effective value, including paragraph marks
    // that affect line height, without rejecting an explicit zero override.
    // ODT superscript/subscript is separate from Word's absolute baseline shift.
    if (properties != null && properties.positionHalfPoints != 0) {
      throw UnsupportedError(
        'Editable Zotero ODT cannot preserve explicitly raised or lowered text.',
      );
    }
  }

  /// Special note definitions are retained in the original DOCX part rather
  /// than the editable note list. Inspect just those preserved definitions;
  /// normal source-note XML can be stale after legitimate edits or unlinking.
  static void _retainedNoteMetadata(WmlDocument document) {
    final package = document.package;
    if (package == null) return;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    if (office?.targetMode == RelationshipTargetMode.external) {
      throw const FormatException('The Word main part must be internal.');
    }
    final main = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final relationships = package.relationshipsFor(main);
    for (final kind in ['footnote', 'endnote']) {
      final relationship = relationships.firstByType(
        kind == 'footnote'
            ? RelationshipTypes.footnotes
            : RelationshipTypes.endnotes,
      );
      if (relationship?.targetMode == RelationshipTargetMode.external) {
        throw const FormatException('Native note metadata must be internal.');
      }
      final uri = relationship == null
          ? OpcUris.resolve(main, '${kind}s.xml')
          : relationships.resolve(relationship);
      final part = package.getPart(uri);
      if (part == null) continue;
      if (part.length > 16 * 1024 * 1024) {
        throw const FormatException(
          'Native note metadata exceeds the ODT limit.',
        );
      }
      final reader = XmlPullReader(part.readText());
      int? retainedDepth;
      final retainedText = StringBuffer();
      var elements = 0;
      while (reader.next()) {
        if (reader.depth > 128 || elements > 100000) {
          throw const FormatException(
            'Native note metadata exceeds the ODT limit.',
          );
        }
        if (retainedDepth != null && reader.depth < retainedDepth) {
          retainedDepth = null;
        }
        if (reader.eventType == XmlEventType.startElement) {
          elements++;
          if (reader.namespaceUri == OfficeNamespaces.w &&
              reader.localName == kind &&
              const {
                'separator',
                'continuationSeparator',
                'continuationNotice',
              }.contains(
                reader.getAttribute('type', namespaceUri: OfficeNamespaces.w),
              )) {
            retainedDepth = reader.depth;
          }
          if (retainedDepth != null) {
            for (var i = 0; i < reader.attributeCount; i++) {
              if (_looksZotero(reader.attributeValue(i))) _unrecognized();
            }
          }
        } else if (retainedDepth != null &&
            (reader.eventType == XmlEventType.characters ||
                reader.eventType == XmlEventType.cdata)) {
          retainedText.write(reader.text);
        }
      }
      if (_looksZotero(retainedText.toString())) _unrecognized();
    }
  }

  static void _opaque(String? xml) {
    if (xml == null || xml.isEmpty) return;
    if (xml.length > 8 * 1024 * 1024 || _looksZotero(xml)) _unrecognized();
    // Entity-encoded names/instructions must not bypass the opaque-data guard.
    final reader = XmlPullReader(xml);
    final text = StringBuffer();
    var elements = 0;
    while (reader.next()) {
      if (reader.depth > 128 || elements > 100000) {
        throw const FormatException('Native metadata exceeds the ODT limit.');
      }
      if (reader.eventType == XmlEventType.startElement) {
        elements++;
        for (var index = 0; index < reader.attributeCount; index++) {
          if (_looksZotero(reader.attributeValue(index))) _unrecognized();
        }
      } else if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        text.write(reader.text);
      }
    }
    if (elements == 0) {
      throw const FormatException('Uninspectable native ODT export metadata.');
    }
    if (_looksZotero(text.toString())) _unrecognized();
  }

  static Never _alias() => throw UnsupportedError(
    'Repeated or cyclic Word ownership cannot be exported as editable Zotero ODT.',
  );
}

bool _looksZotero(String? text) =>
    text != null &&
    RegExp(
      r'ZOTERO|CSL_CITATION|CSL_BIBLIOGRAPHY|DOCUMENT_PREFERENCES',
      caseSensitive: false,
    ).hasMatch(text);

Never _unrecognized() => throw UnsupportedError(
  'Unrecognized, incomplete or opaque Zotero data cannot be exported safely to editable ODT.',
);

void _xmlText(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index < value.length) {
        final low = value.codeUnitAt(index);
        if (low >= 0xdc00 && low <= 0xdfff) continue;
      }
      throw const FormatException(
        'Zotero metadata contains an invalid Unicode character.',
      );
    }
    if ((unit < 0x20 && unit != 9 && unit != 10 && unit != 13) ||
        (unit >= 0xdc00 && unit <= 0xdfff) ||
        unit == 0xfffe ||
        unit == 0xffff) {
      throw const FormatException(
        'Zotero metadata contains a character unsupported by XML.',
      );
    }
  }
}
