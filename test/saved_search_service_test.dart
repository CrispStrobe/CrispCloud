// test/saved_search_service_test.dart
//
// Unit tests for SavedSearch model and SavedSearchService.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/saved_search_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // SavedSearch model
  // ---------------------------------------------------------------------------
  group('SavedSearch model', () {
    test('toJson includes required fields', () {
      final search = SavedSearch(
        name: 'My Search',
        query: '*.dart',
        createdAt: DateTime(2026, 5, 1),
      );
      final json = search.toJson();
      expect(json['name'], 'My Search');
      expect(json['query'], '*.dart');
      expect(json['createdAt'], '2026-05-01T00:00:00.000');
      expect(json['filterByType'], isEmpty);
    });

    test('toJson includes all filter fields', () {
      final search = SavedSearch(
        name: 'Filtered',
        query: 'report',
        filterByType: ['.pdf', '.docx'],
        filterByMinSize: 1024,
        filterByMaxSize: 10485760,
        filterByDateAfter: DateTime(2026, 1, 1),
        filterByDateBefore: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 5, 1),
      );
      final json = search.toJson();
      expect(json['filterByType'], ['.pdf', '.docx']);
      expect(json['filterByMinSize'], 1024);
      expect(json['filterByMaxSize'], 10485760);
      expect(json['filterByDateAfter'], '2026-01-01T00:00:00.000');
      expect(json['filterByDateBefore'], '2026-12-31T00:00:00.000');
    });

    test('toJson omits null optional fields', () {
      final search = SavedSearch(
        name: 'Simple',
        query: 'hello',
        createdAt: DateTime(2026, 1, 1),
      );
      final json = search.toJson();
      expect(json.containsKey('filterByMinSize'), false);
      expect(json.containsKey('filterByMaxSize'), false);
      expect(json.containsKey('filterByDateAfter'), false);
      expect(json.containsKey('filterByDateBefore'), false);
    });

    test('fromJson round-trip preserves all fields', () {
      final original = SavedSearch(
        name: 'Full Search',
        query: 'budget',
        filterByType: ['.xlsx', '.csv'],
        filterByMinSize: 500,
        filterByMaxSize: 5000000,
        filterByDateAfter: DateTime(2025, 6, 1),
        filterByDateBefore: DateTime(2026, 6, 1),
        createdAt: DateTime(2026, 3, 15),
      );
      final json = original.toJson();
      final restored = SavedSearch.fromJson(json);

      expect(restored.name, 'Full Search');
      expect(restored.query, 'budget');
      expect(restored.filterByType, ['.xlsx', '.csv']);
      expect(restored.filterByMinSize, 500);
      expect(restored.filterByMaxSize, 5000000);
      expect(restored.filterByDateAfter, DateTime(2025, 6, 1));
      expect(restored.filterByDateBefore, DateTime(2026, 6, 1));
      expect(restored.createdAt, DateTime(2026, 3, 15));
    });

    test('fromJson handles missing filterByType', () {
      final search = SavedSearch.fromJson({
        'name': 'Test',
        'query': 'q',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(search.filterByType, isEmpty);
    });

    test('filterSummary with no filters', () {
      final search = SavedSearch(
        name: 'x',
        query: 'q',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(search.filterSummary, 'No filters');
    });

    test('filterSummary with type filter', () {
      final search = SavedSearch(
        name: 'x',
        query: 'q',
        filterByType: ['.pdf', '.doc'],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(search.filterSummary, contains('type:'));
      expect(search.filterSummary, contains('.pdf'));
    });

    test('filterSummary truncates more than 3 types', () {
      final search = SavedSearch(
        name: 'x',
        query: 'q',
        filterByType: ['.a', '.b', '.c', '.d', '.e'],
        createdAt: DateTime(2026, 1, 1),
      );
      final summary = search.filterSummary;
      expect(summary, contains('.a'));
      expect(summary, contains('.b'));
      expect(summary, contains('.c'));
      // Should have ellipsis for truncated types
      expect(summary, contains('\u2026')); // Unicode ellipsis
    });

    test('filterSummary with size filters', () {
      final search = SavedSearch(
        name: 'x',
        query: 'q',
        filterByMinSize: 1024,
        filterByMaxSize: 1048576,
        createdAt: DateTime(2026, 1, 1),
      );
      final summary = search.filterSummary;
      expect(summary, contains('min:'));
      expect(summary, contains('max:'));
      expect(summary, contains('KB'));
      expect(summary, contains('MB'));
    });

    test('filterSummary with date filters', () {
      final search = SavedSearch(
        name: 'x',
        query: 'q',
        filterByDateAfter: DateTime(2026, 1, 1),
        filterByDateBefore: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );
      final summary = search.filterSummary;
      expect(summary, contains('after:'));
      expect(summary, contains('before:'));
      expect(summary, contains('2026'));
    });

    test('_fmtSize formats bytes correctly', () {
      // Test via filterSummary
      final searchBytes = SavedSearch(
        name: 'x', query: 'q', filterByMinSize: 500, createdAt: DateTime(2026, 1, 1),
      );
      expect(searchBytes.filterSummary, contains('500 B'));

      final searchKB = SavedSearch(
        name: 'x', query: 'q', filterByMinSize: 2048, createdAt: DateTime(2026, 1, 1),
      );
      expect(searchKB.filterSummary, contains('KB'));

      final searchGB = SavedSearch(
        name: 'x', query: 'q', filterByMinSize: 2 * 1024 * 1024 * 1024, createdAt: DateTime(2026, 1, 1),
      );
      expect(searchGB.filterSummary, contains('GB'));
    });
  });

  // ---------------------------------------------------------------------------
  // SavedSearchService (SharedPreferences-based)
  // ---------------------------------------------------------------------------
  group('SavedSearchService', () {
    late SavedSearchService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = SavedSearchService();
    });

    test('getAll returns empty list when no saved searches', () async {
      final result = await service.getAll();
      expect(result, isEmpty);
    });

    test('save and getAll round-trip', () async {
      final search = SavedSearch(
        name: 'Test Search',
        query: 'hello',
        createdAt: DateTime(2026, 1, 1),
      );
      await service.save(search);

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'Test Search');
      expect(all.first.query, 'hello');
    });

    test('save multiple searches', () async {
      await service.save(SavedSearch(name: 'A', query: 'q1', createdAt: DateTime(2026, 1, 1)));
      await service.save(SavedSearch(name: 'B', query: 'q2', createdAt: DateTime(2026, 1, 2)));
      await service.save(SavedSearch(name: 'C', query: 'q3', createdAt: DateTime(2026, 1, 3)));

      final all = await service.getAll();
      expect(all.length, 3);
      final names = all.map((s) => s.name).toSet();
      expect(names, containsAll(['A', 'B', 'C']));
    });

    test('save with same name replaces existing', () async {
      await service.save(SavedSearch(name: 'Dup', query: 'original', createdAt: DateTime(2026, 1, 1)));
      await service.save(SavedSearch(name: 'Dup', query: 'updated', createdAt: DateTime(2026, 1, 2)));

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.query, 'updated');
    });

    test('delete removes the named search', () async {
      await service.save(SavedSearch(name: 'Keep', query: 'q1', createdAt: DateTime(2026, 1, 1)));
      await service.save(SavedSearch(name: 'Remove', query: 'q2', createdAt: DateTime(2026, 1, 2)));

      await service.delete('Remove');

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'Keep');
    });

    test('delete non-existent name is a no-op', () async {
      await service.save(SavedSearch(name: 'X', query: 'q', createdAt: DateTime(2026, 1, 1)));
      await service.delete('NonExistent');

      final all = await service.getAll();
      expect(all.length, 1);
    });

    test('persists across service instances', () async {
      await service.save(SavedSearch(name: 'Persistent', query: 'pq', createdAt: DateTime(2026, 1, 1)));

      // Create a new service instance (same SharedPreferences)
      final service2 = SavedSearchService();
      final all = await service2.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'Persistent');
    });

    test('save preserves filters', () async {
      await service.save(SavedSearch(
        name: 'Filtered',
        query: 'report',
        filterByType: ['.pdf'],
        filterByMinSize: 1024,
        filterByMaxSize: 10000,
        filterByDateAfter: DateTime(2025, 1, 1),
        filterByDateBefore: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 5, 1),
      ));

      final all = await service.getAll();
      final s = all.first;
      expect(s.filterByType, ['.pdf']);
      expect(s.filterByMinSize, 1024);
      expect(s.filterByMaxSize, 10000);
      expect(s.filterByDateAfter, DateTime(2025, 1, 1));
      expect(s.filterByDateBefore, DateTime(2026, 12, 31));
    });

    test('getAll handles corrupted data gracefully', () async {
      // Write garbage to the prefs key
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_searches', 'not valid json');

      final all = await service.getAll();
      expect(all, isEmpty);
    });
  });
}
