// test/panel_view_mode_test.dart
//
// Tests for PanelViewModeService and PanelViewMode enum.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/panel_view_mode_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PanelViewModeService _fresh() => PanelViewModeService();

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // Default mode
  // =========================================================================

  group('Default mode', () {
    test('default mode is full for left (local) panel', () async {
      expect(await _fresh().getMode(PanelSide.local), PanelViewMode.full);
    });

    test('default mode is full for right (remote) panel', () async {
      expect(await _fresh().getMode(PanelSide.remote), PanelViewMode.full);
    });

    test('get with no persisted data returns full', () async {
      final svc = _fresh();
      for (final side in PanelSide.values) {
        expect(await svc.getMode(side), PanelViewMode.full);
      }
    });
  });

  // =========================================================================
  // Set / persist
  // =========================================================================

  group('setMode', () {
    test('setMode persists mode for local panel', () async {
      final svc1 = _fresh();
      await svc1.setMode(PanelSide.local, PanelViewMode.brief);
      final svc2 = _fresh();
      expect(await svc2.getMode(PanelSide.local), PanelViewMode.brief);
    });

    test('setMode persists mode for remote panel', () async {
      final svc1 = _fresh();
      await svc1.setMode(PanelSide.remote, PanelViewMode.tree);
      final svc2 = _fresh();
      expect(await svc2.getMode(PanelSide.remote), PanelViewMode.tree);
    });

    test('left and right panels are independent', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.brief);
      await svc.setMode(PanelSide.remote, PanelViewMode.tree);
      expect(await svc.getMode(PanelSide.local), PanelViewMode.brief);
      expect(await svc.getMode(PanelSide.remote), PanelViewMode.tree);
    });

    test('changing one panel does not affect the other', () async {
      final svc = _fresh();
      // Start with defaults.
      await svc.setMode(PanelSide.local, PanelViewMode.brief);
      // Remote should still be at default.
      expect(await svc.getMode(PanelSide.remote), PanelViewMode.full);
    });

    test('setMode to same value is idempotent', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.full);
      await svc.setMode(PanelSide.local, PanelViewMode.full);
      expect(await svc.getMode(PanelSide.local), PanelViewMode.full);
    });
  });

  // =========================================================================
  // Cycle mode
  // =========================================================================

  group('cycleMode', () {
    test('brief → full', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.brief);
      final next = await svc.cycleMode(PanelSide.local);
      expect(next, PanelViewMode.full);
    });

    test('full → tree', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.full);
      final next = await svc.cycleMode(PanelSide.local);
      expect(next, PanelViewMode.tree);
    });

    test('tree → brief', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.tree);
      final next = await svc.cycleMode(PanelSide.local);
      expect(next, PanelViewMode.brief);
    });

    test('full cycle brief→full→tree→brief returns to start', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.brief);
      await svc.cycleMode(PanelSide.local); // → full
      await svc.cycleMode(PanelSide.local); // → tree
      await svc.cycleMode(PanelSide.local); // → brief
      expect(await svc.getMode(PanelSide.local), PanelViewMode.brief);
    });

    test('cycleMode persists new mode', () async {
      final svc1 = _fresh();
      await svc1.setMode(PanelSide.remote, PanelViewMode.brief);
      await svc1.cycleMode(PanelSide.remote); // → full

      final svc2 = _fresh();
      expect(await svc2.getMode(PanelSide.remote), PanelViewMode.full);
    });

    test('cycleMode on each panel is independent', () async {
      final svc = _fresh();
      await svc.setMode(PanelSide.local, PanelViewMode.brief);
      await svc.setMode(PanelSide.remote, PanelViewMode.tree);
      await svc.cycleMode(PanelSide.local); // local → full
      expect(await svc.getMode(PanelSide.local), PanelViewMode.full);
      expect(await svc.getMode(PanelSide.remote), PanelViewMode.tree);
    });
  });

  // =========================================================================
  // PanelViewMode enum
  // =========================================================================

  group('PanelViewMode enum', () {
    test('all three modes exist', () {
      expect(PanelViewMode.values, containsAll([
        PanelViewMode.brief,
        PanelViewMode.full,
        PanelViewMode.tree,
      ]));
    });

    test('all modes have non-empty displayName', () {
      for (final mode in PanelViewMode.values) {
        expect(mode.displayName, isNotEmpty,
            reason: '${mode.name} must have a non-empty displayName');
      }
    });

    test('displayName is distinct for each mode', () {
      final names = PanelViewMode.values.map((m) => m.displayName).toSet();
      expect(names.length, PanelViewMode.values.length);
    });

    test('toJson / fromJson round-trips all values', () {
      for (final mode in PanelViewMode.values) {
        expect(PanelViewModeX.fromJson(mode.toJson()), mode);
      }
    });

    test('fromJson throws on unknown value', () {
      expect(
        () => PanelViewModeX.fromJson('__unknown__'),
        throwsArgumentError,
      );
    });

    test('PanelViewMode.brief displayName is Brief', () {
      expect(PanelViewMode.brief.displayName, 'Brief');
    });

    test('PanelViewMode.full displayName is Full', () {
      expect(PanelViewMode.full.displayName, 'Full');
    });

    test('PanelViewMode.tree displayName is Tree', () {
      expect(PanelViewMode.tree.displayName, 'Tree');
    });
  });
}
