// lib/services/background_sync_service.dart
//
// Mobile background sync using Workmanager and iOS BGAppRefreshTask.
// Only active on Android and iOS — no-op on web and desktop platforms.
//
// Usage:
//   await BackgroundSyncService.initialize();
//   await BackgroundSyncService.schedulePeriodicSync(intervalMinutes: 15);
//   await BackgroundSyncService.cancelSync();

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/background_notification_strings.dart';
import 'background_transfer_journal.dart';
import 'log_service.dart';
import 'installation_identity.dart';
import 'sync_database.dart';
import 'sync_engine.dart';
import 'cloud_storage_interface.dart';

// Workmanager and flutter_local_notifications are only used on Android/iOS.
// Conditional imports prevent compilation errors on web/desktop.
import 'background_sync_stub.dart'
    if (dart.library.io) 'background_sync_mobile.dart'
    as mobile;

/// Unique task name registered with Workmanager.
const kBackgroundSyncTaskName = 'crisp_cloud_background_sync';

/// Android callback ID and iOS BGTaskScheduler permitted identifier.
const kBackgroundSyncTaskId = 'crisp_cloud.background_sync';

/// SharedPreferences key that tracks whether background sync is scheduled.
const _kPrefEnabled = 'background_sync_enabled';

/// SharedPreferences key for the sync interval in minutes.
const _kPrefInterval = 'background_sync_interval_minutes';

/// Default sync interval.
const _kDefaultInterval = 15;

/// Runs all pairs, retaining failures even when a client cannot be created.
Future<SyncResult> runBackgroundSyncPairs(
  List<SyncPair> pairs, {
  required Future<CloudStorageClient?> Function(String provider) buildClient,
  required Future<SyncResult> Function(SyncPair pair, CloudStorageClient client)
  syncPair,
}) async {
  var total = const SyncResult();
  for (final pair in pairs) {
    try {
      final client = await buildClient(pair.provider);
      if (client == null) {
        total += SyncResult(
          errors: 1,
          errorMessages: [
            '${pair.name}: Background connection unavailable for ${pair.provider}',
          ],
          failureDetails: [
            SyncFailureDetail(
              location: pair.name,
              provider: pair.provider,
              providerUnavailable: true,
            ),
          ],
        );
        continue;
      }
      total += await syncPair(pair, client);
    } catch (error) {
      total += SyncResult(
        errors: 1,
        errorMessages: ['${pair.name}: $error'],
        failureDetails: [SyncFailureDetail(location: pair.name, cause: error)],
      );
    }
  }
  return total;
}

/// Service that manages background sync scheduling on Android and iOS.
///
/// All public methods are safe to call on any platform — they silently
/// return on web and desktop without doing any work.
class BackgroundSyncService {
  static const _log = Log('BackgroundSyncService');

  /// Whether this service can do anything on the current platform.
  static bool get isSupported => !kIsWeb && mobile.isMobileSupported;

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
  /// it survives app restarts. An optional [scheduler] lets host tests exercise
  /// the same preference bookkeeping with a native scheduler fixture.
  /// On iOS this is the desired interval applied at the next wake. An existing
  /// pending request may retain its earlier requested start time; the native
  /// handler uses the latest saved interval when it schedules the following run.
  static Future<void> schedulePeriodicSync({
    int intervalMinutes = _kDefaultInterval,
    Future<void> Function(int intervalMinutes)? scheduler,
  }) async {
    if (!isSupported && scheduler == null) return;
    try {
      if (scheduler != null) {
        await scheduler(intervalMinutes);
      } else {
        await mobile.scheduleWorkmanagerTask(
          uniqueName: kBackgroundSyncTaskName,
          taskId: kBackgroundSyncTaskId,
          intervalMinutes: intervalMinutes,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefEnabled, true);
      await prefs.setInt(_kPrefInterval, intervalMinutes);
      _log.info('Scheduled background sync every $intervalMinutes min');
    } catch (e, st) {
      _log.error('Failed to schedule background sync', e, st);
      rethrow;
    }
  }

  /// Cancel any previously scheduled background sync task. [canceller] is the
  /// corresponding host-test seam for checking failure/status propagation.
  static Future<void> cancelSync({Future<void> Function()? canceller}) async {
    if (!isSupported && canceller == null) return;
    try {
      await (canceller?.call() ??
          mobile.cancelWorkmanagerTask(kBackgroundSyncTaskName));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefEnabled, false);
      _log.info('Background sync cancelled');
    } catch (e, st) {
      _log.error('Failed to cancel background sync', e, st);
      rethrow;
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
  /// Optional factories allow host-side integration tests to exercise the
  /// same run lifecycle without a platform credential store or user database.
  static Future<bool> executeBackgroundTask({
    SyncDatabase Function()? databaseFactory,
    // Factories return a worker-owned session; it is closed after each pair.
    Future<CloudStorageClient?> Function(String provider)? clientFactory,
    Future<BackgroundTransferJournalRun> Function()? journalFactory,
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required String channelId,
      required String channelName,
    })?
    notificationSender,
  }) async {
    _log.info('Background sync task started');
    final notify = notificationSender ?? mobile.showLocalNotification;

    SyncDatabase? db;
    BackgroundTransferJournalRun? run;
    try {
      // Background isolates must resolve the same persisted installation as
      // foreground pairs. An uninitialized session identity cannot bind paths.
      await InstallationIdentityService.instance.initialize();
      // 1. Open database
      db = databaseFactory?.call() ?? SyncDatabase();

      // 2. Get all enabled sync pairs
      final pairs = await db.getEnabledPairs();
      if (pairs.isEmpty) {
        _log.info('No enabled sync pairs — nothing to do');
        return true;
      }

      // 3. Run sync for each pair
      //    In background we don't have a live auth provider, so we try to
      //    reconstruct a client from stored credentials for each pair.
      // A background isolate must not append to the foreground journal. Its
      // own leased log remains discoverable after termination; foreground
      // recovery imports it only after this writer has released the lease.
      run =
          await (journalFactory?.call() ??
              createBackgroundTransferJournalRun());
      final engine = SyncEngine(db, journal: run.journal);
      var result = const SyncResult();

      for (final pair in pairs) {
        CloudStorageClient? client;
        var providerUnavailable = false;
        try {
          client = await (clientFactory != null
              ? clientFactory(pair.provider)
              : mobile.buildClientForProvider(
                  pair.provider,
                  remotePath: pair.remotePath,
                ));
          if (client == null) {
            providerUnavailable = true;
            throw StateError(
              'Background sync is unavailable for "${pair.provider}". '
              'Open CrispCloud and reconnect the account.',
            );
          }
          if (!client.isAuthenticated) {
            throw StateError(
              'The saved "${pair.provider}" account could not be authenticated.',
            );
          }
          final pairResult = await engine.syncPair(pair, client);
          result += pairResult;
          _log.info('Pair "${pair.name}" synced — $pairResult');
        } catch (e, st) {
          _log.error('Error syncing pair "${pair.name}"', e, st);
          result += SyncResult(
            errors: 1,
            errorMessages: ['${pair.name}: $e'],
            failureDetails: [
              SyncFailureDetail(
                location: pair.name,
                cause: e,
                provider: pair.provider,
                providerUnavailable: providerUnavailable,
              ),
            ],
          );
        } finally {
          try {
            // Production builders use private credential copies, so cleanup
            // cannot erase or replace the foreground account's saved secrets.
            await client?.logout();
          } catch (e, st) {
            _log.error(
              'Could not close the background provider session',
              e,
              st,
            );
            result += SyncResult(
              errors: 1,
              errorMessages: [
                '${pair.name}: Could not close the provider session.',
              ],
              failureDetails: [
                SyncFailureDetail(location: pair.name, cause: e),
              ],
            );
          }
        }
      }

      // 4. Send local notification if there is something worth reporting
      if (result.conflicts > 0 || result.errors > 0) {
        final strings = await BackgroundNotificationStrings.fromPreferences();
        final message = strings.body(
          conflicts: result.conflicts,
          errors: result.errors,
          details: result.failureDetails.isEmpty
              ? result.errorMessages
              : result.failureDetails.map(strings.failureDetail).toList(),
        );
        try {
          await notify(
            id: 1001,
            title: strings.text('title'),
            body: message,
            channelId: 'crisp_cloud_sync',
            channelName: strings.text('channel'),
          );
        } catch (e, st) {
          _log.warn('Could not display the background sync result', e, st);
        }
      }

      _log.info(
        'Background sync task finished. conflicts=${result.conflicts} errors=${result.errors}',
      );
      // Workmanager must receive failure when credentials/providers or a pair
      // fail. Android can then apply the configured retry/backoff policy.
      return result.errors == 0;
    } catch (e, st) {
      _log.error('Background sync task failed', e, st);
      try {
        final strings = await BackgroundNotificationStrings.fromPreferences();
        await notify(
          id: 1002,
          title: strings.text('errorTitle'),
          body: strings.failure(e),
          channelId: 'crisp_cloud_sync',
          channelName: strings.text('channel'),
        );
      } catch (_) {}
      return false;
    } finally {
      try {
        await run?.close();
      } finally {
        await db?.close();
      }
    }
  }
}
