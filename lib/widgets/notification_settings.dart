import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../providers/notification_provider.dart';

class NotificationSettingsPanel extends ConsumerWidget {
  const NotificationSettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(context.commanderTr('Notification duration')),
          trailing: DropdownButton<int>(
            key: const ValueKey('notification-timeout'),
            value: settings.seconds,
            items: [
              for (final seconds in const [5, 10, 30, 60, 0])
                DropdownMenuItem(
                  value: seconds,
                  child: Text(
                    seconds == 0
                        ? context.commanderTr('Until dismissed')
                        : '${seconds}s',
                  ),
                ),
            ],
            onChanged: (seconds) {
              if (seconds != null) notifier.update(seconds: seconds);
            },
          ),
        ),
        SwitchListTile(
          key: const ValueKey('notification-auto-hide-queue'),
          title: Text(context.commanderTr('Hide completed queue')),
          value: settings.hideFinishedQueue,
          onChanged: (value) => notifier.update(hideFinishedQueue: value),
        ),
        SwitchListTile(
          key: const ValueKey('notification-history-toggle'),
          title: Text(
            context.commanderTr('Keep notification history for this session'),
          ),
          value: settings.keepHistory,
          onChanged: (value) {
            notifier.update(keepHistory: value);
            if (!value) ref.read(notificationHistoryProvider.notifier).clear();
          },
        ),
        ListTile(
          key: const ValueKey('notification-history-open'),
          leading: const Icon(Icons.history),
          title: Text(context.commanderTr('Notification history')),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const NotificationHistoryDialog(),
          ),
        ),
      ],
    );
  }
}

class NotificationHistoryDialog extends ConsumerWidget {
  const NotificationHistoryDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(notificationHistoryProvider);
    return AlertDialog(
      title: Text(context.commanderTr('Notification history')),
      content: SizedBox(
        width: 600,
        height: 350,
        child: history.isEmpty
            ? Center(child: Text(context.commanderTr('No notifications.')))
            : ListView.builder(
                itemCount: history.length,
                itemBuilder: (_, index) {
                  final record = history[index];
                  return ListTile(
                    title: SelectableText(record.message),
                    subtitle: Text(record.time.toLocal().toString()),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('notification-history-clear'),
          onPressed: () =>
              ref.read(notificationHistoryProvider.notifier).clear(),
          child: Text(context.commanderTr('Clear')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    );
  }
}
