import 'package:flutter/material.dart';

import '../l10n/commander_strings.dart';

/// Chooses an earliest start in the device's local time. The queue persists the
/// resulting instant in UTC and still revalidates the reviewed plan on dispatch.
Future<DateTime?> showTransferStartPicker(
  BuildContext context, {
  DateTime? initialValue,
}) async {
  final now = DateTime.now();
  final latest = DateTime(now.year + 1, now.month, now.day);
  final proposed = initialValue?.toLocal();
  final initial = proposed != null && proposed.isAfter(now)
      ? (proposed.isAfter(latest) ? latest : proposed)
      : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: latest,
    helpText: context.commanderTr('Schedule transfer'),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: context.commanderTr('Earliest start (local time)'),
  );
  if (time == null || !context.mounted) return null;
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!start.isAfter(DateTime.now()) ||
      start.hour != time.hour ||
      start.minute != time.minute) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          context.commanderTr('Choose a valid start time in the future.'),
        ),
      ),
    );
    return null;
  }
  return start;
}
