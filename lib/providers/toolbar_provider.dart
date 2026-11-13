// lib/providers/toolbar_provider.dart
//
// Riverpod providers for toolbar customisation and per-panel view modes.

import 'dart:io' show Platform;
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../models/file_view_configuration.dart';
import '../services/log_service.dart';
import '../services/panel_view_mode_service.dart';
import '../services/toolbar_customization_service.dart';

bool get _isTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

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
final panelViewModeServiceProvider = Provider<PanelViewModeService>(
  (ref) => PanelViewModeService(),
);

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
    StateNotifierProvider<ToolbarConfigNotifier, ToolbarConfig>((ref) {
      final svc = ref.watch(toolbarCustomizationServiceProvider);
      return ToolbarConfigNotifier(svc);
    });

// ---------------------------------------------------------------------------
// PanelViewMode — family provider
// ---------------------------------------------------------------------------

/// Notifier that holds the [PanelViewMode] for one panel side.
class PanelViewModeNotifier extends StateNotifier<PanelViewMode> {
  PanelViewModeNotifier(this._service, this._side) : super(PanelViewMode.full) {
    _service.getMode(_side).then((mode) {
      if (mounted && _revision == 0) state = mode;
    });
  }

  final PanelViewModeService _service;
  final PanelSide _side;
  int _revision = 0;

  Future<void> applyMode(PanelViewMode mode, {bool persist = false}) async {
    _revision++;
    if (mounted) state = mode;
    if (persist) await _service.setMode(_side, mode);
  }

  Future<void> setMode(PanelViewMode mode) => applyMode(mode, persist: true);

  Future<void> cycleMode() async {
    var next = state.next;
    // Tree view is not available on web — skip to brief.
    if (next == PanelViewMode.tree && kIsWeb) {
      next = PanelViewMode.brief;
    }
    await setMode(next);
  }
}

/// Family provider keyed by [PanelSide]; returns the view mode for that panel.
final panelViewModeProvider =
    StateNotifierProvider.family<
      PanelViewModeNotifier,
      PanelViewMode,
      PanelSide
    >((ref, side) {
      final svc = ref.watch(panelViewModeServiceProvider);
      return PanelViewModeNotifier(svc, side);
    });

/// Per-panel column widths for the compact "Full" view.
/// Keys: 'size', 'date'. Values: pixel widths. Shared between header and tiles.
/// Persisted to SharedPreferences.
final columnWidthsProvider =
    StateNotifierProvider.family<
      _ColumnWidthsNotifier,
      Map<String, double>,
      dynamic
    >((ref, side) => _ColumnWidthsNotifier(side.toString()));

class _ColumnWidthsNotifier extends StateNotifier<Map<String, double>> {
  final String _sideKey;
  int _revision = 0;

  _ColumnWidthsNotifier(this._sideKey)
    : super({'size': 96.0, 'date': 78.0, 'ext': 40.0}) {
    _load();
  }

  Future<void> _load() async {
    if (_isTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = prefs.getString('col_${_sideKey}_all_v1');
      if (serialized != null) {
        final widths = (jsonDecode(serialized) as Map).map(
          (key, value) => MapEntry(key as String, (value as num).toDouble()),
        );
        FileViewConfiguration(widths: widths);
        if (mounted && _revision == 0) state = widths;
        return;
      }
      final size = prefs.getDouble('col_${_sideKey}_size') ?? 96.0;
      final date = prefs.getDouble('col_${_sideKey}_date') ?? 78.0;
      final ext = prefs.getDouble('col_${_sideKey}_ext') ?? 40.0;
      if (mounted && _revision == 0) {
        state = {'size': size, 'date': date, 'ext': ext};
      }
    } catch (e) {
      // Silently ignored
    }
  }

  void setWidth(String col, double w) {
    _revision++;
    state = {...state, col: w.clamp(24.0, 600.0)};
    _save();
  }

  void applyWidths(Map<String, double> widths, {bool persist = false}) {
    FileViewConfiguration(widths: widths);
    _revision++;
    state = Map.of(widths);
    if (persist) _save();
  }

  Future<void> _save() async {
    if (_isTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('col_${_sideKey}_all_v1', jsonEncode(state))) {
        throw StateError('Column widths could not be saved.');
      }
    } catch (error) {
      const Log('Columns').warn('Could not save column widths', error);
    }
  }

  bool isVisible(String col) => (state[col] ?? 0) > 0;

  void toggleVisibility(String col, {double? defaultWidth}) {
    final current = state[col] ?? defaultWidth ?? 0;
    if (current <= 0) {
      // Restore to default
      final defaults = {'size': 96.0, 'date': 78.0, 'ext': 40.0};
      setWidth(col, current < 0 ? -current : defaults[col] ?? 62.0);
    } else {
      // Hide: store as negative (remember last width)
      final hidden = -current;
      _revision++;
      state = {...state, col: hidden};
      _save();
    }
  }
}

class FileColumnsNotifier extends StateNotifier<List<FileColumnDefinition>> {
  FileColumnsNotifier(this.side) : super(FileColumnDefinition.defaults) {
    _load();
  }
  final PanelSide side;
  int _revision = 0;
  String get _key => 'file_columns_${side.name}_v1';

  Future<void> _load() async {
    if (_isTest) return;
    try {
      final text = (await SharedPreferences.getInstance()).getString(_key);
      if (text == null) return;
      final columns = (jsonDecode(text) as List)
          .map(
            (value) => FileColumnDefinition.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      FileViewConfiguration(columns: columns);
      if (mounted && _revision == 0) state = List.unmodifiable(columns);
    } catch (error) {
      const Log('Columns').warn('Could not load column definitions', error);
    }
  }

  void applyColumns(
    List<FileColumnDefinition> columns, {
    bool persist = false,
  }) {
    FileViewConfiguration(columns: columns);
    _revision++;
    state = List.unmodifiable(columns);
    if (persist) _save();
  }

  Future<void> _save() async {
    if (_isTest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _key,
        jsonEncode(state.map((column) => column.toJson()).toList()),
      )) {
        throw StateError('Column definitions could not be saved.');
      }
    } catch (error) {
      const Log('Columns').warn('Could not save column definitions', error);
    }
  }
}

final fileColumnsProvider =
    StateNotifierProvider.family<
      FileColumnsNotifier,
      List<FileColumnDefinition>,
      PanelSide
    >((ref, side) => FileColumnsNotifier(side));
