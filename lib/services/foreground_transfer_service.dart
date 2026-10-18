import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const kForegroundThreshold = Duration(seconds: 5);

/// Owns the single Android data-sync foreground service across transfers.
/// Call from the foreground while starting a user-requested transfer.
class ForegroundTransferService {
  static bool get isSupported => !kIsWeb && Platform.isAndroid;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _active = <int, String>{};
  Future<void>? _initialized;
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _init() => _initialized ??= _plugin
      .initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      )
      .then((_) {});

  AndroidNotificationDetails _details({int current = 0, int total = 0}) =>
      AndroidNotificationDetails(
        'active_transfers',
        'Active transfers',
        channelDescription: 'Progress for user-requested file transfers',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showProgress: total > 0,
        maxProgress: 100,
        progress:
            total <= 0 ? 0 : (100 * current / total).clamp(0, 100).round(),
        indeterminate: total <= 0,
      );
  Future<void> startTransfer(
      {required int id, required String fileName}) async {
    if (!isSupported) return;
    await _init();
    _active[id] = fileName;
    await _android!.startForegroundService(901, 'Transferring files', fileName,
        notificationDetails: _details(),
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync
        });
  }

  Future<void> updateProgress(
      {required int id,
      required String fileName,
      required int bytesTransferred,
      required int totalBytes,
      required double speedBps}) async {
    if (!isSupported || !_active.containsKey(id)) return;
    await _plugin.show(
        901,
        'Transferring files',
        fileName,
        NotificationDetails(
            android: _details(current: bytesTransferred, total: totalBytes)));
  }

  Future<void> finishTransfer({required int id}) async {
    if (!isSupported) return;
    _active.remove(id);
    if (_active.isEmpty) await _android?.stopForegroundService();
  }

  Future<void> cancelAll() async {
    if (!isSupported) return;
    _active.clear();
    await _android?.stopForegroundService();
  }
}
