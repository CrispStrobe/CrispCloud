import 'dart:ui' show Locale;
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

import '../l10n/platform_message_strings.dart';

import 'web_push_service_stub.dart'
    if (dart.library.html) 'web_push_service_web.dart' as impl;

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

  Future<void> notifyTransferComplete(String fileName, {Locale? locale}) => showNotification(
        type: PushNotificationType.transferComplete,
        title: PlatformMessageStrings(locale).text('transferTitle'),
        body: PlatformMessageStrings(locale).value('transferBody', fileName),
        tag: 'transfer-complete',
      );

  Future<void> notifySyncComplete(String providerName, {Locale? locale}) => showNotification(
        type: PushNotificationType.syncComplete,
        title: PlatformMessageStrings(locale).text('syncTitle'),
        body: PlatformMessageStrings(locale).value('syncBody', providerName),
        tag: 'sync-complete',
      );

  Future<void> notifyError(String message, {Locale? locale}) => showNotification(
        type: PushNotificationType.error,
        title: PlatformMessageStrings(locale).text('errorTitle'),
        body: message,
        tag: 'error',
      );

  /// Factory: returns the correct platform implementation.
  factory WebPushService() => impl.createWebPushService();
}
