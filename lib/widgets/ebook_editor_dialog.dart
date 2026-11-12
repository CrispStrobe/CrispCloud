import 'dart:async';
import 'dart:convert';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crisperbooks/crisperbooks.dart' show EbookSpeechDialog;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:re_editor/re_editor.dart';

import '../l10n/ebook_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/ebook_annotations.dart';
import '../services/ebook_chapter_reader_controller.dart';
import '../services/ebook_device_export.dart';
import '../services/ebook_edit_session.dart';
import '../services/ebook_editor_menu.dart';
import '../services/ebook_file_store.dart';
import '../services/ebook_library.dart';
import '../services/ebook_reading_data_files.dart';
import '../services/file_bytes_loader.dart';
import '../services/image_edit_session.dart';
import '../services/panel_source_service.dart';
import '../services/pdf_file_store.dart';
import 'image_editor_surface.dart';
import 'ebook_chapter_reader.dart';
import 'ebook_appearance_dialog.dart';
import 'ebook_library_actions.dart';
import 'ebook_reading_data_dialog.dart';
import 'ebook_kindle_metadata_editor.dart';
import 'ebook_prose_editor.dart';
import 'internal_viewer_dialog.dart'
    show InternalViewerAction, InternalViewerDialog;

Future<void> showEbookEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  bool startEditing = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: EbookEditorDialog(
        file: file,
        side: side,
        startEditing: startEditing,
      ),
    ),
  );
  if (context.mounted) {
    try {
      final panel = ref.read(panelProvider(side));
      await panel.refresh();
      panel.restoreCursorAndFocus(file);
    } catch (_) {
      /* The source may have disconnected while the book was open. */
    }
  }
}

typedef EbookReaderBuilder = Widget Function(
  BuildContext context,
  Uint8List bytes,
  String filename,
  CrispEbookController controller,
);

typedef EbookDocumentLoader = Future<EpubDocument> Function(Uint8List bytes);

/// One host for reading and package editing. The reader never receives storage
/// credentials or writes files; only the captured store can update the source.
class EbookEditorDialog extends ConsumerStatefulWidget {
  const EbookEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.startEditing = false,
    this.bytesOverride,
    this.displayName,
    this.origin,
    this.storeOverride,
    this.deviceExporterOverride,
    this.readerBuilderOverride,
    this.documentLoaderOverride,
    this.linuxHostProbeOverride,
    this.readingDataPickerOverride,
    this.readingDataExporterOverride,
    this.onPrevious,
    this.onNext,
    this.positionLabel,
  });
  final FileItem file;
  final PanelSide side;
  final bool startEditing;
  final Uint8List? bytesOverride;
  final String? displayName;
  final PanelFileOrigin? origin;
  final EbookFileStore? storeOverride;
  final EbookDeviceExporter? deviceExporterOverride;
  final EbookReaderBuilder? readerBuilderOverride;
  final EbookDocumentLoader? documentLoaderOverride;
  final Future<EbookLinuxHostStatus> Function()? linuxHostProbeOverride;
  final EbookReadingDataPicker? readingDataPickerOverride;
  final EbookReadingDataExporter? readingDataExporterOverride;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? positionLabel;
  @override
  ConsumerState<EbookEditorDialog> createState() => _EbookEditorDialogState();
}

class _EbookEditorDialogState extends ConsumerState<EbookEditorDialog> {
  final _reader = CrispEbookController();
  final _chapterReader = EbookChapterReaderController();
  final _source = CodeLineEditingController();
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _authors = TextEditingController();
  final _language = TextEditingController();
  final _description = TextEditingController();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  EbookFileStore? _store;
  EbookEditSession? _session;
  EbookAnnotations? _annotations;
  String _annotationIdentity = '';
  EbookLinuxHostStatus? _linuxHost;
  bool _portableReaderRequested = false;
  bool _readingDataBusy = false;
  bool _readingDataPreviewing = false;
  double? _seekFraction;
  EbookLibrary? _library;
  String? _libraryEntryId;
  FileReference? _librarySource;
  String? _libraryContentSha256;
  bool _libraryWriting = false;
  Uint8List? _bytes;
  String? _resource;
  String _sourceBaseline = '';
  String? _error;
  String? _readerError;
  String? _notice;
  String? _sourceWarning;
  String? _searchNotice;
  List<EbookSearchHit> _searchHits = [];
  List<EpubIssue>? _issues;
  EbookBookInfo? _bookInfo;
  EbookSelection? _selection;
  EbookLocation? _location;
  EbookConversionCapabilities? _conversion;
  ProviderContainer? _container;
  EbookEditorMenuActions? _menu;
  Timer? _annotationTimer;
  EbookCancellationToken? _conversionToken;
  int _readerVersion = 0;
  int _previewState = 0;
  int _searchGeneration = 0;
  bool _loading = true;
  bool _editing = false;
  bool _working = false;
  bool _closing = false;
  bool _discardReadingDataOnClose = false;
  bool _allowPop = false;
  bool _metadataDraft = false;
  bool _sourceDraft = false;
  bool _syncing = false;
  bool _showProse = false;
  bool _converted = false;
  bool _searching = false;
  bool _copyDelivered = false;

  String get _name => widget.displayName ?? widget.file.name;
  EpubDocument? get _document => _session?.document;
  bool get _busy =>
      _loading || _working || _readingDataBusy || (_session?.isSaving ?? false);
  bool get _editable => _document?.canEdit ?? false;
  bool get _dirty =>
      _metadataDraft || _sourceDraft || (_session?.isDirty ?? false);
  bool get _canSaveOriginal =>
      _store != null &&
      !_converted &&
      _name.toLowerCase().endsWith('.epub') &&
      _editable;
  String get _exportLabel => kIsWeb ? 'Download a copy' : 'Export a copy';
  String get _epubName =>
      '${p.basenameWithoutExtension(_name)}${_converted ? '-converted' : '-copy'}.epub';
  bool get _canOpenTextFallback =>
      _bytes != null &&
      (_document != null || _name.toLowerCase().endsWith('.epub'));
  bool get _usesChapterReader =>
      widget.readerBuilderOverride == null &&
      (_portableReaderRequested ||
          (!EbookReaderCapabilities.supportsEmbeddedReader &&
              _linuxHost?.available != true));
  EbookReaderRenderer get _renderer => _usesChapterReader
      ? EbookReaderRenderer.portable
      : EbookReaderRenderer.foliate;
  bool get _readerReady =>
      !_busy && (_usesChapterReader ? _chapterReader.isReady : _reader.isReady);
  Future<void> _goToReader(String target) =>
      _usesChapterReader ? _chapterReader.goTo(target) : _reader.goTo(target);
  Future<void> _previousReaderPage() =>
      _usesChapterReader ? _chapterReader.previous() : _reader.previous();
  Future<void> _nextReaderPage() =>
      _usesChapterReader ? _chapterReader.next() : _reader.next();

  @override
  void initState() {
    super.initState();
    _source.addListener(_onSource);
    for (final field in [_title, _authors, _language, _description]) {
      field.addListener(_onMetadata);
    }
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
    _scheduleMenu();
  }

  @override
  void dispose() {
    _annotationTimer?.cancel();
    _conversionToken?.cancel();
    final annotations = _annotations;
    if (annotations != null && !_discardReadingDataOnClose) {
      unawaited(annotations.save().catchError((Object _) {}));
    }
    final container = _container;
    final menu = _menu;
    if (container != null && menu != null) {
      // Do not modify a provider during route teardown/build, and do not clear
      // menus installed by a different editor while this one was closing.
      scheduleMicrotask(() {
        try {
          if (identical(container.read(ebookEditorMenuProvider), menu)) {
            container.read(ebookEditorMenuProvider.notifier).state = null;
          }
        } catch (_) {
          /* The provider scope has closed. */
        }
      });
    }
    _container = null;
    _reader.dispose();
    _chapterReader.dispose();
    _source.dispose();
    _search.dispose();
    _title.dispose();
    _authors.dispose();
    _language.dispose();
    _description.dispose();
    _session?.dispose();
    _library?.dispose();
    super.dispose();
  }

  void _scheduleMenu() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _container == null) return;
    final enabled = <EbookEditorMenuAction>{
      if (!_busy) EbookEditorMenuAction.close,
      if (!_busy && _canSaveOriginal && _dirty) EbookEditorMenuAction.save,
      if (!_busy && _document != null) EbookEditorMenuAction.exportCopy,
      if (!_busy && _document != null && _store != null)
        EbookEditorMenuAction.saveCopy,
      if (!_busy && (_session?.canUndo ?? false)) EbookEditorMenuAction.undo,
      if (!_busy && (_session?.canRedo ?? false)) EbookEditorMenuAction.redo,
    };
    if (_menu != null && setEquals(enabled, _menu!.enabled)) return;
    _menu = EbookEditorMenuActions(perform: _performMenu, enabled: enabled);
    _container!.read(ebookEditorMenuProvider.notifier).state = _menu;
  });

  void _performMenu(EbookEditorMenuAction action) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    switch (action) {
      case EbookEditorMenuAction.save:
        unawaited(_save());
      case EbookEditorMenuAction.saveCopy:
        unawaited(_save(copy: true));
      case EbookEditorMenuAction.exportCopy:
        unawaited(_export());
      case EbookEditorMenuAction.close:
        unawaited(_requestClose());
      case EbookEditorMenuAction.undo:
        _undo();
      case EbookEditorMenuAction.redo:
        _redo();
    }
  }

  EbookFileStore? _captureStore(PanelFileOrigin? origin) {
    if (widget.storeOverride != null) return widget.storeOverride;
    if (widget.bytesOverride != null || origin == null || !origin.isCurrent) {
      return null;
    }
    final source = origin.source;
    if (source is LocalPanelSource) {
      return EbookFileStore(
        PdfFileStore.local(
          service: ref.read(localFileServiceProvider),
          file: widget.file,
          copyExtension: null,
          inputLimitBytes: kEbookInputLimitBytes,
          outputLimitBytes: kEbookOutputLimitBytes,
        ),
      );
    }
    if (source is RemotePanelSource) {
      return EbookFileStore(
        PdfFileStore.remote(
          client: source.client,
          providerName: source.providerName,
          cache: ref.read(fileCacheProvider),
          file: widget.file.path == null
              ? widget.file.copyWith(
                  path: p.posix.join(source.path, widget.file.name),
                )
              : widget.file,
          copyExtension: null,
          inputLimitBytes: kEbookInputLimitBytes,
          outputLimitBytes: kEbookOutputLimitBytes,
          isCurrentAccount: () => mounted && origin.isCurrent,
        ),
      );
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final origin =
          widget.origin ??
          (widget.bytesOverride != null || widget.storeOverride != null
              ? null
              : ref
                    .read(panelProvider(widget.side))
                    .originForOperation(widget.file));
      _store = _captureStore(origin);
      if (widget.bytesOverride == null &&
          origin?.isCurrent == true &&
          origin!.storageReference.persistent) {
        final paths = origin.storageReference.isLocal ? p.context : p.posix;
        final path =
            widget.file.path ??
            paths.join(origin.source.currentPath, widget.file.name);
        if (paths.isAbsolute(path)) {
          _librarySource = FileReference(
            storage: origin.storageReference,
            path: paths.normalize(path),
            objectId: widget.file.uuid,
          );
        }
      }
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.linux &&
          widget.readerBuilderOverride == null) {
        _linuxHost =
            await (widget.linuxHostProbeOverride?.call() ??
                probeEbookLinuxHost());
      }
      final bytes =
          widget.bytesOverride ??
          await (_store?.load() ??
              loadFileBytes(
                ref,
                widget.file,
                widget.side,
                origin: origin,
                capBytes: kEbookInputLimitBytes,
              ));
      if (bytes.length > kEbookInputLimitBytes) {
        throw StateError('Ebooks up to 64 MiB can be opened here.');
      }
      if (!mounted) return;
      // Retain a bounded read-only copy even if the strict editing model cannot
      // open an incomplete EPUB. The legacy extractor has its own archive caps.
      _bytes = Uint8List.fromList(bytes).asUnmodifiableView();
      final document = _name.toLowerCase().endsWith('.epub')
          ? await (widget.documentLoaderOverride?.call(bytes) ??
                compute(_openEpub, bytes))
          : null;
      if (!mounted) return;
      if (document != null) _installDocument(document);
      _annotationIdentity =
          _store?.documentId ??
          '${origin?.storageId ?? 'attachment'}:${widget.file.path ?? _name}';
      _annotations = await EbookAnnotations.open(
        _annotationIdentity,
        bytes,
        renderer: _renderer,
      );
      _libraryContentSha256 = _annotations!.contentSha256;
      try {
        final library = await EbookLibrary.open();
        if (!mounted) {
          library.dispose();
          return;
        }
        _library = library;
        await _recordLibraryBook();
      } catch (error) {
        // A catalog write must not prevent opening the user's book.
        _notice = _message(error);
      }
      if (!mounted) return;
      unawaited(_loadConversionCapabilities());
      setState(() {
        _loading = false;
        _editing = widget.startEditing && _editable;
        if (document != null && !document.canEdit) {
          _notice =
              'This protected or signed book is available for reading only.';
        } else if (widget.startEditing && document == null) {
          _notice = 'Open the book, then convert it to an editable EPUB copy.';
        }
      });
      _scheduleMenu();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
      _scheduleMenu();
    }
  }

  Future<void> _loadConversionCapabilities() async {
    try {
      final capabilities = await KindlingConverter().capabilities();
      if (mounted) setState(() => _conversion = capabilities);
    } catch (_) {
      // An optional conversion runtime must not prevent reading or EPUB edits.
      if (mounted) setState(() => _conversion = null);
    }
  }

  void _installDocument(EpubDocument document, {bool converted = false}) {
    _session?.removeListener(_changed);
    _session?.dispose();
    _session = EbookEditSession(document, copyOnly: converted || _store == null)
      ..addListener(_changed);
    _converted = converted;
    _previewState = 0;
    _syncForms();
    final chapters = document.chapters;
    if (chapters.isNotEmpty) _selectResource(chapters.first.path, apply: false);
  }

  void _syncForms() {
    final document = _document;
    if (document == null) return;
    _syncing = true;
    _title.text = document.title;
    _authors.text = document.authors.join('\n');
    _language.text = document.language;
    _description.text = document.description;
    _metadataDraft = false;
    _syncing = false;
  }

  void _changed() {
    if (!mounted) return;
    if (!_metadataDraft) _syncForms();
    // Metadata/structure tools can edit the resource currently displayed in
    // Source. Refresh clean buffers so a later keystroke cannot restore stale
    // OPF/nav bytes and silently undo those changes. Pending drafts stay intact.
    if (!_sourceDraft && _resource != null) {
      final resource = _document?.resources
          .where((e) => e.path == _resource)
          .firstOrNull;
      if (resource?.isText == true) {
        final canonical = _document!.readText(_resource!);
        if (_source.text != canonical) {
          _syncing = true;
          _sourceBaseline = canonical;
          _source.text = canonical;
          _syncing = false;
        }
      }
    }
    setState(() {
      _issues = null;
      _copyDelivered = false;
    });
    _scheduleMenu();
  }

  void _onSource() {
    if (_syncing || !mounted) return;
    final draft = _source.text != _sourceBaseline;
    if (draft != _sourceDraft) {
      setState(() {
        _sourceDraft = draft;
        _copyDelivered = false;
      });
      _scheduleMenu();
    }
  }

  void _onMetadata() {
    if (_syncing || !mounted || _document == null) return;
    final doc = _document!;
    final draft =
        _title.text != doc.title ||
        _authors.text != doc.authors.join('\n') ||
        _language.text != doc.language ||
        _description.text != doc.description;
    if (_metadataDraft != draft) {
      setState(() {
        _metadataDraft = draft;
        _copyDelivered = false;
      });
      _scheduleMenu();
    }
  }

  bool _applyDrafts() {
    final session = _session;
    if (session == null) return true;
    try {
      if (_sourceDraft && _resource != null) {
        if (utf8.encode(_source.text).length >
            const EpubLimits().maxTextBytes) {
          throw StateError(
            'This resource exceeds the 8 MiB text editing limit.',
          );
        }
        session.mutate((doc) => doc.updateText(_resource!, _source.text));
        _sourceBaseline = _source.text;
        _sourceDraft = false;
      }
      if (_metadataDraft) {
        session.mutate(
          (doc) => doc.updateMetadata(
            title: _title.text.trim(),
            authors: _authors.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            language: _language.text.trim(),
            description: _description.text,
          ),
        );
        _metadataDraft = false;
      }
      _sourceWarning = null;
      _changed();
      return true;
    } catch (error) {
      setState(() => _sourceWarning = _message(error));
      _snack(_message(error));
      return false;
    }
  }

  void _selectResource(String path, {bool apply = true}) {
    if (apply && !_applyDrafts()) return;
    try {
      final doc = _document!;
      final resource = doc.resources.where((e) => e.path == path).firstOrNull;
      _syncing = true;
      _sourceBaseline = resource?.isText == true ? doc.readText(path) : '';
      _source.text = _sourceBaseline;
      _resource = path;
      _sourceDraft = false;
      _sourceWarning = null;
      _syncing = false;
      if (mounted) setState(() {});
    } catch (error) {
      _syncing = false;
      _snack(_message(error));
    }
  }

  void _undo() {
    if (_busy || !_applyDrafts()) return;
    _session?.undo();
    _resyncAfterHistory();
  }

  void _redo() {
    if (_busy || _sourceDraft || _metadataDraft) return;
    _session?.redo();
    _resyncAfterHistory();
  }

  void _resyncAfterHistory() {
    _syncForms();
    final doc = _document!;
    if (_resource != null && doc.resources.any((e) => e.path == _resource)) {
      _selectResource(_resource!, apply: false);
    } else if (doc.chapters.isNotEmpty) {
      _selectResource(doc.chapters.first.path, apply: false);
    }
    _changed();
  }

  Future<void> _setEditing(bool value) async {
    if (_busy || value == _editing) return;
    if (value) {
      setState(() => _editing = true);
      return;
    }
    if (!_applyDrafts()) return;
    final session = _session;
    setState(() => _working = true);
    _scheduleMenu();
    try {
      if (session != null && (_previewState != session.stateId || _converted)) {
        final state = session.stateId;
        final bytes = session.exportBytes();
        _annotationTimer?.cancel();
        await _annotations?.save();
        final annotations = await EbookAnnotations.open(
          '$_annotationIdentity${_converted ? ':converted' : ''}',
          bytes,
          renderer: _renderer,
        );
        if (!mounted) return;
        if (!identical(session, _session) ||
            state != session.stateId ||
            _sourceDraft ||
            _metadataDraft) {
          _snack(
            'Your edits changed while preparing the preview. Open Read again to refresh.',
          );
          return;
        }
        _bytes = bytes;
        _annotations = annotations;
        _previewState = state;
        _readerVersion++;
        _location = null;
        _selection = null;
        _bookInfo = null;
        _searchHits = [];
        _searchGeneration++;
        _searching = false;
      }
      if (mounted) {
        setState(() {
          _readerError = null;
          _editing = false;
        });
      }
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _scheduleMenu();
      }
    }
  }

  Future<bool> _save({bool copy = false}) async {
    if (_busy || _session == null || !_applyDrafts()) return false;
    if (!copy && !_canSaveOriginal) return _export();
    final store = _store;
    if (store == null) return _export();
    String? name;
    if (copy) {
      name = await _askText('Save a copy', 'File name', _epubName);
      if (name == null || !mounted) return false;
      if (!name.toLowerCase().endsWith('.epub')) name = '$name.epub';
    }
    try {
      final state = _session!.stateId;
      final outcome = await _session!.save(
        copy ? (bytes) => store.saveCopy(bytes, name!) : store.save,
      );
      if (!mounted) return false;
      _copyDelivered =
          outcome != EbookSaveOutcome.savedOriginal &&
          state == _session!.stateId &&
          !_sourceDraft &&
          !_metadataDraft;
      _reportOutcome(outcome);
      _scheduleMenu();
      return outcome == EbookSaveOutcome.savedOriginal && !_dirty;
    } catch (error) {
      _snack(_message(error));
      return false;
    }
  }

  Future<bool> _export() async {
    if (_busy || _session == null || !_applyDrafts()) return false;
    setState(() => _working = true);
    _scheduleMenu();
    try {
      final state = _session!.stateId;
      final bytes = _session!.exportBytes();
      final outcome = await (widget.deviceExporterOverride ?? exportEbookCopy)(
        bytes,
        _epubName,
      );
      if (!mounted || outcome == null) return false;
      _copyDelivered =
          state == _session!.stateId && !_sourceDraft && !_metadataDraft;
      _reportOutcome(outcome);
      return false; // A copy never establishes that the original was saved.
    } catch (error) {
      _snack(_message(error));
      return false;
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _scheduleMenu();
      }
    }
  }

  Future<void> _openTextFallback() async {
    if (_busy || !_canOpenTextFallback) return;
    try {
      var bytes = _bytes!;
      var previousPreview = false;
      final snapshot = _document?.snapshot();
      if (snapshot != null) {
        try {
          // Preview drafts on an isolated package. Entering a read-only fallback
          // must not mutate undo history or require an invalid draft to save.
          if (_sourceDraft && _resource != null) {
            snapshot.updateText(_resource!, _source.text);
          }
          if (_metadataDraft) {
            snapshot.updateMetadata(
              title: _title.text.trim(),
              authors: _authors.text
                  .split('\n')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(),
              language: _language.text.trim(),
              description: _description.text,
            );
          }
          // An unchanged package returns its original bytes even when editing
          // validation finds a pre-existing defect. The legacy extractor can
          // still recover text from such books without repairing the source.
          bytes = snapshot.toBytes();
        } catch (_) {
          previousPreview = true;
        }
      }
      // Open the legacy widget directly: showInternalViewer routes EPUB files
      // back to this editor. A snapshot also preserves the captured source and
      // all unsaved drafts while the fallback is on screen.
      final result = await showDialog<InternalViewerAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog.fullscreen(
          child: Column(
            children: [
              if (previousPreview)
                SafeArea(
                  bottom: false,
                  child: _banner(
                    'Showing the last readable version. Your edits are still kept in the editor.',
                  ),
                ),
              Expanded(
                child: InternalViewerDialog(
                  file: widget.file,
                  side: widget.side,
                  bytesOverride: bytes,
                  displayName: _converted ? _epubName : _name,
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted && result == InternalViewerAction.edit && _editable) {
        await _setEditing(true);
      }
    } catch (error) {
      _snack(_message(error));
    }
  }

  void _reportOutcome(EbookSaveOutcome outcome) => _snack(switch (outcome) {
    EbookSaveOutcome.savedOriginal => 'Saved',
    EbookSaveOutcome.savedCopy =>
      'Copy saved. The original has not been updated.',
    EbookSaveOutcome.downloadedCopy =>
      'Download started. Keep the downloaded file before closing.',
  });

  Future<void> _requestClose({VoidCallback? navigate}) async {
    final route = ModalRoute.of(context);
    if (_closing || _busy || route?.isCurrent == false) return;
    _closing = true;
    try {
      if (_dirty || (_converted && !_copyDelivered)) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('ebook-unsaved-dialog'),
            title: Text(context.ebookTr('Unsaved changes')),
            content: Text(
              context.ebookTr(
                _copyDelivered
                    ? 'A separate copy was exported. Close and leave the original unchanged?'
                    : 'Save changes before closing?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.ebookTr('Continue editing')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(
                  context.ebookTr(_copyDelivered ? 'Close' : 'Discard'),
                ),
              ),
              if (_canSaveOriginal)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'save'),
                  child: Text(context.ebookTr('Save')),
                ),
              if (!_canSaveOriginal && !_copyDelivered)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'export'),
                  child: Text(context.ebookTr(_exportLabel)),
                ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'save' && !await _save()) return;
        if (choice == 'export') {
          await _export();
          return;
        }
      }
      _annotationTimer?.cancel();
      var discardReadingData = false;
      try {
        await _annotations?.save();
        if (_annotations case final annotations?) {
          try {
            await _recordLibraryProgress(annotations);
          } catch (error) {
            // The sidecar is durable. A catalog refresh failure must not turn
            // a successfully saved reading state into a discard prompt.
            _snack(_message(error));
          }
        }
      } catch (error) {
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(context.ebookTr('Reading data could not be saved')),
            content: SingleChildScrollView(
              child: Text(
                '${context.ebookTr(_message(error))}\n\n${context.ebookTr('Your current reading data is still available here. Export it before closing, or explicitly discard these unsaved changes.')}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.ebookTr('Keep reading')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'export'),
                child: Text(context.ebookTr('Export reading data')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(
                  context.ebookTr('Close without saving reading data'),
                ),
              ),
            ],
          ),
        );
        if (choice == 'export') {
          await _exportReadingData();
          return;
        }
        if (choice != 'discard') return;
        discardReadingData = true;
      }
      if (!mounted || route?.isCurrent == false) return;
      // Disposal normally makes one final best-effort save. An explicit discard
      // must not retry a transient failure and silently persist the draft.
      _discardReadingDataOnClose = discardReadingData;
      if (navigate != null) {
        navigate();
        return;
      }
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  Future<void> _convert() async {
    if (!_reader.isReady || _busy) return;
    setState(() => _working = true);
    _scheduleMenu();
    try {
      final payload = await _reader.exportPublication();
      final document = await compute(_importEpub, payload.toJson());
      if (!mounted) return;
      _installDocument(document, converted: true);
      _bookInfo = null;
      _searchHits = [];
      _searchGeneration++;
      _searching = false;
      _selection = null;
      _location = null;
      setState(() {
        _editing = true;
        _copyDelivered = false;
        _notice = {
          'Editing an EPUB copy. Save or export it with a new filename.',
          ...payload.warnings,
          ...document.importWarnings,
        }.join('\n');
      });
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _scheduleMenu();
      }
    }
  }

  Future<void> _exportKindle(KindleExportFormat format) async {
    if (_busy || _session == null || !_applyDrafts()) return;
    setState(() => _working = true);
    _conversionToken = EbookCancellationToken();
    _scheduleMenu();
    try {
      final result = await KindlingConverter().exportKindle(
        _session!.exportBytes(),
        format: format,
        cancellation: _conversionToken,
      );
      if (!mounted) return;
      if (result.warnings.isNotEmpty &&
          !await _confirmWarnings(result.warnings)) {
        return;
      }
      final outcome = await (widget.deviceExporterOverride ?? exportEbookCopy)(
        result.bytes,
        '${p.basenameWithoutExtension(_name)}.${result.extension}',
      );
      if (outcome != null) _reportOutcome(outcome);
    } catch (error) {
      _snack(_message(error));
    } finally {
      _conversionToken = null;
      if (mounted) {
        setState(() => _working = false);
        _scheduleMenu();
      }
    }
  }

  Future<void> _editKindleMetadata() async {
    if (_busy ||
        _bytes == null ||
        _conversion?.canRewriteKindleMetadata != true) {
      return;
    }
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EbookKindleMetadataEditor(
        info: _bookInfo,
        translate: context.ebookTr,
        exportLabel: _exportLabel,
        pickCover: _conversion?.canReplaceKindleCover == true
            ? _pickKindleCover
            : null,
        onApply: _exportKindleMetadataDraft,
        onCancel: () => _conversionToken?.cancel(),
        errorMessage: _message,
      ),
    );
  }

  Future<Uint8List?> _pickKindleCover() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.length > kImageEditorInputLimitBytes) {
      throw StateError('Choose a resource up to 32 MiB.');
    }
    inspectEditableImage(bytes, fileName: file.name);
    return bytes;
  }

  Future<bool> _exportKindleMetadataDraft(KindleMetadataDraft edited) async {
    if (_busy || _bytes == null || !mounted) return false;
    setState(() => _working = true);
    _conversionToken = EbookCancellationToken();
    _scheduleMenu();
    try {
      final format = _name.toLowerCase().endsWith('.azw3')
          ? KindleExportFormat.azw3
          : KindleExportFormat.legacyMobi;
      final result = await KindlingConverter().rewriteMetadata(
        _bytes!,
        patch: edited.patch,
        cover: edited.cover,
        format: format,
        cancellation: _conversionToken,
      );
      if (!mounted) return false;
      if (result.warnings.isNotEmpty &&
          !await _confirmWarnings(result.warnings)) {
        return false;
      }
      // A separate copy is deliberate; the metadata service does not own a
      // source-file baseline, and conversion never changes the original format.
      final outcome = await (widget.deviceExporterOverride ?? exportEbookCopy)(
        result.bytes,
        '${p.basenameWithoutExtension(_name)}-metadata.${result.extension}',
      );
      if (outcome != null) _reportOutcome(outcome);
      return outcome != null;
    } finally {
      _conversionToken = null;
      if (mounted) {
        setState(() => _working = false);
        _scheduleMenu();
      }
    }
  }

  Future<bool> _confirmWarnings(List<String> warnings) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.ebookTr('Conversion notes')),
          content: SingleChildScrollView(child: Text(warnings.join('\n\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.ebookTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.ebookTr(_exportLabel)),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _replaceImage({bool cover = false}) async {
    if (_busy || !_applyDrafts()) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: cover ? FileType.custom : FileType.any,
        allowedExtensions: cover ? ['png', 'jpg', 'jpeg'] : null,
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.length > kImageEditorInputLimitBytes) {
        throw StateError('Choose a resource up to 32 MiB.');
      }
      if (cover) {
        final info = inspectEditableImage(bytes, fileName: file.name);
        _session!.mutate(
          (doc) => doc.replaceCover(
            bytes,
            mediaType: info.format == ImageFileFormat.png
                ? 'image/png'
                : 'image/jpeg',
          ),
        );
      } else {
        final resource = _document!.resources.firstWhere(
          (e) => e.path == _resource,
        );
        if (resource.mediaType == 'image/png' ||
            resource.mediaType == 'image/jpeg') {
          inspectEditableImage(bytes, fileName: resource.path);
        }
        _session!.mutate(
          (doc) => doc.replaceResource(
            resource.path,
            bytes,
            mediaType: resource.mediaType,
          ),
        );
        _selectResource(resource.path, apply: false);
      }
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _editImage() async {
    if (_busy || _resource == null || !_applyDrafts()) return;
    try {
      final path = _resource!;
      final bytes = _document!.readBytes(path);
      final info = inspectEditableImage(bytes, fileName: path);
      final output = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog.fullscreen(
          child: _EbookImageEditor(bytes: bytes, info: info),
        ),
      );
      if (output == null || !mounted) return;
      inspectEditableImage(
        output,
        fileName: path,
        maxBytes: kImageEditorOutputLimitBytes,
      );
      _session!.mutate((doc) => doc.replaceResource(path, output));
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _addChapter() async {
    if (_busy || !_applyDrafts()) return;
    final title = await _askText('Add chapter', 'Chapter title', 'New chapter');
    if (title == null || !mounted) return;
    try {
      late EpubChapter chapter;
      _session!.mutate((doc) => chapter = doc.addChapter(title: title));
      _selectResource(chapter.path, apply: false);
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _removeChapter(EpubChapter chapter) async {
    if (_busy || !_applyDrafts()) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.ebookTr('Remove chapter')),
        content: Text(
          'Remove “${chapter.title}” from the reading order? Its resource stays in the book to preserve existing links.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.ebookTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.ebookTr('Remove chapter')),
          ),
        ],
      ),
    );
    if (remove == true && mounted) {
      try {
        _session!.mutate((doc) => doc.removeChapter(chapter.id));
      } catch (error) {
        _snack(_message(error));
      }
    }
  }

  void _moveChapter(EpubChapter chapter, int index) {
    if (_busy || !_applyDrafts()) return;
    try {
      _session!.mutate((doc) => doc.moveChapter(chapter.id, index));
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _editToc() async {
    if (_busy || !_applyDrafts()) return;
    final entries = await showDialog<List<EpubTocEntry>>(
      context: context,
      builder: (_) => _EbookTocDialog(entries: _document!.toc),
    );
    if (entries == null || !mounted) return;
    try {
      _session!.mutate((doc) => doc.updateToc(entries));
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _editProse(EpubStructuredProseBlock block) async {
    if (_busy || !block.editable || _resource == null || !_applyDrafts()) {
      return;
    }
    final path = _resource!;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EbookProseEditorDialog(
        block: block,
        translate: context.ebookTr,
        errorMessage: _message,
        onPlainTextApply: block.allowsLineBreakEditing
            ? (text) {
                if (_busy || _session == null || !mounted) {
                  throw StateError(
                    'The editor is busy. Try applying the text again.',
                  );
                }
                _session!.mutate(
                  (doc) => doc.updateStructuredProseText(block, text),
                );
                _selectResource(path, apply: false);
              }
            : null,
        onApply: (replacements) {
          if (_busy || _session == null || !mounted) {
            throw StateError(
              'The editor is busy. Try applying the text again.',
            );
          }
          _session!.mutate(
            (doc) => doc.updateStructuredProseBlock(block, replacements),
          );
          _selectResource(path, apply: false);
        },
      ),
    );
  }

  Future<String?> _askText(
    String title,
    String label,
    String value, {
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.ebookTr(title)),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: multiline ? 5 : 1,
            maxLines: multiline ? 16 : 1,
            decoration: InputDecoration(labelText: context.ebookTr(label)),
            onSubmitted: multiline
                ? null
                : (text) => Navigator.pop(context, text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.ebookTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.ebookTr('Apply')),
          ),
        ],
      ),
    );
    // Route teardown can still reference the controller until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  void _validate() {
    if (!_applyDrafts()) return;
    try {
      setState(() => _issues = _document!.validate());
    } catch (error) {
      _snack(_message(error));
    }
  }

  void _onReady(EbookBookInfo info) {
    if (!mounted) return;
    setState(() {
      _bookInfo = info;
      _readerError = null;
    });
    unawaited(
      _recordLibraryBook().catchError(
        (Object error) => _snack(_message(error)),
      ),
    );
    if (_usesChapterReader) return;
    for (final highlight in _annotations?.highlights ?? <EbookHighlight>[]) {
      unawaited(
        _reader
            .addHighlight(highlight)
            .catchError((Object error) => _snack(_message(error))),
      );
    }
  }

  void _onLocation(EbookLocation location) {
    if (!mounted ||
        _closing ||
        _readingDataBusy ||
        _annotations?.isApplyingReadingData == true) {
      return;
    }
    setState(() => _location = location);
    _annotations?.location = location;
    _persistAnnotations();
  }

  void _persistAnnotations() {
    _annotationTimer?.cancel();
    final annotations = _annotations;
    if (annotations == null) return;
    _annotationTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        annotations
            .save()
            .then((_) => _recordLibraryProgress(annotations))
            .catchError((Object error) => _snack(_message(error))),
      );
    });
  }

  Future<void> _searchBook() async {
    if (!_readerReady) return;
    if (_search.text.trim().isEmpty) {
      _chapterReader.clearSearch();
      setState(() {
        ++_searchGeneration;
        _searchHits = [];
        _searchNotice = null;
        _searching = false;
      });
      return;
    }
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _searchNotice = null;
    });
    try {
      final hits = _usesChapterReader
          ? await _chapterReader.search(_search.text.trim())
          : await _reader.search(_search.text.trim());
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _searchHits = hits;
          _searchNotice =
              _usesChapterReader && _chapterReader.searchWarnings.isNotEmpty
              ? _chapterReader.searchWarnings.join('\n')
              : hits.isEmpty
              ? 'No matches.'
              : null;
        });
      }
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  void _bookmark() {
    final annotations = _annotations;
    final location = _location;
    if (annotations == null || location == null || location.cfi.isEmpty) return;
    if (annotations.bookmarks.length >= 500) {
      _snack('This book already has 500 bookmarks.');
      return;
    }
    if (!annotations.bookmarks.any((e) => e.cfi == location.cfi)) {
      setState(() => annotations.bookmarks.add(location));
      _persistAnnotations();
      _snack('Bookmark added');
    }
  }

  Future<void> _highlight() async {
    final selection = _selection;
    final annotations = _annotations;
    if (selection == null || selection.cfi.isEmpty || annotations == null) {
      return;
    }
    if (annotations.highlights.length >= 500) {
      _snack('This book already has 500 highlights.');
      return;
    }
    final note = await _askText(
      'Highlight selection',
      'Note (optional)',
      '',
      multiline: true,
    );
    if (note == null || !mounted) return;
    if (note.length > 2000) {
      _snack('Keep notes under 2,000 characters.');
      return;
    }
    final highlight = EbookHighlight(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      cfi: selection.cfi,
      note: note,
    );
    try {
      await _reader.addHighlight(highlight);
      if (!mounted) return;
      setState(() => annotations.highlights.add(highlight));
      _persistAnnotations();
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _readerCommand(Future<void> Function() command) async {
    try {
      await command();
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _readAloud() async {
    if (!_readerReady || _usesChapterReader) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          EbookSpeechDialog(controller: _reader, translate: context.ebookTr),
    );
  }

  Future<void> _appearance() async {
    final annotations = _annotations;
    if (_busy || annotations == null) return;
    final result = await showDialog<EbookAppearance>(
      context: context,
      builder: (context) => EbookAppearanceDialog(
        appearance: annotations.appearance,
        translate: context.ebookTr,
        portable: _usesChapterReader,
        supportsTextAppearance: _bookInfo?.supportsTextAppearance ?? true,
        supportsLayout: _bookInfo?.supportsLayout ?? !_usesChapterReader,
        supportsPublisherStyles:
            _bookInfo?.supportsPublisherStyles ?? !_usesChapterReader,
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (_usesChapterReader) {
        await _chapterReader.setAppearance(result);
      } else {
        await _reader.setAppearance(result);
      }
      annotations.appearance = result;
      _persistAnnotations();
    } catch (error) {
      _snack(_message(error));
    }
  }

  Future<void> _recordLibraryBook() async {
    final library = _library;
    final annotations = _annotations;
    if (!mounted ||
        library == null ||
        annotations == null ||
        _libraryWriting ||
        annotations.contentSha256 != _libraryContentSha256) {
      return;
    }
    _libraryWriting = true;
    try {
      final title = _bookInfo?.title ?? _document?.title ?? '';
      final entry = await library.recordOpened(
        source: _librarySource,
        contentSha256: annotations.contentSha256,
        contentByteLength: annotations.contentByteLength,
        title: title.trim().isEmpty ? _name : title,
        authors: _bookInfo?.authors ?? _document?.authors ?? const [],
        format: _bookInfo?.sourceFormat ?? widget.file.extension,
        renderer: annotations.renderer,
      );
      _libraryEntryId = entry.id;
      await _recordLibraryProgress(annotations);
    } finally {
      _libraryWriting = false;
      if (mounted && !identical(annotations, _annotations)) {
        unawaited(
          _recordLibraryBook().catchError(
            (Object error) => _snack(_message(error)),
          ),
        );
      }
    }
  }

  Future<void> _recordLibraryProgress(EbookAnnotations annotations) async {
    final library = _library;
    final id = _libraryEntryId;
    final location = annotations.location;
    if (library == null ||
        id == null ||
        location == null ||
        annotations.contentSha256 != _libraryContentSha256 ||
        !identical(annotations, _annotations) ||
        library.get(id) == null) {
      return;
    }
    await library.recordProgress(
      id,
      contentSha256: annotations.contentSha256,
      renderer: annotations.renderer,
      fraction: location.fraction,
    );
  }

  Future<void> _openLibrary() async {
    if (_busy) return;
    final annotations = _annotations;
    setState(() => _readingDataBusy = true);
    _annotationTimer?.cancel();
    try {
      await annotations?.save();
      if (annotations != null) await _recordLibraryProgress(annotations);
      if (!mounted) return;
      setState(() => _readingDataPreviewing = true);
      await showEbookLibrary(
        context,
        ref,
        widget.side,
        library: _library,
        currentEntryId: _libraryEntryId,
      );
      if (!mounted || annotations == null) return;
      // A different reader can have updated this exact sidecar while the
      // library was open. Background relocation was paused for the modal.
      final fresh = await EbookAnnotations.open(
        '$_annotationIdentity${_converted ? ':converted' : ''}',
        _bytes!,
        renderer: annotations.renderer,
      );
      if (!mounted) return;
      final changed =
          fresh.exportReadingData() != annotations.exportReadingData();
      _annotations = fresh;
      if (changed) _recreateReaderFromReadingData(fresh);
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) {
        setState(() {
          _readingDataBusy = false;
          _readingDataPreviewing = false;
        });
      }
    }
  }

  void _recreateReaderFromReadingData(EbookAnnotations annotations) {
    setState(() {
      ++_readerVersion;
      _selection = null;
      _bookInfo = null;
      _location = annotations.location;
      _readerError = null;
      _seekFraction = null;
      _searchHits = [];
      ++_searchGeneration;
      _searching = false;
    });
  }

  Future<void> _exportReadingData() async {
    final annotations = _annotations;
    if (_busy || annotations == null) return;
    setState(() => _readingDataBusy = true);
    _annotationTimer?.cancel();
    try {
      // Export is also the recovery path when local persistence is unavailable
      // or another open reader has saved a newer sidecar. Validate the current
      // in-memory snapshot without requiring a successful local overwrite.
      final result =
          await (widget.readingDataExporterOverride ??
              exportEbookReadingDataFile)(
            annotations.exportReadingData(),
            '${p.basenameWithoutExtension(_name)}.reading.json',
          );
      if (result != null) {
        _snack(
          result == EbookSaveOutcome.downloadedCopy
              ? 'Reading-data download started.'
              : 'Reading data exported.',
        );
      }
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) setState(() => _readingDataBusy = false);
    }
  }

  Future<void> _importReadingData() async {
    final annotations = _annotations;
    if (_busy || annotations == null) return;
    setState(() => _readingDataBusy = true);
    _annotationTimer?.cancel();
    try {
      await annotations.save();
      final encoded =
          await (widget.readingDataPickerOverride ??
              pickEbookReadingDataFile)();
      if (encoded == null || !mounted) return;
      setState(() => _readingDataPreviewing = true);
      final plan = await showDialog<EbookReadingDataImportPlan>(
        context: context,
        builder: (context) => EbookReadingDataDialog(
          annotations: annotations,
          encoded: encoded,
          translate: context.ebookTr,
        ),
      );
      if (mounted) setState(() => _readingDataPreviewing = false);
      if (plan == null || !mounted) return;
      await annotations.applyReadingDataImport(plan);
      if (!mounted) return;
      // Recreate the reader only after persistence commits the entire import.
      _recreateReaderFromReadingData(annotations);
      if (annotations.location == null &&
          _libraryEntryId != null &&
          annotations.contentSha256 == _libraryContentSha256 &&
          _library?.get(_libraryEntryId!) != null) {
        await _library!.clearProgress(
          _libraryEntryId!,
          contentSha256: annotations.contentSha256,
          renderer: annotations.renderer,
        );
      } else {
        await _recordLibraryProgress(annotations);
      }
      _snack('Reading data imported.');
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) {
        setState(() {
          _readingDataBusy = false;
          _readingDataPreviewing = false;
        });
      }
    }
  }

  Future<void> _usePortableReader() async {
    if (_busy || _document == null || _usesChapterReader) return;
    setState(() => _working = true);
    _annotationTimer?.cancel();
    try {
      await _annotations?.save();
      final annotations = await EbookAnnotations.open(
        '$_annotationIdentity${_converted ? ':converted' : ''}',
        _bytes!,
        renderer: EbookReaderRenderer.portable,
      );
      if (!mounted) return;
      setState(() {
        _portableReaderRequested = true;
        _annotations = annotations;
        _readerError = null;
        _selection = null;
        _location = null;
        _bookInfo = null;
        ++_readerVersion;
        _searchHits = [];
        ++_searchGeneration;
        _searching = false;
      });
    } catch (error) {
      _snack(_message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(content: Text(context.ebookTr(message))),
    );
  }

  String _message(Object error) => error
      .toString()
      .replaceAll('PDF', 'ebook')
      .replaceFirst('Bad state: ', '');

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final mac = platform == TargetPlatform.macOS;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyS, meta: mac, control: !mac): () {
        if (!_busy) unawaited(_save());
      },
      SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: mac,
        control: !mac,
        shift: true,
      ): () {
        if (!_busy) unawaited(_save(copy: true));
      },
      SingleActivator(LogicalKeyboardKey.keyW, meta: mac, control: !mac): () =>
          unawaited(_requestClose()),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(_requestClose()),
    };
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: true,
          child: ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: IconButton(
                  tooltip: context.ebookTr('Close'),
                  onPressed: _busy ? null : () => unawaited(_requestClose()),
                  icon: const Icon(Icons.close),
                ),
                title: Text(
                  '${_dirty ? '* ' : ''}$_name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  if (widget.positionLabel != null) Text(widget.positionLabel!),
                  if (widget.onPrevious != null)
                    IconButton(
                      tooltip: 'Previous file',
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _requestClose(navigate: widget.onPrevious),
                            ),
                      icon: const Icon(Icons.skip_previous),
                    ),
                  if (widget.onNext != null)
                    IconButton(
                      tooltip: 'Next file',
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _requestClose(navigate: widget.onNext),
                            ),
                      icon: const Icon(Icons.skip_next),
                    ),
                  if (_document != null && !_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(context.ebookTr('Read')),
                          ),
                          ButtonSegment(
                            value: true,
                            enabled: _editable,
                            label: Text(context.ebookTr('Edit')),
                          ),
                        ],
                        selected: {_editing},
                        onSelectionChanged: _busy
                            ? null
                            : (value) => unawaited(_setEditing(value.single)),
                      ),
                    ),
                  if (_document != null)
                    IconButton(
                      key: const ValueKey('ebook-save'),
                      tooltip: context.ebookTr('Save'),
                      onPressed: !_busy && _dirty && _canSaveOriginal
                          ? () => unawaited(_save())
                          : null,
                      icon: const Icon(Icons.save_outlined),
                    ),
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: _onMenuSelection,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'library',
                        child: Text(context.ebookTr('Ebook library')),
                      ),
                      if (_annotations != null) ...[
                        PopupMenuItem(
                          value: 'exportReadingData',
                          child: Text(context.ebookTr('Export reading data')),
                        ),
                        PopupMenuItem(
                          value: 'importReadingData',
                          child: Text(context.ebookTr('Import reading data')),
                        ),
                      ],
                      if (_document != null && !_usesChapterReader)
                        PopupMenuItem(
                          value: 'portableReader',
                          child: Text(
                            context.ebookTr('Use portable EPUB reader'),
                          ),
                        ),
                      if (_canOpenTextFallback)
                        PopupMenuItem(
                          key: const ValueKey('ebook-text-fallback-menu'),
                          value: 'textFallback',
                          child: Text(context.ebookTr('Open text fallback')),
                        ),
                      if (_document != null)
                        PopupMenuItem(
                          value: 'export',
                          child: Text(context.ebookTr(_exportLabel)),
                        ),
                      if (_document != null && _store != null)
                        PopupMenuItem(
                          value: 'copy',
                          child: Text(context.ebookTr('Save a copy')),
                        ),
                      if (_document != null &&
                          _conversion?.canExportAzw3 == true)
                        PopupMenuItem(
                          value: 'azw3',
                          child: Text(context.ebookTr('Export AZW3')),
                        ),
                      if (_document != null &&
                          _conversion?.canExportLegacyMobi == true)
                        PopupMenuItem(
                          value: 'mobi',
                          child: Text(context.ebookTr('Export MOBI')),
                        ),
                      if (_document == null &&
                          _conversion?.canRewriteKindleMetadata == true &&
                          {'mobi', 'azw', 'azw3'}.contains(
                            p.extension(_name).substring(1).toLowerCase(),
                          ))
                        PopupMenuItem(
                          value: 'kindleMetadata',
                          child: Text(context.ebookTr('Edit Kindle metadata')),
                        ),
                      PopupMenuItem(
                        value: 'close',
                        child: Text(context.ebookTr('Close')),
                      ),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (_busy && !_readingDataPreviewing)
                    const LinearProgressIndicator(),
                  if (_conversionToken != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _conversionToken!.cancel,
                        child: Text(context.ebookTr('Cancel')),
                      ),
                    ),
                  if (_notice != null)
                    _banner(
                      _notice!,
                      onClose: () => setState(() => _notice = null),
                    ),
                  if (_converted)
                    _banner(
                      'Converted EPUB copy — save or export with a new filename.',
                    ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SelectableText(_error!),
                                  if (_canOpenTextFallback) ...[
                                    const SizedBox(height: 16),
                                    _textFallbackButton(),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : _editing
                        ? _editBody()
                        : _readBody(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onMenuSelection(String action) {
    switch (action) {
      case 'library':
        unawaited(_openLibrary());
      case 'exportReadingData':
        unawaited(_exportReadingData());
      case 'importReadingData':
        unawaited(_importReadingData());
      case 'portableReader':
        unawaited(_usePortableReader());
      case 'textFallback':
        unawaited(_openTextFallback());
      case 'export':
        unawaited(_export());
      case 'copy':
        unawaited(_save(copy: true));
      case 'azw3':
        unawaited(_exportKindle(KindleExportFormat.azw3));
      case 'mobi':
        unawaited(_exportKindle(KindleExportFormat.legacyMobi));
      case 'kindleMetadata':
        unawaited(_editKindleMetadata());
      case 'close':
        unawaited(_requestClose());
    }
  }

  Widget _textFallbackButton() => TextButton.icon(
    key: const ValueKey('ebook-text-fallback'),
    onPressed: _busy ? null : _openTextFallback,
    icon: const Icon(Icons.article_outlined),
    label: Text(context.ebookTr('Open text fallback')),
  );

  Widget _banner(String text, {VoidCallback? onClose}) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.ebookTr(text),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    ),
  );

  Widget _readBody() {
    if (_bytes == null) return const SizedBox.shrink();
    final document = _document;
    if (_usesChapterReader && document == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.ebookTr(
                  'This format needs the enhanced reader. The portable reader supports EPUB.',
                ),
                textAlign: TextAlign.center,
              ),
              if (_linuxHost?.reason case final reason?) ...[
                const SizedBox(height: 12),
                SelectableText(
                  context.ebookTr(reason),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }
    final Widget reader = _usesChapterReader
        ? EbookChapterReader(
            translate: context.ebookTr,
            key: ValueKey(_readerVersion),
            document: document!,
            controller: _chapterReader,
            initialSection: _annotations?.location?.sectionIndex ?? 0,
            initialLocation: _annotations?.location?.cfi,
            appearance:
                _annotations?.appearance ??
                const EbookAppearance(flow: 'scrolled'),
            showControls: false,
            onReady: _onReady,
            onLocationChanged: _onLocation,
            onAppearanceChanged: (appearance) {
              _annotations?.appearance = appearance;
              _persistAnnotations();
            },
          )
        : widget.readerBuilderOverride?.call(
                context,
                _bytes!,
                _converted ? _epubName : _name,
                _reader,
              ) ??
              CrispEbookReader(
                key: ValueKey(_readerVersion),
                bytes: _bytes!,
                filename: _converted ? _epubName : _name,
                controller: _reader,
                initialLocation: _annotations?.location?.cfi,
                appearance: _annotations?.appearance ?? const EbookAppearance(),
                onReady: _onReady,
                onLocationChanged: _onLocation,
                onHistoryChanged: (_) {
                  if (mounted) setState(() {});
                },
                onSelection: (selection) {
                  if (mounted) setState(() => _selection = selection);
                },
                onError: (message) {
                  if (mounted) setState(() => _readerError = message);
                },
              );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _icon(
                'Ebook library',
                Icons.library_books_outlined,
                _openLibrary,
              ),
              if (_bookInfo?.supportsNavigationHistory == true) ...[
                _icon(
                  'Back to previous location',
                  Icons.arrow_back,
                  _readerReady && _reader.canGoBack
                      ? () => _readerCommand(_reader.goBack)
                      : null,
                ),
                _icon(
                  'Forward to next location',
                  Icons.arrow_forward,
                  _readerReady && _reader.canGoForward
                      ? () => _readerCommand(_reader.goForward)
                      : null,
                ),
              ],
              _icon(
                _usesChapterReader ? 'Previous chapter' : 'Previous page',
                Icons.chevron_left,
                _readerReady ? () => _readerCommand(_previousReaderPage) : null,
              ),
              _icon(
                _usesChapterReader ? 'Next chapter' : 'Next page',
                Icons.chevron_right,
                _readerReady ? () => _readerCommand(_nextReaderPage) : null,
              ),
              _icon(
                'Contents',
                Icons.list,
                _readerReady ? () => _showReaderList('Contents') : null,
              ),
              _icon(
                'Bookmarks',
                Icons.bookmarks_outlined,
                () => _showReaderList('Bookmarks'),
              ),
              if (!_usesChapterReader)
                _icon(
                  'Highlights',
                  Icons.highlight_outlined,
                  () => _showReaderList('Highlights'),
                ),
              _icon(
                'Add bookmark',
                Icons.bookmark_add_outlined,
                _location != null ? _bookmark : null,
              ),
              if (!_usesChapterReader)
                _icon(
                  'Highlight selection',
                  Icons.format_color_fill,
                  _selection?.cfi.isNotEmpty == true ? _highlight : null,
                ),
              if (!_usesChapterReader)
                _icon(
                  'Copy selection',
                  Icons.content_copy,
                  _selection?.text.isNotEmpty == true
                      ? () => unawaited(
                          Clipboard.setData(
                            ClipboardData(text: _selection!.text),
                          ).then((_) => _snack('Selection copied.')),
                        )
                      : null,
                ),
              if (!_usesChapterReader)
                _icon(
                  'Read aloud',
                  Icons.record_voice_over_outlined,
                  _readerReady ? _readAloud : null,
                ),
              _icon(
                'Appearance',
                Icons.text_fields,
                _readerReady ? _appearance : null,
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.ebookTr('Search'),
                    suffixIcon: IconButton(
                      onPressed: _readerReady ? _searchBook : null,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _searchBook(),
                ),
              ),
              if (_document == null)
                FilledButton.tonalIcon(
                  onPressed: !_busy && _readerReady ? _convert : null,
                  icon: const Icon(Icons.edit_document),
                  label: Text(context.ebookTr('Convert to editable EPUB')),
                ),
            ],
          ),
        ),
        if (_usesChapterReader &&
            _linuxHost != null &&
            !_portableReaderRequested)
          _banner(
            'The enhanced Linux reader is unavailable. Using the portable EPUB reader.',
          ),
        if (_readerError != null) ...[
          _banner(_readerError!),
          if (!_usesChapterReader && _document != null)
            TextButton.icon(
              onPressed: _busy ? null : _usePortableReader,
              icon: const Icon(Icons.menu_book),
              label: Text(context.ebookTr('Use portable EPUB reader')),
            ),
          if (_canOpenTextFallback) _textFallbackButton(),
        ],
        if (_searching) const LinearProgressIndicator(),
        if (_searchNotice != null) _banner(_searchNotice!),
        if (_searchHits.isNotEmpty)
          SizedBox(
            height: 130,
            child: ListView.builder(
              itemCount: _searchHits.length,
              itemBuilder: (context, index) {
                final hit = _searchHits[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    hit.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _readerCommand(() => _goToReader(hit.cfi)),
                );
              },
            ),
          ),
        Expanded(
          child: AbsorbPointer(absorbing: _readingDataBusy, child: reader),
        ),
        if (_location != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _location!.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_usesChapterReader &&
                    _bookInfo?.supportsProgressSeeking == true)
                  Expanded(
                    child: Slider(
                      key: const ValueKey('ebook-reading-progress'),
                      value: (_seekFraction ?? _location!.fraction).clamp(
                        0.0,
                        1.0,
                      ),
                      label:
                          '${((_seekFraction ?? _location!.fraction) * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChanged: _readerReady
                          ? (value) => setState(() => _seekFraction = value)
                          : null,
                      onChangeEnd: _readerReady
                          ? (value) async {
                              await _readerCommand(
                                () => _reader.goToFraction(value),
                              );
                              if (mounted) setState(() => _seekFraction = null);
                            }
                          : null,
                    ),
                  ),
                Text('${(_location!.fraction * 100).round()}%'),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _showReaderList(String kind) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final items = <Widget>[];
          void toc(List<EbookTocItem> entries, int depth) {
            for (final item in entries) {
              items.add(
                ListTile(
                  contentPadding: EdgeInsets.only(
                    left: 16 + depth * 16.0,
                    right: 16,
                  ),
                  title: Text(item.label),
                  onTap: item.href.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context);
                          unawaited(
                            _readerCommand(() => _goToReader(item.href)),
                          );
                        },
                ),
              );
              if (depth < 32) toc(item.children, depth + 1);
            }
          }

          if (kind == 'Contents') toc(_bookInfo?.toc ?? [], 0);
          if (kind == 'Bookmarks') {
            for (final bookmark
                in _annotations?.bookmarks ?? <EbookLocation>[]) {
              items.add(
                ListTile(
                  title: Text(
                    bookmark.chapterTitle.isEmpty
                        ? '${(bookmark.fraction * 100).round()}%'
                        : bookmark.chapterTitle,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setDialogState(
                        () => _annotations!.bookmarks.remove(bookmark),
                      );
                      _persistAnnotations();
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_readerCommand(() => _goToReader(bookmark.cfi)));
                  },
                ),
              );
            }
          }
          if (kind == 'Highlights') {
            for (final highlight
                in _annotations?.highlights ?? <EbookHighlight>[]) {
              items.add(
                ListTile(
                  title: Text(
                    highlight.note.isEmpty
                        ? context.ebookTr('Highlight')
                        : highlight.note,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      unawaited(
                        _readerCommand(
                          () => _reader.removeHighlight(highlight.id),
                        ),
                      );
                      setDialogState(
                        () => _annotations!.highlights.remove(highlight),
                      );
                      _persistAnnotations();
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_readerCommand(() => _goToReader(highlight.cfi)));
                  },
                ),
              );
            }
          }
          return AlertDialog(
            title: Text(context.ebookTr(kind)),
            content: SizedBox(
              width: 500,
              height: 420,
              child: items.isEmpty
                  ? Center(child: Text(context.ebookTr('No entries yet.')))
                  : ListView(children: items),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.ebookTr('Close')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _icon(String label, IconData icon, VoidCallback? action) => IconButton(
    tooltip: context.ebookTr(label),
    onPressed: _busy ? null : action,
    icon: Icon(icon),
  );

  Widget _editBody() => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                tabs: [
                  Tab(text: context.ebookTr('Metadata')),
                  Tab(text: context.ebookTr('Contents')),
                  Tab(text: context.ebookTr('Resources')),
                ],
              ),
            ),
            _icon(
              'Undo',
              Icons.undo,
              !_busy && (_session?.canUndo ?? false) ? _undo : null,
            ),
            _icon(
              'Redo',
              Icons.redo,
              !_busy &&
                      !_sourceDraft &&
                      !_metadataDraft &&
                      (_session?.canRedo ?? false)
                  ? _redo
                  : null,
            ),
            _icon(
              'Validate',
              Icons.fact_check_outlined,
              !_busy ? _validate : null,
            ),
            _icon(
              'Preview',
              Icons.menu_book,
              !_busy ? () => _setEditing(false) : null,
            ),
          ],
        ),
        if (_sourceWarning != null) _banner(_sourceWarning!),
        Expanded(
          child: TabBarView(
            children: [_metadataBody(), _contentsBody(), _resourcesBody()],
          ),
        ),
        if (_issues != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: _issues!.isEmpty
                ? _banner('No validation errors.')
                : ListView(
                    shrinkWrap: true,
                    children: _issues!
                        .map(
                          (issue) => ListTile(
                            dense: true,
                            leading: Icon(
                              issue.isError
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                            ),
                            title: SelectableText(issue.message),
                            subtitle: issue.path == null
                                ? null
                                : Text(issue.path!),
                          ),
                        )
                        .toList(),
                  ),
          ),
      ],
    ),
  );

  Widget _metadataBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_document?.coverPath case final coverPath?)
              Center(
                child: SizedBox(
                  height: 160,
                  child: _imageResourcePreview(coverPath),
                ),
              ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _replaceImage(cover: true),
                icon: const Icon(Icons.image_outlined),
                label: Text(context.ebookTr('Replace cover')),
              ),
            ),
            _field(_title, 'Title'),
            _field(_authors, 'Authors (one per line)', lines: 3),
            _field(_language, 'Language'),
            _field(_description, 'Description', lines: 5),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: !_busy && _metadataDraft ? _applyDrafts : null,
                child: Text(context.ebookTr('Apply')),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'EPUB ${_document!.version} · ${_document!.chapters.length} chapters · ${_document!.resources.length} resources',
            ),
            if (_document!.fixedLayout)
              const Text('Fixed-layout book: use Source for layout edits.'),
          ],
        ),
      ),
    ),
  );

  Widget _imageResourcePreview(String path) {
    Widget failed(Object error) => Center(
      child: Tooltip(
        message: _message(error),
        child: const Icon(Icons.broken_image_outlined, size: 48),
      ),
    );
    try {
      final bytes = _document!.readBytes(path);
      if (isEditableImageFileName(path)) {
        inspectEditableImage(bytes, fileName: path);
      }
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, error, _) => failed(error),
      );
    } catch (error) {
      // CRC, inflation and resource validation happen lazily. A damaged image
      // must leave the rest of the editor available for inspection or repair.
      return failed(error);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: context.ebookTr(label),
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _contentsBody() {
    final chapters = _document!.chapters;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _addChapter,
                icon: const Icon(Icons.add),
                label: Text(context.ebookTr('Add chapter')),
              ),
              TextButton(
                onPressed: _busy ? null : _editToc,
                child: Text(context.ebookTr('Edit contents')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (!_applyDrafts()) return;
                        try {
                          _session!.mutate((doc) => doc.updateToc());
                        } catch (error) {
                          _snack(_message(error));
                        }
                      },
                child: Text(context.ebookTr('Rebuild contents from chapters')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return ListTile(
                leading: Text('${index + 1}'),
                title: Text(chapter.title),
                subtitle: Text(chapter.path),
                onTap: () {
                  _selectResource(chapter.path);
                  DefaultTabController.of(context).animateTo(2);
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _icon(
                      'Move up',
                      Icons.arrow_upward,
                      !_busy && index > 0
                          ? () => _moveChapter(chapter, index - 1)
                          : null,
                    ),
                    _icon(
                      'Move down',
                      Icons.arrow_downward,
                      !_busy && index + 1 < chapters.length
                          ? () => _moveChapter(chapter, index + 1)
                          : null,
                    ),
                    _icon(
                      'Remove chapter',
                      Icons.remove_circle_outline,
                      !_busy ? () => _removeChapter(chapter) : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resourcesBody() {
    final resources = _document!.resources
        .where((r) => !r.isEncrypted)
        .toList();
    final resource = resources.where((r) => r.path == _resource).firstOrNull;
    final xhtml = resource?.mediaType == 'application/xhtml+xml';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: resource?.path,
                  items: resources
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.path,
                          child: Text(r.path, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (path) {
                          if (path != null) _selectResource(path);
                        },
                ),
              ),
              if (xhtml && !_document!.fixedLayout)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.ebookTr('Source')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.ebookTr('Text')),
                      ),
                    ],
                    selected: {_showProse},
                    onSelectionChanged: (value) {
                      if (_applyDrafts()) {
                        setState(() => _showProse = value.single);
                      }
                    },
                  ),
                ),
              if (resource?.isText == true)
                TextButton(
                  onPressed: !_busy && _sourceDraft ? _applyDrafts : null,
                  child: Text(context.ebookTr('Apply')),
                ),
            ],
          ),
        ),
        if (resource == null)
          const Expanded(child: SizedBox.shrink())
        else if (resource.isText &&
            !(_showProse && xhtml && !_document!.fixedLayout))
          Expanded(
            child: CodeEditor(
              controller: _source,
              wordWrap: true,
              style: CodeEditorStyle(
                fontSize: 13,
                fontFamily: 'AppMono',
                textColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              indicatorBuilder: (context, editing, chunks, notifier) =>
                  DefaultCodeLineNumber(
                    controller: editing,
                    notifier: notifier,
                  ),
              padding: const EdgeInsets.all(12),
            ),
          )
        else if (resource.isText)
          Expanded(child: _proseBody(resource.path))
        else
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: resource.mediaType.startsWith('image/')
                      ? _imageResourcePreview(resource.path)
                      : const Center(
                          child: Icon(Icons.insert_drive_file, size: 72),
                        ),
                ),
                Text('${resource.mediaType} · ${resource.size} bytes'),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (isEditableImageFileName(resource.path))
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _editImage,
                          icon: const Icon(Icons.edit),
                          label: Text(context.ebookTr('Edit image')),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _replaceImage,
                        child: Text(context.ebookTr('Replace resource')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _proseBody(String path) {
    try {
      final blocks = _document!.readStructuredProse(path);
      return Column(
        children: [
          _banner(
            'Correct text while preserving formatting and links. Use Source to change protected content.',
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                return ListTile(
                  title: Text(block.text),
                  subtitle: Text(block.tag),
                  trailing: Icon(
                    block.editable ? Icons.edit_outlined : Icons.code,
                  ),
                  onTap: block.editable
                      ? () => _editProse(block)
                      : () => setState(() => _showProse = false),
                );
              },
            ),
          ),
        ],
      );
    } catch (error) {
      return Center(child: Text(_message(error)));
    }
  }
}

EpubDocument _openEpub(Uint8List bytes) => EpubDocument.open(
  bytes,
  limits: const EpubLimits(maxArchiveBytes: kEbookInputLimitBytes),
);
EpubDocument _importEpub(Map<String, dynamic> payload) =>
    EpubDocument.fromPublication(payload);

class _EbookImageEditor extends StatefulWidget {
  const _EbookImageEditor({required this.bytes, required this.info});
  final Uint8List bytes;
  final ImageFileInfo info;
  @override
  State<_EbookImageEditor> createState() => _EbookImageEditorState();
}

class _EbookImageEditorState extends State<_EbookImageEditor> {
  final _key = GlobalKey<ProImageEditorState>();
  bool _exporting = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.ebookTr('Edit image')),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exporting ? null : () => Navigator.pop(context),
      ),
      actions: [
        TextButton(
          onPressed: _exporting
              ? null
              : () async {
                  setState(() => _exporting = true);
                  try {
                    final bytes = await _key.currentState?.captureEditorImage();
                    if (context.mounted && bytes != null) {
                      Navigator.pop(context, bytes);
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$error')));
                    }
                  } finally {
                    if (mounted) setState(() => _exporting = false);
                  }
                },
          child: Text(context.ebookTr('Apply')),
        ),
      ],
    ),
    body: AbsorbPointer(
      absorbing: _exporting,
      child: ImageEditorSurface(
        bytes: widget.bytes,
        info: widget.info,
        editorKey: _key,
        callbacks: const ProImageEditorCallbacks(),
      ),
    ),
  );
}

class _EbookTocDialog extends StatefulWidget {
  const _EbookTocDialog({required this.entries});
  final List<EpubTocEntry> entries;
  @override
  State<_EbookTocDialog> createState() => _EbookTocDialogState();
}

class _EbookTocDialogState extends State<_EbookTocDialog> {
  final _rows =
      <
        ({TextEditingController label, TextEditingController href, int depth})
      >[];
  @override
  void initState() {
    super.initState();
    void add(List<EpubTocEntry> entries, int depth) {
      for (final entry in entries) {
        _rows.add((
          label: TextEditingController(text: entry.label),
          href: TextEditingController(text: entry.href),
          depth: depth,
        ));
        add(entry.children, depth + 1);
      }
    }

    add(widget.entries, 0);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.label.dispose();
      row.href.dispose();
    }
    super.dispose();
  }

  List<EpubTocEntry> _entries() {
    var index = 0;
    List<EpubTocEntry> read(int depth) {
      final entries = <EpubTocEntry>[];
      while (index < _rows.length && _rows[index].depth >= depth) {
        final row = _rows[index++];
        final children = index < _rows.length && _rows[index].depth > row.depth
            ? read(_rows[index].depth)
            : <EpubTocEntry>[];
        entries.add(
          EpubTocEntry(
            label: row.label.text,
            href: row.href.text,
            children: children,
          ),
        );
      }
      return entries;
    }

    return read(0);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.ebookTr('Edit contents')),
    content: SizedBox(
      width: 680,
      height: 440,
      child: ListView(
        children: [
          const Text(
            'Edit labels and archive-relative links. Existing nesting is preserved.',
          ),
          for (final row in _rows)
            Padding(
              padding: EdgeInsets.only(top: 12, left: row.depth * 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.label,
                      decoration: const InputDecoration(labelText: 'Label'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: row.href,
                      decoration: const InputDecoration(labelText: 'Link'),
                    ),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(
              () => _rows.add((
                label: TextEditingController(),
                href: TextEditingController(),
                depth: 0,
              )),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add entry'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.ebookTr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _entries()),
        child: Text(context.ebookTr('Apply')),
      ),
    ],
  );
}
