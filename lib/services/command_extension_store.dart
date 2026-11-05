import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/command_extension.dart';
import '../models/custom_toolbar_command.dart';
import '../utils/async_lock.dart';

class CommandExtensionStore extends ChangeNotifier {
  CommandExtensionStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance {
    ready = _load();
  }
  static const preferencesKey = 'commander_command_extensions_v1';
  static const maxBytes = 4 * 1024 * 1024;
  final Future<SharedPreferences> Function() _preferences;
  final _lock = AsyncLock();
  final _owner = Object();
  final Map<String, InstalledCommandExtension> _installed = {};
  final Map<String, int> _generations = {};
  late final Future<void> ready;
  bool _loaded = false, _disposed = false;
  String? loadError;
  List<InstalledCommandExtension> get installed =>
      List.unmodifiable(_installed.values);
  InstalledCommandExtension? get(String id) => _installed[id];
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      final text = (await _preferences()).getString(preferencesKey);
      if (text != null) {
        if (utf8.encode(text).length > maxBytes) {
          throw const FormatException('Saved command extensions exceed 4 MiB.');
        }
        final value = Map<String, dynamic>.from(jsonDecode(text) as Map);
        if (value['version'] != 1) {
          throw const FormatException('Unsupported saved extension version.');
        }
        final entries = (value['extensions'] as List)
            .map(
              (entry) => InstalledCommandExtension.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ),
            )
            .toList();
        if (entries.length > 128 ||
            entries.map((entry) => entry.manifest.id).toSet().length !=
                entries.length) {
          throw const FormatException(
            'Duplicate extensions or extension limit exceeded.',
          );
        }
        for (final entry in entries) {
          _installed[entry.manifest.id] = entry;
          _generations[entry.manifest.id] = 1;
        }
      }
      _loaded = true;
    } catch (error) {
      loadError = 'Command extensions could not be loaded: $error';
    }
    _changed();
  }

  Future<void> _change(
    String id,
    void Function(Map<String, InstalledCommandExtension>) change,
  ) async {
    await ready;
    await _lock.synchronized(() async {
      if (_disposed) {
        throw StateError('The extension manager has been disposed.');
      }
      if (!_loaded || loadError != null) {
        throw StateError(loadError ?? 'Extension settings are unavailable.');
      }
      final next = Map<String, InstalledCommandExtension>.of(_installed);
      change(next);
      if (next.length > 128) {
        throw const FormatException(
          'At most 128 command extensions can be installed.',
        );
      }
      final text = jsonEncode({
        'version': 1,
        'extensions': next.values.map((entry) => entry.toJson()).toList(),
      });
      if (utf8.encode(text).length > maxBytes) {
        throw const FormatException('Saved command extensions exceed 4 MiB.');
      }
      final prefs = await _preferences();
      if (!await prefs.setString(preferencesKey, text)) {
        throw StateError('Extension settings could not be saved.');
      }
      _installed
        ..clear()
        ..addAll(next);
      _generations[id] = (_generations[id] ?? 0) + 1;
      _changed();
    });
  }

  Future<void> install(
    CommandExtensionManifest manifest, {
    bool replace = false,
  }) {
    // Install/update always starts disabled. It never launches a process or
    // calls an extension-supplied initialization script.
    final safe = CommandExtensionManifest.fromJson(manifest.toJson());
    return _change(safe.id, (next) {
      if (next.containsKey(safe.id) && !replace) {
        throw StateError(
          'This extension is installed. Review and explicitly replace it to update.',
        );
      }
      next[safe.id] = InstalledCommandExtension(manifest: safe);
    });
  }

  Future<void> remove(String id) => _change(id, (next) => next.remove(id));
  Future<void> setEnabled(String id, bool enabled) => _change(id, (next) {
    final current = next[id];
    if (current == null) {
      throw StateError('The extension is no longer installed.');
    }
    next[id] = current.copyWith(enabled: enabled);
  });
  Future<void> configure(String id, CustomToolbarCommand command) =>
      _change(id, (next) {
        final current = next[id];
        if (current == null) {
          throw StateError('The extension is no longer installed.');
        }
        next[id] = current.copyWith(
          overrides: {...current.overrides, command.id: command},
        );
      });
  Future<void> resetSettings(String id) => _change(id, (next) {
    final current = next[id];
    if (current == null) {
      throw StateError('The extension is no longer installed.');
    }
    next[id] = current.copyWith(overrides: {});
  });

  List<CommandExtensionAction> actions(CommandExtensionCapability capability) {
    if (!_loaded || _disposed || loadError != null) return const [];
    return [
      for (final entry in _installed.values)
        if (entry.enabled && entry.manifest.capabilities.contains(capability))
          for (final command in entry.commands)
            CommandExtensionAction(
              extensionId: entry.manifest.id,
              extensionName: entry.manifest.name,
              command: command,
              generation: _generations[entry.manifest.id]!,
              owner: _owner,
            ),
    ];
  }

  bool isActionCurrent(CommandExtensionAction action) =>
      !_disposed &&
      _loaded &&
      loadError == null &&
      identical(action.owner, _owner) &&
      _installed[action.extensionId]?.enabled == true &&
      _generations[action.extensionId] == action.generation &&
      _installed[action.extensionId]!.commands.any(
        (command) => identical(command, action.command),
      );
  String exportManifest(String id, {bool includeSettings = true}) {
    final current = _installed[id];
    if (current == null) {
      throw StateError('The extension is no longer installed.');
    }
    return (includeSettings
            ? current.manifest.withCommands(current.commands)
            : current.manifest)
        .exportText();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
