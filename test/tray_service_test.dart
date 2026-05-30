// test/tray_service_test.dart
//
// Tests for TrayService. Since system_tray requires native bindings,
// we test static methods, state management, and platform guards.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/tray_service.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

void main() {
  group('TrayService', () {
    // --- isSupported ---
    test('isSupported returns true on desktop platforms', () {
      // This test runs on Linux CI, so it should be true
      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        expect(TrayService.isSupported, true);
      }
    });

    test('isSupported consistent with Platform checks', () {
      final expected = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
      expect(TrayService.isSupported, expected);
    });

    // --- Construction and initial state ---
    test('new TrayService is not initialized (dispose is safe)', () async {
      final tray = TrayService();
      // dispose on uninitialized service should not throw
      await tray.dispose();
    });

    test('showApp on uninitialized service does not throw', () {
      final tray = TrayService();
      // Should be a no-op without crashing
      tray.showApp();
    });

    // --- updateStatus on uninitialized service ---
    test('updateStatus on uninitialized service returns immediately', () async {
      final tray = TrayService();
      // Should not throw
      await tray.updateStatus(
        isSyncing: false,
        pairCount: 3,
      );
    });

    test('updateStatus with syncing state on uninitialized service', () async {
      final tray = TrayService();
      await tray.updateStatus(
        isSyncing: true,
        currentPairName: 'test-pair',
      );
    });

    // --- dispose idempotency ---
    test('dispose can be called multiple times safely', () async {
      final tray = TrayService();
      await tray.dispose();
      await tray.dispose(); // second call should not throw
    });
  });

  // --- SyncResult for tooltip display ---
  group('SyncResult for tray tooltip', () {
    test('hasChanges reflects upload/download activity', () {
      const noChanges = SyncResult();
      expect(noChanges.hasChanges, false);

      const withUploads = SyncResult(uploaded: 3);
      expect(withUploads.hasChanges, true);

      const withDownloads = SyncResult(downloaded: 1);
      expect(withDownloads.hasChanges, true);
    });

    test('SyncResult addition combines counts', () {
      const a = SyncResult(uploaded: 2, downloaded: 1);
      const b = SyncResult(uploaded: 1, conflicts: 1);
      final sum = a + b;
      expect(sum.uploaded, 3);
      expect(sum.downloaded, 1);
      expect(sum.conflicts, 1);
    });

    test('SyncResult toString includes all fields', () {
      const r = SyncResult(uploaded: 1, downloaded: 2, conflicts: 3, errors: 4);
      final s = r.toString();
      expect(s, contains('up:1'));
      expect(s, contains('down:2'));
      expect(s, contains('conflicts:3'));
      expect(s, contains('errors:4'));
    });
  });
}
