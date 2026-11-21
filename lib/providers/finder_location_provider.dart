// Riverpod state for macOS Finder locations (File Provider domains).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/finder_location_service.dart';
import 'auth_provider.dart';

class FinderLocationNotifier extends ChangeNotifier {
  FinderLocationNotifier(this._ref, {FinderLocationService? service})
    : _service = service ?? FinderLocationService() {
    if (!isSupported) return;
    unawaited(_init());
  }

  final Ref _ref;
  final FinderLocationService _service;
  bool _loaded = false;

  bool get isSupported => FinderLocationService.isSupported;
  bool get isLoaded => _loaded;
  List<FinderLocation> get locations => _service.locations;
  bool isServing(String id) => _service.isServing(id);

  Future<void> _init() async {
    await _service.load();
    _loaded = true;
    notifyListeners();
    await refreshConnection();
  }

  /// Re-evaluates which locations can be served by the current connection.
  Future<void> refreshConnection() async {
    if (!_loaded) return;
    final auth = _ref.read(authProvider);
    await _service.attach(auth.isConnected ? auth.client : null);
    notifyListeners();
  }

  Future<FinderLocation> addCurrent({
    required String label,
    String remotePath = '/',
  }) async {
    final auth = _ref.read(authProvider);
    if (!auth.isConnected) {
      throw StateError('Connect to a cloud account first.');
    }
    final location = await _service.add(
      auth.client,
      label: label,
      remotePath: remotePath,
    );
    notifyListeners();
    return location;
  }

  Future<void> remove(String id) async {
    await _service.remove(id);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_service.dispose());
    super.dispose();
  }
}

final finderLocationProvider = ChangeNotifierProvider<FinderLocationNotifier>((
  ref,
) {
  final notifier = FinderLocationNotifier(ref);
  ref.listen(authProvider, (_, _) => unawaited(notifier.refreshConnection()));
  return notifier;
});
