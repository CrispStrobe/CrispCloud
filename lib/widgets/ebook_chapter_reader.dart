import 'dart:async';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../l10n/ebook_strings.dart';
import '../services/ebook_chapter_reader_controller.dart';
import '../services/image_edit_session.dart';

/// Portable EPUB reading with bounded search, local locations and appearance.
/// Book bytes remain authoritative; generated anchors exist in a display copy.
class EbookChapterReader extends StatefulWidget {
  const EbookChapterReader({
    super.key,
    required this.document,
    required this.onLocationChanged,
    this.controller,
    this.initialSection = 0,
    this.initialLocation,
    this.appearance = const EbookAppearance(),
    this.onAppearanceChanged,
    this.onReady,
    this.showControls = true,
  });

  final EpubDocument document;
  final ValueChanged<EbookLocation> onLocationChanged;
  final EbookChapterReaderController? controller;
  final int initialSection;
  final String? initialLocation;
  final EbookAppearance appearance;
  final ValueChanged<EbookAppearance>? onAppearanceChanged;
  final ValueChanged<EbookBookInfo>? onReady;
  final bool showControls;

  @override
  State<EbookChapterReader> createState() => _EbookChapterReaderState();
}

class _EbookChapterReaderState extends State<EbookChapterReader> {
  late EbookChapterReaderController _controller;
  late EbookAppearance _appearance;
  late int _index;
  int _revision = -1;
  int _loadGeneration = 0;
  int _navigationGeneration = 0;
  int _readyRevision = -1;
  String? _path;
  PreparedEbookChapter? _prepared;
  String? _error;
  bool _loading = false;
  bool _restoring = false;
  EbookChapterTarget? _pendingTarget;
  Timer? _locationTimer;
  final _scroll = ScrollController();
  GlobalKey<HtmlWidgetState> _html = GlobalKey<HtmlWidgetState>();

  @override
  void initState() {
    super.initState();
    _appearance = _boundedAppearance(widget.appearance);
    _controller = widget.controller ?? EbookChapterReaderController();
    _index = _boundedSection(widget.initialSection);
    _attach();
    _scroll.addListener(_onScroll);
    _restoreInitial();
  }

  int _boundedSection(int index) {
    final chapters = widget.document.chapters;
    return chapters.isEmpty ? 0 : index.clamp(0, chapters.length - 1);
  }

  void _attach() {
    _controller.attach(
      owner: this,
      document: widget.document,
      navigate: _navigate,
      setAppearance: _setAppearance,
    );
  }

  void _restoreInitial() {
    final chapters = widget.document.chapters;
    final location = widget.initialLocation;
    final target = location == null
        ? null
        : EbookChapterTarget.resolve(location, chapters);
    if (target != null) {
      _index = chapters.indexWhere((chapter) => chapter.path == target.path);
      _pendingTarget = target;
    } else if (chapters.isNotEmpty) {
      _pendingTarget = EbookChapterTarget(path: chapters[_index].path);
    }
    _loadChapter();
  }

  @override
  void didUpdateWidget(covariant EbookChapterReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    final documentChanged = !identical(oldWidget.document, widget.document);
    if (controllerChanged) {
      _controller.detach(this);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? EbookChapterReaderController();
    }
    if (controllerChanged || documentChanged) _attach();
    if (!_sameAppearance(oldWidget.appearance, widget.appearance)) {
      _appearance = _boundedAppearance(widget.appearance);
    }
    if (documentChanged || controllerChanged) {
      _index = _boundedSection(widget.initialSection);
      _readyRevision = -1;
      _restoreInitial();
    } else if (oldWidget.initialSection != widget.initialSection ||
        (oldWidget.initialLocation != widget.initialLocation &&
            widget.initialLocation != _controller.location?.cfi)) {
      _index = _boundedSection(widget.initialSection);
      _restoreInitial();
    } else {
      _refreshMutableDocument();
    }
  }

  void _refreshMutableDocument() {
    final chapters = widget.document.chapters;
    if (_revision == widget.document.revision && _index < chapters.length) {
      return;
    }
    final existing = chapters.indexWhere((chapter) => chapter.path == _path);
    _index = existing >= 0 ? existing : _boundedSection(_index);
    _pendingTarget = chapters.isEmpty
        ? null
        : EbookChapterTarget(path: chapters[_index].path);
    _loadChapter();
  }

  void _loadChapter() {
    _locationTimer?.cancel();
    final chapters = widget.document.chapters;
    _controller.refreshDocument();
    _revision = widget.document.revision;
    _index = _boundedSection(_index);
    final generation = ++_loadGeneration;
    ++_navigationGeneration;
    _prepared = null;
    _error = null;
    _html = GlobalKey<HtmlWidgetState>();
    if (chapters.isEmpty) {
      _path = null;
      _loading = false;
      return;
    }
    _path = chapters[_index].path;
    _loading = true;
    final path = _path!;
    unawaited(() async {
      PreparedEbookChapter? prepared;
      String? error;
      try {
        prepared = await _controller.prepareChapter(path);
      } catch (failure) {
        error = '$failure';
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _prepared = prepared;
        _error = error;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _loadGeneration) return;
        _announceReady();
        final target = _pendingTarget ?? EbookChapterTarget(path: path);
        _pendingTarget = null;
        unawaited(_restoreTarget(target));
      });
    }());
  }

  void _announceReady() {
    if (_readyRevision == _revision) return;
    _readyRevision = _revision;
    List<EbookTocItem> mapToc(List<EpubTocEntry> entries) => [
      for (final entry in entries)
        EbookTocItem(
          label: entry.label,
          href: entry.href,
          children: mapToc(entry.children),
        ),
    ];
    widget.onReady?.call(
      EbookBookInfo(
        title: widget.document.title,
        authors: widget.document.authors,
        language: widget.document.language,
        toc: mapToc(widget.document.toc),
        sectionCount: widget.document.chapters.length,
        sourceFormat: 'epub',
        fixedLayout: widget.document.fixedLayout,
        supportsProgressSeeking: false,
        supportsNavigationHistory: false,
        supportsLayout: false,
        supportsPublisherStyles: false,
      ),
    );
  }

  Future<void> _navigate(EbookChapterTarget target) async {
    if (!mounted) return;
    final chapters = widget.document.chapters;
    final index = chapters.indexWhere((chapter) => chapter.path == target.path);
    if (index < 0) return;
    _locationTimer?.cancel();
    final needsLoad =
        target.path != _path || _revision != widget.document.revision;
    setState(() {
      _index = index;
      _pendingTarget = target;
      if (needsLoad) _loadChapter();
    });
    if (!needsLoad && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_pendingTarget, target)) return;
        _pendingTarget = null;
        unawaited(_restoreTarget(target));
      });
    }
  }

  Future<void> _restoreTarget(EbookChapterTarget target) async {
    final generation = ++_navigationGeneration;
    _restoring = true;
    var anchored = false;
    if (target.fragment.isNotEmpty && _html.currentState != null) {
      anchored = await _html.currentState!.scrollToAnchor(target.fragment);
    }
    if (!mounted || generation != _navigationGeneration) return;
    if (!anchored && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent * target.progress);
    }
    _restoring = false;
    _emitLocation(fragment: anchored ? target.fragment : '');
  }

  void _onScroll() {
    if (_restoring || _loading) return;
    _locationTimer?.cancel();
    _locationTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _emitLocation();
    });
  }

  void _emitLocation({String fragment = ''}) {
    final chapters = widget.document.chapters;
    if (chapters.isEmpty || _index >= chapters.length) return;
    final chapter = chapters[_index];
    final extent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final progress = extent > 0
        ? (_scroll.offset / extent).clamp(0.0, 1.0)
        : 0.0;
    final location = EbookLocation(
      cfi: EbookChapterTarget(
        path: chapter.path,
        fragment: fragment,
        progress: progress,
      ).locator,
      fraction: (_index + progress) / chapters.length,
      sectionIndex: _index,
      chapterTitle: chapter.title,
    );
    _controller.recordLocation(this, location);
    widget.onLocationChanged(location);
  }

  void _go(int index) {
    final chapters = widget.document.chapters;
    if (index < 0 || index >= chapters.length) return;
    unawaited(_navigate(EbookChapterTarget(path: chapters[index].path)));
  }

  void _setAppearance(EbookAppearance value) {
    if (!mounted) return;
    final next = _boundedAppearance(value);
    if (_sameAppearance(next, _appearance)) return;
    setState(() => _appearance = next);
    widget.onAppearanceChanged?.call(next);
  }

  void _changeFont(double delta) => _setAppearance(
    _appearance.copyWith(fontSize: _appearance.fontSize + delta),
  );

  static EbookAppearance _boundedAppearance(EbookAppearance value) =>
      value.normalized.copyWith(flow: 'scrolled');

  static bool _sameAppearance(EbookAppearance a, EbookAppearance b) =>
      mapEquals(a.toJson(), b.toJson());

  @override
  void dispose() {
    ++_loadGeneration;
    ++_navigationGeneration;
    _locationTimer?.cancel();
    _controller.detach(this);
    if (widget.controller == null) _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _refreshMutableDocument();
    final chapters = widget.document.chapters;
    if (chapters.isEmpty) {
      return const Center(child: Text('This book has no readable chapters.'));
    }
    _index = _boundedSection(_index);
    final chapter = chapters[_index];
    final base = Uri(
      scheme: 'epub',
      pathSegments: ['', ...chapter.path.split('/')],
    );
    final (background, foreground) = switch (_appearance.theme) {
      'dark' => (const Color(0xff19222e), const Color(0xffdce4ec)),
      'sepia' => (const Color(0xfff5eddb), const Color(0xff493c2c)),
      _ => (Colors.white, const Color(0xff243248)),
    };
    return Column(
      children: [
        if (widget.showControls)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  tooltip: context.ebookTr('Previous chapter'),
                  onPressed: _index > 0 ? () => _go(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _index,
                    items: [
                      for (var index = 0; index < chapters.length; index++)
                        DropdownMenuItem(
                          value: index,
                          child: Text(
                            '${index + 1}. ${chapters[index].title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _go(value);
                    },
                  ),
                ),
                IconButton(
                  tooltip: context.ebookTr('Next chapter'),
                  onPressed: _index + 1 < chapters.length
                      ? () => _go(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Smaller text',
                  onPressed: _appearance.fontSize > 10
                      ? () => _changeFont(-2)
                      : null,
                  icon: const Icon(Icons.text_decrease),
                ),
                IconButton(
                  tooltip: 'Larger text',
                  onPressed: _appearance.fontSize < 48
                      ? () => _changeFont(2)
                      : null,
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: background,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    ),
                  )
                : SelectionArea(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: HtmlWidget(
                            _prepared?.html ?? '',
                            key: _html,
                            baseUrl: base,
                            textStyle: TextStyle(
                              fontSize: _appearance.fontSize,
                              height: _appearance.lineHeight,
                              fontFamily: _appearance.fontFamily,
                              color: foreground,
                            ),
                            factoryBuilder: () =>
                                _LocalEbookImages(widget.document),
                            onTapUrl: (url) {
                              final target = EbookChapterTarget.resolve(
                                url,
                                widget.document.chapters,
                                basePath: chapter.path,
                              );
                              if (target == null) return false;
                              unawaited(_navigate(target));
                              return true;
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LocalEbookImages extends WidgetFactory {
  _LocalEbookImages(this.document);
  final EpubDocument document;

  @override
  Future<bool> onTapUrl(String url) {
    // HtmlWidgetState.scrollToAnchor routes through onTapUrl. Handle its local
    // form directly so the app navigation callback cannot recurse into itself.
    if (url.startsWith('#')) return onTapAnchorWrapper(url.substring(1));
    return super.onTapUrl(url);
  }

  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
  @override
  ImageProvider? imageProviderFromDataUri(String dataUri) => null;
  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'epub' || uri.hasAuthority) return null;
    try {
      final path = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .join('/');
      if (!isEditableImageFileName(path)) return null;
      final bytes = document.readBytes(path);
      inspectEditableImage(bytes, fileName: path);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
