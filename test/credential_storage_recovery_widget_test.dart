import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/services/credential_storage_bootstrap.dart';
import 'package:crisp_cloud/services/credential_storage_recovery.dart';
import 'package:crisp_cloud/widgets/credential_storage_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unavailable default storage offers Retry without a replacement chooser',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupFailureApp(
          error: const CredentialStorageUnavailable(),
          onRetry: () => retries++,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Restore access or unlock it'),
        findsOneWidget,
      );
      expect(find.text('Restore keychain access'), findsNothing);
      expect(find.text('Change credential storage'), findsNothing);
      expect(find.byType(CredentialStorageSetupPanel), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    },
  );

  testWidgets(
    'custom keychain repair explains that the original store is required',
    (tester) async {
      var repairs = 0;
      await tester.pumpWidget(
        StartupFailureApp(
          error: const CredentialStorageUnavailable(),
          onRetry: () {},
          onRestoreStorageAccess: () => repairs++,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Select the original keychain file'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Your storage choice and App Lock remain unchanged',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Restore keychain access'));
      await tester.pumpAndSettle();
      expect(repairs, 1);
      expect(find.byType(CredentialStorageSetupPanel), findsNothing);
      expect(find.text('This session only'), findsNothing);
      expect(find.text('Create vault'), findsNothing);
    },
  );

  testWidgets('storage recovery follows the supported startup locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupFailureApp(
        error: const CredentialStorageRecoveryException(
          CredentialStorageRecoveryFailure.selectionChanged,
        ),
        locale: const Locale('de'),
        onRetry: () {},
        onRestoreStorageAccess: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('während der Wiederherstellung'),
      findsOneWidget,
    );
    expect(find.text('Schlüsselbundzugriff wiederherstellen'), findsOneWidget);
    expect(find.textContaining('Credential storage changed'), findsNothing);
    expect(find.textContaining('akzeptieren'), findsNothing);
  });
}
