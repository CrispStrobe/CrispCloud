import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../l10n/gallery_viewer_strings.dart';
import '../l10n/gallery_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/gallery_media_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../services/gallery_device_export.dart';
import '../services/gallery_media_service.dart';
import '../services/image_edit_session.dart';
import '../services/log_service.dart';
import '../utils/formatters.dart';
import 'file_editor_dialog.dart';
import 'gallery_annotations_dialog.dart';

typedef GalleryImageLoader = Future<GalleryImageData> Function(FileItem file);
typedef GalleryThumbnailLoader = Future<Uint8List?> Function(FileItem file);
typedef GalleryOriginalExporter = Future<GalleryExportResult?> Function(
  FileItem file,
);

/// Open the panel's current image sequence without changing its sort, filter,
/// selection or location. Each read retains the source captured on entry.
Future<void> showGalleryViewer(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
  FileItem initialFile, {
  bool slideshow = false,
  bool compare = false,
}) async {
  final images = List<FileItem>.unmodifiable(
    files.where((file) => !file.isFolder),
  );
  if (images.isEmpty || (compare && (images.length < 2 || images.length > 4))) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.galleryViewerTr(compare
            ? 'Select two to four images to compare.'
            : 'No images to display.')),
      ),
    );
    return;
  }

  final service = ref.read(galleryMediaServiceProvider);
  final saveCopyTitle = context.galleryViewerTr('Save original copy');
  // FileItem equality may identify a path without identifying the account.
  // Requests are deliberately bound to these exact listing objects.
  final requests = Map<FileItem, GalleryMediaRequest>.identity();
  final captureErrors = Map<FileItem, Object>.identity();
  for (final file in images) {
    try {
      requests[file] = captureGalleryMediaRequest(ref, side, file);
    } catch (error) {
      captureErrors[file] = error;
    }
  }
  GalleryMediaRequest requestFor(FileItem file) {
    final error = captureErrors[file];
    if (error != null) throw error;
    return requests[file]!;
  }

  var initialIndex = images.indexWhere((file) => identical(file, initialFile));
  if (initialIndex < 0) initialIndex = 0;
  GalleryViewerResult? result;
  try {
    result = await showDialog<GalleryViewerResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Consumer(builder: (context, viewerRef, _) {
        // Keep an already decoded image tied to the account and listing that
        // supplied it. A read-time guard alone cannot clear idle pixels after
        // logout, switching storage or replacing a browser folder grant.
        viewerRef.watch(authProvider);
        viewerRef.watch(panelSourceProvider(side));
        viewerRef.watch(panelProvider(side));
        return Dialog.fullscreen(child: GalleryViewerDialog(
          files: images,
          initialIndex: initialIndex,
          compare: compare,
          slideshow: slideshow,
          isSourceCurrent: requests.values.every((request) => request.isCurrent),
          imageLoader: (file) => service.loadImage(requestFor(file)),
          thumbnailLoader: (file) =>
              service.loadThumbnail(requestFor(file), size: 128),
          canEdit: (file) {
            final request = requests[file];
            return request != null &&
                request.isCurrent &&
                !request.isArchive &&
                isEditableImageFileName(file.name) &&
                ref.read(panelProvider(side)).originForFile(file) != null;
          },
          onAnnotate: (file) async {
            final request = requests[file];
            if (request == null) return;
            await showGalleryAnnotations(context, ref, {
              request.assetId: file.name,
            });
          },
          catalogBuilder: (_, file) {
            final request = requests[file];
            return request == null
                ? const SizedBox.shrink()
                : _ViewerCatalog(assetId: request.assetId);
          },
          originalExporter: (file) async {
            final bytes = await service.loadOriginal(requestFor(file));
            return exportGalleryFile(
              bytes,
              file.name,
              dialogTitle: saveCopyTitle,
            );
          },
        ));
      }),
    );
    if (!context.mounted) return;
    if (result != null && result.edit) {
      final file = result.file;
      final request = requests[file];
      if (request == null ||
          !request.isCurrent ||
          ref.read(panelProvider(side)).originForFile(file) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.galleryViewerTr(
              'This image’s source has changed. Refresh the folder before editing.',
            )),
          ),
        );
        return;
      }
      await showFileEditorDialog(context, ref, file, side);
    }
  } finally {
    if (context.mounted) {
      final panel = ref.read(panelProvider(side));
      final file = result?.file ?? initialFile;
      if (requests[file]?.isCurrent ?? false) {
        panel.restoreCursorAndFocus(file);
      } else {
        panel.focusList();
      }
    }
  }
}

class GalleryViewerResult {
  const GalleryViewerResult(this.file, {this.edit = false});

  final FileItem file;
  final bool edit;
}

/// Data/callback surface kept independent of panel providers so navigation,
/// slideshow, compare and failed reads can be exercised without cloud accounts.
class GalleryViewerDialog extends StatefulWidget {
  const GalleryViewerDialog({
    super.key,
    required this.files,
    required this.imageLoader,
    required this.thumbnailLoader,
    this.initialIndex = 0,
    this.compare = false,
    this.slideshow = false,
    this.isSourceCurrent = true,
    this.canEdit,
    this.originalExporter,
    this.catalogBuilder,
    this.onAnnotate,
  }) : assert(initialIndex >= 0);

  final List<FileItem> files;
  final GalleryImageLoader imageLoader;
  final GalleryThumbnailLoader thumbnailLoader;
  final int initialIndex;
  final bool compare;
  final bool slideshow;

  /// The host rebuilds this value when source/account provenance changes.
  /// Expiration is permanent for the open viewer; the user opens a fresh
  /// listing to view the new source.
  final bool isSourceCurrent;
  final bool Function(FileItem file)? canEdit;
  final GalleryOriginalExporter? originalExporter;
  final Future<void> Function(FileItem file)? onAnnotate;

  /// Optional host catalog actions (ratings, labels, tags), beside metadata.
  final Widget Function(BuildContext context, FileItem file)? catalogBuilder;

  @override
  State<GalleryViewerDialog> createState() => _GalleryViewerDialogState();
}

enum _Background { dark, light, checkerboard }

enum _MoreCommand {
  rotateLeft,
  flipHorizontal,
  flipVertical,
  reset,
  backgroundDark,
  backgroundLight,
  backgroundCheckerboard,
  smoothPixels,
  slideshowOptions,
  shortcuts,
}

class _GalleryViewerDialogState extends State<GalleryViewerDialog>
    with WidgetsBindingObserver {
  static const _log = Log('GalleryViewer');
  final _focus = FocusNode(debugLabel: 'GalleryViewer');
  final _filmstripScroll = ScrollController();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _slots = <int, _ImageSlot>{};
  final _random = math.Random();
  final _shuffleQueue = <int>[];
  Timer? _slideshowTimer;
  late int _index;
  late bool _compare;
  late bool _playing;
  bool _showFilmstrip = true;
  bool _showMetadata = false;
  bool _linked = true;
  bool _synchronizing = false;
  bool _saving = false;
  bool _smoothPixels = true;
  bool _lifecycleActive = true;
  bool _sourceExpired = false;
  _Background _background = _Background.checkerboard;
  _SlideshowOptions _slideshow = const _SlideshowOptions();

  FileItem? get _file => widget.files.isEmpty ? null : widget.files[_index];
  _ImageSlot? get _active => _slots[_index];
  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;
  bool get _canCompare => widget.files.length >= 2 && widget.files.length <= 4;
  bool get _isSourceCurrent => !_sourceExpired && widget.isSourceCurrent;
  bool get _canEdit =>
      _isSourceCurrent &&
      _file != null &&
      _active?.data != null &&
      _active!.data!.frameCount == 1 &&
      !_active!.data!.isConverted &&
      (widget.canEdit?.call(_file!) ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.files.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.files.length - 1);
    _compare = widget.compare && _canCompare;
    _sourceExpired = !widget.isSourceCurrent;
    _playing = _isSourceCurrent && widget.slideshow && !_compare && widget.files.length > 1;
    _loadVisible();
  }

  @override
  void didUpdateWidget(GalleryViewerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSourceCurrent && !_sourceExpired) {
      _sourceExpired = true;
      _playing = false;
      _slideshowTimer?.cancel();
      _shuffleQueue.clear();
      for (final slot in _slots.values) {
        slot.dispose();
      }
      _slots.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideshowTimer?.cancel();
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _focus.dispose();
    _filmstripScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    if (_lifecycleActive) {
      _armSlideshow();
    } else {
      _slideshowTimer?.cancel();
    }
  }

  String _t(String english) => context.galleryViewerTr(english);

  void _loadVisible() {
    if (!_isSourceCurrent) return;
    final visible = _compare
        ? List<int>.generate(widget.files.length, (index) => index).toSet()
        : widget.files.isEmpty
            ? <int>{}
            : {_index};
    // Keep at most the current image or four comparison images. Filmstrip
    // thumbnails use the separately bounded thumbnail service.
    for (final index in _slots.keys.toList()) {
      if (!visible.contains(index)) _slots.remove(index)!.dispose();
    }
    for (final index in visible) {
      if (_slots.containsKey(index)) continue;
      final slot = _ImageSlot();
      _slots[index] = slot;
      slot.controller.addListener(() => _onTransform(index));
      unawaited(_load(index, slot));
    }
  }

  Future<void> _load(int index, _ImageSlot slot) async {
    try {
      final data = await widget.imageLoader(widget.files[index]);
      if (!mounted || !_isSourceCurrent || !identical(_slots[index], slot)) return;
      setState(() {
        slot.data = data;
        slot.loading = false;
        slot.error = null;
      });
      if (index == _index) _armSlideshow();
    } catch (error, stack) {
      if (!mounted || !_isSourceCurrent || !identical(_slots[index], slot)) return;
      setState(() {
        slot.loading = false;
        slot.error = error;
        if (index == _index) _playing = false;
      });
      _slideshowTimer?.cancel();
      // Retain the stack in the logger for diagnosis without rendering it.
      _log.warn('Gallery read failed', error, stack);
    }
  }

  void _retry(int index) {
    if (!_isSourceCurrent) return;
    _slots.remove(index)?.dispose();
    setState(_loadVisible);
  }

  void _select(int index, {bool manual = true}) {
    if (!_isSourceCurrent || widget.files.isEmpty) return;
    final target = index.clamp(0, widget.files.length - 1);
    if (target == _index) return;
    _slideshowTimer?.cancel();
    if (manual) {
      _shuffleQueue.clear();
      _shuffleCycleCompleted = false;
    }
    setState(() {
      _index = target;
      _loadVisible();
    });
    _scrollFilmstripToCurrent();
    _armSlideshow();
  }

  void _step(int delta) => _select(_index + delta);

  void _scrollFilmstripToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_filmstripScroll.hasClients) return;
      final position = _filmstripScroll.position;
      final target = (_index * 112 + 56 - position.viewportDimension / 2)
          .clamp(0.0, position.maxScrollExtent);
      _filmstripScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _onTransform(int index) {
    if (!mounted || _synchronizing) return;
    if (_compare && _linked) {
      final source = _slots[index]?.controller;
      if (source != null) {
        _synchronizing = true;
        for (final entry in _slots.entries) {
          if (entry.key != index) entry.value.controller.match(source);
        }
        _synchronizing = false;
      }
    }
    setState(() {});
  }

  void _fit() {
    final controller = _active?.controller;
    if (controller == null) return;
    controller.fit();
  }

  void _actualSize() => _active?.controller.actualSize();
  void _zoom(double factor) => _active?.controller.zoom(factor);

  void _rotate(int quarterTurns) {
    final controller = _active?.controller;
    if (controller == null || _active?.data == null) return;
    _synchronizing = true;
    controller.rotate(quarterTurns);
    _synchronizing = false;
    setState(() {});
  }

  void _flip({bool vertical = false}) {
    final controller = _active?.controller;
    if (controller == null || _active?.data == null) return;
    setState(() {
      if (vertical) {
        controller.flipY = !controller.flipY;
      } else {
        controller.flipX = !controller.flipX;
      }
    });
  }

  void _resetView() {
    final controller = _active?.controller;
    if (controller == null) return;
    _synchronizing = true;
    controller.reset();
    _synchronizing = false;
    setState(() {});
  }

  void _toggleCompare() {
    if (!_canCompare) return;
    _slideshowTimer?.cancel();
    setState(() {
      _compare = !_compare;
      _playing = false;
      _loadVisible();
    });
  }

  void _toggleLinked() {
    setState(() => _linked = !_linked);
    if (_linked) _onTransform(_index);
  }

  void _togglePlaying() {
    if (!_isSourceCurrent || _compare || widget.files.length < 2 || _active?.error != null) return;
    if (!_playing) {
      _shuffleQueue.clear();
      _shuffleCycleCompleted = false;
    }
    setState(() => _playing = !_playing);
    if (_playing && _index == widget.files.length - 1 && !_slideshow.shuffle) {
      _select(0);
    }
    _armSlideshow();
  }

  void _armSlideshow() {
    _slideshowTimer?.cancel();
    if (!mounted ||
        !_isSourceCurrent ||
        !_playing ||
        _compare ||
        _saving ||
        !_lifecycleActive ||
        !_routeIsCurrent ||
        _active?.data == null ||
        _active!.loading) {
      return;
    }
    _slideshowTimer = Timer(Duration(seconds: _slideshow.seconds), () {
      if (!mounted || !_isSourceCurrent || !_playing || !_routeIsCurrent) return;
      int? next;
      if (_slideshow.shuffle) {
        if (_shuffleQueue.isEmpty) {
          if (!_slideshow.loop && _shuffleCycleCompleted) {
            setState(() => _playing = false);
            return;
          }
          _shuffleQueue.addAll(
            List<int>.generate(widget.files.length, (index) => index)
                .where((index) => index != _index),
          );
          _shuffleQueue.shuffle(_random);
          _shuffleCycleCompleted = true;
        }
        if (_shuffleQueue.isNotEmpty) next = _shuffleQueue.removeLast();
      } else if (_index + 1 < widget.files.length) {
        next = _index + 1;
      } else if (_slideshow.loop) {
        next = 0;
      }
      if (next == null) {
        setState(() => _playing = false);
      } else {
        _select(next, manual: false);
      }
    });
  }

  bool _shuffleCycleCompleted = false;

  Future<void> _configureSlideshow() async {
    _slideshowTimer?.cancel();
    final result = await showDialog<_SlideshowOptions>(
      context: context,
      builder: (_) => _SlideshowOptionsDialog(initial: _slideshow),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _slideshow = result;
        _shuffleQueue.clear();
        _shuffleCycleCompleted = false;
      });
    }
    _focus.requestFocus();
    _armSlideshow();
  }

  void _close({bool edit = false}) {
    _slideshowTimer?.cancel();
    final file = _file;
    Navigator.of(context).pop(
      file == null ? null : GalleryViewerResult(file, edit: edit),
    );
  }

  Future<void> _saveOriginal() async {
    final exporter = widget.originalExporter;
    final file = _file;
    if (!_isSourceCurrent || _saving || exporter == null || file == null) return;
    _slideshowTimer?.cancel();
    setState(() => _saving = true);
    try {
      final result = await exporter(file);
      if (!mounted || result == null) return;
      _showMessage(result == GalleryExportResult.savedCopy
          ? 'A copy was saved.'
          : 'Download started.');
    } catch (error, stack) {
      _log.warn('Gallery original export failed', error, stack);
      if (mounted) _showMessage('The export could not be completed.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _focus.requestFocus();
        _armSlideshow();
      }
    }
  }

  void _showMessage(String english) {
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(_t(english))));
  }

  Future<void> _annotate() async {
    final file = _file;
    final callback = widget.onAnnotate;
    if (!_isSourceCurrent || file == null || callback == null) return;
    _slideshowTimer?.cancel();
    await callback(file);
    if (!mounted) return;
    _focus.requestFocus();
    _armSlideshow();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_routeIsCurrent ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (!_isSourceCurrent) return KeyEventResult.handled;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      if (key == LogicalKeyboardKey.keyS) {
        unawaited(_saveOriginal());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keyboard.isAltPressed) return KeyEventResult.ignored;
    // Text selection inside metadata retains its native copy/navigation keys.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
    } else if (key == LogicalKeyboardKey.home) {
      _select(0);
    } else if (key == LogicalKeyboardKey.end) {
      _select(widget.files.length - 1);
    } else if (key == LogicalKeyboardKey.space) {
      _togglePlaying();
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoom(1.25);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoom(1 / 1.25);
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _fit();
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      _actualSize();
    } else if (key == LogicalKeyboardKey.keyR) {
      _rotate(keyboard.isShiftPressed ? -1 : 1);
    } else if (key == LogicalKeyboardKey.keyI) {
      setState(() => _showMetadata = !_showMetadata);
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _showFilmstrip = !_showFilmstrip);
      if (_showFilmstrip) _scrollFilmstripToCurrent();
    } else if (key == LogicalKeyboardKey.f4) {
      if (_canEdit) _close(edit: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope<GalleryViewerResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKeyEvent,
            child: LayoutBuilder(
              builder: (context, constraints) => !_isSourceCurrent
                  ? _buildExpiredSource()
                  : Column(
                children: [
                  _buildHeader(),
                  _buildControls(),
                  Expanded(child: _buildWorkspace()),
                  if (_showFilmstrip && widget.files.isNotEmpty && constraints.maxHeight >= 280)
                    _buildFilmstrip(height: constraints.maxHeight >= 440 ? 104 : 72),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildExpiredSource() => Column(children: [
    SizedBox(
      height: 58,
      child: Row(children: [
        _button(Icons.close, 'Close', () => _close(), shortcut: 'Esc'),
        Expanded(child: Text(_t('Image gallery'),
            style: Theme.of(context).textTheme.titleSmall)),
      ]),
    ),
    Expanded(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.link_off, size: 36),
        const SizedBox(height: 16),
        Text(_t('This image’s source has changed. Close the viewer and reopen the folder.'),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => _close(), child: Text(_t('Close'))),
      ]),
    ))),
  ]);

  Widget _buildHeader() {
    final file = _file;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          _button(Icons.close, 'Close', () => _close(), shortcut: 'Esc'),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _compare ? _t('Compare images') : file?.name ?? _t('Image gallery'),
                  key: const ValueKey('gallery-viewer-title'),
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (file != null)
                  Text(
                    '${_index + 1} / ${widget.files.length}'
                    '${_compare ? ' · ${file.name}' : ''}'
                    '${(_active?.controller.hasPreviewTransform ?? false) ? ' · ${_t('Preview only')}' : ''}',
                    key: const ValueKey('gallery-viewer-position'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          _button(Icons.info_outline, 'Metadata', () {
            setState(() => _showMetadata = !_showMetadata);
          }, selected: _showMetadata, shortcut: 'I'),
          _buildMoreMenu(),
        ],
      ),
    );
  }

  Widget _button(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool? selected,
    String? shortcut,
    Key? key,
  }) => IconButton(
    key: key,
    icon: Icon(icon, size: 21),
    tooltip: '${_t(label)}${shortcut == null ? '' : ' ($shortcut)'}',
    isSelected: selected,
    selectedIcon: Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
    onPressed: onPressed,
  );

  Widget _buildControls() {
    final loaded = _active?.data != null;
    final percentage = loaded ? _active?.controller.pixelScale : null;
    return Semantics(
      label: _t('View controls'),
      child: SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _button(Icons.chevron_left, 'Previous image',
                  _index > 0 ? () => _step(-1) : null),
              _button(Icons.chevron_right, 'Next image',
                  _index + 1 < widget.files.length ? () => _step(1) : null),
              const SizedBox(width: 8),
              _button(Icons.fit_screen, 'Fit image', loaded ? _fit : null, shortcut: '0'),
              _button(Icons.crop_original, 'Actual size (1:1)',
                  loaded ? _actualSize : null, shortcut: '1'),
              _button(Icons.remove, 'Zoom out', loaded ? () => _zoom(1 / 1.25) : null),
              SizedBox(
                width: 56,
                child: Text(
                  percentage == null ? '—' : '${(percentage * 100).round()}%',
                  key: const ValueKey('gallery-viewer-zoom'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _button(Icons.add, 'Zoom in', loaded ? () => _zoom(1.25) : null),
              const SizedBox(width: 8),
              _button(Icons.rotate_right, 'Rotate right',
                  loaded ? () => _rotate(1) : null, shortcut: 'R'),
              _button(Icons.flip, 'Flip horizontally', loaded ? () => _flip() : null),
              const SizedBox(width: 8),
              if (!_compare) ...[
                _button(_playing ? Icons.pause : Icons.play_arrow,
                    _playing ? 'Pause slideshow' : 'Start slideshow',
                    widget.files.length > 1 && _active?.error == null ? _togglePlaying : null,
                    shortcut: 'Space'),
                _button(Icons.timer_outlined, 'Slideshow options', _configureSlideshow),
              ],
              if (_canCompare)
                _button(_compare ? Icons.image_outlined : Icons.compare,
                    _compare ? 'Single image' : 'Compare images', _toggleCompare),
              if (_compare)
                _button(_linked ? Icons.link : Icons.link_off,
                    _linked ? 'Unlink zoom and pan' : 'Link zoom and pan',
                    _toggleLinked, selected: _linked),
              _button(Icons.view_carousel_outlined, 'Filmstrip', () {
                setState(() => _showFilmstrip = !_showFilmstrip);
                if (_showFilmstrip) _scrollFilmstripToCurrent();
              }, selected: _showFilmstrip, shortcut: 'F'),
              _button(Icons.edit_outlined, 'Edit image',
                  _canEdit ? () => _close(edit: true) : null, shortcut: 'F4'),
              if (widget.onAnnotate != null)
                IconButton(
                  icon: const Icon(Icons.label_outline, size: 21),
                  tooltip: context.galleryTr('Catalog annotations'),
                  onPressed: _file == null ? null : _annotate,
                ),
              if (widget.originalExporter != null)
                _saving
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Tooltip(
                          message: _t('Loading original…'),
                          child: const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : _button(Icons.download_outlined, 'Save original copy',
                        _file == null ? null : _saveOriginal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu() => PopupMenuButton<_MoreCommand>(
    tooltip: _t('More'),
    onOpened: () => _slideshowTimer?.cancel(),
    onCanceled: _armSlideshow,
    onSelected: (command) {
      switch (command) {
        case _MoreCommand.rotateLeft:
          _rotate(-1);
        case _MoreCommand.flipHorizontal:
          _flip();
        case _MoreCommand.flipVertical:
          _flip(vertical: true);
        case _MoreCommand.reset:
          _resetView();
        case _MoreCommand.backgroundDark:
          setState(() => _background = _Background.dark);
        case _MoreCommand.backgroundLight:
          setState(() => _background = _Background.light);
        case _MoreCommand.backgroundCheckerboard:
          setState(() => _background = _Background.checkerboard);
        case _MoreCommand.smoothPixels:
          setState(() => _smoothPixels = !_smoothPixels);
        case _MoreCommand.slideshowOptions:
          unawaited(_configureSlideshow());
          return;
        case _MoreCommand.shortcuts:
          unawaited(_showShortcuts());
          return;
      }
      _armSlideshow();
    },
    itemBuilder: (_) => [
      _menuItem(_MoreCommand.rotateLeft, 'Rotate left'),
      _menuItem(_MoreCommand.flipHorizontal, 'Flip horizontally'),
      _menuItem(_MoreCommand.flipVertical, 'Flip vertically'),
      _menuItem(_MoreCommand.reset, 'Reset view'),
      const PopupMenuDivider(),
      _checkedItem(_MoreCommand.backgroundDark, 'Dark background', _background == _Background.dark),
      _checkedItem(_MoreCommand.backgroundLight, 'Light background', _background == _Background.light),
      _checkedItem(_MoreCommand.backgroundCheckerboard, 'Checkerboard background', _background == _Background.checkerboard),
      _checkedItem(_MoreCommand.smoothPixels, 'Smooth pixels', _smoothPixels),
      const PopupMenuDivider(),
      _menuItem(_MoreCommand.slideshowOptions, 'Slideshow options'),
      _menuItem(_MoreCommand.shortcuts, 'Keyboard shortcuts'),
    ],
  );

  PopupMenuItem<_MoreCommand> _menuItem(_MoreCommand value, String label) =>
      PopupMenuItem(value: value, child: Text(_t(label)));

  CheckedPopupMenuItem<_MoreCommand> _checkedItem(
    _MoreCommand value, String label, bool checked,
  ) => CheckedPopupMenuItem(value: value, checked: checked, child: Text(_t(label)));

  Future<void> _showShortcuts() async {
    _slideshowTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Keyboard shortcuts')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('← / →   ${_t('Previous image')} / ${_t('Next image')}'),
              Text('Home / End   ${_t('First / last image')}'),
              Text('Space   ${_t('Start slideshow')} / ${_t('Pause slideshow')}'),
              Text('+ / −   ${_t('Zoom in')} / ${_t('Zoom out')}'),
              Text('0   ${_t('Fit image')}'),
              Text('1   ${_t('Actual size (1:1)')}'),
              Text('R / Shift+R   ${_t('Rotate right')} / ${_t('Rotate left')}'),
              Text('I   ${_t('Metadata')}'),
              Text('F   ${_t('Filmstrip')}'),
              Text('F4   ${_t('Edit image')}'),
              Text('Ctrl/Cmd+S   ${_t('Save original copy')}'),
              Text('Esc   ${_t('Close')}'),
            ],
          ),
        ),
        actions: [TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('Close')),
        )],
      ),
    );
    if (!mounted) return;
    _focus.requestFocus();
    _armSlideshow();
  }

  Widget _buildWorkspace() => LayoutBuilder(
    builder: (context, constraints) {
      final images = widget.files.isEmpty
          ? Center(child: Text(_t('No images to display.')))
          : _compare ? _buildComparison() : _buildImage(_index);
      if (!_showMetadata || _file == null) return images;
      if (constraints.maxWidth >= 900) {
        return Row(children: [
          Expanded(child: images),
          const VerticalDivider(width: 1),
          SizedBox(width: 300, child: _buildMetadata()),
        ]);
      }
      return Column(children: [
        Expanded(child: images),
        const Divider(height: 1),
        SizedBox(
          height: math.min(240.0, constraints.maxHeight * 0.45),
          child: _buildMetadata(),
        ),
      ]);
    },
  );

  Widget _buildComparison() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = widget.files.length > 2 || constraints.maxWidth >= 600 ? 2 : 1;
      final rows = (widget.files.length / columns).ceil();
      return Column(
        children: List<Widget>.generate(rows, (row) => Expanded(
          child: Row(
            children: List<Widget>.generate(columns, (column) {
              final index = row * columns + column;
              return Expanded(
                child: index < widget.files.length
                    ? _buildImage(index)
                    : const SizedBox.expand(),
              );
            }),
          ),
        )),
      );
    },
  );

  Widget _buildImage(int index) {
    final file = widget.files[index];
    final slot = _slots[index];
    final scheme = Theme.of(context).colorScheme;
    final selected = index == _index;
    return Semantics(
      label: file.name,
      selected: _compare ? selected : null,
      child: Listener(
        onPointerDown: (_) {
          _focus.requestFocus();
          if (_compare && !selected) _select(index);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: _compare
                ? Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 2)
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.all(_compare ? 2 : 0),
            child: Column(
              children: [
                if (_compare)
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: AlignmentDirectional.centerStart,
                    color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: slot == null || slot.loading
                      ? Center(child: SingleChildScrollView(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(_t('Loading image…')),
                          ],
                        )))
                      : slot.error != null
                          ? _buildLoadError(index, slot.error!)
                          : _GalleryCanvas(
                              key: ValueKey('gallery-canvas-$index'),
                              data: slot.data!,
                              controller: slot.controller,
                              background: _background,
                              smoothPixels: _smoothPixels,
                              onDoubleTap: () {
                                _select(index);
                                if ((slot.controller.pixelScale - 1).abs() < 0.01) {
                                  slot.controller.fit();
                                } else {
                                  slot.controller.actualSize();
                                }
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadError(int index, Object error) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 40),
          const SizedBox(height: 12),
          Text(_t('Could not load this image.'), textAlign: TextAlign.center),
          if (error is GalleryMediaException) ...[
            const SizedBox(height: 8),
            Text(error.message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _retry(index),
            icon: const Icon(Icons.refresh),
            label: Text(_t('Retry')),
          ),
        ],
      ),
    ),
  );

  Widget _buildMetadata() {
    final file = _file!;
    final data = _active?.data;
    final values = <String, String>{
      _t('Name'): file.name,
      if (file.path != null) _t('Path'): file.path!,
      _t('Format'): file.extension.isEmpty ? _t('Unknown') : file.extension.toUpperCase(),
      if (data != null) _t('Dimensions'): '${data.width} × ${data.height}',
      if (file.size != null) _t('File size'): formatBytes(file.size!),
      if (file.updatedAt != null)
        _t('Modified'): DateFormat.yMd(Localizations.localeOf(context).toString())
            .add_Hms().format(file.updatedAt!.toLocal()),
      if (data != null && data.frameCount > 1) _t('Frames'): '${data.frameCount}',
      if (data != null) ...data.metadata,
    };
    final transformed = _active?.controller.hasPreviewTransform ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_t('Metadata'), style: Theme.of(context).textTheme.titleSmall),
        if (widget.catalogBuilder != null) ...[
          const SizedBox(height: 12),
          widget.catalogBuilder!(context, file),
        ],
        const SizedBox(height: 16),
        for (final entry in values.entries) Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 3),
              SelectableText(entry.value, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (data?.isConverted ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_t('Converted preview of the first frame.'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        if (transformed)
          Text(_t('Preview transforms only. Use Edit image to save changes.'),
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildFilmstrip({required double height}) => SizedBox(
    key: const ValueKey('gallery-filmstrip'),
    height: height,
    child: ListView.builder(
      controller: _filmstripScroll,
      scrollDirection: Axis.horizontal,
      itemExtent: 112,
      itemCount: widget.files.length,
      itemBuilder: (context, index) => _FilmstripTile(
        key: ValueKey('gallery-filmstrip-$index'),
        file: widget.files[index],
        thumbnailLoader: widget.thumbnailLoader,
        selected: _index == index,
        onTap: () {
          _select(index);
          _focus.requestFocus();
        },
      ),
    ),
  );
}

class _ImageSlot {
  final controller = _ImageViewController();
  GalleryImageData? data;
  Object? error;
  bool loading = true;

  void dispose() {
    data = null;
    error = null;
    controller.dispose();
  }
}

/// InteractiveViewer transforms a viewport-sized child. Geometry maps that
/// viewport back to the fitted image rectangle for true pixel size and linked
/// comparison of different image aspect ratios.
class _ImageViewController extends ChangeNotifier {
  _ImageViewController() {
    transformation.addListener(_changed);
  }

  final transformation = TransformationController();
  Size? _viewport;
  Size? _source;
  double _devicePixelRatio = 1;
  int _geometryRevision = 0;
  bool _disposed = false;
  int turns = 0;
  bool flipX = false;
  bool flipY = false;

  bool get hasPreviewTransform => turns != 0 || flipX || flipY;
  double get scale => transformation.value.getMaxScaleOnAxis();

  Size? get rotatedSize {
    final source = _source;
    if (source == null) return null;
    return turns.isEven ? source : Size(source.height, source.width);
  }

  Rect? get imageRect {
    final viewport = _viewport;
    final image = rotatedSize;
    if (viewport == null || image == null || image.isEmpty || viewport.isEmpty) {
      return null;
    }
    final fitted = applyBoxFit(BoxFit.contain, image, viewport).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & viewport);
  }

  double get pixelScale {
    final image = rotatedSize;
    final rect = imageRect;
    return image == null || rect == null
        ? 1
        : scale * rect.width * _devicePixelRatio / image.width;
  }

  void setGeometry(Size viewport, Size source, double devicePixelRatio) {
    if (_viewport == viewport &&
        _source == source &&
        _devicePixelRatio == devicePixelRatio) {
      return;
    }
    final preservePixels = _viewport != null && _source == source &&
        (scale - 1).abs() > 0.00001;
    final oldPixelScale = pixelScale;
    final oldCenter = _normalizedCenter();
    final revision = ++_geometryRevision;
    _viewport = viewport;
    _source = source;
    _devicePixelRatio = devicePixelRatio;
    // LayoutBuilder is currently building. Publish the percentage after this
    // frame instead of notifying an ancestor during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || revision != _geometryRevision) return;
      final image = rotatedSize;
      final rect = imageRect;
      if (preservePixels && image != null && rect != null) {
        _setView(oldPixelScale * image.width /
            (rect.width * _devicePixelRatio), oldCenter);
      } else {
        notifyListeners();
      }
    });
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void fit() => transformation.value = Matrix4.identity();

  void actualSize() {
    final image = rotatedSize;
    final rect = imageRect;
    if (image == null || rect == null || rect.width == 0) return;
    _setScale(image.width / (rect.width * _devicePixelRatio));
  }

  void zoom(double factor) => _setScale(scale * factor);

  void _setScale(double requested) {
    final viewport = _viewport;
    if (viewport == null || viewport.isEmpty) return;
    final next = requested.clamp(0.00001, 16384.0);
    final center = viewport.center(Offset.zero);
    final scene = transformation.toScene(center);
    transformation.value = Matrix4.identity()
      ..translateByDouble(center.dx - scene.dx * next,
          center.dy - scene.dy * next, 0, 1)
      ..scaleByDouble(next, next, next, 1);
  }

  void rotate(int value) {
    turns = (turns + value) % 4;
    fit();
  }

  void reset() {
    turns = 0;
    flipX = false;
    flipY = false;
    fit();
  }

  void match(_ImageViewController other) {
    if (other._viewport == null || other.imageRect == null) return;
    _setView(other.scale, other._normalizedCenter());
  }

  Offset _normalizedCenter() {
    final viewport = _viewport;
    final rect = imageRect;
    if (viewport == null || rect == null) return const Offset(0.5, 0.5);
    final scene = transformation.toScene(viewport.center(Offset.zero));
    return Offset((scene.dx - rect.left) / rect.width,
        (scene.dy - rect.top) / rect.height);
  }

  void _setView(double requested, Offset center) {
    final viewport = _viewport;
    final rect = imageRect;
    if (viewport == null || rect == null) return;
    final sceneX = rect.left + center.dx * rect.width;
    final sceneY = rect.top + center.dy * rect.height;
    final next = requested.clamp(0.00001, 16384.0);
    transformation.value = Matrix4.identity()
      ..translateByDouble(viewport.width / 2 - sceneX * next,
          viewport.height / 2 - sceneY * next, 0, 1)
      ..scaleByDouble(next, next, next, 1);
  }

  @override
  void dispose() {
    _disposed = true;
    transformation.removeListener(_changed);
    transformation.dispose();
    super.dispose();
  }
}

class _GalleryCanvas extends StatelessWidget {
  const _GalleryCanvas({
    super.key,
    required this.data,
    required this.controller,
    required this.background,
    required this.smoothPixels,
    required this.onDoubleTap,
  });

  final GalleryImageData data;
  final _ImageViewController controller;
  final _Background background;
  final bool smoothPixels;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      controller.setGeometry(size, Size(data.width.toDouble(), data.height.toDouble()),
          MediaQuery.devicePixelRatioOf(context));
      final backgroundColor = background == _Background.light
          ? const Color(0xfff1f1f1) : const Color(0xff17191d);
      final image = data.isSvg
          ? SvgPicture.memory(data.bytes,
              width: data.width.toDouble(), height: data.height.toDouble(),
              fit: BoxFit.fill)
          : Image.memory(
              data.bytes,
              width: data.width.toDouble(),
              height: data.height.toDouble(),
              fit: BoxFit.fill,
              filterQuality: smoothPixels ? FilterQuality.medium : FilterQuality.none,
              gaplessPlayback: false,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
              ),
            );
      return ColoredBox(
        color: backgroundColor,
        child: CustomPaint(
          painter: background == _Background.checkerboard
              ? const _CheckerboardPainter() : null,
          child: GestureDetector(
            onDoubleTap: onDoubleTap,
            child: InteractiveViewer(
              transformationController: controller.transformation,
              minScale: 0.00001,
              maxScale: 16384,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Transform.flip(
                    flipX: controller.flipX,
                    flipY: controller.flipY,
                    child: RotatedBox(quarterTurns: controller.turns, child: image),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 16.0;
    final paint = Paint()..color = const Color(0xff22252a);
    for (var row = 0; row * step < size.height; row++) {
      for (var column = row.isEven ? 0 : 1; column * step < size.width; column += 2) {
        canvas.drawRect(Rect.fromLTWH(column * step, row * step, step, step), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) => false;
}

class _FilmstripTile extends StatefulWidget {
  const _FilmstripTile({
    super.key,
    required this.file,
    required this.thumbnailLoader,
    required this.selected,
    required this.onTap,
  });

  final FileItem file;
  final GalleryThumbnailLoader thumbnailLoader;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilmstripTile> createState() => _FilmstripTileState();
}

class _FilmstripTileState extends State<_FilmstripTile> {
  late Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = Future<Uint8List?>.sync(() => widget.thumbnailLoader(widget.file));
  }

  @override
  void didUpdateWidget(_FilmstripTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) {
      _thumbnail = Future<Uint8List?>.sync(() => widget.thumbnailLoader(widget.file));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.file.name,
      child: Tooltip(
        message: widget.file.name,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: widget.selected ? scheme.primaryContainer : null,
                border: Border.all(
                  color: widget.selected ? scheme.primary : scheme.outlineVariant,
                  width: widget.selected ? 2 : 1,
                ),
              ),
              child: Column(children: [
                Expanded(child: FutureBuilder<Uint8List?>(
                  future: _thumbnail,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      if (GalleryMediaService.bytesAreSvg(snapshot.data!)) {
                        return SvgPicture.memory(snapshot.data!, fit: BoxFit.contain);
                      }
                      return Image.memory(snapshot.data!, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined));
                    }
                    return Icon(snapshot.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
                        color: scheme.onSurfaceVariant);
                  },
                )),
                const SizedBox(height: 4),
                Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerCatalog extends ConsumerWidget {
  const _ViewerCatalog({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(galleryCatalogProvider);
    final record = catalog.get(assetId);
    String t(String value) => context.galleryTr(value);
    Future<void> update({int? rating, bool? favorite}) async {
      try {
        await catalog.update([assetId], rating: rating, favorite: favorite);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('Save failed'))),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            for (var rating = 1; rating <= 5; rating++)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(rating <= record.rating ? Icons.star : Icons.star_border),
                color: Theme.of(context).colorScheme.primary,
                tooltip: '${t('Rating')}: $rating/5',
                onPressed: () => update(rating: record.rating == rating ? 0 : rating),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              isSelected: record.favorite,
              icon: const Icon(Icons.favorite_border),
              selectedIcon: const Icon(Icons.favorite),
              tooltip: t('Favorite'),
              onPressed: () => update(favorite: !record.favorite),
            ),
          ],
        ),
        if (record.color != GalleryColor.none || record.tags.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (record.color != GalleryColor.none)
              Chip(
                avatar: Icon(Icons.circle, size: 14, color: galleryLabelColor(record.color)),
                label: Text(t(galleryColorName(record.color))),
              ),
            for (final tag in record.tags)
              Chip(label: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        const SizedBox(height: 8),
        Text(t('Catalog saved on this device; image metadata is unchanged.'),
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SlideshowOptions {
  const _SlideshowOptions({this.seconds = 3, this.loop = true, this.shuffle = false});
  final int seconds;
  final bool loop;
  final bool shuffle;
}

class _SlideshowOptionsDialog extends StatefulWidget {
  const _SlideshowOptionsDialog({required this.initial});
  final _SlideshowOptions initial;

  @override
  State<_SlideshowOptionsDialog> createState() => _SlideshowOptionsDialogState();
}

class _SlideshowOptionsDialogState extends State<_SlideshowOptionsDialog> {
  late int _seconds = widget.initial.seconds;
  late bool _loop = widget.initial.loop;
  late bool _shuffle = widget.initial.shuffle;

  @override
  Widget build(BuildContext context) {
    String t(String english) => context.galleryViewerTr(english);
    return AlertDialog(
      title: Text(t('Slideshow options')),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _seconds,
              decoration: InputDecoration(labelText: t('Interval')),
              items: [1, 2, 3, 5, 10, 15, 30].map((seconds) => DropdownMenuItem(
                value: seconds, child: Text('$seconds ${t('seconds')}'),
              )).toList(),
              onChanged: (value) { if (value != null) setState(() => _seconds = value); },
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: Text(t('Loop')),
              value: _loop,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => _loop = value ?? true),
            ),
            CheckboxListTile(
              title: Text(t('Shuffle')),
              value: _shuffle,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => _shuffle = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('Cancel'))),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _SlideshowOptions(seconds: _seconds, loop: _loop, shuffle: _shuffle),
          ),
          child: Text(t('Apply')),
        ),
      ],
    );
  }
}
