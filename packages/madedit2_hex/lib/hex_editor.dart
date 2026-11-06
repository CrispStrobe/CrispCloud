import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hex_controller.dart';
import 'hex_document.dart';
import 'hex_layout.dart';

/// Embeddable native Flutter hex editor. The host owns the controller/source
/// and persistence. Only visible rows and a bounded page cache are read.
class HexEditor extends StatefulWidget {
  const HexEditor({super.key, required this.controller, this.onSave,
    this.saving = false, this.showKeypad = false});
  final HexEditorController controller;
  final VoidCallback? onSave;
  final bool saving;
  final bool showKeypad;
  @override
  State<HexEditor> createState() => _HexEditorState();
}

class _HexEditorState extends State<HexEditor> {
  final _focus = FocusNode(debugLabel: 'Hex editor');
  final _vertical = ScrollController(), _horizontal = ScrollController();
  final _viewport = GlobalKey();
  final _pages = LinkedHashMap<int, Future<Uint8List>>();
  static const _pageSize = 65536;
  late HexSnapshot _snapshot;
  double _charWidth = 9, _rowHeight = 24;
  int? _dragPointer;
  int _previousCaret = 0;
  bool _keypad = false;
  HexEditorController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _snapshot = c.document.snapshot;
    _keypad = widget.showKeypad;
    c.addListener(_changed);
  }
  @override
  void didUpdateWidget(HexEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
      _snapshot = c.document.snapshot;
      _pages.clear();
    }
  }
  void _changed() {
    if (!mounted) return;
    if (_snapshot.revision != c.document.revision) {
      _snapshot = c.document.snapshot;
      _pages.clear();
    }
    setState(() {});
    if (_previousCaret != c.caret) {
      _previousCaret = c.caret;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCaret());
    }
  }
  void _revealCaret() {
    if (!mounted || !_vertical.hasClients) return;
    final top = (c.caret ~/ hexBytesPerRow) * _rowHeight;
    final position = _vertical.position;
    var offset = position.pixels;
    if (top < offset) offset = top;
    if (top + _rowHeight > offset + position.viewportDimension) {
      offset = top + _rowHeight - position.viewportDimension;
    }
    offset = offset.clamp(0.0, position.maxScrollExtent);
    if (offset != position.pixels) _vertical.jumpTo(offset);
  }
  Future<Uint8List> _page(int index) {
    final existing = _pages.remove(index);
    if (existing != null) { _pages[index] = existing; return existing; }
    final offset = index * _pageSize;
    final future = _snapshot.read(offset, math.min(_pageSize, _snapshot.length - offset));
    _pages[index] = future;
    while (_pages.length > 8) { _pages.remove(_pages.keys.first); }
    return future;
  }
  void _hit(Offset point, {bool extend = false}) {
    final row = ((point.dy + (_vertical.hasClients ? _vertical.offset : 0)) / _rowHeight).floor();
    final column = ((point.dx + (_horizontal.hasClients ? _horizontal.offset : 0) - 8) / _charWidth).floor();
    final digits = hexOffsetDigits(c.document.length);
    final asciiStart = asciiCharCol(0, digits);
    var area = HexArea.hex, nibble = 0, byte = 0;
    if (column >= asciiStart) {
      area = HexArea.ascii;
      byte = (column - asciiStart).clamp(0, hexBytesPerRow - 1);
    } else {
      for (var i = 0; i < hexBytesPerRow; i++) {
        if (column >= hexCharCol(i, digits)) {
          byte = i;
          nibble = (column - hexCharCol(i, digits)).clamp(0, 1);
        }
      }
    }
    unawaited(c.select((row * hexBytesPerRow + byte).clamp(0, c.document.length),
        extend: extend, area: area, nibble: nibble));
    _focus.requestFocus();
  }
  void _pointerMove(PointerMoveEvent event) {
    if (_dragPointer != event.pointer) return;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    if (_vertical.hasClients) {
      final delta = local.dy < 20 ? -_rowHeight : local.dy > box.size.height - 20 ? _rowHeight : 0.0;
      if (delta != 0) {
        _vertical.jumpTo((_vertical.offset + delta).clamp(0.0, _vertical.position.maxScrollExtent));
      }
    }
    _hit(local, extend: true);
  }
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    final command = hardware.isControlPressed || hardware.isMetaPressed;
    final shift = hardware.isShiftPressed;
    if (command) {
      if (key == LogicalKeyboardKey.keyS) { widget.onSave?.call(); }
      else if (key == LogicalKeyboardKey.keyA) { unawaited(c.selectAll()); }
      else if (key == LogicalKeyboardKey.keyC) { unawaited(c.copy()); }
      else if (key == LogicalKeyboardKey.keyX) { unawaited(c.copy(cut: true)); }
      else if (key == LogicalKeyboardKey.keyV) { unawaited(c.paste()); }
      else if (key == LogicalKeyboardKey.keyZ) { unawaited(shift ? c.redo() : c.undo()); }
      else if (key == LogicalKeyboardKey.keyY) { unawaited(c.redo()); }
      else if (key == LogicalKeyboardKey.keyF) { unawaited(_find()); }
      else if (key == LogicalKeyboardKey.keyG) { unawaited(_goTo()); }
      else if (key == LogicalKeyboardKey.home) { unawaited(c.select(0, extend: shift)); }
      else if (key == LogicalKeyboardKey.end) { unawaited(c.select(c.document.length, extend: shift)); }
      else { return KeyEventResult.ignored; }
      return KeyEventResult.handled;
    }
    if (hardware.isAltPressed) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft) { unawaited(c.moveNibble(-1, extend: shift)); }
    else if (key == LogicalKeyboardKey.arrowRight) { unawaited(c.moveNibble(1, extend: shift)); }
    else if (key == LogicalKeyboardKey.arrowUp) { unawaited(c.move(-16, extend: shift)); }
    else if (key == LogicalKeyboardKey.arrowDown) { unawaited(c.move(16, extend: shift)); }
    else if (key == LogicalKeyboardKey.home) { unawaited(c.select(c.caret ~/ 16 * 16, extend: shift)); }
    else if (key == LogicalKeyboardKey.end) { unawaited(c.select(math.min(c.document.length, (c.caret ~/ 16 + 1) * 16), extend: shift)); }
    else if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown) {
      final rows = _vertical.hasClients ? math.max(1, (_vertical.position.viewportDimension / _rowHeight).floor()) : 16;
      unawaited(c.move(rows * 16 * (key == LogicalKeyboardKey.pageUp ? -1 : 1), extend: shift));
    }
    else if (key == LogicalKeyboardKey.insert) { unawaited(c.setInsertMode(!c.insertMode)); }
    else if (key == LogicalKeyboardKey.delete) { unawaited(c.delete()); }
    else if (key == LogicalKeyboardKey.backspace) { unawaited(c.delete(backward: true)); }
    else if (key == LogicalKeyboardKey.tab) { unawaited(c.setArea(c.area == HexArea.hex ? HexArea.ascii : HexArea.hex)); }
    else if (key == LogicalKeyboardKey.escape && c.searching) { c.cancelSearch(); }
    else {
      final text = event.character;
      if (text == null || text.isEmpty || text.codeUnits.any((v) => v < 32)) return KeyEventResult.ignored;
      if (c.area == HexArea.hex) {
        final digit = text.length == 1 ? int.tryParse(text, radix: 16) : null;
        if (digit == null) return KeyEventResult.ignored;
        unawaited(c.typeDigit(digit));
      } else { unawaited(c.typeText(text)); }
    }
    return KeyEventResult.handled;
  }
  Future<String?> _prompt(String title, String hint, {String initial = ''}) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: TextField(autofocus: true, controller: input,
        decoration: InputDecoration(hintText: hint), onSubmitted: (text) => Navigator.pop(context, text)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, input.text), child: const Text('Apply'))],
    ));
    // Route dismissal animations may still reference the field this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (mounted) _focus.requestFocus();
    return value;
  }
  void _message(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }
  Future<void> _goTo() async {
    final value = await _prompt('Go to byte offset', 'Decimal, or 0x… for hexadecimal');
    if (value == null || !mounted) return;
    final text = value.trim();
    final offset = text.toLowerCase().startsWith('0x') ? int.tryParse(text.substring(2), radix: 16) : int.tryParse(text);
    if (offset == null || offset < 0 || offset > c.document.length) { _message('Offset must be between 0 and ${c.document.length}.'); return; }
    await c.select(offset);
  }
  Future<void> _find() async {
    final textMode = c.area == HexArea.ascii;
    final value = await _prompt(textMode ? 'Find ${c.latin1 ? 'Latin-1' : 'ASCII'} text' : 'Find hexadecimal bytes',
        textMode ? 'Exact, case-sensitive text' : 'Example: 00 FF 0A');
    if (value == null || !mounted) return;
    try {
      if (textMode && value.runes.any((v) => v > (c.latin1 ? 255 : 127))) throw const FormatException('Text is outside the selected byte encoding.');
      final bytes = textMode ? Uint8List.fromList(value.codeUnits) : parseHexBytes(value);
      await c.findNext(bytes);
    } catch (error) { _message(error); }
  }
  Future<void> _enter() async {
    final value = await _prompt(c.area == HexArea.hex ? 'Enter hexadecimal bytes' : 'Enter byte text',
      c.selectionLength > 0 ? 'Replaces ${c.selectionLength} selected bytes' : c.insertMode ? 'Insert at the caret' : 'Overwrite at the caret');
    if (value == null || !mounted) return;
    try {
      if (c.area == HexArea.hex) { await c.writeBytes(parseHexBytes(value)); }
      else { await c.typeText(value); }
    } catch (error) { _message(error); }
  }
  Widget _button(IconData icon, String label, VoidCallback? action) =>
      IconButton(tooltip: label, onPressed: action, icon: Icon(icon));
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final style = TextStyle(fontFamily: 'monospace', fontSize: 14, color: colors.onSurface);
    final metric = TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context))..layout();
    _charWidth = metric.width;
    _rowHeight = math.max(24, metric.height + 6);
    metric.dispose();
    final digits = hexOffsetDigits(c.document.length);
    final rowWidth = hexRowChars(digits) * _charWidth + 16;
    final rows = c.document.length ~/ 16 + 1; // Includes an append position at EOF.
    final editable = !c.readOnly;
    return Column(children: [
      Material(color: colors.surfaceContainerLow, child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: [
          _button(Icons.undo, 'Undo', editable && c.document.canUndo ? () => unawaited(c.undo()) : null),
          _button(Icons.redo, 'Redo', editable && c.document.canRedo ? () => unawaited(c.redo()) : null),
          _button(Icons.content_cut, 'Cut bytes', editable ? () => unawaited(c.copy(cut: true)) : null),
          _button(Icons.content_copy, 'Copy bytes', () => unawaited(c.copy())),
          _button(Icons.content_paste, 'Paste bytes', editable ? () => unawaited(c.paste()) : null),
          _button(Icons.select_all, 'Select all bytes', () => unawaited(c.selectAll())),
          _button(Icons.search, 'Find bytes or text', () => unawaited(_find())),
          _button(Icons.pin_drop_outlined, 'Go to byte offset', () => unawaited(_goTo())),
          _button(Icons.edit, 'Enter or replace bytes', editable ? () => unawaited(_enter()) : null),
          _button(Icons.keyboard, 'Toggle hexadecimal keypad', () => setState(() => _keypad = !_keypad)),
          TextButton(onPressed: editable ? () => unawaited(c.setInsertMode(!c.insertMode)) : null,
            child: Text(c.insertMode ? 'INS' : 'OVR')),
          TextButton(onPressed: () => unawaited(c.setArea(c.area == HexArea.hex ? HexArea.ascii : HexArea.hex)),
            child: Text(c.area == HexArea.hex ? 'Hex input' : 'Text input')),
          TextButton(onPressed: () => unawaited(c.setLatin1(!c.latin1)), child: Text(c.latin1 ? 'Latin-1' : 'ASCII')),
        ]))),
      if (c.searching) Row(children: [const SizedBox(width: 12), const SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2)), const Expanded(child: Padding(padding: EdgeInsets.all(8),
        child: Text('Searching bytes…'))), TextButton(onPressed: c.cancelSearch, child: const Text('Cancel'))]),
      if (c.error != null) Material(color: colors.errorContainer, child: Row(children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Text(c.error!, style: TextStyle(color: colors.onErrorContainer)))),
        _button(Icons.close, 'Dismiss editor error', c.clearError),
      ])),
      Expanded(child: Focus(autofocus: true, focusNode: _focus, onKeyEvent: _key,
        child: LayoutBuilder(builder: (context, constraints) => Listener(key: _viewport,
          onPointerDown: (event) {
            if (event.kind == PointerDeviceKind.mouse && event.buttons == kPrimaryMouseButton) {
              _dragPointer = event.pointer;
              _hit(event.localPosition, extend: HardwareKeyboard.instance.isShiftPressed);
            }
          }, onPointerMove: _pointerMove,
          onPointerUp: (_) => _dragPointer = null,
          onPointerCancel: (_) => _dragPointer = null,
          child: Scrollbar(controller: _horizontal, notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(controller: _horizontal, scrollDirection: Axis.horizontal,
              child: SizedBox(width: math.max(rowWidth, constraints.maxWidth), height: constraints.maxHeight,
                child: Scrollbar(controller: _vertical,
                  child: ListView.builder(controller: _vertical, itemExtent: _rowHeight, itemCount: rows,
                    itemBuilder: (context, row) {
                      final offset = row * 16;
                      final count = math.min(16, c.document.length - offset);
                      final future = count <= 0 ? Future.value(Uint8List(0)) : _page(offset ~/ _pageSize);
                      return FutureBuilder<Uint8List>(key: ValueKey((_snapshot.revision, row)), future: future,
                        builder: (context, state) {
                          if (state.hasError) return Text('Read failed: ${state.error}', style: TextStyle(color: colors.error));
                          if (!state.hasData) return Text('${hexNumber(offset, digits)}  …', style: style);
                          final bytes = count == 0 ? Uint8List(0) : Uint8List.sublistView(state.data!, offset % _pageSize, offset % _pageSize + count);
                          return GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: (details) {
                            final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
                            if (box != null) _hit(box.globalToLocal(details.globalPosition), extend: HardwareKeyboard.instance.isShiftPressed);
                          }, child: Semantics(label: 'Offset ${hexNumber(offset, digits)}: ${bytes.map((b) => hexNumber(b, 2)).join(' ')}',
                            child: CustomPaint(painter: _HexRowPainter(bytes: bytes, offset: offset, digits: digits,
                              style: style, scaler: MediaQuery.textScalerOf(context), charWidth: _charWidth,
                              selectionStart: c.selectionStart, selectionEnd: c.selectionEnd,
                              caret: c.caret, nibble: c.nibble, area: c.area, insert: c.insertMode,
                              latin1: c.latin1, selection: colors.primary.withValues(alpha: 0.25), cursor: colors.primary),
                              size: Size(rowWidth, _rowHeight))));
                        });
                    }))))))))),
      if (_keypad) Material(color: colors.surfaceContainerLow, child: Wrap(alignment: WrapAlignment.center,
        children: [for (var digit = 0; digit < 16; digit++) SizedBox(width: 44, height: 40,
          child: TextButton(onPressed: editable ? () { if (c.area != HexArea.hex) unawaited(c.setArea(HexArea.hex)); unawaited(c.typeDigit(digit)); } : null,
            child: Text(digit.toRadixString(16).toUpperCase()))),
          _button(Icons.backspace_outlined, 'Delete previous byte', editable ? () => unawaited(c.delete(backward: true)) : null)])),
      Container(width: double.infinity, color: colors.surfaceContainerLow, padding: const EdgeInsets.all(8),
        child: Text('0x${hexNumber(c.caret, digits)} · ${c.document.length} bytes'
          '${c.selectionLength > 0 ? ' · ${c.selectionLength} selected' : ''}'
          ' · ${c.readOnly ? 'Read-only' : widget.saving ? 'Saving…' : c.isDirty ? 'Unsaved' : 'Saved'}',
          maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
    ]);
  }
  @override
  void dispose() {
    c.removeListener(_changed);
    _focus.dispose(); _vertical.dispose(); _horizontal.dispose();
    super.dispose();
  }
}

class _HexRowPainter extends CustomPainter {
  _HexRowPainter({required this.bytes, required this.offset, required this.digits,
    required this.style, required this.scaler, required this.charWidth,
    required this.selectionStart, required this.selectionEnd, required this.caret,
    required this.nibble, required this.area, required this.insert, required this.latin1,
    required this.selection, required this.cursor});
  final Uint8List bytes;
  final int offset, digits, selectionStart, selectionEnd, caret, nibble;
  final TextStyle style;
  final TextScaler scaler;
  final double charWidth;
  final HexArea area;
  final bool insert, latin1;
  final Color selection, cursor;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save(); canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = selection;
    for (var i = 0; i < bytes.length; i++) {
      if (offset + i >= selectionStart && offset + i < selectionEnd) {
        canvas.drawRect(Rect.fromLTWH(8 + hexCharCol(i, digits) * charWidth, 0, 2 * charWidth, size.height), paint);
        canvas.drawRect(Rect.fromLTWH(8 + asciiCharCol(i, digits) * charWidth, 0, charWidth, size.height), paint);
      }
    }
    if (caret >= offset && caret < offset + 16 && caret <= offset + bytes.length) {
      final i = caret - offset;
      final column = area == HexArea.hex ? hexCharCol(i, digits) + nibble : asciiCharCol(i, digits);
      canvas.drawRect(Rect.fromLTWH(8 + column * charWidth, 1, insert ? 2 : charWidth, size.height - 2),
        Paint()..color = cursor.withValues(alpha: insert ? 0.9 : 0.3));
    }
    final text = TextPainter(text: TextSpan(text: hexRowLine(bytes, offset, digits, latin1: latin1), style: style),
      textDirection: TextDirection.ltr, textScaler: scaler)..layout();
    text.paint(canvas, Offset(8, (size.height - text.height) / 2));
    text.dispose(); canvas.restore();
  }
  @override
  bool shouldRepaint(_HexRowPainter old) => true;
}
