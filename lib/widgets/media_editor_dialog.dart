import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../l10n/media_editor_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/media_audio_backend.dart';
import '../services/media_capabilities.dart';
import '../services/media_edit_session.dart';
import '../services/media_editor_backend.dart';
import '../services/media_editor_menu.dart';
import '../services/media_file_store.dart';
import '../services/media_video_backend.dart';
import '../services/panel_source_service.dart';
import 'media_editor_controls.dart';
import 'media_editor_preview.dart';

/// A portable default name, leaving room for the unique suffix and extension
/// within the store's 240-byte filename limit. Iterate Unicode code points so
/// shortening a name cannot split a surrogate pair or an encoded UTF-8 byte.
String defaultMediaExportFileName(String sourceName, String extension) {
  final sourceStem = p
      .basenameWithoutExtension(sourceName)
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim();
  final shortened = StringBuffer();
  var bytes = 0;
  for (final rune in sourceStem.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > 160) break;
    shortened.write(character);
    bytes += length;
  }
  final stem = shortened.toString().trim().replaceAll(RegExp(r'[. ]+$'), '');
  return '${stem.isEmpty ? 'media' : stem}-edited-'
      '${const Uuid().v4().substring(0, 8)}.$extension';
}

Future<void> showMediaEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog.fullscreen(
    child: MediaEditorDialog(file: file, side: side),
  ),
);

/// Host-owned single-file media workflow. The original is staged once and all
/// edits are recipes; a successful render is not a save until the copy persists.
class MediaEditorDialog extends ConsumerStatefulWidget {
  const MediaEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.storeOverride,
    this.backendOverride,
    this.playbackAvailableOverride,
  });
  final FileItem file;
  final PanelSide side;
  final MediaFileStore? storeOverride;
  final MediaEditorBackend? backendOverride;
  final bool? playbackAvailableOverride;
  @override
  ConsumerState<MediaEditorDialog> createState() => _MediaEditorDialogState();
}

class _MediaEditorDialogState extends ConsumerState<MediaEditorDialog> {
  static const _log = Log('MediaEditor');
  final _controlsKey = GlobalKey<MediaEditorControlsState>();
  MediaFileStore? _store;
  MediaEditorBackend? _backend;
  MediaEditSession? _session;
  ProviderContainer? _container;
  MediaEditorMenuActions? _menu;
  MediaCancellation? _cancellation;
  Future<void>? _activeWork;
  String? _inputPath;
  String? _renderedPath;
  MediaInfo? _renderedInfo;
  int? _renderedRevision;
  List<double> _peaks = const [];
  String? _errorKey;
  String? _statusKey;
  String? _lastFileName;
  bool _loading = true;
  bool _loadInProgress = false;
  bool _working = false;
  bool _saving = false;
  bool _naming = false;
  bool _previewingRendered = false;
  bool _allowPop = false;
  bool _menuScheduled = false;
  double _progress = 0;

  bool get _busy => _loading || _working || _naming;
  bool get _canPreview =>
      widget.playbackAvailableOverride ?? MediaCapabilities.hasInlinePreview;
  String get _extension =>
      _session?.info.kind == MediaKind.audio ? 'wav' : 'mp4';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
    _scheduleMenu();
  }

  void _startLoad() {
    if (!mounted || _working || _loadInProgress) return;
    _loadInProgress = true;
    _activeWork = _load();
    unawaited(_activeWork);
  }

  MediaFileStore _captureStore() {
    if (widget.storeOverride case final store?) return store;
    final panel = ref.read(panelProvider(widget.side));
    final selected = ref.read(panelSourceProvider(widget.side));
    if (panel.isInArchive || selected.isArchive || selected.isContainer) {
      throw const _MediaOpenMessage(
        'Extract this file from its archive or container before editing.',
      );
    }
    final origin = panel.originForFile(widget.file);
    if (origin == null) {
      throw const _MediaOpenMessage(
        'Refresh this folder before editing. The file’s source could not be verified.',
      );
    }
    final source = origin.source;
    if (source is LocalPanelSource) {
      return MediaFileStore.local(
        service: ref.read(localFileServiceProvider),
        file: widget.file,
      );
    }
    if (source is RemotePanelSource) {
      return MediaFileStore.remote(
        client: source.client,
        providerName: source.providerName,
        cache: ref.read(fileCacheProvider),
        file: widget.file.path == null
            ? widget.file.copyWith(
                path: p.posix.join(source.path, widget.file.name),
              )
            : widget.file,
        isCurrentAccount: () => mounted && origin.isCurrent,
      );
    }
    throw const _MediaOpenMessage(
      'Extract this file from its archive or container before editing.',
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    _scheduleMenu();
    try {
      final kind = mediaKindForFileName(widget.file.name);
      if (kind == null ||
          (widget.backendOverride == null &&
              !MediaCapabilities.canEdit(kind))) {
        throw const _MediaOpenMessage(
          'This media format cannot be edited on this platform.',
        );
      }
      final store = _store ??= _captureStore();
      final backend = _backend ??=
          widget.backendOverride ??
          (kind == MediaKind.audio ? MediaAudioBackend() : MediaVideoBackend());
      final inputPath = await store.stage();
      if (!mounted) return;
      final info = await backend.probe(inputPath);
      if (info.kind != kind)
        throw const MediaEditException(MediaEditFailure.invalidMedia);
      final peaks = kind == MediaKind.audio
          ? await backend.waveform(inputPath)
          : const <double>[];
      if (!mounted) return;
      _session?.removeListener(_refresh);
      _session?.dispose();
      _session = MediaEditSession(info)..addListener(_refresh);
      setState(() {
        _inputPath = inputPath;
        _peaks = peaks;
        _loading = false;
      });
    } catch (error, stack) {
      _log.warn('Could not open media', error, stack);
      if (mounted)
        setState(() {
          _loading = false;
          _errorKey = _messageFor(error, 'Could not open media');
        });
    } finally {
      _loadInProgress = false;
      _scheduleMenu();
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _scheduleMenu();
  }

  void _scheduleMenu() {
    if (!mounted || _menuScheduled) return;
    _menuScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuScheduled = false;
      if (!mounted) return;
      final session = _session;
      final actions = MediaEditorMenuActions(
        perform: _perform,
        ready: session != null,
        busy: _busy || !(ModalRoute.of(context)?.isCurrent ?? true),
        canUndo: session?.canUndo ?? false,
        canRedo: session?.canRedo ?? false,
        canPreview: _canPreview,
      );
      _menu = actions;
      _container?.read(mediaEditorMenuProvider.notifier).state = actions;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _perform(MediaEditorAction action) {
    if (_busy || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    switch (action) {
      case MediaEditorAction.exportCopy:
        unawaited(_exportCopy());
      case MediaEditorAction.close:
        unawaited(_requestClose());
      case MediaEditorAction.undo:
        if (_session?.canUndo ?? false) {
          _session!.undo();
          _didEdit();
        }
      case MediaEditorAction.redo:
        if (_session?.canRedo ?? false) {
          _session!.redo();
          _didEdit();
        }
      case MediaEditorAction.preview:
        if (_canPreview && _session != null) _startRender();
    }
  }

  void _apply(MediaEdit edit) {
    if (_busy) return;
    try {
      _session!.apply(edit);
      _didEdit();
    } catch (error) {
      setState(() => _errorKey = _messageFor(error, 'Could not apply changes'));
    }
  }

  void _didEdit() {
    _previewingRendered = false;
    _statusKey = null;
    _errorKey = null;
    // Preserve one verified render for failed-save retries, but never reuse it
    // for a different history revision. Remove it on the next render or close.
    _refresh();
  }

  Future<String?> _chooseFileName() async {
    final initial =
        _lastFileName ??
        defaultMediaExportFileName(widget.file.name, _extension);
    return _showEditorPrompt(
      (_) => _MediaExportNameDialog(initialFileName: initial),
    );
  }

  Future<String?> _showEditorPrompt(WidgetBuilder builder) async {
    setState(() => _naming = true);
    _scheduleMenu();
    try {
      // Let the controls finish losing focus and updating their accessibility
      // nodes before a second modal route hides this editor's semantics.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<String>(
        context: context,
        builder: builder,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        barrierColor:
            DialogTheme.of(context).barrierColor ??
            Theme.of(context).dialogTheme.barrierColor ??
            Colors.black54,
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      );
      final result = await navigator.push(route);
      // Flutter 3.47 can retain stale slider semantics if a blocked subtree is
      // rebuilt while a dialog disappears (flutter/flutter#193706). Re-enable
      // the controls only after the modal barrier has actually been removed.
      await route.completed;
      await WidgetsBinding.instance.endOfFrame;
      return result;
    } finally {
      if (mounted) setState(() => _naming = false);
      _scheduleMenu();
    }
  }

  Future<void> _exportCopy() async {
    if (_busy || _session == null) return;
    if (!(_controlsKey.currentState?.commit() ?? true)) return;
    final name = await _chooseFileName();
    if (!mounted || name == null) return;
    if (name.isEmpty ||
        !name.toLowerCase().endsWith('.$_extension') ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name)) {
      setState(
        () =>
            _errorKey = 'Choose a simple filename with the correct extension.',
      );
      return;
    }
    _lastFileName = name;
    _startRender(fileName: name);
    await _activeWork;
  }

  void _startRender({String? fileName}) {
    if (_busy || _session == null) return;
    if (!(_controlsKey.currentState?.commit() ?? true)) return;
    _activeWork = _render(fileName: fileName);
    unawaited(_activeWork);
  }

  Future<void> _render({String? fileName}) async {
    final session = _session!;
    final cancellation = MediaCancellation();
    _cancellation = cancellation;
    setState(() {
      _working = true;
      _progress = 0;
      _errorKey = null;
      _statusKey = null;
    });
    MediaEditRevision? revision;
    String? pendingOutputPath;
    var persisted = false;
    try {
      revision = session.beginExport();
      if (_renderedRevision != revision.id || _renderedPath == null) {
        final oldPath = _renderedPath;
        _renderedPath = null;
        _renderedInfo = null;
        _renderedRevision = null;
        if (oldPath != null) {
          try {
            await File(oldPath).delete();
          } catch (_) {}
        }
        final outputPath = await _store!.createOutputPath(_extension);
        pendingOutputPath = outputPath;
        await _backend!.render(
          inputPath: _inputPath!,
          outputPath: outputPath,
          edit: revision.edit,
          cancellation: cancellation,
          onProgress: (value) {
            if (mounted && value.isFinite)
              setState(() => _progress = value.clamp(0, 1).toDouble());
          },
        );
        cancellation.throwIfCancelled();
        final info = await _backend!.probe(outputPath);
        _validateOutput(session.info, revision.edit, info);
        _renderedPath = outputPath;
        _renderedInfo = info;
        _renderedRevision = revision.id;
        pendingOutputPath = null;
      }
      cancellation.throwIfCancelled();
      if (!mounted) return;
      if (fileName != null) {
        setState(() => _saving = true);
        await _store!.saveCopy(_renderedPath!, fileName);
        persisted = true;
        if (!mounted) return;
        setState(() {
          _statusKey = 'Copy exported';
          _lastFileName = null;
        });
        // Refresh the panel only; the captured store always owns the destination.
        if (widget.storeOverride == null)
          ref.read(panelProvider(widget.side)).refreshFiles();
      } else {
        setState(() => _previewingRendered = true);
      }
    } on MediaOperationCancelled {
      if (mounted) setState(() => _statusKey = 'Export cancelled');
    } catch (error, stack) {
      _log.warn('Could not export media', error, stack);
      if (mounted)
        setState(
          () => _errorKey = _messageFor(error, 'Could not export media'),
        );
    } finally {
      // A completed native file is not retained until the host's independent
      // probe/validation succeeds. Remove it immediately after a failure so
      // repeated retries cannot fill the editor's temporary workspace.
      if (pendingOutputPath != null) {
        try {
          final pending = File(pendingOutputPath);
          if (await pending.exists()) await pending.delete();
        } catch (error, stack) {
          _log.warn(
            'Could not remove an unverified media export',
            error,
            stack,
          );
        }
      }
      _cancellation = null;
      if (mounted) {
        if (revision != null)
          session.finishExport(revision, persisted: persisted);
        setState(() {
          _working = false;
          _saving = false;
        });
        _scheduleMenu();
      }
    }
  }

  void _validateOutput(MediaInfo source, MediaEdit edit, MediaInfo output) {
    final reportedFrameRate = source.frameRate;
    final frameRate =
        reportedFrameRate != null &&
            reportedFrameRate.isFinite &&
            reportedFrameRate > 0
        ? reportedFrameRate
        : 24.0;
    final reportedSampleRate = source.sampleRate;
    final sampleRate = reportedSampleRate != null && reportedSampleRate > 0
        ? reportedSampleRate
        : 48000;
    final toleranceUs = source.kind == MediaKind.audio
        ? math.max(1000, (2000000 / sampleRate).ceil())
        : math.max(100000, (2000000 / frameRate).ceil());
    if (output.kind != source.kind ||
        output.duration <= Duration.zero ||
        (output.duration - edit.duration).inMicroseconds.abs() > toleranceUs) {
      throw const MediaStoreException(MediaStoreFailure.invalidOutput);
    }
  }

  Future<void> _requestClose() async {
    if (_busy || !mounted) return;
    if (!(_controlsKey.currentState?.commit() ?? true)) return;
    if (_session?.isDirty ?? false) {
      final decision = await _showEditorPrompt(
        (dialogContext) => AlertDialog(
          title: Text(dialogContext.mediaTr('Export changes before closing?')),
          content: Text(dialogContext.mediaTr('Unsaved changes will be lost.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(dialogContext.mediaTr('Continue editing')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: Text(dialogContext.mediaTr('Discard')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'export'),
              child: Text(dialogContext.mediaTr('Export copy')),
            ),
          ],
        ),
      );
      if (!mounted || decision == null || decision == 'cancel') return;
      if (decision == 'export') {
        await _exportCopy();
        if (!mounted || (_session?.isDirty ?? true)) return;
      }
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  String _messageFor(Object error, String fallback) {
    if (error is _MediaOpenMessage) return error.message;
    if (error is MediaStoreException)
      return switch (error.reason) {
        MediaStoreFailure.accountChanged =>
          'The storage account changed. Reopen the file before exporting.',
        MediaStoreFailure.tooLarge =>
          error.limitBytes == kMediaRemoteTransferLimitBytes
              ? 'Cloud media editing is limited to 64 MiB per file.'
              : 'Local media editing is limited to 2 GiB per file.',
        MediaStoreFailure.invalidName =>
          'Choose a simple filename with the correct extension.',
        MediaStoreFailure.nameConflict =>
          'A file with this name already exists. Choose another name.',
        MediaStoreFailure.unverifiedDestination ||
        MediaStoreFailure.sourceChanged ||
        MediaStoreFailure.sourceUnavailable => 'The destination could not be verified. Refresh the folder and try again.',
        MediaStoreFailure.accessDenied =>
          'Access to this folder was not granted.',
        MediaStoreFailure.emptyOutput || MediaStoreFailure.invalidOutput =>
          'The exported file could not be verified. Try exporting again.',
        MediaStoreFailure.unsupported =>
          'This media format cannot be edited on this platform.',
        _ => fallback,
      };
    return fallback;
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _session?.removeListener(_refresh);
    _session?.dispose();
    final work = _activeWork;
    final store = _store;
    unawaited(() async {
      try {
        await work;
      } catch (_) {}
      try {
        await store?.dispose();
      } catch (error, stack) {
        _log.warn('Could not remove media workspace', error, stack);
      }
    }());
    final container = _container;
    final menu = _menu;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (container != null &&
            identical(container.read(mediaEditorMenuProvider), menu)) {
          container.read(mediaEditorMenuProvider.notifier).state = null;
        }
      } catch (_) {}
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final title = mediaKindForFileName(widget.file.name) == MediaKind.audio
        ? 'Audio editor'
        : 'Video editor';
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestClose());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              _perform(MediaEditorAction.exportCopy),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              _perform(MediaEditorAction.exportCopy),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              _perform(MediaEditorAction.undo),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
              _perform(MediaEditorAction.undo),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () =>
              _perform(MediaEditorAction.redo),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): () =>
              _perform(MediaEditorAction.redo),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _perform(MediaEditorAction.close),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                tooltip: context.mediaTr('Close editor'),
                onPressed: _busy ? null : _requestClose,
                icon: const Icon(Icons.close),
              ),
              title: Text(
                '${context.mediaTr(title)} · ${widget.file.name}',
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: context.mediaTr('Undo'),
                  onPressed: !_busy && (session?.canUndo ?? false)
                      ? () => _perform(MediaEditorAction.undo)
                      : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: context.mediaTr('Redo'),
                  onPressed: !_busy && (session?.canRedo ?? false)
                      ? () => _perform(MediaEditorAction.redo)
                      : null,
                  icon: const Icon(Icons.redo),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: IconButton.filledTonal(
                    tooltip: context.mediaTr('Export copy'),
                    onPressed: !_busy && session != null ? _exportCopy : null,
                    icon: const Icon(Icons.file_upload_outlined),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(context.mediaTr('Loading media…')),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorKey != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    context.mediaTr(_errorKey!),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (session == null)
                                  OutlinedButton(
                                    onPressed: _startLoad,
                                    child: Text(context.mediaTr('Retry')),
                                  ),
                              ],
                              if (session != null) ...[
                                Text(
                                  context.mediaTr(
                                    _previewingRendered
                                        ? 'Edited preview'
                                        : 'Source preview',
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                MediaEditorPreview(
                                  key: ValueKey(
                                    _previewingRendered
                                        ? _renderedPath!
                                        : _inputPath!,
                                  ),
                                  path: _previewingRendered
                                      ? _renderedPath!
                                      : _inputPath!,
                                  info: _previewingRendered
                                      ? _renderedInfo!
                                      : session.info,
                                  edit: _previewingRendered
                                      ? MediaEdit(
                                          start: Duration.zero,
                                          end: _renderedInfo!.duration,
                                        )
                                      : session.edit,
                                  enabled: !_busy,
                                  playbackAvailable: _canPreview,
                                ),
                                const SizedBox(height: 16),
                                MediaEditorControls(
                                  key: _controlsKey,
                                  info: session.info,
                                  edit: session.edit,
                                  onChanged: _apply,
                                  peaks: _peaks,
                                  enabled: !_busy,
                                ),
                                const SizedBox(height: 24),
                                if (_working) ...[
                                  Text(
                                    context.mediaTr(
                                      _saving ? 'Saving copy…' : 'Exporting…',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _saving ? null : _progress,
                                  ),
                                  if (!_saving)
                                    TextButton(
                                      onPressed: () => _cancellation?.cancel(),
                                      child: Text(
                                        context.mediaTr('Cancel export'),
                                      ),
                                    ),
                                ] else
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _busy ? null : _exportCopy,
                                        icon: const Icon(
                                          Icons.file_upload_outlined,
                                        ),
                                        label: Text(
                                          context.mediaTr('Export copy'),
                                        ),
                                      ),
                                      if (_canPreview)
                                        OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _startRender(),
                                          icon: const Icon(
                                            Icons.play_circle_outline,
                                          ),
                                          label: Text(
                                            context.mediaTr('Preview edit'),
                                          ),
                                        ),
                                    ],
                                  ),
                                if (_statusKey != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(context.mediaTr(_statusKey!)),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Text(
                                  context.mediaTr(
                                    'Exports use WAV audio or MP4 video. The source file is kept.',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The route owns its input for the entire dismissal animation. A showDialog
/// future resolves at pop start, before the outgoing TextField is unmounted.
class _MediaExportNameDialog extends StatefulWidget {
  const _MediaExportNameDialog({required this.initialFileName});
  final String initialFileName;

  @override
  State<_MediaExportNameDialog> createState() => _MediaExportNameDialogState();
}

class _MediaExportNameDialogState extends State<_MediaExportNameDialog> {
  late final _controller = TextEditingController(text: widget.initialFileName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.mediaTr('Export copy')),
    content: SizedBox(
      width: 440,
      child: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.mediaTr('File name')),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.mediaTr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(context.mediaTr('Create copy')),
      ),
    ],
  );
}

class _MediaOpenMessage implements Exception {
  const _MediaOpenMessage(this.message);
  final String message;
}
