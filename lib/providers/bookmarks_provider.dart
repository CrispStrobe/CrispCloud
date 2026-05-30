// lib/providers/bookmarks_provider.dart
//
// Persistent bookmarks (favorite folders/paths).
// Stored in SharedPreferences as JSON.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';

class Bookmark {
  final String name;
  final String path;
  final PanelSide side;

  const Bookmark({required this.name, required this.path, required this.side});

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'side': side.name};

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    name: json['name'] as String,
    path: json['path'] as String,
    side: PanelSide.values.firstWhere((s) => s.name == json['side'], orElse: () => PanelSide.local),
  );
}

class BookmarksNotifier extends ChangeNotifier {
  static const _storageKey = 'bookmarks';
  final List<Bookmark> _bookmarks = [];

  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  BookmarksNotifier() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = json.decode(raw) as List;
        _bookmarks.clear();
        _bookmarks.addAll(list.map((e) => Bookmark.fromJson(e as Map<String, dynamic>)));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Bookmarks load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_bookmarks.map((b) => b.toJson()).toList()));
    } catch (e) {
      debugPrint('Bookmarks save failed: $e');
    }
  }

  void add(String name, String path, PanelSide side) {
    if (_bookmarks.any((b) => b.path == path && b.side == side)) return;
    _bookmarks.add(Bookmark(name: name, path: path, side: side));
    notifyListeners();
    _save();
  }

  void remove(String path, PanelSide side) {
    _bookmarks.removeWhere((b) => b.path == path && b.side == side);
    notifyListeners();
    _save();
  }

  bool isBookmarked(String path, PanelSide side) =>
      _bookmarks.any((b) => b.path == path && b.side == side);
}

final bookmarksProvider = ChangeNotifierProvider<BookmarksNotifier>((ref) => BookmarksNotifier());
