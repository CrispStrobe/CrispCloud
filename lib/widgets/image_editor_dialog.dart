import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pro_image_editor/pro_image_editor.dart';

import '../l10n/image_editor_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../services/image_edit_session.dart';
import '../services/image_editor_menu.dart';
import '../services/image_file_store.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import 'image_editor_surface.dart';

const _log = Log('ImageEditor');

Future<void> showImageEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog.fullscreen(
    child: ImageEditorDialog(file: file, side: side),
  ),
);

/// F4 image editing with host-owned commands and truthful asynchronous saves.
class ImageEditorDialog extends ConsumerStatefulWidget {
  const ImageEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.storeOverride,
    this.editorKey,
    this.enableIsolateGeneration = true,
  });

  final FileItem file;
  final PanelSide side;

  /// Optional embedding/test seams. Production captures a source-bound store.
  final ImageFileStore? storeOverride;
  final GlobalKey<ProImageEditorState>? editorKey;
  final bool enableIsolateGeneration;

  @override
  ConsumerState<ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends ConsumerState<ImageEditorDialog> {
  late final GlobalKey<ProImageEditorState> _editorKey =
      widget.editorKey ?? GlobalKey<ProImageEditorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _focus = FocusNode(debugLabel: 'CrispCloudImageEditor');
  Expando<int> _historyTokens = Expando<int>();
  EditorStateHistory? _originalHistory;
  int _nextToken = 1;
  ImageFileStore? _store;
  ImageEditSession? _session;
  Uint8List? _initialBytes;
  ImageFileInfo? _info;
  ProviderContainer? _container;
  ImageEditorMenuActions? _menuActions;
  bool _loading = true;
  bool _loadInProgress = false;
  bool _ready = false;
  bool _closing = false;
  bool _applying = false;
  bool _allowPop = false;
  bool _refreshScheduled = false;
  SubEditor? _tool;
  String? _errorKey;

  bool get _saving => _session?.isSaving ?? false;
  bool get _busy => _saving || _closing || _applying || _allowPop;
  bool get _dirty => _session?.isDirty ?? false;
  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;
  bool get _toolOpen =>
      _tool != null || (_editorKey.currentState?.isSubEditorOpen ?? false);
  bool get _canEdit => _routeIsCurrent && _ready && !_loading && !_busy && !_toolOpen &&
      !(_editorKey.currentState?.isLayerBeingTransformed ?? false);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
    _scheduleRefresh();
  }

  @override
  void dispose() {
    final container = _container;
    final actions = _menuActions;
    scheduleMicrotask(() {
      try {
        if (container != null &&
            identical(container.read(imageEditorMenuProvider), actions)) {
          container.read(imageEditorMenuProvider.notifier).state = null;
        }
      } catch (_) {
        // The host's ProviderScope may already have been disposed.
      }
    });
    _session?.removeListener(_scheduleRefresh);
    _session?.dispose();
    _focus.dispose();
    super.dispose();
  }

  ImageFileStore _captureStore() {
    if (widget.storeOverride case final store?) return store;
    final panel = ref.read(panelProvider(widget.side));
    final selectedSource = ref.read(panelSourceProvider(widget.side));
    if (panel.isInArchive || selectedSource.isArchive || selectedSource.isContainer) {
      throw const _ImageOpenMessage(
        'Extract this file from its archive or container before editing.',
      );
    }
    final origin = panel.originForFile(widget.file);
    if (origin == null) {
      throw const _ImageOpenMessage(
        'Refresh this folder before editing. The file’s source could not be verified.',
      );
    }
    final source = origin.source;
    if (source is LocalPanelSource) {
      return ImageFileStore.local(
        service: ref.read(localFileServiceProvider),
        file: widget.file,
      );
    }
    if (source is! RemotePanelSource) {
      throw const _ImageOpenMessage(
        'Extract this file from its archive or container before editing.',
      );
    }
    return ImageFileStore.remote(
      client: source.client,
      providerName: source.providerName,
      cache: ref.read(fileCacheProvider),
      file: widget.file.path == null
          ? widget.file.copyWith(path: p.posix.join(source.path, widget.file.name))
          : widget.file,
      isCurrentAccount: () => mounted && origin.isCurrent,
    );
  }

  Future<void> _load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _ready = false;
        _errorKey = null;
      });
    }
    try {
      // Check listing size before touching storage (including unsupported origins).
      if ((widget.file.size ?? 0) > kImageEditorInputLimitBytes) {
        throw const ImageEditException(ImageEditFailure.inputTooLarge);
      }
      final store = _store ??= _captureStore();
      final bytes = await store.load();
      if (!mounted) return;
      final info = inspectEditableImage(bytes, fileName: widget.file.name);
      // Validate compressed pixels with Flutter's real decoder before handing
      // them to a renderer which would otherwise stay on its loading surface.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        if (codec.frameCount != 1) {
          throw const ImageEditException(ImageEditFailure.animatedImage);
        }
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      _session?.removeListener(_scheduleRefresh);
      _session?.dispose();
      _session = ImageEditSession(initialBytes: bytes, format: info.format)
        ..addListener(_scheduleRefresh);
      _historyTokens = Expando<int>();
      _originalHistory = null;
      _nextToken = 1;
      setState(() {
        _initialBytes = Uint8List.fromList(bytes);
        _info = info;
        _loading = false;
        _errorKey = null;
      });
    } catch (error, stack) {
      _log.warn('Could not load image', error, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = _messageFor(error, 'Could not open image');
      });
    } finally {
      _loadInProgress = false;
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    if (!mounted || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      setState(() {});
      _publishMenu();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ImageEditorMenuActions _actions() => ImageEditorMenuActions(
    perform: _perform,
    canSave: _dirty,
    canUndo: _editorKey.currentState?.canUndo ?? false,
    canRedo: _editorKey.currentState?.canRedo ?? false,
    busy: _busy || !_routeIsCurrent,
    canEdit: _canEdit,
  );

  void _publishMenu() {
    final actions = _actions();
    _menuActions = actions;
    _container?.read(imageEditorMenuProvider.notifier).state = actions;
  }

  void _onHistory(StateManager history, ProImageEditorState editor) {
    if (!mounted || history.stateHistory.isEmpty) return;
    final active = history.stateHistory[history.historyPointer];
    // Indexes can be reused by branching/truncation, even index zero. Only
    // the original object is clean at open; weak tokens do not retain all
    // pruned histories and their potentially large image/layer graphs.
    _originalHistory ??= history.stateHistory.first;
    final token = _historyTokens[active] ??=
        identical(active, _originalHistory) ? 0 : _nextToken++;
    _session?.updateRevision(token);
    _scheduleRefresh();
  }

  void _onGestureEnd(List<Layer> layers) {
    final editor = _editorKey.currentState;
    if (editor == null || layers.isEmpty || !editor.isLayerBeingTransformed) return;
    final history = editor.stateManager;
    final active = history.stateHistory[history.historyPointer];
    // Gesture history is created before the drag, then mutated in place.
    // Advancing its token at release makes any changed saved entry dirty.
    _historyTokens[active] = _nextToken++;
    _onHistory(history, editor);
  }

  void _perform(ImageEditorAction action) {
    if (!_actions().isEnabled(action)) return;
    final editor = _editorKey.currentState;
    switch (action) {
      case ImageEditorAction.save:
        unawaited(_save());
      case ImageEditorAction.close:
        unawaited(_close());
      case ImageEditorAction.undo:
        editor?.undoAction();
      case ImageEditorAction.redo:
        editor?.redoAction();
      case ImageEditorAction.cropRotate:
        editor?.openCropRotateEditor();
      case ImageEditorAction.paint:
        editor?.openPaintEditor();
      case ImageEditorAction.text:
        editor?.openTextEditor();
      case ImageEditorAction.filter:
        editor?.openFilterEditor();
      case ImageEditorAction.blur:
        editor?.openBlurEditor();
      case ImageEditorAction.tune:
        editor?.openTuneEditor();
    }
    _scheduleRefresh();
  }

  Future<bool> _save() async {
    final session = _session;
    final store = _store;
    final editor = _editorKey.currentState;
    if (session == null || store == null || editor == null ||
        !_canEdit || !session.isDirty) {
      return false;
    }
    try {
      final outcome = await session.save(
        export: () async {
          // Paint the input lock before taking the image snapshot.
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) throw StateError('Image editor disposed');
          return editor.captureEditorImage();
        },
        write: store.save,
      );
      if (!mounted) return false;
      if (outcome != ImageSaveOutcome.savedOriginal) {
        _showMessage('A copy was downloaded. The original image has not been updated.');
        return false;
      }
      _showMessage(session.isDirty ? 'New changes remain unsaved.' : 'Image saved');
      // Refresh failures must not turn a completed write into a failed save.
      if (widget.storeOverride == null) {
        ref.read(panelProvider(widget.side)).refreshFiles();
      }
      return !session.isDirty;
    } catch (error, stack) {
      _log.warn('Could not save image', error, stack);
      if (mounted) {
        _showMessage(_messageFor(error, 'Could not save image'), error: true);
      }
      return false;
    } finally {
      _scheduleRefresh();
    }
  }

  Future<void> _applyTool() async {
    if (_busy || !_toolOpen) return;
    final editor = _editorKey.currentState;
    if (editor == null || editor.isSubEditorClosing) return;
    setState(() => _applying = true);
    _scheduleRefresh();
    try {
      switch (_tool) {
        case SubEditor.paint:
          await editor.paintEditor.currentState?.done();
        case SubEditor.text:
          editor.textEditor.currentState?.done();
        case SubEditor.cropRotate:
          await editor.cropRotateEditor.currentState?.done();
        case SubEditor.filter:
          await editor.filterEditor.currentState?.done();
        case SubEditor.blur:
          await editor.blurEditor.currentState?.done();
        case SubEditor.tune:
          await editor.tuneEditor.currentState?.done();
        default:
          break;
      }
    } catch (error, stack) {
      _log.warn('Could not apply image tool', error, stack);
      if (mounted) {
        setState(() => _applying = false);
        _showMessage('Could not apply changes', error: true);
      }
    } finally {
      // Keep commands locked through the tool's reverse route transition.
      // onEndCloseSubEditor releases the lock once the host surface is active.
      _scheduleRefresh();
    }
  }

  Future<void> _close() async {
    // Native commands can arrive while a tool popup or Settings overlays the
    // editor. Never pop that unrelated route or discard unseen changes.
    if (_busy || !_routeIsCurrent) return;
    if (_toolOpen) {
      _editorKey.currentState?.closeSubEditor();
      return;
    }
    if (!_dirty) {
      _pop();
      return;
    }
    setState(() => _closing = true);
    _scheduleRefresh();
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('image-unsaved-dialog'),
        title: Text(context.imageTr('Unsaved changes')),
        content: Text(context.imageTr('Save changes before closing?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: Text(context.imageTr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(context.imageTr('Discard')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(context.imageTr('Save')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _closing = false);
    if (action == 'discard' || (action == 'save' && await _save())) {
      _pop();
    }
    _scheduleRefresh();
  }

  void _pop() {
    if (!mounted || _allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _showMessage(String key, {bool error = false}) {
    _messenger.currentState?.showSnackBar(SnackBar(
      content: Text(context.imageTr(key)),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  String _messageFor(Object error, String fallback) => switch (error) {
    _ImageOpenMessage(:final key) => key,
    ImageAccountChangedException() =>
      'The storage account changed. Reopen the image before saving.',
    ImageSaveConflictException() =>
      'The original image changed or could not be verified. Reopen it before saving.',
    ImageEditException(:final reason) => switch (reason) {
      ImageEditFailure.unsupportedFormat => 'Only PNG and JPEG images can be edited.',
      ImageEditFailure.formatMismatch => 'The image contents do not match the filename extension.',
      ImageEditFailure.invalidImage => 'This image is invalid or could not be decoded.',
      ImageEditFailure.animatedImage => 'Animated images cannot be overwritten by this editor.',
      ImageEditFailure.inputTooLarge => 'Image editing is limited to files up to 32 MiB.',
      ImageEditFailure.outputTooLarge => 'The edited image exceeds the 64 MiB save limit.',
      ImageEditFailure.dimensionsTooLarge => 'This image exceeds the 40 megapixel or 16384 pixel dimension limit.',
      ImageEditFailure.staleExport => 'The image changed during export. Please save again.',
    },
    _ => fallback,
  };

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    final bindings = <ShortcutActivator, VoidCallback>{
      for (final meta in [false, true]) ...{
        SingleActivator(LogicalKeyboardKey.keyS, control: !meta, meta: meta):
            () => _perform(ImageEditorAction.save),
        SingleActivator(LogicalKeyboardKey.keyW, control: !meta, meta: meta):
            () => _perform(ImageEditorAction.close),
        SingleActivator(LogicalKeyboardKey.keyZ, control: !meta, meta: meta):
            () => _perform(ImageEditorAction.undo),
        SingleActivator(LogicalKeyboardKey.keyZ, control: !meta, meta: meta, shift: true):
            () => _perform(ImageEditorAction.redo),
      },
      const SingleActivator(LogicalKeyboardKey.keyY, control: true):
          () => _perform(ImageEditorAction.redo),
      const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_close()),
    };
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          autofocus: true,
          focusNode: _focus,
          child: ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(actions),
                    const Divider(height: 1),
                    Expanded(child: _body()),
                    if (_saving) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ImageEditorMenuActions actions) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 12, 4),
            child: Row(children: [
              IconButton(
                key: const ValueKey('image-close'),
                tooltip: context.imageTr('Close editor'),
                onPressed: actions.isEnabled(ImageEditorAction.close)
                    ? () => _perform(ImageEditorAction.close) : null,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(widget.file.name, overflow: TextOverflow.ellipsis)),
              if (_dirty) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Tooltip(
                  message: context.imageTr('Unsaved changes'),
                  child: Icon(Icons.circle, size: 9,
                    semanticLabel: context.imageTr('Unsaved changes'),
                    color: colors.primary),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('image-save'),
                onPressed: actions.isEnabled(ImageEditorAction.save)
                    ? () => _perform(ImageEditorAction.save) : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(context.imageTr(_saving ? 'Saving…' : 'Save')),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              if (!_toolOpen) ...[
              for (final action in _toolActions)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: TextButton.icon(
                    key: ValueKey('image-${action.$1.name}'),
                    onPressed: actions.isEnabled(action.$1)
                        ? () => _perform(action.$1) : null,
                    icon: Icon(action.$3, size: 18),
                    label: Text(context.imageTr(action.$2)),
                  ),
                ),
              ],
              if (_toolOpen) ...[
                TextButton(
                  key: const ValueKey('image-cancel-tool'),
                  onPressed: _busy ? null : () => _editorKey.currentState?.closeSubEditor(),
                  child: Text(context.imageTr('Cancel tool')),
                ),
                FilledButton(
                  key: const ValueKey('image-apply-tool'),
                  onPressed: _busy ? null : () => unawaited(_applyTool()),
                  child: Text(context.imageTr('Apply')),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(context.imageTr('Loading image…')),
      ]));
    }
    if (_errorKey case final error?) {
      return Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.broken_image_outlined, size: 40),
          const SizedBox(height: 12),
          Text(context.imageTr(error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => unawaited(_load()),
            child: Text(context.imageTr('Retry'))),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: AbsorbPointer(
          absorbing: _saving || _closing || _applying,
          child: ImageEditorSurface(
            bytes: _initialBytes!,
            info: _info!,
            editorKey: _editorKey,
            enableIsolateGeneration: widget.enableIsolateGeneration,
            callbacks: ProImageEditorCallbacks(
              onCloseEditor: (_) => unawaited(_close()),
              mainEditorCallbacks: MainEditorCallbacks(
                onStateHistoryChange: _onHistory,
                onLayerInteractionEnd: _onGestureEnd,
                onScaleStart: (_) => _scheduleRefresh(),
                onScaleEnd: (_) => _scheduleRefresh(),
                onImageDecoded: () {
                  _ready = true;
                  final editor = _editorKey.currentState;
                  if (editor != null) _onHistory(editor.stateManager, editor);
                  _scheduleRefresh();
                },
                onOpenSubEditor: (tool) {
                  _tool = tool;
                  _scheduleRefresh();
                },
                onEndCloseSubEditor: (_) {
                  _tool = null;
                  _applying = false;
                  _scheduleRefresh();
                },
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(context.imageTr('Edited images are flattened. Metadata may be removed.'),
          style: Theme.of(context).textTheme.bodySmall),
      ),
    ]);
  }

  static const _toolActions = <(ImageEditorAction, String, IconData)>[
    (ImageEditorAction.undo, 'Undo', Icons.undo),
    (ImageEditorAction.redo, 'Redo', Icons.redo),
    (ImageEditorAction.cropRotate, 'Crop and rotate', Icons.crop_rotate),
    (ImageEditorAction.paint, 'Draw', Icons.brush_outlined),
    (ImageEditorAction.text, 'Text', Icons.text_fields),
    (ImageEditorAction.tune, 'Adjust', Icons.tune),
    (ImageEditorAction.filter, 'Filters', Icons.filter_outlined),
    (ImageEditorAction.blur, 'Blur', Icons.blur_on),
  ];
}

class _ImageOpenMessage implements Exception {
  const _ImageOpenMessage(this.key);
  final String key;
}
