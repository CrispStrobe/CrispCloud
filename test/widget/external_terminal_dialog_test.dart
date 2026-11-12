import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/external_terminal_strings.dart';
import 'package:crisp_cloud/services/external_terminal_service.dart';
import 'package:crisp_cloud/widgets/external_terminal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_terminal_fixture.dart';

void main() {
  late TerminalHostFixture host;
  late ExternalTerminalDirectory directory;
  var current = true;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    host = TerminalHostFixture();
    current = true;
    directory = ExternalTerminalDirectory(
      path: '/files/α & "quoted"',
      isCurrent: () => current,
      hasExistingAccess: () async => true,
    );
  });

  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    bool noDirectory = false,
    bool narrow = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(340, 820)
        : const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Show'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ExternalTerminalDialog(
                  service: ExternalTerminalService(host: host),
                  directory: noDirectory ? null : directory,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('external-terminal-executable')),
      '/tools/terminal',
    );
    await tester.enterText(
      find.byKey(const ValueKey('external-terminal-arguments')),
      '--directory\n{directory}\nliteral "quoted value"',
    );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('preferences and opening the review never start a process', (
    tester,
  ) async {
    await open(tester);
    expect(host.launches, isEmpty);
    expect(host.checkedDirectories, isEmpty);
    await fill(tester);
    await tap(tester, 'Save');
    expect(find.byType(ExternalTerminalDialog), findsNothing);
    expect(host.launches, isEmpty);
    final saved = await ExternalTerminalStore('linux').load();
    expect(saved!.arguments, [
      '--directory',
      '{directory}',
      'literal "quoted value"',
    ]);
  });
  testWidgets(
    'explicit save and open passes the captured folder as one argument',
    (tester) async {
      await open(tester);
      await fill(tester);
      expect(find.text(directory.path), findsOneWidget);
      await tap(tester, 'Save and open');
      expect(host.launches.single.arguments, [
        '--directory',
        directory.path,
        'literal "quoted value"',
      ]);
      expect(host.launches.single.directory, directory.path);
      expect(find.byType(ExternalTerminalDialog), findsNothing);
    },
  );
  testWidgets(
    'without a local capture preferences are editable but launch stays disabled',
    (tester) async {
      await open(tester, noDirectory: true);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save and open'),
            )
            .onPressed,
        isNull,
      );
      await fill(tester);
      await tap(tester, 'Save');
      expect(host.launches, isEmpty);
      expect(await ExternalTerminalStore('linux').load(), isNotNull);
    },
  );
  testWidgets(
    'missing executable stays in review and reset clears the saved preference',
    (tester) async {
      host.executableExists = false;
      await open(tester);
      await fill(tester);
      await tap(tester, 'Save and open');
      expect(find.byType(ExternalTerminalDialog), findsOneWidget);
      expect(
        find.text(
          const ExternalTerminalStrings.forLanguage('en')
              .text('executableUnavailable'),
        ),
        findsOneWidget,
      );
      expect(host.launches, isEmpty);
      await tap(tester, 'Reset');
      expect(await ExternalTerminalStore('linux').load(), isNull);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('external-terminal-executable')),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets('view change during preflight blocks the reviewed launch', (
    tester,
  ) async {
    host.executableGate = Completer<void>();
    await open(tester);
    await fill(tester);
    await tester.tap(find.text('Save and open'));
    await tester.pumpAndSettle();
    expect(host.checkedExecutables, ['/tools/terminal']);
    current = false;
    host.executableGate!.complete();
    await tester.pumpAndSettle();
    expect(host.launches, isEmpty);
    expect(
      find.text(const ExternalTerminalStrings.forLanguage('en').text('changed')),
      findsOneWidget,
    );
  });
  testWidgets('forced disposal cancels pending launch preparation', (
    tester,
  ) async {
    host.executableGate = Completer<void>();
    await open(tester);
    await fill(tester);
    await tester.tap(find.text('Save and open'));
    await tester.pumpAndSettle();
    expect(host.checkedExecutables, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    host.executableGate!.complete();
    await tester.pumpAndSettle();
    expect(host.launches, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['de', 'ar']) {
    testWidgets('review fits a narrow enlarged $language layout', (
      tester,
    ) async {
      await open(tester, language: language, narrow: true);
      await fill(tester);
      final label = ExternalTerminalStrings.forLanguage(language).text('save');
      await tap(tester, label);
      expect(host.launches, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
