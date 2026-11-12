import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/command_entry_strings.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/widgets/command_entry_dialog.dart';
import 'package:crisp_cloud/widgets/custom_command_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/command_entry_fixture.dart';

class _ObservedEntryService extends CommandEntryService {
  _ObservedEntryService({required super.host, required super.processStarter});
  RunningToolbarCommand? running;

  @override
  Future<RunningToolbarCommand> start(
    PreparedCommandEntry review, {
    required bool Function() isReviewCurrent,
  }) async =>
      running = await super.start(review, isReviewCurrent: isReviewCurrent);
}

void main() {
  late CommandEntryTestHost host;
  late CustomToolbarCommandService commands;
  late KeyboardShortcutService shortcuts;
  late _ObservedEntryService service;
  CommandEntryTestProcess? process;
  late CommandEntryContext captured;
  var launches = 0;
  List<String>? launchedArguments;
  const selectedPath = '/work/café " \$(touch nope); {FILE}.txt';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    host = CommandEntryTestHost();
    host.identities[selectedPath] = commandIdentity(selectedPath);
    commands = CustomToolbarCommandService();
    shortcuts = KeyboardShortcutService();
    process = null;
    launches = 0;
    launchedArguments = null;
    service = _ObservedEntryService(
      host: host,
      processStarter: (exe, args, cwd) async {
        launches++;
        launchedArguments = args;
        expect(exe, '/bin/tool');
        expect(cwd, '/work');
        return process ??= CommandEntryTestProcess();
      },
    );
    captured = commandContext(selected: [selectedPath]);
  });
  tearDown(() {
    captured.dispose();
    commands.dispose();
    process?.finish();
  });

  Future<void> mount(
    WidgetTester tester, {
    String language = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CommandEntryDialog(
                  captured: captured,
                  service: service,
                  commands: commands,
                  shortcuts: shortcuts,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder field(String name) => find.byKey(ValueKey('command-entry-$name'));
  TextEditingController argumentController(WidgetTester tester) =>
      tester.widget<TextField>(field('arguments')).controller!;

  Future<void> review(WidgetTester tester) async {
    await tester.enterText(field('executable'), 'tool');
    await tester.ensureVisible(field('review'));
    await tester.tap(field('review'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandRunDialog), findsOneWidget);
    expect(launches, 0);
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('entry and review do not launch until the existing Run button', (
    tester,
  ) async {
    await mount(tester);
    expect(launches, 0);
    await tester.enterText(field('arguments'), '-- {NAME}');
    await tester.ensureVisible(field('insertCommandPath'));
    await tester.tap(field('insertCommandPath'));
    await tester.pump();
    expect(parseCommandEntryArguments(argumentController(tester).text), [
      '--',
      '{NAME}',
      selectedPath,
    ]);
    await review(tester);
    final dialog = tester.widget<CommandRunDialog>(
      find.byType(CommandRunDialog),
    );
    expect(dialog.prepared.executable, '/bin/tool');
    expect(dialog.prepared.arguments, ['--', '{NAME}', selectedPath]);
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump();
    expect(launches, 1);
    expect(launchedArguments, ['--', '{NAME}', selectedPath]);
    expect(service.running, isNotNull);
    final run = service.running!;
    CommandExecutionResult? result;
    var exitObserved = false, stdoutDone = false, stderrDone = false;
    unawaited(run.completed.then((value) => result = value));
    unawaited(process!.exit.future.then((_) => exitObserved = true));
    unawaited(process!.out.done.then((_) => stdoutDone = true));
    unawaited(process!.err.done.then((_) => stderrDone = true));
    process!.out.add('completed'.codeUnits);
    process!.finish();
    for (var tick = 0; tick < 20 && result == null; tick++) {
      // Dart's cancel future for an already-closed stream belongs to Zone.root.
      // Drain its cleanup continuation, then the widget-zone result listener.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(
      result,
      isNotNull,
      reason:
          'exit=$exitObserved stdout=$stdoutDone stderr=$stderrDone '
          'running=${run.isRunning} output=${run.output}',
    );
    expect(result!.exitCode, 0);
    expect(result!.cancelled, isFalse);
    expect(result!.output, 'completed');
    await tester.pumpAndSettle();
    expect(find.text('Exit code: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a review retains draft text and launches nothing', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(field('arguments'), '"draft with spaces"');
    await review(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(CommandRunDialog),
        matching: find.widgetWithText(TextButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommandRunDialog), findsNothing);
    expect(argumentController(tester).text, '"draft with spaces"');
    expect(launches, 0);
  });

  testWidgets(
    'default insertion keys replace whole tokens and preserve caret',
    (tester) async {
      await mount(tester);
      await tester.enterText(field('arguments'), '-- "old name" after');
      argumentController(tester).selection = const TextSelection.collapsed(
        offset: 7,
      );
      await chord(tester, LogicalKeyboardKey.enter);
      expect(parseCommandEntryArguments(argumentController(tester).text), [
        '--',
        'café " \$(touch nope); {FILE}.txt',
        'after',
      ]);
      argumentController(tester).selection = TextSelection.collapsed(
        offset: argumentController(tester).text.length,
      );
      await chord(tester, LogicalKeyboardKey.enter, shift: true);
      expect(
        parseCommandEntryArguments(argumentController(tester).text).last,
        selectedPath,
      );
      expect(launches, 0);
      expect(find.byType(CommandRunDialog), findsNothing);
    },
  );

  testWidgets('custom insertion binding suppresses old key and held repeats', (
    tester,
  ) async {
    await tester.runAsync(
      () => shortcuts.setBinding(
        ShortcutAction.insertCommandFilename,
        const ShortcutBinding(key: 'F9'),
      ),
    );
    await mount(tester);
    await tester.tap(field('arguments'));
    await chord(tester, LogicalKeyboardKey.enter);
    expect(argumentController(tester).text, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(parseCommandEntryArguments(argumentController(tester).text), [
      'café " \$(touch nope); {FILE}.txt',
    ]);
    expect(find.text('F9'), findsOneWidget);
    expect(launches, 0);
  });

  testWidgets('saved program appends typed args and opens its normal review', (
    tester,
  ) async {
    await tester.runAsync(
      () => commands.addCommand(
        const CustomToolbarCommand(
          id: 'saved',
          label: 'Saved tool',
          executable: 'tool',
          arguments: ['{NAME}'],
        ),
      ),
    );
    await mount(tester);
    await tester.tap(field('program-choice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved tool').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('executable')).readOnly, isTrue);
    await tester.enterText(field('arguments'), '{NAME}');
    await tester.ensureVisible(field('review'));
    await tester.tap(field('review'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<CommandRunDialog>(
      find.byType(CommandRunDialog),
    );
    expect(dialog.prepared.arguments, [
      'café " \$(touch nope); {FILE}.txt',
      '{NAME}',
    ]);
    expect(launches, 0);
  });

  testWidgets(
    'closing during preparation cannot open a review or process later',
    (tester) async {
      final gate = Completer<void>();
      host.beforeInspect = (_) => gate.future;
      await mount(tester);
      await tester.enterText(field('executable'), 'tool');
      await tester.tap(field('review'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CommandRunDialog), findsNothing);
      expect(find.byType(CommandEntryDialog), findsNothing);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel during final validation leaves no process launched', (
    tester,
  ) async {
    await mount(tester);
    await review(tester);
    final gate = Completer<void>();
    host.beforeInspect = (_) => gate.future;
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(CommandRunDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect(launches, 0);
    expect(find.widgetWithText(FilledButton, 'Run'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('executable replacement after review prevents Run', (
    tester,
  ) async {
    await mount(tester);
    await review(tester);
    host.identities['/bin/tool'] = commandIdentity('/bin/tool', version: 2);
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();
    expect(
      find.text(const CommandEntryStrings.forLanguage('en').text('changed')),
      findsOneWidget,
    );
    expect(launches, 0);
  });

  for (final language in ['de', 'ar']) {
    testWidgets(
      'narrow enlarged $language entry and review fit without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, language: language, scale: 1.8);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(field('executable'));
        await tester.enterText(field('executable'), 'tool');
        await tester.ensureVisible(field('arguments'));
        await tester.enterText(
          field('arguments'),
          encodeCommandEntryArgument(selectedPath),
        );
        await tester.ensureVisible(field('review'));
        await tester.tap(field('review'));
        await tester.pumpAndSettle();
        expect(find.byType(CommandRunDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(launches, 0);
      },
    );
  }

  testWidgets(
    'existing review rejects changed prepared arguments before start',
    (tester) async {
      final mutable = ['before'];
      final command = CustomToolbarCommand(
        id: 'old',
        label: 'Old',
        executable: '/bin/tool',
        arguments: mutable,
      );
      final legacyService = CustomToolbarCommandService(
        processStarter: (_, _, _) async {
          launches++;
          return process ??= CommandEntryTestProcess();
        },
      );
      addTearDown(legacyService.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CommandRunDialog(
              command: command,
              captured: captured.invocation,
              prepared: legacyService.prepare(command, captured.invocation),
              service: legacyService,
            ),
          ),
        ),
      );
      mutable[0] = 'after';
      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();
      expect(launches, 0);
      expect(
        find.text(const CommandEntryStrings.forLanguage('en').text('changed')),
        findsOneWidget,
      );
    },
  );
}
