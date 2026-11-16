@TestOn('vm')
library;

// Opt-in production-widget captures. Recovery uses an in-memory preference
// record and disconnected sessions; this establishes layout and disclosure,
// not native shell, SSH, tmux-server or packaged-platform acceptance.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/providers/terminal_workspace_recovery_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/terminal_workspace_recovery.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:crisp_cloud/widgets/terminal_workspace_recovery_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('TERMINAL_RECOVERY_VISUALS');
const _directory = String.fromEnvironment(
  'TERMINAL_RECOVERY_VISUAL_DIR',
  defaultValue: 'build/recovery-visuals',
);
const _screen = ValueKey('terminal-recovery-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await (FontLoader(
      'RecoveryRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'AppMono',
    )..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_screen),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_directory)..createSync(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('terminal-layout')));
    await tester.pumpAndSettle();
    final settings = find.text('Session recovery').last;
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.byType(TerminalWorkspaceRecoveryDialog), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('terminal-recovery-enabled')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('terminal-recovery-relaunch')),
          )
          .value,
      isFalse,
    );
  }

  testWidgets(
    'capture recovered workspace and settings at desktop and compact sizes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      final snapshot = TerminalArrangement(
        name: 'Recovered workspace',
        tabs: [
          TerminalArrangementTab(
            name: 'Local work',
            paneState: TerminalPaneState(fontSize: 14),
          ),
          TerminalArrangementTab(
            name: 'Build server',
            paneState: TerminalPaneState(
              fontSize: 15,
              sshConfig: const SshTerminalConfig(
                host: 'build.example.net',
                port: 22,
                username: 'developer',
                tmux: TmuxSessionOptions(
                  sessionName: 'crispcloud',
                  mode: TmuxSessionMode.attach,
                  controlMode: true,
                ),
                jumpHosts: [
                  SshJumpHost(
                    host: 'bastion.example.net',
                    username: 'developer',
                  ),
                ],
              ),
            ),
          ),
          TerminalArrangementTab(name: 'Review'),
        ],
        activeIndex: 1,
        layout: TerminalPaneSplit(
          axis: TerminalSplitAxis.horizontal,
          fraction: 0.56,
          first: TerminalPaneLeaf(0),
          second: TerminalPaneSplit(
            axis: TerminalSplitAxis.vertical,
            fraction: 0.5,
            first: TerminalPaneLeaf(1),
            second: TerminalPaneLeaf(2),
          ),
        ),
      );
      String? raw = jsonEncode(
        TerminalWorkspaceRecoveryRecord(
          enabled: true,
          snapshot: snapshot,
          savedAt: DateTime.utc(2026, 11, 16),
        ).toJson(),
      );
      final recovery = TerminalWorkspaceRecovery(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      final sessions = <TerminalSession>[];
      final providers = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
          terminalWorkspaceRecoveryProvider.overrideWithValue(recovery),
        ],
      );
      providers.read(showTerminalProvider.notifier).state = true;
      providers.read(terminalHeightProvider.notifier).state = 540;
      providers.read(focusAreaProvider.notifier).state = FocusArea.terminal;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() {
        for (final session in sessions) {
          session.dispose();
        }
        providers.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'RecoveryRoboto',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff265e89),
              ),
            ),
            builder: (context, child) =>
                RepaintBoundary(key: _screen, child: child!),
            home: Scaffold(
              body: TerminalTabs(
                sessionFactory: () {
                  final session = TerminalSession();
                  sessions.add(session);
                  return session;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panels = tester
          .widgetList<TerminalPanel>(
            find.byType(TerminalPanel, skipOffstage: false),
          )
          .toList();
      expect(panels, hasLength(3));
      expect(panels.where((panel) => panel.visible), hasLength(3));
      expect(panels.every((panel) => !panel.autoStart), isTrue);
      expect(
        panels.every(
          (panel) => panel.session!.status == TerminalSessionStatus.idle,
        ),
        isTrue,
      );
      expect(panels[1].active, isTrue);
      expect(panels[1].initialPaneState!.sshConfig!.tmux!.controlMode, isTrue);
      await capture(tester, 'recovered-workspace-desktop');
      await openSettings(tester);
      await capture(tester, 'recovery-settings-desktop');
      await tester.tap(find.byKey(const ValueKey('terminal-recovery-close')));
      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(320, 320);
      await tester.pumpAndSettle();
      await openSettings(tester);
      await capture(tester, 'recovery-settings-compact-top');
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('terminal-recovery-enabled'))),
        alignment: 0,
      );
      await capture(tester, 'recovery-settings-compact-choices');
      await tester.ensureVisible(
        find.byKey(const ValueKey('terminal-recovery-forget')),
      );
      await capture(tester, 'recovery-settings-compact-bottom');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('terminal-recovery-save')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('terminal-recovery-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
    skip: !_enabled,
  );
}
