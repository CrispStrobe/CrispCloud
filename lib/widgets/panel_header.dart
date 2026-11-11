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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../l10n/gallery_strings.dart';
import 'file_view_selector.dart';
import 'panel_history_button.dart';
import '../models/panel_side.dart';
import '../models/panel_breadcrumb.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart';
import '../providers/toolbar_provider.dart';
import '../services/panel_view_mode_service.dart';
import '../services/panel_source_service.dart';
import '../services/storage_identity.dart';
import '../services/local_file_service.dart';
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
  _HeaderLocation? _pathEditLocation;
  _HeaderLocation? _volumeMenuLocation;
  bool Function()? _locationMenuIsCurrent;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  _HeaderLocation? _captureLocation(PanelNotifier panel) {
    PanelFileOrigin? origin;
    try {
      origin = panel.captureCurrentOrigin();
    } on StateError {
      // A failed or pending directory request can still navigate within its
      // exact account. An unavailable saved tab must remain unavailable.
      final storage = panel.directoryStorage;
      if (storage != null && panel.directorySourceAvailable) {
        final resolved = panel.resolveStorageReference(
          storage,
          panel.currentPath,
        );
        if (resolved != null &&
            _sameSource(resolved.source, panel.directorySource)) {
          origin = resolved;
        }
      } else if (panel.isInArchive) {
        PanelSource source = panel.archiveSource!.parent;
        while (source is ArchivePanelSource) {
          source = source.parent;
        }
        final resolved = panel.resolveStorageReference(
          storageReferenceForSource(source),
          source.currentPath,
        );
        if (resolved != null && _sameSource(resolved.source, source)) {
          origin = resolved;
        }
      }
    }
    if (origin == null || !origin.isCurrent) return null;
    final capturedOrigin = origin;
    final paths = origin.source.isLocal && !kIsWeb ? p.context : p.posix;
    final sourcePath = paths.normalize(origin.source.currentPath);
    if (!paths.isAbsolute(sourcePath) ||
        sourcePath.length > 8192 ||
        sourcePath.contains('\u0000')) {
      return null;
    }
    final local = ref.read(localFileServiceProvider);
    final root = _locationRoot(origin, local, paths);
    final identity = origin.source.isLocal && local is LocalFileSourceIdentity
        ? (local as LocalFileSourceIdentity).sourceIdentityForPath(sourcePath)
        : null;
    bool grantIsCurrent() {
      if (!capturedOrigin.source.isLocal) return true;
      if (_locationRoot(capturedOrigin, local, paths) != root) return false;
      return local is! LocalFileSourceIdentity ||
          identical(
            (local as LocalFileSourceIdentity).sourceIdentityForPath(
              sourcePath,
            ),
            identity,
          );
    }

    final side = widget.side;
    final displayedPath = panel.currentPath;
    final sessionIsCurrent = panel.captureOperationSession();
    return _HeaderLocation(
      origin: origin,
      paths: paths,
      root: root,
      grantIsCurrent: grantIsCurrent,
      isCurrentCheck: () =>
          mounted &&
          widget.side == side &&
          sessionIsCurrent() &&
          panel.currentPath == displayedPath &&
          (!capturedOrigin.source.isLocal ||
              identical(ref.read(localFileServiceProvider), local)) &&
          capturedOrigin.isCurrent &&
          grantIsCurrent(),
    );
  }

  bool _sameSource(PanelSource first, PanelSource? second) =>
      (first.isLocal && second?.isLocal == true) ||
      (first is RemotePanelSource &&
          second is RemotePanelSource &&
          identical(first.client, second.client));

  String _locationRoot(
    PanelFileOrigin origin,
    LocalFileService local,
    p.Context paths,
  ) {
    final current = paths.normalize(origin.source.currentPath);
    bool contains(String root) =>
        paths.isAbsolute(root) &&
        root.length <= 8192 &&
        !root.contains('\u0000') &&
        (paths.equals(root, current) || paths.isWithin(root, current));
    if (origin.source.isLocal) {
      if (local is LocalFileSourceIdentity) {
        final identities = local as LocalFileSourceIdentity;
        final token = identities.sourceIdentityForPath(current);
        if (token == null) return current;
        var root = current;
        while (true) {
          final parent = paths.dirname(root);
          if (parent == root ||
              !identical(identities.sourceIdentityForPath(parent), token)) {
            return root;
          }
          root = parent;
        }
      }
      final granted = local.grantedBasePath;
      if (granted != null) {
        final root = paths.normalize(granted);
        return contains(root) ? root : current;
      }
      return paths.rootPrefix(current);
    }
    final root = paths.normalize(origin.storageReference.root);
    return contains(root) ? root : current;
  }

  void _clearLocationMenu() {
    _volumeMenuLocation = null;
    _locationMenuIsCurrent = null;
  }

  void _closePathEditor(
    PanelNotifier panel,
    _HeaderLocation location, {
    bool restoreFocus = false,
  }) {
    if (!mounted || !identical(_pathEditLocation, location)) return;
    setState(() => _pathEditLocation = null);
    if (restoreFocus && location.isCurrent) {
      ref.read(activePanelProvider.notifier).state = widget.side;
      panel.listFocusNode.requestFocus();
    }
  }

  Future<void> _submitPath(
    PanelNotifier panel,
    _HeaderLocation location,
    String entered,
  ) async {
    if (!identical(_pathEditLocation, location) || !location.isCurrent) return;
    var path = entered.trim();
    if (path.isEmpty) {
      _closePathEditor(panel, location, restoreFocus: true);
      return;
    }
    final strings = PanelHeaderStrings(context);
    void reject(String message) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }

    if (path.length > 8192 || path.contains('\u0000')) {
      reject(strings.text('Enter a valid path.'));
      return;
    }
    final paths = location.paths;
    if (location.origin.source.isRemote) {
      final advertisedRoot = location.origin.storageReference.root;
      if (!paths.isAbsolute(advertisedRoot) ||
          advertisedRoot.contains('\u0000') ||
          advertisedRoot.length > 8192) {
        reject(strings.text('Enter a valid path.'));
        return;
      }
      final sourceRoot = paths.normalize(advertisedRoot);
      path = paths.normalize(
        paths.isAbsolute(path)
            ? path
            : paths.join(location.origin.source.currentPath, path),
      );
      if (!paths.equals(path, sourceRoot) &&
          !paths.isWithin(sourceRoot, path)) {
        reject(
          strings
              .text('Choose a path within {0}.')
              .replaceAll('{0}', sourceRoot),
        );
        return;
      }
    }
    // An explicit local path may intentionally request another existing or new
    // grant. Only navigation within the captured grant keeps its token guard.
    final localTarget = _localEntryPath(path, location);
    if (location.origin.source.isLocal && !paths.isAbsolute(localTarget)) {
      reject(strings.text('Enter a valid path.'));
      return;
    }
    final keepGrant =
        !location.origin.source.isLocal ||
        paths.equals(localTarget, location.root) ||
        paths.isWithin(location.root, localTarget);
    _closePathEditor(panel, location);
    await _navigateLocation(panel, location, path, keepGrant: keepGrant);
  }

  String _localEntryPath(String path, _HeaderLocation location) {
    if (path.startsWith('"') && path.endsWith('"') && path.length > 1) {
      path = path.substring(1, path.length - 1);
    }
    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path)
            .toFilePath(windows: location.paths.style == p.Style.windows);
      } on Object {
        return path;
      }
    }
    if (!kIsWeb) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        if (path == '~') path = home;
        if (path.startsWith('~/')) path = '$home/${path.substring(2)}';
      }
    }
    return location.paths.normalize(
      location.paths.isAbsolute(path)
          ? path
          : location.paths.join(location.origin.source.currentPath, path),
    );
  }

  Future<void> _navigateLocation(
    PanelNotifier panel,
    _HeaderLocation location,
    String path, {
    required bool keepGrant,
  }) async {
    if (!location.isCurrent) return;
    final side = widget.side;
    ref.read(activePanelProvider.notifier).state = side;
    if (location.origin.source.isLocal) {
      path = _localEntryPath(path, location);
    }
    var origin = keepGrant && location.origin.source.isLocal
        ? location.origin.withAvailabilityGuard(location.grantIsCurrent)
        : location.origin;
    if (!keepGrant && location.origin.source.isLocal) {
      final target = path;
      final resolved = panel.resolveStorageReference(
        location.origin.storageReference,
        target,
      );
      if (resolved == null || !resolved.isCurrent) return;
      origin = resolved;
    }
    if (location.origin.source.isLocal) {
      final target = path;
      final local = ref.read(localFileServiceProvider);
      if (local is LocalFileSourceIdentity) {
        final identities = local as LocalFileSourceIdentity;
        final identity = identities.sourceIdentityForPath(target);
        // An existing target grant keeps its own identity. A new
        // target may acquire the grant explicitly requested by this action.
        if (identity != null) {
          origin = origin.withAvailabilityGuard(
            () => identical(identities.sourceIdentityForPath(target), identity),
          );
        }
      }
    }
    final navigation = panel.navigateToPath(path, origin: origin);
    final targetTab = panel.activeTabId;
    try {
      await navigation;
    } catch (error) {
      if (mounted && widget.side == side && panel.activeTabId == targetTab) {
        ref.read(errorProvider).addError(error.toString(), cause: error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final PanelNotifier panel = ref.watch(panelProvider(widget.side));
    final PanelSource source = ref.watch(panelSourceProvider(widget.side));
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final storage = panel.directoryStorage;
    final tabId = panel.activeTabId;
    final side = widget.side;
    final String path = panel.currentPath;
    final location = _captureLocation(panel);
    if (_pathEditLocation?.isCurrent == false) _pathEditLocation = null;
    final bool isLocal =
        location?.origin.source.isLocal ?? storage?.isLocal ?? source.isLocal;
    final ThemeData theme = Theme.of(context);

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
                    if (!mounted ||
                        widget.side != side ||
                        panel.activeTabId != tabId) {
                      return;
                    }
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
            _volumeButton(panel, isLocal, location),
            if (panel.isInArchive)
              _navButton(
                icon: Icons.close,
                tooltip: context.commanderTr("Exit archive"),
                onPressed: panel.exitArchive,
              ),
            const SizedBox(width: 2),
            Expanded(
              child: _pathEditLocation != null
                  ? _pathEditor(panel, _pathEditLocation!)
                  : _breadcrumbs(context, panel, path, location),
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
              onPressed: location == null
                  ? null
                  : () {
                      if (!location.isCurrent) return;
                      ref.read(activePanelProvider.notifier).state =
                          widget.side;
                      _pathController.text = location.origin.source.currentPath;
                      _pathController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _pathController.text.length,
                      );
                      setState(() => _pathEditLocation = location);
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

  Widget _pathEditor(PanelNotifier panel, _HeaderLocation location) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _closePathEditor(panel, location, restoreFocus: true),
      },
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: ValueKey('panel-path-editor-${widget.side.name}'),
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
              onEditingComplete: () {},
              onSubmitted: (String value) =>
                  _submitPath(panel, location, value),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 17),
            tooltip: context.commanderTr("Cancel"),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                _closePathEditor(panel, location, restoreFocus: true),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbs(
    BuildContext context,
    PanelNotifier panel,
    String path,
    _HeaderLocation? location,
  ) {
    final ThemeData theme = Theme.of(context);
    final crumbs = location == null
        ? const <PanelBreadcrumb>[]
        : buildPanelBreadcrumbs(
            path,
            root: location.root,
            paths: location.paths,
          );

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
                Tooltip(
                  message: crumbs[i].path,
                  child: InkWell(
                    key: ValueKey(
                      'panel-breadcrumb-${widget.side.name}-${crumbs[i].path}',
                    ),
                    onTap: i == crumbs.length - 1
                        ? null
                        : () => _navigateLocation(
                            panel,
                            location!,
                            crumbs[i].path,
                            keepGrant: true,
                          ),
                    onLongPress: () {
                      if (location!.isCurrent) {
                        _toggleBookmark(panel, crumbs[i].path, crumbs[i].label);
                      }
                    },
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
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _volumeButton(
    PanelNotifier panel,
    bool isLocal,
    _HeaderLocation? location,
  ) {
    final ThemeData theme = Theme.of(context);
    final m = BrowserMenuStrings(context);
    if (!isLocal) {
      final bookmarks = ref.watch(bookmarksProvider);
      return PopupMenuButton<Bookmark>(
        tooltip: context.commanderTr("Bookmarks"),
        padding: EdgeInsets.zero,
        onCanceled: _clearLocationMenu,
        onSelected: (Bookmark bookmark) {
          final isCurrent = _locationMenuIsCurrent;
          _clearLocationMenu();
          if (isCurrent?.call() != true) return;
          openBookmark(context, ref, bookmark, side: widget.side);
        },
        itemBuilder: (BuildContext context) {
          final side = widget.side;
          final sessionIsCurrent = panel.captureOperationSession();
          _locationMenuIsCurrent = () =>
              mounted && widget.side == side && sessionIsCurrent();
          return <PopupMenuEntry<Bookmark>>[
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
          ];
        },
        child: _homeVisual(theme, true),
      );
    }

    final drives = ref.watch(drivesProvider);
    return PopupMenuButton<DriveEntry>(
      tooltip: context.commanderTr("Volumes"),
      padding: EdgeInsets.zero,
      enabled: location != null,
      onCanceled: _clearLocationMenu,
      onSelected: (DriveEntry entry) {
        final owner = _volumeMenuLocation;
        final isCurrent = _locationMenuIsCurrent;
        _clearLocationMenu();
        if (owner == null ||
            !owner.origin.source.isLocal ||
            isCurrent?.call() != true) {
          return;
        }
        _navigateLocation(panel, owner, entry.path, keepGrant: false);
      },
      itemBuilder: (BuildContext context) {
        _volumeMenuLocation = location;
        _locationMenuIsCurrent = () => mounted && location?.isCurrent == true;
        final List<DriveEntry> entries = kIsWeb
            ? [
                DriveEntry(
                  path: location!.root,
                  label: location.paths.basename(location.root),
                  icon: Icons.folder_open,
                ),
              ]
            : drives.maybeWhen(
                data: (List<DriveEntry> value) => value,
                orElse: () => <DriveEntry>[
                  DriveEntry(
                    path: kIsWeb
                        ? location?.root ?? '/'
                        : Platform.environment['HOME'] ?? '/',
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
          if (!kIsWeb) const PopupMenuDivider(),
          if (!kIsWeb)
            PopupMenuItem<DriveEntry>(
              value: DriveEntry(
                path: location == null
                    ? p.rootPrefix(panel.currentPath)
                    : location.paths.rootPrefix(
                        location.origin.source.currentPath,
                      ),
                label: location?.root ?? '/',
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

class _HeaderLocation {
  const _HeaderLocation({
    required this.origin,
    required this.paths,
    required this.root,
    required this.grantIsCurrent,
    required this.isCurrentCheck,
  });

  final PanelFileOrigin origin;
  final p.Context paths;
  final String root;
  final bool Function() grantIsCurrent;
  final bool Function() isCurrentCheck;
  bool get isCurrent => isCurrentCheck();
}
