@TestOn('vm')
library;

import 'package:crisp_cloud/l10n/ssh_forwarding_profile_strings.dart';
import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/widgets/ssh_port_forwarding_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_forwarding_profile_fixture.dart';

void main() {
  late ForwardingMemory memory;
  late SshForwardingProfiles store;
  late ProfileTestForwarding forwarding;
  late SshForwardingProfileSession profiles;
  setUp(() {
    memory = ForwardingMemory();
    store = memory.store();
    forwarding = ProfileTestForwarding();
    profiles = SshForwardingProfileSession(
      store: store,
      route: forwardingRoute(),
      forwarding: forwarding,
    );
  });
  tearDown(() {
    profiles.dispose();
    forwarding.dispose();
    store.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(900, 800),
    String language = 'en',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [
          Locale('en'),
          Locale('de'),
          Locale('fr'),
          Locale('es'),
          Locale('pt'),
          Locale('zh'),
          Locale('ja'),
          Locale('ko'),
          Locale('ar'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SshPortForwardingDialog(
                  forwarding: forwarding,
                  profiles: profiles,
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

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final owner = find.byType(AddSshPortForwardDialog).evaluate().isNotEmpty
          ? find.byType(AddSshPortForwardDialog)
          : find.byType(SshPortForwardingDialog);
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(of: owner, matching: find.byType(Scrollable))
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) =>
      tap(tester, find.byKey(const ValueKey('ssh-forward-start')));

  testWidgets(
    'new saved recipe defaults to manual and does not open a listener',
    (tester) async {
      await mount(tester);
      await tap(tester, find.byKey(const ValueKey('ssh-forward-new-profile')));
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('ssh-forward-profile-auto')),
            )
            .value,
        isFalse,
      );
      await enter(tester, 'ssh-forward-profile-name', 'Database');
      await enter(tester, 'ssh-forward-target-port', '5432');
      await save(tester);
      final profile = (await store.load()).single;
      expect(profile.name, 'Database');
      expect(profile.autoStart, isFalse);
      expect(profile.route, profiles.route);
      expect(forwarding.requests, isEmpty);
      expect(find.byType(AddSshPortForwardDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving an active listener preserves requested automatic port and avoids a duplicate',
    (tester) async {
      final listener = forwarding.seed(forwardingProfile().spec);
      await mount(tester);
      await tap(
        tester,
        find.byKey(ValueKey('ssh-forward-save-${listener.id}')),
      );
      await enter(tester, 'ssh-forward-profile-name', 'Database');
      await save(tester);
      final profile = (await store.load()).single;
      expect(profile.spec.bindPort, 0);
      expect(forwarding.forwards.single.id, listener.id);
      final start = find.byKey(
        ValueKey('ssh-forward-profile-start-${profile.id}'),
      );
      await tester.ensureVisible(start);
      expect(tester.widget<TextButton>(start).onPressed, isNull);
      final row = find.byKey(ValueKey('ssh-forward-${listener.id}'));
      await tap(tester, find.descendant(of: row, matching: find.text('Stop')));
      await tap(tester, start);
      expect(forwarding.requests.length, 1);
      expect(forwarding.forwards.single.port, isNot(listener.port));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit Auto-start opt-in is saved without starting now', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.byKey(const ValueKey('ssh-forward-new-profile')));
    await enter(tester, 'ssh-forward-profile-name', 'Database');
    await tap(tester, find.byKey(const ValueKey('ssh-forward-profile-auto')));
    await enter(tester, 'ssh-forward-target-port', '5432');
    await save(tester);
    expect((await store.load()).single.autoStart, isTrue);
    expect(forwarding.forwards, isEmpty);
    expect(find.text('Auto-start after a verified connection'), findsOneWidget);
  });

  testWidgets('editing an active recipe stops it and retains its identity', (
    tester,
  ) async {
    final profile = forwardingProfile();
    await store.save(profile);
    await profiles.start(profile.id);
    await mount(tester);
    await tap(
      tester,
      find.byKey(ValueKey('ssh-forward-profile-edit-${profile.id}')),
    );
    await enter(tester, 'ssh-forward-profile-name', 'Database next');
    await enter(tester, 'ssh-forward-target-port', '5433');
    await save(tester);
    final edited = (await store.load()).single;
    expect(edited.id, profile.id);
    expect(edited.spec.targetPort, 5433);
    expect(forwarding.forwards, isEmpty);
    expect(forwarding.requests.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Delete and stop removes the stored recipe and current listener',
    (tester) async {
      final profile = forwardingProfile();
      await store.save(profile);
      await profiles.start(profile.id);
      await mount(tester);
      await tap(
        tester,
        find.byKey(ValueKey('ssh-forward-profile-delete-${profile.id}')),
      );
      expect(await store.load(), isEmpty);
      expect(forwarding.forwards, isEmpty);
      expect(find.text('No saved forwarding profiles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('corrupt storage offers retry while retaining existing data', (
    tester,
  ) async {
    memory.raw = '{not-json';
    await mount(tester);
    final message = find.text(
      'Saved forwarding could not be loaded. Existing data was preserved.',
    );
    await tester.ensureVisible(message);
    expect(message, findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('ssh-forward-new-profile')),
          )
          .onPressed,
      isNull,
    );
    expect(memory.raw, '{not-json');
    memory.raw = null;
    await tap(tester, find.text('Retry'));
    expect(message, findsNothing);
    expect(find.text('No saved forwarding profiles'), findsOneWidget);
    expect(memory.writes, 0);
  });

  testWidgets(
    'saved startup failure remains visible when reopening the manager',
    (tester) async {
      final profile = forwardingProfile(autoStart: true);
      await store.save(profile);
      forwarding.startError = (_) => StateError('private diagnostic');
      await profiles.startAutomatic();
      await mount(tester);
      final message = find.text('Could not update forwarding profiles.');
      await reveal(tester, message);
      expect(message, findsOneWidget);
      expect(find.text('private diagnostic'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile editor and validation fit a 320 by 320 viewport', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 320));
    await tap(tester, find.byKey(const ValueKey('ssh-forward-new-profile')));
    await save(tester);
    expect(
      find.text('Enter a profile name of 1 to 80 characters.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await enter(tester, 'ssh-forward-profile-name', 'Small screen');
    await tap(tester, find.byKey(const ValueKey('ssh-forward-profile-auto')));
    await enter(tester, 'ssh-forward-target-host', 'database.internal');
    await enter(tester, 'ssh-forward-target-port', '5432');
    await save(tester);
    expect((await store.load()).single.name, 'Small screen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('German profile controls and validation use translated strings', (
    tester,
  ) async {
    await mount(tester, language: 'de', size: const Size(320, 320));
    await tap(tester, find.byKey(const ValueKey('ssh-forward-new-profile')));
    expect(find.text('Weiterleitungsprofil speichern'), findsOneWidget);
    await save(tester);
    expect(
      find.text('Profilnamen mit 1 bis 80 Zeichen eingeben.'),
      findsOneWidget,
    );
    expect(find.text('Save forwarding profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('every forwarding profile message provides all eight translations', () {
    for (final entry in sshForwardingProfileTranslations.entries) {
      expect(entry.value, hasLength(8), reason: entry.key);
      expect(
        entry.value.every((value) => value.trim().isNotEmpty),
        isTrue,
        reason: entry.key,
      );
    }
  });
}
