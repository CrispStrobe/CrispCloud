// lib/providers/plugin_provider.dart
//
// Riverpod providers for the plugin system.
//
// Usage:
//   final registry = ref.watch(pluginRegistryProvider);
//   final enabled  = ref.watch(enabledPluginsProvider);
//   final settings = ref.watch(pluginSettingsProvider('com.example.my-plugin'));

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/plugin_service.dart';

export '../services/plugin_service.dart'
    show
        CrispCloudPlugin,
        FileAction,
        PluginCapability,
        PluginContext,
        PluginMenuItem,
        PluginRegistry,
        PluginSettings,
        PluginToolbarButton;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// ChangeNotifier wrapping [PluginRegistry].
///
/// Exposes mutating operations and calls [notifyListeners] after each one
/// so dependent widgets rebuild automatically.
class PluginRegistryNotifier extends ChangeNotifier {
  static final _registry = PluginRegistry();

  PluginRegistry get registry => _registry;

  /// Register a plugin and notify listeners.
  void registerPlugin(CrispCloudPlugin plugin) {
    _registry.registerPlugin(plugin);
    notifyListeners();
  }

  /// Unregister a plugin (disposing it) and notify listeners.
  Future<void> unregisterPlugin(String id) async {
    await _registry.unregisterPlugin(id);
    notifyListeners();
  }

  /// Enable or disable a plugin and notify listeners.
  Future<void> setEnabled(String id, bool enabled) async {
    await _registry.setEnabled(id, enabled);
    notifyListeners();
  }

  /// Initialize all enabled plugins (call once at app startup).
  Future<void> initializeAll() => _registry.initializeAll();

  /// Dispose all plugins and clear the registry.
  Future<void> disposeAll() async {
    await _registry.disposeAll();
    notifyListeners();
  }

  /// Broadcast a file action to all enabled plugins.
  Future<void> notifyFileAction(
          FileAction action, List<String> filePaths) =>
      _registry.notifyFileAction(action, filePaths);

  /// Save updated settings for a plugin and notify listeners.
  Future<void> savePluginSettings(
      String pluginId, Map<String, dynamic> settings) async {
    await _registry.savePluginSettings(pluginId, settings);
    notifyListeners();
  }

  // Convenience pass-throughs
  List<CrispCloudPlugin> getAllPlugins() => _registry.getAllPlugins();
  List<CrispCloudPlugin> getEnabledPlugins() => _registry.getEnabledPlugins();
  CrispCloudPlugin? getPlugin(String id) => _registry.getPlugin(id);
  PluginSettings? getPluginSettings(String id) =>
      _registry.getPluginSettings(id);
  List<PluginMenuItem> getContextMenuItems(List<String> paths) =>
      _registry.getContextMenuItems(paths);
  List<PluginToolbarButton> getToolbarButtons() =>
      _registry.getToolbarButtons();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Singleton [PluginRegistryNotifier].
final pluginRegistryProvider =
    ChangeNotifierProvider<PluginRegistryNotifier>((ref) {
  return PluginRegistryNotifier();
});

/// Derived list of currently enabled plugins.
///
/// Rebuilds whenever the registry changes.
final enabledPluginsProvider = Provider<List<CrispCloudPlugin>>((ref) {
  final notifier = ref.watch(pluginRegistryProvider);
  return notifier.getEnabledPlugins();
});

/// Per-plugin settings family provider.
///
/// Returns null when the plugin is not registered.
final pluginSettingsProvider =
    Provider.family<PluginSettings?, String>((ref, pluginId) {
  final notifier = ref.watch(pluginRegistryProvider);
  return notifier.getPluginSettings(pluginId);
});
