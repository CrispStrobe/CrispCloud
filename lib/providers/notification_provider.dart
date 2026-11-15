import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings {
  const NotificationSettings({
    this.seconds = 30,
    this.keepHistory = true,
    this.hideFinishedQueue = true,
  });
  final int seconds;
  final bool keepHistory;
  final bool hideFinishedQueue;
}

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings()) {
    _load();
  }
  int _revision = 0;
  Future<void> _load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || revision != _revision) return;
      final seconds = prefs.getInt('notifications_seconds') ?? 30;
      state = NotificationSettings(
        seconds: const [0, 5, 10, 30, 60].contains(seconds) ? seconds : 30,
        keepHistory: prefs.getBool('notifications_history') ?? true,
        hideFinishedQueue:
            prefs.getBool('notifications_hide_finished_queue') ?? true,
      );
    } catch (_) {
      /* Defaults remain usable if preferences are unavailable. */
    }
  }

  Future<void> update({
    int? seconds,
    bool? keepHistory,
    bool? hideFinishedQueue,
  }) async {
    if (seconds != null && !const [0, 5, 10, 30, 60].contains(seconds)) {
      throw ArgumentError.value(seconds);
    }
    _revision++;
    state = NotificationSettings(
      seconds: seconds ?? state.seconds,
      keepHistory: keepHistory ?? state.keepHistory,
      hideFinishedQueue: hideFinishedQueue ?? state.hideFinishedQueue,
    );
    final snapshot = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('notifications_seconds', snapshot.seconds);
      await prefs.setBool('notifications_history', snapshot.keepHistory);
      await prefs.setBool(
        'notifications_hide_finished_queue',
        snapshot.hideFinishedQueue,
      );
    } catch (_) {
      /* A failed preference write must not break the operation. */
    }
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

class NotificationRecord {
  NotificationRecord(this.message) : time = DateTime.now();
  final String message;
  final DateTime time;
}

class NotificationHistory extends StateNotifier<List<NotificationRecord>> {
  NotificationHistory() : super(const []);
  void add(String message) =>
      state = [NotificationRecord(message), ...state.take(199)];
  void clear() => state = const [];
}

/// Session-only text, never callbacks, document objects, or credentials on disk.
final notificationHistoryProvider =
    StateNotifierProvider<NotificationHistory, List<NotificationRecord>>(
      (ref) => NotificationHistory(),
    );
