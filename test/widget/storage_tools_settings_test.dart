import 'package:crisp_cloud/widgets/storage_tools_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'CLI discovery explains both commands and complete-bundle installation',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StorageToolsSettings())),
        ),
      );
      await tester.tap(find.text('Command-line tools'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('crispcloud is the main command'),
        findsOneWidget,
      );
      expect(find.textContaining('complete CLI bundle'), findsOneWidget);
      expect(find.text('Copy command'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Restore metadata from sidecar'), findsOneWidget);
    },
  );
}
