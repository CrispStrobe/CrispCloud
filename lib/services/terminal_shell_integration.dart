import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart';

/// A location in this emulator's scrollback. Metadata is display-only and is
/// never persisted, executed, or used to authorize a filesystem operation.
class TerminalCommandMark {
  TerminalCommandMark._(
    this.id,
    this.anchor,
    this.directory, {
    this.manual = false,
  });

  final int id;
  final CellAnchor anchor;
  final String? directory;
  final bool manual;
  CellAnchor? _input;
  CellAnchor? _output;
  CellAnchor? _end;
  String? command;
  DateTime? startedAt;
  DateTime? finishedAt;
  int? exitCode;

  bool get running => startedAt != null && finishedAt == null;
  Duration? get elapsed => startedAt == null || finishedAt == null
      ? null
      : finishedAt!.difference(startedAt!);

  void _dispose() {
    anchor.dispose();
    _input?.dispose();
    _output?.dispose();
    _end?.dispose();
  }
}

/// Observes sequences already decoded by xterm2: OSC 133/633, OSC 7, and
/// iTerm2 SetMark. It does not intercept input or implement another parser.
/// Anchors follow Unicode/wrapped-line reflow and expire with their buffer.
class TerminalShellIntegration extends ChangeNotifier {
  TerminalShellIntegration(this.terminal, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _previousOsc = terminal.onPrivateOSC;
    _previousDirectory = terminal.onCurrentDirectoryChange;
    _previousMark = terminal.onITerm2Mark;
    _oscHandler = (code, values) {
      _previousOsc?.call(code, values);
      _observeOsc(code, values);
    };
    _directoryHandler = (value) {
      _previousDirectory?.call(value);
      if (_disposed || terminal.isUsingAltBuffer) return;
      final next = _directory(value);
      if (next == null || next == currentDirectory) return;
      currentDirectory = next;
      _changed();
    };
    _markHandler = () {
      _previousMark?.call();
      addMark();
    };
    terminal.onPrivateOSC = _oscHandler;
    terminal.onCurrentDirectoryChange = _directoryHandler;
    terminal.onITerm2Mark = _markHandler;
  }

  static const maximumMarks = 500;
  static const maximumMetadataLength = 2048;
  final Terminal terminal;
  final DateTime Function() _now;
  final _marks = <TerminalCommandMark>[];
  TerminalCommandMark? _current;
  TerminalCommandMark? _lastCompleted;
  int _nextId = 1;
  bool _disposed = false;
  Timer? _notification;
  bool detected = false;
  String? currentDirectory;
  bool _notifyOnCompletion = false;
  int notificationSerial = 0;
  TerminalCommandMark? completionNotification;
  void Function(String, List<String>)? _previousOsc;
  void Function(String)? _previousDirectory;
  VoidCallback? _previousMark;
  late final void Function(String, List<String>) _oscHandler;
  late final void Function(String) _directoryHandler;
  late final VoidCallback _markHandler;

  bool get notifyOnCompletion => _notifyOnCompletion;
  set notifyOnCompletion(bool value) {
    if (_disposed || value == _notifyOnCompletion) return;
    _notifyOnCompletion = value;
    _changed();
  }

  List<TerminalCommandMark> get marks {
    _prune();
    return List.unmodifiable(_marks);
  }

  TerminalCommandMark? get latestCommand {
    _prune();
    if (_current?.startedAt != null) return _current;
    for (final mark in _marks.reversed) {
      if (mark.startedAt != null) return mark;
    }
    return _lastCompleted;
  }

  bool contains(TerminalCommandMark mark) =>
      !_disposed &&
      !terminal.isUsingAltBuffer &&
      _marks.contains(mark) &&
      terminal.buffer.ownsAnchor(mark.anchor);

  void _observeOsc(String code, List<String> values) {
    if (_disposed ||
        terminal.isUsingAltBuffer ||
        (code != '133' && code != '633') ||
        values.isEmpty) {
      return;
    }
    switch (values.first) {
      case 'A':
      case 'N':
      case 'P' when code == '133':
        final kind = terminal.semanticPromptState.promptKind;
        if (kind == TerminalSemanticPromptKind.continuation ||
            kind == TerminalSemanticPromptKind.secondary ||
            kind == TerminalSemanticPromptKind.right) {
          return;
        }
        _beginPrompt();
      case 'B':
      case 'I':
        final mark = _current;
        if (mark == null || !contains(mark) || mark.startedAt != null) return;
        mark._input?.dispose();
        mark._input = terminal.buffer.createAnchorFromCursor();
      case 'C':
        _startCommand();
      case 'D':
        _finishCommand(terminal.semanticPromptState.lastCommandExitCode);
    }
  }

  void _beginPrompt() {
    detected = true;
    _prune();
    // Some shells only report prompts. A fresh prompt still proves the old
    // command stopped, but cannot supply an exit status that was never sent.
    if (_current?.running == true) _finishCommand(null);
    final current = _current;
    if (current != null &&
        contains(current) &&
        current.startedAt == null &&
        current.anchor.y == terminal.buffer.absoluteCursorY) {
      return;
    }
    _current = _newMark();
    _changed();
  }

  TerminalCommandMark _newMark({bool manual = false}) {
    _prune();
    while (_marks.length >= maximumMarks) {
      final removed = _marks.removeAt(0);
      if (identical(removed, _current) && !removed.running) _current = null;
      removed._dispose();
    }
    final mark = TerminalCommandMark._(
      _nextId++,
      terminal.buffer.createAnchorFromCursor(),
      currentDirectory,
      manual: manual,
    );
    _marks.add(mark);
    return mark;
  }

  void addMark() {
    if (_disposed || terminal.isUsingAltBuffer) return;
    _newMark(manual: true);
    _changed();
  }

  void _startCommand() {
    final mark = _current;
    if (mark == null || !contains(mark) || mark.startedAt != null) return;
    mark.startedAt = _now();
    mark._output = terminal.buffer.createAnchorFromCursor();
    final explicit = terminal.semanticPromptState.commandLine;
    if (explicit != null) {
      mark.command = _displayText(explicit);
    } else {
      final input = mark._input;
      final end = mark._output!;
      if (input != null &&
          terminal.buffer.ownsAnchor(input) &&
          input.offset.isBeforeOrSame(end.offset) &&
          end.y - input.y <= 20) {
        mark.command = _displayText(
          terminal.buffer.getText(
            BufferRangeLine(input.offset, end.offset),
            true,
          ),
        );
      }
    }
    _changed();
  }

  void _finishCommand(int? code) {
    final mark = _current;
    if (mark == null || !mark.running) return;
    mark.finishedAt = _now();
    mark.exitCode = code != null && code >= -2147483648 && code <= 2147483647
        ? code
        : null;
    mark._end = terminal.buffer.createAnchorFromCursor();
    _lastCompleted = mark;
    // Long command output may evict the prompt. Keep its bounded status/alert,
    // while rejecting selection/navigation through detached buffer anchors.
    if (!_marks.contains(mark)) mark._dispose();
    if (_notifyOnCompletion) {
      _notifyOnCompletion = false;
      completionNotification = mark;
      notificationSerial++;
    }
    _changed();
  }

  /// Output selection is available only while both endpoints are still owned
  /// by the main buffer. No output is copied or transmitted by this method.
  BufferRangeLine? outputRange(TerminalCommandMark mark) {
    if (!contains(mark)) return null;
    final start = mark._output;
    final end = mark._end;
    if (start == null ||
        end == null ||
        !terminal.buffer.ownsAnchor(start) ||
        !terminal.buffer.ownsAnchor(end) ||
        !start.offset.isBefore(end.offset)) {
      return null;
    }
    return BufferRangeLine(start.offset, end.offset);
  }

  int? lineBefore(int line) {
    if (_disposed || terminal.isUsingAltBuffer) return null;
    _prune();
    int? found;
    for (final mark in _marks) {
      final y = mark.anchor.y;
      if (y < line && (found == null || y > found)) found = y;
    }
    return found;
  }

  int? lineAfter(int line) {
    if (_disposed || terminal.isUsingAltBuffer) return null;
    _prune();
    int? found;
    for (final mark in _marks) {
      final y = mark.anchor.y;
      if (y > line && (found == null || y < found)) found = y;
    }
    return found;
  }

  void _prune() {
    if (_disposed || terminal.isUsingAltBuffer) return;
    _marks.removeWhere((mark) {
      if (terminal.buffer.ownsAnchor(mark.anchor)) return false;
      if (identical(mark, _current) && !mark.running) _current = null;
      mark._dispose();
      return true;
    });
  }

  static String? _displayText(String text) {
    final bounded = text.length > maximumMetadataLength
        ? text.substring(0, maximumMetadataLength)
        : text;
    final plain = bounded
        .replaceAll(
          RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]'),
          ' ',
        )
        .trim();
    return plain.isEmpty ? null : plain;
  }

  static String? _directory(String value) {
    if (value.isEmpty || value.length > maximumMetadataLength) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    // OSC 7 uses file: URLs; OSC 633/iTerm2 may report an absolute path.
    // Both remain untrusted labels and never change the local file panel.
    if (uri.scheme.isNotEmpty && uri.scheme != 'file') return null;
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    String path;
    try {
      path = Uri.decodeComponent(uri.path);
    } on FormatException {
      return null;
    }
    if (!path.startsWith('/')) return null;
    return _displayText(path);
  }

  void _changed() {
    _notification ??= Timer(Duration.zero, () {
      _notification = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notification?.cancel();
    if (identical(terminal.onPrivateOSC, _oscHandler)) {
      terminal.onPrivateOSC = _previousOsc;
    }
    if (identical(terminal.onCurrentDirectoryChange, _directoryHandler)) {
      terminal.onCurrentDirectoryChange = _previousDirectory;
    }
    if (identical(terminal.onITerm2Mark, _markHandler)) {
      terminal.onITerm2Mark = _previousMark;
    }
    for (final mark in _marks) {
      mark._dispose();
    }
    _marks.clear();
    _current?._dispose();
    _lastCompleted?._dispose();
    super.dispose();
  }
}
