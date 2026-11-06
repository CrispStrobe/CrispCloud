// lib/widgets/file_editor_dialog.dart
//
// Built-in text/code editor for remote (and local) files.
// Downloads the file, presents it in an editable code surface with line
// numbers, syntax highlighting, folding and find/replace, and re-uploads on
// save. Warns on unsaved changes.
//
// The editor widget is Re-Editor (MIT). Encoding and line-ending metadata are
// retained by [EditorDocument] so a save does not silently rewrite a Latin-1
// file as UTF-8 or convert CRLF to LF.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../l10n/app_localizations.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../l10n/image_editor_strings.dart';
import '../l10n/media_editor_strings.dart';
import '../services/media_capabilities.dart';
import '../services/code_editor_menu.dart';
import '../services/captured_file_target.dart';
import '../services/editor_document.dart';
import '../services/editor_document_history.dart';
import 'hex_editor_dialog.dart';
import '../services/editor_highlighting.dart';
import '../services/image_edit_session.dart' show isImageEditorFileName;
import '../services/log_service.dart';
import '../services/save_coordinator.dart';
import '../utils/file_editability.dart' show isTextEditableName;
import 'code_editor_context_menu.dart';
import 'code_editor_find_panel.dart';
import 'code_editor_status_bar.dart';
import 'image_editor_dialog.dart';
import 'media_editor_dialog.dart';
import 'office_editor_dialog.dart';
import 'pdf_editor_dialog.dart';

/// Opens a full-screen editor dialog for the given file.
Future<void> showFileEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) async {
  if (file.isFolder) return;
  try {
    if (isImageEditorFileName(file.name)) {
      await showImageEditorDialog(context, ref, file, side);
      return;
    }
    if (isPdfFileName(file.name)) {
      await showPdfEditorDialog(context, ref, file, side);
      return;
    }
    final mediaKind = mediaKindForFileName(file.name);
    if (mediaKind != null) {
      if (MediaCapabilities.canEdit(mediaKind)) {
        await showMediaEditorDialog(context, ref, file, side);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          context.mediaTr('This media format cannot be edited on this platform.'),
        )));
      }
      return;
    }
    // Office documents get the rich Word/Sheet/Slides editor instead of the
    // plain-text editor.
    if (isOfficeFileName(file.name)) {
      await showOfficeEditorDialog(context, ref, file, side);
      return;
    }
    // F4 and the native menu can be invoked even when the viewer's Edit button
    // is disabled. Never decode an unsupported binary file as editable text.
    if (!isTextEditableName(file.name)) {
      await showHexEditorDialog(context, ref, file, side);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FileEditorPage(file: file, side: side),
      ),
    );
  } finally {
    // Returning from any editor should land back on the same file with the
    // panel ready for the next F3/F4, including when opened from a context
    // menu rather than the F-key handler.
    try {
      ref.read(panelProvider(side)).restoreCursorAndFocus(file);
    } catch (_) {
      // The browser may already be disposed.
    }
  }
}

class _FileEditorPage extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;

  const _FileEditorPage({required this.file, required this.side});

  @override
  ConsumerState<_FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends ConsumerState<_FileEditorPage> {
  static const _log = Log('FileEditor');
  static const _autoSaveDelay = Duration(seconds: 30);

  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;
  final CodeScrollController _scrollController = CodeScrollController();
  final SaveCoordinator<EditorDocument> _saveState =
      SaveCoordinator<EditorDocument>();
  final _focusNode = FocusNode();

  EditorDocument? _document;
  final _documentHistory = EditorDocumentHistory();
  Uint8List? _originalBytes;
  Timer? _autoSaveTimer;
  CapturedFileTarget? _target;
  String? _language;
  String? _error;
  CodeLines? _lastCodeLines;
  CodeLineSelection? _lastSelection;
  bool _loading = true;
  bool _suppressChange = false;
  bool _conflictDetected = false;
  bool _highlightEnabled = true;
  bool _wordWrap = false;
  int _cursorLine = 1;
  int _cursorColumn = 1;
  int _lineCount = 1;

  CodeHighlightTheme? _cachedHighlightTheme;
  String? _cachedHighlightKey;
  CodeEditorMenuActions? _menuActions;
  ProviderContainer? _providerContainer;
  String? _menuSignature;

  @override
  void initState() {
    super.initState();
    _language = editorLanguageForFile(widget.file.name);
    _controller = CodeLineEditingController(
      options: const CodeLineOptions(lineBreak: TextLineBreak.lf),
    );
    _findController = CodeFindController(_controller);
    _controller.addListener(_onControllerChanged);
    _saveState.addListener(_onSaveStateChanged);
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    _menuSignature = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishMenu();
    });
  }

  @override
  void dispose() {
    final container = _providerContainer;
    final actions = _menuActions;
    _menuActions = null;
    _providerContainer = null;
    if (container != null && actions != null) {
      // The browser rebuilds from this provider. Clear it after the route has
      // left the tree so native menu commands cannot target a disposed editor.
      scheduleMicrotask(() {
        try {
          if (identical(container.read(codeEditorMenuProvider), actions)) {
            container.read(codeEditorMenuProvider.notifier).state = null;
          }
        } catch (_) {
          // The provider container may already be disposed.
        }
      });
    }
    _autoSaveTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _saveState.removeListener(_onSaveStateChanged);
    _findController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _saveState.dispose();
    super.dispose();
  }

  bool get _isModified => _saveState.isDirty;
  bool get _isSaving => _saveState.isSaving;

  void _publishMenu() {
    final container = _providerContainer;
    if (container == null) return;
    final hasSelection = !_controller.selection.isCollapsed;
    final signature = <bool>[
      _isModified,
      _controller.canUndo,
      _controller.canRedo,
      hasSelection,
      !_loading,
      _language != null,
    ].join('|');
    if (signature == _menuSignature && _menuActions != null) return;
    _menuSignature = signature;
    final actions = CodeEditorMenuActions(
      perform: _performMenuAction,
      canSave: _isModified && !_loading,
      canUndo: _controller.canUndo,
      canRedo: _controller.canRedo,
      hasSelection: hasSelection,
      canReload: !_loading,
      canHighlight: _language != null,
      busy: _loading,
    );
    _menuActions = actions;
    container.read(codeEditorMenuProvider.notifier).state = actions;
  }

  void _performMenuAction(CodeEditorMenuAction action) {
    switch (action) {
      case CodeEditorMenuAction.save:
        unawaited(_saveFile());
        break;
      case CodeEditorMenuAction.close:
        unawaited(_closeEditor());
        break;
      case CodeEditorMenuAction.reload:
        unawaited(_reloadFromDisk());
        break;
      case CodeEditorMenuAction.undo:
        _controller.undo();
        break;
      case CodeEditorMenuAction.redo:
        _controller.redo();
        break;
      case CodeEditorMenuAction.cut:
        _controller.cut();
        break;
      case CodeEditorMenuAction.copy:
        _controller.copy();
        break;
      case CodeEditorMenuAction.paste:
        _controller.paste();
        break;
      case CodeEditorMenuAction.selectAll:
        _controller.selectAll();
        break;
      case CodeEditorMenuAction.find:
        _openFind();
        break;
      case CodeEditorMenuAction.replace:
        _openFind(replace: true);
        break;
      case CodeEditorMenuAction.goToLine:
        unawaited(_goToLine());
        break;
      case CodeEditorMenuAction.toggleWordWrap:
        _toggleWordWrap();
        break;
      case CodeEditorMenuAction.toggleHighlighting:
        _toggleHighlighting();
        break;
    }
  }

  Future<void> _closeEditor() async {
    if (await _confirmDiscard()) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _reloadFromDisk() async {
    if (await _confirmDiscard()) {
      await _loadFile();
    }
  }

  void _onSaveStateChanged() {
    if (!mounted) return;
    setState(() {});
    _publishMenu();
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final codeLines = _controller.codeLines;
    final valueChanged = !identical(codeLines, _lastCodeLines);
    // Folding may replace CodeLines without editing the file.
    final nextText = valueChanged ? _controller.text : null;
    final textChanged = valueChanged && nextText != _document?.text;
    if (textChanged) {
      _lastCodeLines = codeLines;
      if (!_suppressChange && _document != null) {
        _document = _documentHistory.apply(codeLines, nextText!, _document!);
      }
      if (!_suppressChange) {
        _saveState.markChanged();
        _scheduleAutoSave();
      }
    }

    if (valueChanged && !textChanged && _document != null) {
      _documentHistory.remember(codeLines, _document!);
      _lastCodeLines = codeLines;
    }
    final selection = _controller.selection;
    final newLine = selection.extentIndex + 1;
    final newColumn = selection.extentOffset + 1;
    final newLineCount = _controller.lineCount;
    final selectionChanged =
        _lastSelection != selection ||
        newLine != _cursorLine ||
        newColumn != _cursorColumn ||
        newLineCount != _lineCount;
    _lastSelection = selection;
    _cursorLine = newLine;
    _cursorColumn = newColumn;
    _lineCount = newLineCount;

    if (textChanged || selectionChanged) {
      setState(() {});
      _publishMenu();
    }
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      if (!mounted) return;
      if (_saveState.isDirty && !_saveState.isSaving) {
        unawaited(_saveFile(manual: false));
      }
    });
  }

  Future<void> _loadFile({EditorEncoding? encodingOverride}) async {
    _log.debug(
      'loadFile: ${widget.file.name} side=${widget.side.name} web=$kIsWeb',
    );
    _autoSaveTimer?.cancel();
    // Reloading resets the revision counter. Do not do that in the middle of
    // an upload, or the write would mark the freshly loaded document clean or
    // dirty based on the previous document's revision.
    if (_saveState.isSaving) {
      await _saveState.idle;
      if (!mounted) return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _document = null;
    });
    try {
      final target = _target ??= ref
          .read(panelProvider(widget.side))
          .captureFileTarget(widget.file);
      final bytes = await target.load();

      if (!mounted) return;

      final document = EditorDocument.decode(bytes, encoding: encodingOverride);
      _applyDocument(document, bytes);
      setState(() {
        _loading = false;
        _error = null;
        _conflictDetected = false;
      });
      _publishMenu();
      _focusNode.requestFocus();
    } catch (e) {
      _log.warn('operation failed', e);
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load file: $e';
        _loading = false;
      });
      _publishMenu();
    }
  }

  void _applyDocument(EditorDocument document, Uint8List bytes) {
    _suppressChange = true;
    try {
      _controller.text = document.text;
      _controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      _controller.clearHistory();
    } finally {
      _suppressChange = false;
    }
    _lastCodeLines = _controller.codeLines;
    _lastSelection = _controller.selection;
    _lineCount = _controller.lineCount;
    _cursorLine = 1;
    _cursorColumn = 1;
    _document = document;
    _documentHistory.remember(_controller.codeLines, document);
    _originalBytes = bytes;
    _saveState.markLoaded();
    _autoSaveTimer?.cancel();

    if (_language == null) {
      final detected = editorLanguageForContent(document.text);
      if (detected != null) {
        _language = detected;
      }
    }
  }

  /// Save a local snapshot before overwriting (version backup).
  Future<void> _saveLocalSnapshot() async {
    if (kIsWeb || _originalBytes == null) return;
    try {
      final snapshotDir = Directory(
        p.join(Directory.systemTemp.path, 'crispcloud_snapshots'),
      );
      if (!await snapshotDir.exists()) {
        await snapshotDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final name = widget.file.name;
      final snapshotPath = p.join(snapshotDir.path, '${timestamp}_$name');
      await File(snapshotPath).writeAsBytes(_originalBytes!);
    } catch (e) {
      // Snapshot is best-effort, don't fail the save
    }
  }

  /// Save the current document.
  ///
  /// All save entry points (toolbar, keyboard, autosave, conflict banner) go
  /// through this method. It records the revision being written and leaves the
  /// document dirty when the user typed while the upload was in flight.
  Future<void> _saveFile({bool force = false, bool manual = true}) async {
    final document = _document;
    if (document == null || _loading) return;

    // Autosave must not queue extra saves behind a slow upload; a timer will
    // fire again after the next edit. Manual saves are queued by the
    // coordinator so Ctrl+S during an upload still saves the newest text.
    if (!manual && _saveState.isSaving) return;
    if (!force && !_saveState.isDirty && !_saveState.isSaving) return;

    if (!mounted) return;

    final result = await _saveState.save(
      snapshot: () {
        final current = _document;
        if (current == null) {
          throw StateError('The editor has no document to save.');
        }
        return SaveSnapshot<EditorDocument>(
          revision: _saveState.revision,
          value: current.copyWith(text: _controller.text),
        );
      },
      write: (snapshot) async {
        await _saveLocalSnapshot();
        final bytes = snapshot.value.encode();
        await _uploadBytes(bytes);
        _originalBytes = bytes;
      },
    );

    if (!mounted) return;
    if (!result.isSuccess) {
      _showSaveError(result.error);
      return;
    }

    if (result.isDirty) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${widget.file.name} — newer edits are still unsaved.',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _conflictDetected = false;
    });
    ref.read(panelProvider(widget.side)).refreshFiles();
    if (manual) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${widget.file.name}')));
    }
  }

  Future<void> _uploadBytes(Uint8List bytes) async {
    final target = _target;
    if (target == null) throw StateError('Reopen this file before saving.');
    final result = await target.save(bytes);
    if (result == FileWriteOutcome.downloadedCopy) {
      throw const FileTargetConflict(
        'A copy was downloaded. The original file is unchanged and your edits remain unsaved.',
      );
    }
  }

  void _showSaveError(Object? error) {
    if (!mounted) return;
    if (error is FileTargetConflict) {
      setState(() => _conflictDetected = true);
    }
    if (error is EditorEncodingException) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: SnackBarAction(
            label: 'Use UTF-8',
            onPressed: () {
              _setEncoding(EditorEncoding.utf8);
              unawaited(_saveFile(force: true));
            },
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Save failed: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _setEncoding(EditorEncoding encoding) {
    final document = _document;
    if (document == null || document.encoding == encoding) return;
    setState(() => _document = document.copyWith(encoding: encoding));
    _saveState.markChanged();
    _scheduleAutoSave();
  }

  void _setLineEnding(EditorLineEnding lineEnding) {
    final document = _document;
    if (document == null || (document.lineEnding == lineEnding &&
        document.lineEndingPolicy == EditorLineEndingPolicy.normalize)) return;
    setState(() => _document = document.copyWith(lineEnding: lineEnding));
    _saveState.markChanged();
    _scheduleAutoSave();
  }

  void _setEndingPolicy(EditorLineEndingPolicy policy) {
    if (_document == null || _document!.lineEndingPolicy == policy) return;
    setState(() => _document = _document!.copyWith(lineEndingPolicy: policy));
    _saveState.markChanged();
    _scheduleAutoSave();
  }

  void _setNewLineEnding(EditorLineEnding style) {
    if (_document == null || _document!.lineEnding == style) return;
    setState(() => _document = _document!.withNewLineEnding(style));
    // In normalize mode the preference also determines stored line endings.
    if (_document!.lineEndingPolicy == EditorLineEndingPolicy.normalize) {
      _saveState.markChanged();
      _scheduleAutoSave();
    }
  }

  void _toggleBom() {
    final document = _document;
    if (document == null || document.encoding == EditorEncoding.latin1) return;
    setState(() => _document = document.copyWith(
      encoding: document.encoding == EditorEncoding.utf8 ? EditorEncoding.utf8Bom :
        document.encoding == EditorEncoding.utf8Bom ? EditorEncoding.utf8 : document.encoding,
      hadBom: !document.writesBom,
    ));
    _saveState.markChanged();
    _scheduleAutoSave();
  }

  Future<void> _reopenEncoding() async {
    if (!await _confirmDiscard() || !mounted) return;
    final encoding = await showDialog<EditorEncoding>(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('Reopen saved bytes using encoding'),
      children: [for (final value in EditorEncoding.values) SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, value), child: Text(value.label))],
    ));
    if (encoding != null && mounted) await _loadFile(encodingOverride: encoding);
  }

  void _toggleHighlighting() {
    setState(() => _highlightEnabled = !_highlightEnabled);
  }

  void _toggleWordWrap() {
    setState(() => _wordWrap = !_wordWrap);
  }

  void _openFind({bool replace = false}) {
    if (replace) {
      _findController.replaceMode();
    } else {
      _findController.findMode();
    }
  }

  void _closeFind() {
    if (_findController.value != null) {
      _findController.close();
    }
    _focusNode.requestFocus();
  }

  Future<void> _goToLine() async {
    var input = '';
    final line = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to line'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '1–$_lineCount',
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => input = value,
          onSubmitted: (value) {
            Navigator.of(ctx).pop(int.tryParse(value));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(input)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (line == null || !mounted) return;
    final index = (line - 1).clamp(0, _controller.lineCount - 1);
    _controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: 0,
    );
    _scrollController.makeCenterIfInvisible(
      CodeLinePosition(index: index, offset: 0),
    );
    _focusNode.requestFocus();
  }

  Future<bool> _confirmDiscard() async {
    if (!_isModified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.unsavedChanges),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.discard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        unawaited(_saveFile());
      },
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
        unawaited(_saveFile());
      },
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
      const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
        _openFind(replace: true);
      },
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        meta: true,
        alt: true,
      ): () {
        _openFind(replace: true);
      },
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): () {
        unawaited(_goToLine());
      },
      const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
        unawaited(_goToLine());
      },
      const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
    };
  }

  CodeHighlightTheme? _highlightTheme(BuildContext context) {
    final language = _language;
    if (!_highlightEnabled || language == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final key = '$language-${isDark ? 'dark' : 'light'}';
    if (_cachedHighlightKey != key) {
      _cachedHighlightKey = key;
      _cachedHighlightTheme = buildEditorHighlightTheme(
        language: language,
        dark: isDark,
        enabled: _highlightEnabled,
      );
    }
    return _cachedHighlightTheme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = _document;

    return PopScope(
      canPop: !_isModified,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)!.close,
            onPressed: () => unawaited(_closeEditor()),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  widget.file.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (_isModified) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Modified',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (_language != null)
              IconButton(
                icon: Icon(
                  _highlightEnabled ? Icons.code : Icons.code_off,
                  size: 20,
                ),
                tooltip: _highlightEnabled
                    ? 'Disable syntax highlighting'
                    : 'Enable syntax highlighting',
                onPressed: _toggleHighlighting,
              ),
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      Icons.save,
                      color: _isModified ? theme.colorScheme.primary : null,
                    ),
                    tooltip: 'Save (Ctrl/Cmd+S)',
                    onPressed: _isModified
                        ? () => unawaited(_saveFile())
                        : null,
                  ),
            PopupMenuButton<_EditorMenuAction>(
              tooltip: 'Editor options',
              onSelected: _handleMenuAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _EditorMenuAction.find,
                  child: Text('Find…'),
                ),
                PopupMenuItem(
                  value: _EditorMenuAction.replace,
                  child: Text('Find and replace…'),
                ),
                PopupMenuItem(
                  value: _EditorMenuAction.goToLine,
                  child: Text('Go to line…'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _EditorMenuAction.wordWrap,
                  child: Text('Toggle word wrap'),
                ),
                PopupMenuItem(
                  value: _EditorMenuAction.highlight,
                  child: Text('Toggle syntax highlighting'),
                ),
                PopupMenuDivider(),
                const PopupMenuItem(
                  value: _EditorMenuAction.reopenEncoding,
                  child: Text('Reopen using encoding…'),
                ),
                PopupMenuItem(
                  value: _EditorMenuAction.reload,
                  child: Text('Reload from disk'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_conflictDetected)
              MaterialBanner(
                content: const Text(
                  'The original file could not be safely saved. Your edits are '
                  'still here. Retry after reconnecting, or reload the original.',
                ),
                leading: const Icon(Icons.warning, color: Colors.orange),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() => _conflictDetected = false);
                      unawaited(_saveFile(force: true));
                    },
                    child: const Text('Retry save'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _conflictDetected = false);
                      unawaited(_loadFile());
                    },
                    child: Text(AppLocalizations.of(context)!.reload),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _conflictDetected = false),
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                ],
              ),
            Expanded(child: _buildBody(theme)),
            if (!_loading && _error == null && document != null)
              _buildStatusBar(document),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(_EditorMenuAction action) async {
    switch (action) {
      case _EditorMenuAction.find:
        _openFind();
        break;
      case _EditorMenuAction.replace:
        _openFind(replace: true);
        break;
      case _EditorMenuAction.goToLine:
        await _goToLine();
        break;
      case _EditorMenuAction.wordWrap:
        _toggleWordWrap();
        break;
      case _EditorMenuAction.highlight:
        _toggleHighlighting();
        break;
      case _EditorMenuAction.reopenEncoding:
        await _reopenEncoding();
        break;
      case _EditorMenuAction.reload:
        await _reloadFromDisk();
        break;
    }
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: _shortcuts,
      child: CodeEditor(
        controller: _controller,
        findController: _findController,
        scrollController: _scrollController,
        focusNode: _focusNode,
        autofocus: true,
        wordWrap: _wordWrap,
        autocompleteSymbols: true,
        toolbarController: const CodeEditorSelectionToolbarController(),
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'AppMono',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
          fontHeight: 1.45,
          textColor: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surface,
          selectionColor: theme.colorScheme.primary.withValues(alpha: 0.24),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.36),
          cursorColor: theme.colorScheme.primary,
          cursorLineColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          chunkIndicatorColor: theme.colorScheme.onSurfaceVariant,
          codeTheme: _highlightTheme(context),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                    textStyle: TextStyle(
                      fontFamily: 'AppMono',
                      fontSize: 12,
                      height: 1.45,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.65,
                      ),
                    ),
                    focusedTextStyle: TextStyle(
                      fontFamily: 'AppMono',
                      fontSize: 12,
                      height: 1.45,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
        leadingDivider: Container(width: 1, color: theme.dividerColor),
        findBuilder: (context, controller, readOnly) => CodeEditorFindPanel(
          controller: controller,
          editingController: _controller,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Widget _buildStatusBar(EditorDocument document) {
    return CodeEditorStatusBar(
      lineEndingPolicy: document.lineEndingPolicy,
      onPolicySelected: _setEndingPolicy,
      onNewLineEndingSelected: _setNewLineEnding,
      writesBom: document.writesBom,
      onToggleBom: document.encoding == EditorEncoding.latin1 ? null : _toggleBom,
      cursorLine: _cursorLine,
      cursorColumn: _cursorColumn,
      lineCount: _lineCount,
      language: _language,
      lineEnding: document.lineEnding,
      encoding: document.encoding,
      isModified: _isModified,
      isSaving: _isSaving,
      hadMixedLineEndings: document.hadMixedLineEndings,
      onLineEndingSelected: _setLineEnding,
      onEncodingSelected: _setEncoding,
    );
  }
}

enum _EditorMenuAction { find, replace, goToLine, wordWrap, highlight, reload, reopenEncoding }
