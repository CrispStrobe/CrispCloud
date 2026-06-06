// lib/services/web_push_service_web.dart
//
// Web implementation of WebPushService using the browser Notification API.
// Compiled only on the web target (dart.library.html is available).

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

import 'log_service.dart';
import 'web_push_service.dart';

WebPushService createWebPushService() => _WebPushServiceImpl();

class _WebPushServiceImpl implements WebPushService {
  static const _log = Log('WebPushService');

  // Track whether the browser supports the Notification API.
  static bool get _apiAvailable {
    try {
      // universal_html exposes Notification as a class; a simple check is
      // sufficient — if the constructor is reachable the API exists.
      return kIsWeb;
    } catch (_) {
      return false;
    }
  }

  bool _permissionGranted = false;

  @override
  bool get isSupported => _apiAvailable && _permissionGranted;

  @override
  Future<bool> requestPermission() async {
    if (!_apiAvailable) {
      _log.debug('Notification API not available on this browser');
      return false;
    }

    try {
      final current = html.Notification.permission;
      if (current == 'granted') {
        _permissionGranted = true;
        _log.info('Notification permission already granted');
        return true;
      }
      if (current == 'denied') {
        _log.warn('Notification permission denied by user');
        return false;
      }

      // 'default' — ask the user.
      final result = await html.Notification.requestPermission();
      _permissionGranted = result == 'granted';
      _log.info('Notification permission result', {'result': result});
      return _permissionGranted;
    } catch (e, st) {
      _log.error('Error requesting notification permission', e, st);
      return false;
    }
  }

  @override
  Future<void> showNotification({
    required PushNotificationType type,
    required String title,
    required String body,
    String? tag,
  }) async {
    if (!_apiAvailable) return;

    // Lazily check permission in case it was granted outside this service.
    if (!_permissionGranted) {
      final current = html.Notification.permission;
      if (current != 'granted') {
        _log.debug('showNotification skipped – permission not granted');
        return;
      }
      _permissionGranted = true;
    }

    try {
      html.Notification(
        title,
        body: body,
        icon: 'icons/Icon-192.png',
        tag: tag ?? type.name,
      );
      _log.debug('Notification shown', {'title': title, 'type': type.name});
    } catch (e, st) {
      _log.error('Failed to show notification', e, st);
    }
  }

  @override
  Future<void> notifyTransferComplete(String fileName) => showNotification(
        type: PushNotificationType.transferComplete,
        title: 'Transfer complete',
        body: '$fileName has been transferred successfully.',
        tag: 'transfer-complete',
      );

  @override
  Future<void> notifySyncComplete(String providerName) => showNotification(
        type: PushNotificationType.syncComplete,
        title: 'Sync complete',
        body: '$providerName is up to date.',
        tag: 'sync-complete',
      );

  @override
  Future<void> notifyError(String message) => showNotification(
        type: PushNotificationType.error,
        title: 'CrispCloud – Error',
        body: message,
        tag: 'error',
      );
}
