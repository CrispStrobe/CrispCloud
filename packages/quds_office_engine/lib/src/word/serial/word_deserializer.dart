import 'dart:typed_data';

import '../../office/office_document_properties.dart';
import '../../opc/content_types.dart';
import '../../opc/ole/embedded_part.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../math/omml_document.dart';
import '../math/omml_io.dart';
import '../model/wml_clone.dart';
import '../model/wml_document.dart';
import '../model/wml_run_edit.dart';
import '../model/word_bookmarks.dart';
import '../model/word_content_controls.dart';
import '../model/word_field_spans.dart';
import '../model/word_fields.dart';
import '../model/word_link.dart';
import '../model/word_notes.dart';
import '../model/word_proofing_language.dart';
import '../model/word_revision.dart';
import '../model/word_styles.dart';
import '../model/word_toc.dart';
import '../model/word_tree.dart';
import '../model/word_zotero.dart';
import '../properties/wml_properties.dart';
import 'word_bibliography_io.dart';
import 'word_bookmark_io.dart';
import 'word_comment_io.dart';
import 'word_content_control_io.dart';
import 'word_drawing_io.dart';
import 'word_footnote_separator_io.dart';
import 'word_markup_compatibility.dart';
import 'word_opaque_io.dart';
import 'word_property_io.dart';
import 'word_section_io.dart';
import 'word_serializer.dart';
import 'word_settings_io.dart';
import 'word_table_property_io.dart';

part 'word_paragraph_style.dart';
part 'word_style_cascade.dart';

enum _SdtBreakLayout { none, liftLast, opaque }

typedef _ImportedFieldChar = ({WmlFieldBoundaryKind? kind, String? xml});

/// Reads a `.docx` OPC package into a [WmlDocument] tree.
class WordDeserializer {
  final List<WmlEquation> _pendingEquations = <WmlEquation>[];
  final List<WmlVisual> _pendingVisuals = <WmlVisual>[];
  final List<WmlFrame> _pendingFrames = <WmlFrame>[];
  final List<int> _openCommentIds = <int>[];
  final Map<WmlParagraphProps, XmlElement> _paragraphFormatChanges = {};
  final Map<String, List<_NativeMoveRange>> _moveRanges = {};
  final Map<WmlParagraph, List<Object>> _revisionAncestors = Map.identity();

  bool _readMoveBoundary(XmlPullReader reader, String story) {
    if (reader.namespaceUri != OfficeNamespaces.w ||
        !const {
          'moveFromRangeStart',
          'moveFromRangeEnd',
          'moveToRangeStart',
          'moveToRangeEnd',
        }.contains(reader.localName)) {
      return false;
    }
    final node = XmlDocument.readElement(reader);
    final from = node.localName.startsWith('moveFrom');
    final key = '$story:${from ? 'moveFrom' : 'moveTo'}';
    final ranges = _moveRanges.putIfAbsent(key, () => []);
    if (node.localName.endsWith('Start')) {
      ranges.add(_NativeMoveRange(node));
    } else {
      final id = node.getAttribute('id', namespaceUri: OfficeNamespaces.w);
      final index = ranges.lastIndexWhere(
        (r) =>
            r.start.getAttribute('id', namespaceUri: OfficeNamespaces.w) == id,
      );
      if (index >= 0) {
        final range = ranges.removeAt(index);
        if (range.revisions.isNotEmpty) {
          range.revisions.last.moveEndXml = XmlDocument(
            root: node,
          ).toXmlString(declaration: false);
        }
      }
    }
    return true;
  }

  OpcPackage? _package;
  String? _docUri;
  WmlSection? _pendingParagraphSectPr;
  bool _liftSdtSectionBreak = false;
  int _nextSplitControlId = 0x30000000;

  /// Bookmark endpoints found between blocks (directly in the body, a
  /// table, row or cell). OOXML allows them there and Word writes them
  /// routinely, but the model keeps bookmarks inside paragraphs. A start is
  /// moved to the beginning of the next paragraph and an end to the close of
  /// the previous one, so the bookmark still covers the same text; markers
  /// stay queued in document order while anything is pending, which keeps
  /// empty bookmarks (start immediately followed by end) well ordered.
  final List<WmlBookmarkBoundary> _blockMarkers = <WmlBookmarkBoundary>[];
  WmlParagraph? _lastBlockParagraph;
  int _drawingDepth = 0;
  WmlDocument? _document;
  WmlNote? _readingNote;
  bool _noteMarkCaptured = false;
  final Set<WmlTable> _tablesWithOwnBorders = Set<WmlTable>.identity();
  final Set<WmlTable> _tablesWithOwnBorderWidths = Set<WmlTable>.identity();
  final Set<WmlTable> _tablesWithOwnCellMargins = Set<WmlTable>.identity();
  final Set<WmlTable> _tablesWithOwnDirection = Set<WmlTable>.identity();
  final Map<WmlTableCell, Map<String, bool?>> _cellBorderValues =
      Map<WmlTableCell, Map<String, bool?>>.identity();
  final Set<WmlRunProps> _notBold = Set<WmlRunProps>.identity();
  final Set<WmlRunProps> _notItalic = Set<WmlRunProps>.identity();
  final Map<WmlTable, _TableLook> _tableLooks =
      Map<WmlTable, _TableLook>.identity();

  final _paragraphPropertyXml = <(Map<String, String>, String, bool), String>{};

  final _runPropertyCache =
      <
        (Map<String, String>, String, bool),
        ({WmlRunProps props, String xml, bool notBold, bool notItalic})
      >{};

  /// read API.
  WmlDocument read(OpcPackage package) {
    // A reader may be reused after a truncated document or a parse failure.
    // Story state belongs to one document and must not contaminate the next.
    _paragraphPropertyXml.clear();
    _runPropertyCache.clear();
    _pendingEquations.clear();
    _pendingVisuals.clear();
    _pendingFrames.clear();
    _openCommentIds.clear();
    _paragraphFormatChanges.clear();
    _moveRanges.clear();
    _revisionAncestors.clear();
    _tablesWithOwnBorders.clear();
    _tablesWithOwnBorderWidths.clear();
    _tablesWithOwnCellMargins.clear();
    _tablesWithOwnDirection.clear();
    _cellBorderValues.clear();
    _tableLooks.clear();
    _notBold.clear();
    _notItalic.clear();
    _pendingParagraphSectPr = null;
    _liftSdtSectionBreak = false;
    _nextSplitControlId = 0x30000000;
    _openFields.clear();
    _tocBoundaries.clear();
    _fieldCharNamespaces = null;
    _emptyFieldChars.clear();
    _fieldSourceElements.clear();
    _blockMarkers.clear();
    _lastBlockParagraph = null;
    _drawingDepth = 0;
    _document = null;
    _package = null;
    _docUri = null;
    _readingNote = null;
    _noteMarkCaptured = false;
    final PackageRelationship? office = package.packageRelationships
        .firstByType(RelationshipTypes.officeDocument);
    final String docUri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final PackagePart? part = package.getPart(docUri);
    if (part == null) {
      return WmlDocument(
        package: package,
        properties: OfficeDocumentProperties.fromPackage(package),
      );
    }
    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    final WmlDocument document = WmlDocument(
      package: package,
      sections: <WmlSection>[],
      properties: OfficeDocumentProperties.fromPackage(package),
    );
    _package = package;
    _docUri = docUri;
    _document = document;
    _pendingParagraphSectPr = null;
    WmlSection section = WmlSection();
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (WordBookmarkIo.isMarker(reader)) {
        _blockMarker(reader);
      } else if (reader.localName == 'p' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _addParagraph(section.blocks, _readParagraph(reader, package, docUri));
        section = _flushParagraphSectPr(document, section);
      } else if ((reader.localName == 'oMathPara' ||
              reader.localName == 'oMath') &&
          (reader.namespaceUri == OfficeNamespaces.m || reader.prefix == 'm')) {
        final OmmlEquation? math = OmmlIo.readFrom(reader);
        if (math != null) {
          section.blocks.add(WmlEquation(math: math));
        }
      } else if (reader.localName == 'tbl' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        section.blocks.add(_readTable(reader, package, docUri));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        section = _readBodySdt(reader, package, docUri, document, section);
      } else if (reader.localName == 'altChunk' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        section.blocks.add(WordOpaqueIo.read(reader, package, docUri));
      } else if (reader.localName == 'sectPr' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _readSectPr(reader, section, package, docUri);
        document.sections.add(section);
        section = WmlSection();
      } else if (reader.depth == 3) {
        // Any other unmodeled body element is kept verbatim, together with
        // the provenance of the relationships it references.
        section.blocks.add(WordOpaqueIo.read(reader, package, docUri));
      }
    }
    _endBlockStory();
    if (section.blocks.isNotEmpty || document.sections.isEmpty) {
      document.sections.add(section);
    }
    _ensureHeadersFooters(document, package, docUri);
    _readNotes(document, package, docUri);
    // Comments share the document's effective style cascade, including
    // inherited proofing language and explicit noProof resets.
    _readComments(document, package, docUri);
    _readCommentsExtended(document, package, docUri);
    _readStyles(document, package, docUri);
    _applyDocumentStyles(document);
    _notBold.clear();
    _notItalic.clear();
    _applyTableStyles(document, package, docUri);
    _applyNumbering(document, package, docUri);
    // Repair the actual paragraphs before TOC ranges are copied into a cache.
    WordBookmarks.repairUnpaired(document);
    _collapseTocFields(document);
    _readWatermark(document, package);
    WordBibliographyIo.read(document, package, docUri);
    _readSettingsFlags(document, package, docUri);
    if (document.revisions.isNotEmpty) {
      final bodyIndices = <WmlParagraph, int>{
        for (final entry in document.paragraphs.indexed) entry.$2: entry.$1,
      };
      for (final revision in document.revisions) {
        revision.paragraphIndex = bodyIndices[revision.targetParagraph] ?? -1;
      }
    }
    WordContentControls.recordImported(document);
    _fieldCharNamespaces = null;
    _emptyFieldChars.clear();
    _fieldSourceElements.clear();
    _paragraphPropertyXml.clear();
    _runPropertyCache.clear();
    return document;
  }

  /// readBytes API.
  WmlDocument readBytes(Uint8List bytes, {String? password}) =>
      read(OpcPackage.openBytes(bytes, password: password));

  /// Body-level controls may span section boundaries. A trailing break is
  /// lifted after the control; multiple breaks split the control into one
  /// segment per section, keeping its metadata and assigning fresh IDs to the
  /// later segments so the result is a valid native control tree.
  WmlSection _readBodySdt(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlDocument document,
    WmlSection section,
  ) {
    final source = XmlDocument.readElement(reader);
    final layout = _sdtBreakLayout(source);
    if (layout != _SdtBreakLayout.opaque) {
      section.blocks.addAll(
        _readSdtElement(
          source,
          package,
          docUri,
          allowSectionBreak: layout == _SdtBreakLayout.liftLast,
        ),
      );
      return _flushParagraphSectPr(document, section);
    }
    final segments = _splitSdt(source);
    if (segments == null) {
      throw UnsupportedError(
        'A section break inside a content control cannot yet be imported safely',
      );
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (i > 0) _retagSdt(segment, _nextSplitControlId++);
      section.blocks.addAll(
        _readSdtElement(segment, package, docUri, allowSectionBreak: true),
      );
      section = _flushParagraphSectPr(document, section);
    }
    return section;
  }

  List<WmlBlock> _readSdtElement(
    XmlElement source,
    OpcPackage package,
    String docUri, {
    required bool allowSectionBreak,
  }) {
    final reader = XmlPullReader(
      XmlDocument(root: source).toXmlString(declaration: false),
    )..next();
    return _readSdt(
      reader,
      package,
      docUri,
      allowSectionBreak: allowSectionBreak,
    );
  }

  /// Splits a control at top-level paragraph section breaks. Nested breaks or
  /// breaks outside a paragraph return null and remain refused.
  List<XmlElement>? _splitSdt(XmlElement source) {
    final content = source.firstChild(
      'sdtContent',
      namespaceUri: OfficeNamespaces.w,
    );
    if (content == null) return null;
    final children = content.childElements.toList();
    final segments = <XmlElement>[];
    var current = <XmlElement>[];
    var breaks = 0;
    for (final child in children) {
      final found = <XmlElement>[];
      void collect(XmlElement node) {
        for (final nested in node.childElements) {
          if (nested.localName == 'sectPr' &&
              nested.namespaceUri == OfficeNamespaces.w) {
            found.add(nested);
          }
          collect(nested);
        }
      }

      collect(child);
      final directBreak =
          child.localName == 'p' &&
          child
                  .firstChild('pPr', namespaceUri: OfficeNamespaces.w)
                  ?.firstChild('sectPr', namespaceUri: OfficeNamespaces.w) !=
              null;
      if (found.isNotEmpty && (!directBreak || found.length != 1)) return null;
      current.add(child);
      if (directBreak) {
        segments.add(_sdtSegment(source, current));
        current = <XmlElement>[];
        breaks++;
      }
    }
    if (breaks == 0) return null;
    if (current.isNotEmpty) segments.add(_sdtSegment(source, current));
    return segments;
  }

  XmlElement _sdtSegment(XmlElement source, List<XmlElement> children) {
    final copy = source.copy();
    final content = copy.firstChild(
      'sdtContent',
      namespaceUri: OfficeNamespaces.w,
    )!;
    content.children.clear();
    for (final child in children) {
      content.addChild(child.copy());
    }
    return copy;
  }

  void _retagSdt(XmlElement segment, int id) {
    final properties = segment.firstChild(
      'sdtPr',
      namespaceUri: OfficeNamespaces.w,
    );
    properties
        ?.firstChild('id', namespaceUri: OfficeNamespaces.w)
        ?.setAttribute('val', '$id', namespaceUri: OfficeNamespaces.w);
  }

  List<WmlBlock> _readSdt(
    XmlPullReader reader,
    OpcPackage package,
    String docUri, {
    bool allowSectionBreak = false,
  }) {
    final contentType = package.getPart(docUri)?.contentType;
    if (contentType == OfficeContentTypes.wordHeader ||
        contentType == OfficeContentTypes.wordFooter ||
        contentType == OfficeContentTypes.wordComments) {
      _unsupportedControl(
        docUri,
        'block control in a paragraph-only auxiliary story',
      );
    }
    final source = XmlDocument.readElement(reader);
    final breakLayout = _sdtBreakLayout(source);
    if (breakLayout == _SdtBreakLayout.opaque ||
        (breakLayout == _SdtBreakLayout.liftLast && !allowSectionBreak)) {
      throw UnsupportedError(
        'A section break inside a content control cannot yet be imported safely',
      );
    }
    final control = WordContentControlIo.capture(source, package, docUri);
    final content = _sdtContentReader(source);
    final previousLift = _liftSdtSectionBreak;
    _liftSdtSectionBreak = breakLayout == _SdtBreakLayout.liftLast;
    final List<WmlBlock> blocks;
    try {
      blocks = content == null
          ? <WmlBlock>[]
          : _readBlockContent(content, package, docUri);
    } finally {
      _liftSdtSectionBreak = previousLift;
    }
    final tag = control.tag ?? '';
    if (tag.startsWith('qudsFrame:') &&
        !(blocks.length == 1 && blocks.single is WmlFrame)) {
      final frame = _frameFromTag(tag, List<WmlBlock>.of(blocks));
      blocks
        ..clear()
        ..add(frame);
    }
    return <WmlBlock>[WmlContentControlBlock(control: control, blocks: blocks)];
  }

  /// A body control may end with a single section break, which belongs to the
  /// document section rather than the control. More than one break, a nested
  /// break, or a break before the final paragraph cannot be lifted without
  /// changing the control boundary, so the whole control is preserved opaquely.
  _SdtBreakLayout _sdtBreakLayout(XmlElement source) {
    final content = source.firstChild(
      'sdtContent',
      namespaceUri: OfficeNamespaces.w,
    );
    if (content == null) return _SdtBreakLayout.none;
    final children = content.childElements.toList();
    var breaks = 0;
    var lastBreakIndex = -1;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final found = <XmlElement>[];
      void collect(XmlElement node) {
        for (final nested in node.childElements) {
          if (nested.localName == 'sectPr' &&
              nested.namespaceUri == OfficeNamespaces.w) {
            found.add(nested);
          }
          collect(nested);
        }
      }

      collect(child);
      if (found.isEmpty) continue;
      if (child.localName != 'p' || found.length != 1) {
        return _SdtBreakLayout.opaque;
      }
      final properties = child.firstChild(
        'pPr',
        namespaceUri: OfficeNamespaces.w,
      );
      if (properties?.firstChild('sectPr', namespaceUri: OfficeNamespaces.w) ==
          null) {
        return _SdtBreakLayout.opaque;
      }
      breaks += found.length;
      lastBreakIndex = i;
    }
    if (breaks == 0) return _SdtBreakLayout.none;
    return breaks == 1 && lastBreakIndex == children.length - 1
        ? _SdtBreakLayout.liftLast
        : _SdtBreakLayout.opaque;
  }

  XmlPullReader? _sdtContentReader(XmlElement source) {
    final inner = WordMarkupCompatibilityReader(
      XmlDocument(root: source).toXmlString(declaration: false),
    )..next();
    final depth = inner.depth;
    while (inner.next()) {
      if (inner.eventType == XmlEventType.startElement &&
          inner.depth == depth + 1 &&
          inner.localName == 'sdtContent' &&
          inner.namespaceUri == OfficeNamespaces.w) {
        return inner;
      }
    }
    return null;
  }

  /// Auxiliary stories currently own paragraphs directly. A native block SDT
  /// around one paragraph can retain its exact shell on that live paragraph;
  /// richer block topology must not be flattened into this representation.
  ({WmlParagraph paragraph, String? paragraphId}) _readAuxiliaryControl(
    XmlPullReader reader,
    OpcPackage package,
    String storyUri,
    String storyKind,
  ) {
    final source = XmlDocument.readElement(reader);
    var leaf = source;
    while (leaf.localName == 'sdt' && leaf.namespaceUri == OfficeNamespaces.w) {
      final content = leaf.firstChild(
        'sdtContent',
        namespaceUri: OfficeNamespaces.w,
      );
      final children = content?.childElements.toList() ?? <XmlElement>[];
      if (children.length != 1) {
        _unsupportedControl(
          storyUri,
          'block control in a paragraph-only $storyKind story requires '
          'exactly one paragraph',
        );
      }
      leaf = children.single;
    }
    if (leaf.localName != 'p' || leaf.namespaceUri != OfficeNamespaces.w) {
      _unsupportedControl(
        storyUri,
        'block control in a paragraph-only $storyKind story contains '
        'unsupported ${leaf.localName} content',
      );
    }
    bool hasRichBlockContent(XmlElement element) {
      if ((element.namespaceUri == OfficeNamespaces.w &&
              (element.localName == 'drawing' ||
                  element.localName == 'pict' ||
                  element.localName == 'tbl')) ||
          (element.namespaceUri == OfficeNamespaces.m &&
              (element.localName == 'oMath' ||
                  element.localName == 'oMathPara'))) {
        return true;
      }
      return element.childElements.any(hasRichBlockContent);
    }

    if (hasRichBlockContent(leaf)) {
      _unsupportedControl(
        storyUri,
        'block control in a paragraph-only $storyKind story contains '
        'a drawing, table or equation',
      );
    }
    final control = WordContentControlIo.capture(source, package, storyUri);
    final content = _sdtContentReader(source)!;
    while (content.next()) {
      if (content.eventType != XmlEventType.startElement ||
          content.namespaceUri != OfficeNamespaces.w) {
        continue;
      }
      if (content.localName == 'sdt') {
        final nested = _readAuxiliaryControl(
          content,
          package,
          storyUri,
          storyKind,
        );
        nested.paragraph.contentControlWrappers.insert(0, control);
        return nested;
      }
      if (content.localName == 'p') {
        final paragraphId = WordCommentIo.normalizeParagraphId(
          content.getAttribute('paraId', namespaceUri: OfficeNamespaces.w14),
        );
        final paragraph = _readParagraph(content, package, storyUri)
          ..contentControlWrappers.add(control);
        return (paragraph: paragraph, paragraphId: paragraphId);
      }
    }
    throw StateError('Preflighted content control lost its paragraph');
  }

  List<WmlBlock> _readBlockContent(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final List<WmlBlock> blocks = <WmlBlock>[];
    if (reader.isEmptyElement) {
      return blocks;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      // Compatibility wrappers are hidden by the reader but retain source
      // depth. Each block reader consumes its entire subtree, so accepting the
      // selected child at any depth preserves that block without flattening it.
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (WordBookmarkIo.isMarker(reader)) {
        _blockMarker(reader);
      } else if (reader.localName == 'p' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _addParagraph(blocks, _readParagraph(reader, package, docUri));
        if (_pendingParagraphSectPr != null && !_liftSdtSectionBreak) {
          throw UnsupportedError(
            'A section break inside a content control cannot yet be imported safely',
          );
        }
      } else if (reader.localName == 'tbl' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.add(_readTable(reader, package, docUri));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.addAll(_readSdt(reader, package, docUri));
      } else if (reader.localName == 'altChunk' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.add(WordOpaqueIo.read(reader, package, docUri));
      } else if ((reader.localName == 'oMath' ||
              reader.localName == 'oMathPara') &&
          reader.namespaceUri == OfficeNamespaces.m) {
        final math = OmmlIo.readFrom(reader);
        if (math != null) blocks.add(WmlEquation(math: math));
      } else {
        blocks.add(WordOpaqueIo.read(reader, package, docUri));
      }
    }
    return blocks;
  }

  void _readInlineControl(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final source = XmlDocument.readElement(reader);
    bool containsBlockOnlyContent(XmlElement element) {
      if ((element.namespaceUri == OfficeNamespaces.w &&
              (element.localName == 'drawing' ||
                  element.localName == 'pict' ||
                  element.localName == 'p' ||
                  element.localName == 'tbl' ||
                  element.localName == 'tr' ||
                  element.localName == 'tc' ||
                  element.localName == 'sectPr')) ||
          (element.namespaceUri == OfficeNamespaces.m &&
              (element.localName == 'oMath' ||
                  element.localName == 'oMathPara'))) {
        return true;
      }
      return element.childElements.any(containsBlockOnlyContent);
    }

    if (containsBlockOnlyContent(source)) {
      _unsupportedControl(
        docUri,
        'inline control containing a drawing or equation',
      );
    }
    final control = WordContentControlIo.capture(source, package, docUri);
    paragraph.inlines.add(
      WmlContentControlBoundary(control: control, start: true),
    );
    final content = _sdtContentReader(source);
    if (content != null) {
      _readParagraphContent(content, package, docUri, paragraph);
    }
    paragraph.inlines.add(
      WmlContentControlBoundary(control: control, start: false),
    );
  }

  Never _unsupportedControl(String docUri, String context) {
    throw UnsupportedError(
      'Content control in $docUri: $context is not supported. '
      'Import stopped before changing the package to preserve its native structure.',
    );
  }

  WmlFrame _frameFromTag(String tag, List<WmlBlock> blocks) {
    final List<String> parts = tag.substring('qudsFrame:'.length).split(',');
    double numAt(int i, double fallback) =>
        i < parts.length ? double.tryParse(parts[i]) ?? fallback : fallback;
    final String anchorName = parts.length > 4 ? parts[4] : 'page';
    final String wrapName = parts.length > 5 ? parts[5] : 'none';
    String? colorAt(int i) {
      if (i >= parts.length || parts[i].isEmpty) {
        return null;
      }
      return parts[i];
    }

    return WmlFrame(
      x: numAt(0, 72),
      y: numAt(1, 72),
      width: numAt(2, 200),
      height: numAt(3, 120),
      anchor: anchorName == 'margin'
          ? WmlFrameAnchor.margin
          : WmlFrameAnchor.page,
      wrap: switch (wrapName) {
        'square' => WmlFrameWrap.square,
        'topBottom' => WmlFrameWrap.topBottom,
        _ => WmlFrameWrap.none,
      },
      fillColor: colorAt(6),
      strokeColor: colorAt(7),
      blocks: blocks,
    );
  }

  void _addParagraph(List<WmlBlock> blocks, WmlParagraph paragraph) {
    if (_drawingDepth == 0) {
      if (_blockMarkers.isNotEmpty) {
        paragraph.inlines.insertAll(0, _blockMarkers);
        _blockMarkers.clear();
      }
      _lastBlockParagraph = paragraph;
    }
    final bool mathOnly =
        paragraph.inlines.isEmpty && _pendingEquations.isNotEmpty;
    final bool drawingHost =
        paragraph.text.trim().isEmpty &&
        !paragraph.inlines.any(
          (inline) =>
              inline is WmlNoteMarker ||
              inline is WmlBookmarkBoundary ||
              inline is WmlContentControlBoundary ||
              inline is WmlFieldBoundary,
        ) &&
        (_pendingVisuals.isNotEmpty || _pendingFrames.isNotEmpty);
    if (!mathOnly && !drawingHost) {
      blocks.add(paragraph);
    }
    _flushPending(blocks);
  }

  void _blockMarker(XmlPullReader reader) {
    final WmlBookmarkBoundary marker = WordBookmarkIo.read(reader);
    final WmlParagraph? previous = _lastBlockParagraph;
    if (!marker.isStart && _blockMarkers.isEmpty && previous != null) {
      previous.inlines.add(marker);
    } else {
      _blockMarkers.add(marker);
    }
  }

  /// Close a block story: markers still queued (nothing followed them)
  /// close the last paragraph; a story without paragraphs drops them.
  void _endBlockStory() {
    if (_blockMarkers.isNotEmpty) {
      _lastBlockParagraph?.inlines.addAll(_blockMarkers);
      _blockMarkers.clear();
    }
    _lastBlockParagraph = null;
  }

  void _flushPending(List<WmlBlock> blocks) {
    if (_pendingFrames.isNotEmpty) {
      blocks.addAll(_pendingFrames);
      _pendingFrames.clear();
    }
    if (_pendingVisuals.isNotEmpty) {
      blocks.addAll(_pendingVisuals);
      _pendingVisuals.clear();
    }
    if (_pendingEquations.isNotEmpty) {
      blocks.addAll(_pendingEquations);
      _pendingEquations.clear();
    }
  }

  bool _takeDrawing(XmlPullReader reader, OpcPackage package, String docUri) {
    if (reader.localName != 'drawing') {
      return false;
    }
    // A text box's own paragraphs go through _addParagraph, which flushes
    // pending frames/visuals into the blocks being built. Without isolation
    // the frames already collected for the *host* paragraph were flushed
    // into the next text box's content: with n boxes anchored in one
    // paragraph, each box swallowed all earlier ones and export wrote
    // 2^n - 1 boxes (4,095 for twelve). Inner content gets fresh pending
    // lists; the host's are restored afterwards.
    final List<WmlFrame> outerFrames = List<WmlFrame>.of(_pendingFrames);
    final List<WmlVisual> outerVisuals = List<WmlVisual>.of(_pendingVisuals);
    final List<WmlEquation> outerEquations = List<WmlEquation>.of(
      _pendingEquations,
    );
    _pendingFrames.clear();
    _pendingVisuals.clear();
    _pendingEquations.clear();
    final WmlBlock? block;
    _drawingDepth++;

    try {
      block = WordDrawingIo.readBlock(
        reader,
        package,
        docUri,
        readParagraph: (XmlPullReader inner) =>
            _readParagraph(inner, package, docUri),
        readBlockContent: (XmlPullReader inner) =>
            _readBlockContent(inner, package, docUri),
      );
    } finally {
      _drawingDepth--;
      // Anything the inner content left pending belongs to the host too
      // (e.g. a picture inside a text-box paragraph that was not flushed).
      final List<WmlFrame> innerFrames = List<WmlFrame>.of(_pendingFrames);
      final List<WmlVisual> innerVisuals = List<WmlVisual>.of(_pendingVisuals);
      final List<WmlEquation> innerEquations = List<WmlEquation>.of(
        _pendingEquations,
      );
      _pendingFrames
        ..clear()
        ..addAll(outerFrames)
        ..addAll(innerFrames);
      _pendingVisuals
        ..clear()
        ..addAll(outerVisuals)
        ..addAll(innerVisuals);
      _pendingEquations
        ..clear()
        ..addAll(outerEquations)
        ..addAll(innerEquations);
    }
    if (block is WmlVisual) {
      _pendingVisuals.add(block);
    } else if (block is WmlFrame) {
      _pendingFrames.add(block);
    }
    return true;
  }

  WmlParagraph _readParagraph(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final WmlParagraph paragraph = WmlParagraph()
      ..properties.sourcePropertiesXml = '';
    final previousFrames = _pendingFrames.isEmpty
        ? null
        : (Set<WmlFrame>.identity()..addAll(_pendingFrames));
    _readParagraphContent(reader, package, docUri, paragraph);
    _settleFieldSpans(paragraph);
    _settleInlinePictures(paragraph);
    final change = _paragraphFormatChanges.remove(paragraph.properties);
    if (change != null) {
      _recordFormatting(
        paragraph,
        change,
        WmlRevisionKind.paragraphFormat,
        0,
        paragraph.text,
      );
    }
    for (final frame in _pendingFrames) {
      if (previousFrames?.contains(frame) ?? false) continue;
      frame.anchorParagraphProperties ??= paragraph.properties.copy()
        ..importedValues = WordPropertyIo.paragraphValues(paragraph.properties);
    }
    return paragraph;
  }

  void _readParagraphContent(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (reader.localName == 'pPr') {
        _readPPr(reader, paragraph.properties);
      } else if (reader.localName == 'r') {
        _readRunInlines(reader, package, docUri, paragraph);
      } else if (reader.namespaceUri == OfficeNamespaces.w &&
          const {
            'ins',
            'del',
            'moveFrom',
            'moveTo',
          }.contains(reader.localName)) {
        _readTracked(reader, package, docUri, paragraph);
      } else if (reader.localName == 'hyperlink') {
        _readHyperlink(reader, package, docUri, paragraph);
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _readInlineControl(reader, package, docUri, paragraph);
      } else if (reader.localName == 'fldSimple' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        paragraph.inlines.addAll(
          _readSimpleField(reader, package, docUri, paragraph),
        );
      } else if (reader.localName == 'commentRangeStart') {
        final int? id = int.tryParse(
          reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (id != null && !_openCommentIds.contains(id)) {
          _openCommentIds.add(id);
        }
      } else if (reader.localName == 'commentRangeEnd') {
        final int? id = int.tryParse(
          reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (id != null) {
          _openCommentIds.remove(id);
        }
      } else if ((reader.localName == 'bookmarkStart' ||
              reader.localName == 'bookmarkEnd') &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _readBookmark(reader, paragraph);
      } else if (reader.localName == 'br') {
        final String? type = reader.getAttribute(
          'type',
          namespaceUri: OfficeNamespaces.w,
        );
        paragraph.inlines.add(
          WmlBreak(
            type == 'page'
                ? WmlBreakType.page
                : type == 'column'
                ? WmlBreakType.column
                : WmlBreakType.textWrapping,
          ),
        );
        if (type == 'column') {
          paragraph.properties.columnBreakBefore = true;
        }
      } else if (reader.localName == 'object' ||
          reader.localName == 'drawing') {
        if (!_takeDrawing(reader, package, docUri)) {
          final WmlObject? obj = _readObject(reader, package, docUri);
          if (obj != null) {
            paragraph.inlines.add(obj);
          }
        }
      } else if (reader.localName == 'oMath' ||
          reader.localName == 'oMathPara') {
        final OmmlEquation? math = OmmlIo.readFrom(reader);
        if (math != null) {
          _pendingEquations.add(WmlEquation(math: math));
        }
      }
    }
  }

  List<WmlInline> _readSimpleField(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final XmlElement source = XmlDocument.readElement(reader);
    final String? instruction = source.getAttribute(
      'instr',
      namespaceUri: OfficeNamespaces.w,
    );
    final XmlPullReader inner = WordMarkupCompatibilityReader(
      XmlDocument(root: source).toXmlString(declaration: false),
    )..next();
    final int revisionCount = _document?.revisions.length ?? 0;
    // A rich fldSimple is still a field: its instruction belongs to the whole
    // cache, not to any one styled run. Keep Zotero containers (and simple
    // ancestors of them) as complex boundary packets. The containing paragraph
    // can still collapse an ordinary one-run packet after all nesting is known.
    final bool preserveZotero = _containsSimpleZoteroField(source);
    final WmlParagraph result;
    if (preserveZotero) {
      result = WmlParagraph()..properties.sourcePropertiesXml = '';
      // Do not settle the temporary cache paragraph: that would hide a nested
      // complex field in paragraph properties or move a sole picture outside
      // its enclosing citation. The real paragraph settles the complete packet.
      _readParagraphContent(inner, package, docUri, result);
    } else {
      result = _readParagraph(inner, package, docUri);
    }
    // A simple-field cache is parsed in a temporary paragraph. Its tracked
    // run still belongs to the containing paragraph and uses that offset.
    for (final WmlRevision revision
        in _document?.revisions.skip(revisionCount) ?? <WmlRevision>[]) {
      if (identical(revision.targetParagraph, result)) {
        revision
          ..targetParagraph = paragraph
          ..start += paragraph.text.length
          ..end += paragraph.text.length;
      }
    }
    if (preserveZotero && instruction != null) {
      final cache = <WmlInline>[];
      for (final inline in result.inlines) {
        if (inline is WmlRun && inline.fieldInstruction != null) {
          // A nested single-run field may have its own atomic representation.
          // Expand it inside the outer packet so inspection retains nesting and
          // cannot treat either citation as an independently editable cache.
          final code = inline.fieldInstruction!;
          final nestedSource = XmlElement(
            localName: 'fldSimple',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          );
          if (inline.fieldLocked) {
            nestedSource.setAttribute(
              'fldLock',
              '1',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            );
          }
          if (inline.fieldDirty != null) {
            nestedSource.setAttribute(
              'dirty',
              inline.fieldDirty! ? '1' : '0',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            );
          }
          inline
            ..fieldInstruction = null
            ..fieldLocked = false
            ..fieldDirty = null;
          cache.addAll(_simpleFieldPacket(nestedSource, code, [inline]));
        } else {
          cache.add(inline);
        }
      }
      return _simpleFieldPacket(source, instruction, cache);
    }
    final List<XmlElement> children = source.childElements.toList();
    bool isRun(XmlElement child) =>
        child.localName == 'r' && child.namespaceUri == OfficeNamespaces.w;
    bool isTrackedRun(XmlElement child) =>
        (child.localName == 'ins' || child.localName == 'del') &&
        child.namespaceUri == OfficeNamespaces.w &&
        child.childElements.length == 1 &&
        isRun(child.childElements.single);
    final bool singleRun =
        children.isEmpty ||
        (children.length == 1 &&
            (isRun(children.single) || isTrackedRun(children.single)));
    // Retain the native one-run field boundary. Arbitrary rich/nested fields
    // need a span model; do not turn their entire containing paragraph into a
    // field or duplicate one instruction onto each result run.
    if (instruction != null &&
        singleRun &&
        result.properties.fieldInstruction == null &&
        result.inlines.length <= 1 &&
        (result.inlines.isEmpty || result.inlines.single is WmlRun)) {
      final WmlRun run = result.inlines.isEmpty
          ? WmlRun()
          : result.inlines.single as WmlRun;
      if (!run.isAtomic) {
        final String? locked = source.getAttribute(
          'fldLock',
          namespaceUri: OfficeNamespaces.w,
        );
        final String? dirty = source.getAttribute(
          'dirty',
          namespaceUri: OfficeNamespaces.w,
        );
        bool enabled(String? value) =>
            value == '1' || value == 'true' || value == 'on';
        run
          ..fieldInstruction = instruction
          ..fieldLocked = enabled(locked)
          ..fieldDirty = dirty == null ? null : enabled(dirty);
        return <WmlInline>[run];
      }
    }
    return result.inlines;
  }

  static bool _containsSimpleZoteroField(XmlElement element) =>
      (element.localName == 'fldSimple' &&
          element.namespaceUri == OfficeNamespaces.w &&
          WordZotero.kindOfInstruction(
                element.getAttribute('instr', namespaceUri: OfficeNamespaces.w),
              ) !=
              null) ||
      element.childElements.any(_containsSimpleZoteroField);

  static List<WmlInline> _simpleFieldPacket(
    XmlElement source,
    String instruction,
    List<WmlInline> cache,
  ) {
    final begin =
        XmlElement(
          localName: 'fldChar',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
          // Both field forms share dirty/lock flags. Retain extension attributes
          // and their namespace declarations on the begin marker as opaque source
          // metadata; WordZotero refuses replacement when such attributes exist.
          attributes: [
            for (final attribute in source.attributes)
              if (!(attribute.localName == 'instr' &&
                  attribute.namespaceUri == OfficeNamespaces.w))
                attribute.copy(),
          ],
        )..setAttribute(
          'fldCharType',
          'begin',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
    if (!begin.attributes.any(
      (attribute) => attribute.qualifiedName == 'xmlns:w',
    )) {
      begin.attributes.add(
        XmlAttribute(
          localName: 'w',
          prefix: 'xmlns',
          value: OfficeNamespaces.w,
        ),
      );
    }
    return <WmlInline>[
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.begin,
        sourceXml: XmlDocument(root: begin).toXmlString(declaration: false),
      ),
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: instruction,
      ),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      ...cache,
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ];
  }

  void _readBookmark(XmlPullReader reader, WmlParagraph paragraph) {
    final marker = WordBookmarkIo.read(reader);
    final isStart = marker.isStart;
    final name = marker.name;
    paragraph.inlines.add(marker);
    if (isStart && name != null && paragraph.properties.bookmarkName == null) {
      paragraph.properties
        ..bookmarkName = name
        ..sourceBookmarkName = name;
    }
  }

  void _readRunInlines(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    if (reader.isEmptyElement) return;
    // Stage compound runs until their formatting revision has been recorded.
    List<WmlInline>? inlines;
    XmlElement? formattingChange;
    String? boundaryRunPropertiesXml;
    var hasOrdinaryRunIdentity = false;
    var hasNonTextContent = false;
    WmlRun? activeRun;
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final name = reader.localName;
      if (reader.depth == depth + 1) {
        final ordinary =
            reader.namespaceUri == OfficeNamespaces.w &&
            const {'rPr', 't', 'delText'}.contains(name);
        hasOrdinaryRunIdentity |= ordinary;
        hasNonTextContent |= !ordinary;
      }
      if (name == 'rPr' && boundaryRunPropertiesXml == null) {
        // A first rPr can supply the run's properties before allocating
        // defaults that would be discarded on a template cache hit.
        final properties = _readRunProperties(reader, activeRun?.properties);
        (activeRun ??= WmlRun(properties: properties.props)).properties =
            properties.props;
        formattingChange = properties.change;
        boundaryRunPropertiesXml = properties.sourceXml;
        continue;
      }
      final run = activeRun ??= (WmlRun()..properties.sourcePropertiesXml = '');
      if (name == 'rPr') {
        final properties = _readRPr(reader, run.properties);
        formattingChange = properties.change;
        boundaryRunPropertiesXml = properties.sourceXml;
      } else if (name == 't' || name == 'delText') {
        final String text = _elementText(reader);
        // A PAGE instruction elsewhere in this paragraph must not consume a
        // numeric citation cache or ordinary text. Suppress a cached page
        // number only after the complete paragraph is proven to be that field.
        run.text += text;
      } else if (reader.localName == 'footnoteReference' ||
          reader.localName == 'endnoteReference') {
        final int id =
            int.tryParse(
              reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
            ) ??
            1;
        final endnote = reader.localName == 'endnoteReference';
        final custom = const {'1', 'true', 'on'}.contains(
          reader.getAttribute(
            'customMarkFollows',
            namespaceUri: OfficeNamespaces.w,
          ),
        );
        // Keep the marker separate from adjacent native text, including a
        // custom symbol in the same w:r. The invisible custom reference still
        // owns one stable editor offset and the link to its note story.
        if (run.text.isNotEmpty) {
          (inlines ??= <WmlInline>[]).add(
            WmlRun(
              text: run.text,
              properties: run.properties.copy(),
              commentIds: List<int>.of(_openCommentIds),
            ),
          );
          run.text = '';
        }
        (inlines ??= <WmlInline>[]).add(
          WmlRun(
            text: custom ? '\uFFFC' : '$id',
            noteRefId: id,
            noteRefEndnote: endnote,
            noteRefCustomMark: custom,
            properties: run.properties.copy()
              ..vertAlign = WmlVertAlign.superscript,
            commentIds: List<int>.of(_openCommentIds),
          ),
        );
        paragraph.properties.noteId = id;
        paragraph.properties.endnoteRef = endnote;
      } else if (reader.localName == 'footnoteRef' ||
          reader.localName == 'endnoteRef') {
        if (run.text.isNotEmpty) {
          (inlines ??= <WmlInline>[]).add(
            WmlRun(
              text: run.text,
              properties: run.properties.copy(),
              commentIds: List<int>.of(_openCommentIds),
            ),
          );
          run.text = '';
        }
        final WmlRunProps markerProperties = run.properties.copy();
        markerProperties.importedValues = WordPropertyIo.runValues(
          markerProperties,
        );
        (inlines ??= <WmlInline>[]).add(
          WmlNoteMarker(
            endnote: reader.localName == 'endnoteRef',
            properties: markerProperties,
            runPropertiesXml: boundaryRunPropertiesXml,
          ),
        );
        if (_readingNote != null && !_noteMarkCaptured) {
          _readingNote!.referencePropertiesXml =
              run.properties.sourcePropertiesXml ?? '';
          _noteMarkCaptured = true;
        }
      } else if (reader.localName == 'instrText') {
        final String instr = _elementText(reader);
        paragraph.properties.fieldInstruction =
            '${paragraph.properties.fieldInstruction ?? ''}$instr';
        if (_isPageField(instr)) {
          paragraph.properties.pageNumberField = true;
        }
        _flushFieldText(inlines ??= <WmlInline>[], run);
        final boundary = WmlFieldBoundary(
          kind: WmlFieldBoundaryKind.instruction,
          text: instr,
          runPropertiesXml:
              boundaryRunPropertiesXml ?? run.properties.sourcePropertiesXml,
        );
        inlines.add(boundary);
        _noteFieldInstruction(boundary);
      } else if (reader.localName == 'fldChar') {
        final field = _readFieldChar(reader);
        final kind = field.kind;
        if (kind != null) {
          _flushFieldText(inlines ??= <WmlInline>[], run);
          final boundary = WmlFieldBoundary(
            kind: kind,
            sourceXml: field.xml,
            runPropertiesXml:
                boundaryRunPropertiesXml ?? run.properties.sourcePropertiesXml,
          );
          inlines.add(boundary);
          _noteFieldChar(boundary);
          switch (kind) {
            case WmlFieldBoundaryKind.begin:
              paragraph.properties.fieldBegin = true;
            case WmlFieldBoundaryKind.separate:
              paragraph.properties.fieldSeparate = true;
            case WmlFieldBoundaryKind.end:
              paragraph.properties.fieldEnd = true;
            case WmlFieldBoundaryKind.instruction:
              break;
          }
        }
      } else if (reader.localName == 'commentReference') {
        continue;
      } else if (reader.localName == 'sym' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        final WmlRun? symbol = _symbolRun(reader, run.properties);
        if (symbol != null) {
          if (run.text.isNotEmpty) {
            (inlines ??= <WmlInline>[]).add(
              WmlRun(
                text: run.text,
                properties: run.properties.copy(),
                commentIds: List<int>.of(_openCommentIds),
              ),
            );
            run.text = '';
          }
          (inlines ??= <WmlInline>[]).add(symbol);
        }
      } else if (reader.localName == 'softHyphen' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        run.text += '\u00ad';
      } else if (reader.localName == 'noBreakHyphen' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        run.text += '\u2011';
      } else if (reader.localName == 'tab') {
        run.text += '\t';
      } else if (reader.localName == 'br' || reader.localName == 'cr') {
        final String? type = reader.getAttribute(
          'type',
          namespaceUri: OfficeNamespaces.w,
        );
        if (type == 'page' || type == 'column') {
          if (run.text.isNotEmpty) {
            (inlines ??= <WmlInline>[]).add(
              WmlRun(
                text: run.text,
                properties: run.properties.copy(),
                commentIds: List<int>.of(_openCommentIds),
              ),
            );
            run.text = '';
          }
          (inlines ??= <WmlInline>[]).add(
            WmlBreak(type == 'page' ? WmlBreakType.page : WmlBreakType.column),
          );
        } else {
          run.text += '\n';
        }
      } else if (reader.localName == 'pict' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        if (run.text.isNotEmpty) {
          (inlines ??= <WmlInline>[]).add(
            WmlRun(
              text: run.text,
              properties: run.properties.copy(),
              commentIds: List<int>.of(_openCommentIds),
            ),
          );
          run.text = '';
        }
        (inlines ??= <WmlInline>[]).add(
          WmlOpaqueInline(
            content: WordOpaqueIo.read(reader, package, docUri),
            runPropertiesXml: run.properties.sourcePropertiesXml,
          ),
        );
      } else if (reader.localName == 'object' ||
          reader.localName == 'drawing' ||
          reader.localName == 'OLEObject') {
        if (run.text.isNotEmpty) {
          (inlines ??= <WmlInline>[]).add(
            WmlRun(text: run.text, properties: run.properties),
          );
          run.text = '';
        }
        final int pendingBefore = _pendingVisuals.length;
        if (!_takeDrawing(reader, package, docUri)) {
          final WmlObject? obj = _readObject(reader, package, docUri);
          if (obj != null) {
            (inlines ??= <WmlInline>[]).add(obj);
          }
        } else if (_pendingVisuals.length == pendingBefore + 1 &&
            _pendingVisuals.last.visual.kind == OfficeVisualKind.picture &&
            !_pendingVisuals.last.visual.isDiagram &&
            _pendingVisuals.last.visual.picture.wrap == PictureWrap.inline) {
          // An inline picture stays in its line of text (settled in
          // _settleInlinePictures once the paragraph is complete).
          (inlines ??= <WmlInline>[]).add(
            WmlRun(
              text: _inlinePictureChar,
              properties: run.properties.copy(),
              commentIds: List<int>.of(_openCommentIds),
              inlineVisual: _pendingVisuals.removeLast(),
            ),
          );
        }
      }
    }
    final run = activeRun;
    if (run == null) return;
    // An authored empty text/property packet still owns its insertion style.
    // Keep it through save/reopen, including an empty rPr inheriting a style.
    // Bare runs and structural-only field, note, drawing or comment markers
    // must not acquire an extra ordinary run beside their existing model node.
    final hasInlines = inlines?.isNotEmpty ?? false;
    final emptyOrdinaryRun =
        hasOrdinaryRunIdentity && !hasNonTextContent && !hasInlines;
    if (run.text.isNotEmpty ||
        run.noteRefId != null ||
        emptyOrdinaryRun ||
        formattingChange != null && !hasInlines) {
      run.commentIds.addAll(_openCommentIds);
      if (inlines == null && formattingChange == null) {
        paragraph.inlines.add(run);
        return;
      }
      (inlines ??= <WmlInline>[]).add(run);
    }
    if (inlines == null) return;
    // Field and note markers have no ordinary text range to own a revision.
    // Their complete rPr keeps their formatting history in the native marker.
    if (formattingChange != null &&
        (inlines.isEmpty ||
            !inlines.every(
              (inline) => inline is WmlFieldBoundary || inline is WmlNoteMarker,
            ))) {
      if (run.text.isEmpty && inlines.contains(run)) {
        run.properties.hasEmptyFormattingRevision = true;
      }
      final text = inlines.whereType<WmlRun>().map((r) => r.text).join();
      _recordFormatting(
        paragraph,
        formattingChange,
        WmlRevisionKind.runFormat,
        paragraph.text.length,
        text,
        emptyRun: text.isEmpty && inlines.contains(run) ? run : null,
      );
    }
    paragraph.inlines.addAll(inlines);
  }

  String _revisionXml(XmlElement element) {
    final node = element.copy();
    final namespaces = <String, String>{'w': OfficeNamespaces.w};
    void collect(XmlElement item) {
      if (item.prefix.isNotEmpty && item.namespaceUri.isNotEmpty) {
        namespaces[item.prefix] = item.namespaceUri;
      }
      for (final attribute in item.attributes) {
        if (attribute.prefix.isNotEmpty &&
            attribute.prefix != 'xmlns' &&
            attribute.prefix != 'xml' &&
            attribute.namespaceUri.isNotEmpty) {
          namespaces[attribute.prefix] = attribute.namespaceUri;
        }
      }
      for (final child in item.childElements) {
        collect(child);
      }
    }

    collect(node);
    for (final entry in namespaces.entries) {
      node.setAttribute(entry.key, entry.value, prefix: 'xmlns');
    }
    return XmlDocument(root: node).toXmlString(declaration: false);
  }

  void _recordFormatting(
    WmlParagraph paragraph,
    XmlElement change,
    WmlRevisionKind kind,
    int start,
    String text, {
    WmlRun? emptyRun,
  }) {
    final document = _document;
    if (document == null) return;
    final name = kind == WmlRevisionKind.runFormat ? 'rPr' : 'pPr';
    final previous = change.firstChild(name, namespaceUri: OfficeNamespaces.w);
    if (emptyRun != null) emptyRun.formattingAnchor = Object();
    final revision = WordRevisions.record(
      document,
      kind: kind,
      paragraphIndex: -1,
      paragraph: paragraph,
      preserveSourceRange: true,
      emptyFormattingAnchor: emptyRun?.formattingAnchor,
      start: start,
      end: start + text.length,
      text: text,
      author:
          change.getAttribute('author', namespaceUri: OfficeNamespaces.w) ??
          'CrispOffice',
      previousPropertiesXml: previous == null ? null : _revisionXml(previous),
      propertyChangeXml: _revisionXml(change),
    );
    revision.dateIso =
        change.getAttribute('date', namespaceUri: OfficeNamespaces.w) ?? '';
  }

  /// Reuse the native sparse property parser/cascade when rejecting formatting.
  /// The snapshot is the complete *direct* set, so omitted properties inherit.
  void restoreRevisionFormatting(WmlDocument document, WmlRevision revision) {
    final paragraph = WordRevisions.resolveParagraph(document, revision)!;
    final xml = revision.previousPropertiesXml!;
    if (revision.kind == WmlRevisionKind.paragraphFormat) {
      final previous = WmlParagraphProps();
      _readPPr(XmlPullReader(xml)..next(), previous);
      // A formatting change does not replace fields/bookmark/story metadata.
      final current = paragraph.properties;
      previous
        ..fieldInstruction = current.fieldInstruction
        ..fieldBegin = current.fieldBegin
        ..fieldSeparate = current.fieldSeparate
        ..fieldEnd = current.fieldEnd
        ..pageNumberField = current.pageNumberField
        ..listLabel = current.listLabel
        ..listRestart = current.listRestart
        ..columnBreakBefore = current.columnBreakBefore
        ..bookmarkName = current.bookmarkName
        ..sourceBookmarkName = current.sourceBookmarkName
        ..noteId = current.noteId
        ..endnoteRef = current.endnoteRef;
      paragraph.properties = previous;
    } else {
      WmlRunEdit.splitAt(paragraph, revision.end);
      WmlRunEdit.splitAt(paragraph, revision.start);
      var offset = 0;
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        final end = offset + run.text.length;
        if (offset >= revision.start &&
            end <= revision.end &&
            (revision.emptyFormattingAnchor == null ||
                identical(
                  revision.emptyFormattingAnchor,
                  run.formattingAnchor,
                ))) {
          final previous = WmlRunProps();
          _readRPr(XmlPullReader(xml)..next(), previous);
          run.properties = previous;
        }
        offset = end;
      }
    }
    _applyDocumentStyles(document);
  }

  void _readTracked(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final kind = switch (reader.localName) {
      'moveFrom' => WmlRevisionKind.moveFrom,
      'moveTo' => WmlRevisionKind.moveTo,
      'del' => WmlRevisionKind.delete,
      _ => WmlRevisionKind.insert,
    };
    final ranges = _moveRanges['$docUri:${reader.localName}'];
    final move = kind.isMove && ranges != null && ranges.isNotEmpty
        ? ranges.last
        : null;
    final String author =
        reader.getAttribute('author', namespaceUri: OfficeNamespaces.w) ??
        'CrispOffice';
    final String date =
        reader.getAttribute('date', namespaceUri: OfficeNamespaces.w) ?? '';
    final int start = paragraph.text.length;
    if (reader.isEmptyElement) {
      return;
    }
    // A revision can contain fields, controls, links and range markers just
    // like the surrounding paragraph. Reuse the same parser instead of
    // flattening or losing the metadata of less common run content.
    final ancestors = _revisionAncestors.putIfAbsent(paragraph, () => []);
    final nativeAncestors = List<Object>.unmodifiable(ancestors);
    final nativeWrapper = Object();
    ancestors.add(nativeWrapper);
    try {
      _readParagraphContent(reader, package, docUri, paragraph);
    } finally {
      ancestors.removeLast();
      if (ancestors.isEmpty) _revisionAncestors.remove(paragraph);
    }
    final WmlDocument? document = _document;
    if (document == null) {
      return;
    }
    final String text = paragraph.text.substring(start);
    if (text.isEmpty) {
      return;
    }
    final WmlRevision revision = WordRevisions.record(
      document,
      kind: kind,
      paragraphIndex: -1,
      paragraph: paragraph,
      preserveSourceRange: true,
      nativeWrapper: nativeWrapper,
      nativeAncestors: nativeAncestors,
      start: start,
      end: start + text.length,
      text: text,
      author: author,
      moveName: move?.start.getAttribute(
        'name',
        namespaceUri: OfficeNamespaces.w,
      ),
      moveStory: move == null ? null : docUri,
    );
    if (move != null) {
      if (move.revisions.isEmpty) {
        revision.moveStartXml = XmlDocument(
          root: move.start,
        ).toXmlString(declaration: false);
      }
      move.revisions.add(revision);
    }
    revision.dateIso = date;
  }

  void _readPPr(XmlPullReader reader, WmlParagraphProps props) {
    final namespaces = reader.inScopeNamespaces;
    final projected = reader is WordMarkupCompatibilityReader;
    final fragment = reader.readRawElement();
    final key = (namespaces, fragment, projected);
    final cacheable = fragment.length <= 2048;
    var sourceXml = cacheable ? _paragraphPropertyXml[key] : null;
    if (sourceXml == null) {
      final replay = projected
          ? WordMarkupCompatibilityReader(
              fragment,
              inheritedNamespaces: namespaces,
            )
          : XmlPullReader(fragment, inheritedNamespaces: namespaces);
      replay.next();
      final node = XmlDocument.readElement(replay);
      final change = node.firstChild(
        'pPrChange',
        namespaceUri: OfficeNamespaces.w,
      );
      if (change != null) {
        node.children.remove(change);
        _paragraphFormatChanges[props] = change;
      }
      sourceXml = XmlDocument(root: node).toXmlString(declaration: false);
      // Tracked formatting changes have their own XML owner and must be
      // captured for every occurrence.
      if (cacheable && change == null && _paragraphPropertyXml.length < 256) {
        _paragraphPropertyXml[key] = sourceXml;
      }
    }
    props.sourcePropertiesXml = sourceXml;
    // Parse into the current paragraph even on a hit. This also reads any
    // section boundary owned by this paragraph.
    _parsePPr(WordMarkupCompatibilityReader(sourceXml)..next(), props);
  }

  void _parsePPr(XmlPullReader reader, WmlParagraphProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    WmlIndent? logicalIndent;
    String? justification;
    var hasJustification = false;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if ((reader.localName == 'spacing' ||
              reader.localName == 'contextualSpacing' ||
              reader.localName == 'keepLines' ||
              reader.localName == 'keepNext' ||
              reader.localName == 'widowControl' ||
              reader.localName == 'ind' ||
              reader.localName == 'jc' ||
              reader.localName == 'pStyle' ||
              reader.localName == 'bidi' ||
              reader.localName == 'tabs' ||
              reader.localName == 'shd' ||
              reader.localName == 'suppressAutoHyphens') &&
          (reader.depth != depth + 1 ||
              (reader.namespaceUri != OfficeNamespaces.w &&
                  !(reader.namespaceUri.isEmpty && reader.prefix == 'w')))) {
        // Source extensions may use the same names, or contain a nested Word
        // lookalike. Only direct native paragraph properties affect layout.
        // The original pPr fragment remains available for sparse export.
        XmlDocument.readElement(reader);
        continue;
      }
      switch (reader.localName) {
        case 'pPrChange':
          XmlDocument.readElement(reader);
        case 'jc':
          props.explicitJustification = true;
          hasJustification = true;
          justification = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
        case 'suppressAutoHyphens':
          props.suppressAutoHyphens = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'rPr':
          final marker = WmlRunProps();
          _parseRPr(reader, marker);
          props.importedParagraphMark = marker;
          props.proofingLanguage = marker.proofingLanguage;
        case 'bidi':
          props.rightToLeft = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'spacing':
          final String? before = reader.getAttribute(
            'before',
            namespaceUri: OfficeNamespaces.w,
          );
          final String? after = reader.getAttribute(
            'after',
            namespaceUri: OfficeNamespaces.w,
          );
          final String? line = reader.getAttribute(
            'line',
            namespaceUri: OfficeNamespaces.w,
          );
          final String? rule = reader.getAttribute(
            'lineRule',
            namespaceUri: OfficeNamespaces.w,
          );
          if (before != null) {
            props.spacingBefore = _measurePoints(before);
            props.explicitSpacingBefore = true;
          }
          if (after != null) {
            props.spacingAfter = _measurePoints(after);
            props.explicitSpacingAfter = true;
          }
          if (line != null) {
            props.explicitLineSpacing = true;
            if (rule == 'exact' || rule == 'atLeast') {
              props.lineSpacing = _measurePoints(line);
              props.lineSpacingRule = rule == 'exact'
                  ? WmlLineSpacingRule.exact
                  : WmlLineSpacingRule.atLeast;
            } else {
              props.lineSpacing = _measureTwips(line) / 240.0;
              props.lineSpacingRule = WmlLineSpacingRule.auto;
            }
          }
        case 'ind':
          props.explicitIndent = true;
          logicalIndent = WmlIndent(
            left: _twipAttr(
              reader,
              'left',
              fallback: _twipAttr(reader, 'start'),
            ),
            right: _twipAttr(
              reader,
              'right',
              fallback: _twipAttr(reader, 'end'),
            ),
            firstLine: _twipAttr(reader, 'firstLine'),
            hanging: _twipAttr(reader, 'hanging'),
          );
        case 'keepLines':
          props.keepTogether = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'keepNext':
          props.keepWithNext = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'widowControl':
          props.widowControl = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'contextualSpacing':
          props.contextualSpacing = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'pageBreakBefore':
          props.pageBreakBefore = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'numPr':
          _readNumPr(reader, props);
        case 'shd':
          final fill = reader.getAttribute(
            'fill',
            namespaceUri: OfficeNamespaces.w,
          );
          // Automatic background is transparent in the solid-fill model. Its
          // explicit native packet remains in the sparse source, overriding
          // inherited shading without painting a literal non-RGB color.
          props.shadingFill = fill == 'auto' ? null : fill;
        case 'pBdr':
          _readParagraphBorders(reader, props);
        case 'framePr':
          final String? lines = reader.getAttribute(
            'lines',
            namespaceUri: OfficeNamespaces.w,
          );
          if (reader.getAttribute(
                    'dropCap',
                    namespaceUri: OfficeNamespaces.w,
                  ) !=
                  null &&
              lines != null) {
            props.dropCapLines = int.tryParse(lines) ?? 3;
          }
        case 'tabs':
          _readTabs(reader, props);
        case 'pStyle':
          props.styleId = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          props.headingLevel ??= WordToc.headingLevelFromStyle(props.styleId);
        case 'outlineLvl':
          final String? raw = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          if (raw != null) {
            final int? outline = int.tryParse(raw);
            if (outline != null && outline >= 0 && outline <= 8) {
              props.headingLevel = outline + 1;
              props.styleId ??= 'Heading${outline + 1}';
            }
          }
        case 'sectPr':
          final OpcPackage? package = _package;
          final String? docUri = _docUri;
          if (package != null && docUri != null) {
            _pendingParagraphSectPr = WmlSection();
            _readSectPr(reader, _pendingParagraphSectPr!, package, docUri);
          }
      }
    }
    // OOXML start/end, including the transitional left/right aliases, are
    // relative to the effective paragraph direction. Resolve after the whole
    // pPr: a direct bidi or a late style layer can follow jc/ind in the XML.
    if (logicalIndent != null) {
      props.indent = _physicalIndent(logicalIndent, props.rightToLeft == true);
    }
    if (hasJustification) {
      props.justification = _jc(
        justification,
        rightToLeft: props.rightToLeft == true,
      );
    }
  }

  WmlSection _flushParagraphSectPr(WmlDocument document, WmlSection section) {
    final WmlSection? pending = _pendingParagraphSectPr;
    if (pending == null) {
      return section;
    }
    _pendingParagraphSectPr = null;
    section.pageSize = pending.pageSize;
    section.margins = pending.margins;
    section.columnCount = pending.columnCount;
    section.columnSpace = pending.columnSpace;
    section.columnSep = pending.columnSep;
    section.breakKind = pending.breakKind;
    section.differentFirstPage = pending.differentFirstPage;
    section.lineNumbers = pending.lineNumbers;
    section.sourceProperties = pending.sourceProperties;
    section.header.addAll(pending.header);
    section.footer.addAll(pending.footer);
    section.firstHeader.addAll(pending.firstHeader);
    section.firstFooter.addAll(pending.firstFooter);
    section.evenHeader.addAll(pending.evenHeader);
    section.evenFooter.addAll(pending.evenFooter);
    section.headerVisuals.addAll(pending.headerVisuals);
    section.footerVisuals.addAll(pending.footerVisuals);
    section.firstHeaderVisuals.addAll(pending.firstHeaderVisuals);
    section.firstFooterVisuals.addAll(pending.firstFooterVisuals);
    section.evenHeaderVisuals.addAll(pending.evenHeaderVisuals);
    section.evenFooterVisuals.addAll(pending.evenFooterVisuals);
    section.preservedStories.addAll(pending.preservedStories);
    document.sections.add(section);
    return WmlSection();
  }

  void _readHyperlink(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final WmlHyperlink? link = _hyperlinkFrom(reader, package, docUri);
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final int firstInline = paragraph.inlines.length;
      if (reader.localName == 'r') {
        _readRunInlines(reader, package, docUri, paragraph);
      } else if (reader.namespaceUri == OfficeNamespaces.w &&
          const {
            'ins',
            'del',
            'moveFrom',
            'moveTo',
          }.contains(reader.localName)) {
        _readTracked(reader, package, docUri, paragraph);
      } else if (reader.localName == 'fldSimple' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        paragraph.inlines.addAll(
          _readSimpleField(reader, package, docUri, paragraph),
        );
      } else if (reader.localName == 'hyperlink') {
        _readHyperlink(reader, package, docUri, paragraph);
      } else if ((reader.localName == 'bookmarkStart' ||
              reader.localName == 'bookmarkEnd') &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _readBookmark(reader, paragraph);
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _readInlineControl(reader, package, docUri, paragraph);
      }
      for (final WmlInline inline in paragraph.inlines.skip(firstInline)) {
        if (inline is WmlRun) {
          inline.hyperlink ??= link;
          if (link != null && inline.properties.color == '000000') {
            WordLink.applyLook(inline);
          }
        }
      }
    }
  }

  WmlHyperlink? _hyperlinkFrom(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final String? anchor = reader.getAttribute(
      'anchor',
      namespaceUri: OfficeNamespaces.w,
    );
    if (anchor != null && anchor.isNotEmpty) {
      return WmlHyperlink(anchor: anchor);
    }
    final String? rid = reader.getAttribute(
      'id',
      namespaceUri: OfficeNamespaces.r,
    );
    if (rid == null || rid.isEmpty) {
      return null;
    }
    final PackageRelationship? rel = package.relationshipsFor(docUri).byId(rid);
    if (rel == null || rel.target.isEmpty) {
      return null;
    }
    if (rel.targetMode == RelationshipTargetMode.external) {
      final String scheme =
          Uri.tryParse(rel.target)?.scheme.toLowerCase() ?? '';
      final bool drivePath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(rel.target);
      if (scheme.isNotEmpty && scheme != 'file' && !drivePath) {
        return WmlHyperlink(url: rel.target);
      }
      // Relationship targets are file/URI destinations, not bookmark names.
      // In particular, an extensionless relative file must not become w:anchor.
      return WmlHyperlink(file: rel.target);
    }
    return WmlHyperlink.fromTarget(rel.target);
  }

  void _collapseTocFields(WmlDocument document) {
    void collapse(List<WmlBlock> blocks) {
      for (final block in blocks) {
        for (final children in WordTree.childLists(block)) {
          collapse(children);
        }
      }
      // Copy the block list only once a TOC replaces part of it.
      List<WmlBlock>? collapsed;
      WmlToc? open;
      for (var index = 0; index < blocks.length; index++) {
        final block = blocks[index];
        if (block is! WmlParagraph) {
          if (open != null) {
            collapsed!.add(open);
            open = null;
          }
          collapsed?.add(block);
          continue;
        }
        final bool tocInstr = WordToc.isTocInstruction(
          block.properties.fieldInstruction,
        );
        final bool tocStyle =
            WordToc.tocLevelFromStyle(block.properties.styleId) != null;
        final bool tocHeading = WordToc.isTocHeadingStyle(
          block.properties.styleId,
        );
        final bool stillToc =
            tocInstr ||
            tocStyle ||
            tocHeading ||
            block.properties.fieldBegin ||
            block.properties.fieldSeparate ||
            block.properties.fieldEnd;
        if (open == null && (tocInstr || tocStyle || tocHeading)) {
          final output = collapsed ??= blocks.sublist(0, index);
          final (int min, int max) = WordToc.rangeFromInstruction(
            block.properties.fieldInstruction,
          );
          open = WmlToc(minLevel: min, maxLevel: max);
          WordToc.applyPageNumberInstruction(
            open,
            block.properties.fieldInstruction,
          );
          WordToc.absorbNativeResult(open, block);
          if (block.properties.fieldEnd) {
            output.add(open);
            open = null;
          }
          continue;
        }
        if (open != null && stillToc) {
          if (tocInstr) {
            final (int min, int max) = WordToc.rangeFromInstruction(
              block.properties.fieldInstruction,
            );
            open.minLevel = min;
            open.maxLevel = max;
            WordToc.applyPageNumberInstruction(
              open,
              block.properties.fieldInstruction,
            );
          }
          WordToc.absorbNativeResult(open, block);
          if (block.properties.fieldEnd) {
            collapsed!.add(open);
            open = null;
          }
          continue;
        }
        if (open != null) {
          collapsed!.add(open);
          open = null;
        }
        collapsed?.add(block);
      }
      if (open != null) {
        collapsed!.add(open);
      }
      if (collapsed == null) return;
      blocks
        ..clear()
        ..addAll(collapsed);
    }

    for (final section in document.sections) {
      collapse(section.blocks);
    }
  }

  void _readNumPr(XmlPullReader reader, WmlParagraphProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final String? val = reader.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      if (val == null) {
        continue;
      }
      if (reader.localName == 'ilvl') {
        props.ilvl = int.tryParse(val) ?? 0;
      } else if (reader.localName == 'numId') {
        final int? id = int.tryParse(val);
        props.numId = id == 0 ? null : id;
        props.numberingSuppressed = id == 0;
      }
    }
  }

  void _readTabs(XmlPullReader reader, WmlParagraphProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.depth != depth + 1 ||
          reader.localName != 'tab' ||
          (reader.namespaceUri != OfficeNamespaces.w &&
              !(reader.namespaceUri.isEmpty && reader.prefix == 'w'))) {
        XmlDocument.readElement(reader);
        continue;
      }
      final String? pos = reader.getAttribute(
        'pos',
        namespaceUri: OfficeNamespaces.w,
      );
      final String? val = reader.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      final String? leader = reader.getAttribute(
        'leader',
        namespaceUri: OfficeNamespaces.w,
      );
      final position = pos == null ? 0.0 : _measurePoints(pos);
      // Tabs are cumulative through the style cascade. A later stop owns
      // only the same position; a clear or bar removes a prior text stop.
      props.tabs.removeWhere((tab) => tab.position == position);
      if (val == 'clear') continue;
      // A bar stop is a decoration, not a text-positioning tab stop.
      if (val == 'bar') continue;
      props.tabs.add(
        WmlTabStop(
          position: position,
          alignment: switch (val) {
            'center' => WmlTabAlignment.center,
            'right' => WmlTabAlignment.right,
            'decimal' => WmlTabAlignment.decimal,
            _ => WmlTabAlignment.left,
          },
          leader: switch (leader) {
            'dot' => WmlTabLeader.dot,
            'hyphen' => WmlTabLeader.hyphen,
            'underscore' => WmlTabLeader.underscore,
            _ => WmlTabLeader.none,
          },
        ),
      );
    }
    props.tabs.sort((a, b) => a.position.compareTo(b.position));
  }

  /// `w:sym`: one character of a symbol font (Symbol, Wingdings, …) —
  /// bullets, check marks, arrows. It used to be skipped, losing the glyph.
  /// It becomes its own run whose text is the stored character code (Word
  /// keeps these in the private-use area, F000–F0FF) with the symbol font as
  /// *direct* formatting in the run's source properties, so the style
  /// cascade keeps it and export writes `w:t` + `w:rFonts`, which Word
  /// renders identically to the original `w:sym`.
  WmlRun? _symbolRun(XmlPullReader reader, WmlRunProps base) {
    final String? font = reader.getAttribute(
      'font',
      namespaceUri: OfficeNamespaces.w,
    );
    final int? code = int.tryParse(
      reader.getAttribute('char', namespaceUri: OfficeNamespaces.w) ?? '',
      radix: 16,
    );
    if (code == null || code <= 0 || code > 0x10FFFF) return null;
    if (code >= 0xD800 && code <= 0xDFFF) return null;
    final WmlRunProps props = base.copy();
    if (font != null && font.isNotEmpty) {
      final XmlElement source = WordPropertyIo.parse(
        base.sourcePropertiesXml,
        'rPr',
      );
      source.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.localName == 'rFonts' &&
            node.namespaceUri == OfficeNamespaces.w,
      );
      XmlAttribute attr(String name) => XmlAttribute(
        localName: name,
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
        value: font,
      );
      // CT_RPr order: rStyle, then rFonts.
      final int at =
          source.children.indexWhere(
            (node) => node is XmlElement && node.localName == 'rStyle',
          ) +
          1;
      source.children.insert(
        at,
        XmlElement(
          localName: 'rFonts',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
          attributes: [attr('ascii'), attr('hAnsi'), attr('cs')],
        ),
      );
      props
        ..sourcePropertiesXml = XmlDocument(
          root: source,
        ).toXmlString(declaration: false)
        ..asciiFont = font
        ..csFont = font;
    }
    return WmlRun(
      text: String.fromCharCode(code),
      properties: props,
      commentIds: List<int>.of(_openCommentIds),
    );
  }

  // Ordinary field markers repeat in long bibliographies, reference lists,
  // and TOCs. Share the immutable XML only within the same namespace scope.
  Map<String, String>? _fieldCharNamespaces;
  final _emptyFieldChars = <String, _ImportedFieldChar>{};
  final _fieldSourceElements = <String, XmlElement>{};
  static const _fieldCacheLimit = 64;

  _ImportedFieldChar _readFieldChar(XmlPullReader reader) {
    if (!reader.isEmptyElement) {
      return _parseFieldChar(reader);
    }
    final namespaces = reader.inScopeNamespaces;
    if (!identical(namespaces, _fieldCharNamespaces)) {
      _fieldCharNamespaces = namespaces;
      _emptyFieldChars.clear();
    }
    final fragment = reader.readRawElement();
    final cacheable = fragment.length <= 1024;
    final cached = cacheable ? _emptyFieldChars[fragment] : null;
    if (cached != null) return cached;
    final field = _parseFieldChar(
      XmlPullReader(fragment, inheritedNamespaces: namespaces)..next(),
    );
    if (cacheable && _emptyFieldChars.length < _fieldCacheLimit) {
      _emptyFieldChars[fragment] = field;
    }
    return field;
  }

  static _ImportedFieldChar _parseFieldChar(XmlPullReader reader) {
    final node = XmlDocument.readElement(reader);
    final kind = switch (node.getAttribute(
      'fldCharType',
      namespaceUri: OfficeNamespaces.w,
    )) {
      'begin' => WmlFieldBoundaryKind.begin,
      'separate' => WmlFieldBoundaryKind.separate,
      'end' => WmlFieldBoundaryKind.end,
      _ => null,
    };
    return (
      kind: kind,
      xml: kind == null
          ? null
          : XmlDocument(root: node).toXmlString(declaration: false),
    );
  }

  XmlElement? _fieldSourceElement(String xml) {
    // Both field guards inspect the same normalized XML without mutating it.
    final cacheable = xml.length <= 4096;
    final cached = cacheable ? _fieldSourceElements[xml] : null;
    if (cached != null) return cached;
    final root = XmlDocument.parse(xml).root;
    if (root != null && cacheable) {
      if (_fieldSourceElements.length >= _fieldCacheLimit) {
        _fieldSourceElements.remove(_fieldSourceElements.keys.first);
      }
      _fieldSourceElements[xml] = root;
    }
    return root;
  }

  // -- complex-field spans --------------------------------------------------
  // Open fields across paragraphs (a TOC spans many). Each entry is the begin
  // boundary plus whether its instruction marked it as a TOC.
  final List<(WmlFieldBoundary, bool)> _openFields = [];
  // The value distinguishes the TOC wrapper from fields inside its cache.
  final Map<WmlFieldBoundary, bool> _tocBoundaries = Map.identity();

  void _flushFieldText(List<WmlInline> inlines, WmlRun run) {
    if (run.text.isEmpty) return;
    inlines.add(
      WmlRun(
        text: run.text,
        properties: run.properties.copy(),
        commentIds: List<int>.of(_openCommentIds),
      ),
    );
    run.text = '';
  }

  bool get _insideToc => _openFields.any((entry) => entry.$2);

  void _noteTocBoundary(WmlFieldBoundary boundary) {
    if (_insideToc) _tocBoundaries[boundary] = _openFields.last.$2;
  }

  void _noteFieldChar(WmlFieldBoundary boundary) {
    switch (boundary.kind) {
      case WmlFieldBoundaryKind.begin:
        _openFields.add((boundary, false));
        _noteTocBoundary(boundary);
      case WmlFieldBoundaryKind.separate:
        _noteTocBoundary(boundary);
      case WmlFieldBoundaryKind.end:
        _noteTocBoundary(boundary);
        if (_openFields.isNotEmpty) _openFields.removeLast();
      case WmlFieldBoundaryKind.instruction:
        break;
    }
  }

  void _noteFieldInstruction(WmlFieldBoundary boundary) {
    if (_openFields.isNotEmpty) {
      final (begin, toc) = _openFields.last;
      if (!toc && WordToc.isTocInstruction(boundary.text)) {
        _openFields[_openFields.length - 1] = (begin, true);
        _tocBoundaries[begin] = true;
      }
    }
    _noteTocBoundary(boundary);
  }

  /// Decide, once a paragraph is complete, how its fields are represented.
  void _settleFieldSpans(WmlParagraph paragraph) {
    List<WmlFieldBoundary>? boundaries;
    for (final inline in paragraph.inlines) {
      if (inline is WmlFieldBoundary) {
        (boundaries ??= <WmlFieldBoundary>[]).add(inline);
      }
    }
    if (boundaries == null) return;
    if (_collapseZoteroFields(paragraph)) {
      boundaries = paragraph.inlines.whereType<WmlFieldBoundary>().toList();
      if (boundaries.isEmpty) {
        _clearParagraphField(paragraph);
        return;
      }
    }
    bool strip() {
      paragraph.inlines.removeWhere((inline) => inline is WmlFieldBoundary);
      return true;
    }

    // Only the TOC wrapper spans paragraphs. Nested PAGEREF fields keep
    // their own inline boundaries and must not close the wrapper.
    if (boundaries.every(_tocBoundaries.containsKey)) {
      final wrapper = boundaries.where((b) => _tocBoundaries[b]!).toList();
      final instruction = wrapper
          .where((b) => b.kind == WmlFieldBoundaryKind.instruction)
          .map((b) => b.text)
          .join();
      _clearParagraphField(paragraph);
      paragraph.properties
        ..fieldInstruction = instruction.isEmpty ? null : instruction
        ..fieldBegin = wrapper.any((b) => b.kind == WmlFieldBoundaryKind.begin)
        ..fieldSeparate = wrapper.any(
          (b) => b.kind == WmlFieldBoundaryKind.separate,
        )
        ..fieldEnd = wrapper.any((b) => b.kind == WmlFieldBoundaryKind.end);
      paragraph.inlines.removeWhere(
        (inline) =>
            inline is WmlFieldBoundary && _tocBoundaries[inline] == true,
      );
      return;
    }
    // Exactly one top-level field that wraps all of the paragraph's text,
    // no nesting and no form-field data: the paragraph model is exact.
    final kinds = boundaries.map((b) => b.kind).toList();
    final nested = kinds.where((k) => k == WmlFieldBoundaryKind.begin).length;
    // Opaque pictures, objects and range markers outside the field must not
    // be pulled into its result by the whole-paragraph compatibility model.
    final firstContent = paragraph.inlines.indexWhere(
      (inline) => inline is! WmlFieldBoundary,
    );
    final lastContent = paragraph.inlines.lastIndexWhere(
      (inline) => inline is! WmlFieldBoundary,
    );
    final begin = paragraph.inlines.indexOf(boundaries.first);
    final end = paragraph.inlines.indexOf(boundaries.last);
    final simple =
        nested == 1 &&
        kinds.first == WmlFieldBoundaryKind.begin &&
        kinds.last == WmlFieldBoundaryKind.end &&
        kinds.where((k) => k == WmlFieldBoundaryKind.end).length == 1 &&
        !(boundaries.first.sourceXml ?? '').contains('ffData') &&
        (firstContent < 0 || begin < firstContent) &&
        (lastContent < 0 || end > lastContent) &&
        (paragraph.properties.fieldInstruction ?? '').trim().isNotEmpty &&
        _plainParagraphFieldPacket(paragraph.inlines, begin, end);
    if (simple &&
        WordZotero.kindOfInstruction(paragraph.properties.fieldInstruction) ==
            null) {
      final page = _isPageField(paragraph.properties.fieldInstruction!);
      if (page &&
          !WordFields.isPlainPageInstruction(
            paragraph.properties.fieldInstruction!,
          )) {
        // The paragraph PAGE model regenerates an ordinary number. Preserve
        // unsupported format switches and their caches as native boundaries
        // before the ordinary numeric-cache suppression below can erase them.
        _clearParagraphField(paragraph);
        return;
      }
      paragraph.properties.pageNumberField = page;
      if (page) {
        if (_document?.revisions.any(
              (revision) =>
                  revision.accepted == null &&
                  identical(revision.targetParagraph, paragraph),
            ) ==
            true) {
          // A tracked cached result owns real text offsets. Keep its complete
          // field span until that revision is resolved instead of deleting the
          // text underneath its revision range.
          _clearParagraphField(paragraph);
          return;
        }
        for (final run in paragraph.inlines.whereType<WmlRun>()) {
          if (_cachedPageResult.hasMatch(run.text)) run.text = '';
        }
      }
      strip();
      return;
    }
    // Inexact for the paragraph model: keep the spans and drop the
    // paragraph-level reading, which would otherwise wrap all text.
    _clearParagraphField(paragraph);
  }

  bool _plainParagraphFieldPacket(List<WmlInline> inlines, int begin, int end) {
    var instructed = false;
    var separated = false;
    for (var index = begin; index <= end; index++) {
      final inline = inlines[index];
      if (inline is! WmlFieldBoundary) {
        if (!separated) return false;
        continue;
      }
      if (!_plainParagraphFieldBoundary(inline)) return false;
      if (inline.kind == WmlFieldBoundaryKind.instruction) {
        if (separated) return false;
        instructed = true;
      } else if (inline.kind == WmlFieldBoundaryKind.separate) {
        if (!instructed || separated) return false;
        separated = true;
      }
    }
    return separated;
  }

  bool _plainParagraphFieldBoundary(WmlFieldBoundary boundary) {
    // Paragraph properties cannot represent a locked field, formatted code
    // run, form state or foreign boundary metadata. Keeping the packet also
    // keeps its authored cache and permits native serialization to retain it.
    if (boundary.runPropertiesXml?.trim().isNotEmpty == true) return false;
    final source = boundary.sourceXml;
    if (source == null) return true;
    if (boundary.kind == WmlFieldBoundaryKind.instruction) return false;
    final element = _fieldSourceElement(source);
    if (element == null ||
        element.localName != 'fldChar' ||
        element.namespaceUri != OfficeNamespaces.w ||
        element.children.isNotEmpty ||
        element.getAttribute('fldCharType', namespaceUri: OfficeNamespaces.w) !=
            boundary.kind.name) {
      return false;
    }
    final seen = <String>{};
    for (final attribute in element.attributes) {
      if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
        continue;
      }
      final name = attribute.localName;
      final value = attribute.value;
      if (attribute.namespaceUri != OfficeNamespaces.w ||
          !seen.add(name) ||
          !{'fldCharType', 'fldLock', 'dirty'}.contains(name)) {
        return false;
      }
      if (name == 'fldLock' && !{'0', 'false', 'off'}.contains(value)) {
        return false;
      }
      if (name == 'dirty' &&
          !{'0', 'false', 'off', '1', 'true', 'on'}.contains(value)) {
        return false;
      }
    }
    return true;
  }

  void _clearParagraphField(WmlParagraph paragraph) => paragraph.properties
    ..fieldInstruction = null
    ..fieldBegin = false
    ..fieldSeparate = false
    ..fieldEnd = false
    ..pageNumberField = false;

  /// A Zotero field with exactly one ordinary cached run has an exact atomic
  /// representation. Rich, nested, malformed, or cross-paragraph fields keep
  /// their original boundary packets instead of flattening their formatting.
  bool _collapseZoteroFields(WmlParagraph paragraph) {
    List<({int start, int end, WmlRun run})>? replacements;
    var depth = 0;
    var start = -1;
    var nested = false;
    for (var index = 0; index < paragraph.inlines.length; index++) {
      final inline = paragraph.inlines[index];
      if (inline is! WmlFieldBoundary) continue;
      if (inline.kind == WmlFieldBoundaryKind.begin) {
        if (depth == 0) {
          start = index;
          nested = false;
        } else {
          nested = true;
        }
        depth++;
      } else if (inline.kind == WmlFieldBoundaryKind.end && depth > 0) {
        depth--;
        if (depth != 0 || nested || start < 0) continue;
        final packet = paragraph.inlines.sublist(start, index + 1);
        final instruction = StringBuffer();
        WmlRun? cache;
        var separated = false;
        var valid = true;
        bool locked = false;
        bool? dirty;
        for (final member in packet) {
          if (member is WmlFieldBoundary) {
            // Code-run properties and foreign field attributes are opaque
            // source metadata. Keep their boundary packet if atomizing would
            // discard them, even though the displayed cache is a single run.
            if (member.runPropertiesXml?.trim().isNotEmpty == true) {
              valid = false;
            }
            if (member.kind == WmlFieldBoundaryKind.instruction) {
              if (separated) valid = false;
              instruction.write(member.text);
            } else {
              if (member.kind == WmlFieldBoundaryKind.separate) {
                if (separated) valid = false;
                separated = true;
              }
              final source = member.sourceXml == null
                  ? null
                  : _fieldSourceElement(member.sourceXml!);
              if (source != null) {
                if (source.children.isNotEmpty ||
                    source.attributes.any(
                      (a) =>
                          a.prefix != 'xmlns' &&
                          a.qualifiedName != 'xmlns' &&
                          (a.namespaceUri != OfficeNamespaces.w ||
                              !<String>{
                                'fldCharType',
                                'fldLock',
                                'dirty',
                              }.contains(a.localName)),
                    )) {
                  valid = false;
                }
                if (member.kind == WmlFieldBoundaryKind.begin) {
                  bool enabled(String? value) =>
                      value == '1' || value == 'true' || value == 'on';
                  locked = enabled(
                    source.getAttribute(
                      'fldLock',
                      namespaceUri: OfficeNamespaces.w,
                    ),
                  );
                  final marker = source.getAttribute(
                    'dirty',
                    namespaceUri: OfficeNamespaces.w,
                  );
                  dirty = marker == null ? null : enabled(marker);
                }
              }
            }
          } else if (member is WmlRun &&
              separated &&
              cache == null &&
              member.fieldInstruction == null &&
              member.noteRefId == null &&
              member.inlineVisual == null &&
              member.hyperlink == null) {
            cache = member;
          } else {
            valid = false;
          }
        }
        final code = instruction.toString();
        if (!valid ||
            cache == null ||
            !separated ||
            WordZotero.metadataOf(code) == null) {
          continue;
        }
        cache
          ..fieldInstruction = code
          ..fieldLocked = locked
          ..fieldDirty = dirty;
        (replacements ??= []).add((
          start: start,
          end: index + 1,
          run: cache,
        ));
      }
    }
    if (replacements == null) return false;
    for (final replacement in replacements.reversed) {
      paragraph.inlines.replaceRange(
        replacement.start,
        replacement.end,
        <WmlInline>[replacement.run],
      );
    }
    return true;
  }

  static const String _inlinePictureChar = '\uFFFC';

  /// Keep the legacy block representation only for bare picture paragraphs.
  /// Moving an authored run out of its paragraph discards its hyperlink,
  /// formatting, list/heading ownership, and its one-character editor offset.
  /// Native inline runs written by this suite include paragraph/run properties;
  /// the separate block-picture writer deliberately emits neither.
  void _settleInlinePictures(WmlParagraph paragraph) {
    final inlines = paragraph.inlines;
    if (inlines.isEmpty ||
        (paragraph.properties.sourcePropertiesXml?.isNotEmpty ?? false) ||
        paragraph.contentControlWrappers.isNotEmpty) {
      return;
    }
    for (final inline in inlines) {
      if (inline is! WmlRun ||
          inline.inlineVisual == null ||
          inline.text != _inlinePictureChar ||
          inline.hyperlink != null ||
          inline.commentIds.isNotEmpty ||
          inline.fieldInstruction != null ||
          inline.noteRefId != null ||
          (inline.properties.sourcePropertiesXml?.isNotEmpty ?? false)) {
        return;
      }
    }
    if (_document?.revisions.any(
          (revision) => identical(revision.targetParagraph, paragraph),
        ) ??
        false) {
      return;
    }
    for (final inline in inlines) {
      _pendingVisuals.add((inline as WmlRun).inlineVisual!);
    }
    inlines.clear();
  }

  ({WmlRunProps props, XmlElement? change, String sourceXml})
  _readRunProperties(XmlPullReader reader, WmlRunProps? initial) {
    final namespaces = reader.inScopeNamespaces;
    final projected = reader is WordMarkupCompatibilityReader;
    final fragment = reader.readRawElement();
    final cacheable = fragment.length <= 2048;
    final key = (namespaces, fragment, projected);
    // Duplicate rPr blocks are common in native Word documents. Cache only
    // the private parsed template, never a run's editable property object.
    final cached = cacheable ? _runPropertyCache[key] : null;
    if (cached != null) {
      final copy = cached.props.copy();
      if (cached.notBold) _notBold.add(copy);
      if (cached.notItalic) _notItalic.add(copy);
      return (props: copy, change: null, sourceXml: cached.xml);
    }
    final replay = projected
        ? WordMarkupCompatibilityReader(
            fragment,
            inheritedNamespaces: namespaces,
          )
        : XmlPullReader(fragment, inheritedNamespaces: namespaces);
    replay.next();
    final props = initial ?? WmlRunProps();
    final result = _readRPr(replay, props);
    if (cacheable && result.change == null && _runPropertyCache.length < 256) {
      _runPropertyCache[key] = (
        props: props.copy(),
        xml: result.sourceXml,
        notBold: _notBold.contains(props),
        notItalic: _notItalic.contains(props),
      );
    }
    return (props: props, change: result.change, sourceXml: result.sourceXml);
  }

  ({XmlElement? change, String sourceXml}) _readRPr(
    XmlPullReader reader,
    WmlRunProps props,
  ) {
    final XmlElement node = XmlDocument.readElement(reader);
    final sourceXml = XmlDocument(root: node).toXmlString(declaration: false);
    final change = node.firstChild(
      'rPrChange',
      namespaceUri: OfficeNamespaces.w,
    );
    if (change == null) {
      props.sourcePropertiesXml = sourceXml;
    } else {
      node.children.remove(change);
      props.sourcePropertiesXml = XmlDocument(
        root: node,
      ).toXmlString(declaration: false);
    }
    final XmlPullReader source = WordMarkupCompatibilityReader(
      props.sourcePropertiesXml!,
    )..next();
    _parseRPr(source, props);
    return (change: change, sourceXml: sourceXml);
  }

  void _parseRPr(XmlPullReader reader, WmlRunProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    // The model exposes the regular font size. Keep the separate complex-
    // script size as a fallback only when no regular size is present. In an
    // effective style cascade an inherited szCs must not override a direct sz.
    // Source XML still retains both properties for independent round trips.
    var hasRegularSize = false;
    String? plainShading;
    var hasPlainShading = false;
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (const {
            'kern',
            'position',
            'noProof',
            'caps',
            'smallCaps',
            'color',
            'highlight',
            'shd',
            'lang',
            'rFonts',
            'rStyle',
          }.contains(reader.localName) &&
          (reader.depth != depth + 1 ||
              (reader.namespaceUri != OfficeNamespaces.w &&
                  !(reader.namespaceUri.isEmpty && reader.prefix == 'w')))) {
        // Opaque extensions and nested lookalikes do not define native run
        // controls. Preserve their XML without projecting their values.
        XmlDocument.readElement(reader);
        continue;
      }
      if (reader.localName == 'rPrChange' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        XmlDocument.readElement(reader);
        continue;
      }
      if (reader.localName == 'rFonts') {
        for (final group in const <String, Set<String>>{
          'ascii': {'ascii', 'hAnsi', 'asciiTheme', 'hAnsiTheme'},
          'cs': {'cs', 'cstheme'},
        }.entries) {
          if (group.value.any(
            (attribute) =>
                reader.getAttribute(
                  attribute,
                  namespaceUri: OfficeNamespaces.w,
                ) !=
                null,
          )) {
            props.explicitProperties.add('rFonts:${group.key}');
          }
        }
      } else {
        props.explicitProperties.add(reader.localName);
      }
      switch (reader.localName) {
        case 'lang':
          props.proofingLanguage = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          props.complexScriptLanguage = reader.getAttribute(
            'bidi',
            namespaceUri: OfficeNamespaces.w,
          );
        case 'rtl' || 'cs':
          final on = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
          props.complexScript = (props.complexScript ?? false) || on;
        case 'noProof':
          props.noProof = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'rStyle':
          props.styleId = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
        case 'b':
          props.bold = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
          if (!props.bold) {
            _notBold.add(props);
          }
        case 'i':
          props.italic = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
          if (!props.italic) {
            _notItalic.add(props);
          }
        case 'strike':
          props.strike = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'smallCaps':
          props.smallCaps = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'caps':
          props.allCaps = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'color':
          props.color =
              reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ??
              props.color;
        case 'highlight':
          props.highlight = WmlHighlight.toRgb(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'shd':
          // Only a native, opaque, unthemed clear fill has the same semantics
          // as the editor's scalar text background. Preserve all other shapes
          // as source XML, without inventing a rendered color.
          final pattern = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          final fill = reader.getAttribute(
            'fill',
            namespaceUri: OfficeNamespaces.w,
          );
          final themed =
              const {
                'themeColor',
                'themeTint',
                'themeShade',
                'themeFill',
                'themeFillTint',
                'themeFillShade',
              }.any(
                (name) =>
                    reader.getAttribute(
                      name,
                      namespaceUri: OfficeNamespaces.w,
                    ) !=
                    null,
              );
          if (!themed &&
              (pattern == null || pattern == 'clear') &&
              (fill == 'auto' ||
                  fill != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(fill))) {
            hasPlainShading = true;
            plainShading = fill == 'auto' ? null : fill!.toUpperCase();
          }
        case 'kern':
          props.kerningHalfPoints = int.tryParse(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '',
          );
        case 'position':
          final raw = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          final value =
              raw == null || !RegExp(r'^[+-]?[0-9]+$').hasMatch(raw.trim())
              ? null
              : int.tryParse(raw.trim());
          // Keep unsupported measurements opaque rather than inventing a
          // rounded baseline. Native macro writes validate the retained source.
          if (value != null && value >= -2147483648 && value <= 2147483647) {
            props.positionHalfPoints = value;
          }
        case 'sz':
        case 'szCs':
          final regularSize = reader.localName == 'sz';
          final String? sz = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          if (sz != null && (regularSize || !hasRegularSize)) {
            props.fontSizeHalfPoints = _measureHalfPoints(sz);
            hasRegularSize = hasRegularSize || regularSize;
          }
        case 'u':
          props.underline = WmlUnderline.fromXml(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'vertAlign':
          props.vertAlign = switch (reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          )) {
            'superscript' => WmlVertAlign.superscript,
            'subscript' => WmlVertAlign.subscript,
            _ => WmlVertAlign.baseline,
          };
        case 'rFonts':
          props.asciiFont =
              reader.getAttribute('ascii', namespaceUri: OfficeNamespaces.w) ??
              props.asciiFont;
          props.csFont =
              reader.getAttribute('cs', namespaceUri: OfficeNamespaces.w) ??
              props.csFont;
      }
    }
    if (hasPlainShading && props.highlight == null) {
      props.highlight = plainShading;
      props.explicitProperties.add('shd:highlight');
    }
  }

  static const int _maxTableXmlDepth = 128;

  WmlTable _readTable(XmlPullReader reader, OpcPackage package, String docUri) {
    if (reader.depth > _maxTableXmlDepth) {
      throw const FormatException('Word table nesting exceeds the safe limit');
    }
    final WmlTable table = WmlTable(
      properties: WmlTableProps(borders: false)..sourcePropertiesXml = '',
    );
    if (reader.isEmptyElement) {
      return table;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tblPr' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          reader.depth == depth + 1) {
        final XmlElement source = XmlDocument.readElement(reader);
        final String xml = XmlDocument(
          root: source,
        ).toXmlString(declaration: false);
        table.properties.sourcePropertiesXml = xml;
        _readTableProperties(WordMarkupCompatibilityReader(xml)..next(), table);
      } else if (reader.localName == 'gridCol') {
        final String? w = reader.getAttribute(
          'w',
          namespaceUri: OfficeNamespaces.w,
        );
        table.grid.add(w == null ? 100 : _measurePoints(w));
      } else if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (WordBookmarkIo.isMarker(reader)) {
        _blockMarker(reader);
      } else if (reader.localName == 'tr') {
        table.rows.add(_readRow(reader, package, docUri, table));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _unsupportedControl(docUri, 'content control wrapping table rows');
      }
    }
    _applyTableStyleToCells(table);
    table.properties.importedValues = WordTablePropertyIo.values(
      table.properties,
    );
    return table;
  }

  void _readTableProperties(XmlPullReader reader, WmlTable table) {
    final int depth = reader.depth;
    final nativeContainer =
        reader.localName == 'tblPr' &&
        reader.namespaceUri == OfficeNamespaces.w;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.depth != depth + 1) {
        continue;
      }
      if (reader.localName == 'tblStyle' &&
          nativeContainer &&
          reader.namespaceUri == OfficeNamespaces.w) {
        table.properties.styleId = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
      } else if (reader.localName == 'tblBorders') {
        _tablesWithOwnBorders.add(table);
        if (_readTblBorders(reader, table.properties)) {
          _tablesWithOwnBorderWidths.add(table);
        }
      } else if (reader.localName == 'tblLook') {
        _tableLooks[table] = _TableLook.read(reader);
      } else if (reader.localName == 'bidiVisual' &&
          nativeContainer &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _tablesWithOwnDirection.add(table);
        table.properties.rightToLeft = _onOff(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.localName == 'jc') {
        table.properties.alignment = _jc(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.localName == 'tblCellMar' &&
          nativeContainer &&
          reader.namespaceUri == OfficeNamespaces.w) {
        final firstDeclaration = _tablesWithOwnCellMargins.add(table);
        final element = XmlDocument.readElement(reader);
        final margin = WordTablePropertyIo.uniformCellMargin(element);
        // Any direct container blocks a guessed style fallback. Unsupported
        // or duplicate declarations keep their source XML and native fallback.
        table.properties.cellMargin = firstDeclaration ? margin ?? 4 : 4;
        table.properties.importedCellInsets = firstDeclaration && margin == null
            ? WordTablePropertyIo.directCellInsets(element)
            : null;
      }
    }
  }

  /// Returns whether a drawn direct border declares its own width.
  bool _readTblBorders(XmlPullReader reader, WmlTableProps props) {
    if (reader.isEmptyElement) {
      return false;
    }
    var hasDirectWidth = false;
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final String? val = reader.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      if (val == 'nil' || val == 'none') {
        continue;
      }
      final String? sz = reader.getAttribute(
        'sz',
        namespaceUri: OfficeNamespaces.w,
      );
      final String? color = reader.getAttribute(
        'color',
        namespaceUri: OfficeNamespaces.w,
      );
      if (sz != null) {
        props.borderWidth = (int.tryParse(sz) ?? 4) / 8.0;
        hasDirectWidth = true;
      }
      if (color != null && color.isNotEmpty && color.toLowerCase() != 'auto') {
        props.borderColor = color;
      }
      props.borders = true;
    }
    return hasDirectWidth;
  }

  /// Applies `styles.xml` table styles (borders, header row and banded row
  /// shading) to tables that do not set their own `w:tblBorders`. Styles
  /// that are missing from the package fall back to the style-id guess.
  void _applyTableStyles(
    WmlDocument document,
    OpcPackage package,
    String docUri,
  ) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? rel = rels.firstByType(RelationshipTypes.styles);
    final PackagePart? part = rel == null
        ? package.getPart('/word/styles.xml')
        : package.getPart(rels.resolve(rel));
    final Map<String, _TableStyle> styles = part == null
        ? <String, _TableStyle>{}
        : _TableStyle.readAll(part.readText());
    final defaultStyles = styles.entries
        .where((entry) => entry.value.isDefault)
        .toList();
    final defaultMarginStyle = defaultStyles.length == 1
        ? _TableStyle.resolve(defaultStyles.single.key, styles)
        : null;

    void applyTo(WmlTable table) {
      final String? styleId = table.properties.styleId;
      final _TableStyle? style = styleId == null
          ? null
          : _TableStyle.resolve(styleId, styles);
      final marginStyle = styleId == null ? defaultMarginStyle : style;
      if (!_tablesWithOwnDirection.contains(table)) {
        table.properties.rightToLeft = marginStyle?.rightToLeft ?? false;
      }
      // Word's left/start and right/end declarations describe leading and
      // trailing edges. Resolve them only after effective table direction is
      // known; native cells and the renderer store physical left/right sides.
      for (final row in table.rows) {
        for (final cell in row.cells) {
          final borders = _cellBorderValues.remove(cell);
          if (borders == null) continue;
          final leading = borders.containsKey('start')
              ? borders['start']
              : borders['left'];
          final trailing = borders.containsKey('end')
              ? borders['end']
              : borders['right'];
          cell
            ..borderTop = borders['top']
            ..borderBottom = borders['bottom']
            ..borderLeft = table.properties.rightToLeft ? trailing : leading
            ..borderRight = table.properties.rightToLeft ? leading : trailing;
        }
      }
      if (!_tablesWithOwnCellMargins.contains(table)) {
        if (marginStyle?.cellMargin case final margin?) {
          table.properties.cellMargin = margin;
        }
      }
      if (!_tablesWithOwnBorders.contains(table)) {
        if (style != null && style.bordersDeclared) {
          table.properties.borders = style.borderColor != null;
          if (style.borderColor != null) {
            table.properties
              ..borderColor = style.borderColor
              ..borderWidth = style.borderWidth;
          }
        } else if (styleId != null && _tableStyleLooksGrid(styleId)) {
          table.properties
            ..borders = true
            ..borderColor ??= '000000'
            ..borderWidth = 0.5;
        }
      } else if (style != null &&
          style.bordersDeclared &&
          style.borderColor != null &&
          (table.properties.borderColor == null ||
              table.properties.borderColor!.toLowerCase() == 'auto')) {
        // Word resolves an omitted/automatic direct border from the table
        // style. In particular Medium Grid 3's white grid must stay white
        // instead of becoming a black rectangle around every cell.
        table.properties.borderColor = style.borderColor;
        // Preserve an authored direct size; an omitted size still inherits.
        if (!_tablesWithOwnBorderWidths.contains(table)) {
          table.properties.borderWidth = style.borderWidth;
        }
      }
      if (style != null) {
        final _TableLook look = _tableLooks[table] ?? const _TableLook();
        for (var r = 0; r < table.rows.length; r++) {
          final bool header = r == 0 && look.firstRow;
          final int bodyRow = look.firstRow ? r - 1 : r;
          final String? fill = header
              ? style.firstRowFill
              : (look.bandedRows && bodyRow >= 0 && bodyRow.isEven
                    ? style.band1Fill
                    : null);
          if (fill == null) {
            continue;
          }
          for (final WmlTableCell cell in table.rows[r].cells) {
            cell.fillColor ??= fill;
          }
        }
        // Conditional run properties already went through _StyleCascade.
        // Reapplying them here would replace direct/character overrides and
        // reach into nested tables whose formatting belongs to another style.
        // Table styles in Word set the cell paragraph rhythm. Applying this
        // only to Table Grid left Medium Grid rows roughly 8 pt too tall.
        for (final WmlTableRow row in table.rows) {
          for (final WmlTableCell cell in row.cells) {
            for (final WmlBlock block in WordTree.visibleBlocks(cell.blocks)) {
              if (block is! WmlParagraph) continue;
              final properties = block.properties;
              var changed = false;
              if (!properties.explicitSpacingAfter &&
                  properties.spacingAfter != 0) {
                properties.spacingAfter = 0;
                changed = true;
              }
              if (!properties.explicitLineSpacing &&
                  properties.lineSpacingRule == WmlLineSpacingRule.auto &&
                  properties.lineSpacing != 1) {
                properties.lineSpacing = 1;
                changed = true;
              }
              if (changed && properties.importedValues != null) {
                // These are import defaults, not user edits. Keep them in the
                // effective baseline so sparse export does not pin new direct
                // spacing onto paragraphs that still inherit their styles.
                properties.importedValues = WordPropertyIo.paragraphValues(
                  properties,
                );
              }
            }
          }
        }
      }
      table.properties.importedValues = WordTablePropertyIo.values(
        table.properties,
      );
      for (final WmlTableRow row in table.rows) {
        for (final WmlTableCell cell in row.cells) {
          _walkTables(cell.blocks, applyTo);
        }
      }
    }

    for (final WmlSection section in document.sections) {
      _walkTables(section.blocks, applyTo);
    }
    for (final WmlNote note in <WmlNote>[
      ...document.footnotes,
      ...document.endnotes,
    ]) {
      _walkTables(note.blocks, applyTo);
    }
    _tablesWithOwnBorders.clear();
    _tablesWithOwnBorderWidths.clear();
    _tablesWithOwnCellMargins.clear();
    _tablesWithOwnDirection.clear();
    _cellBorderValues.clear();
    _tableLooks.clear();
  }

  static void _walkTables(
    List<WmlBlock> blocks,
    void Function(WmlTable) visit,
  ) {
    for (final WmlBlock block in blocks) {
      if (block is WmlTable) {
        visit(block);
      } else if (block is WmlFrame) {
        _walkTables(block.blocks, visit);
      } else if (block is WmlContentControlBlock) {
        _walkTables(block.blocks, visit);
      }
    }
  }

  static bool _tableStyleLooksGrid(String? styleId) {
    if (styleId == null || styleId.isEmpty) {
      return true;
    }
    final String lower = styleId.toLowerCase();
    return lower == 'tablegrid' ||
        lower == 'tablenormal' ||
        lower.contains('grid') ||
        lower.contains('listtable') ||
        lower.startsWith('table');
  }

  void _applyTableStyleToCells(WmlTable table) {
    final bool gridLike = _tableStyleLooksGrid(table.properties.styleId);
    if (!gridLike) {
      return;
    }
    for (final WmlTableRow row in table.rows) {
      for (final WmlTableCell cell in row.cells) {
        for (final WmlBlock block in WordTree.visibleBlocks(cell.blocks)) {
          if (block is! WmlParagraph) {
            continue;
          }
          // TableGrid pPr: after=0, line=240. Never clobber direct pPr spacing
          // (e.g. line=278) — the old 1.15≈278 heuristic wrongly crushed it.
          if (!block.properties.explicitSpacingAfter) {
            block.properties.spacingAfter = 0;
          }
          if (!block.properties.explicitLineSpacing &&
              block.properties.lineSpacingRule == WmlLineSpacingRule.auto) {
            block.properties.lineSpacing = 1.0;
          }
        }
      }
    }
  }

  WmlTableRow _readRow(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlTable table,
  ) {
    final WmlTableRow row = WmlTableRow();
    if (reader.isEmptyElement) {
      return row;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if ((reader.localName == 'gridBefore' ||
              reader.localName == 'gridAfter') &&
          reader.namespaceUri == OfficeNamespaces.w &&
          reader.depth == depth + 2) {
        final value = int.tryParse(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (value == null || value < 0) {
          throw FormatException('Invalid table row ${reader.localName}');
        }
        if (reader.localName == 'gridBefore') {
          row.gridBefore = value;
        } else {
          row.gridAfter = value;
        }
      } else if (reader.localName == 'cantSplit') {
        row.cantSplit = true;
      } else if (reader.localName == 'trHeight') {
        final String? raw = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
        if (raw != null) {
          row.height = _measurePoints(raw);
          row.heightIsExact =
              reader.getAttribute('hRule', namespaceUri: OfficeNamespaces.w) ==
              'exact';
        }
      } else if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (WordBookmarkIo.isMarker(reader)) {
        _blockMarker(reader);
      } else if (reader.localName == 'tc') {
        row.cells.add(_readCell(reader, package, docUri));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        row.cells.add(_readControlledCell(reader, package, docUri));
      }
    }
    return row;
  }

  WmlTableCell _readControlledCell(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final source = XmlDocument.readElement(reader);
    final children = source
        .firstChild('sdtContent', namespaceUri: OfficeNamespaces.w)
        ?.childElements
        .toList();
    if (children == null ||
        children.length != 1 ||
        children.single.namespaceUri != OfficeNamespaces.w ||
        !const {'tc', 'sdt'}.contains(children.single.localName)) {
      _unsupportedControl(docUri, 'content control without one table cell');
    }
    final content = _sdtContentReader(source)!;
    while (content.next() && content.eventType != XmlEventType.startElement) {
      // Skip whitespace and comments before the single cell.
    }
    final cell = content.localName == 'sdt'
        ? _readControlledCell(content, package, docUri)
        : _readCell(content, package, docUri);
    cell.contentControlWrappers.insert(
      0,
      WordContentControlIo.capture(source, package, docUri),
    );
    return cell;
  }

  WmlTableCell _readCell(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final WmlTableCell cell = WmlTableCell();
    if (reader.isEmptyElement) {
      return cell;
    }
    final int depth = reader.depth;
    int? nativePropertiesDepth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.endElement &&
          nativePropertiesDepth != null &&
          reader.depth == nativePropertiesDepth - 1) {
        nativePropertiesDepth = null;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tcPr' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          reader.depth == depth + 1 &&
          !reader.isEmptyElement) {
        nativePropertiesDepth = reader.depth;
      }
      if (reader.localName == 'tcW' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          reader.depth == depth + 2) {
        if (cell.sourceWidthXml != null) {
          throw const FormatException(
            'Duplicate preferred width in table cell',
          );
        }
        final source = XmlDocument.readElement(reader);
        cell.sourceWidthXml = XmlDocument(
          root: source,
        ).toXmlString(declaration: false);
        final type =
            source.getAttribute('type', namespaceUri: OfficeNamespaces.w) ??
            'dxa';
        final twips = int.tryParse(
          source.getAttribute('w', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (type == 'dxa' && twips != null && twips >= 0) {
          cell.width = twipsToPoints(twips);
        }
        cell.sourceWidthPoints = cell.width;
      } else if (reader.localName == 'gridSpan') {
        cell.gridSpan = _count(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.localName == 'vMerge') {
        final String? val = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
        cell.vMerge = val == 'restart' ? WmlVMerge.restart : WmlVMerge.cont;
      } else if (reader.localName == 'tcBorders' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          nativePropertiesDepth != null &&
          reader.depth == nativePropertiesDepth + 1) {
        _readTcBorders(reader, cell);
      } else if (reader.localName == 'shd') {
        final String? fill = reader.getAttribute(
          'fill',
          namespaceUri: OfficeNamespaces.w,
        );
        if (fill != null &&
            fill.isNotEmpty &&
            fill.toLowerCase() != 'auto' &&
            fill.toUpperCase() != 'FFFFFF') {
          cell.fillColor = fill;
        }
      } else if (_readMoveBoundary(reader, docUri)) {
        continue;
      } else if (WordBookmarkIo.isMarker(reader)) {
        _blockMarker(reader);
      } else if (reader.localName == 'p') {
        _addParagraph(cell.blocks, _readParagraph(reader, package, docUri));
      } else if (reader.localName == 'oMathPara' ||
          reader.localName == 'oMath') {
        final OmmlEquation? math = OmmlIo.readFrom(reader);
        if (math != null) {
          cell.blocks.add(WmlEquation(math: math));
        }
      } else if (reader.localName == 'tbl') {
        cell.blocks.add(_readTable(reader, package, docUri));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        cell.blocks.addAll(_readSdt(reader, package, docUri));
      } else if (reader.localName == 'altChunk' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        cell.blocks.add(WordOpaqueIo.read(reader, package, docUri));
      }
    }
    return cell;
  }

  void _readTcBorders(XmlPullReader reader, WmlTableCell cell) {
    if (_cellBorderValues.containsKey(cell)) {
      throw const FormatException('Duplicate native cell border container.');
    }
    final source = XmlDocument.readElement(reader);
    final values = <String, bool?>{};
    for (final border in source.childElements) {
      if (border.namespaceUri != OfficeNamespaces.w ||
          !const {
            'top',
            'bottom',
            'left',
            'right',
            'start',
            'end',
          }.contains(border.localName)) {
        continue;
      }
      if (values.containsKey(border.localName) ||
          border.childElements.isNotEmpty) {
        throw const FormatException(
          'Ambiguous native cell border declaration.',
        );
      }
      final value = border.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      values[border.localName] = switch (value) {
        'nil' || 'none' => false,
        null => null,
        _ => true,
      };
    }
    // MS-OI29500 14.4.1/14.4.5: modern start/end win over their legacy
    // left/right siblings independent of XML order. Physical mapping waits
    // for the table's direct/inherited bidiVisual value in _applyTableStyles.
    _cellBorderValues[cell] = values;
  }

  void _readSectPr(
    XmlPullReader reader,
    WmlSection section,
    OpcPackage package,
    String docUri,
  ) {
    final XmlElement source = XmlDocument.readElement(reader);
    final String sourceXml = XmlDocument(
      root: source,
    ).toXmlString(declaration: false);
    reader = WordMarkupCompatibilityReader(sourceXml)..next();
    String? headerRid;
    String? footerRid;
    String? firstHeaderRid;
    String? firstFooterRid;
    String? evenHeaderRid;
    String? evenFooterRid;
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement ||
            reader.depth != depth + 1 ||
            reader.namespaceUri != OfficeNamespaces.w) {
          continue;
        }
        if (reader.localName == 'pgSz') {
          section.pageSize = WmlPageSize(
            width: _twipAttr(reader, 'w', fallback: section.pageSize.width),
            height: _twipAttr(reader, 'h', fallback: section.pageSize.height),
          );
        } else if (reader.localName == 'pgMar') {
          section.margins = WmlPageMargins(
            top: _twipAttr(reader, 'top', fallback: 72),
            bottom: _twipAttr(reader, 'bottom', fallback: 72),
            left: _twipAttr(reader, 'left', fallback: 72),
            right: _twipAttr(reader, 'right', fallback: 72),
            header: _twipAttr(reader, 'header', fallback: 36),
            footer: _twipAttr(reader, 'footer', fallback: 36),
          );
        } else if (reader.localName == 'cols') {
          section.columnCount = _count(
            reader.getAttribute('num', namespaceUri: OfficeNamespaces.w),
          );
          final String? space = reader.getAttribute(
            'space',
            namespaceUri: OfficeNamespaces.w,
          );
          if (space != null) {
            section.columnSpace = _measurePoints(space);
          }
          section.columnSep = const {'1', 'true', 'on'}.contains(
            reader.getAttribute('sep', namespaceUri: OfficeNamespaces.w),
          );
        } else if (reader.localName == 'headerReference') {
          final String? rid = _relationshipId(reader);
          final String type =
              reader.getAttribute('type', namespaceUri: OfficeNamespaces.w) ??
              'default';
          if (type == 'first') {
            firstHeaderRid = rid ?? firstHeaderRid;
          } else if (type == 'even') {
            evenHeaderRid = rid ?? evenHeaderRid;
          } else {
            headerRid = rid ?? headerRid;
          }
        } else if (reader.localName == 'footerReference') {
          final String? rid = _relationshipId(reader);
          final String type =
              reader.getAttribute('type', namespaceUri: OfficeNamespaces.w) ??
              'default';
          if (type == 'first') {
            firstFooterRid = rid ?? firstFooterRid;
          } else if (type == 'even') {
            evenFooterRid = rid ?? evenFooterRid;
          } else {
            footerRid = rid ?? footerRid;
          }
        } else if (reader.localName == 'type') {
          section.breakKind = switch (reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          )) {
            'continuous' => WmlSectionBreakKind.continuous,
            'oddPage' => WmlSectionBreakKind.oddPage,
            'evenPage' => WmlSectionBreakKind.evenPage,
            _ => WmlSectionBreakKind.nextPage,
          };
        } else if (reader.localName == 'titlePg') {
          final String? value = reader.getAttribute('val');
          section.differentFirstPage =
              value != '0' && value != 'false' && value != 'off';
        } else if (reader.localName == 'lnNumType') {
          section.lineNumbers = true;
        }
      }
    }
    section.sourceProperties = WmlSectionSource(
      xml: sourceXml,
      values: WordSectionIo.values(section),
    );
    if (headerRid != null) {
      section.header.addAll(
        _readStoryByRid(
          package,
          docUri,
          headerRid,
          visualsOut: section.headerVisuals,
          preserveInto: (part) => section.preservedStories['header'] = part,
        ),
      );
    }
    if (footerRid != null) {
      section.footer.addAll(
        _readStoryByRid(
          package,
          docUri,
          footerRid,
          visualsOut: section.footerVisuals,
          preserveInto: (part) => section.preservedStories['footer'] = part,
        ),
      );
    }
    if (firstHeaderRid != null) {
      section.firstHeader.addAll(
        _readStoryByRid(
          package,
          docUri,
          firstHeaderRid,
          visualsOut: section.firstHeaderVisuals,
          preserveInto: (part) =>
              section.preservedStories['firstHeader'] = part,
        ),
      );
    }
    if (firstFooterRid != null) {
      section.firstFooter.addAll(
        _readStoryByRid(
          package,
          docUri,
          firstFooterRid,
          visualsOut: section.firstFooterVisuals,
          preserveInto: (part) =>
              section.preservedStories['firstFooter'] = part,
        ),
      );
    }
    if (evenHeaderRid != null) {
      section.evenHeader.addAll(
        _readStoryByRid(
          package,
          docUri,
          evenHeaderRid,
          visualsOut: section.evenHeaderVisuals,
          preserveInto: (part) => section.preservedStories['evenHeader'] = part,
        ),
      );
    }
    if (evenFooterRid != null) {
      section.evenFooter.addAll(
        _readStoryByRid(
          package,
          docUri,
          evenFooterRid,
          visualsOut: section.evenFooterVisuals,
          preserveInto: (part) => section.preservedStories['evenFooter'] = part,
        ),
      );
    }
  }

  void _ensureHeadersFooters(
    WmlDocument document,
    OpcPackage package,
    String docUri,
  ) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? headerRel = rels.firstByType(
      RelationshipTypes.header,
    );
    final PackageRelationship? footerRel = rels.firstByType(
      RelationshipTypes.footer,
    );
    for (final WmlSection section in document.sections) {
      if (section.header.isEmpty &&
          section.headerVisuals.isEmpty &&
          !section.preservedStories.containsKey('header') &&
          headerRel != null) {
        section.header.addAll(
          _readStoryByRid(
            package,
            docUri,
            headerRel.id,
            visualsOut: section.headerVisuals,
            preserveInto: (part) => section.preservedStories['header'] = part,
          ),
        );
      }
      if (section.footer.isEmpty &&
          section.footerVisuals.isEmpty &&
          !section.preservedStories.containsKey('footer') &&
          footerRel != null) {
        section.footer.addAll(
          _readStoryByRid(
            package,
            docUri,
            footerRel.id,
            visualsOut: section.footerVisuals,
            preserveInto: (part) => section.preservedStories['footer'] = part,
          ),
        );
      }
    }
  }

  List<WmlParagraph> _readStoryByRid(
    OpcPackage package,
    String docUri,
    String rid, {
    List<WmlVisual>? visualsOut,
    void Function(WmlOpaqueBlock part)? preserveInto,
  }) {
    // Headers and footers are independent field stories, even while a body
    // paragraph's section properties are being parsed.
    final fields = List<(WmlFieldBoundary, bool)>.of(_openFields);
    final toc = Map<WmlFieldBoundary, bool>.identity()..addAll(_tocBoundaries);
    _openFields.clear();
    _tocBoundaries.clear();
    try {
      return _readStoryByRidPreserving(
        package,
        docUri,
        rid,
        visualsOut: visualsOut,
        preserveInto: preserveInto,
      );
    } finally {
      _openFields
        ..clear()
        ..addAll(fields);
      _tocBoundaries
        ..clear()
        ..addAll(toc);
    }
  }

  List<WmlParagraph> _readStoryByRidPreserving(
    OpcPackage package,
    String docUri,
    String rid, {
    List<WmlVisual>? visualsOut,
    void Function(WmlOpaqueBlock part)? preserveInto,
  }) {
    if (preserveInto == null) {
      return _readStoryByRidModeled(
        package,
        docUri,
        rid,
        visualsOut: visualsOut,
      );
    }
    final int visualCount = visualsOut?.length ?? 0;
    final int revisionCount = _document?.revisions.length ?? 0;
    try {
      return _readStoryByRidModeled(
        package,
        docUri,
        rid,
        visualsOut: visualsOut,
      );
    } on UnsupportedError {
      // The paragraph-only header/footer model cannot represent this part
      // (a content control around a logo, a table or several paragraphs).
      // Keep the whole part verbatim instead of refusing the document.
      visualsOut?.removeRange(visualCount, visualsOut.length);
      // Revisions parsed before fallback refer to abandoned paragraphs. Their
      // native markup remains in the preserved part, not in the editable model.
      final revisions = _document?.revisions;
      revisions?.removeRange(revisionCount, revisions.length);
      _pendingVisuals.clear();
      _pendingFrames.clear();
      _pendingEquations.clear();
      final RelationshipCollection rels = package.relationshipsFor(docUri);
      final PackageRelationship rel = rels.byId(rid)!;
      final String storyUri = rels.resolve(rel);
      // Plain reader: a verbatim copy keeps every mc:AlternateContent
      // branch (e.g. VML fallbacks), unlike the compatibility reader.
      final XmlPullReader reader = XmlPullReader(
        package.getPart(storyUri)!.readText(),
      );
      while (reader.next() && reader.eventType != XmlEventType.startElement) {}
      final opaque = WordOpaqueIo.read(reader, package, storyUri);
      final anchor = _preservedWatermarkAnchor(opaque);
      preserveInto(
        anchor == null
            ? opaque
            : WmlOpaqueBlock(
                xml: opaque.xml,
                sourcePartUri: opaque.sourcePartUri,
                relationships: opaque.relationships,
                headerAnchor: anchor,
              ),
      );
      return <WmlParagraph>[];
    }
  }

  WmlParagraph? _preservedWatermarkAnchor(WmlOpaqueBlock header) {
    XmlElement? child(XmlElement? element, String name) =>
        element?.firstChild(name, namespaceUri: OfficeNamespaces.w);
    final root = XmlDocument.parse(header.xml).root;
    if (root?.namespaceUri != OfficeNamespaces.w ||
        root?.localName != 'hdr' ||
        root?.childElements.length != 1) {
      return null;
    }
    final control = child(root, 'sdt');
    final gallery = child(
      child(child(control, 'sdtPr'), 'docPartObj'),
      'docPartGallery',
    );
    if (gallery?.getAttribute('val', namespaceUri: OfficeNamespaces.w) !=
        'Watermarks') {
      return null;
    }
    final content = child(control, 'sdtContent');
    final paragraph = child(content, 'p');
    if (content?.childElements.length != 1 || paragraph == null) return null;
    final properties = child(paragraph, 'pPr');
    final run = child(paragraph, 'r');
    if (run == null ||
        paragraph.childElements.length != (properties == null ? 1 : 2)) {
      return null;
    }
    final drawing = child(run, 'pict');
    if (drawing == null ||
        run.childElements.length != (child(run, 'rPr') == null ? 1 : 2)) {
      return null;
    }
    final shape = drawing.firstChild('shape', namespaceUri: OfficeNamespaces.v);
    if (shape?.firstChild('textpath', namespaceUri: OfficeNamespaces.v) ==
        null) {
      return null;
    }
    final anchor = WmlParagraph();
    if (properties != null) {
      final fragment = properties.copy();
      final bindings = fragment.attributes.map((a) => a.qualifiedName).toSet();
      for (
        var parent = properties.parent;
        parent != null;
        parent = parent.parent
      ) {
        for (final attr in parent.attributes) {
          if ((attr.prefix == 'xmlns' || attr.localName == 'xmlns') &&
              bindings.add(attr.qualifiedName)) {
            fragment.attributes.add(attr.copy());
          }
        }
      }
      final xml = XmlDocument(root: fragment).toXmlString(declaration: false);
      _readPPr(WordMarkupCompatibilityReader(xml)..next(), anchor.properties);
    } else {
      anchor.properties.sourcePropertiesXml = '';
    }
    return anchor;
  }

  List<WmlParagraph> _readStoryByRidModeled(
    OpcPackage package,
    String docUri,
    String rid, {
    List<WmlVisual>? visualsOut,
  }) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? rel = rels.byId(rid);
    if (rel == null) {
      return <WmlParagraph>[];
    }
    final String storyUri = rels.resolve(rel);
    final PackagePart? part = package.getPart(storyUri);
    if (part == null) {
      return <WmlParagraph>[];
    }
    final List<WmlParagraph> paragraphs = <WmlParagraph>[];
    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'p' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        // Resolve drawings against the header/footer part, not document.xml.
        final WmlParagraph paragraph = _readParagraph(
          reader,
          package,
          storyUri,
        );
        // A drawing-only paragraph is represented by the separate story
        // visual, just as in the body. Retaining both adds a blank paragraph
        // on every save/reopen cycle.
        if (paragraph.inlines.isNotEmpty || _pendingVisuals.isEmpty) {
          paragraphs.add(paragraph);
        }
        if (visualsOut != null && _pendingVisuals.isNotEmpty) {
          visualsOut.addAll(_pendingVisuals);
          _pendingVisuals.clear();
        } else {
          _pendingVisuals.clear();
        }
        _pendingEquations.clear();
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        paragraphs.add(
          _readAuxiliaryControl(
            reader,
            package,
            storyUri,
            'header/footer',
          ).paragraph,
        );
      }
    }
    if (visualsOut != null && _pendingVisuals.isNotEmpty) {
      visualsOut.addAll(_pendingVisuals);
      _pendingVisuals.clear();
    }
    return paragraphs;
  }

  void _applyNumbering(
    WmlDocument document,
    OpcPackage package,
    String docUri,
  ) {
    final Map<int, _NumberingLevel> levels = _readNumbering(package, docUri);
    final sectionEnds = Set<WmlParagraph>.identity();
    for (var index = 0; index + 1 < document.sections.length; index++) {
      final section = document.sections[index];
      final end = WordTree.paragraphs(section.blocks).lastOrNull;
      if (end != null && section.sourceProperties != null) sectionEnds.add(end);
    }
    void applyStory(Iterable<WmlParagraph> paragraphs) {
      if (levels.isEmpty) {
        for (final WmlParagraph paragraph in paragraphs) {
          final int? numId = paragraph.properties.numId;
          if (numId != null && numId != 0) {
            paragraph.properties.listLabel ??= '• ';
          }
        }
        return;
      }
      final Map<String, List<int>> counters = <String, List<int>>{};
      for (final WmlParagraph paragraph in paragraphs) {
        final int? numId = paragraph.properties.numId;
        // `w:numId="0"` removes the paragraph from any list.
        if (numId == null || numId == 0) {
          continue;
        }
        if (paragraph.text.isEmpty) {
          final direct = WordPropertyIo.parse(
            paragraph.properties.sourcePropertiesXml,
            'pPr',
          );
          final sectionMark =
              sectionEnds.contains(paragraph) ||
              direct.firstChild('sectPr', namespaceUri: OfficeNamespaces.w) !=
                  null;
          if (sectionMark &&
              direct.firstChild('numPr', namespaceUri: OfficeNamespaces.w) ==
                  null) {
            // The section mark can inherit the previous heading's style.
            // Word does not display or count its inherited numbering.
            paragraph.properties.listLabel = null;
            continue;
          }
        }
        final int ilvl = paragraph.properties.ilvl.clamp(0, 8);
        final _NumberingLevel? level =
            levels[_levelKey(numId, ilvl)] ?? levels[_levelKey(numId, 0)];
        if (level == null) {
          paragraph.properties.listLabel ??= '• ';
          continue;
        }
        paragraph.properties.listLabelUsesSpace = level.suffix == 'space';
        if (level.isBullet) {
          paragraph.properties.listLabel = level.bulletLabel();
        } else {
          final String key = '$numId';
          final List<int> stack = counters.putIfAbsent(
            key,
            () => List<int>.filled(9, -1),
          );
          final int? restartAt = paragraph.properties.listRestart;
          stack[ilvl] =
              restartAt ?? (stack[ilvl] < 0 ? level.start : stack[ilvl] + 1);
          paragraph.properties.listRestart = null;
          for (int i = ilvl + 1; i < stack.length; i++) {
            stack[i] = -1;
          }
          for (int i = 0; i < ilvl; i++) {
            if (stack[i] < 0) {
              stack[i] = levels[_levelKey(numId, i)]?.start ?? 1;
            }
          }
          paragraph.properties.listLabel = level.decimalLabelStack(
            stack,
            ilvl,
            formats: <String>[
              for (var i = 0; i <= ilvl; i++)
                levels[_levelKey(numId, i)]?.fmt ?? level.fmt,
            ],
          );
        }
        if (paragraph.properties.indent.left == 0 &&
            paragraph.properties.indent.hanging == 0 &&
            (level.left > 0 || level.hanging > 0)) {
          paragraph.properties.indent = WmlIndent(
            left: level.left,
            right: paragraph.properties.indent.right,
            firstLine: paragraph.properties.indent.firstLine,
            hanging: level.hanging,
          );
        }
      }
    }

    // Keep each note's list counters independent from the body and other
    // notes, while resolving all stories against the same native definitions.
    applyStory(document.paragraphs);
    for (final note in [...document.footnotes, ...document.endnotes]) {
      applyStory(note.allParagraphs);
    }
  }

  Map<int, _NumberingLevel> _readNumbering(OpcPackage package, String docUri) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? rel = rels.firstByType(
      RelationshipTypes.numbering,
    );
    final PackagePart? part = rel == null
        ? package.getPart('/word/numbering.xml')
        : package.getPart(rels.resolve(rel));
    if (part == null) {
      return <int, _NumberingLevel>{};
    }
    return _indexNumbering(part.readText());
  }

  Map<int, _NumberingLevel> _indexNumbering(String xml) {
    final XmlElement? root = XmlDocument.parse(xml).root;
    if (root == null) return <int, _NumberingLevel>{};
    final Map<int, Map<int, _NumberingLevel>> byAbstract =
        <int, Map<int, _NumberingLevel>>{};

    _NumberingLevel readLevel(XmlElement node, {_NumberingLevel? base}) {
      final XmlElement? indent = node.firstChild('pPr')?.firstChild('ind');
      return _NumberingLevel(
        fmt:
            node.firstChild('numFmt')?.getAttribute('val') ??
            base?.fmt ??
            'bullet',
        text:
            node.firstChild('lvlText')?.getAttribute('val') ??
            base?.text ??
            '•',
        start:
            int.tryParse(node.firstChild('start')?.getAttribute('val') ?? '') ??
            base?.start ??
            1,
        left: indent?.getAttribute('left') == null
            ? base?.left ?? 0
            : twipsToPoints(int.tryParse(indent!.getAttribute('left')!) ?? 0),
        suffix: node.firstChild('suff')?.getAttribute('val') ?? base?.suffix,
        hanging: indent?.getAttribute('hanging') == null
            ? base?.hanging ?? 0
            : twipsToPoints(
                int.tryParse(indent!.getAttribute('hanging')!) ?? 0,
              ),
      );
    }

    for (final XmlElement definition in root.childrenNamed('abstractNum')) {
      final int? id = int.tryParse(
        definition.getAttribute('abstractNumId') ?? '',
      );
      if (id == null) continue;
      byAbstract[id] = <int, _NumberingLevel>{
        for (final XmlElement level in definition.childrenNamed('lvl'))
          if (int.tryParse(level.getAttribute('ilvl') ?? '')
              case final int ilvl)
            ilvl: readLevel(level),
      };
    }
    final Map<int, _NumberingLevel> mapped = <int, _NumberingLevel>{};
    for (final XmlElement instance in root.childrenNamed('num')) {
      final int? id = int.tryParse(instance.getAttribute('numId') ?? '');
      final int? abstractId = int.tryParse(
        instance.firstChild('abstractNumId')?.getAttribute('val') ?? '',
      );
      if (id == null || abstractId == null) continue;
      final Map<int, _NumberingLevel> levels = <int, _NumberingLevel>{
        ...?byAbstract[abstractId],
      };
      for (final XmlElement override in instance.childrenNamed('lvlOverride')) {
        final int? ilvl = int.tryParse(override.getAttribute('ilvl') ?? '');
        if (ilvl == null) continue;
        _NumberingLevel? level = levels[ilvl];
        if (override.firstChild('lvl') case final XmlElement ownLevel) {
          level = readLevel(ownLevel, base: level);
        }
        if (level == null) continue;
        final int? start = int.tryParse(
          override.firstChild('startOverride')?.getAttribute('val') ?? '',
        );
        levels[ilvl] = start == null
            ? level
            : _NumberingLevel(
                fmt: level.fmt,
                text: level.text,
                start: start,
                left: level.left,
                hanging: level.hanging,
                suffix: level.suffix,
              );
      }
      for (final MapEntry<int, _NumberingLevel> level in levels.entries) {
        mapped[_levelKey(id, level.key)] = level.value;
      }
    }
    return mapped;
  }

  static int _levelKey(int numId, int ilvl) => (numId << 8) | (ilvl & 0xFF);

  static String _elementText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final int depth = reader.depth;
    var first = '';
    StringBuffer? buffer;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        final text = reader.text;
        if (first.isEmpty) {
          first = text;
        } else if (text.isNotEmpty) {
          (buffer ??= StringBuffer(first)).write(text);
        }
      }
    }
    return buffer?.toString() ?? first;
  }

  void _readParagraphBorders(XmlPullReader reader, WmlParagraphProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final String? val = reader.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      if (val == null || val == 'none' || val == 'nil') {
        continue;
      }
      final String? color = reader.getAttribute(
        'color',
        namespaceUri: OfficeNamespaces.w,
      );
      if (color != null && color.isNotEmpty && color.toLowerCase() != 'auto') {
        props.borderColor = color;
      } else {
        props.borderColor ??= '000000';
      }
    }
  }

  void _readWatermark(WmlDocument document, OpcPackage package) {
    final PackagePart? part = package.getPart('/word/watermark.xml');
    if (part != null) {
      final String xml = part.readText();
      final Match? match = RegExp(
        r'<w:watermark[^>]*>([^<]*)</w:watermark>',
      ).firstMatch(xml);
      if (match != null) {
        document.watermark = match
            .group(1)!
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
      }
    }
    final RegExp vml = RegExp(r'string="([^"]*)"');
    for (final PackagePart header in package.parts) {
      if (!header.uri.contains('/word/header')) {
        continue;
      }
      final Match? match = vml.firstMatch(header.readText());
      if (match != null && match.group(1)!.isNotEmpty) {
        document.watermark = match
            .group(1)!
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
        return;
      }
    }
  }

  void _readNotes(WmlDocument document, OpcPackage package, String docUri) {
    document.sourceFootnoteSeparatorsPresent = _readNotesPart(
      document.footnotes,
      package,
      docUri,
      RelationshipTypes.footnotes,
      '/word/footnotes.xml',
      'footnote',
      endnote: false,
    );
    _readNotesPart(
      document.endnotes,
      package,
      docUri,
      RelationshipTypes.endnotes,
      '/word/endnotes.xml',
      'endnote',
      endnote: true,
    );
    WordFootnoteSeparatorIo.readLayout(document);
  }

  bool? _readNotesPart(
    List<WmlNote> bucket,
    OpcPackage package,
    String docUri,
    String relType,
    String fallbackUri,
    String item, {
    required bool endnote,
  }) {
    final PackageRelationship? rel = package
        .relationshipsFor(docUri)
        .firstByType(relType);
    final String uri = rel == null
        ? fallbackUri
        : package.relationshipsFor(docUri).resolve(rel);
    final PackagePart? part = package.getPart(uri);
    if (part == null) {
      return null;
    }
    var separatorsPresent = false;
    bucket.clear();
    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != item) {
        continue;
      }
      final String? noteType = reader.getAttribute(
        'type',
        namespaceUri: OfficeNamespaces.w,
      );
      // Native separator definitions are optional and may be customized. They
      // remain in their owning package part rather than the editable note list.
      if (noteType == 'separator' ||
          noteType == 'continuationSeparator' ||
          noteType == 'continuationNotice') {
        separatorsPresent = true;
        if (!reader.isEmptyElement) {
          final int skipDepth = reader.depth;
          while (reader.next() && reader.depth >= skipDepth) {}
        }
        continue;
      }
      final int id =
          int.tryParse(
            reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
          ) ??
          bucket.length + 1;
      final WmlNote note = WmlNote(
        id: id,
        endnote: endnote,
        addReference: false,
        addReferenceSpace: false,
        referencePropertiesXml: '',
      );
      _readingNote = note;
      _noteMarkCaptured = false;
      _endBlockStory();
      note.blocks.clear();
      if (!reader.isEmptyElement) {
        final int depth = reader.depth;
        while (reader.next() && reader.depth >= depth) {
          if (reader.eventType == XmlEventType.startElement &&
              reader.localName == 'p') {
            _addParagraph(note.blocks, _readParagraph(reader, package, uri));
          } else if (reader.eventType == XmlEventType.startElement &&
              reader.localName == 'tbl') {
            note.blocks.add(_readTable(reader, package, uri));
          } else if (reader.eventType == XmlEventType.startElement &&
              reader.localName == 'sdt') {
            note.blocks.addAll(_readSdt(reader, package, uri));
          } else if (reader.eventType == XmlEventType.startElement &&
              reader.localName == 'altChunk' &&
              reader.namespaceUri == OfficeNamespaces.w) {
            note.blocks.add(WordOpaqueIo.read(reader, package, uri));
          }
        }
      }
      _endBlockStory();
      _readingNote = null;
      if (note.blocks.isEmpty) {
        note.text = '';
      }
      bucket.add(note);
    }
    return separatorsPresent;
  }

  void _readStyles(
    WmlDocument document,
    OpcPackage package,
    String docUri, {
    bool readProofingLanguage = true,
  }) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? rel = rels.firstByType(RelationshipTypes.styles);
    final PackagePart? part = rel == null
        ? package.getPart('/word/styles.xml')
        : package.getPart(rels.resolve(rel));
    if (part == null) {
      return;
    }
    if (readProofingLanguage) {
      final defaultLanguage = XmlDocument.parse(part.readText()).root
          ?.firstChild('docDefaults', namespaceUri: OfficeNamespaces.w)
          ?.firstChild('rPrDefault', namespaceUri: OfficeNamespaces.w)
          ?.firstChild('rPr', namespaceUri: OfficeNamespaces.w)
          ?.firstChild('lang', namespaceUri: OfficeNamespaces.w);
      document.proofingLanguage = defaultLanguage?.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      document.complexScriptLanguage = defaultLanguage?.getAttribute(
        'bidi',
        namespaceUri: OfficeNamespaces.w,
      );
    }
    document.styles.clear();
    final nativeStyles = _StyleCascade(this, document)
      .._load(includeTheme: false);
    bool styleRightToLeft(String styleId) {
      bool? direction;
      for (final properties in <XmlElement?>[
        _StyleCascade._wordChild(
          _StyleCascade._wordChild(nativeStyles.defaults, 'pPrDefault'),
          'pPr',
        ),
        for (final style in nativeStyles.chain(styleId))
          _StyleCascade._wordChild(style, 'pPr'),
      ]) {
        final bidi = _StyleCascade._wordChild(properties, 'bidi');
        if (bidi != null) {
          direction = _onOff(_StyleCascade._tabAttribute(bidi, 'val'));
        }
      }
      return direction == true;
    }

    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    String? id;
    String name = '';
    String? basedOn;
    String? font;
    String? csFont;
    var bold = false;
    var italic = false;
    var color = '000000';
    var fontSizePoints = 11.0;
    var spacingBefore = 0.0;
    var spacingAfter = 8.0;
    String? justification;
    int? headingLevel;
    int? numId;
    int? ilvl;
    WmlIndent? indent;
    while (reader.next()) {
      // Table-style conditional blocks (`w:tblStylePr`) format table regions,
      // not the style itself.
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'tblStylePr') {
        reader.skip();
        continue;
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'style') {
        final String? type = reader.getAttribute(
          'type',
          namespaceUri: OfficeNamespaces.w,
        );
        if (type != null && type != 'paragraph') {
          reader.skip();
          continue;
        }
        id = reader.getAttribute('styleId', namespaceUri: OfficeNamespaces.w);
        name = '';
        basedOn = null;
        font = null;
        csFont = null;
        bold = false;
        italic = false;
        color = '000000';
        fontSizePoints = 11;
        spacingBefore = 0;
        spacingAfter = 8;
        justification = null;
        headingLevel = null;
        numId = null;
        ilvl = null;
        indent = null;
      } else if (reader.eventType == XmlEventType.startElement &&
          id != null &&
          (reader.localName == 'numId' || reader.localName == 'ilvl')) {
        final int? value = int.tryParse(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (reader.localName == 'numId') {
          numId = value;
        } else {
          ilvl = value;
        }
      } else if (reader.eventType == XmlEventType.startElement &&
          id != null &&
          reader.localName == 'ind') {
        indent = WmlIndent(
          left: _twipAttr(reader, 'left', fallback: _twipAttr(reader, 'start')),
          right: _twipAttr(reader, 'right', fallback: _twipAttr(reader, 'end')),
          firstLine: _twipAttr(reader, 'firstLine'),
          hanging: _twipAttr(reader, 'hanging'),
        );
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'name' &&
          id != null) {
        name =
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ??
            name;
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'basedOn' &&
          id != null) {
        basedOn = reader.getAttribute('val', namespaceUri: OfficeNamespaces.w);
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'rFonts') {
        font =
            reader.getAttribute('ascii', namespaceUri: OfficeNamespaces.w) ??
            reader.getAttribute('hAnsi', namespaceUri: OfficeNamespaces.w) ??
            font;
        csFont =
            reader.getAttribute('cs', namespaceUri: OfficeNamespaces.w) ??
            csFont;
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'jc') {
        justification = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'spacing') {
        final String? before = reader.getAttribute(
          'before',
          namespaceUri: OfficeNamespaces.w,
        );
        final String? after = reader.getAttribute(
          'after',
          namespaceUri: OfficeNamespaces.w,
        );
        if (before != null) {
          spacingBefore = _measurePoints(before);
        }
        if (after != null) {
          spacingAfter = _measurePoints(after);
        }
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'outlineLvl') {
        final int? lvl = int.tryParse(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (lvl != null) {
          headingLevel = lvl + 1;
        }
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'b') {
        bold = _onOff(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'i') {
        italic = _onOff(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'color') {
        color =
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ??
            color;
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'sz') {
        final int? half = int.tryParse(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (half != null && half > 0) {
          fontSizePoints = half / 2.0;
        }
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'style' &&
          id != null &&
          id.isNotEmpty) {
        final WmlStyle style = WmlStyle(
          id: id,
          name: name.isEmpty ? id : name,
          nameAr: name.isEmpty ? id : name,
          bold: bold,
          italic: italic,
          color: color,
          fontSizePoints: fontSizePoints,
          spacingBefore: spacingBefore,
          spacingAfter: spacingAfter,
          justification: _jc(justification, rightToLeft: styleRightToLeft(id)),
          headingLevel: headingLevel,
          font: font,
          csFont: csFont,
          basedOn: basedOn,
          numId: numId,
          ilvl: ilvl,
          indent: indent == null
              ? null
              : _physicalIndent(indent, styleRightToLeft(id)),
        );
        document.styles.add(style);
        document.importedStyles[style.id] = style;
        id = null;
      }
    }
  }

  /// Removes direct language overrides from a detached paragraph preview.
  ///
  /// The source identifies the current table/paragraph/character style context.
  /// Effective inherited run languages remain available for live proofing,
  /// while sparse export continues to omit the removed direct override. Other
  /// formatting, East Asian language metadata, and the live document and
  /// package are unchanged. Returns false when the selected text already
  /// inherits its language. The preview must be detached and have source text.
  /// Set [includeComplexScript] to also remove direct `w:lang/@w:bidi`
  /// overrides. Otherwise complex-script metadata is preserved.
  /// Set [activeLanguageOnly] to clear only the language slots used by each
  /// selected fragment, preserving inactive slots. A mixed-script fragment
  /// can use both slots. This takes precedence over [includeComplexScript].
  bool clearRunProofingLanguage(
    WmlDocument document,
    WmlParagraph sourceParagraph,
    WmlParagraph previewParagraph,
    int start,
    int end, {
    bool includeComplexScript = false,
    bool activeLanguageOnly = false,
  }) => _StyleCascade(this, document).clearRunProofingLanguage(
    sourceParagraph,
    previewParagraph,
    start,
    end,
    includeComplexScript: includeComplexScript,
    activeLanguageOnly: activeLanguageOnly,
  );

  /// Upsert one custom paragraph tab, replace the effective custom collection
  /// with [replacement], or clear current custom definitions when both are
  /// null. Default tab settings and hanging indents remain unchanged. Native
  /// sparse properties retain opaque metadata and inherited tabs are cleared
  /// with explicit position records. Unsupported ambiguous source is refused
  /// before the paragraph changes. [paragraphProperties] is an optional
  /// detached candidate carrying other validated paragraph edits, published
  /// together with the replacement. Replacement retains the legacy native
  /// serializer's nonnegative-point input and twip rounding behavior.
  void editParagraphTabStops(
    WmlDocument document,
    WmlParagraph paragraph, {
    WmlTabStop? tab,
    List<WmlTabStop>? replacement,
    WmlParagraphProps? paragraphProperties,
  }) => _StyleCascade(this, document).editParagraphTabStops(
    paragraph,
    tab,
    replacement: replacement,
    properties: paragraphProperties,
  );

  /// Assign an existing native paragraph style by its primary [name] or a
  /// supported Word [builtin] constant. Exactly one selector is required.
  /// Direct paragraph/run properties and opaque style metadata are preserved.
  /// The selected paragraph is prepared privately and only published after
  /// source ownership, style inheritance, and numbering checks succeed.
  void editParagraphStyle(
    WmlDocument document,
    WmlParagraph paragraph, {
    String? name,
    int? builtin,
  }) => _StyleCascade(
    this,
    document,
  ).assignParagraphStyle(paragraph, name: name, builtin: builtin);

  /// Formatting inherited by a paragraph of this native style, without
  /// the current paragraph's direct formatting.
  WmlParagraphProps? paragraphStyleProperties(WmlDocument document, String id) {
    final cascade = _StyleCascade(this, document);
    if (!cascade._load(includeTheme: false)) return null;
    final style = cascade.styles[id];
    if (style == null ||
        (style.getAttribute('type', namespaceUri: OfficeNamespaces.w) ??
                'paragraph') !=
            'paragraph') {
      return null;
    }
    final paragraph = WmlParagraph(properties: WmlParagraphProps(styleId: id));
    cascade.paragraph(paragraph, const []);
    return paragraph.properties;
  }

  /// Recompute effective formatting after editing a source style definition.
  void refreshStyles(WmlDocument document) {
    final OpcPackage? package = document.package;
    if (package == null) return;
    final rel = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    final uri = rel == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(rel);
    _readStyles(document, package, uri, readProofingLanguage: false);
    _applyDocumentStyles(document);
  }

  /// Refresh the native list labels after an editor changes a paragraph style.
  void refreshNumbering(WmlDocument document) {
    final package = document.package;
    if (package == null) return;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    final uri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    _applyNumbering(document, package, uri);
  }

  void _applyDocumentStyles(WmlDocument document) {
    if (_StyleCascade(this, document).apply()) return;
    _applyLegacyDocumentStyles(document);
  }

  void _applyLegacyDocumentStyles(WmlDocument document) {
    void walk(Iterable<WmlParagraph> story) {
      for (final WmlParagraph paragraph in story) {
        WordStyles.resolveOntoParagraph(
          paragraph,
          document: document,
          notBold: _notBold,
          notItalic: _notItalic,
        );
      }
    }

    walk(document.paragraphs);
    for (final comment in document.comments) {
      walk(comment.paragraphs);
    }
    for (final WmlNote note in <WmlNote>[
      ...document.footnotes,
      ...document.endnotes,
    ]) {
      walk(note.allParagraphs);
    }
    for (final WmlSection section in document.sections) {
      walk(section.header);
      walk(section.footer);
      walk(section.firstHeader);
      walk(section.firstFooter);
      walk(section.evenHeader);
      walk(section.evenFooter);
      for (final WmlBlock block in section.blocks) {
        if (block is WmlTable) {
          for (final WmlTableRow row in block.rows) {
            for (final WmlTableCell cell in row.cells) {
              for (final WmlBlock cellBlock in cell.blocks) {
                if (cellBlock is WmlParagraph) {
                  WordStyles.resolveOntoParagraph(
                    cellBlock,
                    document: document,
                    notBold: _notBold,
                    notItalic: _notItalic,
                  );
                }
              }
            }
          }
        }
      }
    }
  }

  void _readSettingsFlags(
    WmlDocument document,
    OpcPackage package,
    String docUri,
  ) {
    final PackageRelationship? rel = package
        .relationshipsFor(docUri)
        .firstByType(RelationshipTypes.settings);
    final PackagePart? part = package.getPart(
      rel == null
          ? '/word/settings.xml'
          : package.relationshipsFor(docUri).resolve(rel),
    );
    if (part == null) {
      return;
    }
    final settings = WordSettingsIo.read(part.readText());
    document
      ..autoHyphenation = settings.autoHyphenation
      ..defaultTabStop = settings.defaultTabStop
      ..sourceNoSpaceRaiseLower = settings.noSpaceRaiseLower
      ..trackRevisions = settings.tracking
      ..restrictEditing = settings.protection
      ..restrictMode = settings.restrictMode
      ..protectionHasPassword = settings.protectionHasPassword
      ..protectionFormattingRestricted =
          settings.protectionFormattingRestricted;
    for (final section in document.sections) {
      section.differentOddEven = settings.oddEven;
    }
  }

  static bool _isPageField(String instr) =>
      WordFields.kindOf(instr) == WmlFieldKind.page;

  /// RegExp API.
  static final RegExp _cachedPageResult = RegExp(r'^\s*\d+\s*$');

  WmlObject? _readObject(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    String? rid = _relationshipId(reader);
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        rid ??= _relationshipId(reader);
      }
    }
    if (rid == null) {
      return null;
    }
    final PackageRelationship? rel = package.relationshipsFor(docUri).byId(rid);
    IsolatedEmbeddedPackage? embedded;
    if (rel != null && rel.targetMode == RelationshipTargetMode.internal) {
      final String target = package.relationshipsFor(docUri).resolve(rel);
      final PackagePart? part = package.getPart(target);
      if (part != null) {
        try {
          embedded = EmbeddedPart.unpack(part.readBytes());
        } on Object {
          if (part.contentType.contains('sheet') || target.endsWith('.xlsx')) {
            embedded = IsolatedEmbeddedPackage(
              package: OpcPackage.openBytes(part.readBytes()),
              kind: OpcPackageKind.sheet,
            );
          }
        }
      }
    }
    return WmlObject(relationshipId: rid, embedded: embedded);
  }

  static String? _relationshipId(XmlPullReader reader) {
    return reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
        reader.getAttribute('id') ??
        reader.getAttribute('embed', namespaceUri: OfficeNamespaces.r) ??
        reader.getAttribute('embed');
  }

  static WmlIndent _physicalIndent(WmlIndent logical, bool rightToLeft) =>
      rightToLeft
      ? logical.copyWith(left: logical.right, right: logical.left)
      : logical;

  static WmlJustification _jc(String? val, {bool rightToLeft = false}) {
    return switch (val) {
      'center' => WmlJustification.center,
      'left' ||
      'start' => rightToLeft ? WmlJustification.right : WmlJustification.left,
      'right' ||
      'end' => rightToLeft ? WmlJustification.left : WmlJustification.right,
      'both' || 'justify' => WmlJustification.justify,
      'distribute' => WmlJustification.distributed,
      _ => WmlJustification.left,
    };
  }

  static bool _onOff(String? val) {
    if (val == null || val.isEmpty) {
      return true;
    }
    switch (val.toLowerCase()) {
      case '0':
      case 'false':
      case 'off':
        return false;
      default:
        return true;
    }
  }

  static final RegExp _universalMeasure = RegExp(
    r'^\s*(-?[0-9]*\.?[0-9]+)\s*(mm|cm|in|pt|pc|pi)?\s*$',
  );

  /// ST_TwipsMeasure / ST_SignedTwipsMeasure: an integer, but producers
  /// also write decimals ("276.5") and ISO 29500 allows universal measures
  /// ("12pt", "0.5in"). Word accepts all of them; refusing the document
  /// over one spacing value is worse than reading it. Malformed values
  /// count as 0 (Word's behaviour) instead of aborting the import.
  static double _measureTwips(String raw) {
    final Match? m = _universalMeasure.firstMatch(raw);
    if (m == null) return 0;
    final double value = double.parse(m.group(1)!);
    if (!value.isFinite) return 0;
    final double result = switch (m.group(2)) {
      'mm' => value * 1440 / 25.4,
      'cm' => value * 1440 / 2.54,
      'in' => value * 1440,
      'pt' => value * 20,
      'pc' || 'pi' => value * 240,
      _ => value,
    };
    return result.isFinite ? result : 0;
  }

  static double _measurePoints(String raw) => _measureTwips(raw) / 20.0;

  /// ST_HpsMeasure: half-points, or a universal measure.
  static int _measureHalfPoints(String raw) {
    final Match? m = _universalMeasure.firstMatch(raw);
    if (m == null) return 24;
    final double value = m.group(2) == null
        ? double.parse(m.group(1)!)
        : _measureTwips(raw) / 10; // twips -> half-points
    if (!value.isFinite) return 24;
    return value.clamp(1, 3276).round();
  }

  /// Integer counts (grid spans, column counts); invalid -> 1.
  static int _count(String? raw) {
    final int? value = int.tryParse(raw?.trim() ?? '');
    return value == null || value < 1 ? 1 : value;
  }

  static double _twipAttr(
    XmlPullReader reader,
    String name, {
    double fallback = 0,
  }) {
    final String? raw = reader.getAttribute(
      name,
      namespaceUri: OfficeNamespaces.w,
    );
    if (raw == null) {
      return fallback;
    }
    return _measurePoints(raw);
  }

  void _readComments(WmlDocument document, OpcPackage package, String docUri) {
    final PackageRelationship? rel = package
        .relationshipsFor(docUri)
        .firstByType(RelationshipTypes.comments);
    if (rel == null) {
      return;
    }
    final PackagePart? part = package.getPart(
      package.relationshipsFor(docUri).resolve(rel),
    );
    if (part == null) {
      return;
    }
    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'comment') {
        continue;
      }
      final int id =
          int.tryParse(
            reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
          ) ??
          document.comments.length;
      final String author =
          reader.getAttribute('author', namespaceUri: OfficeNamespaces.w) ??
          'CrispOffice';
      final String initials =
          reader.getAttribute('initials', namespaceUri: OfficeNamespaces.w) ??
          '';
      final String dateIso =
          reader.getAttribute('date', namespaceUri: OfficeNamespaces.w) ?? '';
      final List<WmlParagraph> paragraphs = <WmlParagraph>[];
      final List<WmlVisual> visuals = <WmlVisual>[];
      final StringBuffer fallback = StringBuffer();
      String? paragraphId;
      final int depth = reader.depth;
      final String commentsUri = package.relationshipsFor(docUri).resolve(rel);
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (reader.localName == 'p') {
          paragraphId = WordCommentIo.normalizeParagraphId(
            reader.getAttribute('paraId', namespaceUri: OfficeNamespaces.w14),
          );
          paragraphs.add(_readParagraph(reader, package, commentsUri));
        } else if (reader.localName == 'drawing') {
          _takeDrawing(reader, package, commentsUri);
        } else if (reader.localName == 'sdt' &&
            reader.namespaceUri == OfficeNamespaces.w) {
          final controlled = _readAuxiliaryControl(
            reader,
            package,
            commentsUri,
            'comment',
          );
          paragraphs.add(controlled.paragraph);
          paragraphId = controlled.paragraphId;
        } else if (reader.localName == 't') {
          if (fallback.isNotEmpty) {
            fallback.write('\n');
          }
          fallback.write(_elementText(reader));
        }
      }
      for (final WmlVisual visual in _pendingVisuals) {
        visuals.add(visual);
      }
      _pendingVisuals.clear();
      document.comments.add(
        WmlComment(
          id: id,
          author: author,
          initials: initials,
          dateIso: dateIso,
          text: fallback.toString(),
          paragraphs: paragraphs.isEmpty ? null : paragraphs,
          visuals: visuals,
          paragraphId: paragraphId,
        ),
      );
    }
  }

  void _readCommentsExtended(
    WmlDocument document,
    OpcPackage package,
    String docUri,
  ) {
    final PackageRelationship? rel = package
        .relationshipsFor(docUri)
        .firstByType(RelationshipTypes.commentsExtended);
    if (rel == null) {
      return;
    }
    final PackagePart? part = package.getPart(
      package.relationshipsFor(docUri).resolve(rel),
    );
    if (part == null) {
      return;
    }
    WordCommentIo.readExtended(
      document.comments,
      WordMarkupCompatibilityReader(part.readText()),
    );
  }
}

/// `w:tblLook`: which conditional table-style regions a table turns on.
class _TableLook {
  const _TableLook({this.firstRow = true, this.bandedRows = true});

  factory _TableLook.read(XmlPullReader reader) => _TableLook._attributes(
    (name) => reader.getAttribute(name, namespaceUri: OfficeNamespaces.w),
  );

  factory _TableLook.element(XmlElement element) => _TableLook._attributes(
    (name) => element.getAttribute(name, namespaceUri: OfficeNamespaces.w),
  );

  factory _TableLook._attributes(String? Function(String) attribute) {
    final String? val = attribute('val');
    final int mask = int.tryParse(val ?? '', radix: 16) ?? 0x04A0;
    bool flag(String name, bool fallback) {
      final String? raw = attribute(name);
      return raw == null ? fallback : (raw == '1' || raw == 'true');
    }

    return _TableLook(
      firstRow: flag('firstRow', mask & 0x0020 != 0),
      bandedRows: !flag('noHBand', mask & 0x0200 != 0),
    );
  }

  final bool firstRow;
  final bool bandedRows;
}

/// The parts of a `styles.xml` table style the layout can draw.
class _TableStyle {
  _TableStyle({this.basedOn});

  String? basedOn;
  bool isDefault = false;

  /// Presence is separate from projection: an unsupported child declaration
  /// must not inherit a parent's scalar and pretend its margins are uniform.
  bool cellMarginsDeclared = false;
  double? cellMargin;

  /// Null inherits; explicit false overrides a right-to-left parent.
  bool? rightToLeft;

  /// The style has its own `w:tblPr/w:tblBorders`.
  bool bordersDeclared = false;

  /// First drawn border color; null when every border is `nil` / `none`.
  String? borderColor;
  double borderWidth = 0.5;
  String? firstRowFill;
  String? band1Fill;

  static _TableStyle? resolve(
    String id,
    Map<String, _TableStyle> styles, [
    Set<String>? seen,
  ]) {
    final _TableStyle? style = styles[id];
    final Set<String> visited = seen ?? <String>{};
    if (style == null || !visited.add(id)) {
      return style;
    }
    final String? parentId = style.basedOn;
    final _TableStyle? parent = parentId == null
        ? null
        : resolve(parentId, styles, visited);
    if (parent == null) {
      return style;
    }
    final _TableStyle merged = _TableStyle(basedOn: parentId)
      ..isDefault = style.isDefault
      ..cellMarginsDeclared =
          style.cellMarginsDeclared || parent.cellMarginsDeclared
      ..cellMargin = style.cellMarginsDeclared
          ? style.cellMargin
          : parent.cellMargin
      ..rightToLeft = style.rightToLeft ?? parent.rightToLeft
      ..bordersDeclared = style.bordersDeclared || parent.bordersDeclared
      ..borderColor = style.bordersDeclared
          ? style.borderColor
          : parent.borderColor
      ..borderWidth = style.bordersDeclared
          ? style.borderWidth
          : parent.borderWidth
      ..firstRowFill = style.firstRowFill ?? parent.firstRowFill
      ..band1Fill = style.band1Fill ?? parent.band1Fill;
    return merged;
  }

  static Map<String, _TableStyle> readAll(String xml) {
    final Map<String, _TableStyle> out = <String, _TableStyle>{};
    final XmlPullReader reader = WordMarkupCompatibilityReader(xml);
    String? id;
    String? basedOn;
    var basedOnDeclared = false;
    var isTable = false;
    _TableStyle? current;
    String? region;
    var inBorders = false;
    int? stylesDepth;
    int? styleDepth;
    int? tablePropertiesDepth;
    while (reader.next()) {
      final String name = reader.localName;
      if (reader.eventType == XmlEventType.endElement) {
        if (name == 'tblStylePr') {
          region = null;
        } else if (name == 'tblBorders') {
          inBorders = false;
        } else if (name == 'tblPr' &&
            tablePropertiesDepth != null &&
            reader.depth == tablePropertiesDepth - 1) {
          tablePropertiesDepth = null;
        } else if (name == 'style' &&
            styleDepth != null &&
            reader.depth == styleDepth - 1) {
          if (isTable && id != null && current != null) {
            out[id] = current..basedOn = basedOn;
          }
          id = null;
          current = null;
          styleDepth = null;
          tablePropertiesDepth = null;
        } else if (name == 'styles' && reader.depth == 0) {
          stylesDepth = null;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      final String? val = reader.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      if (name == 'styles' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          reader.depth == 1) {
        stylesDepth = reader.depth;
      } else if (name == 'style') {
        // Only direct native styles can supply effective table properties.
        // Foreign and nested lookalikes remain in the preserved styles part.
        if (reader.namespaceUri != OfficeNamespaces.w ||
            stylesDepth == null ||
            reader.depth != stylesDepth + 1) {
          XmlDocument.readElement(reader);
          continue;
        }
        isTable =
            reader.getAttribute('type', namespaceUri: OfficeNamespaces.w) ==
            'table';
        id = reader.getAttribute('styleId', namespaceUri: OfficeNamespaces.w);
        basedOn = null;
        basedOnDeclared = false;
        region = null;
        inBorders = false;
        current = _TableStyle();
        styleDepth = reader.depth;
        current.isDefault = const {'1', 'true', 'on'}.contains(
          reader.getAttribute('default', namespaceUri: OfficeNamespaces.w),
        );
        if (reader.isEmptyElement) {
          if (isTable && id != null) out[id] = current;
          id = null;
          current = null;
          styleDepth = null;
        }
        tablePropertiesDepth = null;
      } else if (current == null || !isTable) {
        continue;
      } else if (name == 'tblPr' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          styleDepth != null &&
          reader.depth == styleDepth + 1 &&
          !reader.isEmptyElement) {
        tablePropertiesDepth = reader.depth;
      } else if (name == 'bidiVisual' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          tablePropertiesDepth != null &&
          reader.depth == tablePropertiesDepth + 1) {
        current.rightToLeft = WordDeserializer._onOff(val);
      } else if (name == 'tblCellMar' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          tablePropertiesDepth != null &&
          reader.depth == tablePropertiesDepth + 1) {
        final margin = WordTablePropertyIo.uniformCellMargin(
          XmlDocument.readElement(reader),
        );
        current.cellMargin = current.cellMarginsDeclared ? null : margin;
        current.cellMarginsDeclared = true;
      } else if (name == 'basedOn' &&
          reader.namespaceUri == OfficeNamespaces.w &&
          styleDepth != null &&
          reader.depth == styleDepth + 1) {
        basedOn = basedOnDeclared ? null : val;
        basedOnDeclared = true;
      } else if (name == 'tblStylePr' && !reader.isEmptyElement) {
        region = reader.getAttribute('type', namespaceUri: OfficeNamespaces.w);
      } else if (name == 'tblBorders' && region == null) {
        current.bordersDeclared = true;
        inBorders = !reader.isEmptyElement;
      } else if (inBorders) {
        if (val == null || val == 'nil' || val == 'none') {
          continue;
        }
        if (current.borderColor == null) {
          final String? color = reader.getAttribute(
            'color',
            namespaceUri: OfficeNamespaces.w,
          );
          final int? sz = int.tryParse(
            reader.getAttribute('sz', namespaceUri: OfficeNamespaces.w) ?? '',
          );
          current
            ..borderColor =
                color == null || color.isEmpty || color.toLowerCase() == 'auto'
                ? '000000'
                : color
            ..borderWidth = sz == null ? 0.5 : sz / 8.0;
        }
      } else if (name == 'shd' &&
          (region == 'firstRow' || region == 'band1Horz')) {
        final String? fill = reader.getAttribute(
          'fill',
          namespaceUri: OfficeNamespaces.w,
        );
        if (fill == null || fill.isEmpty || fill.toLowerCase() == 'auto') {
          continue;
        }
        if (region == 'firstRow') {
          current.firstRowFill = fill;
        } else {
          current.band1Fill = fill;
        }
      }
    }
    return out;
  }
}

class _NumberingLevel {
  const _NumberingLevel({
    required this.fmt,
    required this.text,
    required this.start,
    this.left = 0,
    this.hanging = 0,
    this.suffix,
  });

  /// fmt API.
  final String fmt;

  /// text API.
  final String text;

  /// start API.
  final int start;

  /// left API.
  final double left;

  /// hanging API.
  final double hanging;

  final String? suffix;

  /// isBullet API.
  bool get isBullet =>
      fmt == 'bullet' || (text.isNotEmpty && text.codeUnitAt(0) >= 0xF000);

  /// bulletLabel API.
  String bulletLabel() {
    final String raw = text.trim();
    if (raw.isEmpty) {
      return '• ';
    }
    final int cu = raw.codeUnitAt(0);
    // Symbol / Wingdings private-use → solid bullet.
    if (cu >= 0xF000) {
      return '• ';
    }
    // Word often uses literal "o" with a Courier face for a hollow bullet.
    if (raw == 'o') {
      return '◦ ';
    }
    return '$raw ';
  }

  /// decimalLabel API.
  String decimalLabel(int value) {
    if (text.contains('%1')) {
      return '${text.replaceAll('%1', '$value')} ';
    }
    return '$value. ';
  }

  static String _formatNumber(int number, String format) {
    if (format == 'decimalZero') return '$number'.padLeft(2, '0');
    if ((format == 'upperLetter' || format == 'lowerLetter') && number > 0) {
      var n = number;
      var result = '';
      while (n > 0) {
        n--;
        result = String.fromCharCode(65 + n % 26) + result;
        n ~/= 26;
      }
      return format == 'lowerLetter' ? result.toLowerCase() : result;
    }
    if ((format == 'upperRoman' || format == 'lowerRoman') &&
        number > 0 &&
        number < 4000) {
      var n = number;
      final StringBuffer result = StringBuffer();
      const Map<int, String> digits = <int, String>{
        1000: 'M',
        900: 'CM',
        500: 'D',
        400: 'CD',
        100: 'C',
        90: 'XC',
        50: 'L',
        40: 'XL',
        10: 'X',
        9: 'IX',
        5: 'V',
        4: 'IV',
        1: 'I',
      };
      for (final MapEntry<int, String> digit in digits.entries) {
        while (n >= digit.key) {
          result.write(digit.value);
          n -= digit.key;
        }
      }
      return format == 'lowerRoman'
          ? result.toString().toLowerCase()
          : result.toString();
    }
    return '$number';
  }

  /// Expands `%1`…`%9` using the multilevel [stack] through [ilvl].
  ///
  /// Null when the level prints nothing: an empty `w:lvlText`, or a `none`
  /// format with no literal text (LibreOffice heading outlines).
  String? decimalLabelStack(
    List<int> stack,
    int ilvl, {
    List<String>? formats,
  }) {
    if (text.isEmpty) {
      return null;
    }
    if (fmt == 'none') {
      final String literal = text
          .replaceAll(RegExp('%[1-9]'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      return literal.isEmpty ? null : '$literal ';
    }
    if (!text.contains('%')) {
      return '${stack[ilvl]}. ';
    }
    var out = text;
    for (int i = 0; i <= ilvl; i++) {
      out = out.replaceAll(
        '%${i + 1}',
        _formatNumber(stack[i] < 0 ? 1 : stack[i], formats?[i] ?? fmt),
      );
    }
    for (int i = ilvl + 1; i < 9; i++) {
      out = out.replaceAll('%${i + 1}', '');
    }
    // Collapse separators left by unused deeper placeholders (e.g. "1..").
    out = out.replaceAll(RegExp(r'\.{2,}'), '.');
    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trimRight();
    if (out.isEmpty) {
      return '${stack[ilvl]}. ';
    }
    return out.endsWith(' ') ? out : '$out ';
  }
}

class _NativeMoveRange {
  _NativeMoveRange(this.start);
  final XmlElement start;
  final List<WmlRevision> revisions = [];
}
