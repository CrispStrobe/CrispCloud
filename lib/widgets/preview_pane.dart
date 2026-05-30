// lib/widgets/preview_pane.dart
//
// Toggleable preview pane that shows file details and content previews.
// Supports: images (inline), text/code (read-only), and metadata for other types.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'file_list_view.dart' show getFileIcon;

import 'package:flutter_markdown/flutter_markdown.dart';

/// File types we can preview inline.
enum PreviewType { image, text, markdown, pdf, none }

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
    case 'md':
    case 'markdown':
      return PreviewType.markdown;
    case 'pdf':
      return PreviewType.pdf;
    case 'txt':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'csv':
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
    default:
      return PreviewType.none;
  }
}

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
  Uint8List? _previewBytes;
  String? _textContent;
  PdfController? _pdfController;
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
    super.dispose();
  }

  void _loadPreview() {
    final file = widget.file;
    _previewBytes = null;
    _textContent = null;
    _pdfController?.dispose();
    _pdfController = null;
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

    // Only preview small files (< 5 MB for text, < 20 MB for images/PDF)
    final maxSize = previewType == PreviewType.text || previewType == PreviewType.markdown
        ? 5 * 1024 * 1024
        : 20 * 1024 * 1024;
    if (file.size != null && file.size! > maxSize) {
      setState(() => _error = 'File too large to preview (${formatBytes(file.size!)})');
      return;
    }

    setState(() => _loading = true);

    _fetchPreview(file, previewType);
  }

  Future<void> _fetchPreview(FileItem file, PreviewType type) async {
    try {
      Uint8List bytes;
      final client = ref.read(authProvider).client;

      if (widget.side == PanelSide.local && file.path != null) {
        // Local files: read directly
        bytes = await client.downloadFileBytes(file.path!).catchError((_) async {
          // Fallback: try via local file service (not via cloud client)
          throw Exception('Local preview requires file path access');
        });
      } else if (widget.side == PanelSide.remote) {
        // Remote files: download bytes
        final remotePath = file.path ?? '/${file.name}';
        bytes = await client.downloadFileBytes(remotePath);
      } else {
        throw Exception('Cannot determine file source');
      }

      if (!mounted || _loadedFile != file) return; // stale

      if (type == PreviewType.image) {
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
      } else if (type == PreviewType.text || type == PreviewType.markdown) {
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
            Text('Select a file to preview',
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

    // PDF preview
    if (_pdfController != null) {
      return PdfView(
        controller: _pdfController!,
        scrollDirection: Axis.vertical,
        pageSnapping: false,
      );
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

    // Text preview
    if (_textContent != null) {
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
