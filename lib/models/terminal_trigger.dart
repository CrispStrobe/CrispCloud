/// User-authored output observations. Actions never write to a shell or execute
/// a command, and records contain neither credentials nor captured output.
enum TerminalTriggerAction { mark, notify }

enum TerminalTriggerMatchKind { literal, safePattern }

class TerminalTrigger {
  TerminalTrigger({
    required this.id,
    required this.name,
    required this.pattern,
    this.matchKind = TerminalTriggerMatchKind.literal,
    this.action = TerminalTriggerAction.notify,
    this.enabled = true,
    this.caseSensitive = true,
    this.oncePerSession = false,
    this.cooldownSeconds = 5,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        !validName(name) ||
        !validPattern(pattern) ||
        cooldownSeconds < 0 ||
        cooldownSeconds > maximumCooldownSeconds) {
      throw const FormatException('Invalid terminal trigger');
    }
    _matcher = matchKind == TerminalTriggerMatchKind.safePattern
        ? TerminalTriggerPattern(pattern, caseSensitive: caseSensitive)
        : null;
  }

  static const maximumNameLength = 80;
  static const maximumPatternLength = 256;
  static const maximumCooldownSeconds = 3600;
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');

  static bool validName(String value) =>
      value.trim().isNotEmpty &&
      value.length <= maximumNameLength &&
      !_controls.hasMatch(value);

  static bool validPattern(String value) =>
      value.isNotEmpty &&
      value.length <= maximumPatternLength &&
      !_controls.hasMatch(value);

  final String id;
  final String name;
  final String pattern;
  final TerminalTriggerMatchKind matchKind;
  final TerminalTriggerAction action;
  final bool enabled;
  final bool caseSensitive;
  final bool oncePerSession;
  final int cooldownSeconds;
  late final TerminalTriggerPattern? _matcher;

  bool matches(String line) =>
      _matcher?.hasMatch(line) ??
      (caseSensitive
          ? line.contains(pattern)
          : line.toLowerCase().contains(pattern.toLowerCase()));

  /// Conservative work estimate for the observer's per-second budget. This is
  /// separate from the notification limit, which cannot bound no-match work.
  int get matchWorkPerRune => _matcher?.workPerRune ?? 1;

  TerminalTrigger copyWith({bool? enabled}) => TerminalTrigger(
    id: id,
    name: name,
    pattern: pattern,
    matchKind: matchKind,
    action: action,
    enabled: enabled ?? this.enabled,
    caseSensitive: caseSensitive,
    oncePerSession: oncePerSession,
    cooldownSeconds: cooldownSeconds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'matchKind': matchKind.name,
    'action': action.name,
    'enabled': enabled,
    'caseSensitive': caseSensitive,
    'oncePerSession': oncePerSession,
    'cooldownSeconds': cooldownSeconds,
  };

  factory TerminalTrigger.fromJson(Map<String, dynamic> value) {
    if (value['id'] is! String ||
        value['name'] is! String ||
        value['pattern'] is! String ||
        value['matchKind'] is! String ||
        value['action'] is! String ||
        value['cooldownSeconds'] is! int ||
        [
          'enabled',
          'caseSensitive',
          'oncePerSession',
        ].any((key) => value[key] is! bool)) {
      throw const FormatException('Invalid terminal trigger record');
    }
    final kinds = TerminalTriggerMatchKind.values.where(
      (kind) => kind.name == value['matchKind'],
    );
    final actions = TerminalTriggerAction.values.where(
      (action) => action.name == value['action'],
    );
    if (kinds.length != 1 || actions.length != 1) {
      throw const FormatException('Unsupported terminal trigger action');
    }
    return TerminalTrigger(
      id: value['id'] as String,
      name: value['name'] as String,
      pattern: value['pattern'] as String,
      matchKind: kinds.single,
      action: actions.single,
      enabled: value['enabled'] as bool,
      caseSensitive: value['caseSensitive'] as bool,
      oncePerSession: value['oncePerSession'] as bool,
      cooldownSeconds: value['cooldownSeconds'] as int,
    );
  }
}

/// A deliberately limited regular-expression syntax evaluated as a finite
/// state machine. There is no backtracking, so repeated quantifiers cannot
/// freeze the terminal. Work is O(input runes × pattern tokens), with both
/// inputs bounded by the caller. Supported: literals, dot, character classes,
/// ranges, ^/$ anchors, ?, *, + and \d/\s/\w (and their inverse forms).
/// Groups, alternation, lookaround, backreferences and counted repeats reject.
class TerminalTriggerPattern {
  TerminalTriggerPattern(String pattern, {this.caseSensitive = true}) {
    if (!TerminalTrigger.validPattern(pattern)) {
      throw const FormatException('Invalid terminal trigger pattern');
    }
    final source = pattern.runes.toList();
    var index = 0;
    if (source.first == 94) {
      _start = true;
      index++;
    }
    while (index < source.length) {
      var rune = source[index++];
      if (rune == 36 && index == source.length) {
        _end = true;
        break;
      }
      _PatternAtom atom;
      if (rune == 92) {
        if (index >= source.length) _invalid();
        rune = source[index++];
        atom = _escaped(rune);
      } else if (rune == 46) {
        atom = _PatternAtom.any();
      } else if (rune == 91) {
        var inverse = false;
        if (index < source.length && source[index] == 94) {
          inverse = true;
          index++;
        }
        final ranges = <(int, int)>[];
        while (index < source.length && source[index] != 93) {
          var first = source[index++];
          if (first == 92) {
            if (index >= source.length) _invalid();
            first = source[index++];
            if (_asciiLetterOrDigit(first)) _invalid();
          }
          var last = first;
          if (index + 1 < source.length &&
              source[index] == 45 &&
              source[index + 1] != 93) {
            index++;
            last = source[index++];
            if (last == 92) {
              if (index >= source.length) _invalid();
              last = source[index++];
              if (_asciiLetterOrDigit(last)) _invalid();
            }
            if (last < first) _invalid();
          }
          ranges.add((first, last));
        }
        if (index >= source.length || ranges.isEmpty) _invalid();
        index++; // Closing bracket.
        atom = _PatternAtom(ranges: ranges, inverse: inverse);
      } else {
        if (const {
          40,
          41,
          123,
          125,
          124,
          42,
          43,
          63,
          94,
          36,
          93,
        }.contains(rune)) {
          _invalid();
        }
        atom = _PatternAtom.literal(rune);
      }
      if (index < source.length && const {42, 43, 63}.contains(source[index])) {
        atom.quantifier = source[index++];
      }
      _atoms.add(atom);
    }
    // Empty-string matching would notify on arbitrary output. Require every
    // accepted pattern to consume at least one rune.
    if (_atoms.isEmpty || _atoms.every((a) => a.skippable)) _invalid();
  }

  final bool caseSensitive;
  final _atoms = <_PatternAtom>[];
  bool _start = false;
  bool _end = false;

  int get workPerRune =>
      _atoms.length * 3 +
      _atoms.fold(0, (sum, atom) => sum + atom.ranges.length);

  static int _singleRune(String value, int fallback) {
    final runes = value.runes.iterator;
    if (!runes.moveNext()) return fallback;
    final result = runes.current;
    return runes.moveNext() ? fallback : result;
  }

  static Never _invalid() =>
      throw const FormatException('Unsupported terminal pattern syntax');

  static bool _asciiLetterOrDigit(int rune) =>
      (rune >= 48 && rune <= 57) ||
      (rune >= 65 && rune <= 90) ||
      (rune >= 97 && rune <= 122);

  static _PatternAtom _escaped(int rune) {
    if (rune == 100 || rune == 68) {
      return _PatternAtom(ranges: [(48, 57)], inverse: rune == 68);
    }
    if (rune == 115 || rune == 83) {
      return _PatternAtom(ranges: [(9, 13), (32, 32)], inverse: rune == 83);
    }
    if (rune == 119 || rune == 87) {
      return _PatternAtom(
        ranges: [(48, 57), (65, 90), (95, 95), (97, 122)],
        inverse: rune == 87,
      );
    }
    if (_asciiLetterOrDigit(rune)) _invalid();
    return _PatternAtom.literal(rune);
  }

  void _closure(List<bool> states) {
    for (var i = 0; i < _atoms.length; i++) {
      if (states[i] && _atoms[i].skippable) states[i + 1] = true;
    }
  }

  bool hasMatch(String value) {
    var states = List<bool>.filled(_atoms.length + 1, false);
    var next = List<bool>.filled(states.length, false);
    states[0] = true;
    _closure(states);
    for (final rune in value.runes) {
      final text = caseSensitive ? null : String.fromCharCode(rune);
      final lower = text == null ? rune : _singleRune(text.toLowerCase(), rune);
      final upper = text == null ? rune : _singleRune(text.toUpperCase(), rune);
      if (!_start) {
        states[0] = true;
        _closure(states);
      }
      next.fillRange(0, next.length, false);
      for (var i = 0; i < _atoms.length; i++) {
        if (states[i] && _atoms[i].matches(rune, lower, upper)) {
          next[i + 1] = true;
          if (_atoms[i].repeating) next[i] = true;
        }
      }
      _closure(next);
      final previous = states;
      states = next;
      next = previous;
      if (!_end && states.last) return true;
    }
    return states.last;
  }
}

class _PatternAtom {
  _PatternAtom({required this.ranges, this.inverse = false}) : any = false;
  _PatternAtom.literal(int rune)
    : ranges = [(rune, rune)],
      inverse = false,
      any = false;
  _PatternAtom.any() : ranges = const [], inverse = false, any = true;

  final List<(int, int)> ranges;
  final bool inverse;
  final bool any;
  int quantifier = 0;
  bool get skippable => quantifier == 42 || quantifier == 63;
  bool get repeating => quantifier == 42 || quantifier == 43;
  bool matches(int rune, int lower, int upper) =>
      any ||
      ranges.any(
            (range) =>
                (rune >= range.$1 && rune <= range.$2) ||
                (lower >= range.$1 && lower <= range.$2) ||
                (upper >= range.$1 && upper <= range.$2),
          ) !=
          inverse;
}
