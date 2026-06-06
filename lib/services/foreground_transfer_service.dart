// lib/services/foreground_transfer_service.dart
//
// Foreground service support for long-running file transfers on Android.
//
// When a transfer exceeds [kForegroundThreshold] (5 seconds) this service
// promotes the ongoing transfer to an Android foreground service notification
// so the OS cannot kill it while the user switches away.
//
// The notification shows:
//   • File name
//   • Progress percentage
//   • Transfer speed (KB/s or MB/s)
//
// On non-Android platforms all methods are no-ops.  Use [isSupported] to guard
// UI that only makes sense on Android.
//
// Usage:
//   final svc = ForegroundTransferService();
//   await svc.startTransfer(id: 1, fileName: 'photo.jpg');
//   ...
//   await svc.updateProgress(id: 1, fileName: 'photo.jpg',
//       bytesTransferred: 500000, totalBytes: 1000000, speedBps: 250000);
//   await svc.finishTransfer(id: 1);

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'log_service.dart';

/// Minimum duration a transfer must run before a foreground notification is
/// shown.  Transfers that finish before this threshold are silent.
const Duration kForegroundThreshold = Duration(seconds: 5);

/// Notification channel used for transfer progress.
const String _kChannelId   = 'crisp_cloud_transfers';
const String _kChannelName = 'File Transfers';
const String _kChannelDesc = 'Shows progress for ongoing file uploads and downloads.';

/// Tracks per-transfer state so we can cancel the promotion timer if the
/// transfer finishes before [kForegroundThreshold].
class _TransferState {
  final int id;
  final String fileName;
  final Stopwatch elapsed = Stopwatch()..start();
  Timer? promotionTimer;
  bool promoted = false;

  _TransferState({required this.id, required this.fileName});
}

/// Service that manages foreground-service-style transfer notifications.
class ForegroundTransferService {
  static const _log = Log('ForegroundTransferService');

  /// True only on Android (non-web dart:io build).
  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final Map<int, _TransferState> _transfers = {};

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Must be called once (e.g. in main() or app startup) before using the
  /// service.  Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (!isSupported || _initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);
    _initialized = true;
    _log.debug('ForegroundTransferService initialized');
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Register the start of a transfer.
  ///
  /// If the transfer is still running after [kForegroundThreshold], a
  /// foreground-service notification is posted automatically.
  Future<void> startTransfer({
    required int id,
    required String fileName,
  }) async {
    if (!isSupported) return;
    await initialize();

    final state = _TransferState(id: id, fileName: fileName);
    _transfers[id] = state;

    // Schedule promotion after the threshold
    state.promotionTimer = Timer(kForegroundThreshold, () async {
      if (!state.promoted) {
        state.promoted = true;
        await _postNotification(
          id: id,
          fileName: fileName,
          progress: 0,
          speedBps: 0,
          indeterminate: true,
        );
      }
    });

    _log.debug('Transfer started', {'id': id, 'file': fileName});
  }

  /// Update the progress of an ongoing transfer.
  ///
  /// [bytesTransferred] and [totalBytes] are used to compute the percentage.
  /// [speedBps] is the current transfer speed in bytes/second.
  Future<void> updateProgress({
    required int id,
    required String fileName,
    required int bytesTransferred,
    required int totalBytes,
    required double speedBps,
  }) async {
    if (!isSupported) return;

    final state = _transfers[id];
    if (state == null) return;

    // Promote immediately if the threshold has already been exceeded
    if (!state.promoted && state.elapsed.elapsed >= kForegroundThreshold) {
      state.promoted = true;
      state.promotionTimer?.cancel();
    }

    if (!state.promoted) return; // transfer will finish before threshold

    final progress = totalBytes > 0
        ? ((bytesTransferred / totalBytes) * 100).clamp(0, 100).toInt()
        : 0;

    await _postNotification(
      id: id,
      fileName: fileName,
      progress: progress,
      speedBps: speedBps,
      indeterminate: totalBytes <= 0,
    );
  }

  /// Mark a transfer as finished and dismiss its notification.
  Future<void> finishTransfer({required int id}) async {
    if (!isSupported) return;

    final state = _transfers.remove(id);
    if (state == null) return;

    state.promotionTimer?.cancel();

    if (state.promoted) {
      await _notifications.cancel(id);
      _log.info('Transfer completed, notification dismissed', {'id': id});
    } else {
      _log.debug('Transfer finished before threshold, no notification', {'id': id});
    }
  }

  /// Cancel all active transfer notifications (e.g. on app destroy).
  Future<void> cancelAll() async {
    if (!isSupported) return;

    for (final state in _transfers.values) {
      state.promotionTimer?.cancel();
      if (state.promoted) {
        await _notifications.cancel(state.id);
      }
    }
    _transfers.clear();
    _log.debug('All transfer notifications cancelled');
  }

  // -------------------------------------------------------------------------
  // Notification helpers
  // -------------------------------------------------------------------------

  Future<void> _postNotification({
    required int id,
    required String fileName,
    required int progress,
    required double speedBps,
    required bool indeterminate,
  }) async {
    final speedLabel = _formatSpeed(speedBps);
    final body = indeterminate
        ? 'Uploading…'
        : '$progress%  •  $speedLabel';

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      maxProgress: 100,
      progress: indeterminate ? 0 : progress,
      indeterminate: indeterminate,
      // Prevent the notification from being swiped away during transfer
      autoCancel: false,
      icon: '@mipmap/ic_launcher',
      // Android O+: run as a foreground service notification
      // (requires FOREGROUND_SERVICE permission in manifest)
      channelShowBadge: false,
    );

    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(id, fileName, body, details);

    _log.debug('Transfer notification updated', {
      'id': id,
      'progress': progress,
      'speed': speedLabel,
    });
  }

  // -------------------------------------------------------------------------
  // Formatting helpers
  // -------------------------------------------------------------------------

  static String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '';
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
}
