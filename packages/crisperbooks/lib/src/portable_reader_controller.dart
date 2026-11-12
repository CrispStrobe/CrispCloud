import 'dart:async';
import 'dart:convert';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Portable locations deliberately do not impersonate Foliate EPUB CFIs.
class EbookChapterTarget {
  const EbookChapterTarget({
    required this.path,
    this.fragment = '',
    this.progress = 0,
  });

  static const prefix = 'crisp-reader:v1:';
  final String path;
  final String fragment;
  final double progress;

  String get locator =>
      '$prefix${base64Url.encode(utf8.encode(jsonEncode({'path': path, if (fragment.isNotEmpty) 'fragment': fragment, 'progress': progress.clamp(0, 1)})))}';

  /// [basePath] is a decoded archive path. Without it, hrefs are archive-relative.
  static EbookChapterTarget? resolve(
    String value,
    List<EpubChapter> chapters, {
    String? basePath,
  }) {
    if (value.length > 16384) return null;
    try {
      EbookChapterTarget result;
      if (value.startsWith(prefix)) {
        final decoded = jsonDecode(
          utf8.decode(
            base64Url.decode(
              base64Url.normalize(value.substring(prefix.length)),
            ),
          ),
        );
        if (decoded is! Map || decoded['path'] is! String) return null;
        final fragment = decoded['fragment'] ?? '';
        final progress = decoded['progress'] ?? 0;
        if (fragment is! String ||
            fragment.length > 4096 ||
            progress is! num ||
            !progress.isFinite ||
            progress < 0 ||
            progress > 1) {
          return null;
        }
        result = EbookChapterTarget(
          path: decoded['path'] as String,
          fragment: fragment,
          progress: progress.toDouble(),
        );
      } else if (value.startsWith('crisp-section:')) {
        final index = int.tryParse(value.substring('crisp-section:'.length));
        if (index == null || index < 0 || index >= chapters.length) return null;
        result = EbookChapterTarget(path: chapters[index].path);
      } else {
        final base = Uri(
          scheme: 'epub',
          pathSegments: ['', ...?basePath?.split('/')],
        );
        final uri = base.resolve(value);
        if (uri.scheme != 'epub' || uri.hasAuthority || uri.hasQuery) {
          return null;
        }
        result = EbookChapterTarget(
          path: uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .join('/'),
          fragment: Uri.decodeComponent(uri.fragment),
        );
      }
      return chapters.any((chapter) => chapter.path == result.path)
          ? result
          : null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

class EbookChapterTextBlock {
  const EbookChapterTextBlock(this.anchor, this.text);
  final String anchor;
  final String text;
}

class PreparedEbookChapter {
  const PreparedEbookChapter(this.html, this.blocks);
  final String html;
  final List<EbookChapterTextBlock> blocks;

  int get estimatedBytes =>
      2 *
      (html.length +
          blocks.fold<int>(
            0,
            (sum, block) => sum + block.text.length + block.anchor.length,
          ));
}

const _blockTags = {
  'body',
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'div',
  'section',
  'article',
  'blockquote',
  'pre',
  'li',
  'dt',
  'dd',
  'td',
  'th',
  'figcaption',
};
const _unreadableTags = {
  'script',
  'style',
  'template',
  'noscript',
  'iframe',
  'object',
  'head',
};

/// Runs in an isolate for larger chapters. Added IDs exist only in this display
/// copy; EPUB resources are never rewritten to support search or bookmarks.
PreparedEbookChapter prepareEbookChapter(String source) {
  final document = html.parse(source);
  final body = document.body;
  if (body == null) return PreparedEbookChapter(source, const []);
  final ids = <String>{};
  final pending = <(dom.Node, int)>[(body, 0)];
  var count = 0;
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    if (++count > 25000 || depth > 128) {
      throw const FormatException(
        'This chapter is too complex for the portable reader.',
      );
    }
    if (node is dom.Element && node.id.isNotEmpty) ids.add(node.id);
    for (final child in node.nodes.reversed) {
      pending.add((child, depth + 1));
    }
  }

  final blocks = <EbookChapterTextBlock>[];
  final anchors = <String>[];
  var buffer = StringBuffer();
  var ordinal = 0;
  void flush() {
    final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    buffer = StringBuffer();
    if (text.isNotEmpty && anchors.isNotEmpty) {
      blocks.add(EbookChapterTextBlock(anchors.last, text));
    }
  }

  final stack = <(dom.Node, bool)>[(body, false)];
  while (stack.isNotEmpty) {
    final (node, exiting) = stack.removeLast();
    if (node is dom.Text) {
      buffer.write(node.data);
      continue;
    }
    if (node is! dom.Element) continue;
    if (_unreadableTags.contains(node.localName) ||
        node.attributes.containsKey('hidden')) {
      continue;
    }
    final isBlock = _blockTags.contains(node.localName);
    if (exiting) {
      if (isBlock) {
        flush();
        anchors.removeLast();
      }
      continue;
    }
    if (isBlock) {
      flush();
      if (node.id.isEmpty) {
        String id;
        do {
          id = 'crisp-reader-block-${ordinal++}';
        } while (ids.contains(id));
        node.id = id;
        ids.add(id);
      }
      anchors.add(node.id);
    }
    if (node.localName == 'br') buffer.write('\n');
    stack.add((node, true));
    for (final child in node.nodes.reversed) {
      stack.add((child, false));
    }
  }
  return PreparedEbookChapter(document.outerHtml, List.unmodifiable(blocks));
}

/// Controller for the portable EPUB renderer. It shares the app's reading
/// models while keeping its own location namespace and rendering capabilities.
class EbookChapterReaderController extends ChangeNotifier {
  static const maximumSearchChapterBytes = 2 * 1024 * 1024;
  static const maximumSearchBytes = 32 * 1024 * 1024;
  static const maximumSearchChapters = 2000;
  static const _maximumCacheBytes = 8 * 1024 * 1024;

  EpubDocument? _document;
  Object? _owner;
  int _revision = -1;
  int _searchGeneration = 0;
  bool _disposed = false;
  bool _notificationPending = false;
  Future<void> Function(EbookChapterTarget)? _navigate;
  void Function(EbookAppearance)? _setAppearance;
  final _cache = <String, PreparedEbookChapter>{};
  Map<String, int> _resourceSizes = const {};
  List<String> _searchWarnings = const [];
  EbookLocation? _location;

  bool get isReady => !_disposed && _document != null && _navigate != null;
  EbookLocation? get location => _location;
  List<String> get searchWarnings => _searchWarnings;

  /// Widget binding; an owner token prevents an obsolete widget detaching a
  /// controller that has already moved to a replacement reader.
  void attach({
    required Object owner,
    required EpubDocument document,
    required Future<void> Function(EbookChapterTarget) navigate,
    required void Function(EbookAppearance) setAppearance,
  }) {
    if (_disposed) {
      throw StateError('The chapter reader controller is disposed.');
    }
    if (!identical(document, _document) || !identical(owner, _owner)) {
      _location = null;
      _cache.clear();
      _revision = -1;
      ++_searchGeneration;
    }
    _owner = owner;
    _document = document;
    _navigate = navigate;
    _setAppearance = setAppearance;
    refreshDocument();
    _notifyLater();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _document = null;
    _navigate = null;
    _setAppearance = null;
    _location = null;
    _cache.clear();
    _resourceSizes = const {};
    ++_searchGeneration;
    _notifyLater();
  }

  void refreshDocument() {
    final revision = _document?.revision ?? -1;
    if (revision == _revision) return;
    _revision = revision;
    _cache.clear();
    _resourceSizes = {
      for (final resource in _document?.resources ?? const <EpubResource>[])
        resource.path: resource.size,
    };
    _searchWarnings = const [];
    ++_searchGeneration;
  }

  void recordLocation(Object owner, EbookLocation value) {
    if (_disposed || !identical(owner, _owner)) return;
    _location = value;
    _notifyLater();
  }

  void _notifyLater() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  EpubDocument get _book {
    if (!isReady) throw StateError('The chapter reader is not ready.');
    refreshDocument();
    return _document!;
  }

  Future<PreparedEbookChapter> prepareChapter(String path) async {
    final document = _book;
    final revision = document.revision;
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    final size = _resourceSizes[path];
    if (size == null) {
      throw const FormatException('This chapter is no longer available.');
    }
    // Preserve the document's existing text-read limit (8 MiB by default).
    // Searching a whole book has its own smaller per-chapter budget below.
    final source = document.readText(path);
    final prepared = source.length <= 16384
        ? prepareEbookChapter(source)
        : await compute(
            prepareEbookChapter,
            source,
            debugLabel: 'ebook chapter',
          );
    if (!_disposed &&
        identical(document, _document) &&
        document.revision == revision) {
      _cache[path] = prepared;
      var bytes = _cache.values.fold<int>(
        0,
        (sum, item) => sum + item.estimatedBytes,
      );
      while (_cache.isNotEmpty && bytes > _maximumCacheBytes) {
        bytes -= _cache.remove(_cache.keys.first)!.estimatedBytes;
      }
    }
    return prepared;
  }

  Future<void> goTo(String target) async {
    final book = _book;
    final parsed = EbookChapterTarget.resolve(target, book.chapters);
    if (parsed == null) {
      throw const FormatException(
        'This reading position is no longer available.',
      );
    }
    await _navigate!(parsed);
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);
  Future<void> _step(int offset) async {
    final chapters = _book.chapters;
    final index = (_location?.sectionIndex ?? 0) + offset;
    if (index >= 0 && index < chapters.length) {
      await _navigate!(EbookChapterTarget(path: chapters[index].path));
    }
  }

  Future<void> setAppearance(EbookAppearance appearance) async {
    _book;
    _setAppearance!(appearance);
  }

  void clearSearch() {
    ++_searchGeneration;
    _searchWarnings = const [];
  }

  Future<List<EbookSearchHit>> search(String query, {int limit = 200}) async {
    final document = _book;
    final revision = document.revision;
    final generation = ++_searchGeneration;
    _searchWarnings = const [];
    query = query.trim();
    if (query.isEmpty) return const [];
    if (query.length > 1000) {
      throw const FormatException('Search text exceeds 1,000 characters.');
    }
    final maximumHits = limit.clamp(1, 1000);
    final pattern = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
      unicode: true,
    );
    final chapters = document.chapters;
    final sizes = _resourceSizes;
    final hits = <EbookSearchHit>[];
    final warnings = <String>[];
    var bytes = 0;
    bool current() =>
        !_disposed &&
        generation == _searchGeneration &&
        identical(document, _document) &&
        document.revision == revision;
    for (var index = 0; index < chapters.length; index++) {
      await Future<void>.delayed(Duration.zero);
      if (!current()) return const [];
      final chapter = chapters[index];
      final size = sizes[chapter.path] ?? 0;
      if (index >= maximumSearchChapters) {
        warnings.add(
          'Search stopped at the 2,000-chapter / 32 MiB search limit.',
        );
        break;
      }
      if (size > maximumSearchChapterBytes) {
        if (warnings.length < 20) {
          warnings.add(
            'Could not search ${chapter.title}: this chapter exceeds the 2 MiB search limit.',
          );
        }
        continue;
      }
      if (bytes + size > maximumSearchBytes) {
        warnings.add(
          'Search stopped at the 2,000-chapter / 32 MiB search limit.',
        );
        break;
      }
      bytes += size;
      try {
        final prepared = await prepareChapter(chapter.path);
        if (!current()) return const [];
        for (final block in prepared.blocks) {
          for (final match in pattern.allMatches(block.text)) {
            final start = (match.start - 60).clamp(0, block.text.length);
            final end = (match.end + 100).clamp(0, block.text.length);
            hits.add(
              EbookSearchHit(
                cfi: EbookChapterTarget(
                  path: chapter.path,
                  fragment: block.anchor,
                ).locator,
                excerpt:
                    '${start > 0 ? '…' : ''}${block.text.substring(start, end)}${end < block.text.length ? '…' : ''}',
                sectionIndex: index,
              ),
            );
            if (hits.length >= maximumHits) {
              _searchWarnings = List.unmodifiable(warnings);
              return List.unmodifiable(hits);
            }
          }
        }
      } on Exception catch (error) {
        if (warnings.length < 20) {
          warnings.add('Could not search ${chapter.title}: $error');
        }
      }
    }
    if (!current()) return const [];
    _searchWarnings = List.unmodifiable(warnings);
    return List.unmodifiable(hits);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_searchGeneration;
    _cache.clear();
    _document = null;
    _navigate = null;
    _setAppearance = null;
    super.dispose();
  }
}
