// test/toolbar_customization_test.dart
//
// Tests for ToolbarCustomizationService, ToolbarItem enum and ToolbarConfig.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/toolbar_customization_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ToolbarCustomizationService _fresh() => ToolbarCustomizationService();

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // Default configuration
  // =========================================================================

  group('Default configuration', () {
    test('getDefaults contains every ToolbarItem value', () {
      final defaults = _fresh().getDefaults();
      expect(defaults.order, containsAll(ToolbarItem.values));
      expect(defaults.visibleItems, containsAll(ToolbarItem.values));
    });

    test('default visibleItems length equals number of ToolbarItem values', () {
      final defaults = _fresh().getDefaults();
      expect(defaults.visibleItems.length, ToolbarItem.values.length);
    });

    test('default order length equals number of ToolbarItem values', () {
      final defaults = _fresh().getDefaults();
      expect(defaults.order.length, ToolbarItem.values.length);
    });

    test('getConfig returns defaults before any load', () {
      final svc = _fresh();
      final config = svc.getConfig();
      expect(config.visibleItems, containsAll(ToolbarItem.values));
    });

    test('isVisible returns true for all items by default', () {
      final svc = _fresh();
      for (final item in ToolbarItem.values) {
        expect(svc.isVisible(item), isTrue, reason: '${item.name} should be visible');
      }
    });

    test('load with no persisted data yields defaults', () async {
      final svc = _fresh();
      await svc.load();
      expect(svc.getConfig(), equals(svc.getDefaults()));
    });
  });

  // =========================================================================
  // Visibility
  // =========================================================================

  group('Visibility', () {
    test('hiding an item removes it from visibleItems', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setVisibility(ToolbarItem.preview, false);
      expect(svc.getConfig().visibleItems, isNot(contains(ToolbarItem.preview)));
    });

    test('hidden item reports isVisible false', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setVisibility(ToolbarItem.settings, false);
      expect(svc.isVisible(ToolbarItem.settings), isFalse);
    });

    test('showing a hidden item adds it back to visibleItems', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setVisibility(ToolbarItem.preview, false);
      await svc.setVisibility(ToolbarItem.preview, true);
      expect(svc.getConfig().visibleItems, contains(ToolbarItem.preview));
    });

    test('showing already-visible item is idempotent', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setVisibility(ToolbarItem.refresh, true);
      await svc.setVisibility(ToolbarItem.refresh, true);
      final count = svc.getConfig().visibleItems
          .where((e) => e == ToolbarItem.refresh)
          .length;
      expect(count, 1);
    });

    test('hiding then showing restores original count', () async {
      final svc = _fresh();
      await svc.load();
      final before = svc.getConfig().visibleItems.length;
      await svc.setVisibility(ToolbarItem.filter, false);
      await svc.setVisibility(ToolbarItem.filter, true);
      expect(svc.getConfig().visibleItems.length, before);
    });

    test('all items can be hidden (empty visible list is allowed)', () async {
      final svc = _fresh();
      await svc.load();
      for (final item in ToolbarItem.values) {
        await svc.setVisibility(item, false);
      }
      expect(svc.getConfig().visibleItems, isEmpty);
    });

    test('visibility change persists across service instances', () async {
      final svc1 = _fresh();
      await svc1.load();
      await svc1.setVisibility(ToolbarItem.mount, false);

      final svc2 = _fresh();
      await svc2.load();
      expect(svc2.getConfig().visibleItems, isNot(contains(ToolbarItem.mount)));
    });
  });

  // =========================================================================
  // Order
  // =========================================================================

  group('Order', () {
    test('setOrder reorders visibleItems to match new order', () async {
      final svc = _fresh();
      await svc.load();
      // Put settings first.
      final reversed = ToolbarItem.values.reversed.toList();
      await svc.setOrder(reversed);
      expect(svc.getConfig().order.first, ToolbarItem.values.last);
    });

    test('setOrder with duplicates keeps only first occurrence', () async {
      final svc = _fresh();
      await svc.load();
      final withDups = [
        ToolbarItem.browse,
        ToolbarItem.browse,
        ToolbarItem.up,
        ToolbarItem.browse,
        ...ToolbarItem.values,
      ];
      await svc.setOrder(withDups);
      final count = svc.getConfig().order
          .where((e) => e == ToolbarItem.browse)
          .length;
      expect(count, 1);
    });

    test('setOrder persists across service instances', () async {
      final reversed = ToolbarItem.values.reversed.toList();
      final svc1 = _fresh();
      await svc1.load();
      await svc1.setOrder(reversed);

      final svc2 = _fresh();
      await svc2.load();
      expect(svc2.getConfig().order.first, reversed.first);
    });

    test('setOrder with partial list appends missing items at end', () async {
      final svc = _fresh();
      await svc.load();
      // Only pass two items; the rest should still appear in the order.
      await svc.setOrder([ToolbarItem.settings, ToolbarItem.browse]);
      final order = svc.getConfig().order;
      expect(order, containsAll(ToolbarItem.values));
    });

    test('visibleItems respects new order after setOrder', () async {
      final svc = _fresh();
      await svc.load();
      // Hide one item first so we can check ordering of visible items.
      await svc.setVisibility(ToolbarItem.settings, false);
      final newOrder = [
        ToolbarItem.refresh,
        ToolbarItem.up,
        ToolbarItem.browse,
        ...ToolbarItem.values.where((e) =>
            e != ToolbarItem.refresh &&
            e != ToolbarItem.up &&
            e != ToolbarItem.browse),
      ];
      await svc.setOrder(newOrder);
      final visible = svc.getConfig().visibleItems;
      expect(visible.first, ToolbarItem.refresh);
      expect(visible, isNot(contains(ToolbarItem.settings)));
    });
  });

  // =========================================================================
  // Reset
  // =========================================================================

  group('Reset', () {
    test('resetToDefaults restores all items visible', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setVisibility(ToolbarItem.preview, false);
      await svc.setVisibility(ToolbarItem.settings, false);
      await svc.resetToDefaults();
      expect(svc.getConfig().visibleItems, containsAll(ToolbarItem.values));
    });

    test('resetToDefaults restores original order', () async {
      final svc = _fresh();
      await svc.load();
      await svc.setOrder(ToolbarItem.values.reversed.toList());
      await svc.resetToDefaults();
      expect(svc.getConfig().order, equals(svc.getDefaults().order));
    });

    test('resetToDefaults persists across service instances', () async {
      final svc1 = _fresh();
      await svc1.load();
      await svc1.setVisibility(ToolbarItem.mount, false);
      await svc1.resetToDefaults();

      final svc2 = _fresh();
      await svc2.load();
      expect(svc2.getConfig().visibleItems, containsAll(ToolbarItem.values));
    });
  });

  // =========================================================================
  // Serialization
  // =========================================================================

  group('ToolbarConfig serialization', () {
    test('toJson / fromJson round-trips visibleItems', () {
      final svc = _fresh();
      final original = svc.getDefaults();
      final restored = ToolbarConfig.fromJson(original.toJson());
      expect(restored.visibleItems, equals(original.visibleItems));
    });

    test('toJson / fromJson round-trips order', () {
      final svc = _fresh();
      final original = svc.getDefaults();
      final restored = ToolbarConfig.fromJson(original.toJson());
      expect(restored.order, equals(original.order));
    });

    test('full round-trip through JSON string', () {
      final svc = _fresh();
      final original = svc.getDefaults();
      final jsonStr = jsonEncode(original.toJson());
      final restored = ToolbarConfig.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
      expect(restored, equals(original));
    });

    test('fromJson with empty visibleItems list is valid', () {
      final json = {
        'visibleItems': <String>[],
        'order': ToolbarItem.values.map((e) => e.name).toList(),
      };
      final config = ToolbarConfig.fromJson(json);
      expect(config.visibleItems, isEmpty);
    });

    test('ToolbarItem.fromJson round-trips all values', () {
      for (final item in ToolbarItem.values) {
        expect(ToolbarItemX.fromJson(item.toJson()), item);
      }
    });

    test('ToolbarItem.fromJson throws on unknown value', () {
      expect(
        () => ToolbarItemX.fromJson('__nonexistent__'),
        throwsArgumentError,
      );
    });
  });

  // =========================================================================
  // ToolbarItem enum completeness
  // =========================================================================

  group('ToolbarItem enum', () {
    test('all expected items are present', () {
      const expected = [
        ToolbarItem.browse,
        ToolbarItem.up,
        ToolbarItem.refresh,
        ToolbarItem.newFolder,
        ToolbarItem.filter,
        ToolbarItem.search,
        ToolbarItem.findPattern,
        ToolbarItem.viewMode,
        ToolbarItem.preview,
        ToolbarItem.treeView,
        ToolbarItem.mount,
        ToolbarItem.syncManager,
        ToolbarItem.commandPalette,
        ToolbarItem.settings,
      ];
      expect(ToolbarItem.values, containsAll(expected));
    });

    test('all items have non-empty displayName', () {
      for (final item in ToolbarItem.values) {
        expect(item.displayName, isNotEmpty,
            reason: '${item.name} must have a non-empty displayName');
      }
    });
  });
}
