part of '../crisp_ebook.dart';

const _proseXhtmlNamespace = 'http://www.w3.org/1999/xhtml';
const _maxStructuredProseSegments = 1024;
const _structuredProseTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'figcaption',
};
const _proseInlineTags = {
  'a',
  'abbr',
  'b',
  'bdi',
  'bdo',
  'cite',
  'code',
  'del',
  'dfn',
  'em',
  'i',
  'ins',
  'kbd',
  'mark',
  'q',
  's',
  'samp',
  'small',
  'span',
  'strong',
  'sub',
  'sup',
  'time',
  'u',
  'var',
};
const _proseContainerTags = {
  'body',
  'section',
  'article',
  'aside',
  'main',
  'nav',
  'header',
  'footer',
  'div',
  'figure',
  'ol',
  'ul',
  'dl',
  'dt',
  'dd',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'td',
  'th',
  'details',
  'summary',
};

/// Corrects the text inside existing formatting without reconstructing a
/// paragraph or converting it through a different document model.
extension EpubStructuredProseEditing on EpubDocument {
  List<EpubStructuredProseBlock> readStructuredProse(String resourcePath) {
    final source = _structuredProseSource(resourcePath);
    final fingerprint = crypto.sha256
        .convert(readBytes(resourcePath))
        .toString();
    final elements = _structuredProseElements(source);
    return List.unmodifiable([
      for (final entry in elements.asMap().entries)
        EpubStructuredProseBlock(
          resourcePath: resourcePath,
          resourceFingerprint: fingerprint,
          index: entry.key,
          tag: entry.value.name.local,
          id: entry.value.getAttribute('id'),
          allowsLineBreakEditing: _plainProse(entry.value),
          segments: _structuredProseSegments(
            entry.value,
            resourcePath,
          ).map((segment) => segment.view).toList(),
        ),
    ]);
  }

  /// Applies a batch to original XML text nodes. Every index and value is
  /// checked before any document mutation, and [block]'s entire resource must
  /// still match. Empty/no-op batches do not serialize or dirty the package.
  void updateStructuredProseBlock(
    EpubStructuredProseBlock block,
    Map<int, String> replacements,
  ) {
    _assertStructure();
    final source = _structuredProseSource(block.resourcePath);
    final fingerprint = crypto.sha256
        .convert(readBytes(block.resourcePath))
        .toString();
    if (fingerprint != block.resourceFingerprint) {
      throw EpubException(
        'stale_edit',
        'This chapter changed after the text editor was opened. Reopen it before applying these edits.',
        path: block.resourcePath,
      );
    }
    final elements = _structuredProseElements(source);
    if (block.index < 0 || block.index >= elements.length) {
      throw RangeError.index(block.index, elements, 'block.index');
    }
    final element = elements[block.index];
    final segments = _structuredProseSegments(element, block.resourcePath);
    final changes = <(XmlText, String)>[];
    var replacementBytes = 0;
    for (final entry in replacements.entries) {
      if (entry.key < 0 || entry.key >= segments.length) {
        throw RangeError.index(entry.key, segments, 'segment.index');
      }
      final segment = segments[entry.key];
      if (!segment.view.editable || segment.node is! XmlText) {
        throw EpubException(
          'protected_prose',
          'This segment contains protected content. Use source editing to change it.',
          path: block.resourcePath,
        );
      }
      // Check a cheap UTF-16 bound before allocating its UTF-8 representation.
      if (entry.value.length > limits.maxTextBytes) {
        throw _proseTextLimit(block.resourcePath);
      }
      _validateProseText(entry.value, block.resourcePath);
      replacementBytes += utf8.encode(entry.value).length;
      if (replacementBytes > limits.maxTextBytes) {
        throw _proseTextLimit(block.resourcePath);
      }
      if (entry.value != segment.view.text) {
        changes.add((segment.node as XmlText, entry.value));
      }
    }
    if (changes.isEmpty) return;
    for (final (node, text) in changes) {
      node.value = text;
    }
    // This is a private parsed tree. updateText is transactional and checks the
    // serialized size before publishing either the chapter or OPF timestamp.
    updateText(block.resourcePath, source.toXmlString());
  }

  /// Retains the original plain-paragraph authoring behavior: newlines become
  /// XHTML line breaks. Inline markup or attributed/structured breaks cannot
  /// enter this path, and the complete resulting XML is checked before publish.
  void updateStructuredProseText(EpubStructuredProseBlock block, String text) {
    _assertStructure();
    final source = _structuredProseSource(block.resourcePath);
    final fingerprint = crypto.sha256
        .convert(readBytes(block.resourcePath))
        .toString();
    if (fingerprint != block.resourceFingerprint) {
      throw EpubException(
        'stale_edit',
        'This chapter changed after the text editor was opened. Reopen it before applying these edits.',
        path: block.resourcePath,
      );
    }
    final elements = _structuredProseElements(source);
    if (block.index < 0 || block.index >= elements.length) {
      throw RangeError.index(block.index, elements, 'block.index');
    }
    final element = elements[block.index];
    if (!_plainProse(element)) {
      throw EpubException(
        'complex_prose',
        'This block contains formatting or embedded content; edit its individual text segments.',
        path: block.resourcePath,
      );
    }
    if (text.length > limits.maxTextBytes) {
      throw _proseTextLimit(block.resourcePath);
    }
    _validateProseText(text, block.resourcePath);
    if (utf8.encode(text).length > limits.maxTextBytes) {
      throw _proseTextLimit(block.resourcePath);
    }
    final expectedText = _proseText(element);
    if (text == expectedText) return;
    var segmentCount = 1;
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 10 &&
          (segmentCount += 2) > _maxStructuredProseSegments) {
        throw EpubException(
          'prose_limit',
          'This paragraph has too many text segments. Use source editing.',
          path: block.resourcePath,
        );
      }
    }
    // Preserve the existing plain editor's newline-to-br semantics on this
    // private tree. Count before split/allocation, then validate the resulting
    // chapter so a bounded UI edit cannot publish an over-budget XML resource.
    element.children.clear();
    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      if (index != 0)
        element.children.add(XmlElement(_childName(element, 'br')));
      element.children.add(XmlText(lines[index]));
    }
    final serialized = source.toXmlString();
    _parseXml(serialized, block.resourcePath, limits);
    updateText(block.resourcePath, serialized);
  }

  XmlDocument _structuredProseSource(String resourcePath) {
    _safeArchivePath(resourcePath);
    if (fixedLayout) {
      throw const EpubException(
        'fixed_layout',
        'Use source editing for fixed-layout books.',
      );
    }
    final resource = resources
        .where((item) => item.path == resourcePath)
        .firstOrNull;
    if (resource == null || resource.mediaType != 'application/xhtml+xml') {
      throw EpubException(
        'prose_resource',
        'Structured text editing requires an XHTML resource.',
        path: resourcePath,
      );
    }
    if (resource.isEncrypted) {
      throw EpubException(
        'encrypted_resource',
        'An obfuscated or encrypted resource cannot be edited as plain text.',
        path: resourcePath,
      );
    }
    final source = _xml(resourcePath);
    if (source.rootElement.name.local != 'html' ||
        source.rootElement.namespaceUri != _proseXhtmlNamespace) {
      throw EpubException(
        'prose_resource',
        'Structured text editing requires a complete XHTML document.',
        path: resourcePath,
      );
    }
    return source;
  }
}

bool _reachableProseElement(XmlElement element) =>
    element.namespaceUri == _proseXhtmlNamespace &&
    (_structuredProseTags.contains(element.name.local) ||
        _proseContainerTags.contains(element.name.local) ||
        _proseInlineTags.contains(element.name.local));

List<XmlElement> _structuredProseElements(XmlDocument document) {
  final result = <XmlElement>[];
  bool hasNestedBlock(XmlElement parent) => parent.childElements.any(
    (child) =>
        _reachableProseElement(child) &&
        (_structuredProseTags.contains(child.name.local) ||
            hasNestedBlock(child)),
  );
  void visit(XmlElement element) {
    if (!_reachableProseElement(element)) return;
    if (_structuredProseTags.contains(element.name.local) &&
        !hasNestedBlock(element)) {
      result.add(element);
      return;
    }
    for (final child in element.childElements) {
      visit(child);
    }
  }

  for (final body in document.rootElement.childElements.where(
    (element) =>
        element.name.local == 'body' &&
        element.namespaceUri == _proseXhtmlNamespace,
  )) {
    visit(body);
  }
  return result;
}

class _ProseSegmentNode {
  const _ProseSegmentNode(this.node, this.view);
  final XmlNode node;
  final EpubProseSegment view;
}

List<_ProseSegmentNode> _structuredProseSegments(
  XmlElement block,
  String resourcePath,
) {
  final result = <_ProseSegmentNode>[];
  void add(
    XmlNode node,
    String text,
    EpubProseSegmentKind kind,
    Set<EpubProseMark> marks, {
    bool editable = false,
    String? tag,
    String? href,
  }) {
    if (result.length >= _maxStructuredProseSegments) {
      throw EpubException(
        'prose_limit',
        'This paragraph has too many text segments. Use source editing.',
        path: resourcePath,
      );
    }
    result.add(
      _ProseSegmentNode(
        node,
        EpubProseSegment(
          index: result.length,
          text: text,
          kind: kind,
          editable: editable,
          marks: marks,
          tag: tag,
          href: href,
        ),
      ),
    );
  }

  void visit(XmlNode node, Set<EpubProseMark> marks, String? href) {
    if (node is XmlText) {
      add(
        node,
        node.value,
        EpubProseSegmentKind.text,
        marks,
        editable: true,
        href: href,
      );
      return;
    }
    if (node is XmlElement) {
      final local = node.name.local;
      if (node.namespaceUri == _proseXhtmlNamespace && local == 'br') {
        add(node, '\n', EpubProseSegmentKind.lineBreak, marks, tag: local);
        return;
      }
      if (node.namespaceUri == _proseXhtmlNamespace &&
          _proseInlineTags.contains(local)) {
        final inherited = <EpubProseMark>{
          ...marks,
          ...switch (local) {
            'strong' || 'b' => {EpubProseMark.bold},
            'em' || 'i' || 'cite' || 'dfn' || 'var' => {EpubProseMark.italic},
            'u' || 'ins' => {EpubProseMark.underline},
            's' || 'del' => {EpubProseMark.strikethrough},
            'code' || 'kbd' || 'samp' => {EpubProseMark.code},
            'a' => {EpubProseMark.link},
            'sup' => {EpubProseMark.superscript},
            'sub' => {EpubProseMark.subscript},
            _ => <EpubProseMark>{},
          },
        };
        for (final child in node.children) {
          visit(
            child,
            inherited,
            local == 'a' ? node.getAttribute('href') : href,
          );
        }
        return;
      }
      add(
        node,
        node.innerText,
        EpubProseSegmentKind.protectedContent,
        marks,
        tag: node.name.qualified,
      );
      return;
    }
    // Comments, processing instructions and CDATA retain their exact node kind.
    add(
      node,
      node is XmlCDATA ? node.value : '',
      EpubProseSegmentKind.protectedContent,
      marks,
      tag: node is XmlCDATA
          ? 'CDATA'
          : node is XmlComment
          ? '#comment'
          : '#markup',
    );
  }

  for (final child in block.children) {
    visit(child, const {}, null);
  }
  return result;
}

EpubException _proseTextLimit(String path) => EpubException(
  'text_limit',
  'The text resource exceeds the editor limit.',
  path: path,
);

void _validateProseText(String value, String path) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit == 9 ||
        unit == 10 ||
        unit == 13 ||
        (unit >= 0x20 && unit <= 0xd7ff) ||
        (unit >= 0xe000 && unit <= 0xfffd))
      continue;
    if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < value.length) {
      final next = value.codeUnitAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        i++;
        continue;
      }
    }
    throw EpubException(
      'invalid_prose_text',
      'The replacement contains an invalid XML character.',
      path: path,
    );
  }
}
