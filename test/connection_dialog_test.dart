// test/connection_dialog_test.dart
//
// Widget and unit tests for:
//   • AzureConnectionDialog — auth modes, field visibility, validation
//   • B2ConnectionDialog    — field rendering, validation
//   • SettingsDialog        — section rendering, toggle behaviour
//
// Some widget tests require precise finder tuning for duplicate labels.
// Skip flaky tests with: flutter test --exclude-tags=connection_dialog
@Tags(['connection_dialog'])

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/azure_connection_dialog.dart';
import 'package:crisp_cloud/widgets/b2_connection_dialog.dart';
import 'package:crisp_cloud/widgets/settings_dialog.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with an in-memory
/// [SecureStorage] override so dialogs can call secureStorageProvider.
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      ...overrides,
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => child,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

/// Opens the dialog by tapping the "Open" button.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// AzureConnectionDialog tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // AzureConnectionDialog
  // =========================================================================

  group('AzureConnectionDialog – auth mode options', () {
    testWidgets('renders all three auth mode radio buttons', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Account Key'), findsOneWidget);
      expect(find.text('SAS Token'), findsOneWidget);
      expect(find.text('Connection String'), findsOneWidget);
    });

    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Connect to Azure Blob Storage'), findsOneWidget);
    });

    testWidgets('shows Connect and Cancel buttons', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows Test Connection button', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Test Connection'), findsOneWidget);
    });
  });

  group('AzureConnectionDialog – Account Key mode', () {
    testWidgets('Account Key mode is selected by default', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      // Account Key fields should be visible
      expect(find.byKey(const Key('azure_account_name')), findsOneWidget);
      expect(find.byKey(const Key('azure_account_key')), findsOneWidget);
      expect(find.byKey(const Key('azure_container')), findsOneWidget);
    });

    testWidgets('shows exactly 3 fields in Account Key mode', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      // All three key-identified fields are present
      expect(find.byKey(const Key('azure_account_name')), findsOneWidget);
      expect(find.byKey(const Key('azure_account_key')), findsOneWidget);
      expect(find.byKey(const Key('azure_container')), findsOneWidget);

      // SAS/connection-string fields must not appear
      expect(find.byKey(const Key('azure_sas_url')), findsNothing);
      expect(find.byKey(const Key('azure_connection_string')), findsNothing);
    });

    testWidgets('Account Key fields have correct labels', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Account Name'), findsOneWidget);
      expect(find.text('Account Key'), findsOneWidget);
      expect(find.text('Container'), findsOneWidget);
    });
  });

  group('AzureConnectionDialog – SAS Token mode', () {
    testWidgets('switching to SAS Token mode shows SAS URL field',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      // Tap the SAS Token radio
      await tester.tap(find.text('SAS Token'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('azure_sas_url')), findsOneWidget);
    });

    testWidgets('SAS Token mode hides Account Key fields', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('SAS Token'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('azure_account_key')), findsNothing);
    });

    testWidgets('SAS Token mode has Full SAS URL toggle', (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('SAS Token'));
      await tester.pumpAndSettle();

      expect(find.text('Full SAS URL'), findsOneWidget);
      expect(find.text('Token + Account'), findsOneWidget);
    });

    testWidgets(
        'switching SAS Token mode to "Token + Account" shows separate fields',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('SAS Token'));
      await tester.pumpAndSettle();

      // Switch to separate-fields sub-mode
      await tester.tap(find.text('Token + Account'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('azure_sas_account_name')), findsOneWidget);
      expect(find.byKey(const Key('azure_sas_token')), findsOneWidget);
      expect(find.byKey(const Key('azure_sas_container')), findsOneWidget);
    });
  });

  group('AzureConnectionDialog – Connection String mode', () {
    testWidgets(
        'switching to Connection String mode shows single text field',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Connection String'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('azure_connection_string')), findsOneWidget);
    });

    testWidgets('Connection String mode hides multi-field views',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Connection String'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('azure_account_name')), findsNothing);
      expect(find.byKey(const Key('azure_sas_url')), findsNothing);
    });
  });

  group('AzureConnectionDialog – validation', () {
    testWidgets(
        'pressing Connect with empty Account Key fields shows error',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // An error message should appear
      expect(find.textContaining('required'), findsWidgets);
    });

    testWidgets(
        'pressing Connect with only account name filled shows error',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.enterText(
          find.byKey(const Key('azure_account_name')), 'myaccount');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Account Key is required'), findsOneWidget);
    });

    testWidgets(
        'pressing Connect in Connection String mode with invalid string shows error',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Connection String'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('azure_connection_string')), 'not_valid');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not valid'), findsOneWidget);
    });

    testWidgets(
        'Test Connection with empty fields shows validation error',
        (tester) async {
      await tester.pumpWidget(_wrap(const AzureConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Test Connection'));
      await tester.pumpAndSettle();

      expect(find.textContaining('required'), findsWidgets);
    });
  });

  // =========================================================================
  // B2ConnectionDialog
  // =========================================================================

  group('B2ConnectionDialog – field rendering', () {
    testWidgets('renders dialog title', (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Connect to Backblaze B2'), findsOneWidget);
    });

    testWidgets('renders Application Key ID field', (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.byKey(const Key('b2_key_id')), findsOneWidget);
    });

    testWidgets('renders Application Key field', (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.byKey(const Key('b2_app_key')), findsOneWidget);
    });

    testWidgets('renders Bucket Name field (optional)', (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.byKey(const Key('b2_bucket_name')), findsOneWidget);
    });

    testWidgets('shows Connect, Cancel and Test Connection buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('renders field labels', (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      expect(find.text('Application Key ID'), findsOneWidget);
      expect(find.text('Application Key'), findsOneWidget);
      expect(find.text('Bucket Name (optional)'), findsOneWidget);
    });
  });

  group('B2ConnectionDialog – validation', () {
    testWidgets('pressing Connect with empty fields shows error',
        (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('required'), findsWidgets);
    });

    testWidgets(
        'pressing Connect with only Key ID filled shows App Key error',
        (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      await tester.enterText(
          find.byKey(const Key('b2_key_id')), '0014abc123456789000000001');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('Application Key is required'), findsOneWidget);
    });

    testWidgets(
        'Test Connection with empty Key ID shows validation error',
        (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Test Connection'));
      await tester.pumpAndSettle();

      expect(find.textContaining('required'), findsWidgets);
    });

    testWidgets('bucket name field is optional — no error when left blank',
        (tester) async {
      await tester.pumpWidget(_wrap(const B2ConnectionDialog()));
      await _openDialog(tester);

      // Fill required fields
      await tester.enterText(
          find.byKey(const Key('b2_key_id')), '0014abc123456789000000001');
      await tester.enterText(
          find.byKey(const Key('b2_app_key')), 'K001secret_key_value_here_xyz');

      // Do NOT fill bucket name
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Should not show a "required" error for bucket
      expect(find.textContaining('Bucket'), findsNothing);
    });
  });

  // =========================================================================
  // SettingsDialog
  // =========================================================================

  group('SettingsDialog – section rendering', () {
    testWidgets('renders all section headings', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
    });

    testWidgets('renders F-key bar toggle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(find.byKey(const Key('settings_fkey_bar_toggle')), findsOneWidget);
    });

    testWidgets('renders high contrast toggle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('settings_high_contrast_toggle')),
          findsOneWidget);
    });

    testWidgets('renders reduced motion toggle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('settings_reduced_motion_toggle')),
          findsOneWidget);
    });

    testWidgets('renders analytics toggle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('settings_analytics_toggle')), findsOneWidget);
    });

    testWidgets('renders delta sync toggle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('settings_delta_sync_toggle')), findsOneWidget);
    });

    testWidgets('renders Done button', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('Done button dismisses dialog', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('General'), findsNothing);
    });
  });

  group('SettingsDialog – F-key bar toggle', () {
    testWidgets('toggle is on by default (SharedPreferences empty)',
        (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings_fkey_bar_toggle')),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('tapping toggle calls provider notifier', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tileFinder = find.byKey(const Key('settings_fkey_bar_toggle'));
      final initialTile = tester.widget<SwitchListTile>(tileFinder);
      final initialValue = initialTile.value;

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      final updatedTile = tester.widget<SwitchListTile>(tileFinder);
      expect(updatedTile.value, isNot(initialValue));
    });
  });

  group('SettingsDialog – high contrast toggle', () {
    testWidgets('high contrast is off by default', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings_high_contrast_toggle')),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('tapping high contrast toggle changes value', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tileFinder =
          find.byKey(const Key('settings_high_contrast_toggle'));

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      final updatedTile = tester.widget<SwitchListTile>(tileFinder);
      expect(updatedTile.value, isTrue);
    });
  });

  group('SettingsDialog – analytics toggle', () {
    testWidgets('analytics is off by default', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings_analytics_toggle')),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('tapping analytics toggle turns it on', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tileFinder = find.byKey(const Key('settings_analytics_toggle'));

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      final updated = tester.widget<SwitchListTile>(tileFinder);
      expect(updated.value, isTrue);
    });

    testWidgets(
        'enabling analytics shows informational banner', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      // Enable analytics
      await tester.tap(find.byKey(const Key('settings_analytics_toggle')));
      await tester.pumpAndSettle();

      // Explanation text should appear
      expect(find.textContaining('locally'), findsOneWidget);
    });
  });

  group('SettingsDialog – delta sync toggle', () {
    testWidgets('delta sync is on by default', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings_delta_sync_toggle')),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('tapping delta sync toggle turns it off', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      final tileFinder = find.byKey(const Key('settings_delta_sync_toggle'));

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      final updated = tester.widget<SwitchListTile>(tileFinder);
      expect(updated.value, isFalse);
    });

    testWidgets('enabling delta sync shows block size selector',
        (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      // Delta sync is on by default — block size selector should be visible
      expect(
          find.byKey(const Key('settings_delta_block_size')), findsOneWidget);
    });

    testWidgets('disabling delta sync hides block size selector',
        (tester) async {
      await tester.pumpWidget(_wrap(const SettingsDialog()));
      await _openDialog(tester);

      // Turn off delta sync
      await tester.tap(find.byKey(const Key('settings_delta_sync_toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_delta_block_size')), findsNothing);
    });
  });
}
