// macOS Finder locations backed by the CrispCloud File Provider extension.
//
// Each location is an NSFileProviderDomain shown under "Locations" in the
// Finder sidebar. The extension runs in its own sandboxed process and cannot
// run Dart provider code, so the app serves each location through the existing
// FuseFilesystem IPC protocol on a Unix socket inside the shared App Group
// container. The location therefore works while CrispCloud is running and
// connected to that account; otherwise Finder shows it as unavailable.
//
// Unlike macFUSE/FUSE-T this needs no third-party runtime, kernel extension or
// installer, and stays inside the App Sandbox, so it is allowed in the Mac App
// Store build.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart';
import 'fuse_filesystem.dart';
import 'log_service.dart';

/// A Finder location configured by the user.
@immutable
class FinderLocation {
  const FinderLocation({
    required this.id,
    required this.label,
    required this.provider,
    required this.remotePath,
    this.userId,
    this.bucketId,
  });

  /// Domain identifier and socket name: 8 lowercase hex characters.
  final String id;
  final String label;

  /// [CloudStorageClient.providerName] of the account.
  final String provider;
  final String? userId;
  final String? bucketId;
  final String remotePath;

  static final _idPattern = RegExp(r'^[0-9a-f]{8}$');

  bool matches(CloudStorageClient client) =>
      client.providerName == provider &&
      client.userId == userId &&
      client.bucketId == bucketId;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'provider': provider,
    'userId': userId,
    'bucketId': bucketId,
    'remotePath': remotePath,
  };

  static FinderLocation? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final label = value['label'];
    final provider = value['provider'];
    final remotePath = value['remotePath'];
    if (id is! String ||
        !_idPattern.hasMatch(id) ||
        label is! String ||
        provider is! String ||
        remotePath is! String ||
        !remotePath.startsWith('/')) {
      return null;
    }
    return FinderLocation(
      id: id,
      label: label,
      provider: provider,
      remotePath: remotePath,
      userId: value['userId'] as String?,
      bucketId: value['bucketId'] as String?,
    );
  }
}

/// Starts the IPC server for one location. Replaceable in tests.
typedef FinderLocationServerFactory = FuseFilesystem Function({
  required CloudStorageClient client,
  required String remotePath,
  required String socketPath,
});

FuseFilesystem _defaultServer({
  required CloudStorageClient client,
  required String remotePath,
  required String socketPath,
}) => FuseFilesystem(
  client: client,
  remotePath: remotePath,
  readOnly: false,
  socketPath: socketPath,
);

class FinderLocationService {
  FinderLocationService({
    MethodChannel? channel,
    FinderLocationServerFactory? serverFactory,
    Random? random,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _serverFactory = serverFactory ?? _defaultServer,
       _random = random ?? Random.secure();

  static const channelName = 'com.crispcloud/file_provider';
  static const _prefsKey = 'finder_locations_v1';
  static const _log = Log('FinderLocations');

  static bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.macOS &&
      Platform.isMacOS;

  final MethodChannel _channel;
  final FinderLocationServerFactory _serverFactory;
  final Random _random;

  final _locations = <FinderLocation>[];
  final _servers =
      <String, ({FuseFilesystem server, CloudStorageClient client})>{};

  /// How often Finder is asked to re-check served folders for remote changes.
  static const refreshInterval = Duration(minutes: 1);
  Timer? _refresh;

  List<FinderLocation> get locations => List.unmodifiable(_locations);

  bool isServing(String id) => _servers.containsKey(id);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _locations.clear();
    if (raw == null) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        _locations.addAll(decoded.map(FinderLocation.fromJson).nonNulls);
      }
    } catch (e) {
      _log.warn('Ignoring unreadable Finder locations: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      json.encode(_locations.map((l) => l.toJson()).toList()),
    );
  }

  Future<String> _socketPath(String id) async {
    final container = await _channel.invokeMethod<String>('groupContainer');
    if (container == null || container.isEmpty) {
      throw StateError(
        'The shared app container is unavailable; Finder locations need a '
        'signed build with the CrispCloud app group.',
      );
    }
    return p.join(container, 'fp', id);
  }

  /// Adds [client]'s [remotePath] as a Finder location and starts serving it.
  Future<FinderLocation> add(
    CloudStorageClient client, {
    required String label,
    String remotePath = '/',
  }) async {
    if (!client.isAuthenticated) {
      throw StateError('Connect to the account before adding it to Finder.');
    }
    String id;
    do {
      id = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    } while (_locations.any((l) => l.id == id));
    final location = FinderLocation(
      id: id,
      label: label.trim().isEmpty ? client.providerName : label.trim(),
      provider: client.providerName,
      userId: client.userId,
      bucketId: client.bucketId,
      remotePath: remotePath.isEmpty ? '/' : remotePath,
    );
    await _start(location, client);
    try {
      await _channel.invokeMethod<void>('addDomain', {
        'id': location.id,
        'displayName': location.label,
      });
    } catch (_) {
      await _stop(location.id);
      rethrow;
    }
    _locations.add(location);
    await _save();
    return location;
  }

  Future<void> remove(String id) async {
    await _stop(id);
    try {
      await _channel.invokeMethod<void>('removeDomain', {'id': id});
    } finally {
      _locations.removeWhere((l) => l.id == id);
      await _save();
    }
  }

  /// Serves every location belonging to [client]; stops locations whose
  /// account is no longer connected. Call whenever the connection changes.
  Future<void> attach(CloudStorageClient? client) async {
    for (final entry in _servers.entries.toList()) {
      if (!entry.value.client.isAuthenticated ||
          (client != null &&
              entry.value.client != client &&
              _locations
                  .firstWhere((l) => l.id == entry.key, orElse: () => _orphan)
                  .matches(client))) {
        await _stop(entry.key);
      }
    }
    if (client == null || !client.isAuthenticated) return;
    for (final location in _locations) {
      if (!location.matches(client) || _servers.containsKey(location.id)) {
        continue;
      }
      try {
        await _start(location, client);
        await _channel.invokeMethod<void>('signal', {'id': location.id});
      } catch (e) {
        _log.warn('Finder location ${location.id} could not start: $e');
      }
    }
  }

  static const _orphan = FinderLocation(
    id: '00000000',
    label: '',
    provider: '',
    remotePath: '/',
  );

  Future<void> _start(
    FinderLocation location,
    CloudStorageClient client,
  ) async {
    final server = _serverFactory(
      client: client,
      remotePath: location.remotePath,
      socketPath: await _socketPath(location.id),
    );
    unawaited(server.serveRequests());
    try {
      await server.ready.timeout(const Duration(seconds: 5));
    } catch (_) {
      await server.dispose();
      rethrow;
    }
    _servers[location.id] = (server: server, client: client);
    _refresh ??= Timer.periodic(refreshInterval, (_) => _signalAll());
  }

  void _signalAll() {
    for (final id in _servers.keys) {
      unawaited(
        _channel
            .invokeMethod<void>('signal', {'id': id})
            .catchError((Object e) => _log.debug('Finder refresh failed: $e')),
      );
    }
  }

  Future<void> _stop(String id) async {
    final entry = _servers.remove(id);
    if (_servers.isEmpty) {
      _refresh?.cancel();
      _refresh = null;
    }
    await entry?.server.dispose();
  }

  Future<void> dispose() async {
    for (final id in _servers.keys.toList()) {
      await _stop(id);
    }
  }
}
