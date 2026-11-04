import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../editor_pdf/pdf_text_selection.dart';
import 'office_controller.dart';
import 'office_theme.dart';
import 'pdf_controller.dart';

/// Enum OfficeContextKind.
enum OfficeContextKind {
  document,
  table,
  tableHandle,
  picture,
  comment,
  hyperlink,
  equation,
  sheetCell,
  sheetRowHeader,
  sheetColHeader,
  slideShape,
  slideCanvas,
}

/// Class OfficeContextHit.
class OfficeContextHit {
  /// OfficeContextHit API.
  const OfficeContextHit({
    required this.kind,
    required this.globalPosition,
    this.table,
    this.tableRow,
    this.tableCol,
    this.visual,
    this.commentId,
    this.link,
    this.equation,
    this.cell,
    this.shape,
  });

  /// kind API.
  final OfficeContextKind kind;

  /// globalPosition API.
  final Offset globalPosition;

  /// table API.
  final WmlTable? table;

  /// tableRow API.
  final int? tableRow;

  /// tableCol API.
  final int? tableCol;

  /// visual API.
  final OfficeVisual? visual;

  /// commentId API.
  final int? commentId;

  /// link API.
  final WmlHyperlink? link;

  /// equation API.
  final WmlEquation? equation;

  /// cell API.
  final SmlCellRef? cell;

  /// shape API.
  final PmlShape? shape;
}

/// Class OfficeContextAction.
class OfficeContextAction {
  /// OfficeContextAction API.
  const OfficeContextAction({
    required this.id,
    required this.label,
    this.icon,
    this.shortcut,
    this.enabled = true,
    this.danger = false,
    this.separatorBefore = false,
    this.isCaption = false,
  });

  /// Non-interactive section label.
  const OfficeContextAction.caption(this.label, {this.separatorBefore = false})
    : id = '',
      icon = null,
      shortcut = null,
      enabled = false,
      danger = false,
      isCaption = true;

  /// id API.
  final String id;

  /// label API.
  final String label;

  /// icon API.
  final IconData? icon;

  /// shortcut API.
  final String? shortcut;

  /// enabled API.
  final bool enabled;

  /// danger API.
  final bool danger;

  /// separatorBefore API.
  final bool separatorBefore;

  /// Section label, not a command.
  final bool isCaption;
}

/// Right-click target on a PDF page.
class PdfContextHit {
  /// PdfContextHit API.
  const PdfContextHit({
    required this.globalPosition,
    required this.pageIndex,
    this.link,
    this.annot,
  });

  /// globalPosition API.
  final Offset globalPosition;

  /// pageIndex API.
  final int pageIndex;

  /// Internal or URI hotspot under the pointer.
  final PdfLinkAction? link;

  /// Markup annotation under the pointer, never a link.
  final PdfAnnot? annot;
}

/// Overlay context menu with its own [Material] surface (Column, not a list).
abstract final class OfficeContextMenu {
  /// dismiss API.
  static void dismiss(OverlayEntry? entry) {
    if (entry == null) {
      return;
    }
    try {
      // `mounted` stays true until the next frame, so a second dismiss (the
      // menu already closed itself) must not call remove() again.
      entry.remove();
    } on Object {
      return;
    }
  }

  static OverlayEntry? show({
    required BuildContext context,
    required Offset globalPosition,
    required List<OfficeContextAction> actions,
    required ValueChanged<String> onSelect,
    String? filterHint,
  }) {
    if (actions.isEmpty) {
      return null;
    }
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return null;
    }
    ThemeData theme = ThemeData.light();
    try {
      theme = Theme.of(context);
    } on Object {
      theme = ThemeData.light();
    }
    final TextDirection direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    var closed = false;
    late final OverlayEntry entry;
    void close() {
      if (closed) {
        return;
      }
      closed = true;
      OfficeContextMenu.dismiss(entry);
    }

    entry = OverlayEntry(
      builder: (BuildContext _) {
        return _OfficeContextOverlay(
          globalPosition: globalPosition,
          actions: actions,
          theme: theme,
          direction: direction,
          filterHint: filterHint,
          onDismiss: close,
          onSelect: (String id) {
            close();
            onSelect(id);
          },
        );
      },
    );
    overlay.insert(entry);
    return entry;
  }

  /// word API.
  static List<OfficeContextAction> word({
    required OfficeContextHit hit,
    required WordEditorController controller,
  }) {
    final OfficeStrings strings = controller.config.strings;
    final bool mutate = controller.config.allowsMutation;
    final List<OfficeContextAction> items = <OfficeContextAction>[
      OfficeContextAction(
        id: 'cut',
        label: strings.cut,
        icon: Icons.content_cut,
        shortcut: 'Ctrl+X',
        enabled: mutate && controller.canCut,
      ),
      OfficeContextAction(
        id: 'copy',
        label: strings.copy,
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        enabled: controller.canCopy,
      ),
      OfficeContextAction(
        id: 'paste',
        label: strings.paste,
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: mutate && controller.canPaste,
      ),
      OfficeContextAction(
        id: 'selectAll',
        label: strings.selectAll,
        icon: Icons.select_all,
        shortcut: 'Ctrl+A',
        enabled: controller.config.allowsSelection,
        separatorBefore: true,
      ),
    ];
    if ((hit.kind == OfficeContextKind.table ||
            hit.kind == OfficeContextKind.tableHandle) &&
        hit.table != null) {
      final bool canDeleteRow = hit.table!.rows.length > 1;
      final bool canDeleteCol = WordTable.columnCount(hit.table!) > 1;
      items.addAll(<OfficeContextAction>[
        OfficeContextAction(
          id: 'insertRowAbove',
          label: strings.insertRowAbove,
          icon: Icons.keyboard_arrow_up,
          enabled: mutate,
          separatorBefore: true,
        ),
        OfficeContextAction(
          id: 'insertRowBelow',
          label: strings.insertRowBelow,
          icon: Icons.keyboard_arrow_down,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'insertColLeft',
          label: strings.insertColumnLeft,
          icon: Icons.keyboard_arrow_left,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'insertColRight',
          label: strings.insertColumnRight,
          icon: Icons.keyboard_arrow_right,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'mergeTableCells',
          label: strings.mergeTableCells,
          icon: Icons.call_merge,
          enabled: mutate && controller.canMergeTableCells,
          separatorBefore: true,
        ),
        OfficeContextAction(
          id: 'unmergeTableCells',
          label: strings.unmergeTableCells,
          icon: Icons.call_split,
          enabled: mutate && controller.canUnmergeTableCells,
        ),
        OfficeContextAction(
          id: 'autoFitContents',
          label: strings.autoFitContents,
          icon: Icons.fit_screen,
          enabled: mutate,
          separatorBefore: true,
        ),
        OfficeContextAction(
          id: 'autoFitWindow',
          label: strings.autoFitWindow,
          icon: Icons.width_full,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'autoFitFixed',
          label: strings.autoFitFixed,
          icon: Icons.view_week_outlined,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'deleteRow',
          label: strings.deleteRow,
          icon: Icons.table_rows_outlined,
          enabled: mutate && canDeleteRow,
          danger: true,
          separatorBefore: true,
        ),
        OfficeContextAction(
          id: 'deleteCol',
          label: strings.deleteColumn,
          icon: Icons.view_column_outlined,
          enabled: mutate && canDeleteCol,
          danger: true,
        ),
        if (hit.kind == OfficeContextKind.tableHandle)
          OfficeContextAction(
            id: 'deleteTable',
            label: strings.deleteTable,
            icon: Icons.delete_outline,
            enabled: mutate,
            danger: true,
          ),
      ]);
    }
    if (hit.kind == OfficeContextKind.picture) {
      items.add(
        OfficeContextAction(
          id: 'cropPicture',
          label: strings.cropMode,
          icon: Icons.crop,
          enabled: mutate,
          separatorBefore: true,
        ),
      );
    }
    if (hit.link != null) {
      items.add(
        OfficeContextAction(
          id: 'followLink',
          label: strings.followLink,
          icon: Icons.open_in_new,
          separatorBefore: true,
        ),
      );
    }
    if (hit.kind == OfficeContextKind.comment && hit.commentId != null) {
      final WmlComment? comment = WordComment.byId(
        controller.document,
        hit.commentId!,
      );
      final bool resolved = comment?.resolved ?? false;
      items.addAll(<OfficeContextAction>[
        OfficeContextAction(
          id: 'replyComment',
          label: strings.replyComment,
          icon: Icons.reply,
          enabled: mutate,
          separatorBefore: true,
        ),
        OfficeContextAction(
          id: resolved ? 'reopenComment' : 'resolveComment',
          label: resolved ? strings.reopenComment : strings.resolveComment,
          icon: resolved ? Icons.replay : Icons.task_alt,
          enabled: mutate,
        ),
        OfficeContextAction(
          id: 'deleteComment',
          label: strings.deleteComment,
          icon: Icons.delete_outline,
          enabled: mutate,
          danger: true,
        ),
      ]);
    } else if (hit.kind == OfficeContextKind.document ||
        hit.kind == OfficeContextKind.table) {
      items.add(
        OfficeContextAction(
          id: 'insertComment',
          label: strings.insertComment,
          icon: Icons.add_comment_outlined,
          enabled: mutate && !controller.isEditingComment,
          separatorBefore: true,
        ),
      );
    }
    return items;
  }

  /// Viewer and editor menu for a PDF page.
  static List<OfficeContextAction> pdf({
    required PdfViewerController controller,
    required PdfContextHit hit,
  }) {
    final OfficeStrings strings = controller.config.strings;
    final bool mutate =
        controller.config.allowsMutation && controller is PdfEditorController;
    final int page = hit.pageIndex;
    final bool hasText =
        page >= 0 &&
        page < controller.lists.length &&
        controller.lists[page].runs.isNotEmpty;
    final PdfTextSelection? selection = controller.selection;
    final bool canCopy = selection != null && !selection.isCollapsed;
    final PdfLinkAction? link = hit.link;
    final bool external = link?.uri != null && link!.uri!.isNotEmpty;
    final List<OfficeContextAction> items = <OfficeContextAction>[
      OfficeContextAction.caption(strings.pdfMenuSelection),
      OfficeContextAction(
        id: 'copy',
        label: strings.copy,
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        enabled: canCopy,
      ),
      OfficeContextAction(
        id: 'selectAll',
        label: strings.selectAll,
        icon: Icons.select_all,
        shortcut: 'Ctrl+A',
        enabled: controller.lists.any(
          (PdfDisplayList list) => list.runs.isNotEmpty,
        ),
      ),
      OfficeContextAction(
        id: 'selectPage',
        label: strings.selectPage,
        icon: Icons.crop_free,
        shortcut: 'Ctrl+Shift+A',
        enabled: hasText,
      ),
      if (link != null)
        OfficeContextAction(
          id: 'followLink',
          label: external ? strings.followLink : strings.goToDestination,
          icon: external ? Icons.open_in_new : Icons.shortcut,
        ),
      OfficeContextAction.caption(strings.pdfMenuView, separatorBefore: true),
      OfficeContextAction(
        id: 'zoomIn',
        label: strings.zoomIn,
        icon: Icons.zoom_in,
        shortcut: 'Ctrl++',
      ),
      OfficeContextAction(
        id: 'zoomOut',
        label: strings.zoomOut,
        icon: Icons.zoom_out,
        shortcut: 'Ctrl+-',
      ),
      OfficeContextAction(
        id: 'actualSize',
        label: strings.actualSize,
        icon: Icons.one_x_mobiledata,
        shortcut: 'Ctrl+0',
      ),
      OfficeContextAction(
        id: 'fitWidth',
        label: strings.fitWidth,
        icon: Icons.fit_screen,
      ),
      OfficeContextAction(
        id: 'fitPage',
        label: strings.fitPage,
        icon: Icons.fit_screen_outlined,
      ),
      OfficeContextAction.caption(strings.pdfMenuPage, separatorBefore: true),
      OfficeContextAction(
        id: 'previousPage',
        label: strings.previousPage,
        icon: Icons.keyboard_arrow_up,
        enabled: page > 0,
      ),
      OfficeContextAction(
        id: 'nextPage',
        label: strings.nextPage,
        icon: Icons.keyboard_arrow_down,
        enabled: page + 1 < controller.pageCount,
      ),
    ];
    if (!mutate) {
      return items;
    }
    final PdfEditorController editor = controller;
    final bool locked =
        editor.file?.permissions != null &&
        !editor.file!.permissions!.canAnnotate;
    final PdfAnnot? annot = hit.annot;
    items.addAll(<OfficeContextAction>[
      OfficeContextAction.caption(strings.pdfMenuMarkup, separatorBefore: true),
      OfficeContextAction(
        id: 'highlight',
        label: strings.highlight,
        icon: Icons.highlight,
        enabled: canCopy && !locked,
      ),
      OfficeContextAction(
        id: 'strikethrough',
        label: strings.strikethrough,
        icon: Icons.strikethrough_s,
        enabled: canCopy && !locked,
      ),
      OfficeContextAction(
        id: 'underline',
        label: strings.underline,
        icon: Icons.format_underlined,
        enabled: canCopy && !locked,
      ),
      if (annot != null)
        OfficeContextAction(
          id: 'deleteAnnot',
          label: strings.deleteAnnotation,
          icon: Icons.delete_outline,
          enabled: !locked,
          danger: true,
        ),
      OfficeContextAction(
        id: 'rotatePage',
        label: strings.rotatePage,
        icon: Icons.rotate_right,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'rotatePageLeft',
        label: strings.rotatePageLeft,
        icon: Icons.rotate_left,
      ),
      OfficeContextAction(
        id: 'insertPage',
        label: strings.insertPage,
        icon: Icons.note_add_outlined,
      ),
      OfficeContextAction(
        id: 'deletePage',
        label: strings.deletePage,
        icon: Icons.delete_outline,
        enabled: controller.pageCount > 1,
        danger: true,
      ),
      OfficeContextAction(
        id: 'undo',
        label: strings.undo,
        icon: Icons.undo,
        shortcut: 'Ctrl+Z',
        enabled: editor.canUndo,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'redo',
        label: strings.redo,
        icon: Icons.redo,
        shortcut: 'Ctrl+Y',
        enabled: editor.canRedo,
      ),
    ]);
    return items;
  }

  /// sheet API.
  static List<OfficeContextAction> sheet({
    required OfficeContextHit hit,
    required SheetEditorController controller,
  }) {
    final OfficeStrings strings = controller.config.strings;
    final bool mutate = controller.config.allowsMutation;
    return <OfficeContextAction>[
      OfficeContextAction(
        id: 'cut',
        label: strings.cut,
        icon: Icons.content_cut,
        shortcut: 'Ctrl+X',
        enabled: mutate && controller.canCut,
      ),
      OfficeContextAction(
        id: 'copy',
        label: strings.copy,
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        enabled: controller.canCopy,
      ),
      OfficeContextAction(
        id: 'paste',
        label: strings.paste,
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: mutate && controller.canPaste,
      ),
      OfficeContextAction(
        id: 'insertSheetRow',
        label: strings.insertSheetRow,
        icon: Icons.table_rows,
        enabled: mutate,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'insertSheetCol',
        label: strings.insertSheetColumn,
        icon: Icons.view_column,
        enabled: mutate,
      ),
      OfficeContextAction(
        id: 'deleteSheetRow',
        label: strings.deleteSheetRow,
        icon: Icons.table_rows_outlined,
        enabled: mutate,
        danger: true,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'deleteSheetCol',
        label: strings.deleteSheetColumn,
        icon: Icons.view_column_outlined,
        enabled: mutate,
        danger: true,
      ),
      OfficeContextAction(
        id: 'clearCells',
        label: strings.clearCells,
        icon: Icons.backspace_outlined,
        enabled: mutate,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'mergeAndCenter',
        label: strings.mergeAndCenter,
        icon: Icons.call_merge,
        enabled: mutate && controller.canMergeAndCenter,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'unmergeCells',
        label: strings.unmergeCells,
        icon: Icons.call_split,
        enabled: mutate && controller.canUnmergeCells,
      ),
    ];
  }

  /// slide API.
  static List<OfficeContextAction> slide({
    required OfficeContextHit hit,
    required SlideEditorController controller,
  }) {
    final OfficeStrings strings = controller.config.strings;
    final bool mutate = controller.config.allowsMutation;
    return <OfficeContextAction>[
      OfficeContextAction(
        id: 'cut',
        label: strings.cut,
        icon: Icons.content_cut,
        shortcut: 'Ctrl+X',
        enabled: mutate && controller.canCut,
      ),
      OfficeContextAction(
        id: 'copy',
        label: strings.copy,
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        enabled: controller.canCopy,
      ),
      OfficeContextAction(
        id: 'paste',
        label: strings.paste,
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: mutate && controller.canPaste,
      ),
      if (hit.kind == OfficeContextKind.slideShape)
        OfficeContextAction(
          id: 'deleteShape',
          label: strings.deleteShape,
          icon: Icons.delete_outline,
          enabled: mutate,
          danger: true,
          separatorBefore: true,
        ),
    ];
  }

  /// slideSorter API.
  static List<OfficeContextAction> slideSorter({
    required SlideEditorController controller,
    required int index,
  }) {
    final OfficeStrings strings = controller.config.strings;
    final bool mutate = controller.config.allowsMutation;
    final bool hidden =
        index >= 0 &&
        index < controller.presentation.slides.length &&
        controller.presentation.slides[index].hidden;
    return <OfficeContextAction>[
      OfficeContextAction(
        id: 'copySlide',
        label: strings.copySlide,
        icon: Icons.copy_outlined,
        enabled: index >= 0 && index < controller.presentation.slides.length,
      ),
      OfficeContextAction(
        id: 'pasteSlide',
        label: strings.pasteSlide,
        icon: Icons.paste_outlined,
        enabled: mutate && controller.canPasteSlide,
      ),
      OfficeContextAction(
        id: 'duplicateSlide',
        label: strings.duplicateSlide,
        icon: Icons.control_point_duplicate_outlined,
        enabled: mutate,
      ),
      OfficeContextAction(
        id: hidden ? 'showSlide' : 'hideSlide',
        label: hidden ? strings.showSlide : strings.hideSlide,
        icon: hidden
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        enabled: mutate,
        separatorBefore: true,
      ),
    ];
  }
}

class _MenuPalette {
  const _MenuPalette({
    required this.surface,
    required this.border,
    required this.hover,
    required this.text,
    required this.muted,
    required this.danger,
    required this.icon,
    required this.divider,
    required this.disabled,
  });

  factory _MenuPalette.of(ThemeData theme) {
    final bool dark = theme.brightness == Brightness.dark;
    if (dark) {
      return const _MenuPalette(
        surface: Color(0xFF2B2B2B),
        border: Color(0xFF3D3D3D),
        hover: Color(0xFF3A3A3A),
        text: Color(0xFFF3F3F3),
        muted: Color(0xFFB0B0B0),
        danger: Color(0xFFFF8A80),
        icon: Color(0xFFD0D0D0),
        divider: Color(0xFF444444),
        disabled: Color(0xFF7A7A7A),
      );
    }
    return const _MenuPalette(
      surface: Color(0xFFFFFFFF),
      border: Color(0xFFE1DFDD),
      hover: Color(0xFFE8F0FE),
      text: Color(0xFF242424),
      muted: Color(0xFF605E5C),
      danger: Color(0xFFC4314B),
      icon: Color(0xFF323130),
      divider: Color(0xFFE1DFDD),
      disabled: Color(0xFFA19F9D),
    );
  }

  /// surface API.
  final Color surface;

  /// border API.
  final Color border;

  /// hover API.
  final Color hover;

  /// text API.
  final Color text;

  /// muted API.
  final Color muted;

  /// danger API.
  final Color danger;

  /// icon API.
  final Color icon;

  /// divider API.
  final Color divider;

  /// disabled API.
  final Color disabled;
}

class _OfficeContextOverlay extends StatefulWidget {
  const _OfficeContextOverlay({
    required this.globalPosition,
    required this.actions,
    required this.theme,
    required this.direction,
    required this.onDismiss,
    required this.onSelect,
    this.filterHint,
  });

  /// globalPosition API.
  final Offset globalPosition;

  /// actions API.
  final List<OfficeContextAction> actions;

  /// theme API.
  final ThemeData theme;

  /// direction API.
  final TextDirection direction;

  /// Shown while the query is empty. Typing filters when this is set or the
  /// menu has more than eight commands.
  final String? filterHint;

  /// onDismiss API.
  final VoidCallback onDismiss;

  /// onSelect API.
  final ValueChanged<String> onSelect;

  @override
  State<_OfficeContextOverlay> createState() => _OfficeContextOverlayState();
}

class _MenuRow {
  const _MenuRow(this.action, this.top, this.height);

  final OfficeContextAction action;
  final double top;
  final double height;
}

class _OfficeContextOverlayState extends State<_OfficeContextOverlay> {
  static const double _width = 292;
  static const double _filterHeight = 34;

  final FocusNode _focus = FocusNode();
  String _query = '';
  double _scroll = 0;
  int _selected = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _filtering {
    if (widget.filterHint != null) {
      return true;
    }
    var commands = 0;
    for (final OfficeContextAction a in widget.actions) {
      if (!a.isCaption) {
        commands++;
      }
    }
    return commands > 8;
  }

  List<OfficeContextAction> get _visible {
    if (_query.isEmpty) {
      return widget.actions;
    }
    final String q = _query.toLowerCase();
    return <OfficeContextAction>[
      for (final OfficeContextAction a in widget.actions)
        if (!a.isCaption && a.label.toLowerCase().contains(q))
          OfficeContextAction(
            id: a.id,
            label: a.label,
            icon: a.icon,
            shortcut: a.shortcut,
            enabled: a.enabled,
            danger: a.danger,
          ),
    ];
  }

  List<_MenuRow> _rows(List<OfficeContextAction> items) {
    final List<_MenuRow> out = <_MenuRow>[];
    var y = 0.0;
    for (final OfficeContextAction a in items) {
      if (a.separatorBefore) {
        y += 9;
      }
      final double h = a.isCaption ? 22 : 36;
      out.add(_MenuRow(a, y, h));
      y += h;
    }
    return out;
  }

  int _selectableCount(List<OfficeContextAction> items) {
    var n = 0;
    for (final OfficeContextAction a in items) {
      if (!a.isCaption && a.enabled) {
        n++;
      }
    }
    return n;
  }

  OfficeContextAction? _selectedAction(List<OfficeContextAction> items) {
    var i = 0;
    for (final OfficeContextAction a in items) {
      if (a.isCaption || !a.enabled) {
        continue;
      }
      if (i == _selected) {
        return a;
      }
      i++;
    }
    return null;
  }

  void _nudge(double dy) {
    final double maxScroll = _maxScroll(MediaQuery.sizeOf(context));
    setState(() {
      _scroll = (_scroll + dy).clamp(0, maxScroll);
    });
  }

  void _reveal(Size screen) {
    final List<OfficeContextAction> items = _visible;
    final List<_MenuRow> rows = _rows(items);
    var i = 0;
    _MenuRow? row;
    for (var r = 0; r < rows.length; r++) {
      final OfficeContextAction a = rows[r].action;
      if (a.isCaption || !a.enabled) {
        continue;
      }
      if (i == _selected) {
        row = rows[r];
        break;
      }
      i++;
    }
    if (row == null) {
      return;
    }
    final double view = _viewHeight(screen, _extent(items));
    if (row.top < _scroll) {
      _scroll = row.top;
    } else if (row.top + row.height > _scroll + view) {
      _scroll = row.top + row.height - view;
    }
    _scroll = _scroll.clamp(0, _maxScroll(screen));
  }

  double _extent(List<OfficeContextAction> items) {
    var h = 0.0;
    for (final OfficeContextAction a in items) {
      h += (a.separatorBefore ? 9 : 0) + (a.isCaption ? 22 : 36);
    }
    return h;
  }

  double _viewHeight(Size screen, double extent) {
    final double chrome = 12 + (_filtering ? _filterHeight : 0);
    final double maxHeight = (screen.height - 16).clamp(80.0, screen.height);
    final double natural = chrome + extent;
    final double menu = natural > maxHeight ? maxHeight : natural;
    return menu - chrome;
  }

  double _maxScroll(Size screen) {
    final double extent = _extent(_visible);
    return math.max(0, extent - _viewHeight(screen, extent));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_filtering || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_query.isNotEmpty) {
        setState(() {
          _query = '';
          _scroll = 0;
          _selected = 0;
        });
      } else {
        widget.onDismiss();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_query.isNotEmpty) {
        setState(() {
          _query = _query.substring(0, _query.length - 1);
          _scroll = 0;
          _selected = 0;
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final OfficeContextAction? action = _selectedAction(_visible);
      if (action != null) {
        widget.onSelect(action.id);
      }
      return KeyEventResult.handled;
    }
    final int count = _selectableCount(_visible);
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (count > 0) {
        setState(() {
          _selected = key == LogicalKeyboardKey.arrowDown
              ? math.min(count - 1, _selected + 1)
              : math.max(0, _selected - 1);
          _reveal(MediaQuery.sizeOf(context));
        });
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final String? typed = event.character;
    final String ch = (typed != null && typed.isNotEmpty)
        ? typed
        : (key.keyLabel.length == 1 ? key.keyLabel : '');
    if (ch.isEmpty || ch.codeUnitAt(0) < 0x20) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _query += ch;
      _scroll = 0;
      _selected = 0;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final _MenuPalette palette = _MenuPalette.of(widget.theme);
    final Size screen = MediaQuery.sizeOf(context);
    final bool filtering = _filtering;
    final List<OfficeContextAction> items = _visible;
    final double extent = _extent(items);
    final double view = _viewHeight(screen, extent);
    final double chrome = 12 + (filtering ? _filterHeight : 0);
    final double height = chrome + view;
    final double maxScroll = math.max(0, extent - view);
    final double offset = _scroll.clamp(0, maxScroll);
    final double left = widget.globalPosition.dx.clamp(
      8,
      (screen.width - _width - 8).clamp(8, screen.width),
    );
    final double top = widget.globalPosition.dy.clamp(
      8,
      (screen.height - height - 8).clamp(8, screen.height),
    );
    final OfficeContextAction? current = _selectedAction(items);
    final double thumb = maxScroll <= 0
        ? 0
        : math.max(18, view * view / extent);
    return Directionality(
      textDirection: widget.direction,
      child: Theme(
        data: widget.theme,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => widget.onDismiss(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: _width,
                height: height,
                child: Focus(
                  focusNode: _focus,
                  autofocus: filtering,
                  onKeyEvent: _onKey,
                  child: Material(
                    key: const Key('office-context-menu'),
                    color: palette.surface,
                    elevation: 12,
                    shadowColor: const Color(0x40000000),
                    surfaceTintColor: const Color(0x00000000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: palette.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (filtering)
                            SizedBox(
                              height: _filterHeight,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  2,
                                  12,
                                  4,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.search,
                                      size: 16,
                                      color: palette.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _query.isEmpty
                                            ? (widget.filterHint ??
                                                  'Type to search')
                                            : _query,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _query.isEmpty
                                              ? palette.muted
                                              : palette.text,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          SizedBox(
                            height: view,
                            child: Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: ClipRect(
                                    child: Listener(
                                      onPointerSignal: (PointerSignalEvent e) {
                                        if (e is PointerScrollEvent) {
                                          _nudge(e.scrollDelta.dy);
                                        } else if (e
                                            is PointerPanZoomUpdateEvent) {
                                          _nudge(
                                            (e as PointerPanZoomUpdateEvent)
                                                .panDelta
                                                .dy,
                                          );
                                        }
                                      },
                                      child: Transform.translate(
                                        offset: Offset(0, -offset),
                                        child: OverflowBox(
                                          alignment: Alignment.topLeft,
                                          minWidth: 0,
                                          maxWidth: _width,
                                          minHeight: 0,
                                          maxHeight: double.infinity,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: <Widget>[
                                              for (final OfficeContextAction
                                                  action
                                                  in items) ...<Widget>[
                                                if (action.separatorBefore)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 4,
                                                        ),
                                                    child: ColoredBox(
                                                      color: palette.divider,
                                                      child: const SizedBox(
                                                        height: 1,
                                                      ),
                                                    ),
                                                  ),
                                                _OfficeContextItem(
                                                  action: action,
                                                  palette: palette,
                                                  selected:
                                                      filtering &&
                                                      !action.isCaption &&
                                                      action.enabled &&
                                                      identical(
                                                        action,
                                                        current,
                                                      ),
                                                  onSelect: widget.onSelect,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (maxScroll > 0)
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    bottom: 2,
                                    width: 8,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onVerticalDragUpdate:
                                          (DragUpdateDetails d) {
                                            final double track = math.max(
                                              1,
                                              view - thumb,
                                            );
                                            _nudge(
                                              d.delta.dy * maxScroll / track,
                                            );
                                          },
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            top: (view - thumb) <= 0
                                                ? 0
                                                : (view - 4 - thumb) *
                                                      (offset / maxScroll),
                                          ),
                                          child: Container(
                                            width: 4,
                                            height: thumb,
                                            decoration: BoxDecoration(
                                              color: palette.muted,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
}

class _OfficeContextItem extends StatefulWidget {
  const _OfficeContextItem({
    required this.action,
    required this.palette,
    required this.onSelect,
    this.selected = false,
  });

  /// action API.
  final OfficeContextAction action;

  /// palette API.
  final _MenuPalette palette;

  /// onSelect API.
  final ValueChanged<String> onSelect;

  /// Keyboard highlight.
  final bool selected;

  @override
  /// createState API.
  State<_OfficeContextItem> createState() => _OfficeContextItemState();
}

class _OfficeContextItemState extends State<_OfficeContextItem> {
  var _hot = false;

  @override
  /// build API.
  Widget build(BuildContext context) {
    final OfficeContextAction action = widget.action;
    final _MenuPalette palette = widget.palette;
    if (action.isCaption) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: palette.muted,
            height: 1.2,
          ),
        ),
      );
    }
    final Color fg = !action.enabled
        ? palette.disabled
        : (action.danger ? palette.danger : palette.text);
    final Color iconColor = !action.enabled
        ? palette.disabled
        : (action.danger ? palette.danger : palette.icon);
    return MouseRegion(
      onEnter: (_) {
        if (action.enabled) {
          setState(() => _hot = true);
        }
      },
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.enabled ? () => widget.onSelect(action.id) : null,
        child: ColoredBox(
          color: (_hot || widget.selected) && action.enabled
              ? palette.hover
              : const Color(0x00000000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: action.icon == null
                      ? const SizedBox.shrink()
                      : Icon(action.icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: fg,
                      height: 1.2,
                    ),
                  ),
                ),
                if (action.shortcut != null) ...<Widget>[
                  const SizedBox(width: 16),
                  Text(
                    action.shortcut!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: action.enabled ? palette.muted : palette.disabled,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
