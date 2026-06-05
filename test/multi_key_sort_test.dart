// test/multi_key_sort_test.dart
//
// Tests for multi-key sorting (Phase 1.2).

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';

void main() {
  group('_compareSortKey', () {
    test('name sort is case-insensitive', () {
      final a = FileItem(name: 'alpha.txt', isFolder: false);
      final b = FileItem(name: 'Beta.txt', isFolder: false);
      final result = PanelNotifier.compareSortKey(a, b, SortBy.name);
      expect(result, lessThan(0)); // 'alpha' < 'beta'
    });

    test('size sort treats null as 0', () {
      final a = FileItem(name: 'a.txt', isFolder: false, size: null);
      final b = FileItem(name: 'b.txt', isFolder: false, size: 100);
      final result = PanelNotifier.compareSortKey(a, b, SortBy.size);
      expect(result, lessThan(0)); // 0 < 100
    });

    test('date sort treats null as epoch', () {
      final a = FileItem(name: 'a.txt', isFolder: false, updatedAt: null);
      final b = FileItem(name: 'b.txt', isFolder: false, updatedAt: DateTime(2024));
      final result = PanelNotifier.compareSortKey(a, b, SortBy.date);
      expect(result, lessThan(0)); // 1970 < 2024
    });

    test('extension sort extracts file extension', () {
      final a = FileItem(name: 'file.dart', isFolder: false);
      final b = FileItem(name: 'file.txt', isFolder: false);
      final result = PanelNotifier.compareSortKey(a, b, SortBy.extension);
      expect(result, lessThan(0)); // 'dart' < 'txt'
    });

    test('extension sort returns 0 for folders', () {
      final a = FileItem(name: 'folder_a', isFolder: true);
      final b = FileItem(name: 'folder_b', isFolder: true);
      final result = PanelNotifier.compareSortKey(a, b, SortBy.extension);
      expect(result, 0);
    });
  });
}
