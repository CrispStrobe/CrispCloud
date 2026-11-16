import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ssh_forwarding_profile_fixture.dart';

void main() {
  group('forwarding route and recipe', () {
    test('roundtrips all kinds and keeps requested port zero', () {
      for (final kind in SshPortForwardKind.values) {
        final original = forwardingProfile(kind: kind, autoStart: true);
        final decoded = SshForwardingProfile.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(decoded.hasSameContents(original), isTrue);
        expect(decoded.spec.bindPort, 0);
        expect(decoded.autoStart, isTrue);
      }
    });

    test(
      'captures a route without retaining top-level or jump credentials',
      () {
        final jumps = [
          const SshJumpHost(
            host: 'bastion.example',
            username: 'jump-user',
            password: 'jump-secret',
            privateKey: 'jump-private',
            passphrase: 'jump-phrase',
          ),
        ];
        final route = SshForwardingRoute.fromConfig(
          SshTerminalConfig(
            host: 'server.example',
            port: 2222,
            username: 'alice',
            authentication: SshTerminalAuthentication.privateKey,
            password: 'password-secret',
            privateKey: 'key-secret',
            passphrase: 'passphrase-secret',
            gateway: Uri.parse('wss://gateway.example/ssh'),
            jumpHosts: jumps,
          ),
        );
        jumps.clear();
        final encoded = jsonEncode(route.toJson());
        for (final text in [
          'secret',
          'private',
          'phrase',
          'password',
          'authentication',
        ]) {
          expect(encoded, isNot(contains(text)));
        }
        expect(route.jumpHosts.single.username, 'jump-user');
        expect(() => route.jumpHosts.clear(), throwsUnsupportedError);
        expect(
          SshForwardingRoute.fromJson(
            jsonDecode(encoded) as Map<String, dynamic>,
          ),
          route,
        );
      },
    );

    test(
      'exact endpoints, usernames, gateway and ordered hops identify a route',
      () {
        final hop = SshForwardingEndpoint(
          host: 'bastion',
          port: 22,
          username: 'bob',
        );
        final second = SshForwardingEndpoint(
          host: 'inner',
          port: 22,
          username: 'carol',
        );
        final route = forwardingRoute(jumpHosts: [hop, second]);
        for (final other in [
          forwardingRoute(host: 'SERVER.example', jumpHosts: [hop, second]),
          forwardingRoute(host: 'server.example.', jumpHosts: [hop, second]),
          forwardingRoute(port: 2222, jumpHosts: [hop, second]),
          forwardingRoute(username: 'ALICE', jumpHosts: [hop, second]),
          forwardingRoute(
            gateway: Uri.parse('wss://gateway.example/ssh'),
            jumpHosts: [hop, second],
          ),
          forwardingRoute(jumpHosts: [second, hop]),
          forwardingRoute(jumpHosts: [hop]),
          forwardingRoute(),
        ]) {
          expect(other, isNot(route));
        }
        expect(route, forwardingRoute(jumpHosts: [hop, second]));
        expect(
          route.hashCode,
          forwardingRoute(jumpHosts: [hop, second]).hashCode,
        );
      },
    );

    test('authentication changes do not select a different route', () {
      final first = SshForwardingRoute.fromConfig(
        const SshTerminalConfig(
          host: 'server.example',
          port: 22,
          username: 'alice',
          password: 'one',
        ),
      );
      final second = SshForwardingRoute.fromConfig(
        const SshTerminalConfig(
          host: 'server.example',
          port: 22,
          username: 'alice',
          authentication: SshTerminalAuthentication.privateKey,
          privateKey: 'two',
        ),
      );
      expect(first, second);
    });

    test('rejects unsafe routes and persisted gateway port zero', () {
      for (final gateway in [
        'https://gateway.example',
        'wss://user:secret@gateway.example',
        'wss://gateway.example/?token=secret',
        'wss://gateway.example/#secret',
      ]) {
        expect(
          () => forwardingRoute(gateway: Uri.parse(gateway)),
          throwsFormatException,
        );
      }
      expect(() => forwardingRoute(host: 'bad\nserver'), throwsFormatException);
      expect(() => forwardingRoute(port: 0), throwsFormatException);
      final raw = Map<String, dynamic>.from(forwardingRoute().toJson())
        ..['gateway'] = 'wss://gateway.example:0/ssh';
      expect(() => SshForwardingRoute.fromJson(raw), throwsFormatException);
      expect(
        () => forwardingRoute(
          jumpHosts: [
            SshForwardingEndpoint(
              host: 'SERVER.example.',
              port: 22,
              username: 'bob',
            ),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown future fields and malformed profile records', () {
      final profile = forwardingProfile();
      final raw =
          jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>;
      expect(
        () => SshForwardingProfile.fromJson({...raw, 'future': true}),
        throwsFormatException,
      );
      expect(
        () => SshForwardingProfile.fromJson({...raw, 'autoStart': 'true'}),
        throwsFormatException,
      );
      expect(
        () => SshForwardingProfile.fromJson({
          ...raw,
          'spec': {...raw['spec'] as Map<String, dynamic>, 'bindPort': 1.5},
        }),
        throwsFormatException,
      );
      for (final name in ['', ' name', 'name ', 'bad\nname', 'a' * 81]) {
        expect(() => forwardingProfile(name: name), throwsFormatException);
      }
    });
  });

  group('forwarding profile store', () {
    late ForwardingMemory memory;
    late SshForwardingProfiles store;
    setUp(() {
      memory = ForwardingMemory();
      store = memory.store();
    });
    tearDown(() => store.dispose());

    test(
      'concurrent saves reload under lock and preserve both routes',
      () async {
        final first = forwardingProfile();
        final second = forwardingProfile(
          id: 'other',
          route: forwardingRoute(host: 'other.example'),
        );
        await Future.wait([store.save(first), store.save(second)]);
        expect((await store.load()).map((profile) => profile.id), [
          'database',
          'other',
        ]);
        expect(memory.writes, 2);
      },
    );

    test('default store instances coordinate reload and writes', () async {
      SharedPreferences.setMockInitialValues({});
      final first = SshForwardingProfiles();
      final second = SshForwardingProfiles();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await Future.wait([
        first.save(forwardingProfile()),
        second.save(forwardingProfile(id: 'web', targetPort: 8080)),
      ]);
      expect((await first.load()).map((profile) => profile.id).toSet(), {
        'database',
        'web',
      });
      expect((await second.load()).length, 2);
    });

    test(
      'duplicates require both a unique name and recipe within a route',
      () async {
        await store.save(forwardingProfile());
        await expectLater(
          store.save(
            forwardingProfile(id: 'clone', name: 'DATABASE', targetPort: 80),
          ),
          throwsA(isA<SshForwardingProfileException>()),
        );
        await expectLater(
          store.save(forwardingProfile(id: 'copy')),
          throwsA(isA<SshForwardingProfileException>()),
        );
        await store.save(
          forwardingProfile(
            id: 'different-route',
            name: 'database',
            route: forwardingRoute(username: 'bob'),
          ),
        );
        expect((await store.load()).length, 2);
      },
    );

    test(
      'optimistic replacement rejects stale edits and deleted snapshots',
      () async {
        final original = forwardingProfile();
        await store.save(original);
        final updated = forwardingProfile(name: 'Renamed', autoStart: true);
        await store.save(updated, replacing: original);
        await expectLater(
          store.save(forwardingProfile(name: 'Stale'), replacing: original),
          throwsA(isA<SshForwardingProfileException>()),
        );
        await expectLater(
          store.delete(original),
          throwsA(isA<SshForwardingProfileException>()),
        );
        await store.delete(updated);
        await expectLater(
          store.save(original, replacing: updated),
          throwsA(isA<SshForwardingProfileException>()),
        );
        expect(await store.load(), isEmpty);
      },
    );

    test('cannot migrate an edited profile to a different route', () async {
      final original = forwardingProfile();
      await store.save(original);
      await expectLater(
        store.save(
          forwardingProfile(route: forwardingRoute(username: 'bob')),
          replacing: original,
        ),
        throwsA(isA<SshForwardingProfileException>()),
      );
      expect((await store.load()).single.route, original.route);
    });

    test('global and per-route limits fail before a write', () async {
      for (var i = 0; i < 16; i++) {
        await store.save(forwardingProfile(id: 'p$i', targetPort: 1000 + i));
      }
      await expectLater(
        store.save(forwardingProfile(id: 'too-many', targetPort: 2000)),
        throwsA(isA<SshForwardingProfileException>()),
      );
      expect(memory.writes, 16);
      for (var i = 16; i < 50; i++) {
        await store.save(
          forwardingProfile(
            id: 'p$i',
            route: forwardingRoute(host: 'host$i.example'),
          ),
        );
      }
      await expectLater(
        store.save(
          forwardingProfile(
            id: 'over-limit',
            route: forwardingRoute(host: 'new.example'),
          ),
        ),
        throwsA(isA<SshForwardingProfileException>()),
      );
      expect(memory.writes, 50);
    });

    test(
      'corrupt, future, oversized and duplicate stores survive every mutation',
      () async {
        final entry = forwardingProfile().toJson();
        for (final raw in [
          '{broken',
          jsonEncode({'version': 2, 'profiles': []}),
          jsonEncode({'version': 1, 'profiles': [], 'future': true}),
          jsonEncode({
            'version': 1,
            'profiles': [
              {...entry, 'future': true},
            ],
          }),
          jsonEncode({
            'version': 1,
            'profiles': [entry, entry],
          }),
          ' ' * (SshForwardingProfiles.maximumStorageLength + 1),
        ]) {
          memory.raw = raw;
          await expectLater(
            store.load(),
            throwsA(isA<SshForwardingProfileException>()),
          );
          await expectLater(
            store.save(forwardingProfile(id: 'new')),
            throwsA(isA<SshForwardingProfileException>()),
          );
          await expectLater(
            store.delete(forwardingProfile()),
            throwsA(isA<SshForwardingProfileException>()),
          );
          expect(memory.raw, raw);
          expect(memory.writes, 0);
        }
      },
    );

    test(
      'write errors do not leak storage details or replace old data',
      () async {
        await store.save(forwardingProfile());
        final before = memory.raw;
        memory.writeError = StateError('token-secret');
        await expectLater(
          store.save(forwardingProfile(id: 'new', targetPort: 80)),
          throwsA(
            isA<SshForwardingProfileException>().having(
              (error) => error.message,
              'safe message',
              'Could not save forwarding profiles.',
            ),
          ),
        );
        expect(memory.raw, before);
      },
    );
  });

  group('verified connection coordination', () {
    late ForwardingMemory memory;
    late SshForwardingProfiles store;
    late ProfileTestForwarding forwarding;
    late SshForwardingProfileSession session;
    setUp(() {
      memory = ForwardingMemory();
      store = memory.store();
      forwarding = ProfileTestForwarding();
      session = SshForwardingProfileSession(
        store: store,
        route: forwardingRoute(),
        forwarding: forwarding,
      );
    });
    tearDown(() {
      session.dispose();
      forwarding.dispose();
      store.dispose();
    });

    Future<void> tick() => Future<void>.delayed(Duration.zero);

    test(
      'starts only explicit auto-start recipes for the exact route once',
      () async {
        await store.save(forwardingProfile(autoStart: true));
        await store.save(forwardingProfile(id: 'manual', targetPort: 80));
        await store.save(
          forwardingProfile(
            id: 'other',
            route: forwardingRoute(username: 'bob'),
            autoStart: true,
          ),
        );
        await Future.wait([session.startAutomatic(), session.startAutomatic()]);
        expect(forwarding.requests.length, 1);
        expect(forwarding.forwards.single.spec.targetPort, 5432);
        expect(session.profiles.map((profile) => profile.id), [
          'database',
          'manual',
        ]);
        final duplicateCoordinator = SshForwardingProfileSession(
          store: store,
          route: forwardingRoute(),
          forwarding: forwarding,
        );
        await duplicateCoordinator.startAutomatic();
        duplicateCoordinator.dispose();
        expect(forwarding.requests.length, 1);
      },
    );

    test(
      'manual starts coalesce and adopt an equal ad-hoc port-zero listener',
      () async {
        final profile = forwardingProfile();
        await store.save(profile);
        final pending = forwarding.pendingStart = Completer<void>();
        final first = session.start(profile.id);
        final second = session.start(profile.id);
        await tick();
        expect(forwarding.requests.length, 1);
        pending.complete();
        final results = await Future.wait([first, second]);
        expect(results[0]!.id, results[1]!.id);
        await session.start(profile.id);
        expect(forwarding.requests.length, 1);
        final otherManager = ProfileTestForwarding();
        final seed = otherManager.seed(profile.spec);
        final otherSession = SshForwardingProfileSession(
          store: store,
          route: profile.route,
          forwarding: otherManager,
        );
        expect((await otherSession.start(profile.id))!.id, seed.id);
        expect(otherManager.requests, isEmpty);
        otherSession.dispose();
        otherManager.dispose();
      },
    );

    test('saving enabled profiles does not start current listeners; reconnect does', () async {
      await session.startAutomatic();
      final profile = forwardingProfile(autoStart: true);
      await session.save(profile);
      await session.startAutomatic();
      expect(forwarding.requests, isEmpty);
      final nextManager = ProfileTestForwarding();
      final nextSession = SshForwardingProfileSession(
        store: store,
        route: profile.route,
        forwarding: nextManager,
      );
      await nextSession.startAutomatic();
      expect(nextManager.requests.length, 1);
      nextSession.dispose();
      nextManager.dispose();
    });

    test(
      'Stop does not trigger another automatic start on the same connection',
      () async {
        await store.save(forwardingProfile(autoStart: true));
        await session.startAutomatic();
        await session.stop(forwarding.forwards.single.id);
        await session.startAutomatic();
        expect(forwarding.forwards, isEmpty);
        expect(forwarding.requests.length, 1);
        await session.start('database');
        expect(forwarding.requests.length, 2);
      },
    );

    test(
      'cancelled connection during storage read never opens a listener',
      () async {
        await store.save(forwardingProfile(autoStart: true));
        await session.refresh();
        final gate = memory.pendingRead = Completer<void>();
        var current = true;
        final guarded = SshForwardingProfileSession(
          store: store,
          route: forwardingRoute(),
          forwarding: forwarding,
          isCurrent: () => current,
        );
        final work = guarded.startAutomatic();
        current = false;
        gate.complete();
        await work;
        expect(forwarding.requests, isEmpty);
        guarded.dispose();
      },
    );

    test(
      'disposal closes a late start and cancels remaining auto-start work',
      () async {
        await store.save(forwardingProfile(autoStart: true));
        await store.save(
          forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
        );
        final manager = ProfileTestForwarding();
        final coordinator = SshForwardingProfileSession(
          store: store,
          route: forwardingRoute(),
          forwarding: manager,
        );
        final gate = manager.pendingStart = Completer<void>();
        final work = coordinator.startAutomatic();
        await tick();
        expect(manager.requests.length, 1);
        coordinator.dispose();
        gate.complete();
        await work;
        expect(manager.forwards, isEmpty);
        expect(manager.stops, ['listener-1']);
        expect(manager.requests.length, 1);
        manager.dispose();
      },
    );

    test(
      'automatic failure is visible, bounded and permits another recipe',
      () async {
        await store.save(forwardingProfile(autoStart: true));
        await store.save(
          forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
        );
        forwarding.startError = (spec) =>
            spec.targetPort == 5432 ? StateError('private-diagnostic') : null;
        await session.startAutomatic();
        expect(forwarding.requests.length, 2);
        expect(
          session.profileError('database'),
          'Could not update forwarding profiles.',
        );
        expect(forwarding.forwards.last.status, SshPortForwardStatus.active);
        forwarding.startError = null;
        await session.start('database');
        expect(forwarding.stops, ['listener-1']);
        expect(forwarding.forwards.length, 2);
        expect(session.profileError('database'), isNull);
      },
    );

    test(
      'invalid storage surfaces a retained error without autostart',
      () async {
        memory.raw = '{private-data';
        await session.startAutomatic();
        expect(
          session.error,
          'Saved forwarding could not be loaded. Existing data was preserved.',
        );
        expect(forwarding.requests, isEmpty);
        expect(memory.raw, '{private-data');
      },
    );

    test(
      'delete stops matching listeners across sessions and preserves others',
      () async {
        final profile = forwardingProfile();
        await store.save(profile);
        final otherManager = ProfileTestForwarding();
        final other = SshForwardingProfileSession(
          store: store,
          route: profile.route,
          forwarding: otherManager,
        );
        await session.start(profile.id);
        await other.start(profile.id);
        final untouched = forwarding.seed(
          forwardingProfile(id: 'web', targetPort: 80).spec,
        );
        await session.delete(profile);
        expect(forwarding.forwards.single.id, untouched.id);
        expect(otherManager.forwards, isEmpty);
        expect(await store.load(), isEmpty);
        other.dispose();
        otherManager.dispose();
      },
    );

    test(
      'delete cancels a pending start before removing its saved recipe',
      () async {
        final profile = forwardingProfile();
        await store.save(profile);
        final gate = forwarding.pendingStart = Completer<void>();
        final start = session.start(profile.id);
        await tick();
        final deletion = session.delete(profile);
        await tick();
        expect((jsonDecode(memory.raw!) as Map)['profiles'], hasLength(1));
        gate.complete();
        await Future.wait([start, deletion]);
        expect(forwarding.forwards, isEmpty);
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'stop failure preserves the profile and exposes the manager error',
      () async {
        final profile = forwardingProfile();
        await store.save(profile);
        await session.start(profile.id);
        forwarding.stopError = const SshPortForwardException(
          'Could not stop forwarding.',
        );
        await expectLater(
          session.delete(profile),
          throwsA(isA<SshPortForwardException>()),
        );
        expect((await store.load()).single.id, profile.id);
        expect(forwarding.forwards.length, 1);
      },
    );

    test(
      'recipe edit stops old listeners; metadata edit keeps them running',
      () async {
        final profile = forwardingProfile();
        await store.save(profile);
        await session.start(profile.id);
        final renamed = forwardingProfile(name: 'Database', autoStart: true);
        await session.save(renamed, replacing: profile);
        expect(forwarding.forwards.length, 1);
        expect(forwarding.stops, isEmpty);
        final modified = forwardingProfile(
          name: 'Database',
          autoStart: true,
          targetPort: 5433,
        );
        await session.save(modified, replacing: renamed);
        expect(forwarding.forwards, isEmpty);
        expect((await store.load()).single.spec.targetPort, 5433);
        expect(forwarding.requests.length, 1);
      },
    );

    test(
      'default stores stop listeners even when held by different providers',
      () async {
        SharedPreferences.setMockInitialValues({});
        final firstStore = SshForwardingProfiles();
        final secondStore = SshForwardingProfiles();
        final otherManager = ProfileTestForwarding();
        final profile = forwardingProfile();
        final other = SshForwardingProfileSession(
          store: secondStore,
          route: profile.route,
          forwarding: otherManager,
        );
        await firstStore.save(profile);
        await other.start(profile.id);
        await firstStore.delete(profile);
        expect(otherManager.forwards, isEmpty);
        expect(await secondStore.load(), isEmpty);
        other.dispose();
        otherManager.dispose();
        firstStore.dispose();
        secondStore.dispose();
      },
    );
  });
}
