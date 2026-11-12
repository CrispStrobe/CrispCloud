// lib/widgets/preview_media.dart
//
// Shared preview widgets used by both the side PreviewPane and the F3
// internal viewer dialog: media player, web media player, font sample,
// CSV/TSV table, and Office document text extraction.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:quds_office_engine/quds_office_engine.dart'
    show OfficePackageParts, extractLegacyWordText;
import 'package:universal_html/html.dart' as html;
import 'package:video_player/video_player.dart';

import '../l10n/preview_media_strings.dart';
import '../services/archive_viewer_service.dart';

/// RFC 4180-style delimited parser: supports quoted cells, embedded commas,
/// quotes and newlines. Used for CSV/TSV previews and spreadsheets.
List<List<String>> _parseDelimited(String content, String separator) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < content.length; i++) {
    final ch = content[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < content.length && content[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == separator) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// MIME type for audio/video extensions (HTML5 playback on web).
String mimeTypeForExt(String ext) {
  return switch (ext.toLowerCase()) {
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'ogg' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'wma' => 'audio/x-ms-wma',
    'opus' => 'audio/opus',
    'aiff' || 'aif' => 'audio/aiff',
    'mid' || 'midi' => 'audio/midi',
    'amr' => 'audio/amr',
    'au' => 'audio/basic',
    'gsm' => 'audio/gsm',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    'mkv' => 'video/x-matroska',
    'wmv' => 'video/x-ms-wmv',
    'flv' => 'video/x-flv',
    '3gp' => 'video/3gpp',
    'mpg' || 'mpeg' => 'video/mpeg',
    _ => 'application/octet-stream',
  };
}

/// Extract readable text from Office documents (DOCX, XLSX, PPTX, ODT, EPUB).
/// These are ZIP files containing XML; we parse the XML for text content.
/// Maximum bytes read from one XML part of an Office/EPUB document.
const int _kOfficeXmlCap = 8 * 1024 * 1024;

/// Extract readable text from Office documents (DOCX, XLSX, PPTX, ODT, EPUB).
///
/// Uses the viewer's hardened archive layer: metadata-only open, per-entry
/// size caps while decompressing (zip-bomb safe), typed rejections.
Future<String> extractOfficeText(
  Uint8List bytes,
  String filename, {
  PreviewMediaStrings? strings,
}) async {
  final ext = filename.split('.').last.toLowerCase();
  final buffer = StringBuffer();
  ViewerArchive? archive;
  try {
    if (ext == 'doc' || ext == 'dot') {
      final text = extractLegacyWordText(bytes);
      return text.isEmpty
          ? (strings?.text('noText') ?? '(No text content found)')
          : text;
    }
    archive = await openViewerArchive(bytes, name: filename);
    final openedArchive = archive;
    final files = archive.members.where((m) => m.isFile).toList();
    Future<String?> readPart(String name) async {
      final member = files.where((file) => file.name == name).firstOrNull;
      if (member == null || member.size > _kOfficeXmlCap) return null;
      try {
        final data = await openedArchive.readMember(
          member,
          maxBytes: _kOfficeXmlCap,
        );
        return utf8.decode(data, allowMalformed: true);
      } on ArchiveViewException {
        return null;
      }
    }

    final xmlPaths = switch (ext) {
      // Follow the package's main-part relationship; documents may place
      // their body outside word/document.xml.
      'docx' || 'docm' || 'dotx' || 'dotm' => <String>[
        await OfficePackageParts(readPart).mainPart('word/document.xml'),
      ],
      'xlsx' || 'xlsm' || 'xltx' =>
        files
            .map((f) => f.name)
            .where((n) => n.startsWith('xl/worksheets/') && n.endsWith('.xml'))
            .toList(),
      'pptx' || 'pptm' || 'potx' =>
        files
            .map((f) => f.name)
            .where((n) => n.startsWith('ppt/slides/') && n.endsWith('.xml'))
            .toList(),
      'odt' || 'ods' || 'odp' => <String>['content.xml'],
      'epub' =>
        files
            .map((f) => f.name)
            .where(
              (n) =>
                  n.endsWith('.xhtml') ||
                  n.endsWith('.html') ||
                  n.endsWith('.htm'),
            )
            .toList(),
      _ => <String>[],
    };

    for (final xmlPath in xmlPaths) {
      final xmlContent = await readPart(xmlPath);
      if (xmlContent == null) continue;
      // Strip XML tags and extract text content.
      final text = xmlContent
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln('\n---\n');
        buffer.writeln(text);
        if (buffer.length > 4 * 1024 * 1024) break;
      }
    }
  } on FormatException {
    return (strings?.text('extractFailed') ??
        '(Could not extract text from this document)');
  } on ArchiveViewException {
    return (strings?.text('extractFailed') ??
        '(Could not extract text from this document)');
  } on ArchivePasswordRequiredException {
    return (strings?.text('encrypted') ?? '(This document is encrypted)');
  } finally {
    await archive?.close();
  }

  return buffer.isEmpty
      ? (strings?.text('noText') ?? '(No text content found)')
      : buffer.toString();
}

/// Inline media player for video and audio files.
class MediaPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isAudio;

  const MediaPlayer({
    super.key,
    required this.controller,
    this.isAudio = false,
  });

  @override
  State<MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<MediaPlayer> {
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
                      Icon(
                        Icons.music_note,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        PreviewMediaStrings(context)
                            .text(isPlaying ? 'playing' : 'paused'),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.surfaceContainerHigh,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: duration.inMilliseconds > 0
                      ? position.inMilliseconds / duration.inMilliseconds
                      : 0.0,
                  onChanged: (v) {
                    controller.seekTo(
                      Duration(
                        milliseconds: (v * duration.inMilliseconds).round(),
                      ),
                    );
                  },
                ),
              ),
              // Play/pause + time
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 20,
                    ),
                    tooltip: PreviewMediaStrings(context)
                        .text(isPlaying ? 'pause' : 'play'),
                    onPressed: () {
                      if (isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // Volume toggle
                  IconButton(
                    icon: Icon(
                      controller.value.volume > 0
                          ? Icons.volume_up
                          : Icons.volume_off,
                      size: 18,
                    ),
                    tooltip: PreviewMediaStrings(context)
                        .text(controller.value.volume > 0 ? 'mute' : 'unmute'),
                    onPressed: () {
                      controller.setVolume(
                        controller.value.volume > 0 ? 0.0 : 1.0,
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
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
class WebMediaPlayer extends StatelessWidget {
  final String blobUrl;
  final bool isAudio;

  const WebMediaPlayer({
    super.key,
    required this.blobUrl,
    this.isAudio = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isAudio ? Icons.music_note : Icons.videocam, size: 64),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(
              isAudio
                  ? PreviewMediaStrings(context).text('playAudio')
                  : PreviewMediaStrings(context).text('playVideo'),
            ),
            onPressed: () {
              html.window.open(blobUrl, '_blank');
            },
          ),
        ],
      ),
    );
  }
}

/// Font preview — loads font from bytes and displays sample text.
class FontPreview extends StatefulWidget {
  final Uint8List fontBytes;
  final String filename;

  const FontPreview({
    super.key,
    required this.fontBytes,
    required this.filename,
  });

  @override
  State<FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<FontPreview> {
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
      if (mounted) {
        setState(() {
          _fontFamily = family;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[FontPreview] Font load failed: $e');
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
          Text(
            widget.filename,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          for (final size in [12.0, 16.0, 24.0, 32.0, 48.0, 72.0]) ...[
            Text(
              '${size.toInt()}px',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              PreviewMediaStrings(context).text('sample'),
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
class CsvTableView extends StatelessWidget {
  final String content;
  final String filename;

  const CsvTableView({
    super.key,
    required this.content,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTsv = filename.toLowerCase().endsWith('.tsv');
    final separator = isTsv ? '\t' : ',';

    final rows = _parseDelimited(
      content,
      separator,
    ).where((row) => row.any((cell) => cell.trim().isNotEmpty)).toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(PreviewMediaStrings(context).text('emptyFile')),
      );
    }

    final headerRow = rows.first;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    // Bound the table: huge rows/columns can otherwise exhaust memory.
    final colCount = headerRow.length > 64 ? 64 : headerRow.length;

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
                  (i) => DataCell(
                    Text(
                      i < row.length ? row[i].trim() : '',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
