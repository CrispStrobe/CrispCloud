import 'dart:convert';

import 'package:crisp_cloud/models/terminal_key_binding.dart';
import 'package:crisp_cloud/services/terminal_key_bindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart';

TerminalKeyBinding _binding(int index) => TerminalKeyBinding(
  chord: TerminalKeyChord(
    keyId: LogicalKeyboardKey.keyA.keyId + index % 26,
    ctrl: true,
    alt: index >= 26,
  ),
  action: TerminalKeyBindingAction.text,
  text: 'value $index',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'logical chords match exact modifier state and preserve unicode IDs',
    () {
      final chord = TerminalKeyChord(
        keyId: LogicalKeyboardKey.keyK.keyId,
        ctrl: true,
        alt: true,
      );
      const event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyK,
        physicalKey: PhysicalKeyboardKey.keyK,
        timeStamp: Duration.zero,
      );
      expect(
        chord.matches(event, ctrl: true, alt: true, shift: false, meta: false),
        isTrue,
      );
      expect(
        chord.matches(event, ctrl: true, alt: true, shift: true, meta: false),
        isFalse,
      );
      expect(
        chord.matches(event, ctrl: true, alt: false, shift: false, meta: false),
        isFalse,
      );
      expect(chord.label, 'Ctrl+Alt+K');
      final unicode = TerminalKeyChord(keyId: 'é'.runes.single, alt: true);
      expect(TerminalKeyChord.fromJson(unicode.toJson()), unicode);
    },
  );

  test(
    'plain typing, modifiers and unstable logical IDs cannot become shortcuts',
    () {
      for (final id in [
        LogicalKeyboardKey.keyA.keyId,
        LogicalKeyboardKey.space.keyId,
        LogicalKeyboardKey.shiftLeft.keyId,
        LogicalKeyboardKey.capsLock.keyId,
        0,
        -1,
        0xd800,
        0x110000,
        0x1020000ffff,
      ]) {
        expect(() => TerminalKeyChord(keyId: id), throwsFormatException);
      }
      expect(
        () =>
            TerminalKeyChord(keyId: LogicalKeyboardKey.keyA.keyId, shift: true),
        throwsFormatException,
      );
      expect(TerminalKeyChord(keyId: LogicalKeyboardKey.f7.keyId).label, 'F7');
      expect(
        TerminalKeyChord(keyId: LogicalKeyboardKey.arrowUp.keyId).label,
        'Arrow Up',
      );
    },
  );

  test('workspace, copy, search and interrupt shortcuts retain priority', () {
    for (final key in [
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketRight,
    ]) {
      expect(
        TerminalKeyChord(
          keyId: key.keyId,
          ctrl: true,
          shift: true,
        ).isReserved(apple: false),
        isTrue,
        reason: key.keyLabel,
      );
    }
    for (final key in [
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketRight,
    ]) {
      expect(
        TerminalKeyChord(keyId: key.keyId, meta: true).isReserved(apple: true),
        isTrue,
      );
    }
    expect(
      TerminalKeyChord(
        keyId: LogicalKeyboardKey.arrowUp.keyId,
        meta: true,
        alt: true,
      ).isReserved(apple: true),
      isTrue,
    );
    expect(
      TerminalKeyChord(
        keyId: LogicalKeyboardKey.arrowDown.keyId,
        ctrl: true,
        alt: true,
      ).isReserved(apple: false),
      isTrue,
    );
    expect(
      TerminalKeyChord(
        keyId: LogicalKeyboardKey.keyC.keyId,
        ctrl: true,
      ).isReserved(apple: true),
      isTrue,
    );
    expect(
      TerminalKeyChord(
        keyId: LogicalKeyboardKey.keyK.keyId,
        ctrl: true,
        alt: true,
      ).isReserved(apple: false),
      isFalse,
    );
  });

  test('text mappings preserve literal text and never append an Enter', () {
    final binding = TerminalKeyBinding(
      chord: _binding(0).chord,
      action: TerminalKeyBindingAction.text,
      text:
          r'echo $HOME \n'
          ' café🙂',
    );
    final restored = TerminalKeyBinding.fromJson(
      jsonDecode(jsonEncode(binding.toJson())),
    );
    expect(restored.toJson(), binding.toJson());
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    addTearDown(terminal.dispose);
    restored.input.applyTo(terminal);
    expect(output, [binding.text]);
    expect(output.single, isNot(endsWith('\r')));
  });

  test('key actions use each recipients cursor and keyboard modes', () {
    final binding = TerminalKeyBinding(
      chord: _binding(0).chord,
      action: TerminalKeyBindingAction.key,
      key: TerminalKey.arrowUp,
    );
    final normalOutput = <String>[];
    final applicationOutput = <String>[];
    final kittyOutput = <String>[];
    final normal = Terminal(onOutput: normalOutput.add);
    final application = Terminal(onOutput: applicationOutput.add)
      ..write('\x1b[?1h');
    final kitty = Terminal(onOutput: kittyOutput.add)..write('\x1b[>3u');
    addTearDown(() {
      normal.dispose();
      application.dispose();
      kitty.dispose();
    });
    binding.input.applyTo(normal);
    binding.input.applyTo(application);
    binding.input.applyTo(kitty);
    expect(normalOutput, ['\x1b[A']);
    expect(applicationOutput, ['\x1bOA']);
    expect(kittyOutput, ['\x1b[A', '\x1b[1;1:3A']);
  });

  test('printable key taps include explicit text only for legacy fallback', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    addTearDown(terminal.dispose);
    TerminalKeyBinding(
      chord: _binding(0).chord,
      action: TerminalKeyBindingAction.key,
      key: TerminalKey.keyA,
    ).input.applyTo(terminal);
    TerminalKeyBinding(
      chord: _binding(0).chord,
      action: TerminalKeyBindingAction.key,
      key: TerminalKey.digit1,
      shift: true,
    ).input.applyTo(terminal);
    TerminalKeyBinding(
      chord: _binding(0).chord,
      action: TerminalKeyBindingAction.key,
      key: TerminalKey.keyA,
      ctrl: true,
    ).input.applyTo(terminal);
    expect(output, ['a', '!', '\x01']);
  });

  test('payloads and action schemas are bounded and fail closed', () {
    for (final text in ['', 'x' * 4097, '\x1b[A', '\x03', '\x9b31m']) {
      expect(
        () => TerminalKeyBinding(
          chord: _binding(0).chord,
          action: TerminalKeyBindingAction.text,
          text: text,
        ),
        throwsFormatException,
      );
    }
    expect(TerminalKeyBinding.isValidText('one\ntwo\tthree\r'), isTrue);
    final valid = _binding(0).toJson();
    for (final change in <Map<String, Object?>>[
      {'enabled': 'true'},
      {'chord': null},
      {
        'action': {'kind': 'execute'},
      },
      {
        'action': {'kind': 'text', 'text': 42},
      },
      {
        'action': {
          'kind': 'key',
          'key': 'none',
          'ctrl': false,
          'alt': false,
          'shift': false,
          'meta': false,
        },
      },
    ]) {
      expect(
        () => TerminalKeyBinding.fromJson({...valid, ...change}),
        throwsFormatException,
      );
    }
    expect(
      () => TerminalKeyBinding(
        chord: _binding(0).chord,
        action: TerminalKeyBindingAction.key,
        key: TerminalKey.none,
      ),
      throwsFormatException,
    );
  });

  group('local store', () {
    late TerminalKeyBindings store;
    String? raw;
    var writes = 0;
    setUp(() {
      raw = null;
      writes = 0;
      store = TerminalKeyBindings(
        read: () async => raw,
        write: (value) async {
          writes++;
          raw = value;
        },
      );
    });

    test(
      'serializes concurrent additions, edits, disabling and deletion',
      () async {
        await Future.wait([
          for (var i = 0; i < 12; i++) store.save(_binding(i)),
        ]);
        expect(await store.load(), hasLength(12));
        final original = (await store.load())[3];
        await store.save(
          original.copyWith(enabled: false),
          replacing: original.chord,
        );
        expect((await store.load())[3].enabled, isFalse);
        final changed = _binding(20);
        await store.save(changed, replacing: original.chord);
        expect((await store.load())[3].chord, changed.chord);
        await store.delete(changed.chord);
        expect(await store.load(), hasLength(11));
        expect(jsonDecode(raw!)['version'], 1);
        final bindings = await store.load();
        expect(() => bindings.clear(), throwsUnsupportedError);
      },
    );

    test('never silently overwrites another chord while editing', () async {
      await store.save(_binding(0));
      await store.save(_binding(1));
      final before = raw;
      await expectLater(store.save(_binding(0)), throwsStateError);
      await expectLater(
        store.save(_binding(0), replacing: _binding(1).chord),
        throwsStateError,
      );
      await expectLater(
        store.save(_binding(2), replacing: _binding(3).chord),
        throwsStateError,
      );
      expect(raw, before);
    });

    test('bounds mappings and permits an update at capacity', () async {
      for (var i = 0; i < TerminalKeyBindings.maximumBindings; i++) {
        await store.save(_binding(i));
      }
      await expectLater(store.save(_binding(50)), throwsStateError);
      await store.save(
        _binding(0).copyWith(enabled: false),
        replacing: _binding(0).chord,
      );
      expect(await store.load(), hasLength(50));
      expect((await store.load()).first.enabled, isFalse);
    });

    test('corrupt, duplicate and future stores remain untouched', () async {
      for (final invalid in [
        '{bad',
        'null',
        jsonEncode({'version': 2, 'bindings': []}),
        // Whole-valued doubles are ints on Dart web. Keep the VM-only
        // representation check and reject fractions on every backend.
        if (!kIsWeb) jsonEncode({'version': 1.0, 'bindings': []}),
        jsonEncode({'version': 1.5, 'bindings': []}),
        jsonEncode({
          'version': 1,
          'bindings': [null],
        }),
        jsonEncode({
          'version': 1,
          'bindings': [_binding(0).toJson(), _binding(0).toJson()],
        }),
        jsonEncode({
          'version': 1,
          'bindings': [for (var i = 0; i < 51; i++) _binding(i).toJson()],
        }),
        ' ' * (TerminalKeyBindings.maximumStorageLength + 1),
      ]) {
        raw = invalid;
        await expectLater(store.load(), throwsFormatException);
        await expectLater(store.save(_binding(0)), throwsFormatException);
        await expectLater(
          store.delete(_binding(0).chord),
          throwsFormatException,
        );
        expect(raw, invalid);
      }
      expect(writes, 0);
    });

    test(
      'default stores coordinate and backend failures release the lock',
      () async {
        SharedPreferences.setMockInitialValues({});
        final first = TerminalKeyBindings();
        final second = TerminalKeyBindings();
        await Future.wait([first.save(_binding(0)), second.save(_binding(1))]);
        expect(await first.load(), hasLength(2));
        var fail = true;
        final failing = TerminalKeyBindings(
          read: () async => raw,
          write: (value) async {
            if (fail) throw StateError('unavailable');
            raw = value;
          },
        );
        await expectLater(failing.save(_binding(0)), throwsStateError);
        fail = false;
        await failing.save(_binding(0));
        expect(await failing.load(), hasLength(1));
      },
    );
  });
}
