import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/tmux_control_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'capture escape grammar differs from output for literal backslashes',
    () {
      expect(
        utf8.decode(decodeTmuxCapture(ascii.encode(r'C:\\tmp\\033[31m'))),
        r'C:\tmp\033[31m',
      );
      expect(
        decodeTmuxCapture(ascii.encode(r'\033[31mred\033[0m')),
        ascii.encode('\x1b[31mred\x1b[0m'),
      );
      expect(
        () => decodeTmuxOctal(ascii.encode(r'\\')),
        throwsA(isA<TmuxControlProtocolException>()),
      );
    },
  );
  test(
    'fragments every byte without interpreting notification-like command data',
    () {
      final events = <TmuxControlEvent>[];
      final parser = TmuxControlParser(onEvent: events.add);
      final bytes = utf8.encode(
        '%begin 1700 12 1\n'
        '%output %7 not a notification\n'
        '%begin 1700 99 1\n'
        '%end 1700 99 1\n'
        '%error 1700 12 0\n'
        '%end 1700 12 1\n'
        '%window-renamed @3 Grüße 中 🌍\n',
      );
      for (final byte in bytes) {
        parser.add([byte]);
      }
      parser.finish();
      expect(events, hasLength(2));
      final response = events.first as TmuxControlBlock;
      expect(response.success, isTrue);
      expect(response.time, '1700');
      expect(response.number, '12');
      expect(response.flags, '1');
      expect(response.lines.map((line) => utf8.decode(line)), [
        '%output %7 not a notification',
        '%begin 1700 99 1',
        '%end 1700 99 1',
        '%error 1700 12 0',
      ]);
      final name = events.last as TmuxControlNotification;
      expect(name.name, '%window-renamed');
      expect(name.text, '@3 Grüße 中 🌍');
    },
  );

  test('each possible transport split yields identical guards and output', () {
    final wire = utf8.encode(
      '%begin 1 2 0\n%end 1 2 0\n%output %8 a\\134b\\015\\012\n%exit\n',
    );
    for (var split = 0; split <= wire.length; split++) {
      final events = <TmuxControlEvent>[];
      final parser = TmuxControlParser(onEvent: events.add);
      parser.add(wire.sublist(0, split));
      parser.add(wire.sublist(split));
      parser.finish();
      expect(events, hasLength(3), reason: 'split $split');
      expect(
        (events[1] as TmuxControlNotification).text,
        '%8 a\\134b\\015\\012',
      );
      expect((events[2] as TmuxControlNotification).arguments, isEmpty);
    }
  });

  test('raw high bytes survive separate output records', () {
    final events = <TmuxControlEvent>[];
    final parser = TmuxControlParser(onEvent: events.add);
    parser.add([
      ...ascii.encode('%output %1 '),
      0xf0,
      0x9f,
      10,
      ...ascii.encode('%output %1 '),
      0x8c,
      0x8d,
      10,
    ]);
    expect((events[0] as TmuxControlNotification).arguments.sublist(3), [
      0xf0,
      0x9f,
    ]);
    expect((events[1] as TmuxControlNotification).arguments.sublist(3), [
      0x8c,
      0x8d,
    ]);
  });

  test('empty response and matching error response are distinct', () {
    final events = <TmuxControlEvent>[];
    final parser = TmuxControlParser(onEvent: events.add);
    parser.add(
      ascii.encode(
        '%begin 2 3 1\n%end 2 3 1\n%begin 2 4 1\nno target\n%error 2 4 1\n',
      ),
    );
    expect((events[0] as TmuxControlBlock).lines, isEmpty);
    expect((events[1] as TmuxControlBlock).success, isFalse);
    expect((events[1] as TmuxControlBlock).text, 'no target');
  });

  test('unmatched standalone guards and nonprotocol text fail closed', () {
    for (final input in [
      '%end 1 2 1\n',
      '%error 1 2 1\n',
      '%begin bad\n',
      'shell prompt\n',
      '\n',
    ]) {
      final parser = TmuxControlParser(onEvent: (_) {});
      expect(
        () => parser.add(ascii.encode(input)),
        throwsA(isA<TmuxControlProtocolException>()),
        reason: input,
      );
    }
  });

  test('EOF during a line or command never produces a successful response', () {
    for (final input in [
      '%output %0 partial',
      '%begin 1 2 1\n',
      '%begin 1 2 1\nbody\n%end 1 3 1\n',
    ]) {
      final events = <TmuxControlEvent>[];
      final parser = TmuxControlParser(onEvent: events.add)
        ..add(ascii.encode(input));
      expect(parser.finish, throwsA(isA<TmuxControlProtocolException>()));
      expect(events, isEmpty);
    }
  });

  test(
    'line limit applies across chunks and before allocating a whole line',
    () {
      final parser = TmuxControlParser(onEvent: (_) {}, maximumLineBytes: 12);
      parser.add(ascii.encode('%output %0 '));
      expect(
        () => parser.add(ascii.encode('ab')),
        throwsA(isA<TmuxControlProtocolException>()),
      );
    },
  );

  test('response bytes and response line count are independently bounded', () {
    final bytes = TmuxControlParser(onEvent: (_) {}, maximumBlockBytes: 4);
    bytes.add(ascii.encode('%begin 1 2 1\nabc\n'));
    expect(
      () => bytes.add(ascii.encode('x\n')),
      throwsA(isA<TmuxControlProtocolException>()),
    );
    final lines = TmuxControlParser(onEvent: (_) {}, maximumBlockLines: 2);
    lines.add(ascii.encode('%begin 1 2 1\n\n\n'));
    expect(() => lines.add([10]), throwsA(isA<TmuxControlProtocolException>()));
  });

  test('stop discards partial data and revokes future callbacks', () {
    final events = <TmuxControlEvent>[];
    final parser = TmuxControlParser(onEvent: events.add);
    parser.add(ascii.encode('%begin 1 2 1\nbody'));
    parser.stop();
    parser.add(ascii.encode('\n%end 1 2 1\n%exit\n'));
    parser.finish();
    expect(events, isEmpty);
  });

  test('octal decoding preserves every byte and rejects ambiguous escapes', () {
    final escaped = ascii.encode(
      List.generate(
        256,
        (value) => '\\${value.toRadixString(8).padLeft(3, '0')}',
      ).join(),
    );
    expect(
      decodeTmuxOctal(escaped),
      Uint8List.fromList(List.generate(256, (value) => value)),
    );
    for (final value in ['\\', '\\00', '\\400', '\\999', '\\x1b', '\\12a']) {
      expect(
        () => decodeTmuxOctal(ascii.encode(value)),
        throwsA(isA<TmuxControlProtocolException>()),
        reason: value,
      );
    }
    expect(
      utf8.decode(decodeTmuxOctal(utf8.encode('Grüße 中 🌍\\134'))),
      'Grüße 中 🌍\\',
    );
  });
}
