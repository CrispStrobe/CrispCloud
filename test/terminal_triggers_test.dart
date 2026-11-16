import 'dart:convert';

import 'package:crisp_cloud/models/terminal_trigger.dart';
import 'package:crisp_cloud/services/terminal_triggers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TerminalTrigger _rule({
  String id = 'error',
  String name = 'Build failure',
  String pattern = 'ERROR',
  TerminalTriggerMatchKind kind = TerminalTriggerMatchKind.literal,
  TerminalTriggerAction action = TerminalTriggerAction.notify,
  bool enabled = true,
  bool caseSensitive = true,
  bool once = false,
  int cooldown = 0,
}) => TerminalTrigger(
  id: id,
  name: name,
  pattern: pattern,
  matchKind: kind,
  action: action,
  enabled: enabled,
  caseSensitive: caseSensitive,
  oncePerSession: once,
  cooldownSeconds: cooldown,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('trigger models and bounded pattern evaluation', () {
    test('JSON round trip preserves exact authored rules', () {
      final rule = _rule(
        pattern: r'^ERROR:\s+[0-9]+ café🙂$',
        kind: TerminalTriggerMatchKind.safePattern,
        action: TerminalTriggerAction.mark,
        enabled: false,
        caseSensitive: false,
        once: true,
        cooldown: 20,
      );
      final restored = TerminalTrigger.fromJson(
        jsonDecode(jsonEncode(rule.toJson())),
      );
      expect(restored.toJson(), rule.toJson());
      expect(restored.copyWith(enabled: true).toJson(), {
        ...rule.toJson(),
        'enabled': true,
      });
    });

    test(
      'literal mode interprets punctuation literally with Unicode matching',
      () {
        final rule = _rule(pattern: r'ERROR.* café🙂');
        expect(rule.matches(r'build ERROR.* café🙂 failed'), isTrue);
        expect(rule.matches('ERROR: café🙂'), isFalse);
        expect(
          _rule(pattern: 'CAFÉ🙂', caseSensitive: false).matches('café🙂'),
          isTrue,
        );
      },
    );

    test(
      'validation rejects controls, unbounded text and invalid action data',
      () {
        for (final name in ['', '   ', 'x' * 81, 'bad\nname', '\x1bname']) {
          expect(() => _rule(name: name), throwsFormatException);
        }
        for (final pattern in ['', 'x' * 257, 'bad\npattern', '\x9dtitle']) {
          expect(() => _rule(pattern: pattern), throwsFormatException);
        }
        for (final id in ['', ' ', '../trigger', 'x' * 81]) {
          expect(() => _rule(id: id), throwsFormatException);
        }
        expect(() => _rule(cooldown: -1), throwsFormatException);
        expect(() => _rule(cooldown: 3601), throwsFormatException);
        for (final replacement in [
          {'action': 'execute'},
          {'enabled': 1},
          {'cooldownSeconds': 1.2},
          {'matchKind': 'javascript'},
          {'id': null},
        ]) {
          expect(
            () =>
                TerminalTrigger.fromJson({..._rule().toJson(), ...replacement}),
            throwsFormatException,
          );
        }
      },
    );

    test('finite-state patterns agree with regular expression oracle for supported syntax', () {
      final patterns = [
        'ERROR',
        '^ERROR',
        r'ERROR$',
        r'^ERROR$',
        r'ERR.OR',
        r'ERR.*OR',
        r'ER+OR',
        r'E?RROR',
        r'^[a-z]+[0-9]?$',
        r'^[^0-9]+$',
        r'error\s+\d+',
        r'\w+\.dart',
        r'\D+',
        r'\S+',
        r'\W+',
        r'^café🙂+$',
        r'build\[ok\]',
        r'a*b+c?d',
        r'^[A-Z]+$',
        r'[a-zA-Z_]+',
        r'^a?b*cd+$',
      ];
      final samples = [
        '',
        'ERROR',
        'XERROR',
        'ERRORX',
        'ERZOR',
        'error 123',
        'error x',
        'build[ok]',
        'test.dart',
        'testDdart',
        'éCOLE',
        'café🙂🙂',
        'abcd',
        'bbd',
        'aacddd',
        'cd',
        '123',
        'ABC',
        '_hello',
        '  ',
      ];
      for (final sensitive in [true, false]) {
        for (final pattern in patterns) {
          final matcher = TerminalTriggerPattern(
            pattern,
            caseSensitive: sensitive,
          );
          final oracle = RegExp(
            pattern,
            caseSensitive: sensitive,
            unicode: true,
          );
          for (final sample in samples) {
            expect(
              matcher.hasMatch(sample),
              oracle.hasMatch(sample),
              reason: '$pattern / $sample / case=$sensitive',
            );
          }
        }
      }
    });

    test('patterns reject backtracking features and patterns that match empty input', () {
      for (final pattern in [
        r'(a+)+$',
        r'a|b',
        r'(?=a)',
        r'(a)\1',
        r'a{1,2}',
        r'a**',
        r'a+?',
        r'*a',
        r'[z-a]',
        r'[abc',
        r'[]',
        r'[\d]',
        r'\1',
        r'\b',
        'a\\',
        '^',
        r'$',
        r'^$',
        'a*',
        '.*',
        'a?b*',
      ]) {
        expect(
          () => TerminalTriggerPattern(pattern),
          throwsFormatException,
          reason: pattern,
        );
      }
    });

    test('overlapping quantifiers evaluate large non-matching input without backtracking', () {
      final matcher = TerminalTriggerPattern('${'a*' * 100}b');
      expect(matcher.hasMatch('a' * 4096), isFalse);
      expect(matcher.hasMatch('${'a' * 4095}b'), isTrue);
    });

    test('inverse escapes keep their meaning in case insensitive mode', () {
      final nonDigit = TerminalTriggerPattern(r'^\D+$', caseSensitive: false);
      expect(nonDigit.hasMatch('ERROR'), isTrue);
      expect(nonDigit.hasMatch('123'), isFalse);
    });
  });

  group('persistent rules', () {
    late String? raw;
    late int writes;
    late TerminalTriggers store;
    setUp(() {
      raw = null;
      writes = 0;
      store = TerminalTriggers(
        read: () async => raw,
        write: (value) async {
          writes++;
          raw = value;
        },
      );
    });

    test(
      'create, edit, disable and delete preserve distinct identities',
      () async {
        final first = _rule();
        final second = _rule(id: 'success', pattern: 'SUCCESS');
        await store.save(first);
        await store.save(second);
        await store.save(first.copyWith(enabled: false), replacing: first.id);
        expect((await store.load()).map((item) => item.id), [
          'error',
          'success',
        ]);
        expect((await store.load()).first.enabled, isFalse);
        await store.delete(first.id);
        expect((await store.load()).single.toJson(), second.toJson());
        expect(raw, isNot(contains('capturedOutput')));
      },
    );

    test(
      'concurrent mutations serialize without dropping another rule',
      () async {
        await Future.wait([
          store.save(_rule(id: 'one')),
          store.save(_rule(id: 'two')),
          store.save(_rule(id: 'three')),
        ]);
        expect((await store.load()).map((item) => item.id), [
          'one',
          'two',
          'three',
        ]);
        expect(writes, 3);
      },
    );

    test('duplicate and stale edits are refused without a write', () async {
      await store.save(_rule());
      final prior = raw;
      await expectLater(store.save(_rule()), throwsStateError);
      await expectLater(
        store.save(_rule(id: 'new'), replacing: 'missing'),
        throwsStateError,
      );
      expect(raw, prior);
      expect(writes, 1);
    });

    test('capacity failure preserves all existing rules', () async {
      for (var i = 0; i < TerminalTriggers.maximumTriggers; i++) {
        await store.save(_rule(id: 'rule_$i'));
      }
      final prior = raw;
      await expectLater(store.save(_rule(id: 'extra')), throwsStateError);
      expect(raw, prior);
      expect((await store.load()).length, 50);
    });

    test(
      'corrupt, duplicate, oversize and newer stores cannot be overwritten',
      () async {
        final records = [
          'not json',
          jsonEncode({'version': 2, 'triggers': []}),
          jsonEncode({
            'version': 1,
            'triggers': [_rule().toJson(), _rule().toJson()],
          }),
          jsonEncode({
            'version': 1,
            'triggers': [null],
          }),
          jsonEncode({
            'version': 1,
            'triggers': List.generate(51, (i) => _rule(id: 'rule_$i').toJson()),
          }),
          ' ' * (TerminalTriggers.maximumStorageLength + 1),
        ];
        for (final record in records) {
          raw = record;
          await expectLater(store.load(), throwsFormatException);
          await expectLater(store.save(_rule()), throwsFormatException);
          await expectLater(store.delete('error'), throwsFormatException);
          expect(raw, record);
        }
        expect(writes, 0);
      },
    );

    test(
      'default preference store works with independent service instances',
      () async {
        SharedPreferences.setMockInitialValues({});
        final first = TerminalTriggers();
        final second = TerminalTriggers();
        await Future.wait([
          first.save(_rule()),
          second.save(_rule(id: 'second')),
        ]);
        expect((await first.load()).length, 2);
        expect((await second.load()).length, 2);
      },
    );

    test('storage failures surface and leave prior data intact', () async {
      final failure = TerminalTriggers(
        read: () async => raw,
        write: (_) async => throw StateError('disk full'),
      );
      await expectLater(failure.save(_rule()), throwsStateError);
      expect(raw, isNull);
      expect(
        () => TerminalTriggers(read: () async => null),
        throwsArgumentError,
      );
    });
  });

  group('streamed output observation', () {
    late List<TerminalTriggerMatch> matches;
    late DateTime now;
    late TerminalTriggerEngine engine;
    setUp(() {
      matches = [];
      now = DateTime.utc(2026, 11, 16);
      engine = TerminalTriggerEngine(onMatch: matches.add, now: () => now);
      engine.updateTriggers([_rule()]);
    });

    test('partial lines wait for a newline and final unterminated output emits once', () {
      engine.addOutput('ERR');
      engine.addOutput('OR café🙂');
      expect(matches, isEmpty);
      engine.addOutput('\r\nERROR tail');
      expect(matches.map((m) => m.line), ['ERROR café🙂']);
      engine.finish();
      engine.finish();
      engine.addOutput('ERROR ignored\n');
      expect(matches.map((m) => m.line), ['ERROR café🙂', 'ERROR tail']);
    });

    test('normalization is independent of every UTF-16 chunk boundary', () {
      const input =
          '\x1b[31mERROR café🙂\x1b[0m\r\n'
          '\x1b]0;ERROR title\x07ok\n'
          '\x1bPERROR payload\x1b\\ok\n'
          '\x1b[?1049hERROR hidden\n\x1b[?1049lERROR visible\n';
      engine.addOutput(input);
      final expected = matches.map((m) => m.line).toList();
      expect(expected, ['ERROR café🙂', 'ERROR visible']);
      for (var split = 0; split <= input.length; split++) {
        matches.clear();
        engine.reset();
        engine.addOutput(input.substring(0, split));
        engine.addOutput(input.substring(split));
        expect(matches.map((m) => m.line), expected, reason: 'split $split');
      }
      matches.clear();
      engine.reset();
      for (final unit in input.codeUnits) {
        engine.addOutput(String.fromCharCode(unit));
      }
      expect(matches.map((m) => m.line), expected);
    });

    test(
      'CR overwrite, backspace, tabs and erase-line use visible final text',
      () {
        engine.addOutput('ERROR failed\rOK\x1b[K\n');
        engine.addOutput('progress\rERROR\x1b[K\n');
        engine.addOutput('ERR\bROR\n');
        engine.addOutput('a\tERROR\n');
        expect(matches.map((m) => m.line), ['ERROR', 'ERROR', 'a       ERROR']);
      },
    );

    test('cursor movement and oversized lines are dropped, then observation recovers', () {
      engine.addOutput('ERROR\x1b[2A moved\n');
      engine.addOutput(
        '${'x' * TerminalTriggerEngine.maximumLineLength}ERROR\n',
      );
      engine.addOutput('ERROR next\n');
      expect(matches.map((m) => m.line), ['ERROR next']);
    });

    test('C1 control strings and all string terminators are stripped', () {
      engine.addOutput('\x9dERROR title\x9cERROR main\n');
      engine.addOutput('\x90ERROR payload\x1b\\okay\n');
      engine.addOutput('\x1b_ERROR private\x1b\\ERROR public\n');
      engine.addOutput('\x9b31mERROR color\x9b0m\n');
      expect(matches.map((m) => m.line), [
        'ERROR main',
        'ERROR public',
        'ERROR color',
      ]);
    });

    test(
      'unterminated and oversized control strings cannot leak trigger text',
      () {
        engine.addOutput('\x1b]title ${'x' * 200000}ERROR\n');
        expect(matches, isEmpty);
        engine.addOutput('\x07ERROR recovered\n');
        expect(matches.single.line, 'ERROR recovered');
        engine.addOutput(
          '\x1b[${'1;' * 10000}mERROR too long control\nERROR next\n',
        );
        expect(matches.map((m) => m.line), ['ERROR recovered', 'ERROR next']);
      },
    );

    test(
      'alternate-screen output is excluded with same-chunk entry and exit',
      () {
        for (final mode in ['47', '1047', '1049']) {
          engine.addOutput(
            'main prefix\x1b[?$mode'
            'hERROR hidden\n'
            '\x1b[?$mode'
            'lERROR main $mode\n',
          );
        }
        expect(matches.map((m) => m.line), [
          'ERROR main 47',
          'ERROR main 1047',
          'ERROR main 1049',
        ]);
      },
    );

    test('one-shot rules survive repeated configuration loads and reset with transport', () {
      final rule = _rule(once: true);
      engine.updateTriggers([rule]);
      engine.addOutput('ERROR first\n');
      engine.updateTriggers([TerminalTrigger.fromJson(rule.toJson())]);
      engine.addOutput('ERROR second\n');
      engine.updateTriggers([rule.copyWith(enabled: false)]);
      engine.addOutput('ERROR disabled\n');
      engine.updateTriggers([rule]);
      engine.addOutput('ERROR enabled again\n');
      expect(matches.length, 1);
      engine.reset();
      engine.addOutput('ERROR new transport\n');
      expect(matches.map((m) => m.line), [
        'ERROR first',
        'ERROR new transport',
      ]);
    });

    test('cooldown and action rate limit prevent repeated alert floods', () {
      engine.updateTriggers([_rule(cooldown: 5)]);
      engine.addOutput('ERROR\n' * 20);
      expect(matches.length, 1);
      now = now.add(const Duration(seconds: 4));
      engine.addOutput('ERROR\n');
      expect(matches.length, 1);
      now = now.add(const Duration(seconds: 1));
      engine.addOutput('ERROR\n');
      expect(matches.length, 2);
      engine.reset();
      matches.clear();
      engine.updateTriggers([_rule()]);
      engine.addOutput('ERROR\n' * 1000);
      expect(matches.length, TerminalTriggerEngine.maximumActionsPerSecond);
      now = now.add(const Duration(seconds: 1));
      engine.addOutput('ERROR\n');
      expect(matches.length, TerminalTriggerEngine.maximumActionsPerSecond + 1);
    });

    test('independent actions fire once per matching line and disabled rules never fire', () {
      engine.updateTriggers([
        _rule(id: 'mark', action: TerminalTriggerAction.mark),
        _rule(id: 'alert'),
        _rule(id: 'disabled', enabled: false),
      ]);
      engine.addOutput('ERROR ERROR\n');
      expect(matches.map((m) => m.trigger.id), ['mark', 'alert']);
      expect(matches.map((m) => m.trigger.action), [
        TerminalTriggerAction.mark,
        TerminalTriggerAction.notify,
      ]);
    });

    test('reentrant callback output cannot recursively trigger actions', () {
      engine = TerminalTriggerEngine(
        onMatch: (match) {
          matches.add(match);
          engine.addOutput('ERROR recursion\n');
          engine.finish();
        },
      );
      engine.updateTriggers([_rule()]);
      engine.addOutput('ERROR incoming\n');
      expect(matches.single.line, 'ERROR incoming');
    });

    test(
      'reset drops partial control sequences, input lines and lifetime history',
      () {
        engine.addOutput('ERROR\x1b]unfinished title');
        engine.reset();
        engine.addOutput('plain\nERROR new\n');
        expect(matches.single.line, 'ERROR new');
      },
    );

    test('runtime rule sets are bounded and duplicate ids reject', () {
      expect(
        () => engine.updateTriggers([_rule(), _rule()]),
        throwsFormatException,
      );
      expect(
        () => engine.updateTriggers(
          List.generate(51, (i) => _rule(id: 'rule_$i')),
        ),
        throwsFormatException,
      );
    });
  });
}
