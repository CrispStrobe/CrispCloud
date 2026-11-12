// lib/widgets/office_editor_ribbon.dart
//
// Host ribbon for the embedded Quds Office editors. The package paints the
// document surface; this widget supplies the Word/Excel/PowerPoint-style
// chrome: menu bar, tabbed ribbon, font and paragraph controls, insert/layout
// commands, sheet formatting, slide transitions and animations.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_editor_strings.dart';
import '../l10n/office_ribbon_control_strings.dart';
import '../services/office_editor_menu.dart';
import 'office_editor_dialogs.dart';

/// Full ribbon chrome for an [OfficeController].
class OfficeEditorRibbon extends StatefulWidget {
  const OfficeEditorRibbon({
    super.key,
    required this.controller,
    required this.kind,
    required this.config,
    required this.onSave,
    required this.onClose,
    required this.onConfigChanged,
    required this.onFind,
    this.title = '',
    this.dirty = false,
    this.saving = false,
  });

  final OfficeController controller;
  final OfficeEditorKind kind;
  final OfficeSurfaceConfig config;
  final VoidCallback onSave;
  final VoidCallback onClose;
  final ValueChanged<OfficeSurfaceConfig> onConfigChanged;
  final VoidCallback onFind;
  final String title;
  final bool dirty;
  final bool saving;

  @override
  State<OfficeEditorRibbon> createState() => OfficeEditorRibbonState();
}

class OfficeEditorRibbonState extends State<OfficeEditorRibbon> {
  int _tab = 0;
  bool _collapsed = false;
  bool _trackChanges = false;
  bool _wordProtected = false;
  bool _lineNumbers = false;
  bool _transitionAll = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == OfficeEditorKind.word) {
      final WordEditorController word = widget.controller as WordEditorController;
      _trackChanges = word.document.trackRevisions;
      _wordProtected = word.document.restrictEditing;
    }
  }

  OfficeController get _c => widget.controller;
  WordEditorController get _word => _c as WordEditorController;
  SheetEditorController get _sheet => _c as SheetEditorController;
  SlideEditorController get _slides => _c as SlideEditorController;

  List<String> get _tabs => switch (widget.kind) {
        OfficeEditorKind.word => const <String>[
            'Home',
            'Insert',
            'Layout',
            'Review',
            'View',
          ],
        OfficeEditorKind.sheet => const <String>[
            'Home',
            'Insert',
            'Data',
            'View',
          ],
        OfficeEditorKind.slides => const <String>[
            'Home',
            'Insert',
            'Design',
            'Transitions',
            'Animations',
            'Slide Show',
            'Review',
          ],
        OfficeEditorKind.unsupported => const <String>[],
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListenableBuilder(
            listenable: _c,
            builder: (BuildContext context, Widget? child) => _menuBar(theme),
          ),
          _tabStrip(theme),
          if (!_collapsed)
            ListenableBuilder(
              listenable: _c,
              builder: (BuildContext context, Widget? child) =>
                  _ribbonBody(theme),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Menu bar
  // ---------------------------------------------------------------------------

  Widget _menuBar(ThemeData theme) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: theme.colorScheme.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _MenuButton(label: context.tr('File'), items: _fileMenu(theme)),
            _MenuButton(label: context.tr('Edit'), items: _editMenu(theme)),
            _MenuButton(label: context.tr('View'), items: _viewMenu(theme)),
            _MenuButton(label: context.tr('Insert'), items: _insertMenu(theme)),
            _MenuButton(label: context.tr('Format'), items: _formatMenu(theme)),
            _MenuButton(label: context.tr('Tools'), items: _toolsMenu(theme)),
            _MenuButton(label: context.tr('Help'), items: _helpMenu(theme)),
          ],
        ),
      ),
    );
  }

  List<Widget> _fileMenu(ThemeData theme) => <Widget>[
        _menuItem('Save', widget.onSave, icon: Icons.save_outlined),
        if (widget.kind == OfficeEditorKind.word)
          _menuItem('Page setup…', _pageSetupMenu, icon: Icons.tune),
        const Divider(height: 1),
        _menuItem('Close editor', widget.onClose, icon: Icons.close),
      ];

  List<Widget> _editMenu(ThemeData theme) => <Widget>[
        _menuItem('Undo', _c.canUndo ? _c.undo : null, icon: Icons.undo),
        _menuItem('Redo', _c.canRedo ? _c.redo : null, icon: Icons.redo),
        const Divider(height: 1),
        _menuItem('Cut', _canMutate ? _cut : null, icon: Icons.cut),
        _menuItem('Copy', _copy, icon: Icons.copy),
        _menuItem('Paste', _canMutate ? _paste : null, icon: Icons.paste),
        _menuItem('Select all', _selectAll, icon: Icons.select_all),
        const Divider(height: 1),
        _menuItem('Find…', widget.onFind, icon: Icons.search),
        _menuItem('Replace…', _c.requestReplace, icon: Icons.find_replace),
      ];

  List<Widget> _insertMenu(ThemeData theme) {
    switch (widget.kind) {
      case OfficeEditorKind.word:
        return <Widget>[
          _menuItem('Table…', _insertTable, icon: Icons.table_chart),
          _menuItem('Hyperlink…', _insertHyperlink, icon: Icons.link),
          _menuItem(
            'Comment…',
            _c.config.allowsMutation ? _insertComment : null,
            icon: Icons.comment_outlined,
          ),
          _menuItem('Footnote…',
              _canMutate ? () => _insertNote(endnote: false) : null,
              icon: Icons.format_list_numbered),
          _menuItem('Endnote…',
              _canMutate ? () => _insertNote(endnote: true) : null,
              icon: Icons.notes),
          const Divider(height: 1),
          _menuItem('Page break', _pageBreak, icon: Icons.insert_page_break),
          _menuItem('Section break', _sectionBreak, icon: Icons.horizontal_split),
          _menuItem('Column break', _columnBreak, icon: Icons.vertical_split),
          _menuItem('Table of contents', _insertToc, icon: Icons.toc),
          const Divider(height: 1),
          _menuItem('Header', _beginHeader, icon: Icons.web_asset),
          _menuItem('Footer', _beginFooter, icon: Icons.web_asset_off),
          _menuItem('Page number', _insertPageNumber, icon: Icons.pin),
          _menuItem('Watermark…', _watermark, icon: Icons.branding_watermark),
        ];
      case OfficeEditorKind.sheet:
        return <Widget>[
          _menuItem('Insert rows above', () => _sheet.insertSheetRows(after: false),
              icon: Icons.add),
          _menuItem('Insert rows below', () => _sheet.insertSheetRows(after: true),
              icon: Icons.add),
          _menuItem('Insert columns left',
              () => _sheet.insertSheetCols(after: false),
              icon: Icons.add),
          _menuItem('Insert columns right',
              () => _sheet.insertSheetCols(after: true),
              icon: Icons.add),
          const Divider(height: 1),
          _menuItem('Delete rows', _sheetDeleteRows,
              icon: Icons.delete_outline),
          _menuItem('Delete columns', _sheetDeleteCols,
              icon: Icons.delete_outline),
          _menuItem('Table', _sheetAddTable, icon: Icons.table_chart),
          _menuItem('Comment…', _sheetComment, icon: Icons.comment_outlined),
        ];
      case OfficeEditorKind.slides:
        return <Widget>[
          _menuItem('New slide', _slideNew, icon: Icons.add_box_outlined),
          _menuItem('Duplicate slide', _slideDuplicate,
              icon: Icons.copy_all_outlined),
          _menuItem('Text box', _slideTextBox, icon: Icons.text_fields),
          _menuItem('Rectangle', () => _slideAddShape(PmlShapePreset.rect),
              icon: Icons.crop_square),
          _menuItem('Ellipse', () => _slideAddShape(PmlShapePreset.ellipse),
              icon: Icons.circle_outlined),
          _menuItem('Line', () => _slideAddShape(PmlShapePreset.connector),
              icon: Icons.horizontal_rule),
          _menuItem('Table…', _slideInsertTable, icon: Icons.table_chart),
          _menuItem('Picture…', _slideInsertPicture, icon: Icons.image_outlined),
          const Divider(height: 1),
          _menuItem('Speaker notes…', _slideNotes, icon: Icons.notes),
        ];
      case OfficeEditorKind.unsupported:
        return const <Widget>[];
    }
  }

  List<Widget> _formatMenu(ThemeData theme) {
    switch (widget.kind) {
      case OfficeEditorKind.word:
        return <Widget>[
          _menuItem('Font…', _wordFontDialog, icon: Icons.text_fields),
          _menuItem('Paragraph…', _wordParagraphDialog, icon: Icons.notes),
          const Divider(height: 1),
          _menuItem('Bullets', () => _toggleList(false),
              icon: Icons.format_list_bulleted),
          _menuItem('Numbering', () => _toggleList(true),
              icon: Icons.format_list_numbered),
          _menuItem('Clear formatting', _clearWordFormat,
              icon: Icons.format_clear),
        ];
      case OfficeEditorKind.sheet:
        return <Widget>[
          _menuItem('Fill color…', _sheetFill, icon: Icons.format_color_fill),
          _menuItem('Font color…', _sheetFontColor,
              icon: Icons.format_color_text),
          _menuItem('Clear formatting', _sheetClearFormat,
              icon: Icons.format_clear),
          const Divider(height: 1),
          _menuItem('Merge and center', _sheet.toggleMergeAndCenter,
              icon: Icons.merge_type),
          _menuItem('Unmerge', _sheet.unmergeCells, icon: Icons.call_split),
        ];
      case OfficeEditorKind.slides:
        return <Widget>[
          _menuItem('Text color…', _slideTextColor, icon: Icons.format_color_text),
          _menuItem('Shape fill…', _slideFill, icon: Icons.format_color_fill),
          _menuItem('Background…', _slideBackground, icon: Icons.wallpaper),
          const Divider(height: 1),
          _menuItem('Align left', () => _slideAlign(PmlTextAlign.left),
              icon: Icons.format_align_left),
          _menuItem('Align center', () => _slideAlign(PmlTextAlign.center),
              icon: Icons.format_align_center),
          _menuItem('Align right', () => _slideAlign(PmlTextAlign.right),
              icon: Icons.format_align_right),
          _menuItem('Justify', () => _slideAlign(PmlTextAlign.justify),
              icon: Icons.format_align_justify),
        ];
      case OfficeEditorKind.unsupported:
        return const <Widget>[];
    }
  }

  List<Widget> _viewMenu(ThemeData theme) {
    final List<Widget> items = <Widget>[];
    switch (widget.kind) {
      case OfficeEditorKind.word:
        items.add(_menuItem(
          widget.config.showRulers ? 'Hide rulers' : 'Show rulers',
          () => _setConfig(showRulers: !widget.config.showRulers),
          icon: Icons.straighten,
        ));
        items.add(_menuItem(
          widget.config.showNotesPane ? 'Hide footnotes' : 'Show footnotes',
          () => _setConfig(showNotesPane: !widget.config.showNotesPane),
          icon: Icons.notes,
        ));
        break;
      case OfficeEditorKind.sheet:
        items.addAll(<Widget>[
          _menuItem(
            widget.config.showFormulaBar ? 'Hide formula bar' : 'Show formula bar',
            () => _setConfig(showFormulaBar: !widget.config.showFormulaBar),
            icon: Icons.functions,
          ),
          _menuItem(
            widget.config.showGridlines ? 'Hide gridlines' : 'Show gridlines',
            () => _setConfig(showGridlines: !widget.config.showGridlines),
            icon: Icons.grid_on,
          ),
          _menuItem(
            widget.config.showGridHeaders
                ? 'Hide row/column headers'
                : 'Show row/column headers',
            () => _setConfig(
              showGridHeaders: !widget.config.showGridHeaders,
            ),
            icon: Icons.view_column_outlined,
          ),
        ]);
        break;
      case OfficeEditorKind.slides:
        items.add(_menuItem(
          widget.config.showSlideHandles ? 'Hide handles' : 'Show handles',
          () => _setConfig(showSlideHandles: !widget.config.showSlideHandles),
          icon: Icons.crop_free,
        ));
        break;
      case OfficeEditorKind.unsupported:
        break;
    }
    items.addAll(<Widget>[
      const Divider(height: 1),
      _menuItem(
        _c.mode == OfficeInteractionMode.editing
            ? 'Reading view'
            : 'Return to editing',
        _toggleReadingMode,
        icon: Icons.chrome_reader_mode_outlined,
      ),
      _menuItem('Collapse ribbon', () => setState(() => _collapsed = true),
          icon: Icons.keyboard_arrow_up),
    ]);
    return items;
  }

  List<Widget> _toolsMenu(ThemeData theme) {
    switch (widget.kind) {
      case OfficeEditorKind.word:
        return <Widget>[
          _menuItem('Word count…', _wordCount, icon: Icons.analytics_outlined),
          _menuItem(
            _trackChanges ? 'Stop tracking changes' : 'Track changes',
            _toggleTrackChanges,
            icon: Icons.track_changes,
          ),
          const Divider(height: 1),
          _menuItem(
            _wordProtected ? 'Unprotect document' : 'Protect document',
            _toggleProtect,
            icon: Icons.lock_outline,
          ),
          _menuItem('Left-to-right', () => _word.setParagraphDirection(rtl: false),
              icon: Icons.format_textdirection_l_to_r),
          _menuItem('Right-to-left', () => _word.setParagraphDirection(rtl: true),
              icon: Icons.format_textdirection_r_to_l),
        ];
      case OfficeEditorKind.sheet:
        return <Widget>[
          _menuItem('Protect sheet…', _sheetProtect, icon: Icons.lock_outline),
          _menuItem('Unprotect sheet', _sheetUnprotect, icon: Icons.lock_open),
          _menuItem('Toggle right-to-left', _sheet.toggleSheetRightToLeft,
              icon: Icons.format_textdirection_r_to_l),
          _menuItem('Comment…', _sheetComment, icon: Icons.comment_outlined),
        ];
      case OfficeEditorKind.slides:
        return <Widget>[
          _menuItem('Speaker notes…', _slideNotes, icon: Icons.notes),
          _menuItem('Slide count…', _wordCount, icon: Icons.analytics_outlined),
          _menuItem('Animations', () => setState(() => _tab = 4),
              icon: Icons.animation),
          _menuItem('Transitions', () => setState(() => _tab = 3),
              icon: Icons.swap_horiz),
        ];
      case OfficeEditorKind.unsupported:
        return const <Widget>[];
    }
  }

  List<Widget> _helpMenu(ThemeData theme) => <Widget>[
        _menuItem(
          'Keyboard shortcuts…',
          () => showOfficeShortcuts(
            context,
            switch (widget.kind) {
              OfficeEditorKind.word => 'word',
              OfficeEditorKind.sheet => 'sheet',
              OfficeEditorKind.slides => 'slides',
              OfficeEditorKind.unsupported => 'office',
            },
          ),
          icon: Icons.keyboard_outlined,
        ),
        _menuItem('About the editor…', _aboutEditor, icon: Icons.info_outline),
      ];

  Widget _menuItem(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15),
            const SizedBox(width: 8),
          ],
          Text(context.tr(label), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _tabStrip(ThemeData theme) {
    return Container(
      height: 32,
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: context.tr('Close'),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          if (widget.title.isNotEmpty)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${widget.title}${widget.dirty ? ' •' : ''}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < _tabs.length; i++)
                    InkWell(
                      onTap: () => setState(() {
                        _tab = i;
                        _collapsed = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _tab == i
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          context.tr(_tabs[i]),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                _tab == i ? FontWeight.w600 : FontWeight.w400,
                            color: _tab == i
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: OfficeRibbonControlStrings(context).text(_collapsed ? 'Expand ribbon' : 'Collapse ribbon'),
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _collapsed = !_collapsed),
            icon: Icon(
              _collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            ),
          ),
          IconButton(
            tooltip: context.tr('Save'),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: widget.saving ? null : widget.onSave,
            icon: widget.saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: context.tr('Close'),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _ribbonBody(ThemeData theme) {
    final int tab = _tab.clamp(0, _tabs.length - 1);
    final List<Widget> groups = switch (widget.kind) {
      OfficeEditorKind.word => _wordTab(tab, theme),
      OfficeEditorKind.sheet => _sheetTab(tab, theme),
      OfficeEditorKind.slides => _slideTab(tab, theme),
      OfficeEditorKind.unsupported => const <Widget>[],
    };
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: groups,
        ),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> groups) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < groups.length; i++) {
      if (i > 0) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
          child: VerticalDivider(
            width: 1,
            thickness: 0.5,
            color: Theme.of(context).dividerColor,
          ),
        ));
      }
      out.add(groups[i]);
    }
    return out;
  }

  Widget _group(String label, List<Widget> children) {
    return Tooltip(
      message: context.tr(label),
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Word tabs
  // ---------------------------------------------------------------------------

  WmlRunProps get _runProps => _word.activeRunProps;

  WmlParagraphProps? get _paraProps {
    final List<WmlParagraph> paras = _word.document.paragraphs.toList();
    if (paras.isEmpty) return null;
    final int index =
        _word.documentCaret.paragraphIndex.clamp(0, paras.length - 1);
    return paras[index].properties;
  }

  List<Widget> _wordTab(int tab, ThemeData theme) {
    switch (tab) {
      case 0:
        return _withDividers(<Widget>[
          _group('Clipboard', <Widget>[
            _bigButton(Icons.content_paste, 'Paste', _paste),
            _bigButton(Icons.cut, 'Cut', _cut),
            _bigButton(Icons.copy, 'Copy', _copy),
            _bigButton(Icons.select_all, 'Select all', _selectAll),
          ]),
          _group('Font', <Widget>[
            _fontFamilyDropdown(),
            _fontSizeDropdown(),
            _iconButton(
              Icons.format_bold,
              'Bold (Ctrl+B)',
              _toggleBold,
              active: _runProps.bold,
            ),
            _iconButton(
              Icons.format_italic,
              'Italic (Ctrl+I)',
              _toggleItalic,
              active: _runProps.italic,
            ),
            _underlineControl(),
            _iconButton(
              Icons.format_strikethrough,
              'Strikethrough',
              _toggleStrike,
              active: _runProps.strike,
            ),
            _vertAlignControl(),
            _colorButton(
              Icons.format_color_text,
              'Font color',
              _runProps.color,
              _setTextColor,
            ),
            _colorButton(
              Icons.highlight,
              'Highlight',
              _runProps.highlight ?? '',
              _setHighlight,
              allowNone: true,
            ),
            _iconButton(Icons.more_horiz, 'Font settings…', _wordFontDialog),
          ]),
          _group('Paragraph', <Widget>[
            _iconButton(
              Icons.format_list_bulleted,
              'Bullets',
              () => _toggleList(false),
            ),
            _iconButton(
              Icons.format_list_numbered,
              'Numbering',
              () => _toggleList(true),
            ),
            _iconButton(
              Icons.format_indent_decrease,
              'Decrease indent',
              () => _nudgeIndent(-18),
            ),
            _iconButton(
              Icons.format_indent_increase,
              'Increase indent',
              () => _nudgeIndent(18),
            ),
            _alignControl(),
            _lineSpacingControl(),
            _wordDirectionControl(),
            _iconButton(
              Icons.more_horiz,
              'Paragraph settings…',
              _wordParagraphDialog,
            ),
          ]),
          _group('Styles', <Widget>[
            _wordStyleDropdown(),
            _iconButton(Icons.format_clear, 'Clear formatting', _clearWordFormat),
          ]),
          _group('Editing', <Widget>[
            _iconButton(Icons.search, 'Find (Ctrl+F)', widget.onFind),
            _iconButton(Icons.find_replace, 'Replace', _c.requestReplace),
            _iconButton(Icons.comment_outlined, 'New comment', _insertComment),
          ]),
        ]);
      case 1:
        final bool inTable = _word.isInTable;
        return _withDividers(<Widget>[
          _group('Pages', <Widget>[
            _bigButton(Icons.insert_page_break, 'Page break', _pageBreak),
            _bigButton(Icons.horizontal_split, 'Section break', _sectionBreak),
            _bigButton(Icons.vertical_split, 'Column break', _columnBreak),
          ]),
          _group('Tables', <Widget>[
            _bigButton(Icons.table_chart, 'Table', _insertTable),
            _iconButton(
              Icons.playlist_add,
              'Insert row above',
              () => _word.insertTableRow(after: false),
              enabled: inTable,
            ),
            _iconButton(
              Icons.playlist_add,
              'Insert row below',
              () => _word.insertTableRow(after: true),
              enabled: inTable,
            ),
            _iconButton(
              Icons.view_week_outlined,
              'Insert column left',
              () => _word.insertTableColumn(after: false),
              enabled: inTable,
            ),
            _iconButton(
              Icons.view_week_outlined,
              'Insert column right',
              () => _word.insertTableColumn(after: true),
              enabled: inTable,
            ),
            _iconButton(
              Icons.delete_outline,
              'Delete row',
              () => _word.deleteTableRow(),
              enabled: inTable,
            ),
            _iconButton(
              Icons.delete_outline,
              'Delete column',
              () => _word.deleteTableColumn(),
              enabled: inTable,
            ),
            _iconButton(
              Icons.delete_forever_outlined,
              'Delete table',
              () => _word.deleteTable(),
              enabled: inTable,
            ),
            _iconButton(
              Icons.merge_type,
              'Merge cells',
              _word.mergeTableCells,
              enabled: inTable,
            ),
            _iconButton(
              Icons.call_split,
              'Unmerge cells',
              _word.unmergeTableCells,
              enabled: inTable,
            ),
          ]),
          _group('Illustrations', <Widget>[
            _bigButton(Icons.image_outlined, 'Picture', _wordInsertPicture),
          ]),
          _group('Notes', <Widget>[
            _bigButton(Icons.format_list_numbered, 'Footnote',
                () => _insertNote(endnote: false), enabled: _canMutate),
            _bigButton(Icons.notes, 'Endnote',
                () => _insertNote(endnote: true), enabled: _canMutate),
          ]),
          _group('Links', <Widget>[
            _bigButton(Icons.link, 'Hyperlink', _insertHyperlink),
            _bigButton(Icons.comment_outlined, 'Comment', _insertComment),
          ]),
          _group('Header & Footer', <Widget>[
            _bigButton(Icons.web_asset, 'Header', _beginHeader),
            _bigButton(Icons.web_asset_off, 'Footer', _beginFooter),
            _iconButton(Icons.pin, 'Page number', _insertPageNumber),
            _iconButton(Icons.pin_end, 'Total pages',
                () => _word.insertField(WmlFieldKind.numPages)),
            if (_word.isEditingHeaderFooter)
              _iconButton(
                Icons.check,
                'Close header/footer',
                _word.endHeaderFooterEdit,
                active: true,
              ),
          ]),
          _group('Text', <Widget>[
            _bigButton(Icons.toc, 'Contents', _insertToc),
            _bigButton(Icons.branding_watermark, 'Watermark', _watermark),
            _iconButton(Icons.calendar_today, 'Date',
                () => _word.insertField(WmlFieldKind.date)),
            _iconButton(Icons.schedule, 'Time',
                () => _word.insertField(WmlFieldKind.time)),
          ]),
          _group('Symbols', <Widget>[
            _iconButton(Icons.functions, 'Page field',
                () => _word.insertField(WmlFieldKind.page)),
            _iconButton(Icons.numbers, 'Number of pages',
                () => _word.insertField(WmlFieldKind.numPages)),
          ]),
        ]);
      case 2:
        return _withDividers(<Widget>[
          _group('Page Setup', <Widget>[
            _bigMenuButton(
              Icons.straighten,
              'Margins',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Normal', () => _setMargins(WmlPageMargins.normal)),
                _actionItem('Narrow', () => _setMargins(WmlPageMargins.narrow)),
                _actionItem(
                    'Moderate', () => _setMargins(WmlPageMargins.moderate)),
                _actionItem('Wide', () => _setMargins(WmlPageMargins.wide)),
                const PopupMenuDivider(),
                _actionItem('Custom…', _customMargins),
              ],
            ),
            _bigMenuButton(
              Icons.crop_rotate,
              'Orientation',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Portrait', () => _word.setPageLandscape(false)),
                _actionItem('Landscape', () => _word.setPageLandscape(true)),
              ],
            ),
            _bigMenuButton(
              Icons.description_outlined,
              'Size',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('A4', () => _word.setPageSize(WmlPageSize.a4())),
                _actionItem('Letter',
                    () => _word.setPageSize(WmlPageSize.letter())),
                _actionItem('Legal', () => _word.setPageSize(WmlPageSize.legal())),
                _actionItem('A3', () => _word.setPageSize(WmlPageSize.a3())),
              ],
            ),
            _bigMenuButton(
              Icons.view_column_outlined,
              'Columns',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('One', () => _word.setSectionColumns(1)),
                _actionItem('Two', () => _word.setSectionColumns(2)),
                _actionItem('Three', () => _word.setSectionColumns(3)),
              ],
            ),
            _iconButton(
              Icons.format_list_numbered,
              'Line numbers',
              () {
                _lineNumbers = !_lineNumbers;
                _word.setLineNumbers(_lineNumbers);
                setState(() {});
              },
              active: _lineNumbers,
            ),
          ]),
          _group('Paragraph', <Widget>[
            _iconButton(Icons.format_indent_decrease, 'Decrease indent',
                () => _nudgeIndent(-18)),
            _iconButton(Icons.format_indent_increase, 'Increase indent',
                () => _nudgeIndent(18)),
            _lineSpacingControl(),
            _bigMenuButton(
              Icons.space_bar,
              'Spacing',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Add 6 pt before', () => _spaceBefore(6)),
                _actionItem('Add 12 pt before', () => _spaceBefore(12)),
                _actionItem('Add 6 pt after', () => _spaceAfter(6)),
                _actionItem('Add 12 pt after', () => _spaceAfter(12)),
                const PopupMenuDivider(),
                _actionItem('Remove before', () => _spaceBefore(0)),
                _actionItem('Remove after', () => _spaceAfter(0)),
              ],
            ),
            _iconButton(Icons.format_clear, 'Clear formatting',
                _clearWordFormat),
          ]),
          _group('Background', <Widget>[
            _bigButton(Icons.branding_watermark, 'Watermark', _watermark),
            _iconButton(Icons.format_color_fill, 'Paragraph shading',
                _paragraphShading),
          ]),
        ]);
      case 3:
        return _withDividers(<Widget>[
          _group('Proofing', <Widget>[
            _bigButton(Icons.analytics_outlined, 'Word count', _wordCount),
            _bigButton(Icons.spellcheck, 'Spell check', _spellCheck),
          ]),
          _group('Comments', <Widget>[
            _bigButton(Icons.comment_outlined, 'New comment', _insertComment),
          ]),
          _group('Tracking', <Widget>[
            _bigButton(
              Icons.track_changes,
              _trackChanges ? 'Tracking on' : 'Track changes',
              _toggleTrackChanges,
              active: _trackChanges,
            ),
          ]),
          _group('Protect', <Widget>[
            _bigButton(
              Icons.lock_outline,
              _wordProtected ? 'Protected' : 'Protect',
              _toggleProtect,
              active: _wordProtected,
            ),
          ]),
          _group('Language', <Widget>[
            _iconButton(Icons.format_textdirection_l_to_r, 'Left-to-right',
                () => _word.setParagraphDirection(rtl: false)),
            _iconButton(Icons.format_textdirection_r_to_l, 'Right-to-left',
                () => _word.setParagraphDirection(rtl: true)),
          ]),
        ]);
      case 4:
        return _withDividers(<Widget>[
          _group('Show', <Widget>[
            _bigButton(
              Icons.straighten,
              widget.config.showRulers ? 'Hide rulers' : 'Show rulers',
              () => _setConfig(showRulers: !widget.config.showRulers),
              active: widget.config.showRulers,
            ),
            _bigButton(
              Icons.notes,
              widget.config.showNotesPane ? 'Hide footnotes' : 'Show footnotes',
              () => _setConfig(showNotesPane: !widget.config.showNotesPane),
              active: widget.config.showNotesPane,
            ),
          ]),
          _group('Workspace', <Widget>[
            _bigButton(
              Icons.chrome_reader_mode_outlined,
              _c.mode == OfficeInteractionMode.editing
                  ? 'Reading view'
                  : 'Edit',
              _toggleReadingMode,
              active: _c.mode != OfficeInteractionMode.editing,
            ),
            _bigButton(
              Icons.keyboard_arrow_up,
              _collapsed ? 'Expand' : 'Collapse',
              () => setState(() => _collapsed = !_collapsed),
              active: _collapsed,
            ),
          ]),
          _group('Help', <Widget>[
            _bigButton(Icons.keyboard_outlined, 'Shortcuts',
                () => showOfficeShortcuts(context, 'word')),
            _bigButton(Icons.info_outline, 'About', _aboutEditor),
          ]),
        ]);
      default:
        return const <Widget>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Sheet tabs
  // ---------------------------------------------------------------------------

  SmlCell get _cell => _sheet.sheet.cell(_sheet.activeCell);

  List<Widget> _sheetTab(int tab, ThemeData theme) {
    switch (tab) {
      case 0:
        return _withDividers(<Widget>[
          _group('Clipboard', <Widget>[
            _bigButton(Icons.content_paste, 'Paste', _paste),
            _bigButton(Icons.cut, 'Cut', _cut),
            _bigButton(Icons.copy, 'Copy', _copy),
            _bigButton(Icons.select_all, 'Select all', _selectAll),
          ]),
          _group('Font', <Widget>[
            _sheetFontSizeDropdown(),
            _iconButton(Icons.format_bold, 'Bold', _sheetBold,
                active: _cell.fontBold),
            _colorButton(
              Icons.format_color_text,
              'Font color',
              _cell.fontRgb,
              _sheetFontColorValue,
            ),
            _colorButton(
              Icons.format_color_fill,
              'Fill color',
              _cell.fillRgb,
              _sheetFillValue,
              allowNone: true,
            ),
            _iconButton(Icons.format_clear, 'Clear formatting',
                _sheetClearFormat),
          ]),
          _group('Alignment', <Widget>[
            _iconButton(
              Icons.format_align_left,
              'Align left',
              () => _sheetAlign(SmlHAlign.left),
              active: _cell.horizontalAlign == SmlHAlign.left,
            ),
            _iconButton(
              Icons.format_align_center,
              'Align center',
              () => _sheetAlign(SmlHAlign.center),
              active: _cell.horizontalAlign == SmlHAlign.center,
            ),
            _iconButton(
              Icons.format_align_right,
              'Align right',
              () => _sheetAlign(SmlHAlign.right),
              active: _cell.horizontalAlign == SmlHAlign.right,
            ),
            _iconButton(
              Icons.clear_all,
              'General alignment',
              () => _sheetAlign(SmlHAlign.general),
              active: _cell.horizontalAlign == SmlHAlign.general,
            ),
            _iconButton(Icons.merge_type, 'Merge & center',
                _sheet.toggleMergeAndCenter),
            _iconButton(Icons.call_split, 'Unmerge', _sheet.unmergeCells),
          ]),
          _group('Cells', <Widget>[
            _iconButton(Icons.add, 'Insert row above',
                () => _sheet.insertSheetRows(after: false)),
            _iconButton(Icons.add, 'Insert row below',
                () => _sheet.insertSheetRows(after: true)),
            _iconButton(Icons.add, 'Insert column left',
                () => _sheet.insertSheetCols(after: false)),
            _iconButton(Icons.add, 'Insert column right',
                () => _sheet.insertSheetCols(after: true)),
            _iconButton(Icons.delete_outline, 'Delete rows',
                _sheetDeleteRows),
            _iconButton(Icons.delete_outline, 'Delete columns',
                _sheetDeleteCols),
            _iconButton(Icons.backspace_outlined, 'Clear contents',
                _sheet.clearSelectedCells),
          ]),
          _group('Editing', <Widget>[
            _iconButton(Icons.search, 'Find (Ctrl+F)', widget.onFind),
            _bigMenuButton(
              Icons.sort,
              'Sort',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Sort A → Z',
                    () => _sheet.sortSelection(ascending: true)),
                _actionItem('Sort Z → A',
                    () => _sheet.sortSelection(ascending: false)),
              ],
            ),
            _iconButton(Icons.filter_alt_outlined, 'Filter',
                () => _sheet.filterSelection()),
            _iconButton(Icons.filter_alt_off_outlined, 'Clear filter',
                _sheet.clearFilter),
          ]),
        ]);
      case 1:
        return _withDividers(<Widget>[
          _group('Rows & Columns', <Widget>[
            _bigMenuButton(
              Icons.add,
              'Insert',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Rows above',
                    () => _sheet.insertSheetRows(after: false)),
                _actionItem('Rows below',
                    () => _sheet.insertSheetRows(after: true)),
                _actionItem('Columns left',
                    () => _sheet.insertSheetCols(after: false)),
                _actionItem('Columns right',
                    () => _sheet.insertSheetCols(after: true)),
              ],
            ),
            _bigMenuButton(
              Icons.delete_outline,
              'Delete',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Rows', _sheetDeleteRows),
                _actionItem('Columns', _sheetDeleteCols),
              ],
            ),
            _iconButton(Icons.height, 'Row height +',
                () => _sheet.nudgeRowHeight(6)),
            _iconButton(Icons.height, 'Row height −',
                () => _sheet.nudgeRowHeight(-6)),
            _iconButton(Icons.swap_horiz, 'Column width +',
                () => _sheet.nudgeColumnWidth(8)),
            _iconButton(Icons.swap_horiz, 'Column width −',
                () => _sheet.nudgeColumnWidth(-8)),
          ]),
          _group('Tables', <Widget>[
            _bigButton(Icons.table_chart, 'Table', _sheetAddTable),
            _bigButton(Icons.comment_outlined, 'Comment', _sheetComment),
          ]),
          _group('Freeze', <Widget>[
            _bigButton(Icons.ac_unit, 'Freeze panes',
                _sheet.toggleFreezePanes,
                active: _sheet.hasFrozenPanes),
            _iconButton(Icons.vertical_align_top, 'Top row',
                _sheet.freezeTopRow),
            _iconButton(Icons.align_horizontal_left, 'First column',
                _sheet.freezeFirstColumn),
          ]),
          _group('Data', <Widget>[
            _bigButton(Icons.filter_alt_outlined, 'Filter',
                () => _sheet.filterSelection()),
            _iconButton(Icons.filter_alt_off_outlined, 'Clear filter',
                _sheet.clearFilter),
            _iconButton(Icons.sort, 'Sort ascending',
                () => _sheet.sortSelection(ascending: true)),
            _iconButton(Icons.sort, 'Sort descending',
                () => _sheet.sortSelection(ascending: false)),
          ]),
        ]);
      case 2:
        return _withDividers(<Widget>[
          _group('Sort & Filter', <Widget>[
            _bigButton(Icons.sort, 'Sort A → Z',
                () => _sheet.sortSelection(ascending: true)),
            _bigButton(Icons.sort, 'Sort Z → A',
                () => _sheet.sortSelection(ascending: false)),
            _bigButton(Icons.filter_alt_outlined, 'Filter',
                () => _sheet.filterSelection()),
            _bigButton(Icons.filter_alt_off_outlined, 'Clear',
                _sheet.clearFilter),
          ]),
          _group('Sheet', <Widget>[
            _bigButton(Icons.ac_unit, 'Freeze panes',
                _sheet.toggleFreezePanes,
                active: _sheet.hasFrozenPanes),
            _iconButton(Icons.vertical_align_top, 'Freeze top row',
                _sheet.freezeTopRow),
            _iconButton(Icons.align_horizontal_left, 'Freeze first column',
                _sheet.freezeFirstColumn),
            _iconButton(Icons.format_textdirection_r_to_l, 'Right-to-left',
                _sheet.toggleSheetRightToLeft,
                active: _sheet.sheet.rightToLeft),
          ]),
          _group('Protect', <Widget>[
            _bigButton(Icons.lock_outline, 'Protect', _sheetProtect,
                active: _sheet.sheet.protection != null),
            _bigButton(Icons.lock_open, 'Unprotect', _sheetUnprotect),
          ]),
          _group('Comments', <Widget>[
            _bigButton(Icons.comment_outlined, 'New comment', _sheetComment),
          ]),
        ]);
      case 3:
        return _withDividers(<Widget>[
          _group('Show', <Widget>[
            _bigButton(
              Icons.functions,
              widget.config.showFormulaBar ? 'Hide formula bar' : 'Show formula bar',
              () => _setConfig(showFormulaBar: !widget.config.showFormulaBar),
              active: widget.config.showFormulaBar,
            ),
            _bigButton(
              Icons.grid_on,
              widget.config.showGridlines ? 'Hide gridlines' : 'Show gridlines',
              () => _setConfig(showGridlines: !widget.config.showGridlines),
              active: widget.config.showGridlines,
            ),
            _bigButton(
              Icons.view_column_outlined,
              widget.config.showGridHeaders ? 'Hide headers' : 'Show headers',
              () => _setConfig(
                  showGridHeaders: !widget.config.showGridHeaders),
              active: widget.config.showGridHeaders,
            ),
          ]),
          _group('Workspace', <Widget>[
            _bigButton(
              Icons.chrome_reader_mode_outlined,
              _c.mode == OfficeInteractionMode.editing
                  ? 'Reading view'
                  : 'Edit',
              _toggleReadingMode,
              active: _c.mode != OfficeInteractionMode.editing,
            ),
            _bigButton(
              Icons.keyboard_arrow_up,
              _collapsed ? 'Expand' : 'Collapse',
              () => setState(() => _collapsed = !_collapsed),
              active: _collapsed,
            ),
          ]),
          _group('Help', <Widget>[
            _bigButton(Icons.keyboard_outlined, 'Shortcuts',
                () => showOfficeShortcuts(context, 'sheet')),
            _bigButton(Icons.info_outline, 'About', _aboutEditor),
          ]),
        ]);
      default:
        return const <Widget>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Slide tabs
  // ---------------------------------------------------------------------------

  PmlShape? get _shape => _slides.selected;

  List<Widget> _slideTab(int tab, ThemeData theme) {
    switch (tab) {
      case 0:
        return _withDividers(<Widget>[
          _group('Clipboard', <Widget>[
            _bigButton(Icons.content_paste, 'Paste', _paste),
            _bigButton(Icons.cut, 'Cut', _cut),
            _bigButton(Icons.copy, 'Copy', _copy),
            _bigButton(Icons.select_all, 'Select all', _selectAll),
          ]),
          _group('Slides', <Widget>[
            _bigButton(Icons.add_box_outlined, 'New slide', _slideNew),
            _bigButton(Icons.copy_all_outlined, 'Duplicate', _slideDuplicate),
            _bigButton(Icons.delete_outline, 'Delete', _slideDelete),
          ]),
          _group('Font', <Widget>[
            _slideFontSizeDropdown(),
            _colorButton(
              Icons.format_color_text,
              'Text color',
              _shape?.textColor ?? '',
              _slideTextColorValue,
            ),
            _colorButton(
              Icons.format_color_fill,
              'Shape fill',
              _shape?.fillColor ?? '',
              _slideFillValue,
              allowNone: true,
            ),
            _iconButton(
              Icons.format_align_left,
              'Align left',
              () => _slideAlign(PmlTextAlign.left),
              active: _shape?.textAlign == PmlTextAlign.left,
            ),
            _iconButton(
              Icons.format_align_center,
              'Align center',
              () => _slideAlign(PmlTextAlign.center),
              active: _shape?.textAlign == PmlTextAlign.center,
            ),
            _iconButton(
              Icons.format_align_right,
              'Align right',
              () => _slideAlign(PmlTextAlign.right),
              active: _shape?.textAlign == PmlTextAlign.right,
            ),
            _iconButton(
              Icons.format_align_justify,
              'Justify',
              () => _slideAlign(PmlTextAlign.justify),
              active: _shape?.textAlign == PmlTextAlign.justify,
            ),
          ]),
          _group('Drawing', <Widget>[
            _bigButton(Icons.text_fields, 'Text box', _slideTextBox),
            _iconButton(Icons.crop_square, 'Rectangle',
                () => _slideAddShape(PmlShapePreset.rect)),
            _iconButton(Icons.circle_outlined, 'Ellipse',
                () => _slideAddShape(PmlShapePreset.ellipse)),
            _iconButton(Icons.horizontal_rule, 'Line',
                () => _slideAddShape(PmlShapePreset.connector)),
            _iconButton(Icons.table_chart, 'Table', _slideInsertTable),
          ]),
          _group('Arrange', <Widget>[
            _bigMenuButton(
              Icons.align_horizontal_center,
              'Align',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Align left',
                    () => _slides.alignShapes(PmlAlignAxis.left)),
                _actionItem('Align center',
                    () => _slides.alignShapes(PmlAlignAxis.center)),
                _actionItem('Align right',
                    () => _slides.alignShapes(PmlAlignAxis.right)),
                _actionItem('Align top',
                    () => _slides.alignShapes(PmlAlignAxis.top)),
                _actionItem('Align middle',
                    () => _slides.alignShapes(PmlAlignAxis.middle)),
                _actionItem('Align bottom',
                    () => _slides.alignShapes(PmlAlignAxis.bottom)),
                const PopupMenuDivider(),
                _actionItem('Distribute horizontally',
                    () => _slides.distributeShapes(horizontal: true)),
                _actionItem('Distribute vertically',
                    () => _slides.distributeShapes(horizontal: false)),
              ],
            ),
            _iconButton(Icons.flip_to_front, 'Bring forward',
                () => _slides.reorderSelected(forward: true)),
            _iconButton(Icons.flip_to_back, 'Send backward',
                () => _slides.reorderSelected(forward: false)),
            _iconButton(Icons.workspaces_outline, 'Group',
                () => _slides.groupShapes()),
            _iconButton(Icons.workspaces, 'Ungroup',
                () => _slides.ungroupShapes()),
            _iconButton(Icons.delete_outline, 'Delete shape',
                _slides.deleteSelectedShape,
                enabled: _shape != null),
          ]),
          _group('Editing', <Widget>[
            _iconButton(Icons.search, 'Find (Ctrl+F)', widget.onFind),
            _iconButton(Icons.notes, 'Speaker notes', _slideNotes),
          ]),
        ]);
      case 1:
        return _withDividers(<Widget>[
          _group('Slides', <Widget>[
            _bigButton(Icons.add_box_outlined, 'New slide', _slideNew),
            _bigButton(Icons.copy_all_outlined, 'Duplicate', _slideDuplicate),
            _bigButton(Icons.delete_outline, 'Delete', _slideDelete),
            _bigButton(Icons.notes, 'Notes', _slideNotes),
          ]),
          _group('Text', <Widget>[
            _bigButton(Icons.text_fields, 'Text box', _slideTextBox),
          ]),
          _group('Shapes', <Widget>[
            _bigMenuButton(
              Icons.category_outlined,
              'Shapes',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Rectangle',
                    () => _slideAddShape(PmlShapePreset.rect)),
                _actionItem('Rounded rectangle',
                    () => _slideAddShape(PmlShapePreset.roundRect)),
                _actionItem('Ellipse',
                    () => _slideAddShape(PmlShapePreset.ellipse)),
                _actionItem('Triangle',
                    () => _slideAddShape(PmlShapePreset.triangle)),
                _actionItem('Line',
                    () => _slideAddShape(PmlShapePreset.connector)),
              ],
            ),
            _bigButton(Icons.table_chart, 'Table', _slideInsertTable),
          ]),
          _group('Media', <Widget>[
            _bigButton(Icons.image_outlined, 'Picture', _slideInsertPicture),
            _bigButton(Icons.slideshow, 'Slide show', _slideShowFromStart),
          ]),
        ]);
      case 2:
        return _withDividers(<Widget>[
          _group('Background', <Widget>[
            _bigButton(Icons.wallpaper, 'Background', _slideBackground),
            _bigButton(Icons.format_color_fill, 'Shape fill', _slideFill),
            _bigButton(Icons.format_color_text, 'Text color', _slideTextColor),
          ]),
          _group('Text', <Widget>[
            _slideFontSizeDropdown(),
            _iconButton(Icons.format_align_left, 'Align left',
                () => _slideAlign(PmlTextAlign.left)),
            _iconButton(Icons.format_align_center, 'Align center',
                () => _slideAlign(PmlTextAlign.center)),
            _iconButton(Icons.format_align_right, 'Align right',
                () => _slideAlign(PmlTextAlign.right)),
            _iconButton(Icons.format_align_justify, 'Justify',
                () => _slideAlign(PmlTextAlign.justify)),
          ]),
          _group('Theme', <Widget>[
            _bigMenuButton(
              Icons.palette_outlined,
              'Colors',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Blue', () => _applySlidePalette('4472C4')),
                _actionItem('Red', () => _applySlidePalette('C00000')),
                _actionItem('Green', () => _applySlidePalette('217346')),
                _actionItem('Dark', () => _applySlidePalette('1F1F1F')),
              ],
            ),
          ]),
        ]);
      case 3:
        final PmlSlideTransition transition = _slides.slide.transition;
        return _withDividers(<Widget>[
          _group('Transition', <Widget>[
            _label('Effect'),
            _transitionDropdown(transition.kind, transition.durationMs),
            _label('Duration'),
            _smallDropdown<int>(
              value: transition.durationMs,
              items: const <int>[300, 500, 700, 1000, 1500, 2000],
              label: (int value) => '${value}ms',
              onChanged: (int value) {
                _applyTransition(transition.kind, value);
              },
            ),
            _iconButton(
              Icons.select_all,
              'Apply to all slides',
              () {
                setState(() => _transitionAll = !_transitionAll);
                _applyTransition(
                  transition.kind,
                  transition.durationMs,
                  applyToAll: _transitionAll,
                );
              },
              active: _transitionAll,
            ),
            _iconButton(Icons.play_arrow, 'Preview transition',
                () => _slides.setSlideTransition(
                      PmlSlideTransition(
                        kind: transition.kind,
                        durationMs: transition.durationMs,
                      ),
                      preview: true,
                    )),
          ]),
          _group('Slide Show', <Widget>[
            _bigButton(Icons.play_circle_outline, 'From start',
                _slideShowFromStart),
            _bigButton(Icons.play_arrow, 'From current', _slideShowFromCurrent),
            _bigButton(Icons.stop_circle_outlined, 'End show', _slides.endShow),
          ]),
        ]);
      case 4:
        return _withDividers(<Widget>[
          _group('Animation', <Widget>[
            _bigMenuButton(
              Icons.animation,
              'Add',
              <PopupMenuEntry<VoidCallback>>[
                _actionItem('Appear',
                    () => _slideAddAnimation(PmlAnimPreset.appear)),
                _actionItem('Fade',
                    () => _slideAddAnimation(PmlAnimPreset.fade)),
                _actionItem('Fly in',
                    () => _slideAddAnimation(PmlAnimPreset.flyIn)),
                _actionItem('Float in',
                    () => _slideAddAnimation(PmlAnimPreset.floatIn)),
                _actionItem('Zoom',
                    () => _slideAddAnimation(PmlAnimPreset.zoom)),
                _actionItem('Bounce',
                    () => _slideAddAnimation(PmlAnimPreset.bounce)),
                _actionItem('Pulse',
                    () => _slideAddAnimation(PmlAnimPreset.pulse)),
              ],
            ),
            _bigButton(Icons.play_arrow, 'Preview', _slidePreviewAnimation),
            _bigButton(Icons.delete_outline, 'Remove',
                _slideRemoveAnimation),
          ]),
          _group('Animation Pane', <Widget>[
            _bigButton(Icons.keyboard_arrow_up, 'Previous animation',
                _slidePreviousAnimation,
                enabled: _hasAnimation),
            _bigButton(Icons.keyboard_arrow_down, 'Next animation',
                _slideNextAnimation,
                enabled: _selectedAnimation != null),
            _iconButton(Icons.play_circle_outline, 'Loop preview',
                _slidePreviewAnimation,
                enabled: _selectedAnimation != null),
          ]),
          _group('Transition', <Widget>[
            _bigButton(Icons.swap_horiz, 'Transitions',
                () => setState(() => _tab = 3)),
          ]),
        ]);
      case 5:
        return _withDividers(<Widget>[
          _group('Start Slide Show', <Widget>[
            _bigButton(Icons.play_circle_outline, 'From beginning',
                _slideShowFromStart),
            _bigButton(Icons.play_arrow, 'From current',
                _slideShowFromCurrent),
            _bigButton(Icons.stop_circle_outlined, 'End show', _slides.endShow),
          ]),
          _group('Options', <Widget>[
            _iconButton(Icons.skip_previous, 'Previous slide',
                _slidePrevious),
            _iconButton(Icons.skip_next, 'Next slide', _slideNext),
            _iconButton(Icons.notes, 'Speaker notes', _slideNotes),
          ]),
        ]);
      case 6:
        return _withDividers(<Widget>[
          _group('Notes', <Widget>[
            _bigButton(Icons.notes, 'Speaker notes', _slideNotes),
            _bigButton(Icons.analytics_outlined, 'Statistics', _wordCount),
          ]),
          _group('Slides', <Widget>[
            _bigButton(Icons.visibility, 'Show/hide slide', _slideToggleHidden),
            _bigButton(Icons.content_copy, 'Duplicate', _slideDuplicate),
          ]),
          _group('Help', <Widget>[
            _bigButton(Icons.keyboard_outlined, 'Shortcuts',
                () => showOfficeShortcuts(context, 'slides')),
            _bigButton(Icons.info_outline, 'About', _aboutEditor),
          ]),
        ]);
      default:
        return const <Widget>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Shared small controls
  // ---------------------------------------------------------------------------

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
    bool enabled = true,
  }) {
    final ThemeData theme = Theme.of(context);
    return IconButton(
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      tooltip: context.tr(tooltip),
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor:
            active ? theme.colorScheme.primaryContainer : Colors.transparent,
        foregroundColor: active
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
      ),
      icon: Icon(icon),
    );
  }

  Widget _bigButton(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool active = false,
    bool enabled = true,
  }) {
    final bool usable = enabled && onPressed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        onTap: usable ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: _bigButtonVisual(
          icon,
          label,
          active: active,
          enabled: usable,
        ),
      ),
    );
  }

  Widget _bigButtonVisual(
    IconData icon,
    String label, {
    bool active = false,
    bool enabled = true,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 54,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            icon,
            size: 17,
            color: enabled
                ? (active
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface)
                : theme.disabledColor,
          ),
          const SizedBox(height: 2),
          Text(
            context.tr(label),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              height: 1.0,
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.disabledColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigMenuButton(
    IconData icon,
    String label,
    List<PopupMenuEntry<VoidCallback>> entries,
  ) {
    return PopupMenuButton<VoidCallback>(
      tooltip: context.tr(label),
      onSelected: (VoidCallback action) => action(),
      itemBuilder: (BuildContext context) => entries,
      child: _bigButtonVisual(icon, label),
    );
  }

  PopupMenuItem<VoidCallback> _actionItem(String label, VoidCallback action) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      height: 32,
      child: Text(context.tr(label), style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        OfficeRibbonControlStrings(context).text(text),
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _smallDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
    double width = 64,
    TextStyle Function(T value)? itemStyle,
    double itemHeight = 48,
  }) {
    final List<T> values = items.contains(value)
        ? items
        : <T>[value, ...items];
    return Container(
      width: width,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          iconSize: 15,
          itemHeight: itemHeight,
          menuMaxHeight: 360,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
          items: <DropdownMenuItem<T>>[
            for (final T item in values)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  label(item),
                  overflow: TextOverflow.ellipsis,
                  style: itemStyle?.call(item),
                ),
              ),
          ],
          onChanged: (T? next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  Widget _fontFamilyDropdown() {
    final String current = _runProps.asciiFont.isEmpty
        ? 'Arial'
        : _runProps.asciiFont;
    final List<String> families = kOfficeFontFamilies.contains(current)
        ? kOfficeFontFamilies
        : <String>[current, ...kOfficeFontFamilies];
    return PopupMenuButton<String>(
      tooltip: context.tr('Font'),
      onSelected: _setFontFamily,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        for (final String family in families)
          PopupMenuItem<String>(
            value: family,
            height: 32,
            child: Text(
              family,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: family, fontSize: 13),
            ),
          ),
      ],
      child: Container(
        width: 122,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                current,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: current, fontSize: 12),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _fontSizeDropdown() {
    final int current = (_runProps.fontSizeHalfPoints / 2).round();
    return _smallDropdown<int>(
      value: current.clamp(8, 96),
      items: kOfficeFontSizes,
      label: (int value) => '$value',
      width: 58,
      onChanged: _setFontSize,
    );
  }

  Widget _sheetFontSizeDropdown() {
    final int current = _cell.fontSize.round();
    return _smallDropdown<int>(
      value: current.clamp(8, 96),
      items: kOfficeFontSizes,
      label: (int value) => '$value',
      width: 58,
      onChanged: (int value) => _sheetStyle((SmlCell cell) {
        cell.fontSize = value.toDouble();
      }),
    );
  }

  Widget _slideFontSizeDropdown() {
    final double size = _shape?.fontSizePt ?? 18;
    final int current = size > 0 ? size.round().clamp(8, 96) : 18;
    return _smallDropdown<int>(
      value: current,
      items: kOfficeFontSizes,
      label: (int value) => '$value',
      width: 58,
      onChanged: (int value) =>
          _slides.updateSelected(fontSizePt: value.toDouble()),
    );
  }

  Widget _alignControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _iconButton(
          Icons.format_align_left,
          'Align left',
          () => _align(WmlJustification.left),
          active: _paraProps?.justification == WmlJustification.left,
        ),
        _iconButton(
          Icons.format_align_center,
          'Align center',
          () => _align(WmlJustification.center),
          active: _paraProps?.justification == WmlJustification.center,
        ),
        _iconButton(
          Icons.format_align_right,
          'Align right',
          () => _align(WmlJustification.right),
          active: _paraProps?.justification == WmlJustification.right,
        ),
        _iconButton(
          Icons.format_align_justify,
          'Justify',
          () => _align(WmlJustification.justify),
          active: _paraProps?.justification == WmlJustification.justify,
        ),
      ],
    );
  }

  Widget _underlineControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _iconButton(
          Icons.format_underlined,
          'Underline (Ctrl+U)',
          () => _toggleUnderline(WmlUnderline.single),
          active: _runProps.underline != WmlUnderline.none,
        ),
        PopupMenuButton<WmlUnderline>(
          tooltip: OfficeRibbonControlStrings(context).text('Underline style'),
          padding: EdgeInsets.zero,
          iconSize: 14,
          onSelected: _toggleUnderline,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<WmlUnderline>>[
            for (final WmlUnderline style in WmlUnderline.values)
              PopupMenuItem<WmlUnderline>(
                value: style,
                height: 30,
                child: Text(OfficeRibbonControlStrings(context).text(switch (style) {
                  WmlUnderline.none => 'None',
                  WmlUnderline.single => 'Single',
                  WmlUnderline.double => 'Double',
                  WmlUnderline.dotted => 'Dotted',
                  WmlUnderline.wavy => 'Wavy',
                }), style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _vertAlignControl() {
    return PopupMenuButton<WmlVertAlign>(
      tooltip: OfficeRibbonControlStrings(context).text('Superscript / subscript'),
      icon: const Icon(Icons.superscript, size: 17),
      iconSize: 17,
      padding: EdgeInsets.zero,
      onSelected: (WmlVertAlign align) {
        _wordRun((WmlRunProps props) {
          props.vertAlign =
              props.vertAlign == align ? WmlVertAlign.baseline : align;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<WmlVertAlign>>[
        PopupMenuItem<WmlVertAlign>(
          value: WmlVertAlign.superscript,
          child: Text(OfficeRibbonControlStrings(context).text('Superscript'), style: const TextStyle(fontSize: 12)),
        ),
        PopupMenuItem<WmlVertAlign>(
          value: WmlVertAlign.subscript,
          child: Text(OfficeRibbonControlStrings(context).text('Subscript'), style: const TextStyle(fontSize: 12)),
        ),
        PopupMenuItem<WmlVertAlign>(
          value: WmlVertAlign.baseline,
          child: Text(OfficeRibbonControlStrings(context).text('Baseline'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _lineSpacingControl() {
    return PopupMenuButton<double>(
      tooltip: OfficeRibbonControlStrings(context).text('Line spacing'),
      icon: const Icon(Icons.format_line_spacing, size: 17),
      iconSize: 17,
      padding: EdgeInsets.zero,
      onSelected: (double value) {
        _wordPara((WmlParagraphProps props) {
          props.lineSpacing = value;
          props.lineSpacingRule = WmlLineSpacingRule.auto;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
        for (final double value in <double>[1.0, 1.15, 1.5, 2.0, 2.5, 3.0])
          PopupMenuItem<double>(
            value: value,
            height: 30,
            child: Text(
              value == 1.0 ? OfficeRibbonControlStrings(context).text('Single') : OfficeRibbonControlStrings(context).lines(value),
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _wordDirectionControl() {
    return PopupMenuButton<bool>(
      tooltip: OfficeRibbonControlStrings(context).text('Text direction'),
      icon: const Icon(Icons.format_textdirection_l_to_r, size: 17),
      iconSize: 17,
      padding: EdgeInsets.zero,
      onSelected: (bool rtl) => _word.setParagraphDirection(rtl: rtl),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
        PopupMenuItem<bool>(
          value: false,
          child: Text(OfficeRibbonControlStrings(context).text('Left-to-right'), style: const TextStyle(fontSize: 12)),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: Text(OfficeRibbonControlStrings(context).text('Right-to-left'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _wordStyleDropdown() {
    final int heading = _word.activeHeadingLevel;
    final String? styleId = _paraProps?.styleId;
    const Map<String, String> labels = <String, String>{
      'Normal': 'Normal',
      'Title': 'Title',
      'Subtitle': 'Subtitle',
      'Quote': 'Quote',
      'IntenseQuote': 'Intense Quote',
      'Heading1': 'Heading 1',
      'Heading2': 'Heading 2',
      'Heading3': 'Heading 3',
    };
    final String current = heading > 0
        ? 'Heading $heading'
        : (styleId != null && labels.containsKey(styleId)
            ? labels[styleId]!
            : 'Normal');
    final List<String> values = <String>[
      'Normal',
      'Title',
      'Subtitle',
      'Heading 1',
      'Heading 2',
      'Heading 3',
      'Heading 4',
      'Heading 5',
      'Heading 6',
      'Quote',
    ];
    return _smallDropdown<String>(
      value: values.contains(current) ? current : 'Normal',
      items: values,
      label: (String value) => context.tr(value),
      width: 118,
      onChanged: (String value) {
        if (value.startsWith('Heading ')) {
          _word.applyHeading(int.parse(value.substring(8)));
        } else {
          const Map<String, String> ids = <String, String>{
            'Normal': 'Normal',
            'Title': 'Title',
            'Subtitle': 'Subtitle',
            'Quote': 'Quote',
          };
          _word.applyStyle(ids[value] ?? value);
        }
      },
    );
  }

  Widget _colorButton(
    IconData icon,
    String tooltip,
    String currentColor,
    ValueChanged<String> onChanged, {
    bool allowNone = false,
  }) {
    return InkWell(
      onTap: () async {
        final String? picked = await showOfficeColorPicker(
          context,
          initial: currentColor,
          allowNone: allowNone,
          noneLabel: context.tr('No color'),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: context.tr(tooltip),
        child: Container(
          width: 28,
          height: 26,
          padding: const EdgeInsets.only(top: 2, bottom: 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(icon, size: 15),
              Container(
                height: 2.5,
                width: 18,
                decoration: BoxDecoration(
                  color: _colorFromHex(currentColor),
                  borderRadius: BorderRadius.circular(1),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transitionDropdown(PmlTransitionKind kind, int durationMs) {
    const List<PmlTransitionKind> kinds = <PmlTransitionKind>[
      PmlTransitionKind.none,
      PmlTransitionKind.fade,
      PmlTransitionKind.push,
      PmlTransitionKind.wipe,
      PmlTransitionKind.split,
      PmlTransitionKind.uncover,
      PmlTransitionKind.cover,
      PmlTransitionKind.dissolve,
      PmlTransitionKind.zoom,
      PmlTransitionKind.morph,
    ];
    return _smallDropdown<PmlTransitionKind>(
      value: kinds.contains(kind) ? kind : PmlTransitionKind.none,
      items: kinds,
      label: _transitionLabel,
      width: 110,
      onChanged: (PmlTransitionKind value) =>
          _applyTransition(value, durationMs),
    );
  }

  String _transitionLabel(PmlTransitionKind value) {
    const Map<PmlTransitionKind, String> names =
        <PmlTransitionKind, String>{
      PmlTransitionKind.none: 'None',
      PmlTransitionKind.fade: 'Fade',
      PmlTransitionKind.push: 'Push',
      PmlTransitionKind.wipe: 'Wipe',
      PmlTransitionKind.split: 'Split',
      PmlTransitionKind.uncover: 'Uncover',
      PmlTransitionKind.cover: 'Cover',
      PmlTransitionKind.dissolve: 'Dissolve',
      PmlTransitionKind.zoom: 'Zoom',
      PmlTransitionKind.morph: 'Morph',
    };
    return context.tr(names[value] ?? value.name);
  }

  Color _colorFromHex(String hex) {
    final String normalized = hex.trim().toUpperCase().replaceAll('#', '');
    if (normalized.length != 6) return Colors.transparent;
    final int? value = int.tryParse(normalized, radix: 16);
    return value == null ? Colors.transparent : Color(0xFF000000 | value);
  }

  // ---------------------------------------------------------------------------
  // Common actions
  // ---------------------------------------------------------------------------

  bool get _canMutate => _c.config.allowsMutation;

  /// Entry point used by the native macOS menu bar.
  void perform(OfficeEditorAction action) {
    switch (action) {
      case OfficeEditorAction.save:
        widget.onSave();
      case OfficeEditorAction.close:
        widget.onClose();
      case OfficeEditorAction.undo:
        _c.undo();
      case OfficeEditorAction.redo:
        _c.redo();
      case OfficeEditorAction.cut:
        _copyOrCut(cut: true);
      case OfficeEditorAction.copy:
        _copyOrCut(cut: false);
      case OfficeEditorAction.paste:
        _paste();
      case OfficeEditorAction.selectAll:
        _selectAll();
      case OfficeEditorAction.bold:
        if (widget.kind == OfficeEditorKind.word) _toggleBold();
      case OfficeEditorAction.italic:
        if (widget.kind == OfficeEditorKind.word) _toggleItalic();
      case OfficeEditorAction.underline:
        if (widget.kind == OfficeEditorKind.word) {
          _toggleUnderline(WmlUnderline.single);
        }
      case OfficeEditorAction.find:
        widget.onFind();
      case OfficeEditorAction.replace:
        _c.requestReplace();
      case OfficeEditorAction.readingView:
        _toggleReadingMode();
      case OfficeEditorAction.keyboardShortcuts:
        showOfficeShortcuts(
          context,
          switch (widget.kind) {
            OfficeEditorKind.word => 'word',
            OfficeEditorKind.sheet => 'sheet',
            OfficeEditorKind.slides => 'slides',
            OfficeEditorKind.unsupported => 'office',
          },
        );
      case OfficeEditorAction.about:
        _aboutEditor();
      case OfficeEditorAction.font:
        if (widget.kind == OfficeEditorKind.word) _wordFontDialog();
      case OfficeEditorAction.paragraph:
        if (widget.kind == OfficeEditorKind.word) _wordParagraphDialog();
      case OfficeEditorAction.insertTable:
        if (widget.kind == OfficeEditorKind.word) {
          _insertTable();
        } else if (widget.kind == OfficeEditorKind.sheet) {
          _sheetAddTable();
        }
      case OfficeEditorAction.insertHyperlink:
        if (widget.kind == OfficeEditorKind.word) _insertHyperlink();
      case OfficeEditorAction.insertPicture:
        if (widget.kind == OfficeEditorKind.word) {
          _wordInsertPicture();
        } else if (widget.kind == OfficeEditorKind.slides) {
          _slideInsertPicture();
        }
      case OfficeEditorAction.insertComment:
        if (widget.kind == OfficeEditorKind.word) _insertComment();
      case OfficeEditorAction.pageBreak:
        if (widget.kind == OfficeEditorKind.word) _pageBreak();
      case OfficeEditorAction.sectionBreak:
        if (widget.kind == OfficeEditorKind.word) _sectionBreak();
      case OfficeEditorAction.tableOfContents:
        if (widget.kind == OfficeEditorKind.word) _insertToc();
      case OfficeEditorAction.header:
        if (widget.kind == OfficeEditorKind.word) _beginHeader();
      case OfficeEditorAction.footer:
        if (widget.kind == OfficeEditorKind.word) _beginFooter();
      case OfficeEditorAction.pageNumber:
        if (widget.kind == OfficeEditorKind.word) _insertPageNumber();
      case OfficeEditorAction.watermark:
        if (widget.kind == OfficeEditorKind.word) _watermark();
      case OfficeEditorAction.pageSetup:
        if (widget.kind == OfficeEditorKind.word) _pageSetupMenu();
      case OfficeEditorAction.wordCount:
        _wordCount();
      case OfficeEditorAction.trackChanges:
        if (widget.kind == OfficeEditorKind.word) _toggleTrackChanges();
      case OfficeEditorAction.protect:
        if (widget.kind == OfficeEditorKind.word) _toggleProtect();
      case OfficeEditorAction.rowsAbove:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.insertSheetRows(after: false);
        }
      case OfficeEditorAction.rowsBelow:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.insertSheetRows(after: true);
        }
      case OfficeEditorAction.columnsLeft:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.insertSheetCols(after: false);
        }
      case OfficeEditorAction.columnsRight:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.insertSheetCols(after: true);
        }
      case OfficeEditorAction.deleteRows:
        if (widget.kind == OfficeEditorKind.sheet) _sheetDeleteRows();
      case OfficeEditorAction.deleteColumns:
        if (widget.kind == OfficeEditorKind.sheet) _sheetDeleteCols();
      case OfficeEditorAction.sortAscending:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.sortSelection(ascending: true);
        }
      case OfficeEditorAction.sortDescending:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.sortSelection(ascending: false);
        }
      case OfficeEditorAction.filter:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.filterSelection();
        }
      case OfficeEditorAction.clearFilter:
        if (widget.kind == OfficeEditorKind.sheet) _sheet.clearFilter();
      case OfficeEditorAction.freezePanes:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.toggleFreezePanes();
        }
      case OfficeEditorAction.protectSheet:
        if (widget.kind == OfficeEditorKind.sheet) _sheetProtect();
      case OfficeEditorAction.sheetComment:
        if (widget.kind == OfficeEditorKind.sheet) _sheetComment();
      case OfficeEditorAction.fillColor:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheetFill();
        } else if (widget.kind == OfficeEditorKind.slides) {
          _slideFill();
        }
      case OfficeEditorAction.fontColor:
        if (widget.kind == OfficeEditorKind.sheet) _sheetFontColor();
      case OfficeEditorAction.clearFormatting:
        if (widget.kind == OfficeEditorKind.word) {
          _clearWordFormat();
        } else if (widget.kind == OfficeEditorKind.sheet) {
          _sheetClearFormat();
        }
      case OfficeEditorAction.mergeCells:
        if (widget.kind == OfficeEditorKind.sheet) {
          _sheet.toggleMergeAndCenter();
        }
      case OfficeEditorAction.unmergeCells:
        if (widget.kind == OfficeEditorKind.sheet) _sheet.unmergeCells();
      case OfficeEditorAction.newSlide:
        if (widget.kind == OfficeEditorKind.slides) _slideNew();
      case OfficeEditorAction.duplicateSlide:
        if (widget.kind == OfficeEditorKind.slides) _slideDuplicate();
      case OfficeEditorAction.deleteSlide:
        if (widget.kind == OfficeEditorKind.slides) _slideDelete();
      case OfficeEditorAction.textBox:
        if (widget.kind == OfficeEditorKind.slides) _slideTextBox();
      case OfficeEditorAction.rectangle:
        if (widget.kind == OfficeEditorKind.slides) {
          _slideAddShape(PmlShapePreset.rect);
        }
      case OfficeEditorAction.ellipse:
        if (widget.kind == OfficeEditorKind.slides) {
          _slideAddShape(PmlShapePreset.ellipse);
        }
      case OfficeEditorAction.line:
        if (widget.kind == OfficeEditorKind.slides) {
          _slideAddShape(PmlShapePreset.connector);
        }
      case OfficeEditorAction.slideTable:
        if (widget.kind == OfficeEditorKind.slides) _slideInsertTable();
      case OfficeEditorAction.slidePicture:
        if (widget.kind == OfficeEditorKind.slides) _slideInsertPicture();
      case OfficeEditorAction.speakerNotes:
        if (widget.kind == OfficeEditorKind.slides) _slideNotes();
      case OfficeEditorAction.slideShow:
        if (widget.kind == OfficeEditorKind.slides) _slideShowFromStart();
      case OfficeEditorAction.transitions:
        if (widget.kind == OfficeEditorKind.slides) setState(() => _tab = 3);
      case OfficeEditorAction.animations:
        if (widget.kind == OfficeEditorKind.slides) setState(() => _tab = 4);
      case OfficeEditorAction.background:
        if (widget.kind == OfficeEditorKind.slides) _slideBackground();
      case OfficeEditorAction.textColor:
        if (widget.kind == OfficeEditorKind.slides) _slideTextColor();
      case OfficeEditorAction.shapeFill:
        if (widget.kind == OfficeEditorKind.slides) _slideFill();
    }
  }

  Future<void> _copyOrCut({required bool cut}) async {
    if (cut) {
      await _c.cutToClipboard();
    } else {
      await _c.copyToClipboard();
    }
  }

  Future<void> _copy() => _c.copyToClipboard();
  Future<void> _cut() => _c.cutToClipboard();
  Future<void> _paste() => _c.pasteFromClipboard();
  void _selectAll() => _c.selectAll();

  void _setConfig({
    bool? showRulers,
    bool? showFormulaBar,
    bool? showGridHeaders,
    bool? showGridlines,
    bool? showSlideHandles,
    bool? showNotesPane,
  }) {
    final OfficeSurfaceConfig next = widget.config.copyWith(
      showRulers: showRulers,
      showNotesPane: showNotesPane,
      showFormulaBar: showFormulaBar,
      showGridHeaders: showGridHeaders,
      showGridlines: showGridlines,
      showSlideHandles: showSlideHandles,
    );
    widget.onConfigChanged(next);
  }

  void _toggleReadingMode() {
    final OfficeInteractionMode next =
        _c.mode == OfficeInteractionMode.editing
            ? OfficeInteractionMode.viewing
            : OfficeInteractionMode.editing;
    widget.onConfigChanged(widget.config.copyWith(mode: next));
  }

  void _aboutEditor() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.tr('Office editor')),
        content: Text(
          context.tr(
            'Word, spreadsheet and presentation editing is powered by the '
            'open-source Quds Office engine (MIT).\n\n'
            'The editor supports OOXML documents (.docx, .xlsx, .pptx). '
            'Save writes back to the original file.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _wordCount() async {
    final OfficeTextStats stats = _c.documentStats;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.tr('Statistics')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _statRow('Words', stats.words),
            _statRow('Characters (with spaces)', stats.characters),
            _statRow('Characters (no spaces)', stats.charactersNoSpaces),
            _statRow('Paragraphs', stats.paragraphs),
            if (stats.pages > 0) _statRow('Pages', stats.pages),
            if (stats.cells > 0) _statRow('Cells', stats.cells),
            if (stats.slides > 0) _statRow('Slides', stats.slides),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 210, child: Text(context.tr(label))),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Word actions
  // ---------------------------------------------------------------------------

  void _wordRun(void Function(WmlRunProps props) update) {
    _word.applyRunFormat(update);
  }

  void _wordPara(void Function(WmlParagraphProps props) update) {
    _word.applyParagraphFormat(update);
  }

  void _toggleBold() => _wordRun((WmlRunProps p) => p.bold = !p.bold);

  void _toggleItalic() => _wordRun((WmlRunProps p) => p.italic = !p.italic);

  void _toggleStrike() => _wordRun((WmlRunProps p) => p.strike = !p.strike);

  void _toggleUnderline(WmlUnderline style) {
    _wordRun((WmlRunProps p) {
      p.underline = p.underline == style ? WmlUnderline.none : style;
    });
  }

  void _setFontFamily(String family) {
    _wordRun((WmlRunProps p) {
      p.asciiFont = family;
      p.csFont = family;
    });
  }

  void _setFontSize(int size) {
    _wordRun((WmlRunProps p) => p.fontSizeHalfPoints = size * 2);
  }

  void _setTextColor(String color) {
    _wordRun((WmlRunProps p) => p.color = color.isEmpty ? '000000' : color);
  }

  void _setHighlight(String color) {
    _wordRun((WmlRunProps p) => p.highlight = color.isEmpty ? null : color);
  }

  void _clearWordFormat() {
    _wordRun((WmlRunProps p) {
      p.bold = false;
      p.italic = false;
      p.underline = WmlUnderline.none;
      p.strike = false;
      p.color = '000000';
      p.highlight = null;
      p.vertAlign = WmlVertAlign.baseline;
      p.fontSizeHalfPoints = 22;
      p.asciiFont = 'Arial';
      p.csFont = 'Arial';
    });
  }

  void _align(WmlJustification align) {
    _wordPara((WmlParagraphProps p) => p.justification = align);
  }

  void _toggleList(bool numbered) => _word.toggleList(numbered: numbered);

  void _nudgeIndent(double delta) {
    final double left = _paraProps?.indent.left ?? 0;
    _word.setParagraphIndent(left: (left + delta).clamp(0, 720));
  }

  void _spaceBefore(double value) {
    _wordPara((WmlParagraphProps p) {
      p.spacingBefore = value;
      p.explicitSpacingBefore = value > 0;
    });
  }

  void _spaceAfter(double value) {
    _wordPara((WmlParagraphProps p) {
      p.spacingAfter = value;
      p.explicitSpacingAfter = value > 0;
    });
  }

  void _wordFontDialog() async {
    final WordFontChoice? choice = await showWordFontDialog(
      context,
      current: _runProps,
    );
    if (choice == null) return;
    _wordRun((WmlRunProps p) {
      p.asciiFont = choice.family;
      p.csFont = choice.family;
      p.fontSizeHalfPoints = choice.sizePt * 2;
      p.bold = choice.bold;
      p.italic = choice.italic;
      p.underline = choice.underline;
      p.strike = choice.strike;
      p.color = choice.color;
      p.highlight = choice.highlight;
      p.vertAlign = choice.vertAlign;
    });
  }

  void _wordParagraphDialog() async {
    final WmlParagraphProps? current = _paraProps;
    if (current == null) return;
    final WordParagraphChoice? choice = await showWordParagraphDialog(
      context,
      current: current,
    );
    if (choice == null) return;
    _wordPara((WmlParagraphProps p) {
      p.justification = choice.align;
      p.indent = WmlIndent(
        left: choice.left,
        right: choice.right,
        firstLine: choice.firstLine,
        hanging: choice.hanging,
      );
      p.spacingBefore = choice.spacingBefore;
      p.spacingAfter = choice.spacingAfter;
      p.lineSpacing = choice.lineSpacing;
      p.lineSpacingRule = choice.lineSpacingRule;
      p.dropCapLines = choice.dropCapLines;
      p.borderColor =
          choice.borderColor.isEmpty ? null : choice.borderColor;
      p.tabs = <WmlTabStop>[
        for (final double position in choice.tabStops)
          WmlTabStop(position: position),
      ];
      p.keepTogether = choice.keepTogether;
      p.pageBreakBefore = choice.pageBreakBefore;
    });
  }

  Future<void> _wordInsertPicture() async {
    final PlatformFile? file = await _pickImage();
    if (file?.bytes == null) return;
    _word.insertPicture(
      OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: file!.name,
        imageBytes: file.bytes,
        width: 360,
        height: 200,
      ),
    );
  }

  Future<PlatformFile?> _pickImage() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final PlatformFile file = result.files.first;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Could not read the selected image.'))),
        );
      }
      return null;
    }
    if (file.bytes!.length > 32 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Images larger than 32 MB are not supported.'))),
        );
      }
      return null;
    }
    return file;
  }

  void _insertTable() async {
    final ({int rows, int columns})? result =
        await showInsertTableDialog(context);
    if (result == null) return;
    _word.insertTable(rows: result.rows, columns: result.columns);
  }

  void _insertHyperlink() async {
    final ({String text, String url})? result =
        await showHyperlinkDialog(context);
    if (result == null) return;
    _word.insertHyperlink(
      text: result.text.isEmpty ? result.url : result.text,
      target: result.url,
    );
  }

  void _insertComment() async {
    final ({String text, String author})? result =
        await showCommentDialog(context);
    if (result == null) return;
    _word.insertComment(text: result.text, author: result.author);
  }

  Future<void> _insertNote({required bool endnote}) async {
    if (!_canMutate) return;
    final WordEditorController controller = _word;
    final String? text = await showOfficePromptDialog(
      context,
      title: context.tr(endnote ? 'Insert endnote' : 'Insert footnote'),
      label: context.tr('Text'),
      multiline: true,
      trimResult: false,
      confirmLabel: context.tr('Insert'),
    );
    if (!mounted || text == null || !_canMutate ||
        !identical(controller, widget.controller)) {
      return;
    }
    controller.insertFootnote(text: text, endnote: endnote);
    // Show the notes pane, where the new note can be edited further.
    if (!widget.config.showNotesPane) {
      _setConfig(showNotesPane: true);
    }
  }

  void _pageBreak() => _word.insertPageBreak();

  void _sectionBreak() => _word.insertSectionBreak();

  void _columnBreak() => _word.insertColumnBreak();

  void _insertToc() => _word.insertTableOfContents();

  void _beginHeader() {
    if (_word.isEditingHeaderFooter) {
      _word.endHeaderFooterEdit();
    } else {
      _word.beginHeaderFooterEdit(_word.visiblePageIndex, footer: false);
    }
  }

  void _beginFooter() {
    if (_word.isEditingHeaderFooter) {
      _word.endHeaderFooterEdit();
    } else {
      _word.beginHeaderFooterEdit(_word.visiblePageIndex, footer: true);
    }
  }

  void _insertPageNumber() => _word.insertField(WmlFieldKind.page);

  void _watermark() async {
    final String? text = await showOfficePromptDialog(
      context,
      title: context.tr('Watermark'),
      label: context.tr('Text'),
      helper: 'Leave empty to remove the watermark',
      confirmLabel: context.tr('Apply'),
    );
    if (text == null) return;
    _word.setWatermark(text);
  }

  void _paragraphShading() async {
    final String? picked = await showOfficeColorPicker(
      context,
      initial: '',
      allowNone: true,
      noneLabel: context.tr('No shading'),
    );
    if (picked == null) return;
    _word.setParagraphShading(picked.isEmpty ? null : picked);
  }

  void _setMargins(WmlPageMargins margins) => _word.setPageMargins(margins);

  void _customMargins() async {
    final WmlPageMargins current = _word.sectionAtCaret.margins;
    final ({double top, double bottom, double left, double right})? result =
        await showPageMarginsDialog(context, current: current);
    if (result == null) return;
    _word.setPageMargins(WmlPageMargins(
      top: result.top,
      bottom: result.bottom,
      left: result.left,
      right: result.right,
      header: current.header,
      footer: current.footer,
    ));
  }

  void _pageSetupMenu() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: Text(context.tr('Page Setup')),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _customMargins();
            },
            child: Text(context.tr('Margins')),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _word.setPageLandscape(!_word.isPageLandscape);
            },
            child: Text(
              _word.isPageLandscape
                  ? context.tr('Portrait')
                  : context.tr('Landscape'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _watermark();
            },
            child: Text(context.tr('Watermark')),
          ),
        ],
      ),
    );
  }

  void _toggleTrackChanges() {
    setState(() => _trackChanges = !_trackChanges);
    _word.setTrackRevisions(_trackChanges);
  }

  void _toggleProtect() async {
    if (_wordProtected) {
      _word.setRestrictEditing(false);
      setState(() => _wordProtected = false);
      return;
    }
    final bool confirmed = await showOfficeConfirm(
      context,
      title: context.tr('Protect document'),
      message: context.tr('Prevent further edits to this document?'),
      confirmLabel: context.tr('Protect'),
    );
    if (!confirmed) return;
    _word.setRestrictEditing(true);
    setState(() => _wordProtected = true);
  }

  void _spellCheck() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'Spell checking uses the host integration. No spell-check provider '
            'is configured in this build.',
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sheet actions
  // ---------------------------------------------------------------------------

  void _sheetStyle(void Function(SmlCell cell) update) {
    if (!_canMutate) return;
    final SmlRange range = _sheet.selection.range;
    final _CellStyleCommand command = _CellStyleCommand(
      controller: _sheet,
      range: range,
      update: update,
    );
    _sheet.commands.commit(command);
    _sheet.refresh();
  }

  void _sheetBold() {
    final bool bold = !_cell.fontBold;
    _sheetStyle((SmlCell cell) => cell.fontBold = bold);
  }

  void _sheetAlign(SmlHAlign align) {
    _sheetStyle((SmlCell cell) => cell.horizontalAlign = align);
  }

  Future<void> _sheetFill() async {
    final String? picked = await showOfficeColorPicker(
      context,
      initial: _cell.fillRgb,
      allowNone: true,
      noneLabel: context.tr('No fill'),
    );
    if (picked == null) return;
    _sheetFillValue(picked);
  }

  void _sheetFillValue(String color) {
    _sheetStyle((SmlCell cell) => cell.fillRgb = color);
  }

  Future<void> _sheetFontColor() async {
    final String? picked = await showOfficeColorPicker(
      context,
      initial: _cell.fontRgb,
    );
    if (picked == null) return;
    _sheetFontColorValue(picked);
  }

  void _sheetFontColorValue(String color) {
    _sheetStyle((SmlCell cell) => cell.fontRgb = color);
  }

  void _sheetClearFormat() {
    _sheetStyle((SmlCell cell) {
      cell.fontBold = false;
      cell.fontSize = 11;
      cell.horizontalAlign = SmlHAlign.general;
      cell.fillRgb = '';
      cell.fontRgb = '';
      cell.styleIndex = 0;
    });
  }

  void _sheetDeleteRows() {
    final SmlRange range = _sheet.selection.range;
    _sheet.deleteSheetRows(count: range.maxRow - range.minRow + 1);
  }

  void _sheetDeleteCols() {
    final SmlRange range = _sheet.selection.range;
    _sheet.deleteSheetCols(count: range.maxCol - range.minCol + 1);
  }

  void _sheetAddTable() {
    _sheet.addTable(range: _sheet.selection.range);
  }

  void _sheetComment() async {
    final ({String text, String author})? result =
        await showCommentDialog(context);
    if (result == null) return;
    _sheet.setCellComment(
      result.text,
      ref: _sheet.activeCell,
      author: result.author,
    );
  }

  Future<void> _sheetProtect() async {
    final String? password = await showOfficePromptDialog(
      context,
      title: context.tr('Protect sheet'),
      label: context.tr('Password (optional)'),
      confirmLabel: context.tr('Protect'),
    );
    if (password == null) return;
    _sheet.protectSheet(enabled: true, password: password);
  }

  Future<void> _sheetUnprotect() async {
    final String? password = await showOfficePromptDialog(
      context,
      title: context.tr('Unprotect sheet'),
      label: context.tr('Password'),
      confirmLabel: context.tr('Unprotect'),
    );
    if (password == null) return;
    _sheet.protectSheet(enabled: false, password: password);
  }

  // ---------------------------------------------------------------------------
  // Slide actions
  // ---------------------------------------------------------------------------

  int get _slideCount => _slides.presentation.slides.length;

  PmlShapeAnimation? get _selectedAnimation => _slides.selectedAnimation;

  bool get _hasAnimation =>
      _slides.slide.animations.isNotEmpty;

  void _slideNew() {
    if (!_canMutate) return;
    final List<PmlSlide> slides = _slides.presentation.slides;
    final int id = slides.fold<int>(
          256,
          (int max, PmlSlide slide) => slide.id > max ? slide.id : max,
        ) +
        1;
    final int index = (_slides.activeSlideIndex + 1).clamp(0, slides.length);
    final _InsertSlideCommand command = _InsertSlideCommand(
      controller: _slides,
      slide: PmlSlide(id: id),
      index: index,
    );
    _slides.commands.commit(command);
    _slides.refresh();
  }

  void _slideDuplicate() {
    _slides.duplicateSlide(_slides.activeSlideIndex);
  }

  Future<void> _slideDelete() async {
    if (_slideCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('A presentation needs at least one slide.'))),
      );
      return;
    }
    final bool confirmed = await showOfficeConfirm(
      context,
      title: context.tr('Delete slide'),
      message: '${context.tr('Delete slide')} ${_slides.activeSlideIndex + 1}?',
      confirmLabel: context.tr('Delete'),
      destructive: true,
    );
    if (!confirmed) return;
    final _DeleteSlideCommand command = _DeleteSlideCommand(
      controller: _slides,
      index: _slides.activeSlideIndex,
    );
    _slides.commands.commit(command);
    _slides.refresh();
  }

  void _slideTextBox() async {
    final String? text = await showOfficePromptDialog(
      context,
      title: context.tr('Insert text box'),
      label: context.tr('Text'),
      multiline: true,
      confirmLabel: context.tr('Insert'),
    );
    if (text == null) return;
    _slideAddShape(
      PmlShapePreset.rect,
      text: text,
      fill: '',
      textColor: '000000',
      name: 'Text Box',
    );
  }

  void _slideAddShape(
    PmlShapePreset preset, {
    String text = '',
    String? fill,
    String textColor = 'FFFFFF',
    String? name,
  }) {
    if (!_canMutate) return;
    final PmlSlide slide = _slides.slide;
    final int id = slide.shapes.fold<int>(
          2,
          (int max, PmlShape shape) => shape.id > max ? shape.id : max,
        ) +
        1;
    final PmlShape shape = PmlShape(
      id: id,
      name: name ?? preset.name,
      preset: preset,
      transform: const PmlTransform(
        x: 1200000,
        y: 1200000,
        cx: 3800000,
        cy: 1700000,
      ),
      text: text,
      fillColor: fill ?? (preset == PmlShapePreset.connector ? '' : '4472C4'),
      textColor: textColor,
      fontSizePt: 18,
      textAlign: PmlTextAlign.center,
    );
    _slides.commands.commit(_AddShapeCommand(_slides, shape));
    _slides.refresh();
  }

  Future<void> _slideInsertPicture() async {
    if (!_canMutate) return;
    final PlatformFile? file = await _pickImage();
    if (file?.bytes == null) return;
    final PmlSlide slide = _slides.slide;
    final int id = slide.shapes.fold<int>(
          2,
          (int max, PmlShape shape) => shape.id > max ? shape.id : max,
        ) +
        1;
    final PmlShape shape = PmlShape(
      id: id,
      name: file!.name,
      preset: PmlShapePreset.rect,
      transform: const PmlTransform(
        x: 1200000,
        y: 1200000,
        cx: 4572000,
        cy: 2571750,
      ),
      fillColor: '',
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: file.name,
        imageBytes: file.bytes,
        width: 360,
        height: 203,
      ),
    );
    _slides.commands.commit(_AddShapeCommand(_slides, shape));
    _slides.refresh();
  }

  void _slideInsertTable() async {
    final ({int rows, int columns})? result =
        await showInsertTableDialog(context);
    if (result == null) return;
    _slides.insertTable(rows: result.rows, cols: result.columns);
  }

  Future<void> _slideTextColor() async {
    final PmlShape? shape = _shape;
    if (shape == null) return;
    final String? picked = await showOfficeColorPicker(
      context,
      initial: shape.textColor,
    );
    if (picked == null) return;
    _slideTextColorValue(picked);
  }

  void _slideTextColorValue(String color) {
    final PmlShape? shape = _shape;
    if (shape == null || !_canMutate) return;
    _slides.commands.commit(_SlideTextColorCommand(_slides, shape, color));
    _slides.refresh();
  }

  Future<void> _slideFill() async {
    final PmlShape? shape = _shape;
    if (shape == null) return;
    final String? picked = await showOfficeColorPicker(
      context,
      initial: shape.fillColor,
      allowNone: true,
      noneLabel: context.tr('No fill'),
    );
    if (picked == null) return;
    _slideFillValue(picked);
  }

  void _slideFillValue(String color) {
    _slides.updateSelected(fillColor: color);
  }

  Future<void> _slideBackground() async {
    final String? picked = await showOfficeColorPicker(
      context,
      initial: _slides.presentation.master.background,
    );
    if (picked == null) return;
    _slides.applyMasterBackground(picked);
  }

  void _applySlidePalette(String color) {
    final PmlShape? shape = _shape;
    if (shape != null) _slideFillValue(color);
    _slides.applyMasterBackground(color);
  }

  void _slideAlign(PmlTextAlign align) {
    _slides.setSelectedTextAlign(align);
  }

  void _applyTransition(
    PmlTransitionKind kind,
    int durationMs, {
    bool? applyToAll,
  }) {
    _slides.setSlideTransition(
      PmlSlideTransition(kind: kind, durationMs: durationMs),
      applyToAll: applyToAll ?? _transitionAll,
      preview: false,
    );
  }

  void _slideShowFromStart() => _slides.startShow(from: 0);
  void _slideShowFromCurrent() =>
      _slides.startShow(from: _slides.activeSlideIndex);

  void _slideNotes() async {
    final String? text = await showOfficePromptDialog(
      context,
      title: context.tr('Speaker Notes'),
      label: context.tr('Notes'),
      initial: _slides.speakerNotes,
      multiline: true,
      confirmLabel: context.tr('Apply'),
    );
    if (text == null) return;
    _slides.setSpeakerNotes(text);
  }

  void _slideToggleHidden() {
    _slides.toggleSlideHidden(_slides.activeSlideIndex);
  }

  void _slideAddAnimation(PmlAnimPreset preset) {
    if (_shape == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Select a shape first.'))),
      );
      return;
    }
    _slides.addShapeAnimation(preset);
  }

  void _slideRemoveAnimation() {
    final int? index = _slides.selectedAnimationIndex;
    if (index == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Select an animation first.'))),
      );
      return;
    }
    _slides.removeShapeAnimation(index);
  }

  void _slidePreviewAnimation() {
    final int? index = _slides.selectedAnimationIndex;
    if (index == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Select an animation first.'))),
      );
      return;
    }
    _slides.previewAnimationAt(index);
  }

  void _slidePreviousAnimation() {
    final int? index = _slides.selectedAnimationIndex;
    if (index == null || index <= 0) return;
    _slides.selectAnimation(index - 1);
    _slides.previewAnimationAt(index - 1);
  }

  void _slideNextAnimation() {
    final int? index = _slides.selectedAnimationIndex;
    if (index == null) return;
    if (index + 1 >= _slides.slide.animations.length) return;
    _slides.selectAnimation(index + 1);
    _slides.previewAnimationAt(index + 1);
  }

  void _slidePrevious() {
    final int index = _slides.activeSlideIndex;
    if (index > 0) _slides.setActiveSlide(index - 1);
  }

  void _slideNext() {
    final int index = _slides.activeSlideIndex;
    if (index < _slideCount - 1) _slides.setActiveSlide(index + 1);
  }
}

// -----------------------------------------------------------------------------
// Lightweight ribbon widgets
// -----------------------------------------------------------------------------

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.items});

  final String label;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: items,
      builder: (BuildContext context, MenuController controller, Widget? child) {
        return InkWell(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Sheet cell style command (font bold / size / alignment / fill / color)
// -----------------------------------------------------------------------------

class _CellStyleCommand implements OfficeCommand {
  _CellStyleCommand({
    required this.controller,
    required this.range,
    required this.update,
  }) {
    for (final SmlCellRef ref in range.cells) {
      final SmlCell cell = controller.sheet.cell(ref);
      _before[ref.a1] = (
        ref: ref,
        bold: cell.fontBold,
        size: cell.fontSize,
        align: cell.horizontalAlign,
        fill: cell.fillRgb,
        font: cell.fontRgb,
        styleIndex: cell.styleIndex,
      );
    }
  }

  final SheetEditorController controller;
  final SmlRange range;
  final void Function(SmlCell cell) update;

  final Map<String, ({SmlCellRef ref, bool bold, double size, SmlHAlign align, String fill, String font, int styleIndex})>
      _before = <String, ({SmlCellRef ref, bool bold, double size, SmlHAlign align, String fill, String font, int styleIndex})>{};

  @override
  void execute() {
    for (final SmlCellRef ref in range.cells) {
      update(controller.sheet.cell(ref));
    }
    controller.refresh();
  }

  @override
  void undo() {
    for (final ({SmlCellRef ref, bool bold, double size, SmlHAlign align, String fill, String font, int styleIndex}) snap
        in _before.values) {
      final SmlCell cell = controller.sheet.cell(snap.ref);
      cell
        ..fontBold = snap.bold
        ..fontSize = snap.size
        ..horizontalAlign = snap.align
        ..fillRgb = snap.fill
        ..fontRgb = snap.font
        ..styleIndex = snap.styleIndex;
    }
    controller.refresh();
  }

  @override
  OfficeCommand invert() => this;
}

// -----------------------------------------------------------------------------
// Slide commands
// -----------------------------------------------------------------------------

class _InsertSlideCommand implements OfficeCommand {
  _InsertSlideCommand({
    required this.controller,
    required this.slide,
    required this.index,
  }) : _previous = controller.activeSlideIndex;

  final SlideEditorController controller;
  final PmlSlide slide;
  final int index;
  final int _previous;

  @override
  void execute() {
    final List<PmlSlide> slides = controller.presentation.slides;
    slides.insert(index.clamp(0, slides.length), slide);
    controller.setActiveSlide(index.clamp(0, slides.length - 1));
    controller.refresh();
  }

  @override
  void undo() {
    controller.presentation.slides.remove(slide);
    if (controller.presentation.slides.isEmpty) {
      controller.presentation.slides.add(PmlSlide(id: 256));
    }
    controller.setActiveSlide(
      _previous.clamp(0, controller.presentation.slides.length - 1),
    );
    controller.refresh();
  }

  @override
  OfficeCommand invert() => this;
}

class _DeleteSlideCommand implements OfficeCommand {
  _DeleteSlideCommand({required this.controller, required this.index})
      : _removed = controller.presentation.slides[index],
        _previous = controller.activeSlideIndex;

  final SlideEditorController controller;
  final int index;
  final int _previous;
  final PmlSlide _removed;

  @override
  void execute() {
    controller.presentation.slides.remove(_removed);
    controller.setActiveSlide(
      index.clamp(0, controller.presentation.slides.length - 1),
    );
    controller.refresh();
  }

  @override
  void undo() {
    controller.presentation.slides.insert(
      index.clamp(0, controller.presentation.slides.length),
      _removed,
    );
    controller.setActiveSlide(
      _previous.clamp(0, controller.presentation.slides.length - 1),
    );
    controller.refresh();
  }

  @override
  OfficeCommand invert() => this;
}

class _AddShapeCommand implements OfficeCommand {
  _AddShapeCommand(this.controller, this.shape);

  final SlideEditorController controller;
  final PmlShape shape;
  PmlShape? _previousSelection;

  @override
  void execute() {
    _previousSelection ??= controller.selected;
    controller.slide.shapes.add(shape);
    controller.selected = shape;
    controller.refresh();
  }

  @override
  void undo() {
    controller.slide.shapes.remove(shape);
    controller.selected = _previousSelection;
    controller.refresh();
  }

  @override
  OfficeCommand invert() => this;
}

class _SlideTextColorCommand implements OfficeCommand {
  _SlideTextColorCommand(this.controller, this.shape, this.color)
      : _previous = shape.textColor;

  final SlideEditorController controller;
  final PmlShape shape;
  final String color;
  final String _previous;

  @override
  void execute() {
    shape.textColor = color;
    controller.refresh();
  }

  @override
  void undo() {
    shape.textColor = _previous;
    controller.refresh();
  }

  @override
  OfficeCommand invert() => this;
}
