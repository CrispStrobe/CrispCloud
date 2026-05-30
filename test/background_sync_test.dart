// test/background_sync_test.dart
//
// Tests for BackgroundSyncService API and the stub implementation.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/background_sync_service.dart';
import 'package:crisp_cloud/services/background_sync_stub.dart' as stub;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // Stub functions
  // ---------------------------------------------------------------------------
  group('background_sync_stub', () {
    test('isMobileSupported returns false', () {
      expect(stub.isMobileSupported, false);
    });

    test('initializeWorkmanager completes without error', () async {
      await stub.initializeWorkmanager();
    });

    test('scheduleWorkmanagerTask completes without error', () async {
      await stub.scheduleWorkmanagerTask(
        uniqueName: 'test_task',
        taskId: 'test_id',
        intervalMinutes: 15,
      );
    });

    test('cancelWorkmanagerTask completes without error', () async {
      await stub.cancelWorkmanagerTask('test_task');
    });

    test('buildClientForProvider always returns null', () async {
      final client = await stub.buildClientForProvider('gdrive');
      expect(client, isNull);

      final client2 = await stub.buildClientForProvider('s3');
      expect(client2, isNull);
    });

    test('showLocalNotification completes without error', () async {
      await stub.showLocalNotification(
        id: 42,
        title: 'Test',
        body: 'Test body',
        channelId: 'test_channel',
        channelName: 'Test Channel',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // BackgroundSyncService static API
  // ---------------------------------------------------------------------------
  group('BackgroundSyncService', () {
    test('isSupported returns false on non-mobile (stub) platforms', () {
      // On desktop/CI, the stub is used, so isSupported should be false
      expect(BackgroundSyncService.isSupported, false);
    });

    test('initialize is a no-op on unsupported platforms', () async {
      // Should not throw
      await BackgroundSyncService.initialize();
    });

    test('schedulePeriodicSync is a no-op on unsupported platforms', () async {
      await BackgroundSyncService.schedulePeriodicSync(intervalMinutes: 30);
      // Should not persist because isSupported is false
    });

    test('cancelSync is a no-op on unsupported platforms', () async {
      await BackgroundSyncService.cancelSync();
    });

    test('isScheduled returns false on unsupported platforms', () async {
      final scheduled = await BackgroundSyncService.isScheduled();
      expect(scheduled, false);
    });

    test('getIntervalMinutes returns default (15) when nothing is saved', () async {
      final interval = await BackgroundSyncService.getIntervalMinutes();
      expect(interval, 15);
    });

    test('getIntervalMinutes returns saved value', () async {
      SharedPreferences.setMockInitialValues({
        'background_sync_interval_minutes': 30,
      });
      final interval = await BackgroundSyncService.getIntervalMinutes();
      expect(interval, 30);
    });

    test('isScheduled respects SharedPreferences flag', () async {
      // Even if we write the pref, isSupported is false so isScheduled returns false
      SharedPreferences.setMockInitialValues({
        'background_sync_enabled': true,
      });
      final scheduled = await BackgroundSyncService.isScheduled();
      expect(scheduled, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  group('Background sync constants', () {
    test('task name is set', () {
      expect(kBackgroundSyncTaskName, 'crisp_cloud_background_sync');
    });

    test('task id is set', () {
      expect(kBackgroundSyncTaskId, 'crisp_cloud.background_sync');
    });
  });
}
