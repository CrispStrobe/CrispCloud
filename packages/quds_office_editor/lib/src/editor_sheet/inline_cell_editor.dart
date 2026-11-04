import 'package:flutter/services.dart';

import '../core/input_bridge.dart';
import '../editor_word/caret_engine.dart';

/// Floating IME session synchronized with an in-place edit string.
class InlineCellEditor {
  /// InlineCellEditor API.
  InlineCellEditor({
    required this.onCommit,
    this.onChanged,
    this.commitOnNewline = true,
  });

  /// Function API.
  final void Function(String text) onCommit;

  /// Function API.
  final void Function()? onChanged;

  /// commitOnNewline API.
  final bool commitOnNewline;

  /// bridge API.
  late final OfficeInputBridge bridge = OfficeInputBridge(
    onValue: _onValue,
    onAction: _onAction,
  );

  /// formulaBar API.
  String formulaBar = '';

  /// editing API.
  var editing = false;

  /// caretIndex API.
  var caretIndex = 0;

  /// selectionBase API.
  var selectionBase = 0;

  /// selectionStart API.
  int get selectionStart =>
      selectionBase < caretIndex ? selectionBase : caretIndex;

  /// selectionEnd API.
  int get selectionEnd =>
      selectionBase > caretIndex ? selectionBase : caretIndex;

  /// hasSelection API.
  bool get hasSelection => selectionStart != selectionEnd;

  /// begin API.
  void begin(String initial, {int? caret, bool multiline = false}) {
    editing = true;
    formulaBar = initial;
    caretIndex = (caret ?? initial.length).clamp(0, initial.length);
    selectionBase = caretIndex;
    bridge.setValue(
      TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: caretIndex),
      ),
    );
    bridge.attach(
      multiline: multiline,
      action: multiline ? TextInputAction.newline : TextInputAction.done,
    );
    onChanged?.call();
  }

  /// end API.
  void end() {
    if (!editing) {
      return;
    }
    editing = false;
    onCommit(formulaBar);
    bridge.detach();
  }

  /// setCaret API.
  void setCaret(int index, {bool extend = false}) {
    caretIndex = index.clamp(0, formulaBar.length);
    if (!extend) {
      selectionBase = caretIndex;
    }
    _syncBridge();
    onChanged?.call();
  }

  /// moveCaret API.
  void moveCaret(int delta, {bool extend = false}) {
    setCaret(caretIndex + delta, extend: extend);
  }

  /// selectAll API.
  void selectAll() {
    if (!editing) {
      return;
    }
    selectionBase = 0;
    caretIndex = formulaBar.length;
    _syncBridge();
    onChanged?.call();
  }

  /// selectWord API.
  void selectWord(int index) {
    if (!editing) {
      return;
    }
    final ({int start, int end}) span = CaretEngine.wordBounds(
      formulaBar,
      index,
    );
    selectionBase = span.start;
    caretIndex = span.end;
    _syncBridge();
    onChanged?.call();
  }

  /// selectParagraph API.
  void selectParagraph(int index) {
    if (!editing) {
      return;
    }
    final ({int start, int end}) span = CaretEngine.paragraphBounds(
      formulaBar,
      index,
    );
    selectionBase = span.start;
    caretIndex = span.end;
    _syncBridge();
    onChanged?.call();
  }

  /// deleteBackward API.
  void deleteBackward() {
    if (!editing) {
      return;
    }
    if (hasSelection) {
      replaceRange(selectionStart, selectionEnd, '');
      return;
    }
    if (caretIndex <= 0) {
      return;
    }
    replaceRange(caretIndex - 1, caretIndex, '');
  }

  /// deleteForward API.
  void deleteForward() {
    if (!editing) {
      return;
    }
    if (hasSelection) {
      replaceRange(selectionStart, selectionEnd, '');
      return;
    }
    if (caretIndex >= formulaBar.length) {
      return;
    }
    replaceRange(caretIndex, caretIndex + 1, '');
  }

  /// replaceRange API.
  void replaceRange(int start, int end, String insert) {
    if (!editing) {
      return;
    }
    final int from = start.clamp(0, formulaBar.length);
    final int to = end.clamp(from, formulaBar.length);
    formulaBar = formulaBar.replaceRange(from, to, insert);
    caretIndex = from + insert.length;
    selectionBase = caretIndex;
    _syncBridge();
    onChanged?.call();
  }

  void _syncBridge() {
    bridge.setValue(
      TextEditingValue(
        text: formulaBar,
        selection: TextSelection(
          baseOffset: selectionBase.clamp(0, formulaBar.length),
          extentOffset: caretIndex.clamp(0, formulaBar.length),
        ),
      ),
    );
  }

  void _onValue(TextEditingValue value) {
    formulaBar = value.text;
    caretIndex = value.selection.extentOffset.clamp(0, formulaBar.length);
    selectionBase = value.selection.baseOffset.clamp(0, formulaBar.length);
    onChanged?.call();
  }

  void _onAction(TextInputAction action) {
    if (action == TextInputAction.done ||
        action == TextInputAction.next ||
        (action == TextInputAction.newline && commitOnNewline)) {
      end();
    }
  }
}
