import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_provider.dart';

/// Routine confirmations have a fixed deadline, even when actionable or error
/// notifications are configured to remain until dismissed.
class TransientSnackBar extends SnackBar {
  const TransientSnackBar({
    super.key,
    required super.content,
    super.action,
    super.backgroundColor,
  }) : super(duration: const Duration(seconds: 30), persist: false);
}

/// Applies the same dismissal policy to root and editor-local notifications.
/// Flutter otherwise makes snackbars with an Undo action persistent by default.
class AppScaffoldMessenger extends ScaffoldMessenger {
  const AppScaffoldMessenger({super.key, required super.child});
  @override
  ScaffoldMessengerState createState() => _AppScaffoldMessengerState();
}

class _AppScaffoldMessengerState extends ScaffoldMessengerState {
  final _timers = <Timer>{};
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    final settings = container.read(notificationSettingsProvider);
    if (settings.keepHistory) {
      final content = snackBar.content;
      final text = switch (content) {
        Text() => content.data ?? content.textSpan?.toPlainText() ?? '',
        SelectableText() =>
          content.data ?? content.textSpan?.toPlainText() ?? '',
        _ => '',
      };
      if (text.isNotEmpty) {
        container.read(notificationHistoryProvider.notifier).add(text);
      }
    }
    Timer? timer;
    late ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller;
    final seconds = snackBar is TransientSnackBar ? 30 : settings.seconds;
    final duration = Duration(seconds: seconds == 0 ? 31536000 : seconds);
    final replacement = SnackBar(
      key: snackBar.key,
      content: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall,
        child: snackBar.content,
      ),
      backgroundColor: snackBar.backgroundColor,
      elevation: snackBar.elevation,
      margin: snackBar.margin,
      padding: snackBar.padding ?? const EdgeInsets.symmetric(horizontal: 12),
      width: snackBar.width,
      shape: snackBar.shape,
      hitTestBehavior: snackBar.hitTestBehavior,
      behavior: snackBar.behavior,
      action: snackBar.action,
      actionOverflowThreshold: snackBar.actionOverflowThreshold,
      showCloseIcon: true,
      closeIconColor: snackBar.closeIconColor,
      duration: duration,
      persist: seconds == 0,
      animation: snackBar.animation,
      dismissDirection: snackBar.dismissDirection,
      clipBehavior: snackBar.clipBehavior,
      onVisible: () {
        // Also time out action bars with accessibility navigation enabled.
        if (seconds > 0) {
          timer = Timer(duration, () {
            if (mounted) controller.close();
          });
          _timers.add(timer!);
        }
        snackBar.onVisible?.call();
      },
    );
    // A new notification replaces the visible one; history retains its text.
    clearSnackBars();
    controller = super.showSnackBar(
      replacement,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
    unawaited(
      controller.closed.then((_) {
        timer?.cancel();
        _timers.remove(timer);
      }),
    );
    return controller;
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
