import 'package:crisp_cloud/providers/notification_provider.dart';
import 'package:crisp_cloud/widgets/app_scaffold_messenger.dart';
import 'package:crisp_cloud/widgets/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Undo notification closes at 30 seconds and stays in history', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var undone = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: AppScaffoldMessenger(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Folder created'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => undone = true,
                    ),
                  ),
                ),
                child: const Text('Create'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.showCloseIcon, isTrue);
    expect(bar.persist, isFalse);
    expect(bar.duration, const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Folder created'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Folder created'), findsNothing);
    expect(undone, isFalse);
    expect(
      container.read(notificationHistoryProvider).single.message,
      'Folder created',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(undone, isFalse);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
  });

  testWidgets(
    'manual dismissal and disabled history are configurable; history can be purged',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(notificationSettingsProvider.notifier)
          .update(seconds: 0);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (_, child) => AppScaffoldMessenger(child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  const NotificationSettingsPanel(),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Saved'))),
                      child: const Text('Notify'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isTrue);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-history-open')));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('notification-history-clear')),
      );
      await tester.pumpAndSettle();
      expect(container.read(notificationHistoryProvider), isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('notification-history-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      expect(container.read(notificationHistoryProvider), isEmpty);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    },
  );

  test('settings persist and history stays bounded and session-only', () async {
    final first = NotificationSettingsNotifier();
    await first.update(
      seconds: 10,
      keepHistory: false,
      hideFinishedQueue: false,
    );
    first.dispose();
    final restored = NotificationSettingsNotifier();
    await Future<void>.delayed(Duration.zero);
    expect(restored.state.seconds, 10);
    expect(restored.state.keepHistory, isFalse);
    expect(restored.state.hideFinishedQueue, isFalse);
    restored.dispose();
    final history = NotificationHistory();
    for (var i = 0; i < 250; i++) {
      history.add('Message $i');
    }
    expect(history.state.length, 200);
    expect(history.state.first.message, 'Message 249');
    history.clear();
    expect(history.state, isEmpty);
    history.dispose();
  });
}
