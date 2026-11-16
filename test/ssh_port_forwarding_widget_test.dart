@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/widgets/ssh_port_forwarding_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Optional production-widget captures use a synthetic forwarding manager. They
// document layout only; real sockets/SSH are covered by separate transport tests.
const _capture = bool.fromEnvironment('SSH_FORWARD_VISUALS');
const _visualDirectory = String.fromEnvironment(
  'SSH_FORWARD_VISUAL_DIR',
  defaultValue: 'build/ssh-forwarding-visuals',
);
const _screen = ValueKey('ssh-forward-test-screen');
const _add = ValueKey('ssh-forward-add');
const _start = ValueKey('ssh-forward-start');
const _kind = ValueKey('ssh-forward-kind');
const _bindPort = ValueKey('ssh-forward-bind-port');
const _targetHost = ValueKey('ssh-forward-target-host');
const _targetPort = ValueKey('ssh-forward-target-port');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Forwarding forwarding;

  setUpAll(() async {
    if (!_capture) return;
    final font = FontLoader('ForwardingRoboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() => forwarding = _Forwarding());
  tearDown(() => forwarding.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(800, 700),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: _capture ? 'ForwardingRoboto' : null,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff265e89)),
        ),
        builder: (context, child) =>
            RepaintBoundary(key: _screen, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      SshPortForwardingDialog(forwarding: forwarding),
                ),
                child: const Text('Open forwarding'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open forwarding'));
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester) async {
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
  }

  Future<void> chooseKind(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.byKey(_kind));
    await tester.tap(find.byKey(_kind));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Key key, String value) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.enterText(find.byKey(key), value);
    await tester.pump();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_start));
    await tester.tap(find.byKey(_start));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_screen),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_visualDirectory)
        ..createSync(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final (kind, label) in [
    (SshPortForwardKind.local, 'Local'),
    (SshPortForwardKind.remote, 'Remote'),
    (SshPortForwardKind.dynamic, 'SOCKS5'),
  ]) {
    testWidgets('$label submits its route and displays the assigned port', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text('No active forwarding'), findsOneWidget);
      await add(tester);
      if (kind != SshPortForwardKind.local) await chooseKind(tester, label);
      if (kind == SshPortForwardKind.dynamic) {
        expect(find.byKey(_targetHost), findsNothing);
        expect(find.byKey(_targetPort), findsNothing);
      } else {
        await enter(tester, _targetHost, 'database.internal');
        await enter(tester, _targetPort, '5432');
      }
      await start(tester);
      expect(forwarding.requests, hasLength(1));
      final request = forwarding.requests.single;
      expect(request.kind, kind);
      expect(request.bindHost, '127.0.0.1');
      expect(request.bindPort, 0);
      expect(
        request.targetHost,
        kind == SshPortForwardKind.dynamic ? isNull : 'database.internal',
      );
      expect(
        request.targetPort,
        kind == SshPortForwardKind.dynamic ? isNull : 5432,
      );
      expect(find.byType(AddSshPortForwardDialog), findsNothing);
      expect(find.text('127.0.0.1:41001'), findsOneWidget);
      expect(find.text('$label · Listening'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('IPv6 and a fixed listening port remain explicit', (
    tester,
  ) async {
    await mount(tester);
    await add(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('::1 (IPv6)').last);
    await tester.pumpAndSettle();
    await enter(tester, _bindPort, '9222');
    await enter(tester, _targetHost, '::1');
    await enter(tester, _targetPort, '443');
    await start(tester);
    expect(forwarding.requests.single.bindHost, '::1');
    expect(forwarding.requests.single.bindPort, 9222);
    expect(forwarding.requests.single.targetHost, '::1');
    expect(find.text('::1:9222'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid ports and empty destinations never reach the transport',
    (tester) async {
      await mount(tester);
      await add(tester);
      await enter(tester, _bindPort, '65536');
      await enter(tester, _targetHost, '   ');
      await enter(tester, _targetPort, '0');
      await start(tester);
      expect(find.text('Use a port from 0 to 65535.'), findsOneWidget);
      expect(find.text('Use a port from 1 to 65535.'), findsOneWidget);
      expect(find.text('Enter a destination host.'), findsOneWidget);
      expect(forwarding.requests, isEmpty);
      await enter(tester, _bindPort, '65535');
      await enter(tester, _targetHost, '  target.internal  ');
      await enter(tester, _targetPort, '65535');
      await start(tester);
      expect(forwarding.requests.single.targetHost, 'target.internal');
      expect(forwarding.requests.single.bindPort, 65535);
      expect(forwarding.requests.single.targetPort, 65535);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending creation cannot submit twice or dismiss its owner', (
    tester,
  ) async {
    final pending = forwarding.pendingStart = Completer<void>();
    await mount(tester);
    await add(tester);
    await enter(tester, _targetPort, '80');
    await tester.tap(find.byKey(_start));
    await tester.pumpAndSettle();
    expect(forwarding.requests, hasLength(1));
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(forwarding.requests, hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AddSshPortForwardDialog), findsNothing);
    expect(find.text('127.0.0.1:41001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disconnect disables an already open editor without reconnecting',
    (tester) async {
      await mount(tester);
      await add(tester);
      await enter(tester, _targetPort, '80');
      await forwarding.close();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AddSshPortForwardDialog),
          matching: find.text('This SSH connection has ended.'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('This SSH connection has ended.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_add)).onPressed, isNull);
      expect(forwarding.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late startup failure after disconnect stays on the ended route',
    (tester) async {
      final pending = forwarding.pendingStart = Completer<void>();
      await mount(tester);
      await add(tester);
      await enter(tester, _targetPort, '80');
      await tester.tap(find.byKey(_start));
      await tester.pump();
      await forwarding.close();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddSshPortForwardDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AddSshPortForwardDialog),
          matching: find.text('This SSH connection has ended.'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
      expect(forwarding.forwards, isEmpty);
      expect(forwarding.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a refusal remains reviewable and permits a corrected retry', (
    tester,
  ) async {
    forwarding.startError = const SshPortForwardException('Refused');
    await mount(tester);
    await add(tester);
    await enter(tester, _targetPort, '80');
    await start(tester);
    expect(
      find.text(
        'Could not start forwarding. Check the listener and destination.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AddSshPortForwardDialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(_start)).onPressed,
      isNotNull,
    );
    forwarding.startError = null;
    await enter(tester, _targetPort, '8080');
    await start(tester);
    expect(forwarding.requests, hasLength(2));
    expect(forwarding.forwards.single.spec.targetPort, 8080);
    expect(find.byType(AddSshPortForwardDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing the dialog retains listeners; Stop removes only its row',
    (tester) async {
      forwarding.seed(SshPortForwardKind.local, activeConnections: 2);
      forwarding.seed(SshPortForwardKind.dynamic);
      await mount(tester);
      expect(find.text('Connections: 2'), findsOneWidget);
      await capture(tester, 'forwarding-desktop');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(forwarding.forwards, hasLength(2));
      expect(forwarding.closeCalls, 0);
      await tester.tap(find.text('Open forwarding'));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('ssh-forward-forward-1'));
      await tester.tap(find.descendant(of: first, matching: find.text('Stop')));
      await tester.pumpAndSettle();
      expect(forwarding.stops, ['forward-1']);
      expect(forwarding.forwards.single.id, 'forward-2');
      expect(find.text('SOCKS5 · Listening'), findsOneWidget);
      expect(forwarding.closeCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending Stop is disabled and a stop failure remains visible', (
    tester,
  ) async {
    forwarding.seed(SshPortForwardKind.local);
    final pending = forwarding.pendingStop = Completer<void>();
    forwarding.stopError = const SshPortForwardException('Not confirmed');
    await mount(tester);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Stop'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(forwarding.stops, ['forward-1']);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not stop forwarding.'), findsOneWidget);
    expect(forwarding.forwards, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the listener cap includes failed rows and reopens after Stop', (
    tester,
  ) async {
    for (var i = 0; i < SshPortForwarding.maximumForwards; i++) {
      forwarding.seed(
        SshPortForwardKind.local,
        status: i == 0
            ? SshPortForwardStatus.failed
            : SshPortForwardStatus.active,
      );
    }
    await mount(tester);
    expect(tester.widget<FilledButton>(find.byKey(_add)).onPressed, isNull);
    expect(find.text('Local · Failed'), findsOneWidget);
    await tester.tap(find.text('Stop').first);
    await tester.pumpAndSettle();
    expect(forwarding.forwards, hasLength(15));
    expect(tester.widget<FilledButton>(find.byKey(_add)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote startup cleanup explains why SSH was closed', (
    tester,
  ) async {
    const reason =
        'The remote forwarding request could not be confirmed; the SSH connection was closed.';
    forwarding.startError = const SshPortForwardException(reason);
    await mount(tester);
    await add(tester);
    await enter(tester, _targetPort, '5432');
    await start(tester);
    expect(find.text(reason), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote stop cleanup preserves its actionable explanation', (
    tester,
  ) async {
    const reason =
        'The server did not confirm stopping the forward; the SSH connection was closed.';
    forwarding.seed(SshPortForwardKind.remote);
    forwarding.stopError = const SshPortForwardException(reason);
    await mount(tester);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text(reason), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager and form remain usable at 320 by 320', (tester) async {
    forwarding.seed(SshPortForwardKind.remote);
    await mount(tester, size: const Size(320, 320));
    await capture(tester, 'forwarding-narrow');
    expect(tester.takeException(), isNull);
    await add(tester);
    await capture(tester, 'forwarding-editor-narrow');
    await start(tester);
    expect(find.text('Use a port from 1 to 65535.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(_targetPort));
    await capture(tester, 'forwarding-error-narrow');
    await enter(tester, _targetHost, 'database.internal');
    await enter(tester, _targetPort, '5432');
    await start(tester);
    expect(forwarding.requests, hasLength(1));
    expect(forwarding.forwards, hasLength(2));
    expect(find.byType(AddSshPortForwardDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Forwarding extends SshPortForwarding {
  _Forwarding() : super.base();

  final List<SshPortForwardSnapshot> _forwards = [];
  final List<SshPortForwardSpec> requests = [];
  final List<String> stops = [];
  Completer<void>? pendingStart;
  Completer<void>? pendingStop;
  Object? startError;
  Object? stopError;
  int closeCalls = 0;
  bool _closed = false;
  int _serial = 0;

  @override
  bool get isClosed => _closed;
  @override
  List<SshPortForwardSnapshot> get forwards => List.unmodifiable(_forwards);

  void seed(
    SshPortForwardKind kind, {
    SshPortForwardStatus status = SshPortForwardStatus.active,
    int activeConnections = 0,
  }) {
    final spec = SshPortForwardSpec(
      kind: kind,
      targetHost: kind == SshPortForwardKind.dynamic
          ? null
          : 'database.internal',
      targetPort: kind == SshPortForwardKind.dynamic ? null : 5432,
    );
    _insert(spec, status: status, activeConnections: activeConnections);
  }

  SshPortForwardSnapshot _insert(
    SshPortForwardSpec spec, {
    SshPortForwardStatus status = SshPortForwardStatus.active,
    int activeConnections = 0,
  }) {
    final serial = ++_serial;
    final snapshot = SshPortForwardSnapshot(
      id: 'forward-$serial',
      spec: spec,
      status: status,
      port: spec.bindPort == 0 ? 41000 + serial : spec.bindPort,
      activeConnections: activeConnections,
      error: status == SshPortForwardStatus.failed
          ? 'Listener unavailable.'
          : null,
    );
    _forwards.add(snapshot);
    notifyListeners();
    return snapshot;
  }

  @override
  Future<SshPortForwardSnapshot> start(SshPortForwardSpec spec) async {
    requests.add(spec);
    await pendingStart?.future;
    if (_closed) throw const SshPortForwardException('Closed');
    if (startError != null) throw startError!;
    return _insert(spec);
  }

  @override
  Future<void> stop(String id) async {
    stops.add(id);
    await pendingStop?.future;
    if (stopError != null) throw stopError!;
    _forwards.removeWhere((entry) => entry.id == id);
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    _closed = true;
    _forwards.clear();
    notifyListeners();
  }
}
