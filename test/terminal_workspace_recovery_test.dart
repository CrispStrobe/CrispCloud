import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/terminal_workspace_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TerminalArrangement _snapshot(String name) => TerminalArrangement(
  name: 'Recovered workspace',
  tabs: [TerminalArrangementTab(name: name)],
);

TerminalArrangement _fullSnapshot() {
  TerminalPaneLayout nested(int index) => index == 7
      ? TerminalPaneLeaf(index)
      : TerminalPaneSplit(
          axis: index.isEven
              ? TerminalSplitAxis.horizontal
              : TerminalSplitAxis.vertical,
          fraction: index.isEven ? 0.65 : 0.35,
          first: TerminalPaneLeaf(index),
          second: nested(index + 1),
        );
  return TerminalArrangement(
    name: 'Recovered workspace',
    activeIndex: 6,
    layout: nested(0),
    tabs: [
      for (var index = 0; index < 8; index++)
        TerminalArrangementTab(
          name: 'Terminal $index',
          paneState: TerminalPaneState(
            fontSize: 8 + index * 3,
            sshConfig: index.isEven
                ? null
                : SshTerminalConfig(
                    host: 'host-$index.example',
                    port: 2200 + index,
                    username: 'alice',
                    authentication: SshTerminalAuthentication.agent,
                    forwardAgent: true,
                    password: 'never-persist-password',
                    privateKey: 'never-persist-private-key',
                    passphrase: 'never-persist-passphrase',
                    gateway: Uri.parse('wss://gateway.example/ssh'),
                    tmux: const TmuxSessionOptions(
                      sessionName: 'project',
                      mode: TmuxSessionMode.attach,
                      controlMode: true,
                    ),
                    jumpHosts: [
                      for (var hop = 0; hop < 3; hop++)
                        SshJumpHost(
                          host: 'hop-$hop.example',
                          port: 22,
                          username: 'jump-user',
                          authentication: SshTerminalAuthentication.privateKey,
                          password: 'never-persist-jump-password',
                          privateKey: 'never-persist-jump-key',
                          passphrase: 'never-persist-jump-passphrase',
                        ),
                    ],
                  ),
          ),
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final savedAt = DateTime.utc(2026, 11, 16, 10, 30);

  group('recovery record', () {
    test('round-trips eight panes, nested geometry and safe destinations', () {
      final record = TerminalWorkspaceRecoveryRecord(
        enabled: true,
        relaunchLocalShells: true,
        snapshot: _fullSnapshot(),
        savedAt: savedAt,
      );
      final encoded = jsonEncode(record.toJson());
      expect(encoded, isNot(contains('never-persist')));
      final restored = TerminalWorkspaceRecoveryRecord.fromJson(
        jsonDecode(encoded),
      );
      expect(restored.toJson(), record.toJson());
      expect(restored.savedAt, savedAt);
      expect(restored.savedAt!.isUtc, isTrue);
      expect(restored.snapshot!.tabs, hasLength(8));
      expect(restored.snapshot!.layout.leafIds, List.generate(8, (i) => i));
      expect(restored.snapshot!.activeIndex, 6);
      final config = restored.snapshot!.tabs[1].paneState.sshConfig!;
      expect(config.password, isEmpty);
      expect(config.privateKey, isEmpty);
      expect(config.passphrase, isEmpty);
      expect(config.tmux!.controlMode, isTrue);
      expect(config.tmux!.mode, TmuxSessionMode.attach);
      expect(config.authentication, SshTerminalAuthentication.agent);
      expect(config.forwardAgent, isTrue);
      expect(config.jumpHosts, hasLength(3));
      for (final jump in config.jumpHosts) {
        expect(jump.password, isEmpty);
        expect(jump.privateKey, isEmpty);
        expect(jump.passphrase, isEmpty);
      }
    });

    test('drops injected commands, output and runtime permissions', () {
      final data = TerminalWorkspaceRecoveryRecord(
        enabled: true,
        snapshot: _snapshot('Remote'),
        savedAt: savedAt,
      ).toJson();
      data['command'] = 'untrusted-command';
      data['broadcast'] = ['untrusted-member'];
      data['grant'] = 'untrusted-grant';
      data['output'] = 'untrusted-output';
      final snapshot = data['snapshot'] as Map<String, Object?>;
      snapshot['workingDirectory'] = '/untrusted-cwd';
      final tabs = snapshot['tabs'] as List;
      tabs[0] = {
        'name': 'Remote',
        'connection': 'untrusted-live-connection',
        'pane': {
          'fontSize': 18,
          'ssh': {
            'name': 'destination',
            'host': 'remote.example',
            'port': 22,
            'username': 'alice',
            'authentication': 'password',
            'password': 'untrusted-password',
            'privateKey': 'untrusted-key',
            'passphrase': 'untrusted-passphrase',
            'session': {'kind': 'shell'},
          },
        },
      };
      final restored = TerminalWorkspaceRecoveryRecord.fromJson(
        jsonDecode(jsonEncode(data)),
      );
      final serialized = jsonEncode(restored.toJson());
      expect(serialized, isNot(contains('untrusted')));
      expect(restored.snapshot!.tabs.single.paneState.fontSize, 18);
      expect(
        restored.snapshot!.tabs.single.paneState.sshConfig!.password,
        isEmpty,
      );
    });

    test('requires a complete timestamp and full consistent topology', () {
      final valid = TerminalWorkspaceRecoveryRecord(
        enabled: true,
        snapshot: _snapshot('One'),
        savedAt: savedAt,
      ).toJson();
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v.remove('snapshot'),
        (v) => v.remove('savedAt'),
        (v) => v['savedAt'] = -1,
        (v) => v['savedAt'] = 1.5,
        (v) => v['savedAt'] = '2026-11-16',
        (v) =>
            v['savedAt'] = TerminalWorkspaceRecoveryRecord.maximumTimestamp + 1,
        (v) => v['enabled'] = 'true',
        (v) => v['relaunchLocalShells'] = 1,
        (v) => v.remove('relaunchLocalShells'),
        (v) => v['snapshot'] = [],
        (v) => (v['snapshot'] as Map).remove('layout'),
        (v) => (v['snapshot'] as Map)['activeIndex'] = 3,
        (v) => (v['snapshot'] as Map)['firstIndex'] = 1,
      ]) {
        final data = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
        mutate(data);
        expect(
          () => TerminalWorkspaceRecoveryRecord.fromJson(data),
          throwsFormatException,
        );
      }
      expect(
        () => TerminalWorkspaceRecoveryRecord(snapshot: _snapshot('One')),
        throwsFormatException,
      );
      expect(
        () => TerminalWorkspaceRecoveryRecord(savedAt: savedAt),
        throwsFormatException,
      );
    });

    test('rejects missing, newer and noninteger schema versions', () {
      for (final version in [null, 0, 2, '1', 1.5]) {
        final data = <String, dynamic>{
          'version': version,
          'enabled': false,
          'relaunchLocalShells': false,
        };
        expect(
          () => TerminalWorkspaceRecoveryRecord.fromJson(data),
          throwsFormatException,
        );
      }
    });
  });

  group('recovery storage', () {
    late String? raw;
    late List<String> writes;
    late TerminalWorkspaceRecovery store;
    late TerminalWorkspaceRecoveryLease lease;

    setUp(() {
      raw = null;
      writes = [];
      store = TerminalWorkspaceRecovery(
        read: () async => raw,
        write: (value) async {
          writes.add(value);
          raw = value;
        },
        clock: () => savedAt,
      );
      lease = store.acquireLease();
    });

    tearDown(() => lease.close());

    test('defaults off and never saves a snapshot before opt-in', () async {
      final initial = await store.load();
      expect(initial.enabled, isFalse);
      expect(initial.relaunchLocalShells, isFalse);
      expect(initial.snapshot, isNull);
      final ignored = await store.save(_snapshot('One'), lease: lease);
      expect(ignored.toJson(), initial.toJson());
      expect(raw, isNull);
      expect(writes, isEmpty);
    });

    test(
      'writes and loads a credential-free checkpoint as one value',
      () async {
        final configured = await store.configure(
          lease: lease,
          enabled: true,
          relaunchLocalShells: false,
        );
        expect(configured.snapshot, isNull);
        final saved = await store.save(_fullSnapshot(), lease: lease);
        expect(saved.savedAt, savedAt);
        expect(saved.enabled, isTrue);
        expect(saved.relaunchLocalShells, isFalse);
        expect(raw, isNot(contains('never-persist')));
        expect(writes, hasLength(2));
        final loaded = await store.load();
        expect(loaded.toJson(), saved.toJson());
        for (final bytes in writes) {
          expect(
            () => TerminalWorkspaceRecoveryRecord.fromJson(jsonDecode(bytes)),
            returnsNormally,
          );
        }
      },
    );

    test('identical layout saves do not rewrite the checkpoint', () async {
      await store.configure(
        lease: lease,
        enabled: true,
        relaunchLocalShells: false,
      );
      await store.save(_fullSnapshot(), lease: lease);
      final original = raw;
      await store.save(_fullSnapshot(), lease: lease);
      expect(raw, original);
      expect(writes, hasLength(2));
    });

    test(
      'disable preserves last snapshot without accepting new saves',
      () async {
        await store.configure(
          lease: lease,
          enabled: true,
          relaunchLocalShells: true,
        );
        await store.save(_snapshot('Keep'), lease: lease);
        final disabled = await store.configure(
          lease: lease,
          enabled: false,
          relaunchLocalShells: false,
        );
        expect(disabled.snapshot!.tabs.single.name, 'Keep');
        expect(disabled.savedAt, savedAt);
        final ignored = await store.save(_snapshot('Ignore'), lease: lease);
        expect(ignored.toJson(), disabled.toJson());
        expect(writes, hasLength(3));
        final enabled = await store.configure(
          lease: lease,
          enabled: true,
          relaunchLocalShells: false,
        );
        expect(enabled.snapshot!.tabs.single.name, 'Keep');
        expect(enabled.relaunchLocalShells, isFalse);
      },
    );

    test('forget clears snapshot and both opt-ins', () async {
      await store.configure(
        lease: lease,
        enabled: true,
        relaunchLocalShells: true,
      );
      await store.save(_snapshot('Forget'), lease: lease);
      final forgotten = await store.forget(lease: lease);
      expect(forgotten.enabled, isFalse);
      expect(forgotten.relaunchLocalShells, isFalse);
      expect(forgotten.snapshot, isNull);
      expect(forgotten.savedAt, isNull);
      expect(raw, isNot(contains('Forget')));
      await store.save(_snapshot('Too late'), lease: lease);
      expect((await store.load()).snapshot, isNull);
    });

    test('serializes saves and setting updates in invocation order', () async {
      final first = store.configure(
        lease: lease,
        enabled: true,
        relaunchLocalShells: true,
      );
      final second = store.save(_snapshot('One'), lease: lease);
      final third = store.save(_snapshot('Two'), lease: lease);
      await Future.wait([first, second, third]);
      expect(writes, hasLength(3));
      expect((await store.load()).snapshot!.tabs.single.name, 'Two');
      final disable = store.configure(
        lease: lease,
        enabled: false,
        relaunchLocalShells: false,
      );
      final lateSave = store.save(_snapshot('Three'), lease: lease);
      await Future.wait([disable, lateSave]);
      expect((await store.load()).snapshot!.tabs.single.name, 'Two');
    });

    test(
      'older save queued before configure cannot use later opt-in',
      () async {
        final ignored = store.save(_snapshot('Before consent'), lease: lease);
        final enabling = store.configure(
          lease: lease,
          enabled: true,
          relaunchLocalShells: false,
        );
        await Future.wait([ignored, enabling]);
        expect((await store.load()).snapshot, isNull);
        expect(writes, hasLength(1));
      },
    );

    test('preserves invalid bytes until explicit forget resets them', () async {
      for (final invalid in [
        '{bad json',
        '[]',
        '{"version":2,"enabled":true,"relaunchLocalShells":false}',
        '{"version":1,"enabled":true,"relaunchLocalShells":0}',
        'x' * (TerminalWorkspaceRecovery.maximumStorageLength + 1),
      ]) {
        raw = invalid;
        writes.clear();
        await expectLater(store.load(), throwsFormatException);
        await expectLater(
          store.configure(
            lease: lease,
            enabled: true,
            relaunchLocalShells: true,
          ),
          throwsFormatException,
        );
        await expectLater(
          store.save(_snapshot('Do not overwrite'), lease: lease),
          throwsFormatException,
        );
        expect(raw, invalid);
        expect(writes, isEmpty);
        await store.forget(lease: lease);
        expect((await store.load()).enabled, isFalse);
        expect(writes, hasLength(1));
      }
    });

    test('requires paired backend callbacks', () {
      expect(
        () => TerminalWorkspaceRecovery(read: () async => null),
        throwsArgumentError,
      );
      expect(
        () => TerminalWorkspaceRecovery(write: (_) async {}),
        throwsArgumentError,
      );
    });
  });

  group('recovery concurrency', () {
    test('disable revokes a save still reading the previous state', () async {
      var raw = jsonEncode(
        TerminalWorkspaceRecoveryRecord(
          enabled: true,
          snapshot: _snapshot('Original'),
          savedAt: savedAt,
        ).toJson(),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      final writes = <String>[];
      final store = TerminalWorkspaceRecovery(
        read: () async {
          if (reads++ == 0) {
            entered.complete();
            await release.future;
          }
          return raw;
        },
        write: (value) async {
          writes.add(value);
          raw = value;
        },
      );
      final lease = store.acquireLease();
      addTearDown(lease.close);
      final save = store.save(_snapshot('Stale'), lease: lease);
      await entered.future;
      final disable = store.configure(
        lease: lease,
        enabled: false,
        relaunchLocalShells: false,
      );
      release.complete();
      await Future.wait([save, disable]);
      expect(writes, hasLength(1));
      final loaded = await store.load();
      expect(loaded.enabled, isFalse);
      expect(loaded.snapshot!.tabs.single.name, 'Original');
    });

    test('forget fences queued saves before a later enable', () async {
      var raw = jsonEncode(
        TerminalWorkspaceRecoveryRecord(enabled: true).toJson(),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      var firstRead = true;
      final store = TerminalWorkspaceRecovery(
        read: () async {
          if (firstRead) {
            firstRead = false;
            entered.complete();
            await release.future;
          }
          return raw;
        },
        write: (value) async => raw = value,
      );
      final lease = store.acquireLease();
      addTearDown(lease.close);
      final saveOne = store.save(_snapshot('Old one'), lease: lease);
      await entered.future;
      final saveTwo = store.save(_snapshot('Old two'), lease: lease);
      final forget = store.forget(lease: lease);
      final enable = store.configure(
        lease: lease,
        enabled: true,
        relaunchLocalShells: false,
      );
      release.complete();
      await Future.wait([saveOne, saveTwo, forget, enable]);
      final loaded = await store.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.snapshot, isNull);
    });

    test(
      'closing owner during read rejects write before backend access',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final writes = <String>[];
        final store = TerminalWorkspaceRecovery(
          read: () async {
            entered.complete();
            await release.future;
            return jsonEncode(
              TerminalWorkspaceRecoveryRecord(enabled: true).toJson(),
            );
          },
          write: (value) async => writes.add(value),
        );
        final lease = store.acquireLease();
        final save = store.save(_snapshot('Stale'), lease: lease);
        final failure = expectLater(
          save,
          throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
        );
        await entered.future;
        lease.close();
        release.complete();
        await failure;
        expect(writes, isEmpty);
        expect(lease.isCurrent, isFalse);
      },
    );

    test('new owner supersedes old queued operations and old close', () async {
      String? raw;
      final store = TerminalWorkspaceRecovery(
        read: () async => raw,
        write: (value) async => raw = value,
      );
      final old = store.acquireLease();
      final oldConfiguration = store.configure(
        lease: old,
        enabled: true,
        relaunchLocalShells: true,
      );
      final oldFailure = expectLater(
        oldConfiguration,
        throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
      );
      final current = store.acquireLease();
      addTearDown(current.close);
      old.close();
      expect(current.isCurrent, isTrue);
      await oldFailure;
      await store.configure(
        lease: current,
        enabled: true,
        relaunchLocalShells: false,
      );
      await store.save(_snapshot('Current'), lease: current);
      await expectLater(
        store.forget(lease: old),
        throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
      );
      final loaded = await store.load();
      expect(loaded.snapshot!.tabs.single.name, 'Current');
      expect(loaded.relaunchLocalShells, isFalse);
    });

    test(
      'new owner reads only after an already-started write settles',
      () async {
        var raw = jsonEncode(
          TerminalWorkspaceRecoveryRecord(enabled: true).toJson(),
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        var firstWrite = true;
        final store = TerminalWorkspaceRecovery(
          read: () async => raw,
          write: (value) async {
            if (firstWrite) {
              firstWrite = false;
              entered.complete();
              await release.future;
            }
            raw = value;
          },
        );
        final old = store.acquireLease();
        final oldSave = store.save(_snapshot('In flight'), lease: old);
        await entered.future;
        old.close();
        final current = store.acquireLease();
        addTearDown(current.close);
        var readFinished = false;
        final load = store.load().then((record) {
          readFinished = true;
          return record;
        });
        final newSave = store.save(_snapshot('New owner'), lease: current);
        await Future<void>.delayed(Duration.zero);
        expect(readFinished, isFalse);
        release.complete();
        await oldSave;
        expect((await load).snapshot!.tabs.single.name, 'In flight');
        await newSave;
        expect((await store.load()).snapshot!.tabs.single.name, 'New owner');
      },
    );

    test('lease from a different backend cannot authorize changes', () async {
      final first = TerminalWorkspaceRecovery(
        read: () async => null,
        write: (_) async {},
      );
      var writes = 0;
      final second = TerminalWorkspaceRecovery(
        read: () async => null,
        write: (_) async => writes++,
      );
      final wrong = first.acquireLease();
      addTearDown(wrong.close);
      await expectLater(
        second.configure(
          lease: wrong,
          enabled: true,
          relaunchLocalShells: false,
        ),
        throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
      );
      expect(writes, 0);
      expect(wrong.isCurrent, isTrue);
    });

    test(
      'failed backend write does not poison subsequent saves or reset',
      () async {
        String? raw;
        var fail = true;
        final store = TerminalWorkspaceRecovery(
          read: () async => raw,
          write: (value) async {
            if (fail) throw StateError('disk full');
            raw = value;
          },
        );
        final lease = store.acquireLease();
        addTearDown(lease.close);
        await expectLater(
          store.configure(
            lease: lease,
            enabled: true,
            relaunchLocalShells: false,
          ),
          throwsStateError,
        );
        expect(raw, isNull);
        expect((await store.load()).enabled, isFalse);
        fail = false;
        await store.configure(
          lease: lease,
          enabled: true,
          relaunchLocalShells: false,
        );
        await store.save(_snapshot('Original'), lease: lease);
        final original = raw;
        fail = true;
        await expectLater(
          store.save(_snapshot('Failed'), lease: lease),
          throwsStateError,
        );
        expect(raw, original);
        fail = false;
        await store.forget(lease: lease);
        expect((await store.load()).snapshot, isNull);
      },
    );

    test(
      'failed read preserves storage and explicit forget remains usable',
      () async {
        var failRead = true;
        String? raw = 'unreadable bytes';
        var writes = 0;
        final store = TerminalWorkspaceRecovery(
          read: () async {
            if (failRead) throw StateError('storage unavailable');
            return raw;
          },
          write: (value) async {
            raw = value;
            writes++;
          },
        );
        final lease = store.acquireLease();
        addTearDown(lease.close);
        await expectLater(store.load(), throwsStateError);
        await expectLater(
          store.configure(
            lease: lease,
            enabled: true,
            relaunchLocalShells: false,
          ),
          throwsStateError,
        );
        expect(raw, 'unreadable bytes');
        expect(writes, 0);
        await store.forget(lease: lease);
        failRead = false;
        expect((await store.load()).enabled, isFalse);
        expect(writes, 1);
      },
    );
  });

  test(
    'default services share preferences and exclusive mount authority',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = TerminalWorkspaceRecovery(clock: () => savedAt);
      final second = TerminalWorkspaceRecovery(clock: () => savedAt);
      final firstLease = first.acquireLease();
      await first.configure(
        lease: firstLease,
        enabled: true,
        relaunchLocalShells: true,
      );
      await first.save(_snapshot('Original'), lease: firstLease);
      final secondLease = second.acquireLease();
      addTearDown(secondLease.close);
      expect(firstLease.isCurrent, isFalse);
      await expectLater(
        first.save(_snapshot('Old mount'), lease: firstLease),
        throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
      );
      expect((await second.load()).snapshot!.tabs.single.name, 'Original');
      await second.save(_snapshot('New mount'), lease: secondLease);
      expect((await first.load()).snapshot!.tabs.single.name, 'New mount');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {TerminalWorkspaceRecovery.preferencesKey});
      firstLease.close();
      expect(secondLease.isCurrent, isTrue);
    },
  );
}
