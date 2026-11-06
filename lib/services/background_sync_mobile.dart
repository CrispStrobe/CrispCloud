// Mobile background workers have their own Flutter engine and plugin registry.
// Restore only supported provider sessions from the same secure maps as the
// foreground app. Worker-local credential copies keep logout and transient
// connection failures from changing the foreground account's stored secrets.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:workmanager/workmanager.dart';

import 'background_sync_service.dart';
import 'cloud_storage_interface.dart';
import 'ftp_client_adapter.dart';
import 'ftp_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'webdav_client_adapter.dart';
import 'webdav_config_service.dart';

const _log = Log('BackgroundSyncMobile');

bool get isMobileSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Both engines invoke this top-level entry point after native plugins are
/// registered. Workmanager also initializes the widget binding before dispatch.
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask(dispatchBackgroundSyncTask);
}

/// Android delivers taskId; Apple delivers the registered uniqueName. Accept
/// the previous name as well so already-enqueued Android work can complete.
Future<bool> dispatchBackgroundSyncTask(
  String taskName,
  Map<String, dynamic>? inputData, {
  Future<bool> Function()? execute,
}) async {
  _log.info('Background task woken: $taskName');
  if (taskName != kBackgroundSyncTaskId &&
      taskName != kBackgroundSyncTaskName) {
    _log.warn('Unknown background task was not executed: $taskName');
    return false;
  }
  return (execute ?? BackgroundSyncService.executeBackgroundTask)();
}

Future<void> initializeWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher);
}

Future<void> scheduleWorkmanagerTask({
  required String uniqueName,
  required String taskId,
  required int intervalMinutes,
  TargetPlatform? targetPlatform,
}) async {
  if (intervalMinutes < 15) {
    throw ArgumentError.value(intervalMinutes, 'intervalMinutes', 'Minimum 15');
  }
  final isApple =
      (targetPlatform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  // workmanager_apple schedules BGAppRefreshTask by uniqueName, not taskId.
  // This name must match AppDelegate and BGTaskSchedulerPermittedIdentifiers.
  final scheduledName = isApple ? taskId : uniqueName;
  // Both schedulers replace an existing request with this identifier. Do not
  // cancel first: a failed reschedule must retain the previous pending work.
  await Workmanager().registerPeriodicTask(
    scheduledName,
    taskId,
    frequency: Duration(minutes: intervalMinutes),
    initialDelay: Duration(minutes: intervalMinutes),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
  // The pinned Apple plugin logs submit errors instead of returning them over
  // its channel. This proves a pending wake exists, not that a replacement was
  // accepted: an older request may remain after a swallowed submit failure.
  // The saved interval is the desired cadence; AppDelegate reads it on every
  // wake and uses it for the next reschedule, including a retained old request.
  if (isApple && !await Workmanager().isScheduledByUniqueName(scheduledName)) {
    throw StateError(
      'iOS did not accept the background sync request. '
      'Check Background App Refresh and retry.',
    );
  }
}

Future<void> cancelWorkmanagerTask(
  String uniqueName, {
  TargetPlatform? targetPlatform,
}) async {
  await Workmanager().cancelByUniqueName(uniqueName);
  if ((targetPlatform ?? defaultTargetPlatform) == TargetPlatform.iOS &&
      uniqueName != kBackgroundSyncTaskId) {
    await Workmanager().cancelByUniqueName(kBackgroundSyncTaskId);
  }
}

/// A credential/connection failure safe to display without exposing secrets.
class BackgroundSyncClientException implements Exception {
  const BackgroundSyncClientException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Restore a private, authenticated FTP/FTPS or WebDAV session. No preference
/// fallback, credential migration, login parsing, or write to [secureStorage]
/// happens here. Provider changes are still checked against SyncSourceBinding
/// by the sync engine before any file operation.
Future<CloudStorageClient> buildClientForProvider(
  String provider, {
  SecureStorage? secureStorage,
  FTPClientFactory? ftpClientFactory,
  webdav.Client Function(String, String, String)? webDavClientFactory,
  String remotePath = '/',
}) async {
  final kind = provider.toLowerCase();
  final String credentialKey;
  switch (kind) {
    case 'ftp':
    case 'ftps':
      credentialKey = 'ftp_credentials';
    case 'webdav':
      credentialKey = 'webdav_credentials';
    default:
      throw BackgroundSyncClientException(
        'Background sync is unavailable for "$provider". '
        'Open CrispCloud to sync this pair.',
      );
  }
  Map<String, String>? credentials;
  try {
    credentials = await (secureStorage ?? PlatformSecureStorage()).readMap(
      credentialKey,
    );
  } catch (_) {
    throw const BackgroundSyncClientException(
      'The secure credential store is unavailable. Unlock the device and '
      'open CrispCloud before retrying background sync.',
    );
  }
  if (credentials == null || !_validCredentials(kind, credentials)) {
    throw BackgroundSyncClientException(
      'Saved $provider credentials are missing or incomplete. '
      'Open CrispCloud and reconnect this account.',
    );
  }

  // Each adapter may clear its config during logout. Only this worker's copy
  // can be affected, including after a connection/authentication failure.
  final privateCredentials = InMemorySecureStorage();
  await privateCredentials.writeMap(credentialKey, Map.of(credentials));
  CloudStorageClient? client;
  try {
    if (kind == 'webdav') {
      final adapter = WebDavClientAdapter(
        config: WebDavConfigService(
          configPath: '',
          secureStorage: privateCredentials,
        ),
        clientFactory: webDavClientFactory,
      );
      client = adapter;
      await adapter.restoreSession(remotePath: remotePath);
    } else {
      final adapter = FTPClientAdapter(
        config: FTPConfigService(
          configPath: '',
          secureStorage: privateCredentials,
        ),
        clientFactory: ftpClientFactory,
      );
      client = adapter;
      await adapter.restoreSession();
    }
    if (!client.isAuthenticated) {
      throw StateError('The provider did not authenticate the saved session.');
    }
    return client;
  } catch (_) {
    try {
      await client?.logout();
    } catch (_) {
      // Preserve the connection failure, without exposing transport secrets.
    }
    await privateCredentials.deleteAll();
    throw BackgroundSyncClientException(
      'Could not connect to the saved $provider account. '
      'Check the connection and sign-in in CrispCloud, then retry.',
    );
  }
}

bool _validCredentials(String provider, Map<String, String> credentials) {
  final host = credentials['host'];
  final user = credentials['username'];
  if (host == null ||
      host.isEmpty ||
      host.trim() != host ||
      user == null ||
      user.isEmpty ||
      credentials['password'] == null ||
      RegExp(r'[\x00\r\n]').hasMatch(host) ||
      RegExp(r'[\x00\r\n]').hasMatch(user)) {
    return false;
  }
  if (provider == 'webdav') {
    final uri = Uri.tryParse(host);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }
  final port = int.tryParse(credentials['port'] ?? '');
  final tls = credentials['useTLS'];
  return port != null &&
      port > 0 &&
      port <= 65535 &&
      (tls == 'true' || tls == 'false') &&
      (provider != 'ftps' || tls == 'true');
}

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
