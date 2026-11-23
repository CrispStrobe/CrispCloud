// widgets/panel_header.dart
//
// One compact command row per panel. It unifies the former source selector,
// path toolbar, volume bar, and breadcrumb row:
//
//   [source/volumes] [back] [forward] [up] [history] [breadcrumbs ...]
//   [browse] [flat] [...]
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
import '../utils/native_home_directory.dart';

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
      final home = nativeHomeDirectory(
        Platform.environment,
        windows: Platform.isWindows,
      );
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
      key: ValueKey('panel-activity-header-${widget.side.name}'),
      color: widget.isActive
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: <Widget>[
                if (widget.showSource) ...<Widget>[
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: PanelSourceSelector(
                      side: widget.side,
                      locations: _sourceLocations(panel, location),
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
                        if (selected is LocalPanelSource &&
                            selected.currentPath == '/') {
                          // The picker's "Local" entry is a placeholder root.
                          // Land on a real, readable folder instead.
                          final landing = await panel.localLandingPath();
                          if (!mounted || panel.activeTabId != tabId) return;
                          selected = LocalPanelSource(landing);
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
                _navButton(
                  icon: Icons.arrow_upward,
                  tooltip: context.commanderTr("Up"),
                  onPressed: () {
                    ref.read(activePanelProvider.notifier).state = widget.side;
                    panel.navigateUp();
                  },
                ),
                if (panel.isInArchive)
                  _navButton(
                    icon: Icons.close,
                    tooltip: context.commanderTr("Exit archive"),
                    onPressed: panel.exitArchive,
                  ),
                const SizedBox(width: 2),
                Expanded(
                  child: GestureDetector(
                    key: ValueKey('panel-path-context-${widget.side.name}'),
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) =>
                        _showPathMenu(panel, details.globalPosition),
                    onLongPressStart: (details) =>
                        _showPathMenu(panel, details.globalPosition),
                    child: _breadcrumbs(context, panel, path, location),
                  ),
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
                const SizedBox(width: 2),
              ],
            ),
          ),
          if (_pathEditLocation != null)
            Padding(
              key: ValueKey('panel-path-editor-row-${widget.side.name}'),
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: _pathEditor(panel, _pathEditLocation!),
            ),
        ],
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
                  triggerMode: TooltipTriggerMode.manual,
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

  List<PanelSourceLocation> _sourceLocations(
    PanelNotifier panel,
    _HeaderLocation? location,
  ) {
    final side = widget.side;
    final sessionIsCurrent = panel.captureOperationSession();
    bool isCurrent() => mounted && widget.side == side && sessionIsCurrent();
    final drives = ref.watch(drivesProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final m = BrowserMenuStrings(context);
    final entries = kIsWeb
        ? <DriveEntry>[
            if (location != null && location.origin.source.isLocal)
              DriveEntry(
                path: location.root,
                label: location.paths.basename(location.root),
                icon: Icons.folder_open,
              ),
          ]
        : drives.maybeWhen(
            data: (value) => value,
            orElse: () => [
              DriveEntry(
                path:
                    Platform.environment['HOME'] ??
                    Platform.environment['USERPROFILE'] ??
                    '/',
                label: 'Home',
                icon: Icons.home,
              ),
            ],
          );
    Future<void> navigate(String path) async {
      if (!isCurrent()) return;
      if (location != null && location.origin.source.isLocal) {
        if (location.isCurrent) {
          _navigateLocation(panel, location, path, keepGrant: false);
        }
        return;
      }
      final origin = panel.resolveStorageReference(
        storageReferenceForSource(LocalPanelSource(path)),
        path,
      );
      if (origin != null && origin.isCurrent) {
        ref.read(activePanelProvider.notifier).state = side;
        try {
          await panel.navigateToPath(path, origin: origin);
        } catch (error) {
          if (isCurrent()) {
            ref.read(errorProvider).addError(error.toString(), cause: error);
          }
        }
      }
    }

    return [
      for (final entry in entries)
        PanelSourceLocation(
          key: 'drive:${entry.path}',
          label: entry.icon == Icons.home && entry.label == 'Home'
              ? m.text('Home')
              : entry.label,
          icon: entry.icon,
          onSelected: () {
            // A volume can be removed while this menu is open.
            if (!isCurrent()) return;
            final live = ref.read(drivesProvider);
            if (!kIsWeb &&
                live.hasValue &&
                !live.requireValue.any((drive) => drive.path == entry.path)) {
              return;
            }
            navigate(entry.path);
          },
        ),
      if (!kIsWeb)
        PanelSourceLocation(
          key: 'computer',
          label: context.commanderTr('Computer'),
          icon: Icons.computer,
          onSelected: () => navigate(
            location != null && location.origin.source.isLocal
                ? location.paths.rootPrefix(location.origin.source.currentPath)
                : p.rootPrefix(
                    Platform.environment['HOME'] ??
                        Platform.environment['USERPROFILE'] ??
                        p.current,
                  ),
          ),
        ),
      for (final bookmark in bookmarks.bookmarks)
        PanelSourceLocation(
          key: 'bookmark:${bookmark.identity}',
          label: bookmark.name,
          icon: Icons.bookmark_outline,
          onSelected: () {
            if (isCurrent() &&
                ref.read(bookmarksProvider).bookmarks.contains(bookmark)) {
              openBookmark(context, ref, bookmark, side: side);
            }
          },
        ),
    ];
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
    // Narrow layouts keep account selectors above the active pane. Retain
    // local destinations in its menu without adding another house button.
    final locations = widget.showSource
        ? const <PanelSourceLocation>[]
        : _sourceLocations(panel, _captureLocation(panel));

    return PopupMenuButton<String>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      tooltip: context.commanderTr("More commands"),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_horiz,
        size: 19,
        color: theme.colorScheme.onPrimaryContainer,
      ),
      onSelected: (String value) {
        if (value.startsWith('location:')) {
          final index = int.tryParse(value.substring('location:'.length));
          if (index != null && index >= 0 && index < locations.length) {
            locations[index].onSelected();
          }
          return;
        }
        _handleMenu(value, panel, isLocal);
      },
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
        for (var index = 0; index < locations.length; index++)
          _menuItem(
            'location:$index',
            locations[index].icon,
            locations[index].label,
          ),
        if (locations.isNotEmpty) const PopupMenuDivider(),
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

  Future<void> _showPathMenu(PanelNotifier panel, Offset position) async {
    final location = _captureLocation(panel);
    if (location == null || !location.isCurrent) return;
    final side = widget.side;
    final otherProvider = panelProvider(oppositePanel(side));
    final other = ref.exists(otherProvider) ? ref.read(otherProvider) : null;
    final otherIsCurrent = other?.captureOperationSession();
    bool canUseOther() => otherIsCurrent?.call() ?? !ref.exists(otherProvider);
    final bookmarks = ref.read(bookmarksProvider);
    await bookmarks.ready;
    if (!mounted || !location.isCurrent) return;
    final directory = !panel.isInArchive && !panel.showingSearchResults;
    final archive = panel.archiveSource;
    String archiveFilePath(ArchivePanelSource source) {
      final parent = source.parent;
      return parent is ArchivePanelSource
          ? '${archiveFilePath(parent)}!/${source.archivePath.replaceFirst(RegExp(r'^/+'), '')}'
          : source.archivePath;
    }

    final path = archive == null
        ? location.origin.source.currentPath
        : '${archiveFilePath(archive)}!/${archive.innerPath}';
    final bookmarked =
        directory &&
        bookmarks.isBookmarked(
          path,
          side,
          storage: location.origin.storageReference,
        );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor = overlay.globalToLocal(position);
    final strings = PanelHeaderStrings(context);
    final action = await showMenu<String>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Tooltip(
            message: path,
            child: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
        const PopupMenuDivider(),
        for (final item in [
          ('copy', 'Copy full path', Icons.copy, !panel.showingSearchResults),
          (
            'favorite',
            bookmarked ? 'Remove from favorites' : 'Add to favorites',
            bookmarked ? Icons.star : Icons.star_border,
            directory,
          ),
          (
            'other',
            'Open in other pane',
            Icons.drive_file_move_outline,
            directory,
          ),
          ('swap', 'Swap panels', Icons.swap_horiz, true),
          ('edit', 'Edit path', Icons.edit_outlined, directory),
          ('refresh', 'Refresh', Icons.refresh, true),
        ])
          PopupMenuItem<String>(
            key: ValueKey('panel-path-action-${item.$1}'),
            value: item.$1,
            enabled: item.$4,
            child: Row(
              children: [
                Icon(item.$3, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    strings.text(item.$2) == item.$2
                        ? context.commanderTr(item.$2)
                        : strings.text(item.$2),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (!mounted || action == null || !location.isCurrent) return;
    try {
      switch (action) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: path));
        case 'favorite':
          _toggleBookmark(panel, path, location.paths.basename(path));
        case 'other':
          if (!canUseOther()) return;
          final PanelNotifier target =
              other ?? ref.read<PanelNotifier>(otherProvider);
          await target.openSavedLocation({
            'path': path,
            'storage': location.origin.storageReference.toJson(),
          });
        case 'swap':
          if (!canUseOther()) return;
          await swapPanelSources(ref);
        case 'edit':
          setState(() {
            _pathEditLocation = location;
            _pathController.text = path;
          });
        case 'refresh':
          await panel.refresh();
      }
    } catch (error) {
      if (mounted) {
        ref.read(errorProvider).addError(error.toString(), cause: error);
      }
    }
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
