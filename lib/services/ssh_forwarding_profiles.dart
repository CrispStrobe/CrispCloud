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
  final _runtimes = <_ForwardingProfileRuntime>{};
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
    final runtimes = _relatedStores
        .expand((store) => store._runtimes)
        .where((runtime) => runtime.route == profile.route)
        .toSet();
    // Invalidate all shared operations before awaiting any cleanup. Runtime
    // records outlive disposed views until their verified manager closes, so a
    // late start cannot escape an edit/delete by losing its original pane.
    for (final runtime in runtimes) {
      runtime.invalidate(profile.id);
    }
    for (final runtime in runtimes) {
      await runtime.stopProfile(profile);
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
    for (final runtime in _runtimes.toList()) {
      runtime.detachStore(this);
    }
    super.dispose();
  }
}

/// One view of a verified transport's saved forwarding. Runtime starts,
/// cancellation and automatic-start progress belong to the shared manager;
/// profile display and explicit start authority still belong to this view.
class SshForwardingProfileSession extends ChangeNotifier {
  SshForwardingProfileSession({
    required this.store,
    required this.route,
    required this.forwarding,
    this._isCurrent,
  }) {
    _runtime = _runtimes[forwarding] ??= _ForwardingProfileRuntime(
      route,
      forwarding,
    );
    if (_runtime.route != route) {
      throw ArgumentError('A forwarding manager belongs to one exact route.');
    }
    _runtime.attach(this);
    store.addListener(_storeChanged);
    forwarding.addListener(_forwardChanged);
  }

  static final _runtimes = Expando<_ForwardingProfileRuntime>();
  final SshForwardingProfiles store;
  final SshForwardingRoute route;
  final SshPortForwarding forwarding;
  final bool Function()? _isCurrent;
  late final _ForwardingProfileRuntime _runtime;
  List<SshForwardingProfile> _profiles = const [];
  int _refreshGeneration = 0;
  bool _disposed = false;
  String? _error;

  List<SshForwardingProfile> get profiles => _profiles;
  String? get error => _error ?? _runtime.automaticError;
  bool get isCurrent =>
      !_disposed && !forwarding.isClosed && (_isCurrent?.call() ?? true);
  bool isStarting(String id) => _runtime.pending.containsKey(id);
  String? profileError(String id) => _runtime.errors[id];

  SshPortForwardSnapshot? listenerFor(SshForwardingProfile profile) =>
      _runtime.listenerFor(profile);

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
        _runtime.errors.removeWhere(
          (id, _) => !_profiles.any((profile) => profile.id == id),
        );
        _error = null;
        _runtime.automaticError = null;
        _runtime._changed();
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

  /// Joins the route's one automatic-start snapshot. Another current view can
  /// finish it if this view closes. A stopped/attempted recipe is never retried
  /// automatically on this connection, and later saved recipes wait for a new
  /// verified connection.
  Future<void> startAutomatic() => _runtime.startAutomatic(this);

  Future<SshPortForwardSnapshot?> start(String id) => isCurrent
      ? _runtime.start(this, id).future
      : Future<SshPortForwardSnapshot?>.value();

  Future<void> stop(String listenerId) => _runtime.stop(listenerId);

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
    if (_disposed) return;
    _disposed = true;
    _runtime.detach(this);
    store.removeListener(_storeChanged);
    forwarding.removeListener(_forwardChanged);
    super.dispose();
  }
}

class _ProfileStart {
  _ProfileStart(this.id, this.generation, {required this.automatic})
    : manual = !automatic;

  final String id;
  final int generation;
  bool automatic;
  bool manual;
  final owners = <SshForwardingProfileSession>{};
  final result = Completer<SshPortForwardSnapshot?>();
  Future<SshPortForwardSnapshot?> get future => result.future;
  Future<SshPortForwardSnapshot?>? running;
  SshForwardingProfile? profile;
  bool abandoned = false;
}

/// One exact verified manager owns this state, independently of a pane's
/// lifetime. Stores retain it while the manager lives so edits/deletes can
/// await unpublished or late startup cleanup after every view has detached.
class _ForwardingProfileRuntime {
  _ForwardingProfileRuntime(this.route, this.forwarding) {
    forwarding.addListener(_managerChanged);
  }

  final SshForwardingRoute route;
  final SshPortForwarding forwarding;
  final sessions = <SshForwardingProfileSession>{};
  final stores = <SshForwardingProfiles>{};
  final automaticOwners = <SshForwardingProfileSession>{};
  final pending = <String, _ProfileStart>{};
  final errors = <String, String>{};
  final generations = <String, int>{};
  final attemptedAutomatic = <String>{};
  final suppressedAutomatic = <String>{};
  List<SshForwardingProfile> automaticProfiles = const [];
  Future<List<SshForwardingProfile>?>? _initialProfiles;
  Future<void>? _automatic;
  String? automaticError;
  bool _released = false;
  bool _snapshotResolved = false;
  final _stoppedBeforeSnapshot = <SshPortForwardSpec>[];
  bool _suppressInitialAutomatic = false;

  void attach(SshForwardingProfileSession session) {
    sessions.add(session);
    stores.add(session.store);
    session.store._runtimes.add(this);
  }

  void detach(SshForwardingProfileSession session) {
    sessions.remove(session);
    automaticOwners.remove(session);
    for (final work in pending.values) {
      work.owners.remove(session);
    }
    _releaseIfClosed();
  }

  void detachStore(SshForwardingProfiles store) {
    stores.remove(store);
    store._runtimes.remove(this);
  }

  void _changed() {
    for (final session in sessions.toList()) {
      session._changed();
    }
  }

  void _managerChanged() => _releaseIfClosed();

  void _releaseIfClosed() {
    if (_released || !forwarding.isClosed || pending.isNotEmpty) return;
    _released = true;
    forwarding.removeListener(_managerChanged);
    for (final store in stores.toList()) {
      detachStore(store);
    }
  }

  SshPortForwardSnapshot? listenerFor(SshForwardingProfile profile) {
    for (final listener in forwarding.forwards) {
      if (sshForwardingSpecsEqual(listener.spec, profile.spec)) return listener;
    }
    return null;
  }

  SshForwardingProfileSession? get _automaticOwner {
    for (final owner in automaticOwners) {
      if (owner.isCurrent) return owner;
    }
    return null;
  }

  Future<void> startAutomatic(SshForwardingProfileSession owner) {
    if (!owner.isCurrent) return Future<void>.value();
    final joined = automaticOwners.add(owner);
    if (_initialProfiles == null) {
      // Preserve this initial read's own snapshot if a display refresh wins.
      _initialProfiles = owner._refresh();
    } else if (joined) {
      unawaited(owner.refresh());
    }
    final running = _automatic;
    if (running != null) return running;
    final completion = Completer<void>();
    _automatic = completion.future;
    unawaited(
      _runAutomatic().then<void>(
        (_) {
          _automatic = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _automatic = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _runAutomatic() async {
    final firstRead = !_snapshotResolved;
    final initial = await _initialProfiles!;
    _snapshotResolved = true;
    if (initial == null) {
      _stoppedBeforeSnapshot.clear();
      if (firstRead) {
        automaticError = 'Saved forwarding could not be loaded. Existing data was preserved.';
        _changed();
      }
      return;
    }
    automaticProfiles = initial;
    for (final profile in initial) {
      if (_suppressInitialAutomatic ||
          _stoppedBeforeSnapshot.any(
            (spec) => sshForwardingSpecsEqual(spec, profile.spec),
          )) {
        suppressedAutomatic.add(profile.id);
      }
    }
    _stoppedBeforeSnapshot.clear();
    for (final profile in initial.where((profile) => profile.autoStart)) {
      final id = profile.id;
      while (!attemptedAutomatic.contains(id) &&
          !suppressedAutomatic.contains(id)) {
        final owner = _automaticOwner;
        if (owner == null || forwarding.isClosed) return;
        final work = start(owner, id, automatic: true);
        try {
          await work.future;
        } catch (_) {
          // Errors are shared by all views; other eligible recipes still run.
        }
        // Cancellation with no surviving authorized view is resumable by a
        // later sibling. Stop/edit/delete increments the shared generation and
        // suppression, so those actions never become an automatic retry.
        if (work.abandoned) {
          if (_automaticOwner == null || forwarding.isClosed) return;
          continue;
        }
        attemptedAutomatic.add(id);
      }
    }
  }

  _ProfileStart start(
    SshForwardingProfileSession owner,
    String id, {
    bool automatic = false,
  }) {
    final existing = pending[id];
    if (existing != null) {
      existing.owners.add(owner);
      existing.automatic |= automatic;
      existing.manual |= !automatic;
      return existing;
    }
    final work = _ProfileStart(id, generations[id] ?? 0, automatic: automatic)
      ..owners.add(owner);
    pending[id] = work;
    unawaited(
      work.future.then<void>(
        (_) => _finished(work),
        onError: (Object _, StackTrace __) => _finished(work),
      ),
    );
    unawaited(
      _readAndStart(
        owner.store,
        work,
      ).then<void>(work.result.complete, onError: work.result.completeError),
    );
    _changed();
    return work;
  }

  void _finished(_ProfileStart work) {
    if (identical(pending[work.id], work)) {
      pending.remove(work.id);
      generations.remove(work.id);
    }
    _changed();
    _releaseIfClosed();
  }

  bool _valid(_ProfileStart work) {
    if (forwarding.isClosed || work.generation != (generations[work.id] ?? 0)) {
      return false;
    }
    if (work.owners.any((owner) => owner.isCurrent) ||
        _automaticOwner != null) {
      return true;
    }
    work.abandoned = true;
    return false;
  }

  Future<SshPortForwardSnapshot?> _readAndStart(
    SshForwardingProfiles store,
    _ProfileStart work,
  ) async {
    final id = work.id;
    try {
      final latest = await store.load();
      if (!_valid(work)) return null;
      final matches = latest.where(
        (profile) => profile.id == id && profile.route == route,
      );
      if (matches.isEmpty) {
        if (work.automatic) return null;
        throw const SshForwardingProfileException(
          'This profile changed elsewhere. Reopen it and try again.',
        );
      }
      final profile = work.profile = matches.single;
      if (work.automatic &&
          !work.manual &&
          (!profile.autoStart || suppressedAutomatic.contains(id))) {
        return null;
      }
      errors.remove(id);
      final existing = listenerFor(profile);
      if (existing != null) {
        if (existing.status == SshPortForwardStatus.active ||
            existing.status == SshPortForwardStatus.starting) {
          return existing;
        }
        if (existing.status == SshPortForwardStatus.stopping) return null;
        await forwarding.stop(existing.id);
        if (!_valid(work)) return null;
      }
      // Publish the no-storage cleanup future before opening the listener.
      // A synchronous manager notification may already request Stop/delete.
      final running = Completer<SshPortForwardSnapshot?>();
      work.running = running.future;
      unawaited(
        _open(
          profile,
          work,
        ).then<void>(running.complete, onError: running.completeError),
      );
      return await running.future;
    } catch (error) {
      if (_valid(work)) {
        errors[id] = sshForwardingProfileErrorMessage(error);
        _changed();
      }
      rethrow;
    }
  }

  Future<SshPortForwardSnapshot?> _open(
    SshForwardingProfile profile,
    _ProfileStart work,
  ) async {
    if (!_valid(work)) return null;
    final listener = await forwarding.start(profile.spec);
    if (!_valid(work)) {
      if (!forwarding.isClosed) await forwarding.stop(listener.id);
      return null;
    }
    return listener;
  }

  void invalidate(String id) {
    if (pending.containsKey(id)) {
      generations[id] = (generations[id] ?? 0) + 1;
    }
    // This also suppresses IDs whose initial automatic read has not finished.
    if (_initialProfiles != null &&
        (!_snapshotResolved ||
            automaticProfiles.any((profile) => profile.id == id))) {
      suppressedAutomatic.add(id);
    }
  }

  Future<void> stopProfile(SshForwardingProfile profile) async {
    final running = pending[profile.id]?.running;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // Retry against manager state; failed cleanup must block persistence.
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
    final listener = forwarding.forwards
        .where((listener) => listener.id == listenerId)
        .firstOrNull;
    if (listener == null) return;
    if (_initialProfiles != null &&
        !_snapshotResolved &&
        !_stoppedBeforeSnapshot.any(
          (spec) => sshForwardingSpecsEqual(spec, listener.spec),
        )) {
      // A newly mounted sibling may not have loaded profile IDs yet. Remember
      // explicit stops by spec until the one startup snapshot arrives. If an
      // unavailable store outlasts excessive stop/recreate operations, revoke
      // that automatic attempt instead of retaining unbounded metadata.
      if (_stoppedBeforeSnapshot.length <
          SshForwardingProfiles.maximumProfiles) {
        _stoppedBeforeSnapshot.add(listener.spec);
      } else {
        _suppressInitialAutomatic = true;
      }
    }
    final matching = <String, SshForwardingProfile>{
      for (final profile in [
        ...automaticProfiles,
        for (final session in sessions) ...session.profiles,
        for (final work in pending.values)
          if (work.profile != null) work.profile!,
      ])
        if (sshForwardingSpecsEqual(listener.spec, profile.spec))
          profile.id: profile,
    };
    for (final id in matching.keys) {
      invalidate(id);
    }
    for (final profile in matching.values) {
      await stopProfile(profile);
    }
    // Unmanaged listeners and already-finished profile operations still stop.
    if (forwarding.forwards.any((entry) => entry.id == listenerId)) {
      await forwarding.stop(listenerId);
    }
  }
}

String sshForwardingProfileErrorMessage(Object error) => switch (error) {
  SshForwardingProfileException() => error.message,
  SshPortForwardException() => error.message,
  FormatException() => 'Check the forwarding profile settings.',
  _ => 'Could not update forwarding profiles.',
};
