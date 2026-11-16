import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_forwarding_profile.dart';
import '../utils/async_lock.dart';
import 'ssh_port_forwarding.dart';

export '../models/ssh_forwarding_profile.dart';

class SshForwardingProfileException implements Exception {
  const SshForwardingProfileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Versioned, bounded local forwarding recipes. Every mutation reloads under a
/// shared lock. Invalid/future data is never replaced by an empty store.
class SshForwardingProfiles extends ChangeNotifier {
  SshForwardingProfiles({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _preferences = read == null,
       _lock = read == null ? _preferencesLock : AsyncLock() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both forwarding profile storage callbacks');
    }
    if (_preferences) _preferenceStores.add(this);
  }

  static const preferencesKey = 'terminal_ssh_forwarding_profiles_v1';
  static const maximumProfiles = 50;
  static const maximumProfilesPerRoute = SshPortForwarding.maximumForwards;
  static const maximumStorageLength = 128 * 1024;
  static final _preferencesLock = AsyncLock();
  static final _preferenceStores = <SshForwardingProfiles>{};
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final bool _preferences;
  final AsyncLock _lock;
  final _sessions = <SshForwardingProfileSession>{};
  bool _disposed = false;

  Iterable<SshForwardingProfiles> get _relatedStores =>
      _preferences ? _preferenceStores.toList() : [this];

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      preferencesKey,
      value,
    )) {
      throw StateError('Forwarding profile storage failed');
    }
  }

  Future<List<SshForwardingProfile>> load() => _lock.synchronized(_load);

  Future<List<SshForwardingProfile>> _load() async {
    try {
      final raw = await _read();
      if (raw == null) return const [];
      if (raw.length > maximumStorageLength) throw const FormatException();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data.keys.any((key) => key != 'version' && key != 'profiles') ||
          data['version'] is! int ||
          data['version'] != 1 ||
          data['profiles'] is! List) {
        throw const FormatException();
      }
      final entries = data['profiles'] as List;
      if (entries.length > maximumProfiles) throw const FormatException();
      final profiles = <SshForwardingProfile>[];
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) throw const FormatException();
        final profile = SshForwardingProfile.fromJson(entry);
        _validateAddition(profiles, profile);
        profiles.add(profile);
      }
      profiles.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return List.unmodifiable(profiles);
    } catch (_) {
      throw const SshForwardingProfileException(
        'Saved forwarding could not be loaded. Existing data was preserved.',
      );
    }
  }

  static void _validateAddition(
    List<SshForwardingProfile> profiles,
    SshForwardingProfile addition,
  ) {
    if (profiles.length >= maximumProfiles) {
      throw const SshForwardingProfileException(
        'The limit of 50 saved forwarding profiles has been reached.',
      );
    }
    if (profiles.any((profile) => profile.id == addition.id)) {
      throw const SshForwardingProfileException(
        'This forwarding profile already exists.',
      );
    }
    final sameRoute = profiles.where(
      (profile) => profile.route == addition.route,
    );
    if (sameRoute.length >= maximumProfilesPerRoute) {
      throw const SshForwardingProfileException(
        'Use at most 16 forwarding profiles for one SSH route.',
      );
    }
    if (sameRoute.any(
      (profile) => profile.name.toLowerCase() == addition.name.toLowerCase(),
    )) {
      throw const SshForwardingProfileException(
        'A profile with this name already exists for this route.',
      );
    }
    if (sameRoute.any(
      (profile) => sshForwardingSpecsEqual(profile.spec, addition.spec),
    )) {
      throw const SshForwardingProfileException(
        'This forwarding configuration is already saved for this route.',
      );
    }
  }

  /// [replacing] is the exact snapshot that was edited. Stale editors cannot
  /// overwrite a newer edit or resurrect a profile deleted in another pane.
  /// Changing a recipe stops its existing listeners before committing it.
  Future<void> save(
    SshForwardingProfile profile, {
    SshForwardingProfile? replacing,
  }) => _lock.synchronized(() async {
    final profiles = (await _load()).toList();
    final index = replacing == null
        ? -1
        : profiles.indexWhere((value) => value.id == replacing.id);
    if (replacing != null &&
        (index < 0 ||
            !profiles[index].hasSameContents(replacing) ||
            profile.id != replacing.id ||
            profile.route != replacing.route)) {
      throw const SshForwardingProfileException(
        'This profile changed elsewhere. Reopen it and try again.',
      );
    }
    final others = [...profiles];
    if (index >= 0) others.removeAt(index);
    _validateAddition(others, profile);
    if (replacing != null &&
        !sshForwardingSpecsEqual(replacing.spec, profile.spec)) {
      await _stopBeforeChange(replacing);
    }
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _persist(profiles);
  });

  /// Deletion stops this recipe in every live session sharing this store.
  /// If any listener cannot be stopped, the saved profile remains available.
  Future<void> delete(SshForwardingProfile profile) =>
      _lock.synchronized(() async {
        final profiles = (await _load()).toList();
        final index = profiles.indexWhere((value) => value.id == profile.id);
        if (index < 0) return;
        if (!profiles[index].hasSameContents(profile)) {
          throw const SshForwardingProfileException(
            'This profile changed elsewhere. Reopen it and try again.',
          );
        }
        await _stopBeforeChange(profile);
        profiles.removeAt(index);
        await _persist(profiles);
      });

  Future<void> _stopBeforeChange(SshForwardingProfile profile) async {
    final sessions = _relatedStores
        .expand((store) => store._sessions)
        .where((session) => session.route == profile.route)
        .toList();
    // Invalidate all starts before waiting for any of them. These operations
    // never read storage, so holding the storage lock cannot deadlock a start
    // that is still waiting for its initial profile read.
    for (final session in sessions) {
      session._invalidate(profile.id);
    }
    for (final session in sessions) {
      await session._stopProfile(profile);
    }
  }

  Future<void> _persist(List<SshForwardingProfile> profiles) async {
    final value = jsonEncode({
      'version': 1,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    });
    if (value.length > maximumStorageLength) {
      throw const SshForwardingProfileException(
        'Saved forwarding exceeds the storage limit.',
      );
    }
    try {
      await _write(value);
    } catch (_) {
      throw const SshForwardingProfileException(
        'Could not save forwarding profiles.',
      );
    }
    for (final store in _relatedStores) {
      if (!store._disposed) store.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _preferenceStores.remove(this);
    super.dispose();
  }
}

/// One verified transport's profile coordinator. Construct only after host-key
/// verification and authentication succeed; a reconnect must use its new
/// manager. Closing a management dialog does not dispose this coordinator.
class SshForwardingProfileSession extends ChangeNotifier {
  SshForwardingProfileSession({
    required this.store,
    required this.route,
    required this.forwarding,
    this._isCurrent,
  }) {
    store._sessions.add(this);
    store.addListener(_storeChanged);
    forwarding.addListener(_forwardChanged);
  }

  static final _automaticManagers = Expando<bool>();
  final SshForwardingProfiles store;
  final SshForwardingRoute route;
  final SshPortForwarding forwarding;
  final bool Function()? _isCurrent;
  List<SshForwardingProfile> _profiles = const [];
  final _errors = <String, String>{};
  final _generations = <String, int>{};
  final _automaticIds = <String>{};
  final _suppressedAutomatic = <String>{};
  final _pending = <String, Future<SshPortForwardSnapshot?>>{};
  final _running = <String, Future<SshPortForwardSnapshot?>>{};
  Future<void>? _automatic;
  int _refreshGeneration = 0;
  bool _disposed = false;
  String? _error;

  List<SshForwardingProfile> get profiles => _profiles;
  String? get error => _error;
  bool get isCurrent =>
      !_disposed && !forwarding.isClosed && (_isCurrent?.call() ?? true);
  bool isStarting(String id) => _pending.containsKey(id);
  String? profileError(String id) => _errors[id];

  SshPortForwardSnapshot? listenerFor(SshForwardingProfile profile) {
    for (final listener in forwarding.forwards) {
      if (sshForwardingSpecsEqual(listener.spec, profile.spec)) return listener;
    }
    return null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _storeChanged() => unawaited(refresh());
  void _forwardChanged() => _changed();

  Future<void> refresh() async {
    await _refresh();
  }

  Future<List<SshForwardingProfile>?> _refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final loaded = await store.load();
      final profiles = List<SshForwardingProfile>.unmodifiable(
        loaded.where((profile) => profile.route == route),
      );
      if (!_disposed && generation == _refreshGeneration) {
        _profiles = profiles;
        _errors.removeWhere(
          (id, _) => !_profiles.any((profile) => profile.id == id),
        );
        _error = null;
        _changed();
      }
      return profiles;
    } catch (_) {
      if (!_disposed && generation == _refreshGeneration) {
        _error = 'Saved forwarding could not be loaded. Existing data was preserved.';
        _changed();
      }
      return null;
    }
  }

  /// Idempotent even when a pane rebuild accidentally creates another
  /// coordinator for the same connection. Saving/enabling a profile never
  /// starts it implicitly on the current connection.
  Future<void> startAutomatic() => _automatic ??= _startAutomatic();

  Future<void> _startAutomatic() async {
    final shouldStart = _automaticManagers[forwarding] != true;
    _automaticManagers[forwarding] = true;
    // Keep this read's snapshot even if a dialog/store refresh supersedes its
    // UI update. Reading the shared cache here can silently consume the one
    // automatic attempt before a competing refresh has populated that cache.
    final initialProfiles = await _refresh();
    if (!shouldStart || !isCurrent || initialProfiles == null) return;
    final ids = initialProfiles
        .where((profile) => profile.autoStart)
        .map((profile) => profile.id)
        .toList();
    _automaticIds.addAll(ids);
    for (final id in ids) {
      if (!isCurrent) return;
      if (_suppressedAutomatic.contains(id)) continue;
      try {
        await _start(id, automatic: true);
      } catch (_) {
        // Each failure is retained beside its profile. Other eligible recipes
        // still get a turn unless the SSH transport itself has ended.
      }
    }
  }

  Future<SshPortForwardSnapshot?> start(String id) => _start(id);

  Future<SshPortForwardSnapshot?> _start(String id, {bool automatic = false}) {
    final existing = _pending[id];
    if (existing != null) return existing;
    final generation = _generations[id] ?? 0;
    final future = _readAndStart(id, generation, automatic: automatic);
    _pending[id] = future;
    _changed();
    unawaited(
      future.then<void>(
        (_) => _finished(id, future),
        onError: (Object _, StackTrace __) => _finished(id, future),
      ),
    );
    return future;
  }

  void _finished(String id, Future<SshPortForwardSnapshot?> future) {
    if (identical(_pending[id], future)) _pending.remove(id);
    if (identical(_running[id], future)) _running.remove(id);
    if (!_pending.containsKey(id) && !_running.containsKey(id)) {
      _generations.remove(id);
    }
    _changed();
  }

  bool _valid(String id, int generation) =>
      isCurrent && generation == (_generations[id] ?? 0);

  Future<SshPortForwardSnapshot?> _readAndStart(
    String id,
    int generation, {
    required bool automatic,
  }) async {
    try {
      final latest = await store.load();
      if (!_valid(id, generation)) return null;
      final matches = latest.where(
        (profile) => profile.id == id && profile.route == route,
      );
      if (matches.isEmpty) {
        if (automatic) return null;
        throw const SshForwardingProfileException(
          'This profile changed elsewhere. Reopen it and try again.',
        );
      }
      final profile = matches.single;
      if (automatic &&
          (!profile.autoStart || _suppressedAutomatic.contains(id))) {
        return null;
      }
      _errors.remove(id);
      final existing = listenerFor(profile);
      if (existing != null) {
        if (existing.status == SshPortForwardStatus.active ||
            existing.status == SshPortForwardStatus.starting) {
          return existing;
        }
        if (existing.status == SshPortForwardStatus.stopping) return null;
        await forwarding.stop(existing.id);
        if (!_valid(id, generation)) return null;
      }
      // Everything after this point is independent of the storage lock.
      // A save/delete can invalidate and await this future without deadlock.
      final running = _open(profile, generation);
      _running[id] = running;
      try {
        return await running;
      } finally {
        if (identical(_running[id], running)) _running.remove(id);
      }
    } catch (error) {
      if (_valid(id, generation)) {
        _errors[id] = sshForwardingProfileErrorMessage(error);
        _changed();
      }
      rethrow;
    }
  }

  Future<SshPortForwardSnapshot?> _open(
    SshForwardingProfile profile,
    int generation,
  ) async {
    if (!_valid(profile.id, generation)) return null;
    final listener = await forwarding.start(profile.spec);
    if (!_valid(profile.id, generation)) {
      if (!forwarding.isClosed) await forwarding.stop(listener.id);
      return null;
    }
    return listener;
  }

  void _invalidate(String id) {
    if (_pending.containsKey(id) || _running.containsKey(id)) {
      _generations[id] = (_generations[id] ?? 0) + 1;
    }
    if (_automaticIds.contains(id)) _suppressedAutomatic.add(id);
  }

  Future<void> _stopProfile(SshForwardingProfile profile) async {
    final running = _running[profile.id];
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // Cleanup is retried against the manager below. Its record remains
        // visible if startup or cancellation could not complete.
      }
    }
    if (forwarding.isClosed) return;
    for (final listener in forwarding.forwards) {
      if (sshForwardingSpecsEqual(listener.spec, profile.spec)) {
        await forwarding.stop(listener.id);
      }
    }
  }

  Future<void> stop(String listenerId) async {
    for (final profile in profiles) {
      if (listenerFor(profile)?.id == listenerId) _invalidate(profile.id);
    }
    await forwarding.stop(listenerId);
  }

  Future<void> save(
    SshForwardingProfile profile, {
    SshForwardingProfile? replacing,
  }) async {
    if (profile.route != route) {
      throw const SshForwardingProfileException(
        'Invalid forwarding profile route.',
      );
    }
    await store.save(profile, replacing: replacing);
    await refresh();
  }

  Future<void> delete(SshForwardingProfile profile) async {
    if (profile.route != route) {
      throw const SshForwardingProfileException(
        'Invalid forwarding profile route.',
      );
    }
    await store.delete(profile);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    store._sessions.remove(this);
    store.removeListener(_storeChanged);
    forwarding.removeListener(_forwardChanged);
    // Existing listeners remain owned by the transport manager. In-flight
    // starts observe isCurrent=false and close any late successful result.
    super.dispose();
  }
}

String sshForwardingProfileErrorMessage(Object error) => switch (error) {
  SshForwardingProfileException() => error.message,
  SshPortForwardException() => error.message,
  FormatException() => 'Check the forwarding profile settings.',
  _ => 'Could not update forwarding profiles.',
};
