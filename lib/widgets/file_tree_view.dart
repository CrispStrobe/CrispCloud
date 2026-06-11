// widgets/file_tree_view.dart
//
// DC-style in-panel folder tree (PanelViewMode.tree).
// Shows a hierarchical list of directories; clicking/Enter navigates the panel.

import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';

class _TreeNode {
  final String path;
  final String name;
  final int depth;
  bool isExpanded;
  bool isLoading = false;
  List<_TreeNode>? children;

  _TreeNode({
    required this.path,
    required this.name,
    required this.depth,
    this.isExpanded = false,
  });
}

class FileTreeView extends ConsumerStatefulWidget {
  final PanelSide side;

  const FileTreeView({super.key, required this.side});

  @override
  ConsumerState<FileTreeView> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends ConsumerState<FileTreeView> {
  final List<_TreeNode> _flatList = [];
  final ScrollController _scrollController = ScrollController();
  int _cursorIdx = 0;
  String? _lastPanelPath;

  @override
  void initState() {
    super.initState();
    _initRoot();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initRoot() async {
    String root;
    if (kIsWeb) {
      root = '/';
    } else {
      root = Platform.environment['HOME'] ?? '/';
    }

    final panel = ref.read(panelProvider(widget.side));
    final currentPath = panel.currentPath;

    // Start with a root node covering as much of the current path as we can
    final rootNode = _TreeNode(path: root, name: _label(root), depth: 0, isExpanded: true);
    _flatList.clear();
    _flatList.add(rootNode);

    await _loadChildren(rootNode);
    await _expandToPath(currentPath);

    if (mounted) setState(() {});
    _syncCursorToPath(currentPath);
  }

  String _label(String path) {
    final base = p.basename(path);
    return base.isEmpty ? path : base;
  }

  Future<List<_TreeNode>> _fetchSubdirs(_TreeNode parent) async {
    try {
      final svc = ref.read(localFileServiceProvider);
      final entities = await svc.listDirectory(parent.path);
      if (entities == null) return [];
      final dirs = <_TreeNode>[];
      for (final e in entities) {
        if (e is Directory) {
          final name = p.basename(e.path);
          if (name.startsWith('.')) continue;
          dirs.add(_TreeNode(path: e.path, name: name, depth: parent.depth + 1));
        }
      }
      dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return dirs;
    } catch (e) {
      // TODO: add logging
      return [];
    }
  }

  Future<void> _loadChildren(_TreeNode node) async {
    if (node.children != null) return;
    node.isLoading = true;
    final children = await _fetchSubdirs(node);
    node.children = children;
    node.isLoading = false;
  }

  int _indexOfNode(_TreeNode node) => _flatList.indexOf(node);

  void _expand(_TreeNode node) async {
    if (node.isExpanded) return;
    await _loadChildren(node);
    final idx = _indexOfNode(node);
    if (idx == -1) return;
    node.isExpanded = true;
    _flatList.insertAll(idx + 1, node.children ?? []);
    if (mounted) setState(() {});
  }

  void _collapse(_TreeNode node) {
    if (!node.isExpanded) return;
    node.isExpanded = false;
    _flatList.removeWhere((n) => n.path.startsWith(node.path + p.separator) ||
        (n.path.startsWith('${node.path}/') && n != node));
    if (mounted) setState(() {});
  }

  // Expand each ancestor of [targetPath] so the node is visible.
  Future<void> _expandToPath(String targetPath) async {
    if (_flatList.isEmpty) return;

    // Build list of ancestor paths from root down
    final parts = p.split(targetPath);
    String built = parts.first;
    final ancestors = <String>[];
    for (int i = 1; i < parts.length; i++) {
      built = p.join(built, parts[i]);
      ancestors.add(built);
    }

    for (final ancestor in ancestors) {
      final node = _flatList.firstWhere((n) => n.path == ancestor, orElse: () => _flatList.first);
      if (node.path == ancestor && !node.isExpanded) {
        await _loadChildren(node);
        final idx = _indexOfNode(node);
        if (idx == -1) continue;
        node.isExpanded = true;
        _flatList.insertAll(idx + 1, node.children ?? []);
      }
    }
  }

  void _syncCursorToPath(String path) {
    final idx = _flatList.indexWhere((n) => n.path == path);
    if (idx != -1) {
      _cursorIdx = idx;
      _scrollToCursor();
    }
  }

  void _scrollToCursor() {
    const rowH = 28.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final offset = _cursorIdx * rowH;
      final vMin = _scrollController.offset;
      final vMax = vMin + _scrollController.position.viewportDimension;
      if (offset < vMin || offset + rowH > vMax) {
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigate(_TreeNode node) {
    ref.read(panelProvider(widget.side)).navigateToPath(node.path);
  }

  @override
  Widget build(BuildContext context) {
    // Sync when panel path changes
    final panel = ref.watch(panelProvider(widget.side));
    final currentPath = panel.currentPath;
    if (currentPath != _lastPanelPath) {
      _lastPanelPath = currentPath;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _expandToPath(currentPath);
        if (mounted) {
          setState(() {});
          _syncCursorToPath(currentPath);
        }
      });
    }

    final isActivePanel = ref.read(activePanelProvider) == widget.side;
    final theme = Theme.of(context);

    return Focus(
      autofocus: isActivePanel,
      canRequestFocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final activePanel = ref.read(activePanelProvider);
        if (widget.side != activePanel) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_cursorIdx < _flatList.length - 1) {
            setState(() => _cursorIdx++);
            _scrollToCursor();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_cursorIdx > 0) {
            setState(() => _cursorIdx--);
            _scrollToCursor();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final node = _flatList[_cursorIdx];
          if (!node.isExpanded) {
            _expand(node);
          } else {
            _navigate(node);
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final node = _flatList[_cursorIdx];
          if (node.isExpanded) {
            _collapse(node);
          } else {
            // Go to parent node
            final parentPath = p.dirname(node.path);
            final parentIdx = _flatList.indexWhere((n) => n.path == parentPath);
            if (parentIdx != -1) setState(() => _cursorIdx = parentIdx);
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _navigate(_flatList[_cursorIdx]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (context) {
        final platform = Theme.of(context).platform;
        final isMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
        return ListView.builder(
        controller: _scrollController,
        itemCount: _flatList.length,
        itemExtent: isMobile ? 48.0 : 28.0,
        itemBuilder: (context, idx) {
          final node = _flatList[idx];
          final isCursor = idx == _cursorIdx;
          final isCurrentPath = node.path == currentPath;
          final bgColor = isCursor
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : isCurrentPath
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                  : Colors.transparent;

          return GestureDetector(
            onTap: () {
              setState(() => _cursorIdx = idx);
              _navigate(node);
            },
            onDoubleTap: () {
              setState(() => _cursorIdx = idx);
              if (node.isExpanded) {
                _collapse(node);
              } else {
                _expand(node);
              }
            },
            child: Container(
              color: bgColor,
              padding: EdgeInsets.only(left: 4.0 + node.depth * 16.0),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // Expand/collapse button
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: node.isLoading
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : GestureDetector(
                            onTap: () {
                              setState(() => _cursorIdx = idx);
                              if (node.isExpanded) {
                                _collapse(node);
                              } else {
                                _expand(node);
                              }
                            },
                            child: Icon(
                              node.isExpanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 18,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    node.isExpanded ? Icons.folder_open : Icons.folder,
                    size: 15,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      node.name,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.0,
                        fontWeight: isCurrentPath ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCursor)
                    Container(width: 3, height: 28, color: theme.colorScheme.primary),
                ],
              ),
            ),
          );
        },
      );
      }),
    );
  }
}
