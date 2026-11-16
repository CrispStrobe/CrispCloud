import 'dart:async';

import 'package:crisp_cloud/l10n/terminal_recovery_strings.dart';
import 'package:crisp_cloud/models/terminal_workspace_recovery.dart';
import 'package:crisp_cloud/widgets/terminal_workspace_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _dialogKey = ValueKey('terminal-recovery-dialog');
const _enabledKey = ValueKey('terminal-recovery-enabled');
const _relaunchKey = ValueKey('terminal-recovery-relaunch');
const _saveKey = ValueKey('terminal-recovery-save');
const _forgetKey = ValueKey('terminal-recovery-forget');
const _confirmForgetKey = ValueKey('terminal-recovery-confirm-forget');
const _retryKey = ValueKey('terminal-recovery-retry');

void main() {
  testWidgets('recovery and shell relaunch require separate choices', (
    tester,
  ) async {
    final saves = <List<bool>>[];
    final results = await _open(
      tester,
      onSave: (enabled, relaunch) async {
        saves.add([enabled, relaunch]);
        return TerminalWorkspaceRecoveryRecord(
          enabled: enabled,
          relaunchLocalShells: relaunch,
        );
      },
    );
    expect(_toggle(tester, _enabledKey).value, isFalse);
    expect(_toggle(tester, _relaunchKey).value, isFalse);
    expect(_toggle(tester, _relaunchKey).onChanged, isNull);
    await _tap(tester, _enabledKey);
    expect(_toggle(tester, _relaunchKey).onChanged, isNotNull);
    expect(_toggle(tester, _relaunchKey).value, isFalse);
    await _tap(tester, _relaunchKey);
    await _tap(tester, _saveKey);
    expect(saves, [
      <bool>[true, true],
    ]);
    expect(results, [true]);
    expect(find.byKey(_dialogKey), findsNothing);
  });

  testWidgets('turning recovery off withdraws shell relaunch choice', (
    tester,
  ) async {
    final saves = <List<bool>>[];
    await _open(
      tester,
      initial: TerminalWorkspaceRecoveryRecord(
        enabled: true,
        relaunchLocalShells: true,
      ),
      onSave: (enabled, relaunch) async {
        saves.add([enabled, relaunch]);
        return const TerminalWorkspaceRecoveryRecord.disabled();
      },
    );
    await _tap(tester, _enabledKey);
    expect(_toggle(tester, _relaunchKey).value, isFalse);
    expect(_toggle(tester, _relaunchKey).onChanged, isNull);
    await _tap(tester, _enabledKey);
    expect(_toggle(tester, _relaunchKey).value, isFalse);
    await _tap(tester, _saveKey);
    expect(saves, [
      <bool>[true, false],
    ]);
  });

  testWidgets('canceling edited settings does not save', (tester) async {
    var saves = 0;
    final results = await _open(
      tester,
      onSave: (enabled, relaunch) async {
        saves++;
        return const TerminalWorkspaceRecoveryRecord.disabled();
      },
    );
    await _tap(tester, _enabledKey);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(results, [null]);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
      'pending save permits ${systemBack ? 'back' : 'Close'} and cannot pop a replacement route',
      (tester) async {
        final pending = Completer<TerminalWorkspaceRecoveryRecord>();
        var saves = 0;
        final results = await _open(
          tester,
          onSave: (enabled, relaunch) {
            saves++;
            return pending.future;
          },
        );
        await tester.tap(find.byKey(_saveKey));
        await tester.pump();
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        expect(_toggle(tester, _enabledKey).onChanged, isNull);
        expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
        final navigator = Navigator.of(tester.element(find.byKey(_dialogKey)));
        if (systemBack) {
          await navigator.maybePop();
        } else {
          await tester.tap(find.widgetWithText(TextButton, 'Close'));
        }
        // Complete while the old route is still animating out, rather than
        // relying only on State.mounted after the dialog has been disposed.
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Replacement page')),
            ),
          ),
        );
        pending.complete(const TerminalWorkspaceRecoveryRecord.disabled());
        await tester.pumpAndSettle();
        expect(results, [null]);
        expect(saves, 1);
        expect(find.text('Replacement page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('save failure retains edits and can be submitted again', (
    tester,
  ) async {
    var saves = 0;
    final results = await _open(
      tester,
      onSave: (enabled, relaunch) async {
        saves++;
        if (saves == 1) throw StateError('storage unavailable');
        return TerminalWorkspaceRecoveryRecord(enabled: enabled);
      },
    );
    await _tap(tester, _enabledKey);
    await _tap(tester, _saveKey);
    expect(find.text('Could not save session recovery.'), findsOneWidget);
    expect(_toggle(tester, _enabledKey).value, isTrue);
    expect(results, isEmpty);
    await _tap(tester, _saveKey);
    expect(saves, 2);
    expect(results, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable store disables writes until retry succeeds', (
    tester,
  ) async {
    var retries = 0;
    await _open(
      tester,
      initial: null,
      initialError: 'Could not load session recovery. Saved data was kept.',
      onRetry: () async {
        retries++;
        return TerminalWorkspaceRecoveryRecord(enabled: true);
      },
    );
    expect(_toggle(tester, _enabledKey).onChanged, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await _tap(tester, _retryKey);
    expect(retries, 1);
    expect(find.byKey(const ValueKey('terminal-recovery-error')), findsNothing);
    expect(_toggle(tester, _enabledKey).onChanged, isNotNull);
    expect(_toggle(tester, _enabledKey).value, isTrue);
  });

  testWidgets('failed retry keeps unreadable saved data protected', (
    tester,
  ) async {
    await _open(
      tester,
      initial: null,
      onRetry: () async => throw const FormatException('newer schema'),
    );
    await _tap(tester, _retryKey);
    expect(
      find.text('Could not load session recovery. Saved data was kept.'),
      findsOneWidget,
    );
    expect(_toggle(tester, _enabledKey).onChanged, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forget can explicitly reset unreadable data after confirmation',
    (tester) async {
      var forgets = 0;
      final results = await _open(
        tester,
        initial: null,
        onForget: () async {
          forgets++;
          return const TerminalWorkspaceRecoveryRecord.disabled();
        },
      );
      await _tap(tester, _forgetKey);
      expect(find.text('Forget saved workspace?'), findsOneWidget);
      expect(forgets, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(forgets, 0);
      await _tap(tester, _forgetKey);
      await _tap(tester, _confirmForgetKey);
      expect(forgets, 1);
      expect(results, isEmpty);
      expect(find.byKey(_dialogKey), findsOneWidget);
      expect(_toggle(tester, _enabledKey).value, isFalse);
      expect(_toggle(tester, _enabledKey).onChanged, isNotNull);
      expect(_toggle(tester, _relaunchKey).value, isFalse);
      expect(
        find.byKey(const ValueKey('terminal-recovery-error')),
        findsNothing,
      );
    },
  );

  testWidgets('failed forget preserves choices and reports the failure', (
    tester,
  ) async {
    await _open(
      tester,
      initial: TerminalWorkspaceRecoveryRecord(
        enabled: true,
        relaunchLocalShells: true,
      ),
      onForget: () async => throw StateError('write denied'),
    );
    await _tap(tester, _forgetKey);
    await _tap(tester, _confirmForgetKey);
    expect(find.text('Could not forget saved workspace.'), findsOneWidget);
    expect(_toggle(tester, _enabledKey).value, isTrue);
    expect(_toggle(tester, _relaunchKey).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'de', 'ar']) {
    testWidgets('settings remain usable at 320 by 320 in $language', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 320);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final results = await _open(tester, locale: Locale(language));
      expect(tester.takeException(), isNull);
      await _tap(tester, _enabledKey);
      await _tap(tester, _relaunchKey);
      await _tap(tester, _forgetKey);
      expect(tester.takeException(), isNull);
      await _tap(tester, _confirmForgetKey);
      expect(tester.takeException(), isNull);
      await _tap(tester, _saveKey);
      expect(results, [true]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'every recovery string has translations in all supported locales',
    (tester) async {
      const keys = [
        'Session recovery',
        'Remember terminal workspace',
        'Relaunch local shells',
        'Restore tabs, panes, names, font sizes and SSH destinations when you next open the terminal.',
        'SSH connections still ask for authentication. Passwords, terminal output and running processes are not saved.',
        'Start new local shells in the current local folder. Previous commands and working directories are not restored.',
        'Forget saved workspace',
        'Forget saved workspace?',
        'This turns off recovery and clears the saved workspace. Your current terminals stay open.',
        'Forget',
        'Retry',
        'Close',
        'Another terminal workspace is managing recovery.',
        'Loading saved workspace…',
        'Workspace recovered. Connect each SSH destination when ready.',
        'Could not load session recovery. Saved data was kept.',
        'Could not save session recovery.',
        'Could not forget saved workspace.',
        'Session recovery is paused. Retry in Session recovery.',
      ];
      for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        final values = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: [Locale(language)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) {
                values
                  ..clear()
                  ..addAll(keys.map(context.terminalRecoveryTr));
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(values, hasLength(keys.length));
        for (var index = 0; index < keys.length; index++) {
          expect(values[index], isNotEmpty);
          expect(
            values[index],
            isNot(keys[index]),
            reason: '$language ${keys[index]}',
          );
        }
      }
    },
  );
}

SwitchListTile _toggle(WidgetTester tester, Key key) =>
    tester.widget<SwitchListTile>(find.byKey(key));

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<List<bool?>> _open(
  WidgetTester tester, {
  TerminalWorkspaceRecoveryRecord? initial =
      const TerminalWorkspaceRecoveryRecord.disabled(),
  String? initialError,
  Locale locale = const Locale('en'),
  Future<TerminalWorkspaceRecoveryRecord> Function(bool, bool)? onSave,
  Future<TerminalWorkspaceRecoveryRecord> Function()? onForget,
  Future<TerminalWorkspaceRecoveryRecord> Function()? onRetry,
}) async {
  final results = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (_) => TerminalWorkspaceRecoveryDialog(
                    initialRecord: initial,
                    initialError: initialError,
                    onSave:
                        onSave ??
                        (enabled, relaunch) async =>
                            TerminalWorkspaceRecoveryRecord(
                              enabled: enabled,
                              relaunchLocalShells: relaunch,
                            ),
                    onForget:
                        onForget ??
                        () async =>
                            const TerminalWorkspaceRecoveryRecord.disabled(),
                    onRetry:
                        onRetry ??
                        () async =>
                            const TerminalWorkspaceRecoveryRecord.disabled(),
                  ),
                );
                results.add(result);
              },
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
  return results;
}
