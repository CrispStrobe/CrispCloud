// Native Flutter byte-window UI derived from the MadEdit2 hex viewport.
// Copyright (c) 2026 madedit. MIT License; see the package LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hex_editor_controller.dart';
import 'hex_viewport.dart';

/// Optional color overrides. Unspecified colors follow the enclosing theme.
@immutable
class HexEditorTheme {
  const HexEditorTheme({
    this.backgroundColor,
    this.foregroundColor,
    this.offsetColor,
    this.selectionColor,
    this.caretColor,
    this.currentRowColor,
    this.headerColor,
  });

  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? offsetColor;
  final Color? selectionColor;
  final Color? caretColor;
  final Color? currentRowColor;
  final Color? headerColor;
}

/// Labels for the editor's small context menu and accessibility surface.
/// The host owns file dialogs, search/go-to controls, and status/toolbar text.
@immutable
class HexEditorLabels {
  const HexEditorLabels({
    this.editor = 'Hex editor',
    this.offset = 'Offset',
    this.text = 'Text',
    this.copy = 'Copy',
    this.cut = 'Cut',
    this.paste = 'Paste',
    this.selectAll = 'Select all',
    this.enterBytes = 'Enter bytes…',
    this.hexInput = 'Hexadecimal bytes',
    this.textInput = 'Byte text (Latin-1)',
    this.apply = 'Apply',
    this.cancel = 'Cancel',
    this.retry = 'Retry',
    this.scroll = 'Scroll bytes',
    this.loading = 'Loading bytes',
  });

  final String editor;
  final String offset;
  final String text;
  final String copy;
  final String cut;
  final String paste;
  final String selectAll;
  final String enterBytes;
  final String hexInput;
  final String textInput;
  final String apply;
  final String cancel;
  final String retry;
  final String scroll;
  final String loading;
}

/// A virtualized native Flutter hex editor. Only the visible byte range is read
/// and painted; file length is never turned into a giant scrollable widget.
///
/// Hardware keyboard input, mouse/touch selection, long-press/right-click
/// clipboard actions and a touch-friendly byte-entry dialog are built in.
/// The caller retains ownership of [controller] and its document.
class HexEditor extends StatefulWidget {
  const HexEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.bytesPerRow = 16,
    this.fontSize = 13,
    this.fontFamily = 'monospace',
    this.rowHeight,
    this.theme,
    this.labels = const HexEditorLabels(),
    this.focusNode,
    this.autofocus = true,
    this.showHeader = true,
    this.onError,
    this.requestSave,
    this.requestSearch,
    this.requestGoTo,
  }) : assert(bytesPerRow >= 4 && bytesPerRow <= 64),
       assert(fontSize > 0),
       assert(rowHeight == null || rowHeight > 0);

  final HexEditorController controller;
  final bool readOnly;
  final int bytesPerRow;
  final double fontSize;
  final String fontFamily;
  final double? rowHeight;
  final HexEditorTheme? theme;
  final HexEditorLabels labels;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool showHeader;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final FutureOr<void> Function()? requestSave;
  final VoidCallback? requestSearch;
  final VoidCallback? requestGoTo;

  @override
  State<HexEditor> createState() => _HexEditorState();
}

class _HexEditorState extends State<HexEditor> {
  final ScrollController _horizontal = ScrollController();
  late FocusNode _focus;
  bool _ownsFocus = false;
  Timer? _blink;
  Timer? _autoScroll;
  bool _caretOn = true;
  int _topRow = 0;
  int _visibleRows = 1;
  int _loadRows = 2;
  int _seenNavigation = 0;
  int _generation = 0;
  int _knownDocumentRevision = -1;
  bool _loadScheduled = false;
  bool _followHorizontal = true;
  bool _loading = false;
  Uint8List _bytes = Uint8List(0);
  (int, int, int)? _loadedKey;
  (int, int, int)? _loadingKey;
  Object? _loadError;
  String? _inputError;
  HexViewportGeometry? _geometry;
  double _viewportHeight = 0;
  double _wheelRemainder = 0;
  int? _dragAnchor;
  Offset? _dragPosition;
  HexEditorArea _dragArea = HexEditorArea.hex;

  HexEditorController get _controller => widget.controller;
  bool get _canEdit =>
      !widget.readOnly && !_controller.readOnly && !_controller.busy;
  int get _base => _topRow * widget.bytesPerRow;
  int get _totalRows => _controller.length ~/ widget.bytesPerRow + 1;
  int get _maxTopRow => math.max(0, _totalRows - _visibleRows);

  @override
  void initState() {
    super.initState();
    _setFocusNode();
    _controller.addListener(_controllerChanged);
    _seenNavigation = _controller.navigationRevision;
    _knownDocumentRevision = _controller.document.revision;
    _topRow = _controller.caretOffset ~/ widget.bytesPerRow;
    _blink = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted && _focus.hasFocus && !_controller.busy) {
        setState(() => _caretOn = !_caretOn);
      }
    });
  }

  void _setFocusNode() {
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'HexEditor');
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant HexEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_focusChanged);
      if (_ownsFocus) _focus.dispose();
      _setFocusNode();
    }
    if (oldWidget.controller != _controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      _controller.addListener(_controllerChanged);
      _seenNavigation = _controller.navigationRevision;
      _knownDocumentRevision = _controller.document.revision;
      _topRow = _controller.caretOffset ~/ widget.bytesPerRow;
      _invalidateWindow();
    }
    if (oldWidget.bytesPerRow != widget.bytesPerRow) {
      _topRow = _controller.caretOffset ~/ widget.bytesPerRow;
      _invalidateWindow();
    }
  }

  void _focusChanged() {
    if (mounted) setState(() => _caretOn = true);
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(() {
      _caretOn = true;
      if (_seenNavigation != _controller.navigationRevision) {
        _seenNavigation = _controller.navigationRevision;
        _ensureCaretVisible();
        _followHorizontal = true;
      }
      _topRow = _topRow.clamp(0, _maxTopRow);
      if (_knownDocumentRevision != _controller.document.revision) {
        _knownDocumentRevision = _controller.document.revision;
        _invalidateWindow();
      }
    });
    _scheduleLoad();
  }

  void _ensureCaretVisible() {
    final row = _controller.caretOffset ~/ widget.bytesPerRow;
    if (row < _topRow) {
      _topRow = row;
    } else if (row >= _topRow + _visibleRows) {
      _topRow = row - _visibleRows + 1;
    }
  }

  void _invalidateWindow() {
    _generation++;
    _loadedKey = null;
    _loadingKey = null;
    _bytes = Uint8List(0);
    _loadError = null;
  }

  (int, int, int) get _windowKey =>
      (_base, _loadRows * widget.bytesPerRow, _controller.document.revision);

  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) {
        if (_followHorizontal) {
          _followHorizontal = false;
          _ensureHorizontalVisible();
        }
        _loadWindow();
      }
    });
  }

  void _ensureHorizontalVisible() {
    final geometry = _geometry;
    if (geometry == null || !_horizontal.hasClients) return;
    final byte = _controller.caretOffset % widget.bytesPerRow;
    final column = _controller.activeArea == HexEditorArea.hex
        ? geometry.hexColumn(byte) + _controller.caretNibble
        : geometry.asciiColumn(byte);
    final left = geometry.x(column);
    final right = left + geometry.characterWidth * 2;
    final position = _horizontal.position;
    if (left < _horizontal.offset) {
      _horizontal.jumpTo(left.clamp(0, position.maxScrollExtent));
    } else if (right > _horizontal.offset + position.viewportDimension) {
      _horizontal.jumpTo(
        (right - position.viewportDimension).clamp(0, position.maxScrollExtent),
      );
    }
  }

  Future<void> _loadWindow({bool force = false}) async {
    final key = _windowKey;
    if (!force && (key == _loadedKey || key == _loadingKey)) return;
    final controller = _controller;
    final ticket = ++_generation;
    setState(() {
      _loading = true;
      _loadingKey = key;
      _bytes = Uint8List(0);
      _loadError = null;
    });
    try {
      final bytes = await controller.document.read(key.$1, key.$2);
      if (!mounted ||
          ticket != _generation ||
          controller != _controller ||
          key != _windowKey) {
        return;
      }
      setState(() {
        _bytes = bytes;
        _loadedKey = key;
        _loadingKey = null;
        _loading = false;
      });
    } catch (error, stack) {
      if (!mounted ||
          ticket != _generation ||
          controller != _controller ||
          key != _windowKey) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
        _loadingKey = null;
        // A failed window stays failed until explicit retry or navigation.
        _loadedKey = key;
      });
      widget.onError?.call(error, stack);
    }
  }

  void _scrollToRow(int row) {
    final next = row.clamp(0, _maxTopRow);
    if (next == _topRow) return;
    setState(() {
      _topRow = next;
      _invalidateWindow();
    });
    _scheduleLoad();
  }

  void _scrollRows(double rows) {
    _wheelRemainder += rows;
    final whole = _wheelRemainder.truncate();
    if (whole == 0) return;
    _wheelRemainder -= whole;
    _scrollToRow(_topRow + whole);
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift || event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()) {
        if (_horizontal.hasClients) {
          final delta = shift ? event.scrollDelta.dy : event.scrollDelta.dx;
          _horizontal.jumpTo(
            (_horizontal.offset + delta).clamp(
              0,
              _horizontal.position.maxScrollExtent,
            ),
          );
        }
      } else {
        _scrollRows(event.scrollDelta.dy / (_geometry?.rowHeight ?? 20));
      }
    });
  }

  HexViewportHit? _hit(Offset position, {bool clampY = false}) =>
      _geometry?.hitTest(
        position,
        base: _base,
        length: _controller.length,
        visibleRows: _visibleRows,
        clampY: clampY,
      );

  void _tap(TapDownDetails details) {
    final hit = _hit(details.localPosition);
    if (hit == null) return;
    _focus.requestFocus();
    _controller.setCaret(
      hit.offset,
      nibble: hit.nibble,
      area: hit.area,
      extendSelection: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void _dragStart(DragStartDetails details) {
    final hit = _hit(details.localPosition, clampY: true);
    if (hit == null) return;
    _focus.requestFocus();
    _dragAnchor = HardwareKeyboard.instance.isShiftPressed
        ? _controller.selection.anchor
        : hit.offset;
    _dragArea = hit.area;
    _dragPosition = details.localPosition;
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 70), (_) {
      final point = _dragPosition;
      if (point == null || !mounted) return;
      final header = _geometry?.headerHeight ?? 0;
      if (point.dy < header) {
        _scrollToRow(_topRow - 2);
        _updateDrag(point);
      } else if (point.dy > _viewportHeight - 12) {
        _scrollToRow(_topRow + 2);
        _updateDrag(point);
      }
    });
  }

  void _updateDrag(Offset point) {
    _dragPosition = point;
    final anchor = _dragAnchor;
    final hit = _hit(point, clampY: true);
    if (anchor == null || hit == null) return;
    final end = hit.offset >= anchor
        ? math.min(_controller.length, hit.offset + 1)
        : hit.offset;
    _controller.setSelection(anchor, end, area: _dragArea);
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragAnchor = null;
    _dragPosition = null;
  }

  void _run(Future<void> future) {
    unawaited(
      future.then<void>(
        (_) {
          if (mounted && _inputError != null) {
            setState(() => _inputError = null);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!mounted) return;
          if (widget.onError != null) {
            widget.onError!(error, stack);
          } else {
            setState(() => _inputError = error.toString());
          }
        },
      ),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    if (command && !alt) {
      if (key == LogicalKeyboardKey.keyA) {
        _controller.selectAll();
      } else if (key == LogicalKeyboardKey.keyC) {
        _run(_controller.copy());
      } else if (key == LogicalKeyboardKey.keyX && _canEdit) {
        _run(_controller.cut());
      } else if (key == LogicalKeyboardKey.keyV && _canEdit) {
        _run(_controller.paste());
      } else if (key == LogicalKeyboardKey.keyZ && _canEdit) {
        _run(shift ? _controller.redo() : _controller.undo());
      } else if (key == LogicalKeyboardKey.keyY && _canEdit) {
        _run(_controller.redo());
      } else if (key == LogicalKeyboardKey.keyS && widget.requestSave != null) {
        _run(() async {
          await _controller.settled;
          if (mounted) await widget.requestSave!();
        }());
      } else if (key == LogicalKeyboardKey.keyF &&
          widget.requestSearch != null) {
        widget.requestSearch!();
      } else if (key == LogicalKeyboardKey.keyG && widget.requestGoTo != null) {
        widget.requestGoTo!();
      } else if (key == LogicalKeyboardKey.home) {
        _controller.setCaret(0, extendSelection: shift);
      } else if (key == LogicalKeyboardKey.end) {
        _controller.setCaret(_controller.length, extendSelection: shift);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (alt || command) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _controller.moveHorizontal(
        key == LogicalKeyboardKey.arrowLeft ? -1 : 1,
        extendSelection: shift,
      );
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _controller.moveCaret(
        key == LogicalKeyboardKey.arrowUp
            ? -widget.bytesPerRow
            : widget.bytesPerRow,
        extendSelection: shift,
      );
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      final delta = math.max(1, _visibleRows - 1) * widget.bytesPerRow;
      _controller.moveCaret(
        key == LogicalKeyboardKey.pageUp ? -delta : delta,
        extendSelection: shift,
      );
    } else if (key == LogicalKeyboardKey.home) {
      _controller.setCaret(
        (_controller.caretOffset ~/ widget.bytesPerRow) * widget.bytesPerRow,
        extendSelection: shift,
      );
    } else if (key == LogicalKeyboardKey.end) {
      _controller.setCaret(
        math.min(
          _controller.length,
          (_controller.caretOffset ~/ widget.bytesPerRow + 1) *
              widget.bytesPerRow,
        ),
        extendSelection: shift,
      );
    } else if (key == LogicalKeyboardKey.tab && !shift) {
      _controller.toggleArea();
    } else if (key == LogicalKeyboardKey.escape) {
      _controller.cancelSearch();
      _controller.clearSelection();
      if (_inputError != null) setState(() => _inputError = null);
    } else if (key == LogicalKeyboardKey.f3 && _controller.hasSearchPattern) {
      _run(
        (shift ? _controller.findPrevious() : _controller.findNext())
            .then<void>((_) {}),
      );
    } else if (!_canEdit) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.insert) {
      _controller.toggleInsertMode();
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _run(
        _controller.deleteSelection(
          backward: key == LogicalKeyboardKey.backspace,
        ),
      );
    } else {
      final character = event.character;
      if (character == null || character.isEmpty) return KeyEventResult.ignored;
      if (_controller.activeArea == HexEditorArea.hex) {
        if (!RegExp(r'^[0-9a-fA-F]$').hasMatch(character)) {
          return KeyEventResult.ignored;
        }
        _run(_controller.typeHexDigit(int.parse(character, radix: 16)));
      } else {
        try {
          _run(_controller.typeText(character));
        } catch (error, stack) {
          _run(Future<void>.error(error, stack));
        }
      }
    }
    return KeyEventResult.handled;
  }

  Future<void> _contextMenu(
    Offset global, {
    Offset? local,
    bool touch = false,
  }) async {
    _focus.requestFocus();
    if (local != null && !_controller.hasSelection) {
      final hit = _hit(local);
      if (hit != null) {
        if (touch && hit.offset < _controller.length) {
          _controller.setSelection(hit.offset, hit.offset + 1, area: hit.area);
        } else {
          _controller.setCaret(hit.offset, nibble: hit.nibble, area: hit.area);
        }
      }
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final point = overlay.globalToLocal(global);
    final labels = widget.labels;
    final command = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        point & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          enabled: _controller.hasSelection,
          child: Text(labels.copy),
        ),
        PopupMenuItem(
          value: 'cut',
          enabled: _canEdit && _controller.hasSelection,
          child: Text(labels.cut),
        ),
        PopupMenuItem(
          value: 'paste',
          enabled: _canEdit,
          child: Text(labels.paste),
        ),
        PopupMenuItem(
          value: 'input',
          enabled: _canEdit,
          child: Text(labels.enterBytes),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'all',
          enabled: _controller.length > 0,
          child: Text(labels.selectAll),
        ),
      ],
    );
    if (!mounted) return;
    switch (command) {
      case 'copy':
        _run(_controller.copy());
      case 'cut':
        if (_canEdit) _run(_controller.cut());
      case 'paste':
        if (_canEdit) _run(_controller.paste());
      case 'all':
        _controller.selectAll();
      case 'input':
        if (_canEdit) await _showInput();
    }
    if (mounted) _focus.requestFocus();
  }

  Future<void> _showInput() async {
    final input = TextEditingController();
    String? error;
    final area = _controller.activeArea;
    final labels = widget.labels;
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            void submit() {
              try {
                if (area == HexEditorArea.hex) {
                  HexEditorController.parseHex(input.text);
                }
                if (area == HexEditorArea.ascii &&
                    input.text.runes.any((r) => r > 255)) {
                  throw const FormatException(
                    'Enter Latin-1 characters or use the hex column.',
                  );
                }
                Navigator.pop(context, input.text);
              } catch (e) {
                update(() => error = e.toString());
              }
            }

            return AlertDialog(
              title: Text(
                area == HexEditorArea.hex ? labels.hexInput : labels.textInput,
              ),
              content: SizedBox(
                width: 360,
                child: TextField(
                  controller: input,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: area == HexEditorArea.hex ? '00 FF A5' : null,
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(labels.cancel),
                ),
                FilledButton(onPressed: submit, child: Text(labels.apply)),
              ],
            );
          },
        ),
      );
      if (text != null && mounted && _canEdit) {
        _run(_controller.pasteText(text, area: area));
      }
    } finally {
      // Dialog descendants are disposed after the route's reverse animation.
      WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 320.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        return SizedBox(
          width: width,
          height: height,
          child: _buildViewport(context, width, height),
        );
      },
    );
  }

  Widget _buildViewport(BuildContext context, double width, double height) {
    final colors = Theme.of(context).colorScheme;
    final overrides = widget.theme;
    final background = overrides?.backgroundColor ?? colors.surface;
    final foreground = overrides?.foregroundColor ?? colors.onSurface;
    final textStyle = TextStyle(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      height: 1,
      color: foreground,
    );
    final measure = TextPainter(
      text: TextSpan(text: '0000000000', style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final rowHeight =
        widget.rowHeight ?? math.max(widget.fontSize * 1.6, measure.height + 4);
    final headerHeight = widget.showHeader ? rowHeight + 8 : 0.0;
    final available = math.max(rowHeight, height - headerHeight - 12);
    _visibleRows = math.max(1, (available / rowHeight).floor());
    _loadRows = math.max(1, (available / rowHeight).ceil() + 1);
    _topRow = _topRow.clamp(0, _maxTopRow);
    _viewportHeight = height;
    final geometry = HexViewportGeometry(
      bytesPerRow: widget.bytesPerRow,
      offsetDigits: HexViewportGeometry.digitsForLength(_controller.length),
      characterWidth: measure.width / 10,
      rowHeight: rowHeight,
      headerHeight: headerHeight,
    );
    _geometry = geometry;
    _scheduleLoad();
    final canvasWidth = math.max(geometry.width, width - 14);
    final offsetColor = overrides?.offsetColor ?? colors.onSurfaceVariant;
    final painter = HexViewportPainter(
      bytes: _loadedKey == _windowKey ? _bytes : Uint8List(0),
      base: _base,
      documentLength: _controller.length,
      geometry: geometry,
      textStyle: textStyle,
      background: background,
      foreground: foreground,
      offsetColor: offsetColor,
      selectionColor: overrides?.selectionColor ?? colors.primary.withAlpha(70),
      caretColor: overrides?.caretColor ?? colors.primary,
      currentRowColor:
          overrides?.currentRowColor ?? colors.onSurface.withAlpha(7),
      headerColor: overrides?.headerColor ?? colors.surfaceContainerHighest,
      caretOffset: _controller.caretOffset,
      caretNibble: _controller.caretNibble,
      area: _controller.activeArea,
      selectionStart: _controller.selectionStart,
      selectionEnd: _controller.selectionEnd,
      insertMode: _controller.insertMode,
      showCaret: _caretOn || !_focus.hasFocus,
      focused: _focus.hasFocus,
      offsetLabel: widget.labels.offset,
      textLabel: widget.labels.text,
      onSemanticSelect: (offset) {
        _focus.requestFocus();
        _controller.setCaret(offset);
      },
    );
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      child: Semantics(
        container: true,
        label: widget.labels.editor,
        value:
            '${widget.labels.offset} 0x${_controller.caretOffset.toRadixString(16).toUpperCase()}, '
            '${_controller.selectionLength} bytes selected',
        increasedValue:
            '${widget.labels.offset} 0x${math.min(_controller.length, _controller.caretOffset + 1).toRadixString(16).toUpperCase()}',
        decreasedValue:
            '${widget.labels.offset} 0x${math.max(0, _controller.caretOffset - 1).toRadixString(16).toUpperCase()}',
        readOnly: !_canEdit,
        focusable: true,
        focused: _focus.hasFocus,
        onIncrease: () => _controller.moveCaret(1),
        onDecrease: () => _controller.moveCaret(-1),
        child: ColoredBox(
          color: background,
          child: Stack(
            children: [
              Positioned.fill(
                right: 14,
                child: Listener(
                  onPointerSignal: _pointerSignal,
                  onPointerPanZoomUpdate: (event) =>
                      _scrollRows(-event.panDelta.dy / rowHeight),
                  child: Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    thickness: 9,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: canvasWidth,
                        height: math.max(0, height - 12),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.text,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            dragStartBehavior: DragStartBehavior.down,
                            onTapDown: _tap,
                            onPanStart: _dragStart,
                            onPanUpdate: (details) =>
                                _updateDrag(details.localPosition),
                            onPanEnd: (_) => _endDrag(),
                            onPanCancel: _endDrag,
                            onSecondaryTapDown: (details) => _contextMenu(
                              details.globalPosition,
                              local: details.localPosition,
                            ),
                            onLongPressStart: (details) => _contextMenu(
                              details.globalPosition,
                              local: details.localPosition,
                              touch: true,
                            ),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                key: const ValueKey('hex-bytes-paint'),
                                painter: painter,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: math.min(headerHeight, math.max(0, height - 12)),
                bottom: math.min(12, height),
                right: 0,
                width: 14,
                child: _ByteScrollbar(
                  topRow: _topRow,
                  totalRows: _totalRows,
                  visibleRows: _visibleRows,
                  color: offsetColor.withAlpha(140),
                  label: widget.labels.scroll,
                  onRow: _scrollToRow,
                ),
              ),
              if (_loading)
                Positioned(
                  top: headerHeight,
                  left: 0,
                  right: 14,
                  child: Semantics(
                    label: widget.labels.loading,
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              if (_loadError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _loadError.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _loadWindow(force: true),
                          child: Text(widget.labels.retry),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_inputError != null)
                Positioned(
                  left: 12,
                  right: 26,
                  bottom: 16,
                  child: Material(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _inputError!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _blink?.cancel();
    _endDrag();
    _controller.removeListener(_controllerChanged);
    _focus.removeListener(_focusChanged);
    if (_ownsFocus) _focus.dispose();
    _horizontal.dispose();
    super.dispose();
  }
}

class _ByteScrollbar extends StatelessWidget {
  const _ByteScrollbar({
    required this.topRow,
    required this.totalRows,
    required this.visibleRows,
    required this.color,
    required this.label,
    required this.onRow,
  });

  final int topRow;
  final int totalRows;
  final int visibleRows;
  final Color color;
  final String label;
  final ValueChanged<int> onRow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      final maxRow = math.max(0, totalRows - visibleRows);
      final thumbHeight = maxRow == 0
          ? height
          : math.min(height, math.max(28.0, height * visibleRows / totalRows));
      final travel = math.max(0.0, height - thumbHeight);
      final top = maxRow == 0 ? 0.0 : travel * topRow / maxRow;
      void jump(double y) {
        if (travel <= 0) return;
        onRow(
          (((y - thumbHeight / 2) / travel).clamp(0.0, 1.0) * maxRow).round(),
        );
      }

      return Semantics(
        label: label,
        value:
            '${totalRows <= 1 ? 0 : (topRow / (totalRows - 1) * 100).round()}%',
        increasedValue:
            '${totalRows <= 1 ? 0 : (math.min(maxRow, topRow + visibleRows) / (totalRows - 1) * 100).round()}%',
        decreasedValue:
            '${totalRows <= 1 ? 0 : (math.max(0, topRow - visibleRows) / (totalRows - 1) * 100).round()}%',
        onIncrease: () => onRow(topRow + visibleRows),
        onDecrease: () => onRow(topRow - visibleRows),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => jump(details.localPosition.dy),
          onVerticalDragStart: (details) => jump(details.localPosition.dy),
          onVerticalDragUpdate: (details) => jump(details.localPosition.dy),
          child: Stack(
            children: [
              Positioned(
                top: top,
                height: thumbHeight,
                left: 3,
                right: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
