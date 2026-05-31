// lib/services/web_push_service_stub.dart
//
// No-op stub compiled on non-web platforms (native, desktop, CLI tests).

import 'web_push_service.dart';

WebPushService createWebPushService() => _StubWebPushService();

class _StubWebPushService implements WebPushService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> showNotification({
    required PushNotificationType type,
    required String title,
    required String body,
    String? tag,
  }) async {}

  @override
  Future<void> notifyTransferComplete(String fileName) async {}

  @override
  Future<void> notifySyncComplete(String providerName) async {}

  @override
  Future<void> notifyError(String message) async {}
}
