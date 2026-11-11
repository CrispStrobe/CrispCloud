// lib/widgets/tree_sidebar.dart
//
// Expandable folder tree sidebar (like VS Code / Windows Explorer).
// Shows the folder hierarchy for the active panel.
// Folders can be expanded/collapsed independently; clicking navigates the panel.
// Subdirectories are loaded lazily on expand.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/navigation_strings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/file_operation_backend.dart';
import '../services/panel_source_service.dart';
import 'bookmark_actions.dart';

class TreeSidebar extends ConsumerStatefulWidget {
  const TreeSidebar({super.key});

  @override
  ConsumerState<TreeSidebar> createState() => _TreeSidebarState();
}

class _TreeSidebarState extends ConsumerState<TreeSidebar> {
  final Set<String> _expandedPaths = {};
  final Map<String, List<FileItem>> _childCache = {};
  final Set<String> _loadingPaths = {};
  final Set<String> _scheduledPaths = {};
  final Map<String, Object> _loadErrors = {};
  _TreeScope? _scope;
  String? _lastCurrentPath;
  int _treeRevision = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final activePanel = ref.watch(activePanelProvider);
    final panel = ref.watch(panelProvider(activePanel));
    // A disconnected source can invalidate a tree without a new file listing.
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final scope = _scopeFor(panel, activePanel);
    final theme = Theme.of(context);
    final currentPath = panel.currentPath;
    final ancestors = scope == null
        ? const <String>[]
        : _ancestors(currentPath, scope);
    if (scope != null) {
      if (_lastCurrentPath != currentPath) {
        _lastCurrentPath = currentPath;
        _expandedPaths.addAll(ancestors);
      }
      // The panel already has a fresh verified listing for this directory.
      // Share that read instead of issuing a duplicate cloud request.
      _childCache[currentPath] = _folders(
        currentPath,
        panel.files ?? const [],
        scope,
      );
      _loadErrors.remove(currentPath);
      for (final ancestor in ancestors) {
        if (_expandedPaths.contains(ancestor))
          _scheduleChildren(ancestor, scope);
      }
    }

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  scope?.origin.source.isRemote == true
                      ? Icons.cloud
                      : Icons.folder,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: scope == null
                        ? NavigationStrings(context).text('treeUnavailable')
                        : panel.storageDisplayName(
                            scope.origin.storageReference,
                          ),
                    child: Text(
                      scope == null
                          ? NavigationStrings(context).text('folders')
                          : scope.origin.source.isLocal
                          ? l.localFiles
                          : panel.storageDisplayName(
                              scope.origin.storageReference,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPanelBookmarked(ref.watch(bookmarksProvider), panel)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: l.bookmarkFolder,
                  onPressed: scope == null
                      ? null
                      : () => togglePanelBookmark(
                          context,
                          ref,
                          activePanel,
                          label: _pathLabel(currentPath),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: l.refresh,
                  onPressed: scope == null
                      ? null
                      : () {
                          _clearTree();
                          setState(() {});
                          panel.refresh();
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBookmarks(context, activePanel),
                  _buildRecent(context, activePanel),
                  if (scope == null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (panel.isLoading)
                              const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            Text(
                              NavigationStrings(context).text(
                                panel.isLoading
                                    ? 'loadingFolders'
                                    : 'treeUnavailable',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (ancestors.isNotEmpty)
                    ..._buildBranch(
                      ancestors.first,
                      currentPath,
                      scope,
                      0,
                      ancestors,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _TreeScope? _scopeFor(PanelNotifier panel, PanelSide side) {
    if (panel.isLoading || panel.isInArchive || panel.showingSearchResults)
      return null;
    PanelFileOrigin origin;
    try {
      origin = panel.captureCurrentOrigin();
    } on Object {
      return null;
    }
    final root = _treeRoot(origin);
    final current = _scope;
    if (current == null || !current.matches(panel, side, origin, root)) {
      _clearTree();
      _scope = _TreeScope(
        side,
        panel.activeTabId,
        origin,
        panel.showHiddenFiles,
        root,
      );
    }
    return _scope;
  }

  void _clearTree() {
    _treeRevision++;
    _expandedPaths.clear();
    _childCache.clear();
    _loadingPaths.clear();
    _scheduledPaths.clear();
    _loadErrors.clear();
    _lastCurrentPath = null;
    _scope = null;
  }

  bool _isCurrent(_TreeScope scope) {
    if (!mounted ||
        !identical(_scope, scope) ||
        !scope.origin.isCurrent ||
        ref.read(activePanelProvider) != scope.side)
      return false;
    final panel = ref.read(panelProvider(scope.side));
    if (panel.isLoading || panel.isInArchive || panel.showingSearchResults)
      return false;
    try {
      final origin = panel.captureCurrentOrigin();
      return scope.matches(panel, scope.side, origin, _treeRoot(origin));
    } on Object {
      return false;
    }
  }

  String _treeRoot(PanelFileOrigin origin) {
    final paths = origin.source.isLocal && !kIsWeb ? p.context : p.posix;
    final current = paths.normalize(origin.source.currentPath);
    final grantedRoot = origin.source.isLocal
        ? ref.read(localFileServiceProvider).grantedBasePath
        : null;
    for (final candidate in [grantedRoot, origin.storageReference.root]) {
      if (candidate == null) continue;
      final root = paths.normalize(candidate);
      if (paths.isAbsolute(root) &&
          (root == current || paths.isWithin(root, current))) {
        return root;
      }
    }
    return paths.rootPrefix(current);
  }

  List<String> _ancestors(String path, _TreeScope scope) {
    final paths = scope.paths;
    var current = paths.normalize(path);
    final result = <String>[];
    while (result.length < 128) {
      result.insert(0, current);
      if (current == scope.root) break;
      final parent = paths.dirname(current);
      if (parent == current || parent == '.') break;
      current = parent;
    }
    return result;
  }

  List<FileItem> _folders(
    String path,
    List<FileItem> entries,
    _TreeScope scope,
  ) {
    final paths = scope.paths;
    final parent = paths.normalize(path);
    final seen = <String>{};
    final folders = <FileItem>[];
    for (final entry in entries) {
      if (!entry.isFolder ||
          entry.name == '.' ||
          entry.name == '..' ||
          (!scope.showHidden && entry.name.startsWith('.')))
        continue;
      final child = paths.normalize(
        entry.path ?? paths.join(parent, entry.name),
      );
      // A directory listing may contribute only direct children of that route.
      if (child == parent ||
          paths.dirname(child) != parent ||
          paths.basename(child) != entry.name ||
          !seen.add(child))
        continue;
      folders.add(entry.copyWith(path: child));
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return folders;
  }

  List<Widget> _buildBranch(
    String path,
    String currentPath,
    _TreeScope scope,
    int depth,
    List<String> ancestors,
  ) {
    final expanded = _expandedPaths.contains(path);
    final result = <Widget>[
      _TreeNode(
        key: ValueKey('tree:${scope.origin.storageId}:$path'),
        name: _pathLabel(path),
        path: path,
        depth: depth,
        isExpanded: expanded,
        isCurrent: path == currentPath,
        isLoading:
            _loadingPaths.contains(path) || _scheduledPaths.contains(path),
        onTap: () => _openPath(path, scope),
        onToggle: () => _toggleExpand(path, scope),
      ),
    ];
    if (!expanded || depth >= 127) return result;
    final error = _loadErrors[path];
    if (error != null) {
      result.add(
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 8),
          child: Tooltip(
            message: '$error',
            child: TextButton.icon(
              onPressed: () {
                _loadErrors.remove(path);
                _loadChildren(path, scope);
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                NavigationStrings(context).text('retryFolder'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    final children = <String>{
      for (final folder in _childCache[path] ?? const <FileItem>[])
        folder.path!,
    };
    final ancestorIndex = ancestors.indexOf(path);
    if (ancestorIndex >= 0 && ancestorIndex + 1 < ancestors.length) {
      children.add(ancestors[ancestorIndex + 1]);
    }
    final ordered = children.toList()
      ..sort(
        (a, b) =>
            _pathLabel(a).toLowerCase().compareTo(_pathLabel(b).toLowerCase()),
      );
    for (final child in ordered) {
      result.addAll(
        _buildBranch(child, currentPath, scope, depth + 1, ancestors),
      );
    }
    return result;
  }

  void _scheduleChildren(String path, _TreeScope scope) {
    if (_childCache.containsKey(path) ||
        _loadingPaths.contains(path) ||
        _scheduledPaths.contains(path) ||
        _loadErrors.containsKey(path))
      return;
    _scheduledPaths.add(path);
    final revision = _treeRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _treeRevision) return;
      _scheduledPaths.remove(path);
      if (_expandedPaths.contains(path) && _isCurrent(scope)) {
        unawaited(_loadChildren(path, scope));
      }
    });
  }

  void _toggleExpand(String path, _TreeScope scope) {
    if (!_isCurrent(scope)) return;
    final expand = !_expandedPaths.contains(path);
    setState(() {
      if (expand) {
        _expandedPaths.add(path);
        _loadErrors.remove(path);
      } else {
        _expandedPaths.remove(path);
      }
    });
    if (expand) unawaited(_loadChildren(path, scope));
  }

  Future<void> _openPath(String path, _TreeScope scope) async {
    if (!_isCurrent(scope)) return;
    final panel = ref.read(panelProvider(scope.side));
    try {
      await panel.navigateToPath(path, origin: scope.origin);
    } catch (error) {
      if (mounted && identical(_scope, scope)) {
        ref
            .read(errorProvider)
            .addError(
              'Could not open the saved location: $error',
              code: PanelErrorCode.navigationFailed,
              arguments: {'error': '$error'},
            );
      }
    }
  }

  Future<void> _loadChildren(String path, _TreeScope scope) async {
    if (!_isCurrent(scope) ||
        _childCache.containsKey(path) ||
        _loadingPaths.contains(path))
      return;
    final revision = _treeRevision;
    bool current() => revision == _treeRevision && _isCurrent(scope);
    setState(() => _loadingPaths.add(path));
    try {
      final local = ref.read(localFileServiceProvider);
      // Background expansion must not open an OS access picker. A route that
      // needs a grant can be opened explicitly through normal navigation.
      if (scope.origin.source.isLocal && !await local.hasAccessToPath(path)) {
        throw StateError('Directory access is unavailable.');
      }
      if (!current()) return;
      final backend = fileOperationBackend(
        source: scope.origin.source.withPath(path),
        local: local,
        isCurrent: current,
      );
      final entries = await backend.list(path);
      if (!current()) return;
      setState(() {
        _childCache[path] = _folders(path, entries, scope);
        _loadErrors.remove(path);
      });
    } catch (error) {
      if (current()) setState(() => _loadErrors[path] = error);
    } finally {
      if (mounted && revision == _treeRevision && identical(_scope, scope)) {
        setState(() => _loadingPaths.remove(path));
      }
    }
  }

  Widget _buildBookmarks(BuildContext context, PanelSide activePanel) {
    final l = AppLocalizations.of(context)!;
    final bm = ref.watch(bookmarksProvider);
    final filtered = bm.bookmarks.where((b) => b.side == activePanel).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
          child: Text(
            l.bookmarks.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...filtered.map(
          (b) => InkWell(
            onTap: () => openBookmark(context, ref, b, side: activePanel),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.bookmark,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      b.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => removeBookmark(context, ref, b),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  Widget _buildRecent(BuildContext context, PanelSide activePanel) {
    final l = AppLocalizations.of(context)!;
    final recent = ref.watch(recentLocationsProvider).forSide(activePanel);
    if (recent.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final panel = ref.read(panelProvider(activePanel));
    // Show max 8 recent entries
    final shown = recent.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4, right: 8),
          child: Row(
            children: [
              Text(
                l.recentLocations.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => ref.read(recentLocationsProvider).clear(),
                child: Icon(
                  Icons.clear_all,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...shown.map(
          (r) => Tooltip(
            message: r.storage == null
                ? NavigationStrings(context).text('older')
                : '${panel.storageDisplayName(r.storage!)}: ${r.path}',
            child: InkWell(
              onTap: r.storage == null
                  ? null
                  : () => panel.openRecentLocation(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.storage == null
                            ? r.label
                            : '${r.label} · ${panel.storageDisplayName(r.storage!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: r.storage == null ? theme.disabledColor : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  String _pathLabel(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }
}

class _TreeNode extends StatelessWidget {
  final String name;
  final String path;
  final int depth;
  final bool isExpanded;
  final bool isCurrent;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _TreeNode({
    super.key,
    required this.name,
    required this.path,
    required this.depth,
    required this.isExpanded,
    required this.isCurrent,
    this.isLoading = false,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = (8.0 + depth * 16.0).clamp(8.0, 120.0);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: indent, right: 8, top: 3, bottom: 3),
        color: isCurrent
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        child: Row(
          children: [
            // Expand/collapse chevron
            IconButton(
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: NavigationStrings(context)
                  .text(isExpanded ? 'collapseFolder' : 'expandFolder'),
              icon: isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 4),
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              size: 16,
              color: isCurrent
                  ? theme.colorScheme.primary
                  : Colors.amber.shade700,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrent
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeScope {
  const _TreeScope(
    this.side,
    this.tabId,
    this.origin,
    this.showHidden,
    this.root,
  );
  final PanelSide side;
  final String tabId;
  final PanelFileOrigin origin;
  final bool showHidden;
  final String root;

  p.Context get paths => origin.source.isLocal && !kIsWeb ? p.context : p.posix;

  bool matches(
    PanelNotifier panel,
    PanelSide activeSide,
    PanelFileOrigin current,
    String currentRoot,
  ) {
    if (side != activeSide ||
        tabId != panel.activeTabId ||
        showHidden != panel.showHiddenFiles ||
        root != currentRoot ||
        !origin.isCurrent ||
        origin.storageReference != current.storageReference)
      return false;
    final before = origin.source;
    final after = current.source;
    return before is LocalPanelSource && after is LocalPanelSource ||
        before is RemotePanelSource &&
            after is RemotePanelSource &&
            identical(before.client, after.client);
  }
}
