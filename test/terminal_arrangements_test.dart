import 'dart:convert';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/terminal_arrangements.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TerminalArrangement _arrangement(String name) =>
    TerminalArrangement(name: name, tabs: [TerminalArrangementTab()]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('arrangement schema', () {
    test(
      'round-trips names, pane positions, size and safe SSH destinations',
      () {
        final arrangement = TerminalArrangement(
          name: 'Daily work',
          tabs: [
            TerminalArrangementTab(name: 'Local'),
            TerminalArrangementTab(
              name: 'Build machine',
              paneState: TerminalPaneState(
                fontSize: 19,
                sshConfig: SshTerminalConfig(
                  host: 'ssh.example',
                  port: 2222,
                  username: 'alice',
                  password: 'password-never-store',
                  privateKey: 'private-key-never-store',
                  passphrase: 'passphrase-never-store',
                  authentication: SshTerminalAuthentication.privateKey,
                  gateway: Uri.parse('wss://gateway.example/ssh'),
                  jumpHosts: const [
                    SshJumpHost(
                      host: 'bastion.example',
                      port: 22,
                      username: 'gateway-user',
                      authentication: SshTerminalAuthentication.privateKey,
                      password: 'jump-password-never-store',
                      privateKey: 'jump-key-never-store',
                      passphrase: 'jump-phrase-never-store',
                    ),
                  ],
                  tmux: const TmuxSessionOptions(
                    sessionName: 'build',
                    mode: TmuxSessionMode.attach,
                  ),
                ),
              ),
            ),
            TerminalArrangementTab(
              paneState: TerminalPaneState(
                fontSize: 8,
                sshConfig: const SshTerminalConfig(
                  host: 'screen.example',
                  port: 22,
                  username: 'bob',
                  screen: ScreenSessionOptions(
                    sessionName: '142.work',
                    mode: ScreenSessionMode.attach,
                  ),
                ),
              ),
            ),
          ],
          firstIndex: 2,
          secondIndex: 1,
          activeIndex: 1,
          splitAxis: TerminalSplitAxis.vertical,
          splitFraction: 0.65,
        );
        final encoded = jsonEncode(arrangement.toJson());
        expect(encoded, isNot(contains('never-store')));
        final parsed = TerminalArrangement.fromJson(jsonDecode(encoded));
        expect(parsed.toJson(), arrangement.toJson());
        expect(parsed.tabs.first.paneState.sshConfig, isNull);
        final config = parsed.tabs[1].paneState.sshConfig!;
        expect(config.authentication, SshTerminalAuthentication.privateKey);
        expect(config.password, isEmpty);
        expect(config.privateKey, isEmpty);
        expect(config.passphrase, isEmpty);
        expect(config.tmux!.mode, TmuxSessionMode.attach);
        expect(config.jumpHosts.single.host, 'bastion.example');
        expect(config.jumpHosts.single.password, isEmpty);
        expect(config.jumpHosts.single.privateKey, isEmpty);
        expect(config.jumpHosts.single.passphrase, isEmpty);
        expect(
          parsed.tabs[2].paneState.sshConfig!.screen!.sessionName,
          '142.work',
        );
        expect(parsed.splitFraction, 0.65);
        expect(parsed.activeIndex, 1);
        expect(parsed.firstIndex, 2);
        expect(parsed.secondIndex, 1);
        expect(() => parsed.tabs.clear(), throwsUnsupportedError);
      },
    );

    test('ignores injected secrets and executable data when decoding', () {
      final data = _arrangement('Safe').toJson();
      data['commands'] = ['rm -rf data'];
      data['output'] = 'secret scrollback';
      (data['tabs'] as List)[0] = {
        'name': 'Destination',
        'pane': {
          'fontSize': 13,
          'ssh': {
            'name': 'destination',
            'host': 'ssh.example',
            'port': 22,
            'username': 'alice',
            'authentication': 'password',
            'password': 'injected-password',
            'privateKey': 'injected-key',
            'passphrase': 'injected-phrase',
            'session': {'kind': 'shell'},
          },
        },
      };
      final restored = TerminalArrangement.fromJson(
        jsonDecode(jsonEncode(data)),
      );
      final serialized = jsonEncode(restored.toJson());
      for (final text in [
        'injected-',
        'rm -rf',
        'secret scrollback',
        'commands',
        'output',
      ]) {
        expect(serialized, isNot(contains(text)));
      }
    });

    test('rejects invalid names, font sizes, tab counts and pane indexes', () {
      for (final name in [
        '',
        '  ',
        ' leading',
        'trailing ',
        'a\nb',
        'a' * 81,
      ]) {
        expect(() => _arrangement(name), throwsFormatException);
      }
      for (final name in ['', ' leading', 'a\tb', 'a' * 61]) {
        expect(() => TerminalArrangementTab(name: name), throwsFormatException);
      }
      for (final size in [double.nan, double.infinity, 7.0, 33.0]) {
        expect(() => TerminalPaneState(fontSize: size), throwsFormatException);
      }
      for (final count in [0, 9]) {
        expect(
          () => TerminalArrangement(
            name: 'Bad count',
            tabs: List.generate(count, (_) => TerminalArrangementTab()),
          ),
          throwsFormatException,
        );
      }
      for (final modification in <Map<String, Object?>>[
        {'activeIndex': -1},
        {'firstIndex': 1},
        {'secondIndex': 0},
        {'secondIndex': 99},
        {'splitFraction': -0.1},
        {'splitFraction': 0.9},
        {'splitAxis': 'diagonal'},
        // Reject fractional IDs on every backend; integral doubles
        // retain a distinct type only on the VM.
        if (!kIsWeb) {'activeIndex': 0.0},
        {'activeIndex': 0.5},
        {'secondIndex': '0'},
        {'tabs': 'bad'},
        {
          'tabs': [null],
        },
        {
          'tabs': [
            {
              'pane': {'fontSize': '13'},
            },
          ],
        },
        {
          'tabs': [
            {
              'pane': {'fontSize': 13, 'ssh': 'ssh.example'},
            },
          ],
        },
      ]) {
        final value = {..._arrangement('Invalid').toJson(), ...modification};
        expect(
          () => TerminalArrangement.fromJson(jsonDecode(jsonEncode(value))),
          throwsFormatException,
          reason: '$modification',
        );
      }
      expect(
        () => TerminalArrangement(
          name: 'Hidden active',
          tabs: [TerminalArrangementTab(), TerminalArrangementTab()],
          activeIndex: 1,
        ),
        throwsFormatException,
      );
    });

    test('validates destinations with the shared SSH profile schema', () {
      for (final config in [
        const SshTerminalConfig(host: '', port: 22, username: 'alice'),
        const SshTerminalConfig(
          host: 'ssh.example',
          port: 0,
          username: 'alice',
        ),
        const SshTerminalConfig(host: 'ssh.example', port: 22, username: ''),
        SshTerminalConfig(
          host: 'ssh.example',
          port: 22,
          username: 'alice',
          gateway: Uri.parse('https://gateway.example'),
        ),
      ]) {
        expect(
          () => TerminalPaneState(sshConfig: config),
          throwsFormatException,
        );
      }
    });

    test('nested arrangements retain hidden tabs and active inner leaves', () {
      final layout = TerminalPaneSplit(
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.6,
        first: TerminalPaneSplit(
          axis: TerminalSplitAxis.vertical,
          fraction: 0.7,
          first: TerminalPaneLeaf(2),
          second: TerminalPaneLeaf(0),
        ),
        second: TerminalPaneLeaf(3),
      );
      final arrangement = TerminalArrangement(
        name: 'Nested',
        tabs: List.generate(
          4,
          (index) => TerminalArrangementTab(name: '$index'),
        ),
        activeIndex: 0,
        layout: layout,
      );
      final restored = TerminalArrangement.fromJson(
        jsonDecode(jsonEncode(arrangement.toJson())),
      );
      expect(restored.layout, layout);
      expect(restored.activeIndex, 0);
      expect(restored.firstIndex, 2);
      expect(restored.secondIndex, 3);
      expect(restored.splitFraction, 0.6);
      expect(restored.tabs, hasLength(4));
      expect(restored.layout.contains(1), isFalse);
      for (final invalid in [TerminalPaneLeaf(4), TerminalPaneLeaf(1)]) {
        expect(
          () => TerminalArrangement(
            name: 'Invalid active or index',
            tabs: arrangement.tabs,
            activeIndex: 0,
            layout: invalid,
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects contradictory or missing nested layout data', () {
      final arrangement = TerminalArrangement(
        name: 'Split',
        tabs: List.generate(3, (_) => TerminalArrangementTab()),
        activeIndex: 1,
        layout: TerminalPaneSplit(
          axis: TerminalSplitAxis.vertical,
          first: TerminalPaneLeaf(0),
          second: TerminalPaneLeaf(1),
        ),
      );
      for (final change in <Map<String, Object?>>[
        {'layout': null},
        {'layout': []},
        {'layout': TerminalPaneLeaf(0).toJson()},
        {'firstIndex': 2},
        {'secondIndex': 2},
        {'splitAxis': 'horizontal'},
        {'splitFraction': 0.6},
        {'activeIndex': 2},
      ]) {
        expect(
          () => TerminalArrangement.fromJson(
            jsonDecode(jsonEncode({...arrangement.toJson(), ...change})),
          ),
          throwsFormatException,
        );
      }
      final missing = arrangement.toJson()..remove('layout');
      expect(
        () => TerminalArrangement.fromJson(missing, requireLayout: true),
        throwsFormatException,
      );
      expect(TerminalArrangement.fromJson(missing).layout, arrangement.layout);
    });
  });

  group('arrangement store', () {
    late String? raw;
    late int writes;
    late TerminalArrangements store;

    setUp(() {
      raw = null;
      writes = 0;
      store = TerminalArrangements(
        read: () async => raw,
        write: (value) async {
          writes++;
          raw = value;
        },
      );
    });

    test('serializes concurrent saves and retains unrelated records', () async {
      await Future.wait([
        for (var i = 0; i < 12; i++) store.save(_arrangement('Session $i')),
      ]);
      final saved = await store.load();
      expect(saved, hasLength(12));
      expect(saved.map((item) => item.name).toSet(), {
        for (var i = 0; i < 12; i++) 'Session $i',
      });
      await store.save(
        TerminalArrangement(
          name: 'Session 4',
          tabs: [TerminalArrangementTab(name: 'Changed')],
        ),
      );
      expect(await store.load(), hasLength(12));
      await store.delete('Session 5');
      expect(await store.load(), hasLength(11));
      expect(
        (await store.load())
            .singleWhere((item) => item.name == 'Session 4')
            .tabs
            .single
            .name,
        'Changed',
      );
    });

    test('reads legacy v1 and migrates all records on the next save', () async {
      final old = {
        'name': 'Legacy',
        'tabs': [
          TerminalArrangementTab(name: 'First').toJson(),
          TerminalArrangementTab(name: 'Second').toJson(),
          TerminalArrangementTab(name: 'Hidden').toJson(),
        ],
        'activeIndex': 0,
        'firstIndex': 1,
        'secondIndex': 0,
        'splitAxis': 'vertical',
        'splitFraction': 0.65,
      };
      raw = jsonEncode({
        'version': 1,
        'arrangements': [old],
      });
      final before = raw;
      final legacy = (await store.load()).single;
      expect(legacy.layout.leafIds, [1, 0]);
      expect(legacy.layout.splitAt('')!.axis, TerminalSplitAxis.vertical);
      expect(legacy.layout.splitAt('')!.fraction, 0.65);
      expect(raw, before, reason: 'Reading does not mutate persisted data');
      expect(writes, 0);
      final nested = TerminalArrangement(
        name: 'New nested layout',
        tabs: List.generate(3, (_) => TerminalArrangementTab()),
        activeIndex: 2,
        layout: TerminalPaneLeaf(0)
            .splitLeaf(0, 1, TerminalSplitAxis.horizontal)
            .splitLeaf(1, 2, TerminalSplitAxis.vertical),
      );
      await store.save(nested);
      final encoded = jsonDecode(raw!);
      expect(encoded['version'], 2);
      expect(
        (encoded['arrangements'] as List).every(
          (entry) => entry['layout'] is Map,
        ),
        isTrue,
      );
      final restored = await store.load();
      expect(restored.first.layout, legacy.layout);
      expect(restored.first.tabs, hasLength(3));
      expect(restored.last.layout, nested.layout);
      await store.delete(nested.name);
      expect((await store.load()).single.layout, legacy.layout);
      expect(jsonDecode(raw!)['version'], 2);
    });

    test(
      'bounds saved arrangements but permits replacement at capacity',
      () async {
        for (var i = 0; i < TerminalArrangements.maxArrangements; i++) {
          await store.save(_arrangement('Arrangement $i'));
        }
        final before = raw;
        await expectLater(
          store.save(_arrangement('Overflow')),
          throwsStateError,
        );
        expect(raw, before);
        await store.save(
          TerminalArrangement(
            name: 'Arrangement 0',
            tabs: [TerminalArrangementTab(name: 'Updated')],
          ),
        );
        expect(await store.load(), hasLength(20));
        expect((await store.load()).first.tabs.single.name, 'Updated');
      },
    );

    test(
      'rejects corrupt or newer data before save or delete writes',
      () async {
        for (final invalid in [
          '{bad json',
          'null',
          jsonEncode({'version': 99, 'arrangements': []}),
          // Whole-valued doubles are ints on Dart web. Keep the VM-only
          // representation check and reject fractions on every backend.
          if (!kIsWeb) jsonEncode({'version': 1.0, 'arrangements': []}),
          jsonEncode({'version': 1.5, 'arrangements': []}),
          jsonEncode({'version': 1, 'arrangements': 'invalid'}),
          jsonEncode({
            'version': 1,
            'arrangements': [null],
          }),
          jsonEncode({
            'version': 2,
            'arrangements': [
              _arrangement('Missing layout').toJson()..remove('layout'),
            ],
          }),
          jsonEncode({
            'version': 1,
            'arrangements': [
              _arrangement('Duplicate').toJson(),
              _arrangement('Duplicate').toJson(),
            ],
          }),
          jsonEncode({
            'version': 1,
            'arrangements': [
              for (var i = 0; i < 21; i++) _arrangement('$i').toJson(),
            ],
          }),
          ' ' * (TerminalArrangements.maxStorageLength + 1),
        ]) {
          raw = invalid;
          await expectLater(store.load(), throwsFormatException);
          await expectLater(
            store.save(_arrangement('New')),
            throwsFormatException,
          );
          await expectLater(store.delete('Old'), throwsFormatException);
          expect(raw, invalid);
        }
        expect(writes, 0);
      },
    );

    test('releases the lock after backend errors', () async {
      var fail = true;
      final failing = TerminalArrangements(
        read: () async => raw,
        write: (value) async {
          if (fail) throw StateError('disk unavailable');
          raw = value;
        },
      );
      await expectLater(failing.save(_arrangement('Retry')), throwsStateError);
      fail = false;
      await failing.save(_arrangement('Retry'));
      expect((await failing.load()).single.name, 'Retry');
    });

    test('default backend coordinates distinct store instances', () async {
      SharedPreferences.setMockInitialValues({});
      final first = TerminalArrangements();
      final second = TerminalArrangements();
      await Future.wait([
        first.save(_arrangement('First')),
        second.save(_arrangement('Second')),
      ]);
      expect((await first.load()).map((item) => item.name), [
        'First',
        'Second',
      ]);
      expect((await second.load()).map((item) => item.name), [
        'First',
        'Second',
      ]);
    });
  });
}
