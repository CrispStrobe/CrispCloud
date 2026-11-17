import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../opc/zip/zip_writer.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';
import '../properties/wml_properties.dart';

/// Bounded new-document ODT writer for the shared Word model.
///
/// This is an export path. It emits the modeled text, paragraph/run formatting,
/// tables, pictures, frames, page geometry and basic headers/footers. It does
/// not claim to preserve arbitrary imported ODF XML or every Word feature.
/// Word and Zotero fields export their visible cached results; their native
/// instructions and editable field metadata are not part of this export.
abstract final class OdtDocumentWriter {
  /// Serializes [document] as a new ODT package.
  static Uint8List writeBytes(WmlDocument document) {
    final layout = _OdtLayout(document);
    final body = _bodyXml(layout);
    final styles = _stylesXml(document, layout);
    final content = _contentXml(body, layout);
    final manifest = _manifestXml(layout.media);
    final meta = _metaXml(document);
    final zip = ZipWriter();
    zip.addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    );
    zip.addFile('META-INF/manifest.xml', utf8.encode(manifest));
    zip.addFile('content.xml', utf8.encode(content));
    zip.addFile('styles.xml', utf8.encode(styles));
    zip.addFile('meta.xml', utf8.encode(meta));
    for (final entry in layout.mediaBytes.entries) {
      zip.addFile(entry.key, entry.value);
    }
    return zip.close();
  }

  static const _mime = 'application/vnd.oasis.opendocument.text';

  static List<({String xml, _OdtSectionStart start})> _bodyXml(
    _OdtLayout layout,
  ) {
    final parts = <({String xml, _OdtSectionStart start})>[];
    for (var index = 0; index < layout.sections.length; index++) {
      final body = XmlWriter();
      final section = layout.sections[index];
      final start = layout.sectionStarts[index];
      _writeBlocks(body, section.blocks, layout, sectionStart: start);
      // Empty and entirely unmodeled sections still own a page boundary. The
      // small empty anchor cannot consume a later section's first paragraph.
      if (!start.consumed) {
        start.empty = true;
        _writeSectionAnchor(body, layout, start);
      }
      parts.add((xml: body.toXml(), start: start));
    }
    return parts;
  }

  static String _contentXml(
    List<({String xml, _OdtSectionStart start})> body,
    _OdtLayout layout,
  ) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-content', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeContentStyles(w);
    w.writeEndElement();
    w.writeStartElement('body', prefix: 'office');
    w.writeStartElement('text', prefix: 'office');
    for (final part in body) {
      final start = part.start;
      if (start.empty &&
          start.index > 0 &&
          start.kind == WmlSectionBreakKind.continuous &&
          start.masterPage == null) {
        continue;
      }
      w.writeRaw(part.xml);
    }
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _stylesXml(WmlDocument document, _OdtLayout layout) {
    // Master-page stories use automatic styles in styles.xml, while body
    // stories use those in content.xml. Keep the style registries separate and
    // share the package media registry so header/footer pictures cannot collide.
    final stories = _OdtLayout(document, sharedMedia: layout);
    final master = XmlWriter();
    master.writeStartElement('master-styles', prefix: 'office');
    String? previousPageKey;
    for (var index = 0; index < layout.sections.length; index++) {
      final section = layout.sections[index];
      final story = XmlWriter();
      if (section.header.isNotEmpty) {
        story.writeStartElement('header', prefix: 'style');
        stories.withListStory(
          () => _writeBlocks(story, section.header, stories),
        );
        story.writeEndElement();
      }
      if (section.footer.isNotEmpty) {
        story.writeStartElement('footer', prefix: 'style');
        stories.withListStory(
          () => _writeBlocks(story, section.footer, stories),
        );
        story.writeEndElement();
      }
      final storyXml = story.toXml();
      final pageKey =
          '${_pageLayoutKey(section)}|${_storyKey(storyXml, section, stories)}';
      if (index > 0 &&
          section.breakKind == WmlSectionBreakKind.continuous &&
          pageKey == previousPageKey) {
        // Selecting even an equivalent new master inserts a page break in
        // ODF. Reuse the current master for a continuous, unchanged page style.
        layout.sectionStarts[index].masterPage = null;
      }
      previousPageKey = pageKey;
      final name = index == 0 ? 'Standard' : 'mp$index';
      void writeMaster(
        String masterName,
        String pageLayout, {
        String? next,
        String? contents,
      }) {
        master.writeStartElement('master-page', prefix: 'style');
        master.writeAttribute('style:name', masterName);
        master.writeAttribute('style:page-layout-name', pageLayout);
        if (next != null) master.writeAttribute('style:next-style-name', next);
        master.writeRaw(contents ?? storyXml);
        master.writeEndElement();
      }

      if (layout.sectionStarts[index].parity != null) {
        // The entry and continuation masters repeat visible stories, but a
        // shared annotation definition must appear only once in the package.
        writeMaster(name, 'pm$index', contents: _withoutAnnotations(storyXml));
        writeMaster('${name}Start', 'pm${index}Start', next: name);
      } else {
        writeMaster(name, 'pm$index');
      }
    }
    master.writeEndElement();

    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-styles', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('styles', prefix: 'office');
    w.writeStartElement('default-style', prefix: 'style');
    w.writeAttribute('style:family', 'paragraph');
    w.writeStartElement('paragraph-properties', prefix: 'style');
    w.writeAttribute('fo:margin-top', '0in');
    w.writeAttribute('fo:margin-bottom', '0.08in');
    w.writeEndElement();
    w.writeStartElement('text-properties', prefix: 'style');
    w.writeAttribute('fo:font-family', 'Arial');
    w.writeAttribute('fo:font-size', '11pt');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'style',
      prefix: 'style',
      attributes: {'style:name': 'Standard', 'style:family': 'paragraph'},
    );
    for (var level = 1; level <= 9; level++) {
      w.writeStartElement('style', prefix: 'style');
      w.writeAttribute('style:name', 'Heading_20_$level');
      w.writeAttribute('style:family', 'paragraph');
      w.writeAttribute('style:parent-style-name', 'Standard');
      w.writeAttribute('style:default-outline-level', '$level');
      w.writeStartElement('text-properties', prefix: 'style');
      w.writeAttribute('fo:font-weight', 'bold');
      w.writeAttribute('fo:font-size', '${24 - level * 2}pt');
      w.writeEndElement();
      w.writeEndElement();
    }
    for (final ordered in <bool>[false, true]) {
      w.writeStartElement('list-style', prefix: 'text');
      w.writeAttribute('style:name', ordered ? 'L2' : 'L1');
      for (var level = 1; level <= 9; level++) {
        w.writeStartElement(
          ordered ? 'list-level-style-number' : 'list-level-style-bullet',
          prefix: 'text',
        );
        w.writeAttribute('text:level', '$level');
        if (ordered) {
          w.writeAttribute('style:num-format', '1');
          w.writeAttribute('style:num-suffix', '.');
        } else {
          w.writeAttribute('text:bullet-char', '•');
        }
        w.writeStartElement('list-level-properties', prefix: 'style');
        w.writeAttribute(
          'text:list-level-position-and-space-mode',
          'label-alignment',
        );
        w.writeEmptyElement(
          'list-level-label-alignment',
          prefix: 'style',
          attributes: {
            'text:label-followed-by': 'listtab',
            'text:list-tab-stop-position': '${level * 0.25}in',
            'fo:margin-left': '${level * 0.25}in',
            'fo:text-indent': '-0.25in',
          },
        );
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeStartElement('automatic-styles', prefix: 'office');
    for (var index = 0; index < layout.sections.length; index++) {
      final section = layout.sections[index];
      final page = section.pageSize;
      final margins = section.margins;
      void writePageLayout(String name, {String? usage}) {
        w.writeStartElement('page-layout', prefix: 'style');
        w.writeAttribute('style:name', name);
        if (usage != null) w.writeAttribute('style:page-usage', usage);
        w.writeStartElement('page-layout-properties', prefix: 'style');
        w.writeAttribute('fo:page-width', '${page.width.toStringAsFixed(2)}pt');
        w.writeAttribute(
          'fo:page-height',
          '${page.height.toStringAsFixed(2)}pt',
        );
        w.writeAttribute(
          'fo:margin-top',
          '${margins.top.toStringAsFixed(2)}pt',
        );
        w.writeAttribute(
          'fo:margin-bottom',
          '${margins.bottom.toStringAsFixed(2)}pt',
        );
        w.writeAttribute(
          'fo:margin-left',
          '${margins.left.toStringAsFixed(2)}pt',
        );
        w.writeAttribute(
          'fo:margin-right',
          '${margins.right.toStringAsFixed(2)}pt',
        );
        w.writeEndElement();
        w.writeEndElement();
      }

      writePageLayout('pm$index');
      if (layout.sectionStarts[index].parity case final parity?) {
        writePageLayout('pm${index}Start', usage: parity);
      }
    }
    stories.writeContentStyles(w);
    w.writeEndElement();
    w.writeRaw(master.toXml());
    w.writeEndElement();
    return w.toXml();
  }

  static String _pageLayoutKey(WmlSection section) => <double>[
    section.pageSize.width,
    section.pageSize.height,
    section.margins.top,
    section.margins.bottom,
    section.margins.left,
    section.margins.right,
  ].map((value) => value.toStringAsFixed(2)).join('|');

  static XmlElement _storyRoot(String xml) {
    final envelope = XmlWriter();
    envelope.writeStartElement('master-styles', prefix: 'office');
    _namespaces(envelope);
    envelope.writeRaw(xml);
    envelope.writeEndElement();
    return XmlDocument.parse(envelope.toXml()).root!;
  }

  static void _removeAnnotations(XmlElement element) {
    element.children.removeWhere(
      (node) =>
          node is XmlElement &&
          node.localName == 'annotation' &&
          node.namespaceUri ==
              'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    );
    for (final child in element.childElements) {
      _removeAnnotations(child);
    }
  }

  static String _withoutAnnotations(String xml) {
    final root = _storyRoot(xml);
    _removeAnnotations(root);
    final result = XmlWriter();
    for (final child in root.children) {
      child.writeTo(result);
    }
    return result.toXml();
  }

  static String _storyKey(String xml, WmlSection section, _OdtLayout layout) {
    final root = _storyRoot(xml);
    // Annotation emission is deliberately shared across all stories. Its
    // bookkeeping must not turn repeated authored headers into new pages;
    // compare their reference positions below instead of emitted bodies.
    _removeAnnotations(root);
    void normalize(XmlElement element) {
      if (element.localName == 'image' &&
          element.namespaceUri ==
              'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0') {
        final path = element.getAttribute(
          'href',
          namespaceUri: 'http://www.w3.org/1999/xlink',
        );
        final bytes = layout.mediaBytes[path];
        if (bytes != null) {
          // This is only a comparison key, never an emitted package URL.
          element.setAttribute(
            'href',
            base64Encode(bytes),
            prefix: 'xlink',
            namespaceUri: 'http://www.w3.org/1999/xlink',
          );
        }
      }
      for (final child in element.childElements) {
        normalize(child);
      }
    }

    normalize(root);
    final normalized = XmlWriter();
    root.writeTo(normalized);
    final commentReferences = [
      for (final paragraphs in [section.header, section.footer])
        [
          for (final paragraph in paragraphs)
            [
              for (final run in paragraph.inlines.whereType<WmlRun>())
                run.commentIds,
            ],
        ],
    ];
    return '${normalized.toXml()}|${jsonEncode(commentReferences)}';
  }

  static void _namespaces(XmlWriter w) {
    w.writeNamespace(
      'office',
      'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    );
    w.writeNamespace(
      'style',
      'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    );
    w.writeNamespace('text', 'urn:oasis:names:tc:opendocument:xmlns:text:1.0');
    w.writeNamespace(
      'table',
      'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    );
    w.writeNamespace(
      'draw',
      'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    );
    w.writeNamespace(
      'fo',
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    );
    w.writeNamespace(
      'svg',
      'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    );
    w.writeNamespace('xlink', 'http://www.w3.org/1999/xlink');
    w.writeNamespace('dc', 'http://purl.org/dc/elements/1.1/');
    w.writeNamespace('meta', 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0');
  }

  static void _writeBlocks(
    XmlWriter w,
    List<WmlBlock> blocks,
    _OdtLayout layout, {
    _OdtSectionStart? sectionStart,
  }) {
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final start = sectionStart?.consumed == false ? sectionStart : null;
      if (block is WmlParagraph &&
          block.properties.numId != null &&
          block.properties.numId != 0 &&
          !block.properties.numberingSuppressed) {
        final list = <WmlParagraph>[block];
        while (index + 1 < blocks.length) {
          final next = blocks[index + 1];
          if (next is! WmlParagraph ||
              next.properties.numId != block.properties.numId ||
              next.properties.numId == 0 ||
              next.properties.numberingSuppressed) {
            break;
          }
          list.add(next);
          index++;
        }
        final style = _sectionParagraphStyle(layout, start, block.properties);
        _writeList(w, list, layout, firstParagraphStyle: style);
      } else {
        _writeBlock(w, block, layout, sectionStart: start);
      }
    }
  }

  static void _writeList(
    XmlWriter w,
    List<WmlParagraph> paragraphs,
    _OdtLayout layout, {
    String? firstParagraphStyle,
  }) {
    final roots = <_OdtListItem>[];
    final stack = <_OdtListItem>[];
    for (final paragraph in paragraphs) {
      final item = _OdtListItem(paragraph, layout.listMarker(paragraph));
      // Compare authored levels, not their normalized output depth. Otherwise
      // a skipped level such as 0,3,3 accidentally turns the second level-3
      // paragraph into a grandchild. A missing ancestor needs no invented item.
      while (stack.isNotEmpty && stack.last.level >= item.level) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(item);
      } else {
        stack.last.children.add(item);
      }
      stack.add(item);
    }
    var first = true;
    void writeItems(List<_OdtListItem> items) {
      String? previousStyle;
      for (final item in items) {
        final style = layout.listStyle(item.marker);
        if (previousStyle != style) {
          if (previousStyle != null) w.writeEndElement();
          w.writeStartElement('list', prefix: 'text');
          w.writeAttribute('text:style-name', style);
          previousStyle = style;
        }
        w.writeStartElement('list-item', prefix: 'text');
        if (item.marker.start case final start?) {
          w.writeAttribute('text:start-value', '$start');
        }
        final override = first ? firstParagraphStyle : null;
        first = false;
        _writeParagraph(w, item.paragraph, layout, styleOverride: override);
        if (item.children.isNotEmpty) writeItems(item.children);
        w.writeEndElement();
      }
      if (previousStyle != null) w.writeEndElement();
    }

    writeItems(roots);
  }

  static void _writeBlock(
    XmlWriter w,
    WmlBlock block,
    _OdtLayout layout, {
    _OdtSectionStart? sectionStart,
  }) {
    switch (block) {
      case WmlParagraph():
        _writeParagraph(
          w,
          block,
          layout,
          styleOverride: _sectionParagraphStyle(
            layout,
            sectionStart,
            block.properties,
          ),
        );
      case WmlTable():
        if (layout.inNoteBody) {
          _writeNoteTableText(w, block, layout);
        } else {
          _writeTable(w, block, layout, sectionStart: sectionStart);
          sectionStart?.consumed = true;
        }
      case WmlVisual():
        w.writeStartElement('p', prefix: 'text');
        final style = _sectionParagraphStyle(
          layout,
          sectionStart,
          WmlParagraphProps(),
        );
        if (style != null) w.writeAttribute('text:style-name', style);
        _writeVisual(w, block.visual, layout, inline: true);
        w.writeEndElement();
      case WmlFrame():
        if (sectionStart != null) {
          w.writeStartElement('p', prefix: 'text');
          w.writeAttribute(
            'text:style-name',
            layout.paragraphStyle(
              WmlParagraphProps(),
              sectionStart: sectionStart,
              emptyAnchor: true,
            ),
          );
          sectionStart.consumed = true;
          _writeFrame(w, block, layout, inParagraph: true);
          w.writeEndElement();
        } else {
          _writeFrame(w, block, layout);
        }
      case WmlEquation():
        break;
      case WmlContentControlBlock():
        _writeBlocks(w, block.blocks, layout, sectionStart: sectionStart);
      case WmlOpaqueBlock() || WmlToc():
        break;
    }
  }

  static String? _sectionParagraphStyle(
    _OdtLayout layout,
    _OdtSectionStart? start,
    WmlParagraphProps properties,
  ) {
    if (start == null) return null;
    start.consumed = true;
    if (start.index == 0) return null;
    return layout.paragraphStyle(
      properties,
      heading: properties.headingLevel,
      sectionStart: start,
    );
  }

  static void _writeSectionAnchor(
    XmlWriter w,
    _OdtLayout layout,
    _OdtSectionStart start,
  ) {
    w.writeStartElement('p', prefix: 'text');
    w.writeAttribute(
      'text:style-name',
      layout.paragraphStyle(
        WmlParagraphProps(),
        sectionStart: start,
        emptyAnchor: true,
      ),
    );
    start.consumed = true;
    w.writeEndElement();
  }

  static void _writeParagraph(
    XmlWriter w,
    WmlParagraph paragraph,
    _OdtLayout layout, {
    String? styleOverride,
  }) {
    final heading = paragraph.properties.headingLevel;
    // An annotation accepts paragraphs and lists, not heading elements. Keep
    // its resolved heading style without emitting an illegal child element.
    final tag = heading == null || layout.inCommentBody ? 'p' : 'h';
    w.writeStartElement(tag, prefix: 'text');
    if (heading != null && !layout.inCommentBody) {
      w.writeAttribute('text:outline-level', '${heading.clamp(1, 9)}');
    }
    w.writeAttribute(
      'text:style-name',
      styleOverride ??
          layout.paragraphStyle(paragraph.properties, heading: heading),
    );
    if (layout.noteReferenceSpacePending) {
      layout.noteReferenceSpacePending = false;
      final text = paragraph.text;
      if (text.isNotEmpty && !RegExp(r'^\s').hasMatch(text)) {
        writeOdfText(w, ' ');
      }
    }
    for (final inline in paragraph.inlines) {
      _writeInline(w, inline, layout);
    }
    w.writeEndElement();
  }

  static void _writeInline(XmlWriter w, WmlInline inline, _OdtLayout layout) {
    switch (inline) {
      case WmlRun():
        final style = layout.runStyle(inline.properties);
        final href = inline.hyperlink?.url;
        final commentLink =
            layout.inCommentBody && href != null && href.isNotEmpty;
        if (href != null && href.isNotEmpty) {
          w.writeStartElement('a', prefix: 'text');
          w.writeAttribute('xlink:href', href);
          w.writeAttribute('xlink:type', 'simple');
          // Writer's annotation importer loses link text nested in a span.
          // text:a can carry the same style directly, with its text unchanged.
          if (commentLink) w.writeAttribute('text:style-name', style);
        }
        if (inline.noteRefId != null) {
          final note = layout.notes.resolve(inline);
          if (note != null) {
            final label = layout.notes.labelFor(inline, note);
            if (layout.noteBodiesAllowed) {
              w.writeStartElement('span', prefix: 'text');
              w.writeAttribute('text:style-name', style);
              _writeNote(w, inline, note, label, layout);
              w.writeEndElement();
            } else {
              _writeStyledText(w, label, style, styleOnParent: commentLink);
            }
          } else {
            // Missing or ambiguous definitions must not erase cached text.
            _writeStyledText(w, inline.text, style, styleOnParent: commentLink);
          }
        } else {
          _writeStyledText(w, inline.text, style, styleOnParent: commentLink);
        }
        if (inline.inlineVisual case final visual?) {
          _writeVisual(w, visual.visual, layout, inline: true);
        }
        if (href != null && href.isNotEmpty) w.writeEndElement();
        if (layout.commentsAllowed) {
          for (final commentId in inline.commentIds) {
            final comment = layout.comments.definitions[commentId];
            final eligible =
                layout.noteBodiesAllowed ||
                !layout.comments.bodyAnchors.contains(commentId);
            if (comment != null &&
                eligible &&
                layout.comments.emitted.add(commentId)) {
              _writeComment(w, comment, layout);
            }
          }
        }
      case WmlBreak():
        w.writeEmptyElement(
          inline.type == WmlBreakType.textWrapping
              ? 'line-break'
              : 'soft-page-break',
          prefix: 'text',
        );
      case WmlFieldBoundary():
        // Instructions are hidden field metadata, not document text. The
        // surrounding result runs remain in the inline sequence, including
        // citations and bibliographies that span several paragraphs.
        break;
      case WmlContentControlBoundary() ||
          WmlNoteMarker() ||
          WmlBookmarkBoundary():
        break;
      case WmlObject():
      case WmlOpaqueInline():
        break;
    }
  }

  static void _writeStyledText(
    XmlWriter w,
    String text,
    String style, {
    bool styleOnParent = false,
  }) {
    if (text.isEmpty) return;
    if (styleOnParent) {
      writeOdfText(w, text);
      return;
    }
    w.writeStartElement('span', prefix: 'text');
    w.writeAttribute('text:style-name', style);
    writeOdfText(w, text);
    w.writeEndElement();
  }

  static void _writeComment(
    XmlWriter w,
    WmlComment comment,
    _OdtLayout layout,
  ) {
    w.writeStartElement('annotation', prefix: 'office');
    w.writeAttribute('office:display', 'true');
    if (comment.author.isNotEmpty) {
      w.writeStartElement('creator', prefix: 'dc');
      w.writeText(comment.author);
      w.writeEndElement();
    }
    if (comment.dateIso.isNotEmpty) {
      final validDate = _OdtComments.isDateTime(comment.dateIso);
      w.writeStartElement(
        validDate ? 'date' : 'date-string',
        prefix: validDate ? 'dc' : 'meta',
      );
      w.writeText(comment.dateIso);
      w.writeEndElement();
    }
    if (comment.initials.isNotEmpty) {
      w.writeStartElement('creator-initials', prefix: 'meta');
      w.writeText(comment.initials);
      w.writeEndElement();
    }
    final previousComments = layout.commentsAllowed;
    final previousCommentBody = layout.inCommentBody;
    final previousNotes = layout.noteBodiesAllowed;
    final previousReferenceSpace = layout.noteReferenceSpacePending;
    layout.commentsAllowed = false;
    layout.inCommentBody = true;
    layout.noteBodiesAllowed = false;
    layout.noteReferenceSpacePending = false;
    try {
      // Comments are a separate story. Nested comment IDs must not consume a
      // later visible anchor, and note references retain marks without moving
      // their bodies here. This also bounds recursive comment/note expansion.
      layout.withListStory(() => _writeBlocks(w, comment.paragraphs, layout));
      for (final visual in comment.visuals) {
        w.writeStartElement('p', prefix: 'text');
        _writeVisual(w, visual.visual, layout, inline: true);
        w.writeEndElement();
      }
      if (comment.paragraphs.isEmpty && comment.visuals.isEmpty) {
        _writePlainParagraph(w, '');
      }
    } finally {
      layout.commentsAllowed = previousComments;
      layout.inCommentBody = previousCommentBody;
      layout.noteBodiesAllowed = previousNotes;
      layout.noteReferenceSpacePending = previousReferenceSpace;
    }
    w.writeEndElement();
  }

  static void _writeNote(
    XmlWriter w,
    WmlRun reference,
    WmlNote note,
    String label,
    _OdtLayout layout,
  ) {
    final key = (reference.noteRefEndnote, reference.noteRefId!);
    final noteClass = reference.noteRefEndnote ? 'endnote' : 'footnote';
    final existing = layout.notes.emitted[key];
    if (existing != null) {
      // A differently authored cached mark cannot be represented by a field
      // which a consumer would replace with the first citation's label.
      if (existing.label != label) {
        writeOdfText(w, label);
        return;
      }
      w.writeStartElement('note-ref', prefix: 'text');
      w.writeAttribute('text:ref-name', existing.id);
      w.writeAttribute('text:note-class', noteClass);
      w.writeAttribute('text:reference-format', 'text');
      w.writeText(label);
      w.writeEndElement();
      return;
    }
    final record = _OdtNoteRecord(
      '${reference.noteRefEndnote ? 'end' : 'ftn'}${layout.notes.emitted.length + 1}',
      label,
    );
    layout.notes.emitted[key] = record;
    w.writeStartElement('note', prefix: 'text');
    w.writeAttribute('text:note-class', noteClass);
    w.writeAttribute('text:id', record.id);
    w.writeStartElement('note-citation', prefix: 'text');
    // ODF consumers can renumber the character data when text:label is absent.
    // Preserve the resolved Word label, including custom and Roman marks.
    // LibreOffice treats an empty fixed label as automatic numbering. Keep
    // empty character data, using only a nonprinting metadata label to suppress
    // the extra numeral beside an independently authored custom mark.
    w.writeAttribute('text:label', label.isEmpty ? '\u2060' : label);
    w.writeText(label);
    w.writeEndElement();
    w.writeStartElement('note-body', prefix: 'text');
    final previous = layout.noteBodiesAllowed;
    final previousNoteBody = layout.inNoteBody;
    final previousReferenceSpace = layout.noteReferenceSpacePending;
    layout.noteBodiesAllowed = false;
    layout.inNoteBody = true;
    layout.noteReferenceSpacePending =
        label.isNotEmpty &&
        note.addReference &&
        note.addReferenceSpace &&
        !note.hasReferenceMarkers;
    try {
      if (note.blocks.isEmpty) {
        _writePlainParagraph(w, '');
      } else {
        layout.withListStory(() => _writeBlocks(w, note.blocks, layout));
      }
    } finally {
      layout.noteBodiesAllowed = previous;
      layout.inNoteBody = previousNoteBody;
      layout.noteReferenceSpacePending = previousReferenceSpace;
    }
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeNoteTableText(
    XmlWriter w,
    WmlTable table,
    _OdtLayout layout,
  ) {
    // The tested Writer consumer silently omits tables inside note bodies.
    // Preserve visible cell stories as paragraphs in physical source order;
    // ordinary body/frame tables retain their structural export.
    final cells = _OdtTableCells(table);
    void blank() {
      _writePlainParagraph(w, '');
      layout.noteReferenceSpacePending = false;
    }

    if (table.rows.isEmpty) blank();
    for (var row = 0; row < table.rows.length; row++) {
      if (table.rows[row].cells.isEmpty) blank();
      for (var column = 0; column < table.rows[row].cells.length; column++) {
        if (cells.rows[row][column].covered) continue;
        final blocks = table.rows[row].cells[column].blocks;
        if (blocks.isEmpty) {
          blank();
        } else {
          _writeBlocks(w, blocks, layout);
        }
      }
    }
  }

  static void _writeTable(
    XmlWriter w,
    WmlTable table,
    _OdtLayout layout, {
    _OdtSectionStart? sectionStart,
  }) {
    final cells = _OdtTableCells(table);
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', 'Table${layout.tableCount++}');
    w.writeAttribute(
      'table:style-name',
      layout.tableStyle(sectionStart: sectionStart),
    );
    for (final width in table.grid) {
      w.writeStartElement('table-column', prefix: 'table');
      w.writeAttribute('table:style-name', layout.columnStyle(width));
      w.writeEndElement();
    }
    final inferredColumns = cells.columnCount - BigInt.from(table.grid.length);
    if (inferredColumns > BigInt.zero) {
      w.writeEmptyElement(
        'table-column',
        prefix: 'table',
        attributes: inferredColumns == BigInt.one
            ? null
            : {'table:number-columns-repeated': '$inferredColumns'},
      );
    }
    if (table.rows.isEmpty) {
      w.writeStartElement('table-row', prefix: 'table');
      _writeOmittedCells(w, cells.columnCount);
      w.writeEndElement();
    }
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      w.writeStartElement('table-row', prefix: 'table');
      _writeOmittedCells(
        w,
        BigInt.from(row.gridBefore > 0 ? row.gridBefore : 0),
      );
      for (var index = 0; index < row.cells.length; index++) {
        final cell = row.cells[index];
        final placement = cells.rows[rowIndex][index];
        w.writeStartElement(
          placement.covered ? 'covered-table-cell' : 'table-cell',
          prefix: 'table',
        );
        if (!placement.covered) {
          if (placement.columns > 1) {
            w.writeAttribute(
              'table:number-columns-spanned',
              '${placement.columns}',
            );
          }
          if (placement.rows > 1) {
            w.writeAttribute('table:number-rows-spanned', '${placement.rows}');
          }
        }
        if (cell.fillColor case final fill?) {
          w.writeAttribute('table:style-name', layout.cellStyle(fill));
        }
        final notesAllowed = layout.noteBodiesAllowed;
        final commentsAllowed = layout.commentsAllowed;
        if (placement.covered) {
          layout.noteBodiesAllowed = false;
          layout.commentsAllowed = false;
        }
        try {
          if (cell.blocks.isEmpty) {
            _writePlainParagraph(w, '');
          } else {
            if (placement.covered) {
              layout.withListStory(() => _writeBlocks(w, cell.blocks, layout));
            } else {
              _writeBlocks(w, cell.blocks, layout);
            }
          }
        } finally {
          layout.noteBodiesAllowed = notesAllowed;
          layout.commentsAllowed = commentsAllowed;
        }
        w.writeEndElement();
        _writeCoveredCells(w, placement.columns - 1);
      }
      _writeOmittedCells(
        w,
        BigInt.from(row.gridAfter > 0 ? row.gridAfter : 0) +
            cells.columnCount -
            cells.rowWidths[rowIndex],
      );
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeCoveredCells(XmlWriter w, int count) {
    if (count <= 0) return;
    w.writeEmptyElement(
      'covered-table-cell',
      prefix: 'table',
      attributes: count == 1
          ? null
          : {'table:number-columns-repeated': '$count'},
    );
  }

  static void _writeOmittedCells(XmlWriter w, BigInt count) {
    if (count <= BigInt.zero) return;
    w.writeStartElement('table-cell', prefix: 'table');
    if (count > BigInt.one) {
      w.writeAttribute('table:number-columns-repeated', '$count');
    }
    _writePlainParagraph(w, '');
    w.writeEndElement();
  }

  static void _writeFrame(
    XmlWriter w,
    WmlFrame frame,
    _OdtLayout layout, {
    bool inParagraph = false,
  }) {
    w.writeStartElement('frame', prefix: 'draw');
    w.writeAttribute('text:anchor-type', inParagraph ? 'paragraph' : 'page');
    if (inParagraph) {
      w.writeAttribute('draw:style-name', layout.pageFrameStyle());
    }
    w.writeAttribute('svg:x', '${frame.x.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:y', '${frame.y.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:width', '${frame.width.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:height', '${frame.height.toStringAsFixed(2)}pt');
    if (frame.fillColor case final fill?) {
      w.writeAttribute('draw:fill-color', '#${fill.toLowerCase()}');
    }
    w.writeStartElement('text-box', prefix: 'draw');
    final notesAllowed = layout.noteBodiesAllowed;
    layout.noteBodiesAllowed = false;
    try {
      layout.withListStory(() => _writeBlocks(w, frame.blocks, layout));
    } finally {
      layout.noteBodiesAllowed = notesAllowed;
    }
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeVisual(
    XmlWriter w,
    OfficeVisual visual,
    _OdtLayout layout, {
    bool inline = false,
  }) {
    final bytes = visual.imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final path = layout.addMedia(bytes);
      w.writeStartElement('frame', prefix: 'draw');
      w.writeAttribute('text:anchor-type', 'as-char');
      w.writeAttribute('draw:name', visual.title);
      w.writeAttribute('svg:width', '${visual.width.toStringAsFixed(2)}pt');
      w.writeAttribute('svg:height', '${visual.height.toStringAsFixed(2)}pt');
      w.writeEmptyElement(
        'image',
        prefix: 'draw',
        attributes: {'xlink:href': path, 'xlink:type': 'simple'},
      );
      w.writeEndElement();
    } else if (inline) {
      writeOdfText(w, visual.title);
    } else {
      _writePlainParagraph(w, visual.title);
    }
  }

  static void _writePlainParagraph(XmlWriter w, String text) {
    w.writeStartElement('p', prefix: 'text');
    if (text.isNotEmpty) writeOdfText(w, text);
    w.writeEndElement();
  }

  static String _manifestXml(List<String> media) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(
      'manifest',
      prefix: 'manifest',
      namespaceUri: 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0',
    );
    w.writeAttribute('manifest:version', '1.3');
    void entry(String path, String type) {
      w.writeEmptyElement(
        'file-entry',
        prefix: 'manifest',
        attributes: {'manifest:full-path': path, 'manifest:media-type': type},
      );
    }

    entry('/', _mime);
    entry('content.xml', 'text/xml');
    entry('styles.xml', 'text/xml');
    entry('meta.xml', 'text/xml');
    for (final path in media) {
      entry(path, _mediaType(path));
    }
    w.writeEndElement();
    return w.toXml();
  }

  static String _metaXml(WmlDocument document) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-meta', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('meta', prefix: 'office');
    if (document.properties.title.isNotEmpty) {
      w.writeStartElement('title', prefix: 'dc');
      w.writeText(document.properties.title);
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _mediaType(String path) => path.endsWith('.png')
      ? 'image/png'
      : path.endsWith('.jpg')
      ? 'image/jpeg'
      : 'application/octet-stream';
}

/// Infers vertical ownership only for exactly aligned, consecutive cells.
///
/// Like WordTable's logical addressing, a continuation must have the same
/// logical start and column span as its predecessor. An orphan or mismatched
/// continuation stays visible as an ordinary cell, rather than hiding its
/// content under an unrelated anchor. Invalid row metadata breaks all chains
/// through that row. Known row omissions retain their logical positions.
///
/// Storage and iteration are proportional to physical cells, not authored
/// column spans. BigInt offsets prevent cumulative span overflow on VM and web.
class _OdtTableCells {
  _OdtTableCells(WmlTable table)
    : columnCount = BigInt.from(table.grid.isEmpty ? 1 : table.grid.length) {
    var previous = <(BigInt, int), _OdtTableCell>{};
    for (final row in table.rows) {
      final placements = <_OdtTableCell>[];
      rows.add(placements);
      final valid =
          row.gridBefore >= 0 &&
          row.gridAfter >= 0 &&
          row.cells.every((cell) => cell.gridSpan > 0);
      final current = <(BigInt, int), _OdtTableCell>{};
      var column = BigInt.from(row.gridBefore > 0 ? row.gridBefore : 0);
      for (final cell in row.cells) {
        final span = cell.gridSpan > 0 ? cell.gridSpan : 1;
        final placement = _OdtTableCell(span);
        placements.add(placement);
        final key = (column, span);
        if (valid) {
          if (cell.vMerge == WmlVMerge.restart) {
            current[key] = placement;
          } else if (cell.vMerge == WmlVMerge.cont) {
            final anchor = previous[key];
            if (anchor != null) {
              placement.covered = true;
              anchor.rows++;
              current[key] = anchor;
            }
          }
        }
        column += BigInt.from(span);
      }
      column += BigInt.from(row.gridAfter > 0 ? row.gridAfter : 0);
      rowWidths.add(column);
      if (column > columnCount) columnCount = column;
      previous = current;
    }
  }

  final rows = <List<_OdtTableCell>>[];
  final rowWidths = <BigInt>[];
  BigInt columnCount;
}

class _OdtTableCell {
  _OdtTableCell(this.columns);

  final int columns;
  int rows = 1;
  bool covered = false;
}

class _OdtNoteRecord {
  _OdtNoteRecord(this.id, this.label);

  final String id;
  final String label;
}

/// Note definitions and labels are independent of per-part style registries.
class _OdtNotes {
  _OdtNotes(this.document) {
    for (final endnote in [false, true]) {
      for (final note in endnote ? document.endnotes : document.footnotes) {
        if (note.endnote != endnote) continue;
        final key = (endnote, note.id);
        definitions[key] = definitions.containsKey(key) ? null : note;
      }
    }
  }

  final WmlDocument document;
  final definitions = <(bool, int), WmlNote?>{};
  final emitted = <(bool, int), _OdtNoteRecord>{};
  late final numbering = WordNoteNumbering(
    document,
    emptyReferencesAreAutomatic: true,
    paragraphsForSection: (section) => _visibleParagraphs(section.blocks),
  );

  WmlNote? resolve(WmlRun reference) =>
      definitions[(reference.noteRefEndnote, reference.noteRefId!)];

  String labelFor(WmlRun reference, WmlNote note) =>
      numbering.referenceLabel(reference) ??
      (reference.noteRefCustomMark
          ? ''
          : reference.text.isNotEmpty
          ? reference.text
          : numbering.labelFor(note));

  static Iterable<WmlParagraph> _visibleParagraphs(
    Iterable<WmlBlock> blocks,
  ) sync* {
    for (final block in blocks) {
      if (block is WmlParagraph) {
        yield block;
      } else if (block is WmlContentControlBlock) {
        yield* _visibleParagraphs(block.blocks);
      } else if (block is WmlTable) {
        final cells = _OdtTableCells(block);
        for (var row = 0; row < block.rows.length; row++) {
          for (
            var column = 0;
            column < block.rows[row].cells.length;
            column++
          ) {
            if (!cells.rows[row][column].covered) {
              yield* _visibleParagraphs(block.rows[row].cells[column].blocks);
            }
          }
        }
      }
      // Frames and master-page/note stories are outside the body sequence.
    }
  }
}

/// Comments use one definition/emission registry across body and master parts.
/// Visible main-body anchors take precedence over auxiliary stories, whose
/// first visible anchor otherwise emits the comment. Hidden/recursive anchors
/// do not consume it. Missing/ambiguous definitions leave source runs untouched.
class _OdtComments {
  _OdtComments(WmlDocument document) {
    for (final comment in document.comments) {
      definitions[comment.id] = definitions.containsKey(comment.id)
          ? null
          : comment;
    }
    for (final section in document.sections) {
      for (final paragraph in _OdtNotes._visibleParagraphs(section.blocks)) {
        for (final run in paragraph.inlines.whereType<WmlRun>()) {
          bodyAnchors.addAll(run.commentIds);
        }
      }
    }
  }

  final definitions = <int, WmlComment?>{};
  final emitted = <int>{};
  final bodyAnchors = <int>{};

  // XML Schema dateTime has stricter lexical/calendar constraints than
  // DateTime.parse, which accepts overflow dates and compact ISO forms.
  static final _dateTime = RegExp(
    r'^(-?)([0-9]{4,})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])'
    r'T([01][0-9]|2[0-4]):([0-5][0-9]):([0-5][0-9])'
    r'(?:\.([0-9]+))?(Z|[+-](?:0[0-9]|1[0-4]):[0-5][0-9])?$',
  );

  static bool isDateTime(String value) {
    // Scan just the edges. A trailing-whitespace regex can retry at every
    // interior space and take quadratic time on malformed imported metadata.
    var start = 0;
    var end = value.length;
    while (start < end && _isXmlWhitespace(value.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isXmlWhitespace(value.codeUnitAt(end - 1))) {
      end--;
    }
    final normalized = value.substring(start, end);
    final match = _dateTime.firstMatch(normalized);
    if (match == null || match.end != normalized.length) return false;
    final year = match[2]!;
    if (year == '0000' || (year.length > 4 && year.startsWith('0'))) {
      return false;
    }
    // Only the last four digits affect leap years; do not parse an unbounded
    // extended year into a machine integer or depend on the host time zone.
    final cycle = int.parse(year.substring(year.length - 4));
    final leap = cycle % 4 == 0 && (cycle % 100 != 0 || cycle % 400 == 0);
    final month = int.parse(match[3]!);
    final days = month == 2
        ? (leap ? 29 : 28)
        : const {4, 6, 9, 11}.contains(month)
        ? 30
        : 31;
    if (int.parse(match[4]!) > days) return false;
    if (match[5] == '24' &&
        (match[6] != '00' ||
            match[7] != '00' ||
            (match[8]?.contains(RegExp('[1-9]')) ?? false))) {
      return false;
    }
    final zone = match[9];
    return zone == null ||
        zone == 'Z' ||
        zone.substring(1, 3) != '14' ||
        zone.endsWith(':00');
  }

  static bool _isXmlWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;
}

class _OdtSectionStart {
  _OdtSectionStart(this.index, this.kind)
    : masterPage = index == 0
          ? null
          : kind == WmlSectionBreakKind.oddPage ||
                kind == WmlSectionBreakKind.evenPage
          ? 'mp${index}Start'
          : 'mp$index';

  final int index;
  final WmlSectionBreakKind kind;
  String? masterPage;
  bool consumed = false;
  bool empty = false;

  bool get breakBefore => index > 0 && kind != WmlSectionBreakKind.continuous;

  String? get parity => index == 0
      ? null
      : switch (kind) {
          WmlSectionBreakKind.oddPage => 'right',
          WmlSectionBreakKind.evenPage => 'left',
          _ => null,
        };
}

class _OdtLayout {
  _OdtLayout(this.document, {_OdtLayout? sharedMedia})
    : sections = document.sections.isEmpty
          ? <WmlSection>[WmlSection()]
          : document.sections,
      media = sharedMedia?.media ?? <String>[],
      _mediaBytes = sharedMedia?._mediaBytes ?? <String, Uint8List>{},
      notes = sharedMedia?.notes ?? _OdtNotes(document),
      comments = sharedMedia?.comments ?? _OdtComments(document),
      noteBodiesAllowed = sharedMedia == null;

  final WmlDocument document;
  final List<WmlSection> sections;
  late final List<_OdtSectionStart> sectionStarts = [
    for (var index = 0; index < sections.length; index++)
      _OdtSectionStart(index, sections[index].breakKind),
  ];
  final List<String> media;
  final _OdtNotes notes;
  final _OdtComments comments;
  bool noteBodiesAllowed;
  bool commentsAllowed = true;
  bool inCommentBody = false;
  bool inNoteBody = false;
  bool noteReferenceSpacePending = false;
  final Map<String, String> _runStyles = <String, String>{};
  final Map<String, String> _paragraphStyles = <String, String>{};
  final Map<String, String> _columnStyles = <String, String>{};
  final Map<String, String> _cellStyles = <String, String>{};
  final Map<(String?, String, String, String), String> _listStyles = {};
  late final _listDefinitions = _OdtListDefinitions(document);
  var _listCounters = <int, List<BigInt?>>{};
  final List<String> _styleBuffers = <String>[];
  final List<String Function()> _deferredStyleBuffers = [];
  int tableCount = 0;

  String addMedia(Uint8List bytes) {
    final ext = _extension(bytes);
    final path = 'Pictures/image${media.length + 1}.$ext';
    media.add(path);
    _mediaBytes[path] = bytes;
    return path;
  }

  final Map<String, Uint8List> _mediaBytes;

  Map<String, Uint8List> get mediaBytes => _mediaBytes;

  String runStyle(WmlRunProps props) {
    final key =
        '${props.bold}|${props.italic}|${props.underline.index}|${props.strike}|${props.color}|${props.fontSizeHalfPoints}|${props.asciiFont}|${props.highlight}|${props.vertAlign.index}';
    return _runStyles.putIfAbsent(key, () {
      final name = 'T${_runStyles.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="text">'
        '<style:text-properties',
      );
      if (props.bold) buffer.write(' fo:font-weight="bold"');
      if (props.italic) buffer.write(' fo:font-style="italic"');
      if (props.underline != WmlUnderline.none) {
        buffer.write(' style:text-underline-style="solid"');
        buffer.write(' style:text-underline-type="single"');
      }
      if (props.strike) buffer.write(' style:text-line-through-style="solid"');
      if (props.color.isNotEmpty) {
        buffer.write(' fo:color="#${props.color.toLowerCase()}"');
      }
      buffer.write(
        ' fo:font-size="${props.fontSizePoints.toStringAsFixed(1)}pt"',
      );
      if (props.asciiFont.isNotEmpty) {
        buffer.write(' fo:font-family="${_escape(props.asciiFont)}"');
      }
      if (props.highlight case final highlight?) {
        buffer.write(' fo:background-color="#${highlight.toLowerCase()}"');
      }
      if (props.vertAlign == WmlVertAlign.superscript) {
        buffer.write(' style:text-position="super 58%"');
      } else if (props.vertAlign == WmlVertAlign.subscript) {
        buffer.write(' style:text-position="sub 58%"');
      }
      buffer.write('/></style:style>');
      _styleBuffers.add(buffer.toString());
      return name;
    });
  }

  String paragraphStyle(
    WmlParagraphProps props, {
    int? heading,
    _OdtSectionStart? sectionStart,
    bool emptyAnchor = false,
  }) {
    final key =
        '${heading == null ? 'body' : heading.clamp(1, 9)}|${props.justification.index}|${props.rightToLeft}|${props.lineSpacingRule.index}|${props.lineSpacing}|${props.spacingBefore}|${props.spacingAfter}|${props.indent.left}|${props.indent.right}|${props.indent.firstLine}|${props.indent.hanging}|${props.pageBreakBefore}|${sectionStart?.index}|$emptyAnchor';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = sectionStart == null
          ? 'P${_paragraphStyles.length + 1}'
          : 'SB${sectionStart.index}';
      String styleXml() {
        final buffer = StringBuffer(
          '<style:style style:name="$name" style:family="paragraph" '
          'style:parent-style-name="${heading == null ? 'Standard' : 'Heading_20_${heading.clamp(1, 9)}'}"',
        );
        if (sectionStart?.masterPage case final master?) {
          buffer.write(' style:master-page-name="$master"');
        }
        buffer.write('><style:paragraph-properties');
        // The model's left/right alignment is physical, independently of the
        // paragraph's BiDi base direction. ODF start/end would reverse it in RTL.
        final align = switch (props.justification) {
          WmlJustification.center => 'center',
          WmlJustification.right => 'right',
          WmlJustification.justify || WmlJustification.distributed => 'justify',
          WmlJustification.left => 'left',
        };
        buffer.write(' fo:text-align="$align"');
        if (props.rightToLeft case final direction?) {
          buffer.write(
            ' style:writing-mode="${direction ? 'rl-tb' : 'lr-tb'}"',
          );
          buffer.write(' style:writing-mode-automatic="false"');
        }
        // Write zero margins too: omission inherits the generated default style,
        // whose bottom margin is nonzero. Headings retain their resolved values.
        if (_paragraphDecimal(emptyAnchor ? 0 : props.spacingBefore)
            case final before?) {
          buffer.write(' fo:margin-top="${before}pt"');
        }
        if (_paragraphDecimal(emptyAnchor ? 0 : props.spacingAfter)
            case final after?) {
          buffer.write(' fo:margin-bottom="${after}pt"');
        }
        if (emptyAnchor) {
          buffer.write(' fo:line-height="1pt"');
        } else if (props.lineSpacing > 0) {
          switch (props.lineSpacingRule) {
            case WmlLineSpacingRule.auto:
              if (_paragraphDecimal(props.lineSpacing * 100)
                  case final percent?) {
                buffer.write(' fo:line-height="$percent%"');
              }
            case WmlLineSpacingRule.exact:
              if (_paragraphDecimal(props.lineSpacing) case final points?) {
                buffer.write(' fo:line-height="${points}pt"');
              }
            case WmlLineSpacingRule.atLeast:
              if (_paragraphDecimal(props.lineSpacing) case final points?) {
                buffer.write(' style:line-height-at-least="${points}pt"');
              }
          }
        }
        if (props.pageBreakBefore || sectionStart?.breakBefore == true) {
          buffer.write(' fo:break-before="page"');
        }
        if (sectionStart?.index case final index? when index > 0) {
          buffer.write(' style:page-number="auto"');
        }
        if (props.indent.left != 0) {
          if (_paragraphDecimal(props.indent.left) case final left?) {
            buffer.write(' fo:margin-left="${left}pt"');
          }
        }
        if (props.indent.right != 0) {
          if (_paragraphDecimal(props.indent.right) case final right?) {
            buffer.write(' fo:margin-right="${right}pt"');
          }
        }
        final firstLine = props.indent.hanging != 0
            ? -props.indent.hanging
            : props.indent.firstLine;
        if (firstLine != 0) {
          if (_paragraphDecimal(firstLine) case final points?) {
            buffer.write(' fo:text-indent="${points}pt"');
          }
        }
        buffer.write('/>');
        if (emptyAnchor) {
          buffer.write('<style:text-properties fo:font-size="1pt"/>');
        }
        buffer.write('</style:style>');
        return buffer.toString();
      }

      if (sectionStart == null) {
        _styleBuffers.add(styleXml());
      } else {
        // Header/footer comparison resolves continuous master reuse after
        // the body has been written, preserving main-body annotation priority.
        _deferredStyleBuffers.add(styleXml);
      }
      return name;
    });
  }

  static String? _paragraphDecimal(double value) {
    if (!value.isFinite) return null;
    final decimal = value.toStringAsFixed(2);
    // ODF lengths and percentages do not accept exponent notation, which
    // toStringAsFixed uses for magnitudes of at least 10^21.
    return decimal.contains('e') ? null : decimal;
  }

  String tableStyle({_OdtSectionStart? sectionStart}) {
    final name = 'Tab${tableCount + 1}';
    String styleXml() {
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="table"',
      );
      if (sectionStart?.masterPage case final master?) {
        buffer.write(' style:master-page-name="$master"');
      }
      buffer.write(
        '><style:table-properties style:rel-width="100%" table:align="margins"',
      );
      if (sectionStart?.breakBefore == true) {
        buffer.write(' fo:break-before="page"');
      }
      if (sectionStart?.index case final index? when index > 0) {
        buffer.write(' style:page-number="auto"');
      }
      buffer.write('/></style:style>');
      return buffer.toString();
    }

    if (sectionStart == null) {
      _styleBuffers.add(styleXml());
    } else {
      _deferredStyleBuffers.add(styleXml);
    }
    return name;
  }

  bool _pageFrameStyleWritten = false;

  String pageFrameStyle() {
    const name = 'SectionFrame';
    if (!_pageFrameStyleWritten) {
      _pageFrameStyleWritten = true;
      _styleBuffers.add(
        '<style:style style:name="$name" style:family="graphic">'
        '<style:graphic-properties style:horizontal-pos="from-left" '
        'style:horizontal-rel="page" style:vertical-pos="from-top" '
        'style:vertical-rel="page" style:wrap="none"/></style:style>',
      );
    }
    return name;
  }

  String columnStyle(double width) {
    final key = width.toStringAsFixed(2);
    return _columnStyles.putIfAbsent(key, () {
      final name = 'Co${_columnStyles.length + 1}';
      _styleBuffers.add(
        '<style:style style:name="$name" style:family="table-column">'
        '<style:table-column-properties style:column-width="${width.toStringAsFixed(2)}pt"/>'
        '</style:style>',
      );
      return name;
    });
  }

  /// Auxiliary stories and hidden cell stories must not consume body numbers.
  void withListStory(void Function() write) {
    final previous = _listCounters;
    _listCounters = <int, List<BigInt?>>{};
    try {
      write();
    } finally {
      _listCounters = previous;
    }
  }

  _OdtListMarker listMarker(WmlParagraph paragraph) {
    final props = paragraph.properties;
    final level = props.ilvl.clamp(0, 8);
    // A new parent item resets supported child sequences even when its own
    // marker is a bullet or a literal Roman/multilevel label. Its marker need
    // not be a mapped decimal for the authored hierarchy to remain meaningful.
    final active = _listCounters[props.numId];
    if (active != null) {
      for (var deeper = level + 1; deeper < active.length; deeper++) {
        active[deeper] = null;
      }
    }
    final definition =
        _listDefinitions.levels[(props.numId!, level)] ??
        _listDefinitions.levels[(props.numId!, 0)];
    final label = props.listLabel?.trim() ?? '';
    final bullet = definition?.isBullet ?? false;
    if (bullet || const {'•', '◦', '▪', 'o'}.contains(label)) {
      var text = label;
      if (text.isEmpty) {
        final native = definition!.text.trim();
        // Match the shared model's symbol-font and Courier bullet fallback.
        // Native private-use codes have no useful meaning in the exported
        // default font. An explicit cached glyph remains authoritative.
        text = native.isEmpty || native.codeUnitAt(0) >= 0xf000
            ? '•'
            : native == 'o'
            ? '◦'
            : native;
      }
      if (text.runes.length == 1) return _OdtListMarker.bullet(text);
      return _OdtListMarker.literal(text);
    }

    String? prefix;
    String? suffix;
    BigInt? initial;
    if (definition != null) {
      final token = '%${level + 1}';
      final parts = definition.text.split(token);
      if (definition.format == 'decimal' &&
          !definition.specialRestart &&
          parts.length == 2 &&
          !parts.any((part) => part.contains(RegExp('%[1-9]')))) {
        prefix = parts.first;
        suffix = parts.last;
        initial = definition.start;
      } else if (definition.format == 'none' && label.isEmpty) {
        return _OdtListMarker.literal(
          definition.text.replaceAll(RegExp('%[1-9]'), ''),
        );
      } else {
        // A cached Roman, alphabetic or multilevel label is visible model
        // content. Keep it literal instead of inventing decimal semantics.
        return _OdtListMarker.literal(label);
      }
    } else {
      final match = RegExp(r'^(\(?)(0|[1-9][0-9]*)([.)]?)$').firstMatch(label);
      if (match != null && (match[1]!.isEmpty || match[3] == ')')) {
        prefix = match[1];
        suffix = match[3];
        initial = BigInt.tryParse(match[2]!);
      } else if (label.isEmpty) {
        return _OdtListMarker.bullet('•');
      } else {
        return _OdtListMarker.literal(label);
      }
    }
    if (prefix == null || suffix == null || initial == null) {
      return _OdtListMarker.literal(label);
    }
    final counters = _listCounters.putIfAbsent(
      props.numId!,
      () => List<BigInt?>.filled(9, null),
    );
    final previous = counters[level];
    final value = props.listRestart == null
        ? (previous == null ? initial : previous + BigInt.one)
        : BigInt.from(props.listRestart!);
    counters[level] = value;
    // ODF start-value is positiveInteger. Nonpositive Word values remain
    // visible literal labels, without emitting schema-invalid attributes.
    if (value <= BigInt.zero) {
      return _OdtListMarker.literal('$prefix$value$suffix');
    }
    return _OdtListMarker.number(prefix, suffix, value);
  }

  String listStyle(_OdtListMarker marker) {
    if (marker.bullet == '•') return 'L1';
    if (marker.format == '1' && marker.prefix.isEmpty && marker.suffix == '.') {
      return 'L2';
    }
    return _listStyles.putIfAbsent(
      (marker.bullet, marker.format, marker.prefix, marker.suffix),
      () {
        final name = 'LM${_listStyles.length + 1}';
        final w = XmlWriter();
        w.writeStartElement('list-style', prefix: 'text');
        w.writeAttribute('style:name', name);
        for (var level = 1; level <= 9; level++) {
          w.writeStartElement(
            marker.bullet == null
                ? 'list-level-style-number'
                : 'list-level-style-bullet',
            prefix: 'text',
          );
          w.writeAttribute('text:level', '$level');
          if (marker.bullet case final bullet?) {
            w.writeAttribute('text:bullet-char', bullet);
          } else {
            w.writeAttribute('style:num-format', marker.format);
            w.writeAttribute('style:num-prefix', marker.prefix);
            w.writeAttribute('style:num-suffix', marker.suffix);
          }
          w.writeStartElement('list-level-properties', prefix: 'style');
          w.writeAttribute(
            'text:list-level-position-and-space-mode',
            'label-alignment',
          );
          w.writeEmptyElement(
            'list-level-label-alignment',
            prefix: 'style',
            attributes: {
              'text:label-followed-by': 'listtab',
              'text:list-tab-stop-position': '${level * 0.25}in',
              'fo:margin-left': '${level * 0.25}in',
              'fo:text-indent': '-0.25in',
            },
          );
          w.writeEndElement();
          w.writeEndElement();
        }
        w.writeEndElement();
        _styleBuffers.add(w.toXml());
        return name;
      },
    );
  }

  String cellStyle(String fill) {
    return _cellStyles.putIfAbsent(fill, () {
      final name = 'Ce${_cellStyles.length + 1}';
      _styleBuffers.add(
        '<style:style style:name="$name" style:family="table-cell">'
        '<style:table-cell-properties fo:background-color="#${fill.toLowerCase()}"/>'
        '</style:style>',
      );
      return name;
    });
  }

  void writeContentStyles(XmlWriter w) {
    for (final buffer in _styleBuffers) {
      w.writeRaw(buffer);
    }
    for (final writeStyle in _deferredStyleBuffers) {
      w.writeRaw(writeStyle());
    }
  }

  static String _extension(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    return 'bin';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _OdtListItem {
  _OdtListItem(this.paragraph, this.marker)
    : level = paragraph.properties.ilvl.clamp(0, 8);

  final WmlParagraph paragraph;
  final int level;
  final _OdtListMarker marker;
  final List<_OdtListItem> children = <_OdtListItem>[];
}

class _OdtListMarker {
  const _OdtListMarker.bullet(String value)
    : bullet = value,
      format = '',
      prefix = '',
      suffix = '',
      start = null;

  const _OdtListMarker.number(this.prefix, this.suffix, this.start)
    : bullet = null,
      format = '1';

  const _OdtListMarker.literal(this.prefix)
    : bullet = null,
      format = '',
      suffix = '',
      start = null;

  final String? bullet;
  final String format;
  final String prefix;
  final String suffix;
  final BigInt? start;
}

class _OdtListDefinition {
  const _OdtListDefinition({
    required this.format,
    required this.text,
    required this.start,
    required this.specialRestart,
  });

  final String format;
  final String text;
  final BigInt? start;
  final bool specialRestart;

  bool get isBullet =>
      format == 'bullet' || (text.isNotEmpty && text.codeUnitAt(0) >= 0xf000);
}

/// Read only the native metadata needed for an unambiguous decimal mapping.
/// Unsupported definitions retain their cached labels instead of being coerced.
class _OdtListDefinitions {
  _OdtListDefinitions(WmlDocument document) {
    final package = document.package;
    if (package == null) return;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    if (office?.targetMode == RelationshipTargetMode.external) return;
    final main = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final relationships = package.relationshipsFor(main);
    final rel = relationships.firstByType(RelationshipTypes.numbering);
    if (rel?.targetMode == RelationshipTargetMode.external) return;
    final part = package.getPart(
      rel == null
          ? OpcUris.resolve(main, 'numbering.xml')
          : relationships.resolve(rel),
    );
    if (part == null) return;
    XmlElement? root;
    try {
      root = XmlDocument.parse(part.readText()).root;
    } on XmlParseException {
      return;
    } on FormatException {
      return;
    } on StateError {
      return;
    }
    if (root?.namespaceUri != OfficeNamespaces.w ||
        root?.localName != 'numbering') {
      return;
    }
    final abstracts = _indexed(root!, 'abstractNum', 'abstractNumId');
    final instances = _indexed(root, 'num', 'numId');
    for (final instance in instances.entries) {
      final node = instance.value;
      if (node == null) continue;
      final abstractId = int.tryParse(_value(node, 'abstractNumId') ?? '');
      final definition = abstracts[abstractId];
      final source = definition == null
          ? <int, XmlElement?>{}
          : _indexed(definition, 'lvl', 'ilvl');
      final overrides = _indexed(node, 'lvlOverride', 'ilvl');
      for (var level = 0; level < 9; level++) {
        if (source.containsKey(level) && source[level] == null ||
            overrides.containsKey(level) && overrides[level] == null) {
          continue;
        }
        final base = source[level];
        final override = overrides[level];
        final own = override?.firstChild(
          'lvl',
          namespaceUri: OfficeNamespaces.w,
        );
        if (base == null && own == null) continue;
        final start =
            _value(override, 'startOverride') ??
            _value(own, 'start') ??
            _value(base, 'start') ??
            '1';
        levels[(instance.key, level)] = _OdtListDefinition(
          format: _value(own, 'numFmt') ?? _value(base, 'numFmt') ?? 'bullet',
          text: _value(own, 'lvlText') ?? _value(base, 'lvlText') ?? '',
          start: BigInt.tryParse(start),
          specialRestart:
              _value(own, 'lvlRestart') != null ||
              _value(base, 'lvlRestart') != null,
        );
      }
    }
  }

  final levels = <(int, int), _OdtListDefinition>{};

  static String? _value(XmlElement? element, String name) => element
      ?.firstChild(name, namespaceUri: OfficeNamespaces.w)
      ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);

  static Map<int, XmlElement?> _indexed(
    XmlElement root,
    String name,
    String attribute,
  ) {
    final result = <int, XmlElement?>{};
    for (final node in root.childrenNamed(
      name,
      namespaceUri: OfficeNamespaces.w,
    )) {
      final id = int.tryParse(
        node.getAttribute(attribute, namespaceUri: OfficeNamespaces.w) ?? '',
      );
      if (id != null && id >= 0 && id <= 0x7fffffff) {
        result[id] = result.containsKey(id) ? null : node;
      }
    }
    return result;
  }
}
