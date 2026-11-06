import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'hex_document.dart';
import 'hex_layout.dart';

/// Serialized editing commands: a slow disk read or clipboard operation cannot
/// reorder two keystrokes. Rendering/search use immutable revision snapshots.
class HexEditorController extends ChangeNotifier {
  HexEditorController(this.document, {this.readOnly = false});
  final HexDocument document;
  bool readOnly;
  int _caret = 0, _anchor = 0, _nibble = 0;
  HexArea _area = HexArea.hex;
  bool _insert = false, _latin1 = false, _disposed = false;
  String? _error;
  Future<void> _tail = Future<void>.value();
  (int, int)? _pendingNibble;
  final Map<int, (int, int, int)> _positions = {};
  int _searchGeneration = 0;
  bool _searching = false;
  int get caret => _caret;
  int get anchor => _anchor;
  int get nibble => _nibble;
  int get selectionStart => math.min(_caret, _anchor);
  int get selectionEnd => math.max(_caret, _anchor);
  int get selectionLength => selectionEnd - selectionStart;
  HexArea get area => _area;
  bool get insertMode => _insert;
  bool get latin1 => _latin1;
  bool get isDirty => document.isDirty;
  bool get searching => _searching;
  String? get error => _error;
  Future<void> get idle => _tail;

  void _notify() { if (!_disposed) notifyListeners(); }
  void clearError() { _error = null; _notify(); }
  void _remember() {
    _positions[document.revision] = (_caret, _anchor, _nibble);
    if (_positions.length > document.maxUndoSteps * 3) _positions.remove(_positions.keys.first);
  }
  void _editable() { if (readOnly) throw StateError('This file is read-only.'); }
  Future<bool> _run(FutureOr<void> Function() action) {
    final done = Completer<bool>();
    _tail = _tail.then((_) async {
      if (_disposed) { done.complete(false); return; }
      final before = document.revision;
      try {
        _error = null;
        await action();
        if (document.revision != before) { _searchGeneration++; _searching = false; }
        done.complete(true);
      } catch (error) { _error = error.toString(); done.complete(false); }
      _notify();
    });
    return done.future;
  }
  void markSaved(HexSnapshot snapshot) {
    document.markSaved(snapshot);
    _pendingNibble = null;
    _notify();
  }
  Future<bool> select(int offset, {bool extend = false, HexArea? area, int nibble = 0}) => _run(() {
    _caret = offset.clamp(0, document.length);
    if (!extend) _anchor = _caret;
    _nibble = _caret == document.length ? 0 : nibble.clamp(0, 1);
    if (area != null) _area = area;
    _pendingNibble = null;
  });
  Future<bool> selectRange(int start, int end) => _run(() {
    RangeError.checkValidRange(start, end, document.length);
    _anchor = start; _caret = end; _nibble = 0; _pendingNibble = null;
  });
  Future<bool> selectAll() => selectRange(0, document.length);
  Future<bool> move(int bytes, {bool extend = false}) => _run(() {
    _caret = (_caret + bytes).clamp(0, document.length);
    if (!extend) _anchor = _caret;
    _nibble = 0; _pendingNibble = null;
  });
  Future<bool> moveNibble(int delta, {bool extend = false}) => _run(() {
    if (_area == HexArea.ascii || extend) {
      _caret = (_caret + delta).clamp(0, document.length);
      _nibble = 0;
    } else {
      final next = hexClampNibblePos(_caret * 2 + _nibble + delta, document.length, allowEnd: true);
      _caret = next ~/ 2; _nibble = next % 2;
    }
    if (!extend) _anchor = _caret;
    _pendingNibble = null;
  });
  Future<bool> setInsertMode(bool value) => _run(() { _insert = value; _pendingNibble = null; });
  Future<bool> setLatin1(bool value) => _run(() { _latin1 = value; });
  Future<bool> setArea(HexArea value) => _run(() { _area = value; _nibble = 0; _pendingNibble = null; });

  Future<bool> typeDigit(int digit) => _run(() async {
    _editable();
    if (digit < 0 || digit > 15) throw RangeError.range(digit, 0, 15, 'digit');
    _remember();
    if (selectionLength > 0 || ((_insert || _caret == document.length) && _nibble == 0)) {
      final at = selectionStart;
      document.replace(at, selectionLength, [digit << 4]);
      _caret = at; _anchor = at; _nibble = 1;
      _pendingNibble = (document.revision, at);
      return;
    }
    final byte = (await document.read(_caret, 1))[0];
    final low = _nibble == 1;
    final value = low ? (byte & 0xf0) | digit : (digit << 4) | (byte & 15);
    document.replace(_caret, 1, [value],
      coalesce: low && _pendingNibble == (document.revision, _caret));
    if (low) { _caret++; _nibble = 0; _pendingNibble = null; }
    else { _nibble = 1; _pendingNibble = (document.revision, _caret); }
    _anchor = _caret;
  });

  Future<bool> writeBytes(List<int> bytes) => _run(() => _write(bytes));
  void _write(List<int> bytes) {
    _editable();
    if (bytes.isEmpty) return;
    final at = selectionStart;
    final count = selectionLength > 0 ? selectionLength :
        (_insert || at == document.length ? 0 : bytes.length);
    if (at + count > document.length) throw StateError('Not enough bytes to overwrite. Switch to Insert mode to grow the file.');
    _remember();
    document.replace(at, count, bytes);
    _caret = at + bytes.length; _anchor = _caret; _nibble = 0; _pendingNibble = null;
  }
  Future<bool> typeText(String text) => _run(() {
    final maximum = _latin1 ? 255 : 127;
    if (text.runes.any((value) => value > maximum)) {
      throw StateError('Text entry must fit ${_latin1 ? 'Latin-1' : 'ASCII'}. Use hexadecimal bytes for other encodings.');
    }
    _write(text.codeUnits);
  });
  Future<bool> delete({bool backward = false}) => _run(() {
    _editable();
    final at = selectionLength > 0 ? selectionStart : _caret - (backward ? 1 : 0);
    final count = selectionLength > 0 ? selectionLength : 1;
    if (at < 0 || at >= document.length) return;
    _remember(); document.delete(at, count);
    _caret = at; _anchor = at; _nibble = 0; _pendingNibble = null;
  });
  Future<bool> undo() => _run(() { _editable(); _remember(); if (document.undo()) _restorePosition(); });
  Future<bool> redo() => _run(() { _editable(); _remember(); if (document.redo()) _restorePosition(); });
  void _restorePosition() {
    final value = _positions[document.revision];
    _caret = (value?.$1 ?? _caret).clamp(0, document.length);
    _anchor = (value?.$2 ?? _caret).clamp(0, document.length);
    _nibble = _caret == document.length ? 0 : value?.$3 ?? 0;
    _pendingNibble = null;
  }

  Future<bool> copy({bool cut = false}) => _run(() async {
    if (cut) _editable();
    final at = selectionStart;
    final count = selectionLength > 0 ? selectionLength : at < document.length ? 1 : 0;
    if (count == 0) return;
    if (count > document.maxSingleEditBytes) throw StateError('Selection exceeds the clipboard size limit.');
    final bytes = await document.read(at, count);
    final text = _area == HexArea.hex ? bytes.map((b) => hexNumber(b, 2)).join(' ') :
        String.fromCharCodes(bytes);
    await Clipboard.setData(ClipboardData(text: text));
    if (cut) {
      _remember(); document.delete(at, count);
      _caret = at; _anchor = at; _nibble = 0;
    }
    _pendingNibble = null;
  });
  Future<bool> paste() => _run(() async {
    _editable();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (text.length > document.maxSingleEditBytes * 4) throw StateError('Clipboard exceeds the edit size limit.');
    if (_area == HexArea.hex) { _write(parseHexBytes(text)); }
    else {
      if (text.runes.any((c) => c > (_latin1 ? 255 : 127))) throw StateError('Clipboard contains characters outside the selected byte encoding.');
      _write(text.codeUnits);
    }
  });

  void cancelSearch() { _searchGeneration++; _searching = false; _notify(); }
  Future<int?> findNext(Uint8List pattern, {bool wrap = true}) async {
    await idle;
    if (_disposed) return null;
    final snapshot = document.snapshot;
    final generation = ++_searchGeneration;
    final start = selectionLength > 0 ? selectionEnd : caret;
    _searching = true; _error = null; _notify();
    bool cancelled() => _disposed || generation != _searchGeneration || snapshot.revision != document.revision;
    try {
      var found = await snapshot.find(pattern, start: start, cancelled: cancelled);
      if (found == null && wrap && start > 0) {
        // Include matches starting before start and ending just after it.
        final end = math.min(snapshot.length, start + pattern.length - 1);
        found = await snapshot.find(pattern, end: end, cancelled: cancelled);
        if (found != null && found >= start) found = null;
      }
      if (cancelled()) return null;
      if (found != null) { await selectRange(found, found + pattern.length); }
      else { _error = 'No matching bytes found.'; }
      return found;
    } on HexSearchCancelled { return null; }
    catch (error) { if (!cancelled()) _error = error.toString(); return null; }
    finally { if (generation == _searchGeneration) _searching = false; _notify(); }
  }
  @override
  void dispose() { _disposed = true; _searchGeneration++; super.dispose(); }
}
