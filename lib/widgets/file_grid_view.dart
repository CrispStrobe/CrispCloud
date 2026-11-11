import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gallery_strings.dart';
import '../models/file_item.dart';
import '../models/file_collection.dart';
import '../models/panel_side.dart';
import '../providers/gallery_media_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/focus_area_provider.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart';
import '../services/gallery_device_export.dart';
import '../services/gallery_catalog_service.dart';
import '../services/gallery_media_service.dart';
import '../services/panel_source_service.dart';
import '../services/keyboard_shortcut_service.dart';
import '../utils/formatters.dart';
import 'batch_rename_dialog.dart';
import 'file_context_menu.dart';
import 'file_list_view.dart' show getFileIcon;
import 'folder_drop_target.dart';
import 'folder_size_presentation.dart';
import 'gallery_annotations_dialog.dart';
import 'gallery_export_dialog.dart';
import 'gallery_thumbnail.dart';
import 'gallery_viewer_dialog.dart';

/// Virtualized image-first layouts over the existing panel inventory.
/// Selection uses the exact visible, ordered file objects, including ranges.
class FileGridView extends ConsumerStatefulWidget {
  const FileGridView({
    super.key,
    required this.side,
    required this.files,
    required this.scrollController,
    this.galleryOnly = false,
    this.tileLayout = false,
  });
  final PanelSide side;
  final List<FileItem> files;
  final ScrollController scrollController;
  final bool galleryOnly;
  final bool tileLayout;
  @override
  ConsumerState<FileGridView> createState() => _FileGridViewState();
}

class _FileGridViewState extends ConsumerState<FileGridView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  FileItem? _anchor;
  bool _filtersExpanded = false;
  String? _catalogError;
  List<FileItem> _visible = [];
  Map<FileItem, GalleryMediaRequest?> _requests = Map.identity();
  int _projectionVersion = 0;
  final Object _collectionProjectionOwner = Object();
  PanelNotifier? _projectionPanel;
  Object? _collectionProjectionSignature;
  int _collectionProjectionRequest = 0;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(galleryQueryProvider(widget.side)).text;
    Future<void>.microtask(() async {
      try {
        await ref.read(galleryCatalogProvider).load();
      } catch (error) {
        if (mounted) setState(() => _catalogError = '$error');
      }
    });
  }

  @override
  void dispose() {
    _collectionProjectionRequest++;
    _projectionPanel?.clearCollectionProjection(_collectionProjectionOwner);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String t(String value) => context.galleryTr(value);
  void _query(GalleryQuery value) =>
      ref.read(galleryQueryProvider(widget.side).notifier).state = value;
  GalleryMediaRequest? _request(FileItem file) => _requests.putIfAbsent(
    file,
    () => tryCaptureGalleryMediaRequest(ref, widget.side, file),
  );
  GalleryRecord _record(FileItem file) {
    final request = _request(file);
    return request == null
        ? const GalleryRecord()
        : ref.read(galleryCatalogProvider).get(request.assetId);
  }

  Map<String, String> _catalogNames(Iterable<FileItem> files) => {
    for (final file in files.where(isGalleryImage))
      if (_request(file) case final request?)
        if (request.isCurrent) request.assetId: file.name,
  };
  List<FileItem> _targets({bool imagesOnly = false}) {
    final panel = ref.read(panelProvider(widget.side));
    var result = panel.isPagedCollection
        ? panel.selection.where((file) => file.name != '..').toList()
        : _visible
              .where((file) => file.name != '..' && panel.isSelected(file))
              .toList();
    if (result.isEmpty &&
        panel.cursorItem != null &&
        _visible.any((file) => identical(file, panel.cursorItem))) {
      result = [panel.cursorItem!];
    }
    return imagesOnly ? result.where(isGalleryImage).toList() : result;
  }

  /// Existing file commands still route by side. Only expose them when that
  /// routing agrees with every verified file origin and the selected source.
  bool _canUseFileActions(Iterable<FileItem> files) {
    final targets = files.toList();
    if (targets.isEmpty) return false;
    final panel = ref.read(panelProvider(widget.side));
    if (panel.isPagedCollection) return !panel.collectionBusy;
    final source = ref.read(panelSourceProvider(widget.side));
    final auth = ref.read(authProvider);
    if (panel.isInArchive || panel.isFlatView || panel.showingSearchResults) {
      return false;
    }
    if (widget.side == PanelSide.local && source is! LocalPanelSource) {
      return false;
    }
    if (widget.side == PanelSide.remote &&
        (source is! RemotePanelSource ||
            !identical(source.client, auth.client))) {
      return false;
    }
    return targets.every((file) {
      final origin = panel.originForFile(file);
      if (origin == null || !origin.isCurrent) return false;
      return widget.side == PanelSide.local
          ? origin.source is LocalPanelSource
          : origin.source is RemotePanelSource &&
                identical(
                  (origin.source as RemotePanelSource).client,
                  auth.client,
                );
    });
  }

  void _unavailableActions() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        t(
          'File commands are unavailable for this source. View and export remain available.',
        ),
      ),
    ),
  );

  Future<void> _contextMenu(FileItem file, Offset position) async {
    final panel = ref.read(panelProvider(widget.side));
    if (!panel.isSelected(file)) _select(file);
    final targets = _targets();
    if (_canUseFileActions(targets)) {
      showFileContextMenu(context, ref, widget.side, file, position);
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Text(t(file.isFolder ? 'Folder' : 'Open viewer')),
        ),
        if (isGalleryImage(file)) ...[
          PopupMenuItem(
            value: 'annotations',
            child: Text(t('Catalog annotations')),
          ),
          PopupMenuItem(
            value: 'export',
            child: Text(t('Convert / resize copies')),
          ),
        ],
      ],
    );
    if (!mounted) return;
    if (action == 'open') {
      await _open(file);
    } else if (action == 'annotations') {
      await showGalleryAnnotations(context, ref, _catalogNames(targets));
    } else if (action == 'export') {
      await showGalleryExportDialog(
        context,
        ref,
        widget.side,
        targets.where(isGalleryImage).toList(),
      );
    }
  }

  Future<void> _annotate({int? rating, bool? favorite}) async {
    try {
      final files = await ref
          .read(panelProvider(widget.side))
          .prepareOperationFiles(_targets(imagesOnly: true));
      if (!mounted) return;
      final keys = _catalogNames(files).keys;
      if (keys.isEmpty) return;
      await ref
          .read(galleryCatalogProvider)
          .update(keys, rating: rating, favorite: favorite);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${t('Save failed')}: $error')));
      }
    }
  }

  void _select(FileItem file, {bool shift = false, bool toggle = false}) {
    final panel = ref.read(panelProvider(widget.side));
    if (shift && _anchor != null) {
      final a = _visible.indexWhere((item) => identical(item, _anchor));
      final b = _visible.indexWhere((item) => identical(item, file));
      if (a >= 0 && b >= 0) {
        final range = _visible.sublist(math.min(a, b), math.max(a, b) + 1);
        panel.selectVisibleItems(
          [...(toggle ? panel.selection : <FileItem>[]), ...range],
          cursor: file,
          anchor: _anchor,
        );
        return;
      }
    }
    final chosen = toggle ? panel.selection.toList() : <FileItem>[];
    if (toggle && chosen.contains(file)) {
      chosen.remove(file);
    } else {
      chosen.add(file);
    }
    _anchor = file;
    panel.selectVisibleItems(chosen, cursor: file, anchor: file);
  }

  void _selectAll({bool invert = false}) {
    final panel = ref.read(panelProvider(widget.side));
    if (panel.isPagedCollection) {
      unawaited(
        panel.selectWholeCollection(invert: invert).catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$error')));
          }
        }),
      );
      return;
    }
    panel.selectVisibleItems(
      _visible.where(
        (file) => file.name != '..' && (!invert || !panel.isSelected(file)),
      ),
    );
  }

  void _configureCollectionProjection(
    PanelNotifier panel,
    GalleryQuery query,
    GalleryCatalogService catalog,
    GalleryCatalogIdentityLookup identities,
    Object selectedSource,
  ) {
    if (!panel.isPagedCollection) {
      _collectionProjectionRequest++;
      _projectionPanel?.clearCollectionProjection(_collectionProjectionOwner);
      _projectionPanel = null;
      _collectionProjectionSignature = null;
      return;
    }
    final signature = (
      query,
      catalog.revision,
      identities.signature,
      selectedSource,
      widget.galleryOnly,
      panel.activeCollectionId,
    );
    if (identical(panel, _projectionPanel) &&
        signature == _collectionProjectionSignature) {
      return;
    }
    final previous = _projectionPanel;
    _projectionPanel = panel;
    _collectionProjectionSignature = signature;
    final request = ++_collectionProjectionRequest;
    final revision = catalog.revision;
    final matches = query.matcher(imagesOnly: widget.galleryOnly);
    final records = Expando<GalleryRecord>('collection gallery annotations');
    GalleryRecord record(FileCollectionEntry entry) {
      if (catalog.revision != revision || !identities.isCurrent) {
        throw const GalleryMediaException(
          'The gallery catalog or original account changed. Refresh the collection.',
        );
      }
      if (!query.needsCatalogRecords) return const GalleryRecord();
      final cached = records[entry];
      if (cached != null) return cached;
      final id = identities.assetId(entry.reference);
      return records[entry] = id == null
          ? const GalleryRecord()
          : catalog.get(id);
    }

    // Register outside build. The closures hold only captured service objects,
    // query data and source identities; none reads this widget's ref later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _collectionProjectionRequest) return;
      if (previous != null && !identical(previous, panel)) {
        previous.clearCollectionProjection(_collectionProjectionOwner);
      }
      panel.setCollectionProjection(
        _collectionProjectionOwner,
        signature: signature,
        matches: (entry) => matches(entry.file, record(entry)),
        compare: (a, b) => query.compareFiles(
          a.file,
          b.file,
          aRecord: query.sort == GallerySort.rating
              ? record(a)
              : const GalleryRecord(),
          bRecord: query.sort == GallerySort.rating
              ? record(b)
              : const GalleryRecord(),
        ),
      );
    });
  }

  Future<void> _open(FileItem file, {bool slideshow = false}) async {
    if (file.isFolder || !isGalleryImage(file)) {
      await ref.read(panelProvider(widget.side)).navigateInto(file);
      return;
    }
    await showGalleryViewer(
      context,
      ref,
      widget.side,
      _visible.where(isGalleryImage).toList(),
      file,
      slideshow: slideshow,
    );
    if (mounted) {
      ref.read(panelProvider(widget.side)).listFocusNode.requestFocus();
    }
  }

  Future<void> _compare() async {
    try {
      final files = await ref
          .read(panelProvider(widget.side))
          .prepareOperationFiles(_targets(imagesOnly: true));
      if (!mounted) return;
      if (files.length < 2 || files.length > 4) return;
      await showGalleryViewer(
        context,
        ref,
        widget.side,
        files,
        files.first,
        compare: true,
      );
      if (mounted) {
        ref.read(panelProvider(widget.side)).listFocusNode.requestFocus();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showAnnotations() async {
    try {
      final files = await ref
          .read(panelProvider(widget.side))
          .prepareOperationFiles(_targets(imagesOnly: true));
      if (mounted) {
        await showGalleryAnnotations(context, ref, _catalogNames(files));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  KeyEventResult _onKey(KeyEvent event, int columns, double rowHeight) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        ref.read(activePanelProvider) != widget.side ||
        ref.read(focusAreaProvider).panelSide != widget.side ||
        ref.read(terminalInputFocusedProvider) ||
        _searchFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;
    final panel = ref.read(panelProvider(widget.side));
    final shortcuts = ref.read(keyboardShortcutServiceProvider);
    final command = shortcuts.resolveBrowser(
      event,
      isCtrl: keyboard.isControlPressed,
      isMeta: keyboard.isMetaPressed,
      isShift: keyboard.isShiftPressed,
      isAlt: keyboard.isAltPressed,
    );
    // The effective command owns the key. A rebound function key may now be
    // navigation or filtering, so its former file action must not block it.
    if (command != null && event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final keepExtensionRename =
        command == null &&
        !modifier &&
        !keyboard.isAltPressed &&
        keyboard.isShiftPressed &&
        key == LogicalKeyboardKey.f6;
    if (([
              ShortcutAction.delete,
              ShortcutAction.rename,
              ShortcutAction.copy,
              ShortcutAction.cut,
              ShortcutAction.paste,
              ShortcutAction.copyWithOptions,
              ShortcutAction.moveWithOptions,
            ].contains(command) ||
            keepExtensionRename) &&
        !_canUseFileActions(_targets())) {
      _unavailableActions();
      return KeyEventResult.handled;
    }
    if (command == ShortcutAction.selectAll) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (command == ShortcutAction.filter) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (command != null ||
        modifier ||
        keyboard.isAltPressed ||
        shortcuts.suppressesDefault(
          event,
          isCtrl: keyboard.isControlPressed,
          isMeta: keyboard.isMetaPressed,
          isShift: keyboard.isShiftPressed,
          isAlt: keyboard.isAltPressed,
        )) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      panel.clearSelection();
      return KeyEventResult.handled;
    }
    if (_visible.isEmpty) return KeyEventResult.ignored;
    var index = _visible.indexWhere(
      (item) => identical(item, panel.cursorItem),
    );
    final absent = index < 0;
    if (absent) index = 0;
    final pageRows = widget.scrollController.hasClients
        ? math.max(
            1,
            (widget.scrollController.position.viewportDimension / rowHeight)
                .floor(),
          )
        : 3;
    int? next;
    if (key == LogicalKeyboardKey.arrowRight) {
      next = index + (Directionality.of(context) == TextDirection.rtl ? -1 : 1);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      next = index + (Directionality.of(context) == TextDirection.rtl ? 1 : -1);
    }
    if (key == LogicalKeyboardKey.arrowDown) next = index + columns;
    if (key == LogicalKeyboardKey.arrowUp) next = index - columns;
    if (key == LogicalKeyboardKey.home) next = 0;
    if (key == LogicalKeyboardKey.end) next = _visible.length - 1;
    if (key == LogicalKeyboardKey.pageDown) next = index + columns * pageRows;
    if (key == LogicalKeyboardKey.pageUp) next = index - columns * pageRows;
    if (next != null) {
      if (absent && key != LogicalKeyboardKey.end) next = 0;
      final file = _visible[next.clamp(0, _visible.length - 1)];
      if (modifier && !keyboard.isShiftPressed) {
        panel.setCursorToItem(file);
      } else {
        _anchor ??= panel.cursorItem;
        _select(file, shift: keyboard.isShiftPressed, toggle: modifier);
      }
      return KeyEventResult.handled;
    }
    final current = _visible[index];
    if (key == LogicalKeyboardKey.enter) {
      _open(current);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.insert) {
      _select(current, toggle: true);
      return KeyEventResult.handled;
    }
    if (!modifier && !keyboard.isAltPressed) {
      const ratingKeys = [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ];
      final rating = ratingKeys.indexOf(key);
      if (rating >= 0) {
        _annotate(rating: rating);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyF) {
        _annotate(favorite: !_record(current).favorite);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _reconcileSelection() {
    final version = ++_projectionVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _projectionVersion) return;
      final panel = ref.read(panelProvider(widget.side));
      final visible = Set<FileItem>.identity()..addAll(_visible);
      if (!panel.isPagedCollection &&
          panel.selection.any((file) => !visible.contains(file))) {
        panel.selectVisibleItems(
          panel.selection.where(visible.contains).toList(),
        );
      }
      if (panel.cursorItem != null &&
          !visible.contains(panel.cursorItem) &&
          _visible.isNotEmpty) {
        panel.setCursorToItem(_visible.first);
      }
    });
  }

  void _scrollToCursor(int columns, double rowHeight) {
    final panel = ref.read(panelProvider(widget.side));
    final item = panel.itemToScrollTo;
    if (item == null) return;
    final index = _visible.indexWhere((file) => identical(file, item));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(panel.itemToScrollTo, item)) return;
      panel.clearItemToScrollTo();
      final controller = widget.scrollController;
      if (index < 0 || !controller.hasClients) return;
      final top = 8 + (index ~/ columns) * rowHeight;
      final bottom = top + rowHeight;
      final viewport = controller.position.viewportDimension;
      final target = top < controller.offset
          ? top
          : bottom > controller.offset + viewport
          ? bottom - viewport
          : controller.offset;
      controller.jumpTo(target.clamp(0, controller.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final terminalVisible = ref.watch(showTerminalProvider);
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final source = ref.watch(panelSourceProvider(widget.side));
    final query = ref.watch(galleryQueryProvider(widget.side));
    final prefs = ref.watch(galleryPreferencesProvider(widget.side));
    final catalog = ref.watch(galleryCatalogProvider);
    final identities = captureGalleryCatalogIdentityLookup(ref, widget.side);
    _configureCollectionProjection(panel, query, catalog, identities, source);
    _requests = Map.identity();
    // Paged rows have already been filtered and sorted across the entire
    // collection. Applying the gallery query again here would hide/sort only
    // one window and make its range/count/cursor disagree with the full query.
    final visible = panel.isPagedCollection
        ? List<FileItem>.of(widget.files)
        : query.apply(widget.files, _record, imagesOnly: widget.galleryOnly);
    if (!listEqualsIdentical(_visible, visible)) {
      _visible = visible;
      _reconcileSelection();
    }
    final images = visible.where(isGalleryImage).toList();
    final selected = panel.isPagedCollection
        ? panel.selection.toList()
        : visible
              .where(panel.isSelected)
              .where((file) => file.name != '..')
              .toList();
    final count = _targets(imagesOnly: true).length;
    return Column(
      children: [
        _toolbar(query, prefs, images, selected, count >= 2 && count <= 4),
        if (_filtersExpanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: SingleChildScrollView(child: _filters(query)),
          ),
        if (_catalogError != null)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              '${t('Catalog unavailable')}: $_catalogError',
              maxLines: 2,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxExtent = widget.tileLayout
                  ? prefs.thumbnailSize * 1.8
                  : prefs.thumbnailSize;
              final columns = math.max(
                1,
                ((constraints.maxWidth - 16) / (maxExtent + 8)).ceil(),
              );
              final itemWidth = math.max(
                1.0,
                (constraints.maxWidth - 16 - (columns - 1) * 8) / columns,
              );
              final imageHeight = widget.tileLayout
                  ? math.min(itemWidth * 0.38, prefs.thumbnailSize * 0.58)
                  : itemWidth * 0.76;
              final scaler = MediaQuery.textScalerOf(context);
              final nameHeight = prefs.showNames
                  ? scaler.scale(14) * 2 + 6
                  : 0.0;
              final detailsHeight = prefs.showDetails
                  ? scaler.scale(12) * (widget.tileLayout ? 3 : 2) + 10
                  : 0.0;
              final rowHeight = widget.tileLayout
                  ? math.max(imageHeight + 20, nameHeight + detailsHeight + 20)
                  : imageHeight + nameHeight + detailsHeight + 20;
              _scrollToCursor(columns, rowHeight + 8);
              return Focus(
                focusNode: panel.listFocusNode,
                autofocus:
                    !terminalVisible &&
                    ref.read(activePanelProvider) == widget.side,
                skipTraversal: true,
                onKeyEvent: (_, event) => _onKey(event, columns, rowHeight + 8),
                child: visible.isEmpty
                    ? _empty()
                    : GridView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: rowHeight,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _tile(visible[index], prefs, imageHeight),
                      ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            '${visible.where((f) => f.name != '..').length} ${t('items')} · '
            '${images.length} ${t('images')} · ${selected.length} ${t('selected')}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            t(widget.galleryOnly ? 'No matching images' : 'No matching files'),
          ),
          const SizedBox(height: 6),
          Text(
            t('Try another filter or open a folder.'),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: _clearFilters, child: Text(t('Clear filters'))),
        ],
      ),
    ),
  );
  void _clearFilters() {
    final current = ref.read(galleryQueryProvider(widget.side));
    _search.clear();
    _query(GalleryQuery(sort: current.sort, descending: current.descending));
  }

  Widget _toolbar(
    GalleryQuery query,
    GalleryPreferences prefs,
    List<FileItem> images,
    List<FileItem> selected,
    bool canCompare,
  ) {
    Widget button(IconData icon, String label, VoidCallback? action) =>
        IconButton(
          icon: Icon(icon, size: 20),
          tooltip: t(label),
          onPressed: action,
          visualDensity: VisualDensity.compact,
        );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('gallery-search-${widget.side.name}'),
                    controller: _search,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: t('Search names and tags'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (text) => _query(query.copyWith(text: text)),
                  ),
                ),
                button(
                  query.hasFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  'Filters',
                  () => setState(() => _filtersExpanded = !_filtersExpanded),
                ),
                if (query.hasFilters)
                  button(
                    Icons.filter_alt_off_outlined,
                    'Clear filters',
                    _clearFilters,
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                PopupMenuButton<GallerySort>(
                  tooltip: t('Sort by'),
                  icon: const Icon(Icons.sort, size: 20),
                  initialValue: query.sort,
                  onSelected: (sort) => _query(query.copyWith(sort: sort)),
                  itemBuilder: (_) => [
                    for (final sort in GallerySort.values)
                      CheckedPopupMenuItem(
                        value: sort,
                        checked: query.sort == sort,
                        child: Text(
                          t(switch (sort) {
                            GallerySort.name => 'Name',
                            GallerySort.extension => 'Extension',
                            GallerySort.modified => 'Modified date',
                            GallerySort.size => 'Size',
                            GallerySort.rating => 'Rating',
                          }),
                        ),
                      ),
                  ],
                ),
                button(
                  query.descending ? Icons.south : Icons.north,
                  query.descending ? 'Descending' : 'Ascending',
                  () => _query(query.copyWith(descending: !query.descending)),
                ),
                SizedBox(
                  width: 108,
                  child: Slider(
                    label: '${prefs.thumbnailSize.round()} px',
                    semanticFormatterCallback: (value) =>
                        '${t('Thumbnail size')}: ${value.round()}',
                    value: prefs.thumbnailSize,
                    min: 120,
                    max: 360,
                    divisions: 12,
                    onChanged: (size) => ref
                        .read(galleryPreferencesProvider(widget.side).notifier)
                        .update(prefs.copyWith(thumbnailSize: size)),
                  ),
                ),
                button(
                  prefs.fill ? Icons.fit_screen : Icons.crop,
                  prefs.fill ? 'Fit images' : 'Fill tiles',
                  () => ref
                      .read(galleryPreferencesProvider(widget.side).notifier)
                      .update(prefs.copyWith(fill: !prefs.fill)),
                ),
                button(
                  Icons.slideshow,
                  'Slideshow',
                  images.isEmpty
                      ? null
                      : () {
                          final current = ref
                              .read(panelProvider(widget.side))
                              .cursorItem;
                          _open(
                            images.contains(current) ? current! : images.first,
                            slideshow: true,
                          );
                        },
                ),
                button(
                  Icons.compare_outlined,
                  canCompare
                      ? 'Compare selected images'
                      : 'Select 2–4 images to compare',
                  canCompare ? _compare : null,
                ),
                button(
                  Icons.star_border,
                  'Catalog annotations',
                  _targets(imagesOnly: true).isEmpty ? null : _showAnnotations,
                ),
                PopupMenuButton<String>(
                  tooltip: t('More actions'),
                  icon: const Icon(Icons.more_horiz),
                  onSelected: _action,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'select_all',
                      child: Text(t('Select all visible')),
                    ),
                    PopupMenuItem(
                      value: 'invert',
                      child: Text(t('Invert visible selection')),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      child: Text(t('Clear selection')),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: 'names',
                      checked: prefs.showNames,
                      child: Text(t('Show filenames')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'details',
                      checked: prefs.showDetails,
                      child: Text(t('Show details')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'convert',
                      enabled: _targets(imagesOnly: true).isNotEmpty,
                      child: Text(t('Convert / resize copies')),
                    ),
                    PopupMenuItem(
                      value: 'contact',
                      enabled: images.isNotEmpty,
                      child: Text(t('Contact sheet')),
                    ),
                    PopupMenuItem(
                      value: 'catalog',
                      enabled: images.isNotEmpty,
                      child: Text(t('Export catalog')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'rename',
                      enabled:
                          _targets().length > 1 &&
                          _canUseFileActions(_targets()),
                      child: Text(t('Batch rename')),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      enabled: _canUseFileActions(_targets()),
                      child: Text(t('Copy to…')),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      enabled: _canUseFileActions(_targets()),
                      child: Text(t('Move to…')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled:
                          selected.isNotEmpty && _canUseFileActions(selected),
                      child: Text(t('Delete…')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'help',
                      child: Text(t('Keyboard shortcuts')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(String action) async {
    final panel = ref.read(panelProvider(widget.side));
    final prefs = ref.read(galleryPreferencesProvider(widget.side));
    var targets = _targets();
    if (panel.isPagedCollection &&
        ['convert', 'contact', 'catalog'].contains(action)) {
      try {
        targets = await panel.prepareOperationFiles(targets);
        if (!mounted) return;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
        return;
      }
    }
    final images = targets.where(isGalleryImage).toList();
    final markedImages = panel.isPagedCollection && panel.selection.isNotEmpty
        ? images
        : _visible.where(isGalleryImage).where(panel.isSelected).toList();
    if (['rename', 'copy', 'move', 'delete'].contains(action) &&
        !_canUseFileActions(targets)) {
      _unavailableActions();
      return;
    }
    ref.read(activePanelProvider.notifier).state = widget.side;
    switch (action) {
      case 'select_all':
        _selectAll();
      case 'invert':
        _selectAll(invert: true);
      case 'clear':
        panel.clearSelection();
      case 'names':
        ref
            .read(galleryPreferencesProvider(widget.side).notifier)
            .update(prefs.copyWith(showNames: !prefs.showNames));
      case 'details':
        ref
            .read(galleryPreferencesProvider(widget.side).notifier)
            .update(prefs.copyWith(showDetails: !prefs.showDetails));
      case 'convert':
        await showGalleryExportDialog(context, ref, widget.side, images);
      case 'contact':
        await showGalleryExportDialog(
          context,
          ref,
          widget.side,
          markedImages.isEmpty
              ? _visible.where(isGalleryImage).toList()
              : markedImages,
          contactSheet: true,
        );
      case 'catalog':
        try {
          final exportFiles =
              (markedImages.isEmpty
                      ? _visible.where(isGalleryImage)
                      : markedImages)
                  .toList();
          final requests = exportFiles.map(_request).toList();
          if (requests.isEmpty || requests.any((request) => request == null)) {
            throw const GalleryMediaException(
              'The image sources could not be verified. Refresh the folder before exporting.',
            );
          }
          final catalog = ref.read(galleryCatalogProvider);
          await catalog.load();
          if (!mounted) return;
          for (final request in requests) {
            request!.assertCurrent();
          }
          final names = {
            for (final request in requests) request!.assetId: request.file.name,
          };
          await exportGalleryFile(
            Uint8List.fromList(utf8.encode(catalog.exportJson(names))),
            'crispcloud-catalog.json',
            mimeType: 'application/json',
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${t('Export failed')}: $error')),
            );
          }
        }
      case 'rename':
        if (targets.isNotEmpty) {
          showBatchRenameDialog(context, ref, widget.side, targets);
        }
      case 'copy':
        if (targets.isNotEmpty) {
          showCopyDialog(context, ref, widget.side, targets);
        }
      case 'move':
        if (targets.isNotEmpty) {
          showMoveDialog(context, ref, widget.side, targets);
        }
      case 'delete':
        if (targets.isNotEmpty) {
          confirmDelete(context, ref, widget.side, targets);
        }
      case 'help':
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('Keyboard shortcuts')),
            content: Text(
              t(
                'Arrows: navigate · Shift: extend · Ctrl/Cmd+A: select visible · Enter: open · 0–5: rate · F: favorite',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Close')),
              ),
            ],
          ),
        );
    }
  }

  Widget _filters(GalleryQuery query) {
    final extensions =
        widget.files
            .where(
              (f) => !f.isFolder && (!widget.galleryOnly || isGalleryImage(f)),
            )
            .map((f) => f.extension)
            .toSet()
            .toList()
          ..sort();
    if (query.extension.isNotEmpty && !extensions.contains(query.extension)) {
      extensions.add(query.extension);
    }
    Widget dropdown<T>(
      String label,
      T value,
      List<DropdownMenuItem<T>> items,
      void Function(T?) onChanged,
    ) => SizedBox(
      width: 164,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: t(label), isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          dropdown<String>('Format', query.extension, [
            DropdownMenuItem(value: '', child: Text(t('All formats'))),
            for (final extension in extensions.where((e) => e.isNotEmpty))
              DropdownMenuItem(
                value: extension,
                child: Text(extension.toUpperCase()),
              ),
          ], (value) => _query(query.copyWith(extension: value))),
          dropdown<int>('Rating', query.minimumRating, [
            DropdownMenuItem(value: 0, child: Text(t('Any rating'))),
            for (var i = 1; i <= 5; i++)
              DropdownMenuItem(value: i, child: Text('${'★' * i} +')),
          ], (value) => _query(query.copyWith(minimumRating: value))),
          dropdown<int>(
            'Color label',
            query.color?.index ?? -1,
            [
              DropdownMenuItem(value: -1, child: Text(t('Any label'))),
              for (final value in GalleryColor.values)
                DropdownMenuItem(
                  value: value.index,
                  child: Text(t(galleryColorName(value))),
                ),
            ],
            (value) => _query(
              query.copyWith(
                color: value == -1 ? null : GalleryColor.values[value!],
                clearColor: value == -1,
              ),
            ),
          ),
          FilterChip(
            label: Text(t('Favorites only')),
            selected: query.favoritesOnly,
            onSelected: (value) => _query(query.copyWith(favoritesOnly: value)),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(
              query.after == null
                  ? t('Modified date')
                  : '${formatDate(query.after!)} – ${query.before == null ? '' : formatDate(query.before!)}',
            ),
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                initialDateRange: query.after == null || query.before == null
                    ? null
                    : DateTimeRange(start: query.after!, end: query.before!),
              );
              if (mounted && range != null) {
                _query(query.copyWith(after: range.start, before: range.end));
              }
            },
          ),
          if (query.after != null)
            IconButton(
              icon: const Icon(Icons.event_busy),
              tooltip: t('Clear dates'),
              onPressed: () => _query(query.copyWith(clearDates: true)),
            ),
        ],
      ),
    );
  }

  Widget _tile(FileItem file, GalleryPreferences prefs, double imageHeight) {
    final panel = ref.read(panelProvider(widget.side));
    final folderSize = FolderSizePresentation.forFile(
      context,
      file,
      panel.folderSizeFor(file),
    );
    final selected = panel.isSelected(file);
    final cursor = identical(panel.cursorItem, file);
    final record = _record(file);
    final scheme = Theme.of(context).colorScheme;
    final labelColor = galleryLabelColor(record.color);
    final image = file.isFolder
        ? Center(
            child: Icon(
              file.name == '..' ? Icons.drive_folder_upload : Icons.folder,
              color: Colors.amber,
              size: widget.tileLayout ? 42 : 60,
            ),
          )
        : isGalleryImage(file)
        ? GalleryThumbnail(
            side: widget.side,
            file: file,
            request: _request(file),
            size: math.min(
              512,
              (prefs.thumbnailSize * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
            fit: prefs.fill ? BoxFit.cover : BoxFit.contain,
          )
        : Center(
            child: Icon(
              getFileIcon(file.name),
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
          );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefs.showNames)
          Text(
            file.name,
            maxLines: widget.tileLayout ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: selected ? FontWeight.bold : null),
          ),
        if (prefs.showDetails) ...[
          Text(
            file.isFolder
                ? folderSize?.label ?? t('Folder')
                : '${file.extension.toUpperCase()} · ${file.size == null ? '—' : formatBytes(file.size!)}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.tileLayout && file.updatedAt != null)
            Text(
              formatDate(file.updatedAt!),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          if (isGalleryImage(file))
            Row(
              children: [
                if (record.favorite)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.favorite, size: 12, color: Colors.red),
                  ),
                Flexible(
                  child: Text(
                    '${'★' * record.rating}${'☆' * (5 - record.rating)}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 12,
                      color: record.rating > 0
                          ? Colors.amber.shade800
                          : scheme.outline,
                    ),
                  ),
                ),
                if (record.tags.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      record.tags.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ],
    );
    final card = Semantics(
      label:
          '${file.name}${file.isFolder ? ', ${t('Folder')}' : ''}${folderSize == null ? '' : ', ${folderSize.tooltip}'}',
      selected: selected,
      button: true,
      child: Tooltip(
        message:
            '${file.path ?? file.name}\n${folderSize?.tooltip ?? (file.size == null ? '' : formatBytes(file.size!))}',
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: cursor
                  ? scheme.primary
                  : labelColor ??
                        (selected
                            ? scheme.primary.withValues(alpha: 0.5)
                            : scheme.outlineVariant),
              width: cursor ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              panel.listFocusNode.requestFocus();
              _select(
                file,
                shift: HardwareKeyboard.instance.isShiftPressed,
                toggle:
                    HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed,
              );
            },
            onDoubleTap: () => _open(file),
            onSecondaryTapDown: (details) {
              panel.listFocusNode.requestFocus();
              _contextMenu(file, details.globalPosition);
            },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: widget.tileLayout
                      ? Row(
                          children: [
                            SizedBox(
                              width: imageHeight,
                              height: imageHeight,
                              child: image,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: description),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: imageHeight, child: image),
                            if (prefs.showNames || prefs.showDetails)
                              const SizedBox(height: 6),
                            description,
                          ],
                        ),
                ),
                if (file.name != '..')
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Checkbox(
                        value: selected,
                        semanticLabel: '${t('selected')}: ${file.name}',
                        onChanged: (_) {
                          panel.listFocusNode.requestFocus();
                          _select(file, toggle: true);
                        },
                      ),
                    ),
                  ),
                if (labelColor != null)
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, color: labelColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return PanelFileDragSource(
      side: widget.side,
      file: file,
      child: file.isFolder
          ? FolderDropTarget(side: widget.side, folder: file, child: card)
          : card,
    );
  }
}

bool listEqualsIdentical(List<FileItem> a, List<FileItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
