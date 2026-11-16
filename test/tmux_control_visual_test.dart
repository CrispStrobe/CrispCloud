// Opt-in production-widget captures with in-memory pane connections, not
// end-to-end SSH acceptance. Run with --dart-define=TMUX_CONTROL_VISUALS=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_key_bindings_provider.dart';
import 'package:crisp_cloud/providers/terminal_triggers_provider.dart';
import 'package:crisp_cloud/widgets/tmux_control_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tmux_control_workspace_fixture.dart';

const _capture = bool.fromEnvironment('TMUX_CONTROL_VISUALS');
const _directory = String.fromEnvironment(
  'TMUX_CONTROL_VISUAL_DIR',
  defaultValue: 'build/tmux-control-visuals',
);
const _screen = ValueKey('tmux-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_capture) return;
    for (final family in ['StoreRoboto', 'Roboto']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      await loader.load();
    }
    await (FontLoader(
      'AppMono',
    )..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
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

  testWidgets('capture native tmux workspace at desktop and compact sizes', (
    tester,
  ) async {
    final client = TmuxWorkspaceFixture();
    await client.initialize();
    final providers = ProviderContainer(
      overrides: [
        terminalKeyBindingListProvider.overrideWith((ref) async => []),
        terminalTriggerListProvider.overrideWith((ref) async => []),
      ],
    );
    providers.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    client.panes['%1']!.session.terminal.write(
      '\x1b[36mdeveloper@build\x1b[0m \x1b[34m~/crispcloud\x1b[0m\r\n'
      '\$ flutter test\r\n'
      '\x1b[32m+42: All tests passed!\x1b[0m\r\n'
      '\r\n\$ ',
    );
    client.panes['%2']!.session.terminal.write(
      '\x1b[33mBuild output\x1b[0m\r\n'
      '08:42:10  Connecting to builder\r\n'
      '08:42:11  Workspace is ready\r\n'
      '08:42:12  Watching for changes\r\n'
      '\x1b[32m✓\x1b[0m Unicode: café 中文\r\n',
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: RepaintBoundary(
          key: _screen,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'StoreRoboto',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff265e89),
              ),
            ),
            home: Scaffold(body: TmuxControlWorkspace(client: client)),
          ),
        ),
      ),
    );
    await tester.pump();
    await capture(tester, 'tmux-native-desktop');
    await tester.tap(find.byKey(const ValueKey('tmux-action-zoom')));
    await capture(tester, 'tmux-native-zoom');
    await tester.tap(find.byKey(const ValueKey('tmux-action-zoom')));
    tester.view.physicalSize = const Size(320, 320);
    await tester.pump();
    await capture(tester, 'tmux-native-compact');
    await tester.tap(find.byKey(const ValueKey('tmux-pane-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Pane %2'), findsOneWidget);
    await capture(tester, 'tmux-native-pane-picker');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    client.dispose();
    providers.dispose();
  }, skip: !_capture);
}
