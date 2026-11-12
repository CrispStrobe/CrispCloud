part of '../crisp_ebook.dart';

/// Limits and document date for a separate FictionBook conversion.
///
/// The source EPUB is never changed. FictionBook cannot represent every EPUB
/// feature: [FictionBookExportResult.warnings] describes the supported
/// simplifications, while missing content/resources and unsupported media fail.
class FictionBookExportOptions {
  final int maxOutputBytes;
  final int maxImages;
  final DateTime? createdAt;

  const FictionBookExportOptions({
    this.maxOutputBytes = 128 * 1024 * 1024,
    this.maxImages = 10000,
    this.createdAt,
  });
}

class FictionBookExportResult {
  final Uint8List bytes;
  final bool zipped;
  final List<EpubIssue> warnings;

  FictionBookExportResult._(this.bytes, this.zipped, List<EpubIssue> warnings)
    : warnings = List.unmodifiable(warnings);

  String get extension => zipped ? 'fbz' : 'fb2';
  String get mediaType =>
      zipped ? 'application/zip' : 'application/x-fictionbook+xml';
}

extension EpubFictionBookExport on EpubDocument {
  /// Exports editable content as UTF-8 FB2, or an FBZ containing `book.fb2`.
  ///
  /// This is a conversion, not a lossless round trip of the original EPUB or
  /// FictionBook container. Book text, structural emphasis, chapters, links,
  /// marked notes, tables, and supported raster images are retained. EPUB CSS
  /// and fonts are not carried across. Signed/encrypted books, fixed layouts,
  /// foreign markup and active/media content are refused. No resource is fetched
  /// from the network and this method performs no filesystem access.
  FictionBookExportResult exportFictionBook({
    bool zipped = false,
    FictionBookExportOptions options = const FictionBookExportOptions(),
  }) => _FictionBookWriter(this, options).export(zipped: zipped);
}

const _fbNamespace = 'http://www.gribuser.ru/xml/fictionbook/2.0';
const _fbXlink = 'http://www.w3.org/1999/xlink';
const _fbXhtml = 'http://www.w3.org/1999/xhtml';
const _fbBlockTags = {
  'body',
  'html',
  'section',
  'article',
  'div',
  'main',
  'header',
  'footer',
  'nav',
  'aside',
  'figure',
  'figcaption',
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'ul',
  'ol',
  'li',
  'dl',
  'dt',
  'dd',
  'table',
  'td',
  'th',
  'hr',
};
const _fbForbiddenTags = {
  'script',
  'iframe',
  'object',
  'embed',
  'audio',
  'video',
  'canvas',
  'svg',
  'math',
  'form',
  'input',
  'textarea',
  'button',
  'select',
  'ruby',
};

class _FictionBookChapter {
  final EpubChapter chapter;
  final XmlElement body;
  final String id;
  _FictionBookChapter(this.chapter, this.body, this.id);
}

class _FictionBookWriter {
  final EpubDocument source;
  final FictionBookExportOptions options;
  final _warnings = <EpubIssue>[];
  final _warningKeys = <String>{};
  final _chapters = <_FictionBookChapter>[];
  final _ids = <String, String>{};
  final _anchors = <XmlElement, String>{};
  final _images = <String, XmlElement>{};
  final _notes = <XmlElement>[];
  late final Map<String, EpubResource> _resources;
  var _nextId = 0;
  var _estimatedBytes = 0;

  _FictionBookWriter(this.source, this.options);

  FictionBookExportResult export({required bool zipped}) {
    if (options.maxOutputBytes < 1 ||
        options.maxOutputBytes > 256 * 1024 * 1024 ||
        options.maxImages < 1 ||
        options.maxImages > 10000) {
      throw const EpubException(
        'fb2_limits',
        'Invalid FictionBook export limits.',
      );
    }
    source._assertEditable();
    if (source.fixedLayout) {
      throw const EpubException(
        'fb2_fixed_layout',
        'FictionBook export requires a reflowable book. Fixed page layouts cannot be preserved.',
      );
    }
    final errors = source.validate().where((issue) => issue.isError);
    if (errors.isNotEmpty) {
      throw EpubException(
        'invalid_epub',
        errors.first.message,
        path: errors.first.path,
      );
    }
    _resources = {
      for (final resource in source.resources) resource.path: resource,
    };
    final chapters = source.chapters;
    if (chapters.isEmpty) {
      throw const EpubException(
        'fb2_empty_book',
        'The book has no reading order.',
      );
    }
    final seenPaths = <String>{};
    for (final chapter in chapters) {
      if (!seenPaths.add(chapter.path)) {
        throw EpubException(
          'fb2_duplicate_chapter',
          'Repeated reading-order resources cannot be given unambiguous FictionBook links.',
          path: chapter.path,
        );
      }
      if (_resources[chapter.path]?.mediaType != 'application/xhtml+xml') {
        throw EpubException(
          'fb2_chapter_format',
          'FictionBook export requires XHTML text chapters.',
          path: chapter.path,
        );
      }
      final document = source._xml(chapter.path);
      final body = _elements(document, 'body').firstOrNull;
      if (body == null) {
        throw EpubException(
          'fb2_missing_body',
          'The chapter has no body.',
          path: chapter.path,
        );
      }
      final id = _newId();
      _checkVocabulary(body, chapter.path);
      _ids[_target(chapter.path, '')] = id;
      _anchors[body] = id;
      _anchors[document.rootElement] = id;
      for (final element in body.descendants.whereType<XmlElement>()) {
        _checkVocabulary(element, chapter.path);
        if (_fbBlockTags.contains(element.name.local)) {
          _anchors[element] = _newId();
        }
      }
      for (final element in [
        document.rootElement,
        body,
        ...body.descendants.whereType<XmlElement>(),
      ]) {
        final original =
            element.getAttribute('id') ??
            element.getAttribute(
              'id',
              namespace: 'http://www.w3.org/XML/1998/namespace',
            );
        if (original == null || original.isEmpty) continue;
        final target = _target(chapter.path, original);
        if (_ids.containsKey(target)) {
          throw EpubException(
            'fb2_duplicate_id',
            'Duplicate chapter anchor.',
            path: chapter.path,
          );
        }
        XmlNode? owner = element;
        while (owner is XmlElement && !_anchors.containsKey(owner)) {
          owner = owner.parent;
        }
        _ids[target] = owner is XmlElement ? _anchors[owner]! : id;
        if (owner != element) {
          _warn(
            'fb2_inline_anchor',
            'Inline link targets move to the containing paragraph or section.',
            chapter.path,
          );
        }
      }
      _chapters.add(_FictionBookChapter(chapter, body, id));
    }
    _warn(
      'fb2_presentation',
      'FictionBook uses its reader’s typography. EPUB stylesheets, fonts, page geometry and custom styling are not retained.',
    );
    _warn(
      'fb2_contents',
      'FictionBook contents are built from the reading order, section titles and headings; custom EPUB navigation labels can change.',
    );
    final main = <XmlNode>[];
    for (final chapter in _chapters) {
      final section = _section(
        chapter.body,
        chapter.chapter.path,
        title: chapter.chapter.title,
        forceId: chapter.id,
        collectNotes: true,
      );
      if (_isNote(chapter.body) ||
          _tokens(
            chapter.body.getAttribute('class'),
          ).contains('notesBodyType')) {
        _notes.add(section);
      } else {
        if (!chapter.chapter.linear) {
          _warn(
            'fb2_non_linear',
            'An auxiliary chapter is included in the FictionBook reading order.',
            chapter.chapter.path,
          );
        }
        main.add(section);
      }
    }
    if (main.isEmpty)
      main.add(_element('section', children: [_element('empty-line')]));
    final description = _description();
    final root = _element(
      'FictionBook',
      attributes: {
        'xmlns': _fbNamespace,
        'xmlns:l': _fbXlink,
        'xmlns:xml': 'http://www.w3.org/XML/1998/namespace',
      },
      children: [
        description,
        _element('body', children: main),
        if (_notes.isNotEmpty)
          _element('body', attributes: {'name': 'notes'}, children: _notes),
        ..._images.values,
      ],
    );
    final document = XmlDocument([
      XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'),
      root,
    ]);
    final exportedIds = root.descendants.whereType<XmlElement>()
        .map((element) => element.getAttribute('id')).whereType<String>().toSet();
    for (final element in root.descendants.whereType<XmlElement>()) {
      final href = element.getAttribute('href', namespace: _fbXlink);
      if (href != null && href.startsWith('#') && !exportedIds.contains(href.substring(1))) {
        throw const EpubException('fb2_unrepresentable_anchor',
            'A link target belongs to structure that FictionBook cannot retain. Simplify the linked structure before export.');
      }
    }
    final bytes = Uint8List.fromList(utf8.encode(document.toXmlString()));
    if (bytes.length > options.maxOutputBytes) {
      throw const EpubException(
        'fb2_output_limit',
        'The FictionBook exceeds the output size limit.',
      );
    }
    if (!zipped) return FictionBookExportResult._(bytes, false, _warnings);
    final container = archive.Archive()
      ..addFile(archive.ArchiveFile.bytes('book.fb2', bytes));
    final compressed = archive.ZipEncoder().encodeBytes(container);
    if (compressed.length > options.maxOutputBytes) {
      throw const EpubException(
        'fb2_output_limit',
        'The FictionBook archive exceeds the output size limit.',
      );
    }
    return FictionBookExportResult._(compressed, true, _warnings);
  }

  XmlElement _description() {
    final authors = source.authors
        .where((author) => author.trim().isNotEmpty)
        .toList();
    if (authors.isEmpty) {
      authors.add('Unknown');
      _warn(
        'fb2_unknown_author',
        'FictionBook requires an author; the missing name is recorded as “Unknown”.',
      );
    }
    final cover = source.coverPath;
    final coverId = cover == null ? null : _binary(cover, source.packagePath);
    final date = (options.createdAt ?? DateTime.now()).toUtc();
    if (date.year < 1 || date.year > 9999) {
      throw const EpubException(
        'fb2_date',
        'The export date must have a four-digit positive year.',
      );
    }
    final dateText =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final subjects = source
        ._metadataElements('subject')
        .map((element) => element.innerText)
        .toList();
    final publisher = source._metadataValue('publisher');
    final published = source._metadataValue('date');
    final identifier = source.identifier.trim();
    final info = _element(
      'title-info',
      children: [
        _element('genre', text: 'unrecognised'),
        for (final author in authors)
          _element('author', children: [_element('nickname', text: author)]),
        _element('book-title', text: source.title),
        if (source.description.trim().isNotEmpty)
          _element(
            'annotation',
            children: [
              for (final paragraph in source.description.split(
                RegExp(r'\r?\n\s*\r?\n'),
              ))
                _element('p', text: paragraph),
            ],
          ),
        if (subjects.isNotEmpty)
          _element('keywords', text: subjects.join(', ')),
        if (published.isNotEmpty) _element('date', text: published),
        if (coverId != null)
          _element(
            'coverpage',
            children: [
              _element('image', attributes: {'l:href': '#$coverId'}),
            ],
          ),
        _element(
          'lang',
          text: source.language.isEmpty ? 'und' : source.language,
        ),
      ],
    );
    _warn(
      'fb2_genre',
      'The FictionBook genre is “unrecognised”; EPUB subjects are retained as keywords.',
    );
    return _element(
      'description',
      children: [
        info,
        _element(
          'document-info',
          children: [
            _element(
              'author',
              children: [_element('nickname', text: 'CrispCloud')],
            ),
            _element('program-used', text: 'CrispCloud FictionBook exporter'),
            _element('date', text: dateText, attributes: {'value': dateText}),
            _element(
              'id',
              text: identifier.isEmpty
                  ? 'urn:crispcloud:fb2:${crypto.sha256.convert(utf8.encode('${source.title}\n${source.authors.join('\n')}'))}'
                  : identifier,
            ),
            _element('version', text: '1.0'),
          ],
        ),
        if (publisher.isNotEmpty)
          _element(
            'publish-info',
            children: [_element('publisher', text: publisher)],
          ),
        if (identifier.isNotEmpty)
          _element(
            'custom-info',
            text: identifier,
            attributes: {'info-type': 'source-identifier'},
          ),
      ],
    );
  }

  XmlElement _section(
    XmlElement element,
    String resourcePath, {
    String? title,
    String? forceId,
    bool collectNotes = true,
  }) {
    final children = <XmlNode>[];
    final heading = element.childElements.firstOrNull;
    final initialHeading = heading != null && _headingLevel(heading) != null;
    final chosenTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : initialHeading
        ? heading.innerText.trim()
        : null;
    if (chosenTitle != null && chosenTitle.isNotEmpty) {
      final sameHeading =
          initialHeading &&
          _normalized(heading.innerText) == _normalized(chosenTitle);
      children.add(
        _element(
          'title',
          children: sameHeading
              ? _paragraph(heading, resourcePath)
              : [_element('p', text: chosenTitle)],
        ),
      );
    }
    final nodes = element.children
        .where(
          (node) =>
              !(initialHeading &&
                  identical(node, heading) &&
                  chosenTitle != null &&
                  _normalized(heading.innerText) == _normalized(chosenTitle)),
        )
        .toList();
    children.addAll(_blocks(nodes, resourcePath, collectNotes: collectNotes));
    _normalizeSection(children);
    return _element(
      'section',
      attributes: {
        if (forceId ?? _anchors[element] case final String id) 'id': id,
        ..._language(element),
      },
      children: children,
    );
  }

  /// FB2 sections contain either child sections or a run of flow blocks.
  /// Group interleaved flow blocks into anonymous sections without reordering.
  void _normalizeSection(List<XmlNode> children) {
    final pending = children.toList();
    children.clear();
    final title =
        pending.firstOrNull is XmlElement &&
            (pending.first as XmlElement).name.local == 'title'
        ? pending.removeAt(0)
        : null;
    if (pending.any(
      (child) => child is XmlElement && child.name.local == 'section',
    )) {
      final normalized = <XmlNode>[];
      var group = <XmlNode>[];
      void flush() {
        if (group.isEmpty) return;
        normalized.add(_element('section', children: group));
        group = [];
      }

      for (final child in pending) {
        if (child is XmlElement && child.name.local == 'section') {
          flush();
          normalized.add(child);
        } else {
          group.add(child);
        }
      }
      flush();
      children
        ..clear()
        ..addAll(normalized);
    } else {
      children.addAll(pending);
    }
    if (children.isEmpty) children.add(_element('empty-line'));
    if (title != null) children.insert(0, title);
  }

  List<XmlNode> _blocks(
    Iterable<XmlNode> nodes,
    String resourcePath, {
    bool collectNotes = true,
  }) {
    final result = <XmlNode>[];
    var inline = <XmlNode>[];
    final headings = <(int, XmlElement)>[];
    List<XmlNode> destination() =>
        headings.isEmpty ? result : headings.last.$2.children;
    void flush() {
      if (inline.isEmpty) return;
      if (inline.any(
        (node) => node is XmlElement || (node.value ?? '').trim().isNotEmpty,
      )) {
        destination().addAll(_paragraphNodes(inline, resourcePath));
      }
      inline = [];
    }

    for (final node in nodes) {
      if (node is! XmlElement) {
        if (node is XmlText || node is XmlCDATA) inline.add(node);
        continue;
      }
      final tag = node.name.local;
      if (!_fbBlockTags.contains(tag) && tag != 'img') {
        inline.add(node);
        continue;
      }
      flush();
      if (collectNotes && _isNote(node)) {
        _notes.add(_section(node, resourcePath, collectNotes: false));
        continue;
      }
      final level = _headingLevel(node);
      if (level != null) {
        while (headings.isNotEmpty && headings.last.$1 >= level)
          headings.removeLast();
        final section = _element(
          'section',
          children: [
            _element('title', children: _paragraph(node, resourcePath)),
          ],
        );
        destination().add(section);
        headings.add((level, section));
        continue;
      }
      final out = destination();
      if (tag == 'p' || tag == 'figcaption' || tag == 'dt' || tag == 'dd') {
        out.addAll(_paragraph(node, resourcePath));
      } else if (tag == 'img') {
        out.add(_element('p', children: [_image(node, resourcePath)]));
      } else if (tag == 'hr') {
        out.add(
          _element('p', text: '* * *', attributes: _blockAttributes(node)),
        );
      } else if (tag == 'pre') {
        _warn(
          'fb2_preformatted',
          'Preformatted lines are retained as separate code paragraphs; exact spacing depends on the reader.',
          resourcePath,
        );
        final lines = node.innerText.split(RegExp(r'\r?\n'));
        for (var i = 0; i < lines.length; i++) {
          out.add(
            _element(
              'p',
              attributes: i == 0 ? _blockAttributes(node) : const {},
              children: [_element('code', text: lines[i])],
            ),
          );
        }
      } else if (tag == 'table') {
        out.addAll(_table(node, resourcePath));
      } else if (tag == 'ul' || tag == 'ol') {
        out.add(_list(node, resourcePath));
      } else if (tag == 'blockquote') {
        final blocks = _blocks(
          node.children,
          resourcePath,
          collectNotes: collectNotes,
        );
        if (blocks.any(
          (child) => child is XmlElement && child.name.local == 'section',
        )) {
          _warn(
            'fb2_quote_structure',
            'A quotation containing sections keeps its structure without a citation wrapper.',
            resourcePath,
          );
          out.add(_section(node, resourcePath, collectNotes: collectNotes));
        } else {
          out.add(
            _element(
              'cite',
              attributes: _blockAttributes(node),
              children: blocks,
            ),
          );
        }
      } else if (tag == 'td' || tag == 'th') {
        throw EpubException(
          'fb2_table_structure',
          'A table cell occurs outside a table.',
          path: resourcePath,
        );
      } else {
        out.add(_section(node, resourcePath, collectNotes: collectNotes));
      }
    }
    flush();
    void normalizeHeadings(List<XmlNode> entries) {
      for (final entry in entries.whereType<XmlElement>()) {
        if (entry.name.local != 'section') continue;
        normalizeHeadings(entry.children);
        _normalizeSection(entry.children);
      }
    }

    normalizeHeadings(result);
    return result;
  }

  XmlElement _list(XmlElement list, String resourcePath) {
    _warn(
      'fb2_lists',
      'Lists are represented by numbered or bulleted paragraphs; custom list markers are not retained.',
      resourcePath,
    );
    final items = <XmlNode>[];
    var number = int.tryParse(list.getAttribute('start') ?? '') ?? 1;
    if (number.abs() > 1000000) number = 1;
    for (final child in list.childElements) {
      if (child.name.local != 'li') {
        throw EpubException(
          'fb2_list_structure',
          'A list contains an unsupported child element.',
          path: resourcePath,
        );
      }
      number = int.tryParse(child.getAttribute('value') ?? '') ?? number;
      final prefix = list.name.local == 'ol' ? '$number. ' : '• ';
      final blocks = _blocks(child.children, resourcePath);
      if (blocks.firstOrNull is XmlElement &&
          (blocks.first as XmlElement).name.local == 'p') {
        (blocks.first as XmlElement).children.insert(0, _text(prefix));
      } else {
        blocks.insert(0, _element('p', text: prefix.trimRight()));
      }
      _normalizeSection(blocks);
      items.add(
        _element(
          'section',
          attributes: _blockAttributes(child),
          children: blocks,
        ),
      );
      number++;
    }
    if (items.isEmpty) items.add(_element('empty-line'));
    return _element(
      'section',
      attributes: _blockAttributes(list),
      children: items,
    );
  }

  List<XmlNode> _table(XmlElement table, String resourcePath) {
    final result = <XmlNode>[];
    final rows = <XmlNode>[];
    for (final caption in table.childElements.where(
      (child) => child.name.local == 'caption',
    )) {
      result.addAll(_paragraph(caption, resourcePath));
    }
    for (final row in table.descendants.whereType<XmlElement>().where(
      (child) => child.name.local == 'tr',
    )) {
      if (row.ancestors.whereType<XmlElement>().firstWhere(
            (parent) => parent.name.local == 'table',
          ) !=
          table) {
        throw EpubException(
          'fb2_nested_table',
          'Nested tables cannot be exported to FictionBook.',
          path: resourcePath,
        );
      }
      final cells = <XmlNode>[];
      for (final cell in row.childElements) {
        if (!{'td', 'th'}.contains(cell.name.local)) {
          throw EpubException(
            'fb2_table_structure',
            'A table row has an unsupported child element.',
            path: resourcePath,
          );
        }
        final attrs = _blockAttributes(cell);
        for (final name in ['colspan', 'rowspan']) {
          final raw = cell.getAttribute(name);
          if (raw == null) continue;
          final value = int.tryParse(raw);
          if (value == null || value < 1 || value > 1000) {
            throw EpubException(
              'fb2_table_span',
              'A table span is invalid or exceeds the export limit.',
              path: resourcePath,
            );
          }
          attrs[name] = '$value';
        }
        final align = cell.getAttribute('align');
        if ({'left', 'right', 'center'}.contains(align))
          attrs['align'] = align!;
        final valign = cell.getAttribute('valign');
        if ({'top', 'middle', 'bottom'}.contains(valign))
          attrs['valign'] = valign!;
        final lines = _inline(
          cell.children,
          resourcePath,
          allowBlockText: true,
        );
        if (lines.length > 1)
          _warn(
            'fb2_table_lines',
            'Multiple lines inside table cells are separated with spaces.',
            resourcePath,
          );
        cells.add(
          _element(
            cell.name.local,
            attributes: attrs,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) _text(' '),
                ...lines[i],
              ],
            ],
          ),
        );
      }
      if (cells.isEmpty)
        throw EpubException(
          'fb2_table_structure',
          'An empty table row cannot be exported.',
          path: resourcePath,
        );
      rows.add(_element('tr', children: cells));
    }
    if (rows.isEmpty)
      throw EpubException(
        'fb2_table_structure',
        'An empty table cannot be exported.',
        path: resourcePath,
      );
    result.add(
      _element(
        'table',
        attributes: {if (_anchors[table] case final String id) 'id': id},
        children: rows,
      ),
    );
    return result;
  }

  List<XmlElement> _paragraph(XmlElement element, String resourcePath) =>
      _paragraphNodes(
        element.children,
        resourcePath,
        attributes: _blockAttributes(element),
      );

  List<XmlElement> _paragraphNodes(
    Iterable<XmlNode> nodes,
    String resourcePath, {
    Map<String, String> attributes = const {},
  }) {
    final lines = _inline(nodes, resourcePath);
    if (lines.length > 1)
      _warn(
        'fb2_line_breaks',
        'Explicit line breaks are retained as paragraph boundaries.',
        resourcePath,
      );
    return [
      for (var i = 0; i < lines.length; i++)
        _element(
          'p',
          attributes: i == 0
              ? attributes
              : {
                  if (attributes['xml:lang'] case final String language)
                    'xml:lang': language,
                },
          children: lines[i],
        ),
    ];
  }

  List<List<XmlNode>> _inline(
    Iterable<XmlNode> nodes,
    String resourcePath, {
    bool inLink = false,
    bool allowBlockText = false,
  }) {
    final lines = <List<XmlNode>>[[]];
    for (final node in nodes) {
      if (node is XmlText || node is XmlCDATA) {
        lines.last.add(_text(node.value ?? ''));
        continue;
      }
      if (node is! XmlElement) continue;
      _checkVocabulary(node, resourcePath);
      final tag = node.name.local;
      if (tag == 'br') {
        lines.add([]);
        continue;
      }
      if (_fbBlockTags.contains(tag)) {
        if (!allowBlockText ||
            {
              'table',
              'ul',
              'ol',
              'section',
              'article',
              'aside',
            }.contains(tag)) {
          throw EpubException(
            'fb2_inline_structure',
            'A block element cannot be represented inside FictionBook inline content.',
            path: resourcePath,
          );
        }
        _warn(
          'fb2_table_blocks',
          'Block structure inside a table cell is flattened while retaining text.',
          resourcePath,
        );
        if (lines.last.isNotEmpty) lines.add([]);
      }
      if (tag == 'img') {
        lines.last.add(_image(node, resourcePath));
        continue;
      }
      var name = switch (tag) {
        'b' || 'strong' => 'strong',
        'i' || 'em' || 'cite' => 'emphasis',
        's' || 'del' || 'strike' => 'strikethrough',
        'sub' => 'sub',
        'sup' => 'sup',
        'code' || 'kbd' || 'samp' => 'code',
        'a' => 'a',
        _ => '',
      };
      final attrs = <String, String>{};
      if (tag == 'a') {
        if (inLink)
          throw EpubException(
            'fb2_nested_link',
            'Nested links cannot be exported.',
            path: resourcePath,
          );
        final href = node.getAttribute('href');
        if (href == null || href.isEmpty) {
          name = '';
        } else {
          attrs['l:href'] = _link(href, resourcePath);
          if (_tokens(_attribute(node, 'type')).contains('noteref') ||
              _tokens(node.getAttribute('role')).contains('doc-noteref')) {
            if (!attrs['l:href']!.startsWith('#')) {
              throw EpubException(
                'fb2_note_link',
                'A note reference must point inside the book.',
                path: resourcePath,
              );
            }
            attrs['type'] = 'note';
          }
        }
      } else if (!{
            'span',
            'small',
            'q',
            'abbr',
            'dfn',
            'time',
            'wbr',
          }.contains(tag) &&
          name.isEmpty &&
          !allowBlockText) {
        _warn(
          'fb2_inline_style',
          'Unsupported inline styling is removed while retaining its text.',
          resourcePath,
        );
      }
      if (!inLink && name != 'a') attrs.addAll(_language(node));
      final parts = _inline(
        node.children,
        resourcePath,
        inLink: inLink || name == 'a',
        allowBlockText: allowBlockText,
      );
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (name.isEmpty) {
          if (tag == 'q' && i == 0) lines.last.add(_text('“'));
          lines.last.addAll(parts[i]);
          if (tag == 'q' && i == parts.length - 1) lines.last.add(_text('”'));
        } else {
          lines.last.add(_element(name, attributes: attrs, children: parts[i]));
        }
      }
    }
    return lines;
  }

  String _link(String href, String resourcePath) {
    final uri = Uri.tryParse(href);
    if (uri == null)
      throw EpubException('fb2_link', 'Invalid hyperlink.', path: resourcePath);
    if (uri.hasScheme || uri.hasAuthority) {
      if (!{'https', 'http', 'mailto'}.contains(uri.scheme.toLowerCase()) ||
          (uri.scheme.toLowerCase() != 'mailto' && uri.host.isEmpty) ||
          uri.userInfo.isNotEmpty) {
        throw EpubException(
          'fb2_link_scheme',
          'FictionBook links support only local targets, HTTP, HTTPS and mailto.',
          path: resourcePath,
        );
      }
      return href;
    }
    final path = _resolveLocal(resourcePath, href);
    final id = _ids[_target(path!, Uri.decodeComponent(uri.fragment))];
    if (id == null) {
      throw EpubException(
        'fb2_unresolved_link',
        'A hyperlink points to content that is not in the exported reading order.',
        path: resourcePath,
      );
    }
    return '#$id';
  }

  XmlElement _image(XmlElement image, String resourcePath) {
    final src = image.getAttribute('src');
    if (src == null || src.isEmpty) {
      throw EpubException(
        'fb2_image_source',
        'An image has no source.',
        path: resourcePath,
      );
    }
    if (image.getAttribute('srcset')?.isNotEmpty == true) {
      _warn(
        'fb2_image_variants',
        'The default image is retained; responsive image variants are not carried across.',
        resourcePath,
      );
    }
    final target = _resolveLocal(resourcePath, src);
    if (target == null) {
      throw EpubException(
        'fb2_external_image',
        'Images must be packaged in the book before FictionBook export.',
        path: resourcePath,
      );
    }
    final id = _binary(target, resourcePath);
    return _element(
      'image',
      attributes: {
        'l:href': '#$id',
        if (image.getAttribute('alt') case final String alt) 'alt': alt,
      },
    );
  }

  String _binary(String imagePath, String resourcePath) {
    if (_images[imagePath] case final XmlElement image)
      return image.getAttribute('id')!;
    if (_images.length >= options.maxImages) {
      throw const EpubException(
        'fb2_image_limit',
        'The FictionBook contains too many images.',
      );
    }
    final resource = _resources[imagePath];
    if (resource == null || resource.isEncrypted) {
      throw EpubException(
        'fb2_image_source',
        'An image is missing or encrypted.',
        path: imagePath,
      );
    }
    if (!{
      'image/png',
      'image/jpeg',
      'image/gif',
    }.contains(resource.mediaType)) {
      throw EpubException(
        'fb2_image_format',
        'FictionBook export supports PNG, JPEG and GIF images. Convert this image before exporting.',
        path: imagePath,
      );
    }
    _reserve(((resource.size + 2) ~/ 3) * 4);
    final bytes = source.readBytes(imagePath);
    final matches = switch (resource.mediaType) {
      'image/png' =>
        bytes.length >= 8 &&
            [
              137,
              80,
              78,
              71,
              13,
              10,
              26,
              10,
            ].indexed.every((entry) => bytes[entry.$1] == entry.$2),
      'image/jpeg' =>
        bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255,
      'image/gif' =>
        bytes.length >= 6 &&
            (ascii.decode(bytes.sublist(0, 6), allowInvalid: true) ==
                    'GIF87a' ||
                ascii.decode(bytes.sublist(0, 6), allowInvalid: true) ==
                    'GIF89a'),
      _ => false,
    };
    if (!matches)
      throw EpubException(
        'fb2_image_signature',
        'The image data does not match its declared type.',
        path: imagePath,
      );
    final id = 'image-${_images.length + 1}';
    final element = _element(
      'binary',
      attributes: {'id': id, 'content-type': resource.mediaType},
    );
    // Already charged before allocating base64.
    element.children.add(XmlText(base64Encode(bytes)));
    _images[imagePath] = element;
    return id;
  }

  void _checkVocabulary(XmlElement element, String resourcePath) {
    final namespace = element.name.namespaceUri;
    if ((namespace != null && namespace.isNotEmpty && namespace != _fbXhtml) ||
        _fbForbiddenTags.contains(element.name.local)) {
      throw EpubException(
        'fb2_unsupported_content',
        'FictionBook cannot preserve <${element.name.qualified}> content. Keep this book as EPUB or simplify it before export.',
        path: resourcePath,
      );
    }
    if (element.attributes.any(
      (attribute) => attribute.name.local.toLowerCase().startsWith('on'),
    )) {
      throw EpubException(
        'fb2_active_content',
        'Active event handlers must be removed before FictionBook export.',
        path: resourcePath,
      );
    }
    if (element.getAttribute('style')?.isNotEmpty == true ||
        element.getAttribute('class')?.isNotEmpty == true) {
      _warn(
        'fb2_custom_style',
        'CSS classes and inline style rules are not retained.',
        resourcePath,
      );
    }
  }

  bool _isNote(XmlElement element) {
    final semantics = _tokens(_attribute(element, 'type'));
    final roles = _tokens(element.getAttribute('role'));
    return semantics.any(
          {
            'footnote',
            'endnote',
            'rearnote',
            'footnotes',
            'endnotes',
            'rearnotes',
          }.contains,
        ) ||
        roles.any({'doc-footnote', 'doc-endnote', 'doc-endnotes'}.contains);
  }

  Map<String, String> _blockAttributes(XmlElement element) => {
    if (_anchors[element] case final String id) 'id': id,
    ..._language(element),
  };

  Map<String, String> _language(XmlElement element) {
    final language =
        element.getAttribute(
          'lang',
          namespace: 'http://www.w3.org/XML/1998/namespace',
        ) ??
        element.getAttribute('xml:lang') ??
        element.getAttribute('lang');
    return {if (language != null && language.isNotEmpty) 'xml:lang': language};
  }

  XmlElement _element(
    String name, {
    Map<String, String> attributes = const {},
    Iterable<XmlNode> children = const [],
    String? text,
  }) {
    _reserve(
      2 * name.length +
          5 +
          attributes.entries.fold<int>(
            0,
            (sum, entry) =>
                sum + entry.key.length + _escape(entry.value).length + 4,
          ),
    );
    return XmlElement(
      XmlName(name),
      [
        for (final entry in attributes.entries)
          XmlAttribute(XmlName.fromString(entry.key), entry.value),
      ],
      [...children, if (text != null) _text(text)],
    );
  }

  XmlText _text(String text) {
    if (text.runes.any(
      (rune) =>
          rune != 9 &&
          rune != 10 &&
          rune != 13 &&
          (rune < 32 ||
              (rune >= 0xd800 && rune <= 0xdfff) ||
              rune == 0xfffe ||
              rune == 0xffff),
    )) {
      throw const EpubException(
        'fb2_xml_character',
        'The book contains characters that XML cannot represent.',
      );
    }
    _reserve(utf8.encode(_escape(text)).length);
    return XmlText(text);
  }

  void _reserve(int bytes) {
    _estimatedBytes += bytes;
    if (_estimatedBytes > options.maxOutputBytes) {
      throw const EpubException(
        'fb2_output_limit',
        'The FictionBook exceeds the output size limit.',
      );
    }
  }

  void _warn(String code, String message, [String? resourcePath]) {
    if (_warningKeys.add('$code|${resourcePath ?? ''}')) {
      if (_warnings.length < 500) {
        _warnings.add(
          EpubIssue(
            EpubIssueSeverity.warning,
            code,
            message,
            path: resourcePath,
          ),
        );
      } else if (_warnings.length == 500) {
        _warnings.add(
          const EpubIssue(
            EpubIssueSeverity.warning,
            'fb2_more_warnings',
            'Additional resources have the same conversion limitations.',
          ),
        );
      }
    }
  }

  String _newId() => 'anchor-${++_nextId}';
  String _target(String resourcePath, String fragment) =>
      '$resourcePath\u0000$fragment';
  Set<String> _tokens(String? value) => (value ?? '')
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toSet();
  String _normalized(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');
  int? _headingLevel(XmlElement element) =>
      RegExp(r'^h[1-6]$').hasMatch(element.name.local)
      ? int.parse(element.name.local.substring(1))
      : null;
}
