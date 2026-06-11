// lib/providers/recent_locations_provider.dart
//
// Tracks recently navigated paths per panel side.
// Persisted in SharedPreferences as JSON.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../services/log_service.dart';

class RecentLocationsNotifier extends ChangeNotifier {
  static const _storageKey = 'recent_locations';
  static const maxRecent = 20;

  final List<RecentEntry> _entries = [];

  List<RecentEntry> get entries => List.unmodifiable(_entries);

  /// Get recent entries for a specific side.
  List<RecentEntry> forSide(PanelSide side) =>
      _entries.where((e) => e.side == side).toList();

  RecentLocationsNotifier() {
    _load();
  }

  /// Record a navigation to [path] on [side].
  void add(String path, PanelSide side) {
    // Remove existing entry for same path+side (move to top)
    _entries.removeWhere((e) => e.path == path && e.side == side);
    _entries.insert(0, RecentEntry(path: path, side: side, visitedAt: DateTime.now()));
    // Trim to max
    while (_entries.length > maxRecent) {
      _entries.removeLast();
    }
    notifyListeners();
    _save();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
    _save();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = json.decode(raw) as List;
        _entries.clear();
        _entries.addAll(list.map((e) => RecentEntry.fromJson(e as Map<String, dynamic>)));
        notifyListeners();
      }
    } catch (e) {
      // Silently ignored
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_entries.map((e) => e.toJson()).toList()));
    } catch (e) {
      // Silently ignored
    }
  }
}

class RecentEntry {
  final String path;
  final PanelSide side;
  final DateTime visitedAt;

  const RecentEntry({required this.path, required this.side, required this.visitedAt});

  String get label {
    if (path == '/' || path.isEmpty) return '/';
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '/');
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'side': side.name,
    'visitedAt': visitedAt.toIso8601String(),
  };

  factory RecentEntry.fromJson(Map<String, dynamic> json) => RecentEntry(
    path: json['path'] as String,
    side: PanelSide.values.firstWhere((s) => s.name == json['side'], orElse: () => PanelSide.local),
    visitedAt: DateTime.tryParse(json['visitedAt'] ?? '') ?? DateTime.now(),
  );
}

final recentLocationsProvider = ChangeNotifierProvider<RecentLocationsNotifier>(
  (ref) => RecentLocationsNotifier(),
);
