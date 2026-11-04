import 'dart:convert';
import 'dart:typed_data';

import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_writer.dart';
import '../math/omml_io.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';
import '../model/word_revision.dart';
import '../model/word_styles.dart';
import '../model/word_toc.dart';
import '../properties/wml_properties.dart';
import 'word_drawing_io.dart';
import 'word_frame_io.dart';

/// Writes a [WmlDocument] back to a `.docx` OPC package.
class WordSerializer {
  var _docPrId = 1;
  var _hfPart = 1;
  final List<({String id, String target})> _externalLinks =
      <({String id, String target})>[];
  final Set<int> _openComments = <int>{};
  Map<WmlSection, _HeaderFooterIds> _headerFooterIds =
      <WmlSection, _HeaderFooterIds>{};
  WmlDocument? _document;

  /// writeBytes API.
  Uint8List writeBytes(WmlDocument document, {String? password}) {
    return write(document).save(password: password);
  }

  /// write API.
  OpcPackage write(WmlDocument document) {
    final OpcPackage package =
        document.package ?? OpcPackage.create(OpcPackageKind.word);
    if (package.getPart('/word/document.xml') == null) {
      package.createPart(
        '/word/document.xml',
        OfficeContentTypes.wordMain,
        utf8.encode('<w:document xmlns:w="${OfficeNamespaces.w}"/>'),
      );
      if (package.packageRelationships.firstByType(
            RelationshipTypes.officeDocument,
          ) ==
          null) {
        package.packageRelationships.add(
          type: RelationshipTypes.officeDocument,
          target: 'word/document.xml',
        );
      }
    }
    _externalLinks.clear();
    _openComments.clear();
    _document = document;
    _headerFooterIds = _syncHeadersFooters(document, package);
    _syncEmbeddings(document, package);
    final Map<OfficeVisual, String> imageIds = _syncImages(document, package);
    package
        .getPart('/word/document.xml')!
        .writeText(_documentXml(document, imageIds));
    _syncHyperlinkRels(package);
    _syncComments(document, package);
    _syncWatermark(document, package);
    _syncNumbering(package);
    _syncStyles(document, package);
    _syncNotes(document, package);
    _syncCitations(document, package);
    _syncSettings(document, package);
    document.properties.writeToPackage(package);
    document.package = package;
    return package;
  }

  void _syncHyperlinkRels(OpcPackage package) {
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    for (final ({String id, String target}) link in _externalLinks) {
      final PackageRelationship? existing = rels.byId(link.id);
      if (existing != null) {
        continue;
      }
      rels.add(
        id: link.id,
        type: RelationshipTypes.hyperlink,
        target: link.target,
        targetMode: RelationshipTargetMode.external,
      );
    }
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
        final String target = OpcUris.relativize('/word/document.xml', uri);
        final existing = package
            .relationshipsFor('/word/document.xml')
            .items
            .where((r) => r.target == target);
        if (existing.isEmpty) {
          inline.relationshipId = package
              .relationshipsFor('/word/document.xml')
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
    }
  }

  void _writeToc(XmlWriter w, WmlToc toc) {
    WordToc.ensureBody(toc);
    _writeParagraph(w, toc.titleParagraph);
    w.writeStartElement('p', prefix: 'w');
    _writePPr(w, WmlParagraphProps());
    _writeFieldChar(w, 'begin');
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('instrText', prefix: 'w');
    w.writeAttribute('xml:space', 'preserve');
    w.writeText(' TOC \\o "${toc.minLevel}-${toc.maxLevel}" \\h \\z \\u ');
    w.writeEndElement();
    w.writeEndElement();
    _writeFieldChar(w, 'separate');
    w.writeEndElement();
    final int count = toc.itemParagraphs.length;
    for (int i = 0; i < count; i++) {
      final WmlParagraph para = _copyParagraph(toc.itemParagraphs[i]);
      para.properties.tabs = <WmlTabStop>[
        WmlTabStop(
          position: 468,
          alignment: WmlTabAlignment.right,
          leader: WmlTabLeader.dot,
        ),
      ];
      if (toc.showPageNumbers && i < toc.entries.length) {
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
      properties: source.properties,
      inlines: <WmlInline>[
        for (final WmlInline inline in source.inlines)
          if (inline is WmlRun)
            WmlRun(
              text: inline.text,
              properties: inline.properties.copy(),
              hyperlink: inline.hyperlink?.copy(),
              commentIds: List<int>.from(inline.commentIds),
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
    const String uri = '/word/comments.xml';
    const String extUri = '/word/commentsExtended.xml';
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    if (document.comments.isEmpty) {
      package
          .getPart(uri)
          ?.writeText(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:comments xmlns:w="${OfficeNamespaces.w}"/>',
          );
      package
          .getPart(extUri)
          ?.writeText(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w15:commentsEx xmlns:w15="${OfficeNamespaces.w15}"/>',
          );
      return;
    }
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
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(
        uri,
        OfficeContentTypes.wordComments,
        utf8.encode(w.toXml()),
      );
    } else {
      existing.writeText(w.toXml());
    }
    if (rels.firstByType(RelationshipTypes.comments) == null) {
      rels.add(
        type: RelationshipTypes.comments,
        target: 'comments.xml',
        id: 'rIdComments',
      );
    }
    _syncCommentsExtended(document, package, rels);
  }

  void _syncCommentsExtended(
    WmlDocument document,
    OpcPackage package,
    RelationshipCollection rels,
  ) {
    const String uri = '/word/commentsExtended.xml';
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('commentsEx', prefix: 'w15');
    w.writeNamespace('w15', OfficeNamespaces.w15);
    for (final WmlComment comment in document.comments) {
      w.writeEmptyElement(
        'commentEx',
        prefix: 'w15',
        attributes: <String, String>{
          'w15:paraId': comment.id.toRadixString(16).padLeft(8, '0'),
          if (comment.parentId != null)
            'w15:paraIdParent': comment.parentId!
                .toRadixString(16)
                .padLeft(8, '0'),
          'w15:done': comment.resolved ? '1' : '0',
        },
      );
    }
    w.writeEndElement();
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(
        uri,
        OfficeContentTypes.wordCommentsExtended,
        utf8.encode(w.toXml()),
      );
    } else {
      existing.writeText(w.toXml());
    }
    if (rels.firstByType(RelationshipTypes.commentsExtended) == null) {
      rels.add(
        type: RelationshipTypes.commentsExtended,
        target: 'commentsExtended.xml',
        id: 'rIdCommentsEx',
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
  }) {
    w.writeStartElement('p', prefix: 'w');
    _writePPr(w, paragraph.properties, sectionBreak: sectionBreak);
    if (paragraph.properties.columnBreakBefore &&
        !paragraph.inlines.any(
          (WmlInline inline) =>
              inline is WmlBreak && inline.type == WmlBreakType.column,
        )) {
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('br', prefix: 'w');
      w.writeAttribute('w:type', 'column');
      w.writeEndElement();
      w.writeEndElement();
    }
    final String? bookmark = paragraph.properties.bookmarkName;
    if (bookmark != null && bookmark.isNotEmpty) {
      w.writeEmptyElement(
        'bookmarkStart',
        prefix: 'w',
        attributes: <String, String>{
          'w:id': '${bookmark.hashCode & 0x7fffffff}',
          'w:name': bookmark,
        },
      );
    }
    final String? field = paragraph.properties.fieldInstruction;
    final bool pageField =
        paragraph.properties.pageNumberField &&
        (field == null || field.trim().isEmpty);
    if (field != null && field.trim().isNotEmpty) {
      _writeFieldChar(w, 'begin');
      w.writeStartElement('r', prefix: 'w');
      w.writeStartElement('instrText', prefix: 'w');
      w.writeAttribute('xml:space', 'preserve');
      w.writeText(field);
      w.writeEndElement();
      w.writeEndElement();
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
              next.hyperlink?.displayTarget != link.displayTarget) {
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
    if (field != null && field.trim().isNotEmpty) {
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
        attributes: <String, String>{
          'w:id': '${bookmark.hashCode & 0x7fffffff}',
        },
      );
    }
    w.writeEndElement();
  }

  void _writeTrackedRun(
    XmlWriter w,
    WmlParagraph paragraph,
    WmlRun inline,
    int offset,
  ) {
    final WmlRevision? revision = _revisionAt(paragraph, offset, inline.text.length);
    if (revision == null) {
      _writeRun(w, inline);
      return;
    }
    w.writeStartElement(
      revision.kind == WmlRevisionKind.delete ? 'del' : 'ins',
      prefix: 'w',
    );
    w.writeAttribute('w:id', '${revision.id}');
    w.writeAttribute('w:author', revision.author);
    if (revision.dateIso.isNotEmpty) {
      w.writeAttribute('w:date', revision.dateIso);
    }
    _writeRun(w, inline, deleted: revision.kind == WmlRevisionKind.delete);
    w.writeEndElement();
  }

  WmlRevision? _revisionAt(WmlParagraph paragraph, int offset, int length) {
    final WmlDocument? document = _document;
    if (document == null || length <= 0) {
      return null;
    }
    var index = 0;
    for (final WmlParagraph item in document.paragraphs) {
      if (identical(item, paragraph)) {
        final int end = offset + length;
        for (final WmlRevision revision in document.revisions) {
          if (revision.paragraphIndex == index &&
              revision.start < end &&
              revision.end > offset) {
            return revision;
          }
        }
        return null;
      }
      index++;
    }
    return null;
  }

  void _writeRun(XmlWriter w, WmlRun inline, {bool deleted = false}) {
    w.writeStartElement('r', prefix: 'w');
    _writeRPr(w, inline.properties);
    if (inline.noteRefId != null) {
      w.writeEmptyElement(
        inline.noteRefEndnote ? 'endnoteReference' : 'footnoteReference',
        prefix: 'w',
        attributes: <String, String>{'w:id': '${inline.noteRefId}'},
      );
      w.writeEndElement();
      return;
    }
    _writeRunContent(w, inline.text, deleted: deleted);
    w.writeEndElement();
  }

  void _writeRunContent(XmlWriter w, String text, {required bool deleted}) {
    if (!text.contains('\t')) {
      _writeTextNode(w, text, deleted: deleted);
      return;
    }
    var start = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x09) {
        continue;
      }
      if (i > start) {
        _writeTextNode(w, text.substring(start, i), deleted: deleted);
      }
      w.writeEmptyElement('tab', prefix: 'w');
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
    for (final ({String id, String target}) existing in _externalLinks) {
      if (existing.target == target) {
        return existing.id;
      }
    }
    final String id = 'rIdLink${_externalLinks.length + 1}';
    _externalLinks.add((id: id, target: target));
    return id;
  }

  void _writePPr(
    XmlWriter w,
    WmlParagraphProps p, {
    WmlSection? sectionBreak,
  }) {
    w.writeStartElement('pPr', prefix: 'w');
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
    if (p.keepTogether) {
      w.writeEmptyElement('keepLines', prefix: 'w');
    }
    if (p.pageBreakBefore) {
      w.writeEmptyElement('pageBreakBefore', prefix: 'w');
    }
    if (p.styleId != null && p.styleId!.isNotEmpty) {
      w.writeEmptyElement(
        'pStyle',
        prefix: 'w',
        attributes: <String, String>{'w:val': p.styleId!},
      );
    }
    if (p.headingLevel != null && p.headingLevel! >= 1) {
      w.writeEmptyElement(
        'outlineLvl',
        prefix: 'w',
        attributes: <String, String>{'w:val': '${p.headingLevel! - 1}'},
      );
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
    if (p.numId != null) {
      w.writeStartElement('numPr', prefix: 'w');
      w.writeEmptyElement(
        'ilvl',
        prefix: 'w',
        attributes: <String, String>{'w:val': '${p.ilvl}'},
      );
      w.writeEmptyElement(
        'numId',
        prefix: 'w',
        attributes: <String, String>{'w:val': '${p.numId}'},
      );
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
    if (sectionBreak != null) {
      _writeSectPr(w, sectionBreak);
    }
    w.writeEndElement();
  }

  void _writeRPr(XmlWriter w, WmlRunProps r) {
    w.writeStartElement('rPr', prefix: 'w');
    if (r.bold) {
      w.writeEmptyElement('b', prefix: 'w');
    }
    if (r.italic) {
      w.writeEmptyElement('i', prefix: 'w');
    }
    if (r.strike) {
      w.writeEmptyElement('strike', prefix: 'w');
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
    w.writeEmptyElement(
      'color',
      prefix: 'w',
      attributes: <String, String>{'w:val': r.color},
    );
    if (r.highlight != null) {
      w.writeEmptyElement(
        'highlight',
        prefix: 'w',
        attributes: <String, String>{'w:val': r.highlight!},
      );
    }
    w.writeEmptyElement(
      'sz',
      prefix: 'w',
      attributes: <String, String>{'w:val': '${r.fontSizeHalfPoints}'},
    );
    w.writeEmptyElement(
      'rFonts',
      prefix: 'w',
      attributes: <String, String>{
        'w:ascii': r.asciiFont,
        'w:hAnsi': r.asciiFont,
        'w:cs': r.csFont,
      },
    );
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
    w.writeStartElement('tblPr', prefix: 'w');
    if (table.properties.rightToLeft) {
      w.writeEmptyElement('bidiVisual', prefix: 'w');
    }
    w.writeEmptyElement(
      'jc',
      prefix: 'w',
      attributes: <String, String>{
        'w:val': switch (table.properties.alignment) {
          WmlJustification.center => 'center',
          WmlJustification.right => 'right',
          WmlJustification.justify => 'both',
          WmlJustification.distributed => 'distribute',
          WmlJustification.left => 'left',
        },
      },
    );
    if (table.properties.borders) {
      final String color = table.properties.borderColor ?? 'BFBFBF';
      w.writeStartElement('tblBorders', prefix: 'w');
      for (final String edge in <String>[
        'top',
        'left',
        'bottom',
        'right',
        'insideH',
        'insideV',
      ]) {
        w.writeEmptyElement(
          edge,
          prefix: 'w',
          attributes: <String, String>{
            'w:val': 'single',
            'w:sz': '4',
            'w:space': '0',
            'w:color': color,
          },
        );
      }
      w.writeEndElement();
    }
    w.writeEndElement();
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
      writeBlock: (XmlWriter inner, WmlBlock child) {
        _writeBlock(inner, child, imageIds);
      },
      docPrId: _docPrId++,
    );
  }

  void _writeSectPr(XmlWriter w, WmlSection section) {
    w.writeStartElement('sectPr', prefix: 'w');
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
    w.writeEmptyElement(
      'cols',
      prefix: 'w',
      attributes: <String, String>{
        'w:num': '${section.resolvedColumnCount}',
        'w:space': '${pointsToTwips(section.columnSpace)}',
        if (section.columnSep) 'w:sep': '1',
      },
    );
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
    if (section.differentFirstPage) {
      w.writeEmptyElement('titlePg', prefix: 'w');
    }
    if (section.lineNumbers) {
      w.writeEmptyElement(
        'lnNumType',
        prefix: 'w',
        attributes: <String, String>{'w:countBy': '1'},
      );
    }
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
      ref(ids.footer, 'footerReference', 'default');
      ref(ids.firstHeader, 'headerReference', 'first');
      ref(ids.firstFooter, 'footerReference', 'first');
      ref(ids.evenHeader, 'headerReference', 'even');
      ref(ids.evenFooter, 'footerReference', 'even');
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
        _ColumnSlice(const <WmlBlock>[], section.columnCount, section.breakKind),
      ];
    }
    return <_ColumnSlice>[
      _ColumnSlice(slices.first.blocks, slices.first.columnCount, section.breakKind),
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
          header: true,
          watermark: i == 0 ? watermark : '',
        ),
        footer: _writeHfPart(package, section.footer, header: false),
        firstHeader: _writeHfPart(package, section.firstHeader, header: true),
        firstFooter: _writeHfPart(package, section.firstFooter, header: false),
        evenHeader: _writeHfPart(package, section.evenHeader, header: true),
        evenFooter: _writeHfPart(package, section.evenFooter, header: false),
      );
    }
    return map;
  }

  String? _writeHfPart(
    OpcPackage package,
    List<WmlParagraph> story, {
    required bool header,
    String watermark = '',
  }) {
    if (story.isEmpty && watermark.isEmpty) {
      return null;
    }
    final int n = _hfPart++;
    final String name = header ? 'header$n.xml' : 'footer$n.xml';
    final String uri = '/word/$name';
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(header ? 'hdr' : 'ftr', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    if (watermark.isNotEmpty) {
      w.writeNamespace('v', OfficeNamespaces.v);
      w.writeNamespace('o', OfficeNamespaces.o);
    }
    for (final WmlParagraph paragraph in story) {
      _writeParagraph(w, paragraph);
    }
    if (watermark.isNotEmpty) {
      _writeVmlWatermark(w, watermark);
    }
    w.writeEndElement();
    return _putNamedPart(
      package,
      uri,
      header ? OfficeContentTypes.wordHeader : OfficeContentTypes.wordFooter,
      w.toXml(),
      header ? RelationshipTypes.header : RelationshipTypes.footer,
      name,
    );
  }

  void _syncSettings(WmlDocument document, OpcPackage package) {
    const String uri = '/word/settings.xml';
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('settings', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    if (document.trackRevisions) {
      w.writeEmptyElement('trackRevisions', prefix: 'w');
    }
    if (document.restrictEditing) {
      w.writeEmptyElement(
        'documentProtection',
        prefix: 'w',
        attributes: <String, String>{'w:enforcement': '1'},
      );
    }
    if (document.sections.any((WmlSection s) => s.differentOddEven)) {
      w.writeEmptyElement('evenAndOddHeaders', prefix: 'w');
    }
    w.writeEndElement();
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordSettings,
      w.toXml(),
      RelationshipTypes.settings,
      'settings.xml',
    );
  }

  String _putNamedPart(
    OpcPackage package,
    String uri,
    String contentType,
    String xml,
    String relType,
    String target,
  ) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, contentType, utf8.encode(xml));
    } else {
      existing.writeText(xml);
    }
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    for (final PackageRelationship rel in rels.items) {
      if (rel.target == target) {
        return rel.id;
      }
    }
    return rels.add(type: relType, target: target).id;
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

  void _syncCitations(WmlDocument document, OpcPackage package) {
    if (document.citations.isEmpty && document.indexMarks.isEmpty) {
      return;
    }
    final StringBuffer sources = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<b:Sources xmlns:b="http://schemas.openxmlformats.org/officeDocument/2006/bibliography">',
    );
    for (final WmlCitation citation in document.citations) {
      sources.write(
        '<b:Source><b:Tag>${_xmlEscape(citation.tag)}</b:Tag>'
        '<b:Author>${_xmlEscape(citation.author)}</b:Author>'
        '<b:Title>${_xmlEscape(citation.title)}</b:Title>'
        '<b:Year>${_xmlEscape(citation.year)}</b:Year></b:Source>',
      );
    }
    sources.write('</b:Sources>');
    final String xml = sources.toString();
    for (final String uri in <String>[
      '/customXml/sources.xml',
      '/customXml/item1.xml',
    ]) {
      final PackagePart? existing = package.getPart(uri);
      if (existing == null) {
        package.createPart(uri, 'application/xml', utf8.encode(xml));
      } else {
        existing.writeText(xml);
      }
    }
  }

  void _syncNumbering(OpcPackage package) {
    const String uri = '/word/numbering.xml';
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
          attributes: <String, String>{
            'w:val': bullet ? 'bullet' : 'decimal',
          },
        );
        final String lvlText = bullet
            ? (ilvl == 0
                  ? '•'
                  : ilvl == 1
                  ? '◦'
                  : '▪')
            : List<String>.generate(ilvl + 1, (int i) => '%${i + 1}').join('.');
        w.writeEmptyElement(
          'lvlText',
          prefix: 'w',
          attributes: <String, String>{'w:val': lvlText},
        );
        if (ilvl > 0) {
          w.writeEmptyElement(
            'lvlRestart',
            prefix: 'w',
            attributes: <String, String>{'w:val': '$ilvl'},
          );
        }
        w.writeStartElement('pPr', prefix: 'w');
        w.writeStartElement('ind', prefix: 'w');
        w.writeAttribute('w:left', '${(ilvl + 1) * 360}');
        w.writeAttribute('w:hanging', '180');
        w.writeEndElement();
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
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
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordNumbering,
      w.toXml(),
      RelationshipTypes.numbering,
      'numbering.xml',
    );
  }

  void _syncStyles(WmlDocument document, OpcPackage package) {
    const String uri = '/word/styles.xml';
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('styles', prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
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
    final Iterable<WmlStyle> styles =
        document.styles.isEmpty ? WordStyles.all : document.styles;
    for (final WmlStyle style in styles) {
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
      w.writeStartElement('spacing', prefix: 'w');
      w.writeAttribute('w:before', '${pointsToTwips(style.spacingBefore)}');
      w.writeAttribute('w:after', '${pointsToTwips(style.spacingAfter)}');
      w.writeEndElement();
      if (style.headingLevel != null) {
        w.writeEmptyElement(
          'outlineLvl',
          prefix: 'w',
          attributes: <String, String>{'w:val': '${style.headingLevel! - 1}'},
        );
      }
      w.writeEndElement();
      w.writeStartElement('rPr', prefix: 'w');
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
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
    _putPart(
      package,
      uri,
      OfficeContentTypes.wordStyles,
      w.toXml(),
      RelationshipTypes.styles,
      'styles.xml',
    );
  }

  void _syncNotes(WmlDocument document, OpcPackage package) {
    _writeNotesPart(
      package,
      document.footnotes,
      '/word/footnotes.xml',
      OfficeContentTypes.wordFootnotes,
      RelationshipTypes.footnotes,
      'footnotes.xml',
      'footnotes',
      'footnote',
    );
    _writeNotesPart(
      package,
      document.endnotes,
      '/word/endnotes.xml',
      OfficeContentTypes.wordEndnotes,
      RelationshipTypes.endnotes,
      'endnotes.xml',
      'endnotes',
      'endnote',
    );
  }

  void _writeNotesPart(
    OpcPackage package,
    List<WmlNote> notes,
    String uri,
    String contentType,
    String relType,
    String target,
    String root,
    String item,
  ) {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(root, prefix: 'w');
    w.writeNamespace('w', OfficeNamespaces.w);
    for (final WmlNote note in notes) {
      w.writeStartElement(item, prefix: 'w');
      w.writeAttribute('w:id', '${note.id}');
      for (final WmlParagraph paragraph in note.paragraphs) {
        _writeParagraph(w, paragraph);
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    _putPart(package, uri, contentType, w.toXml(), relType, target);
  }

  void _putPart(
    OpcPackage package,
    String uri,
    String contentType,
    String xml,
    String relType,
    String target,
  ) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, contentType, utf8.encode(xml));
    } else {
      existing.writeText(xml);
    }
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    if (rels.firstByType(relType) == null) {
      rels.add(type: relType, target: target);
    }
  }

  static String _xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
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
