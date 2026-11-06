// lib/widgets/preview_pane.dart
//
// Toggleable preview pane that shows file details and content previews.
// Supports: images (inline), text/code (read-only), markdown (rendered),
// PDF (scrollable), video/audio (streaming player), and metadata for other types.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_operation_backend.dart';
import '../services/local_file_service.dart';
import '../services/viewer_spool.dart';
import '../l10n/pdf_editor_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../services/file_bytes_loader.dart';
import '../services/internal_viewer_service.dart';
import '../utils/formatters.dart';
import 'file_list_view.dart' show getFileIcon;
import 'preview_media.dart';
import 'pdf_editor_dialog.dart';
import 'code_highlighting.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';

import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';

import '../services/log_service.dart';
import '../l10n/preview_media_strings.dart';

/// File types we can preview inline.
enum PreviewType {
  image,
  svg,
  text,
  markdown,
  csv,
  pdf,
  video,
  audio,
  office,
  font,
  none,
}

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
Future<String> _extractOfficeText(
  Uint8List bytes,
  String filename,
  PreviewMediaStrings strings,
) => extractOfficeText(bytes, filename, strings: strings);
String _mimeTypeForExt(String ext) => mimeTypeForExt(ext);

class PreviewPane extends ConsumerStatefulWidget {
  final FileItem? file;
  final PanelSide side;

  const PreviewPane({super.key, required this.file, required this.side});

  @override
  ConsumerState<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends ConsumerState<PreviewPane> {
  static const _log = Log('PreviewPane');
  Uint8List? _previewBytes;
  String? _textContent;
  PdfController? _pdfController;
  PdfDocument? _pdfDocument;
  ViewerSpool? _spool;
  LocalFileService? _mediaLocal;
  int _loadToken = 0;
  VideoPlayerController? _videoController;
  String? _mediaBlobUrl; // Web: blob URL for HTML5 audio/video
  bool _loading = false;
  String Function(BuildContext)? _error;
  FileItem? _loadedFile; // track which file we loaded

  @override
  void didUpdateWidget(PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload preview when file changes
    if (!identical(widget.file, _loadedFile) || widget.side != oldWidget.side) {
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
    ++_loadToken;
    _releaseResources();
    super.dispose();
  }

  void _releaseResources() {
    final pdf = _pdfController;
    final document = _pdfDocument;
    final video = _videoController;
    final spool = _spool;
    final local = _mediaLocal;
    final blob = _mediaBlobUrl;
    _pdfController = null;
    _pdfDocument = null;
    _videoController = null;
    _spool = null;
    _mediaLocal = null;
    _mediaBlobUrl = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      pdf?.dispose();
      try {
        await document?.close();
      } catch (_) {}
      try {
        await video?.dispose();
      } catch (_) {}
      try {
        await local?.endStreamAccess();
      } catch (_) {}
      try {
        await spool?.close();
      } catch (_) {}
      if (blob != null && kIsWeb) html.Url.revokeObjectUrl(blob);
    });
  }

  bool _sameRequest(FileItem file, int token) =>
      mounted && token == _loadToken && identical(file, _loadedFile);

  void _loadPreview() {
    final file = widget.file;
    final token = ++_loadToken;
    _releaseResources();
    _previewBytes = null;
    _textContent = null;
    _error = null;
    _loading = false;
    _loadedFile = file;
    if (file == null || file.isFolder) {
      setState(() {});
      return;
    }
    final type = _classifyFile(file.name);
    if (type == PreviewType.none) {
      setState(() {});
      return;
    }
    final origin = ref
        .read(panelProvider(widget.side))
        .originForOperation(file);
    if (origin == null || !origin.isCurrent) {
      setState(
        () =>
            _error = (context) =>
                PreviewMediaStrings(context).text('sourceUnavailable'),
      );
      return;
    }
    final media = type == PreviewType.video || type == PreviewType.audio;
    final maxSize = type == PreviewType.text || type == PreviewType.markdown
        ? 5 * 1024 * 1024
        : media
        ? 100 * 1024 * 1024
        : 20 * 1024 * 1024;
    if ((!media || kIsWeb || !origin.source.isLocal) &&
        file.size != null &&
        file.size! > maxSize) {
      setState(
        () => _error = (context) {
          final strings = PreviewMediaStrings(context);
          return '${strings.text('fileTooLarge', {'size': formatBytes(file.size!)})}. ${strings.text('openViewer')}';
        },
      );
      return;
    }
    setState(() => _loading = true);
    if (media) {
      unawaited(_fetchMediaPreview(file, origin, token));
    } else {
      unawaited(_fetchPreview(file, type, origin, token));
    }
  }

  Future<void> _fetchPreview(
    FileItem file,
    PreviewType type,
    PanelFileOrigin origin,
    int token,
  ) async {
    try {
      final limit = type == PreviewType.text || type == PreviewType.markdown
          ? 5 * 1024 * 1024
          : 20 * 1024 * 1024;
      final bytes = await loadFileBytes(
        ref,
        file,
        widget.side,
        capBytes: limit,
        origin: origin,
      );
      if (!_sameRequest(file, token)) return;
      if (!origin.isCurrent) {
        throw const FileBytesLoadException(
          'The original preview source is unavailable.',
        );
      }
      if (type == PreviewType.pdf) {
        final document = await PdfDocument.openData(bytes);
        if (!_sameRequest(file, token) || !origin.isCurrent) {
          await document.close();
          if (!origin.isCurrent) {
            throw const FileBytesLoadException(
              'The original preview source is unavailable.',
            );
          }
          return;
        }
        _pdfDocument = document;
        _pdfController = PdfController(document: Future.value(document));
      } else if (type == PreviewType.office) {
        final text = await _extractOfficeText(
          bytes,
          file.name,
          PreviewMediaStrings(context),
        );
        if (!_sameRequest(file, token)) return;
        if (!origin.isCurrent) {
          throw const FileBytesLoadException(
            'The original preview source is unavailable.',
          );
        }
        _textContent = text;
      } else if (type == PreviewType.csv ||
          type == PreviewType.text ||
          type == PreviewType.markdown) {
        _textContent = InternalViewerService.decodeTextForView(bytes).text;
      } else {
        _previewBytes = bytes;
      }
      setState(() => _loading = false);
    } catch (error) {
      _log.warn('preview failed', error);
      if (!_sameRequest(file, token)) return;
      setState(() {
        _error = (context) => PreviewMediaStrings(context).text(
          'previewFailed',
          {'error': localizedProviderError(context, error)},
        );
        _loading = false;
      });
    }
  }

  Future<void> _fetchMediaPreview(
    FileItem file,
    PanelFileOrigin origin,
    int token,
  ) async {
    ViewerSpool? spool;
    LocalFileService? local;
    VideoPlayerController? controller;
    var retained = false;
    try {
      if (kIsWeb) {
        final bytes = await loadFileBytes(
          ref,
          file,
          widget.side,
          capBytes: 100 * 1024 * 1024,
          origin: origin,
        );
        if (!_sameRequest(file, token)) return;
        if (!origin.isCurrent) {
          throw const FileBytesLoadException(
            'The original preview source is unavailable.',
          );
        }
        final blob = html.Blob([bytes], _mimeTypeForExt(file.extension));
        setState(() {
          _mediaBlobUrl = html.Url.createObjectUrlFromBlob(blob);
          _loading = false;
        });
        return;
      }
      late String path;
      if (origin.source.isLocal && file.path != null) {
        final localService = ref.read(localFileServiceProvider);
        if (!origin.isCurrent ||
            !await localService.beginStreamAccess(file.path!)) {
          throw const FileBytesLoadException(
            'Access to the original media file was not granted.',
          );
        }
        local = localService;
        path = file.path!;
      } else {
        final backend = fileOperationBackend(
          source: origin.source,
          local: ref.read(localFileServiceProvider),
          isCurrent: () => mounted && origin.isCurrent,
        );
        spool = await createViewerSpool(
          backend,
          file,
          maxBytes: 100 * 1024 * 1024,
          isCancelled: () => !_sameRequest(file, token),
        );
        path = spool.path;
      }
      if (!_sameRequest(file, token)) return;
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!_sameRequest(file, token)) return;
      if (!origin.isCurrent) {
        throw const FileBytesLoadException(
          'The original preview source is unavailable.',
        );
      }
      setState(() {
        _videoController = controller;
        _spool = spool;
        _mediaLocal = local;
        _loading = false;
      });
      retained = true;
    } catch (error) {
      _log.warn('media preview failed', error);
      if (!_sameRequest(file, token)) return;
      setState(() {
        _error = (context) => PreviewMediaStrings(context).text('mediaFailed', {
          'error': localizedProviderError(context, error),
        });
        _loading = false;
      });
    } finally {
      if (!retained) {
        try {
          await controller?.dispose();
        } catch (_) {}
        try {
          await local?.endStreamAccess();
        } catch (_) {}
        try {
          await spool?.close();
        } catch (_) {}
      }
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
            Text(
              AppLocalizations.of(context)!.selectFileToPreview,
              style: TextStyle(color: theme.disabledColor),
            ),
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
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (file.size != null)
                          Text(
                            formatBytes(file.size!),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (file.size != null && file.updatedAt != null)
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (file.updatedAt != null)
                          Text(
                            formatDateFull(file.updatedAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!file.isFolder && isPdfFileName(file.name))
                IconButton(
                  tooltip: context.pdfTr('Edit PDF'),
                  icon: const Icon(Icons.edit_document),
                  onPressed: () async {
                    await showPdfEditorDialog(context, ref, file, widget.side);
                    if (mounted && widget.file == file) _loadPreview();
                  },
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
              Text(
                _error!(context),
                style: TextStyle(color: theme.disabledColor, fontSize: 12),
                textAlign: TextAlign.center,
              ),
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
          child: SvgPicture.memory(_previewBytes!, fit: BoxFit.contain),
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
                  tooltip: PreviewMediaStrings(context).text('firstPage'),
                  onPressed: () => _pdfController!.jumpToPage(1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  tooltip: PreviewMediaStrings(context).text('previousPage'),
                  onPressed: () {
                    final current = _pdfController!.page;
                    if (current > 1) _pdfController!.jumpToPage(current - 1);
                  },
                ),
                PdfPageNumber(
                  controller: _pdfController!,
                  builder: (_, __, page, total) => Text(
                    '$page / $total',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  tooltip: PreviewMediaStrings(context).text('nextPage'),
                  onPressed: () {
                    final current = _pdfController!.page;
                    _pdfController!.jumpToPage(current + 1);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.last_page, size: 20),
                  tooltip: AppLocalizations.of(context)!.lastPage,
                  onPressed: () => _pdfController!.jumpToPage(
                    _pdfController!.pagesCount ?? 1,
                  ),
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
    if (_textContent != null &&
        _classifyFile(file.name) == PreviewType.markdown) {
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
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
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
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toUpperCase()
        : '';

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
              child: Text(
                ext,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (file.size != null)
            _infoRow(
              context,
              PreviewMediaStrings(context).text('size'),
              formatBytes(file.size!),
            ),
          if (file.updatedAt != null)
            _infoRow(context, 'Modified', formatDateFull(file.updatedAt!)),
          if (file.path != null) _infoRow(context, 'Path', file.path!),
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
