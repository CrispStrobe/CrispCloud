// lib/models/panel_tab.dart
//
// Model for a single tab in a file panel.
// Each tab has its own path, file listing, selection state, and scroll position.

import 'file_item.dart';

class PanelTab {
  final String id;
  String path;
  String label;
  List<FileItem>? files;
  final Set<FileItem> selection = {};
  FileItem? lastSelected;
  bool isPinned;

  PanelTab({
    required this.id,
    required this.path,
    String? label,
    this.files,
    this.isPinned = false,
  }) : label = label ?? _labelFromPath(path);

  static String _labelFromPath(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }

  void updateLabel() {
    label = _labelFromPath(path);
  }

  PanelTab copyWith({String? path, List<FileItem>? files}) {
    return PanelTab(
      id: id,
      path: path ?? this.path,
      files: files ?? this.files,
      isPinned: isPinned,
    );
  }
}
