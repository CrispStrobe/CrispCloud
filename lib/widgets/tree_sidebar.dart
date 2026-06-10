// lib/widgets/tree_sidebar.dart
//
// Expandable folder tree sidebar (like VS Code / Windows Explorer).
// Shows the folder hierarchy for the active panel.
// Folders can be expanded/collapsed independently; clicking navigates the panel.
// Subdirectories are loaded lazily on expand.

import 'dart:io' if (dart.library.html) 'dart:html';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';

class TreeSidebar extends ConsumerStatefulWidget {
  const TreeSidebar({super.key});

  @override
  ConsumerState<TreeSidebar> createState() => _TreeSidebarState();
}

class _TreeSidebarState extends ConsumerState<TreeSidebar> {
  final Set<String> _expandedPaths = {};
  final Map<String, List<FileItem>> _childCache = {};
  final Set<String> _loadingPaths = {};

  @override
  Widget build(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final panel = ref.watch(panelProvider(activePanel));
    final isLocal = activePanel == PanelSide.local;
    final theme = Theme.of(context);
    final currentPath = panel.currentPath;

    // Auto-expand the current directory.
    if (!_expandedPaths.contains(currentPath)) {
      _expandedPaths.add(currentPath);
      _loadChildren(currentPath, activePanel);
    }

    // Build ancestor paths so the tree shows the full path from root.
    final ancestors = _getAncestors(currentPath, isLocal);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(isLocal ? Icons.folder : Icons.cloud, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLocal ? 'Local Files' : 'Remote Files',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    ref.watch(bookmarksProvider).isBookmarked(currentPath, activePanel)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 14,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Bookmark current folder',
                  onPressed: () {
                    final bm = ref.read(bookmarksProvider);
                    if (bm.isBookmarked(currentPath, activePanel)) {
                      bm.remove(currentPath, activePanel);
                    } else {
                      bm.add(_pathLabel(currentPath), currentPath, activePanel);
                    }
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Refresh',
                  onPressed: () {
                    _childCache.clear();
                    _expandedPaths.clear();
                    _expandedPaths.add(currentPath);
                    _loadChildren(currentPath, activePanel);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          // Bookmarks section
          _buildBookmarks(context, activePanel),
          // Recent locations section
          _buildRecent(context, activePanel),
          // Tree content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildHierarchy(ancestors, currentPath, activePanel, 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get ancestor paths from root to [path].
  List<String> _getAncestors(String path, bool isLocal) {
    final ancestors = <String>[];
    var current = path;
    while (true) {
      ancestors.insert(0, current);
      final parent = isLocal ? p.dirname(current) : p.posix.dirname(current);
      if (parent == current || parent == '.' || parent.isEmpty) break;
      current = parent;
    }
    // Ensure root is included.
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final root = isLocal ? (isWindows ? current : '/') : '/';
    if (ancestors.isEmpty || ancestors.first != root) {
      ancestors.insert(0, root);
    }
    return ancestors;
  }

  /// Build the tree hierarchy: ancestors expanded down to current path,
  /// plus expanded subdirectories.
  List<Widget> _buildHierarchy(
    List<String> ancestors,
    String currentPath,
    PanelSide side,
    int startDepth,
  ) {
    final widgets = <Widget>[];
    final panel = ref.read(panelProvider(side));

    for (var i = 0; i < ancestors.length; i++) {
      final ancestorPath = ancestors[i];
      final depth = startDepth + i;
      final isCurrent = ancestorPath == currentPath;
      final isExpanded = _expandedPaths.contains(ancestorPath);

      widgets.add(_TreeNode(
        name: _pathLabel(ancestorPath),
        path: ancestorPath,
        depth: depth,
        isExpanded: isExpanded,
        isCurrent: isCurrent,
        isLoading: _loadingPaths.contains(ancestorPath),
        onTap: () => panel.navigateToPath(ancestorPath),
        onToggle: () => _toggleExpand(ancestorPath, side),
      ));

      // If expanded and this IS the last ancestor (or an expanded sibling),
      // show its children.
      if (isExpanded && i == ancestors.length - 1) {
        widgets.addAll(_buildChildren(ancestorPath, currentPath, side, depth + 1));
      }
    }
    return widgets;
  }

  /// Build child nodes for an expanded directory.
  List<Widget> _buildChildren(
    String parentPath,
    String currentPath,
    PanelSide side,
    int depth,
  ) {
    final panel = ref.read(panelProvider(side));
    final children = _childCache[parentPath];
    if (children == null) return [];

    final widgets = <Widget>[];
    final isLocal = side == PanelSide.local;

    for (final folder in children) {
      if (folder.name == '..') continue;
      final folderPath = isLocal
          ? (folder.path ?? p.join(parentPath, folder.name))
          : p.posix.join(parentPath, folder.name);
      final isExpanded = _expandedPaths.contains(folderPath);
      final isCurrent = folderPath == currentPath;

      widgets.add(_TreeNode(
        name: folder.name,
        path: folderPath,
        depth: depth,
        isExpanded: isExpanded,
        isCurrent: isCurrent,
        isLoading: _loadingPaths.contains(folderPath),
        onTap: () => panel.navigateToPath(folderPath),
        onToggle: () => _toggleExpand(folderPath, side),
      ));

      // Recursively show expanded subtrees.
      if (isExpanded) {
        widgets.addAll(_buildChildren(folderPath, currentPath, side, depth + 1));
      }
    }
    return widgets;
  }

  void _toggleExpand(String path, PanelSide side) {
    setState(() {
      if (_expandedPaths.contains(path)) {
        _expandedPaths.remove(path);
      } else {
        _expandedPaths.add(path);
        _loadChildren(path, side);
      }
    });
  }

  Future<void> _loadChildren(String path, PanelSide side) async {
    if (_childCache.containsKey(path)) return;
    if (_loadingPaths.contains(path)) return;

    setState(() => _loadingPaths.add(path));

    try {
      List<FileItem> folders;
      if (side == PanelSide.local && !kIsWeb) {
        // Load subdirectories directly from filesystem.
        final dir = Directory(path);
        if (!await dir.exists()) {
          folders = [];
        } else {
          final entities = await dir.list().toList();
          folders = <FileItem>[];
          for (final entity in entities) {
            try {
              final stat = await entity.stat();
              if (stat.type == FileSystemEntityType.directory) {
                final name = p.basename(entity.path);
                if (!name.startsWith('.')) {
                  folders.add(FileItem(name: name, path: entity.path, isFolder: true));
                }
              }
            } catch (_) {
              continue;
            }
          }
          folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
      } else if (side == PanelSide.local && kIsWeb) {
        // Web local: use the panel's files if this is the active path.
        final panel = ref.read(panelProvider(side));
        if (panel.currentPath == path) {
          folders = (panel.files ?? []).where((f) => f.isFolder && f.name != '..').toList();
        } else {
          folders = [];
        }
      } else {
        // Remote or web: use the panel's current files if this is the active path,
        // otherwise we can't easily load arbitrary remote subdirectories.
        final panel = ref.read(panelProvider(side));
        if (panel.currentPath == path) {
          folders = (panel.files ?? []).where((f) => f.isFolder && f.name != '..').toList();
        } else {
          // For remote, attempt via auth client.
          try {
            final auth = ref.read(authProvider);
            if (auth.isConnected) {
              final result = await auth.client.listPath(path);
              final rawFolders = result['folders'] as List<dynamic>? ?? [];
              folders = rawFolders
                  .map((m) => FileItem(
                        name: (m as Map<String, dynamic>)['name'] ?? 'Unknown',
                        isFolder: true,
                      ))
                  .toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            } else {
              folders = [];
            }
          } catch (_) {
            folders = [];
          }
        }
      }
      if (mounted) {
        setState(() {
          _childCache[path] = folders;
          _loadingPaths.remove(path);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPaths.remove(path));
      }
    }
  }

  Widget _buildBookmarks(BuildContext context, PanelSide activePanel) {
    final bm = ref.watch(bookmarksProvider);
    final filtered = bm.bookmarks.where((b) => b.side == activePanel).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final panel = ref.read(panelProvider(activePanel));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
          child: Text('BOOKMARKS', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          )),
        ),
        ...filtered.map((b) => InkWell(
          onTap: () => panel.navigateToPath(b.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                Icon(Icons.bookmark, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(b.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                InkWell(
                  onTap: () => ref.read(bookmarksProvider).remove(b.path, b.side),
                  child: Icon(Icons.close, size: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        )),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  Widget _buildRecent(BuildContext context, PanelSide activePanel) {
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
              Text('RECENT', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              )),
              const Spacer(),
              InkWell(
                onTap: () => ref.read(recentLocationsProvider).clear(),
                child: Icon(Icons.clear_all, size: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        ...shown.map((r) => InkWell(
          onTap: () => panel.navigateToPath(r.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                Icon(Icons.history, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(r.label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        )),
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
    final indent = 8.0 + depth * 16.0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: indent, right: 8, top: 3, bottom: 3),
        color: isCurrent ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        child: Row(
          children: [
            // Expand/collapse chevron
            GestureDetector(
              onTap: onToggle,
              child: SizedBox(
                width: 16,
                height: 16,
                child: isLoading
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
            ),
            const SizedBox(width: 4),
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              size: 16,
              color: isCurrent ? theme.colorScheme.primary : Colors.amber.shade700,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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
