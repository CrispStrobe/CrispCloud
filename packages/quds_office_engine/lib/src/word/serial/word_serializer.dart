import 'dart:convert';
import 'dart:typed_data';

import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_writer.dart';
import '../math/omml_io.dart';
import '../model/wml_clone.dart';
import '../model/wml_document.dart';
import '../model/word_bookmarks.dart';
import '../model/word_content_controls.dart';
import '../model/word_notes.dart';
import '../model/word_revision.dart';
import '../model/word_styles.dart';
import '../model/word_toc.dart';
import '../model/word_tree.dart';
import '../properties/wml_properties.dart';
import 'word_bibliography_io.dart';
import 'word_bookmark_io.dart';
import 'word_comment_io.dart';
import 'word_content_control_io.dart';
import 'word_drawing_io.dart';
import 'word_frame_io.dart';
import 'word_numbering_io.dart';
import 'word_opaque_io.dart';
import 'word_property_io.dart';
import 'word_section_io.dart';
import 'word_settings_io.dart';
import 'word_table_property_io.dart';

/// Writes a [WmlDocument] back to a `.docx` OPC package.
class WordSerializer {
  /// Direct run properties, excluding unchanged inherited formatting.
  String runPropertiesXml(WmlRunProps properties) {
    final writer = XmlWriter();
    _writeRPr(writer, properties);
    return writer.toXml();
  }

  /// Direct paragraph properties, excluding unchanged inherited formatting.
  String paragraphPropertiesXml(WmlParagraphProps properties) {
    final writer = XmlWriter();
    _writePPr(writer, properties);
    return writer.toXml();
  }

  var _docPrId = 1;
  var _hfPart = 1;
  OpcPackage? _package;
  String _mainPartUri = '/word/document.xml';
  String _activePartUri = '/word/document.xml';
  final Set<int> _openComments = <int>{};
  Map<WmlSection, _HeaderFooterIds> _headerFooterIds =
      <WmlSection, _HeaderFooterIds>{};
  WmlDocument? _document;
  late WordSectionRevisionIds _sectionRevisionIds;
  final Map<WmlParagraph, int> _restartNumberingIds =
      Map<WmlParagraph, int>.identity();
  Map<String, String> _generatedBookmarkIds = <String, String>{};

  /// writeBytes API.
  Uint8List writeBytes(WmlDocument document, {String? password}) {
    return write(document).save(password: password);
  }

  /// write API.
  OpcPackage write(WmlDocument document) {
    _generatedBookmarkIds = WordBookmarks.generatedIds(document);
    WordRevisions.validate(document);
    WordContentControls.validate(document);
    for (final blocks in [
      for (final section in document.sections) section.blocks,
      for (final note in [...document.footnotes, ...document.endnotes])
        note.blocks,
    ]) {
      for (final table in WordTree.descendants(blocks).whereType<WmlTable>()) {
        for (final row in table.rows) {
          for (final cell in row.cells) {
            final width = cell.width;
            if (width != null && (!width.isFinite || width < 0)) {
              throw ArgumentError(
                'Table cell width must be finite and nonnegative',
              );
            }
          }
        }
      }
    }
    final OpcPackage package =
        document.package ?? OpcPackage.create(OpcPackageKind.word);
    final PackageRelationship? office = package.packageRelationships
        .firstByType(RelationshipTypes.officeDocument);
    if (office?.targetMode == RelationshipTargetMode.external) {
      throw const FormatException(
        'The Word main part must be inside its package',
      );
    }
    _mainPartUri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    if (package.getPart(_mainPartUri) == null) {
      package.createPart(
        _mainPartUri,
        OfficeContentTypes.wordMain,
        utf8.encode('<w:document xmlns:w="${OfficeNamespaces.w}"/>'),
      );
    }
    if (office == null) {
      package.packageRelationships.add(
        type: RelationshipTypes.officeDocument,
        target: _mainPartUri.substring(1),
      );
    }
    _package = package;
    _activePartUri = _mainPartUri;
    _docPrId = 1;
    _openComments.clear();
    _document = document;
    _sectionRevisionIds = WordSectionRevisionIds(document.sections);
    _syncNumbering(package);
    _restartNumberingIds
      ..clear()
      ..addAll(
        WordNumberingIo.prepareRestarts(
          document,
          package.getPart(
            _relatedPartUri(
              package,
              RelationshipTypes.numbering,
              'numbering.xml',
            ),
          )!,
        ),
      );
    _headerFooterIds = _syncHeadersFooters(document, package);
    _syncEmbeddings(document, package);
    final Map<OfficeVisual, String> imageIds = _syncImages(document, package);
    package.getPart(_mainPartUri)!.writeText(_documentXml(document, imageIds));
    _syncComments(document, package);
    _syncWatermark(document, package);
    _syncStyles(document, package);
    _syncNotes(document, package);
    WordBibliographyIo.write(document, package, _mainPartUri);
    _syncSettings(document, package);
    document.properties.writeToPackage(package);
    document.package = package;
    return package;
  }

  void _syncEmbeddings(WmlDocument document, OpcPackage package) {
    var oleIndex = 1;
    for (final WmlParagraph paragraph in document.paragraphs) {
      for (final WmlInline inline in paragraph.inlines) {
        if (inline is! WmlObject || inline.embedded == null) {
          continue;
        }
        final String uri = '/word/embeddings/oleObject$oleIndex.bin';
        oleIndex++;
        final Uint8List bin = inline.embedded!.pack();
        if (package.getPart(uri) == null) {
          package.createPart(uri, OfficeContentTypes.oleObject, bin);
        } else {
          package.getPart(uri)!.writeBytes(bin);
        }
        final String target = OpcUris.relativize(_mainPartUri, uri);
        final existing = package
            .relationshipsFor(_mainPartUri)
            .items
            .where((r) => r.target == target);
        if (existing.isEmpty) {
          inline.relationshipId = package
              .relationshipsFor(_mainPartUri)
              .add(type: RelationshipTypes.oleObject, target: target)
              .id;
        } else {
          inline.relationshipId = existing.first.id;
        }
      }
    }
  }

  Map<OfficeVisual, String> _syncImages(
    WmlDocument document,
    OpcPackage package,
  ) {
    return WordDrawingIo.syncVisuals(
      document.visuals.map((WmlVisual wrap) => wrap.visual),
      package,
      partUri: _mainPartUri,
    );
  }

  String _documentXml(
    WmlDocument document,
    Map<OfficeVisual, String> imageIds,
  ) {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeNamespace('o', OfficeNamespaces.o);
    w.writeNamespace('m', OfficeNamespaces.m);
    w.writeNamespace('wp', OfficeNamespaces.wp);
    w.writeNamespace('a', OfficeNamespaces.a);
    w.writeNamespace('pic', OfficeNamespaces.pic);
    w.writeNamespace('c', OfficeNamespaces.c);
    w.writeNamespace('mc', OfficeNamespaces.mc);
    w.writeNamespace('v', OfficeNamespaces.v);
    w.writeNamespace('wps', OfficeNamespaces.wps);
    w.writeAttribute('mc:Ignorable', 'wps');
    w.writeStartElement('body', prefix: 'w');
    final List<({WmlSection section, _ColumnSlice slice, bool last})> writes =
        <({WmlSection section, _ColumnSlice slice, bool last})>[];
    for (int i = 0; i < document.sections.length; i++) {
      final WmlSection section = document.sections[i];
      final List<_ColumnSlice> slices = _columnSlices(section);
      for (int s = 0; s < slices.length; s++) {
        writes.add((
          section: section,
          slice: slices[s],
          last: i == document.sections.length - 1 && s == slices.length - 1,
        ));
      }
    }
    for (final ({WmlSection section, _ColumnSlice slice, bool last}) item
        in writes) {
      final int savedCols = item.section.columnCount;
      final WmlSectionBreakKind savedBreak = item.section.breakKind;
      item.section.columnCount = item.slice.columnCount;
      item.section.breakKind = item.slice.breakKind;
      for (int b = 0; b < item.slice.blocks.length; b++) {
        final WmlBlock block = item.slice.blocks[b];
        final bool lastBlock = b == item.slice.blocks.length - 1;
        if (!item.last && lastBlock && block is WmlParagraph) {
          _writeParagraph(w, block, sectionBreak: item.section);
        } else {
          _writeBlock(w, block, imageIds);
        }
      }
      if (item.last) {
        _writeSectPr(w, item.section);
      } else if (item.slice.blocks.isEmpty ||
          item.slice.blocks.last is! WmlParagraph) {
        _writeParagraph(w, WmlParagraph(), sectionBreak: item.section);
      }
      item.section.columnCount = savedCols;
      item.section.breakKind = savedBreak;
    }
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  void _writeBlock(
    XmlWriter w,
    WmlBlock block,
    Map<OfficeVisual, String> imageIds,
  ) {
    switch (block) {
      case WmlContentControlBlock():
        final shell = WordContentControlIo.start(
          w,
          block.control,
          _package!,
          _activePartUri,
        );
        for (final child in block.blocks) {
          _writeBlock(w, child, imageIds);
        }
        WordContentControlIo.end(w, shell);
      case WmlParagraph():
        _writeParagraph(w, block);
      case WmlTable():
        _writeTable(w, block, imageIds);
      case WmlFrame():
        _writeFrame(w, block, imageIds);
      case WmlVisual():
        final String? rId = imageIds[block.visual];
        if (rId != null) {
          if (block.visual.isChart) {
            WordDrawingIo.writeChart(
              w,
              relationshipId: rId,
              visual: block.visual,
              docPrId: _docPrId++,
            );
          } else {
            WordDrawingIo.writeInline(
              w,
              relationshipId: rId,
              visual: block.visual,
              docPrId: _docPrId++,
            );
          }
        } else {
          _writeParagraph(
            w,
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(
                  text: '[${block.visual.kind.name}] ${block.visual.title}',
                ),
              ],
            ),
          );
        }
      case WmlEquation():
        w.writeStartElement('p', prefix: 'w');
        OmmlIo.writeEquation(w, block.math);
        w.writeEndElement();
      case WmlToc():
        _writeToc(w, block);
      case WmlOpaqueBlock():
        WordOpaqueIo.write(w, block, _package!, _activePartUri);
    }
  }

  void _writeToc(XmlWriter w, WmlToc toc) {
    WordToc.ensureBody(toc);
    final native = WordToc.nativeParagraphs(toc);
    if (native != null) {
      for (final paragraph in native) {
        _writeParagraph(w, paragraph, nativeTocBoundary: true);
      }
      return;
    }
    _writeParagraph(w, toc.titleParagraph);
    w.writeStartElement('p', prefix: 'w');
    _writePPr(w, WmlParagraphProps());
    _writeFieldChar(w, 'begin');
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('instrText', prefix: 'w');
    w.writeAttribute('xml:space', 'preserve');
    final String numberSwitch = !toc.showPageNumbers
        ? ' \\n'
        : toc.omitPageNumbersFromLevel != null &&
              toc.omitPageNumbersThroughLevel != null
        ? ' \\n "${toc.omitPageNumbersFromLevel}-${toc.omitPageNumbersThroughLevel}"'
        : '';
    w.writeText(
      ' TOC \\o "${toc.minLevel}-${toc.maxLevel}" \\h \\z \\u$numberSwitch ',
    );
    w.writeEndElement();
    w.writeEndElement();
    _writeFieldChar(w, 'separate');
    w.writeEndElement();
    final int count = toc.itemParagraphs.length;
    for (int i = 0; i < count; i++) {
      final WmlParagraph para = _copyParagraph(toc.itemParagraphs[i]);
      // An imported cache paragraph can also contain the source TOC's begin
      // and instruction. The live TOC above owns that field; retaining the
      // paragraph instruction would nest a second complete TOC in its cache.
      if (WordToc.isTocInstruction(para.properties.fieldInstruction)) {
        para.properties
          ..fieldInstruction = null
          ..fieldBegin = false
          ..fieldSeparate = false
          ..fieldEnd = false;
      }
      final bool showNumber =
          i < toc.entries.length &&
          toc.showsPageNumberForLevel(toc.entries[i].level);
      if (showNumber &&
          !para.properties.tabs.any(
            (tab) => tab.alignment == WmlTabAlignment.right,
          )) {
        para.properties.tabs.add(
          const WmlTabStop(
            position: 468,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.dot,
          ),
        );
      }
      if (showNumber) {
        para.inlines.add(WmlRun(text: '\t${toc.entries[i].pageNumber}'));
      }
      _writeParagraph(w, para);
    }
    w.writeStartElement('p', prefix: 'w');
    _writeFieldChar(w, 'end');
    w.writeEndElement();
  }

  WmlParagraph _copyParagraph(WmlParagraph source) {
    return WmlParagraph(
      properties: source.properties.copy(),
      inlines: <WmlInline>[
        for (final WmlInline inline in source.inlines)
          if (inline is WmlRun)
            WmlRun(
              text: inline.text,
              properties: inline.properties.copy(),
              hyperlink: inline.hyperlink?.copy(),
              commentIds: List<int>.from(inline.commentIds),
              noteRefId: inline.noteRefId,
              noteRefEndnote: inline.noteRefEndnote,
              fieldInstruction: inline.fieldInstruction,
              fieldLocked: inline.fieldLocked,
              fieldDirty: inline.fieldDirty,
            )
          else
            inline,
      ],
    );
  }

  List<int> _peekCommentIds(WmlParagraph paragraph, int index) {
    for (int i = index; i < paragraph.inlines.length; i++) {
      final WmlInline inline = paragraph.inlines[i];
      if (inline is WmlRun) {
        return inline.commentIds;
      }
    }
    return const <int>[];
  }

  void _openCommentStarts(XmlWriter w, List<int> ids) {
    for (final int id in ids) {
      if (_openComments.add(id)) {
        w.writeEmptyElement(
          'commentRangeStart',
          prefix: 'w',
          attributes: <String, String>{'w:id': '$id'},
        );
      }
    }
  }

  void _closeCommentsNotIn(XmlWriter w, List<int> keep) {
    final List<int> closing = <int>[
      for (final int id in _openComments)
        if (!keep.contains(id)) id,
    ];
    for (final int id in closing) {
      _openComments.remove(id);
      w.writeEmptyElement(
        'commentRangeEnd',
        prefix: 'w',
        attributes: <String, String>{'w:id': '$id'},
      );
      w.writeStartElement('r', prefix: 'w');
      w.writeEmptyElement(
        'commentReference',
        prefix: 'w',
        attributes: <String, String>{'w:id': '$id'},
      );
      w.writeEndElement();
    }
  }

  void _syncComments(WmlDocument document, OpcPackage package) {
    final String uri = _relatedPartUri(
      package,
      RelationshipTypes.comments,
      'comments.xml',
    );
    final String extUri = _relatedPartUri(
      package,
      RelationshipTypes.commentsExtended,
      'commentsExtended.xml',
    );
    final RelationshipCollection rels = package.relationshipsFor(_mainPartUri);
    if (document.comments.isEmpty) {
      WordCommentIo.writePart(
        package,
        uri,
        OfficeContentTypes.wordComments,
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:comments xmlns:w="${OfficeNamespaces.w}"/>',
        create: false,
      );
      WordCommentIo.writePart(
        package,
        extUri,
        OfficeContentTypes.wordCommentsExtended,
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w15:commentsEx xmlns:w15="${OfficeNamespaces.w15}"/>',
        create: false,
      );
      return;
    }
    final Map<int, String> paragraphIds = WordCommentIo.paragraphIds(
      document.comments,
    );
    final Map<OfficeVisual, String> imageIds = WordDrawingIo.syncVisuals(
      <OfficeVisual>[
        for (final WmlComment comment in document.comments)
          for (final WmlVisual visual in comment.visuals) visual.visual,
      ],
      package,
      partUri: uri,
      mediaPrefix: 'commentImage',
    );
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    final String previousPart = _activePartUri;
    _activePartUri = uri;
    w.writeStartElement('comments', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeNamespace('wp', OfficeNamespaces.wp);
    w.writeNamespace('a', OfficeNamespaces.a);
    w.writeNamespace('pic', OfficeNamespaces.pic);
    for (final WmlComment comment in document.comments) {
      w.writeStartElement('comment', prefix: 'w');
      w.writeAttribute('w:id', '${comment.id}');
      w.writeAttribute('w:author', comment.author);
      w.writeAttribute('w:initials', comment.initials);
      if (comment.dateIso.isNotEmpty) {
        w.writeAttribute('w:date', comment.dateIso);
      }
      if (comment.paragraphs.isEmpty && comment.visuals.isEmpty) {
        _writeParagraph(w, WmlParagraph(inlines: <WmlInline>[WmlRun()]));
      }
      for (final WmlParagraph paragraph in comment.paragraphs) {
        _writeParagraph(w, paragraph);
      }
      for (final WmlVisual visual in comment.visuals) {
        _writeBlock(w, visual, imageIds);
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    WordCommentIo.writePart(
      package,
      uri,
      OfficeContentTypes.wordComments,
      WordCommentIo.attachParagraphIds(w.toXml(), paragraphIds),
    );
    if (rels.firstByType(RelationshipTypes.comments) == null) {
      rels.add(
        type: RelationshipTypes.comments,
        target: OpcUris.relativize(_mainPartUri, uri),
      );
    }
    _activePartUri = previousPart;
    _syncCommentsExtended(document, package, rels, paragraphIds);
  }

  void _syncCommentsExtended(
    WmlDocument document,
    OpcPackage package,
    RelationshipCollection rels,
    Map<int, String> paragraphIds,
  ) {
    final String uri = _relatedPartUri(
      package,
      RelationshipTypes.commentsExtended,
      'commentsExtended.xml',
    );
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('commentsEx', prefix: 'w15');
    w.writeNamespace('w15', OfficeNamespaces.w15);
    for (final WmlComment comment in document.comments) {
      w.writeEmptyElement(
        'commentEx',
        prefix: 'w15',
        attributes: <String, String>{
          'w15:paraId': paragraphIds[comment.id]!,
          if (comment.parentId != null)
            'w15:paraIdParent': paragraphIds[comment.parentId]!,
          'w15:done': comment.resolved ? '1' : '0',
        },
      );
    }
    w.writeEndElement();
    WordCommentIo.writePart(
      package,
      uri,
      OfficeContentTypes.wordCommentsExtended,
      w.toXml(),
    );
    if (rels.firstByType(RelationshipTypes.commentsExtended) == null) {
      rels.add(
        type: RelationshipTypes.commentsExtended,
        target: OpcUris.relativize(_mainPartUri, uri),
      );
    }
  }

  void _writePageFieldResult(XmlWriter w, WmlRun inline) {
    final Match? split = RegExp(r'^(\d+)(\s*\|.*)$').firstMatch(inline.text);
    if (split == null) {
      _writeRun(w, inline);
      _writeFieldChar(w, 'end');
      return;
    }
    _writeRun(w, WmlRun(text: split.group(1)!, properties: inline.properties));
    _writeFieldChar(w, 'end');
    _writeRun(w, WmlRun(text: split.group(2)!, properties: inline.properties));
  }

  void _writeFieldChar(XmlWriter w, String type) {
    w.writeStartElement('r', prefix: 'w');
    w.writeEmptyElement(
      'fldChar',
      prefix: 'w',
      attributes: <String, String>{'w:fldCharType': type},
    );
    w.writeEndElement();
  }

  void _writeParagraph(
    XmlWriter w,
    WmlParagraph paragraph, {
    WmlSection? sectionBreak,
    bool noteReference = false,
    bool endnote = false,
    bool addNoteReferenceSpace = true,
    String? noteReferencePropertiesXml,
    bool nativeTocBoundary = false,
  }) {
    final paragraphShells = <XmlElement>[
      for (final control in paragraph.contentControlWrappers)
        WordContentControlIo.start(w, control, _package!, _activePartUri),
    ];
    w.writeStartElement('p', prefix: 'w');
    final int? numberedInstance = _restartNumberingIds[paragraph];
    final WmlParagraphProps properties = numberedInstance == null
        ? paragraph.properties
        : (paragraph.properties.copy()..numId = numberedInstance);
    _writePPr(w, properties, sectionBreak: sectionBreak);
    if (noteReference) {
      // Word displays the automatic note number from this marker in the note
      // body. Without it, Word shows the note text but no number.
      w.writeStartElement('r', prefix: 'w');
      if (noteReferencePropertiesXml == null) {
        w.writeStartElement('rPr', prefix: 'w');
        w.writeStartElement('rStyle', prefix: 'w');
        w.writeAttribute(
          'w:val',
          endnote ? 'EndnoteReference' : 'FootnoteReference',
        );
        w.writeEndElement();
        // Newly created notes have a conventional superscript mark. Imported
        // marks retain their exact source properties, including no rPr.
        w.writeEmptyElement(
          'vertAlign',
          prefix: 'w',
          attributes: <String, String>{'w:val': 'superscript'},
        );
        w.writeEndElement();
      } else if (noteReferencePropertiesXml.isNotEmpty) {
        XmlDocument.parse(noteReferencePropertiesXml).root!.writeTo(w);
      }
      w.writeEmptyElement(endnote ? 'endnoteRef' : 'footnoteRef', prefix: 'w');
      w.writeEndElement();
      // New notes get a separator; imported stories already carry their exact
      // whitespace, including an intentionally absent space after the mark.
      if (addNoteReferenceSpace &&
          (paragraph.text.isEmpty ||
              !RegExp(r'^\s').hasMatch(paragraph.text))) {
        w.writeStartElement('r', prefix: 'w');
        w.writeStartElement('t', prefix: 'w');
        w.writeAttribute('xml:space', 'preserve');
        w.writeText(' ');
        w.writeEndElement();
        w.writeEndElement();
      }
    }
    if (paragraph.properties.columnBreakBefore &&
        !_hasLeadingColumnBreak(paragraph)) {
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('br', prefix: 'w');
      w.writeAttribute('w:type', 'column');
      w.writeEndElement();
      w.writeEndElement();
    }
    final String? bookmark = WordBookmarks.generatedName(paragraph);
    if (bookmark != null && bookmark.isNotEmpty) {
      w.writeEmptyElement(
        'bookmarkStart',
        prefix: 'w',
        attributes: <String, String>{
          'w:id': _generatedBookmarkIds[bookmark]!,
          'w:name': bookmark,
        },
      );
    }
    final String? field = paragraph.properties.fieldInstruction;
    final bool pageField =
        paragraph.properties.pageNumberField &&
        (field == null || field.trim().isEmpty);
    if (nativeTocBoundary && paragraph.properties.fieldBegin) {
      _writeFieldChar(w, 'begin');
    }
    if (field != null && field.trim().isNotEmpty) {
      if (!nativeTocBoundary) _writeFieldChar(w, 'begin');
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('instrText', prefix: 'w');
      w.writeAttribute('xml:space', 'preserve');
      w.writeText(field);
      w.writeEndElement();
      w.writeEndElement();
      if (!nativeTocBoundary || paragraph.properties.fieldSeparate) {
        _writeFieldChar(w, 'separate');
      }
    } else if (nativeTocBoundary && paragraph.properties.fieldSeparate) {
      _writeFieldChar(w, 'separate');
    } else if (pageField) {
      _writeFieldChar(w, 'begin');
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('instrText', prefix: 'w');
      w.writeAttribute('xml:space', 'preserve');
      w.writeText(' PAGE ');
      w.writeEndElement();
      w.writeEndElement();
      _writeFieldChar(w, 'separate');
    }
    var i = 0;
    var offset = 0;
    var pageFieldOpen = pageField;
    final controlShells = <XmlElement>[];
    while (i < paragraph.inlines.length) {
      final WmlInline inline = paragraph.inlines[i];
      if (inline is WmlRun) {
        _openCommentStarts(w, inline.commentIds);
      }
      if (inline is WmlRun && inline.hyperlink != null) {
        final WmlHyperlink link = inline.hyperlink!;
        var end = i + 1;
        while (end < paragraph.inlines.length) {
          final WmlInline next = paragraph.inlines[end];
          if (next is! WmlRun ||
              next.hyperlink == null ||
              next.hyperlink!.anchor != link.anchor ||
              next.hyperlink!.url != link.url ||
              next.hyperlink!.file != link.file) {
            break;
          }
          end++;
        }
        w.writeStartElement('hyperlink', prefix: 'w');
        if (link.isInternal) {
          w.writeAttribute('w:anchor', link.anchor!);
        } else {
          w.writeAttribute('r:id', _externalLinkId(link));
        }
        w.writeAttribute('w:history', '1');
        for (int r = i; r < end; r++) {
          final WmlRun run = paragraph.inlines[r] as WmlRun;
          if (r > i) {
            _openCommentStarts(w, run.commentIds);
          }
          _writeTrackedRun(w, paragraph, run, offset);
          offset += run.text.length;
        }
        w.writeEndElement();
        _closeCommentsNotIn(w, _peekCommentIds(paragraph, end));
        i = end;
        continue;
      }
      switch (inline) {
        case WmlContentControlBoundary():
          if (inline.start) {
            controlShells.add(
              WordContentControlIo.start(
                w,
                inline.control,
                _package!,
                _activePartUri,
              ),
            );
          } else {
            WordContentControlIo.end(w, controlShells.removeLast());
          }
        case WmlBookmarkBoundary():
          _writeBookmarkBoundary(w, inline);
        case WmlNoteMarker():
          w.writeStartElement('r', prefix: 'w');
          final marker = inline.properties;
          final changed = WordPropertyIo.runValues(marker).entries.any(
            (entry) => marker.importedValues?[entry.key] != entry.value,
          );
          if (marker.sourcePropertiesXml != '' || changed) {
            _writeRPr(w, marker);
          }
          w.writeEmptyElement(
            inline.endnote ? 'endnoteRef' : 'footnoteRef',
            prefix: 'w',
          );
          w.writeEndElement();
        case WmlRun():
          if (pageFieldOpen) {
            _writePageFieldResult(w, inline);
            pageFieldOpen = false;
          } else {
            _writeTrackedRun(w, paragraph, inline, offset);
          }
          offset += inline.text.length;
        case WmlBreak():
          w.writeStartElement('r', prefix: 'w');
          w.writeStartElement('br', prefix: 'w');
          if (inline.type == WmlBreakType.page) {
            w.writeAttribute('w:type', 'page');
          } else if (inline.type == WmlBreakType.column) {
            w.writeAttribute('w:type', 'column');
          }
          w.writeEndElement();
          w.writeEndElement();
        case WmlObject():
          w.writeStartElement('r', prefix: 'w');
          w.writeStartElement('object', prefix: 'w');
          w.writeStartElement('OLEObject', prefix: 'o');
          w.writeAttribute('r:id', inline.relationshipId);
          w.writeEndElement();
          w.writeEndElement();
          w.writeEndElement();
      }
      _closeCommentsNotIn(w, _peekCommentIds(paragraph, i + 1));
      i++;
    }
    _closeCommentsNotIn(w, const <int>[]);
    if (nativeTocBoundary
        ? paragraph.properties.fieldEnd
        : field != null && field.trim().isNotEmpty) {
      _writeFieldChar(w, 'end');
    } else if (pageFieldOpen) {
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('t', prefix: 'w');
      w.writeText('1');
      w.writeEndElement();
      w.writeEndElement();
      _writeFieldChar(w, 'end');
    }
    if (bookmark != null && bookmark.isNotEmpty) {
      w.writeEmptyElement(
        'bookmarkEnd',
        prefix: 'w',
        attributes: <String, String>{'w:id': _generatedBookmarkIds[bookmark]!},
      );
    }
    w.writeEndElement();
    for (final shell in paragraphShells.reversed) {
      WordContentControlIo.end(w, shell);
    }
  }

  void _writeBookmarkBoundary(XmlWriter writer, WmlBookmarkBoundary boundary) {
    WordBookmarkIo.write(writer, boundary);
  }

  void _writeTrackedRun(
    XmlWriter w,
    WmlParagraph paragraph,
    WmlRun inline,
    int offset,
  ) {
    final List<WmlRevision> revisions = _revisionsFor(paragraph).toList();
    if (revisions.isEmpty || inline.text.isEmpty) {
      _writeRun(w, inline);
      return;
    }
    final int length = inline.text.length;
    final Set<int> boundaries = <int>{0, length};
    if (!inline.isAtomic) {
      for (final WmlRevision revision in revisions) {
        if (revision.start < offset + length && revision.end > offset) {
          boundaries
            ..add((revision.start - offset).clamp(0, length))
            ..add((revision.end - offset).clamp(0, length));
        }
      }
    }
    final List<int> cuts = boundaries.toList()..sort();
    for (var i = 1; i < cuts.length; i++) {
      final int start = offset + cuts[i - 1];
      final int end = offset + cuts[i];
      WmlRevision? tracked;
      for (final WmlRevision revision in revisions) {
        if (revision.start < end && revision.end > start) {
          tracked = revision;
          break;
        }
      }
      final WmlRun run = cuts.length == 2
          ? inline
          : (WmlClone.inlines(<WmlInline>[inline]).single as WmlRun
              ..text = inline.text.substring(cuts[i - 1], cuts[i]));
      _writeRun(w, run, revision: tracked);
    }
  }

  bool _hasLeadingColumnBreak(WmlParagraph paragraph) {
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun && inline.text.isEmpty) continue;
      return inline is WmlBreak && inline.type == WmlBreakType.column;
    }
    return false;
  }

  Iterable<WmlRevision> _revisionsFor(WmlParagraph paragraph) sync* {
    final WmlDocument? document = _document;
    if (document == null) return;
    for (final WmlRevision revision in document.revisions) {
      if (revision.accepted == null &&
          identical(
            revision.targetParagraph ??
                WordRevisions.resolveParagraph(document, revision),
            paragraph,
          )) {
        yield revision;
      }
    }
  }

  void _writeRun(XmlWriter w, WmlRun inline, {WmlRevision? revision}) {
    final String? instruction = inline.fieldInstruction;
    if (instruction != null) {
      w.writeStartElement('fldSimple', prefix: 'w');
      w.writeAttribute('w:instr', instruction);
      if (inline.fieldLocked) w.writeAttribute('w:fldLock', '1');
      if (inline.fieldDirty != null) {
        w.writeAttribute('w:dirty', inline.fieldDirty! ? '1' : '0');
      }
    }
    // Native simple fields contain tracked runs. A fldSimple inside ins/del
    // is not a valid WordprocessingML run-content child.
    final bool deleted = revision?.kind == WmlRevisionKind.delete;
    if (revision != null) {
      w.writeStartElement(deleted ? 'del' : 'ins', prefix: 'w');
      w.writeAttribute('w:id', '${revision.id}');
      w.writeAttribute('w:author', revision.author);
      if (revision.dateIso.isNotEmpty) {
        w.writeAttribute('w:date', revision.dateIso);
      }
    }
    w.writeStartElement('r', prefix: 'w');
    _writeRPr(w, inline.properties);
    if (inline.noteRefId != null) {
      w.writeEmptyElement(
        inline.noteRefEndnote ? 'endnoteReference' : 'footnoteReference',
        prefix: 'w',
        attributes: <String, String>{'w:id': '${inline.noteRefId}'},
      );
    } else {
      _writeRunContent(w, inline.text, deleted: deleted);
    }
    w.writeEndElement();
    if (revision != null) w.writeEndElement();
    if (instruction != null) w.writeEndElement();
  }

  void _writeRunContent(XmlWriter w, String text, {required bool deleted}) {
    if (!text.contains(RegExp(r'[\t\r\n]'))) {
      _writeTextNode(w, text, deleted: deleted);
      return;
    }
    var start = 0;
    for (int i = 0; i < text.length; i++) {
      final int code = text.codeUnitAt(i);
      if (code != 0x09 && code != 0x0a && code != 0x0d) {
        continue;
      }
      if (i > start) {
        _writeTextNode(w, text.substring(start, i), deleted: deleted);
      }
      w.writeEmptyElement(code == 0x09 ? 'tab' : 'br', prefix: 'w');
      if (code == 0x0d &&
          i + 1 < text.length &&
          text.codeUnitAt(i + 1) == 0x0a) {
        i++;
      }
      start = i + 1;
    }
    if (start < text.length) {
      _writeTextNode(w, text.substring(start), deleted: deleted);
    }
  }

  void _writeTextNode(XmlWriter w, String text, {required bool deleted}) {
    w.writeStartElement(deleted ? 'delText' : 't', prefix: 'w');
    w.writeAttribute('xml:space', 'preserve');
    w.writeText(text);
    w.writeEndElement();
  }

  String _externalLinkId(WmlHyperlink link) {
    final String target = link.url ?? link.file ?? '';
    final RelationshipCollection rels = _package!.relationshipsFor(
      _activePartUri,
    );
    for (final PackageRelationship rel in rels.items) {
      if (rel.type == RelationshipTypes.hyperlink &&
          rel.target == target &&
          rel.targetMode == RelationshipTargetMode.external) {
        return rel.id;
      }
    }
    return rels
        .add(
          type: RelationshipTypes.hyperlink,
          target: target,
          targetMode: RelationshipTargetMode.external,
        )
        .id;
  }

  void _writePPr(XmlWriter w, WmlParagraphProps p, {WmlSection? sectionBreak}) {
    if (p.importedValues != null && p.sourcePropertiesXml != null) {
      final XmlWriter generated = XmlWriter();
      _writeFullPPr(generated, p, sectionBreak: sectionBreak);
      WordPropertyIo.preserve(
        XmlDocument.parse(generated.toXml()).root!,
        p.sourcePropertiesXml!,
        p.importedValues!,
        WordPropertyIo.paragraphValues(p),
      ).writeTo(w);
      return;
    }
    _writeFullPPr(w, p, sectionBreak: sectionBreak);
  }

  void _writeFullPPr(
    XmlWriter w,
    WmlParagraphProps p, {
    WmlSection? sectionBreak,
  }) {
    w.writeStartElement('pPr', prefix: 'w');

    // OOXML schema order for w:pPr is significant. Word reports files as
    // corrupt when pBdr/shd/framePr/tabs are emitted after spacing/jc.
    if (p.styleId != null && p.styleId!.isNotEmpty) {
      w.writeEmptyElement(
        'pStyle',
        prefix: 'w',
        attributes: <String, String>{'w:val': p.styleId!},
      );
    }
    if (p.keepTogether) {
      w.writeEmptyElement('keepLines', prefix: 'w');
    }
    if (p.pageBreakBefore) {
      w.writeEmptyElement('pageBreakBefore', prefix: 'w');
    }
    if (p.dropCapLines > 0) {
      w.writeEmptyElement(
        'framePr',
        prefix: 'w',
        attributes: <String, String>{
          'w:dropCap': 'drop',
          'w:lines': '${p.dropCapLines}',
        },
      );
    }
    final int? numberingId = p.numId ?? (p.numberingSuppressed ? 0 : null);
    if (numberingId != null) {
      w.writeStartElement('numPr', prefix: 'w');
      w.writeEmptyElement(
        'ilvl',
        prefix: 'w',
        attributes: <String, String>{'w:val': '${p.ilvl}'},
      );
      w.writeEmptyElement(
        'numId',
        prefix: 'w',
        attributes: <String, String>{'w:val': '$numberingId'},
      );
      w.writeEndElement();
    }
    if (p.borderColor != null && p.borderColor!.isNotEmpty) {
      w.writeStartElement('pBdr', prefix: 'w');
      for (final String edge in <String>['top', 'left', 'bottom', 'right']) {
        w.writeEmptyElement(
          edge,
          prefix: 'w',
          attributes: <String, String>{
            'w:val': 'single',
            'w:sz': '4',
            'w:color': p.borderColor!,
          },
        );
      }
      w.writeEndElement();
    }
    if (p.shadingFill != null && p.shadingFill!.isNotEmpty) {
      w.writeEmptyElement(
        'shd',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': 'clear',
          'w:fill': p.shadingFill!,
        },
      );
    }
    if (p.tabs.isNotEmpty) {
      w.writeStartElement('tabs', prefix: 'w');
      for (final WmlTabStop tab in p.tabs) {
        w.writeStartElement('tab', prefix: 'w');
        w.writeAttribute('w:val', tab.alignment.name);
        w.writeAttribute('w:pos', '${pointsToTwips(tab.position)}');
        if (tab.leader != WmlTabLeader.none) {
          w.writeAttribute('w:leader', tab.leader.name);
        }
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    if (p.rightToLeft == true) {
      w.writeEmptyElement('bidi', prefix: 'w');
    } else if (p.rightToLeft == false) {
      w.writeEmptyElement(
        'bidi',
        prefix: 'w',
        attributes: <String, String>{'w:val': '0'},
      );
    }
    w.writeStartElement('spacing', prefix: 'w');
    w.writeAttribute('w:before', '${pointsToTwips(p.spacingBefore)}');
    w.writeAttribute('w:after', '${pointsToTwips(p.spacingAfter)}');
    if (p.lineSpacingRule == WmlLineSpacingRule.auto) {
      w.writeAttribute('w:line', '${(p.lineSpacing * 240).round()}');
      w.writeAttribute('w:lineRule', 'auto');
    } else {
      w.writeAttribute('w:line', '${pointsToTwips(p.lineSpacing)}');
      w.writeAttribute(
        'w:lineRule',
        p.lineSpacingRule == WmlLineSpacingRule.exact ? 'exact' : 'atLeast',
      );
    }
    w.writeEndElement();
    w.writeStartElement('ind', prefix: 'w');
    w.writeAttribute('w:left', '${pointsToTwips(p.indent.left)}');
    w.writeAttribute('w:right', '${pointsToTwips(p.indent.right)}');
    if (p.indent.firstLine > 0) {
      w.writeAttribute('w:firstLine', '${pointsToTwips(p.indent.firstLine)}');
    }
    if (p.indent.hanging > 0) {
      w.writeAttribute('w:hanging', '${pointsToTwips(p.indent.hanging)}');
    }
    w.writeEndElement();
    w.writeEmptyElement(
      'jc',
      prefix: 'w',
      attributes: <String, String>{
        'w:val': switch (p.justification) {
          WmlJustification.center => 'center',
          WmlJustification.right => 'right',
          WmlJustification.justify => 'both',
          WmlJustification.distributed => 'distribute',
          WmlJustification.left => 'left',
        },
      },
    );
    if (p.headingLevel != null && p.headingLevel! >= 1) {
      w.writeEmptyElement(
        'outlineLvl',
        prefix: 'w',
        attributes: <String, String>{'w:val': '${p.headingLevel! - 1}'},
      );
    }
    if (sectionBreak != null) {
      _writeSectPr(w, sectionBreak);
    }
    w.writeEndElement();
  }

  void _writeRPr(XmlWriter w, WmlRunProps r) {
    if (r.importedValues != null && r.sourcePropertiesXml != null) {
      final XmlWriter generated = XmlWriter();
      _writeFullRPr(generated, r);
      WordPropertyIo.preserve(
        XmlDocument.parse(generated.toXml()).root!,
        r.sourcePropertiesXml!,
        r.importedValues!,
        WordPropertyIo.runValues(r),
      ).writeTo(w);
      return;
    }
    _writeFullRPr(w, r);
  }

  void _writeFullRPr(XmlWriter w, WmlRunProps r) {
    w.writeStartElement('rPr', prefix: 'w');
    if (r.styleId != null) {
      w.writeEmptyElement(
        'rStyle',
        prefix: 'w',
        attributes: {'w:val': r.styleId!},
      );
    }
    // OOXML CT_RPr order is strict: rFonts, b, i, strike, color, sz,
    // highlight, u, vertAlign. Word reports the package as corrupt when these
    // appear in a different order.
    if (r.asciiFont.isNotEmpty || r.csFont.isNotEmpty) {
      final String latin = r.asciiFont.isEmpty ? r.csFont : r.asciiFont;
      w.writeEmptyElement(
        'rFonts',
        prefix: 'w',
        attributes: <String, String>{
          'w:ascii': latin,
          'w:hAnsi': latin,
          if (r.csFont.isNotEmpty) 'w:cs': r.csFont,
        },
      );
    }
    w.writeEmptyElement(
      'b',
      prefix: 'w',
      attributes: <String, String>{'w:val': r.bold ? '1' : '0'},
    );
    w.writeEmptyElement(
      'i',
      prefix: 'w',
      attributes: <String, String>{'w:val': r.italic ? '1' : '0'},
    );
    if (r.strike) {
      w.writeEmptyElement('strike', prefix: 'w');
    }
    w.writeEmptyElement(
      'color',
      prefix: 'w',
      attributes: <String, String>{'w:val': r.color},
    );
    w.writeEmptyElement(
      'sz',
      prefix: 'w',
      attributes: <String, String>{'w:val': '${r.fontSizeHalfPoints}'},
    );
    final String? highlight = WmlHighlight.toName(r.highlight);
    if (highlight != null) {
      w.writeEmptyElement(
        'highlight',
        prefix: 'w',
        attributes: <String, String>{'w:val': highlight},
      );
    }
    if (r.underline != WmlUnderline.none) {
      w.writeEmptyElement(
        'u',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': switch (r.underline) {
            WmlUnderline.double => 'double',
            WmlUnderline.dotted => 'dotted',
            WmlUnderline.wavy => 'wave',
            _ => 'single',
          },
        },
      );
    }
    if (r.vertAlign != WmlVertAlign.baseline) {
      w.writeEmptyElement(
        'vertAlign',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': r.vertAlign == WmlVertAlign.superscript
              ? 'superscript'
              : 'subscript',
        },
      );
    }
    w.writeEndElement();
  }

  void _writeTable(
    XmlWriter w,
    WmlTable table,
    Map<OfficeVisual, String> imageIds,
  ) {
    w.writeStartElement('tbl', prefix: 'w');
    WordTablePropertyIo.write(w, table.properties);
    w.writeStartElement('tblGrid', prefix: 'w');
    for (final double col in table.grid) {
      w.writeEmptyElement(
        'gridCol',
        prefix: 'w',
        attributes: <String, String>{'w:w': '${pointsToTwips(col)}'},
      );
    }
    w.writeEndElement();
    for (final WmlTableRow row in table.rows) {
      w.writeStartElement('tr', prefix: 'w');
      if (row.cantSplit || row.height != null) {
        w.writeStartElement('trPr', prefix: 'w');
        if (row.cantSplit) {
          w.writeEmptyElement('cantSplit', prefix: 'w');
        }
        if (row.height != null) {
          w.writeEmptyElement(
            'trHeight',
            prefix: 'w',
            attributes: <String, String>{
              'w:val': '${pointsToTwips(row.height!)}',
              'w:hRule': 'atLeast',
            },
          );
        }
        w.writeEndElement();
      }
      for (final WmlTableCell cell in row.cells) {
        w.writeStartElement('tc', prefix: 'w');
        w.writeStartElement('tcPr', prefix: 'w');
        if (cell.sourceWidthXml != null &&
            cell.width == cell.sourceWidthPoints) {
          w.writeRaw(cell.sourceWidthXml!);
        } else if (cell.width != null) {
          w.writeEmptyElement(
            'tcW',
            prefix: 'w',
            attributes: <String, String>{
              'w:w': '${pointsToTwips(cell.width!)}',
              'w:type': 'dxa',
            },
          );
        }
        if (cell.gridSpan > 1) {
          w.writeEmptyElement(
            'gridSpan',
            prefix: 'w',
            attributes: <String, String>{'w:val': '${cell.gridSpan}'},
          );
        }
        if (cell.vMerge != WmlVMerge.none) {
          w.writeEmptyElement(
            'vMerge',
            prefix: 'w',
            attributes: cell.vMerge == WmlVMerge.restart
                ? <String, String>{'w:val': 'restart'}
                : null,
          );
        }
        if (cell.fillColor != null && cell.fillColor!.isNotEmpty) {
          w.writeEmptyElement(
            'shd',
            prefix: 'w',
            attributes: <String, String>{
              'w:val': 'clear',
              'w:fill': cell.fillColor!,
            },
          );
        }
        w.writeEndElement();
        if (cell.blocks.isEmpty) {
          _writeParagraph(w, WmlParagraph());
        } else {
          for (final WmlBlock block in cell.blocks) {
            _writeBlock(w, block, imageIds);
          }
        }
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  void _writeFrame(
    XmlWriter w,
    WmlFrame frame,
    Map<OfficeVisual, String> imageIds,
  ) {
    WordFrameIo.write(
      w,
      frame,
      writeParagraphProperties: (writer, properties) =>
          _writePPr(writer, properties),
      writeBlock: (XmlWriter inner, WmlBlock child) {
        _writeBlock(inner, child, imageIds);
      },
      docPrId: _docPrId++,
    );
  }

  void _writeSectPr(XmlWriter writer, WmlSection section) {
    final XmlWriter generated = XmlWriter();
    _writeGeneratedSectPr(generated, section);
    final XmlElement element = XmlDocument.parse(generated.toXml()).root!;
    final XmlElement preserved = WordSectionIo.preserve(element, section);
    _sectionRevisionIds.ensureUnique(preserved);
    preserved.writeTo(writer);
  }

  void _writeGeneratedSectPr(XmlWriter w, WmlSection section) {
    w.writeStartElement('sectPr', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    w.writeNamespace('r', OfficeNamespaces.r);
    final _HeaderFooterIds? ids = _headerFooterIds[section];
    if (ids != null) {
      void ref(String? rid, String kind, String type) {
        if (rid == null) {
          return;
        }
        w.writeEmptyElement(
          kind,
          prefix: 'w',
          attributes: <String, String>{'r:id': rid, 'w:type': type},
        );
      }

      ref(ids.header, 'headerReference', 'default');
      ref(ids.firstHeader, 'headerReference', 'first');
      ref(ids.evenHeader, 'headerReference', 'even');
      ref(ids.footer, 'footerReference', 'default');
      ref(ids.firstFooter, 'footerReference', 'first');
      ref(ids.evenFooter, 'footerReference', 'even');
    }
    w.writeEmptyElement(
      'type',
      prefix: 'w',
      attributes: <String, String>{
        'w:val': switch (section.breakKind) {
          WmlSectionBreakKind.continuous => 'continuous',
          WmlSectionBreakKind.oddPage => 'oddPage',
          WmlSectionBreakKind.evenPage => 'evenPage',
          WmlSectionBreakKind.nextPage => 'nextPage',
        },
      },
    );
    w.writeEmptyElement(
      'pgSz',
      prefix: 'w',
      attributes: <String, String>{
        'w:w': '${pointsToTwips(section.pageSize.width)}',
        'w:h': '${pointsToTwips(section.pageSize.height)}',
        if (section.pageSize.isLandscape) 'w:orient': 'landscape',
      },
    );
    w.writeEmptyElement(
      'pgMar',
      prefix: 'w',
      attributes: <String, String>{
        'w:top': '${pointsToTwips(section.margins.top)}',
        'w:bottom': '${pointsToTwips(section.margins.bottom)}',
        'w:left': '${pointsToTwips(section.margins.left)}',
        'w:right': '${pointsToTwips(section.margins.right)}',
        'w:header': '${pointsToTwips(section.margins.header)}',
        'w:footer': '${pointsToTwips(section.margins.footer)}',
      },
    );
    if (section.lineNumbers) {
      w.writeEmptyElement(
        'lnNumType',
        prefix: 'w',
        attributes: <String, String>{'w:countBy': '1'},
      );
    }
    w.writeEmptyElement(
      'cols',
      prefix: 'w',
      attributes: <String, String>{
        'w:num': '${section.resolvedColumnCount}',
        'w:space': '${pointsToTwips(section.columnSpace)}',
        if (section.columnSep) 'w:sep': '1',
      },
    );
    if (section.differentFirstPage) {
      w.writeEmptyElement('titlePg', prefix: 'w');
    }
    w.writeEndElement();
  }

  List<_ColumnSlice> _columnSlices(WmlSection section) {
    final List<_ColumnSlice> slices = <_ColumnSlice>[];
    final List<WmlBlock> buf = <WmlBlock>[];
    var cols = section.columnCount;

    void flush(WmlSectionBreakKind kind) {
      if (buf.isEmpty) {
        return;
      }
      slices.add(_ColumnSlice(List<WmlBlock>.of(buf), cols, kind));
      buf.clear();
    }

    for (int i = 0; i < section.blocks.length; i++) {
      final int want = _blockColumnCount(section, i);
      if (buf.isNotEmpty && want != cols) {
        flush(WmlSectionBreakKind.continuous);
      }
      cols = want;
      buf.add(section.blocks[i]);
    }
    flush(section.breakKind);
    if (slices.isEmpty) {
      return <_ColumnSlice>[
        _ColumnSlice(
          const <WmlBlock>[],
          section.columnCount,
          section.breakKind,
        ),
      ];
    }
    return <_ColumnSlice>[
      _ColumnSlice(
        slices.first.blocks,
        slices.first.columnCount,
        section.breakKind,
      ),
      for (int i = 1; i < slices.length; i++)
        _ColumnSlice(
          slices[i].blocks,
          slices[i].columnCount,
          WmlSectionBreakKind.continuous,
        ),
    ];
  }

  int _blockColumnCount(WmlSection section, int index) {
    if (section.columnCount < 2) {
      return section.columnCount;
    }
    final WmlBlock block = section.blocks[index];
    if (_isWideTable(section, block)) {
      return 1;
    }
    if (block is WmlParagraph &&
        block.properties.pageBreakBefore &&
        index + 1 < section.blocks.length &&
        _isWideTable(section, section.blocks[index + 1])) {
      return 1;
    }
    return section.columnCount;
  }

  bool _isWideTable(WmlSection section, WmlBlock block) {
    if (block is! WmlTable || block.grid.isEmpty) {
      return false;
    }
    final double width = block.grid.fold<double>(
      0,
      (double a, double x) => a + x,
    );
    final double content =
        section.pageSize.width - section.margins.left - section.margins.right;
    final double colW =
        (content - section.columnSpace * (section.columnCount - 1)) /
        section.columnCount;
    return width > colW + 8;
  }

  Map<WmlSection, _HeaderFooterIds> _syncHeadersFooters(
    WmlDocument document,
    OpcPackage package,
  ) {
    _hfPart = 1;
    final Map<WmlSection, _HeaderFooterIds> map =
        <WmlSection, _HeaderFooterIds>{};
    final String watermark = document.watermark;
    for (int i = 0; i < document.sections.length; i++) {
      final WmlSection section = document.sections[i];
      map[section] = _HeaderFooterIds(
        header: _writeHfPart(
          package,
          section.header,
          visuals: section.headerVisuals,
          header: true,
          watermark: i == 0 ? watermark : '',
        ),
        footer: _writeHfPart(
          package,
          section.footer,
          visuals: section.footerVisuals,
          header: false,
        ),
        firstHeader: _writeHfPart(
          package,
          section.firstHeader,
          visuals: section.firstHeaderVisuals,
          header: true,
        ),
        firstFooter: _writeHfPart(
          package,
          section.firstFooter,
          visuals: section.firstFooterVisuals,
          header: false,
        ),
        evenHeader: _writeHfPart(
          package,
          section.evenHeader,
          visuals: section.evenHeaderVisuals,
          header: true,
        ),
        evenFooter: _writeHfPart(
          package,
          section.evenFooter,
          visuals: section.evenFooterVisuals,
          header: false,
        ),
      );
    }
    return map;
  }

  String? _writeHfPart(
    OpcPackage package,
    List<WmlParagraph> story, {
    required List<WmlVisual> visuals,
    required bool header,
    String watermark = '',
  }) {
    if (story.isEmpty && visuals.isEmpty && watermark.isEmpty) {
      return null;
    }
    final int n = _hfPart++;
    final String name = header ? 'header$n.xml' : 'footer$n.xml';
    final String uri = OpcUris.resolve(_mainPartUri, name);
    final Map<OfficeVisual, String> imageIds = WordDrawingIo.syncVisuals(
      visuals.map((WmlVisual visual) => visual.visual),
      package,
      partUri: uri,
      mediaPrefix: '${header ? 'header' : 'footer'}${n}Image',
    );
    final String previousPart = _activePartUri;
    _activePartUri = uri;
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(header ? 'hdr' : 'ftr', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeNamespace('wp', OfficeNamespaces.wp);
    w.writeNamespace('a', OfficeNamespaces.a);
    w.writeNamespace('pic', OfficeNamespaces.pic);
    w.writeNamespace('c', OfficeNamespaces.c);
    if (watermark.isNotEmpty) {
      w.writeNamespace('v', OfficeNamespaces.v);
      w.writeNamespace('o', OfficeNamespaces.o);
    }
    for (final WmlParagraph paragraph in story) {
      _writeParagraph(w, paragraph);
    }
    for (final WmlVisual visual in visuals) {
      _writeBlock(w, visual, imageIds);
    }
    if (watermark.isNotEmpty) {
      _writeVmlWatermark(w, watermark);
    }
    w.writeEndElement();
    _activePartUri = previousPart;
    return _putNamedPart(
      package,
      uri,
      header ? OfficeContentTypes.wordHeader : OfficeContentTypes.wordFooter,
      w.toXml(),
      header ? RelationshipTypes.header : RelationshipTypes.footer,
    );
  }

  void _syncSettings(WmlDocument document, OpcPackage package) {
    final String uri = _relatedPartUri(
      package,
      RelationshipTypes.settings,
      'settings.xml',
    );
    final xml = WordSettingsIo.merge(
      package.getPart(uri)?.readText(),
      tracking: document.trackRevisions,
      protection: document.restrictEditing,
      oddEven: document.sections.any((s) => s.differentOddEven),
    );
    if (xml == null) return;
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordSettings,
      xml,
      RelationshipTypes.settings,
    );
  }

  String _putNamedPart(
    OpcPackage package,
    String uri,
    String contentType,
    String xml,
    String relType,
  ) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, contentType, utf8.encode(xml));
    } else {
      existing.writeText(xml);
    }
    final RelationshipCollection rels = package.relationshipsFor(_mainPartUri);
    for (final PackageRelationship rel in rels.items) {
      if (rel.type == relType &&
          rel.targetMode == RelationshipTargetMode.internal &&
          rels.resolve(rel) == uri) {
        return rel.id;
      }
    }
    return rels
        .add(type: relType, target: OpcUris.relativize(_mainPartUri, uri))
        .id;
  }

  void _syncWatermark(WmlDocument document, OpcPackage package) {
    package.deletePart('/word/watermark.xml');
  }

  void _writeVmlWatermark(XmlWriter w, String text) {
    w.writeStartElement('p', prefix: 'w');
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('pict', prefix: 'w');
    w.writeStartElement('shape', prefix: 'v');
    w.writeAttribute('id', 'PowerPlusWaterMarkObject');
    w.writeAttribute(
      'style',
      'position:absolute;margin-left:0;margin-top:0;width:528pt;height:132pt;rotation:315;z-index:-251658752;mso-position-horizontal:center;mso-position-vertical:center',
    );
    w.writeAttribute('fillcolor', 'silver');
    w.writeAttribute('stroked', 'f');
    w.writeStartElement('textpath', prefix: 'v');
    w.writeAttribute('on', 't');
    w.writeAttribute('string', text);
    w.writeAttribute('style', 'font-family:Calibri;font-size:1pt');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  void _syncNumbering(OpcPackage package) {
    final String uri = _relatedPartUri(
      package,
      RelationshipTypes.numbering,
      'numbering.xml',
    );
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('numbering', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    for (final int id in <int>[1, 2]) {
      w.writeStartElement('abstractNum', prefix: 'w');
      w.writeAttribute('w:abstractNumId', '$id');
      w.writeEmptyElement(
        'multiLevelType',
        prefix: 'w',
        attributes: <String, String>{'w:val': 'hybridMultilevel'},
      );
      final bool bullet = id == 1;
      for (int ilvl = 0; ilvl < 9; ilvl++) {
        w.writeStartElement('lvl', prefix: 'w');
        w.writeAttribute('w:ilvl', '$ilvl');
        w.writeEmptyElement(
          'start',
          prefix: 'w',
          attributes: <String, String>{'w:val': '1'},
        );
        w.writeEmptyElement(
          'numFmt',
          prefix: 'w',
          attributes: <String, String>{'w:val': bullet ? 'bullet' : 'decimal'},
        );
        final String lvlText = bullet
            ? (ilvl == 0
                  ? '•'
                  : ilvl == 1
                  ? '◦'
                  : '▪')
            : List<String>.generate(ilvl + 1, (int i) => '%${i + 1}').join('.');
        if (ilvl > 0) {
          w.writeEmptyElement(
            'lvlRestart',
            prefix: 'w',
            attributes: <String, String>{'w:val': '$ilvl'},
          );
        }
        w.writeEmptyElement(
          'lvlText',
          prefix: 'w',
          attributes: <String, String>{'w:val': lvlText},
        );
        w.writeStartElement('pPr', prefix: 'w');
        w.writeStartElement('ind', prefix: 'w');
        w.writeAttribute('w:left', '${(ilvl + 1) * 360}');
        w.writeAttribute('w:hanging', '180');
        w.writeEndElement();
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    for (final int id in <int>[1, 2]) {
      w.writeStartElement('num', prefix: 'w');
      w.writeAttribute('w:numId', '$id');
      w.writeEmptyElement(
        'abstractNumId',
        prefix: 'w',
        attributes: <String, String>{'w:val': '$id'},
      );
      w.writeEndElement();
    }
    w.writeEndElement();
    final XmlDocument generated = XmlDocument.parse(w.toXml());
    final PackagePart? original = package.getPart(uri);
    String xml = generated.toXmlString();
    if (original != null) {
      final XmlDocument preserved = XmlDocument.parse(original.readText());
      final XmlElement? root = preserved.root;
      if (root != null) {
        for (final XmlElement node in generated.root!.childElements) {
          final String key = node.localName == 'num'
              ? 'numId'
              : 'abstractNumId';
          if (root
              .childrenNamed(node.localName)
              .any(
                (XmlElement old) =>
                    old.getAttribute(key) == node.getAttribute(key),
              )) {
            continue;
          }
          // CT_Numbering requires abstractNum before num instances.
          final int firstNum = root.children.indexWhere(
            (XmlNode n) => n is XmlElement && n.localName == 'num',
          );
          final XmlElement copy = node.copy()
            ..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
          if (node.localName == 'abstractNum' && firstNum >= 0) {
            root.children.insert(firstNum, copy..parent = root);
          } else {
            root.addChild(copy);
          }
        }
        xml = preserved.toXmlString();
      }
    }
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordNumbering,
      xml,
      RelationshipTypes.numbering,
    );
  }

  Map<String, WmlStyle> _stylesForExport(
    WmlDocument document, {
    bool includeDefaultStyles = true,
  }) {
    final Map<String, WmlStyle> styles = <String, WmlStyle>{
      for (final WmlStyle style
          in document.styles.isEmpty && includeDefaultStyles
              ? WordStyles.all
              : document.styles)
        style.id: style,
    };
    final Map<String, WmlStyle> builtIns = <String, WmlStyle>{
      for (final WmlStyle style in WordStyles.catalog) style.id: style,
    };
    final Set<String> visited = <String>{};
    void include(String? id) {
      if (id == null || !visited.add(id)) return;
      final WmlStyle? style = styles[id] ?? builtIns[id];
      if (style == null) return;
      styles[id] = style;
      include(style.basedOn);
    }

    for (final WmlStyle style in List<WmlStyle>.of(styles.values)) {
      include(style.id);
    }
    final Iterable<WmlParagraph> paragraphs = <WmlParagraph>[
      ...document.paragraphs,
      for (final WmlSection section in document.sections) ...<WmlParagraph>[
        ...section.header,
        ...section.footer,
        ...section.firstHeader,
        ...section.firstFooter,
        ...section.evenHeader,
        ...section.evenFooter,
      ],
      for (final WmlNote note in <WmlNote>[
        ...document.footnotes,
        ...document.endnotes,
      ])
        ...note.allParagraphs,
      for (final WmlComment comment in document.comments) ...comment.paragraphs,
    ];
    for (final WmlParagraph paragraph in paragraphs) {
      include(paragraph.properties.styleId);
    }
    return styles;
  }

  void _syncStyles(WmlDocument document, OpcPackage package) {
    final String uri = _relatedPartUri(
      package,
      RelationshipTypes.styles,
      'styles.xml',
    );
    final PackagePart? original = package.getPart(uri);
    final bool importedWithoutStyles =
        document.package != null && original == null;
    final Map<String, WmlStyle> current = _stylesForExport(
      document,
      includeDefaultStyles: document.package == null,
    );
    if (importedWithoutStyles && current.isEmpty) return;
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('styles', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    if (!importedWithoutStyles) {
      w.writeStartElement('docDefaults', prefix: 'w');
      w.writeStartElement('rPrDefault', prefix: 'w');
      w.writeStartElement('rPr', prefix: 'w');
      w.writeEmptyElement(
        'rFonts',
        prefix: 'w',
        attributes: const <String, String>{
          'w:ascii': 'Arial',
          'w:hAnsi': 'Arial',
          'w:cs': 'Arial',
        },
      );
      w.writeEmptyElement(
        'sz',
        prefix: 'w',
        attributes: const <String, String>{'w:val': '22'},
      );
      w.writeEndElement();
      w.writeEndElement();
      w.writeEndElement();
    }
    for (final WmlStyle style in current.values) {
      w.writeStartElement('style', prefix: 'w');
      w.writeAttribute('w:type', 'paragraph');
      w.writeAttribute('w:styleId', style.id);
      w.writeEmptyElement(
        'name',
        prefix: 'w',
        attributes: <String, String>{'w:val': style.name},
      );
      if (style.basedOn != null && style.basedOn!.isNotEmpty) {
        w.writeEmptyElement(
          'basedOn',
          prefix: 'w',
          attributes: <String, String>{'w:val': style.basedOn!},
        );
      }
      w.writeStartElement('pPr', prefix: 'w');
      if (style.numId != null) {
        w.writeStartElement('numPr', prefix: 'w');
        w.writeEmptyElement(
          'ilvl',
          prefix: 'w',
          attributes: <String, String>{'w:val': '${style.ilvl ?? 0}'},
        );
        w.writeEmptyElement(
          'numId',
          prefix: 'w',
          attributes: <String, String>{'w:val': '${style.numId}'},
        );
        w.writeEndElement();
      }
      w.writeStartElement('spacing', prefix: 'w');
      w.writeAttribute('w:before', '${pointsToTwips(style.spacingBefore)}');
      w.writeAttribute('w:after', '${pointsToTwips(style.spacingAfter)}');
      w.writeEndElement();
      final WmlIndent? indent = style.indent;
      if (indent != null) {
        w.writeEmptyElement(
          'ind',
          prefix: 'w',
          attributes: <String, String>{
            'w:left': '${pointsToTwips(indent.left)}',
            'w:right': '${pointsToTwips(indent.right)}',
            if (indent.firstLine != 0)
              'w:firstLine': '${pointsToTwips(indent.firstLine)}',
            if (indent.hanging != 0)
              'w:hanging': '${pointsToTwips(indent.hanging)}',
          },
        );
      }
      w.writeEmptyElement(
        'jc',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': switch (style.justification) {
            WmlJustification.center => 'center',
            WmlJustification.right => 'right',
            WmlJustification.justify => 'both',
            WmlJustification.distributed => 'distribute',
            WmlJustification.left => 'left',
          },
        },
      );
      if (style.headingLevel != null) {
        w.writeEmptyElement(
          'outlineLvl',
          prefix: 'w',
          attributes: <String, String>{'w:val': '${style.headingLevel! - 1}'},
        );
      }
      w.writeEndElement();
      w.writeStartElement('rPr', prefix: 'w');
      if (style.font != null && style.font!.isNotEmpty) {
        w.writeEmptyElement(
          'rFonts',
          prefix: 'w',
          attributes: <String, String>{
            'w:ascii': style.font!,
            'w:hAnsi': style.font!,
            if (style.csFont != null && style.csFont!.isNotEmpty)
              'w:cs': style.csFont!,
          },
        );
      }
      if (style.bold) {
        w.writeEmptyElement('b', prefix: 'w');
      }
      if (style.italic) {
        w.writeEmptyElement('i', prefix: 'w');
      }
      w.writeEmptyElement(
        'color',
        prefix: 'w',
        attributes: <String, String>{'w:val': style.color},
      );
      w.writeEmptyElement(
        'sz',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': '${(style.fontSizePoints * 2).round()}',
        },
      );
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
    final XmlDocument generated = XmlDocument.parse(w.toXml());
    String xml = generated.toXmlString();
    if (original != null) {
      final XmlDocument preserved = XmlDocument.parse(original.readText());
      final XmlElement? root = preserved.root;
      if (root != null) {
        root.children.removeWhere(
          (XmlNode node) =>
              node is XmlElement &&
              node.localName == 'style' &&
              document.importedStyles.containsKey(
                node.getAttribute('styleId'),
              ) &&
              !current.containsKey(node.getAttribute('styleId')),
        );
        for (final XmlElement node in generated.root!.childrenNamed('style')) {
          final String? id = node.getAttribute('styleId');
          if (id != null &&
              identical(current[id], document.importedStyles[id])) {
            continue;
          }
          final int at = root.children.indexWhere(
            (XmlNode old) =>
                old is XmlElement &&
                old.localName == 'style' &&
                old.getAttribute('styleId') == id,
          );
          final XmlElement copy = node.copy()
            ..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
          if (at < 0) {
            root.addChild(copy);
          } else {
            root.children[at] = copy..parent = root;
          }
        }
        xml = preserved.toXmlString();
      }
    }
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordStyles,
      xml,
      RelationshipTypes.styles,
    );
  }

  void _syncNotes(WmlDocument document, OpcPackage package) {
    _writeNotesPart(
      package,
      document.footnotes,
      _relatedPartUri(package, RelationshipTypes.footnotes, 'footnotes.xml'),
      OfficeContentTypes.wordFootnotes,
      RelationshipTypes.footnotes,
      'footnotes',
      'footnote',
    );
    _writeNotesPart(
      package,
      document.endnotes,
      _relatedPartUri(package, RelationshipTypes.endnotes, 'endnotes.xml'),
      OfficeContentTypes.wordEndnotes,
      RelationshipTypes.endnotes,
      'endnotes',
      'endnote',
    );
  }

  void _writeNoteChrome(XmlWriter w, String item, XmlElement? source) {
    if (source != null) {
      // An imported part owns its separator choices, including their absence.
      // Replacing them with the conventional pair adds a visible rule to
      // documents that deliberately contain no separator definition.
      for (final node in source.childElements) {
        if (node.namespaceUri != OfficeNamespaces.w ||
            node.localName != item ||
            !const {
              'separator',
              'continuationSeparator',
              'continuationNotice',
            }.contains(
              node.getAttribute('type', namespaceUri: OfficeNamespaces.w),
            )) {
          continue;
        }
        final retained = node.copy();
        // Native fragments may depend on aliases or markup-compatibility
        // context declared on their original root. Keep that context local so
        // a foreign source `w` binding cannot reinterpret generated notes.
        for (final attribute in source.attributes) {
          final inherited =
              attribute.prefix == 'xmlns' ||
              attribute.qualifiedName == 'xmlns' ||
              attribute.namespaceUri == OfficeNamespaces.xml ||
              attribute.namespaceUri == OfficeNamespaces.mc;
          if (inherited &&
              !retained.attributes.any(
                (existing) => existing.qualifiedName == attribute.qualifiedName,
              )) {
            retained.attributes.add(attribute.copy());
          }
        }
        retained.writeTo(w);
      }
      return;
    }
    const chrome = <({int id, String type, String element})>[
      (id: -1, type: 'separator', element: 'separator'),
      (id: 0, type: 'continuationSeparator', element: 'continuationSeparator'),
    ];
    for (final entry in chrome) {
      w.writeStartElement(item, prefix: 'w');
      w.writeAttribute('w:type', entry.type);
      w.writeAttribute('w:id', '${entry.id}');
      w.writeStartElement('p', prefix: 'w');
      w.writeStartElement('r', prefix: 'w');
      w.writeEmptyElement(entry.element, prefix: 'w');
      w.writeEndElement();
      w.writeEndElement();
      w.writeEndElement();
    }
  }

  void _writeNotesPart(
    OpcPackage package,
    List<WmlNote> notes,
    String uri,
    String contentType,
    String relType,
    String root,
    String item,
  ) {
    final sourcePart = package.getPart(uri);
    final source = sourcePart == null
        ? null
        : XmlDocument.parse(sourcePart.readText()).root;
    final Map<OfficeVisual, String> imageIds = WordDrawingIo.syncVisuals(
      notes
          .expand((WmlNote note) => note.visuals)
          .map((WmlVisual v) => v.visual),
      package,
      partUri: uri,
      mediaPrefix: '${item}Image',
    );
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(root, prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeNamespace('wp', OfficeNamespaces.wp);
    w.writeNamespace('a', OfficeNamespaces.a);
    w.writeNamespace('pic', WordDrawingIo.pictureUri);
    final String previousPart = _activePartUri;
    _activePartUri = uri;
    // Separators are not editable note bodies. Preserve their native metadata;
    // only a newly created note part receives the conventional standard pair.
    _writeNoteChrome(w, item, source);
    for (final WmlNote note in notes) {
      w.writeStartElement(item, prefix: 'w');
      w.writeAttribute('w:id', '${note.id}');
      // Imported absence is intentional. A marker already present in any
      // paragraph or nested table must stay there without a second prefix.
      var referenceWritten = !note.addReference || note.hasReferenceMarkers;
      for (final WmlBlock block in note.blocks) {
        if (!referenceWritten) {
          _writeParagraph(
            w,
            block is WmlParagraph ? block : WmlParagraph(),
            noteReference: true,
            endnote: note.endnote,
            addNoteReferenceSpace: note.addReferenceSpace,
            noteReferencePropertiesXml: note.referencePropertiesXml,
          );
          referenceWritten = true;
          if (block is WmlParagraph) continue;
        }
        _writeBlock(w, block, imageIds);
      }
      if (!referenceWritten || note.blocks.isEmpty) {
        _writeParagraph(
          w,
          WmlParagraph(),
          noteReference: !referenceWritten,
          endnote: note.endnote,
          addNoteReferenceSpace: note.addReferenceSpace,
          noteReferencePropertiesXml: note.referencePropertiesXml,
        );
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    _activePartUri = previousPart;
    _putPart(package, uri, contentType, w.toXml(), relType);
  }

  void _putPart(
    OpcPackage package,
    String uri,
    String contentType,
    String xml,
    String relType,
  ) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, contentType, utf8.encode(xml));
    } else {
      existing.writeText(xml);
    }
    final RelationshipCollection rels = package.relationshipsFor(_mainPartUri);
    if (rels.firstByType(relType) == null) {
      rels.add(type: relType, target: OpcUris.relativize(_mainPartUri, uri));
    }
  }

  String _relatedPartUri(OpcPackage package, String type, String name) {
    final RelationshipCollection rels = package.relationshipsFor(_mainPartUri);
    final PackageRelationship? rel = rels.firstByType(type);
    if (rel == null) return OpcUris.resolve(_mainPartUri, name);
    if (rel.targetMode == RelationshipTargetMode.external) {
      throw FormatException('The Word $name part must be inside its package');
    }
    return rels.resolve(rel);
  }
}

class _ColumnSlice {
  _ColumnSlice(this.blocks, this.columnCount, this.breakKind);

  final List<WmlBlock> blocks;
  final int columnCount;
  final WmlSectionBreakKind breakKind;
}

class _HeaderFooterIds {
  _HeaderFooterIds({
    this.header,
    this.footer,
    this.firstHeader,
    this.firstFooter,
    this.evenHeader,
    this.evenFooter,
  });

  final String? header;
  final String? footer;
  final String? firstHeader;
  final String? firstFooter;
  final String? evenHeader;
  final String? evenFooter;
}
