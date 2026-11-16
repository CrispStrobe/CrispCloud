import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/terminal_trigger.dart';
import '../utils/async_lock.dart';

/// Versioned local rules. Corrupt/newer records remain intact on failed writes.
class TerminalTriggers {
  TerminalTriggers({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _lock = read == null ? _preferencesLock : AsyncLock() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both terminal trigger storage callbacks');
    }
  }

  static const preferencesKey = 'terminal_output_triggers_v1';
  static const maximumTriggers = 50;
  static const maximumStorageLength = 128 * 1024;
  static final _preferencesLock = AsyncLock();
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final AsyncLock _lock;

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(preferencesKey, value)) {
      throw StateError('Terminal trigger storage failed');
    }
  }

  Future<List<TerminalTrigger>> load() => _lock.synchronized(_load);

  Future<List<TerminalTrigger>> _load() async {
    final raw = await _read();
    if (raw == null) return const [];
    if (raw.length > maximumStorageLength) {
      throw const FormatException('Terminal trigger store exceeds limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['triggers'] is! List) {
      throw const FormatException('Unsupported terminal trigger store');
    }
    final entries = data['triggers'] as List;
    if (entries.length > maximumTriggers) {
      throw const FormatException('Too many terminal triggers');
    }
    final ids = <String>{};
    final triggers = <TerminalTrigger>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid terminal trigger record');
      }
      final trigger = TerminalTrigger.fromJson(entry);
      if (!ids.add(trigger.id)) {
        throw const FormatException('Duplicate terminal trigger');
      }
      triggers.add(trigger);
    }
    return List.unmodifiable(triggers);
  }

  Future<void> save(TerminalTrigger trigger, {String? replacing}) =>
      _lock.synchronized(() async {
        final triggers = (await _load()).toList();
        final previous = replacing == null
            ? -1
            : triggers.indexWhere((item) => item.id == replacing);
        if (replacing != null && previous < 0) {
          throw StateError('Terminal trigger changed while editing');
        }
        if (triggers.asMap().entries.any(
          (entry) => entry.key != previous && entry.value.id == trigger.id,
        )) {
          throw StateError('Terminal trigger already exists');
        }
        if (previous < 0) {
          if (triggers.length >= maximumTriggers) {
            throw StateError('Terminal trigger limit reached');
          }
          triggers.add(trigger);
        } else {
          triggers[previous] = trigger;
        }
        await _persist(triggers);
      });

  Future<void> delete(String id) => _lock.synchronized(() async {
    final triggers = (await _load()).where((item) => item.id != id).toList();
    await _persist(triggers);
  });

  Future<void> _persist(List<TerminalTrigger> triggers) async {
    final value = jsonEncode({
      'version': 1,
      'triggers': triggers.map((item) => item.toJson()).toList(),
    });
    if (value.length > maximumStorageLength) {
      throw StateError('Terminal trigger store exceeds limit');
    }
    await _write(value);
  }
}

class TerminalTriggerMatch {
  const TerminalTriggerMatch(this.trigger, this.line);
  final TerminalTrigger trigger;
  final String line;
}

enum _OutputState { text, escape, csi, string, stringEscape, charset }

/// Bounded observation of decoded transport output, independent of scrollback.
///
/// This is a line observer, not a second terminal emulator. It strips control
/// strings and styling, handles CR/backspace/erase-line progress output, and
/// discards lines containing other cursor movement. Alternate-screen output is
/// excluded. Feed only incoming transport text, before rendering it; never feed
/// input, protocol responses, or in-app notifications back into this observer.
class TerminalTriggerEngine {
  TerminalTriggerEngine({required this.onMatch, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const maximumLineLength = 4096;
  static const maximumActionsPerSecond = 10;
  static const maximumMatchWorkPerSecond = 2 * 1000 * 1000;
  final void Function(TerminalTriggerMatch) onMatch;
  final DateTime Function() _now;
  List<TerminalTrigger> _triggers = const [];
  final _lastFired = <String, DateTime>{};
  final _fired = <String>{};
  final _line = <int>[];
  int _cursor = 0;
  bool _invalidLine = false;
  bool _alternate = false;
  bool _feeding = false;
  bool _finished = false;
  bool _stringIsOsc = false;
  int? _highSurrogate;
  _OutputState _state = _OutputState.text;
  String _csi = '';
  DateTime? _burstStart;
  int _burstCount = 0;
  int _matchWork = 0;
  int _skippedLines = 0;

  /// Completed lines skipped because all eligible matching would exceed the
  /// observer's budget. Output rendering continues independently.
  int get skippedLines => _skippedLines;

  void updateTriggers(List<TerminalTrigger> triggers) {
    if (triggers.length > TerminalTriggers.maximumTriggers ||
        triggers.map((item) => item.id).toSet().length != triggers.length) {
      throw const FormatException('Invalid terminal trigger list');
    }
    final ids = triggers.map((item) => item.id).toSet();
    _lastFired.removeWhere((id, _) => !ids.contains(id));
    _fired.removeWhere((id) => !ids.contains(id));
    _triggers = List.unmodifiable(triggers);
  }

  /// A new transport starts a fresh observation lifetime. Rules remain loaded.
  void reset() {
    _lastFired.clear();
    _fired.clear();
    _clearLine();
    _alternate = false;
    _state = _OutputState.text;
    _csi = '';
    _highSurrogate = null;
    _burstStart = null;
    _burstCount = 0;
    _matchWork = 0;
    _skippedLines = 0;
    _finished = false;
  }

  void addOutput(String data, {bool alternateScreen = false}) {
    if (_feeding || _finished) return;
    _feeding = true;
    try {
      // The caller may know about a screen switch written outside the normal
      // transport stream. CSI switches within this chunk remain authoritative.
      if (alternateScreen && !_alternate) {
        _alternate = true;
        _clearLine();
      }
      for (final unit in data.codeUnits) {
        final high = _highSurrogate;
        _highSurrogate = null;
        if (high != null) {
          if (unit >= 0xdc00 && unit <= 0xdfff) {
            _accept(0x10000 + ((high - 0xd800) << 10) + unit - 0xdc00);
            continue;
          }
          _accept(0xfffd);
        }
        if (unit >= 0xd800 && unit <= 0xdbff) {
          _highSurrogate = unit;
        } else {
          _accept(unit >= 0xdc00 && unit <= 0xdfff ? 0xfffd : unit);
        }
      }
    } finally {
      _feeding = false;
    }
  }

  /// The final unterminated line may match once when transport output ends.
  void finish() {
    if (_feeding || _finished) return;
    _finished = true;
    if (_highSurrogate != null) {
      _highSurrogate = null;
      _put(0xfffd);
    }
    if (_state == _OutputState.text && _line.isNotEmpty) _completeLine();
    _clearLine();
  }

  void _accept(int rune) {
    if (_state == _OutputState.string) {
      if ((_stringIsOsc && rune == 7) || rune == 0x9c) {
        _state = _OutputState.text;
      } else if (rune == 27) {
        _state = _OutputState.stringEscape;
      }
      return;
    }
    if (_state == _OutputState.stringEscape) {
      _state = rune == 92 || rune == 0x9c || (_stringIsOsc && rune == 7)
          ? _OutputState.text
          : rune == 27
          ? _OutputState.stringEscape
          : _OutputState.string;
      return;
    }
    if (_state == _OutputState.charset) {
      _state = _OutputState.text;
      return;
    }
    if (_state == _OutputState.escape) {
      _state = _OutputState.text;
      if (rune == 91) {
        _state = _OutputState.csi;
        _csi = '';
      } else if (const {93, 80, 88, 94, 95}.contains(rune)) {
        _state = _OutputState.string;
        _stringIsOsc = rune == 93;
      } else if (const {40, 41, 42, 43, 45, 46, 47}.contains(rune)) {
        _state = _OutputState.charset;
      } else if (rune == 27) {
        _state = _OutputState.escape;
      } else if (rune != 92) {
        _invalidLine = true;
      }
      return;
    }
    if (_state == _OutputState.csi) {
      if (rune >= 0x40 && rune <= 0x7e) {
        _handleCsi(String.fromCharCode(rune));
        _state = _OutputState.text;
        _csi = '';
      } else if (rune == 27) {
        _state = _OutputState.escape;
      } else if (_csi.length < 128 && rune >= 0x20 && rune <= 0x3f) {
        _csi += String.fromCharCode(rune);
      } else {
        _invalidLine = true;
        // Keep dropping until the sequence ends, without retaining its bytes.
      }
      return;
    }
    if (rune == 27) {
      _state = _OutputState.escape;
    } else if (rune == 0x9b) {
      _state = _OutputState.csi;
      _csi = '';
    } else if (const {0x90, 0x98, 0x9d, 0x9e, 0x9f}.contains(rune)) {
      _state = _OutputState.string;
      _stringIsOsc = rune == 0x9d;
    } else if (rune == 10) {
      _completeLine();
      _clearLine();
    } else if (rune == 13) {
      _cursor = 0;
    } else if (rune == 8) {
      if (_cursor > 0) _cursor--;
    } else if (rune == 9) {
      final end = (_cursor ~/ 8 + 1) * 8;
      while (_cursor < end && !_invalidLine && !_alternate) {
        _put(32);
      }
    } else if (rune >= 32 && !(rune >= 0x7f && rune <= 0x9f)) {
      _put(rune);
    }
  }

  void _put(int rune) {
    if (_alternate || _invalidLine) return;
    if (_cursor >= maximumLineLength) {
      _line.clear();
      _invalidLine = true;
      return;
    }
    if (_cursor < _line.length) {
      _line[_cursor] = rune;
    } else {
      _line.add(rune);
    }
    _cursor++;
  }

  void _handleCsi(String finalByte) {
    if ((finalByte == 'h' || finalByte == 'l') && _csi.startsWith('?')) {
      final modes = _csi.substring(1).split(';');
      if (modes.any(const {'47', '1047', '1049'}.contains)) {
        _alternate = finalByte == 'h';
        _clearLine();
      }
      // Origin, insert, wrapping and scrolling modes affect how a line is
      // displayed. Ignore only known non-text modes; invalidate everything else.
      if (modes.any((mode) => !const {
        '1', '12', '25', '47', '1047', '1049', '1000', '1002', '1003',
        '1004', '1005', '1006', '1015', '2004',
      }.contains(mode))) {
        _invalidLine = true;
      }
      return;
    }
    if (finalByte == 'm') return; // Graphics rendition never changes text.
    if (finalByte == 'K' && !_alternate && !_invalidLine) {
      if (_csi.isEmpty || _csi == '0') {
        if (_cursor < _line.length) _line.removeRange(_cursor, _line.length);
      } else if (_csi == '1') {
        for (var i = 0; i <= _cursor && i < _line.length; i++) {
          _line[i] = 32;
        }
      } else if (_csi == '2') {
        _line.clear();
        // Erase does not move the terminal cursor.
        _line.addAll(List.filled(_cursor, 32));
      } else {
        _invalidLine = true;
      }
      return;
    }
    // Terminal replies, keyboard protocol, cursor visibility and mode changes
    // do not constitute printable text. Cursor/screen edits invalidate the line.
    if (finalByte == 'u' &&
        (_csi.startsWith('>') || _csi.startsWith('<') ||
          _csi.startsWith('=') || _csi.startsWith('?'))) return;
    if (const {'n', 'c'}.contains(finalByte)) return;
    _invalidLine = true;
  }

  void _clearLine() {
    _line.clear();
    _cursor = 0;
    _invalidLine = false;
  }

  void _completeLine() {
    if (_alternate || _invalidLine || _line.isEmpty) return;
    final line = String.fromCharCodes(_line);
    final now = _now();
    if (_burstStart == null || now.difference(_burstStart!).inSeconds >= 1) {
      _burstStart = now;
      _burstCount = 0;
      _matchWork = 0;
    }
    final eligible = <TerminalTrigger>[];
    for (final trigger in _triggers) {
      if (!trigger.enabled ||
          (trigger.oncePerSession && _fired.contains(trigger.id))) {
        continue;
      }
      eligible.add(trigger);
    }
    if (eligible.isEmpty) return;
    final work = _line.length * eligible.fold(0, (sum, rule) => sum + rule.matchWorkPerRune);
    // Reserve the whole line before matching. Transport chunking therefore
    // cannot change which rules receive an expensive line, and no-match floods
    // are bounded just like matching floods. Skipped lines are not replayed.
    if (work > maximumMatchWorkPerSecond - _matchWork) {
      _skippedLines++;
      return;
    }
    _matchWork += work;
    // Snapshot allows callback-driven edits without mutating this iteration.
    for (final trigger in eligible) {
      if (_burstCount >= maximumActionsPerSecond) break;
      final previous = _lastFired[trigger.id];
      if (previous != null &&
          now.difference(previous).inMilliseconds <
              trigger.cooldownSeconds * 1000) {
        continue;
      }
      if (!trigger.matches(line)) continue;
      _fired.add(trigger.id);
      _lastFired[trigger.id] = now;
      _burstCount++;
      onMatch(TerminalTriggerMatch(trigger, line));
    }
  }
}
