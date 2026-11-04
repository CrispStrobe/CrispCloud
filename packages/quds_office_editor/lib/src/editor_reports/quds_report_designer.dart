import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_reports.dart';

import '../editor_sheet/inline_cell_editor.dart';
import '../embed/office_context_menu.dart';
import '../embed/office_host_fonts.dart';
import '../embed/office_theme.dart';
import 'render_report_data_explorer.dart';
import 'render_report_designer.dart';
import 'render_report_inspector.dart';
import 'render_report_preview.dart';
import 'render_report_problems.dart';
import 'render_report_toolbar.dart';
import 'render_report_toolbox.dart';
import 'report_completion_popup.dart';
import 'report_bundled_fonts.dart';
import 'report_designer_controller.dart';
import 'report_designer_strings.dart';
import 'report_template_library.dart';

/// Band report designer: toolbar, an insert panel, the design canvas or
/// live preview, and the property inspector, all painted by custom
/// RenderBoxes.
///
/// ```dart
/// final controller = ReportDesignerController.fromXml(qrepXml);
/// QudsReportDesigner(
///   controller: controller,
///   onExport: (format, bytes) => save(format, bytes),
/// );
/// ```
class QudsReportDesigner extends StatefulWidget {
  /// QudsReportDesigner API.
  const QudsReportDesigner({
    super.key,
    required this.controller,
    this.theme = OfficeTheme.light,
    this.inspectorWidth = 300,
    this.initialInspectorWidth,
    this.minInspectorWidth = 240,
    this.maxInspectorWidth = 640,
    this.onInspectorWidthChanged,
    this.problemsHeight = 180,
    this.onProblemsHeightChanged,
    this.focusNode,
    this.autofocus = true,
    this.loadBundledFonts = true,
    this.onExport,
    this.onPrint,
    this.templates,
    this.onPickImage,
    this.onPickFont,
    this.deviceFonts,
    this.onPickData,
    this.onPickShape,
    this.onPromptParameters,
    this.strings,
  });

  /// controller API.
  final ReportDesignerController controller;

  /// theme API.
  final OfficeTheme theme;

  /// Default width of the property inspector, logical pixels. Drag the
  /// splitter on its edge to resize; double-click it to restore this width.
  final double inspectorWidth;

  /// Starting width (for example one a host saved from
  /// [onInspectorWidthChanged]); [inspectorWidth] when null.
  final double? initialInspectorWidth;

  /// Narrowest the inspector can be dragged.
  final double minInspectorWidth;

  /// Widest the inspector can be dragged (the canvas keeps at least 240 px).
  final double maxInspectorWidth;

  /// Called with the new width when a splitter drag ends or is reset, so a
  /// host can persist it.
  final ValueChanged<double>? onInspectorWidthChanged;

  /// Starting height of the problems panel, which opens under the canvas
  /// when [ReportDesignerController.problemsOpen] is true. Drag its top
  /// edge to resize.
  final double problemsHeight;

  /// Called with the new height when a drag of the problems panel's top
  /// edge ends, so a host can persist it.
  final ValueChanged<double>? onProblemsHeightChanged;

  /// Keyboard focus; created internally when null.
  final FocusNode? focusNode;

  /// autofocus API.
  final bool autofocus;

  /// When the controller has no fonts, load the faces bundled with this
  /// package (Liberation, Noto Naskh Arabic) for the preview and exports.
  final bool loadBundledFonts;

  /// Receives exported bytes; the export button is hidden when null.
  final void Function(ReportExportFormat format, Uint8List bytes)? onExport;

  /// Receives the report as PDF, rendered with the preview data, when the
  /// user clicks **Print** or presses Ctrl+P. The button is hidden when null.
  /// The host shows the print dialog, for example with the `printing`
  /// package.
  final Future<void> Function(Uint8List pdf)? onPrint;

  /// Asked before preview, print, and export when the template has
  /// [ReportVariable.prompt] variables. Return false to stay put. The host
  /// writes the answers with [ReportDesignerController.setRuntimeValues].
  /// Design mode itself does not ask. Null skips the question.
  final Future<bool> Function(List<ReportVariable> prompts)?
  onPromptParameters;

  /// Ready-made reports offered by the Templates button (hidden when empty).
  /// Picking one replaces the template and uses its sample data. Null offers
  /// the bundled `.qrep` files ([ReportTemplateLibrary.bundled]).
  final List<ReportTemplateInfo>? templates;

  /// Opens a host file picker for "Import image…" (PNG / JPEG); the picked
  /// image is embedded in the report and saved inside the `.qrep` package.
  /// The import buttons are hidden when null.
  final ReportImagePicker? onPickImage;

  /// Opens a host file picker for "Import font file…" (TrueType `.ttf`);
  /// the faces are embedded in the report and saved inside the `.qrep`
  /// package. The button is hidden when null.
  final ReportFontPicker? onPickFont;

  /// Installed fonts listed on the inspector's Fonts page, where one click
  /// embeds a family in the report. Typing an installed family into a font
  /// field embeds it too. The list is hidden when null.
  final ReportDeviceFonts? deviceFonts;

  /// Opens a host file picker for the data explorer's "Import…" button
  /// (`.csv` or `.json`); the rows become the report's sample data, saved
  /// inside the `.qrep` package. The button is hidden when null.
  final ReportDataPicker? onPickData;

  /// Opens a host file picker for a shape map's "Import shapes…" button
  /// (`.shp` with its `.dbf`, GeoJSON, or `.qmap`). Hidden when null.
  final ReportShapePicker? onPickShape;

  /// Interface language; follows the app locale
  /// ([Localizations.maybeLocaleOf]) when null, English when the locale has
  /// no translation.
  final ReportDesignerStrings? strings;

  @override
  State<QudsReportDesigner> createState() => _QudsReportDesignerState();
}

class _QudsReportDesignerState extends State<QudsReportDesigner> {
  FocusNode? _ownFocus;
  OverlayEntry? _menu;
  String _message = '';
  final GlobalKey _inspectorKey = GlobalKey();
  final GlobalKey _toolboxKey = GlobalKey();
  final GlobalKey _workKey = GlobalKey();
  ReportToolboxHover? _toolHover;
  late double _inspectorWidth =
      widget.initialInspectorWidth ?? widget.inspectorWidth;
  bool _splitterHot = false;
  bool _splitterDrag = false;
  late double _problemsHeight = widget.problemsHeight;
  bool _problemsHot = false;
  bool _problemsDrag = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  ReportDesignerController get _c => widget.controller;

  String _t(String english) => _c.strings.t(english);

  void _onToolHover(ReportToolboxHover? next) {
    if (!mounted || _toolHover == next) {
      return;
    }
    setState(() => _toolHover = next);
  }

  Widget _toolCard(BoxConstraints box) {
    final ReportToolboxHover? hover = _toolHover;
    final BuildContext? toolboxContext = _toolboxKey.currentContext;
    final BuildContext? stackContext = _workKey.currentContext;
    if (hover == null || toolboxContext == null || stackContext == null) {
      return const SizedBox.shrink();
    }
    final RenderObject? toolboxObject = toolboxContext.findRenderObject();
    final RenderObject? stackObject = stackContext.findRenderObject();
    if (toolboxObject is! RenderBox ||
        stackObject is! RenderBox ||
        !toolboxObject.hasSize ||
        !stackObject.hasSize) {
      return const SizedBox.shrink();
    }
    const double cardW = 252;
    const double cardH = 172;
    final Offset topRight = stackObject.globalToLocal(
      toolboxObject.localToGlobal(hover.button.topRight),
    );
    final Offset topLeft = stackObject.globalToLocal(
      toolboxObject.localToGlobal(hover.button.topLeft),
    );
    double left = topRight.dx + 8;
    if (left + cardW > box.maxWidth - 8) {
      left = topLeft.dx - cardW - 8;
    }
    if (left < 8) {
      left = 8;
    }
    double top = topRight.dy - 4;
    if (top + cardH > box.maxHeight - 8) {
      top = box.maxHeight - cardH - 8;
    }
    if (top < 8) {
      top = 8;
    }
    return Positioned(
      left: left,
      top: top,
      width: cardW,
      height: cardH,
      child: IgnorePointer(
        child: ReportToolboxCard(
          title: _t(hover.title),
          description: _t(hover.description),
          icon: hover.icon,
          theme: widget.theme,
          direction: _c.strings.direction,
        ),
      ),
    );
  }

  void _syncStrings() {
    final ReportDesignerStrings s =
        widget.strings ??
        ReportDesignerStrings.forLocale(Localizations.maybeLocaleOf(context));
    if (identical(s, _c.strings)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _c.strings = s;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncStrings();
  }

  static const double _mm = 72 / 25.4;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _bindPicker(null);
    OfficeHostFonts.ensureRegistered().then((_) {
      if (mounted) {
        _c.refresh();
      }
    });
    _loadFonts();
    _loadTemplates();
  }

  List<ReportTemplateInfo> _bundled = const <ReportTemplateInfo>[];

  List<ReportTemplateInfo> get _templates => widget.templates ?? _bundled;

  void _loadTemplates() {
    if (widget.templates != null || _bundled.isNotEmpty) {
      return;
    }
    unawaited(
      ReportTemplateLibrary.bundled().then((List<ReportTemplateInfo> all) {
        if (mounted) {
          setState(() => _bundled = all);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(QudsReportDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadTemplates();
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _loadFonts();
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        (oldWidget.onPickImage == null) != (widget.onPickImage == null) ||
        oldWidget.onPickFont != widget.onPickFont ||
        oldWidget.onPickData != widget.onPickData ||
        oldWidget.onPickShape != widget.onPickShape ||
        !identical(oldWidget.deviceFonts, widget.deviceFonts)) {
      _bindPicker(oldWidget.controller);
    }
    if (oldWidget.initialInspectorWidth != widget.initialInspectorWidth ||
        oldWidget.inspectorWidth != widget.inspectorWidth) {
      _inspectorWidth = widget.initialInspectorWidth ?? widget.inspectorWidth;
    }
    if (!identical(oldWidget.strings, widget.strings) ||
        !identical(oldWidget.controller, widget.controller)) {
      _syncStrings();
    }
    if (oldWidget.focusNode != widget.focusNode && widget.focusNode != null) {
      _ownFocus?.dispose();
      _ownFocus = null;
    }
  }

  @override
  void dispose() {
    _dismissMenu();
    if (_c.imagePicker == _pickImage) {
      _c.imagePicker = null;
    }
    if (_c.fontPicker == widget.onPickFont) {
      _c.fontPicker = null;
    }
    if (_c.dataPicker == widget.onPickData) {
      _c.dataPicker = null;
    }
    if (_c.shapePicker == widget.onPickShape) {
      _c.shapePicker = null;
    }
    if (identical(_c.deviceFonts, widget.deviceFonts)) {
      _c.deviceFonts = null;
    }
    _c.removeListener(_onController);
    _ownFocus?.dispose();
    super.dispose();
  }

  static const double _splitterWidth = 6;

  double _clampInspector(double width, double available) {
    final double max = math.min(
      widget.maxInspectorWidth,
      available - _splitterWidth - 240,
    );
    final double lo = math.min(widget.minInspectorWidth, max);
    return width.clamp(math.max(0, lo), math.max(lo, max)).toDouble();
  }

  Widget _splitter(OfficeTheme theme, double available) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final bool active = _splitterHot || _splitterDrag;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _splitterHot = true),
      onExit: (_) => setState(() => _splitterHot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => setState(() {
          _splitterDrag = true;
          _inspectorWidth = _clampInspector(_inspectorWidth, available);
        }),
        onHorizontalDragUpdate: (DragUpdateDetails d) => setState(() {
          _inspectorWidth = _clampInspector(
            _inspectorWidth + (rtl ? d.delta.dx : -d.delta.dx),
            available,
          );
        }),
        onHorizontalDragEnd: (_) {
          setState(() => _splitterDrag = false);
          widget.onInspectorWidthChanged?.call(_inspectorWidth);
        },
        onDoubleTap: () {
          setState(() => _inspectorWidth = widget.inspectorWidth);
          widget.onInspectorWidthChanged?.call(_inspectorWidth);
        },
        child: SizedBox(
          width: _splitterWidth,
          child: CustomPaint(
            painter: _SplitterPainter(
              line: theme.pageBorder,
              accent: theme.selectionStroke,
              active: active,
            ),
          ),
        ),
      ),
    );
  }

  Widget _problemsSplitter(OfficeTheme theme, double available) {
    final bool active = _problemsHot || _problemsDrag;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _problemsHot = true),
      onExit: (_) => setState(() => _problemsHot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (_) => setState(() => _problemsDrag = true),
        onVerticalDragUpdate: (DragUpdateDetails d) => setState(() {
          _problemsHeight = _clampProblems(
            _problemsHeight - d.delta.dy,
            available,
          );
        }),
        onVerticalDragEnd: (_) {
          setState(() => _problemsDrag = false);
          widget.onProblemsHeightChanged?.call(_problemsHeight);
        },
        child: SizedBox(
          height: _splitterWidth,
          child: CustomPaint(
            painter: _SplitterPainter(
              line: theme.pageBorder,
              accent: theme.selectionStroke,
              active: active,
              vertical: false,
            ),
          ),
        ),
      ),
    );
  }

  static double _clampProblems(double height, double available) {
    final double max = math.max(
      RenderReportProblems.headerHeight,
      available - 160,
    );
    return height.clamp(RenderReportProblems.headerHeight + 46, max).toDouble();
  }

  void _bindPicker(ReportDesignerController? previous) {
    if (previous != null && !identical(previous, _c)) {
      if (previous.imagePicker == _pickImage) {
        previous.imagePicker = null;
      }
      previous
        ..fontPicker = null
        ..dataPicker = null
        ..shapePicker = null
        ..deviceFonts = null;
    }
    _c.imagePicker = widget.onPickImage == null ? null : _pickImage;
    _c.fontPicker = widget.onPickFont;
    _c.dataPicker = widget.onPickData;
    _c.shapePicker = widget.onPickShape;
    _c.deviceFonts = widget.deviceFonts;
    _loadCanvasFonts();
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _c.refresh();
        }
      });
    }
  }

  Future<({String name, Uint8List bytes})?> _pickImage() async {
    final ReportImagePicker? pick = widget.onPickImage;
    final ({String name, Uint8List bytes})? file = await pick?.call();
    if (file == null || !mounted) {
      return null;
    }
    if (ReportImageFormat.sniff(file.bytes) == null) {
      setState(() => _message = '"${file.name}" is not a PNG or JPEG image');
      return null;
    }
    return file;
  }

  void _loadFonts() {
    if (!widget.loadBundledFonts || !_c.fonts.isEmpty) {
      return;
    }
    final ReportDesignerController target = _c;
    ReportBundledFonts.shared().then(
      (ReportFontRegistry fonts) {
        if (mounted && identical(target, _c) && _c.fonts.isEmpty) {
          _c.useFonts(fonts);
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _message = 'Fonts unavailable: $e');
        }
      },
    );
  }

  void _onController() {
    if (mounted) {
      _loadCanvasFonts();
      setState(() => _message = '');
    }
  }

  static final Map<String, ReportFontFiles> _canvasFonts =
      <String, ReportFontFiles>{};

  /// Registers embedded families with the engine's font collection so the
  /// design canvas (Flutter text) draws them; the canvas repaints when
  /// [PaintingBinding.systemFonts] reports the new faces.
  void _loadCanvasFonts() {
    for (final MapEntry<String, ReportFontFiles> f
        in _c.embeddedFonts.entries) {
      if (identical(_canvasFonts[f.key], f.value)) {
        continue;
      }
      _canvasFonts[f.key] = f.value;
      final FontLoader loader = FontLoader(f.key);
      for (final Uint8List? face in <Uint8List?>[
        f.value.regular,
        f.value.bold,
      ]) {
        if (face != null) {
          loader.addFont(Future<ByteData>.value(ByteData.sublistView(face)));
        }
      }
      unawaited(
        loader.load().catchError((Object e) {
          if (mounted) {
            setState(() => _message = 'Could not load ${f.key}: $e');
          }
        }),
      );
    }
  }

  void _activate() {
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  // ------------------------------------------------------------ menus

  void _dismissMenu() {
    OfficeContextMenu.dismiss(_menu);
    _menu = null;
  }

  void _showMenu(
    Offset at,
    List<OfficeContextAction> actions,
    ValueChanged<String> onSelect, {
    String? filterHint,
  }) {
    _dismissMenu();
    _menu = OfficeContextMenu.show(
      context: context,
      globalPosition: at,
      actions: <OfficeContextAction>[
        for (final OfficeContextAction a in actions)
          a.isCaption
              ? OfficeContextAction.caption(
                  _t(a.label),
                  separatorBefore: a.separatorBefore,
                )
              : OfficeContextAction(
                  id: a.id,
                  label: _t(a.label),
                  icon: a.icon,
                  shortcut: a.shortcut,
                  enabled: a.enabled,
                  danger: a.danger,
                  separatorBefore: a.separatorBefore,
                ),
      ],
      filterHint: filterHint,
      onSelect: (String id) {
        _menu = null;
        onSelect(id);
      },
    );
  }

  void _canvasMenu(ReportCanvasContextHit hit) {
    _activate();
    final String? id = hit.elementId;
    final ReportElement? element = id == null
        ? null
        : _c.template.findElement(id)?.$2;
    final bool any = _c.selection.isNotEmpty;
    final List<OfficeContextAction> actions = <OfficeContextAction>[
      if (element is ReportTextElement)
        const OfficeContextAction(
          id: 'editText',
          label: 'Edit text',
          icon: Icons.edit,
          shortcut: 'F2',
        ),
      OfficeContextAction(
        id: 'cut',
        label: 'Cut',
        icon: Icons.content_cut,
        shortcut: 'Ctrl+X',
        enabled: any,
        separatorBefore: element is ReportTextElement,
      ),
      OfficeContextAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        enabled: any,
      ),
      OfficeContextAction(
        id: 'paste',
        label: 'Paste',
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: _c.canPaste,
      ),
      OfficeContextAction(
        id: 'duplicate',
        label: 'Duplicate',
        icon: Icons.copy_all,
        shortcut: 'Ctrl+D',
        enabled: any,
      ),
      OfficeContextAction(
        id: 'front',
        label: 'Bring to front',
        icon: Icons.flip_to_front,
        enabled: any,
        separatorBefore: true,
      ),
      OfficeContextAction(
        id: 'back',
        label: 'Send to back',
        icon: Icons.flip_to_back,
        enabled: any,
      ),
      if (element is ReportTableElement)
        const OfficeContextAction(
          id: 'addColumn',
          label: 'Add column',
          icon: Icons.view_column,
          separatorBefore: true,
        ),
      if (element is ReportTableElement && element.columns.length > 1)
        const OfficeContextAction(
          id: 'removeColumn',
          label: 'Remove last column',
          icon: Icons.remove,
        ),
      OfficeContextAction(
        id: 'delete',
        label: 'Delete',
        icon: Icons.delete_outline,
        shortcut: 'Del',
        enabled: any,
        danger: true,
        separatorBefore: true,
      ),
      if (hit.band case final ReportBandKind band)
        OfficeContextAction(
          id: 'removeBand',
          label: '${_t('Remove band')}: ${_t(band.xmlName)}',
          icon: Icons.remove_circle_outline,
          danger: true,
        ),
    ];
    _showMenu(hit.globalPosition, actions, (String action) {
      switch (action) {
        case 'editText':
          if (id != null) {
            _c.beginTextEdit(id);
          }
        case 'cut':
          _c.cutSelection();
        case 'copy':
          _c.copySelection();
        case 'paste':
          _c.paste();
        case 'duplicate':
          _c.duplicateSelection();
        case 'front':
          _c.bringToFront();
        case 'back':
          _c.sendToBack();
        case 'addColumn':
          if (id != null) {
            _c.addTableColumn(id);
          }
        case 'removeColumn':
          if (id != null && element is ReportTableElement) {
            _c.removeTableColumn(id, element.columns.length - 1);
          }
        case 'delete':
          _c.deleteSelection();
        case 'removeBand':
          final ReportBandKind? band = hit.band;
          if (band != null) {
            _c.removeBand(band);
          }
      }
    });
  }

  void _bandMenu(Offset at) {
    final List<OfficeContextAction> actions = <OfficeContextAction>[
      const OfficeContextAction.caption('Add band'),
      for (final ReportBandKind kind in ReportBandKind.values)
        OfficeContextAction(
          id: kind.name,
          label: _t(kind.xmlName),
          icon: _c.template.band(kind) != null ? Icons.check : null,
        ),
    ];
    _showMenu(at, actions, (String id) {
      for (final ReportBandKind kind in ReportBandKind.values) {
        if (kind.name == id) {
          _c.addBand(kind);
        }
      }
    });
  }

  void _exportMenu(Offset at) {
    _showMenu(
      at,
      const <OfficeContextAction>[
        OfficeContextAction(
          id: 'pdf',
          label: 'PDF document',
          icon: Icons.picture_as_pdf,
        ),
        OfficeContextAction(
          id: 'xlsx',
          label: 'Excel workbook',
          icon: Icons.grid_on,
        ),
        OfficeContextAction(
          id: 'docx',
          label: 'Word document',
          icon: Icons.description,
        ),
      ],
      (String id) {
        for (final ReportExportFormat f in ReportExportFormat.values) {
          if (f.name == id) {
            _export(f);
          }
        }
      },
    );
  }

  static IconData _variableIcon(ReportVariableType t) => switch (t) {
    ReportVariableType.text => Icons.text_fields,
    ReportVariableType.number => Icons.pin_outlined,
    ReportVariableType.boolean => Icons.toggle_on_outlined,
    ReportVariableType.date => Icons.event,
    ReportVariableType.list => Icons.format_list_bulleted,
    ReportVariableType.expression => Icons.functions,
  };

  void _variablesMenu(Offset at) {
    final List<ReportVariable> vars = _c.template.variables;
    final bool editing = _c.editingId != null || _c.editingProperty != null;
    _showMenu(
      at,
      <OfficeContextAction>[
        OfficeContextAction.caption(
          vars.isEmpty
              ? 'No template variables yet'
              : (editing ? 'Insert at the caret' : 'Insert as a text box'),
        ),
        for (int i = 0; i < vars.length; i++)
          OfficeContextAction(
            id: 'insert.$i',
            label: vars[i].description.isEmpty
                ? '${vars[i].name}   ·  ${vars[i].type.name}'
                : '${vars[i].name}   ·  ${vars[i].description}',
            icon: _variableIcon(vars[i].type),
          ),
        const OfficeContextAction(
          id: 'new',
          label: 'New variable…',
          icon: Icons.add,
          separatorBefore: true,
        ),
        const OfficeContextAction(
          id: 'edit',
          label: 'Edit variables',
          icon: Icons.tune,
        ),
      ],
      (String id) {
        if (id.startsWith('insert.')) {
          final int i = int.parse(id.substring(7));
          if (i < vars.length) {
            _c.insertVariable(vars[i].name);
          }
          return;
        }
        if (id == 'new') {
          _c.select(null);
          _c.addVariable();
          _c.beginPropertyEdit('var.${_c.template.variables.length - 1}.name');
          return;
        }
        if (id == 'edit') {
          _c.select(null);
        }
      },
    );
  }

  static IconData _categoryIcon(ReportTemplateCategory c) => switch (c) {
    ReportTemplateCategory.sales => Icons.point_of_sale,
    ReportTemplateCategory.finance => Icons.account_balance,
    ReportTemplateCategory.inventory => Icons.inventory_2,
    ReportTemplateCategory.analytics => Icons.insights,
    ReportTemplateCategory.hr => Icons.badge_outlined,
  };

  /// Families grouped under category captions; a family with several
  /// languages asks for one ([_languageMenu]).
  void _templatesMenu(Offset at) {
    final List<ReportTemplateInfo> list = _templates;
    final List<ReportTemplateInfo> heads = <ReportTemplateInfo>[];
    final Set<String> seen = <String>{};
    for (final ReportTemplateInfo info in list) {
      if (seen.add(info.family)) {
        heads.add(info);
      }
    }
    List<ReportTemplateInfo> variants(String family) => <ReportTemplateInfo>[
      for (final ReportTemplateInfo info in list)
        if (info.family == family) info,
    ];
    _showMenu(
      at,
      <OfficeContextAction>[
        for (final ReportTemplateCategory c in ReportTemplateCategory.values)
          if (heads.any(
            (ReportTemplateInfo t) => t.category == c,
          )) ...<OfficeContextAction>[
            OfficeContextAction.caption('${c.title}  ·  ${c.titleAr}'),
            for (final ReportTemplateInfo t in heads)
              if (t.category == c)
                OfficeContextAction(
                  id: 'fam.${t.family}',
                  label: t.familyTitle,
                  icon: _categoryIcon(c),
                  shortcut: t.familyTitleAr,
                ),
          ],
        const OfficeContextAction(
          id: 'blank',
          label: 'Blank report',
          icon: Icons.note_add_outlined,
          separatorBefore: true,
        ),
      ],
      (String id) {
        if (id == 'blank') {
          _c.mockData = null;
          _c.replaceTemplate(ReportTemplate());
          return;
        }
        for (final ReportTemplateInfo t in heads) {
          if (id == 'fam.${t.family}') {
            final List<ReportTemplateInfo> v = variants(t.family);
            if (v.length == 1) {
              _loadTemplate(v.single);
            } else {
              _languageMenu(at, v);
            }
          }
        }
      },
    );
  }

  void _languageMenu(Offset at, List<ReportTemplateInfo> variants) {
    final ReportTemplateInfo first = variants.first;
    _showMenu(
      at,
      <OfficeContextAction>[
        OfficeContextAction.caption(
          '${first.familyTitle}  ·  ${first.familyTitleAr}',
        ),
        for (final ReportTemplateInfo info in variants)
          OfficeContextAction(
            id: 'tpl.${info.id}',
            label: info.language.label,
            icon: Icons.translate,
            shortcut: info.language.code.toUpperCase(),
          ),
      ],
      (String id) {
        for (final ReportTemplateInfo info in variants) {
          if (id == 'tpl.${info.id}') {
            _loadTemplate(info);
          }
        }
      },
    );
  }

  void _loadTemplate(ReportTemplateInfo info) {
    _c.loadTemplate(info);
    _c.fitWidth();
    setState(() => _message = '${_t('Loaded')} "${info.title}"');
  }

  Future<void> _goPreview() async {
    if (_c.mode == ReportDesignMode.preview) {
      _c.togglePreview();
      return;
    }
    if (!await _promptParameters()) {
      return;
    }
    _c.mode = ReportDesignMode.preview;
  }

  Future<bool> _promptParameters() async {
    final Future<bool> Function(List<ReportVariable>)? ask =
        widget.onPromptParameters;
    final List<ReportVariable> prompts = _c.promptVariables;
    if (ask == null || prompts.isEmpty) {
      return true;
    }
    return ask(prompts);
  }

  Future<void> _export(ReportExportFormat format) async {
    final void Function(ReportExportFormat, Uint8List)? sink = widget.onExport;
    if (sink == null || !await _promptParameters()) {
      return;
    }
    setState(
      () => _message = '${_t('Exporting')} ${format.name.toUpperCase()}…',
    );
    try {
      final Uint8List bytes = await _c.export(format);
      sink(format, bytes);
      if (mounted) {
        setState(
          () => _message =
              '${_t('Exported')} ${format.name.toUpperCase()} '
              '(${_size(bytes.length)})',
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _message = '${_t('Export failed')}: $e');
      }
    }
  }

  Future<void> _print() async {
    final Future<void> Function(Uint8List)? sink = widget.onPrint;
    if (sink == null || !await _promptParameters()) {
      return;
    }
    setState(() => _message = '${_t('Preparing to print')}…');
    try {
      final Uint8List pdf = await _c.export(ReportExportFormat.pdf);
      await sink(pdf);
      if (mounted) {
        setState(() => _message = '');
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _message = '${_t('Print failed')}: $e');
      }
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _inspectorChoice(ReportInspectorChoice choice) {
    _activate();
    final ReportProperty p = choice.property;
    _showMenu(
      choice.globalPosition,
      <OfficeContextAction>[
        OfficeContextAction.caption(p.label),
        for (final String option in choice.choices)
          OfficeContextAction(
            id: option,
            label: choice.options == null
                ? _c.strings.option(option)
                : (option.isEmpty ? _t('None') : option),
            icon: option == p.value ? Icons.check : null,
            shortcut: choice.details[option],
          ),
      ],
      (String value) => _c.setProperty(p.key, value),
      filterHint: choice.choices.length > 8 ? _t('Type to search') : null,
    );
  }

  // ------------------------------------------------------------ toolbar

  static const List<ReportToolboxEntry> _insertTools = <ReportToolboxEntry>[
    ReportToolboxEntry(
      tool: ReportDesignTool.select,
      icon: ReportToolbarIcon.select,
      title: 'Select (Esc)',
      description: 'Pick, move, and resize what is already on the page.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.text,
      icon: ReportToolbarIcon.text,
      title: 'Text box',
      description: 'Fixed words, or a field such as {{Data.customer}}.',
      gapBefore: true,
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.pageNumber,
      icon: ReportToolbarIcon.pageNumber,
      title: 'Page number',
      description: 'Prints the number of this page.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.pages,
      icon: ReportToolbarIcon.pages,
      title: 'Page count',
      description: 'This page and the page count, such as 2 / 5.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.date,
      icon: ReportToolbarIcon.date,
      title: 'Print date',
      description: 'The date the report is printed.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.reportName,
      icon: ReportToolbarIcon.reportName,
      title: 'Report name',
      description: 'The name stored on the report.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.rowNumber,
      icon: ReportToolbarIcon.rowNumber,
      title: 'Row number',
      description:
          '1, 2, 3… for the current record. Place it in the detail band.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.total,
      icon: ReportToolbarIcon.total,
      title: 'Column total',
      description: 'The sum of a column. Change Row.total to your own field.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.signature,
      icon: ReportToolbarIcon.signature,
      title: 'Signature',
      description: 'A line to sign on, with a caption underneath.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.image,
      icon: ReportToolbarIcon.image,
      title: 'Image',
      description:
          'A picture. Import a PNG or JPEG and it is stored inside the report.',
      gapBefore: true,
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.table,
      icon: ReportToolbarIcon.table,
      title: 'Repeating table',
      description: 'One row for every record. Bind each column to a field.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.barcode,
      icon: ReportToolbarIcon.barcode,
      title: 'Barcode',
      description: 'A Code 128 barcode from a number or a field.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.qr,
      icon: ReportToolbarIcon.qr,
      title: 'QR code',
      description: 'A square code for a link, a reference, or a field.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.line,
      icon: ReportToolbarIcon.line,
      title: 'Line',
      description: 'A straight rule for separators and underlines.',
      gapBefore: true,
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.rectangle,
      icon: ReportToolbarIcon.rectangle,
      title: 'Rectangle',
      description: 'A box. Fill it, or leave it as an outline.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.rounded,
      icon: ReportToolbarIcon.rounded,
      title: 'Rounded box',
      description: 'A box with rounded corners, for a card or a frame.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.ellipse,
      icon: ReportToolbarIcon.ellipse,
      title: 'Ellipse',
      description: 'A circle or an oval.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.chart,
      icon: ReportToolbarIcon.chart,
      title: 'Chart',
      description:
          'Columns, lines, pies, and the other charts, bound to a table.',
      gapBefore: true,
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.map,
      icon: ReportToolbarIcon.map,
      title: 'Map',
      description:
          'Regions from a shape file. Color each one from a column, joined by a key.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.section,
      icon: ReportToolbarIcon.table,
      title: 'Section',
      description: 'Another detail table, with its own data set.',
      gapBefore: true,
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.crosstab,
      icon: ReportToolbarIcon.chart,
      title: 'Crosstab',
      description: 'Rows by one field, columns by another, with a total.',
    ),
    ReportToolboxEntry(
      tool: ReportDesignTool.subreport,
      icon: ReportToolbarIcon.text,
      title: 'Subreport',
      description: 'A child template stored in the same report file.',
    ),
  ];

  static const Map<ReportAlignAction, (ReportToolbarIcon, String)>
  _aligns = <ReportAlignAction, (ReportToolbarIcon, String)>{
    ReportAlignAction.left: (ReportToolbarIcon.alignLeft, 'Align left'),
    ReportAlignAction.centerX: (ReportToolbarIcon.alignCenter, 'Align centers'),
    ReportAlignAction.right: (ReportToolbarIcon.alignRight, 'Align right'),
    ReportAlignAction.top: (ReportToolbarIcon.alignTop, 'Align top'),
    ReportAlignAction.middle: (ReportToolbarIcon.alignMiddle, 'Align middles'),
    ReportAlignAction.bottom: (ReportToolbarIcon.alignBottom, 'Align bottom'),
    ReportAlignAction.distributeX: (
      ReportToolbarIcon.distributeX,
      'Distribute horizontally',
    ),
    ReportAlignAction.distributeY: (
      ReportToolbarIcon.distributeY,
      'Distribute vertically',
    ),
    ReportAlignAction.sameWidth: (ReportToolbarIcon.sameWidth, 'Same width'),
    ReportAlignAction.sameHeight: (ReportToolbarIcon.sameHeight, 'Same height'),
  };

  List<ReportToolbarItem> _toolbarItems() {
    final bool design = _c.mode == ReportDesignMode.design;
    final bool preview = _c.mode == ReportDesignMode.preview;
    final bool data = _c.mode == ReportDesignMode.data;
    final int n = _c.selectedElements.length;
    return <ReportToolbarItem>[
      if (_templates.isNotEmpty)
        const ReportToolbarItem(
          id: 'templates',
          icon: ReportToolbarIcon.templates,
          tooltip: 'Start from a ready-made report',
          label: 'Templates',
        ),
      ReportToolbarItem(
        id: 'variables',
        icon: ReportToolbarIcon.variables,
        tooltip: 'Insert or edit template variables',
        label: 'Variables',
        enabled: design,
      ),
      ReportToolbarItem(
        id: 'undo',
        icon: ReportToolbarIcon.undo,
        tooltip: 'Undo (Ctrl+Z)',
        enabled: _c.canUndo,
        separatorBefore: true,
      ),
      ReportToolbarItem(
        id: 'redo',
        icon: ReportToolbarIcon.redo,
        tooltip: 'Redo (Ctrl+Y)',
        enabled: _c.canRedo,
      ),
      ReportToolbarItem(
        id: 'duplicate',
        icon: ReportToolbarIcon.duplicate,
        tooltip: 'Duplicate (Ctrl+D)',
        enabled: design && n > 0,
      ),
      ReportToolbarItem(
        id: 'delete',
        icon: ReportToolbarIcon.delete,
        tooltip: 'Delete (Del)',
        enabled: design && n > 0,
      ),
      for (final MapEntry<ReportAlignAction, (ReportToolbarIcon, String)> a
          in _aligns.entries)
        ReportToolbarItem(
          id: 'align.${a.key.name}',
          icon: a.value.$1,
          tooltip: a.value.$2,
          enabled: design && n >= _minSelection(a.key),
          separatorBefore:
              a.key == ReportAlignAction.left ||
              a.key == ReportAlignAction.distributeX,
        ),
      ReportToolbarItem(
        id: 'front',
        icon: ReportToolbarIcon.front,
        tooltip: 'Bring to front',
        enabled: design && n > 0,
        separatorBefore: true,
      ),
      ReportToolbarItem(
        id: 'back',
        icon: ReportToolbarIcon.back,
        tooltip: 'Send to back',
        enabled: design && n > 0,
      ),
      ReportToolbarItem(
        id: 'band',
        icon: ReportToolbarIcon.band,
        tooltip: 'Add band',
        enabled: design,
        separatorBefore: true,
      ),
      ReportToolbarItem(
        id: 'grid',
        icon: ReportToolbarIcon.grid,
        tooltip: 'Grid and snapping',
        enabled: design,
        active: design && _c.showGrid,
      ),
      const ReportToolbarItem(
        id: 'zoomOut',
        icon: ReportToolbarIcon.zoomOut,
        tooltip: 'Zoom out (Ctrl+-)',
        separatorBefore: true,
      ),
      const ReportToolbarItem(
        id: 'zoomIn',
        icon: ReportToolbarIcon.zoomIn,
        tooltip: 'Zoom in (Ctrl+=)',
      ),
      ReportToolbarItem(
        id: 'fit',
        icon: ReportToolbarIcon.fitWidth,
        tooltip: 'Fit page width',
        enabled: design,
      ),
      ReportToolbarItem(
        id: 'data',
        icon: data ? ReportToolbarIcon.design : ReportToolbarIcon.data,
        tooltip: data
            ? 'Back to design (F6)'
            : 'Explore and edit the report data (F6)',
        label: data ? 'Design' : 'Data',
        active: data,
        separatorBefore: true,
      ),
      ReportToolbarItem(
        id: 'mode',
        icon: preview ? ReportToolbarIcon.design : ReportToolbarIcon.preview,
        tooltip: preview ? 'Back to design (F5)' : 'Live preview (F5)',
        label: preview ? 'Design' : 'Preview',
        active: preview,
      ),
      if (widget.onExport != null)
        const ReportToolbarItem(
          id: 'export',
          icon: ReportToolbarIcon.export,
          tooltip: 'Export with preview data',
          label: 'Export',
        ),
      if (widget.onPrint != null)
        const ReportToolbarItem(
          id: 'print',
          icon: ReportToolbarIcon.print,
          tooltip: 'Print with preview data (Ctrl+P)',
          label: 'Print',
        ),
    ];
  }

  static int _minSelection(ReportAlignAction a) => switch (a) {
    ReportAlignAction.distributeX || ReportAlignAction.distributeY => 3,
    ReportAlignAction.sameWidth || ReportAlignAction.sameHeight => 2,
    _ => 1,
  };

  void _onToolbar(String id, Offset at) {
    _activate();
    if (id.startsWith('tool.')) {
      for (final ReportDesignTool t in ReportDesignTool.values) {
        if (id == 'tool.${t.name}') {
          _c.tool = t;
        }
      }
      return;
    }
    if (id.startsWith('align.')) {
      for (final ReportAlignAction a in ReportAlignAction.values) {
        if (id == 'align.${a.name}') {
          _c.align(a);
        }
      }
      return;
    }
    switch (id) {
      case 'undo':
        _c.undo();
      case 'redo':
        _c.redo();
      case 'duplicate':
        _c.duplicateSelection();
      case 'delete':
        _c.deleteSelection();
      case 'front':
        _c.bringToFront();
      case 'back':
        _c.sendToBack();
      case 'band':
        _bandMenu(at);
      case 'grid':
        _c.toggleGrid();
      case 'zoomOut':
        _c.zoom = _c.zoom / 1.2;
      case 'zoomIn':
        _c.zoom = _c.zoom * 1.2;
      case 'fit':
        _c.fitWidth();
      case 'mode':
        _goPreview();
      case 'data':
        _c.toggleData();
      case 'export':
        _exportMenu(at);
      case 'print':
        _print();
      case 'templates':
        _templatesMenu(at);
      case 'variables':
        _variablesMenu(at);
    }
  }

  String _status() {
    if (_message.isNotEmpty) {
      return _message;
    }
    final String? notice = _c.notice;
    if (notice != null && notice.isNotEmpty) {
      return _t(notice);
    }
    if (_c.mode == ReportDesignMode.data) {
      final ReportDataTableView t = _c.dataTable;
      final StringBuffer d = StringBuffer('${_t('Data')}  ·  ${t.title}');
      final int row = _c.dataRow;
      final int col = _c.dataColumn;
      if (row >= 0 && col >= 0) {
        d.write('  ·  ${_t('Row')} ${row + 1}, ${t.columns[col].name}');
        if (!_c.canEditDataCell(row, col) && !_c.hasHostData) {
          d.write(
            '  ·  ${_t(t.columns[col].isCalculated ? 'calculated' : 'read-only')}',
          );
        }
      } else if (col >= 0) {
        d.write('  ·  ${_t('Column')} ${t.columns[col].name}');
      } else if (row >= 0) {
        d.write('  ·  ${_t('Row')} ${row + 1}');
      }
      if (_c.hasHostData) {
        d.write('  ·  ${_t('host data (read-only)')}');
      }
      return d.toString();
    }
    final StringBuffer s = StringBuffer('${(_c.zoom * 100).round()}%');
    final List<ReportElement> sel = _c.selectedElements;
    if (sel.length == 1) {
      final ReportRect r = _c.physicalRect(sel.first);
      s.write(
        '  ·  ${sel.first.displayName}  '
        '${ReportUnits.trimNumber(r.left / _mm, decimals: 1)}, '
        '${ReportUnits.trimNumber(r.top / _mm, decimals: 1)} mm  '
        '${ReportUnits.trimNumber(r.width / _mm, decimals: 1)} × '
        '${ReportUnits.trimNumber(r.height / _mm, decimals: 1)} mm',
      );
    } else if (sel.length > 1) {
      s.write('  ·  ${sel.length} selected');
    }
    if (_c.hasHostData) {
      s.write('  ·  host data');
    }
    return s.toString();
  }

  // ------------------------------------------------------------ keyboard

  static bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  static bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_c.editingId != null) {
      if (_ctrl && key == LogicalKeyboardKey.keyB) {
        _c.toggleRunBold();
        return KeyEventResult.handled;
      }
      return _editKey(
        _c.textEditor,
        event,
        multiline: true,
        commit: _c.commitTextEdit,
        cancel: _c.cancelTextEdit,
        tab: _c.commitTextEdit,
      );
    }
    final ({int row, int column})? cell = _c.editingDataCell;
    if (cell != null) {
      return _cellEditKey(event, cell);
    }
    if (_c.editingProperty != null) {
      final ReportProperty? p = _editingProperty();
      if (p != null &&
          p.isSteppable &&
          _c.completion == null &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        final InlineCellEditor ed = _c.propertyEditor;
        final String text = ed.formulaBar;
        final String next = _c.steppedValue(
          p,
          key == LogicalKeyboardKey.arrowUp ? 1 : -1,
          large: _shift,
          from: text,
        );
        ed.replaceRange(0, text.length, next);
        return KeyEventResult.handled;
      }
      return _editKey(
        _c.propertyEditor,
        event,
        multiline: p?.kind == ReportPropertyKind.multiline,
        commit: _c.commitPropertyEdit,
        cancel: _c.cancelPropertyEdit,
        tab: () {
          final RenderObject? ro = _inspectorKey.currentContext
              ?.findRenderObject();
          if (ro is RenderReportInspector) {
            ro.editNext(backwards: _shift);
          } else {
            _c.commitPropertyEdit();
          }
        },
      );
    }
    if (key == LogicalKeyboardKey.f5) {
      _goPreview();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f6) {
      _c.toggleData();
      return KeyEventResult.handled;
    }
    if (_ctrl && key == LogicalKeyboardKey.keyP && widget.onPrint != null) {
      _print();
      return KeyEventResult.handled;
    }
    if (_ctrl &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.numpadAdd)) {
      _c.zoom = _c.zoom * 1.2;
      return KeyEventResult.handled;
    }
    if (_ctrl &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      _c.zoom = _c.zoom / 1.2;
      return KeyEventResult.handled;
    }
    if (_ctrl && key == LogicalKeyboardKey.digit0) {
      _c.fitWidth();
      return KeyEventResult.handled;
    }
    if (_ctrl && key == LogicalKeyboardKey.keyZ) {
      _shift ? _c.redo() : _c.undo();
      return KeyEventResult.handled;
    }
    if (_ctrl && key == LogicalKeyboardKey.keyY) {
      _c.redo();
      return KeyEventResult.handled;
    }
    if (_c.mode == ReportDesignMode.data) {
      return _dataKey(event);
    }
    if (_c.mode != ReportDesignMode.design) {
      if (key == LogicalKeyboardKey.escape) {
        _c.togglePreview();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_ctrl) {
      if (key == LogicalKeyboardKey.keyC) {
        _c.copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _c.cutSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _c.paste();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD) {
        _c.duplicateSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _c.selectAll();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_c.tool != ReportDesignTool.select) {
        _c.tool = ReportDesignTool.select;
      } else {
        _c.select(null);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final ReportElement? e = _c.primary;
      if (e is ReportTextElement) {
        _c.beginTextEdit(e.id);
      }
      return KeyEventResult.handled;
    }
    final double step = _shift
        ? 0.1 * _mm
        : (_c.snapToGrid ? _c.gridSize : _mm);
    final (double, double)? delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => (-step, 0),
      LogicalKeyboardKey.arrowRight => (step, 0),
      LogicalKeyboardKey.arrowUp => (0, -step),
      LogicalKeyboardKey.arrowDown => (0, step),
      _ => null,
    };
    if (delta != null) {
      if (_c.selection.isNotEmpty) {
        _c.nudge(delta.$1, delta.$2);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      final List<ReportElement> all = <ReportElement>[
        for (final (ReportBand, ReportElement) be in _c.template.allElements)
          be.$2,
      ];
      if (all.isNotEmpty) {
        final ReportElement? p = _c.primary;
        var i = p == null ? -1 : all.indexOf(p);
        i = _shift ? i - 1 : i + 1;
        _c.select(all[(i + all.length) % all.length].id);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves the explorer selection by ([dr], [dc]), starting at the first
  /// cell when nothing is selected.
  void _moveCell(int dr, int dc) {
    final ReportDataTableView t = _c.dataTable;
    if (t.rows.isEmpty && dr != 0) {
      return;
    }
    final int row = _c.dataRow;
    final int col = _c.dataColumn;
    if (row < 0 && col < 0) {
      _c.selectDataCell(t.rows.isEmpty ? -1 : 0, t.columns.isEmpty ? -1 : 0);
      return;
    }
    _c.selectDataCell(
      row < 0 ? (dr > 0 ? 0 : -1) : (row + dr).clamp(0, t.rows.length - 1),
      col < 0 ? 0 : (col + dc).clamp(0, t.columns.length - 1),
    );
  }

  KeyEventResult _dataKey(KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    final int row = _c.dataRow;
    final int col = _c.dataColumn;
    final (int, int)? move = switch (key) {
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      LogicalKeyboardKey.arrowLeft => (0, -1),
      LogicalKeyboardKey.arrowRight => (0, 1),
      LogicalKeyboardKey.tab => (0, _shift ? -1 : 1),
      LogicalKeyboardKey.pageUp => (-20, 0),
      LogicalKeyboardKey.pageDown => (20, 0),
      _ => null,
    };
    if (move != null) {
      _moveCell(move.$1, move.$2);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (row >= 0 || col >= 0) {
        _c.selectDataCell(-1, -1);
      } else {
        _c.toggleData();
      }
      return KeyEventResult.handled;
    }
    if (_ctrl) {
      if (key == LogicalKeyboardKey.keyC && row >= 0 && col >= 0) {
        Clipboard.setData(
          ClipboardData(
            text: ReportDesignerController.dataCellText(
              _c.dataTable.rows[row][col],
            ),
          ),
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV && row >= 0 && col >= 0) {
        Clipboard.getData(Clipboard.kTextPlain).then((ClipboardData? data) {
          final String? text = data?.text;
          if (text != null && mounted) {
            _c.setDataCell(row, col, text.trim());
          }
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!_c.beginCellEdit(row, col) && row >= 0) {
        _moveCell(1, 0);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (row >= 0 && col >= 0) {
        _c.setDataCell(row, col, '');
      } else if (row >= 0 && col < 0 && !_c.dataTable.isFields) {
        _c.removeDataRows(<int>[row]);
      }
      return KeyEventResult.handled;
    }
    final String? ch = event.character;
    if (ch != null &&
        ch.isNotEmpty &&
        ch.codeUnitAt(0) >= 0x20 &&
        ch.codeUnitAt(0) != 0x7F &&
        row >= 0 &&
        col >= 0) {
      _c.beginCellEdit(row, col, initial: ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _cellEditKey(KeyEvent event, ({int row, int column}) cell) {
    final LogicalKeyboardKey key = event.logicalKey;
    final (int, int)? move = switch (key) {
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter => (_shift ? -1 : 1, 0),
      LogicalKeyboardKey.tab => (0, _shift ? -1 : 1),
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      _ => null,
    };
    if (move != null) {
      _c.commitPropertyEdit();
      _c.selectDataCell(cell.row, cell.column);
      _moveCell(move.$1, move.$2);
      return KeyEventResult.handled;
    }
    return _editKey(
      _c.propertyEditor,
      event,
      multiline: false,
      commit: _c.commitPropertyEdit,
      cancel: _c.cancelPropertyEdit,
      tab: _c.commitPropertyEdit,
    );
  }

  void _dataMenu(ReportDataContextHit hit) {
    _activate();
    final ReportDataTableView t = _c.dataTable;
    final bool editable = _c.dataEditable;
    final bool fields = t.isFields;
    final bool shape = _c.shapeKeyForTable(t.name) != null;
    final List<OfficeContextAction> actions = <OfficeContextAction>[
      if (hit.area == ReportDataArea.cell &&
          _c.canEditDataCell(hit.row, hit.column))
        const OfficeContextAction(
          id: 'edit',
          label: 'Edit cell',
          icon: Icons.edit,
          shortcut: 'F2',
        ),
      if (hit.area == ReportDataArea.cell &&
          _c.canEditDataCell(hit.row, hit.column))
        const OfficeContextAction(
          id: 'clear',
          label: 'Clear cell',
          icon: Icons.backspace_outlined,
          shortcut: 'Del',
        ),
      if (!fields &&
          editable &&
          !shape &&
          hit.row >= 0) ...<OfficeContextAction>[
        const OfficeContextAction(
          id: 'rowAbove',
          label: 'Insert row above',
          icon: Icons.north,
          separatorBefore: true,
        ),
        const OfficeContextAction(
          id: 'rowBelow',
          label: 'Insert row below',
          icon: Icons.south,
        ),
        const OfficeContextAction(
          id: 'rowDelete',
          label: 'Delete row',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
      if (!fields &&
          editable &&
          !shape &&
          hit.row < 0 &&
          hit.area != ReportDataArea.table)
        const OfficeContextAction(
          id: 'rowAdd',
          label: 'Add row',
          icon: Icons.add,
        ),
      if (!fields && hit.area != ReportDataArea.table) ...<OfficeContextAction>[
        const OfficeContextAction(
          id: 'colAdd',
          label: 'Add column',
          icon: Icons.view_column_outlined,
          separatorBefore: true,
        ),
        const OfficeContextAction(
          id: 'calcAdd',
          label: 'Add calculated column',
          icon: Icons.functions,
        ),
        if (editable)
          const OfficeContextAction(
            id: 'constAdd',
            label: 'Add constant column',
            icon: Icons.push_pin_outlined,
          ),
      ],
      if (!fields && hit.column >= 0) ...<OfficeContextAction>[
        OfficeContextAction(
          id: 'colRename',
          label: 'Rename column "${t.columns[hit.column].name}"',
          icon: Icons.drive_file_rename_outline,
          enabled: editable,
        ),
        const OfficeContextAction(
          id: 'colDelete',
          label: 'Delete column',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
      if (fields && editable)
        const OfficeContextAction(
          id: 'fieldAdd',
          label: 'Add field',
          icon: Icons.add,
        ),
      if (fields && editable && hit.row >= 0)
        const OfficeContextAction(
          id: 'fieldDelete',
          label: 'Delete field',
          icon: Icons.delete_outline,
          danger: true,
        ),
      if (hit.area == ReportDataArea.table && !fields && !shape)
        const OfficeContextAction(
          id: 'tableDelete',
          label: 'Delete table',
          icon: Icons.delete_outline,
          danger: true,
        ),
      if (_c.dataPicker != null && editable)
        const OfficeContextAction(
          id: 'import',
          label: 'Import CSV / JSON…',
          icon: Icons.upload_file,
          separatorBefore: true,
        ),
    ];
    if (actions.isEmpty) {
      return;
    }
    _showMenu(hit.globalPosition, actions, (String id) {
      _c.inspectorPage = ReportInspectorPage.properties;
      switch (id) {
        case 'edit':
          _c.beginCellEdit(hit.row, hit.column);
        case 'clear':
          _c.setDataCell(hit.row, hit.column, '');
        case 'rowAbove':
          _c.addDataRow(at: hit.row);
        case 'rowBelow':
          _c.addDataRow(at: hit.row + 1);
        case 'rowDelete':
          _c.removeDataRows(<int>[hit.row]);
        case 'rowAdd':
          _c.addDataRow();
        case 'colAdd':
          _c.setProperty('data.col+', '');
        case 'calcAdd':
          _c.setProperty('data.calc+', '');
        case 'constAdd':
          _c.setProperty('data.const+', '');
        case 'colRename':
          _c.selectDataCell(-1, hit.column);
          _c.beginPropertyEdit('data.col.name');
        case 'colDelete':
          _c.removeDataColumn(t.columns[hit.column].name);
        case 'fieldAdd':
          _c.beginPropertyEdit('data.field+');
        case 'fieldDelete':
          _c.setProperty('data.field.remove', '');
        case 'tableDelete':
          _c.removeDataTable(hit.table);
        case 'import':
          _c.setProperty('data.import', '');
      }
    });
  }

  ReportProperty? _editingProperty() {
    final String? key = _c.editingProperty;
    for (final ReportProperty p in _c.properties) {
      if (p.key == key) {
        return p;
      }
    }
    return null;
  }

  /// Keys the IME does not deliver as text, plus keys the app-level
  /// [Shortcuts] would otherwise steal (arrows, Tab).
  KeyEventResult _editKey(
    InlineCellEditor ed,
    KeyEvent event, {
    required bool multiline,
    required VoidCallback commit,
    required VoidCallback cancel,
    required VoidCallback tab,
  }) {
    final LogicalKeyboardKey key = event.logicalKey;
    final bool shift = _shift;
    final String text = ed.formulaBar;
    if (_ctrl && key == LogicalKeyboardKey.space) {
      _c.triggerCompletion();
      return KeyEventResult.handled;
    }
    if (_c.completion != null) {
      final int? move = switch (key) {
        LogicalKeyboardKey.arrowDown => 1,
        LogicalKeyboardKey.arrowUp => -1,
        LogicalKeyboardKey.pageDown => ReportCompletionPopup.maxRows,
        LogicalKeyboardKey.pageUp => -ReportCompletionPopup.maxRows,
        _ => null,
      };
      if (move != null) {
        _c.moveCompletion(move);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.tab) &&
          !_ctrl &&
          _c.acceptCompletion()) {
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _c.dismissCompletion();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      cancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      tab();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_ctrl || !multiline) {
        commit();
      } else {
        ed.replaceRange(ed.selectionStart, ed.selectionEnd, '\n');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      ed.deleteBackward();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      ed.deleteForward();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final int dir = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      if (!shift && ed.hasSelection) {
        ed.setCaret(dir < 0 ? ed.selectionStart : ed.selectionEnd);
      } else if (_ctrl) {
        ed.setCaret(_wordEdge(text, ed.caretIndex, dir), extend: shift);
      } else {
        ed.moveCaret(dir, extend: shift);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      ed.setCaret(
        _ctrl ? 0 : text.lastIndexOf('\n', ed.caretIndex - 1) + 1,
        extend: shift,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      final int nl = text.indexOf('\n', ed.caretIndex);
      ed.setCaret(_ctrl || nl < 0 ? text.length : nl, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final bool up = key == LogicalKeyboardKey.arrowUp;
      final int caret = ed.caretIndex;
      final int start = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
      final int column = caret - start;
      int target;
      if (up) {
        if (start == 0) {
          target = 0;
        } else {
          final int prevStart = text.lastIndexOf('\n', start - 2) + 1;
          target = (prevStart + column).clamp(prevStart, start - 1);
        }
      } else {
        final int nl = text.indexOf('\n', caret);
        if (nl < 0) {
          target = text.length;
        } else {
          final int nextEnd = text.indexOf('\n', nl + 1);
          final int end = nextEnd < 0 ? text.length : nextEnd;
          target = (nl + 1 + column).clamp(nl + 1, end);
        }
      }
      ed.setCaret(target, extend: shift);
      return KeyEventResult.handled;
    }
    if (_ctrl) {
      if (key == LogicalKeyboardKey.keyA) {
        ed.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX) {
        if (ed.hasSelection) {
          Clipboard.setData(
            ClipboardData(
              text: text.substring(ed.selectionStart, ed.selectionEnd),
            ),
          );
          if (key == LogicalKeyboardKey.keyX) {
            ed.deleteBackward();
          }
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        Clipboard.getData(Clipboard.kTextPlain).then((ClipboardData? data) {
          final String? paste = data?.text;
          if (paste != null && ed.editing) {
            ed.replaceRange(
              ed.selectionStart,
              ed.selectionEnd,
              multiline ? paste : paste.replaceAll(RegExp(r'[\r\n]+'), ' '),
            );
          }
        });
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  static int _wordEdge(String text, int from, int dir) {
    var i = from;
    bool word(int at) {
      final int c = text.codeUnitAt(at);
      return c != 0x20 && c != 0x0A && c != 0x09;
    }

    if (dir < 0) {
      while (i > 0 && !word(i - 1)) {
        i--;
      }
      while (i > 0 && word(i - 1)) {
        i--;
      }
    } else {
      while (i < text.length && !word(i)) {
        i++;
      }
      while (i < text.length && word(i)) {
        i++;
      }
    }
    return i;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final OfficeTheme theme = widget.theme;
    final Widget surface = switch (_c.mode) {
      ReportDesignMode.design => ReportDesignerCanvas(
        controller: _c,
        theme: theme,
        onContextMenu: _canvasMenu,
        onActivate: _activate,
      ),
      ReportDesignMode.data => ReportDataExplorer(
        controller: _c,
        theme: theme,
        onContextMenu: _dataMenu,
        onActivate: _activate,
      ),
      ReportDesignMode.preview => ReportPreviewSurface(
        document: _c.previewLayout,
        error: _c.previewError?.toString(),
        zoom: _c.zoom,
        theme: theme,
        onZoom: (double z) => _c.zoom = z,
        onPickElement: (String id) {
          _c.mode = ReportDesignMode.design;
          _c.select(id);
        },
      ),
    };
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ReportToolbar(
            items: <ReportToolbarItem>[
              for (final ReportToolbarItem i in _toolbarItems())
                ReportToolbarItem(
                  id: i.id,
                  icon: i.icon,
                  tooltip: _t(i.tooltip),
                  label: i.label == null ? null : _t(i.label!),
                  enabled: i.enabled,
                  active: i.active,
                  separatorBefore: i.separatorBefore,
                ),
            ],
            status: _status(),
            theme: theme,
            onPressedAt: _onToolbar,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double toolbox = _c.mode == ReportDesignMode.design
                    ? ReportToolbox.width
                    : 0;
                final double width = _clampInspector(
                  _inspectorWidth,
                  box.maxWidth - toolbox,
                );
                final Widget work = _c.problemsOpen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: surface),
                          _problemsSplitter(theme, box.maxHeight),
                          SizedBox(
                            height: _clampProblems(
                              _problemsHeight,
                              box.maxHeight,
                            ),
                            child: ReportProblemsPanel(
                              controller: _c,
                              theme: theme,
                            ),
                          ),
                        ],
                      )
                    : surface;
                final bool design = _c.mode == ReportDesignMode.design;
                return Stack(
                  key: _workKey,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (design)
                          SizedBox(
                            width: ReportToolbox.width,
                            child: ReportToolbox(
                              key: _toolboxKey,
                              entries: _insertTools,
                              heading: _t('Insert'),
                              active: _c.tool,
                              theme: theme,
                              onPressed: (ReportDesignTool tool) {
                                _activate();
                                _c.tool = tool;
                              },
                              onHover: _onToolHover,
                            ),
                          ),
                        Expanded(child: work),
                        _splitter(theme, box.maxWidth),
                        SizedBox(
                          width: width,
                          child: ReportInspector(
                            key: _inspectorKey,
                            controller: _c,
                            theme: theme,
                            onChoose: _inspectorChoice,
                            onActivate: _activate,
                          ),
                        ),
                      ],
                    ),
                    if (design) _toolCard(box),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitterPainter extends CustomPainter {
  const _SplitterPainter({
    required this.line,
    required this.accent,
    required this.active,
    this.vertical = true,
  });

  final Color line;
  final Color accent;
  final bool active;

  /// A vertical line between side-by-side panes; false for a horizontal
  /// line between stacked panes.
  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    if (active) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = accent.withValues(alpha: 0.12),
      );
    }
    final Offset mid = size.center(Offset.zero);
    canvas.drawLine(
      vertical ? Offset(mid.dx, 0) : Offset(0, mid.dy),
      vertical ? Offset(mid.dx, size.height) : Offset(size.width, mid.dy),
      Paint()
        ..color = active ? accent : line
        ..strokeWidth = active ? 2 : 1,
    );
    if (active) {
      final Paint dot = Paint()..color = accent;
      for (int i = -1; i <= 1; i++) {
        canvas.drawCircle(
          vertical ? mid + Offset(0, i * 6.0) : mid + Offset(i * 6.0, 0),
          1.6,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SplitterPainter old) =>
      old.line != line ||
      old.accent != accent ||
      old.active != active ||
      old.vertical != vertical;
}
