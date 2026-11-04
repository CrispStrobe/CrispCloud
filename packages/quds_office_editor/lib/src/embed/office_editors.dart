import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../editor_sheet/render_sheet_grid.dart';
import '../editor_slide/render_slide_stage.dart';
import '../editor_word/paint_run_text.dart';
import '../editor_word/render_word_canvas.dart';
import 'office_clipboard.dart';
import 'office_context_menu.dart';
import 'office_controller.dart';
import 'office_direction_keys.dart';
import 'office_theme.dart';
import 'word_notes_pane.dart';

/// Class OfficeUndoIntent.
class OfficeUndoIntent extends Intent {
  /// OfficeUndoIntent API.
  const OfficeUndoIntent();
}

/// Class OfficeRedoIntent.
class OfficeRedoIntent extends Intent {
  /// OfficeRedoIntent API.
  const OfficeRedoIntent();
}

/// Class OfficeSelectAllIntent.
class OfficeSelectAllIntent extends Intent {
  /// OfficeSelectAllIntent API.
  const OfficeSelectAllIntent();
}

/// Class OfficeCopyIntent.
class OfficeCopyIntent extends Intent {
  /// OfficeCopyIntent API.
  const OfficeCopyIntent();
}

/// Class OfficeCutIntent.
class OfficeCutIntent extends Intent {
  /// OfficeCutIntent API.
  const OfficeCutIntent();
}

/// Class OfficePasteIntent.
class OfficePasteIntent extends Intent {
  /// OfficePasteIntent API.
  const OfficePasteIntent([this.mode = OfficePasteMode.keepSource]);

  /// mode API.
  final OfficePasteMode mode;
}

/// Class OfficeFindIntent.
class OfficeFindIntent extends Intent {
  /// OfficeFindIntent API.
  const OfficeFindIntent();
}

/// Class OfficeReplaceIntent.
class OfficeReplaceIntent extends Intent {
  /// OfficeReplaceIntent API.
  const OfficeReplaceIntent();
}

/// Class OfficePrintIntent.
class OfficePrintIntent extends Intent {
  /// OfficePrintIntent API.
  const OfficePrintIntent();
}

/// Class OfficeSpellCheckIntent.
class OfficeSpellCheckIntent extends Intent {
  /// OfficeSpellCheckIntent API.
  const OfficeSpellCheckIntent();
}

/// Class OfficeFindNextIntent.
class OfficeFindNextIntent extends Intent {
  /// OfficeFindNextIntent API.
  const OfficeFindNextIntent({this.forward = true});

  /// forward API.
  final bool forward;
}

/// Handles Ctrl+F/H/P, F3, and F7 from Focus.onKeyEvent (Shortcuts is a child).
bool officeHandleDocumentShortcut(OfficeController controller, KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return false;
  }
  final bool ctrl =
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  final bool shift = HardwareKeyboard.instance.isShiftPressed;
  if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
    controller.requestFind();
    return true;
  }
  if (ctrl && event.logicalKey == LogicalKeyboardKey.keyH) {
    controller.requestReplace();
    return true;
  }
  if (ctrl && event.logicalKey == LogicalKeyboardKey.keyP) {
    controller.requestPrint();
    return true;
  }
  if (event.logicalKey == LogicalKeyboardKey.f3) {
    if (controller.findSession.hits.isEmpty &&
        (controller.findSession.options == null ||
            controller.findSession.options!.query.isEmpty)) {
      controller.requestFind();
    } else if (shift) {
      controller.findPrevious();
    } else {
      controller.findNext();
    }
    return true;
  }
  if (event.logicalKey == LogicalKeyboardKey.f7) {
    controller.requestSpellCheck();
    return true;
  }
  if (event.logicalKey == LogicalKeyboardKey.escape &&
      controller.findSession.active) {
    controller.closeFind();
    return true;
  }
  if (ctrl && controller.config.allowsMutation) {
    if (controller is WordEditorController) {
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        controller.applyRunFormat((WmlRunProps p) => p.bold = !p.bold);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        controller.applyRunFormat((WmlRunProps p) => p.italic = !p.italic);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyU) {
        controller.applyRunFormat((WmlRunProps p) {
          p.underline = p.underline == WmlUnderline.none
              ? WmlUnderline.single
              : WmlUnderline.none;
        });
        return true;
      }
    }
  }
  return false;
}

/// Embeddable Word surface with focus, IME, shortcuts, and chrome slots.
class QudsWordEditor extends StatefulWidget {
  /// QudsWordEditor API.
  const QudsWordEditor({
    super.key,
    required this.controller,
    this.config,
    this.focusNode,
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.findBarBuilder,
    this.navigationBuilder,
    this.notesPaneBuilder,
    this.onSelectionChanged,
  });

  /// controller API.
  final WordEditorController controller;

  /// config API.
  final OfficeSurfaceConfig? config;

  /// focusNode API.
  final FocusNode? focusNode;

  /// Function API.
  final Widget Function(BuildContext context, WordEditorController controller)?
  /// toolbarBuilder API.
  toolbarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, WordEditorController controller)?
  /// statusBarBuilder API.
  statusBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, WordEditorController controller)?
  /// findBarBuilder API.
  findBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, WordEditorController controller)?
  /// navigationBuilder API.
  navigationBuilder;

  /// Function API.
  final Widget Function(BuildContext context, WordEditorController controller)?
  /// notesPaneBuilder API.
  notesPaneBuilder;

  /// onSelectionChanged API.
  final VoidCallback? onSelectionChanged;

  @override
  /// createState API.
  State<QudsWordEditor> createState() => _QudsWordEditorState();
}

class _QudsWordEditorState extends State<QudsWordEditor>
    with TickerProviderStateMixin {
  late final FocusNode _focus;
  late final bool _ownsFocus;
  late final Ticker _ticker;
  OverlayEntry? _contextMenu;

  /// controller API.
  WordEditorController get _c => widget.controller;

  @override
  /// initState API.
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'QudsWordEditor');
    _ticker = createTicker((Duration elapsed) {
      if (!_c.config.showsCaret) {
        return;
      }
      final bool before = _c.caret.visible;
      _c.caret.tick(elapsed);
      if (before != _c.caret.visible && mounted) {
        setState(() {});
      }
    })..start();
    _c.addListener(_onCtrl);
    PaintingBinding.instance.systemFonts.addListener(_onSystemFonts);
    _c.onRequestFocus = () {
      if (mounted) {
        _focus.requestFocus();
      }
    };
    if (widget.config != null) {
      _c.syncConfig(widget.config!);
    }
    if (_c.config.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  /// didUpdateWidget API.
  void didUpdateWidget(QudsWordEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != null && !identical(widget.config, _c.config)) {
      _c.syncConfig(widget.config!);
    }
  }

  void _onSystemFonts() {
    PaintRunText.clearAdvanceCache();
    if (mounted) {
      _c.refreshMetrics();
    }
  }

  void _onCtrl() {
    if (mounted) {
      setState(() {});
      widget.onSelectionChanged?.call();
    }
  }

  @override
  /// dispose API.
  void dispose() {
    _dismissContextMenu();
    _ticker.dispose();
    _c.removeListener(_onCtrl);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFonts);
    _c.onRequestFocus = null;
    if (_ownsFocus) {
      _focus.dispose();
    }
    super.dispose();
  }

  void _dismissContextMenu() {
    OfficeContextMenu.dismiss(_contextMenu);
    _contextMenu = null;
  }

  void _showWordContext(OfficeContextHit hit) {
    _dismissContextMenu();
    _contextMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: hit.globalPosition,
      actions: OfficeContextMenu.word(hit: hit, controller: _c),
      onSelect: (String id) {
        _contextMenu = null;
        _runWordContext(hit, id);
      },
    );
  }

  void _runWordContext(OfficeContextHit hit, String id) {
    switch (id) {
      case 'cut':
        _c.cutToClipboard();
      case 'copy':
        _c.copyToClipboard();
      case 'paste':
        _c.pasteFromClipboard();
      case 'selectAll':
        _c.selectAll();
      case 'insertRowAbove':
        _c.insertTableRow(after: false, table: hit.table, row: hit.tableRow);
      case 'insertRowBelow':
        _c.insertTableRow(after: true, table: hit.table, row: hit.tableRow);
      case 'insertColLeft':
        _c.insertTableColumn(after: false, table: hit.table, col: hit.tableCol);
      case 'insertColRight':
        _c.insertTableColumn(after: true, table: hit.table, col: hit.tableCol);
      case 'deleteRow':
        _c.deleteTableRow(table: hit.table, row: hit.tableRow);
      case 'deleteCol':
        _c.deleteTableColumn(table: hit.table, col: hit.tableCol);
      case 'deleteTable':
        _c.deleteTable(table: hit.table);
      case 'autoFitContents':
        _c.autoFitTable(WordTableAutoFit.contents, table: hit.table);
      case 'autoFitWindow':
        _c.autoFitTable(WordTableAutoFit.window, table: hit.table);
      case 'autoFitFixed':
        _c.autoFitTable(WordTableAutoFit.fixed, table: hit.table);
      case 'mergeTableCells':
        _c.mergeTableCells();
      case 'unmergeTableCells':
        _c.unmergeTableCells();
      case 'insertComment':
        _c.insertComment();
      case 'replyComment':
        if (hit.commentId != null) {
          _c.insertComment(parentId: hit.commentId);
          if (_c.document.comments.isNotEmpty) {
            _c.beginCommentEdit(_c.document.comments.last.id);
          }
        }
      case 'resolveComment':
        if (hit.commentId != null) {
          _c.setCommentResolved(hit.commentId!, true);
        }
      case 'reopenComment':
        if (hit.commentId != null) {
          _c.setCommentResolved(hit.commentId!, false);
        }
      case 'deleteComment':
        if (hit.commentId != null) {
          _c.deleteComment(hit.commentId!);
        }
      case 'followLink':
        if (hit.link != null) {
          _c.followLink(hit.link!);
        }
      case 'cropPicture':
        _c.togglePictureCropMode();
    }
  }

  void _onFocus() {
    if (_focus.hasFocus && _c.config.allowsMutation) {
      _c.attachInput();
    } else if (!_c.config.allowsMutation) {
      _c.detachInput();
    }
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _onWordKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool? directionRtl = officeDirectionFromKeyEvent(event);
    if (directionRtl != null && _c.config.allowsMutation) {
      _c.setParagraphDirection(rtl: directionRtl);
      return KeyEventResult.handled;
    }
    if (officeHandleDocumentShortcut(_c, event)) {
      return KeyEventResult.handled;
    }
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    if (_c.isEditingHeaderFooter &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _c.endHeaderFooterEdit();
      return KeyEventResult.handled;
    }
    if (_c.selectedFrame != null && !_c.editingFrame) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _c.selectFrame(null);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final double step = shift ? 12 : 8;
        final double dx = event.logicalKey == LogicalKeyboardKey.arrowLeft
            ? -step
            : (event.logicalKey == LogicalKeyboardKey.arrowRight ? step : 0);
        final double dy = event.logicalKey == LogicalKeyboardKey.arrowUp
            ? -step
            : (event.logicalKey == LogicalKeyboardKey.arrowDown ? step : 0);
        _c.nudgeSelectedFrame(dx: dx, dy: dy, resize: shift);
        return KeyEventResult.handled;
      }
    }
    if (_c.editingFrame && event.logicalKey == LogicalKeyboardKey.escape) {
      _c.selectFrame(_c.selectedFrame);
      return KeyEventResult.handled;
    }
    if (_c.selectedVisual != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_c.pictureCropMode) {
          _c.togglePictureCropMode();
        } else {
          _c.selectVisual(null);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        _c.togglePictureCropMode();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final double step = shift ? 12 : 8;
        final double dx = event.logicalKey == LogicalKeyboardKey.arrowLeft
            ? -step
            : (event.logicalKey == LogicalKeyboardKey.arrowRight ? step : 0);
        final double dy = event.logicalKey == LogicalKeyboardKey.arrowUp
            ? -step
            : (event.logicalKey == LogicalKeyboardKey.arrowDown ? step : 0);
        _c.nudgeSelectedVisual(
          dx: dx,
          dy: dy,
          resize: shift,
          crop: _c.pictureCropMode,
        );
        return KeyEventResult.handled;
      }
    }
    if (_c.selectedEquation != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _c.selectEquation(null);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        _c.moveEquationSlot(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _c.moveEquationArrow(dx: 1, dy: 0);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _c.moveEquationArrow(dx: -1, dy: 0);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _c.moveEquationArrow(dx: 0, dy: 1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _c.moveEquationArrow(dx: 0, dy: -1);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_c.moveTableCell(forward: !shift)) {
        return KeyEventResult.handled;
      }
      if (_c.config.allowsMutation && !shift) {
        _c.insertText('\t');
        return KeyEventResult.handled;
      }
    }
    if (_c.config.allowsSelection) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _c.moveCaretVisual(toRight: false, extend: shift);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _c.moveCaretVisual(toRight: true, extend: shift);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _c.moveCaretLine(-1, extend: shift);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _c.moveCaretLine(1, extend: shift);
        return KeyEventResult.handled;
      }
    }
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      _c.selectAll();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _c.copyToClipboard();
      return KeyEventResult.handled;
    }
    if (!_c.config.allowsMutation) {
      return KeyEventResult.ignored;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _c.redo();
      } else {
        _c.undo();
      }
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      _c.redo();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      _c.cutToClipboard();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _c.pasteFromClipboard(
        mode: shift ? OfficePasteMode.keepTextOnly : OfficePasteMode.keepSource,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _c.deleteSelectionOr(backward: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _c.deleteSelectionOr(backward: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _c.insertParagraphBreak();
      return KeyEventResult.handled;
    }
    // Fallback when IME is detached (e.g. after ribbon / language click).
    if (!_c.input.isAttached) {
      final String? ch = event.character;
      if (ch != null &&
          ch.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        final int unit = ch.codeUnitAt(0);
        if (unit >= 32 || unit == 9) {
          _c.insertText(ch);
          _c.attachInput();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Map<ShortcutActivator, Intent> get _shortcuts {
    return <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
          const OfficeUndoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
          const OfficeUndoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true):
          const OfficeRedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyY, meta: true):
          const OfficeRedoIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): const OfficeRedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true):
          const OfficeSelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
          const OfficeSelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          const OfficeCopyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
          const OfficeCopyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true):
          const OfficeCutIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
          const OfficeCutIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true):
          const OfficePasteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
          const OfficePasteIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      ): const OfficePasteIntent(
        OfficePasteMode.keepTextOnly,
      ),
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
          const OfficePasteIntent(OfficePasteMode.keepTextOnly),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true, alt: true):
          const OfficePasteIntent(OfficePasteMode.mergeFormatting),
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          const _MoveCaretIntent(-1),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          const _MoveCaretIntent(1),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
          const _MoveCaretIntent(-1, extend: true),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
          const _MoveCaretIntent(1, extend: true),
      const SingleActivator(LogicalKeyboardKey.arrowUp):
          const _MoveParagraphIntent(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown):
          const _MoveParagraphIntent(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
          const _MoveParagraphIntent(-1, extend: true),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
          const _MoveParagraphIntent(1, extend: true),
      const SingleActivator(LogicalKeyboardKey.backspace): const _DeleteIntent(
        backward: true,
      ),
      const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(
        backward: false,
      ),
      const SingleActivator(LogicalKeyboardKey.enter): const _BreakIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          const OfficeFindIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const OfficeFindIntent(),
      const SingleActivator(LogicalKeyboardKey.keyH, control: true):
          const OfficeReplaceIntent(),
      const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
          const OfficeReplaceIntent(),
      const SingleActivator(LogicalKeyboardKey.keyP, control: true):
          const OfficePrintIntent(),
      const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
          const OfficePrintIntent(),
      const SingleActivator(LogicalKeyboardKey.f7):
          const OfficeSpellCheckIntent(),
      const SingleActivator(LogicalKeyboardKey.f3):
          const OfficeFindNextIntent(),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true):
          const OfficeFindNextIntent(forward: false),
    };
  }

  @override
  /// build API.
  Widget build(BuildContext context) {
    final OfficeSurfaceConfig config = widget.config ?? _c.config;
    return Directionality(
      textDirection: config.textDirection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.toolbarBuilder != null)
            widget.toolbarBuilder!(context, _c),
          if (widget.findBarBuilder != null &&
              (config.showFindChrome || _c.findSession.active))
            widget.findBarBuilder!(context, _c),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.navigationBuilder != null &&
                    config.effectiveShowNavigationPane(
                      MediaQuery.sizeOf(context),
                    ))
                  SizedBox(
                    width: 220,
                    child: widget.navigationBuilder!(context, _c),
                  ),
                Expanded(
                  child: Focus(
                    focusNode: _focus,
                    onFocusChange: (_) => _onFocus(),
                    onKeyEvent: _onWordKey,
                    child: Shortcuts(
                      shortcuts: _shortcuts,
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ..._documentActions(_c),
                          OfficeUndoIntent: CallbackAction<OfficeUndoIntent>(
                            onInvoke: (_) {
                              _c.undo();
                              return null;
                            },
                          ),
                          OfficeRedoIntent: CallbackAction<OfficeRedoIntent>(
                            onInvoke: (_) {
                              _c.redo();
                              return null;
                            },
                          ),
                          OfficeSelectAllIntent:
                              CallbackAction<OfficeSelectAllIntent>(
                                onInvoke: (_) {
                                  _c.selectAll();
                                  return null;
                                },
                              ),
                          OfficeCopyIntent: CallbackAction<OfficeCopyIntent>(
                            onInvoke: (_) {
                              _c.copyToClipboard();
                              return null;
                            },
                          ),
                          OfficeCutIntent: CallbackAction<OfficeCutIntent>(
                            onInvoke: (_) {
                              _c.cutToClipboard();
                              return null;
                            },
                          ),
                          OfficePasteIntent: CallbackAction<OfficePasteIntent>(
                            onInvoke: (OfficePasteIntent i) {
                              _c.pasteFromClipboard(mode: i.mode);
                              return null;
                            },
                          ),
                          ..._documentActions(_c),
                          _MoveCaretIntent: CallbackAction<_MoveCaretIntent>(
                            onInvoke: (_MoveCaretIntent i) {
                              _c.moveCaretVisual(
                                toRight: i.delta > 0,
                                extend: i.extend,
                              );
                              return null;
                            },
                          ),
                          _MoveParagraphIntent:
                              CallbackAction<_MoveParagraphIntent>(
                                onInvoke: (_MoveParagraphIntent i) {
                                  _c.moveCaretLine(i.delta, extend: i.extend);
                                  return null;
                                },
                              ),
                          _DeleteIntent: CallbackAction<_DeleteIntent>(
                            onInvoke: (_DeleteIntent i) {
                              _c.deleteSelectionOr(backward: i.backward);
                              return null;
                            },
                          ),
                          _BreakIntent: CallbackAction<_BreakIntent>(
                            onInvoke: (_) {
                              _c.insertParagraphBreak();
                              return null;
                            },
                          ),
                        },
                        child: Semantics(
                          container: true,
                          label: _c.semanticsLabel,
                          value: _c.semanticsValue,
                          readOnly: !config.allowsMutation,
                          textField: config.allowsMutation,
                          child: WordCanvas(
                            document: _c.document,
                            laidOut: _c.documentLaidOut,
                            caret: _c.caret,
                            findHits: _c.findSession.hits,
                            activeFindIndex: _c.findSession.index,
                            viewport: _c.viewport,
                            config: config,
                            hasFocus:
                                !_c.isEditingComment &&
                                (_focus.hasFocus || _c.input.isAttached),
                            semanticsLabel: _c.semanticsLabel,
                            semanticsValue: _c.semanticsValue,
                            selectedVisual: _c.selectedVisual,
                            selectedFrame: _c.selectedFrame,
                            editingFrame: _c.editingFrame,
                            selectedEquation: _c.selectedEquation,
                            equationSlot: _c.equationSlot,
                            equationCaret: _c.equationCaret,
                            pictureCropMode: _c.pictureCropMode,
                            onBeginVisualTransform: _c.beginVisualTransform,
                            onPreviewVisualMove: _c.previewVisualMove,
                            onPreviewVisualResize: _c.previewVisualResize,
                            onPreviewVisualCrop: _c.previewVisualCrop,
                            onPreviewVisualRotate: _c.previewVisualRotate,
                            onCommitVisualTransform: _c.commitVisualTransform,
                            isVisualInSelection: _c.isVisualInSelection,
                            onExtendThroughVisual:
                                _c.extendSelectionThroughVisual,
                            onSelectVisual: _c.selectVisualFromOffice,
                            onSelectFrame: (WmlFrame? frame) =>
                                _c.selectFrame(frame),
                            onEditFrame: (WmlFrame frame) =>
                                _c.selectFrame(frame, editing: true),
                            onBeginFrameTransform: _c.beginFrameTransform,
                            onPreviewFrameMove: _c.previewFrameMove,
                            onPreviewFrameResize: _c.previewFrameResize,
                            onCommitFrameTransform: _c.commitFrameTransform,
                            onSelectEquation:
                                (WmlEquation? equation, int? slot, int? caret) {
                                  _c.selectEquation(
                                    equation,
                                    slot: slot,
                                    caret: caret,
                                  );
                                },
                            onActivateVisual: (OfficeVisual visual) {
                              _c.selectVisualFromOffice(visual);
                              _c.cycleSelectedVisualKind();
                            },
                            onJumpParagraph: _c.jumpToParagraph,
                            onFollowLink: _c.followLink,
                            selectedCommentId: _c.selectedCommentId,
                            onSelectComment: _c.selectComment,
                            onContextMenu: _showWordContext,
                            onInsertTableRowAt: _c.insertTableRowAt,
                            onInsertTableColumnAt: _c.insertTableColumnAt,
                            onBeginTableResize: _c.beginTableResize,
                            onPreviewTableColumnWidth:
                                _c.previewTableColumnWidth,
                            onPreviewTableRowHeight: _c.previewTableRowHeight,
                            onCommitTableResize: _c.commitTableResize,
                            selectedTable: _c.selectedTable,
                            onSelectTable: _c.selectTable,
                            selectedTableBand: _c.selectedTableBand,
                            onSelectTableBand: _c.selectTableBand,
                            storyParagraphs: _c.isEditingHeaderFooter
                                ? _c.headerFooterParagraphs
                                : null,
                            editingHeader: _c.isEditingHeader,
                            editingFooter: _c.isEditingFooter,
                            onBeginHeaderFooterEdit: _c.beginHeaderFooterEdit,
                            onEndHeaderFooterEdit: _c.endHeaderFooterEdit,
                            onBeginRulerEdit: _c.beginRulerEdit,
                            onPreviewRulerEdit: _c.previewRulerEdit,
                            onCommitRulerEdit: _c.commitRulerEdit,
                            onChanged: () {
                              _focus.requestFocus();
                              if (config.allowsMutation) {
                                _c.attachInput();
                              }
                              _c.refresh();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (config.showNotesPane)
                  SizedBox(
                    width: 240,
                    child: widget.notesPaneBuilder != null
                        ? widget.notesPaneBuilder!(context, _c)
                        : WordNotesPane(controller: _c),
                  ),
              ],
            ),
          ),
          if (widget.statusBarBuilder != null)
            widget.statusBarBuilder!(context, _c),
        ],
      ),
    );
  }
}

/// Embeddable spreadsheet surface.
class QudsSheetEditor extends StatefulWidget {
  /// QudsSheetEditor API.
  const QudsSheetEditor({
    super.key,
    required this.controller,
    this.config,
    this.focusNode,
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.findBarBuilder,
    this.navigationBuilder,
    this.frozenRows = 0,
    this.frozenCols = 0,
  });

  /// controller API.
  final SheetEditorController controller;

  /// config API.
  final OfficeSurfaceConfig? config;

  /// focusNode API.
  final FocusNode? focusNode;

  /// Function API.
  final Widget Function(BuildContext context, SheetEditorController controller)?
  /// toolbarBuilder API.
  toolbarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SheetEditorController controller)?
  /// statusBarBuilder API.
  statusBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SheetEditorController controller)?
  /// findBarBuilder API.
  findBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SheetEditorController controller)?
  /// navigationBuilder API.
  navigationBuilder;

  /// frozenRows API.
  final int frozenRows;

  /// frozenCols API.
  final int frozenCols;

  @override
  /// createState API.
  State<QudsSheetEditor> createState() => _QudsSheetEditorState();
}

class _QudsSheetEditorState extends State<QudsSheetEditor> {
  late final FocusNode _focus;
  late final bool _ownsFocus;
  Timer? _navRepeat;
  OverlayEntry? _contextMenu;

  /// controller API.
  SheetEditorController get _c => widget.controller;

  @override
  /// initState API.
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'QudsSheetEditor');
    _c.addListener(_rebuild);
    _focus.addListener(_onSheetFocus);
    if (widget.config != null) {
      _c.syncConfig(widget.config!);
    }
    if (_c.config.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  /// didUpdateWidget API.
  void didUpdateWidget(QudsSheetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != null && !identical(widget.config, _c.config)) {
      _c.syncConfig(widget.config!);
    }
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSheetFocus() {
    if (!_focus.hasFocus) {
      _stopNavRepeat();
    }
  }

  @override
  /// dispose API.
  void dispose() {
    _dismissContextMenu();
    _stopNavRepeat();
    _focus.removeListener(_onSheetFocus);
    _c.removeListener(_rebuild);
    if (_ownsFocus) {
      _focus.dispose();
    }
    super.dispose();
  }

  void _dismissContextMenu() {
    OfficeContextMenu.dismiss(_contextMenu);
    _contextMenu = null;
  }

  void _showSheetContext(OfficeContextHit hit) {
    _dismissContextMenu();
    _contextMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: hit.globalPosition,
      actions: OfficeContextMenu.sheet(hit: hit, controller: _c),
      onSelect: (String id) {
        _contextMenu = null;
        _runSheetContext(id);
      },
    );
  }

  void _runSheetContext(String id) {
    switch (id) {
      case 'cut':
        _c.cutToClipboard();
      case 'copy':
        _c.copyToClipboard();
      case 'paste':
        _c.pasteFromClipboard();
      case 'insertSheetRow':
        _c.insertSheetRows(after: false);
      case 'insertSheetCol':
        _c.insertSheetCols(after: false);
      case 'deleteSheetRow':
        _c.deleteSheetRows();
      case 'deleteSheetCol':
        _c.deleteSheetCols();
      case 'clearCells':
        _c.clearSelectedCells();
      case 'mergeAndCenter':
        _c.toggleMergeAndCenter();
      case 'unmergeCells':
        _c.unmergeCells();
    }
  }

  void _stopNavRepeat() {
    _navRepeat?.cancel();
    _navRepeat = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (_isSheetNavKey(event.logicalKey)) {
        _stopNavRepeat();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final bool repeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !repeat) {
      return KeyEventResult.ignored;
    }
    if (repeat) {
      if (_isSheetNavKey(event.logicalKey)) {
        _stopNavRepeat();
      }
      if (_handleSheetNav(event, startRepeat: false)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final bool? directionRtl = officeDirectionFromKeyEvent(event);
    if (directionRtl != null && _c.config.allowsMutation) {
      _c.setSheetRightToLeft(directionRtl);
      return KeyEventResult.handled;
    }
    if (officeHandleDocumentShortcut(_c, event)) {
      return KeyEventResult.handled;
    }
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      _c.selectAll();
      return KeyEventResult.handled;
    }
    if (_c.cellEditor.editing && _c.functionSuggestions.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _c.moveFunctionSuggestion(
          event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        _c.applyFunctionSuggestion();
        return KeyEventResult.handled;
      }
    }
    if (_handleSheetNav(event)) {
      return KeyEventResult.handled;
    }
    if (!_c.config.allowsMutation) {
      return KeyEventResult.ignored;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (_c.cellEditor.editing) {
        _c.commitCellEdit();
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        _c.redo();
      } else {
        _c.undo();
      }
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      if (_c.cellEditor.editing) {
        _c.commitCellEdit();
      }
      _c.redo();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _c.copyToClipboard();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      _c.cutToClipboard();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _c.pasteFromClipboard(
        mode: HardwareKeyboard.instance.isShiftPressed
            ? OfficePasteMode.keepTextOnly
            : OfficePasteMode.keepSource,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      if (_c.cellEditor.editing) {
        return KeyEventResult.ignored;
      }
      _c.beginCellEdit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_c.cellEditor.editing && _c.functionSuggestions.isNotEmpty) {
        _c.dismissFunctionSuggestions();
        return KeyEventResult.handled;
      }
      _c.cancelCellEdit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_c.cellEditor.editing) {
        if (_c.functionSuggestions.isNotEmpty) {
          _c.applyFunctionSuggestion();
          return KeyEventResult.handled;
        }
        _c.commitCellEdit();
        _c.moveSelection(0, 1);
      } else {
        _c.beginCellEdit();
      }
      return KeyEventResult.handled;
    }
    if (_c.cellEditor.editing) {
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _c.deleteEditBackward();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.delete) {
        _c.deleteEditForward();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _c.clearSelectedCells();
      return KeyEventResult.handled;
    }
    final String? ch = event.character;
    if (ch == null ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      _c.beginCellEdit(initial: ch, replace: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isSheetNavKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end;
  }

  /// [Focus.onKeyEvent] is a parent of [Shortcuts], so ignored keys bubble
  /// up and never reach the arrow bindings. Navigate here instead.
  bool _handleSheetNav(KeyEvent event, {bool startRepeat = true}) {
    if (!_c.config.allowsSelection) {
      return false;
    }
    final bool extend = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _moveSheet(
        extend ? -1 : 1,
        0,
        extend: false,
        leaveEdit: true,
        startRepeat: false,
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _moveSheet(
        0,
        _c.visibleRowPage,
        extend: extend,
        leaveEdit: true,
        startRepeat: startRepeat,
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _moveSheet(
        0,
        -_c.visibleRowPage,
        extend: extend,
        leaveEdit: true,
        startRepeat: startRepeat,
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.home && !_c.cellEditor.editing) {
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        _c.moveSelectionTo(const SmlCellRef(0, 0), extend: extend);
      } else {
        _c.moveSelectionTo(
          SmlCellRef(0, _c.selection.focus.row),
          extend: extend,
        );
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.end && !_c.cellEditor.editing) {
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        _c.moveSelectionTo(_c.lastUsedCell(), extend: extend);
      } else {
        _c.moveSelectionTo(
          SmlCellRef(
            _c.lastUsedColOnRow(_c.selection.focus.row),
            _c.selection.focus.row,
          ),
          extend: extend,
        );
      }
      return true;
    }
    final (int dc, int dr)? step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => (-1, 0),
      LogicalKeyboardKey.arrowRight => (1, 0),
      LogicalKeyboardKey.arrowUp => (0, -1),
      LogicalKeyboardKey.arrowDown => (0, 1),
      _ => null,
    };
    if (step == null) {
      return false;
    }
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      if (_c.cellEditor.editing) {
        _c.commitCellEdit();
      }
      final int navDc = _c.sheet.rightToLeft ? -step.$1 : step.$1;
      _c.jumpSelectionByOccupancy(navDc, step.$2, extend: extend);
      return true;
    }
    _moveSheet(
      step.$1,
      step.$2,
      extend: extend,
      leaveEdit: false,
      startRepeat: startRepeat,
    );
    return true;
  }

  void _moveSheet(
    int dc,
    int dr, {
    required bool extend,
    required bool leaveEdit,
    bool startRepeat = true,
  }) {
    if (_c.cellEditor.editing) {
      if (!leaveEdit && dr == 0) {
        _c.moveEditCaret(dc, extend: extend);
        return;
      }
      _c.commitCellEdit();
    }
    final int navDc = (!leaveEdit && _c.sheet.rightToLeft) ? -dc : dc;
    _c.moveSelection(navDc, dr, extend: extend);
    if (startRepeat && _navRepeat == null) {
      _navRepeat = Timer(const Duration(milliseconds: 380), () {
        _moveSheet(
          dc,
          dr,
          extend: extend,
          leaveEdit: leaveEdit,
          startRepeat: false,
        );
        _navRepeat = Timer.periodic(const Duration(milliseconds: 42), (_) {
          _moveSheet(
            dc,
            dr,
            extend: extend,
            leaveEdit: leaveEdit,
            startRepeat: false,
          );
        });
      });
    }
  }

  @override
  /// build API.
  Widget build(BuildContext context) {
    final OfficeSurfaceConfig config = widget.config ?? _c.config;
    final TextDirection direction = _c.sheet.rightToLeft
        ? TextDirection.rtl
        : config.textDirection;
    return Directionality(
      textDirection: direction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.toolbarBuilder != null)
            widget.toolbarBuilder!(context, _c),
          if (widget.findBarBuilder != null &&
              (config.showFindChrome || _c.findSession.active))
            widget.findBarBuilder!(context, _c),
          Expanded(
            child: Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: Shortcuts(
                shortcuts: <ShortcutActivator, Intent>{
                  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                      const OfficeFindIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyH, control: true):
                      const OfficeReplaceIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                      const OfficePrintIntent(),
                  const SingleActivator(LogicalKeyboardKey.f7):
                      const OfficeSpellCheckIntent(),
                  const SingleActivator(LogicalKeyboardKey.f3):
                      const OfficeFindNextIntent(),
                  const SingleActivator(LogicalKeyboardKey.f3, shift: true):
                      const OfficeFindNextIntent(forward: false),
                  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                      const OfficeUndoIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                      const OfficeRedoIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyY, meta: true):
                      const OfficeRedoIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                      const OfficeSelectAllIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                      const OfficeSelectAllIntent(),
                  const SingleActivator(LogicalKeyboardKey.arrowLeft):
                      const _SheetMoveIntent(-1, 0),
                  const SingleActivator(LogicalKeyboardKey.arrowRight):
                      const _SheetMoveIntent(1, 0),
                  const SingleActivator(LogicalKeyboardKey.arrowUp):
                      const _SheetMoveIntent(0, -1),
                  const SingleActivator(LogicalKeyboardKey.arrowDown):
                      const _SheetMoveIntent(0, 1),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowLeft,
                    shift: true,
                  ): const _SheetMoveIntent(
                    -1,
                    0,
                    extend: true,
                  ),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowRight,
                    shift: true,
                  ): const _SheetMoveIntent(
                    1,
                    0,
                    extend: true,
                  ),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    shift: true,
                  ): const _SheetMoveIntent(
                    0,
                    -1,
                    extend: true,
                  ),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    shift: true,
                  ): const _SheetMoveIntent(
                    0,
                    1,
                    extend: true,
                  ),
                  const SingleActivator(LogicalKeyboardKey.tab):
                      const _SheetMoveIntent(1, 0, leaveEdit: true),
                  const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                      const _SheetMoveIntent(-1, 0, leaveEdit: true),
                  const SingleActivator(LogicalKeyboardKey.backspace):
                      const _SheetClearIntent(),
                  const SingleActivator(LogicalKeyboardKey.delete):
                      const _SheetClearIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                      const OfficeCopyIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyX, control: true):
                      const OfficeCutIntent(),
                  const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                      const OfficePasteIntent(),
                  const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    control: true,
                    shift: true,
                  ): const OfficePasteIntent(
                    OfficePasteMode.keepTextOnly,
                  ),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    ..._documentActions(_c),
                    OfficeUndoIntent: CallbackAction<OfficeUndoIntent>(
                      onInvoke: (_) {
                        _c.undo();
                        return null;
                      },
                    ),
                    OfficeRedoIntent: CallbackAction<OfficeRedoIntent>(
                      onInvoke: (_) {
                        _c.redo();
                        return null;
                      },
                    ),
                    OfficeSelectAllIntent:
                        CallbackAction<OfficeSelectAllIntent>(
                          onInvoke: (_) {
                            _c.selectAll();
                            return null;
                          },
                        ),
                    _SheetMoveIntent: CallbackAction<_SheetMoveIntent>(
                      onInvoke: (_SheetMoveIntent i) {
                        _moveSheet(
                          i.dc,
                          i.dr,
                          extend: i.extend,
                          leaveEdit: i.leaveEdit,
                        );
                        return null;
                      },
                    ),
                    _SheetClearIntent: CallbackAction<_SheetClearIntent>(
                      onInvoke: (_) {
                        _c.clearSelectedCells();
                        return null;
                      },
                    ),
                    OfficeCopyIntent: CallbackAction<OfficeCopyIntent>(
                      onInvoke: (_) {
                        _c.copyToClipboard();
                        return null;
                      },
                    ),
                    OfficeCutIntent: CallbackAction<OfficeCutIntent>(
                      onInvoke: (_) {
                        _c.cutToClipboard();
                        return null;
                      },
                    ),
                    OfficePasteIntent: CallbackAction<OfficePasteIntent>(
                      onInvoke: (OfficePasteIntent i) {
                        _c.pasteFromClipboard(mode: i.mode);
                        return null;
                      },
                    ),
                  },
                  child: Semantics(
                    container: true,
                    label: _c.semanticsLabel,
                    value: _c.semanticsValue,
                    readOnly: !config.allowsMutation,
                    child: SheetGrid(
                      sheet: _c.sheet,
                      selection: _c.selection,
                      findHits: _c.findSession.hits,
                      activeFindIndex: _c.findSession.index,
                      formulaBar: _c.formulaBarText,
                      nameBox: _c.nameBoxText,
                      frozenRows: widget.frozenRows > 0
                          ? widget.frozenRows
                          : _c.sheet.freezeRows,
                      frozenCols: widget.frozenCols > 0
                          ? widget.frozenCols
                          : _c.sheet.freezeCols,
                      config: config,
                      hasFocus: _focus.hasFocus,
                      semanticsLabel: _c.semanticsLabel,
                      semanticsValue: _c.semanticsValue,
                      viewport: _c.viewport,
                      selectedDrawingIndex: _c.selectedDrawingIndex,
                      editing: _c.cellEditor.editing,
                      editText: _c.cellEditor.formulaBar,
                      editCaret: _c.cellEditor.caretIndex,
                      editBase: _c.cellEditor.selectionBase,
                      cellLabel: _c.cellDisplayText,
                      onSelectDrawing: _c.selectDrawing,
                      onActivateDrawing: _c.cycleSelectedDrawingKind,
                      onPlaceEditCaret: _c.placeEditCaret,
                      onCommitEdit: _c.commitCellEdit,
                      onPointRef: _c.pointEditRef,
                      functionSuggestions: _c.functionSuggestions,
                      functionSuggestionIndex: _c.functionSuggestionIndex,
                      functionTooltipArabic: identical(
                        config.strings,
                        OfficeStrings.arabic,
                      ),
                      onHighlightFunction: _c.highlightFunctionSuggestion,
                      onApplyFunction: (int index) {
                        _c.applyFunctionSuggestion(index);
                      },
                      onResizeColumn: _c.previewColumnWidth,
                      onResizeRow: _c.previewRowHeight,
                      onCommitResize: _c.commitResize,
                      onBeginDrawingTransform: _c.beginDrawingTransform,
                      onMoveDrawing: _c.previewDrawingMove,
                      onResizeDrawing: _c.previewDrawingResize,
                      onCommitDrawingTransform: _c.commitDrawingTransform,
                      onChanged: () {
                        _focus.requestFocus();
                        _c.refresh();
                      },
                      onActivate: _c.beginCellEdit,
                      onContextMenu: _showSheetContext,
                      onInsertRowAt: (int index) {
                        _c.insertSheetRows(after: false, index: index);
                      },
                      onInsertColAt: (int index) {
                        _c.insertSheetCols(after: false, index: index);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.statusBarBuilder != null)
            widget.statusBarBuilder!(context, _c),
        ],
      ),
    );
  }
}

/// Embeddable slide surface.
class QudsSlideEditor extends StatefulWidget {
  /// QudsSlideEditor API.
  const QudsSlideEditor({
    super.key,
    required this.controller,
    this.config,
    this.focusNode,
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.findBarBuilder,
    this.navigationBuilder,
    this.notesPaneBuilder,
  });

  /// controller API.
  final SlideEditorController controller;

  /// config API.
  final OfficeSurfaceConfig? config;

  /// focusNode API.
  final FocusNode? focusNode;

  /// Function API.
  final Widget Function(BuildContext context, SlideEditorController controller)?
  /// toolbarBuilder API.
  toolbarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SlideEditorController controller)?
  /// statusBarBuilder API.
  statusBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SlideEditorController controller)?
  /// findBarBuilder API.
  findBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SlideEditorController controller)?
  /// navigationBuilder API.
  navigationBuilder;

  /// Function API.
  final Widget Function(BuildContext context, SlideEditorController controller)?
  /// notesPaneBuilder API.
  notesPaneBuilder;

  @override
  /// createState API.
  State<QudsSlideEditor> createState() => _QudsSlideEditorState();
}

class _QudsSlideEditorState extends State<QudsSlideEditor>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focus;
  late final bool _ownsFocus;
  Ticker? _showTicker;

  /// zero API.
  Duration _lastTick = Duration.zero;
  var _wasPlayingMotion = false;
  OverlayEntry? _showOverlay;
  OverlayEntry? _contextMenu;

  /// controller API.
  SlideEditorController get _c => widget.controller;

  @override
  /// initState API.
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'QudsSlideEditor');
    _c.addListener(_rebuild);
    _c.motionFrame.addListener(_onMotionFrame);
    if (widget.config != null) {
      _c.syncConfig(widget.config!);
    }
    _syncShowTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncShowOverlay();
      }
    });
  }

  @override
  /// didUpdateWidget API.
  void didUpdateWidget(QudsSlideEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != null && !identical(widget.config, _c.config)) {
      _c.syncConfig(widget.config!);
    }
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
      _syncShowTicker();
      _syncShowOverlay();
      if (_c.isPlayingMotion && !_focus.hasFocus) {
        _focus.requestFocus();
      }
    }
  }

  void _onMotionFrame() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _showOverlay?.markNeedsBuild();
  }

  void _syncShowTicker() {
    final bool playing = _c.isPlayingMotion;
    if (playing) {
      _showTicker ??= createTicker(_onShowTick);
      if (!(_showTicker!.isActive)) {
        _lastTick = Duration.zero;
        _showTicker!.start();
      } else if (!_wasPlayingMotion) {
        _lastTick = Duration.zero;
      }
    } else if (_showTicker != null && _showTicker!.isActive) {
      _showTicker!.stop();
      _lastTick = Duration.zero;
    }
    _wasPlayingMotion = playing;
  }

  void _onShowTick(Duration elapsed) {
    var dt = elapsed.inMilliseconds - _lastTick.inMilliseconds;
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      dt = elapsed.inMilliseconds.clamp(0, 32);
    } else {
      _lastTick = elapsed;
    }
    if (dt <= 0) {
      return;
    }
    if (dt > 32) {
      dt = 32;
    }
    _c.tickShow(dt);
  }

  void _syncShowOverlay() {
    if (_c.isPresenting) {
      final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return;
      }
      if (_showOverlay == null) {
        _showOverlay = OverlayEntry(builder: _buildFullscreenShow);
        overlay.insert(_showOverlay!);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        _showOverlay!.markNeedsBuild();
      }
    } else if (_showOverlay != null) {
      _showOverlay!.remove();
      _showOverlay = null;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Widget _buildFullscreenShow(BuildContext context) {
    final OfficeSurfaceConfig config = widget.config ?? _c.config;
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: _onSlideKey,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: SlideStage(
            slide: _c.slideShow?.currentSlide ?? _c.slide,
            selected: null,
            viewport: _c.viewport,
            config: config,
            hasFocus: true,
            semanticsLabel: _c.semanticsLabel,
            semanticsValue: _c.semanticsValue,
            outgoingSlide: _c.slideShow?.outgoingSlide,
            transitionProgress: _c.slideShow?.transitionProgress ?? 1,
            playingTransition:
                _c.slideShow?.playingTransition ??
                (_c.slideShow?.currentSlide ?? _c.slide).transition,
            animSamples: _c.showSamples,
            presenting: true,
            onShowAdvance: _c.showNext,
          ),
        ),
      ),
    );
  }

  KeyEventResult _onSlideKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!_c.isPresenting && officeHandleDocumentShortcut(_c, event)) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      if (_c.isPresenting) {
        _c.endShow();
      } else {
        if (_c.isPreviewing) {
          _c.endShow();
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          _c.startShow(from: _c.activeSlideIndex);
        } else {
          _c.startShow(from: 0);
        }
      }
      return KeyEventResult.handled;
    }
    if (_c.isPreviewing && event.logicalKey == LogicalKeyboardKey.escape) {
      _c.endShow();
      return KeyEventResult.handled;
    }
    if (_c.isPresenting) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _c.endShow();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.pageUp ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _c.showPrevious();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.pageDown ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _c.showNext();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _dismissContextMenu() {
    OfficeContextMenu.dismiss(_contextMenu);
    _contextMenu = null;
  }

  void _showSlideContext(OfficeContextHit hit) {
    _dismissContextMenu();
    _contextMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: hit.globalPosition,
      actions: OfficeContextMenu.slide(hit: hit, controller: _c),
      onSelect: (String id) {
        _contextMenu = null;
        switch (id) {
          case 'cut':
            _c.cutToClipboard();
          case 'copy':
            _c.copyToClipboard();
          case 'paste':
            _c.pasteFromClipboard();
          case 'deleteShape':
            _c.deleteSelectedShape();
        }
      },
    );
  }

  @override
  /// dispose API.
  void dispose() {
    _dismissContextMenu();
    _showOverlay?.remove();
    _showOverlay = null;
    _showTicker?.dispose();
    _c.motionFrame.removeListener(_onMotionFrame);
    _c.removeListener(_rebuild);
    if (_ownsFocus) {
      _focus.dispose();
    }
    super.dispose();
  }

  @override
  /// build API.
  Widget build(BuildContext context) {
    final OfficeSurfaceConfig config = widget.config ?? _c.config;
    return Directionality(
      textDirection: config.textDirection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.toolbarBuilder != null)
            widget.toolbarBuilder!(context, _c),
          if (widget.findBarBuilder != null &&
              (config.showFindChrome || _c.findSession.active))
            widget.findBarBuilder!(context, _c),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.navigationBuilder != null &&
                    !_c.isPresenting &&
                    config.effectiveShowNavigationPane(
                      MediaQuery.sizeOf(context),
                    ))
                  SizedBox(
                    width: 220,
                    child: widget.navigationBuilder!(context, _c),
                  ),
                Expanded(
                  child: Focus(
                    autofocus: true,
                    focusNode: _focus,
                    onKeyEvent: (FocusNode node, KeyEvent event) {
                      final KeyEventResult show = _onSlideKey(node, event);
                      if (show != KeyEventResult.ignored) {
                        return show;
                      }
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.tab &&
                          _c.selectedTable != null &&
                          _c.config.allowsMutation) {
                        _c.moveSelectedTableCell(
                          forward: !HardwareKeyboard.instance.isShiftPressed,
                        );
                        return KeyEventResult.handled;
                      }
                      final bool? directionRtl = officeDirectionFromKeyEvent(
                        event,
                      );
                      if (directionRtl != null && _c.config.allowsMutation) {
                        _c.setSelectedTextDirection(rtl: directionRtl);
                        return KeyEventResult.handled;
                      }
                      final bool ctrl =
                          HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed;
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
                        _c.selectAll();
                        return KeyEventResult.handled;
                      }
                      if (!_c.config.allowsMutation) {
                        return KeyEventResult.ignored;
                      }
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          _c.redo();
                        } else {
                          _c.undo();
                        }
                        return KeyEventResult.handled;
                      }
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
                        _c.redo();
                        return KeyEventResult.handled;
                      }
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
                        _c.copyToClipboard();
                        return KeyEventResult.handled;
                      }
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyX) {
                        _c.cutToClipboard();
                        return KeyEventResult.handled;
                      }
                      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
                        _c.pasteFromClipboard(
                          mode: HardwareKeyboard.instance.isShiftPressed
                              ? OfficePasteMode.keepTextOnly
                              : OfficePasteMode.keepSource,
                        );
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        if (_c.editingText) {
                          _c.cancelTextEdit();
                          return KeyEventResult.handled;
                        }
                      }
                      if (event.logicalKey == LogicalKeyboardKey.f2) {
                        _c.beginTextEdit();
                        return KeyEventResult.handled;
                      }
                      if (_c.editingText) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                          event.logicalKey == LogicalKeyboardKey.arrowRight ||
                          event.logicalKey == LogicalKeyboardKey.arrowUp ||
                          event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (_c.selected == null) {
                          return KeyEventResult.ignored;
                        }
                        final int step =
                            HardwareKeyboard.instance.isShiftPressed
                            ? 12700
                            : 127000;
                        final int dx =
                            event.logicalKey == LogicalKeyboardKey.arrowLeft
                            ? -step
                            : (event.logicalKey == LogicalKeyboardKey.arrowRight
                                  ? step
                                  : 0);
                        final int dy =
                            event.logicalKey == LogicalKeyboardKey.arrowUp
                            ? -step
                            : (event.logicalKey == LogicalKeyboardKey.arrowDown
                                  ? step
                                  : 0);
                        _c.nudgeSelected(dx, dy);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                        _c.beginTextEdit();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.delete ||
                          event.logicalKey == LogicalKeyboardKey.backspace) {
                        _c.deleteSelectedShape();
                        return KeyEventResult.handled;
                      }
                      final String? ch = event.character;
                      if (ch != null &&
                          ch.length == 1 &&
                          ch.codeUnitAt(0) >= 32 &&
                          !ctrl) {
                        _c.beginTextEdit(initial: ch, replace: true);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        const SingleActivator(
                          LogicalKeyboardKey.keyF,
                          control: true,
                        ): const OfficeFindIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyH,
                          control: true,
                        ): const OfficeReplaceIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyP,
                          control: true,
                        ): const OfficePrintIntent(),
                        const SingleActivator(LogicalKeyboardKey.f7):
                            const OfficeSpellCheckIntent(),
                        const SingleActivator(LogicalKeyboardKey.f3):
                            const OfficeFindNextIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.f3,
                          shift: true,
                        ): const OfficeFindNextIntent(
                          forward: false,
                        ),
                        const SingleActivator(
                          LogicalKeyboardKey.keyZ,
                          control: true,
                        ): const OfficeUndoIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyY,
                          control: true,
                        ): const OfficeRedoIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyY,
                          meta: true,
                        ): const OfficeRedoIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyA,
                          control: true,
                        ): const OfficeSelectAllIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyA,
                          meta: true,
                        ): const OfficeSelectAllIntent(),
                        const SingleActivator(LogicalKeyboardKey.arrowLeft):
                            const _NudgeIntent(-127000, 0),
                        const SingleActivator(LogicalKeyboardKey.arrowRight):
                            const _NudgeIntent(127000, 0),
                        const SingleActivator(LogicalKeyboardKey.arrowUp):
                            const _NudgeIntent(0, -127000),
                        const SingleActivator(LogicalKeyboardKey.arrowDown):
                            const _NudgeIntent(0, 127000),
                        const SingleActivator(
                          LogicalKeyboardKey.arrowLeft,
                          shift: true,
                        ): const _NudgeIntent(
                          -12700,
                          0,
                        ),
                        const SingleActivator(
                          LogicalKeyboardKey.arrowRight,
                          shift: true,
                        ): const _NudgeIntent(
                          12700,
                          0,
                        ),
                        const SingleActivator(
                          LogicalKeyboardKey.arrowUp,
                          shift: true,
                        ): const _NudgeIntent(
                          0,
                          -12700,
                        ),
                        const SingleActivator(
                          LogicalKeyboardKey.arrowDown,
                          shift: true,
                        ): const _NudgeIntent(
                          0,
                          12700,
                        ),
                        const SingleActivator(
                          LogicalKeyboardKey.keyC,
                          control: true,
                        ): const OfficeCopyIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyX,
                          control: true,
                        ): const OfficeCutIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          control: true,
                        ): const OfficePasteIntent(),
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          control: true,
                          shift: true,
                        ): const OfficePasteIntent(
                          OfficePasteMode.keepTextOnly,
                        ),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ..._documentActions(_c),
                          OfficeUndoIntent: CallbackAction<OfficeUndoIntent>(
                            onInvoke: (_) {
                              _c.undo();
                              return null;
                            },
                          ),
                          OfficeRedoIntent: CallbackAction<OfficeRedoIntent>(
                            onInvoke: (_) {
                              _c.redo();
                              return null;
                            },
                          ),
                          OfficeSelectAllIntent:
                              CallbackAction<OfficeSelectAllIntent>(
                                onInvoke: (_) {
                                  _c.selectAll();
                                  return null;
                                },
                              ),
                          OfficeCopyIntent: CallbackAction<OfficeCopyIntent>(
                            onInvoke: (_) {
                              _c.copyToClipboard();
                              return null;
                            },
                          ),
                          OfficeCutIntent: CallbackAction<OfficeCutIntent>(
                            onInvoke: (_) {
                              _c.cutToClipboard();
                              return null;
                            },
                          ),
                          OfficePasteIntent: CallbackAction<OfficePasteIntent>(
                            onInvoke: (OfficePasteIntent i) {
                              _c.pasteFromClipboard(mode: i.mode);
                              return null;
                            },
                          ),
                          _NudgeIntent: CallbackAction<_NudgeIntent>(
                            onInvoke: (_NudgeIntent i) {
                              if (_c.editingText) {
                                final int delta = i.dx < 0 || i.dy < 0 ? -1 : 1;
                                _c.moveTextCaret(delta);
                                return null;
                              }
                              _c.nudgeSelected(i.dx, i.dy);
                              return null;
                            },
                          ),
                        },
                        child: Semantics(
                          container: true,
                          label: _c.semanticsLabel,
                          value: _c.semanticsValue,
                          readOnly: !config.allowsMutation,
                          child: SlideStage(
                            slide: _c.isPlayingMotion
                                ? (_c.slideShow?.currentSlide ?? _c.slide)
                                : _c.canvasSlide,
                            selected: _c.isPresenting ? null : _c.selected,
                            selectedShapes: _c.isPresenting
                                ? const <PmlShape>[]
                                : _c.selectedShapes,
                            viewport: _c.viewport,
                            config: config,
                            hasFocus: _focus.hasFocus,
                            semanticsLabel: _c.semanticsLabel,
                            semanticsValue: _c.semanticsValue,
                            editing: _c.editingText,
                            editCaret: _c.textEditor.caretIndex,
                            editBase: _c.textEditor.selectionBase,
                            outgoingSlide: _c.slideShow?.outgoingSlide,
                            transitionProgress:
                                _c.slideShow?.transitionProgress ?? 1,
                            playingTransition: _c.isPlayingMotion
                                ? (_c.slideShow?.playingTransition ??
                                      (_c.slideShow?.currentSlide ?? _c.slide)
                                          .transition)
                                : null,
                            animSamples: _c.isPlayingMotion
                                ? _c.showSamples
                                : null,
                            presenting: _c.isPlayingMotion,
                            onShowAdvance: _c.isPresenting
                                ? _c.showNext
                                : _c.endShow,
                            onSelect: _c.selectShape,
                            onSelectTableCell: _c.selectTableCell,
                            onTransforms: _c.applyTransforms,
                            selectedTableRow: _c.selectedTableRow,
                            selectedTableCol: _c.selectedTableCol,
                            onContextMenu: _showSlideContext,
                            onTransform: _c.applyTransform,
                            onActivate: _c.beginTextEdit,
                            onPlaceCaret: (int index, {bool extend = false}) {
                              _c.placeTextCaret(index, extend: extend);
                            },
                            onSelectWord: _c.selectTextWordAt,
                            onSelectParagraph: _c.selectTextParagraphAt,
                            onCommitEdit: _c.commitTextEdit,
                            onChanged: () {
                              _focus.requestFocus();
                              _c.refresh();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_c.isPresenting && widget.notesPaneBuilder != null)
            widget.notesPaneBuilder!(context, _c)
          else if (!_c.isPresenting && _c.speakerNotes.trim().isNotEmpty)
            SizedBox(
              height: 72,
              child: SpeakerNotesBar(
                label: config.strings.speakerNotes,
                notes: _c.speakerNotes,
                theme: config.theme,
                fontFamily: config.theme.fontFamily,
              ),
            ),
          if (widget.statusBarBuilder != null)
            widget.statusBarBuilder!(context, _c),
        ],
      ),
    );
  }
}

/// Opens any Office package and hosts the matching editor, with chrome slots.
class QudsOfficeHost extends StatefulWidget {
  /// QudsOfficeHost API.
  const QudsOfficeHost({
    super.key,
    this.bytes,
    this.password,
    this.kind,
    this.word,
    this.sheet,
    this.slide,
    this.config = const OfficeSurfaceConfig(),
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.findBarBuilder,
    this.navigationBuilder,
    this.onControllerReady,
  });

  /// bytes API.
  final Uint8List? bytes;

  /// password API.
  final String? password;

  /// kind API.
  final OpcPackageKind? kind;

  /// word API.
  final WordEditorController? word;

  /// sheet API.
  final SheetEditorController? sheet;

  /// slide API.
  final SlideEditorController? slide;

  /// config API.
  final OfficeSurfaceConfig config;

  /// Function API.
  final Widget Function(BuildContext context, OfficeController controller)?
  /// toolbarBuilder API.
  toolbarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, OfficeController controller)?
  /// statusBarBuilder API.
  statusBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, OfficeController controller)?
  /// findBarBuilder API.
  findBarBuilder;

  /// Function API.
  final Widget Function(BuildContext context, OfficeController controller)?
  /// navigationBuilder API.
  navigationBuilder;

  /// Function API.
  final void Function(OfficeController controller)? onControllerReady;

  @override
  /// createState API.
  State<QudsOfficeHost> createState() => _QudsOfficeHostState();
}

class _QudsOfficeHostState extends State<QudsOfficeHost> {
  late OfficeController _controller;
  var _owns = false;

  @override
  /// initState API.
  void initState() {
    super.initState();
    _controller = _create();
    widget.onControllerReady?.call(_controller);
  }

  OfficeController _create() {
    if (widget.word != null) {
      widget.word!.config = widget.config;
      return widget.word!;
    }
    if (widget.sheet != null) {
      widget.sheet!.config = widget.config;
      return widget.sheet!;
    }
    if (widget.slide != null) {
      widget.slide!.config = widget.config;
      return widget.slide!;
    }
    _owns = true;
    final Uint8List? bytes = widget.bytes;
    if (bytes != null) {
      final OpcPackage package = OfficeRepair.open(
        bytes,
        password: widget.password,
      );
      switch (package.kind) {
        case OpcPackageKind.word:
          return WordEditorController.fromBytes(
            bytes,
            password: widget.password,
            config: widget.config,
          );
        case OpcPackageKind.sheet:
          return SheetEditorController.fromBytes(
            bytes,
            password: widget.password,
            config: widget.config,
          );
        case OpcPackageKind.slide:
          return SlideEditorController.fromBytes(
            bytes,
            password: widget.password,
            config: widget.config,
          );
        case OpcPackageKind.unknown:
          break;
      }
    }
    return switch (widget.kind ?? OpcPackageKind.word) {
      OpcPackageKind.sheet => SheetEditorController(config: widget.config),
      OpcPackageKind.slide => SlideEditorController(config: widget.config),
      OpcPackageKind.word ||
      OpcPackageKind.unknown => WordEditorController(config: widget.config),
    };
  }

  @override
  /// dispose API.
  void dispose() {
    if (_owns) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  /// build API.
  Widget build(BuildContext context) {
    final OfficeController controller = _controller;
    return switch (controller) {
      WordEditorController c => QudsWordEditor(
        controller: c,
        config: widget.config,
        toolbarBuilder: widget.toolbarBuilder == null
            ? null
            : (BuildContext ctx, WordEditorController _) =>
                  widget.toolbarBuilder!(ctx, c),
        statusBarBuilder: widget.statusBarBuilder == null
            ? null
            : (BuildContext ctx, WordEditorController _) =>
                  widget.statusBarBuilder!(ctx, c),
        findBarBuilder: widget.findBarBuilder == null
            ? null
            : (BuildContext ctx, WordEditorController _) =>
                  widget.findBarBuilder!(ctx, c),
        navigationBuilder: widget.navigationBuilder == null
            ? null
            : (BuildContext ctx, WordEditorController _) =>
                  widget.navigationBuilder!(ctx, c),
      ),
      SheetEditorController c => QudsSheetEditor(
        controller: c,
        config: widget.config,
        toolbarBuilder: widget.toolbarBuilder == null
            ? null
            : (BuildContext ctx, SheetEditorController _) =>
                  widget.toolbarBuilder!(ctx, c),
        statusBarBuilder: widget.statusBarBuilder == null
            ? null
            : (BuildContext ctx, SheetEditorController _) =>
                  widget.statusBarBuilder!(ctx, c),
        findBarBuilder: widget.findBarBuilder == null
            ? null
            : (BuildContext ctx, SheetEditorController _) =>
                  widget.findBarBuilder!(ctx, c),
        navigationBuilder: widget.navigationBuilder == null
            ? null
            : (BuildContext ctx, SheetEditorController _) =>
                  widget.navigationBuilder!(ctx, c),
      ),
      SlideEditorController c => QudsSlideEditor(
        controller: c,
        config: widget.config,
        toolbarBuilder: widget.toolbarBuilder == null
            ? null
            : (BuildContext ctx, SlideEditorController _) =>
                  widget.toolbarBuilder!(ctx, c),
        statusBarBuilder: widget.statusBarBuilder == null
            ? null
            : (BuildContext ctx, SlideEditorController _) =>
                  widget.statusBarBuilder!(ctx, c),
        findBarBuilder: widget.findBarBuilder == null
            ? null
            : (BuildContext ctx, SlideEditorController _) =>
                  widget.findBarBuilder!(ctx, c),
        navigationBuilder: widget.navigationBuilder == null
            ? null
            : (BuildContext ctx, SlideEditorController _) =>
                  widget.navigationBuilder!(ctx, c),
      ),
      OfficeController() => const SizedBox.shrink(),
    };
  }
}

class _MoveCaretIntent extends Intent {
  /// extend API.
  const _MoveCaretIntent(this.delta, {this.extend = false});

  /// delta API.
  final int delta;

  /// extend API.
  final bool extend;
}

class _MoveParagraphIntent extends Intent {
  /// extend API.
  const _MoveParagraphIntent(this.delta, {this.extend = false});

  /// delta API.
  final int delta;

  /// extend API.
  final bool extend;
}

class _DeleteIntent extends Intent {
  const _DeleteIntent({required this.backward});

  /// backward API.
  final bool backward;
}

class _BreakIntent extends Intent {
  const _BreakIntent();
}

class _SheetMoveIntent extends Intent {
  const _SheetMoveIntent(
    this.dc,
    this.dr, {
    this.extend = false,
    this.leaveEdit = false,
  });

  /// dc API.
  final int dc;

  /// dr API.
  final int dr;

  /// extend API.
  final bool extend;

  /// leaveEdit API.
  final bool leaveEdit;
}

class _SheetClearIntent extends Intent {
  const _SheetClearIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.dx, this.dy);

  /// dx API.
  final int dx;

  /// dy API.
  final int dy;
}

/// Speaker-notes strip painted by a RenderBox (not a TextField / ListView).
class SpeakerNotesBar extends LeafRenderObjectWidget {
  /// SpeakerNotesBar API.
  const SpeakerNotesBar({
    super.key,
    required this.label,
    required this.notes,
    required this.theme,
    this.fontFamily,
  });

  /// label API.
  final String label;

  /// notes API.
  final String notes;

  /// theme API.
  final OfficeTheme theme;

  /// fontFamily API.
  final String? fontFamily;

  @override
  /// createRenderObject API.
  RenderObject createRenderObject(BuildContext context) {
    return RenderSpeakerNotesBar(
      label: label,
      notes: notes,
      theme: theme,
      fontFamily: fontFamily,
    );
  }

  @override
  /// updateRenderObject API.
  void updateRenderObject(
    BuildContext context,
    RenderSpeakerNotesBar renderObject,
  ) {
    renderObject
      ..label = label
      ..notes = notes
      ..theme = theme
      ..fontFamily = fontFamily;
  }
}

/// Class RenderSpeakerNotesBar.
class RenderSpeakerNotesBar extends RenderBox {
  /// RenderSpeakerNotesBar API.
  RenderSpeakerNotesBar({
    required this._label,
    required this._notes,
    required this._theme,
    this._fontFamily,
  });

  String _label;
  String _notes;
  OfficeTheme _theme;
  String? _fontFamily;

  /// label API.
  set label(String value) {
    if (_label == value) {
      return;
    }
    _label = value;
    markNeedsPaint();
  }

  /// notes API.
  set notes(String value) {
    if (_notes == value) {
      return;
    }
    _notes = value;
    markNeedsPaint();
  }

  /// theme API.
  set theme(OfficeTheme value) {
    if (_theme == value) {
      return;
    }
    _theme = value;
    markNeedsPaint();
  }

  /// fontFamily API.
  set fontFamily(String? value) {
    if (_fontFamily == value) {
      return;
    }
    _fontFamily = value;
    markNeedsPaint();
  }

  @override
  /// performLayout API.
  void performLayout() {
    size = constraints.constrain(Size(constraints.maxWidth, 72));
  }

  @override
  /// paint API.
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.drawRect(offset & size, Paint()..color = _theme.chromeFill);
    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, size.width, 1),
      Paint()..color = _theme.gridLine,
    );
    final ui.ParagraphBuilder head = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 10, fontFamily: _fontFamily),
    );
    head.pushStyle(ui.TextStyle(color: _theme.headerText, fontSize: 10));
    head.addText(_label);
    final ui.Paragraph headP = head.build()
      ..layout(ui.ParagraphConstraints(width: size.width - 16));
    canvas.drawParagraph(headP, offset + const Offset(8, 6));
    final ui.ParagraphBuilder body = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 12, fontFamily: _fontFamily, maxLines: 2),
    );
    body.pushStyle(ui.TextStyle(color: _theme.chromeText, fontSize: 12));
    body.addText(_notes);
    final ui.Paragraph bodyP = body.build()
      ..layout(ui.ParagraphConstraints(width: size.width - 16));
    canvas.drawParagraph(bodyP, offset + const Offset(8, 24));
  }
}

Map<Type, Action<Intent>> _documentActions(OfficeController controller) {
  return <Type, Action<Intent>>{
    OfficeFindIntent: CallbackAction<OfficeFindIntent>(
      onInvoke: (_) {
        controller.requestFind();
        return null;
      },
    ),
    OfficeReplaceIntent: CallbackAction<OfficeReplaceIntent>(
      onInvoke: (_) {
        controller.requestReplace();
        return null;
      },
    ),
    OfficePrintIntent: CallbackAction<OfficePrintIntent>(
      onInvoke: (_) {
        controller.requestPrint();
        return null;
      },
    ),
    OfficeSpellCheckIntent: CallbackAction<OfficeSpellCheckIntent>(
      onInvoke: (_) {
        controller.requestSpellCheck();
        return null;
      },
    ),
    OfficeFindNextIntent: CallbackAction<OfficeFindNextIntent>(
      onInvoke: (OfficeFindNextIntent i) {
        if (i.forward) {
          controller.findNext();
        } else {
          controller.findPrevious();
        }
        return null;
      },
    ),
  };
}
