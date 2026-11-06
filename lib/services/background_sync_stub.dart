// lib/services/background_sync_stub.dart
//
// Stub implementation of background sync helpers for web and desktop.
// All functions are no-ops that satisfy the type system so the main service
// file compiles on every platform without conditional compilation pragmas.

import '../services/cloud_storage_interface.dart';

/// Returns false on non-mobile platforms.
bool get isMobileSupported => false;

Future<void> initializeWorkmanager() async {}

Future<void> scheduleWorkmanagerTask({
  required String uniqueName,
  required String taskId,
  required int intervalMinutes,
}) async {}

Future<void> cancelWorkmanagerTask(String uniqueName) async {}

/// Unsupported providers must never be reported as a successful sync skip.
Future<CloudStorageClient> buildClientForProvider(
  String provider, {
  String remotePath = '/',
}) async =>
    throw UnsupportedError('Background sync is unavailable on this platform.');

Future<void> showLocalNotification({
  required int id,
  required String title,
  required String body,
  required String channelId,
  required String channelName,
}) async {}
