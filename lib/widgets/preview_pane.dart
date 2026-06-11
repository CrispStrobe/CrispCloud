// lib/widgets/preview_pane.dart
//
// Toggleable preview pane that shows file details and content previews.
// Supports: images (inline), text/code (read-only), markdown (rendered),
// PDF (scrollable), video/audio (streaming player), and metadata for other types.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show FontLoader;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'file_list_view.dart' show getFileIcon;

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';
import 'package:archive/archive.dart' show ZipDecoder;
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
    case 'txt':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'csv':
    case 'tsv':
      return PreviewType.csv;
    case 'log':
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
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'dart' => 'dart',
    'js' || 'jsx' => 'javascript',
    'ts' || 'tsx' => 'typescript',
    'py' => 'python',
    'rb' => 'ruby',
    'go' => 'go',
    'rs' => 'rust',
    'java' => 'java',
    'kt' => 'kotlin',
    'swift' => 'swift',
    'c' || 'h' => 'c',
    'cpp' || 'hpp' || 'cc' => 'cpp',
    'cs' => 'csharp',
    'php' => 'php',
    'html' || 'htm' => 'xml',
    'css' => 'css',
    'scss' => 'scss',
    'less' => 'less',
    'sql' => 'sql',
    'sh' || 'bash' || 'zsh' => 'bash',
    'ps1' => 'powershell',
    'r' => 'r',
    'lua' => 'lua',
    'yaml' || 'yml' => 'yaml',
    'json' => 'json',
    'xml' => 'xml',
    'toml' => 'ini',
    'makefile' => 'makefile',
    'dockerfile' => 'dockerfile',
    _ => null,
  };
}

/// Extract readable text from Office documents (DOCX, XLSX, PPTX, ODT).
/// These are ZIP files containing XML; we parse the XML for text content.
String _extractOfficeText(Uint8List bytes, String filename) {
  final ext = filename.split('.').last.toLowerCase();
  final archive = ZipDecoder().decodeBytes(bytes);

  // Determine which XML file contains the text.
  final xmlPaths = switch (ext) {
    'docx' => ['word/document.xml'],
    'xlsx' => archive.files
        .where((f) => f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml'))
        .map((f) => f.name)
        .toList(),
    'pptx' => archive.files
        .where((f) => f.name.startsWith('ppt/slides/') && f.name.endsWith('.xml'))
        .map((f) => f.name)
        .toList(),
    'odt' || 'ods' || 'odp' => ['content.xml'],
    'epub' => archive.files
        .where((f) => f.name.endsWith('.xhtml') || f.name.endsWith('.html') || f.name.endsWith('.htm'))
        .map((f) => f.name)
        .toList(),
    _ => <String>[],
  };

  final buffer = StringBuffer();
  for (final xmlPath in xmlPaths) {
    final entry = archive.files.where((f) => f.name == xmlPath).firstOrNull;
    if (entry == null || !entry.isFile) continue;
    final xmlContent = String.fromCharCodes(entry.content as List<int>);
    // Strip XML tags and extract text content.
    final text = xmlContent
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln('\n---\n');
      buffer.writeln(text);
    }
  }

  return buffer.isEmpty ? '(No text content found)' : buffer.toString();
}

String _mimeTypeForExt(String ext) {
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'ogg' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'wma' => 'audio/x-ms-wma',
    'opus' => 'audio/opus',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    'mkv' => 'video/x-matroska',
    _ => 'application/octet-stream',
  };
}

class PreviewPane extends ConsumerStatefulWidget {
  static const _log = Log('PreviewPane');

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
      Uint8List bytes;

      if (widget.side == PanelSide.local && file.path != null) {
        // Local files: read directly from filesystem (or via LocalFileService on web)
        if (kIsWeb) {
          final localSvc = ref.read(localFileServiceProvider);
          bytes = await localSvc.readFile(file.path!, fileItem: file);
        } else {
          final localFile = File(file.path!);
          if (!await localFile.exists()) {
            throw Exception('File not found: ${file.path}');
          }
          bytes = await localFile.readAsBytes();
        }
      } else if (widget.side == PanelSide.remote) {
        final client = ref.read(authProvider).client;
        // Remote files: check cache first, then download
        final remotePath = file.path ?? '/${file.name}';
        final providerName = ref.read(authProvider).providerName;
        final cache = ref.read(fileCacheProvider);

        final cached = await cache.get(remotePath, providerName);
        if (cached != null) {
          bytes = Uint8List.fromList(cached);
        } else {
          bytes = await client.downloadFileBytes(remotePath);
          // Cache for offline access (fire-and-forget)
          cache.put(remotePath, providerName, bytes);
        }
      } else {
        throw Exception('Cannot determine file source');
      }

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
          setState(() {
            _error = 'PDF render failed: $e';
            _loading = false;
          });
        }
      } else if (type == PreviewType.office) {
        // Extract text from Office documents (DOCX/XLSX/PPTX/ODT).
        try {
          _textContent = _extractOfficeText(bytes, file.name);
        } catch (_) {
          _textContent = '(Could not extract text from this document)';
        }
        setState(() => _loading = false);
      } else if (type == PreviewType.csv || type == PreviewType.text || type == PreviewType.markdown) {
        // Decode as text (UTF-8 with fallback)
        try {
          _textContent = String.fromCharCodes(bytes);
        } catch (_) {
          _textContent = '(binary content — cannot display as text)';
        }
        setState(() => _loading = false);
      }
    } catch (e) {
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
        // Web fallback: read bytes via LocalFileService
        final localSvc = ref.read(localFileServiceProvider);
        bytes = await localSvc.readFile(file.path!, fileItem: file);
      } else {
        // Remote file: download to temp, then play
        final client = ref.read(authProvider).client;
        final remotePath = file.path ?? '/${file.name}';
        final providerName = ref.read(authProvider).providerName;
        final cache = ref.read(fileCacheProvider);

        final cached = await cache.get(remotePath, providerName);
        if (cached != null) {
          bytes = Uint8List.fromList(cached);
        } else {
          bytes = await client.downloadFileBytes(remotePath);
          cache.put(remotePath, providerName, bytes);
        }
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
      return _FontPreview(fontBytes: _previewBytes!, filename: file.name);
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
                  builder: (_, page, total, __) => Text(
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
      return _WebMediaPlayer(blobUrl: _mediaBlobUrl!, isAudio: isAudio);
    }

    // Video/Audio preview (native)
    if (_videoController != null) {
      return _MediaPlayer(
        controller: _videoController!,
        isAudio: _classifyFile(file.name) == PreviewType.audio,
      );
    }

    // CSV/TSV table preview
    if (_textContent != null && _classifyFile(file.name) == PreviewType.csv) {
      return _CsvTableView(content: _textContent!, filename: file.name);
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

/// Inline media player for video and audio files.
class _MediaPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isAudio;

  const _MediaPlayer({
    required this.controller,
    this.isAudio = false,
  });

  @override
  State<_MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<_MediaPlayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final isPlaying = controller.value.isPlaying;
    final position = controller.value.position;
    final duration = controller.value.duration;

    return Column(
      children: [
        // Video display or audio icon
        Expanded(
          child: widget.isAudio
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note, size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        isPlaying ? 'Playing' : 'Paused',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: controller.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        )
                      : const CircularProgressIndicator(),
                ),
        ),
        // Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.surfaceContainerHigh,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: duration.inMilliseconds > 0
                      ? position.inMilliseconds / duration.inMilliseconds
                      : 0.0,
                  onChanged: (v) {
                    controller.seekTo(Duration(
                      milliseconds: (v * duration.inMilliseconds).round(),
                    ));
                  },
                ),
              ),
              // Play/pause + time
              Row(
                children: [
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
                    onPressed: () {
                      if (isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // Volume toggle
                  IconButton(
                    icon: Icon(
                      controller.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
                      size: 18,
                    ),
                    onPressed: () {
                      controller.setVolume(controller.value.volume > 0 ? 0.0 : 1.0);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Web-only media player — opens blob URL in browser tab for playback.
/// Font preview — loads font from bytes and displays sample text.
class _FontPreview extends StatefulWidget {
  final Uint8List fontBytes;
  final String filename;

  const _FontPreview({required this.fontBytes, required this.filename});

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  String? _fontFamily;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  Future<void> _loadFont() async {
    final family = 'preview_${widget.filename.hashCode}';
    try {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(widget.fontBytes)));
      await loader.load();
      if (mounted) setState(() { _fontFamily = family; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final style = _fontFamily != null
        ? TextStyle(fontFamily: _fontFamily)
        : const TextStyle();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.filename, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 16),
          for (final size in [12.0, 16.0, 24.0, 32.0, 48.0, 72.0]) ...[
            Text('${size.toInt()}px', style: TextStyle(
              fontSize: 10, color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 4),
            Text(
              'The quick brown fox jumps over the lazy dog',
              style: style.copyWith(fontSize: size),
            ),
            const SizedBox(height: 8),
            Text(
              'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
              style: style.copyWith(fontSize: size * 0.6),
            ),
            const SizedBox(height: 4),
            Text(
              'abcdefghijklmnopqrstuvwxyz 0123456789',
              style: style.copyWith(fontSize: size * 0.6),
            ),
            const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

/// CSV/TSV table preview widget.
class _CsvTableView extends StatelessWidget {
  final String content;
  final String filename;

  const _CsvTableView({required this.content, required this.filename});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTsv = filename.toLowerCase().endsWith('.tsv');
    final separator = isTsv ? '\t' : ',';

    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.emptyFile));
    }

    // Parse rows — simple split (doesn't handle quoted commas, but works for most CSVs).
    final rows = lines.map((line) => line.split(separator)).toList();
    final headerRow = rows.first;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    final colCount = headerRow.length;

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 40,
            columnSpacing: 16,
            horizontalMargin: 12,
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
            dataTextStyle: const TextStyle(fontSize: 11),
            columns: List.generate(
              colCount,
              (i) => DataColumn(label: Text(headerRow[i].trim())),
            ),
            rows: dataRows.take(500).map((row) {
              return DataRow(
                cells: List.generate(
                  colCount,
                  (i) => DataCell(Text(
                    i < row.length ? row[i].trim() : '',
                    overflow: TextOverflow.ellipsis,
                  )),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Web-only media player — opens blob URL in browser tab for playback.
class _WebMediaPlayer extends StatelessWidget {
  final String blobUrl;
  final bool isAudio;

  const _WebMediaPlayer({required this.blobUrl, this.isAudio = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAudio ? Icons.music_note : Icons.videocam,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(isAudio ? AppLocalizations.of(context)!.playAudio : AppLocalizations.of(context)!.playVideo),
            onPressed: () {
              html.window.open(blobUrl, '_blank');
            },
          ),
        ],
      ),
    );
  }
}
