// lib/providers/toolbar_provider.dart
//
// Riverpod providers for toolbar customisation and per-panel view modes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../services/panel_view_mode_service.dart';
import '../services/toolbar_customization_service.dart';

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
    final next = await _service.cycleMode(_side);
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
