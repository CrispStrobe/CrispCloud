import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/widgets/custom_command_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child, {String locale = 'en', double scale = 1}) =>
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

class _Process extends Fake implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exit = Completer<int>();
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish(143);
    return true;
  }

  void finish(int code) {
    out.close();
    err.close();
    if (!exit.isCompleted) exit.complete(code);
  }
}

class _Service extends CustomToolbarCommandService {
  _Service({super.processStarter});
  RunningToolbarCommand? running;
  @override
  Future<RunningToolbarCommand> start(
    CustomToolbarCommand command,
    CommandInvocationContext context, {
    int maxOutputBytes = 256 * 1024,
  }) async {
    return running = await super.start(
      command,
      context,
      maxOutputBytes: maxOutputBytes,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('editor saves executable and literal argument lines', (
    tester,
  ) async {
    CustomToolbarCommand? saved;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<CustomToolbarCommand>(
                context: context,
                builder: (_) => const CustomCommandEditor(),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'My tool');
    await tester.enterText(
      find.widgetWithText(TextField, 'Executable'),
      '/tools/my tool',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Arguments (one per line)'),
      '--\n{SELECTED}\nquoted "text"',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.executable, '/tools/my tool');
    expect(saved!.arguments, ['--', '{SELECTED}', 'quoted "text"']);
    final service = CustomToolbarCommandService();
    await service.addCommand(saved!);
    final restored = CustomToolbarCommandService();
    await restored.load();
    expect(restored.commands.single.arguments, saved!.arguments);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'legacy command remains visible and cannot save without conversion',
    (tester) async {
      await tester.pumpWidget(
        app(
          const CustomCommandEditor(
            command: CustomToolbarCommand(
              id: 'legacy',
              label: 'Legacy',
              command: 'echo {SELECTED} | sort',
            ),
          ),
        ),
      );
      expect(find.text('echo {SELECTED} | sort'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Executable'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException:'), findsOneWidget);
    },
  );
  for (final language in ['de', 'ar']) {
    testWidgets(
      'command manager and editor fit narrow large-text $language screens',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = CustomToolbarCommandService();
        await service.addCommand(
          const CustomToolbarCommand(
            id: 'test',
            label: 'A local tool',
            executable: '/tools/run',
            arguments: ['{SELECTED}'],
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              customToolbarCommandServiceProvider.overrideWith((_) => service),
            ],
            child: app(
              const CustomCommandsDialog(side: PanelSide.local),
              locale: language,
              scale: 1.8,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('A local tool'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('A local tool'));
        await tester.pumpAndSettle();
        expect(find.byType(CustomCommandEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'reviewed command requires Run and shows captured process outcome',
    (tester) async {
      var launches = 0;
      final process = _Process();
      final service = _Service(
        processStarter: (exe, args, cwd) async {
          launches++;
          expect(args, ['/work/name " \$(id)']);
          return process;
        },
      );
      const command = CustomToolbarCommand(
        id: 'x',
        label: 'Tool',
        executable: '/tool',
        arguments: ['{SELECTED}'],
      );
      final captured = CommandInvocationContext(
        storage: const StorageReference(
          kind: 'local',
          provider: 'local',
          accountKey: 'test',
        ),
        currentPath: '/work',
        selectedPaths: ['/work/name " \$(id)'],
        isCurrent: () => true,
      );
      await tester.pumpWidget(
        app(
          CommandRunDialog(
            command: command,
            captured: captured,
            prepared: service.prepare(command, captured),
            service: service,
          ),
        ),
      );
      expect(launches, 0);
      expect(find.text('/work/name " \$(id)'), findsOneWidget);
      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(launches, 1);
      process.out.add('completed'.codeUnits);
      process.finish(0);
      await tester.runAsync(() => service.running!.completed);
      await tester.pumpAndSettle();
      expect(find.text('completed'), findsOneWidget);
      expect(find.text('Exit code: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
