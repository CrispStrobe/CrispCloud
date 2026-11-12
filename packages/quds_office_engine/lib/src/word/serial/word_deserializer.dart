import 'dart:typed_data';

import '../../office/office_document_properties.dart';
import '../../opc/ole/embedded_part.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../math/omml_document.dart';
import '../math/omml_io.dart';
import '../model/wml_document.dart';
import '../model/word_link.dart';
import '../model/word_notes.dart';
import '../model/word_revision.dart';
import '../model/word_styles.dart';
import '../model/word_toc.dart';
import '../properties/wml_properties.dart';
import 'word_comment_io.dart';
import 'word_drawing_io.dart';
import 'word_markup_compatibility.dart';
import 'word_opaque_io.dart';
import 'word_property_io.dart';
import 'word_section_io.dart';
import 'word_serializer.dart';
import 'word_table_property_io.dart';

part 'word_style_cascade.dart';

/// Reads a `.docx` OPC package into a [WmlDocument] tree.
class WordDeserializer {
  final List<WmlEquation> _pendingEquations = <WmlEquation>[];
  final List<WmlVisual> _pendingVisuals = <WmlVisual>[];
  final List<WmlFrame> _pendingFrames = <WmlFrame>[];
  final List<int> _openCommentIds = <int>[];
  OpcPackage? _package;
  String? _docUri;
  WmlSection? _pendingParagraphSectPr;
  WmlDocument? _document;
  WmlNote? _readingNote;
  bool _noteMarkCaptured = false;
  final Set<WmlTable> _tablesWithOwnBorders = Set<WmlTable>.identity();
  final Set<WmlRunProps> _notBold = Set<WmlRunProps>.identity();
  final Set<WmlRunProps> _notItalic = Set<WmlRunProps>.identity();
  final Map<WmlTable, _TableLook> _tableLooks =
      Map<WmlTable, _TableLook>.identity();

  /// read API.
  WmlDocument read(OpcPackage package) {
    // A reader may be reused after a truncated document or a parse failure.
    // Story state belongs to one document and must not contaminate the next.
    _pendingEquations.clear();
    _pendingVisuals.clear();
    _pendingFrames.clear();
    _openCommentIds.clear();
    _tablesWithOwnBorders.clear();
    _tableLooks.clear();
    _notBold.clear();
    _notItalic.clear();
    _pendingParagraphSectPr = null;
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
      if (reader.localName == 'p' &&
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
        section.blocks.addAll(_readSdt(reader, package, docUri));
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
    if (section.blocks.isNotEmpty || document.sections.isEmpty) {
      document.sections.add(section);
    }
    _ensureHeadersFooters(document, package, docUri);
    _readNotes(document, package, docUri);
    _readStyles(document, package, docUri);
    _applyDocumentStyles(document);
    _notBold.clear();
    _notItalic.clear();
    _applyTableStyles(document, package, docUri);
    _applyNumbering(document, package, docUri);
    _collapseTocFields(document);
    _readComments(document, package, docUri);
    _readCommentsExtended(document, package, docUri);
    _readWatermark(document, package);
    _readCitations(document, package);
    _readSettingsFlags(document, package, docUri);
    return document;
  }

  /// readBytes API.
  WmlDocument readBytes(Uint8List bytes, {String? password}) =>
      read(OpcPackage.openBytes(bytes, password: password));

  List<WmlBlock> _readSdt(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    var tag = '';
    final List<WmlBlock> blocks = <WmlBlock>[];
    if (reader.isEmptyElement) {
      return blocks;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tag') {
        tag =
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? tag;
      } else if (reader.localName == 'p' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        _addParagraph(blocks, _readParagraph(reader, package, docUri));
      } else if (reader.localName == 'tbl' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.add(_readTable(reader, package, docUri));
      } else if (reader.localName == 'sdt' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.addAll(_readSdt(reader, package, docUri));
      } else if (reader.localName == 'altChunk' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        blocks.add(WordOpaqueIo.read(reader, package, docUri));
      }
    }
    if (tag.startsWith('qudsFrame:')) {
      return <WmlBlock>[_frameFromTag(tag, blocks)];
    }
    return blocks;
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
      wrap: wrapName == 'square' ? WmlFrameWrap.square : WmlFrameWrap.none,
      fillColor: colorAt(6),
      strokeColor: colorAt(7),
      blocks: blocks,
    );
  }

  void _addParagraph(List<WmlBlock> blocks, WmlParagraph paragraph) {
    final bool mathOnly =
        paragraph.inlines.isEmpty && _pendingEquations.isNotEmpty;
    final bool drawingHost =
        paragraph.text.trim().isEmpty &&
        (_pendingVisuals.isNotEmpty || _pendingFrames.isNotEmpty);
    if (!mathOnly && !drawingHost) {
      blocks.add(paragraph);
    }
    _flushPending(blocks);
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
    final WmlBlock? block = WordDrawingIo.readBlock(
      reader,
      package,
      docUri,
      readParagraph: (XmlPullReader inner) =>
          _readParagraph(inner, package, docUri),
    );
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
    if (reader.isEmptyElement) {
      return paragraph;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'pPr') {
        _readPPr(reader, paragraph.properties);
      } else if (reader.localName == 'r') {
        paragraph.inlines.addAll(
          _readRunInlines(reader, package, docUri, paragraph),
        );
      } else if (reader.localName == 'ins' || reader.localName == 'del') {
        _readTracked(reader, package, docUri, paragraph);
      } else if (reader.localName == 'hyperlink') {
        paragraph.inlines.addAll(
          _readHyperlinkInlines(reader, package, docUri, paragraph),
        );
      } else if (reader.localName == 'fldSimple' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        paragraph.inlines.addAll(_readSimpleField(reader, package, docUri));
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
      } else if (reader.localName == 'bookmarkStart') {
        paragraph.properties.bookmarkName ??= reader.getAttribute(
          'name',
          namespaceUri: OfficeNamespaces.w,
        );
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
    return paragraph;
  }

  List<WmlInline> _readSimpleField(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final XmlElement source = XmlDocument.readElement(reader);
    final String? instruction = source.getAttribute(
      'instr',
      namespaceUri: OfficeNamespaces.w,
    );
    final XmlPullReader inner = WordMarkupCompatibilityReader(
      XmlDocument(root: source).toXmlString(declaration: false),
    )..next();
    final WmlParagraph result = _readParagraph(inner, package, docUri);
    final List<XmlElement> children = source.childElements.toList();
    final bool singleRun =
        children.isEmpty ||
        (children.length == 1 &&
            children.single.localName == 'r' &&
            children.single.namespaceUri == OfficeNamespaces.w);
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

  List<WmlInline> _readRunInlines(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final List<WmlInline> inlines = <WmlInline>[];
    final WmlRun run = WmlRun()..properties.sourcePropertiesXml = '';
    if (reader.isEmptyElement) {
      return inlines;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'rPr') {
        _readRPr(reader, run.properties);
      } else if (reader.localName == 't' || reader.localName == 'delText') {
        final String text = _elementText(reader);
        if (paragraph.properties.pageNumberField &&
            _cachedPageResult.hasMatch(text)) {
          continue;
        }
        run.text += text;
      } else if (reader.localName == 'footnoteReference' ||
          reader.localName == 'endnoteReference') {
        final int id =
            int.tryParse(
              reader.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
            ) ??
            1;
        run.noteRefId = id;
        run.noteRefEndnote = reader.localName == 'endnoteReference';
        if (run.text.isEmpty) {
          run.text = '$id';
        }
        // A footnote/endnote mark is superscript by definition. Word stores
        // this in the FootnoteReference character style, which the importer
        // does not resolve, so apply it directly or the mark renders as a
        // normal baseline digit.
        run.properties.vertAlign = WmlVertAlign.superscript;
        paragraph.properties.noteId = id;
        paragraph.properties.endnoteRef = run.noteRefEndnote;
      } else if (reader.localName == 'footnoteRef' ||
          reader.localName == 'endnoteRef') {
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
      } else if (reader.localName == 'fldChar') {
        final String? type = reader.getAttribute(
          'fldCharType',
          namespaceUri: OfficeNamespaces.w,
        );
        if (type == 'begin') {
          paragraph.properties.fieldBegin = true;
        } else if (type == 'end') {
          paragraph.properties.fieldEnd = true;
        }
      } else if (reader.localName == 'commentReference') {
        continue;
      } else if (reader.localName == 'tab') {
        run.text += '\t';
      } else if (reader.localName == 'br' || reader.localName == 'cr') {
        final String? type = reader.getAttribute(
          'type',
          namespaceUri: OfficeNamespaces.w,
        );
        if (type == 'page' || type == 'column') {
          if (run.text.isNotEmpty) {
            inlines.add(
              WmlRun(
                text: run.text,
                properties: run.properties.copy(),
                commentIds: List<int>.of(_openCommentIds),
              ),
            );
            run.text = '';
          }
          inlines.add(
            WmlBreak(type == 'page' ? WmlBreakType.page : WmlBreakType.column),
          );
        } else {
          run.text += '\n';
        }
      } else if (reader.localName == 'object' ||
          reader.localName == 'drawing' ||
          reader.localName == 'OLEObject') {
        if (run.text.isNotEmpty) {
          inlines.add(WmlRun(text: run.text, properties: run.properties));
          run.text = '';
        }
        if (!_takeDrawing(reader, package, docUri)) {
          final WmlObject? obj = _readObject(reader, package, docUri);
          if (obj != null) {
            inlines.add(obj);
          }
        }
      }
    }
    if (run.text.isNotEmpty || run.noteRefId != null) {
      run.commentIds.addAll(_openCommentIds);
      inlines.add(run);
    }
    return inlines;
  }

  void _readTracked(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final bool deleted = reader.localName == 'del';
    final String author =
        reader.getAttribute('author', namespaceUri: OfficeNamespaces.w) ??
        'Quds Office';
    final String date =
        reader.getAttribute('date', namespaceUri: OfficeNamespaces.w) ?? '';
    final int start = paragraph.text.length;
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'r') {
        paragraph.inlines.addAll(
          _readRunInlines(reader, package, docUri, paragraph),
        );
      }
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
      kind: deleted ? WmlRevisionKind.delete : WmlRevisionKind.insert,
      paragraphIndex: document.paragraphs.length,
      start: start,
      end: start + text.length,
      text: text,
      author: author,
    );
    if (date.isNotEmpty) {
      revision.dateIso = date;
    }
  }

  void _readPPr(XmlPullReader reader, WmlParagraphProps props) {
    final XmlElement node = XmlDocument.readElement(reader);
    props.sourcePropertiesXml = XmlDocument(
      root: node,
    ).toXmlString(declaration: false);
    final XmlPullReader source = WordMarkupCompatibilityReader(
      props.sourcePropertiesXml!,
    )..next();
    _parsePPr(source, props);
  }

  void _parsePPr(XmlPullReader reader, WmlParagraphProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      switch (reader.localName) {
        case 'jc':
          props.explicitJustification = true;
          props.justification = _jc(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
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
            props.spacingBefore = twipsToPoints(int.parse(before));
            props.explicitSpacingBefore = true;
          }
          if (after != null) {
            props.spacingAfter = twipsToPoints(int.parse(after));
            props.explicitSpacingAfter = true;
          }
          if (line != null) {
            props.explicitLineSpacing = true;
            if (rule == 'exact' || rule == 'atLeast') {
              props.lineSpacing = twipsToPoints(int.parse(line));
              props.lineSpacingRule = rule == 'exact'
                  ? WmlLineSpacingRule.exact
                  : WmlLineSpacingRule.atLeast;
            } else {
              props.lineSpacing = int.parse(line) / 240.0;
              props.lineSpacingRule = WmlLineSpacingRule.auto;
            }
          }
        case 'ind':
          props.explicitIndent = true;
          props.indent = WmlIndent(
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
        case 'pageBreakBefore':
          props.pageBreakBefore = _onOff(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'numPr':
          _readNumPr(reader, props);
        case 'shd':
          props.shadingFill = reader.getAttribute(
            'fill',
            namespaceUri: OfficeNamespaces.w,
          );
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
    document.sections.add(section);
    return WmlSection();
  }

  List<WmlInline> _readHyperlinkInlines(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
    WmlParagraph paragraph,
  ) {
    final WmlHyperlink? link = _hyperlinkFrom(reader, package, docUri);
    final List<WmlInline> inlines = <WmlInline>[];
    if (reader.isEmptyElement) {
      return inlines;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'r') {
        for (final WmlInline inline in _readRunInlines(
          reader,
          package,
          docUri,
          paragraph,
        )) {
          if (inline is WmlRun) {
            inline.hyperlink = link;
            if (link != null && inline.properties.color == '000000') {
              WordLink.applyLook(inline);
            }
          }
          inlines.add(inline);
        }
      } else if (reader.localName == 'hyperlink') {
        inlines.addAll(
          _readHyperlinkInlines(reader, package, docUri, paragraph),
        );
      }
    }
    return inlines;
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
    for (final WmlSection section in document.sections) {
      final List<WmlBlock> collapsed = <WmlBlock>[];
      WmlToc? open;
      for (final WmlBlock block in section.blocks) {
        if (block is! WmlParagraph) {
          if (open != null) {
            collapsed.add(open);
            open = null;
          }
          collapsed.add(block);
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
            block.properties.fieldEnd;
        if (open == null && (tocInstr || tocStyle || tocHeading)) {
          final (int min, int max) = WordToc.rangeFromInstruction(
            block.properties.fieldInstruction,
          );
          open = WmlToc(minLevel: min, maxLevel: max);
          WordToc.applyPageNumberInstruction(
            open,
            block.properties.fieldInstruction,
          );
          WordToc.absorbResult(open, block);
          if (block.properties.fieldEnd) {
            collapsed.add(open);
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
          WordToc.absorbResult(open, block);
          if (block.properties.fieldEnd) {
            collapsed.add(open);
            open = null;
          }
          continue;
        }
        if (open != null) {
          collapsed.add(open);
          open = null;
        }
        collapsed.add(block);
      }
      if (open != null) {
        collapsed.add(open);
      }
      section.blocks
        ..clear()
        ..addAll(collapsed);
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
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'tab') {
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
        props.tabs.add(
          WmlTabStop(
            position: pos == null ? 0 : twipsToPoints(int.parse(pos)),
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
    }
  }

  void _readRPr(XmlPullReader reader, WmlRunProps props) {
    final XmlElement node = XmlDocument.readElement(reader);
    props.sourcePropertiesXml = XmlDocument(
      root: node,
    ).toXmlString(declaration: false);
    final XmlPullReader source = WordMarkupCompatibilityReader(
      props.sourcePropertiesXml!,
    )..next();
    _parseRPr(source, props);
  }

  void _parseRPr(XmlPullReader reader, WmlRunProps props) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      props.explicitProperties.add(reader.localName);
      switch (reader.localName) {
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
        case 'color':
          props.color =
              reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ??
              props.color;
        case 'highlight':
          props.highlight = WmlHighlight.toRgb(
            reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          );
        case 'sz':
        case 'szCs':
          final String? sz = reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          );
          if (sz != null) {
            props.fontSizeHalfPoints = int.parse(sz);
          }
        case 'u':
          props.underline = switch (reader.getAttribute(
            'val',
            namespaceUri: OfficeNamespaces.w,
          )) {
            'double' => WmlUnderline.double,
            'dotted' => WmlUnderline.dotted,
            'wave' => WmlUnderline.wavy,
            'none' => WmlUnderline.none,
            _ => WmlUnderline.single,
          };
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
  }

  WmlTable _readTable(XmlPullReader reader, OpcPackage package, String docUri) {
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
      if (reader.localName == 'tblPr') {
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
        table.grid.add(w == null ? 100 : twipsToPoints(int.parse(w)));
      } else if (reader.localName == 'tr') {
        table.rows.add(_readRow(reader, package, docUri, table));
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
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.depth != depth + 1) {
        continue;
      }
      if (reader.localName == 'tblStyle') {
        table.properties.styleId = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
      } else if (reader.localName == 'tblBorders') {
        _tablesWithOwnBorders.add(table);
        _readTblBorders(reader, table.properties);
      } else if (reader.localName == 'tblLook') {
        _tableLooks[table] = _TableLook.read(reader);
      } else if (reader.localName == 'bidiVisual') {
        table.properties.rightToLeft = _onOff(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      } else if (reader.localName == 'jc') {
        table.properties.alignment = _jc(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        );
      }
    }
  }

  void _readTblBorders(XmlPullReader reader, WmlTableProps props) {
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
      }
      if (color != null && color.isNotEmpty && color.toLowerCase() != 'auto') {
        props.borderColor = color;
      }
      props.borders = true;
    }
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

    void applyTo(WmlTable table) {
      final String? styleId = table.properties.styleId;
      final _TableStyle? style = styleId == null
          ? null
          : _TableStyle.resolve(styleId, styles);
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
        for (final WmlBlock block in cell.blocks) {
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
      if (reader.localName == 'cantSplit') {
        row.cantSplit = true;
      } else if (reader.localName == 'trHeight') {
        final String? raw = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
        if (raw != null) {
          row.height = twipsToPoints(int.parse(raw));
        }
      } else if (reader.localName == 'tc') {
        row.cells.add(_readCell(reader, package, docUri));
      }
    }
    return row;
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
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'gridSpan') {
        cell.gridSpan = int.parse(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w) ?? '1',
        );
      } else if (reader.localName == 'vMerge') {
        final String? val = reader.getAttribute(
          'val',
          namespaceUri: OfficeNamespaces.w,
        );
        cell.vMerge = val == 'restart' ? WmlVMerge.restart : WmlVMerge.cont;
      } else if (reader.localName == 'tcBorders') {
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
      } else if (reader.localName == 'altChunk' &&
          reader.namespaceUri == OfficeNamespaces.w) {
        cell.blocks.add(WordOpaqueIo.read(reader, package, docUri));
      }
    }
    return cell;
  }

  void _readTcBorders(XmlPullReader reader, WmlTableCell cell) {
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
      final bool? edge = switch (val) {
        'nil' || 'none' => false,
        null => null,
        _ => true,
      };
      switch (reader.localName) {
        case 'top':
          cell.borderTop = edge;
        case 'bottom':
          cell.borderBottom = edge;
        case 'left':
          cell.borderLeft = edge;
        case 'right':
          cell.borderRight = edge;
      }
    }
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
          section.columnCount = int.parse(
            reader.getAttribute('num', namespaceUri: OfficeNamespaces.w) ?? '1',
          );
          final String? space = reader.getAttribute(
            'space',
            namespaceUri: OfficeNamespaces.w,
          );
          if (space != null) {
            section.columnSpace = twipsToPoints(int.parse(space));
          }
          section.columnSep =
              reader.getAttribute('sep', namespaceUri: OfficeNamespaces.w) ==
              '1';
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
          headerRel != null) {
        section.header.addAll(
          _readStoryByRid(
            package,
            docUri,
            headerRel.id,
            visualsOut: section.headerVisuals,
          ),
        );
      }
      if (section.footer.isEmpty &&
          section.footerVisuals.isEmpty &&
          footerRel != null) {
        section.footer.addAll(
          _readStoryByRid(
            package,
            docUri,
            footerRel.id,
            visualsOut: section.footerVisuals,
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
    if (levels.isEmpty) {
      for (final WmlParagraph paragraph in document.paragraphs) {
        final int? numId = paragraph.properties.numId;
        if (numId != null && numId != 0) {
          paragraph.properties.listLabel ??= '• ';
        }
      }
      return;
    }
    final Map<String, List<int>> counters = <String, List<int>>{};
    for (final WmlParagraph paragraph in document.paragraphs) {
      final int? numId = paragraph.properties.numId;
      // `w:numId="0"` removes the paragraph from any list.
      if (numId == null || numId == 0) {
        continue;
      }
      final int ilvl = paragraph.properties.ilvl.clamp(0, 8);
      final _NumberingLevel? level =
          levels[_levelKey(numId, ilvl)] ?? levels[_levelKey(numId, 0)];
      if (level == null) {
        paragraph.properties.listLabel ??= '• ';
        continue;
      }
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
    final StringBuffer buffer = StringBuffer();
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
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
      final String? color = reader.getAttribute(
        'color',
        namespaceUri: OfficeNamespaces.w,
      );
      if (color != null && color.isNotEmpty) {
        props.borderColor = color;
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

  void _readCitations(WmlDocument document, OpcPackage package) {
    final PackagePart? part =
        package.getPart('/customXml/sources.xml') ??
        package.getPart('/customXml/item1.xml');
    if (part == null) {
      return;
    }
    final XmlPullReader reader = WordMarkupCompatibilityReader(part.readText());
    String tag = '';
    String author = '';
    String title = '';
    String year = '';
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'Source') {
        tag = '';
        author = '';
        title = '';
        year = '';
      } else if (reader.eventType == XmlEventType.startElement &&
          (reader.localName == 'Tag' ||
              reader.localName == 'Author' ||
              reader.localName == 'Title' ||
              reader.localName == 'Year')) {
        final String name = reader.localName;
        final String text = _elementText(reader);
        switch (name) {
          case 'Tag':
            tag = text;
          case 'Author':
            author = text;
          case 'Title':
            title = text;
          case 'Year':
            year = text;
        }
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'Source' &&
          tag.isNotEmpty) {
        document.citations.add(
          WmlCitation(tag: tag, author: author, title: title, year: year),
        );
      }
    }
  }

  void _readNotes(WmlDocument document, OpcPackage package, String docUri) {
    _readNotesPart(
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
  }

  void _readNotesPart(
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
      return;
    }
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
      // Word always ships separator / continuationSeparator notes (ids -1, 0).
      // They are chrome, not document content — skip them.
      if (noteType == 'separator' ||
          noteType == 'continuationSeparator' ||
          noteType == 'continuationNotice') {
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
        addReferenceSpace: false,
        referencePropertiesXml: '',
      );
      _readingNote = note;
      _noteMarkCaptured = false;
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
      _readingNote = null;
      if (note.blocks.isEmpty) {
        note.text = '';
      }
      bucket.add(note);
    }
  }

  void _readStyles(WmlDocument document, OpcPackage package, String docUri) {
    final RelationshipCollection rels = package.relationshipsFor(docUri);
    final PackageRelationship? rel = rels.firstByType(RelationshipTypes.styles);
    final PackagePart? part = rel == null
        ? package.getPart('/word/styles.xml')
        : package.getPart(rels.resolve(rel));
    if (part == null) {
      return;
    }
    document.styles.clear();
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
    WmlJustification justification = WmlJustification.left;
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
        justification = WmlJustification.left;
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
        justification = _jc(
          reader.getAttribute('val', namespaceUri: OfficeNamespaces.w),
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
          spacingBefore = twipsToPoints(int.parse(before));
        }
        if (after != null) {
          spacingAfter = twipsToPoints(int.parse(after));
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
          justification: justification,
          headingLevel: headingLevel,
          font: font,
          csFont: csFont,
          basedOn: basedOn,
          numId: numId,
          ilvl: ilvl,
          indent: indent,
        );
        document.styles.add(style);
        document.importedStyles[style.id] = style;
        id = null;
      }
    }
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
    _readStyles(document, package, uri);
    _applyDocumentStyles(document);
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
    final String xml = part.readText();
    if (xml.contains('trackRevisions')) {
      document.trackRevisions = !xml.contains('w:val="0"');
    }
    if (xml.contains('documentProtection')) {
      document.restrictEditing = true;
    }
    if (xml.contains('evenAndOddHeaders')) {
      for (final WmlSection section in document.sections) {
        section.differentOddEven = true;
      }
    }
  }

  static bool _isPageField(String instr) {
    final String upper = instr.toUpperCase();
    return RegExp(r'(^|[^A-Z])PAGE([^A-Z]|$)').hasMatch(upper);
  }

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

  static WmlJustification _jc(String? val) {
    return switch (val) {
      'center' => WmlJustification.center,
      'right' => WmlJustification.right,
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
    return twipsToPoints(int.parse(raw));
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
          'Quds Office';
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

  factory _TableLook.read(XmlPullReader reader) {
    final String? val = reader.getAttribute(
      'val',
      namespaceUri: OfficeNamespaces.w,
    );
    final int mask = int.tryParse(val ?? '', radix: 16) ?? 0x04A0;
    bool flag(String name, bool fallback) {
      final String? raw = reader.getAttribute(
        name,
        namespaceUri: OfficeNamespaces.w,
      );
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
    var isTable = false;
    _TableStyle? current;
    String? region;
    var inBorders = false;
    while (reader.next()) {
      final String name = reader.localName;
      if (reader.eventType == XmlEventType.endElement) {
        if (name == 'tblStylePr') {
          region = null;
        } else if (name == 'tblBorders') {
          inBorders = false;
        } else if (name == 'style') {
          if (isTable && id != null && current != null) {
            out[id] = current..basedOn = basedOn;
          }
          id = null;
          current = null;
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
      if (name == 'style') {
        isTable =
            reader.getAttribute('type', namespaceUri: OfficeNamespaces.w) ==
            'table';
        id = reader.getAttribute('styleId', namespaceUri: OfficeNamespaces.w);
        basedOn = null;
        region = null;
        inBorders = false;
        current = _TableStyle();
      } else if (current == null || !isTable) {
        continue;
      } else if (name == 'basedOn') {
        basedOn = val;
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
