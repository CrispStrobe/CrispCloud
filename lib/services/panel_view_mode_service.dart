// lib/services/panel_view_mode_service.dart
//
// Per-panel view mode: brief, full, tree.
// Implements PLAN.md 11.5.

import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';

// ---------------------------------------------------------------------------
// PanelViewMode
// ---------------------------------------------------------------------------

/// The three view modes available for each file-manager panel.
enum PanelViewMode {
  /// Compact rows showing filename only.
  brief,

  /// Standard rows showing filename, size, date and permissions.
  full,

  /// Hierarchical folder tree with expand/collapse controls.
  tree,
}

extension PanelViewModeX on PanelViewMode {
  /// Human-readable label used in menus and tooltips.
  String get displayName {
    switch (this) {
      case PanelViewMode.brief:
        return 'Brief';
      case PanelViewMode.full:
        return 'Full';
      case PanelViewMode.tree:
        return 'Tree';
    }
  }

  /// Toggle between the two implemented modes: brief (comfortable) ↔ full (compact).
  /// Tree view is reserved for a future implementation.
  PanelViewMode get next {
    switch (this) {
      case PanelViewMode.brief:
        return PanelViewMode.full;
      case PanelViewMode.full:
      case PanelViewMode.tree:
        return PanelViewMode.brief;
    }
  }

  String toJson() => name;

  static PanelViewMode fromJson(String value) {
    return PanelViewMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown PanelViewMode: $value'),
    );
  }
}

// ---------------------------------------------------------------------------
// PanelViewModeService
// ---------------------------------------------------------------------------

/// Manages and persists the view mode for the left (local) and right (remote)
/// panels independently.
class PanelViewModeService {
  static const _defaultMode = PanelViewMode.full;

  // In-memory cache keyed by PanelSide.
  final Map<PanelSide, PanelViewMode> _cache = {};

  // ---- Prefs key -----------------------------------------------------------

  static String _prefsKey(PanelSide side) =>
      'panel_view_mode_${side.name}_v1';

  // ---- Loading -------------------------------------------------------------

  /// Loads the persisted mode for [side].  Returns [_defaultMode] if nothing
  /// is stored or if the stored value is unrecognisable.
  Future<PanelViewMode> _load(PanelSide side) async {
    if (_cache.containsKey(side)) return _cache[side]!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(side));
    if (raw == null) {
      _cache[side] = _defaultMode;
      return _defaultMode;
    }
    try {
      final mode = PanelViewModeX.fromJson(raw);
      _cache[side] = mode;
      return mode;
    } catch (_) {
      _cache[side] = _defaultMode;
      return _defaultMode;
    }
  }

  // ---- Public API ----------------------------------------------------------

  /// Returns the current view mode for [side].
  ///
  /// If this is the first call the value is loaded from SharedPreferences;
  /// subsequent calls are served from the in-memory cache.
  Future<PanelViewMode> getMode(PanelSide side) => _load(side);

  /// Sets the view mode for [side] and persists it.
  Future<void> setMode(PanelSide side, PanelViewMode mode) async {
    _cache[side] = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey(side), mode.toJson());
  }

  /// Advances [side] to the next mode in the brief → full → tree → brief
  /// cycle and persists it.
  Future<PanelViewMode> cycleMode(PanelSide side) async {
    final current = await getMode(side);
    final next = current.next;
    await setMode(side, next);
    return next;
  }
}
