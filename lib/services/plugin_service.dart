// lib/services/plugin_service.dart
//
// First-party plugin API, lifecycle registry, and scoped execution context.
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
import '../utils/async_lock.dart';
import 'plugin_workspace.dart';
export 'plugin_workspace.dart';

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
enum FileAction { upload, download, delete, rename, move, copy, create }

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

  PluginSettings copyWith({bool? enabled, Map<String, dynamic>? settings}) =>
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
    settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
  );

  @override
  bool operator ==(Object other) =>
      other is PluginSettings &&
      other.pluginId == pluginId &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(pluginId, enabled);

  @override
  String toString() => 'PluginSettings(pluginId: $pluginId, enabled: $enabled)';
}

// ---------------------------------------------------------------------------
// PluginContext — scoped resources passed to trusted first-party plugins
// ---------------------------------------------------------------------------

/// A narrow convenience API for trusted in-process Dart code. It does not
/// expose credentials or provider clients, but it is NOT an OS sandbox: Dart
/// code compiled into the application still has the application's privileges.
abstract class PluginContext {
  /// A real scoped directory on native platforms, or a virtual memory namespace
  /// on web. Native filesystem APIs are not available on web.
  String get tempDir;
  Future<Map<String, dynamic>> getSettings();
  Future<void> saveSettings(Map<String, dynamic> settings);
  void log(String message);
}

class _PluginContextImpl implements PluginContext {
  _PluginContextImpl(this.id, this.workspace, this.read, this.write);
  final String id;
  final PluginWorkspace workspace;
  final Map<String, dynamic> Function() read;
  final Future<void> Function(Map<String, dynamic>) write;
  bool active = true;
  void _check() {
    if (!active) throw StateError('This extension context has been disposed.');
  }

  @override
  String get tempDir {
    _check();
    return workspace.path;
  }

  @override
  Future<Map<String, dynamic>> getSettings() async {
    _check();
    return read();
  }

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    _check();
    await write(settings);
  }

  @override
  void log(String message) {
    _check();
    const Log('PluginContext').info('[$id] $message');
  }

  Future<void> close() async {
    active = false;
    await workspace.close();
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
  /// [context] provides scoped resources, not an operating-system sandbox.
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
enum PluginRuntimeStatus { registered, disabled, initializing, ready, failed }

typedef PluginWorkspaceFactory = Future<PluginWorkspace> Function(String id);

class PluginRegistry {
  PluginRegistry({
    PluginWorkspaceFactory? workspaceFactory,
    Future<SharedPreferences> Function()? preferences,
  }) : _workspaceFactory = workspaceFactory ?? createPluginWorkspace,
       _preferences = preferences ?? SharedPreferences.getInstance;
  static const _log = Log('PluginRegistry');
  final PluginWorkspaceFactory _workspaceFactory;
  final Future<SharedPreferences> Function() _preferences;
  final _lifecycle = AsyncLock();
  final _settingsLock = AsyncLock();
  final List<CrispCloudPlugin> _plugins = [];
  final Map<String, PluginSettings> _settings = {};
  final Map<String, PluginRuntimeStatus> _status = {};
  final Map<String, String> _errors = {};
  final Map<String, _PluginContextImpl> _contexts = {};
  final Set<String> _loaded = {};
  final Set<String> _started = {};

  Map<String, String> get errors => Map.unmodifiable(_errors);
  PluginRuntimeStatus? statusOf(String id) => _status[id];
  bool isReady(String id) =>
      _status[id] == PluginRuntimeStatus.ready &&
      _settings[id]?.enabled == true;

  static Map<String, dynamic> _copySettings(Map<String, dynamic> settings) {
    final text = jsonEncode(settings);
    if (utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('Extension settings exceed 1 MiB.');
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  void _failed(String id, Object error) {
    _errors[id] = error.toString();
    _status[id] = PluginRuntimeStatus.failed;
    _log.error('Extension "$id" failed', error);
  }

  Future<bool> _loadSettings(CrispCloudPlugin plugin) async {
    if (_loaded.contains(plugin.id)) return true;
    try {
      final prefs = await _preferences();
      final enabled =
          prefs.getBool(_prefsEnabledKey(plugin.id)) ??
          _settings[plugin.id]!.enabled;
      _settings[plugin.id] = _settings[plugin.id]!.copyWith(enabled: enabled);
      final raw = prefs.getString(_prefsSettingsKey(plugin.id));
      final saved = raw == null
          ? <String, dynamic>{}
          : _copySettings(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      _settings[plugin.id] = PluginSettings(
        pluginId: plugin.id,
        enabled: enabled,
        settings: _copySettings({...plugin.getDefaultSettings(), ...saved}),
      );
      _loaded.add(plugin.id);
      if (!enabled) _status[plugin.id] = PluginRuntimeStatus.disabled;
      return true;
    } catch (error) {
      _failed(plugin.id, error);
      return false;
    }
  }

  Future<void> _writeSettings(
    String id,
    Map<String, dynamic> values, {
    bool Function()? isCurrent,
  }) => _settingsLock.synchronized(() async {
    final plugin = getPlugin(id);
    if (plugin == null) {
      throw StateError('The extension is no longer installed.');
    }
    final saved = _copySettings(values);
    final merged = _copySettings({...plugin.getDefaultSettings(), ...saved});
    final prefs = await _preferences();
    if (isCurrent?.call() == false) {
      throw StateError('This extension context has been disposed.');
    }
    if (!await prefs.setString(_prefsSettingsKey(id), jsonEncode(saved))) {
      throw StateError('Extension settings could not be saved.');
    }
    _settings[id] = _settings[id]!.copyWith(settings: merged);
  });

  Future<void> _stop(CrispCloudPlugin plugin) async {
    final id = plugin.id;
    _status[id] = PluginRuntimeStatus.disabled;
    if (_started.remove(id)) {
      try {
        await plugin.dispose();
      } catch (error) {
        _errors[id] = 'Dispose failed: $error';
        _log.error('Error disposing extension "$id"', error);
      }
    }
    final context = _contexts.remove(id);
    if (context != null) {
      try {
        await context.close();
      } catch (error) {
        _errors[id] = 'Temporary resource cleanup failed: $error';
      }
    }
  }

  Future<bool> _start(CrispCloudPlugin plugin) async {
    final id = plugin.id;
    if (isReady(id)) return true;
    if (_status[id] == PluginRuntimeStatus.failed ||
        !await _loadSettings(plugin)) {
      return false;
    }
    if (_settings[id]?.enabled != true) {
      _status[id] = PluginRuntimeStatus.disabled;
      return false;
    }
    _status[id] = PluginRuntimeStatus.initializing;
    _errors.remove(id);
    try {
      final workspace = await _workspaceFactory(id);
      late final _PluginContextImpl context;
      context = _PluginContextImpl(
        id,
        workspace,
        () => _copySettings(_settings[id]!.settings),
        (values) => _writeSettings(
          id,
          values,
          isCurrent: () => context.active && identical(_contexts[id], context),
        ),
      );
      _contexts[id] = context;
      _started.add(id);
      await plugin.initialize(context);
      _status[id] = PluginRuntimeStatus.ready;
      return true;
    } catch (error) {
      await _stop(plugin);
      _failed(id, error);
      return false;
    }
  }

  void registerPlugin(CrispCloudPlugin plugin, {bool enabledByDefault = true}) {
    validatePluginId(plugin.id);
    if (_plugins.any((value) => value.id == plugin.id)) {
      throw ArgumentError(
        'An extension with id "${plugin.id}" is already registered.',
      );
    }
    final defaults = _copySettings(plugin.getDefaultSettings());
    _plugins.add(plugin);
    _settings[plugin.id] = PluginSettings(
      pluginId: plugin.id,
      enabled: enabledByDefault,
      settings: defaults,
    );
    _status[plugin.id] = PluginRuntimeStatus.registered;
  }

  Future<void> unregisterPlugin(String id, {bool removeSettings = false}) =>
      _lifecycle.synchronized(() async {
        final plugin = getPlugin(id);
        if (plugin == null) return;
        await _stop(plugin);
        if (removeSettings) {
          final prefs = await _preferences();
          if (!await prefs.remove(_prefsEnabledKey(id)) ||
              !await prefs.remove(_prefsSettingsKey(id))) {
            throw StateError('Extension settings could not be removed.');
          }
        }
        _plugins.remove(plugin);
        _settings.remove(id);
        _status.remove(id);
        _errors.remove(id);
        _loaded.remove(id);
      });

  CrispCloudPlugin? getPlugin(String id) =>
      _plugins.where((plugin) => plugin.id == id).firstOrNull;
  List<CrispCloudPlugin> getAllPlugins() => List.unmodifiable(_plugins);

  /// Only successfully initialized, enabled plugins may contribute hooks.
  List<CrispCloudPlugin> getEnabledPlugins() =>
      _plugins.where((plugin) => isReady(plugin.id)).toList(growable: false);

  Future<void> setEnabled(String id, bool enabled) =>
      _lifecycle.synchronized(() async {
        final plugin = getPlugin(id);
        if (plugin == null) return;
        if (!await _loadSettings(plugin) && enabled) {
          throw StateError(
            _errors[id] ?? 'Extension settings could not be read.',
          );
        }
        final prefs = await _preferences();
        if (!await prefs.setBool(_prefsEnabledKey(id), enabled)) {
          throw StateError('Extension enabled state could not be saved.');
        }
        _settings[id] = _settings[id]!.copyWith(enabled: enabled);
        if (!enabled) {
          await _stop(plugin);
          return;
        }
        if (!isReady(id)) {
          _status[id] = PluginRuntimeStatus.registered;
          _errors.remove(id);
        }
        if (!await _start(plugin)) {
          throw StateError(_errors[id] ?? 'Extension initialization failed.');
        }
      });

  Future<void> initializeAll() => _lifecycle.synchronized(() async {
    for (final plugin in List.of(_plugins)) {
      await _start(plugin);
    }
  });

  Future<void> retryPlugin(String id) => _lifecycle.synchronized(() async {
    final plugin = getPlugin(id);
    if (plugin == null) return;
    await _stop(plugin);
    _loaded.remove(id);
    _errors.remove(id);
    _status[id] = PluginRuntimeStatus.registered;
    if (!await _start(plugin) && _settings[id]?.enabled == true) {
      throw StateError(_errors[id] ?? 'Extension initialization failed.');
    }
  });

  Future<void> disposeAll() => _lifecycle.synchronized(() async {
    for (final plugin in List.of(_plugins)) {
      await _stop(plugin);
    }
    _plugins.clear();
    _settings.clear();
    _status.clear();
    _errors.clear();
    _loaded.clear();
  });

  Future<void> notifyFileAction(
    FileAction action,
    List<String> filePaths,
  ) async {
    await initializeAll();
    await _lifecycle.synchronized(() async {
      for (final plugin in getEnabledPlugins()) {
        if (!plugin.capabilities.contains(PluginCapability.fileAction)) {
          continue;
        }
        try {
          await plugin.onFileAction(action, List.unmodifiable(filePaths));
        } catch (error) {
          _errors[plugin.id] = 'File action failed: $error';
        }
      }
    });
  }

  List<PluginMenuItem> getContextMenuItems(List<String> paths) {
    final items = <PluginMenuItem>[];
    for (final plugin in getEnabledPlugins()) {
      if (!plugin.capabilities.contains(PluginCapability.contextMenu)) continue;
      try {
        items.addAll(plugin.getContextMenuItems(List.unmodifiable(paths)));
      } catch (error) {
        _errors[plugin.id] = 'Context menu failed: $error';
      }
    }
    return items;
  }

  List<PluginToolbarButton> getToolbarButtons() {
    final items = <PluginToolbarButton>[];
    for (final plugin in getEnabledPlugins()) {
      if (!plugin.capabilities.contains(PluginCapability.toolbar)) continue;
      try {
        items.addAll(plugin.getToolbarButtons());
      } catch (error) {
        _errors[plugin.id] = 'Toolbar contribution failed: $error';
      }
    }
    return items;
  }

  PluginSettings? getPluginSettings(String id) {
    final value = _settings[id];
    return value?.copyWith(settings: _copySettings(value.settings));
  }

  Future<void> savePluginSettings(
    String id,
    Map<String, dynamic> values,
  ) => _lifecycle.synchronized(() async {
    final plugin = getPlugin(id);
    if (plugin == null) return;
    // This explicit settings replacement can repair malformed saved JSON;
    // the enabled flag was still read before decoding the old settings.
    await _loadSettings(plugin);
    await _writeSettings(id, values);
    _loaded.add(id);
    final enabled = _settings[id]!.enabled;
    await _stop(plugin);
    _status[id] = PluginRuntimeStatus.registered;
    _errors.remove(id);
    if (enabled && !await _start(plugin)) {
      throw StateError(
        'Settings saved, but the extension could not restart: ${_errors[id]}',
      );
    }
    if (!enabled) _status[id] = PluginRuntimeStatus.disabled;
  });
}
