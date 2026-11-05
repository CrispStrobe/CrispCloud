import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace_configuration.dart';
import '../utils/async_lock.dart';

abstract interface class WorkspacePersistence {
  Future<String?> read();
  Future<bool> write(String value);
}

class PreferencesWorkspacePersistence implements WorkspacePersistence {
  static const key = 'commander.workspace.v1';
  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(key);
  }

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// One acknowledged settings document. Failed or corrupt reads never replace
/// an existing catalog with an empty one; mutations are serialized per store.
class WorkspaceStore {
  WorkspaceStore({WorkspacePersistence? persistence})
    : _persistence = persistence ?? PreferencesWorkspacePersistence();
  final WorkspacePersistence _persistence;
  final _lock = AsyncLock();
  static const maxBytes = 2 * 1024 * 1024;

  static WorkspaceCatalog decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException(
        'Workspace files must be no larger than 2 MiB.',
      );
    }
    return WorkspaceCatalog.fromJson(
      Map<String, dynamic>.from(jsonDecode(text) as Map),
    );
  }

  Future<WorkspaceCatalog> _load() async {
    final text = await _persistence.read();
    return text == null ? WorkspaceCatalog() : decode(text);
  }

  Future<WorkspaceCatalog> load() => _lock.synchronized(_load);
  Future<String> exportText() async =>
      const JsonEncoder.withIndent('  ').convert((await load()).toJson());

  Future<void> _update(WorkspaceCatalog Function(WorkspaceCatalog) change) =>
      _lock.synchronized(() async {
        final next = change(await _load());
        final text = jsonEncode(next.toJson());
        if (utf8.encode(text).length > maxBytes) {
          throw const FormatException(
            'The saved workspace catalog exceeds 2 MiB.',
          );
        }
        if (!await _persistence.write(text)) {
          throw StateError('Workspace settings could not be saved.');
        }
      });

  List<T> _upsert<T extends NamedWorkspaceItem>(List<T> values, T value) {
    final result = List<T>.of(values);
    final index = result.indexWhere((entry) => entry.id == value.id);
    if (index < 0) {
      result.add(value);
    } else {
      result[index] = value;
    }
    return result;
  }

  Future<void> saveGroup(SavedWorkspace value) => _update(
    (catalog) => WorkspaceCatalog(
      groups: _upsert(catalog.groups, value),
      pairs: catalog.pairs,
      profiles: catalog.profiles,
    ),
  );
  Future<void> savePair(PairedBookmark value) => _update(
    (catalog) => WorkspaceCatalog(
      groups: catalog.groups,
      pairs: _upsert(catalog.pairs, value),
      profiles: catalog.profiles,
    ),
  );
  Future<void> saveProfile(SavedViewProfile value) => _update(
    (catalog) => WorkspaceCatalog(
      groups: catalog.groups,
      pairs: catalog.pairs,
      profiles: _upsert(catalog.profiles, value),
    ),
  );
  Future<void> removeGroup(String id) => _update(
    (catalog) => WorkspaceCatalog(
      groups: catalog.groups.where((item) => item.id != id).toList(),
      pairs: catalog.pairs,
      profiles: catalog.profiles,
    ),
  );
  Future<void> removePair(String id) => _update(
    (catalog) => WorkspaceCatalog(
      groups: catalog.groups,
      pairs: catalog.pairs.where((item) => item.id != id).toList(),
      profiles: catalog.profiles,
    ),
  );
  Future<void> removeProfile(String id) => _update(
    (catalog) => WorkspaceCatalog(
      groups: catalog.groups,
      pairs: catalog.pairs,
      profiles: catalog.profiles.where((item) => item.id != id).toList(),
    ),
  );

  Future<void> importText(String text, {bool replaceAll = false}) async {
    // Validate the complete import before obtaining the mutation lock.
    final imported = decode(text);
    await _update((catalog) {
      if (replaceAll) return imported;
      var groups = catalog.groups;
      var pairs = catalog.pairs;
      var profiles = catalog.profiles;
      for (final value in imported.groups) {
        groups = _upsert(groups, value);
      }
      for (final value in imported.pairs) {
        pairs = _upsert(pairs, value);
      }
      for (final value in imported.profiles) {
        profiles = _upsert(profiles, value);
      }
      return WorkspaceCatalog(groups: groups, pairs: pairs, profiles: profiles);
    });
  }

  Future<void> reorder(String section, int oldIndex, int newIndex) =>
      _update((catalog) {
        List<T> changed<T>(List<T> original) {
          final values = List<T>.of(original);
          if (oldIndex < 0 ||
              oldIndex >= values.length ||
              newIndex < 0 ||
              newIndex > values.length) {
            throw const FormatException('Invalid workspace item order.');
          }
          if (newIndex > oldIndex) newIndex--;
          values.insert(newIndex, values.removeAt(oldIndex));
          return values;
        }

        return switch (section) {
          'groups' => WorkspaceCatalog(
            groups: changed(catalog.groups),
            pairs: catalog.pairs,
            profiles: catalog.profiles,
          ),
          'pairs' => WorkspaceCatalog(
            groups: catalog.groups,
            pairs: changed(catalog.pairs),
            profiles: catalog.profiles,
          ),
          'profiles' => WorkspaceCatalog(
            groups: catalog.groups,
            pairs: catalog.pairs,
            profiles: changed(catalog.profiles),
          ),
          _ => throw const FormatException('Unknown workspace section.'),
        };
      });
}
