import 'package:crisp_cloud/widgets/document_history_dialog.dart';
import 'package:crisp_cloud/services/document_history.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('history remains scrollable on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: const Scaffold(body: DocumentHistoryDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('history-purge')), findsOneWidget);
  });
  testWidgets('purge requires confirmation and clears persisted entries', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final history = container.read(documentHistoryProvider);
    await history.record(
      const FileReference(
        storage: StorageReference(
          kind: 'local',
          provider: 'local',
          accountKey: 'local',
        ),
        path: '/notes.txt',
      ),
      edited: true,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DocumentHistoryDialog())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-purge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(history.entries, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('history-purge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purge list…').last);
    await tester.pumpAndSettle();
    expect(history.entries, isEmpty);
    final restarted = DocumentHistory();
    await restarted.ready;
    expect(restarted.entries, isEmpty);
    restarted.dispose();
  });
}
