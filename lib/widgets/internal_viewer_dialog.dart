// lib/widgets/internal_viewer_dialog.dart
//
// Full-screen internal viewer (F3).
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
//   archive  — streamed native containers and bounded nested member previews
//
// Hex, ASCII, Binary and Text always work, even for files too large to load
// fully, thanks to ViewBytesSource streaming on native platforms.

import 'dart:async';
import 'dart:math' as math;
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
import 'package:file_viewer_documents/file_viewer_documents.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:universal_html/html.dart' as html;
import 'package:video_player/video_player.dart';

import '../l10n/commander_strings.dart';
import '../l10n/binary_structure_strings.dart';
import '../l10n/lrc_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_streamed_reader.dart';
import '../services/archive_viewer_service.dart';
import '../services/archive_viewer_source.dart';
import '../services/archive_viewer_streaming.dart';
import '../services/binary_structure_service.dart';
import '../services/binary_structure_source.dart';
import '../services/file_bytes_loader.dart';
import '../services/ebook_file_store.dart' show isEbookFileName;
import 'ebook_editor_dialog.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/viewer_spool.dart';
import '../services/viewer_tail_service.dart';
import '../services/viewer_search_service.dart';
import '../services/internal_viewer_service.dart';
import '../services/lrc_parser.dart';
import '../services/lrc_source.dart';
import '../services/local_file_service.dart';
import '../services/log_service.dart';
import '../services/office_document_service.dart';
import '../services/email_message_service.dart';
import '../services/mbox_message_service.dart';
import '../services/document_preview_source.dart';
import '../l10n/email_viewer_strings.dart';
import '../l10n/mbox_viewer_strings.dart';
import '../l10n/document_viewer_strings.dart';
import 'email_message_view.dart';
import 'mbox_message_view.dart';
import '../services/office_pdf_service.dart';
import '../services/pdf_text_service.dart';
import '../services/system_preview_service.dart';
import '../utils/file_editability.dart';
import '../utils/formatters.dart';
import 'code_highlighting.dart';
import 'syntax_line_view.dart';
import '../services/syntax_line_highlighting.dart';
import 'hex_viewer.dart';
import 'binary_structure_dialog.dart';
import 'lrc_preview.dart';
import 'internal_viewer_views.dart';
import 'office_html_widget_factory.dart';
import 'pptx_slide_viewer.dart';
import 'preview_media.dart';
import 'xml_tree_view.dart';
import 'keepass_editor_dialog.dart';
import 'legacy_word_conversion_action.dart';
import '../l10n/legacy_word_conversion_strings.dart';
import '../l10n/internal_viewer_strings.dart';
import '../l10n/office_preview_strings.dart';
import '../l10n/file_bytes_error_strings.dart';
import '../l10n/archive_viewer_error_strings.dart';
import '../l10n/archive_integrity_strings.dart';
import 'archive_integrity_dialog.dart';
import '../l10n/native_preview_error_strings.dart';
import '../l10n/office_pdf_error_strings.dart';

const _log = Log('InternalViewer');

/// Files up to this size are loaded fully into memory on open; larger local
/// files are streamed from disk.
const int kAutoFullLoadBytes = 16 * 1024 * 1024;

/// Upper bound for modes that need the complete byte array (image/media/pdf/…).
const int kViewerFullDataCap = 64 * 1024 * 1024;

const int _kSearchMaxMatches = 2000;
const int _kHighlightMaxChars = 400 * 1024;
const int _kEmailSearchMaxLines = 200000;
const int _kEmailSearchMaxUtf8Bytes = 8 * 1024 * 1024;

/// Rich rendered modes (markdown/CSV/office) are truncated above this size so
/// a single huge document cannot freeze the UI thread.
const int _kRichRenderCap = 4 * 1024 * 1024;

/// Fonts above this size are refused (engine font parsing is costly).
const int _kFontPreviewCap = 32 * 1024 * 1024;

const InternalViewerService _viewerService = InternalViewerService();

/// Open the internal viewer for [file] as a full-screen dialog.
/// Result requested by the viewer when it closes.
enum InternalViewerAction { close, edit }

Future<InternalViewerAction> showInternalViewer(
  BuildContext context, {
  required FileItem file,
  required PanelSide side,
  Uint8List? bytesOverride,
  String? displayName,
  PanelFileOrigin? origin,
  ValueChanged<FileItem>? onFileChanged,
}) async {
  final result = await showDialog<InternalViewerAction>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: _ViewerSessionHost(
        file: file,
        side: side,
        bytesOverride: bytesOverride,
        displayName: displayName,
        origin: origin,
        onFileChanged: onFileChanged,
      ),
    ),
  );
  return result ?? InternalViewerAction.close;
}

/// Captures the ordered visible selection once. Navigating a collection never
/// resolves a row through whichever account happens to be active later.
class _ViewerSessionHost extends ConsumerStatefulWidget {
  const _ViewerSessionHost({
    required this.file,
    required this.side,
    this.bytesOverride,
    this.displayName,
    this.origin,
    this.onFileChanged,
  });
  final FileItem file;
  final PanelSide side;
  final Uint8List? bytesOverride;
  final String? displayName;
  final PanelFileOrigin? origin;
  final ValueChanged<FileItem>? onFileChanged;
  @override
  ConsumerState<_ViewerSessionHost> createState() => _ViewerSessionHostState();
}

class _ViewerSessionHostState extends ConsumerState<_ViewerSessionHost> {
  late List<({FileItem file, PanelFileOrigin? origin})> _items;
  int _index = 0;
  @override
  void initState() {
    super.initState();
    if (widget.bytesOverride != null) {
      _items = [(file: widget.file, origin: null)];
      return;
    }
    final panel = ref.read(panelProvider(widget.side));
    final visible = (panel.displayedFiles ?? const <FileItem>[])
        .where((file) => !file.isFolder && file.name != '..')
        .toList();
    final selected = visible.where(panel.selection.contains).toList();
    final candidates = widget.bytesOverride != null
        ? [widget.file]
        : selected.length > 1 &&
              selected.any((file) => identical(file, widget.file))
        ? selected
        : visible;
    if (!candidates.any((file) => identical(file, widget.file))) {
      candidates.insert(0, widget.file);
    }
    _items = [
      for (final file in candidates)
        (
          file: file,
          origin: identical(file, widget.file) && widget.origin != null
              ? widget.origin
              : panel.originForOperation(file),
        ),
    ];
    _index = _items.indexWhere((item) => identical(item.file, widget.file));
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _items.length) return;
    setState(() => _index = next);
    widget.onFileChanged?.call(_items[next].file);
  }

  @override
  Widget build(BuildContext context) {
    final item = _items[_index];
    final onPrevious = _index > 0 ? () => _go(-1) : null;
    final onNext = _index + 1 < _items.length ? () => _go(1) : null;
    final position = _items.length > 1
        ? '${_index + 1} / ${_items.length}'
        : null;
    if (isEbookFileName(widget.displayName ?? item.file.name)) {
      return EbookEditorDialog(
        key: ValueKey(_index),
        file: item.file,
        side: widget.side,
        origin: item.origin,
        bytesOverride: widget.bytesOverride,
        displayName: widget.displayName,
        onPrevious: onPrevious,
        onNext: onNext,
        positionLabel: position,
      );
    }
    if (isKeePassFileName(widget.displayName ?? item.file.name)) {
      return KeePassEditorDialog(
        key: ValueKey(_index),
        file: widget.bytesOverride != null && widget.displayName != null
            ? item.file.copyWith(name: widget.displayName)
            : item.file,
        side: widget.side,
        origin: item.origin,
        bytesOverride: widget.bytesOverride,
        readOnly: true,
        onPrevious: onPrevious,
        onNext: onNext,
        positionLabel: position,
      );
    }
    return InternalViewerDialog(
      key: ValueKey(_index),
      file: item.file,
      side: widget.side,
      origin: item.origin,
      bytesOverride: widget.bytesOverride,
      displayName: widget.displayName,
      onPrevious: onPrevious,
      onNext: onNext,
      positionLabel: position,
    );
  }
}

class InternalViewerDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;
  final PanelFileOrigin? origin;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? positionLabel;

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
    this.origin,
    this.onPrevious,
    this.onNext,
    this.positionLabel,
  });

  @override
  ConsumerState<InternalViewerDialog> createState() =>
      _InternalViewerDialogState();
}

class _InternalViewerDialogState extends ConsumerState<InternalViewerDialog> {
  // ---- Core data -----------------------------------------------------------
  Uint8List? _fullData;
  ViewBytesSource? _source;
  PanelFileOrigin? _origin;
  ViewerSpool? _spool;
  int _loadToken = 0;
  int _downloadedBytes = 0;
  int? _downloadTotal;
  Timer? _tailTimer;
  ViewerTailService? _tailService;
  bool _tailEnabled = false;
  bool _tailLoading = false;
  String? _tailEncoding;

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
  LrcDocument? _lrcDocument;
  LrcSourceError? _lrcError;
  OfficeDocument? _officeDoc;
  EmailMessageDocument? _emailMessage;
  MboxDocument? _mailbox;
  int _mailboxIndex = 0;
  MboxMessageError? _mailboxMessageError;
  Uint8List? _documentPreviewBytes;
  bool _documentTextFallback = false;
  String? _nativePptError;
  String? _xmlToolsError;
  bool _xmlToolsLoading = false;
  ViewBytesSource? _emailSearchSource;
  Future<bool>? _emailSearchPreparation;
  bool _emailSearchLimited = false;
  bool _emailSearchLimitShown = false;
  List<String>? _emailLines;
  List<int>? _emailLineStarts;
  _OfficeView _officeView = _OfficeView.formatted;
  PdfController? _officePdfController;
  PdfDocument? _officePdfDoc;
  bool _officePdfLoading = false;
  String? _officePdfError;

  // PDF text layer
  bool _pdfShowText = false;
  bool _htmlRendered = true;
  bool _xmlTree = true;
  bool _xmlTools = false;
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
  bool _searching = false;
  int _searchGeneration = 0;
  int _searchBytesScanned = 0;
  bool _isByteSearch = false;
  Uint8List? _searchBytes;
  List<int> _matches = const [];
  List<int> _matchEnds = const [];
  int _matchBase = 0;
  int _totalMatches = 0;
  int? _nextSearchOffset;
  int? _nextTextOffset;
  bool _matchCase = false;
  int _matchIndex = -1;
  String? _searchNote;
  int? _matchHighlightStart;
  int? _matchHighlightEnd;
  int? _streamScrollTo;
  int _streamScrollRequest = 0;
  int? _selectedByte;
  int? _structureHighlightStart;
  int? _structureHighlightEnd;
  bool _inspectingStructure = false;

  // Cache for the safe-view char offset of the active match.
  int? _cachedSafeMatchIndex;
  bool? _cachedSafeMatchBinary;
  int? _cachedSafeMatchOffset;

  // ---- Rich-mode resources -------------------------------------------------
  PdfController? _pdfController;
  PdfDocument? _pdfDoc;

  /// True while a macOS/iOS security scope is held for PdfDocument.openFile.
  bool _pdfStreamAccess = false;
  bool _mediaStreamAccess = false;
  VideoPlayerController? _videoController;
  String? _mediaBlobUrl;
  String? _tempMediaPath;
  ViewerArchive? _archive;
  ArchiveViewerSource? _archiveSource;
  final _archiveSources = <ArchiveViewerSource>{};
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

  /// Archive members and test byte overrides have no host path to save to, so
  /// they stay view-only. Otherwise show Edit for formats F4 can save.
  bool get _canEdit =>
      widget.bytesOverride == null &&
      _origin?.isCurrent == true &&
      !widget.file.isFolder &&
      (isEditableInBuiltInEditor(_viewName) || !isTextEditableName(_viewName));

  int get _dataSize => _source?.size ?? widget.file.size ?? 0;

  bool get _isMailbox =>
      (_expansionName ?? _viewName).toLowerCase().endsWith('.mbox');

  DocumentPreviewKind? get _browserDocumentKind =>
      documentPreviewKind(_expansionName ?? _viewName);

  bool get _canChangeEncoding =>
      (_mode == ViewerMode.text ||
      _mode == ViewerMode.lyrics ||
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
          _mode == ViewerMode.hex ||
          (_mode == ViewerMode.email && _searchOpen && _emailLines != null));

  @override
  void initState() {
    super.initState();
    _origin =
        widget.origin ??
        (widget.bytesOverride == null
            ? ref
                  .read(panelProvider(widget.side))
                  .originForOperation(widget.file)
            : null);
  }

  bool _initialLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    // The synchronous error path formats localized messages. Inherited
    // localization data is available here, after initState has completed.
    unawaited(_initialLoad());
  }

  @override
  void dispose() {
    _searchGeneration++;
    ++_loadToken;
    ++_prepareToken;
    _tailTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _vScroll.dispose();
    _disposeModeResources(spool: _spool);
    _spool = null;
    _source?.dispose();
    _source = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  FileOperationBackend _capturedBackend() {
    final origin = _origin;
    if (origin == null || !origin.isCurrent) {
      throw const FileBytesLoadException(
        'The original viewer source is unavailable. Refresh or reopen the file.',
      );
    }
    return fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => mounted && origin.isCurrent,
    );
  }

  String? get _nativeViewPath {
    if (kIsWeb || widget.bytesOverride != null) return null;
    if (_spool != null) return _spool!.path;
    return _origin?.source.isLocal == true ? widget.file.path : null;
  }

  Future<void> _initialLoad({ViewerMode? preferredMode}) async {
    final loadToken = ++_loadToken;
    bool current() => mounted && loadToken == _loadToken;
    try {
      final override = widget.bytesOverride;
      if (override != null) {
        await _useMemorySource(override);
      } else {
        final backend = _capturedBackend();
        final path =
            widget.file.path ??
            backend.paths.join(_origin!.source.currentPath, widget.file.name);
        final fresh = await backend.stat(path);
        if (fresh == null || fresh.isFolder) {
          throw FileBytesLoadException('File not found: $path');
        }
        if (widget.file.uuid != null && widget.file.uuid != fresh.uuid) {
          throw const FileBytesLoadException(
            'A different file now occupies this path. Reopen it.',
          );
        }
        if (!current()) return;
        if (!kIsWeb &&
            _origin!.source.isLocal &&
            ((fresh.size ?? 0) > kAutoFullLoadBytes ||
                _viewName.toLowerCase().endsWith('.pdf') ||
                _viewerService.detectMode(_viewName) == ViewerMode.media)) {
          final local = ref.read(localFileServiceProvider);
          final source = ViewBytesSource.file(
            path,
            acquireAccess: () async {
              if (!_origin!.isCurrent || !await local.beginStreamAccess(path)) {
                throw FileBytesLoadException(
                  'Access to "$path" was not granted.',
                );
              }
            },
            releaseAccess: local.endStreamAccess,
          );
          try {
            await source.open();
            if (!current()) {
              source.dispose();
              return;
            }
            _source?.dispose();
            _source = source;
          } catch (_) {
            source.dispose();
            rethrow;
          }
        } else if (!kIsWeb &&
            !_origin!.source.isLocal &&
            (fresh.size == null || fresh.size! > kAutoFullLoadBytes)) {
          final spool = await createViewerSpool(
            backend,
            fresh,
            isCancelled: () => !current(),
            onProgress: (bytes, total) {
              if (current()) {
                setState(() {
                  _downloadedBytes = bytes;
                  _downloadTotal = total;
                });
              }
            },
          );
          if (!current()) {
            await spool.close();
            return;
          }
          final source = ViewBytesSource.file(spool.path);
          try {
            await source.open();
          } catch (_) {
            source.dispose();
            await spool.close();
            rethrow;
          }
          if (!current()) {
            source.dispose();
            await spool.close();
            return;
          }
          _spool = spool;
          _source?.dispose();
          _source = source;
        } else {
          final data = await loadFileBytes(
            ref,
            widget.file,
            widget.side,
            capBytes: kViewerFullDataCap,
            origin: _origin,
          );
          if (!current()) return;
          await _useMemorySource(data);
        }
      }
      if (!current() || _source == null) return;
      var auto = _viewerService.detectMode(
        _viewName,
        header: _source!.readSync(0, 4096),
      );
      if (auto == ViewerMode.archive && _isSingleCompressed(_viewName)) {
        final expanded = await _expandSingleCompressed();
        if (!current()) return;
        auto = expanded
            ? _viewerService.detectMode(
                _expansionName ?? _viewName,
                header: _source!.readSync(0, 4096),
              )
            : ViewerMode.hex;
      }
      if (!current()) return;
      setState(() {
        _loading = false;
        _autoMode = auto;
      });
      _selectMode(preferredMode ?? auto);
    } catch (e, st) {
      _log.warn('viewer initial load failed', e, st);
      if (!current()) return;
      setState(() {
        _loading = false;
        _error = _describeError(e);
      });
    }
  }

  Future<void> _useMemorySource(Uint8List data) async {
    _resetSearchResults();
    _source?.dispose();
    _fullData = data;
    final source = ViewBytesSource.memory(data);
    await source.open();
    if (!mounted) {
      source.dispose();
      return;
    }
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
    if (_spool != null && _source != null) {
      final bytes = BytesBuilder(copy: false);
      for (var offset = 0; offset < size; offset += 256 * 1024) {
        bytes.add(_source!.readSync(offset, 256 * 1024));
      }
      _fullData = bytes.takeBytes();
      return _fullData!;
    }
    final data = await loadFileBytes(
      ref,
      widget.file,
      widget.side,
      capBytes: kViewerFullDataCap,
      origin: _origin,
    );
    _fullData = data;
    return data;
  }

  static bool _isSingleCompressed(String name) => isSingleCompressedFile(name);

  String _describeError(Object error) {
    if (error is MboxPreviewException) {
      return MboxViewerStrings(context).previewError(error.code);
    }
    if (error is DocumentSourceException) {
      if (_isMailbox) {
        return MboxViewerStrings(context).text(
          error.code == DocumentSourceError.readLimit
              ? 'inputLimit'
              : error.code.name,
        );
      }
      return DocumentViewerStrings(context).text(error.code.name);
    }
    if (error is FileBytesTooLargeException) {
      return '${error.message}\n\n'
          'This mode needs a complete byte array. Hex, ASCII, Binary and text '
          'can use a local file or a streamed temporary copy.';
    }
    if (error is FileBytesTooLargeException) {
      final detail = InternalViewerStrings(context)
          .withNumber('remoteLimit', formatBytes(kViewerFullDataCap));
      return '${localizedFileBytesError(context, error)}\n\n$detail';
    }
    return localizedFileBytesError(context, error);
  }

  // ---------------------------------------------------------------------------
  // Mode selection
  // ---------------------------------------------------------------------------

  void _selectMode(ViewerMode mode) {
    if (!mounted) return;
    _resetSearchResults();
    if (_tailEnabled) {
      _reload(preferredMode: mode);
      return;
    }
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
      _lrcDocument = null;
      _lrcError = null;
      _emailMessage = null;
      _mailbox = null;
      _mailboxIndex = 0;
      _mailboxMessageError = null;
      _documentPreviewBytes = null;
      _documentTextFallback = false;
      _nativePptError = null;
      _xmlToolsError = null;
      _xmlToolsLoading = false;
      _officeView = _OfficeView.formatted;
      _officePdfLoading = false;
      _officePdfError = null;
      _pdfShowText = false;
      _htmlRendered = true;
      _xmlTree = true;
      _xmlTools = false;
      _pdfTextLoading = false;
      _pdfText = null;
      _pdfTextError = null;
    });

    final query = _searchController.text;
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
        case ViewerMode.lyrics:
          final source = _source;
          if (source == null) return;
          final loadToken = _loadToken;
          bool current() =>
              mounted &&
              token == _prepareToken &&
              loadToken == _loadToken &&
              identical(_source, source);
          setState(() => _preparing = true);
          try {
            final result = await readLrcSource(
              source,
              encodingOverride: _encodingOverride,
              isCurrent: current,
            );
            if (!current()) return;
            setState(() {
              _lrcDocument = result.document;
              _encoding = result.encoding;
              _preparing = false;
            });
          } on LrcSourceException catch (error) {
            if (!current()) return;
            setState(() {
              _lrcError = error.code;
              _preparing = false;
            });
          }
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
            note = InternalViewerStrings(context)
                .withNumber('truncated', formatBytes(_kRichRenderCap));
          }
          _richText = text;
          setState(() {
            _preparing = false;
            _viewNote = note;
          });
          return;
        case ViewerMode.email:
          setState(() => _preparing = true);
          if (_isMailbox) {
            final data = await _readDocumentBytes(kMboxPreviewMaxBytes, token);
            if (!mounted || token != _prepareToken || data == null) return;
            final mailbox = parseMboxDocument(data);
            setState(() {
              _mailbox = mailbox;
              _preparing = false;
            });
            if (mailbox.messages.isNotEmpty) _selectMailboxMessage(0);
            return;
          }
          if (_dataSize > kEmailPreviewMaxBytes) {
            throw const FormatException(
              'Email exceeds the 32 MiB preview limit',
            );
          }
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          final message = parseEmailMessage(data, _expansionName ?? _viewName);
          setState(() {
            _emailMessage = message;
            _preparing = false;
          });
          if (_searchOpen && _searchController.text.isNotEmpty) {
            unawaited(_runSearch(_searchController.text));
          }
          return;
        case ViewerMode.office:
          setState(() => _preparing = true);
          final kind = _browserDocumentKind;
          if (kind != null && kind != DocumentPreviewKind.xml) {
            final data = await _readDocumentBytes(
              documentPreviewByteLimit(kind),
              token,
            );
            if (!mounted || token != _prepareToken || data == null) return;
            setState(() {
              _documentPreviewBytes = data;
              _preparing = false;
            });
            return;
          }
          final data = await _ensureFullData();
          if (!mounted || token != _prepareToken) return;
          final document = await parseOfficeDocument(
            data,
            _expansionName ?? _viewName,
          );
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
              _richError =
                  'This font is too large to preview safely '
                  '(${formatBytes(data.length)}).';
            });
            return;
          }
          setState(() => _preparing = false);
          return;
        case ViewerMode.pdf:
          setState(() => _preparing = true);
          final localPath = _nativeViewPath;
          PdfDocument? doc;
          bool streamAccess = false;
          LocalFileService? localSvc;
          if (localPath != null) {
            localSvc = _spool == null
                ? ref.read(localFileServiceProvider)
                : null;
            // Keep the security-scoped access open until the document is
            // closed; PdfDocument reads from the path lazily.
            final acquired =
                localSvc == null || await localSvc.beginStreamAccess(localPath);
            if (!mounted || token != _prepareToken) {
              if (acquired) await localSvc?.endStreamAccess();
              return;
            }
            if (acquired) {
              try {
                doc = await PdfDocument.openFile(localPath);
                streamAccess = localSvc != null;
              } catch (e, st) {
                _log.warn('PdfDocument.openFile failed; using bytes', e, st);
                await localSvc?.endStreamAccess();
              }
            }
          }
          if (doc == null) {
            final data = await _ensureFullData();
            if (!mounted || token != _prepareToken) return;
            doc = await PdfDocument.openData(data);
          }
          if (!mounted || token != _prepareToken) {
            unawaited(doc.close().catchError((Object _) {}));
            if (streamAccess) {
              unawaited(localSvc!.endStreamAccess().catchError((Object _) {}));
            }
            return;
          }
          _pdfDoc = doc;
          _pdfStreamAccess = streamAccess;
          _pdfController = PdfController(document: Future.value(doc));
          setState(() => _preparing = false);
          return;
        case ViewerMode.media:
          setState(() => _preparing = true);
          final nativePath = _nativeViewPath;
          if (nativePath != null) {
            await _prepareMediaFile(nativePath, token);
          } else {
            final data = await _ensureFullData();
            if (!mounted || token != _prepareToken) return;
            await _prepareMedia(data, token);
          }
          if (!mounted || token != _prepareToken) return;
          setState(() => _preparing = false);
          return;
        case ViewerMode.archive:
          setState(() => _preparing = true);
          await _openArchive(token);
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

  Future<Uint8List?> _readDocumentBytes(int maxBytes, int token) async {
    final source = _source;
    if (source == null) return null;
    final loadToken = _loadToken;
    return readDocumentPreviewSource(
      source,
      maxBytes: maxBytes,
      isCurrent: () =>
          mounted &&
          token == _prepareToken &&
          loadToken == _loadToken &&
          identical(source, _source),
    );
  }

  void _selectMailboxMessage(int index) {
    final mailbox = _mailbox;
    if (mailbox == null || index < 0 || index >= mailbox.messages.length) {
      return;
    }
    _searchDebounce?.cancel();
    _resetSearchResults();
    _emailSearchSource?.dispose();
    _emailSearchSource = null;
    _emailSearchPreparation = null;
    _emailSearchLimited = false;
    _emailSearchLimitShown = false;
    _emailLines = null;
    _emailLineStarts = null;
    EmailMessageDocument? message;
    MboxMessageError? error;
    try {
      message = mailbox.parseMessage(index);
    } on MboxMessageException catch (failure) {
      error = failure.code;
    }
    setState(() {
      _mailboxIndex = index;
      _emailMessage = message;
      _mailboxMessageError = error;
    });
    if (_searchOpen && _searchController.text.isNotEmpty) {
      unawaited(_runSearch(_searchController.text));
    }
  }

  void _openEmailAttachment(EmailAttachment attachment) {
    final bytes = attachment.bytes;
    if (bytes == null) return;
    unawaited(
      showInternalViewer(
        context,
        file: widget.file,
        side: widget.side,
        bytesOverride: bytes,
        displayName: attachment.name,
      ),
    );
  }

  Future<void> _loadXmlTools() async {
    if (_documentPreviewBytes != null || _xmlToolsLoading) return;
    final token = _prepareToken;
    setState(() {
      _xmlToolsLoading = true;
      _xmlToolsError = null;
    });
    try {
      final bytes = await _readDocumentBytes(
        documentPreviewByteLimit(DocumentPreviewKind.xml),
        token,
      );
      if (!mounted || token != _prepareToken) return;
      setState(() => _documentPreviewBytes = bytes);
    } catch (error) {
      if (!mounted || token != _prepareToken) return;
      setState(() => _xmlToolsError = _describeError(error));
    } finally {
      if (mounted && token == _prepareToken) {
        setState(() => _xmlToolsLoading = false);
      }
    }
  }

  Future<void> _loadNativePpt() async {
    final bytes = _documentPreviewBytes;
    if (bytes == null || _officeDoc != null) return;
    final token = _prepareToken;
    try {
      final document = await parseOfficeDocument(
        bytes,
        _expansionName ?? _viewName,
      );
      if (!mounted || token != _prepareToken) return;
      setState(() {
        _officeDoc = document;
        _officeView = _OfficeView.text;
        _nativePptError = null;
      });
    } catch (error) {
      if (!mounted || token != _prepareToken) return;
      setState(() => _nativePptError = _describeError(error));
    }
  }

  Widget _documentPreview(
    Uint8List bytes,
    DocumentPreviewKind kind,
    ThemeData theme,
  ) {
    return DocumentPreview(
      key: ValueKey((_loadToken, _prepareToken, kind)),
      bytes: bytes,
      filename: _expansionName ?? _viewName,
      kind: kind,
      locale: Localizations.localeOf(context).toLanguageTag(),
      dark: theme.brightness == Brightness.dark,
      fontScale: _zoom,
      onShowSource: () => _selectMode(ViewerMode.text),
    );
  }

  void _disposeModeResources({ViewerSpool? spool}) {
    // Revoke borrowed readers immediately, before disposing the viewer source.
    // This also cancels readers still opening or waiting for a password.
    for (final source in _archiveSources) {
      unawaited(source.close());
    }
    _archiveSources.clear();
    _archiveSource = null;
    _emailMessage = null;
    _mailbox = null;
    _mailboxMessageError = null;
    _documentPreviewBytes = null;
    _emailSearchSource?.dispose();
    _emailSearchSource = null;
    _emailSearchPreparation = null;
    _emailSearchLimited = false;
    _emailSearchLimitShown = false;
    _emailLines = null;
    _emailLineStarts = null;
    final pdf = _pdfController;
    _pdfController = null;
    final doc = _pdfDoc;
    _pdfDoc = null;
    final releasePdfStream = _pdfStreamAccess;
    _pdfStreamAccess = false;
    final pdfLocalService = releasePdfStream
        ? ref.read(localFileServiceProvider)
        : null;
    final mediaAccess = _mediaStreamAccess;
    _mediaStreamAccess = false;
    final mediaLocal = mediaAccess ? ref.read(localFileServiceProvider) : null;
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
      if (doc != null) {
        try {
          await doc.close();
        } catch (_) {
          // Best effort.
        }
      }
      if (releasePdfStream) {
        try {
          await pdfLocalService?.endStreamAccess();
        } catch (_) {
          // Best effort.
        }
      }
      if (video != null) {
        try {
          await video.dispose();
        } catch (_) {
          // Best effort.
        }
      }
      if (mediaAccess) {
        try {
          await mediaLocal?.endStreamAccess();
        } catch (_) {}
      }
      if (archive != null) await archive.close();
      if (spool != null) {
        try {
          await spool.close();
        } catch (_) {}
      }
      if (blobUrl != null && kIsWeb) html.Url.revokeObjectUrl(blobUrl);
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

  ArchiveViewerSource _borrowArchiveSource(
    ViewBytesSource source,
    int prepareToken,
    int loadToken,
    String name,
  ) {
    final borrowed = ArchiveViewerSource(
      source,
      name: name,
      isCurrent: () =>
          mounted &&
          _mode == ViewerMode.archive &&
          prepareToken == _prepareToken &&
          loadToken == _loadToken &&
          identical(_source, source),
    );
    _archiveSources.add(borrowed);
    return borrowed;
  }

  void _releaseArchiveSource(ArchiveViewerSource? source) {
    if (source == null) return;
    _archiveSources.remove(source);
    unawaited(source.close());
  }

  Future<({ViewerArchive archive, ArchiveViewerSource source})>
  _openArchiveHandle(
    ViewBytesSource source, {
    required int prepareToken,
    required int loadToken,
    required String name,
    required bool Function() isCurrent,
    String? password,
  }) async {
    var borrowed = _borrowArchiveSource(source, prepareToken, loadToken, name);
    var retained = false;
    try {
      ViewerArchive archive;
      final streamed =
          !kIsWeb &&
          widget.bytesOverride == null &&
          _expansionName == null &&
          isStreamedArchiveViewerName(name) &&
          matchesStreamedArchiveViewerSignature(
            name,
            await borrowed.read(0, source.size < 8 ? source.size : 8),
          );
      if (streamed) {
        try {
          archive = (await openStreamedArchiveSource(
            borrowed,
            name: name,
            password: password,
            isCancelled: () => !isCurrent(),
            inspectIsoForRewrite: false,
          )).archive;
          // Preservation restrictions govern edits, not F3's read-only view.
        } on ArchiveViewException catch (error) {
          if (!useBoundedArchiveViewerFallback(error)) rethrow;
          // Failed readers own and close their adapter. The viewer still owns
          // the underlying file and its access grant; fallback must borrow it
          // again so password retries never reuse a closed adapter.
          _releaseArchiveSource(borrowed);
          if (!isCurrent()) {
            throw const ArchiveViewException('Archive opening was cancelled.');
          }
          borrowed = _borrowArchiveSource(
            source,
            prepareToken,
            loadToken,
            name,
          );
          archive = await openViewerArchiveSource(
            borrowed,
            name: name,
            password: password,
          );
        }
      } else {
        archive = await openViewerArchiveSource(
          borrowed,
          name: name,
          password: password,
        );
      }
      retained = true;
      return (archive: archive, source: borrowed);
    } finally {
      if (!retained) _releaseArchiveSource(borrowed);
    }
  }

  Future<void> _openArchive(int token) async {
    final source = _source;
    if (source == null) {
      throw const ArchiveViewException('The archive source is unavailable.');
    }
    final loadToken = _loadToken;
    final name = _expansionName ?? _viewName;
    bool current() =>
        mounted &&
        token == _prepareToken &&
        loadToken == _loadToken &&
        identical(_source, source) &&
        _mode == ViewerMode.archive;
    var password = _archivePassword;
    var passwordWasRequired = false;
    // The first open discovers header encryption; allow three submitted
    // passwords after that probe, without prompting for an unused attempt.
    for (var attempt = 0; attempt <= 3; attempt++) {
      if (!mounted || !current()) return;
      ArchiveViewerSource? borrowed;
      var accepted = false;
      try {
        final opened = await _openArchiveHandle(
          source,
          prepareToken: token,
          loadToken: loadToken,
          name: name,
          isCurrent: current,
          password: password,
        );
        borrowed = opened.source;
        final handle = opened.archive;
        if (!mounted || !current()) {
          await handle.close();
          return;
        }
        final previous = _archive;
        final previousSource = _archiveSource;
        setState(() {
          _archive = handle;
          _archiveSource = borrowed;
          _archiveMembers = handle.members;
          _archivePassword = password;
          _preparing = false;
        });
        accepted = true;
        _releaseArchiveSource(previousSource);
        if (previous != null) unawaited(previous.close());
        return;
      } on ArchivePasswordRequiredException catch (e) {
        if (!mounted || !current()) return;
        passwordWasRequired = true;
        if (attempt == 3) break;
        setState(() => _preparing = false);
        if (e.wrongPassword) {
          _showSnack(InternalViewerStrings(context).text('incorrectPassword'));
        }
        final entered = await _promptArchivePassword(wrong: e.wrongPassword);
        if (!mounted || !current()) return;
        if (entered == null) {
          setState(
            () => _richError = InternalViewerStrings(context).text('protected'),
          );
          return;
        }
        password = entered;
        setState(() => _preparing = true);
      } on ArchiveViewException catch (e) {
        if (!mounted || !current()) return;
        // Encrypted 7z headers have no separate password verifier: a bad
        // password can surface as a decoded-header CRC error. Offer a retry
        // only after this opening has actually requested a password. Limits
        // and other failures must retain their original error handling.
        if (passwordWasRequired &&
            password != null &&
            e.code == ArchiveMessageCode.corrupt) {
          if (attempt == 3) break;
          setState(() => _preparing = false);
          final entered = await _promptArchivePassword(
            wrong: true,
            possiblyCorrupt: true,
          );
          if (!mounted || !current()) return;
          if (entered == null) {
            setState(
              () => _richError = localizedArchiveViewerError(context, e),
            );
            return;
          }
          password = entered;
          setState(() => _preparing = true);
          continue;
        }
        setState(() {
          _preparing = false;
          _richError = localizedArchiveViewerError(context, e);
        });
        return;
      } finally {
        if (!accepted) _releaseArchiveSource(borrowed);
      }
    }
    if (!mounted || !current()) return;
    setState(() {
      _preparing = false;
      _richError = InternalViewerStrings(context).text('tooMany');
    });
  }

  Future<void> _prepareMediaFile(String path, int token) async {
    final local = _spool == null ? ref.read(localFileServiceProvider) : null;
    if (local != null && !await local.beginStreamAccess(path)) {
      throw FileBytesLoadException('Access to "$path" was not granted.');
    }
    final candidate = VideoPlayerController.file(File(path));
    var retained = false;
    try {
      await candidate.initialize();
      if (!mounted || token != _prepareToken) return;
      _videoController = candidate;
      _mediaStreamAccess = local != null;
      retained = true;
    } finally {
      if (!retained) {
        await candidate.dispose();
        await local?.endStreamAccess();
      }
    }
  }

  Future<void> _prepareMedia(Uint8List data, int token) async {
    final mediaGone = InternalViewerStrings(context).text('mediaGone');
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
        lastError = FileSystemException(mediaGone, path);
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
          StateError(InternalViewerStrings(context).text('mediaUnavailable'));
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
      encoding: _encodingOverride ?? _tailEncoding,
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
    final offsetMode =
        _mode == ViewerMode.hex || (_isStreamed && _mode != ViewerMode.email);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: offsetMode
            ? InternalViewerStrings(context).text('goOffset')
            : InternalViewerStrings(context).text('goLine'),
        hintText: offsetMode
            ? InternalViewerStrings(context).text('offsetHint')
            : InternalViewerStrings(context).text('lineNumber'),
        confirmLabel: InternalViewerStrings(context).text('go'),
      ),
    );
    final text = result?.trim() ?? '';
    if (text.isEmpty) return;

    if (offsetMode) {
      final offset = _parseOffset(text, defaultRadix: 10);
      if (offset == null || offset < 0) return;
      if (_mode == ViewerMode.hex) {
        _scrollToRow(offset ~/ _bytesPerLine);
      } else if (_isStreamed) {
        setState(() {
          _streamScrollTo = offset;
          _streamScrollRequest++;
        });
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

  Future<String?> _promptArchivePassword({
    required bool wrong,
    bool possiblyCorrupt = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: possiblyCorrupt
            ? localizedArchiveViewerError(
                context,
                const ArchivePasswordRequiredException(
                  'The password is wrong or the archive is corrupt.',
                  code: ArchiveMessageCode.wrongOrCorrupt,
                  wrongPassword: true,
                ),
              )
            : wrong
            ? InternalViewerStrings(context).text('wrongPassword')
            : InternalViewerStrings(context).text('passwordRequired'),
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

  void _resetSearchResults({bool cancel = true}) {
    if (cancel) {
      _searchGeneration++;
      _searchDebounce?.cancel();
    }
    _searching = false;
    _matches = const [];
    _matchEnds = const [];
    _matchIndex = -1;
    _matchBase = 0;
    _totalMatches = 0;
    _nextSearchOffset = null;
    _nextTextOffset = null;
    _searchNote = null;
    _matchHighlightStart = null;
    _matchHighlightEnd = null;
    _structureHighlightStart = null;
    _structureHighlightEnd = null;
    _isByteSearch = false;
    _searchBytes = null;
    _cachedSafeMatchIndex = null;
    _cachedSafeMatchBinary = null;
    _cachedSafeMatchOffset = null;
  }

  void _toggleSearch() {
    _resetSearchResults();
    if (_searchOpen) {
      _searchDebounce?.cancel();
      setState(() {
        _searchOpen = false;
        _searchController.clear();
      });
      return;
    }
    setState(() => _searchOpen = true);
    if (_mode != ViewerMode.text &&
        _mode != ViewerMode.ascii &&
        _mode != ViewerMode.binary &&
        _mode != ViewerMode.hex &&
        _mode != ViewerMode.email) {
      _selectMode(ViewerMode.text);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _resetSearchResults();
      if (_isStreamed && _mode != ViewerMode.email && value.isNotEmpty) {
        _searchNote = 'Press Enter to scan the file';
      }
    });
    if ((_isStreamed && _mode != ViewerMode.email) || value.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch(value);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    _runSearch(value);
  }

  Future<bool> _prepareEmailSearch() {
    if (_emailSearchSource != null) return Future.value(true);
    final message = _emailMessage;
    if (message == null) return Future.value(false);
    return _emailSearchPreparation ??= _buildEmailSearch(
      message,
      _prepareToken,
    );
  }

  Future<bool> _buildEmailSearch(
    EmailMessageDocument message,
    int token,
  ) async {
    final text = message.searchText;
    // Count before splitting or UTF-8 encoding. A small message containing
    // millions of newlines must not allocate two huge line-index arrays just
    // because the user opened its formatted preview.
    var lines = 1;
    var encodedSize = 0;
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == 10) lines++;
      if (unit < 0x80) {
        encodedSize++;
      } else if (unit < 0x800) {
        encodedSize += 2;
      } else if (unit >= 0xd800 &&
          unit <= 0xdbff &&
          index + 1 < text.length &&
          text.codeUnitAt(index + 1) >= 0xdc00 &&
          text.codeUnitAt(index + 1) <= 0xdfff) {
        encodedSize += 4;
        index++;
      } else {
        encodedSize += 3;
      }
      if (lines > _kEmailSearchMaxLines ||
          encodedSize > _kEmailSearchMaxUtf8Bytes) {
        _emailSearchLimited = true;
        return false;
      }
    }
    final source = ViewBytesSource.memory(
      Uint8List.fromList(utf8.encode(text)),
    );
    await source.open();
    if (!mounted ||
        token != _prepareToken ||
        !identical(message, _emailMessage)) {
      source.dispose();
      return false;
    }
    setState(() {
      _emailSearchSource = source;
      _emailLines = _splitDisplayLines(text);
      _emailLineStarts = _lineStartsOf(text);
    });
    return true;
  }

  Future<void> _runSearch(
    String raw, {
    int startOffset = 0,
    int startTextOffset = 0,
    int skipMatches = 0,
    int matchBase = 0,
    bool selectLast = false,
  }) async {
    if (!mounted) return;
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final emailMode = _mode == ViewerMode.email;
    final textMode = _mode == ViewerMode.text || emailMode;
    // Spaces and strings beginning with "0x" remain literal in Text mode.
    final query =
        _mode == ViewerMode.hex ||
            (!textMode && raw.trimLeft().toLowerCase().startsWith('0x'))
        ? raw.trim()
        : raw;
    setState(() => _resetSearchResults(cancel: false));
    if (query.isEmpty) return;
    if (emailMode && !await _prepareEmailSearch()) {
      if (!mounted || generation != _searchGeneration) return;
      if (_emailSearchLimited) {
        final note = EmailViewerStrings(context).text('searchLimit');
        setState(() => _searchNote = note);
        if (!_emailSearchLimitShown) {
          _emailSearchLimitShown = true;
          _showSnack(note);
        }
      }
      return;
    }
    if (!mounted || generation != _searchGeneration) return;
    final source = emailMode ? _emailSearchSource : _source;
    if (source == null) return;
    try {
      String? encoding;
      if (emailMode) {
        encoding = 'utf8';
      } else if (textMode) {
        if (!source.isStreamed) _ensureText();
        encoding =
            _encodingOverride ??
            (!source.isStreamed ? _encoding : null) ??
            viewerSourceEncoding(source);
      }
      final pattern = textMode ? null : _patternFor(query);
      setState(() {
        _isByteSearch = !textMode || source.isStreamed;
        _searchBytes = pattern;
        _searching = true;
        _searchBytesScanned = startOffset;
      });
      bool cancelled() =>
          !mounted ||
          generation != _searchGeneration ||
          !identical(emailMode ? _emailSearchSource : _source, source);
      void checkSource() {
        if (_origin?.isCurrent == false) {
          throw StateError('The viewed source is unavailable.');
        }
      }

      void progress(int bytes, int total) {
        if (!cancelled()) setState(() => _searchBytesScanned = bytes);
      }

      final result = textMode
          ? await searchViewerText(
              source,
              query,
              encoding: encoding!,
              caseSensitive: _matchCase,
              skipBom: _encodingOverride == null,
              maximumOffsets: _kSearchMaxMatches,
              startOffset: startOffset,
              startTextOffset: startTextOffset,
              skipMatches: skipMatches,
              isCancelled: cancelled,
              checkSource: checkSource,
              onProgress: progress,
            )
          : await searchViewerBytes(
              source,
              pattern!,
              maximumOffsets: _kSearchMaxMatches,
              startOffset: startOffset,
              skipMatches: skipMatches,
              isCancelled: cancelled,
              checkSource: checkSource,
              onProgress: progress,
            );
      if (cancelled()) return;
      final characterOffsets = textMode && !source.isStreamed;
      final found = characterOffsets ? result.textOffsets : result.offsets;
      final ends = characterOffsets ? result.textEndOffsets : result.endOffsets;
      final total = startOffset == 0
          ? result.totalMatches
          : matchBase + result.totalMatches;
      setState(() {
        _matches = found;
        _matchEnds = ends;
        _matchIndex = found.isEmpty
            ? -1
            : selectLast
            ? found.length - 1
            : 0;
        _matchBase = matchBase;
        _totalMatches = total;
        _nextSearchOffset = result.nextOffset;
        _nextTextOffset = result.nextTextOffset;
        _searchNote = total > found.length && found.isNotEmpty
            ? context.commanderTr("Showing matches {0}–{1} of {2}", [
                matchBase + 1,
                matchBase + found.length,
                total,
              ])
            : context.commanderTr("Searched entire file ({0})", [
                formatBytes(source.size),
              ]);
      });
      if (_matchIndex >= 0) _navigateToMatch();
    } on ViewerSearchCancelled {
      // The action that invalidated this scan has already cleared its results.
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _resetSearchResults(cancel: false);
          _searchNote = '$error';
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
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

  void _gotoMatch(int step) {
    if (_searching || _matches.isEmpty) return;
    final next = _matchIndex + step;
    if (next >= 0 && next < _matches.length) {
      setState(() => _matchIndex = next);
      _navigateToMatch();
      return;
    }
    if (_totalMatches <= _matches.length) {
      setState(() => _matchIndex = next < 0 ? _matches.length - 1 : 0);
      _navigateToMatch();
      return;
    }
    if (step > 0 &&
        _matchBase + _matches.length < _totalMatches &&
        _nextSearchOffset != null) {
      unawaited(
        _runSearch(
          _searchController.text,
          startOffset: _nextSearchOffset!,
          startTextOffset: _nextTextOffset ?? 0,
          matchBase: _matchBase + _matches.length,
        ),
      );
      return;
    }
    // Previous/last pages rescan with a bounded result index instead of keeping
    // every earlier match in memory. Forward pages resume at their exact cursor.
    final base = step > 0
        ? 0
        : _matchBase > 0
        ? (_matchBase - _kSearchMaxMatches).clamp(0, _totalMatches)
        : ((_totalMatches - 1) ~/ _kSearchMaxMatches) * _kSearchMaxMatches;
    unawaited(
      _runSearch(
        _searchController.text,
        skipMatches: base,
        matchBase: base,
        selectLast: step < 0,
      ),
    );
  }

  void _navigateToMatch() {
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return;
    final offset = _matches[_matchIndex];

    if (_isByteSearch) {
      final end = _matchEnds.length > _matchIndex
          ? _matchEnds[_matchIndex]
          : offset + 1;
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
    if (_mode == ViewerMode.email) {
      final starts = _emailLineStarts;
      if (starts != null) _scrollToRow(_lineIndexOfOffset(starts, offset));
      return;
    }
    if (_isStreamed) {
      setState(() {
        _streamScrollTo = offset;
        _streamScrollRequest++;
      });
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

  Future<void> _showBinaryStructure() async {
    final source = _source;
    if (source == null || _mode != ViewerMode.hex || _inspectingStructure) {
      return;
    }
    final loadToken = _loadToken;
    final prepareToken = _prepareToken;
    bool current() =>
        mounted &&
        identical(_source, source) &&
        loadToken == _loadToken &&
        prepareToken == _prepareToken &&
        _mode == ViewerMode.hex;

    setState(() => _inspectingStructure = true);
    try {
      final analysis = await inspectBinaryStructureSource(source);
      if (!mounted || !current()) return;
      final field = await showDialog<BinaryStructureField>(
        context: context,
        builder: (_) => BinaryStructureDialog(
          analysis: analysis,
          filename: _expansionName ?? _viewName,
        ),
      );
      if (!current() || field == null) return;
      await source.validateUnchanged();
      if (!current()) return;
      setState(() {
        _resetSearchResults();
        _searchOpen = false;
        _searchController.clear();
        _selectedByte = field.start;
        _structureHighlightStart = field.start;
        _structureHighlightEnd = field.end;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current()) _scrollToRow(field.start ~/ _bytesPerLine);
      });
    } catch (error, stack) {
      _log.warn('Binary header inspection failed', error, stack);
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(BinaryStructureStrings(context).text('readError')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _inspectingStructure = false);
    }
  }

  void _reload({ViewerMode? preferredMode}) {
    _resetSearchResults();
    _tailTimer?.cancel();
    _tailEnabled = false;
    _tailService = null;
    _tailEncoding = null;
    ++_prepareToken;
    ++_loadToken;
    _disposeModeResources(spool: _spool);
    _spool = null;
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
    _downloadedBytes = 0;
    _downloadTotal = null;
    unawaited(_initialLoad(preferredMode: preferredMode));
  }

  void _toggleTail() {
    _resetSearchResults();
    if (_tailEnabled) {
      _reload();
      return;
    }
    try {
      final backend = _capturedBackend();
      _tailService = ViewerTailService(backend, widget.file);
      ++_loadToken;
      ++_prepareToken;
      _disposeModeResources(spool: _spool);
      _spool = null;
      _source?.dispose();
      _source = null;
      _fullData = null;
      _searchController.clear();
      setState(() {
        _tailEnabled = true;
        _loading = true;
        _error = null;
      });
      unawaited(_pollTail());
      _tailTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_pollTail()),
      );
    } catch (error) {
      _showSnack('$error');
    }
  }

  Future<void> _pollTail() async {
    if (_tailLoading || !_tailEnabled) return;
    _tailLoading = true;
    final service = _tailService;
    try {
      final sample = await service!.read(
        isCancelled: () => !mounted || !_tailEnabled || service != _tailService,
        encodingOverride: _encodingOverride,
      );
      if (!mounted || !_tailEnabled || service != _tailService) return;
      await _useMemorySource(sample.bytes);
      _decodedText = null;
      _lineStarts = null;
      _displayLines = null;
      _safeText = null;
      _safeLines = null;
      _safeStarts = null;
      _safeBinary = null;
      _matches = const [];
      _matchIndex = -1;
      _matchHighlightStart = null;
      _matchHighlightEnd = null;
      _tailEncoding = sample.offset > 0 ? sample.encoding : null;
      _ensureText();
      setState(() {
        _loading = false;
        _mode = ViewerMode.text;
        _richError = null;
        _viewNote = context.commanderTr("Following bytes {0}–{1}", [
          sample.offset,
          sample.totalBytes,
        ]);
        if (sample.replacedOrTruncated) {
          _viewNote =
              '$_viewNote · ${context.commanderTr("File replaced or truncated")}';
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tailEnabled && _vScroll.hasClients) {
          _vScroll.jumpTo(_vScroll.position.maxScrollExtent);
        }
      });
    } catch (error) {
      if (!mounted || !_tailEnabled || service != _tailService) return;
      _tailTimer?.cancel();
      setState(() {
        _tailEnabled = false;
        _loading = false;
        _error = '$error';
      });
    } finally {
      _tailLoading = false;
    }
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
    if (_mode == ViewerMode.office &&
        _documentPreviewBytes != null &&
        !_documentTextFallback) {
      _showSnack(DocumentViewerStrings(context).text('selectToCopy'));
      return;
    }
    String? text;
    if (_mode == ViewerMode.email) {
      text = _emailMessage?.searchText;
    } else if (_mode == ViewerMode.lyrics) {
      text = _lrcDocument?.source;
    } else if (_mode == ViewerMode.ascii || _mode == ViewerMode.binary) {
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
      text = _mode == ViewerMode.office && _officeDoc != null
          ? _localizedOfficeText(_officeDoc!)
          : _decodedText ?? _richText;
      if (text == null) {
        try {
          final data = await _ensureFullData();
          text = InternalViewerService.decodeTextForView(
            data,
            encoding: _encodingOverride,
          ).text;
        } catch (e) {
          if (!mounted) return;
          _showSnack(InternalViewerStrings(context).withNumber('copyError', e));
          return;
        }
      }
    }
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      _showSnack(InternalViewerStrings(context).text('nothingCopy'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showSnack(
      InternalViewerStrings(context).withNumber('copied', text.length),
    );
  }

  Future<void> _testArchiveIntegrity() async {
    final source = _source;
    final prepareToken = _prepareToken, loadToken = _loadToken;
    bool sameViewer() =>
        mounted &&
        _mode == ViewerMode.archive &&
        prepareToken == _prepareToken &&
        loadToken == _loadToken &&
        identical(_source, source);
    var handle = _archive;
    if (handle == null || handle.isClosed) return;
    if (_archivePassword == null) {
      final encrypted = handle.members.where(
        (member) =>
            member.isEncrypted &&
            member.isFile &&
            !member.isSpecial &&
            !member.pathEscapedRoot,
      );
      if (encrypted.isNotEmpty) {
        final unlocked = await _unlockArchiveEntry(
          encrypted.first,
          wrong: false,
        );
        if (!sameViewer() || unlocked == null) return;
        handle = _archive;
      }
    }
    if (!mounted || !sameViewer() || handle == null || handle.isClosed) return;
    final captured = handle;
    await showArchiveIntegrityDialog(
      context,
      archive: captured,
      displayName: _expansionName ?? _viewName,
      isCurrent: () => sameViewer() && identical(_archive, captured),
    );
  }

  Future<void> _openArchiveMember(ViewerArchiveMember member) async {
    final initial = _archive;
    if (initial == null) return;
    final source = _source;
    final prepareToken = _prepareToken, loadToken = _loadToken;
    ViewerArchive handle = initial;
    var target = member;
    bool sameViewer() =>
        mounted &&
        _mode == ViewerMode.archive &&
        prepareToken == _prepareToken &&
        loadToken == _loadToken &&
        identical(_source, source);
    bool current() =>
        sameViewer() && identical(_archive, handle) && !handle.isClosed;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || !current()) return;
      try {
        final bytes = await handle.readMember(target);
        if (!mounted || !current()) return;
        await showInternalViewer(
          context,
          file: widget.file,
          side: widget.side,
          bytesOverride: bytes,
          displayName: target.name,
        );
        return;
      } on ArchivePasswordRequiredException catch (e) {
        if (!mounted || !current()) return;
        final unlocked = await _unlockArchiveEntry(
          target,
          wrong: e.wrongPassword || _archivePassword != null,
        );
        if (!mounted || !sameViewer()) return;
        final reopened = _archive;
        if (unlocked == null ||
            reopened == null ||
            reopened.isClosed ||
            unlocked.index >= reopened.members.length ||
            !identical(reopened.members[unlocked.index], unlocked)) {
          return;
        }
        handle = reopened;
        target = unlocked;
      } on ArchiveViewException catch (e) {
        if (!mounted || !current()) return;
        _showSnack(localizedArchiveViewerError(context, e));
        return;
      } catch (e, st) {
        if (!mounted || !current()) return;
        _log.warn('archive member open failed', e, st);
        _showSnack(InternalViewerStrings(context).withNumber('openError', e));
        return;
      }
    }
    if (mounted && current()) {
      _showSnack(InternalViewerStrings(context).text('encryptedEntry'));
    }
  }

  Future<ViewerArchiveMember?> _unlockArchiveEntry(
    ViewerArchiveMember member, {
    required bool wrong,
  }) async {
    final previous = _archive;
    final source = _source;
    final prepareToken = _prepareToken, loadToken = _loadToken;
    final name = _expansionName ?? _viewName;
    if (previous == null ||
        source == null ||
        member.index < 0 ||
        member.index >= previous.members.length ||
        !identical(previous.members[member.index], member)) {
      return null;
    }
    bool current() =>
        mounted &&
        _mode == ViewerMode.archive &&
        prepareToken == _prepareToken &&
        loadToken == _loadToken &&
        identical(_source, source) &&
        identical(_archive, previous) &&
        !previous.isClosed;
    final entered = await _promptArchivePassword(wrong: wrong);
    if (!mounted || entered == null || !current()) return null;
    ArchiveViewerSource? borrowed;
    var accepted = false;
    try {
      final opened = await _openArchiveHandle(
        source,
        prepareToken: prepareToken,
        loadToken: loadToken,
        name: name,
        isCurrent: current,
        password: entered,
      );
      borrowed = opened.source;
      final reopened = opened.archive;
      if (!mounted || !current()) {
        await reopened.close();
        return null;
      }
      final match = member.index < reopened.members.length
          ? reopened.members[member.index]
          : null;
      if (match == null ||
          match.name != member.name ||
          match.size != member.size ||
          !match.isFile ||
          match.isSpecial ||
          match.pathEscapedRoot ||
          match.isEncrypted != member.isEncrypted) {
        await reopened.close();
        if (mounted && current()) {
          _showSnack(InternalViewerStrings(context).text('entryGone'));
        }
        return null;
      }
      final previousSource = _archiveSource;
      setState(() {
        _archive = reopened;
        _archiveSource = borrowed;
        _archiveMembers = reopened.members;
        _archivePassword = entered;
      });
      accepted = true;
      _releaseArchiveSource(previousSource);
      unawaited(previous.close());
      return match;
    } on ArchivePasswordRequiredException catch (e) {
      if (!mounted || !current()) return null;
      _showSnack(
        InternalViewerStrings(context)
            .text(e.wrongPassword ? 'incorrectPassword' : 'passwordRequired'),
      );
      return null;
    } on ArchiveViewException catch (e) {
      if (!mounted || !current()) return null;
      _showSnack(localizedArchiveViewerError(context, e));
      return null;
    } catch (e, st) {
      if (!mounted || !current()) return null;
      _log.warn('archive entry unlock failed', e, st);
      _showSnack(InternalViewerStrings(context).withNumber('openError', e));
      return null;
    } finally {
      if (!accepted) _releaseArchiveSource(borrowed);
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
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            widget.onPrevious?.call(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            widget.onNext?.call(),
        const SingleActivator(LogicalKeyboardKey.f5): _reload,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _reload,
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (_canEdit) Navigator.of(context).pop(InternalViewerAction.edit);
        },
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
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    64,
                    MediaQuery.sizeOf(context).width - 220,
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.positionLabel != null) ...[
                        IconButton(
                          tooltip: context.commanderTr(
                            "Previous file (Alt+Left)",
                          ),
                          onPressed: widget.onPrevious,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Center(child: Text(widget.positionLabel!)),
                        IconButton(
                          tooltip: context.commanderTr("Next file (Alt+Right)"),
                          onPressed: widget.onNext,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                      IconButton(
                        tooltip: context.commanderTr("Reload (F5)"),
                        onPressed: _loading ? null : _reload,
                        icon: const Icon(Icons.refresh),
                      ),
                      if (!_loading && _error == null) ...[
                        if (widget.bytesOverride == null &&
                            _origin?.isCurrent == true)
                          IconButton(
                            tooltip: _tailEnabled
                                ? context.commanderTr("Stop following")
                                : context.commanderTr("Follow end of file"),
                            onPressed: _toggleTail,
                            icon: Icon(
                              _tailEnabled
                                  ? Icons.pause_circle_outline
                                  : Icons.vertical_align_bottom,
                            ),
                          ),
                        if (isLegacyWordFileName(_viewName) &&
                            widget.bytesOverride == null &&
                            _origin?.isCurrent == true)
                          IconButton(
                            tooltip: LegacyWordConversionStrings(
                              Localizations.localeOf(context),
                            ).title,
                            icon: const Icon(Icons.transform),
                            onPressed: () => showLegacyWordConversionForFile(
                              context,
                              ref,
                              widget.file,
                              widget.side,
                              origin: _origin,
                            ),
                          ),
                        if (_canEdit)
                          IconButton(
                            tooltip: context.commanderTr("Edit (F4)"),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop(InternalViewerAction.edit),
                          ),
                        IconButton(
                          tooltip: InternalViewerStrings(context)
                              .text('search'),
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
                            tooltip: InternalViewerStrings(context)
                                .text('encoding'),
                            icon: const Icon(Icons.text_fields),
                            onSelected: (value) =>
                                _setEncoding(value == 'auto' ? null : value),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'auto',
                                child: Text(
                                  InternalViewerStrings(context).text('auto'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'utf8',
                                child: Text(context.commanderTr("UTF-8")),
                              ),
                              PopupMenuItem(
                                value: 'utf16le',
                                child: Text(context.commanderTr("UTF-16 LE")),
                              ),
                              PopupMenuItem(
                                value: 'utf16be',
                                child: Text(context.commanderTr("UTF-16 BE")),
                              ),
                              PopupMenuItem(
                                value: 'utf32le',
                                child: Text(context.commanderTr("UTF-32 LE")),
                              ),
                              PopupMenuItem(
                                value: 'utf32be',
                                child: Text(context.commanderTr("UTF-32 BE")),
                              ),
                              PopupMenuItem(
                                value: 'latin1',
                                child: Text(context.commanderTr("Latin-1")),
                              ),
                              const PopupMenuItem(
                                value: 'cp437',
                                child: Text('DOS (CP437)'),
                              ),
                              const PopupMenuItem(
                                value: 'windows1252',
                                child: Text('Windows-1252'),
                              ),
                            ],
                          ),
                        PopupMenuButton<String>(
                          tooltip: InternalViewerStrings(context).text('more'),
                          icon: const Icon(Icons.more_vert),
                          onSelected: _onMenuSelected,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'goto',
                              child: Text(
                                InternalViewerStrings(context).text('gotoMenu'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'zoom_in',
                              child: Text(
                                InternalViewerStrings(context).text('zoomIn'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'zoom_out',
                              child: Text(
                                InternalViewerStrings(context).text('zoomOut'),
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'bpl8',
                              child: Text(
                                InternalViewerStrings(context)
                                    .withNumber('hexRows', 8),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'bpl16',
                              child: Text(
                                InternalViewerStrings(context)
                                    .withNumber('hexRows', 16),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'bpl32',
                              child: Text(
                                InternalViewerStrings(context)
                                    .withNumber('hexRows', 32),
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'copy_all',
                              child: Text(
                                InternalViewerStrings(context).text('copyAll'),
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'reload',
                              child: Text(
                                InternalViewerStrings(context).text('reload'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            if (_downloadedBytes > 0)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  context.commanderTr(
                                    "Preparing temporary copy: {0}{1}",
                                    [
                                      formatBytes(_downloadedBytes),
                                      _downloadTotal == null
                                          ? ''
                                          : ' / ${formatBytes(_downloadTotal!)}',
                                    ],
                                  ),
                                ),
                              ),
                            Text(
                              context.commanderTr(
                                "Close or select another file to cancel.",
                              ),
                            ),
                          ],
                        ),
                      )
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
      ViewerMode.lyrics,
      ViewerMode.font,
      ViewerMode.csv,
      ViewerMode.office,
      ViewerMode.email,
      ViewerMode.archive,
    ].where((mode) => mode == _autoMode);

    return Container(
      height: math.max(48, MediaQuery.textScalerOf(context).scale(16) + 40),
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
                  _modeChip(
                    InternalViewerStrings(context).text('text'),
                    ViewerMode.text,
                  ),
                  _modeChip('ASCII', ViewerMode.ascii),
                  _modeChip(
                    InternalViewerStrings(context).text('binary'),
                    ViewerMode.binary,
                  ),
                  _modeChip('Hex', ViewerMode.hex),
                  if (_mode == ViewerMode.hex)
                    IconButton(
                      key: const ValueKey('viewer-binary-structure'),
                      tooltip: BinaryStructureStrings(context).text('inspect'),
                      icon: const Icon(Icons.account_tree_outlined, size: 20),
                      onPressed: _inspectingStructure
                          ? null
                          : () => unawaited(_showBinaryStructure()),
                    ),
                  _modeChip(
                    InternalViewerStrings(context).text('image'),
                    ViewerMode.image,
                  ),
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
                        tooltip: context.commanderTr(
                          "Open in system preview (Quick Look)",
                        ),
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
        label: Text(
          context.commanderTr(label),
          style: const TextStyle(fontSize: 12),
        ),
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
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  Widget _pdfViewToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SegmentedButton<bool>(
        style: _compactButtonStyle,
        segments: [
          ButtonSegment(
            value: false,
            label: Text(context.commanderTr("Pages")),
          ),
          ButtonSegment(value: true, label: Text(context.commanderTr("Text"))),
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
          ButtonSegment(
            value: true,
            label: Text(context.commanderTr("Rendered")),
          ),
          ButtonSegment(
            value: false,
            label: Text(context.commanderTr("Source")),
          ),
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
      child: SegmentedButton<String>(
        style: _compactButtonStyle,
        segments: [
          ButtonSegment(
            value: 'tree',
            label: Text(context.commanderTr("Tree")),
          ),
          ButtonSegment(
            value: 'source',
            label: Text(context.commanderTr("Source")),
          ),
          ButtonSegment(
            value: 'tools',
            label: Text(DocumentViewerStrings(context).text('xmlTools')),
          ),
        ],
        selected: {
          _xmlTools
              ? 'tools'
              : _xmlTree
              ? 'tree'
              : 'source',
        },
        onSelectionChanged: (selection) {
          final value = selection.first;
          setState(() {
            _xmlTools = value == 'tools';
            _xmlTree = value == 'tree';
          });
          if (_xmlTools) unawaited(_loadXmlTools());
        },
      ),
    );
  }

  Widget _officeViewToggle() {
    if (_documentPreviewBytes != null) {
      if (_browserDocumentKind != DocumentPreviewKind.ppt) {
        return const SizedBox.shrink();
      }
      final strings = DocumentViewerStrings(context);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: SegmentedButton<bool>(
          style: _compactButtonStyle,
          segments: [
            ButtonSegment(value: false, label: Text(strings.text('preview'))),
            if (_browserDocumentKind == DocumentPreviewKind.ppt)
              ButtonSegment(
                value: true,
                label: Text(strings.text('nativeText')),
              ),
          ],
          selected: {_documentTextFallback},
          onSelectionChanged: (selection) {
            setState(() => _documentTextFallback = selection.first);
            if (_documentTextFallback) unawaited(_loadNativePpt());
          },
        ),
      );
    }
    final document = _officeDoc;
    if (document == null) return const SizedBox.shrink();
    final lowerName = _viewName.toLowerCase();
    final legacyOffice =
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pps') ||
        lowerName.endsWith('.pot') ||
        lowerName.endsWith('.rtf') ||
        lowerName.endsWith('.doc') ||
        lowerName.endsWith('.dot');
    final options = <_OfficeView>[
      if (document.deck != null) _OfficeView.slides,
      if (!legacyOffice) _OfficeView.pdf,
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
              label: Text(context.commanderTr(_officeViewLabel(option))),
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
    final textSearch = _mode == ViewerMode.text || _mode == ViewerMode.email;
    final total = _totalMatches;
    final position = _matchIndex >= 0 ? '${_matchBase + _matchIndex + 1}' : '0';
    return SizedBox(
      width: math.min(340, MediaQuery.sizeOf(context).width),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('viewer-search-input'),
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _mode == ViewerMode.hex
                      ? InternalViewerStrings(context).text('hexHint')
                      : context.commanderTr(
                          textSearch
                              ? "Search text"
                              : "Search text or 0x… bytes",
                        ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
              ),
            ),
            if (textSearch)
              IconButton(
                key: const ValueKey('viewer-match-case'),
                tooltip: context.commanderTr("Match case"),
                isSelected: _matchCase,
                icon: const Icon(Icons.text_fields, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _matchCase = !_matchCase);
                  _runSearch(_searchController.text);
                },
              ),
            const SizedBox(width: 4),
            Text(
              '$position/$total',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_searching)
              IconButton(
                tooltip: context.commanderTr("Stop search"),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                onPressed: () => setState(() {
                  _resetSearchResults();
                  _searchNote = context.commanderTr("Search cancelled");
                }),
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              tooltip: InternalViewerStrings(context).text('previous'),
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: _searching || _matches.isEmpty
                  ? null
                  : () => _gotoMatch(-1),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              tooltip: InternalViewerStrings(context).text('next'),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: _searching || _matches.isEmpty
                  ? null
                  : () => _gotoMatch(1),
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
          context.commanderTr("Preparing view…"),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_richError != null) return _messagePane(_richError!, theme);

    final source = _source;
    if (source == null) {
      return _messagePane(InternalViewerStrings(context).text('noData'), theme);
    }

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
          highlightRangeStart:
              _structureHighlightStart ??
              (_isByteSearch ? _matchHighlightStart : null),
          highlightRangeEnd:
              _structureHighlightEnd ??
              (_isByteSearch ? _matchHighlightEnd : null),
          onByteTapped: (offset) => setState(() {
            _selectedByte = offset;
            _structureHighlightStart = null;
            _structureHighlightEnd = null;
          }),
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
      case ViewerMode.lyrics:
        final lyrics = _lrcDocument;
        if (lyrics == null) {
          return LrcPreviewUnavailable(
            message: LrcStrings(context).text(switch (_lrcError) {
              LrcSourceError.readLimit => 'limit',
              LrcSourceError.sourceChanged => 'sourceChanged',
              _ => 'readFailed',
            }),
            onShowSource: () => _selectMode(ViewerMode.text),
          );
        }
        return LrcPreview(
          key: const ValueKey('lrc-preview'),
          document: lyrics,
          fontScale: _zoom,
          onShowSource: () => _selectMode(ViewerMode.text),
        );
      case ViewerMode.font:
        final data = _fullData;
        if (data == null) {
          return _messagePane(
            InternalViewerStrings(context).text('fontUnavailable'),
            theme,
          );
        }
        return FontPreview(fontBytes: data, filename: _viewName);
      case ViewerMode.csv:
        return CsvTableView(content: _richText ?? '', filename: _viewName);
      case ViewerMode.office:
        return _buildOfficeBody(theme);
      case ViewerMode.email:
        final mailbox = _mailbox;
        if (mailbox != null) {
          return MboxMessageView(
            document: mailbox,
            selectedIndex: _mailboxIndex,
            message: _emailMessage,
            messageError: _mailboxMessageError,
            onSelectMessage: _selectMailboxMessage,
            onShowSource: () => _selectMode(ViewerMode.text),
            fontScale: _zoom,
            onOpenAttachment: _openEmailAttachment,
            body: _searchOpen && _emailLines != null
                ? _buildEmailSearchBody()
                : null,
          );
        }
        final message = _emailMessage;
        if (message == null) {
          return _messagePane(
            InternalViewerStrings(context).text('noData'),
            theme,
          );
        }
        if (_searchOpen && _emailLines != null) {
          return _buildEmailSearchBody();
        }
        return EmailMessageView(
          message: message,
          fontScale: _zoom,
          onOpenAttachment: _openEmailAttachment,
        );
      case ViewerMode.archive:
        return _buildArchiveList(theme);
      case ViewerMode.unsupported:
        return _messagePane(
          InternalViewerStrings(context).text('previewUnavailable'),
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
          encoding: viewerSourceEncoding(source, override: _encodingOverride),
          fontScale: _zoom,
          controller: _vScroll,
          matchStart: _isByteSearch ? _matchHighlightStart : null,
          matchEnd: _isByteSearch ? _matchHighlightEnd : null,
          scrollToByte: _streamScrollTo,
          scrollRequest: _streamScrollRequest,
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
    if (language != null && text.length <= kVirtualSyntaxMaxChars) {
      return SelectionArea(
        child: SyntaxLineView(
          text: text,
          language: language,
          lines: lines,
          fontScale: _zoom,
          controller: _vScroll,
          activeMatchLine: span?.line,
          activeMatchLocal: span == null ? null : (span.start, span.end),
        ),
      );
    }

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
          scrollRequest: _streamScrollRequest,
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

  Widget _buildEmailSearchBody() {
    final span = _textMatchSpan();
    return SelectionArea(
      child: MonoLineListView(
        lines: _emailLines ?? const [],
        fontScale: _zoom,
        controller: _vScroll,
        activeMatchLine: span?.line,
        activeMatchLocal: span == null ? null : (span.start, span.end),
      ),
    );
  }

  Widget _buildXmlBody(ThemeData theme) {
    if (_xmlTools) {
      if (_xmlToolsError case final error?) return _messagePane(error, theme);
      final data = _documentPreviewBytes;
      if (data == null) return const Center(child: CircularProgressIndicator());
      return _documentPreview(data, DocumentPreviewKind.xml, theme);
    }
    final source = _source!;
    if (source.isStreamed || !_xmlTree) {
      if (source.isStreamed) {
        return StreamingSafeView(
          source: source,
          rawText: true,
          encoding: viewerSourceEncoding(source, override: _encodingOverride),
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
      _showSnack(InternalViewerStrings(context).text('docUnavailable'));
      return;
    }
    try {
      await _systemPreviewService.show(data, _viewName);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        InternalViewerStrings(
          context,
        ).withNumber('previewError', localizedNativePreviewError(context, e)),
      );
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
        _officePdfError = localizedOfficePdfError(context, e);
      });
    }
  }

  Widget _buildOfficeBody(ThemeData theme) {
    final data = _documentPreviewBytes;
    final kind = _browserDocumentKind;
    if (data != null && kind != null && !_documentTextFallback) {
      return _documentPreview(data, kind, theme);
    }
    if (_documentTextFallback && _nativePptError != null) {
      return _messagePane(_nativePptError!, theme);
    }
    final document = _officeDoc;
    if (document == null) {
      return Center(
        child: Text(
          context.commanderTr("Preparing document…"),
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

  String _localizedOfficeText(OfficeDocument document) {
    final locale = Localizations.localeOf(context);
    final strings = OfficePreviewStrings(locale);
    return strings.headings(
      strings.text(document),
      document.textHeadings,
      locale,
    );
  }

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
              context.commanderTr("Laying out pages…"),
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
                    child: Text(context.commanderTr("Retry")),
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
              context.commanderTr("Laying out pages…"),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return PdfPagePanel(controller: controller);
      case _OfficeView.table:
        final csv = document.csv;
        if (csv != null && csv.isNotEmpty) {
          final locale = Localizations.localeOf(context);
          final localized = OfficePreviewStrings(locale)
              .headings(csv, document.csvHeadings, locale);
          return CsvTableView(content: localized, filename: _viewName);
        }
        return _buildOfficeText(document, theme);
      case _OfficeView.formatted:
        final safeHtml = document.safeHtml;
        if (safeHtml != null && safeHtml.length <= _kRichRenderCap) {
          return SelectionArea(
            child: SingleChildScrollView(
              controller: _vScroll,
              padding: const EdgeInsets.all(12),
              child: HtmlWidget(
                safeHtml,
                factoryBuilder: OfficeHtmlWidgetFactory.new,
                textStyle: TextStyle(fontSize: 13 * _zoom, height: 1.45),
                onTapUrl: (_) => true,
              ),
            ),
          );
        }
        if (safeHtml != null) return _buildOfficeText(document, theme);
        final locale = Localizations.localeOf(context);
        final markdown = OfficePreviewStrings(locale)
            .headings(document.markdown, document.markdownHeadings, locale)
            .trim();
        if (markdown.isEmpty) {
          if (document.plainText.trim().isNotEmpty) {
            return _buildOfficeText(document, theme);
          }
          return _messagePane(
            'No readable content found in this document.',
            theme,
          );
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
            InternalViewerStrings(context).text('noRaw'),
            theme,
          );
        }
        return XmlTreeView(xml: raw, fontSize: 12.5 * _zoom);
    }
  }

  Widget _buildOfficeText(OfficeDocument document, ThemeData theme) {
    final full = _localizedOfficeText(document);
    if (full.trim().isEmpty) {
      return _messagePane(InternalViewerStrings(context).text('noText'), theme);
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
          context.commanderTr("Rendering PDF…"),
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
      return Center(
        child: Text(
          context.commanderTr("Extracting text layer…"),
          style: style,
        ),
      );
    }
    final error = _pdfTextError;
    if (error != null) return _messagePane(error, theme);
    final text = _pdfText;
    if (text == null) {
      return Center(
        child: Text(
          context.commanderTr("Extracting text layer…"),
          style: style,
        ),
      );
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
          _pdfTextError = InternalViewerStrings(context).text('pdfUnsupported');
        } else if (text.trim().isEmpty) {
          _pdfTextError = InternalViewerStrings(context).text('pdfNoText');
        } else {
          _pdfText = text;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfTextLoading = false;
        _pdfTextError = InternalViewerStrings(context)
            .withNumber('pdfError', localizedNativePreviewError(context, e));
      });
    }
  }

  Widget _buildImageBody() {
    final data = _fullData;
    if (data == null) {
      return _messagePane(
        InternalViewerStrings(context).text('imageUnavailable'),
        Theme.of(context),
      );
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
                  child: Text(
                    context.commanderTr("Unable to decode this image."),
                  ),
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
          context.commanderTr("Opening archive…"),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final list = files.isEmpty
        ? _messagePane(
            InternalViewerStrings(context).text('emptyArchive'),
            theme,
          )
        : ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final member = files[index];
              final isFile = member.isFile;
              return ListTile(
                dense: true,
                leading: Icon(
                  isFile
                      ? Icons.insert_drive_file_outlined
                      : Icons.folder_outlined,
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
                          message: context.commanderTr(
                            "Path escaped the archive root (sanitized)",
                          ),
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
                enabled: isFile && !member.isSpecial && !member.pathEscapedRoot,
                onTap: isFile && !member.isSpecial && !member.pathEscapedRoot
                    ? () => unawaited(_openArchiveMember(member))
                    : null,
              );
            },
          );
    final notices = _archive?.notices ?? const <String>[];
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              key: const ValueKey('test-archive'),
              onPressed: () => unawaited(_testArchiveIntegrity()),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(archiveIntegrityText(context, 'Test archive')),
            ),
          ),
        ),
        if (notices.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('archive-format-notices'),
            leading: const Icon(Icons.info_outline),
            title: Text(context.commanderTr('Container details')),
            initiallyExpanded: notices.any(
              (notice) =>
                  notice.contains('unavailable') ||
                  notice.contains('No supported filesystem'),
            ),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    notices.join('\n\n'),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        Expanded(child: list),
      ],
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
                    child: Text(context.commanderTr("Hex view")),
                  ),
                  OutlinedButton(
                    onPressed: () => _selectMode(ViewerMode.ascii),
                    child: Text(context.commanderTr("ASCII view")),
                  ),
                  OutlinedButton(
                    onPressed: () => _selectMode(ViewerMode.binary),
                    child: Text(context.commanderTr("Binary view")),
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
    final note = _mode == ViewerMode.office && _officeDoc != null
        ? OfficePreviewStrings(Localizations.localeOf(context))
                  .note(_officeDoc!) ??
              _viewNote
        : _viewNote;
    final style = TextStyle(
      fontSize: 11.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final parts = <String>[
      context.commanderTr(_modeLabelOf(_mode)),
      formatBytes(_dataSize),
      if (_isStreamed) context.commanderTr("Streamed"),
      if (_mode == ViewerMode.hex)
        context.commanderTr("{0} bytes/row", [_bytesPerLine]),
      if (_mode == ViewerMode.archive && _archive != null)
        _archive!.formatName.toUpperCase(),
      if (_mode == ViewerMode.pdf && _pdfShowText && _pdfText != null)
        context.commanderTr("{0} characters", [_pdfText!.length]),
      if (_canChangeEncoding && _encoding != null) _encoding!,
      if (note != null) note,
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
      return context.commanderTr("Offset {0}", [
        '0x${offset.toRadixString(16).toUpperCase().padLeft(8, '0')}',
      ]);
    }
    return context.commanderTr("Line {0}", [row + 1]);
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
    if (_searching) {
      return context.commanderTr("Searching {0} of {1}", [
        formatBytes(_searchBytesScanned),
        formatBytes(
          _mode == ViewerMode.email
              ? (_emailSearchSource?.size ?? 0)
              : _dataSize,
        ),
      ]);
    }
    final base = _matches.isEmpty
        ? context.commanderTr("No matches")
        : '${_matchBase + _matchIndex + 1}/$_totalMatches';
    if (_searchNote == null) return base;
    return '$base (${context.commanderTr(_searchNote!)})';
  }

  // ---------------------------------------------------------------------------
  // Match spans
  // ---------------------------------------------------------------------------

  _MatchSpan? _textMatchSpan() {
    if (!_searchOpen || _isByteSearch) return null;
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return null;
    final starts = _mode == ViewerMode.email ? _emailLineStarts : _lineStarts;
    if (starts == null) return null;
    final offset = _matches[_matchIndex];
    final line = _lineIndexOfOffset(starts, offset);
    final local = offset - starts[line];
    final end = _matchEnds.length > _matchIndex
        ? _matchEnds[_matchIndex]
        : offset + 1;
    return _MatchSpan(line, local, local + end - offset);
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

  String _modeLabelOf(ViewerMode mode) {
    switch (mode) {
      case ViewerMode.text:
        return InternalViewerStrings(context).text('text');
      case ViewerMode.ascii:
        return 'ASCII';
      case ViewerMode.binary:
        return InternalViewerStrings(context).text('binary');
      case ViewerMode.hex:
        return 'Hex';
      case ViewerMode.image:
        return InternalViewerStrings(context).text('image');
      case ViewerMode.markdown:
        return 'Markdown';
      case ViewerMode.html:
        return 'HTML';
      case ViewerMode.xml:
        return 'XML';
      case ViewerMode.pdf:
        return 'PDF';
      case ViewerMode.media:
        return InternalViewerStrings(context).text('media');
      case ViewerMode.lyrics:
        return LrcStrings(context).text('lyrics');
      case ViewerMode.font:
        return InternalViewerStrings(context).text('font');
      case ViewerMode.csv:
        return InternalViewerStrings(context).text('table');
      case ViewerMode.office:
        return 'Office';
      case ViewerMode.email:
        return EmailViewerStrings(context).text('email');
      case ViewerMode.archive:
        return InternalViewerStrings(context).text('archive');
      case ViewerMode.unsupported:
        return InternalViewerStrings(context).text('unsupported');
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
      title: Text(context.commanderTr(widget.title)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        decoration: InputDecoration(
          labelText: widget.label == null
              ? null
              : context.commanderTr(widget.label!),
          hintText: widget.hintText == null
              ? null
              : context.commanderTr(widget.hintText!),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(InternalViewerStrings(context).text('cancel')),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(context.commanderTr(widget.confirmLabel)),
        ),
      ],
    );
  }
}

enum _OfficeView { slides, pdf, formatted, table, text, raw }
