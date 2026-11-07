import 'package:characters/characters.dart';

/// The local engine has FILE streams, not an OS PTY. This small canonical input
/// discipline supplies echo/editing for Dash and line-oriented commands. It does
/// not claim raw-mode, job-control or full-screen-program compatibility.
class InputAction {
  const InputAction(this.kind, [this.text = '']);
  final String kind;
  final String text;
}

class CanonicalInput {
  final List<String> _line = [];
  final List<String> _history = [];
  int _cursor = 0;
  int? _historyIndex;
  String _draft = '';
  String _escape = '';
  bool _afterCr = false;
  static const maxLineLength = 16384;

  List<InputAction> accept(String input) {
    final result = <InputAction>[];
    for (final character in input.characters) {
      if (_escape.isNotEmpty) {
        _escape += character;
        if (_escape == '\x1b[' || _escape == '\x1bO') continue;
        if (RegExp(r'^\x1b\[[0-9;]*$').hasMatch(_escape)) continue;
        _handleEscape(_escape, result);
        _escape = '';
        continue;
      }
      if (character == '\x1b') {
        _escape = character;
        continue;
      }
      if (character == '\n' && _afterCr) {
        _afterCr = false;
        continue;
      }
      _afterCr = character == '\r';
      switch (character) {
        case '\r':
        case '\n':
        case '\r\n':
          final value = _line.join();
          if (value.isNotEmpty && (_history.isEmpty || _history.last != value)) {
            _history.add(value);
            if (_history.length > 100) _history.removeAt(0);
          }
          result.add(const InputAction('echo', '\r\n'));
          result.add(InputAction('write', '$value\n'));
          _reset();
        case '\x03':
          result.add(const InputAction('echo', '^C\r\n'));
          result.add(const InputAction('interrupt'));
          _reset();
        case '\x04':
          if (_line.isEmpty) {
            result.add(const InputAction('eof'));
          } else {
            result.add(InputAction('write', _line.join()));
            _reset();
          }
        case '\x7f':
        case '\b':
          if (_cursor > 0) {
            final width = _width(_line[_cursor - 1]);
            _line.removeAt(--_cursor);
            result.add(InputAction('echo', '${_left(width)}${_tail()}'));
          }
        case '\x01':
          _move(0, result);
        case '\x05':
          _move(_line.length, result);
        case '\x15':
          _replace('', result);
        case '\x0b':
          _line.removeRange(_cursor, _line.length);
          result.add(const InputAction('echo', '\x1b[K'));
        case '\x17':
          var position = _cursor;
          while (position > 0 && _line[position - 1].trim().isEmpty) {
            position--;
          }
          while (position > 0 && _line[position - 1].trim().isNotEmpty) {
            position--;
          }
          final width = _length(_line.sublist(position, _cursor));
          _line.removeRange(position, _cursor);
          _cursor = position;
          result.add(InputAction('echo', '${_left(width)}${_tail()}'));
        default:
          if (character.codeUnitAt(0) < 32 && character != '\t') continue;
          if (_line.length >= maxLineLength) {
            result.add(const InputAction('echo', '\x07'));
            continue;
          }
          // Tabs are accepted literally; the terminal advances to a tab stop.
          _line.insert(_cursor++, character);
          result.add(InputAction('echo', '$character${_tail()}'));
      }
    }
    return result;
  }

  void _handleEscape(String escape, List<InputAction> actions) {
    switch (escape) {
      case '\x1b[D':
      case '\x1bOD':
        _move(_cursor - 1, actions);
      case '\x1b[C':
      case '\x1bOC':
        _move(_cursor + 1, actions);
      case '\x1b[H':
      case '\x1bOH':
      case '\x1b[1~':
        _move(0, actions);
      case '\x1b[F':
      case '\x1bOF':
      case '\x1b[4~':
        _move(_line.length, actions);
      case '\x1b[3~':
        if (_cursor < _line.length) {
          _line.removeAt(_cursor);
          actions.add(InputAction('echo', _tail()));
        }
      case '\x1b[A':
        if (_history.isNotEmpty) {
          if (_historyIndex == null) _draft = _line.join();
          _historyIndex = ((_historyIndex ?? _history.length) - 1)
              .clamp(0, _history.length - 1);
          _replace(_history[_historyIndex!], actions);
        }
      case '\x1b[B':
        if (_historyIndex != null) {
          _historyIndex = _historyIndex! + 1;
          if (_historyIndex! >= _history.length) {
            _historyIndex = null;
            _replace(_draft, actions);
          } else {
            _replace(_history[_historyIndex!], actions);
          }
        }
      // Bracketed paste boundaries and unsupported terminal keys are ignored.
      default:
        break;
    }
  }

  void _reset() {
    _line.clear();
    _cursor = 0;
    _historyIndex = null;
    _draft = '';
  }

  void _replace(String text, List<InputAction> actions) {
    final back = _left(_length(_line.take(_cursor)));
    _line
      ..clear()
      ..addAll(text.characters);
    _cursor = _line.length;
    actions.add(InputAction('echo', '$back\x1b[K$text'));
  }

  void _move(int index, List<InputAction> actions) {
    final next = index.clamp(0, _line.length);
    final width = _length(_line.sublist(
      next < _cursor ? next : _cursor,
      next > _cursor ? next : _cursor,
    ));
    if (width != 0) {
      actions.add(InputAction('echo', '\x1b[$width${next < _cursor ? 'D' : 'C'}'));
    }
    _cursor = next;
  }

  String _tail() {
    final tail = _line.skip(_cursor);
    return '${tail.join()}\x1b[K${_left(_length(tail))}';
  }

  static String _left(int count) => count > 0 ? '\x1b[${count}D' : '';
  static int _length(Iterable<String> values) =>
      values.fold(0, (sum, value) => sum + _width(value));

  static int _width(String value) {
    final rune = value.runes.first;
    return (rune >= 0x1100 &&
            (rune <= 0x115f ||
                (rune >= 0x2e80 && rune <= 0xa4cf) ||
                (rune >= 0xac00 && rune <= 0xd7a3) ||
                (rune >= 0xf900 && rune <= 0xfaff) ||
                (rune >= 0xfe10 && rune <= 0xfe6f) ||
                (rune >= 0xff01 && rune <= 0xff60) ||
                (rune >= 0x1f000 && rune <= 0x1faff) ||
                rune >= 0x20000))
        ? 2
        : 1;
  }
}
