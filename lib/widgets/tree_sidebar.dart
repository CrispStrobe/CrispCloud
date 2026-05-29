// lib/widgets/tree_sidebar.dart
//
// Expandable folder tree sidebar (like VS Code explorer).
// Shows the folder hierarchy for the active panel.
// Clicking a folder navigates the panel to that path.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/panel_side.dart';
import '../providers/providers.dart';

class TreeSidebar extends ConsumerStatefulWidget {
  const TreeSidebar({super.key});

  @override
  ConsumerState<TreeSidebar> createState() => _TreeSidebarState();
}

class _TreeSidebarState extends ConsumerState<TreeSidebar> {
  final Set<String> _expandedPaths = {};

  @override
  Widget build(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final panel = ref.watch(panelProvider(activePanel));
    final isLocal = activePanel == PanelSide.local;
    final theme = Theme.of(context);

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
                  icon: const Icon(Icons.refresh, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Refresh',
                  onPressed: () {
                    _expandedPaths.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          // Tree content
          Expanded(
            child: SingleChildScrollView(
              child: _buildTree(panel.currentPath, activePanel, 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTree(String rootPath, PanelSide side, int depth) {
    final panel = ref.read(panelProvider(side));
    final folders = panel.files
        ?.where((f) => f.isFolder)
        .toList() ?? [];

    if (folders.isEmpty && depth == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No folders', style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current directory entry
        if (depth == 0)
          _TreeNode(
            name: _pathLabel(rootPath),
            path: rootPath,
            depth: 0,
            isExpanded: true,
            isCurrent: true,
            onTap: () {},
            onToggle: () {},
          ),
        // Child folders from current listing
        ...folders.map((folder) {
          final folderPath = side == PanelSide.local
              ? (folder.path ?? p.join(rootPath, folder.name))
              : p.posix.join(rootPath, folder.name);
          return _TreeNode(
            name: folder.name,
            path: folderPath,
            depth: depth + 1,
            isExpanded: false,
            isCurrent: false,
            onTap: () => panel.navigateInto(folder),
            onToggle: () => panel.navigateInto(folder),
          );
        }),
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
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _TreeNode({
    required this.name,
    required this.path,
    required this.depth,
    required this.isExpanded,
    required this.isCurrent,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = 12.0 + depth * 16.0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: indent, right: 8, top: 4, bottom: 4),
        color: isCurrent ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null,
        child: Row(
          children: [
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
