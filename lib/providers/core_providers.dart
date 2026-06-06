// lib/providers/core_providers.dart
//
// Base dependencies injected via ProviderScope overrides in main.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../services/audit_service.dart';
import '../services/file_cache_service.dart';
import '../services/local_file_service.dart';
import '../services/thumbnail_service.dart';
import '../services/proxy_service.dart';
import '../services/secure_storage_service.dart';

/// Platform secure storage — overridden in main.dart with the real instance.
final secureStorageProvider = Provider<SecureStorage>((ref) {
  throw UnimplementedError('secureStorageProvider must be overridden');
});

/// Platform-specific config path — overridden in main.dart.
final configPathProvider = Provider<String>((ref) {
  throw UnimplementedError('configPathProvider must be overridden');
});

/// Singleton local file service.
final localFileServiceProvider = Provider<LocalFileService>((ref) {
  return LocalFileService();
});

/// Which panel is active (Local / Remote).
final activePanelProvider = StateProvider<PanelSide>((ref) => PanelSide.local);

/// Whether the preview pane is visible.
final showPreviewProvider = StateProvider<bool>((ref) => false);

/// Whether the tree sidebar is visible.
final showTreeSidebarProvider = StateProvider<bool>((ref) => false);

/// Show the selection action bar inside the panel (touch/tablet mode).
/// Default false: DC-mode uses status bar + F-keys + keyboard shortcuts only.
final showSelectionBarProvider = StateProvider<bool>((ref) => false);

/// Panel split ratio (0.0–1.0, left panel share).
final panelSplitRatioProvider = StateProvider<double>((ref) => 0.5);

/// File view mode per panel.
enum ViewMode { list, grid, column }
final localViewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.list);
final remoteViewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.list);

/// Proxy service — overridden in main.dart with the loaded instance.
final proxyServiceProvider = Provider<ProxyService>((ref) {
  return ProxyService(); // Default: no proxy
});

/// File cache service — overridden in main.dart with initialized instance.
final fileCacheProvider = Provider<FileCacheService>((ref) {
  return FileCacheService();
});

/// Thumbnail service — overridden in main.dart with initialized instance.
final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  return ThumbnailService();
});

/// Audit service — overridden in main.dart with initialized instance.
final auditServiceProvider = Provider<AuditService>((ref) {
  return AuditService();
});

// ---------------------------------------------------------------------------
// Layout Presets
// ---------------------------------------------------------------------------

/// Available layout presets.
enum LayoutPreset {
  /// Two-panel Commander-style layout (default).
  commander,

  /// Single panel with tree sidebar always visible.
  explorer,

  /// Single panel, grid view forced.
  gallery,
}

// ---------------------------------------------------------------------------
// Font Settings
// ---------------------------------------------------------------------------

/// Configurable font size for file lists (default 13.0).
final fontSizeProvider = StateNotifierProvider<_FontSizeNotifier, double>(
  (ref) => _FontSizeNotifier(),
);

class _FontSizeNotifier extends StateNotifier<double> {
  _FontSizeNotifier() : super(13.0) { _load(); }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = prefs.getDouble('font_size');
      if (size != null) state = size;
    } catch (_) {}
  }
  Future<void> setSize(double size) async {
    state = size.clamp(10.0, 20.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('font_size', state);
    } catch (_) {}
  }
}

/// Configurable font family (default 'system', options: system, monospace, serif, sansSerif).
final fontFamilyProvider = StateNotifierProvider<_FontFamilyNotifier, String>(
  (ref) => _FontFamilyNotifier(),
);

class _FontFamilyNotifier extends StateNotifier<String> {
  _FontFamilyNotifier() : super('system') { _load(); }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString('font_family') ?? 'system';
    } catch (_) {}
  }
  Future<void> setFamily(String family) async {
    state = family;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('font_family', state);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Privacy Score
// ---------------------------------------------------------------------------

/// Calculate privacy score for a provider (0-100).
/// E2E encrypted = 100, encrypted-at-rest = 70, encrypted-in-transit = 40, unencrypted = 10
int privacyScore(String providerName) {
  switch (providerName.toLowerCase()) {
    case 'filen': return 100;   // E2E encrypted
    case 'internxt': return 100; // E2E encrypted
    case 's3': return 60;       // encrypted-at-rest (optional SSE)
    case 'google drive': case 'gdrive': return 50; // encrypted-at-rest
    case 'onedrive': return 50;  // encrypted-at-rest
    case 'dropbox': return 50;   // encrypted-at-rest
    case 'pcloud': return 55;    // crypto folder option
    case 'nextcloud': return 65; // self-hosted, E2E optional
    case 'sftp': return 70;      // encrypted-in-transit, user controls server
    case 'webdav': return 40;    // depends on HTTPS config
    case 'ftp': return 20;       // plain text unless FTPS
    default: return 30;
  }
}

/// Privacy score label.
String privacyLabel(int score) {
  if (score >= 90) return 'Excellent';
  if (score >= 70) return 'Good';
  if (score >= 50) return 'Fair';
  if (score >= 30) return 'Low';
  return 'Poor';
}

// ---------------------------------------------------------------------------
// Security: Disable Screenshots (Mobile)
// ---------------------------------------------------------------------------

/// Whether to disable screenshots on mobile (opt-in).
final disableScreenshotsProvider = StateNotifierProvider<_DisableScreenshotsNotifier, bool>(
  (ref) => _DisableScreenshotsNotifier(),
);

class _DisableScreenshotsNotifier extends StateNotifier<bool> {
  _DisableScreenshotsNotifier() : super(false) { _load(); }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool('disable_screenshots') ?? false;
    } catch (_) {}
  }
  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('disable_screenshots', state);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// External Editor
// ---------------------------------------------------------------------------

const _preferExternalEditorKey = 'prefer_external_editor';

/// When true, "Edit" in the context menu defaults to opening with the system
/// editor instead of the built-in editor.
final preferExternalEditorProvider =
    StateNotifierProvider<PreferExternalEditorNotifier, bool>(
  (ref) => PreferExternalEditorNotifier(),
);

class PreferExternalEditorNotifier extends StateNotifier<bool> {
  PreferExternalEditorNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferExternalEditorKey) ?? false;
    } catch (_) {}
  }

  Future<void> toggle() => setValue(!state);

  Future<void> setValue(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferExternalEditorKey, value);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------

const _layoutPresetKey = 'layout_preset';

/// Currently selected layout preset. Persisted to SharedPreferences.
final layoutPresetProvider =
    StateNotifierProvider<LayoutPresetNotifier, LayoutPreset>(
  (ref) => LayoutPresetNotifier(),
);

class LayoutPresetNotifier extends StateNotifier<LayoutPreset> {
  LayoutPresetNotifier() : super(LayoutPreset.commander) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_layoutPresetKey);
      if (name != null) {
        final preset = LayoutPreset.values.firstWhere(
          (p) => p.name == name,
          orElse: () => LayoutPreset.commander,
        );
        state = preset;
      }
    } catch (_) {}
  }

  Future<void> setPreset(LayoutPreset preset) async {
    state = preset;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_layoutPresetKey, preset.name);
    } catch (_) {}
  }
}
