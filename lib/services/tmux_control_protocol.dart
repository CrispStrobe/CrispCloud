import 'dart:convert';
import 'dart:typed_data';

/// A malformed or over-budget tmux control stream cannot be resynchronized.
class TmuxControlProtocolException implements Exception {
  const TmuxControlProtocolException(this.message);
  final String message;
  @override
  String toString() => 'tmux control protocol: $message';
}

sealed class TmuxControlEvent {
  const TmuxControlEvent();
}

/// The byte-exact body between one matched pair of command guards.
class TmuxControlBlock extends TmuxControlEvent {
  const TmuxControlBlock({
    required this.time,
    required this.number,
    required this.flags,
    required this.success,
    required this.lines,
  });

  final String time;
  final String number;
  final String flags;
  final bool success;
  final List<Uint8List> lines;

  String get text =>
      lines.map((line) => utf8.decode(line, allowMalformed: true)).join('\n');
}

class TmuxControlNotification extends TmuxControlEvent {
  const TmuxControlNotification(this.name, this.arguments);
  final String name;
  final Uint8List arguments;
  String get text => utf8.decode(arguments, allowMalformed: true);
}

/// Bounded incremental framing of the single-`-C`, no-PTY wire protocol.
///
/// Keep bytes until a pane has been selected. A UTF-8 character can be split
/// between *different* `%output` records, so decoding the protocol as text first
/// corrupts otherwise valid terminal output. Command bodies are opaque: a
/// `%output`, `%begin`, or nonmatching `%end` inside a body is ordinary data.
/// See https://github.com/tmux/tmux/wiki/Control-Mode.
class TmuxControlParser {
  TmuxControlParser({
    required this.onEvent,
    this.maximumLineBytes = 256 * 1024,
    this.maximumBlockBytes = 2 * 1024 * 1024,
    this.maximumBlockLines = 4096,
  });

  final void Function(TmuxControlEvent) onEvent;
  final int maximumLineBytes;
  final int maximumBlockBytes;
  final int maximumBlockLines;
  final _partial = BytesBuilder(copy: false);
  final _body = <Uint8List>[];
  List<String>? _guard;
  int _bodyBytes = 0;
  bool _finished = false;

  void add(List<int> bytes) {
    if (_finished) return;
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 10) continue;
      _append(bytes, start, i);
      final line = _partial.takeBytes();
      _line(line);
      if (_finished) return;
      start = i + 1;
    }
    _append(bytes, start, bytes.length);
  }

  void _append(List<int> bytes, int start, int end) {
    if (start == end) return;
    if (_partial.length + end - start > maximumLineBytes) {
      throw const TmuxControlProtocolException('A record is too large.');
    }
    _partial.add(bytes.sublist(start, end));
  }

  void _line(Uint8List line) {
    final guard = _guard;
    // Guard syntax is ASCII and short. Do not decode an arbitrary body line.
    final possibleGuard = line.length <= 96 && line.isNotEmpty && line[0] == 37
        ? ascii.decode(line, allowInvalid: true)
        : '';
    if (guard != null) {
      final ending = _end.firstMatch(possibleGuard);
      if (ending != null &&
          ending[2] == guard[0] &&
          ending[3] == guard[1] &&
          ending[4] == guard[2]) {
        final event = TmuxControlBlock(
          time: guard[0],
          number: guard[1],
          flags: guard[2],
          success: ending[1] == 'end',
          lines: List.unmodifiable(_body),
        );
        _body.clear();
        _bodyBytes = 0;
        _guard = null;
        onEvent(event);
        return;
      }
      _bodyBytes += line.length + 1;
      if (_bodyBytes > maximumBlockBytes || _body.length >= maximumBlockLines) {
        throw const TmuxControlProtocolException(
          'A command response is too large.',
        );
      }
      _body.add(line);
      return;
    }
    final opening = _begin.firstMatch(possibleGuard);
    if (opening != null) {
      _guard = [opening[1]!, opening[2]!, opening[3]!];
      return;
    }
    if (line.isEmpty || line[0] != 37) {
      throw const TmuxControlProtocolException(
        'Expected a control-mode record. Use tmux 3.2 or newer.',
      );
    }
    final separator = line.indexOf(32);
    final end = separator < 0 ? line.length : separator;
    if (end > 64 || line.take(end).any((byte) => byte > 127 || byte < 33)) {
      throw const TmuxControlProtocolException('Invalid notification name.');
    }
    final name = ascii.decode(line.sublist(0, end));
    if (name == '%begin' || name == '%end' || name == '%error') {
      throw const TmuxControlProtocolException('Unmatched command guard.');
    }
    onEvent(
      TmuxControlNotification(
        name,
        separator < 0
            ? Uint8List(0)
            : Uint8List.sublistView(line, separator + 1),
      ),
    );
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    if (_partial.length != 0 || _guard != null) {
      throw const TmuxControlProtocolException(
        'The control stream ended early.',
      );
    }
  }

  void stop() {
    _finished = true;
    _partial.clear();
    _body.clear();
    _guard = null;
  }

  static final _begin = RegExp(
    r'^%begin ([0-9]{1,20}) ([0-9]{1,20}) ([0-9]{1,8})$',
  );
  static final _end = RegExp(
    r'^%(end|error) ([0-9]{1,20}) ([0-9]{1,20}) ([0-9]{1,8})$',
  );
}

/// Decodes tmux's octal representation without joining unrelated pane bytes.
Uint8List decodeTmuxOctal(List<int> source) {
  final bytes = BytesBuilder(copy: false);
  for (var i = 0; i < source.length; i++) {
    final value = source[i];
    if (value != 92) {
      bytes.addByte(value);
      continue;
    }
    if (i + 3 >= source.length ||
        source[i + 1] < 48 ||
        source[i + 1] > 51 ||
        source[i + 2] < 48 ||
        source[i + 2] > 55 ||
        source[i + 3] < 48 ||
        source[i + 3] > 55) {
      throw const TmuxControlProtocolException('Invalid octal output escape.');
    }
    bytes.addByte(
      ((source[i + 1] - 48) << 6) |
          ((source[i + 2] - 48) << 3) |
          (source[i + 3] - 48),
    );
    i += 3;
  }
  return bytes.takeBytes();
}
