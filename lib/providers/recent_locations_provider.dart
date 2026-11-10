// lib/providers/recent_locations_provider.dart
//
// Tracks recently navigated paths with their original storage identity.
// Persisted in SharedPreferences as JSON.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../models/panel_navigation.dart';
import '../models/storage_reference.dart';
import '../utils/async_lock.dart';

class RecentLocationsNotifier extends ChangeNotifier {
  static const _storageKey = 'recent_locations';
  static const maxRecent = 20;

  final List<RecentEntry> _entries = [];
  final _saveLock = AsyncLock();
  late final Future<void> ready;
  int _clearRevision = 0;
  bool _disposed = false;

  List<RecentEntry> get entries => List.unmodifiable(_entries);

  /// Get recent entries for a specific side.
  List<RecentEntry> forSide(PanelSide side) =>
      _entries.where((e) => e.side == side).toList();

  RecentLocationsNotifier() {
    ready = _load();
  }

  /// Record a navigation to [path] on [side].
  void add(String path, PanelSide side, {StorageReference? storage}) {
    if (_disposed || path.isEmpty || path.contains('\u0000')) return;
    // The same path in two accounts represents two distinct destinations.
    _entries.removeWhere(
      (e) => e.path == path && e.side == side && e.storage == storage,
    );
    _entries.insert(
      0,
      RecentEntry(
        path: path,
        side: side,
        storage: storage,
        visitedAt: DateTime.now(),
      ),
    );
    // Trim to max
    while (_entries.length > maxRecent) {
      _entries.removeLast();
    }
    notifyListeners();
    _save();
  }

  void clear() {
    _clearRevision++;
    _entries.clear();
    notifyListeners();
    _save();
  }

  Future<void> _load() async {
    final clearRevision = _clearRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || clearRevision != _clearRevision) return;
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = json.decode(raw) as List;
        // Navigation can happen during preference loading. Keep those fresh
        // destinations first instead of overwriting them with saved state.
        for (final item in list) {
          if (_entries.length >= maxRecent) break;
          try {
            final entry = RecentEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            );
            if (!_entries.any((value) => value.sameLocation(entry))) {
              _entries.add(entry);
            }
          } on Object {
            // A damaged entry does not hide the other saved destinations.
          }
        }
        notifyListeners();
      }
    } catch (e) {
      // Silently ignored
    }
  }

  Future<void> _save() async {
    await ready;
    await _saveLock.synchronized(() async {
      if (_disposed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_disposed) return;
        await prefs.setString(
          _storageKey,
          json.encode(_entries.map((e) => e.toJson()).toList()),
        );
      } catch (e) {
        // Silently ignored
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class RecentEntry {
  final String path;
  final PanelSide side;
  final DateTime visitedAt;
  final StorageReference? storage;

  const RecentEntry({
    required this.path,
    required this.side,
    required this.visitedAt,
    this.storage,
  });

  bool sameLocation(RecentEntry other) =>
      path == other.path && side == other.side && storage == other.storage;

  String get label {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'side': side.name,
    'visitedAt': visitedAt.toIso8601String(),
    if (storage != null) 'storage': storage!.toJson(),
  };

  factory RecentEntry.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty || path.contains('\u0000')) {
      throw const FormatException('Invalid recent location.');
    }
    final location = json['storage'] is Map
        ? PanelNavigationEntry.fromJson(json)
        : null;
    return RecentEntry(
      path: location?.path ?? path,
      side: PanelSide.values.firstWhere(
        (s) => s.name == json['side'],
        orElse: () => PanelSide.local,
      ),
      visitedAt: DateTime.tryParse(json['visitedAt'] ?? '') ?? DateTime.now(),
      storage: location?.storage,
    );
  }
}

final recentLocationsProvider = ChangeNotifierProvider<RecentLocationsNotifier>(
  (ref) => RecentLocationsNotifier(),
);
