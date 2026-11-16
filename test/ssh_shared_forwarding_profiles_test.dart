import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_forwarding_profile_fixture.dart';

void main() {
  late ForwardingMemory memory;
  late SshForwardingProfiles store;
  late ProfileTestForwarding forwarding;
  late List<SshForwardingProfileSession> sessions;

  SshForwardingProfileSession owner({
    ProfileTestForwarding? manager,
    bool Function()? isCurrent,
  }) {
    final session = SshForwardingProfileSession(
      store: store,
      route: forwardingRoute(),
      forwarding: manager ?? forwarding,
      isCurrent: isCurrent,
    );
    sessions.add(session);
    return session;
  }

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  setUp(() {
    memory = ForwardingMemory();
    store = memory.store();
    forwarding = ProfileTestForwarding();
    sessions = [];
  });
  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    forwarding.dispose();
    store.dispose();
  });

  test('automatic read survives the originating view closing', () async {
    await store.save(forwardingProfile(autoStart: true));
    final source = owner();
    final sibling = owner();
    final read = memory.pendingRead = Completer<void>();
    final original = source.startAutomatic();
    final adopted = sibling.startAutomatic();
    source.dispose();
    read.complete();
    await Future.wait([original, adopted]);
    expect(forwarding.requests, hasLength(1));
    expect(forwarding.forwards.single.status, SshPortForwardStatus.active);
    expect(sibling.profiles.single.id, 'database');
    expect(forwarding.stops, isEmpty);
  });

  test(
    'late automatic listeners and remaining recipes move to sibling',
    () async {
      await store.save(forwardingProfile(autoStart: true));
      await store.save(
        forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
      );
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final original = source.startAutomatic();
      await tick();
      expect(forwarding.requests, hasLength(1));
      final adopted = sibling.startAutomatic();
      source.dispose();
      opening.complete();
      await Future.wait([original, adopted]);
      expect(forwarding.requests, hasLength(2));
      expect(forwarding.forwards, hasLength(2));
      expect(forwarding.stops, isEmpty);
    },
  );

  test(
    'sibling resumes abandoned initial snapshot without adding newer recipes',
    () async {
      await store.save(forwardingProfile(autoStart: true));
      final source = owner();
      final read = memory.pendingRead = Completer<void>();
      final original = source.startAutomatic();
      source.dispose();
      read.complete();
      await original;
      expect(forwarding.requests, isEmpty);
      await store.save(
        forwardingProfile(id: 'later', targetPort: 80, autoStart: true),
      );
      final sibling = owner();
      await sibling.startAutomatic();
      expect(forwarding.requests, hasLength(1));
      expect(forwarding.forwards.single.spec.targetPort, 5432);
      await sibling.startAutomatic();
      expect(forwarding.requests, hasLength(1));
    },
  );

  test(
    'concurrent manual starts coalesce and survive one caller closing',
    () async {
      await store.save(forwardingProfile());
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final first = source.start('database');
      final second = sibling.start('database');
      expect(identical(first, second), isTrue);
      await tick();
      expect(forwarding.requests, hasLength(1));
      expect(source.isStarting('database'), isTrue);
      expect(sibling.isStarting('database'), isTrue);
      source.dispose();
      opening.complete();
      final listeners = await Future.wait([first, second]);
      expect(listeners[0]!.id, listeners[1]!.id);
      expect(forwarding.stops, isEmpty);
      expect(sibling.isStarting('database'), isFalse);
    },
  );

  test('published sibling retains a late explicit manual listener', () async {
    await store.save(forwardingProfile());
    final source = owner();
    final sibling = owner();
    await sibling.startAutomatic();
    final opening = forwarding.pendingStart = Completer<void>();
    final started = source.start('database');
    await tick();
    source.dispose();
    opening.complete();
    expect(await started, isNotNull);
    expect(forwarding.forwards, hasLength(1));
    expect(forwarding.stops, isEmpty);
  });

  test(
    'Stop from sibling revokes pending startup and suppresses automatic retry',
    () async {
      await store.save(forwardingProfile(autoStart: true));
      await store.save(
        forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
      );
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final automatic = source.startAutomatic();
      await tick();
      final adopted = sibling.startAutomatic();
      var stopped = false;
      final stopping = sibling.stop(forwarding.forwards.single.id).then((_) {
        stopped = true;
      });
      await tick();
      expect(stopped, isFalse);
      source.dispose();
      opening.complete();
      await Future.wait([automatic, adopted, stopping]);
      expect(forwarding.forwards.single.spec.targetPort, 80);
      expect(forwarding.requests, hasLength(2));
      await sibling.startAutomatic();
      expect(forwarding.requests, hasLength(2));
      await sibling.start('database');
      expect(forwarding.requests, hasLength(3));
    },
  );

  test(
    'sibling deletion waits for disposed source startup and cleanup',
    () async {
      final profile = forwardingProfile();
      await store.save(profile);
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final closing = forwarding.pendingStop = Completer<void>();
      final started = source.start(profile.id);
      await tick();
      source.dispose();
      var deleted = false;
      final deletion = sibling.delete(profile).then((_) => deleted = true);
      await tick();
      expect(deleted, isFalse);
      opening.complete();
      await tick();
      expect(deleted, isFalse);
      expect((jsonDecode(memory.raw!) as Map)['profiles'], hasLength(1));
      closing.complete();
      await Future.wait([started, deletion]);
      expect(forwarding.forwards, isEmpty);
      expect(await store.load(), isEmpty);
    },
  );

  test(
    'store deletion retains cleanup ownership after every view disposes',
    () async {
      final profile = forwardingProfile();
      await store.save(profile);
      final source = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final closing = forwarding.pendingStop = Completer<void>();
      final started = source.start(profile.id);
      await tick();
      source.dispose();
      var deleted = false;
      final deletion = store.delete(profile).then((_) => deleted = true);
      await tick();
      expect(deleted, isFalse);
      opening.complete();
      await tick();
      expect(deleted, isFalse);
      closing.complete();
      await Future.wait([started, deletion]);
      expect(forwarding.forwards, isEmpty);
      expect(await store.load(), isEmpty);
    },
  );

  test(
    'cleanup failure after source disposal preserves saved recipe',
    () async {
      final profile = forwardingProfile();
      await store.save(profile);
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final started = source.start(profile.id);
      final failedStart = expectLater(started, throwsA(isA<StateError>()));
      await tick();
      source.dispose();
      forwarding.stopError = StateError('cleanup refused');
      final deletion = sibling.delete(profile);
      final failedDelete = expectLater(deletion, throwsA(isA<StateError>()));
      opening.complete();
      await Future.wait([failedStart, failedDelete]);
      expect((await store.load()).single.id, profile.id);
      expect(forwarding.forwards, hasLength(1));
      forwarding.stopError = null;
      await sibling.delete(profile);
      expect(forwarding.forwards, isEmpty);
      expect(await store.load(), isEmpty);
    },
  );

  test(
    'editing pending recipe stops old listener without automatic restart',
    () async {
      final profile = forwardingProfile(autoStart: true);
      await store.save(profile);
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final original = source.startAutomatic();
      await tick();
      final adopted = sibling.startAutomatic();
      source.dispose();
      final changed = forwardingProfile(autoStart: true, targetPort: 80);
      final editing = sibling.save(changed, replacing: profile);
      await tick();
      opening.complete();
      await Future.wait([original, adopted, editing]);
      expect(forwarding.forwards, isEmpty);
      expect((await store.load()).single.spec.targetPort, 80);
      await sibling.startAutomatic();
      expect(forwarding.requests, hasLength(1));
      await sibling.start(profile.id);
      expect(forwarding.forwards.single.spec.targetPort, 80);
    },
  );

  test('failure is shared and a sibling can explicitly retry it', () async {
    final profile = forwardingProfile(autoStart: true);
    await store.save(profile);
    final source = owner();
    final sibling = owner();
    forwarding.startError = (_) => StateError('private detail');
    await source.startAutomatic();
    expect(
      sibling.profileError(profile.id),
      'Could not update forwarding profiles.',
    );
    source.dispose();
    await sibling.startAutomatic();
    expect(forwarding.requests, hasLength(1));
    forwarding.startError = null;
    await sibling.start(profile.id);
    expect(sibling.profileError(profile.id), isNull);
    expect(forwarding.requests, hasLength(2));
  });

  test(
    'unrelated verified manager cannot retain a cancelled pending listener',
    () async {
      await store.save(forwardingProfile(autoStart: true));
      var current = true;
      final source = owner(isCurrent: () => current);
      final separate = ProfileTestForwarding();
      addTearDown(separate.dispose);
      final other = owner(manager: separate);
      final opening = forwarding.pendingStart = Completer<void>();
      final first = source.startAutomatic();
      await tick();
      current = false;
      await other.startAutomatic();
      opening.complete();
      await first;
      expect(forwarding.forwards, isEmpty);
      expect(separate.forwards, hasLength(1));
    },
  );

  test(
    'closing shared manager revokes late starts for every current owner',
    () async {
      await store.save(forwardingProfile(autoStart: true));
      final source = owner();
      final sibling = owner();
      final opening = forwarding.pendingStart = Completer<void>();
      final original = source.startAutomatic();
      final adopted = sibling.startAutomatic();
      await tick();
      await forwarding.close();
      opening.complete();
      await Future.wait([original, adopted]);
      expect(forwarding.forwards, isEmpty);
      expect(forwarding.requests, hasLength(1));
      expect(await sibling.start('database'), isNull);
    },
  );

  test('Stop before profile IDs load suppresses only the matching automatic recipe', () async {
    final profile = forwardingProfile(autoStart: true);
    await store.save(profile);
    await store.save(
      forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
    );
    final existing = forwarding.seed(profile.spec);
    final source = owner();
    final sibling = owner();
    final read = memory.pendingRead = Completer<void>();
    final original = source.startAutomatic();
    final adopted = sibling.startAutomatic();
    expect(source.profiles, isEmpty);
    expect(sibling.profiles, isEmpty);
    await sibling.stop(existing.id);
    read.complete();
    await Future.wait([original, adopted]);
    expect(forwarding.requests, hasLength(1));
    expect(forwarding.forwards.single.spec.targetPort, 80);
    await sibling.startAutomatic();
    expect(forwarding.requests, hasLength(1));
  });

  test(
    'manual authority survives an automatic request joining its pending read',
    () async {
      store.dispose();
      final enabled = forwardingProfile(autoStart: true);
      final disabled = forwardingProfile(autoStart: false);
      final firstRead = Completer<void>();
      final secondRead = Completer<void>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      var reads = 0;
      store = SshForwardingProfiles(
        read: () async {
          switch (++reads) {
            case 1:
              firstStarted.complete();
              await firstRead.future;
              return jsonEncode({
                'version': 1,
                'profiles': [enabled.toJson()],
              });
            case 2:
              secondStarted.complete();
              await secondRead.future;
          }
          return jsonEncode({
            'version': 1,
            'profiles': [disabled.toJson()],
          });
        },
        write: (_) async {},
      );
      final automaticOwner = owner();
      final manualOwner = owner();
      final automatic = automaticOwner.startAutomatic();
      await firstStarted.future;
      final manual = manualOwner.start(enabled.id);
      firstRead.complete();
      await secondStarted.future;
      secondRead.complete();
      expect(await manual, isNotNull);
      await automatic;
      expect(forwarding.requests, hasLength(1));
      expect(forwarding.forwards.single.status, SshPortForwardStatus.active);
    },
  );

  test('successful refresh clears old load failure without retrying automatic startup', () async {
    memory.raw = '{broken';
    final source = owner();
    await source.startAutomatic();
    expect(source.error, isNotNull);
    final profile = forwardingProfile(autoStart: true);
    memory.raw = jsonEncode({
      'version': 1,
      'profiles': [profile.toJson()],
    });
    await source.refresh();
    expect(source.error, isNull);
    await source.startAutomatic();
    expect(source.error, isNull);
    final sibling = owner();
    await sibling.startAutomatic();
    await sibling.refresh();
    expect(sibling.error, isNull);
    expect(forwarding.requests, isEmpty);
    await sibling.start(profile.id);
    expect(forwarding.requests, hasLength(1));
  });
}
