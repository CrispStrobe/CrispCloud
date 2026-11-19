import 'dart:async';

import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _start = ValueKey('terminal-start-session');
const _destination = SshTerminalConfig(
  host: 'build.example.net',
  port: 2222,
  username: 'developer',
  password: 'must not be reused',
  tmux: TmuxSessionOptions(
    sessionName: 'work',
    mode: TmuxSessionMode.attach,
    controlMode: true,
  ),
  jumpHosts: [
    SshJumpHost(
      host: 'bastion.example.net',
      username: 'developer',
      password: 'must not be reused either',
    ),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<_PanelFixture> mount(
    WidgetTester tester, {
    TerminalPaneState? state,
    bool autoStart = false,
    bool visible = true,
    Size size = const Size(800, 600),
    Locale locale = const Locale('en'),
    TargetPlatform platform = TargetPlatform.linux,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final fixture = _PanelFixture();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.providers,
        child: MaterialApp(
          locale: locale,
          supportedLocales: [locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: TerminalPanel(
              session: fixture.session,
              embedded: true,
              autoStart: autoStart,
              visible: visible,
              initialPaneState: state,
              onActivate: () => fixture.activations++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  Future<void> disconnect(WidgetTester tester, _PanelFixture fixture) async {
    final closing = fixture.session.disconnect();
    await tester.pumpAndSettle();
    await closing;
  }

  Future<void> unmount(WidgetTester tester, _PanelFixture fixture) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await disconnect(tester, fixture);
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('idle local pane starts only through its explicit action', (
    tester,
  ) async {
    final fixture = await mount(tester);
    expect(fixture.session.starts, 0);
    expect(fixture.localSourceReads, 0);
    expect(find.text('Ready to start a session.'), findsOneWidget);
    expect(
      find.text(kIsWeb ? 'Start built-in shell' : 'Start local shell'),
      findsOneWidget,
    );
    expect(find.textContaining('Starting the built-in'), findsNothing);
    fixture.providers.read(focusAreaProvider.notifier).state = FocusArea.local;
    await tester.pump();
    await tester.tap(find.byKey(_start));
    await tester.pumpAndSettle();
    expect(fixture.session.starts, 1);
    expect(fixture.localSourceReads, 2);
    expect(fixture.activations, greaterThan(0));
    expect(fixture.session.kind, TerminalSessionKind.local);
    expect(fixture.session.isConnected, isTrue);
    expect(fixture.providers.read(focusAreaProvider), FocusArea.terminal);
    expect(find.byKey(_start), findsNothing);
    fixture.session.terminal.write('retained output\r\n');
    await disconnect(tester, fixture);
    expect(fixture.session.status, TerminalSessionStatus.disconnected);
    expect(find.text('Ready to start a session.'), findsNothing);
    expect(find.byKey(_start), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester, fixture);
  });

  testWidgets(
    'idle SSH action opens ordinary authentication without connecting',
    (tester) async {
      final fixture = await mount(
        tester,
        state: TerminalPaneState(sshConfig: _destination),
      );
      expect(fixture.session.starts, 0);
      expect(find.text('Reconnect SSH'), findsOneWidget);
      expect(find.text('developer@build.example.net:2222'), findsOneWidget);
      expect(find.text('Local shell'), findsNothing);
      await tester.tap(find.byKey(_start));
      await tester.pumpAndSettle();
      final dialog = tester.widget<SshTerminalConnectDialog>(
        find.byType(SshTerminalConnectDialog),
      );
      expect(dialog.initialConfig!.host, _destination.host);
      expect(dialog.initialConfig!.port, _destination.port);
      expect(dialog.initialConfig!.username, _destination.username);
      expect(dialog.initialConfig!.password, isEmpty);
      expect(dialog.initialConfig!.jumpHosts.single.password, isEmpty);
      expect(dialog.initialConfig!.tmux!.controlMode, isTrue);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('terminal-ssh-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(fixture.session.starts, 0);
      expect(fixture.localSourceReads, 0);
      expect(fixture.session.status, TerminalSessionStatus.idle);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.byKey(_start), findsOneWidget);
      expect(fixture.session.starts, 0);
      expect(tester.takeException(), isNull);
      await unmount(tester, fixture);
    },
  );

  for (final remote in [false, true]) {
    testWidgets(
      'idle ${remote ? 'SSH' : 'local'} action fits a 160-pixel mobile pane',
      (tester) async {
        final fixture = await mount(
          tester,
          state: remote ? TerminalPaneState(sshConfig: _destination) : null,
          size: const Size(160, 320),
          locale: const Locale('de'),
          platform: TargetPlatform.android,
        );
        expect(find.text('Bereit, eine Sitzung zu starten.'), findsOneWidget);
        expect(find.textContaining('wird gestartet'), findsNothing);
        expect(find.byKey(_start).hitTestable(), findsOneWidget);
        final actionBounds = tester.getRect(find.byKey(_start));
        expect(actionBounds.left, greaterThanOrEqualTo(0));
        expect(actionBounds.right, lessThanOrEqualTo(160));
        expect(fixture.session.starts, 0);
        if (!remote) {
          await tester.tap(find.byKey(_start));
          await tester.pumpAndSettle();
          expect(fixture.session.starts, 1);
          expect(find.byKey(_start), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await unmount(tester, fixture);
      },
    );
  }

  testWidgets('autostart keeps the existing start flow without idle actions', (
    tester,
  ) async {
    final fixture = await mount(tester, autoStart: true);
    expect(fixture.session.starts, 1);
    expect(fixture.session.isConnected, isTrue);
    expect(find.byKey(_start), findsNothing);
    expect(find.text('Ready to start a session.'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester, fixture);
  });

  testWidgets('hidden idle pane cannot start from the readiness action', (
    tester,
  ) async {
    final fixture = await mount(tester, visible: false);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    expect(fixture.session.starts, 0);
    expect(tester.takeException(), isNull);
    await unmount(tester, fixture);
  });
}

class _PanelFixture {
  final session = _Session();
  int localSourceReads = 0;
  int activations = 0;
  late final providers = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      panelProvider.overrideWith((ref, side) {
        localSourceReads++;
        throw StateError('No folder is selected in this fixture');
      }),
    ],
  );

  void dispose() {
    session.dispose();
    providers.dispose();
  }
}

class _Session extends TerminalSession {
  int starts = 0;

  @override
  Future<void> connect(
    TerminalConnectionFactory open, {
    required TerminalSessionKind kind,
    String? label,
    TerminalCloseable? openingCleanup,
  }) {
    starts++;
    // Preserve session transitions while substituting only the native backend.
    return super.connect(
      (_, __) async => _Connection(),
      kind: kind,
      label: label,
      openingCleanup: openingCleanup,
    );
  }
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>(onCancel: () async {});
  final _exit = Completer<int?>();

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_output.isClosed) await _output.close();
  }
}
