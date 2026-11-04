// lib/widgets/internal_viewer_dialog.dart
//
// Double-Commander-style full-screen internal viewer (F3).
//
// Supported modes:
//   text     — UTF-8/UTF-16/Latin-1 decoding with syntax highlighting
//   ascii    — "safe ASCII": control bytes as '·', Latin-1 high bytes readable
//   binary   — strict printable-only byte view (everything else '.')
//   hex      — classic offset + hex + ASCII dump (any file, streamed on disk)
//   image    — raster (Image) and SVG (flutter_svg), pinch/zoom
//   markdown — rendered Markdown
//   pdf      — pdfx page view
//   media    — audio/video player
//   font     — font specimen
//   csv      — parsed table (CSV/TSV)
//   office   — DOCX/XLSX/PPTX/ODT/ODS/ODP/EPUB text extraction
//   archive  — ZIP/TAR/TGZ/TBZ2 member listing (members open in a nested viewer)
//
// Hex, ASCII, Binary and Text always work, even for files too large to load
// fully, thanks to ViewBytesSource streaming on native platforms.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:universal_html/html.dart' as html;
import 'package:video_player/video_player.dart';

import '../l10n/internal_viewer_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_viewer_service.dart';
import '../services/file_bytes_loader.dart';
import '../services/internal_viewer_service.dart';
import '../services/log_service.dart';
import '../services/office_document_service.dart';
import '../services/office_pdf_service.dart';
import '../services/pdf_text_service.dart';
import '../services/system_preview_service.dart';
import '../utils/formatters.dart';
import 'code_highlighting.dart';
import 'hex_viewer.dart';
import 'internal_viewer_views.dart';
import 'pptx_slide_viewer.dart';
import 'preview_media.dart';
import 'xml_tree_view.dart';

const _log = Log('InternalViewer');

/// Files up to this size are loaded fully into memory on open; larger local
/// files are streamed from disk.
const int kAutoFullLoadBytes = 16 * 1024 * 1024;

/// Upper bound for modes that need the complete byte array (image/media/pdf/…).
const int kViewerFullDataCap = 64 * 1024 * 1024;

const int _kSearchMaxMatches = 2000;
const int _kStreamSearchCap = 64 * 1024 * 1024;
const int _kHighlightMaxChars = 400 * 1024;

/// Rich rendered modes (markdown/CSV/office) are truncated above this size so
/// a single huge document cannot freeze the UI thread.
const int _kRichRenderCap = 4 * 1024 * 1024;

/// Fonts above this size are refused (engine font parsing is costly).
const int _kFontPreviewCap = 32 * 1024 * 1024;

const InternalViewerService _viewerService = InternalViewerService();

/// Open the internal viewer for [file] as a full-screen dialog.
Future<void> showInternalViewer(
  BuildContext context, {
  required FileItem file,
  required PanelSide side,
  Uint8List? bytesOverride,
  String? displayName,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: InternalViewerDialog(
        file: file,
        side: side,
        bytesOverride: bytesOverride,
        displayName: displayName,
      ),
    ),
  );
}

class InternalViewerDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;

  /// When set, these bytes are viewed instead of reading [file]
  /// (used by tests and by archive-member viewing).
  final Uint8List? bytesOverride;

  /// Title/extension to use instead of [file]'s name (archive members).
  final String? displayName;

  const InternalViewerDialog({
    super.key,
    required this.file,
    required this.side,
    this.bytesOverride,
    this.displayName,
  });

  @override
  ConsumerState<InternalViewerDialog> createState() =>
      _InternalViewerDialogState();
}

class _InternalViewerDialogState extends ConsumerState<InternalViewerDialog> {
  // ---- Core data -----------------------------------------------------------
  Uint8List? _fullData;
  ViewBytesSource? _source;
  bool _loading = true;
  bool _preparing = false;
  String? _error;
  String? _richError;
  String? _viewNote;

  // ---- Mode ----------------------------------------------------------------
  ViewerMode _autoMode = ViewerMode.text;
  ViewerMode _mode = ViewerMode.text;
  int _prepareToken = 0;
  int _bytesPerLine = 16;
  double _zoom = 1.0;

  /// When a plain .gz/.bz2 was expanded, the (decompressed) inner file name.
  String? _expansionName;

  // ---- Text caches ---------------------------------------------------------
  String? _decodedText;
  List<int>? _lineStarts;
  List<String>? _displayLines;
  String? _encoding;
  String? _encodingOverride;
  String? _richText;
  OfficeDocument? _officeDoc;
  _OfficeView _officeView = _OfficeView.formatted;
  PdfController? _officePdfController;
  PdfDocument? _officePdfDoc;
  bool _officePdfLoading = false;
  String? _officePdfError;

  // PDF text layer
  bool _pdfShowText = false;
  bool _htmlRendered = true;
  bool _xmlTree = true;
  bool _pdfTextLoading = false;
  String? _pdfText;
  String? _pdfTextError;
  final PdfTextService _pdfTextService = PdfTextService();
  final SystemPreviewService _systemPreviewService = SystemPreviewService();

  // ---- Safe-byte caches ----------------------------------------------------
  String? _safeText;
  List<String>? _safeLines;
  List<int>? _safeStarts;
  bool? _safeBinary;

  // ---- Search --------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  bool _searchOpen = false;
  bool _isByteSearch = false;
  Uint8List? _searchBytes;
  List<int> _matches = const [];
  int _matchIndex = -1;
  String? _searchNote;
  int? _matchHighlightStart;
  int? _matchHighlightEnd;
  int? _streamScrollTo;
  int? _selectedByte;

  // Cache for the safe-view char offset of the active match.
  int? _cachedSafeMatchIndex;
  bool? _cachedSafeMatchBinary;
  int? _cachedSafeMatchOffset;

  // ---- Rich-mode resources -------------------------------------------------
  PdfController? _pdfController;
  PdfDocument? _pdfDoc;
  VideoPlayerController? _videoController;
  String? _mediaBlobUrl;
  String? _tempMediaPath;
  ViewerArchive? _archive;
  List<ViewerArchiveMember>? _archiveMembers;
  String? _archivePassword;

  // ---- Scroll --------------------------------------------------------------
  final ScrollController _vScroll = ScrollController();

  String get _viewName => widget.displayName ?? widget.file.name;

  String get _title {
    if (_expansionName != null) return '$_viewName  →  $_expansionName';
    return _viewName;
  }

  bool get _isStreamed => _source?.isStreamed ?? false;

  int get _dataSize => _source?.size ?? widget.file.size ?? 0;

  bool get _isByteMode =>
      _mode == ViewerMode.hex ||
      _mode == ViewerMode.ascii ||
      _mode == ViewerMode.binary ||
      (_mode == ViewerMode.text && _isStreamed);

  bool get _canChangeEncoding =>
      !_isStreamed &&
      (_mode == ViewerMode.text ||
          _mode == ViewerMode.markdown ||
          _mode == ViewerMode.csv ||
          _mode == ViewerMode.office);

  bool get _usingHighlightView =>
      _mode == ViewerMode.text &&
      !_isStreamed &&
      (_hlLanguage != null) &&
      ((_decodedText?.length ?? 0) <= _kHighlightMaxChars);

  bool get _modeHasRows =>
      !_usingHighlightView &&
      (_mode == ViewerMode.text ||
          _mode == ViewerMode.ascii ||
          _mode == ViewerMode.binary ||
          _mode == ViewerMode.hex);

  @override
  void initState() {
    super.initState();
    unawaited(_initialLoad());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _vScroll.dispose();
    _disposeModeResources();
    _source?.dispose();
    _source = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _initialLoad() async {
    try {
      final Uint8List? override = widget.bytesOverride;
      if (override != null) {
        await _useMemorySource(override);
      } else if (widget.side == PanelSide.local &&
          !kIsWeb &&
          widget.file.path != null) {
        final path = widget.file.path!;
        final localSvc = ref.read(localFileServiceProvider);

        // Prefer the listing size; fall back to a probe that prompts for
        // macOS sandbox access when needed.
        var length = widget.file.size;
        if (length == null) {
          length = await localSvc.fileLength(path);
          if (length == null) {
            final granted = await localSvc.ensureAccess(path);
            if (!granted) {
              throw FileBytesLoadException(
                'Access to "$path" was not granted. Grant access to its '
                'folder and try again.',
              );
            }
            length = await localSvc.fileLength(path);
          }
        }
        if (length == null) {
          throw FileBytesLoadException(
            'File not found or access denied: $path',
          );
        }

        if (length > kAutoFullLoadBytes) {
          final source = ViewBytesSource.file(
            path,
            acquireAccess: () async {
              final ok = await localSvc.beginStreamAccess(path);
              if (!ok) {
                throw FileBytesLoadException(
                  'Access to "$path" was not granted. Grant access to its '
                  'folder and try again.',
                );
              }
            },
            releaseAccess: localSvc.endStreamAccess,
          );
          await source.open();
          _source?.dispose();
          _source = source;
        } else {
          final data = await loadFileBytes(ref, widget.file, widget.side);
          await _useMemorySource(data);
        }
      } else {
        final data = await loadFileBytes(
          ref,
          widget.file,
          widget.side,
          capBytes: kViewerFullDataCap,
        );
        await _useMemorySource(data);
      }

      if (!mounted || _source == null) return;

      var auto = _viewerService.detectMode(
        _viewName,
        header: _source!.readSync(0, 4096),
      );

      if (auto == ViewerMode.archive && _isSingleCompressed(_viewName)) {
        final expanded = await _expandSingleCompressed();
        if (!mounted) return;
        if (expanded) {
          auto = _viewerService.detectMode(
            _expansionName ?? _viewName,
            header: _source!.readSync(0, 4096),
          );
        } else {
          auto = ViewerMode.hex;
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _autoMode = auto;
      });
      _selectMode(auto);
    } catch (e, st) {
      _log.warn('viewer initial load failed', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describeError(e);
      });
    }
  }

  Future<void> _useMemorySource(Uint8List data) async {
    _source?.dispose();
    _fullData = data;
    final source = ViewBytesSource.memory(data);
    await source.open();
    _source = source;
  }

  /// Expand a single-file .gz/.bz2/.xz/.zst so its content can be viewed.
  Future<bool> _expandSingleCompressed() async {
    try {
      final data = await _ensureFullData();
      final expanded = decompressSingleFile(
        data,
        _viewName,
        maxBytes: kViewerFullDataCap,
      );
      _expansionName = expanded.innerName;
      await _useMemorySource(expanded.data);
      return true;
    } catch (e, st) {
      _log.warn('single-file decompression failed', e, st);
      return false;
    }
  }

  Future<Uint8List> _ensureFullData() async {
    final have = _fullData;
    if (have != null) return have;
    final size = _dataSize;
    if (size > kViewerFullDataCap) {
      throw FileBytesTooLargeException(size, kViewerFullDataCap);
    }
    final data = await loadFileBytes(
      ref,
      widget.file,
      widget.side,
      capBytes: kViewerFullDataCap,
    );
    _fullData = data;
    return data;
  }

  static bool _isSingleCompressed(String name) => isSingleCompressedFile(name);

  String _describeError(Object error) {
    if (error is FileBytesTooLargeException) {
      return '${error.message}\n\n'
          'Hex, ASCII and Binary views need the file on the local disk; '
          'remote files are limited to ${formatBytes(kViewerFullDataCap)}.';
    }
    return error.toString();
  }

  // ---------------------------------------------------------------------------
  // Mode selection
  // ---------------------------------------------------------------------------

  void _selectMode(ViewerMode mode) {
    if (!mounted) return;
    final token = ++_prepareToken;
    _disposeModeResources();
    _searchDebounce?.cancel();
    setState(() {
      _mode = mode;
      _richError = null;
      _viewNote = null;
      _preparing = false;
      _selectedByte = null;
      _matchHighlightStart = null;
      _matchHighlightEnd = null;
      _streamScrollTo = null;
      _matches = const [];
      _matchIndex = -1;
      _cachedSafeMatchIndex = null;
      _cachedSafeMatchBinary = null;
      _cachedSafeMatchOffset = null;
      _officeDoc = null;
      _officeView = _OfficeView.formatted;
      _officePdfLoading = false;
      _officePdfError = null;
      _pdfShowText = false;
      _htmlRendered = true;
      _xmlTree = true;
      _pdfTextLoading = false;
      _pdfText = null;
      _pdfTextError = null;
    });

    final query = _searchController.text.trim();
    if (_searchOpen && query.isNotEmpty) {
      _runSearch(query);
    }

    unawaited(_prepareForMode(mode, token));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final position = _scrollPosition;
      if (mounted && position != null) position.jumpTo(0);
    });
  }

  Future<void> _prepareForMode(ViewerMode mode, int token) async {
    try {
      switch (mode) {
        case ViewerMode.text:
          if (!_isStreamed) _ensureText();
          return;
        case ViewerMode.ascii:
        case ViewerMode.binary:
        case ViewerMode.hex:
        case ViewerMode.unsupported:
          return;
        case ViewerMode.html:
        case ViewerMode.xml:
          if (!_isStreamed) _ensureText();
          return;
        case ViewerMode.markdown:
        case ViewerMode.csv:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          var text = InternalViewerService.decodeTextForView(
            data,
            encoding: _encodingOverride,
          ).text;
          String? note;
          if (text.length > _kRichRenderCap) {
            var cut = text.lastIndexOf('\n', _kRichRenderCap);
            if (cut <= 0) cut = _kRichRenderCap;
            text = text.substring(0, cut);
            note = 'Preview truncated to ${formatBytes(_kRichRenderCap)}';
          }
          _richText = text;
          setState(() {
            _preparing = false;
            _viewNote = note;
          });
          return;
        case ViewerMode.office:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          final document = await parseOfficeDocument(data, _viewName);
          if (!mounted || token != _prepareToken) return;
          _officeDoc = document;
          _richText = document.plainText;
          _officeView = document.deck != null
              ? _OfficeView.slides
              : (document.kind == OfficeDocumentKind.spreadsheet &&
                      (document.csv?.isNotEmpty ?? false)
                  ? _OfficeView.table
                  : _OfficeView.formatted);
          setState(() {
            _preparing = false;
            _viewNote = document.note;
          });
          return;
        case ViewerMode.image:
        case ViewerMode.font:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          if (mode == ViewerMode.font && data.length > _kFontPreviewCap) {
            setState(() {
              _preparing = false;
              _richError = 'This font is too large to preview safely '
                  '(${formatBytes(data.length)}).';
            });
            return;
          }
          setState(() => _preparing = false);
          return;
        case ViewerMode.pdf:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          final doc = await PdfDocument.openData(data);
          if (!mounted || token != _prepareToken) {
            unawaited(doc.close().catchError((Object _) {}));
            return;
          }
          _pdfDoc = doc;
          _pdfController = PdfController(document: Future.value(doc));
          setState(() => _preparing = false);
          return;
        case ViewerMode.media:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          await _prepareMedia(data, token);
          if (!mounted || token != _prepareToken) return;
          setState(() => _preparing = false);
          return;
        case ViewerMode.archive:
          setState(() => _preparing = true);
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          await _openArchive(data, token);
          return;
      }
    } catch (e, st) {
      _log.warn('viewer prepare failed for ${mode.name}', e, st);
      if (!mounted || token != _prepareToken) return;
      setState(() {
        _preparing = false;
        _richError = _describeError(e);
      });
    }
  }

  void _disposeModeResources() {
    final pdf = _pdfController;
    _pdfController = null;
    final doc = _pdfDoc;
    _pdfDoc = null;
    final video = _videoController;
    _videoController = null;
    final tempPath = _tempMediaPath;
    _tempMediaPath = null;
    final blobUrl = _mediaBlobUrl;
    _mediaBlobUrl = null;
    final archive = _archive;
    _archive = null;
    _archiveMembers = null;
    _archivePassword = null;
    final officePdf = _officePdfController;
    _officePdfController = null;
    final officePdfDoc = _officePdfDoc;
    _officePdfDoc = null;

    // The outgoing widget tree still references these controllers during the
    // frame in which the mode changes; dispose them after it is replaced, and
    // only delete the media file after the player has released it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      pdf?.dispose();
      if (doc != null) unawaited(doc.close().catchError((Object _) {}));
      if (video != null) {
        try {
          await video.dispose();
        } catch (_) {
          // Best effort.
        }
      }
      if (blobUrl != null && kIsWeb) html.Url.revokeObjectUrl(blobUrl);
      if (archive != null) unawaited(archive.close());
      officePdf?.dispose();
      if (officePdfDoc != null) {
        unawaited(officePdfDoc.close().catchError((Object _) {}));
      }
      if (tempPath != null) {
        try {
          await File(tempPath).delete();
        } catch (_) {
          // Best effort.
        }
      }
    });
  }

  Future<void> _openArchive(Uint8List data, int token) async {
    var password = _archivePassword;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final handle = await openViewerArchive(
          data,
          name: _viewName,
          password: password,
        );
        if (!mounted || token != _prepareToken) {
          await handle.close();
          return;
        }
        final previous = _archive;
        setState(() {
          _archive = handle;
          _archiveMembers = handle.members;
          _archivePassword = password;
          _preparing = false;
        });
        if (previous != null) unawaited(previous.close());
        return;
      } on ArchivePasswordRequiredException catch (e) {
        if (!mounted || token != _prepareToken) return;
        setState(() => _preparing = false);
        if (e.wrongPassword) _showSnack('Incorrect password.');
        final entered = await _promptArchivePassword(wrong: e.wrongPassword);
        if (!mounted || token != _prepareToken) return;
        if (entered == null) {
          setState(() => _richError = 'This archive is password-protected.');
          return;
        }
        password = entered;
        setState(() => _preparing = true);
      } on ArchiveViewException catch (e) {
        if (!mounted || token != _prepareToken) return;
        setState(() {
          _preparing = false;
          _richError = e.message;
        });
        return;
      }
    }
    if (!mounted || token != _prepareToken) return;
    setState(() {
      _preparing = false;
      _richError = 'Too many incorrect password attempts.';
    });
  }

  Future<void> _prepareMedia(Uint8List data, int token) async {
    if (kIsWeb) {
      final extension = _extensionOf(_viewName);
      final blob = html.Blob([data], mimeTypeForExt(extension));
      final url = html.Url.createObjectUrlFromBlob(blob);
      if (!mounted || token != _prepareToken) {
        html.Url.revokeObjectUrl(url);
        return;
      }
      _mediaBlobUrl = url;
      return;
    }

    // Application Support is stabler than Caches: macOS/Flutter may purge
    // the temporary directory while the player is opening the file.
    final supportDir = await getApplicationSupportDirectory();
    final mediaDir = Directory('${supportDir.path}/viewer_media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    await _cleanupOldMedia(mediaDir);

    final extension = _extensionOf(_viewName);
    final suffix = extension.isEmpty ? '' : '.$extension';
    final path =
        '${mediaDir.path}/viewer_${DateTime.now().microsecondsSinceEpoch}$suffix';

    VideoPlayerController? controller;
    Object? lastError;
    for (var attempt = 0; attempt < 2 && controller == null; attempt++) {
      await File(path).writeAsBytes(data, flush: true);
      if (!await File(path).exists()) {
        lastError = FileSystemException(
          'Media file disappeared before playback',
          path,
        );
        continue;
      }
      final candidate = VideoPlayerController.file(File(path));
      try {
        await candidate.initialize();
        controller = candidate;
        break;
      } catch (e) {
        lastError = e;
        try {
          await candidate.dispose();
        } catch (_) {
          // Best effort.
        }
      }
    }

    if (!mounted || token != _prepareToken) {
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {
          // Best effort.
        }
      }
      try {
        File(path).deleteSync();
      } catch (_) {
        // Best effort only.
      }
      return;
    }
    if (controller == null) {
      try {
        File(path).deleteSync();
      } catch (_) {
        // Best effort only.
      }
      throw lastError ??
          StateError('Media playback is not available for this file.');
    }
    _tempMediaPath = path;
    _videoController = controller;
  }

  Future<void> _cleanupOldMedia(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 12));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {
          // Skip entries that disappear or cannot be inspected.
        }
      }
    } catch (_) {
      // Cleanup is best-effort.
    }
  }


  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  // ---------------------------------------------------------------------------
  // Text / safe-byte decoding
  // ---------------------------------------------------------------------------

  String _ensureText() {
    final cached = _decodedText;
    if (cached != null) return cached;
    final data = _fullData;
    if (data == null) return '';
    final decoded = InternalViewerService.decodeTextForView(
      data,
      encoding: _encodingOverride,
    );
    _decodedText = decoded.text;
    _encoding = decoded.encoding;
    _lineStarts = _lineStartsOf(decoded.text);
    _displayLines = _splitDisplayLines(decoded.text);
    return decoded.text;
  }

  static List<int> _lineStartsOf(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    return starts;
  }

  static List<String> _splitDisplayLines(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.endsWith('\r')) {
        lines[i] = line.substring(0, line.length - 1);
      }
    }
    return lines;
  }

  void _ensureSafeText(bool binary) {
    if (_safeText != null && _safeBinary == binary) return;
    final data = _fullData;
    if (data == null) return;
    final text = InternalViewerService.renderSafeBytes(
      data,
      binaryMode: binary,
    );
    _safeText = text;
    _safeLines = text.split('\n');
    _safeStarts = _lineStartsOf(text);
    _safeBinary = binary;
  }

  static int _lineIndexOfOffset(List<int> starts, int offset) {
    if (starts.isEmpty) return 0;
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  int _safeOffsetForMatch(int matchIndex, bool binary) {
    final cached = _cachedSafeMatchOffset;
    if (cached != null &&
        _cachedSafeMatchIndex == matchIndex &&
        _cachedSafeMatchBinary == binary) {
      return cached;
    }
    final data = _fullData;
    if (data == null) return 0;
    final offset = InternalViewerService.renderSafeBytes(
      data,
      binaryMode: binary,
      end: _matches[matchIndex],
    ).length;
    _cachedSafeMatchIndex = matchIndex;
    _cachedSafeMatchBinary = binary;
    _cachedSafeMatchOffset = offset;
    return offset;
  }

  // ---------------------------------------------------------------------------
  // Scrolling / navigation
  // ---------------------------------------------------------------------------

  double get _rowExtent =>
      _mode == ViewerMode.hex ? hexRowExtent(_zoom) : 13.0 * _zoom * 1.5;

  /// During a mode switch the outgoing and incoming scroll views can briefly
  /// both be attached; only use the controller when exactly one is live.
  ScrollPosition? get _scrollPosition {
    if (!_vScroll.hasClients) return null;
    final positions = _vScroll.positions;
    return positions.length == 1 ? positions.first : null;
  }

  int _topVisibleRow() {
    final position = _scrollPosition;
    if (position == null) return 0;
    final row = ((position.pixels - 4.0) / _rowExtent).round();
    return row < 0 ? 0 : row;
  }

  void _scrollToRow(int row) {
    final position = _scrollPosition;
    if (position == null) return;
    final target = 4.0 + row * _rowExtent;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  void _adjustZoom(double delta) {
    final next = (_zoom + delta).clamp(0.7, 3.0);
    if ((next - _zoom).abs() < 0.001) return;
    setState(() => _zoom = next);
  }

  Future<void> _showGotoDialog() async {
    final offsetMode = _mode == ViewerMode.hex || _isStreamed;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: offsetMode ? InternalViewerStrings(context).text('goOffset') : InternalViewerStrings(context).text('goLine'),
        hintText: offsetMode
            ? InternalViewerStrings(context).text('offsetHint')
            : InternalViewerStrings(context).text('lineNumber'),
        confirmLabel: InternalViewerStrings(context).text('go'),
      ),
    );
    final text = result?.trim() ?? '';
    if (text.isEmpty) return;

    if (offsetMode) {
      final offset = _parseOffset(
        text,
        defaultRadix: _mode == ViewerMode.hex ? 16 : 10,
      );
      if (offset == null || offset < 0) return;
      if (_mode == ViewerMode.hex) {
        _scrollToRow(offset ~/ _bytesPerLine);
      } else if (_isStreamed) {
        setState(() => _streamScrollTo = offset);
      }
      return;
    }

    final line = int.tryParse(text);
    if (line == null) return;
    _scrollToRow((line - 1).clamp(0, 1 << 30));
  }

  static int? _parseOffset(String input, {int defaultRadix = 10}) {
    var value = input.trim().toLowerCase();
    var radix = defaultRadix;
    if (value.startsWith('0x')) {
      value = value.substring(2);
      radix = 16;
    } else if (RegExp(r'[a-f]').hasMatch(value)) {
      radix = 16;
    }
    return int.tryParse(value, radix: radix);
  }

  Future<String?> _promptArchivePassword({required bool wrong}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: wrong ? InternalViewerStrings(context).text('wrongPassword') : InternalViewerStrings(context).text('passwordRequired'),
        label: InternalViewerStrings(context).text('archivePassword'),
        obscureText: true,
      ),
    );
    final value = result?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _toggleSearch() {
    if (_searchOpen) {
      _searchDebounce?.cancel();
      setState(() {
        _searchOpen = false;
        _matches = const [];
        _matchIndex = -1;
        _searchNote = null;
        _matchHighlightStart = null;
        _matchHighlightEnd = null;
        _searchController.clear();
      });
      return;
    }

    setState(() => _searchOpen = true);
    if (_mode != ViewerMode.text &&
        _mode != ViewerMode.ascii &&
        _mode != ViewerMode.binary &&
        _mode != ViewerMode.hex) {
      // Rendered modes (markdown/CSV/office/archive/image/…) don't support
      // match highlighting; fall back to the text view.
      _selectMode(ViewerMode.text);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (_isStreamed) {
      setState(() {
        _searchNote =
            value.trim().isEmpty ? null : InternalViewerStrings(context).text('scan');
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch(value);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    _runSearch(value);
  }

  void _runSearch(String raw) {
    final query = raw.trim();
    if (!mounted) return;

    if (query.isEmpty) {
      setState(() {
        _matches = const [];
        _matchIndex = -1;
        _searchNote = null;
        _matchHighlightStart = null;
        _matchHighlightEnd = null;
        _isByteSearch = false;
        _searchBytes = null;
      });
      return;
    }

    if (_isByteMode) {
      final pattern = _patternFor(query);
      if (pattern.isEmpty) return;
      _searchBytes = pattern;
      _isByteSearch = true;

      List<int> found;
      if (_isStreamed) {
        found = _scanSource(pattern);
      } else {
        final data = _fullData;
        if (data == null) return;
        found = InternalViewerService.findBytes(
          data,
          pattern,
          maxMatches: _kSearchMaxMatches,
        );
      }

      setState(() {
        _matches = found;
        _matchIndex = found.isEmpty ? -1 : 0;
        _searchNote = _isStreamed
            ? 'searched first ${formatBytes(_kStreamSearchCap)}'
            : null;
        _cachedSafeMatchIndex = null;
        _cachedSafeMatchBinary = null;
        _cachedSafeMatchOffset = null;
        _matchHighlightStart = null;
        _matchHighlightEnd = null;
      });
      if (_matchIndex >= 0) _navigateToMatch();
      return;
    }

    _isByteSearch = false;
    _searchBytes = null;
    final text = _ensureText();
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();
    final found = <int>[];
    var from = 0;
    while (found.length < _kSearchMaxMatches) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      found.add(at);
      from = at + 1;
    }

    setState(() {
      _matches = found;
      _matchIndex = found.isEmpty ? -1 : 0;
      _searchNote = null;
      _matchHighlightStart = null;
      _matchHighlightEnd = null;
    });
    if (_matchIndex >= 0) _navigateToMatch();
  }

  Uint8List _patternFor(String query) {
    final wantsHex =
        _mode == ViewerMode.hex || query.toLowerCase().startsWith('0x');
    if (wantsHex) {
      final parsed = InternalViewerService.parseHexPattern(query);
      if (parsed != null) return parsed;
    }
    return Uint8List.fromList(utf8.encode(query));
  }

  List<int> _scanSource(Uint8List pattern) {
    final source = _source;
    final out = <int>[];
    if (source == null) return out;
    final limit =
        source.size < _kStreamSearchCap ? source.size : _kStreamSearchCap;
    const chunk = 1 << 20;
    var position = 0;
    while (position < limit && out.length < _kSearchMaxMatches) {
      final remaining = limit - position;
      final readLength = remaining > chunk + pattern.length - 1
          ? chunk + pattern.length - 1
          : remaining;
      if (readLength <= 0) break;
      final data = source.readSync(position, readLength);
      if (data.isEmpty) break;
      final hits = InternalViewerService.findBytes(
        data,
        pattern,
        maxMatches: _kSearchMaxMatches - out.length,
      );
      for (final hit in hits) {
        final absolute = position + hit;
        if (absolute >= limit) continue;
        // Skip matches re-found in the previous chunk's overlap tail.
        if (out.isNotEmpty && absolute <= out.last) continue;
        out.add(absolute);
      }
      position += chunk;
    }
    return out;
  }

  void _gotoMatch(int step) {
    if (_matches.isEmpty) return;
    var next = _matchIndex + step;
    if (next < 0) next = _matches.length - 1;
    if (next >= _matches.length) next = 0;
    setState(() => _matchIndex = next);
    _navigateToMatch();
  }

  void _navigateToMatch() {
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return;
    final offset = _matches[_matchIndex];

    if (_isByteSearch) {
      final end = offset + (_searchBytes?.length ?? 1);
      setState(() {
        _matchHighlightStart = offset;
        _matchHighlightEnd = end;
      });
    } else {
      setState(() {
        _matchHighlightStart = null;
        _matchHighlightEnd = null;
      });
    }

    // Hex works over the shared controller for both memory and streamed data.
    if (_mode == ViewerMode.hex) {
      _scrollToRow(offset ~/ _bytesPerLine);
      return;
    }
    if (_isStreamed) {
      setState(() => _streamScrollTo = offset);
      return;
    }

    if (_isByteSearch) {
      final binary = _mode == ViewerMode.binary;
      final safeOffset = _safeOffsetForMatch(_matchIndex, binary);
      _ensureSafeText(binary);
      final starts = _safeStarts;
      if (starts == null) return;
      _scrollToRow(_lineIndexOfOffset(starts, safeOffset));
      return;
    }

    final starts = _lineStarts;
    if (starts == null) return;
    _scrollToRow(_lineIndexOfOffset(starts, offset));
  }

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  void _setEncoding(String? encoding) {
    if (_encodingOverride == encoding) return;
    setState(() {
      _encodingOverride = encoding;
      _decodedText = null;
      _lineStarts = null;
      _displayLines = null;
      _richText = null;
      _cachedSafeMatchIndex = null;
      _cachedSafeMatchBinary = null;
      _cachedSafeMatchOffset = null;
    });
    _selectMode(_mode);
  }

  // ---------------------------------------------------------------------------
  // Misc actions
  // ---------------------------------------------------------------------------

  void _reload() {
    ++_prepareToken;
    _disposeModeResources();
    _source?.dispose();
    _source = null;
    _fullData = null;
    _decodedText = null;
    _lineStarts = null;
    _displayLines = null;
    _richText = null;
    _safeText = null;
    _safeLines = null;
    _safeStarts = null;
    _safeBinary = null;
    _matches = const [];
    _matchIndex = -1;
    _matchHighlightStart = null;
    _matchHighlightEnd = null;
    _streamScrollTo = null;
    _selectedByte = null;
    _searchNote = null;
    _searchController.clear();
    _expansionName = null;
    setState(() {
      _loading = true;
      _error = null;
      _richError = null;
      _viewNote = null;
      _preparing = false;
      _mode = ViewerMode.text;
    });
    unawaited(_initialLoad());
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'goto':
        unawaited(_showGotoDialog());
        return;
      case 'zoom_in':
        _adjustZoom(0.1);
        return;
      case 'zoom_out':
        _adjustZoom(-0.1);
        return;
      case 'reload':
        _reload();
        return;
      case 'copy_all':
        unawaited(_copyAll());
        return;
      case 'bpl8':
        setState(() => _bytesPerLine = 8);
        return;
      case 'bpl16':
        setState(() => _bytesPerLine = 16);
        return;
      case 'bpl32':
        setState(() => _bytesPerLine = 32);
        return;
    }
  }

  void _handleEscape() {
    if (_searchOpen) {
      _toggleSearch();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _copyAll() async {
    String? text;
    if (_mode == ViewerMode.ascii || _mode == ViewerMode.binary) {
      final data = _fullData;
      if (data != null) {
        text = InternalViewerService.renderSafeBytes(
          data,
          binaryMode: _mode == ViewerMode.binary,
        );
      }
    } else if (_mode == ViewerMode.text ||
        _mode == ViewerMode.markdown ||
        _mode == ViewerMode.html ||
        _mode == ViewerMode.xml ||
        _mode == ViewerMode.csv ||
        _mode == ViewerMode.office) {
      text = _decodedText ?? _richText;
      if (text == null) {
        try {
          final data = await _ensureFullData();
          text = InternalViewerService.decodeTextForView(
            data,
            encoding: _encodingOverride,
          ).text;
        } catch (e) {
          _showSnack('Cannot copy this view: $e');
          return;
        }
      }
    }
    if (text == null || text.isEmpty) {
      _showSnack('Nothing to copy in this view.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copied ${text.length} characters.');
  }

  Future<void> _openArchiveMember(ViewerArchiveMember member) async {
    final initial = _archive;
    if (initial == null) return;
    ViewerArchive handle = initial;
    var target = member;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final bytes = await handle.readMember(target);
        if (!mounted) return;
        await showInternalViewer(
          context,
          file: widget.file,
          side: widget.side,
          bytesOverride: bytes,
          displayName: target.name,
        );
        return;
      } on ArchivePasswordRequiredException catch (e) {
        // Encrypted entry: prompt, reopen the archive with the password, and
        // retry the read (koni needs the password at open time).
        final unlocked = await _unlockArchiveEntry(
          target,
          wrong: e.wrongPassword || _archivePassword != null,
        );
        final reopened = _archive;
        if (unlocked == null || reopened == null) return;
        handle = reopened;
        target = unlocked;
      } on ArchiveViewException catch (e) {
        _showSnack(e.message);
        return;
      } catch (e, st) {
        _log.warn('archive member open failed', e, st);
        _showSnack('Could not open member: $e');
        return;
      }
    }
    _showSnack('Could not open the encrypted entry.');
  }

  Future<ViewerArchiveMember?> _unlockArchiveEntry(
    ViewerArchiveMember member, {
    required bool wrong,
  }) async {
    final data = _fullData;
    if (data == null) {
      _showSnack('The archive data is no longer available.');
      return null;
    }
    final entered = await _promptArchivePassword(wrong: wrong);
    if (entered == null) return null;
    try {
      final reopened = await openViewerArchive(
        data,
        name: _viewName,
        password: entered,
      );
      final matches = reopened.members
          .where((m) => m.isFile && m.name == member.name)
          .toList();
      if (matches.isEmpty) {
        await reopened.close();
        _showSnack('This entry no longer exists in the archive.');
        return null;
      }
      final previous = _archive;
      setState(() {
        _archive = reopened;
        _archiveMembers = reopened.members;
        _archivePassword = entered;
      });
      if (previous != null) unawaited(previous.close());
      return matches.first;
    } on ArchivePasswordRequiredException catch (e) {
      _showSnack(
          e.wrongPassword ? 'Incorrect password.' : 'Password required.');
      return null;
    } on ArchiveViewException catch (e) {
      _showSnack(e.message);
      return null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f3): () => _gotoMatch(1),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            _gotoMatch(-1),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            unawaited(_showGotoDialog()),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _adjustZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _adjustZoom(-0.1),
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: Text(_title, overflow: TextOverflow.ellipsis),
            titleTextStyle: theme.textTheme.titleMedium,
            actions: [
              if (!_loading && _error == null) ...[
                IconButton(
                  tooltip: InternalViewerStrings(context).text('search'),
                  icon: const Icon(Icons.search),
                  onPressed: _toggleSearch,
                ),
                IconButton(
                  tooltip: InternalViewerStrings(context).text('goto'),
                  icon: const Icon(Icons.my_location),
                  onPressed: () => unawaited(_showGotoDialog()),
                ),
                if (_canChangeEncoding)
                  PopupMenuButton<String>(
                    tooltip: InternalViewerStrings(context).text('encoding'),
                    icon: const Icon(Icons.text_fields),
                    onSelected: (value) =>
                        _setEncoding(value == 'auto' ? null : value),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'auto', child: Text(InternalViewerStrings(context).text('auto'))),
                      PopupMenuItem(value: 'utf8', child: Text('UTF-8')),
                      PopupMenuItem(value: 'utf16le', child: Text('UTF-16 LE')),
                      PopupMenuItem(value: 'utf16be', child: Text('UTF-16 BE')),
                      PopupMenuItem(value: 'latin1', child: Text('Latin-1')),
                    ],
                  ),
                PopupMenuButton<String>(
                  tooltip: InternalViewerStrings(context).text('more'),
                  icon: const Icon(Icons.more_vert),
                  onSelected: _onMenuSelected,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'goto',
                      child: Text(InternalViewerStrings(context).text('gotoMenu')),
                    ),
                    PopupMenuItem(
                      value: 'zoom_in',
                      child: Text(InternalViewerStrings(context).text('zoomIn')),
                    ),
                    PopupMenuItem(
                      value: 'zoom_out',
                      child: Text(InternalViewerStrings(context).text('zoomOut')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'bpl8',
                      child: Text('Hex: 8 bytes per row'),
                    ),
                    PopupMenuItem(
                      value: 'bpl16',
                      child: Text('Hex: 16 bytes per row'),
                    ),
                    PopupMenuItem(
                      value: 'bpl32',
                      child: Text('Hex: 32 bytes per row'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'copy_all',
                      child: Text(InternalViewerStrings(context).text('copyAll')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'reload',
                      child: Text(InternalViewerStrings(context).text('reload')),
                    ),
                  ],
                ),
              ],
              IconButton(
                tooltip: InternalViewerStrings(context).text('close'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          body: Column(
            children: [
              if (!_loading && _error == null) _buildToolbar(theme),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _messagePane(_error!, theme)
                        : _buildBody(theme),
              ),
              if (!_loading) _buildStatusBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final extraModes = <ViewerMode>[
      ViewerMode.markdown,
      ViewerMode.html,
      ViewerMode.xml,
      ViewerMode.pdf,
      ViewerMode.media,
      ViewerMode.font,
      ViewerMode.csv,
      ViewerMode.office,
      ViewerMode.archive,
    ].where((mode) => mode == _autoMode);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _modeChip('Auto', null),
                  _modeChip(InternalViewerStrings(context).text('text'), ViewerMode.text),
                  _modeChip('ASCII', ViewerMode.ascii),
                  _modeChip(InternalViewerStrings(context).text('binary'), ViewerMode.binary),
                  _modeChip('Hex', ViewerMode.hex),
                  _modeChip(InternalViewerStrings(context).text('image'), ViewerMode.image),
                  for (final mode in extraModes)
                    _modeChip(_modeLabelOf(mode), mode),
                  if (_mode == ViewerMode.pdf) _pdfViewToggle(),
                  if (_mode == ViewerMode.html) _htmlViewToggle(),
                  if (_mode == ViewerMode.xml) _xmlViewToggle(),
                  if (_mode == ViewerMode.office) _officeViewToggle(),
                  if (_mode == ViewerMode.office &&
                      _systemPreviewService.isSupported)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: IconButton(
                        tooltip: InternalViewerStrings(context).text('systemPreview'),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        onPressed: () => unawaited(_openSystemPreview()),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_searchOpen) _inlineSearch(theme),
        ],
      ),
    );
  }

  Widget _modeChip(String label, ViewerMode? mode) {
    final selected = mode == null ? _mode == _autoMode : _mode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => _selectMode(mode ?? _autoMode),
      ),
    );
  }

  ButtonStyle get _compactButtonStyle => const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
      );

  Widget _pdfViewToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SegmentedButton<bool>(
        style: _compactButtonStyle,
        segments: [
          ButtonSegment(value: false, label: Text(InternalViewerStrings(context).text('pages'))),
          ButtonSegment(value: true, label: Text(InternalViewerStrings(context).text('text'))),
        ],
        selected: {_pdfShowText},
        onSelectionChanged: (selection) {
          final showText = selection.first;
          setState(() => _pdfShowText = showText);
          if (showText &&
              _pdfText == null &&
              !_pdfTextLoading &&
              _pdfTextError == null) {
            unawaited(_loadPdfText());
          }
        },
      ),
    );
  }

  Widget _htmlViewToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SegmentedButton<bool>(
        style: _compactButtonStyle,
        segments: [
          ButtonSegment(value: true, label: Text(InternalViewerStrings(context).text('rendered'))),
          ButtonSegment(value: false, label: Text(InternalViewerStrings(context).text('source'))),
        ],
        selected: {_htmlRendered},
        onSelectionChanged: (selection) =>
            setState(() => _htmlRendered = selection.first),
      ),
    );
  }

  Widget _xmlViewToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SegmentedButton<bool>(
        style: _compactButtonStyle,
        segments: [
          ButtonSegment(value: true, label: Text(InternalViewerStrings(context).text('tree'))),
          ButtonSegment(value: false, label: Text(InternalViewerStrings(context).text('source'))),
        ],
        selected: {_xmlTree},
        onSelectionChanged: (selection) =>
            setState(() => _xmlTree = selection.first),
      ),
    );
  }

  Widget _officeViewToggle() {
    final document = _officeDoc;
    if (document == null) return const SizedBox.shrink();
    final lowerName = _viewName.toLowerCase();
    final legacyPpt = lowerName.endsWith('.ppt') || lowerName.endsWith('.pps');
    final options = <_OfficeView>[
      if (document.deck != null) _OfficeView.slides,
      if (!legacyPpt) _OfficeView.pdf,
      if (document.kind == OfficeDocumentKind.spreadsheet &&
          (document.csv?.isNotEmpty ?? false))
        _OfficeView.table,
      _OfficeView.formatted,
      _OfficeView.text,
      if (document.rawXml?.isNotEmpty ?? false) _OfficeView.raw,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SegmentedButton<_OfficeView>(
        style: _compactButtonStyle,
        segments: [
          for (final option in options)
            ButtonSegment(
              value: option,
              label: Text(_officeViewLabel(option)),
            ),
        ],
        selected: {_officeView},
        onSelectionChanged: (selection) {
          final view = selection.first;
          setState(() => _officeView = view);
          if (view == _OfficeView.pdf) unawaited(_loadOfficePdf());
        },
      ),
    );
  }

  Widget _inlineSearch(ThemeData theme) {
    final total = _matches.length;
    final position = _matchIndex >= 0 ? '${_matchIndex + 1}' : '0';
    return SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _mode == ViewerMode.hex
                      ? 'Hex bytes (e.g. DE AD BE EF) or text'
                      : 'Search text or 0x… bytes',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$position/$total',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: InternalViewerStrings(context).text('previous'),
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: total == 0 ? null : () => _gotoMatch(-1),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              tooltip: InternalViewerStrings(context).text('next'),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: total == 0 ? null : () => _gotoMatch(1),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              tooltip: InternalViewerStrings(context).text('closeSearch'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: _toggleSearch,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_preparing) {
      return Center(
        child: Text(
          InternalViewerStrings(context).text('preparing'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_richError != null) return _messagePane(_richError!, theme);

    final source = _source;
    if (source == null) return _messagePane(InternalViewerStrings(context).text('noData'), theme);

    switch (_mode) {
      case ViewerMode.text:
        return _buildTextBody(theme);
      case ViewerMode.ascii:
        return _buildSafeBody(false, theme);
      case ViewerMode.binary:
        return _buildSafeBody(true, theme);
      case ViewerMode.hex:
        return HexViewer(
          source: source,
          bytesPerLine: _bytesPerLine,
          fontScale: _zoom,
          controller: _vScroll,
          selectedByte: _selectedByte,
          highlightRangeStart: _isByteSearch ? _matchHighlightStart : null,
          highlightRangeEnd: _isByteSearch ? _matchHighlightEnd : null,
          onByteTapped: (offset) => setState(() => _selectedByte = offset),
        );
      case ViewerMode.image:
        return _buildImageBody();
      case ViewerMode.markdown:
        return Markdown(
          data: _richText ?? '',
          selectable: true,
          padding: const EdgeInsets.all(12),
        );
      case ViewerMode.html:
        return _buildHtmlBody(theme);
      case ViewerMode.xml:
        return _buildXmlBody(theme);
      case ViewerMode.pdf:
        return _buildPdfBody(theme);
      case ViewerMode.media:
        return _buildMediaBody();
      case ViewerMode.font:
        final data = _fullData;
        if (data == null) return _messagePane('Font data unavailable.', theme);
        return FontPreview(fontBytes: data, filename: _viewName);
      case ViewerMode.csv:
        return CsvTableView(content: _richText ?? '', filename: _viewName);
      case ViewerMode.office:
        return _buildOfficeBody(theme);
      case ViewerMode.archive:
        return _buildArchiveList(theme);
      case ViewerMode.unsupported:
        return _messagePane(
          'No preview is available for this file type.\n'
          'Use Hex, ASCII or Binary mode to inspect the raw bytes.',
          theme,
        );
    }
  }

  Widget _buildTextBody(ThemeData theme) {
    final source = _source!;
    if (source.isStreamed) {
      return SelectionArea(
        child: StreamingSafeView(
          source: source,
          rawText: true,
          fontScale: _zoom,
          controller: _vScroll,
          matchStart: _isByteSearch ? _matchHighlightStart : null,
          matchEnd: _isByteSearch ? _matchHighlightEnd : null,
          scrollToByte: _streamScrollTo,
        ),
      );
    }

    final text = _ensureText();
    final language = _hlLanguage;
    if (language != null && text.length <= _kHighlightMaxChars) {
      return SelectionArea(
        child: SingleChildScrollView(
          controller: _vScroll,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HighlightView(
                  text,
                  language: language,
                  theme: theme.brightness == Brightness.dark
                      ? monokaiSublimeTheme
                      : githubTheme,
                  padding: const EdgeInsets.all(8),
                  textStyle: monoTextStyle(
                    13.0 * _zoom,
                    theme.colorScheme.onSurface,
                  ).copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final lines = _displayLines ?? text.split('\n');
    final span = _textMatchSpan();
    return SelectionArea(
      child: MonoLineListView(
        lines: lines,
        fontScale: _zoom,
        controller: _vScroll,
        activeMatchLine: span?.line,
        activeMatchLocal: span == null ? null : (span.start, span.end),
      ),
    );
  }

  Widget _buildSafeBody(bool binary, ThemeData theme) {
    final source = _source!;
    if (source.isStreamed) {
      return SelectionArea(
        child: StreamingSafeView(
          source: source,
          binaryMode: binary,
          fontScale: _zoom,
          controller: _vScroll,
          matchStart: _isByteSearch ? _matchHighlightStart : null,
          matchEnd: _isByteSearch ? _matchHighlightEnd : null,
          scrollToByte: _streamScrollTo,
        ),
      );
    }

    _ensureSafeText(binary);
    final lines = _safeLines ?? const <String>[];
    final span = _safeMatchSpan(binary);
    return SelectionArea(
      child: MonoLineListView(
        lines: lines,
        fontScale: _zoom,
        controller: _vScroll,
        activeMatchLine: span?.line,
        activeMatchLocal: span == null ? null : (span.start, span.end),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // HTML rendering / XML tree (with source views)
  // -------------------------------------------------------------------------

  Widget _buildHtmlBody(ThemeData theme) {
    final source = _source!;
    if (source.isStreamed) {
      return StreamingSafeView(
        source: source,
        rawText: true,
        fontScale: _zoom,
        controller: _vScroll,
      );
    }
    final text = _ensureText();
    if (!_htmlRendered || text.length > _kRichRenderCap) {
      return _buildMarkupSource(text);
    }
    return SelectionArea(
      child: SingleChildScrollView(
        controller: _vScroll,
        padding: const EdgeInsets.all(12),
        child: HtmlWidget(
          text,
          textStyle: TextStyle(fontSize: 13 * _zoom, height: 1.45),
          onTapUrl: (_) => true,
        ),
      ),
    );
  }

  Widget _buildXmlBody(ThemeData theme) {
    final source = _source!;
    if (source.isStreamed || !_xmlTree) {
      if (source.isStreamed) {
        return StreamingSafeView(
          source: source,
          rawText: true,
          fontScale: _zoom,
          controller: _vScroll,
        );
      }
      return _buildMarkupSource(_ensureText());
    }
    final text = _ensureText();
    final capped = text.length > _kRichRenderCap
        ? text.substring(0, _kRichRenderCap)
        : text;
    return XmlTreeView(xml: capped, fontSize: 12.5 * _zoom);
  }

  Widget _buildMarkupSource(String text) {
    final theme = Theme.of(context);
    if (text.length <= _kHighlightMaxChars) {
      return SelectionArea(
        child: SingleChildScrollView(
          controller: _vScroll,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HighlightView(
                  text,
                  language: 'xml',
                  theme: theme.brightness == Brightness.dark
                      ? monokaiSublimeTheme
                      : githubTheme,
                  padding: const EdgeInsets.all(8),
                  textStyle: monoTextStyle(
                    13 * _zoom,
                    theme.colorScheme.onSurface,
                  ).copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MonoLineListView(
      lines: text.split('\n'),
      fontScale: _zoom,
      controller: _vScroll,
    );
  }

  // -------------------------------------------------------------------------
  // Office documents (formatted Markdown / table / text / raw XML)
  // -------------------------------------------------------------------------

  Future<void> _openSystemPreview() async {
    final data = _fullData;
    if (data == null) {
      _showSnack('Document data is not available yet.');
      return;
    }
    try {
      await _systemPreviewService.show(data, _viewName);
    } catch (e) {
      _showSnack('System preview failed: $e');
    }
  }

  Future<void> _loadOfficePdf() async {
    if (_officePdfLoading || _officePdfController != null) return;
    setState(() {
      _officePdfLoading = true;
      _officePdfError = null;
    });
    try {
      final data = await _ensureFullData();
      final pdf = await convertOfficeToPdf(data);
      if (!mounted) return;
      final document = await PdfDocument.openData(pdf);
      if (!mounted) {
        unawaited(document.close());
        return;
      }
      final previousController = _officePdfController;
      final previousDoc = _officePdfDoc;
      _officePdfDoc = document;
      _officePdfController = PdfController(document: Future.value(document));
      previousController?.dispose();
      if (previousDoc != null) unawaited(previousDoc.close());
      setState(() => _officePdfLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _officePdfLoading = false;
        _officePdfError = '$e';
      });
    }
  }

  Widget _buildOfficeBody(ThemeData theme) {
    final document = _officeDoc;
    if (document == null) {
      return Center(
        child: Text(
          InternalViewerStrings(context).text('preparingDoc'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return _buildOfficeContent(document, theme);
  }

  String _officeViewLabel(_OfficeView view) => switch (view) {
        _OfficeView.slides => 'Slides',
        _OfficeView.pdf => 'Pages',
        _OfficeView.formatted => 'Formatted',
        _OfficeView.table => 'Table',
        _OfficeView.text => 'Text',
        _OfficeView.raw => 'XML',
      };

  Widget _buildOfficeContent(OfficeDocument document, ThemeData theme) {
    switch (_officeView) {
      case _OfficeView.slides:
        final deck = document.deck;
        if (deck == null) {
          return _buildOfficeText(document, theme);
        }
        return PptxSlideViewer(deck: deck, fontScale: _zoom);
      case _OfficeView.pdf:
        if (_officePdfLoading) {
          return Center(
            child: Text(
              InternalViewerStrings(context).text('layoutPages'),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        final error = _officePdfError;
        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => unawaited(_loadOfficePdf()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final controller = _officePdfController;
        if (controller == null) {
          return Center(
            child: Text(
              InternalViewerStrings(context).text('layoutPages'),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return PdfPagePanel(controller: controller);
      case _OfficeView.table:
        final csv = document.csv;
        if (csv != null && csv.isNotEmpty) {
          return CsvTableView(content: csv, filename: _viewName);
        }
        return _buildOfficeText(document, theme);
      case _OfficeView.formatted:
        final markdown = document.markdown.trim();
        if (markdown.isEmpty) {
          if (document.plainText.trim().isNotEmpty) {
            return _buildOfficeText(document, theme);
          }
          return _messagePane('No readable content found in this document.', theme);
        }
        return Markdown(
          data: markdown,
          selectable: true,
          padding: const EdgeInsets.all(12),
        );
      case _OfficeView.text:
        return _buildOfficeText(document, theme);
      case _OfficeView.raw:
        final raw = document.rawXml;
        if (raw == null || raw.isEmpty) {
          return _messagePane(
            'Raw XML is not available for this document.',
            theme,
          );
        }
        return XmlTreeView(xml: raw, fontSize: 12.5 * _zoom);
    }
  }

  Widget _buildOfficeText(OfficeDocument document, ThemeData theme) {
    final full = document.plainText;
    if (full.trim().isEmpty) {
      return _messagePane('No readable text found in this document.', theme);
    }
    final text = full.length > _kRichRenderCap
        ? full.substring(0, _kRichRenderCap)
        : full;
    return SelectionArea(
      child: SingleChildScrollView(
        controller: _vScroll,
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: monoTextStyle(
            13 * _zoom,
            theme.colorScheme.onSurface,
          ).copyWith(height: 1.5),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // PDF pages + text layer
  // -------------------------------------------------------------------------

  Widget _buildPdfBody(ThemeData theme) {
    final controller = _pdfController;
    if (controller == null) {
      return Center(
        child: Text(
          'Rendering PDF…',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return _pdfShowText
        ? _buildPdfTextView(theme)
        : PdfPagePanel(controller: controller);
  }

  Widget _buildPdfTextView(ThemeData theme) {
    final style = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    if (_pdfTextLoading) {
      return Center(child: Text(InternalViewerStrings(context).text('extracting'), style: style));
    }
    final error = _pdfTextError;
    if (error != null) return _messagePane(error, theme);
    final text = _pdfText;
    if (text == null) {
      return Center(child: Text(InternalViewerStrings(context).text('extracting'), style: style));
    }
    final capped = text.length > _kRichRenderCap
        ? text.substring(0, _kRichRenderCap)
        : text;
    return SelectionArea(
      child: SingleChildScrollView(
        controller: _vScroll,
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          capped,
          style: monoTextStyle(
            12.5 * _zoom,
            theme.colorScheme.onSurface,
          ).copyWith(height: 1.5),
        ),
      ),
    );
  }

  Future<void> _loadPdfText() async {
    final data = _fullData;
    if (data == null || _pdfTextLoading) return;
    setState(() {
      _pdfTextLoading = true;
      _pdfTextError = null;
    });
    try {
      final text = await _pdfTextService.extractText(data);
      if (!mounted) return;
      setState(() {
        _pdfTextLoading = false;
        if (text == null) {
          _pdfTextError =
              'PDF text extraction is not available on this platform.';
        } else if (text.trim().isEmpty) {
          _pdfTextError =
              'This PDF has no text layer (it may be a scanned document).';
        } else {
          _pdfText = text;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfTextLoading = false;
        _pdfTextError = 'Could not extract PDF text: $e';
      });
    }
  }

  Widget _buildImageBody() {
    final data = _fullData;
    if (data == null) {
      return _messagePane('Image data unavailable.', Theme.of(context));
    }
    final lower = _viewName.toLowerCase();
    final isSvg = lower.endsWith('.svg') || lower.endsWith('.svgz');
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 8,
      child: Center(
        child: isSvg
            // Bound the layout box so a malicious SVG viewBox cannot request
            // an enormous canvas.
            ? SvgPicture.memory(
                data,
                width: 2048,
                height: 2048,
                fit: BoxFit.contain,
              )
            : Image.memory(
                data,
                fit: BoxFit.contain,
                // Decode at most 4096×4096 pixels: bounds memory for
                // image-decompression bombs while remaining crisp on HiDPI.
                cacheWidth: 4096,
                cacheHeight: 4096,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(InternalViewerStrings(context).text('decodeImage')),
                ),
              ),
      ),
    );
  }

  Widget _buildMediaBody() {
    final isAudio = _isAudioName(_viewName);
    final blobUrl = _mediaBlobUrl;
    if (blobUrl != null) {
      return WebMediaPlayer(blobUrl: blobUrl, isAudio: isAudio);
    }
    final controller = _videoController;
    if (controller != null) {
      return MediaPlayer(controller: controller, isAudio: isAudio);
    }
    return const Center(child: CircularProgressIndicator());
  }

  static const Set<String> _audioExtensions = <String>{
    'mp3',
    'wav',
    'flac',
    'aac',
    'ogg',
    'oga',
    'opus',
    'm4a',
    'wma',
    'aiff',
    'aif',
    'mid',
    'midi',
    'gsm',
    'amr',
    'au',
  };

  static bool _isAudioName(String name) =>
      _audioExtensions.contains(_extensionOf(name));

  Widget _buildArchiveList(ThemeData theme) {
    final files = _archiveMembers;
    if (files == null) {
      return Center(
        child: Text(
          InternalViewerStrings(context).text('openingArchive'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (files.isEmpty) {
      return _messagePane(InternalViewerStrings(context).text('emptyArchive'), theme);
    }
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final member = files[index];
        final isFile = member.isFile;
        return ListTile(
          dense: true,
          leading: Icon(
            isFile ? Icons.insert_drive_file_outlined : Icons.folder_outlined,
            size: 18,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (member.isEncrypted)
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              if (member.pathEscapedRoot)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: 'Path escaped the archive root (sanitized)',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          trailing: isFile
              ? Text(
                  formatBytes(member.size),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          onTap: isFile ? () => unawaited(_openArchiveMember(member)) : null,
        );
      },
    );
  }

  Widget _messagePane(String message, ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_source != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _selectMode(ViewerMode.hex),
                    child: const Text('Hex view'),
                  ),
                  OutlinedButton(
                    onPressed: () => _selectMode(ViewerMode.ascii),
                    child: const Text('ASCII view'),
                  ),
                  OutlinedButton(
                    onPressed: () => _selectMode(ViewerMode.binary),
                    child: const Text('Binary view'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(ThemeData theme) {
    final style = TextStyle(
      fontSize: 11.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final parts = <String>[
      _modeLabelOf(_mode),
      formatBytes(_dataSize),
      if (_isStreamed) 'streamed',
      if (_mode == ViewerMode.hex) '$_bytesPerLine bytes/row',
      if (_mode == ViewerMode.archive && _archive != null)
        _archive!.formatName.toUpperCase(),
      if (_mode == ViewerMode.pdf && _pdfShowText && _pdfText != null)
        '${_pdfText!.length} characters',
      if (_canChangeEncoding && _encoding != null) _encoding!,
      if (_viewNote != null) _viewNote!,
      if (_mode == ViewerMode.hex && _selectedByte != null) _selectedByteText(),
      if (_searchStatusText != null) _searchStatusText!,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(parts.join('   ·   '), style: style),
            ),
          ),
          if (_modeHasRows) ...[
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _vScroll,
              builder: (_, __) => Text(_positionLabel(), style: style),
            ),
          ],
        ],
      ),
    );
  }

  String _positionLabel() {
    if (_scrollPosition == null) return '';
    final row = _topVisibleRow();
    if (_mode == ViewerMode.hex) {
      final offset = row * _bytesPerLine;
      return 'offset 0x${offset.toRadixString(16).toUpperCase().padLeft(8, '0')}';
    }
    return 'line ${row + 1}';
  }

  String _selectedByteText() {
    final offset = _selectedByte!;
    final source = _source;
    if (source == null || offset >= source.size) return '';
    final byte = source.readSync(offset, 1);
    final value = byte.isEmpty ? 0 : byte[0];
    return byteStatusText(value, offset);
  }

  String? get _searchStatusText {
    if (!_searchOpen && _matches.isEmpty) return null;
    final base = _matches.isEmpty
        ? 'no matches'
        : '${_matchIndex + 1}/${_matches.length}';
    if (_searchNote == null) return base;
    return '$base (${_searchNote!})';
  }

  // ---------------------------------------------------------------------------
  // Match spans
  // ---------------------------------------------------------------------------

  _MatchSpan? _textMatchSpan() {
    if (!_searchOpen || _isByteSearch) return null;
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return null;
    final starts = _lineStarts;
    if (starts == null) return null;
    final offset = _matches[_matchIndex];
    final line = _lineIndexOfOffset(starts, offset);
    final local = offset - starts[line];
    final length = _searchController.text.trim().length;
    return _MatchSpan(line, local, local + (length < 1 ? 1 : length));
  }

  _MatchSpan? _safeMatchSpan(bool binary) {
    if (!_searchOpen ||
        !_isByteSearch ||
        _matchIndex < 0 ||
        _matchIndex >= _matches.length) {
      return null;
    }
    final starts = _safeStarts;
    if (starts == null) return null;
    final safeOffset = _safeOffsetForMatch(_matchIndex, binary);
    final line = _lineIndexOfOffset(starts, safeOffset);
    final local = safeOffset - starts[line];
    final length = _searchBytes?.length ?? 1;
    return _MatchSpan(line, local, local + length);
  }

  String? get _hlLanguage {
    final language = highlightLanguageFor(_viewName);
    if (language != null && language != 'plaintext') return language;
    final text = _decodedText;
    if (text == null) return null;
    final shebang = highlightLanguageForShebang(text);
    return (shebang == null || shebang == 'plaintext') ? null : shebang;
  }

  static String _modeLabelOf(ViewerMode mode) {
    switch (mode) {
      case ViewerMode.text:
        return 'Text';
      case ViewerMode.ascii:
        return 'ASCII';
      case ViewerMode.binary:
        return 'Binary';
      case ViewerMode.hex:
        return 'Hex';
      case ViewerMode.image:
        return 'Image';
      case ViewerMode.markdown:
        return 'Markdown';
      case ViewerMode.html:
        return 'HTML';
      case ViewerMode.xml:
        return 'XML';
      case ViewerMode.pdf:
        return 'PDF';
      case ViewerMode.media:
        return 'Media';
      case ViewerMode.font:
        return 'Font';
      case ViewerMode.csv:
        return 'Table';
      case ViewerMode.office:
        return 'Office';
      case ViewerMode.archive:
        return 'Archive';
      case ViewerMode.unsupported:
        return 'Unsupported';
    }
  }
}

class _MatchSpan {
  final int line;
  final int start;
  final int end;

  const _MatchSpan(this.line, this.start, this.end);
}

/// Small text prompt (goto line/offset, archive password) that owns and
/// disposes its controller only after the dialog route is gone.
class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? label;
  final String? hintText;
  final bool obscureText;
  final String confirmLabel;

  const _TextPromptDialog({
    required this.title,
    this.label,
    this.hintText,
    this.obscureText = false,
    this.confirmLabel = 'OK',
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(InternalViewerStrings(context).text('cancel')),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}


enum _OfficeView { slides, pdf, formatted, table, text, raw }
