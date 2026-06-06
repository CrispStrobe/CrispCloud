// lib/services/background_sync_service.dart
//
// Mobile background sync using Workmanager (Android) and background fetch (iOS).
// Only active on Android and iOS — no-op on web and desktop platforms.
//
// Usage:
//   await BackgroundSyncService.initialize();
//   await BackgroundSyncService.schedulePeriodicSync(intervalMinutes: 15);
//   await BackgroundSyncService.cancelSync();

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';
import 'sync_database.dart';
import 'sync_engine.dart';

// Workmanager and flutter_local_notifications are only used on Android/iOS.
// Conditional imports prevent compilation errors on web/desktop.
import 'background_sync_stub.dart'
    if (dart.library.io) 'background_sync_mobile.dart' as mobile;

/// Unique task name registered with Workmanager.
const kBackgroundSyncTaskName = 'crisp_cloud_background_sync';

/// Unique task identifier (must be a simple string, no special chars).
const kBackgroundSyncTaskId = 'crisp_cloud.background_sync';

/// SharedPreferences key that tracks whether background sync is scheduled.
const _kPrefEnabled = 'background_sync_enabled';

/// SharedPreferences key for the sync interval in minutes.
const _kPrefInterval = 'background_sync_interval_minutes';

/// Default sync interval.
const _kDefaultInterval = 15;

/// Service that manages background sync scheduling on Android and iOS.
///
/// All public methods are safe to call on any platform — they silently
/// return on web and desktop without doing any work.
class BackgroundSyncService {
  static const _log = Log('BackgroundSyncService');

  /// Whether this service can do anything on the current platform.
  static bool get isSupported =>
      !kIsWeb && mobile.isMobileSupported;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Initialize Workmanager and register the top-level callback.
  ///
  /// Must be called from `main()` before `runApp()`.
  static Future<void> initialize() async {
    if (!isSupported) return;
    try {
      await mobile.initializeWorkmanager();
      _log.info('Workmanager initialized');
    } catch (e, st) {
      _log.error('Failed to initialize Workmanager', e, st);
    }
  }

  // -------------------------------------------------------------------------
  // Scheduling
  // -------------------------------------------------------------------------

  /// Schedule a periodic background sync task.
  ///
  /// [intervalMinutes] — how often the OS should wake the task (minimum 15 min
  /// on Android due to Doze mode; iOS best-effort).  The value is persisted so
  /// it survives app restarts.
  static Future<void> schedulePeriodicSync({
    int intervalMinutes = _kDefaultInterval,
  }) async {
    if (!isSupported) return;
    try {
      await mobile.scheduleWorkmanagerTask(
        uniqueName: kBackgroundSyncTaskName,
        taskId: kBackgroundSyncTaskId,
        intervalMinutes: intervalMinutes,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefEnabled, true);
      await prefs.setInt(_kPrefInterval, intervalMinutes);
      _log.info('Scheduled background sync every $intervalMinutes min');
    } catch (e, st) {
      _log.error('Failed to schedule background sync', e, st);
    }
  }

  /// Cancel any previously scheduled background sync task.
  static Future<void> cancelSync() async {
    if (!isSupported) return;
    try {
      await mobile.cancelWorkmanagerTask(kBackgroundSyncTaskName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefEnabled, false);
      _log.info('Background sync cancelled');
    } catch (e, st) {
      _log.error('Failed to cancel background sync', e, st);
    }
  }

  // -------------------------------------------------------------------------
  // Status queries
  // -------------------------------------------------------------------------

  /// Returns true if background sync is currently scheduled.
  static Future<bool> isScheduled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPrefEnabled) ?? false;
  }

  /// Returns the currently configured sync interval in minutes.
  static Future<int> getIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPrefInterval) ?? _kDefaultInterval;
  }

  // -------------------------------------------------------------------------
  // Background task entry-point
  // -------------------------------------------------------------------------

  /// Called by Workmanager when the OS wakes the background task.
  ///
  /// This runs in an isolate that has NO Flutter widget tree — only raw Dart
  /// and platform channels. Keep it lean: init DB, sync, notify, return.
  static Future<bool> executeBackgroundTask() async {
    _log.info('Background sync task started');

    SyncDatabase? db;
    try {
      // 1. Open database
      db = SyncDatabase();

      // 2. Get all enabled sync pairs
      final pairs = await db.getEnabledPairs();
      if (pairs.isEmpty) {
        _log.info('No enabled sync pairs — nothing to do');
        return true;
      }

      // 3. Run sync for each pair
      //    In background we don't have a live auth provider, so we try to
      //    reconstruct a client from stored credentials for each pair.
      final engine = SyncEngine(db);
      int conflicts = 0;
      int errors = 0;
      final errorMessages = <String>[];

      for (final pair in pairs) {
        try {
          final client = await mobile.buildClientForProvider(pair.provider);
          if (client == null) {
            _log.warn('Could not build client for provider "${pair.provider}" — skipping "${pair.name}"');
            continue;
          }
          final result = await engine.syncPair(pair, client);
          conflicts += result.conflicts;
          errors += result.errors;
          errorMessages.addAll(result.errorMessages);
          _log.info('Pair "${pair.name}" synced — $result');
        } catch (e, st) {
          _log.error('Error syncing pair "${pair.name}"', e, st);
          errors++;
          errorMessages.add('${pair.name}: $e');
        }
      }

      // 4. Send local notification if there is something worth reporting
      if (conflicts > 0 || errors > 0) {
        final message = _buildNotificationBody(
          conflicts: conflicts,
          errors: errors,
          errorMessages: errorMessages,
        );
        await mobile.showLocalNotification(
          id: 1001,
          title: 'CrispCloud Sync',
          body: message,
          channelId: 'crisp_cloud_sync',
          channelName: 'Sync Notifications',
        );
      }

      _log.info('Background sync task finished. conflicts=$conflicts errors=$errors');
      return true;
    } catch (e, st) {
      _log.error('Background sync task failed', e, st);
      try {
        await mobile.showLocalNotification(
          id: 1002,
          title: 'CrispCloud Sync Error',
          body: 'Background sync failed: $e',
          channelId: 'crisp_cloud_sync',
          channelName: 'Sync Notifications',
        );
      } catch (_) {}
      return false;
    } finally {
      await db?.close();
    }
  }

  static String _buildNotificationBody({
    required int conflicts,
    required int errors,
    required List<String> errorMessages,
  }) {
    final parts = <String>[];
    if (conflicts > 0) parts.add('$conflicts conflict${conflicts == 1 ? '' : 's'}');
    if (errors > 0) parts.add('$errors error${errors == 1 ? '' : 's'}');
    if (errorMessages.isNotEmpty) {
      parts.add(errorMessages.first);
    }
    return parts.join(' — ');
  }
}
