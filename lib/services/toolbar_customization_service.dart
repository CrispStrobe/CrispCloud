// lib/services/toolbar_customization_service.dart
//
// Toolbar customization: show/hide buttons, reorder them, persist via
// SharedPreferences.  Implements PLAN.md 5.4.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// ToolbarItem
// ---------------------------------------------------------------------------

/// All toolbar buttons available in CrispCloud.
enum ToolbarItem {
  browse,
  up,
  refresh,
  newFolder,
  filter,
  search,
  findPattern,
  viewMode,
  preview,
  treeView,
  mount,
  syncManager,
  commandPalette,
  settings,
}

extension ToolbarItemX on ToolbarItem {
  /// Human-readable label shown in the customisation dialog.
  String get displayName {
    switch (this) {
      case ToolbarItem.browse:
        return 'Browse';
      case ToolbarItem.up:
        return 'Up';
      case ToolbarItem.refresh:
        return 'Refresh';
      case ToolbarItem.newFolder:
        return 'New Folder';
      case ToolbarItem.filter:
        return 'Filter';
      case ToolbarItem.search:
        return 'Search';
      case ToolbarItem.findPattern:
        return 'Find Pattern';
      case ToolbarItem.viewMode:
        return 'View Mode';
      case ToolbarItem.preview:
        return 'Preview';
      case ToolbarItem.treeView:
        return 'Tree View';
      case ToolbarItem.mount:
        return 'Mount';
      case ToolbarItem.syncManager:
        return 'Sync Manager';
      case ToolbarItem.commandPalette:
        return 'Command Palette';
      case ToolbarItem.settings:
        return 'Settings';
    }
  }

  String toJson() => name;

  static ToolbarItem fromJson(String value) {
    return ToolbarItem.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown ToolbarItem: $value'),
    );
  }
}

// ---------------------------------------------------------------------------
// ToolbarConfig
// ---------------------------------------------------------------------------

/// Immutable snapshot of the current toolbar configuration.
class ToolbarConfig {
  /// Items that should be rendered (others are hidden).
  final List<ToolbarItem> visibleItems;

  /// Full ordered list of all items (including hidden ones).
  /// The toolbar renders [visibleItems] in this relative order.
  final List<ToolbarItem> order;

  const ToolbarConfig({
    required this.visibleItems,
    required this.order,
  });

  /// Returns a copy with the supplied fields replaced.
  ToolbarConfig copyWith({
    List<ToolbarItem>? visibleItems,
    List<ToolbarItem>? order,
  }) {
    return ToolbarConfig(
      visibleItems: visibleItems ?? List.unmodifiable(this.visibleItems),
      order: order ?? List.unmodifiable(this.order),
    );
  }

  // ---- Serialization -------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'visibleItems': visibleItems.map((e) => e.toJson()).toList(),
        'order': order.map((e) => e.toJson()).toList(),
      };

  factory ToolbarConfig.fromJson(Map<String, dynamic> json) {
    final visibleItems = (json['visibleItems'] as List<dynamic>)
        .map((e) => ToolbarItemX.fromJson(e as String))
        .toList();
    final order = (json['order'] as List<dynamic>)
        .map((e) => ToolbarItemX.fromJson(e as String))
        .toList();
    return ToolbarConfig(visibleItems: visibleItems, order: order);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ToolbarConfig) return false;
    if (visibleItems.length != other.visibleItems.length) return false;
    if (order.length != other.order.length) return false;
    for (int i = 0; i < visibleItems.length; i++) {
      if (visibleItems[i] != other.visibleItems[i]) return false;
    }
    for (int i = 0; i < order.length; i++) {
      if (order[i] != other.order[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(visibleItems),
        Object.hashAll(order),
      );
}

// ---------------------------------------------------------------------------
// ToolbarCustomizationService
// ---------------------------------------------------------------------------

/// Manages which toolbar items are visible and in what order.
///
/// All mutating methods persist changes to SharedPreferences so they survive
/// app restarts.
class ToolbarCustomizationService {
  static const _prefsKey = 'toolbar_config_v1';

  // In-memory cache; populated lazily by [load].
  ToolbarConfig? _cache;

  // ---- Default config ------------------------------------------------------

  /// The factory default configuration: all items visible in declaration order.
  ToolbarConfig getDefaults() {
    final all = List<ToolbarItem>.unmodifiable(ToolbarItem.values);
    return ToolbarConfig(
      visibleItems: all,
      order: all,
    );
  }

  // ---- Loading -------------------------------------------------------------

  /// Loads persisted config from SharedPreferences into the in-memory cache.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_cache != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      _cache = getDefaults();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = ToolbarConfig.fromJson(decoded);
    } catch (_) {
      // Corrupted data – fall back to defaults.
      _cache = getDefaults();
    }
  }

  // ---- Getters -------------------------------------------------------------

  /// Returns the current [ToolbarConfig].  Falls back to defaults if [load]
  /// has not been called yet.
  ToolbarConfig getConfig() => _cache ?? getDefaults();

  /// Whether [item] is currently visible.
  bool isVisible(ToolbarItem item) =>
      getConfig().visibleItems.contains(item);

  // ---- Mutation ------------------------------------------------------------

  /// Shows or hides [item].
  Future<void> setVisibility(ToolbarItem item, bool visible) async {
    await load();
    final current = getConfig();
    final visibleSet = current.visibleItems.toSet();
    if (visible) {
      visibleSet.add(item);
    } else {
      visibleSet.remove(item);
    }
    // Preserve order when rebuilding visibleItems list.
    final newVisible = current.order
        .where((e) => visibleSet.contains(e))
        .toList();
    _cache = current.copyWith(visibleItems: newVisible);
    await _persist();
  }

  /// Sets the display order of toolbar items.
  ///
  /// [items] must contain each [ToolbarItem] value at most once; duplicates
  /// are silently removed (only the first occurrence is kept).
  Future<void> setOrder(List<ToolbarItem> items) async {
    await load();
    final current = getConfig();
    // Deduplicate while preserving first-occurrence order.
    final seen = <ToolbarItem>{};
    final deduped = <ToolbarItem>[];
    for (final item in items) {
      if (seen.add(item)) deduped.add(item);
    }
    // Ensure every ToolbarItem is present in the order list; append any
    // missing items at the end.
    for (final item in ToolbarItem.values) {
      if (!seen.contains(item)) deduped.add(item);
    }
    // Rebuild visibleItems respecting the new order.
    final visibleSet = current.visibleItems.toSet();
    final newVisible = deduped.where((e) => visibleSet.contains(e)).toList();
    _cache = ToolbarConfig(visibleItems: newVisible, order: deduped);
    await _persist();
  }

  /// Restores the factory default configuration.
  Future<void> resetToDefaults() async {
    _cache = getDefaults();
    await _persist();
  }

  // ---- Persistence ---------------------------------------------------------

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(getConfig().toJson()));
  }
}
