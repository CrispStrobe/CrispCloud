// lib/models/panel_tab.dart
//
// Model for a single tab in a file panel.
// Each tab has its own path, file listing, selection state, and scroll position.

import 'file_item.dart';
import 'storage_reference.dart';

class PanelTab {
  final String id;
  String path;
  String label;
  List<FileItem>? files;
  final Set<FileItem> selection = {};
  FileItem? lastSelected;
  bool isPinned;
  StorageReference? storage;
  String? collectionId;

  PanelTab({
    required this.id,
    required this.path,
    String? label,
    this.files,
    this.isPinned = false,
    this.storage,
    this.collectionId,
  }) : label = label ?? _labelFromPath(path);

  static String _labelFromPath(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }

  void updateLabel() {
    label = _labelFromPath(path);
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'label': label,
    'pinned': isPinned,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
  };

  factory PanelTab.fromJson(String id, Map<String, dynamic> json) => PanelTab(
    id: id,
    path: json['path'] as String? ?? '/',
    label: json['label'] as String?,
    isPinned: json['pinned'] == true,
    storage: json['storage'] == null
        ? null
        : StorageReference.fromJson(
            Map<String, dynamic>.from(json['storage'] as Map),
          ),
    collectionId: json['collectionId'] as String?,
  );

  PanelTab copyWith({String? path, List<FileItem>? files}) {
    return PanelTab(
      id: id,
      path: path ?? this.path,
      label: path == null ? label : null,
      files: files ?? this.files,
      isPinned: isPinned,
      storage: storage,
      collectionId: collectionId,
    );
  }
}
