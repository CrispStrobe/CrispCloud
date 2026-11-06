import 'dart:async';

import 'sandbox_shell.dart';
import 'terminal_connection.dart';

/// Terminal transport backed by [SandboxShell] instead of a host PTY.
///
/// It implements the small amount of line discipline a terminal needs (echo,
/// backspace, cursor movement, history, Ctrl+C/L/D) so the xterm surface behaves
/// like an interactive shell without spawning an executable.
class SandboxShellConnection implements TerminalConnection {
  SandboxShellConnection(this.shell) {
    _output = StreamController<String>(onListen: _start);
  }

  final SandboxShell shell;
  late final StreamController<String> _output;
  final Completer<int?> _exit = Completer<int?>();
  bool _closed = false;
  bool _started = false;
  String _line = '';
  int _cursor = 0;
  int _historyIndex = -1;
  String _draft = '';
  Future<void> _queue = Future<void>.value();

  @override
  bool get isSandbox => true;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int?> get exitCode => _exit.future;

  void _start() {
    if (_started) return;
    _started = true;
    _output.add(_terminalText(shell.welcome));
    _writePrompt();
  }

  @override
  Future<void> write(String data) {
    if (_closed || data.isEmpty) return Future<void>.value();
    _queue = _queue.then((_) => _handle(data)).catchError((Object _) {});
    return _queue;
  }

  @override
  Future<void> resize(int columns, int rows) async {}

  Future<void> _handle(String data) async {
    var index = 0;
    while (index < data.length && !_closed) {
      final code = data.codeUnitAt(index);
      if (code == 0x1b) {
        final consumed = _handleEscape(data, index);
        if (consumed == 0) break; // Incomplete escape sequence.
        index += consumed;
        continue;
      }
      if (code == 0x0d || code == 0x0a) {
        if (code == 0x0d &&
            index + 1 < data.length &&
            data.codeUnitAt(index + 1) == 0x0a) {
          index++;
        }
        index++;
        await _submit();
        continue;
      }
      switch (code) {
        case 0x7f:
        case 0x08:
          _deleteBefore();
        case 0x03:
          _line = '';
          _cursor = 0;
          _historyIndex = -1;
          _output.add('^C\r\n');
          _writePrompt();
        case 0x04:
          if (_line.isEmpty) {
            await close();
          } else {
            _deleteAt();
          }
        case 0x0c:
          _output.add('\x1b[2J\x1b[H');
          _redraw();
        case 0x01:
          _cursor = 0;
          _redraw();
        case 0x05:
          _cursor = _line.length;
          _redraw();
        case 0x0b:
          _line = _line.substring(0, _cursor);
          _redraw();
        case 0x15:
          _line = _line.substring(_cursor);
          _cursor = 0;
          _redraw();
        case 0x17:
          _deleteWord();
        case 0x09:
          _insert('    ');
        default:
          if (code < 0x20) break;
          if (code >= 0xd800 && code <= 0xdbff && index + 1 < data.length) {
            final next = data.codeUnitAt(index + 1);
            if (next >= 0xdc00 && next <= 0xdfff) {
              _insert(String.fromCharCodes(<int>[code, next]));
              index++;
              break;
            }
          }
          _insert(String.fromCharCode(code));
      }
      index++;
    }
  }

  /// Returns the number of code units consumed, or zero when the sequence is
  /// incomplete and must wait for the next terminal write.
  int _handleEscape(String data, int start) {
    if (start + 1 >= data.length) return 0;
    final second = data.codeUnitAt(start + 1);
    if (second == 0x4f && start + 2 < data.length) {
      _handleEscapeFinal(data[start + 2]);
      return 3;
    }
    if (second != 0x5b) return 2;
    var end = start + 2;
    while (end < data.length) {
      final code = data.codeUnitAt(end);
      if (code >= 0x40 && code <= 0x7e) break;
      end++;
    }
    if (end >= data.length) return 0;
    final sequence = data.substring(start, end + 1);
    if (sequence == '\x1b[200~' || sequence == '\x1b[201~') {
      return sequence.length;
    }
    final finalChar = data[end];
    if (finalChar == '~') {
      final number = int.tryParse(data.substring(start + 2, end));
      if (number == 3) _deleteAt();
      if (number == 1 || number == 7) {
        _cursor = 0;
        _redraw();
      }
      if (number == 4 || number == 8) {
        _cursor = _line.length;
        _redraw();
      }
    } else {
      _handleEscapeFinal(finalChar);
    }
    return sequence.length;
  }

  void _handleEscapeFinal(String finalChar) {
    switch (finalChar) {
      case 'A':
        _historyUp();
      case 'B':
        _historyDown();
      case 'C':
        if (_cursor < _line.length) {
          _cursor++;
          _redraw();
        }
      case 'D':
        if (_cursor > 0) {
          _cursor--;
          _redraw();
        }
      case 'H':
        _cursor = 0;
        _redraw();
      case 'F':
        _cursor = _line.length;
        _redraw();
    }
  }

  void _insert(String text) {
    _line = _line.substring(0, _cursor) + text + _line.substring(_cursor);
    _cursor += text.length;
    _redraw();
  }

  void _deleteBefore() {
    if (_cursor == 0) return;
    var start = _cursor - 1;
    if (start > 0 &&
        _isLowSurrogate(_line.codeUnitAt(start)) &&
        _isHighSurrogate(_line.codeUnitAt(start - 1))) {
      start--;
    }
    _line = _line.substring(0, start) + _line.substring(_cursor);
    _cursor = start;
    _redraw();
  }

  void _deleteAt() {
    if (_cursor >= _line.length) return;
    var end = _cursor + 1;
    if (end < _line.length &&
        _isHighSurrogate(_line.codeUnitAt(_cursor)) &&
        _isLowSurrogate(_line.codeUnitAt(end))) {
      end++;
    }
    _line = _line.substring(0, _cursor) + _line.substring(end);
    _redraw();
  }

  void _deleteWord() {
    var start = _cursor;
    while (start > 0 && _line.codeUnitAt(start - 1) == 0x20) {
      start--;
    }
    while (start > 0 && _line.codeUnitAt(start - 1) != 0x20) {
      start--;
    }
    _line = _line.substring(0, start) + _line.substring(_cursor);
    _cursor = start;
    _redraw();
  }

  bool _isHighSurrogate(int code) => code >= 0xd800 && code <= 0xdbff;
  bool _isLowSurrogate(int code) => code >= 0xdc00 && code <= 0xdfff;

  void _historyUp() {
    if (shell.history.isEmpty) return;
    if (_historyIndex == -1) {
      _draft = _line;
      _historyIndex = shell.history.length;
    }
    if (_historyIndex > 0) {
      _historyIndex--;
      _line = shell.history[_historyIndex];
      _cursor = _line.length;
      _redraw();
    }
  }

  void _historyDown() {
    if (_historyIndex == -1) return;
    if (_historyIndex < shell.history.length - 1) {
      _historyIndex++;
      _line = shell.history[_historyIndex];
    } else {
      _historyIndex = -1;
      _line = _draft;
    }
    _cursor = _line.length;
    _redraw();
  }

  void _redraw() {
    _output.add('\r\x1b[2K');
    _output.add(shell.prompt);
    _output.add(_line);
    final back = _line.length - _cursor;
    if (back > 0) _output.add('\x1b[${back}D');
  }

  void _writePrompt() {
    _output.add(shell.prompt);
  }

  Future<void> _submit() async {
    final line = _line;
    _line = '';
    _cursor = 0;
    _historyIndex = -1;
    _draft = '';
    _output.add('\r\n');
    if (line.trim().isEmpty) {
      _writePrompt();
      return;
    }
    final result = await shell.executeLine(line);
    if (result.stdout.isNotEmpty) {
      _output.add(_terminalText(result.stdout));
      if (!result.stdout.endsWith('\n')) _output.add('\r\n');
    }
    if (result.stderr.isNotEmpty) {
      _output.add('\x1b[31m${_terminalText(result.stderr)}\x1b[0m');
      if (!result.stderr.endsWith('\n')) _output.add('\r\n');
    }
    if (result.exit) {
      await close();
      return;
    }
    _writePrompt();
  }

  String _terminalText(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _output.close();
    } catch (_) {
      // The consumer may already have detached.
    }
    if (!_exit.isCompleted) _exit.complete(0);
  }
}
