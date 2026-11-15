import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/archive_integrity_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/veracrypt_unlock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/veracrypt_container_fixture.dart';

Future<void> _viewer(WidgetTester tester) async {
  final bytes = veraCryptContainerFixture();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InternalViewerDialog(
          file: FileItem(
            name: 'independent.tc',
            isFolder: false,
            size: bytes.length,
          ),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(VeraCryptUnlockDialog), findsOneWidget);
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (ready()) {
      // The decrypted listing/new retry prompt can arrive before the prior
      // credential route has finished its outgoing animation.
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    ready(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((e) => e.data)
        .join(' | '),
  );
}

Future<void> _unlock(WidgetTester tester, String password) async {
  await tester.enterText(
    find.byKey(const ValueKey('veracrypt-password')),
    password,
  );
  await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'F3 unlocks independent TrueCrypt FAT and previews a real member',
    (tester) async {
      await _viewer(tester);
      expect(find.byKey(const ValueKey('veracrypt-pim')), findsNothing);
      await _unlock(tester, veraCryptFixturePassword);
      await _waitFor(
        tester,
        () => find.text('HELLO.TXT').evaluate().isNotEmpty,
      );
      expect(find.text('DOCS/NOTE.TXT'), findsOneWidget);
      expect(find.byType(VeraCryptUnlockDialog), findsNothing);
      await tester.tap(find.text('DOCS/NOTE.TXT'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nested encrypted file.', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(InternalViewerDialog), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wrong credentials can be retried without retaining the password',
    (tester) async {
      await _viewer(tester);
      await _unlock(tester, 'wrong-password');
      await _waitFor(
        tester,
        () => find
            .textContaining('credentials were rejected')
            .evaluate()
            .isNotEmpty,
      );
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('veracrypt-password')),
      );
      expect(input.controller!.text, isEmpty);
      expect(find.textContaining('credentials were rejected'), findsOneWidget);
      await _unlock(tester, veraCryptFixturePassword);
      await _waitFor(
        tester,
        () => find.text('HELLO.TXT').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Lock closes the key owner; reopening requests credentials again',
    (tester) async {
      await _viewer(tester);
      await _unlock(tester, veraCryptFixturePassword);
      await _waitFor(
        tester,
        () => find.text('HELLO.TXT').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('test-archive')));
      await tester.pumpAndSettle();
      final archive = tester
          .widget<ArchiveIntegrityDialog>(find.byType(ArchiveIntegrityDialog))
          .archive;
      expect(archive.isClosed, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('veracrypt-lock')));
      await tester.pumpAndSettle();
      expect(archive.isClosed, isTrue);
      expect(find.text('HELLO.TXT'), findsNothing);
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Archive'),
      );
      chip.onSelected!(true);
      await tester.pumpAndSettle();
      expect(find.byType(VeraCryptUnlockDialog), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('veracrypt-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled unlock stays locked and offers an explicit retry', (
    tester,
  ) async {
    await _viewer(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('HELLO.TXT'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('veracrypt-retry')));
    await tester.pumpAndSettle();
    expect(find.byType(VeraCryptUnlockDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
