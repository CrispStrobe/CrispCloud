// lib/models/panel_tab.dart
//
// Model for a single tab in a file panel.
// Each tab has its own path, file listing, selection state, and scroll position.

import 'file_item.dart';
import 'file_view_configuration.dart';
import 'storage_reference.dart';

enum TabLockMode { none, locked, resetOnLeave, newTab }

extension TabLockModeLabel on TabLockMode {
  String get label => switch (this) {
    TabLockMode.none => 'Normal',
    TabLockMode.locked => 'Lock this location',
    TabLockMode.resetOnLeave => 'Return to locked location on tab change',
    TabLockMode.newTab => 'Open other locations in new tabs',
  };
}

class PanelTab {
  final String id;
  String path;
  String label;
  String? customLabel;
  List<FileItem>? files;
  final Set<FileItem> selection = {};
  FileItem? lastSelected;
  bool isPinned;
  StorageReference? storage;
  String? collectionId;
  TabLockMode lockMode;
  String? lockedPath;
  StorageReference? lockedStorage;
  String? lockedCollectionId;
  FileViewConfiguration? view;
  String? viewProfileId;

  PanelTab({
    required this.id,
    required this.path,
    String? label,
    this.customLabel,
    this.files,
    this.isPinned = false,
    this.storage,
    this.collectionId,
    this.lockMode = TabLockMode.none,
    this.lockedPath,
    this.lockedStorage,
    this.lockedCollectionId,
    this.view,
    this.viewProfileId,
  }) : label = customLabel ?? label ?? _labelFromPath(path);

  bool get isLocked => lockMode != TabLockMode.none;
  bool get isProtected => isPinned || isLocked;

  static String _labelFromPath(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }

  void updateLabel() {
    label = customLabel ?? _labelFromPath(path);
  }

  void renameLabel(String value) {
    customLabel = value.trim().isEmpty ? null : value.trim();
    updateLabel();
  }

  void setLock(TabLockMode mode) {
    if (mode == TabLockMode.none) {
      lockedPath = null;
      lockedStorage = null;
      lockedCollectionId = null;
    } else if (!isLocked || lockedPath == null) {
      lockedPath = path;
      lockedStorage = storage;
      lockedCollectionId = collectionId;
    }
    lockMode = mode;
  }

  bool resetToLockedLocation() {
    if (lockMode != TabLockMode.resetOnLeave || lockedPath == null) {
      return false;
    }
    final changed =
        path != lockedPath ||
        storage != lockedStorage ||
        collectionId != lockedCollectionId;
    path = lockedPath!;
    storage = lockedStorage;
    collectionId = lockedCollectionId;
    if (changed) {
      files = null;
      selection.clear();
      lastSelected = null;
    }
    updateLabel();
    return changed;
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'label': label,
    if (customLabel != null) 'customLabel': customLabel,
    'pinned': isPinned,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
    'lock': lockMode.name,
    if (lockedPath != null) 'lockedPath': lockedPath,
    if (lockedStorage != null) 'lockedStorage': lockedStorage!.toJson(),
    if (lockedCollectionId != null) 'lockedCollectionId': lockedCollectionId,
    if (view != null) 'view': view!.toJson(),
    if (viewProfileId != null) 'viewProfileId': viewProfileId,
  };

  factory PanelTab.fromJson(String id, Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '/';
    if (path.isEmpty || path.contains('\u0000')) {
      throw const FormatException('A tab requires a valid location.');
    }
    final label = json['label'] as String?;
    final custom =
        json['customLabel'] as String? ??
        (!json.containsKey('lock') &&
                label != null &&
                label != _labelFromPath(path) &&
                json['collectionId'] == null
            ? label
            : null);
    final tab = PanelTab(
      id: id,
      path: path,
      label: label,
      customLabel: custom,
      isPinned: json['pinned'] == true,
      storage: json['storage'] == null
          ? null
          : StorageReference.fromJson(
              Map<String, dynamic>.from(json['storage'] as Map),
            ),
      collectionId: json['collectionId'] as String?,
      lockMode: TabLockMode.values.byName(json['lock'] as String? ?? 'none'),
      lockedPath: json['lockedPath'] as String?,
      lockedStorage: json['lockedStorage'] == null
          ? null
          : StorageReference.fromJson(
              Map<String, dynamic>.from(json['lockedStorage'] as Map),
            ),
      lockedCollectionId: json['lockedCollectionId'] as String?,
      view: json['view'] == null
          ? null
          : FileViewConfiguration.fromJson(
              Map<String, dynamic>.from(json['view'] as Map),
            ),
      viewProfileId: json['viewProfileId'] as String?,
    );
    if (tab.isLocked && tab.lockedPath == null) {
      tab.lockedPath = tab.path;
      tab.lockedStorage = tab.storage;
      tab.lockedCollectionId = tab.collectionId;
    }
    tab.resetToLockedLocation();
    return tab;
  }

  PanelTab copyWith({String? path, List<FileItem>? files}) {
    return PanelTab(
      id: id,
      path: path ?? this.path,
      label: path == null ? label : null,
      customLabel: customLabel,
      files: files ?? this.files,
      isPinned: isPinned,
      storage: storage,
      collectionId: collectionId,
      lockMode: lockMode,
      lockedPath: lockedPath,
      lockedStorage: lockedStorage,
      lockedCollectionId: lockedCollectionId,
      view: view,
      viewProfileId: viewProfileId,
    );
  }
}
