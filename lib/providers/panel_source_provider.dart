// lib/providers/panel_source_provider.dart
//
// Riverpod providers for the dual-panel source system.
//   • panelSourceProvider(side)   — StateNotifier for each panel's PanelSource
//   • fkeyBarVisibleProvider      — toggle F-key bar visibility (persistent)
//   • oppositePanel(side)         — helper: the other PanelSide
//   • availableSourcesProvider    — list of selectable sources for the dropdown
//   • activeFKeyContextProvider   — FKeyContext for the currently active panel

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../services/fkey_action_service.dart';
import '../services/panel_source_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'multi_cloud_provider.dart';
import 'panel_provider.dart';

// ---------------------------------------------------------------------------
// Helper: opposite panel
// ---------------------------------------------------------------------------

/// Returns the [PanelSide] that is *not* [side].
PanelSide oppositePanel(PanelSide side) =>
    side == PanelSide.local ? PanelSide.remote : PanelSide.local;

// ---------------------------------------------------------------------------
// panelSourceProvider — family StateNotifier
// ---------------------------------------------------------------------------

class PanelSourceNotifier extends StateNotifier<PanelSource> {
  final PanelSide side;

  PanelSourceNotifier(this.side)
      : super(const LocalPanelSource('/')) {
    _restore();
  }

  // ---- Public API -----------------------------------------------------------

  /// Replace the current source entirely.
  void setSource(PanelSource source) {
    state = source;
    _persist();
  }

  /// Navigate inside the current source to a sub-path.
  void navigateTo(String path) {
    state = state.withPath(path);
    _persist();
  }

  /// Enter an archive file.
  void enterArchive(String archivePath) {
    const service = PanelSourceService();
    state = service.enterArchive(archivePath, state);
    _persist();
  }

  /// Unlock and enter an encrypted container.
  void enterContainer(String containerPath, String password) {
    const service = PanelSourceService();
    state = service.enterContainer(containerPath, password, state);
    _persist();
  }

  /// Navigate to the parent source (exit archive/container).
  void exitToParent() {
    const service = PanelSourceService();
    state = service.exitToParent(state);
    _persist();
  }

  // ---- Persistence ----------------------------------------------------------

  String get _prefKey => 'panel_source_${side.name}';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        // Only local sources can be restored safely.
        // Remote / archive / container require a live session.
        final defaultPath = prefs.getString('${_prefKey}_path') ?? '/';
        state = LocalPanelSource(defaultPath);
      }
    } catch (_) {
      // Silently ignore restore failures.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = state.toJson();
      // Persist only local path; remote/archive are session-only.
      if (json['type'] == 'local') {
        await prefs.setString(_prefKey, 'local');
        await prefs.setString('${_prefKey}_path', json['path'] as String);
      }
    } catch (_) {}
  }
}

/// Family provider: one [PanelSourceNotifier] per [PanelSide].
final panelSourceProvider =
    StateNotifierProvider.family<PanelSourceNotifier, PanelSource, PanelSide>(
  (ref, side) => PanelSourceNotifier(side),
);

// ---------------------------------------------------------------------------
// fkeyBarVisibleProvider — persistent toggle
// ---------------------------------------------------------------------------

class _FKeyBarVisibilityNotifier extends StateNotifier<bool> {
  static const _prefKey = 'fkey_bar_visible';

  _FKeyBarVisibilityNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, state);
    } catch (_) {}
  }

  Future<void> setVisible(bool visible) async {
    state = visible;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, state);
    } catch (_) {}
  }
}

final fkeyBarVisibleProvider =
    StateNotifierProvider<_FKeyBarVisibilityNotifier, bool>(
  (ref) => _FKeyBarVisibilityNotifier(),
);

// ---------------------------------------------------------------------------
// availableSourcesProvider
// ---------------------------------------------------------------------------

/// A [_SourceEntry] mirrors the private class in panel_source_selector.dart;
/// we define a public version here so tests can inspect available sources.
class AvailableSource {
  final String key;
  final String label;
  final PanelSource source;

  const AvailableSource({
    required this.key,
    required this.label,
    required this.source,
  });
}

/// Provides the list of sources the user can switch to in the dropdown.
/// Always includes Local; expands with connected cloud providers.
final availableSourcesProvider = Provider<List<AvailableSource>>((ref) {
  final sources = <AvailableSource>[
    const AvailableSource(
      key: 'local',
      label: 'Local',
      source: LocalPanelSource('/'),
    ),
  ];

  // Add the primary auth provider connection if connected.
  final auth = ref.watch(authProvider);
  if (auth.isConnected) {
    sources.add(AvailableSource(
      key: 'remote:${auth.providerName}',
      label: auth.providerName,
      source: RemotePanelSource(
        providerName: auth.providerName,
        client: auth.client,
        path: '/',
      ),
    ));
  }

  // Add all multi-cloud connections (skip duplicates).
  final multiCloud = ref.watch(multiCloudProvider);
  for (final conn in multiCloud.connections) {
    final key = 'remote:${conn.id}';
    if (sources.any((s) => s.key == key)) continue;
    sources.add(AvailableSource(
      key: key,
      label: conn.label,
      source: RemotePanelSource(
        providerName: conn.label,
        client: conn.client,
        path: '/',
      ),
    ));
  }

  return sources;
});

// ---------------------------------------------------------------------------
// activeFKeyContextProvider
// ---------------------------------------------------------------------------

/// Builds the [FKeyContext] for the currently active panel.
final activeFKeyContextProvider = Provider<FKeyContext?>((ref) {
  final activePanel = ref.watch(activePanelProvider);
  final opposite = oppositePanel(activePanel);

  final activeSrc = ref.watch(panelSourceProvider(activePanel));
  final oppositeSrc = ref.watch(panelSourceProvider(opposite));

  // Read selection from the panel notifier.
  final panel = ref.watch(panelProvider(activePanel));
  final selected = panel.selection.toList();

  if (selected.isNotEmpty) {
    debugPrint('[FKeyContext] rebuilt: ${selected.length} selected, '
        'hasSingleFile=${selected.length == 1 && !selected.first.isFolder}');
  }

  return FKeyContext(
    activePanel: activeSrc,
    oppositePanel: oppositeSrc,
    selectedFiles: selected,
  );
});
