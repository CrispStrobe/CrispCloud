// lib/services/background_sync_mobile.dart
//
// Mobile implementation of background sync helpers.
// This file is only compiled on Android and iOS (dart.library.io guard in
// the conditional import in background_sync_service.dart).
//
// Workmanager runs the callback in a separate Dart isolate — there is no
// Flutter widget tree, no Riverpod, and no Platform channel access unless
// the plugin specifically supports it. We therefore reconstruct a minimal
// storage client from SharedPreferences (non-sensitive prefs only; tokens
// stored in flutter_secure_storage are not accessible without the full
// Flutter engine, so providers that rely solely on secure storage will be
// skipped gracefully).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'background_sync_service.dart';
import 'cloud_storage_interface.dart';
import 'ftp_client_adapter.dart';
import 'ftp_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'webdav_client_adapter.dart';
import 'webdav_config_service.dart';

final _log = Log('BackgroundSyncMobile');

/// True on all dart:io platforms — further narrowed to Android/iOS by the
/// conditional import guard in [BackgroundSyncService].
bool get isMobileSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// ---------------------------------------------------------------------------
// Workmanager top-level callback
// ---------------------------------------------------------------------------

/// Top-level callback registered with Workmanager.
///
/// Must be a top-level function (not a closure or static method) so that
/// Workmanager can call it from its own isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    _log.info('Background task woken: $taskName');
    if (taskName == kBackgroundSyncTaskName) {
      return BackgroundSyncService.executeBackgroundTask();
    }
    return Future.value(true);
  });
}

// ---------------------------------------------------------------------------
// Platform helpers called by BackgroundSyncService
// ---------------------------------------------------------------------------

Future<void> initializeWorkmanager() async {
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );
}

Future<void> scheduleWorkmanagerTask({
  required String uniqueName,
  required String taskId,
  required int intervalMinutes,
}) async {
  // Cancel any pre-existing task with the same name before re-registering so
  // that interval changes take effect immediately.
  await Workmanager().cancelByUniqueName(uniqueName);
  await Workmanager().registerPeriodicTask(
    uniqueName,
    taskId,
    frequency: Duration(minutes: intervalMinutes),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}

Future<void> cancelWorkmanagerTask(String uniqueName) async {
  await Workmanager().cancelByUniqueName(uniqueName);
}

// ---------------------------------------------------------------------------
// Client reconstruction for background isolate
// ---------------------------------------------------------------------------

/// Attempt to build a [CloudStorageClient] from persisted (non-sensitive)
/// preferences for [provider].
///
/// Providers that require OAuth tokens or encryption keys from
/// flutter_secure_storage cannot be reconstructed without the full Flutter
/// engine, so they return `null` (the background task skips them).
///
/// Currently supported in background:
///   - FTP / FTPS  (credentials may be in shared prefs)
///   - WebDAV      (credentials may be in shared prefs)
///
/// All OAuth providers (Dropbox, GDrive, OneDrive, pCloud) and
/// end-to-end-encrypted providers (Filen, Internxt) return `null` because
/// their tokens live in flutter_secure_storage which requires the full
/// Flutter plugin infrastructure.
Future<CloudStorageClient?> buildClientForProvider(String provider) async {
  final prefs = await SharedPreferences.getInstance();

  // We use the same SharedPreferences keys the respective ConfigService classes
  // use to persist non-secret fields.
  switch (provider.toLowerCase()) {
    case 'ftp':
      return _buildFtpClient(prefs);
    case 'webdav':
      return _buildWebDavClient(prefs);
    default:
      // Providers with tokens in secure storage cannot be reached from an
      // isolate that has no Flutter engine platform channels.
      _log.warn('Cannot reconstruct client for provider "$provider" in background — '
          'provider uses secure-storage tokens. Skipping.');
      return null;
  }
}

Future<CloudStorageClient?> _buildFtpClient(SharedPreferences prefs) async {
  // FTPConfigService persists host/port/username in SharedPreferences;
  // password may be in secure storage. We read what we can and attempt
  // an anonymous / guest connection if the password is unavailable.
  final host = prefs.getString('ftp_host');
  final username = prefs.getString('ftp_username');
  final password = prefs.getString('ftp_password'); // populated if persisted
  final port = prefs.getInt('ftp_port') ?? 21;

  if (host == null || host.isEmpty) {
    _log.warn('FTP host not found in SharedPreferences');
    return null;
  }

  try {
    // Use a minimal SecureStorage backed by SharedPreferences for the isolate.
    final secureStorage = _SharedPrefsSecureStorage(prefs);
    final configService = FTPConfigService(
      configPath: '',
      secureStorage: secureStorage,
    );
    // Populate the config with whatever we have.
    if (host.isNotEmpty) await prefs.setString('ftp_host', host);
    if (username != null) await prefs.setString('ftp_username', username);
    if (password != null) await prefs.setString('ftp_password', password);
    await prefs.setInt('ftp_port', port);

    final client = FTPClientAdapter(config: configService);
    _log.info('Built FTP client for background sync');
    return client;
  } catch (e) {
    _log.error('Failed to build FTP client', e);
    return null;
  }
}

Future<CloudStorageClient?> _buildWebDavClient(SharedPreferences prefs) async {
  final url = prefs.getString('webdav_url');
  final username = prefs.getString('webdav_username');
  final password = prefs.getString('webdav_password');

  if (url == null || url.isEmpty) {
    _log.warn('WebDAV URL not found in SharedPreferences');
    return null;
  }

  try {
    final secureStorage = _SharedPrefsSecureStorage(prefs);
    final configService = WebDavConfigService(
      configPath: '',
      secureStorage: secureStorage,
    );
    if (url.isNotEmpty) await prefs.setString('webdav_url', url);
    if (username != null) await prefs.setString('webdav_username', username);
    if (password != null) await prefs.setString('webdav_password', password);

    final client = WebDavClientAdapter(config: configService);
    _log.info('Built WebDAV client for background sync');
    return client;
  } catch (e) {
    _log.error('Failed to build WebDAV client', e);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Local notifications
// ---------------------------------------------------------------------------

Future<void> showLocalNotification({
  required int id,
  required String title,
  required String body,
  required String channelId,
  required String channelName,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();

  // Android init
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  // iOS/macOS init — request no alerts at init time (respect user settings)
  const darwinInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
  );

  await plugin.initialize(initSettings);

  final androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: 'CrispCloud background sync status',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: '@mipmap/ic_launcher',
  );

  const darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentSound: false,
  );

  final notifDetails = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  await plugin.show(id, title, body, notifDetails);
}

// ---------------------------------------------------------------------------
// Minimal SecureStorage backed by SharedPreferences (isolate-safe fallback)
// ---------------------------------------------------------------------------

/// A [SecureStorage] implementation that reads/writes SharedPreferences.
///
/// This is intentionally insecure and is only used inside a background
/// isolate where flutter_secure_storage is unavailable. In practice the
/// only values stored here are FTP/WebDAV credentials that the user has
/// explicitly chosen to persist.
class _SharedPrefsSecureStorage implements SecureStorage {
  final SharedPreferences _prefs;

  _SharedPrefsSecureStorage(this._prefs);

  @override
  Future<String?> read(String key) async => _prefs.getString('_ss_$key');

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString('_ss_$key', value);

  @override
  Future<void> delete(String key) async => _prefs.remove('_ss_$key');

  @override
  Future<bool> containsKey(String key) async =>
      _prefs.containsKey('_ss_$key');

  @override
  Future<void> deleteAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('_ss_')).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}
