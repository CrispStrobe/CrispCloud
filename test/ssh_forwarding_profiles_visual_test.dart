@TestOn('vm')
library;

// Opt-in captures of the production forwarding manager and profile editor.
// The listener fixture establishes layout and lifecycle labels, not socket or
// native-device acceptance. Enable with SSH_FORWARDING_PROFILE_VISUALS=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/widgets/ssh_port_forwarding_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_forwarding_profile_fixture.dart';

const _enabled = bool.fromEnvironment('SSH_FORWARDING_PROFILE_VISUALS');
const _directory = String.fromEnvironment(
  'SSH_FORWARDING_PROFILE_VISUAL_DIR',
  defaultValue: 'build/ssh-forwarding-profile-visuals',
);
const _screen = ValueKey('ssh-forwarding-profile-visual-screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SshForwardingProfiles store;
  late ProfileTestForwarding forwarding;
  late SshForwardingProfileSession profiles;
  late SshForwardingProfile profile;

  setUpAll(() async {
    if (!_enabled) return;
    await (FontLoader(
      'ForwardingRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    store = ForwardingMemory().store();
    forwarding = ProfileTestForwarding();
    profile = forwardingProfile(
      name: 'Development database',
      route: forwardingRoute(
        host: 'build.example.net',
        username: 'developer',
        jumpHosts: [
          SshForwardingEndpoint(
            host: 'bastion.example.net',
            port: 22,
            username: 'developer',
          ),
        ],
      ),
      targetHost: 'db.internal',
      autoStart: true,
    );
    await store.save(profile);
    profiles = SshForwardingProfileSession(
      store: store,
      route: profile.route,
      forwarding: forwarding,
    );
    await profiles.startAutomatic();
  });
  tearDown(() {
    profiles.dispose();
    forwarding.dispose();
    store.dispose();
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'ForwardingRoboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff265e89)),
        ),
        builder: (context, child) =>
            RepaintBoundary(key: _screen, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SshPortForwardingDialog(
                    forwarding: forwarding,
                    profiles: profiles,
                  ),
                ),
                child: const Text('Manage saved forwarding'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage saved forwarding'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(
              of: find.byType(SshPortForwardingDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

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

  for (final (label, size) in [
    ('desktop', const Size(900, 900)),
    ('narrow', const Size(320, 320)),
  ]) {
    testWidgets('saved forwarding manager on $label viewport', (tester) async {
      await mount(tester, size);
      await reveal(tester, find.text(profile.name));
      await capture(tester, 'forwarding-profiles-manager-$label');
    }, skip: !_enabled);

    testWidgets('saved forwarding editor on $label viewport', (tester) async {
      await mount(tester, size);
      final edit = find.byKey(
        ValueKey('ssh-forward-profile-edit-${profile.id}'),
      );
      await reveal(tester, edit);
      expect(edit.hitTestable(), findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final autoStart = find.byKey(const ValueKey('ssh-forward-profile-auto'));
      expect(tester.widget<SwitchListTile>(autoStart).value, isTrue);
      if (label == 'narrow') await reveal(tester, autoStart);
      await capture(tester, 'forwarding-profiles-editor-$label');
    }, skip: !_enabled);
  }
}
