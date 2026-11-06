import 'dart:convert';

import 'package:path/path.dart' as p;

import 'file_view_configuration.dart';
import 'panel_tab.dart';
import 'storage_reference.dart';

void _validateName(String id, String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
      name.trim().isEmpty ||
      name.length > 160 ||
      name.contains('\u0000')) {
    throw const FormatException(
      'Saved workspace items need a valid ID and name.',
    );
  }
}

abstract interface class NamedWorkspaceItem {
  String get id;
  String get name;
}

/// An immutable serialization boundary for a mutable live PanelTab. File
/// contents, selections, client instances and credentials never enter it.
class WorkspaceTabSnapshot {
  WorkspaceTabSnapshot._(this._value);
  final Map<String, dynamic> _value;

  factory WorkspaceTabSnapshot.fromJson(Map<String, dynamic> value) {
    final tab = PanelTab.fromJson('snapshot', value);
    if (tab.storage == null && tab.collectionId == null) {
      throw const FormatException(
        'Each saved tab must identify its storage or collection.',
      );
    }
    void validatePath(String path, StorageReference? storage) {
      final paths = storage?.isLocal == true && storage?.provider == 'windows'
          ? p.windows
          : p.posix;
      if (path.length > 8192 ||
          !paths.isAbsolute(path) ||
          path.contains('\u0000')) {
        throw const FormatException(
          'Saved locations require absolute storage paths.',
        );
      }
    }

    validatePath(tab.path, tab.storage);
    if (tab.lockedPath != null) {
      validatePath(tab.lockedPath!, tab.lockedStorage);
    }
    return WorkspaceTabSnapshot._(tab.toJson());
  }

  factory WorkspaceTabSnapshot.fromTab(PanelTab tab) =>
      WorkspaceTabSnapshot.fromJson(tab.toJson());

  String get path => _value['path'] as String;
  String get label => _value['label'] as String;
  String? get collectionId => _value['collectionId'] as String?;
  StorageReference? get storage => _value['storage'] == null
      ? null
      : StorageReference.fromJson(
          Map<String, dynamic>.from(_value['storage'] as Map),
        );
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_value)) as Map);
  PanelTab toTab(String id) => PanelTab.fromJson(id, toJson());
}

class WorkspacePanelSnapshot {
  WorkspacePanelSnapshot({
    required List<WorkspaceTabSnapshot> tabs,
    this.activeIndex = 0,
  }) : tabs = List.unmodifiable(tabs) {
    if (tabs.isEmpty ||
        tabs.length > 500 ||
        activeIndex < 0 ||
        activeIndex >= tabs.length) {
      throw const FormatException(
        'A saved panel needs 1–500 tabs and a valid active tab.',
      );
    }
  }
  final List<WorkspaceTabSnapshot> tabs;
  final int activeIndex;
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((tab) => tab.toJson()).toList(),
    'active': activeIndex,
  };
  factory WorkspacePanelSnapshot.fromJson(Map<String, dynamic> value) =>
      WorkspacePanelSnapshot(
        tabs: (value['tabs'] as List)
            .map(
              (tab) => WorkspaceTabSnapshot.fromJson(
                Map<String, dynamic>.from(tab as Map),
              ),
            )
            .toList(),
        activeIndex: value['active'] as int? ?? 0,
      );
}

class WorkspaceLayout {
  const WorkspaceLayout({
    this.dualPanel = true,
    this.tree = false,
    this.preview = false,
    this.split = 0.5,
    this.activeSide = 'local',
  });
  final bool dualPanel;
  final bool tree;
  final bool preview;
  final double split;
  final String activeSide;
  void validate() {
    if (!split.isFinite ||
        split < 0.15 ||
        split > 0.85 ||
        !const ['local', 'remote'].contains(activeSide)) {
      throw const FormatException('Invalid workspace panel layout.');
    }
  }

  Map<String, dynamic> toJson() => {
    'dualPanel': dualPanel,
    'tree': tree,
    'preview': preview,
    'split': split,
    'activeSide': activeSide,
  };
  factory WorkspaceLayout.fromJson(Map<String, dynamic> value) {
    final layout = WorkspaceLayout(
      dualPanel: value['dualPanel'] != false,
      tree: value['tree'] == true,
      preview: value['preview'] == true,
      split: (value['split'] as num? ?? 0.5).toDouble(),
      activeSide: value['activeSide'] as String? ?? 'local',
    );
    layout.validate();
    return layout;
  }
}

class SavedWorkspace implements NamedWorkspaceItem {
  SavedWorkspace({
    required this.id,
    required this.name,
    required this.left,
    required this.right,
    this.layout = const WorkspaceLayout(),
  }) {
    _validateName(id, name);
    layout.validate();
  }
  @override
  final String id;
  @override
  final String name;
  final WorkspacePanelSnapshot left;
  final WorkspacePanelSnapshot right;
  final WorkspaceLayout layout;
  SavedWorkspace renamed(String name) => SavedWorkspace(
    id: id,
    name: name,
    left: left,
    right: right,
    layout: layout,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'left': left.toJson(),
    'right': right.toJson(),
    'layout': layout.toJson(),
  };
  factory SavedWorkspace.fromJson(Map<String, dynamic> value) => SavedWorkspace(
    id: value['id'] as String,
    name: value['name'] as String,
    left: WorkspacePanelSnapshot.fromJson(
      Map<String, dynamic>.from(value['left'] as Map),
    ),
    right: WorkspacePanelSnapshot.fromJson(
      Map<String, dynamic>.from(value['right'] as Map),
    ),
    layout: WorkspaceLayout.fromJson(
      Map<String, dynamic>.from(value['layout'] as Map? ?? const {}),
    ),
  );
}

class PairedBookmark implements NamedWorkspaceItem {
  PairedBookmark({
    required this.id,
    required this.name,
    required this.left,
    required this.right,
  }) {
    _validateName(id, name);
  }
  @override
  final String id;
  @override
  final String name;
  final WorkspaceTabSnapshot left;
  final WorkspaceTabSnapshot right;
  PairedBookmark renamed(String name) =>
      PairedBookmark(id: id, name: name, left: left, right: right);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'left': left.toJson(),
    'right': right.toJson(),
  };
  factory PairedBookmark.fromJson(Map<String, dynamic> value) => PairedBookmark(
    id: value['id'] as String,
    name: value['name'] as String,
    left: WorkspaceTabSnapshot.fromJson(
      Map<String, dynamic>.from(value['left'] as Map),
    ),
    right: WorkspaceTabSnapshot.fromJson(
      Map<String, dynamic>.from(value['right'] as Map),
    ),
  );
}

class SavedViewProfile implements NamedWorkspaceItem {
  SavedViewProfile({
    required this.id,
    required this.name,
    required this.configuration,
  }) {
    _validateName(id, name);
  }
  @override
  final String id;
  @override
  final String name;
  final FileViewConfiguration configuration;
  SavedViewProfile renamed(String name) =>
      SavedViewProfile(id: id, name: name, configuration: configuration);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'configuration': configuration.toJson(),
  };
  factory SavedViewProfile.fromJson(Map<String, dynamic> value) =>
      SavedViewProfile(
        id: value['id'] as String,
        name: value['name'] as String,
        configuration: FileViewConfiguration.fromJson(
          Map<String, dynamic>.from(value['configuration'] as Map),
        ),
      );
}

class WorkspaceCatalog {
  WorkspaceCatalog({
    List<SavedWorkspace> groups = const [],
    List<PairedBookmark> pairs = const [],
    List<SavedViewProfile> profiles = const [],
  }) : groups = List.unmodifiable(groups),
       pairs = List.unmodifiable(pairs),
       profiles = List.unmodifiable(profiles) {
    for (final entries in [groups, pairs, profiles]) {
      if (entries.length > 1000 ||
          entries.map((item) => item.id).toSet().length != entries.length) {
        throw const FormatException(
          'Saved workspace IDs must be unique within each section.',
        );
      }
    }
  }
  final List<SavedWorkspace> groups;
  final List<PairedBookmark> pairs;
  final List<SavedViewProfile> profiles;
  Map<String, dynamic> toJson() => {
    'format': 'crispcloud.workspace',
    'version': 1,
    'groups': groups.map((group) => group.toJson()).toList(),
    'pairs': pairs.map((pair) => pair.toJson()).toList(),
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  };
  factory WorkspaceCatalog.fromJson(Map<String, dynamic> value) {
    if (value['format'] != 'crispcloud.workspace' || value['version'] != 1) {
      throw const FormatException('Unsupported workspace exchange format.');
    }
    return WorkspaceCatalog(
      groups: (value['groups'] as List? ?? const [])
          .map(
            (item) =>
                SavedWorkspace.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      pairs: (value['pairs'] as List? ?? const [])
          .map(
            (item) =>
                PairedBookmark.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      profiles: (value['profiles'] as List? ?? const [])
          .map(
            (item) => SavedViewProfile.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
