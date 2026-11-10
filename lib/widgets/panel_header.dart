// widgets/panel_header.dart
//
// One compact command row per panel. It unifies the former source selector,
// path toolbar, volume bar, and breadcrumb row:
//
//   [source] [back] [forward] [home/volumes] [breadcrumbs ...] [browse]
//   [flat] [...] [edit]
//
// The "..." menu also carries the application toolbar actions when the top
// toolbar is collapsed.

import '../l10n/commander_strings.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/gallery_strings.dart';
import 'file_view_selector.dart';
import 'panel_history_button.dart';
import '../models/panel_side.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart';
import '../providers/toolbar_provider.dart';
import '../providers/terminal_provider.dart';
import '../services/panel_swap_service.dart';
import '../services/panel_view_mode_service.dart';
import '../services/panel_source_service.dart';
import '../services/storage_identity.dart';
import '../screens/screen_dialogs.dart';
import '../widgets/command_palette.dart';
import 'bookmark_actions.dart';
import '../widgets/file_context_menu.dart' show showPropertiesDialog;
import '../widgets/file_toolbar.dart' show showPanelFilterDialog;
import '../widgets/search_dialogs.dart' show showSearchDialog, showFindDialog;
import '../widgets/settings_dialog.dart';
import '../widgets/drive_bar.dart' show drivesProvider, DriveEntry;
import '../widgets/panel_source_selector.dart';
import '../l10n/browser_menu_strings.dart';
import '../l10n/panel_header_strings.dart';
import '../l10n/shortcut_strings.dart';

class PanelHeader extends ConsumerStatefulWidget {
  const PanelHeader({
    super.key,
    required this.side,
    required this.isActive,
    this.showSource = true,
  });

  final PanelSide side;
  final bool isActive;
  final bool showSource;

  @override
  ConsumerState<PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends ConsumerState<PanelHeader> {
  final TextEditingController _pathController = TextEditingController();
  bool _editingPath = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PanelNotifier panel = ref.watch(panelProvider(widget.side));
    final PanelSource source = ref.watch(panelSourceProvider(widget.side));
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final storage = panel.directoryStorage;
    final String path = panel.currentPath;
    final bool isLocal = storage?.isLocal ?? source.isLocal;
    final ThemeData theme = Theme.of(context);
    final m = BrowserMenuStrings(context);
    final h = PanelHeaderStrings(context);

    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SizedBox(
        height: 36,
        child: Row(
          children: <Widget>[
            if (widget.showSource) ...<Widget>[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: PanelSourceSelector(
                  side: widget.side,
                  currentSource: panel.directorySource,
                  currentStorage: storage,
                  currentLabel: storage == null
                      ? null
                      : panel.storageDisplayName(storage),
                  currentAvailable:
                      storage == null || panel.directorySourceAvailable,
                  onSelected: (selected) async {
                    if (!selected.isLocal && !selected.isRemote) {
                      ref
                          .read(panelSourceProvider(widget.side).notifier)
                          .setSource(selected);
                      return;
                    }
                    final origin = panel.resolveStorageReference(
                      storageReferenceForSource(selected),
                      selected.currentPath,
                    );
                    if (origin == null || !origin.isCurrent) return;
                    try {
                      // An explicit selection also routes a legacy listing
                      // whose picker already has this value, and a reconnected
                      // account whose previous listing is no longer current.
                      await panel.navigateToPath(
                        selected.currentPath,
                        origin: origin,
                      );
                    } catch (error) {
                      if (mounted) {
                        ref
                            .read(errorProvider)
                            .addError(error.toString(), cause: error);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 2),
            ],
            _navButton(
              icon: Icons.arrow_back,
              tooltip: context.commanderTr("Back"),
              onPressed: panel.canNavigateBack ? panel.navigateBack : null,
            ),
            _navButton(
              icon: Icons.arrow_forward,
              tooltip: context.commanderTr("Forward"),
              onPressed: panel.canNavigateForward
                  ? panel.navigateForward
                  : null,
            ),
            PanelHistoryButton(panel: panel, compact: true),
            _volumeButton(panel, isLocal),
            if (panel.isInArchive)
              _navButton(
                icon: Icons.close,
                tooltip: context.commanderTr("Exit archive"),
                onPressed: panel.exitArchive,
              ),
            const SizedBox(width: 2),
            Expanded(
              child: _editingPath
                  ? _pathEditor(panel)
                  : _breadcrumbs(context, panel, path, isLocal),
            ),
            if (isLocal)
              _navButton(
                icon: Icons.folder_open,
                tooltip:
                    AppLocalizations.of(context)?.browseTooltip ??
                    context.commanderTr("Browse..."),
                onPressed: panel.pickLocalDirectory,
              ),
            if (isLocal)
              _navButton(
                icon: Icons.layers,
                tooltip: panel.isFlatView
                    ? context.commanderTr("Exit flat view")
                    : context.commanderTr("Flat view"),
                active: panel.isFlatView,
                onPressed: panel.toggleFlatView,
              ),
            _moreButton(context, panel, isLocal),
            _navButton(
              icon: Icons.edit,
              tooltip: context.commanderTr("Edit path"),
              onPressed: () {
                _pathController.text = panel.currentPath;
                _pathController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _pathController.text.length,
                );
                setState(() => _editingPath = true);
              },
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final ThemeData theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon, size: 17),
      color: active
          ? theme.colorScheme.primary
          : theme.colorScheme.onPrimaryContainer,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  Widget _pathEditor(PanelNotifier panel) {
    final h = PanelHeaderStrings(context);
    final l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _pathController,
            autofocus: true,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              border: const OutlineInputBorder(),
              hintText: context.commanderTr("Enter path…"),
              prefixIcon: const Icon(Icons.folder_open, size: 17),
            ),
            onSubmitted: (String value) {
              if (value.isNotEmpty) panel.navigateToPath(value);
              setState(() => _editingPath = false);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 17),
          tooltip: context.commanderTr("Cancel"),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _editingPath = false),
        ),
      ],
    );
  }

  Widget _breadcrumbs(
    BuildContext context,
    PanelNotifier panel,
    String path,
    bool isLocal,
  ) {
    final ThemeData theme = Theme.of(context);
    final List<({String label, String path})> crumbs =
        <({String label, String path})>[];
    if (isLocal) {
      if (!kIsWeb && Platform.isWindows) {
        final List<String> parts = path.split('\\');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          accumulated = i == 0 ? parts[i] : '$accumulated\\${parts[i]}';
          crumbs.add((label: parts[i], path: accumulated));
        }
      } else {
        final List<String> parts = path.split('/');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty && i != 0) continue;
          if (i == 0) {
            crumbs.add((label: '/', path: '/'));
            accumulated = '';
          } else {
            accumulated = accumulated.isEmpty
                ? '/${parts[i]}'
                : '$accumulated/${parts[i]}';
            crumbs.add((label: parts[i], path: accumulated));
          }
        }
      }
    } else {
      crumbs.add((label: '/', path: '/'));
      final List<String> parts = path.split('/');
      String accumulated = '';
      for (int i = 1; i < parts.length; i++) {
        if (parts[i].isEmpty) continue;
        accumulated = accumulated.isEmpty
            ? '/${parts[i]}'
            : '$accumulated/${parts[i]}';
        crumbs.add((label: parts[i], path: accumulated));
      }
    }

    if (panel.isInArchive) {
      final archive = panel.archiveSource!;
      final inner = archive.innerPath;
      return Row(
        children: <Widget>[
          Icon(
            Icons.archive_outlined,
            size: 15,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${archive.archiveName}:/${inner.isEmpty ? '' : inner}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (crumbs.isEmpty) {
      return Text(
        path,
        style: TextStyle(
          fontSize: 12.5,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < crumbs.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (i > 0)
                  Icon(
                    Icons.chevron_right,
                    size: 15,
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.55,
                    ),
                  ),
                InkWell(
                  onTap: i == crumbs.length - 1
                      ? null
                      : () => panel.navigateToPath(crumbs[i].path),
                  onLongPress: () =>
                      _toggleBookmark(panel, crumbs[i].path, crumbs[i].label),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Text(
                      crumbs[i].label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: i == crumbs.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _volumeButton(PanelNotifier panel, bool isLocal) {
    final ThemeData theme = Theme.of(context);
    final h = PanelHeaderStrings(context);
    final m = BrowserMenuStrings(context);
    final l = AppLocalizations.of(context);
    if (!isLocal) {
      final bookmarks = ref.watch(bookmarksProvider);
      return PopupMenuButton<Bookmark>(
        tooltip: context.commanderTr("Bookmarks"),
        padding: EdgeInsets.zero,
        onSelected: (Bookmark bookmark) =>
            openBookmark(context, ref, bookmark, side: widget.side),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<Bookmark>>[
          for (final bookmark in bookmarks.bookmarks)
            PopupMenuItem<Bookmark>(
              value: bookmark,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.bookmark_outline, size: 17),
                  const SizedBox(width: 8),
                  Text(bookmark.name),
                ],
              ),
            ),
        ],
        child: _homeVisual(theme, true),
      );
    }

    final drives = ref.watch(drivesProvider);
    return PopupMenuButton<DriveEntry>(
      tooltip: context.commanderTr("Volumes"),
      padding: EdgeInsets.zero,
      onSelected: (DriveEntry entry) => panel.navigateToPath(entry.path),
      itemBuilder: (BuildContext context) {
        final List<DriveEntry> entries = drives.maybeWhen(
          data: (List<DriveEntry> value) => value,
          orElse: () => <DriveEntry>[
            DriveEntry(
              path: Platform.environment['HOME'] ?? '/',
              label: m.text('Home'),
              icon: Icons.home,
            ),
          ],
        );
        return <PopupMenuEntry<DriveEntry>>[
          for (final DriveEntry entry in entries)
            PopupMenuItem<DriveEntry>(
              value: entry,
              child: Row(
                children: <Widget>[
                  Icon(entry.icon, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.icon == Icons.home && entry.label == 'Home'
                          ? m.text('Home')
                          : entry.label,
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<DriveEntry>(
            value: const DriveEntry(
              path: '/',
              label: '/',
              icon: Icons.computer,
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.computer, size: 17),
                const SizedBox(width: 8),
                Text(context.commanderTr("Computer")),
              ],
            ),
          ),
        ];
      },
      child: _homeVisual(theme, drives.isLoading),
    );
  }

  Widget _homeVisual(ThemeData theme, bool loading) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.home,
            size: 17,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 15,
            color: theme.colorScheme.onPrimaryContainer.withValues(
              alpha: loading ? 0.4 : 0.9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreButton(BuildContext context, PanelNotifier panel, bool isLocal) {
    final ThemeData theme = Theme.of(context);
    final bool topVisible = ref.watch(topToolbarVisibleProvider);
    final bool desktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final AuthNotifier auth = ref.watch(authProvider);
    final l =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    final m = BrowserMenuStrings(context);
    final h = PanelHeaderStrings(context);

    return PopupMenuButton<String>(
      tooltip: context.commanderTr("More commands"),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_horiz,
        size: 19,
        color: theme.colorScheme.onPrimaryContainer,
      ),
      onSelected: (String value) => _handleMenu(value, panel, isLocal),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (desktop)
          _menuItem(
            'toggle_top_toolbar',
            topVisible ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            topVisible
                ? h.text('Hide top toolbar')
                : h.text('Show top toolbar'),
          ),
        if (desktop) const PopupMenuDivider(),
        _menuItem('up', Icons.arrow_upward, 'Up'),
        _menuItem('refresh', Icons.refresh, 'Refresh'),
        _menuItem('new_folder', Icons.create_new_folder, 'New folder…'),
        _menuItem('rename', Icons.drive_file_rename_outline, 'Rename…'),
        _menuItem('delete', Icons.delete_outline, 'Delete…'),
        _menuItem('copy', Icons.copy, 'Copy…'),
        _menuItem('move', Icons.drive_file_move, 'Move…'),
        _menuItem('properties', Icons.info_outline, 'Properties…'),
        _menuItem('select_all', Icons.select_all, 'Select all'),
        _menuItem('invert_selection', Icons.flip_to_back, 'Invert selection'),
        const PopupMenuDivider(),
        _menuItem('sort_name', Icons.sort_by_alpha, l.sortByName),
        _menuItem('sort_size', Icons.data_usage, l.sortBySize),
        _menuItem('sort_date', Icons.access_time, l.sortByDate),
        _menuItem('sort_ext', Icons.category, l.sortByExtension),
        _menuItem('sort_order', Icons.swap_vert, m.text('Reverse Sort Order')),
        const PopupMenuDivider(),
        _menuItem('density', Icons.density_medium, 'Toggle row density'),
        _menuItem(
          'view_mode',
          Icons.view_list,
          'Cycle list/icons/tiles/gallery/columns',
        ),
        _menuItem(
          'gallery',
          Icons.photo_library_outlined,
          context.galleryTr('Image gallery'),
        ),
        _menuItem(
          'tiles',
          Icons.view_module_outlined,
          context.galleryTr('Tiles'),
        ),
        _menuItem('filter', Icons.filter_list, 'Filter files…'),
        _menuItem('hidden', Icons.visibility, 'Toggle hidden files'),
        if (isLocal) _menuItem('flat', Icons.layers, 'Toggle flat view'),
        _menuItem('bookmark', Icons.star_border, 'Bookmark this folder'),
        if (isLocal)
          _menuItem(
            'grant_access',
            Icons.lock_open,
            h.text('Grant access to this folder…'),
          ),
        const PopupMenuDivider(),
        _menuItem('goto_path', Icons.route, h.text('Go to path…')),
        _menuItem('search', Icons.search, h.text('Search all files…')),
        _menuItem('find', Icons.find_in_page, h.text('Find by pattern…')),
        _menuItem('command_palette', Icons.terminal, '${l.commandPalette}…'),
        _menuItem('settings', Icons.settings, '${l.settings}…'),
        if (desktop) ...<PopupMenuEntry<String>>[
          const PopupMenuDivider(),
          _menuItem('swap', Icons.swap_horiz, h.text('Swap panels')),
          _menuItem('terminal', Icons.terminal, m.text('Toggle Terminal')),
          _menuItem('dual', Icons.view_column, m.text('Toggle Dual Panel')),
          _menuItem('tree', Icons.account_tree, m.text('Toggle Tree Sidebar')),
          _menuItem('preview', Icons.visibility, m.text('Toggle Preview')),
          if (!auth.isConnected)
            _menuItem('connect', Icons.login, '${l.connect}…')
          else
            _menuItem('logout', Icons.logout, l.logout),
        ],
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value == 'up'
                  ? (AppLocalizations.of(context) ??
                            lookupAppLocalizations(const Locale('en')))
                        .upTooltip
                  : value == 'invert_selection'
                  ? ShortcutStrings(context).description(20)
                  : context.commanderTr(
                      PanelHeaderStrings(context).text(label),
                    ),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(
    String value,
    PanelNotifier panel,
    bool isLocal,
  ) async {
    ref.read(activePanelProvider.notifier).state = widget.side;
    final PanelSide active = ref.read(activePanelProvider);
    final PanelViewMode density = ref.read(panelViewModeProvider(widget.side));
    switch (value) {
      case 'toggle_top_toolbar':
        await ref.read(topToolbarVisibleProvider.notifier).toggle();
      case 'up':
        await panel.navigateUp();
      case 'refresh':
        panel.refresh();
      case 'new_folder':
        showCreateFolderDialog(context, ref, widget.side);
      case 'rename':
        showRenameDialog(context, ref);
      case 'delete':
        confirmDeleteSelected(context, ref);
      case 'copy':
        showCopyDialogFromSelection(context, ref);
      case 'move':
        showMoveDialogFromSelection(context, ref);
      case 'properties':
        final FileItem? item = panel.cursorItem;
        if (item != null) showPropertiesDialog(context, item);
      case 'select_all':
        panel.selectAll();
      case 'invert_selection':
        panel.invertSelection();
      case 'sort_name':
        panel.setSortBy(SortBy.name);
      case 'sort_size':
        panel.setSortBy(SortBy.size);
      case 'sort_date':
        panel.setSortBy(SortBy.date);
      case 'sort_ext':
        panel.setSortBy(SortBy.extension);
      case 'sort_order':
        panel.toggleSortOrder();
      case 'density':
        await ref
            .read(panelViewModeProvider(widget.side).notifier)
            .setMode(density.next);
      case 'view_mode':
        final bool local = widget.side == PanelSide.local;
        final ViewMode mode = local
            ? ref.read(localViewModeProvider)
            : ref.read(remoteViewModeProvider);
        setFileView(ref, widget.side, mode.next);
      case 'gallery':
        setFileView(ref, widget.side, ViewMode.gallery);
      case 'tiles':
        setFileView(ref, widget.side, ViewMode.tiles);
      case 'filter':
        showPanelFilterDialog(context, panel);
      case 'hidden':
        panel.toggleShowHiddenFiles();
      case 'flat':
        panel.toggleFlatView();
      case 'bookmark':
        await togglePanelBookmark(context, ref, widget.side);
      case 'grant_access':
        await panel.grantAccessToCurrentPath();
      case 'goto_path':
        showGoToDialog(context, ref);
      case 'search':
        showSearchDialog(context, ref);
      case 'find':
        showFindDialog(context, ref);
      case 'command_palette':
        showCommandPalette(context, ref);
      case 'settings':
        await showSettingsDialog(context);
      case 'swap':
        await swapPanelSources(ref);
      case 'terminal':
        setTerminalVisible(ref, !ref.read(showTerminalProvider));
      case 'dual':
        ref.read(showDualPanelProvider.notifier).state = !ref.read(
          showDualPanelProvider,
        );
      case 'tree':
        ref.read(showTreeSidebarProvider.notifier).state = !ref.read(
          showTreeSidebarProvider,
        );
      case 'preview':
        ref.read(showPreviewProvider.notifier).state = !ref.read(
          showPreviewProvider,
        );
      case 'connect':
        showConnectionDialogScreen(context);
      case 'logout':
        confirmLogoutRiverpod(context, ref);
    }
  }

  void _toggleBookmark(PanelNotifier panel, String path, String label) {
    togglePanelBookmark(
      context,
      ref,
      widget.side,
      path: path,
      label: label.isEmpty ? '/' : label,
    );
  }
}
