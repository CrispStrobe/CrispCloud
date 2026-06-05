// lib/services/plugin_service.dart
//
// Plugin API, registry, models, and sandboxed execution context for CrispCloud.
//
// Usage:
//   final registry = PluginRegistry();
//   registry.registerPlugin(MyPlugin());
//   await registry.initializeAll();
//   await registry.notifyFileAction(FileAction.upload, ['/path/to/file']);

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// What a plugin is capable of doing inside CrispCloud.
enum PluginCapability {
  contextMenu,
  toolbar,
  fileAction,
  preview,
  provider,
  settings,
}

/// File operations that can trigger plugin hooks.
enum FileAction {
  upload,
  download,
  delete,
  rename,
  move,
  copy,
  create,
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A menu item contributed by a plugin to the context menu.
class PluginMenuItem {
  final String id;
  final String label;

  /// Icon name string (e.g. 'Icons.star') — UI layer resolves to an IconData.
  final String icon;
  final bool enabled;

  /// Optional callback invoked when the menu item is selected.
  final void Function(List<String> filePaths)? onSelected;

  const PluginMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.onSelected,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': icon,
        'enabled': enabled,
      };

  factory PluginMenuItem.fromJson(Map<String, dynamic> json) => PluginMenuItem(
        id: json['id'] as String,
        label: json['label'] as String,
        icon: json['icon'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is PluginMenuItem &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, icon, enabled);

  @override
  String toString() =>
      'PluginMenuItem(id: $id, label: $label, icon: $icon, enabled: $enabled)';
}

/// A button contributed by a plugin to the toolbar.
class PluginToolbarButton {
  final String id;
  final String label;
  final String tooltip;
  final String icon;

  /// Key used by the UI to look up the onPressed handler.
  final String onPressedKey;

  const PluginToolbarButton({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressedKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'tooltip': tooltip,
        'icon': icon,
        'onPressedKey': onPressedKey,
      };

  factory PluginToolbarButton.fromJson(Map<String, dynamic> json) =>
      PluginToolbarButton(
        id: json['id'] as String,
        label: json['label'] as String,
        tooltip: json['tooltip'] as String,
        icon: json['icon'] as String,
        onPressedKey: json['onPressedKey'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PluginToolbarButton &&
      other.id == id &&
      other.label == label &&
      other.tooltip == tooltip &&
      other.icon == icon &&
      other.onPressedKey == onPressedKey;

  @override
  int get hashCode => Object.hash(id, label, tooltip, icon, onPressedKey);

  @override
  String toString() =>
      'PluginToolbarButton(id: $id, label: $label, tooltip: $tooltip)';
}

/// Persisted per-plugin settings: enabled flag plus arbitrary settings map.
class PluginSettings {
  final String pluginId;
  final bool enabled;
  final Map<String, dynamic> settings;

  const PluginSettings({
    required this.pluginId,
    required this.enabled,
    this.settings = const {},
  });

  PluginSettings copyWith({
    bool? enabled,
    Map<String, dynamic>? settings,
  }) =>
      PluginSettings(
        pluginId: pluginId,
        enabled: enabled ?? this.enabled,
        settings: settings ?? this.settings,
      );

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'enabled': enabled,
        'settings': settings,
      };

  factory PluginSettings.fromJson(Map<String, dynamic> json) => PluginSettings(
        pluginId: json['pluginId'] as String,
        enabled: json['enabled'] as bool? ?? true,
        settings:
            (json['settings'] as Map<String, dynamic>?) ?? const {},
      );

  @override
  bool operator ==(Object other) =>
      other is PluginSettings &&
      other.pluginId == pluginId &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(pluginId, enabled);

  @override
  String toString() =>
      'PluginSettings(pluginId: $pluginId, enabled: $enabled)';
}

// ---------------------------------------------------------------------------
// PluginContext — sandboxed execution context passed to plugins
// ---------------------------------------------------------------------------

/// Sandboxed context provided to each plugin on initialisation.
///
/// Deliberately does NOT expose credentials, secure storage, or raw provider
/// clients. Plugins may only:
///   - read/write their own scoped temporary directory,
///   - read/write their own settings,
///   - emit log messages.
abstract class PluginContext {
  /// Path to a writable temporary directory scoped to this plugin.
  String get tempDir;

  /// Read the current settings for this plugin (merged with defaults).
  Future<Map<String, dynamic>> getSettings();

  /// Persist updated settings for this plugin.
  Future<void> saveSettings(Map<String, dynamic> settings);

  /// Emit a log message scoped to this plugin.
  void log(String message);
}

/// Default implementation of [PluginContext] backed by SharedPreferences.
class _PluginContextImpl implements PluginContext {
  final String _pluginId;
  final String _tempDir;
  final Map<String, dynamic> _defaults;
  static final _log = Log('PluginContext');

  _PluginContextImpl({
    required String pluginId,
    required String tempDir,
    required Map<String, dynamic> defaults,
  })  : _pluginId = pluginId,
        _tempDir = tempDir,
        _defaults = defaults;

  @override
  String get tempDir => _tempDir;

  @override
  Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsSettingsKey(_pluginId);
    final raw = prefs.getString(key);
    if (raw == null) return Map<String, dynamic>.from(_defaults);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // Merge: defaults fill in any keys not yet saved.
      return {..._defaults, ...decoded};
    } catch (_) {
      return Map<String, dynamic>.from(_defaults);
    }
  }

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSettingsKey(_pluginId), jsonEncode(settings));
  }

  @override
  void log(String message) {
    _log.info('[$_pluginId] $message');
  }
}

// ---------------------------------------------------------------------------
// Key helpers
// ---------------------------------------------------------------------------

String _prefsEnabledKey(String id) => 'plugin_enabled_$id';
String _prefsSettingsKey(String id) => 'plugin_settings_$id';

// ---------------------------------------------------------------------------
// CrispCloudPlugin — abstract interface
// ---------------------------------------------------------------------------

/// Abstract interface every CrispCloud plugin must implement.
abstract class CrispCloudPlugin {
  /// Unique reverse-DNS identifier, e.g. "com.example.my-plugin".
  String get id;

  /// Human-readable display name.
  String get name;

  /// Semantic version string, e.g. "1.0.0".
  String get version;

  /// Short description of what the plugin does.
  String get description;

  /// Optional author name.
  String? get author;

  /// Optional homepage URL.
  String? get homepage;

  /// Declared capabilities — used to gate which hooks are called.
  List<PluginCapability> get capabilities;

  /// Called once when the plugin is loaded (and enabled).
  /// [context] provides the sandboxed execution environment.
  Future<void> initialize(PluginContext context);

  /// Called when the plugin is unloaded or the app shuts down.
  Future<void> dispose();

  /// Hook fired when a file operation occurs.
  /// Only called when [PluginCapability.fileAction] is declared.
  Future<void> onFileAction(FileAction action, List<String> filePaths);

  /// Return context-menu items to add for the given [filePaths].
  /// Only called when [PluginCapability.contextMenu] is declared.
  List<PluginMenuItem> getContextMenuItems(List<String> filePaths);

  /// Return toolbar buttons to add to the main toolbar.
  /// Only called when [PluginCapability.toolbar] is declared.
  List<PluginToolbarButton> getToolbarButtons();

  /// Return the default settings schema for this plugin.
  /// Returned as a flat Map<String, dynamic> where values are the defaults.
  Map<String, dynamic> getDefaultSettings();
}

// ---------------------------------------------------------------------------
// PluginRegistry
// ---------------------------------------------------------------------------

/// Central registry for all installed plugins.
///
/// Preserves registration order. Use [initializeAll] during app startup
/// and [disposeAll] on shutdown.
class PluginRegistry {
  static final _log = Log('PluginRegistry');

  // Ordered list preserves registration order.
  final List<CrispCloudPlugin> _plugins = [];

  // Mutable settings map keyed by plugin id.
  final Map<String, PluginSettings> _settings = {};

  // Whether persistence has been loaded from SharedPreferences.
  bool _loaded = false;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _loadAllSettings();
    _loaded = true;
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (final plugin in _plugins) {
      final enabled =
          prefs.getBool(_prefsEnabledKey(plugin.id)) ?? true;
      final raw = prefs.getString(_prefsSettingsKey(plugin.id));
      Map<String, dynamic> savedSettings = {};
      if (raw != null) {
        try {
          savedSettings = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      final merged = {...plugin.getDefaultSettings(), ...savedSettings};
      _settings[plugin.id] = PluginSettings(
        pluginId: plugin.id,
        enabled: enabled,
        settings: merged,
      );
    }
  }

  Future<void> _persistEnabled(String id, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey(id), enabled);
  }

  PluginContext _contextFor(CrispCloudPlugin plugin) => _PluginContextImpl(
        pluginId: plugin.id,
        tempDir: '/tmp/crisp_plugins/${plugin.id}',
        defaults: plugin.getDefaultSettings(),
      );

  bool _isEnabled(String id) => _settings[id]?.enabled ?? true;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Register a plugin. Throws [ArgumentError] if a plugin with the same [id]
  /// is already registered.
  void registerPlugin(CrispCloudPlugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) {
      throw ArgumentError(
          'A plugin with id "${plugin.id}" is already registered.');
    }
    _plugins.add(plugin);
    // Set up default settings entry (enable by default).
    if (!_settings.containsKey(plugin.id)) {
      _settings[plugin.id] = PluginSettings(
        pluginId: plugin.id,
        enabled: true,
        settings: Map<String, dynamic>.from(plugin.getDefaultSettings()),
      );
    }
    _log.info('Plugin registered', {'id': plugin.id, 'name': plugin.name});
  }

  /// Unregister a plugin, calling [dispose] on it first.
  ///
  /// Does nothing if the plugin is not registered.
  Future<void> unregisterPlugin(String id) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final plugin = _plugins[index];
    try {
      await plugin.dispose();
    } catch (e) {
      _log.error('Error disposing plugin "$id"', e);
    }
    _plugins.removeAt(index);
    _settings.remove(id);
    _log.info('Plugin unregistered', {'id': id});
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Return the plugin with the given [id], or null if not registered.
  CrispCloudPlugin? getPlugin(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// All registered plugins in registration order.
  List<CrispCloudPlugin> getAllPlugins() => List.unmodifiable(_plugins);

  /// All registered plugins that are currently enabled.
  List<CrispCloudPlugin> getEnabledPlugins() =>
      _plugins.where((p) => _isEnabled(p.id)).toList();

  // ---------------------------------------------------------------------------
  // Enable / disable
  // ---------------------------------------------------------------------------

  /// Enable or disable a plugin by [id] and persist the state.
  Future<void> setEnabled(String id, bool enabled) async {
    if (!_plugins.any((p) => p.id == id)) return;
    final current = _settings[id] ??
        PluginSettings(pluginId: id, enabled: enabled);
    _settings[id] = current.copyWith(enabled: enabled);
    await _persistEnabled(id, enabled);
    _log.info('Plugin ${enabled ? "enabled" : "disabled"}', {'id': id});
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Call [initialize] on all currently enabled plugins.
  Future<void> initializeAll() async {
    await _ensureLoaded();
    for (final plugin in getEnabledPlugins()) {
      try {
        await plugin.initialize(_contextFor(plugin));
        _log.info('Plugin initialized', {'id': plugin.id});
      } catch (e) {
        _log.error('Plugin "${plugin.id}" failed to initialize', e);
      }
    }
  }

  /// Call [dispose] on all registered plugins and clear the registry.
  Future<void> disposeAll() async {
    for (final plugin in List.of(_plugins)) {
      try {
        await plugin.dispose();
      } catch (e) {
        _log.error('Plugin "${plugin.id}" failed to dispose', e);
      }
    }
    _plugins.clear();
    _settings.clear();
    _loaded = false;
    _log.info('All plugins disposed');
  }

  // ---------------------------------------------------------------------------
  // Event broadcasting
  // ---------------------------------------------------------------------------

  /// Notify all enabled plugins with [PluginCapability.fileAction] of a file
  /// operation.
  Future<void> notifyFileAction(
      FileAction action, List<String> filePaths) async {
    final candidates = getEnabledPlugins()
        .where((p) => p.capabilities.contains(PluginCapability.fileAction));
    for (final plugin in candidates) {
      try {
        await plugin.onFileAction(action, filePaths);
      } catch (e) {
        _log.error(
            'Plugin "${plugin.id}" threw on fileAction ${action.name}', e);
      }
    }
  }

  /// Collect context-menu items from all enabled plugins that declare
  /// [PluginCapability.contextMenu].
  List<PluginMenuItem> getContextMenuItems(List<String> filePaths) {
    final items = <PluginMenuItem>[];
    for (final plugin in getEnabledPlugins()) {
      if (!plugin.capabilities.contains(PluginCapability.contextMenu)) {
        continue;
      }
      try {
        items.addAll(plugin.getContextMenuItems(filePaths));
      } catch (e) {
        _log.error(
            'Plugin "${plugin.id}" threw on getContextMenuItems', e);
      }
    }
    return items;
  }

  /// Collect toolbar buttons from all enabled plugins that declare
  /// [PluginCapability.toolbar].
  List<PluginToolbarButton> getToolbarButtons() {
    final buttons = <PluginToolbarButton>[];
    for (final plugin in getEnabledPlugins()) {
      if (!plugin.capabilities.contains(PluginCapability.toolbar)) {
        continue;
      }
      try {
        buttons.addAll(plugin.getToolbarButtons());
      } catch (e) {
        _log.error('Plugin "${plugin.id}" threw on getToolbarButtons', e);
      }
    }
    return buttons;
  }

  // ---------------------------------------------------------------------------
  // Settings access (for provider layer)
  // ---------------------------------------------------------------------------

  /// Return the current [PluginSettings] for [pluginId], or null if unknown.
  PluginSettings? getPluginSettings(String pluginId) =>
      _settings[pluginId];

  /// Overwrite the in-memory settings for [pluginId] and persist.
  Future<void> savePluginSettings(
      String pluginId, Map<String, dynamic> newSettings) async {
    if (!_settings.containsKey(pluginId)) return;
    final current = _settings[pluginId]!;
    _settings[pluginId] = current.copyWith(settings: newSettings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSettingsKey(pluginId), jsonEncode(newSettings));
  }
}
