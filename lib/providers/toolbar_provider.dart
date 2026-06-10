// lib/providers/toolbar_provider.dart
//
// Riverpod providers for toolbar customisation and per-panel view modes.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../services/panel_view_mode_service.dart';
import '../services/toolbar_customization_service.dart';

bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

// ---------------------------------------------------------------------------
// Service singletons
// ---------------------------------------------------------------------------

/// Singleton [ToolbarCustomizationService].
///
/// Load is kicked off immediately; the StateNotifier re-reads after it
/// completes.
final toolbarCustomizationServiceProvider =
    Provider<ToolbarCustomizationService>((ref) {
  final svc = ToolbarCustomizationService();
  svc.load();
  return svc;
});

/// Singleton [PanelViewModeService].
final panelViewModeServiceProvider =
    Provider<PanelViewModeService>((ref) => PanelViewModeService());

// ---------------------------------------------------------------------------
// ToolbarConfig — StateNotifier
// ---------------------------------------------------------------------------

/// Notifier that holds the current [ToolbarConfig] and exposes mutation
/// methods that keep state in sync with the persisted service.
class ToolbarConfigNotifier extends StateNotifier<ToolbarConfig> {
  ToolbarConfigNotifier(this._service) : super(_service.getConfig()) {
    // Reload after the async load completes.
    _service.load().then((_) {
      if (mounted) state = _service.getConfig();
    });
  }

  final ToolbarCustomizationService _service;

  void _refresh() => state = _service.getConfig();

  Future<void> setVisibility(ToolbarItem item, bool visible) async {
    await _service.setVisibility(item, visible);
    _refresh();
  }

  Future<void> setOrder(List<ToolbarItem> items) async {
    await _service.setOrder(items);
    _refresh();
  }

  Future<void> resetToDefaults() async {
    await _service.resetToDefaults();
    _refresh();
  }

  bool isVisible(ToolbarItem item) => _service.isVisible(item);
}

/// StateNotifier provider for the full [ToolbarConfig].
final toolbarConfigProvider =
    StateNotifierProvider<ToolbarConfigNotifier, ToolbarConfig>(
  (ref) {
    final svc = ref.watch(toolbarCustomizationServiceProvider);
    return ToolbarConfigNotifier(svc);
  },
);

// ---------------------------------------------------------------------------
// PanelViewMode — family provider
// ---------------------------------------------------------------------------

/// Notifier that holds the [PanelViewMode] for one panel side.
class PanelViewModeNotifier extends StateNotifier<PanelViewMode> {
  PanelViewModeNotifier(this._service, this._side)
      : super(PanelViewMode.full) {
    _service.getMode(_side).then((mode) {
      if (mounted) state = mode;
    });
  }

  final PanelViewModeService _service;
  final PanelSide _side;

  Future<void> setMode(PanelViewMode mode) async {
    await _service.setMode(_side, mode);
    state = mode;
  }

  Future<void> cycleMode() async {
    var next = await _service.cycleMode(_side);
    // Tree view is not available on web — skip to brief.
    if (next == PanelViewMode.tree && kIsWeb) {
      next = PanelViewMode.brief;
      await _service.setMode(_side, next);
    }
    state = next;
  }
}

/// Family provider keyed by [PanelSide]; returns the view mode for that panel.
final panelViewModeProvider = StateNotifierProvider.family<
    PanelViewModeNotifier, PanelViewMode, PanelSide>(
  (ref, side) {
    final svc = ref.watch(panelViewModeServiceProvider);
    return PanelViewModeNotifier(svc, side);
  },
);

/// Per-panel column widths for the compact "Full" view.
/// Keys: 'size', 'date'. Values: pixel widths. Shared between header and tiles.
/// Persisted to SharedPreferences.
final columnWidthsProvider =
    StateNotifierProvider.family<_ColumnWidthsNotifier, Map<String, double>, dynamic>(
  (ref, side) => _ColumnWidthsNotifier(side.toString()),
);

class _ColumnWidthsNotifier extends StateNotifier<Map<String, double>> {
  final String _sideKey;

  _ColumnWidthsNotifier(this._sideKey)
      : super({'size': 62.0, 'date': 78.0, 'ext': 40.0}) {
    _load();
  }

  Future<void> _load() async {
    if (_isTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = prefs.getDouble('col_${_sideKey}_size') ?? 62.0;
      final date = prefs.getDouble('col_${_sideKey}_date') ?? 78.0;
      final ext = prefs.getDouble('col_${_sideKey}_ext') ?? 40.0;
      state = {'size': size, 'date': date, 'ext': ext};
    } catch (_) {}
  }

  void setWidth(String col, double w) {
    state = {...state, col: w.clamp(36.0, 200.0)};
    if (!_isTest) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble('col_${_sideKey}_$col', state[col]!);
      });
    }
  }

  bool isVisible(String col) => (state[col] ?? 0) > 0;

  void toggleVisibility(String col) {
    final current = state[col] ?? 0;
    if (current <= 0) {
      // Restore to default
      final defaults = {'size': 62.0, 'date': 78.0, 'ext': 40.0};
      setWidth(col, defaults[col] ?? 62.0);
    } else {
      // Hide: store as negative (remember last width)
      final hidden = -current;
      state = {...state, col: hidden};
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble('col_${_sideKey}_$col', hidden);
      });
    }
  }
}
