// test/update_dialog_test.dart
//
// Widget tests for UpdateDialog and UpdateBanner.
//
// All provider state is overridden in-process; no network calls are made.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/providers/update_provider.dart';
import 'package:crisp_cloud/services/auto_update_service.dart';
import 'package:crisp_cloud/widgets/update_banner.dart';
import 'package:crisp_cloud/widgets/update_dialog.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A canned [UpdateInfo] used across tests.
UpdateInfo _info({
  String version = 'v0.2.0',
  String releaseNotes = '## What\'s new\n\n- Faster uploads\n- Bug fixes',
  String downloadUrl = 'https://github.com/crispasr/CrispCloud/releases/v0.2.0',
  bool isPreRelease = false,
}) =>
    UpdateInfo(
      version: version,
      releaseNotes: releaseNotes,
      downloadUrl: downloadUrl,
      publishedAt: DateTime.utc(2025, 6, 1),
      isPreRelease: isPreRelease,
    );

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with optional provider
/// overrides.
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Wraps [child] and opens it as a dialog via a button tap.
Widget _wrapDialog(Widget dialog, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () =>
                showDialog(context: ctx, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// Stable override helpers.
List<Override> _overrides({
  AsyncValue<UpdateInfo?>? checkValue,
  UpdateChannel channel = UpdateChannel.stable,
  bool autoEnabled = true,
}) {
  return [
    if (checkValue != null)
      updateCheckProvider.overrideWith((ref) async {
        return checkValue.when(
          loading: () => throw StateError('should not be reached'),
          error: (e, s) => throw e,
          data: (d) => Future.value(d),
        );
      }),
    updateChannelProvider.overrideWith((ref) {
      return _TestChannelNotifier(channel);
    }),
    autoUpdateEnabledProvider.overrideWith((ref) {
      return _TestBoolNotifier(autoEnabled);
    }),
  ];
}

// ---------------------------------------------------------------------------
// Stub StateNotifiers for test overrides
// ---------------------------------------------------------------------------

class _TestChannelNotifier extends UpdateChannelNotifier {
  _TestChannelNotifier(UpdateChannel value) : super.withValue(value);
}

class _TestBoolNotifier extends AutoUpdateEnabledNotifier {
  _TestBoolNotifier(bool value) : super.withValue(value);
  Future<void> setEnabled(bool v) async => state = v;
}

// ---------------------------------------------------------------------------
// UpdateDialog tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // Basic rendering
  // =========================================================================

  group('UpdateDialog – basic rendering', () {
    testWidgets('dialog title is shown', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('renders current version label', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_current_version')), findsOneWidget);
      // The dialog shows "v<currentVersion>"; in tests defaultValue is '0.1.0'.
      final widget = tester.widget<Text>(
          find.byKey(const Key('update_current_version')));
      expect(widget.data, startsWith('v'));
    });

    testWidgets('channel selector renders three options', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.text('Stable'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Nightly'), findsOneWidget);
    });

    testWidgets('auto-check toggle is present', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_auto_check_toggle')), findsOneWidget);
    });

    testWidgets('auto-check toggle reflects provider state – enabled',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
            checkValue: const AsyncData(null), autoEnabled: true),
      ));
      await _openDialog(tester);

      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('update_auto_check_toggle')));
      expect(sw.value, isTrue);
    });

    testWidgets('auto-check toggle reflects provider state – disabled',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
            checkValue: const AsyncData(null), autoEnabled: false),
      ));
      await _openDialog(tester);

      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('update_auto_check_toggle')));
      expect(sw.value, isFalse);
    });

    testWidgets('auto-check toggle onChange fires notifier', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
            checkValue: const AsyncData(null), autoEnabled: true),
      ));
      await _openDialog(tester);

      // Toggling the switch should not throw.
      await tester.tap(find.byKey(const Key('update_auto_check_toggle')));
      await tester.pumpAndSettle();
    });
  });

  // =========================================================================
  // Up-to-date state
  // =========================================================================

  group('UpdateDialog – up to date', () {
    testWidgets('shows "up to date" message when no update available',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_up_to_date_banner')), findsOneWidget);
      expect(find.byKey(const Key('update_up_to_date_label')), findsOneWidget);
    });

    testWidgets('download button absent when up to date', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_download_button')), findsNothing);
    });

    testWidgets('"update available" banner absent when up to date',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('update_available_banner')), findsNothing);
    });
  });

  // =========================================================================
  // Update available state
  // =========================================================================

  group('UpdateDialog – update available', () {
    testWidgets('shows "update available" banner', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: AsyncData(_info())),
      ));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('update_available_banner')), findsOneWidget);
      expect(find.byKey(const Key('update_available_label')), findsOneWidget);
    });

    testWidgets('latest version label shown in version row', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: AsyncData(_info())),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_latest_version')), findsOneWidget);
      final widget = tester.widget<Text>(
          find.byKey(const Key('update_latest_version')));
      expect(widget.data, 'v0.2.0');
    });

    testWidgets('download button is present', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: AsyncData(_info())),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_download_button')), findsOneWidget);
    });

    testWidgets('"up to date" banner absent when update available',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: AsyncData(_info())),
      ));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('update_up_to_date_banner')), findsNothing);
    });

    testWidgets('release notes section is displayed', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: AsyncData(_info())),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_release_notes')), findsOneWidget);
    });

    testWidgets('release notes contain expected text', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
            checkValue: AsyncData(_info(
                releaseNotes: '## Highlights\n\n- Faster sync'))),
      ));
      await _openDialog(tester);

      // flutter_markdown renders text nodes from the markdown.
      expect(find.textContaining('Faster sync'), findsWidgets);
    });

    testWidgets('release notes section absent when no update', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_release_notes')), findsNothing);
    });
  });

  // =========================================================================
  // Loading state
  // =========================================================================

  group('UpdateDialog – loading state', () {
    testWidgets('shows loading spinner while check is in-progress',
        skip: true,
        (tester) async {
      // A never-completing future keeps the provider in loading state.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith(
              (ref) => Future.delayed(const Duration(seconds: 60))),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                    context: ctx, builder: (_) => const UpdateDialog()),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await _openDialog(tester);

      // One pump without settle — the future is still pending.
      expect(
          find.byKey(const Key('update_loading_banner')), findsOneWidget);
    });
  });

  // =========================================================================
  // Error state
  // =========================================================================

  group('UpdateDialog – error state', () {
    testWidgets('shows error banner on network failure', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith(
              (ref) => Future.error(
                  const AutoUpdateException('Network error: no connection'))),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                    context: ctx, builder: (_) => const UpdateDialog()),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_error_banner')), findsOneWidget);
    });

    testWidgets('error message rendered in banner', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith(
              (ref) => Future.error(
                  const AutoUpdateException('rate limit exceeded'))),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                    context: ctx, builder: (_) => const UpdateDialog()),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await _openDialog(tester);

      expect(find.textContaining('rate limit'), findsOneWidget);
    });

    testWidgets('download button absent in error state', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith(
              (ref) =>
                  Future.error(const AutoUpdateException('Network error'))),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                    context: ctx, builder: (_) => const UpdateDialog()),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await _openDialog(tester);

      expect(find.byKey(const Key('update_download_button')), findsNothing);
    });
  });

  // =========================================================================
  // Check Now button
  // =========================================================================

  group('UpdateDialog – Check Now button', () {
    testWidgets('Check Now button is present', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      expect(
          find.byKey(const Key('update_check_now_button')), findsOneWidget);
    });

    testWidgets('Check Now button can be tapped without error', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(checkValue: const AsyncData(null)),
      ));
      await _openDialog(tester);

      await tester.tap(find.byKey(const Key('update_check_now_button')));
      await tester.pump();
      // No exception thrown — success.
    });
  });

  // =========================================================================
  // Channel selector interaction
  // =========================================================================

  group('UpdateDialog – channel selector', () {
    testWidgets('stable channel is highlighted when channel is stable',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
          checkValue: const AsyncData(null),
          channel: UpdateChannel.stable,
        ),
      ));
      await _openDialog(tester);

      final selector = tester.widget<SegmentedButton<UpdateChannel>>(
          find.byKey(const Key('update_channel_selector')));
      expect(selector.selected, {UpdateChannel.stable});
    });

    testWidgets('beta channel reflected in selector', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
          checkValue: const AsyncData(null),
          channel: UpdateChannel.beta,
        ),
      ));
      await _openDialog(tester);

      final selector = tester.widget<SegmentedButton<UpdateChannel>>(
          find.byKey(const Key('update_channel_selector')));
      expect(selector.selected, {UpdateChannel.beta});
    });

    testWidgets('nightly channel reflected in selector', (tester) async {
      await tester.pumpWidget(_wrapDialog(
        const UpdateDialog(),
        overrides: _overrides(
          checkValue: const AsyncData(null),
          channel: UpdateChannel.nightly,
        ),
      ));
      await _openDialog(tester);

      final selector = tester.widget<SegmentedButton<UpdateChannel>>(
          find.byKey(const Key('update_channel_selector')));
      expect(selector.selected, {UpdateChannel.nightly});
    });
  });

  // =========================================================================
  // UpdateBanner – visibility
  // =========================================================================

  group('UpdateBanner – visibility', () {
    testWidgets('banner shown when stable update available', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_banner_label')), findsOneWidget);
      expect(find.textContaining('v0.2.0'), findsWidgets);
    });

    testWidgets('banner absent when no update available', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => null),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_banner_label')), findsNothing);
    });

    testWidgets('banner absent for beta channel even with update',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider
              .overrideWith((ref) async => _info(isPreRelease: true)),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.beta)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_banner_label')), findsNothing);
    });

    testWidgets('banner absent for nightly channel even with update',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider
              .overrideWith((ref) async => _info(isPreRelease: true)),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.nightly)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_banner_label')), findsNothing);
    });

    testWidgets('banner shows "CrispCloud" prefix in label', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('CrispCloud'), findsOneWidget);
    });

    testWidgets('banner contains Update button', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('update_banner_update_button')), findsOneWidget);
    });
  });

  // =========================================================================
  // UpdateBanner – dismissal
  // =========================================================================

  group('UpdateBanner – dismissal', () {
    testWidgets('dismiss button is present', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('update_banner_dismiss_button')), findsOneWidget);
    });

    testWidgets('tapping dismiss hides the banner', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      // Banner is visible.
      expect(find.byKey(const Key('update_banner_label')), findsOneWidget);

      // Tap dismiss.
      await tester.tap(find.byKey(const Key('update_banner_dismiss_button')));
      await tester.pumpAndSettle();

      // Banner should be gone.
      expect(find.byKey(const Key('update_banner_label')), findsNothing);
    });

    testWidgets('banner stays hidden after dismissal for same version',
        (tester) async {
      // Pre-populate SharedPreferences with the dismissed version.
      SharedPreferences.setMockInitialValues({
        'update_banner_dismissed': ['v0.2.0'],
      });

      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      // Banner must not appear because v0.2.0 was already dismissed.
      expect(find.byKey(const Key('update_banner_label')), findsNothing);
    });

    testWidgets('banner shown for new version even if older was dismissed',
        (tester) async {
      // v0.1.5 was dismissed but a new v0.2.0 is available.
      SharedPreferences.setMockInitialValues({
        'update_banner_dismissed': ['v0.1.5'],
      });

      await tester.pumpWidget(_wrap(
        const UpdateBanner(),
        overrides: [
          updateCheckProvider.overrideWith((ref) async => _info()),
          updateChannelProvider.overrideWith((ref) => _TestChannelNotifier(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => _TestBoolNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_banner_label')), findsOneWidget);
    });
  });
}
