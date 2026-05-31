// lib/services/web_push_service.dart
//
// Web Push Notification service.
//
// On web, requests Notification permission via the browser API and can show
// in-app / service-worker notifications for events such as transfer complete,
// sync complete, and errors.
//
// On non-web platforms a no-op stub is compiled in instead.
//
// Pattern mirrors local_file_service.dart: abstract class + factory that
// delegates to the platform implementation via conditional import.

import 'web_push_service_stub.dart'
    if (dart.library.html) 'web_push_service_web.dart' as _impl;

/// Notification types emitted by CrispCloud.
enum PushNotificationType {
  transferComplete,
  syncComplete,
  error,
  info,
}

/// Abstract interface for web push / in-browser notifications.
abstract class WebPushService {
  /// Request notification permission from the browser.
  /// Returns true if the user granted permission.
  Future<bool> requestPermission();

  /// Whether the platform supports notifications and permission has been
  /// granted.
  bool get isSupported;

  /// Show a notification.
  Future<void> showNotification({
    required PushNotificationType type,
    required String title,
    required String body,
    String? tag,
  });

  /// Convenience helpers -----------------------------------------------

  Future<void> notifyTransferComplete(String fileName) => showNotification(
        type: PushNotificationType.transferComplete,
        title: 'Transfer complete',
        body: '$fileName has been transferred successfully.',
        tag: 'transfer-complete',
      );

  Future<void> notifySyncComplete(String providerName) => showNotification(
        type: PushNotificationType.syncComplete,
        title: 'Sync complete',
        body: '$providerName is up to date.',
        tag: 'sync-complete',
      );

  Future<void> notifyError(String message) => showNotification(
        type: PushNotificationType.error,
        title: 'CrispCloud – Error',
        body: message,
        tag: 'error',
      );

  /// Factory: returns the correct platform implementation.
  factory WebPushService() => _impl.createWebPushService();
}
