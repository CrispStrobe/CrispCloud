import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/hex_document.dart';

/// The active input column. Text input uses one Latin-1 byte per character;
/// the visual text column displays printable ASCII and dots for other bytes.
enum HexEditorArea { hex, ascii }

/// A byte selection. [start] is inclusive and [end] is exclusive.
@immutable
class HexEditorSelection {
  const HexEditorSelection(this.anchor, this.extent);

  final int anchor;
  final int extent;
  int get start => math.min(anchor, extent);
  int get end => math.max(anchor, extent);
  int get length => end - start;
  bool get isCollapsed => anchor == extent;
}

/// Interaction state for a HexEditor. The caller owns [document] and its
/// underlying source; disposing this controller does not close either.
///
/// All edits are byte operations, independent of text encodings. Input is
/// serialized because editing one nibble may need an asynchronous source read.
/// Await [settled] before taking a save snapshot. Navigation invalidates pending
/// input, so a delayed read cannot edit a newly selected location.
class HexEditorController extends ChangeNotifier {
  HexEditorController(this.document, {this.maxClipboardBytes = 16 << 20}) {
    if (maxClipboardBytes < 1) {
      throw ArgumentError.value(maxClipboardBytes, 'maxClipboardBytes');
    }
    _knownRevision = document.revision;
  }

  final HexDocument document;
  final int maxClipboardBytes;

  int _anchor = 0;
  int _caretOffset = 0;
  int _caretNibble = 0;
  HexEditorArea _activeArea = HexEditorArea.hex;
  bool _insertMode = false;
  bool _readOnly = false;
  bool _busy = false;
  bool _disposed = false;
  int _intentEpoch = 0;
  int _navigationRevision = 0;
  late int _knownRevision;
  int _searchEpoch = 0;
  bool _searching = false;
  Uint8List? _lastPattern;
  Future<void> _editTail = Future<void>.value();
  final List<_CaretEdit> _undoCarets = [];
  final List<_CaretEdit> _redoCarets = [];

  int get length => document.length;
  int get caretOffset => _caretOffset;
  int get caretNibble => _caretNibble;
  HexEditorArea get activeArea => _activeArea;
  HexEditorSelection get selection => HexEditorSelection(_anchor, _caretOffset);
  int get selectionStart => math.min(_anchor, _caretOffset);
  int get selectionEnd => math.max(_anchor, _caretOffset);
  int get selectionLength => selectionEnd - selectionStart;
  bool get hasSelection => _anchor != _caretOffset;
  bool get canUndo => document.canUndo;
  bool get canRedo => document.canRedo;
  bool get isDirty => document.isDirty;
  bool get isSearching => _searching;
  bool get hasSearchPattern => _lastPattern != null;

  /// Changes only when a command requests that the viewport follow the caret.
  int get navigationRevision => _navigationRevision;

  /// Completes after previously submitted input has finished or been canceled.
  Future<void> get settled => _editTail;

  bool get insertMode => _insertMode;
  set insertMode(bool value) {
    if (_insertMode == value) return;
    _insertMode = value;
    _caretNibble = 0;
    _intentEpoch++;
    _notify();
  }

  bool get readOnly => _readOnly;
  set readOnly(bool value) {
    if (_readOnly == value) return;
    _readOnly = value;
    _intentEpoch++;
    _notify();
  }

  /// Host-controlled operation lock, for example while replacing a saved file.
  bool get busy => _busy;
  set busy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _intentEpoch++;
    _notify();
  }

  set activeArea(HexEditorArea value) {
    if (_activeArea == value) return;
    _activeArea = value;
    _caretNibble = 0;
    _intentEpoch++;
    _navigationRevision++;
    _notify();
  }

  void toggleInsertMode() => insertMode = !insertMode;
  void toggleArea() => activeArea = activeArea == HexEditorArea.hex
      ? HexEditorArea.ascii
      : HexEditorArea.hex;

  /// Notify the editor after an external document action, such as markSaved().
  void refresh() {
    if (_disposed) return;
    final contentChanged = _knownRevision != document.revision;
    _syncHistory();
    _anchor = _anchor.clamp(0, length);
    _caretOffset = _caretOffset.clamp(0, length);
    if (_caretOffset == length) _caretNibble = 0;
    // Saving updates the clean-state marker without changing the bytes. It
    // must not cancel input that is waiting for an original-source read while
    // the save completes. External byte edits do invalidate that pending input.
    if (contentChanged) _intentEpoch++;
    _notify();
  }

  void goToOffset(int offset) => setCaret(offset);

  void setCaret(
    int offset, {
    int nibble = 0,
    HexEditorArea? area,
    bool extendSelection = false,
  }) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    RangeError.checkValueInInterval(nibble, 0, 1, 'nibble');
    if (_disposed) return;
    _caretOffset = offset;
    _caretNibble = offset == length ? 0 : nibble;
    if (!extendSelection) _anchor = offset;
    if (area != null) _activeArea = area;
    _intentEpoch++;
    _navigationRevision++;
    _notify();
  }

  void setSelection(int anchor, int extent, {HexEditorArea? area}) {
    RangeError.checkValueInInterval(anchor, 0, length, 'anchor');
    RangeError.checkValueInInterval(extent, 0, length, 'extent');
    if (_disposed) return;
    _anchor = anchor;
    _caretOffset = extent;
    _caretNibble = 0;
    if (area != null) _activeArea = area;
    _intentEpoch++;
    _navigationRevision++;
    _notify();
  }

  void selectAll() => setSelection(0, length);
  void clearSelection() => setCaret(_caretOffset, area: _activeArea);

  void moveCaret(int byteDelta, {bool extendSelection = false}) {
    setCaret(
      (_caretOffset + byteDelta).clamp(0, length),
      extendSelection: extendSelection,
    );
  }

  void moveHorizontal(int direction, {bool extendSelection = false}) {
    if (direction != -1 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'Must be -1 or 1');
    }
    if (hasSelection && !extendSelection) {
      setCaret(direction < 0 ? selectionStart : selectionEnd);
      return;
    }
    if (_activeArea == HexEditorArea.ascii || extendSelection) {
      moveCaret(direction, extendSelection: extendSelection);
      return;
    }
    final pos = (_caretOffset * 2 + _caretNibble + direction).clamp(
      0,
      length * 2,
    );
    setCaret(pos ~/ 2, nibble: pos.isEven ? 0 : 1);
  }

  /// Type one nibble. Each committed nibble is an undo step, as in MadEdit2.
  Future<void> typeHexDigit(int digit) {
    RangeError.checkValueInInterval(digit, 0, 15, 'digit');
    return _enqueue((epoch) async {
      final start = hasSelection ? selectionStart : _caretOffset;
      final selected = selectionLength;
      final inserting =
          selected > 0 || (_insertMode && _caretNibble == 0) || start == length;
      if (inserting) {
        _replace(
          start,
          selected,
          Uint8List.fromList([digit << 4]),
          _CaretState(start, start, 1, _activeArea),
        );
        return;
      }
      final rev = document.revision;
      final previous = await document.read(start, 1);
      if (!_valid(epoch) || document.revision != rev) return;
      if (previous.isEmpty) return;
      final isHigh = _caretNibble == 0;
      final value = isHigh
          ? (digit << 4) | (previous.first & 0x0f)
          : (previous.first & 0xf0) | digit;
      final next = isHigh ? start : start + 1;
      _replace(
        start,
        1,
        Uint8List.fromList([value]),
        _CaretState(next, next, isHigh ? 1 : 0, _activeArea),
      );
    });
  }

  Future<void> typeText(String text) {
    final bytes = _textBytes(text);
    return replaceSelection(bytes);
  }

  /// Replaces the selected bytes exactly. Without a selection, insert mode
  /// inserts; overwrite mode replaces available bytes and appends at EOF.
  Future<void> replaceSelection(Uint8List bytes, {bool? insert}) {
    final owned = Uint8List.fromList(bytes);
    return _enqueue((_) {
      if (owned.isEmpty && !hasSelection) return;
      final start = hasSelection ? selectionStart : _caretOffset;
      final removed = hasSelection
          ? selectionLength
          : (insert ?? _insertMode)
          ? 0
          : math.min(owned.length, length - start);
      final next = start + owned.length;
      _replace(start, removed, owned, _CaretState(next, next, 0, _activeArea));
    });
  }

  Future<void> deleteSelection({bool backward = false}) => _enqueue((_) {
    if (hasSelection) {
      final start = selectionStart;
      _replace(
        start,
        selectionLength,
        Uint8List(0),
        _CaretState(start, start, 0, _activeArea),
      );
    } else if (backward && _caretOffset > 0) {
      final start = _caretOffset - 1;
      _replace(
        start,
        1,
        Uint8List(0),
        _CaretState(start, start, 0, _activeArea),
      );
    } else if (!backward && _caretOffset < length) {
      final start = _caretOffset;
      _replace(
        start,
        1,
        Uint8List(0),
        _CaretState(start, start, 0, _activeArea),
      );
    }
  });

  Future<void> undo() => _enqueue((_) {
    _syncHistory();
    if (!document.undo()) return;
    final frame = _undoCarets.isEmpty ? null : _undoCarets.removeLast();
    if (frame != null) _redoCarets.add(frame);
    _restore(frame?.before ?? _state);
    _knownRevision = document.revision;
    _navigationRevision++;
    _notify();
  });

  Future<void> redo() => _enqueue((_) {
    _syncHistory();
    if (!document.redo()) return;
    final frame = _redoCarets.isEmpty ? null : _redoCarets.removeLast();
    if (frame != null) _undoCarets.add(frame);
    _restore(frame?.after ?? _state);
    _knownRevision = document.revision;
    _navigationRevision++;
    _notify();
  });

  Future<String> selectedText({HexEditorArea? area}) async {
    await settled;
    final count = selectionLength;
    if (count > maxClipboardBytes) {
      throw StateError(
        'Selection exceeds the $maxClipboardBytes-byte clipboard limit.',
      );
    }
    if (count == 0) return '';
    final bytes = await document.read(selectionStart, count);
    return (area ?? activeArea) == HexEditorArea.hex
        ? formatHex(bytes)
        : latin1.decode(bytes);
  }

  Future<void> copy({HexEditorArea? area}) async {
    final text = await selectedText(area: area);
    if (text.isNotEmpty) await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> cut({HexEditorArea? area}) => _enqueue((epoch) async {
    if (!hasSelection) return;
    final count = selectionLength;
    if (count > maxClipboardBytes) {
      throw StateError(
        'Selection exceeds the $maxClipboardBytes-byte clipboard limit.',
      );
    }
    final start = selectionStart;
    final rev = document.revision;
    final bytes = await document.read(start, count);
    final text = (area ?? activeArea) == HexEditorArea.hex
        ? formatHex(bytes)
        : latin1.decode(bytes);
    if (!_valid(epoch) || rev != document.revision) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!_valid(epoch) || rev != document.revision) return;
    _replace(
      start,
      count,
      Uint8List(0),
      _CaretState(start, start, 0, _activeArea),
    );
  });

  Future<void> paste({HexEditorArea? area}) {
    final destinationArea = area ?? activeArea;
    return _enqueue((epoch) async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!_valid(epoch) || data?.text == null || data!.text!.isEmpty) return;
      _pasteText(data.text!, destinationArea);
    });
  }

  Future<void> pasteText(String text, {HexEditorArea? area}) {
    final destinationArea = area ?? activeArea;
    return _enqueue((_) => _pasteText(text, destinationArea));
  }

  void _pasteText(String text, HexEditorArea area) {
    // Bound the string before allocating its decoded byte buffer.
    if (text.length > maxClipboardBytes * (area == HexEditorArea.hex ? 5 : 1)) {
      throw StateError(
        'Clipboard content exceeds the $maxClipboardBytes-byte limit.',
      );
    }
    final bytes = area == HexEditorArea.hex ? parseHex(text) : _textBytes(text);
    if (bytes.isEmpty) return;
    if (bytes.length > maxClipboardBytes) {
      throw StateError(
        'Clipboard content exceeds the $maxClipboardBytes-byte limit.',
      );
    }
    final start = hasSelection ? selectionStart : _caretOffset;
    final removed = hasSelection
        ? selectionLength
        : _insertMode
        ? 0
        : math.min(bytes.length, length - start);
    final next = start + bytes.length;
    _replace(start, removed, bytes, _CaretState(next, next, 0, _activeArea));
  }

  /// Accepts pairs of hexadecimal digits, optionally separated by whitespace.
  /// Each whitespace-delimited group may start with 0x. Invalid input is never
  /// silently stripped or interpreted as text.
  static Uint8List parseHex(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);
    final groups = trimmed.split(RegExp(r'\s+'));
    final digits = StringBuffer();
    final valid = RegExp(r'^(?:0[xX])?(?:[0-9a-fA-F]{2})+$');
    for (final group in groups) {
      if (!valid.hasMatch(group)) {
        throw const FormatException(
          'Enter complete hexadecimal byte pairs, for example 00 FF A5.',
        );
      }
      digits.write(
        group.startsWith('0x') || group.startsWith('0X')
            ? group.substring(2)
            : group,
      );
    }
    final source = digits.toString();
    return Uint8List.fromList([
      for (var i = 0; i < source.length; i += 2)
        int.parse(source.substring(i, i + 2), radix: 16),
    ]);
  }

  static String formatHex(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static Uint8List _textBytes(String text) {
    if (text.runes.any((rune) => rune > 255)) {
      throw const FormatException(
        'The byte text column accepts Latin-1 characters only. Use hexadecimal input for arbitrary bytes.',
      );
    }
    return Uint8List.fromList(latin1.encode(text));
  }

  /// Search byte sequences in bounded chunks. A stable snapshot prevents edits
  /// during I/O from producing a mixed-version result. A result is applied only
  /// if the document and user selection have not changed in the meantime.
  Future<int?> find(
    Uint8List pattern, {
    bool forward = true,
    bool wrap = true,
    int? start,
  }) async {
    if (pattern.isEmpty) {
      throw ArgumentError('The search pattern must not be empty.');
    }
    if (pattern.length > 1 << 20) {
      throw ArgumentError('The search pattern must be at most 1 MiB.');
    }
    await settled;
    if (_disposed) return null;
    final owned = Uint8List.fromList(pattern);
    _lastPattern = owned;
    final ticket = ++_searchEpoch;
    final intent = _intentEpoch;
    final snapshot = document.snapshot();
    final revision = snapshot.revision;
    final origin =
        (start ??
                (forward
                    ? (hasSelection ? selectionEnd : caretOffset)
                    : (hasSelection ? selectionStart : caretOffset)))
            .clamp(0, snapshot.length);
    final prefix = _prefixTable(owned);
    _searching = true;
    _notify();
    bool canceled() =>
        _disposed ||
        ticket != _searchEpoch ||
        intent != _intentEpoch ||
        document.revision != revision;
    try {
      int? found;
      if (forward) {
        found = await _findForward(
          snapshot,
          owned,
          prefix,
          origin,
          snapshot.length,
          canceled,
        );
        if (found == null && wrap && origin > 0 && !canceled()) {
          found = await _findForward(
            snapshot,
            owned,
            prefix,
            0,
            origin,
            canceled,
          );
        }
      } else {
        found = await _findBackward(
          snapshot,
          owned,
          prefix,
          0,
          origin,
          canceled,
        );
        if (found == null && wrap && origin < snapshot.length && !canceled()) {
          found = await _findBackward(
            snapshot,
            owned,
            prefix,
            origin,
            snapshot.length,
            canceled,
          );
        }
      }
      if (canceled()) return null;
      if (found != null) setSelection(found, found + owned.length);
      return found;
    } finally {
      await snapshot.close();
      if (!_disposed && ticket == _searchEpoch) {
        _searching = false;
        _notify();
      }
    }
  }

  Future<int?> findNext() =>
      _lastPattern == null ? Future<int?>.value() : find(_lastPattern!);

  Future<int?> findPrevious() => _lastPattern == null
      ? Future<int?>.value()
      : find(_lastPattern!, forward: false);

  void cancelSearch() {
    _searchEpoch++;
    _searching = false;
    _notify();
  }

  static List<int> _prefixTable(Uint8List pattern) {
    final table = List<int>.filled(pattern.length, 0);
    var matched = 0;
    for (var i = 1; i < pattern.length; i++) {
      while (matched > 0 && pattern[i] != pattern[matched]) {
        matched = table[matched - 1];
      }
      if (pattern[i] == pattern[matched]) matched++;
      table[i] = matched;
    }
    return table;
  }

  static Future<int?> _findForward(
    HexSnapshot snapshot,
    Uint8List pattern,
    List<int> prefix,
    int begin,
    int end,
    bool Function() canceled,
  ) async {
    if (begin >= end || pattern.length > snapshot.length) return null;
    final stop = math.min(snapshot.length, end + pattern.length - 1);
    var pos = begin;
    var matched = 0;
    var blocks = 0;
    while (pos < stop && !canceled()) {
      final bytes = await snapshot.read(pos, math.min(64 << 10, stop - pos));
      if (bytes.isEmpty) {
        throw StateError('Byte source ended before its declared length.');
      }
      for (var i = 0; i < bytes.length; i++) {
        while (matched > 0 && bytes[i] != pattern[matched]) {
          matched = prefix[matched - 1];
        }
        if (bytes[i] == pattern[matched]) matched++;
        if (matched == pattern.length) return pos + i + 1 - pattern.length;
      }
      pos += bytes.length;
      if (++blocks % 16 == 0) await Future<void>.delayed(Duration.zero);
    }
    return null;
  }

  static Future<int?> _findBackward(
    HexSnapshot snapshot,
    Uint8List pattern,
    List<int> prefix,
    int begin,
    int end,
    bool Function() canceled,
  ) async {
    if (begin >= end || pattern.length > snapshot.length) return null;
    var high = end;
    var blocks = 0;
    while (high > begin && !canceled()) {
      final low = math.max(begin, high - (64 << 10));
      final count = math.min(
        snapshot.length - low,
        high - low + pattern.length - 1,
      );
      final bytes = await snapshot.read(low, count);
      if (bytes.length != count) {
        throw StateError('Byte source ended before its declared length.');
      }
      int? last;
      var matched = 0;
      for (var i = 0; i < bytes.length; i++) {
        while (matched > 0 && bytes[i] != pattern[matched]) {
          matched = prefix[matched - 1];
        }
        if (bytes[i] == pattern[matched]) matched++;
        if (matched == pattern.length) {
          final candidate = low + i + 1 - pattern.length;
          if (candidate < high) last = candidate;
          matched = prefix[matched - 1];
        }
      }
      if (last != null) return last;
      high = low;
      if (++blocks % 16 == 0) await Future<void>.delayed(Duration.zero);
    }
    return null;
  }

  Future<void> _enqueue(FutureOr<void> Function(int epoch) action) {
    final epoch = _intentEpoch;
    final next = _editTail.then((_) async {
      if (!_valid(epoch)) return;
      if (_readOnly || _busy) {
        throw StateError('This document cannot be edited now.');
      }
      await action(epoch);
    });
    // Retain a completed queue after an error; the returned future still reports
    // that error to its caller. Later commands must not inherit a failed future.
    _editTail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  bool _valid(int epoch) => !_disposed && epoch == _intentEpoch;

  _CaretState get _state =>
      _CaretState(_anchor, _caretOffset, _caretNibble, _activeArea);

  void _restore(_CaretState state) {
    _anchor = state.anchor.clamp(0, length);
    _caretOffset = state.offset.clamp(0, length);
    _caretNibble = _caretOffset == length ? 0 : state.nibble;
    _activeArea = state.area;
  }

  void _replace(int start, int count, Uint8List bytes, _CaretState after) {
    _syncHistory();
    final before = _state;
    final revision = document.revision;
    document.replace(start, count, bytes);
    _restore(after);
    if (document.revision != revision) {
      _undoCarets.add(_CaretEdit(before, _state));
      _redoCarets.clear();
      final retained = document.undoSteps;
      if (_undoCarets.length > retained) {
        _undoCarets.removeRange(0, _undoCarets.length - retained);
      }
    }
    _knownRevision = document.revision;
    _navigationRevision++;
    _notify();
  }

  void _syncHistory() {
    if (_knownRevision == document.revision) return;
    _undoCarets.clear();
    _redoCarets.clear();
    _knownRevision = document.revision;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _intentEpoch++;
    _searchEpoch++;
    super.dispose();
  }
}

class _CaretState {
  const _CaretState(this.anchor, this.offset, this.nibble, this.area);
  final int anchor;
  final int offset;
  final int nibble;
  final HexEditorArea area;
}

class _CaretEdit {
  const _CaretEdit(this.before, this.after);
  final _CaretState before;
  final _CaretState after;
}
