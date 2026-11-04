// lib/widgets/preview_pane.dart
//
// Toggleable preview pane that shows file details and content previews.
// Supports: images (inline), text/code (read-only), markdown (rendered),
// PDF (scrollable), video/audio (streaming player), and metadata for other types.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/file_bytes_loader.dart';
import '../services/internal_viewer_service.dart';
import '../utils/formatters.dart';
import 'file_list_view.dart' show getFileIcon;
import 'preview_media.dart';
import 'code_highlighting.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import '../services/log_service.dart';

/// File types we can preview inline.
enum PreviewType { image, svg, text, markdown, csv, pdf, video, audio, office, font, none }

PreviewType _classifyFile(String name) {
  final ext = name.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'ico':
      return PreviewType.image;
    case 'svg':
      return PreviewType.svg;
    case 'md':
    case 'markdown':
      return PreviewType.markdown;
    case 'pdf':
      return PreviewType.pdf;
    // Video files
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
    case 'wmv':
    case 'flv':
    case 'm4v':
      return PreviewType.video;
    // Audio files
    case 'mp3':
    case 'wav':
    case 'aac':
    case 'flac':
    case 'ogg':
    case 'm4a':
    case 'wma':
    case 'opus':
      return PreviewType.audio;
    case 'tsv':
    case 'csv':
      return PreviewType.csv;
    case 'txt':
    case 'log':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'ini':
    case 'cfg':
    case 'conf':
    case 'toml':
    case 'env':
    case 'gitignore':
    case 'dockerfile':
    // Code files
    case 'dart':
    case 'js':
    case 'ts':
    case 'jsx':
    case 'tsx':
    case 'py':
    case 'rb':
    case 'go':
    case 'rs':
    case 'java':
    case 'kt':
    case 'swift':
    case 'c':
    case 'cpp':
    case 'h':
    case 'hpp':
    case 'cs':
    case 'php':
    case 'html':
    case 'css':
    case 'scss':
    case 'less':
    case 'sql':
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'ps1':
    case 'bat':
    case 'r':
    case 'lua':
    case 'vim':
    case 'makefile':
      return PreviewType.text;
    case 'docx':
    case 'xlsx':
    case 'pptx':
    case 'odt':
    case 'ods':
    case 'odp':
    case 'epub':
      return PreviewType.office;
    case 'ttf':
    case 'otf':
    case 'woff':
    case 'woff2':
      return PreviewType.font;
    default:
      return PreviewType.none;
  }
}

/// Map file extension to highlight.js language name.
String? _highlightLang(String filename) {
  final lang = highlightLanguageFor(filename);
  if (lang != null && lang != 'plaintext') return lang;
  return null;
}

/// Extract readable text from Office documents (DOCX, XLSX, PPTX, ODT, EPUB).
/// Shared implementation lives in preview_media.dart.
Future<String> _extractOfficeText(Uint8List bytes, String filename) =>
    extractOfficeText(bytes, filename);
String _mimeTypeForExt(String ext) => mimeTypeForExt(ext);

class PreviewPane extends ConsumerStatefulWidget {
  final FileItem? file;
  final PanelSide side;

  const PreviewPane({
    super.key,
    required this.file,
    required this.side,
  });

  @override
  ConsumerState<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends ConsumerState<PreviewPane> {
  static const _log = Log('PreviewPane');
  Uint8List? _previewBytes;
  String? _textContent;
  PdfController? _pdfController;
  VideoPlayerController? _videoController;
  String? _mediaBlobUrl; // Web: blob URL for HTML5 audio/video
  bool _loading = false;
  String? _error;
  FileItem? _loadedFile; // track which file we loaded

  @override
  void didUpdateWidget(PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload preview when file changes
    if (widget.file != _loadedFile) {
      _loadPreview();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadPreview() {
    final file = widget.file;
    _log.debug('loadPreview: ${file?.name} side=${widget.side.name} type=${file != null ? _classifyFile(file.name).name : "null"}');
    _previewBytes = null;
    _textContent = null;
    _pdfController?.dispose();
    _pdfController = null;
    _videoController?.dispose();
    _videoController = null;
    _mediaBlobUrl = null;
    _error = null;
    _loadedFile = file;

    if (file == null || file.isFolder) {
      setState(() {});
      return;
    }

    final previewType = _classifyFile(file.name);
    if (previewType == PreviewType.none) {
      setState(() {});
      return;
    }

    // Video/audio: size limits are more generous (100 MB) since they stream
    final maxSize = previewType == PreviewType.text || previewType == PreviewType.markdown
        ? 5 * 1024 * 1024
        : previewType == PreviewType.video || previewType == PreviewType.audio
            ? 100 * 1024 * 1024
            : 20 * 1024 * 1024;
    if (file.size != null && file.size! > maxSize) {
      setState(() => _error = 'File too large to preview (${formatBytes(file.size!)})');
      return;
    }

    setState(() => _loading = true);

    // Video/audio: download to temp file and play via VideoPlayerController
    if (previewType == PreviewType.video || previewType == PreviewType.audio) {
      _fetchMediaPreview(file, previewType);
      return;
    }

    _fetchPreview(file, previewType);
  }

  Future<void> _fetchPreview(FileItem file, PreviewType type) async {
    try {
      // Local files: read from filesystem (or web FS bridge); remote: cache
      // + download. Sizes are pre-checked in _loadPreview; the caps guard
      // files whose size header was missing.
      final effectiveMax = type == PreviewType.video || type == PreviewType.audio
          ? 100 * 1024 * 1024
          : type == PreviewType.text || type == PreviewType.markdown
              ? 5 * 1024 * 1024
              : 20 * 1024 * 1024;
      final bytes =
          await loadFileBytes(ref, file, widget.side, capBytes: effectiveMax);

      if (!mounted || _loadedFile != file) return; // stale

      if (type == PreviewType.font) {
        setState(() {
          _previewBytes = bytes;
          _loading = false;
        });
      } else if (type == PreviewType.image || type == PreviewType.svg) {
        setState(() {
          _previewBytes = bytes;
          _loading = false;
        });
      } else if (type == PreviewType.pdf) {
        try {
          final doc = await PdfDocument.openData(bytes);
          _pdfController = PdfController(document: Future.value(doc));
          setState(() => _loading = false);
        } catch (e) {
          _log.warn('operation failed', e);
          setState(() {
            _error = 'PDF render failed: $e';
            _loading = false;
          });
        }
      } else if (type == PreviewType.office) {
        // Extract text from Office documents (DOCX/XLSX/PPTX/ODT).
        try {
          _textContent = await _extractOfficeText(bytes, file.name);
        } catch (e) {
          _log.warn('operation failed', e);
          _textContent = '(Could not extract text from this document)';
        }
        setState(() => _loading = false);
      } else if (type == PreviewType.csv || type == PreviewType.text || type == PreviewType.markdown) {
        // Decode as text (BOM/UTF-16 aware, UTF-8 with Latin-1 fallback).
        try {
          _textContent = InternalViewerService.decodeTextForView(bytes).text;
        } catch (e) {
          _log.warn('operation failed', e);
          _textContent = '(binary content — cannot display as text)';
        }
        setState(() => _loading = false);
      }
    } catch (e) {
      _log.warn('operation failed', e);
      if (!mounted || _loadedFile != file) return;
      setState(() {
        _error = 'Preview failed: $e';
        _loading = false;
      });
    }
  }

  Future<void> _fetchMediaPreview(FileItem file, PreviewType type) async {
    try {
      Uint8List bytes;

      if (widget.side == PanelSide.local && file.path != null) {
        // Local file: play directly from file path
        if (!kIsWeb) {
          final controller = VideoPlayerController.file(File(file.path!));
          await controller.initialize();
          if (!mounted || _loadedFile != file) {
            controller.dispose();
            return;
          }
          setState(() {
            _videoController = controller;
            _loading = false;
          });
          return;
        }
        // Web fallback: read bytes via the shared loader
        bytes = await loadFileBytes(ref, file, widget.side);
      } else {
        // Remote file: download via the shared loader (cache first)
        bytes = await loadFileBytes(ref, file, widget.side);
      }

      if (!mounted || _loadedFile != file) return;

      if (kIsWeb) {
        // Web: create blob URL for HTML5 audio/video element
        final ext = file.name.split('.').last.toLowerCase();
        final mimeType = _mimeTypeForExt(ext);
        final blob = html.Blob([bytes], mimeType);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        setState(() {
          _mediaBlobUrl = blobUrl;
          _loading = false;
        });
        return;
      }

      // Write to temp file for VideoPlayerController
      final tempDir = await getTemporaryDirectory();
      final ext = file.name.contains('.') ? '.${file.name.split('.').last}' : '';
      final tempFile = File('${tempDir.path}/crispcloud_preview$ext');
      await tempFile.writeAsBytes(bytes);

      final controller = VideoPlayerController.file(tempFile);
      await controller.initialize();

      if (!mounted || _loadedFile != file) {
        controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _loading = false;
      });
    } catch (e) {
      _log.warn('operation failed', e);
      if (!mounted || _loadedFile != file) return;
      setState(() {
        _error = 'Media preview failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final theme = Theme.of(context);

    if (file == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.preview, size: 48, color: theme.disabledColor),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.selectFileToPreview,
                style: TextStyle(color: theme.disabledColor)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with file info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(
                file.isFolder ? Icons.folder : getFileIcon(file.name),
                color: file.isFolder ? Colors.amber : theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (file.size != null)
                          Text(formatBytes(file.size!),
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        if (file.size != null && file.updatedAt != null)
                          Text(' • ', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        if (file.updatedAt != null)
                          Text(formatDateFull(file.updatedAt!),
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Preview content
        Expanded(child: _buildPreviewContent(context, file)),
      ],
    );
  }

  Widget _buildPreviewContent(BuildContext context, FileItem file) {
    final theme = Theme.of(context);

    if (file.isFolder) {
      return _buildMetadataView(context, file);
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 36, color: theme.disabledColor),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.disabledColor, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Font preview — show sample text at various sizes
    if (_previewBytes != null && _classifyFile(file.name) == PreviewType.font) {
      return FontPreview(fontBytes: _previewBytes!, filename: file.name);
    }

    // SVG preview
    if (_previewBytes != null && _classifyFile(file.name) == PreviewType.svg) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: SvgPicture.memory(
            _previewBytes!,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // Image preview
    if (_previewBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.memory(
            _previewBytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, e, __) => _buildMetadataView(context, file),
          ),
        ),
      );
    }

    // PDF preview with page controls
    if (_pdfController != null) {
      return Column(
        children: [
          Expanded(
            child: PdfView(
              controller: _pdfController!,
              scrollDirection: Axis.vertical,
              pageSnapping: false,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page, size: 20),
                  tooltip: AppLocalizations.of(context)!.firstPage,
                  onPressed: () => _pdfController!.jumpToPage(1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  tooltip: AppLocalizations.of(context)!.previousPage,
                  onPressed: () {
                    final current = _pdfController!.page;
                    if (current > 1) _pdfController!.jumpToPage(current - 1);
                  },
                ),
                PdfPageNumber(
                  controller: _pdfController!,
                  builder: (_, __, page, total) => Text(
                    '$page / $total',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  tooltip: AppLocalizations.of(context)!.nextPage,
                  onPressed: () {
                    final current = _pdfController!.page;
                    _pdfController!.jumpToPage(current + 1);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.last_page, size: 20),
                  tooltip: AppLocalizations.of(context)!.lastPage,
                  onPressed: () => _pdfController!.jumpToPage(_pdfController!.pagesCount ?? 1),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Web media preview via blob URL
    if (_mediaBlobUrl != null) {
      final isAudio = _classifyFile(file.name) == PreviewType.audio;
      return WebMediaPlayer(blobUrl: _mediaBlobUrl!, isAudio: isAudio);
    }

    // Video/Audio preview (native)
    if (_videoController != null) {
      return MediaPlayer(
        controller: _videoController!,
        isAudio: _classifyFile(file.name) == PreviewType.audio,
      );
    }

    // CSV/TSV table preview
    if (_textContent != null && _classifyFile(file.name) == PreviewType.csv) {
      return CsvTableView(content: _textContent!, filename: file.name);
    }

    // Markdown preview
    if (_textContent != null && _classifyFile(file.name) == PreviewType.markdown) {
      return Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Markdown(
          data: _textContent!,
          selectable: true,
          padding: const EdgeInsets.all(12),
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            codeblockDecoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }

    // Text/code preview with syntax highlighting
    if (_textContent != null) {
      final lang = _highlightLang(file.name);
      final isDark = theme.brightness == Brightness.dark;
      if (lang != null) {
        return Container(
          color: theme.colorScheme.surfaceContainerLowest,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: HighlightView(
              _textContent!,
              language: lang,
              theme: isDark ? monokaiSublimeTheme : githubTheme,
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
              padding: const EdgeInsets.all(8),
            ),
          ),
        );
      }
      return Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _textContent!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // Fallback: metadata only
    return _buildMetadataView(context, file);
  }

  Widget _buildMetadataView(BuildContext context, FileItem file) {
    final theme = Theme.of(context);
    final ext = file.name.contains('.') ? file.name.split('.').last.toUpperCase() : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(
            file.isFolder ? Icons.folder : getFileIcon(file.name),
            size: 64,
            color: file.isFolder ? Colors.amber : theme.disabledColor,
          ),
          const SizedBox(height: 16),
          if (!file.isFolder && ext.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(ext, style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              )),
            ),
            const SizedBox(height: 12),
          ],
          if (file.size != null)
            _infoRow(context, 'Size', formatBytes(file.size!)),
          if (file.updatedAt != null)
            _infoRow(context, 'Modified', formatDateFull(file.updatedAt!)),
          if (file.path != null)
            _infoRow(context, 'Path', file.path!),
          if (file.uuid != null && file.uuid != file.path)
            _infoRow(context, 'UUID', file.uuid!),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
