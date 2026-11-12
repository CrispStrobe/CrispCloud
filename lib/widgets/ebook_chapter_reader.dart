import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../l10n/ebook_strings.dart';
import '../services/image_edit_session.dart';

/// A portable chapter reader using the app's existing Flutter HTML renderer.
/// Linux does not bundle a browser runtime with incompatible third-party terms.
/// This view deliberately exposes chapter navigation, not foliate pagination,
/// CFI highlights, scripts, remote images or fixed-layout fidelity.
class EbookChapterReader extends StatefulWidget {
  const EbookChapterReader({
    super.key,
    required this.document,
    required this.onLocationChanged,
    this.initialSection = 0,
  });
  final EpubDocument document;
  final ValueChanged<EbookLocation> onLocationChanged;
  final int initialSection;
  @override
  State<EbookChapterReader> createState() => _EbookChapterReaderState();
}

class _EbookChapterReaderState extends State<EbookChapterReader> {
  late int _index;
  double _fontSize = 18;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _index = widget.document.chapters.isEmpty
        ? 0
        : widget.initialSection.clamp(0, widget.document.chapters.length - 1);
  }

  @override
  void didUpdateWidget(covariant EbookChapterReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chapters = widget.document.chapters;
    final requested =
        !identical(oldWidget.document, widget.document) ||
            oldWidget.initialSection != widget.initialSection
        ? widget.initialSection
        : _index;
    final next = chapters.isEmpty ? 0 : requested.clamp(0, chapters.length - 1);
    if (next != _index || !identical(oldWidget.document, widget.document)) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    _index = next;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int index) {
    final chapters = widget.document.chapters;
    if (index < 0 || index >= chapters.length) return;
    setState(() => _index = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    widget.onLocationChanged(
      EbookLocation(
        cfi: 'crisp-section:$index',
        fraction: index / chapters.length,
        sectionIndex: index,
        chapterTitle: chapters[index].title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.document.chapters;
    if (chapters.isEmpty) {
      return const Center(child: Text('This book has no readable chapters.'));
    }
    // EpubDocument is mutable: its reading order can also shrink before a
    // local font-size rebuild, without didUpdateWidget having been called.
    _index = _index.clamp(0, chapters.length - 1);
    final chapter = chapters[_index];
    final base = Uri(
      scheme: 'epub',
      pathSegments: ['', ...chapter.path.split('/')],
    );
    String source;
    try {
      source = widget.document.readText(chapter.path);
    } catch (error) {
      return Center(child: Text('$error'));
    }
    return Column(
      children: [
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
                onPressed: _fontSize > 12
                    ? () => setState(() => _fontSize -= 2)
                    : null,
                icon: const Icon(Icons.text_decrease),
              ),
              IconButton(
                tooltip: 'Larger text',
                onPressed: _fontSize < 36
                    ? () => setState(() => _fontSize += 2)
                    : null,
                icon: const Icon(Icons.text_increase),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.ebookTr(
              'Linux chapter reader. Advanced pagination, highlights and layout preview are available in the web and system WebView reader.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: HtmlWidget(
                    source,
                    key: ValueKey(
                      '${chapter.path}:${widget.document.revision}',
                    ),
                    baseUrl: base,
                    textStyle: TextStyle(fontSize: _fontSize, height: 1.6),
                    factoryBuilder: () => _LocalEbookImages(widget.document),
                    onTapUrl: (url) {
                      try {
                        final uri = base.resolve(url);
                        if (uri.scheme != 'epub' || uri.hasAuthority) {
                          return false;
                        }
                        final path = uri.pathSegments.join('/');
                        final index = widget.document.chapters.indexWhere(
                          (item) => item.path == path,
                        );
                        if (index < 0) return false;
                        _go(index);
                        return true;
                      } on FormatException {
                        // A malformed link must not break the fallback reader.
                        return false;
                      }
                    },
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
      final path = Uri.decodeComponent(uri.path)
          .replaceFirst(RegExp(r'^/'), '');
      if (!isEditableImageFileName(path)) return null;
      final bytes = document.readBytes(path);
      // Reject animated/oversized raster data before allocating decoded pixels.
      inspectEditableImage(bytes, fileName: path);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
