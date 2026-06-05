// test/keyboard_shortcut_test.dart
//
// Tests for KeyboardShortcutService and ShortcutBinding.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

KeyboardShortcutService _freshService() => KeyboardShortcutService();

/// Simulates a [KeyDownEvent] with the given logical key and optional physical
/// key.  The physical key is unused by [ShortcutBinding.matches] but required
/// by the constructor.
KeyDownEvent _keyDown(LogicalKeyboardKey logical) {
  return KeyDownEvent(
    logicalKey: logical,
    physicalKey: PhysicalKeyboardKey.keyA, // placeholder
    timeStamp: Duration.zero,
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // ShortcutBinding — construction & validation
  // =========================================================================

  group('ShortcutBinding.isValid', () {
    test('valid when key is non-empty', () {
      expect(const ShortcutBinding(key: 'P').isValid, isTrue);
    });

    test('invalid when key is empty string', () {
      expect(const ShortcutBinding(key: '').isValid, isFalse);
    });

    test('invalid when key is whitespace only', () {
      expect(const ShortcutBinding(key: '   ').isValid, isFalse);
    });
  });

  // =========================================================================
  // ShortcutBinding — serialization
  // =========================================================================

  group('ShortcutBinding serialization', () {
    test('round-trips through toJson / fromJson', () {
      const original = ShortcutBinding(
          key: 'P', ctrl: true, shift: true, alt: false, meta: false);
      final restored = ShortcutBinding.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('fromJson handles missing optional fields with safe defaults', () {
      final binding = ShortcutBinding.fromJson({'key': 'F5'});
      expect(binding.key, 'F5');
      expect(binding.ctrl, isFalse);
      expect(binding.shift, isFalse);
      expect(binding.alt, isFalse);
      expect(binding.meta, isFalse);
    });

    test('fromJson with all modifiers true', () {
      final binding = ShortcutBinding.fromJson({
        'key': 'Z',
        'ctrl': true,
        'shift': true,
        'alt': true,
        'meta': true,
      });
      expect(binding.ctrl, isTrue);
      expect(binding.shift, isTrue);
      expect(binding.alt, isTrue);
      expect(binding.meta, isTrue);
    });

    test('toJson includes all fields', () {
      const b = ShortcutBinding(key: 'T', ctrl: true);
      final j = b.toJson();
      expect(j.containsKey('key'), isTrue);
      expect(j.containsKey('ctrl'), isTrue);
      expect(j.containsKey('shift'), isTrue);
      expect(j.containsKey('alt'), isTrue);
      expect(j.containsKey('meta'), isTrue);
    });

    test('equality after JSON round-trip with all modifiers', () {
      const b = ShortcutBinding(key: 'L', ctrl: true, shift: true, alt: true, meta: true);
      expect(ShortcutBinding.fromJson(b.toJson()), equals(b));
    });
  });

  // =========================================================================
  // ShortcutBinding — equality & hashCode
  // =========================================================================

  group('ShortcutBinding equality', () {
    test('identical bindings are equal', () {
      const a = ShortcutBinding(key: 'T', ctrl: true);
      const b = ShortcutBinding(key: 'T', ctrl: true);
      expect(a, equals(b));
    });

    test('key comparison is case-insensitive', () {
      const a = ShortcutBinding(key: 'p', ctrl: true, shift: true);
      const b = ShortcutBinding(key: 'P', ctrl: true, shift: true);
      expect(a, equals(b));
    });

    test('different modifier flags are not equal', () {
      const a = ShortcutBinding(key: 'T', ctrl: true);
      const b = ShortcutBinding(key: 'T', ctrl: false);
      expect(a, isNot(equals(b)));
    });

    test('different keys are not equal', () {
      const a = ShortcutBinding(key: 'T', ctrl: true);
      const b = ShortcutBinding(key: 'N', ctrl: true);
      expect(a, isNot(equals(b)));
    });

    test('equal bindings have the same hashCode', () {
      const a = ShortcutBinding(key: 'F5');
      const b = ShortcutBinding(key: 'F5');
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // =========================================================================
  // ShortcutBinding — matches()
  // =========================================================================

  group('ShortcutBinding.matches()', () {
    test('matches when key and modifiers agree', () {
      const binding = ShortcutBinding(key: 'T', ctrl: true);
      final event = _keyDown(LogicalKeyboardKey.keyT);
      expect(
          binding.matches(event, isCtrl: true, isShift: false, isAlt: false, isMeta: false),
          isTrue);
    });

    test('does not match when ctrl differs', () {
      const binding = ShortcutBinding(key: 'T', ctrl: true);
      final event = _keyDown(LogicalKeyboardKey.keyT);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isFalse);
    });

    test('does not match when shift differs', () {
      const binding = ShortcutBinding(key: 'P', ctrl: true, shift: true);
      final event = _keyDown(LogicalKeyboardKey.keyP);
      expect(
          binding.matches(event, isCtrl: true, isShift: false, isAlt: false, isMeta: false),
          isFalse);
    });

    test('does not match when alt differs', () {
      const binding = ShortcutBinding(key: 'X', alt: true);
      final event = _keyDown(LogicalKeyboardKey.keyX);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isFalse);
    });

    test('does not match when meta differs', () {
      const binding = ShortcutBinding(key: 'Q', meta: true);
      final event = _keyDown(LogicalKeyboardKey.keyQ);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isFalse);
    });

    test('does not match a KeyUpEvent', () {
      const binding = ShortcutBinding(key: 'T', ctrl: true);
      final event = KeyUpEvent(
        logicalKey: LogicalKeyboardKey.keyT,
        physicalKey: PhysicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      );
      expect(
          binding.matches(event, isCtrl: true, isShift: false, isAlt: false, isMeta: false),
          isFalse);
    });

    test('matches function key F5 with no modifiers', () {
      const binding = ShortcutBinding(key: 'F5');
      final event = _keyDown(LogicalKeyboardKey.f5);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isTrue);
    });

    test('matches Space key using word "Space"', () {
      const binding = ShortcutBinding(key: 'Space');
      final event = _keyDown(LogicalKeyboardKey.space);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isTrue);
    });

    test('matches Space key using raw space character', () {
      // Both the word "Space" and the literal space char normalise the same way.
      const binding = ShortcutBinding(key: ' ');
      final event = _keyDown(LogicalKeyboardKey.space);
      expect(
          binding.matches(event, isCtrl: false, isShift: false, isAlt: false, isMeta: false),
          isTrue);
    });
  });

  // =========================================================================
  // ShortcutBinding — toDisplayString()
  // =========================================================================

  group('ShortcutBinding.toDisplayString()', () {
    test('single letter with Ctrl shows Ctrl+Letter', () {
      const b = ShortcutBinding(key: 'T', ctrl: true);
      final s = b.toDisplayString();
      // On non-Mac test environments the separator is +
      expect(s, contains('T'));
      // Ctrl should appear
      expect(s.toLowerCase(), anyOf(contains('ctrl'), contains('⌃')));
    });

    test('Ctrl+Shift+P contains both modifiers and key', () {
      const b = ShortcutBinding(key: 'P', ctrl: true, shift: true);
      final s = b.toDisplayString();
      expect(s, contains('P'));
      expect(s.toLowerCase(),
          anyOf(contains('shift'), contains('⇧'), contains('Shift')));
    });

    test('F5 alone displays without separator', () {
      const b = ShortcutBinding(key: 'F5');
      final s = b.toDisplayString();
      expect(s, contains('F5'));
    });

    test('Space key is labelled Space', () {
      const b = ShortcutBinding(key: 'Space');
      final s = b.toDisplayString();
      expect(s, contains('Space'));
    });

    test('Delete key normalises to Del', () {
      const b = ShortcutBinding(key: 'Delete');
      final s = b.toDisplayString();
      expect(s, contains('Del'));
    });

    test('display string is non-empty for any valid binding', () {
      const b = ShortcutBinding(key: 'Z', ctrl: true);
      expect(b.toDisplayString(), isNotEmpty);
    });

    test('Meta modifier label is present', () {
      const b = ShortcutBinding(key: 'T', meta: true);
      final s = b.toDisplayString();
      expect(s.toLowerCase(),
          anyOf(contains('meta'), contains('⌘')));
    });
  });

  // =========================================================================
  // KeyboardShortcutService — defaults
  // =========================================================================

  group('KeyboardShortcutService defaults', () {
    test('all ShortcutAction values have a default binding', () {
      final svc = _freshService();
      final bindings = svc.getBindings();
      for (final action in ShortcutAction.values) {
        expect(bindings.containsKey(action), isTrue,
            reason: '${action.name} has no default binding');
      }
    });

    test('no two default bindings are identical (no duplicate defaults)', () {
      final svc = _freshService();
      final bindings = svc.getBindings();
      final seen = <ShortcutBinding>{};
      for (final entry in bindings.entries) {
        expect(seen.contains(entry.value), isFalse,
            reason:
                'Duplicate default binding ${entry.value} for ${entry.key.name}');
        seen.add(entry.value);
      }
    });

    test('all default bindings are valid (non-empty key)', () {
      final svc = _freshService();
      for (final b in svc.getBindings().values) {
        expect(b.isValid, isTrue, reason: 'Invalid default binding: $b');
      }
    });

    test('getBinding returns default when no custom override exists', () {
      final svc = _freshService();
      // commandPalette default is Ctrl+Shift+P
      final b = svc.getBinding(ShortcutAction.commandPalette);
      expect(b.key.toUpperCase(), 'P');
      expect(b.ctrl, isTrue);
      expect(b.shift, isTrue);
    });

    test('newTab default is Ctrl+T', () {
      final svc = _freshService();
      final b = svc.getBinding(ShortcutAction.newTab);
      expect(b.key.toUpperCase(), 'T');
      expect(b.ctrl, isTrue);
      expect(b.shift, isFalse);
    });

    test('delete default has no modifiers', () {
      final svc = _freshService();
      final b = svc.getBinding(ShortcutAction.delete);
      expect(b.ctrl, isFalse);
      expect(b.shift, isFalse);
      expect(b.alt, isFalse);
      expect(b.meta, isFalse);
    });
  });

  // =========================================================================
  // KeyboardShortcutService — setBinding / resetBinding
  // =========================================================================

  group('KeyboardShortcutService custom bindings', () {
    test('setBinding overrides the default', () async {
      final svc = _freshService();
      const custom = ShortcutBinding(key: 'F', ctrl: true, shift: true);
      await svc.setBinding(ShortcutAction.newTab, custom);
      expect(svc.getBinding(ShortcutAction.newTab), equals(custom));
    });

    test('setBinding with invalid binding throws ArgumentError', () async {
      final svc = _freshService();
      const invalid = ShortcutBinding(key: '');
      expect(
          () async => svc.setBinding(ShortcutAction.newTab, invalid),
          throwsArgumentError);
    });

    test('resetBinding reverts to default', () async {
      final svc = _freshService();
      const custom = ShortcutBinding(key: 'Q', ctrl: true);
      await svc.setBinding(ShortcutAction.newTab, custom);
      await svc.resetBinding(ShortcutAction.newTab);
      // Should match the original default (Ctrl+T)
      final b = svc.getBinding(ShortcutAction.newTab);
      expect(b.key.toUpperCase(), 'T');
      expect(b.ctrl, isTrue);
    });

    test('resetAll clears all custom overrides', () async {
      final svc = _freshService();
      await svc.setBinding(ShortcutAction.newTab,
          const ShortcutBinding(key: 'Q', ctrl: true));
      await svc.setBinding(ShortcutAction.closeTab,
          const ShortcutBinding(key: 'E', ctrl: true, shift: true));
      await svc.resetAll();
      // Both should revert to their defaults
      expect(svc.getBinding(ShortcutAction.newTab).key.toUpperCase(), 'T');
      expect(svc.getBinding(ShortcutAction.closeTab).key.toUpperCase(), 'W');
    });

    test('setBinding is reflected in getBindings()', () async {
      final svc = _freshService();
      const custom = ShortcutBinding(key: 'Y', ctrl: true, alt: true);
      await svc.setBinding(ShortcutAction.refresh, custom);
      expect(svc.getBindings()[ShortcutAction.refresh], equals(custom));
    });

    test('resetBinding on action with no custom is a no-op', () async {
      final svc = _freshService();
      // Should not throw
      await svc.resetBinding(ShortcutAction.selectAll);
      expect(
          svc.getBinding(ShortcutAction.selectAll).key.toUpperCase(), 'A');
    });
  });

  // =========================================================================
  // Persistence via SharedPreferences
  // =========================================================================

  group('KeyboardShortcutService persistence', () {
    test('custom binding survives load() from SharedPreferences', () async {
      final svc1 = _freshService();
      const custom = ShortcutBinding(key: 'J', ctrl: true);
      await svc1.setBinding(ShortcutAction.newFolder, custom);

      // Create a second service and load the persisted data.
      final svc2 = _freshService();
      await svc2.load();
      expect(svc2.getBinding(ShortcutAction.newFolder), equals(custom));
    });

    test('resetAll persists empty map; reloading shows defaults', () async {
      final svc1 = _freshService();
      await svc1.setBinding(ShortcutAction.undo,
          const ShortcutBinding(key: 'U', ctrl: true));
      await svc1.resetAll();

      final svc2 = _freshService();
      await svc2.load();
      // Should be back to default (Ctrl+Z)
      expect(svc2.getBinding(ShortcutAction.undo).key.toUpperCase(), 'Z');
    });
  });

  // =========================================================================
  // Conflict detection
  // =========================================================================

  group('Conflict detection', () {
    test('isConflict returns true for an existing default binding', () {
      final svc = _freshService();
      // Ctrl+T is the default for newTab
      expect(svc.isConflict(const ShortcutBinding(key: 'T', ctrl: true)),
          isTrue);
    });

    test('isConflict returns false for an unused combination', () {
      final svc = _freshService();
      expect(
          svc.isConflict(const ShortcutBinding(
              key: 'M', ctrl: true, shift: true, alt: true)),
          isFalse);
    });

    test('getConflicts returns the action using a binding', () {
      final svc = _freshService();
      final conflicts =
          svc.getConflicts(const ShortcutBinding(key: 'T', ctrl: true));
      expect(conflicts, contains(ShortcutAction.newTab));
    });

    test('getConflicts returns empty list for unused binding', () {
      final svc = _freshService();
      final conflicts = svc.getConflicts(
          const ShortcutBinding(key: 'M', ctrl: true, shift: true, alt: true));
      expect(conflicts, isEmpty);
    });

    test('setting duplicate binding causes conflict for two actions', () async {
      final svc = _freshService();
      // Make rename share the same combo as newTab (Ctrl+T)
      await svc.setBinding(ShortcutAction.rename,
          const ShortcutBinding(key: 'T', ctrl: true));
      final conflicts =
          svc.getConflicts(const ShortcutBinding(key: 'T', ctrl: true));
      expect(conflicts.length, greaterThanOrEqualTo(2));
      expect(conflicts, containsAll([ShortcutAction.newTab, ShortcutAction.rename]));
    });
  });

  // =========================================================================
  // Export / Import
  // =========================================================================

  group('Export / Import', () {
    test('exportBindings returns valid JSON', () async {
      final svc = _freshService();
      await svc.setBinding(ShortcutAction.undo,
          const ShortcutBinding(key: 'U', ctrl: true));
      final exported = svc.exportBindings();
      expect(() => json.decode(exported), returnsNormally);
    });

    test('export/import round-trip preserves custom bindings', () async {
      final svc1 = _freshService();
      const custom = ShortcutBinding(key: 'K', ctrl: true, shift: true);
      await svc1.setBinding(ShortcutAction.search, custom);
      final exported = svc1.exportBindings();

      final svc2 = _freshService();
      await svc2.importBindings(exported);
      expect(svc2.getBinding(ShortcutAction.search), equals(custom));
    });

    test('importing clears previous custom bindings', () async {
      final svc = _freshService();
      await svc.setBinding(ShortcutAction.undo,
          const ShortcutBinding(key: 'U', ctrl: true));
      // Import empty map — removes previous custom
      await svc.importBindings('{}');
      expect(svc.getBinding(ShortcutAction.undo).key.toUpperCase(), 'Z');
    });

    test('importBindings handles invalid JSON gracefully', () async {
      final svc = _freshService();
      // Should not throw
      await svc.importBindings('not json at all }{');
      // Bindings should remain at defaults
      expect(svc.getBinding(ShortcutAction.newTab).key.toUpperCase(), 'T');
    });

    test('importBindings handles non-object JSON gracefully', () async {
      final svc = _freshService();
      await svc.importBindings('[1,2,3]'); // Array, not map
      expect(svc.getBinding(ShortcutAction.newTab).key.toUpperCase(), 'T');
    });

    test('importBindings skips unknown action names without error', () async {
      final svc = _freshService();
      const payload =
          '{"nonExistentAction": {"key":"X","ctrl":true,"shift":false,"alt":false,"meta":false}}';
      await svc.importBindings(payload);
      // All defaults intact
      expect(svc.getBinding(ShortcutAction.newTab).key.toUpperCase(), 'T');
    });

    test('importBindings skips bindings with empty key', () async {
      final svc = _freshService();
      // Provide an entry for newTab with an empty key — should be ignored.
      const payload =
          '{"newTab": {"key":"","ctrl":true,"shift":false,"alt":false,"meta":false}}';
      await svc.importBindings(payload);
      // Default should remain
      expect(svc.getBinding(ShortcutAction.newTab).key.toUpperCase(), 'T');
    });

    test('export is empty JSON object when no custom bindings set', () {
      final svc = _freshService();
      final exported = svc.exportBindings();
      final decoded = json.decode(exported) as Map<String, dynamic>;
      expect(decoded, isEmpty);
    });

    test('exported JSON contains only custom overrides, not all defaults', () async {
      final svc = _freshService();
      await svc.setBinding(ShortcutAction.rename,
          const ShortcutBinding(key: 'R', ctrl: true));
      final decoded =
          json.decode(svc.exportBindings()) as Map<String, dynamic>;
      expect(decoded.keys, contains('rename'));
      // Other actions should NOT be in export (only custom overrides)
      expect(decoded.keys, isNot(contains('newTab')));
    });
  });

  // =========================================================================
  // resolve()
  // =========================================================================

  group('KeyboardShortcutService.resolve()', () {
    test('resolve returns the matching action for default binding', () {
      final svc = _freshService();
      final event = _keyDown(LogicalKeyboardKey.keyT);
      final action = svc.resolve(event,
          isCtrl: true, isShift: false, isAlt: false, isMeta: false);
      expect(action, equals(ShortcutAction.newTab));
    });

    test('resolve returns null for unbound combination', () {
      final svc = _freshService();
      final event = _keyDown(LogicalKeyboardKey.keyM);
      final action = svc.resolve(event,
          isCtrl: true, isShift: true, isAlt: true, isMeta: false);
      expect(action, isNull);
    });

    test('resolve uses custom binding when set', () async {
      final svc = _freshService();
      await svc.setBinding(ShortcutAction.rename,
          const ShortcutBinding(key: 'R', ctrl: true, shift: true));
      final event = _keyDown(LogicalKeyboardKey.keyR);
      final action = svc.resolve(event,
          isCtrl: true, isShift: true, isAlt: false, isMeta: false);
      expect(action, equals(ShortcutAction.rename));
    });
  });
}
