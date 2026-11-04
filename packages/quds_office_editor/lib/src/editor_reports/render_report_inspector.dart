import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../embed/office_theme.dart';
import 'render_report_toolbar.dart';
import 'report_completion_popup.dart';
import 'report_designer_controller.dart';
import 'report_designer_strings.dart';
import 'report_inspector_glyphs.dart';

/// Choice-property click: hosts show the options and call
/// [ReportDesignerController.setProperty].
@immutable
class ReportInspectorChoice {
  /// ReportInspectorChoice API.
  const ReportInspectorChoice({
    required this.property,
    required this.globalPosition,
    this.options,
    this.details = const <String, String>{},
  });

  /// property API.
  final ReportProperty property;

  /// Where to anchor the options menu.
  final Offset globalPosition;

  /// Values to offer instead of [ReportProperty.options] (the presets of a
  /// combo field).
  final List<String>? options;

  /// Secondary text per option (format samples such as `1,234.50`).
  final Map<String, String> details;

  /// Values to show.
  List<String> get choices => options ?? property.options;
}

/// Property inspector of the report designer.
class ReportInspector extends LeafRenderObjectWidget {
  /// ReportInspector API.
  const ReportInspector({
    super.key,
    required this.controller,
    this.theme = OfficeTheme.light,
    this.onChoose,
    this.onActivate,
  });

  /// controller API.
  final ReportDesignerController controller;

  /// theme API.
  final OfficeTheme theme;

  /// Choice-property click.
  final ValueChanged<ReportInspectorChoice>? onChoose;

  /// Pointer down (hosts request keyboard focus).
  final VoidCallback? onActivate;

  @override
  RenderReportInspector createRenderObject(BuildContext context) =>
      RenderReportInspector(
        controller: controller,
        theme: theme,
        onChoose: onChoose,
        onActivate: onActivate,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportInspector renderObject,
  ) {
    renderObject
      ..controller = controller
      ..theme = theme
      ..onChoose = onChoose
      ..onActivate = onActivate;
  }
}

enum _RowKind {
  title,
  tabs,
  group,
  property,
  pair,
  glyphs,
  note,
  node,
  empty,
  search,
  imageCard,
  fontCard,
  formatBox,
}

class _Row {
  _Row(
    this.kind,
    this.rect, {
    this.props = const <ReportProperty>[],
    this.actions = const <ReportProperty>[],
    this.text = '',
    this.detail = '',
    this.severity = 0,
    this.node,
    this.index = -1,
    this.icon,
  });

  final _RowKind kind;
  final Rect rect;
  final List<ReportProperty> props;

  /// Action properties shown as icon buttons in a section heading.
  final List<ReportProperty> actions;
  final String text;
  final String detail;
  final int severity;
  final _VarNode? node;
  final int index;
  final IconData? icon;

  ReportProperty? get property => props.isEmpty ? null : props.first;

  ReportProperty? prop(String suffix) {
    for (final ReportProperty p in props) {
      if (p.key.endsWith(suffix)) {
        return p;
      }
    }
    return null;
  }
}

/// Folder or variable of the Variables explorer.
class _VarNode {
  _VarNode(this.path, this.name, this.depth, {this.variable, this.index = -1});

  final String path;
  final String name;
  final int depth;
  final ReportVariable? variable;

  /// Index of [variable] in [ReportTemplate.variables].
  final int index;
  final List<_VarNode> children = <_VarNode>[];
  int count = 0;

  bool get isFolder => variable == null;
}

enum _HitKind {
  group,
  edit,
  toggle,
  menu,
  segment,
  stepUp,
  stepDown,
  presets,
  palette,
  action,
  glyph,
  tab,
  node,
  nodeToggle,
  folderAction,
  expandAll,
  collapseAll,
}

class _Hit {
  const _Hit(
    this.kind,
    this.rect, {
    this.property,
    this.value = '',
    this.tip,
    this.icon,
    this.danger = false,
    this.active = false,
  });

  final _HitKind kind;
  final Rect rect;
  final ReportProperty? property;
  final String value;

  /// Tooltip shown after hovering.
  final String? tip;

  /// Glyph of an icon button.
  final IconData? icon;
  final bool danger;
  final bool active;

  String get id =>
      '${kind.name}|${property?.key}|$value|'
      '${rect.left.round()}|${rect.top.round()}';
}

/// Anatomy of a text field: box, editable text area, and adornments.
class _Field {
  _Field(this.box, this.text, {this.swatch, this.stepper, this.drop});

  final Rect box;
  final Rect text;
  final Rect? swatch;
  final Rect? stepper;
  final Rect? drop;
}

class _Swatch {
  const _Swatch(this.rect, this.value, this.color, this.label);

  final Rect rect;
  final String value;
  final Color? color;
  final String label;
}

/// Decoded preview of an embedded image.
class _Thumb {
  _Thumb(this.bytes);

  final Uint8List bytes;
  ui.Image? image;
  bool failed = false;
}

/// RenderBox behind [ReportInspector]: collapsible sections with icon
/// actions, switches, segmented buttons, steppers, preset combos, a color
/// palette, the variables explorer, image and font cards with previews, a
/// font picker that renders each family, and inline text editing.
///
/// Rows are laid out in reading order: when [ReportDesignerStrings.isRtl]
/// the canvas is mirrored once and text, icons, and edit fields are drawn
/// un-mirrored in place.
class RenderReportInspector extends RenderBox
    implements MouseTrackerAnnotation {
  /// RenderReportInspector API.
  RenderReportInspector({
    required this._controller,
    required this._theme,
    this.onChoose,
    this.onActivate,
  });

  ReportDesignerController _controller;
  OfficeTheme _theme;

  /// onChoose API.
  ValueChanged<ReportInspectorChoice>? onChoose;

  /// onActivate API.
  VoidCallback? onActivate;

  /// Title row height.
  static const double titleHeight = 56;

  /// Page tabs height (Properties / Variables / Images / Fonts).
  static const double tabsHeight = 36;

  /// Section heading height.
  static const double groupHeight = 32;

  /// Property row height.
  static const double rowHeight = 32;

  static const double _pad = 12;
  static const double _font = 12;
  static const double _sectionGap = 6;
  static const double _nodeHeight = 28;
  static const double _indent = 16;
  static const double _iconButton = 26;
  static const double _fontRowHeight = 48;
  static const int _fontMaxRows = 7;
  static const Duration _tipDelay = Duration(milliseconds: 450);

  double _scroll = 0;
  Offset? _hover;
  double _editScrollX = 0;
  final ReportCompletionPopup _popup = ReportCompletionPopup();
  Rect? _popupRect;
  (Offset, Offset)? _editCaret;
  Offset? _editOrigin;
  final Map<String, TextPainter> _cache = <String, TextPainter>{};
  List<_Row> _rows = <_Row>[];
  double _contentHeight = 0;
  final Set<String> _collapsed = <String>{};
  final Set<String> _closedFolders = <String>{};

  String? _paletteKey;
  Rect? _paletteAnchor;
  Rect? _paletteRect;
  List<_Swatch> _swatches = <_Swatch>[];

  Rect? _fontPopupRect;
  int _fontFirst = 0;
  int _fontVisible = 0;
  int _fontIndexSeen = -1;

  final Map<String, _Thumb> _thumbs = <String, _Thumb>{};

  Timer? _tipTimer;
  String? _tipId;
  bool _tipShown = false;

  /// controller API.
  ReportDesignerController get controller => _controller;

  set controller(ReportDesignerController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _controller = value;
    markNeedsPaint();
  }

  /// theme API.
  OfficeTheme get theme => _theme;

  set theme(OfficeTheme value) {
    if (identical(value, _theme)) {
      return;
    }
    _theme = value;
    _clearCache();
    markNeedsPaint();
  }

  /// Whether section [group] is collapsed.
  bool isCollapsed(String group) => _collapsed.contains(group);

  /// Collapses or expands section [group].
  void setCollapsed(String group, bool collapsed) {
    if (collapsed ? _collapsed.add(group) : _collapsed.remove(group)) {
      markNeedsPaint();
    }
  }

  /// Key of the property whose color palette is open, if any.
  String? get paletteKey => _paletteKey;

  /// Opens the color palette of color property [key] (null closes it).
  void openPalette(String? key) {
    _paletteKey = key;
    _paletteAnchor = null;
    markNeedsPaint();
  }

  /// Whether variable folder [path] is collapsed in the explorer.
  bool isFolderClosed(String path) =>
      _closedFolders.contains(path.toLowerCase());

  /// Collapses or expands variable folder [path].
  void setFolderClosed(String path, bool closed) {
    final String k = path.toLowerCase();
    if (closed ? _closedFolders.add(k) : _closedFolders.remove(k)) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _hideTip();
    super.detach();
  }

  @override
  void dispose() {
    _popup.dispose();
    _clearCache();
    _clearThumbs();
    _hideTip();
    super.dispose();
  }

  void _clearCache() {
    for (final TextPainter tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }

  void _clearThumbs() {
    for (final _Thumb t in _thumbs.values) {
      t.image?.dispose();
    }
    _thumbs.clear();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size s = constraints.biggest;
    return s.isFinite ? s : constraints.constrain(const Size(300, 600));
  }

  @override
  bool hitTestSelf(Offset position) {
    _hover = position;
    return true;
  }

  // ------------------------------------------------------------ language

  ReportDesignerStrings get _s => _controller.strings;

  bool get _rtl => _s.isRtl;

  static final RegExp _numbered = RegExp(r'^(.+?) (\d+)$');

  /// Translation of an English label, also for `Column 2` and
  /// `Table · name` shapes.
  String _tr(String english) {
    if (english.isEmpty) {
      return english;
    }
    final String direct = _s.t(english);
    if (direct != english) {
      return direct;
    }
    final RegExpMatch? n = _numbered.firstMatch(english);
    if (n != null) {
      final String head = _s.t(n[1]!);
      if (head != n[1]) {
        return '$head ${n[2]}';
      }
    }
    final int dot = english.indexOf(' · ');
    if (dot > 0) {
      return '${_s.t(english.substring(0, dot))} · '
          '${english.substring(dot + 3)}';
    }
    return english;
  }

  /// Direction of the first strong character of [text]; the interface
  /// direction when there is none.
  TextDirection _dirOf(String text) {
    for (final int c in text.runes) {
      if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFEFC)) {
        return TextDirection.rtl;
      }
      if ((c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A) ||
          (c >= 0xC0 && c <= 0x024F) ||
          (c >= 0x0370 && c <= 0x052F)) {
        return TextDirection.ltr;
      }
    }
    return _s.direction;
  }

  // ------------------------------------------------------------ colors

  bool get _dark => _theme.chromeFill.computeLuminance() < 0.35;

  Color get _bg => _theme.chromeFill;

  Color get _ink => _theme.chromeText;

  Color get _muted => _ink.withValues(alpha: 0.62);

  Color get _faint => _ink.withValues(alpha: 0.38);

  Color get _accent => _theme.selectionStroke;

  Color get _line => _ink.withValues(alpha: _dark ? 0.14 : 0.12);

  Color get _fieldFill => _dark
      ? Color.alphaBlend(const Color(0x14FFFFFF), _bg)
      : const Color(0xFFFFFFFF);

  Color get _cardFill => _dark
      ? Color.alphaBlend(const Color(0x0CFFFFFF), _bg)
      : const Color(0xFFFFFFFF);

  Color get _popupFill => _dark
      ? Color.alphaBlend(const Color(0x1AFFFFFF), _bg)
      : const Color(0xFFFFFFFF);

  Color get _headerBand => _dark
      ? Color.alphaBlend(const Color(0x08FFFFFF), _bg)
      : Color.alphaBlend(const Color(0x07000000), _bg);

  Color get _danger =>
      _dark ? const Color(0xFFFF7A7A) : const Color(0xFFC62828);

  Color get _editInk =>
      _dark ? const Color(0xFFF3F4F6) : const Color(0xFF111111);

  static const Color _folderTone = Color(0xFFD9A43A);
  static const Color _starTone = Color(0xFFF5B301);

  // ------------------------------------------------------------ drawing

  Offset _logical(Offset p) => _rtl ? Offset(size.width - p.dx, p.dy) : p;

  Rect _physical(Rect r) => _rtl
      ? Rect.fromLTRB(
          size.width - r.right,
          r.top,
          size.width - r.left,
          r.bottom,
        )
      : r;

  Offset? get _hoverL => _hover == null ? null : _logical(_hover!);

  /// Paints [tp] with its reading-order start at logical [at].
  void _draw(Canvas canvas, TextPainter tp, Offset at) {
    if (!_rtl) {
      tp.paint(canvas, at);
      return;
    }
    canvas.save();
    canvas.translate(at.dx + tp.width, at.dy);
    canvas.scale(-1, 1);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _drawCentered(Canvas canvas, TextPainter tp, Offset center) =>
      _draw(canvas, tp, center - Offset(tp.width / 2, tp.height / 2));

  /// Runs [body] in an un-mirrored space whose origin is the physical
  /// top-left of logical [r].
  void _local(Canvas canvas, Rect r, void Function(Canvas c, Size s) body) {
    canvas.save();
    if (_rtl) {
      canvas.translate(r.right, r.top);
      canvas.scale(-1, 1);
    } else {
      canvas.translate(r.left, r.top);
    }
    body(canvas, r.size);
    canvas.restore();
  }

  TextPainter _text(
    String text,
    double fontSize,
    Color color,
    double maxWidth, {
    bool bold = false,
    bool italic = false,
    int lines = 1,
    String? family,
    bool center = false,
  }) {
    final TextDirection dir = _dirOf(text);
    final String key =
        '$text|$fontSize|${color.toARGB32()}|$maxWidth|$bold|$italic|$lines|'
        '$family|$center|${dir.index}';
    final TextPainter? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    if (_cache.length > 900) {
      _clearCache();
    }
    final String ui = _theme.fontFamily ?? 'Liberation Sans';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family ?? ui,
          fontFamilyFallback: <String>[
            if (family != null) ui,
            'Noto Naskh Arabic',
          ],
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: dir,
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth < 10 ? 10 : maxWidth);
    _cache[key] = tp;
    return tp;
  }

  TextPainter _iconPainter(IconData icon, double size, Color color) {
    final String key = 'icon|${icon.codePoint}|$size|${color.toARGB32()}';
    final TextPainter? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          height: 1,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _cache[key] = tp;
    return tp;
  }

  void _icon(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color c,
  ) => _drawCentered(canvas, _iconPainter(icon, size, c), center);

  // ------------------------------------------------------------ icons

  static IconData _actionIcon(String key) {
    if (key.endsWith('.remove')) {
      return Icons.delete_outline;
    }
    if (key.endsWith('.insert')) {
      return Icons.post_add;
    }
    if (key.endsWith('.replace')) {
      return Icons.find_replace;
    }
    return switch (key) {
      'var+' || 'vfolder.add' => Icons.add,
      'vfolder+' => Icons.create_new_folder_outlined,
      'image+' || 'source.import' => Icons.add_photo_alternate_outlined,
      'font+' => Icons.upload_file,
      'data.row+' => Icons.playlist_add,
      'data.col+' => Icons.view_column_outlined,
      'data.calc+' => Icons.functions,
      'data.import' => Icons.file_upload_outlined,
      'data.reset' => Icons.restart_alt,
      _ => key.endsWith('+') ? Icons.add : Icons.bolt_outlined,
    };
  }

  static IconData _groupIcon(String group) {
    switch (group) {
      case 'Layout':
        return Icons.straighten;
      case 'Text':
        return Icons.text_fields;
      case 'Font':
        return Icons.font_download_outlined;
      case 'Box':
        return Icons.crop_square;
      case 'Style':
        return Icons.brush_outlined;
      case 'Image':
        return Icons.image_outlined;
      case 'Barcode':
        return Icons.qr_code_2;
      case 'Shape':
        return Icons.category_outlined;
      case 'Chart':
        return Icons.bar_chart;
      case 'Data' || 'Sample data':
        return Icons.dataset_outlined;
      case 'Table':
        return Icons.table_chart_outlined;
      case 'Band':
        return Icons.view_day_outlined;
      case 'Report':
        return Icons.description_outlined;
      case 'Page':
        return Icons.insert_drive_file_outlined;
      case 'Paging':
        return Icons.auto_stories_outlined;
      case 'Palette':
        return Icons.palette_outlined;
      case 'Fields':
        return Icons.list_alt;
      case 'Template variables' || 'Variable':
        return Icons.data_object;
      case 'Folder':
        return Icons.folder_outlined;
      case 'Embedded images':
        return Icons.photo_library_outlined;
      case 'Add a font':
        return Icons.add_circle_outline;
      case 'Embedded fonts':
        return Icons.font_download_outlined;
      case 'Diagnostics':
        return Icons.health_and_safety_outlined;
    }
    if (group.startsWith('Series')) {
      return Icons.stacked_line_chart;
    }
    if (group.startsWith('Point')) {
      return Icons.scatter_plot_outlined;
    }
    if (group.startsWith('Column')) {
      return Icons.view_column_outlined;
    }
    if (group.startsWith('Table')) {
      return Icons.table_chart_outlined;
    }
    return Icons.tune;
  }

  static IconData _typeIcon(ReportVariableType type) => switch (type) {
    ReportVariableType.text => Icons.text_fields,
    ReportVariableType.number => Icons.tag,
    ReportVariableType.boolean => Icons.toggle_on_outlined,
    ReportVariableType.date => Icons.event,
    ReportVariableType.list => Icons.format_list_bulleted,
    ReportVariableType.expression => Icons.functions,
  };

  // ------------------------------------------------------------ geometry

  double get _labelWidth => math.max(92, size.width * 0.38);

  Rect _valueRect(Rect row, {double trailing = 0}) => Rect.fromLTRB(
    _labelWidth,
    row.top + 4,
    size.width - _pad - trailing,
    row.bottom - 4,
  );

  Rect _formatButton(Rect row) =>
      Rect.fromLTWH(size.width - _pad - 22, row.center.dy - 11, 22, 22);

  List<Rect> _formatInner(Rect card, int count) => <Rect>[
    for (int i = 0; i < count; i++)
      Rect.fromLTWH(
        card.left,
        card.top + 6 + i * rowHeight,
        card.width,
        rowHeight,
      ),
  ];

  (Rect, Rect) _pairRects(Rect row) {
    final double w = (size.width - 2 * _pad - 8) / 2;
    return (
      Rect.fromLTWH(_pad, row.top + 4, w, row.height - 8),
      Rect.fromLTWH(_pad + w + 8, row.top + 4, w, row.height - 8),
    );
  }

  Rect _searchRect(Rect row) =>
      Rect.fromLTRB(_pad, row.top + 6, size.width - _pad, row.bottom - 6);

  Rect _cardRect(Rect row) =>
      Rect.fromLTRB(_pad, row.top + 4, size.width - _pad, row.bottom - 4);

  /// Icon buttons ending at logical [end], first one leftmost.
  List<Rect> _iconRects(double end, double centerY, int count) => <Rect>[
    for (int i = 0; i < count; i++)
      Rect.fromLTWH(
        end - (count - i) * (_iconButton + 2) + 2,
        centerY - _iconButton / 2,
        _iconButton,
        _iconButton,
      ),
  ];

  _Field _field(ReportProperty p, Rect f, {String prefix = ''}) {
    var left = f.left + 8;
    var right = f.right - 6;
    Rect? stepper;
    Rect? drop;
    Rect? swatch;
    if (p.isSteppable) {
      stepper = Rect.fromLTRB(
        f.right - 18,
        f.top + 1,
        f.right - 1,
        f.bottom - 1,
      );
      right = stepper.left - 3;
    }
    final bool font = ReportDesignerController.isFontKey(p.key);
    if ((p.presets.isNotEmpty || p.kind == ReportPropertyKind.color || font) &&
        p.key != 'font.add') {
      drop = Rect.fromLTRB(right - 16, f.top + 1, right + 2, f.bottom - 1);
      right = drop.left - 1;
    }
    if (p.kind == ReportPropertyKind.color) {
      swatch = Rect.fromLTWH(f.left + 5, f.center.dy - 7, 14, 14);
      left = swatch.right + 7;
    }
    if (p.key == 'font.add') {
      left = f.left + 30;
    }
    if (prefix.isNotEmpty) {
      left += _text(prefix, 10.5, _muted, 80, bold: true).width + 6;
    }
    return _Field(
      f,
      Rect.fromLTRB(left, f.top, math.max(left + 8, right), f.bottom),
      swatch: swatch,
      stepper: stepper,
      drop: drop,
    );
  }

  List<(String, Rect)>? _segments(ReportProperty p, Rect v) {
    final List<String> options = p.options;
    if (options.length < 2 || options.length > 6) {
      return null;
    }
    final List<(String, Rect)> out = <(String, Rect)>[];
    if (options.every(ReportInspectorGlyphs.has)) {
      final double w = math.min(32, v.width / options.length);
      final List<String> ordered = _rtl ? options.reversed.toList() : options;
      var x = v.left;
      for (final String o in ordered) {
        out.add((o, Rect.fromLTWH(x, v.top, w, v.height)));
        x += w;
      }
      return out;
    }
    if (options.length > 5) {
      return null;
    }
    final List<double> widths = <double>[
      for (final String o in options)
        _text(_s.option(o), 10.5, _ink, 200).width + 14,
    ];
    final double total = widths.fold(0, (double a, double b) => a + b);
    if (total > v.width) {
      return null;
    }
    final double extra = (v.width - total) / options.length;
    var x = v.left;
    for (int i = 0; i < options.length; i++) {
      final double w = widths[i] + extra;
      out.add((options[i], Rect.fromLTWH(x, v.top, w, v.height)));
      x += w;
    }
    return out;
  }

  Rect _switchRect(Rect v) => Rect.fromLTWH(v.left, v.center.dy - 9, 32, 18);

  List<Rect> _glyphRects(Rect row, int count) {
    final Rect v = _valueRect(row);
    return <Rect>[
      for (int i = 0; i < count; i++)
        Rect.fromLTWH(v.left + i * 34, v.top, 30, v.height),
    ];
  }

  // ------------------------------------------------------------ rows

  List<ReportDiagnostic> get _diag => _controller.problems;

  void _buildRows() {
    final List<_Row> rows = <_Row>[];
    var y = -_scroll;
    rows.add(
      _Row(_RowKind.title, Rect.fromLTWH(0, y, size.width, titleHeight)),
    );
    y += titleHeight;
    rows.add(_Row(_RowKind.tabs, Rect.fromLTWH(0, y, size.width, tabsHeight)));
    y += tabsHeight + 6;
    final List<ReportProperty> props = _controller.properties;
    switch (_controller.inspectorPage) {
      case ReportInspectorPage.variables:
        y = _variableRows(rows, y, props);
      case ReportInspectorPage.images:
        y = _imageRows(rows, y, props);
      case ReportInspectorPage.fonts:
        y = _fontRows(rows, y, props);
      case ReportInspectorPage.properties:
        y = _propertyRows(rows, y, props);
        if (_controller.selection.isEmpty &&
            _controller.selectedBand == null &&
            _controller.mode != ReportDesignMode.data) {
          y = _diagnosticRows(rows, y);
        }
    }
    y += 16;
    _rows = rows;
    _contentHeight = y + _scroll;
  }

  double _group(
    List<_Row> rows,
    double y,
    String group, {
    List<ReportProperty> actions = const <ReportProperty>[],
  }) {
    rows.add(
      _Row(
        _RowKind.group,
        Rect.fromLTWH(0, y, size.width, groupHeight),
        text: group,
        actions: actions,
      ),
    );
    return y + groupHeight;
  }

  double _propertyRows(List<_Row> rows, double y, List<ReportProperty> props) {
    final Map<String, List<ReportProperty>> actions =
        <String, List<ReportProperty>>{};
    final Map<String, List<ReportProperty>> nested =
        <String, List<ReportProperty>>{};
    for (final ReportProperty p in props) {
      if (p.nest != null) {
        (nested[p.nest!] ??= <ReportProperty>[]).add(p);
        continue;
      }
      if (p.kind == ReportPropertyKind.action) {
        (actions[p.group] ??= <ReportProperty>[]).add(p);
      }
    }
    String? group;
    var i = 0;
    while (i < props.length) {
      final ReportProperty p = props[i];
      if (p.nest != null) {
        i++;
        continue;
      }
      if (p.group != group) {
        if (group != null) {
          y += _sectionGap;
        }
        group = p.group;
        y = _group(
          rows,
          y,
          group,
          actions: actions[group] ?? const <ReportProperty>[],
        );
      }
      if (_collapsed.contains(group) || p.kind == ReportPropertyKind.action) {
        i++;
        continue;
      }
      if (p.pair &&
          i + 1 < props.length &&
          props[i + 1].pair &&
          props[i + 1].group == group) {
        rows.add(
          _Row(
            _RowKind.pair,
            Rect.fromLTWH(0, y, size.width, rowHeight),
            props: <ReportProperty>[p, props[i + 1]],
          ),
        );
        y += rowHeight;
        i += 2;
        continue;
      }
      if (p.glyph != null) {
        final List<ReportProperty> run = <ReportProperty>[p];
        while (i + run.length < props.length &&
            props[i + run.length].glyph != null &&
            props[i + run.length].group == group) {
          run.add(props[i + run.length]);
        }
        rows.add(
          _Row(
            _RowKind.glyphs,
            Rect.fromLTWH(0, y, size.width, rowHeight),
            props: run,
            text: 'Style',
          ),
        );
        y += rowHeight;
        i += run.length;
        continue;
      }
      final double h = _rowHeightFor(p);
      final String? box = switch (p.key) {
        'title' => 'title',
        'showLabels' => 'labels',
        'showLegend' => 'legend',
        _ => null,
      };
      final List<ReportProperty>? kids = box == null ? null : nested[box];
      rows.add(
        _Row(
          _RowKind.property,
          Rect.fromLTWH(0, y, size.width, h),
          props: <ReportProperty>[p],
          text: kids == null ? '' : box!,
        ),
      );
      y += h;
      if (kids != null && _controller.formatBox == box) {
        final double boxH = 8 + kids.length * rowHeight + 8;
        rows.add(
          _Row(
            _RowKind.formatBox,
            Rect.fromLTWH(8, y, size.width - 16, boxH),
            props: kids,
          ),
        );
        y += boxH + 4;
      }
      i++;
    }
    return y;
  }

  double _diagnosticRows(List<_Row> rows, double y) {
    const String title = 'Diagnostics';
    y = _group(rows, y + _sectionGap, title);
    if (_collapsed.contains(title)) {
      return y;
    }
    final List<ReportDiagnostic> diag = _diag;
    final List<(int, String)> notes = diag.isEmpty
        ? <(int, String)>[(0, _s.t('No problems found.'))]
        : <(int, String)>[
            for (final ReportDiagnostic d in diag)
              (d.isError ? 2 : 1, '${_s.diagnostic(d.summary)}\n${d.path}'),
          ];
    for (final (int severity, String note) in notes) {
      final TextPainter tp = _noteText(note);
      final double h = math.max(28, tp.height + 12);
      rows.add(
        _Row(
          _RowKind.note,
          Rect.fromLTWH(0, y, size.width, h),
          text: note,
          severity: severity,
        ),
      );
      y += h;
    }
    return y;
  }

  TextPainter _noteText(String note) =>
      _text(note, _font - 0.5, _ink, size.width - 2 * _pad - 24, lines: 5);

  double _emptyRow(
    List<_Row> rows,
    double y, {
    required IconData icon,
    required String title,
    required String detail,
    ReportProperty? action,
  }) {
    final double w = size.width - 2 * _pad - 32;
    final TextPainter t = _text(_s.t(title), 12.5, _ink, w, bold: true);
    final TextPainter d = _text(
      _s.t(detail),
      11,
      _muted,
      w,
      lines: 5,
      center: true,
    );
    final double h =
        12 + 66 + t.height + 6 + d.height + (action == null ? 16 : 54) + 6;
    rows.add(
      _Row(
        _RowKind.empty,
        Rect.fromLTWH(0, y, size.width, h),
        text: title,
        detail: detail,
        icon: icon,
        props: <ReportProperty>[?action],
      ),
    );
    return y + h;
  }

  double _variableRows(List<_Row> rows, double y, List<ReportProperty> props) {
    const String vars = 'Template variables';
    final List<ReportProperty> head = <ReportProperty>[
      for (final ReportProperty p in props)
        if (p.group == vars) p,
    ];
    y = _group(rows, y, vars, actions: head);
    if (!_collapsed.contains(vars)) {
      final List<_VarNode> nodes = _visibleNodes();
      if (nodes.isEmpty) {
        ReportProperty? add;
        for (final ReportProperty p in head) {
          if (p.key == 'var+') {
            add = p;
          }
        }
        y = _emptyRow(
          rows,
          y,
          icon: Icons.data_object,
          title: 'No template variables yet',
          detail:
              'Variables hold values you reuse across the report, such as a '
              'company name or a tax rate. Use dots to group them: stats.sum.',
          action: add,
        );
      } else {
        y += 4;
        for (final _VarNode n in nodes) {
          rows.add(
            _Row(
              _RowKind.node,
              Rect.fromLTWH(0, y, size.width, _nodeHeight),
              node: n,
            ),
          );
          y += _nodeHeight;
        }
        y += 4;
      }
    }
    final List<ReportProperty> rest = <ReportProperty>[
      for (final ReportProperty p in props)
        if (p.group != vars) p,
    ];
    if (rest.isNotEmpty) {
      y = _propertyRows(rows, y + _sectionGap, rest);
    }
    return y;
  }

  List<_VarNode> _variableTree() {
    final List<ReportVariable> vars = _controller.template.variables;
    final _VarNode root = _VarNode('', '', -1);
    final Map<String, _VarNode> folders = <String, _VarNode>{};
    for (int i = 0; i < vars.length; i++) {
      final ReportVariable v = vars[i];
      final List<String> parts = v.segments;
      var at = root;
      for (int d = 0; d < parts.length - 1; d++) {
        final String path = parts.sublist(0, d + 1).join('.');
        final _VarNode folder = folders.putIfAbsent(path.toLowerCase(), () {
          final _VarNode f = _VarNode(path, parts[d], d);
          at.children.add(f);
          return f;
        });
        folder.count++;
        at = folder;
      }
      at.children.add(
        _VarNode(v.name, parts.last, parts.length - 1, variable: v, index: i),
      );
    }
    void order(_VarNode n) {
      final List<_VarNode> sorted = <_VarNode>[
        ...n.children.where((_VarNode c) => c.isFolder),
        ...n.children.where((_VarNode c) => !c.isFolder),
      ];
      n.children
        ..clear()
        ..addAll(sorted);
      n.children.forEach(order);
    }

    order(root);
    return root.children;
  }

  List<_VarNode> _visibleNodes() {
    final List<_VarNode> out = <_VarNode>[];
    void walk(List<_VarNode> nodes) {
      for (final _VarNode n in nodes) {
        out.add(n);
        if (n.isFolder && !isFolderClosed(n.path)) {
          walk(n.children);
        }
      }
    }

    walk(_variableTree());
    return out;
  }

  double _imageRows(List<_Row> rows, double y, List<ReportProperty> props) {
    const String g = 'Embedded images';
    ReportProperty? add;
    for (final ReportProperty p in props) {
      if (p.key == 'image+') {
        add = p;
      }
    }
    y = _group(rows, y, g, actions: <ReportProperty>[?add]);
    if (_collapsed.contains(g)) {
      return y;
    }
    final List<String> names = _controller.imageNames;
    if (names.isEmpty) {
      return _emptyRow(
        rows,
        y,
        icon: Icons.photo_library_outlined,
        title: 'No embedded images yet',
        detail: add == null
            ? 'No embedded images. The host app has not enabled image import.'
            : 'Imported images are saved inside the .qrep.',
        action: add,
      );
    }
    y += 2;
    for (int i = 0; i < names.length; i++) {
      final String prefix = 'img.$i.';
      rows.add(
        _Row(
          _RowKind.imageCard,
          Rect.fromLTWH(0, y, size.width, 92),
          index: i,
          text: names[i],
          props: <ReportProperty>[
            for (final ReportProperty p in props)
              if (p.key.startsWith(prefix)) p,
          ],
        ),
      );
      y += 92;
    }
    return y;
  }

  double _fontRows(List<_Row> rows, double y, List<ReportProperty> props) {
    const String add = 'Add a font';
    ReportProperty? search;
    ReportProperty? import;
    for (final ReportProperty p in props) {
      if (p.key == 'font.add') {
        search = p;
      } else if (p.key == 'font+') {
        import = p;
      }
    }
    if (search != null || import != null) {
      y = _group(rows, y, add, actions: <ReportProperty>[?import]);
      if (search != null && !_collapsed.contains(add)) {
        rows.add(
          _Row(
            _RowKind.search,
            Rect.fromLTWH(0, y, size.width, 44),
            props: <ReportProperty>[search],
          ),
        );
        y += 44;
      }
      y += _sectionGap;
    }
    const String g = 'Embedded fonts';
    y = _group(rows, y, g);
    if (_collapsed.contains(g)) {
      return y;
    }
    final List<String> names = _controller.embeddedFamilies;
    if (names.isEmpty) {
      return _emptyRow(
        rows,
        y,
        icon: Icons.font_download_outlined,
        title: 'No embedded fonts yet',
        detail:
            'Embedded fonts are saved inside the .qrep so the report looks '
            'the same on every machine.',
      );
    }
    y += 2;
    for (int i = 0; i < names.length; i++) {
      final String prefix = 'font.$i.';
      rows.add(
        _Row(
          _RowKind.fontCard,
          Rect.fromLTWH(0, y, size.width, 104),
          index: i,
          text: names[i],
          props: <ReportProperty>[
            for (final ReportProperty p in props)
              if (p.key.startsWith(prefix)) p,
          ],
        ),
      );
      y += 104;
    }
    return y;
  }

  TextPainter _wideNote(ReportProperty p) => _text(
    _tr(p.value),
    _font - 0.5,
    _muted,
    size.width - 2 * _pad,
    italic: true,
    lines: 4,
  );

  double _rowHeightFor(ReportProperty p) {
    if (p.kind == ReportPropertyKind.note && p.label.isEmpty) {
      return math.max(rowHeight, _wideNote(p).height + 12);
    }
    if (_controller.editingProperty != p.key ||
        p.kind != ReportPropertyKind.multiline) {
      return rowHeight;
    }
    final TextPainter tp = _editPainter(p, _multilineWidth);
    final double h = math.max(
      rowHeight,
      math.min(tp.height, 8 * tp.preferredLineHeight) + 12,
    );
    tp.dispose();
    return h;
  }

  double get _multilineWidth => size.width - _pad - _labelWidth - 14;

  TextPainter _editPainter(ReportProperty p, double width) {
    final bool multi = p.kind == ReportPropertyKind.multiline;
    final String text = _controller.propertyEditor.formulaBar;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: _font,
          color: _editInk,
        ),
      ),
      textDirection: _dirOf(text),
    );
    if (multi) {
      tp.layout(maxWidth: width < 10 ? 10 : width);
    } else {
      tp.layout();
    }
    return tp;
  }

  _Row? _rowAt(Offset local) {
    for (final _Row r in _rows) {
      if (r.rect.contains(local)) {
        return r;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ hits

  ReportProperty _synthetic(String key) => ReportProperty(
    key: key,
    label: '',
    kind: ReportPropertyKind.action,
    value: '',
    group: '',
  );

  _Hit _actionHit(ReportProperty p, Rect r) => _Hit(
    _HitKind.action,
    r,
    property: p,
    tip: _tr(p.value.isEmpty ? p.label : p.value),
    icon: _actionIcon(p.key),
    danger: p.key.endsWith('.remove'),
  );

  List<_Hit> _hitsFor(_Row row) {
    switch (row.kind) {
      case _RowKind.group:
        return _groupHits(row);
      case _RowKind.property:
        final bool format = row.text.isNotEmpty;
        return <_Hit>[
          ..._fieldHits(
            row.property!,
            _valueRect(row.rect, trailing: format ? 28 : 0),
          ),
          if (format)
            _Hit(
              _HitKind.action,
              _formatButton(row.rect),
              property: _synthetic('format.${row.text}'),
              value: row.text,
              tip: _s.t('Format'),
              icon: Icons.format_size,
              active: _controller.formatBox == row.text,
            ),
        ];
      case _RowKind.formatBox:
        final List<Rect> inner = _formatInner(row.rect, row.props.length);
        return <_Hit>[
          for (int i = 0; i < inner.length; i++)
            ..._fieldHits(row.props[i], _valueRect(inner[i])),
        ];
      case _RowKind.pair:
        final (Rect a, Rect b) = _pairRects(row.rect);
        return <_Hit>[
          ..._fieldHits(row.props[0], a, prefix: _tr(row.props[0].label)),
          ..._fieldHits(row.props[1], b, prefix: _tr(row.props[1].label)),
        ];
      case _RowKind.glyphs:
        final List<Rect> rects = _glyphRects(row.rect, row.props.length);
        return <_Hit>[
          for (int i = 0; i < rects.length; i++)
            _Hit(
              _HitKind.glyph,
              rects[i],
              property: row.props[i],
              tip: _tr(row.props[i].label),
            ),
        ];
      case _RowKind.tabs:
        return <_Hit>[
          for (final (ReportInspectorPage page, Rect r) in _tabRects(row.rect))
            _Hit(_HitKind.tab, r, value: page.name, tip: _s.t(_tabLabel(page))),
        ];
      case _RowKind.node:
        return _nodeHits(row);
      case _RowKind.empty:
        final ReportProperty? p = row.property;
        if (p == null) {
          return const <_Hit>[];
        }
        return <_Hit>[_Hit(_HitKind.action, _emptyButton(row), property: p)];
      case _RowKind.search:
        return _fieldHits(row.property!, _searchRect(row.rect));
      case _RowKind.imageCard:
        return _imageHits(row);
      case _RowKind.fontCard:
        return _fontHits(row);
      case _RowKind.title:
      case _RowKind.note:
        return const <_Hit>[];
    }
  }

  List<_Hit> _groupHits(_Row row) {
    final bool explorer =
        row.text == 'Template variables' &&
        _controller.variableFolders.isNotEmpty;
    final int n = row.actions.length + (explorer ? 2 : 0);
    final List<Rect> rects = _iconRects(
      size.width - _pad,
      row.rect.center.dy,
      n,
    );
    final List<_Hit> out = <_Hit>[
      for (int i = 0; i < row.actions.length; i++)
        _actionHit(row.actions[i], rects[i]),
      if (explorer) ...<_Hit>[
        _Hit(
          _HitKind.expandAll,
          rects[n - 2],
          tip: _s.t('Expand all'),
          icon: Icons.unfold_more,
        ),
        _Hit(
          _HitKind.collapseAll,
          rects[n - 1],
          tip: _s.t('Collapse all'),
          icon: Icons.unfold_less,
        ),
      ],
      _Hit(_HitKind.group, row.rect, value: row.text),
    ];
    return out;
  }

  double _nodeStart(_VarNode n) => _pad + n.depth * _indent;

  bool _nodeSelected(_VarNode n) =>
      _controller.selectedVariablePath?.toLowerCase() == n.path.toLowerCase();

  bool _nodeIconsVisible(_Row row) {
    final Offset? h = _hoverL;
    return _nodeSelected(row.node!) || (h != null && row.rect.contains(h));
  }

  List<_Hit> _nodeHits(_Row row) {
    final _VarNode n = row.node!;
    final Rect r = row.rect;
    final double x = _nodeStart(n);
    final List<_Hit> out = <_Hit>[];
    if (_nodeIconsVisible(row)) {
      final List<Rect> icons = _iconRects(size.width - _pad, r.center.dy, 2);
      if (n.isFolder) {
        out
          ..add(
            _Hit(
              _HitKind.folderAction,
              icons[0],
              property: _synthetic('vfolder.add'),
              value: n.path,
              tip: _s.t('Add variable here'),
              icon: Icons.add,
            ),
          )
          ..add(
            _Hit(
              _HitKind.folderAction,
              icons[1],
              property: _synthetic('vfolder.remove'),
              value: n.path,
              tip: _s.t('Delete folder'),
              icon: Icons.delete_outline,
              danger: true,
            ),
          );
      } else {
        out
          ..add(
            _actionHit(
              ReportProperty(
                key: 'var.${n.index}.insert',
                label: '',
                kind: ReportPropertyKind.action,
                value: 'Insert into report',
                group: '',
              ),
              icons[0],
            ),
          )
          ..add(
            _actionHit(
              ReportProperty(
                key: 'var.${n.index}.remove',
                label: '',
                kind: ReportPropertyKind.action,
                value: 'Remove variable',
                group: '',
              ),
              icons[1],
            ),
          );
      }
    }
    if (n.isFolder) {
      out.add(
        _Hit(
          _HitKind.nodeToggle,
          Rect.fromLTWH(x - 4, r.top, 22, r.height),
          value: n.path,
        ),
      );
    }
    out.add(_Hit(_HitKind.node, r, value: n.path));
    return out;
  }

  ({Rect card, Rect thumb, Rect name, List<Rect> icons}) _imageParts(Rect row) {
    final Rect card = _cardRect(row);
    final Rect thumb = Rect.fromLTWH(card.left + 8, card.top + 8, 68, 68);
    final List<Rect> icons = _iconRects(card.right - 6, card.top + 22, 2);
    final Rect name = Rect.fromLTRB(
      thumb.right + 10,
      card.top + 8,
      icons.first.left - 6,
      card.top + 36,
    );
    return (card: card, thumb: thumb, name: name, icons: icons);
  }

  List<_Hit> _imageHits(_Row row) {
    final parts = _imageParts(row.rect);
    final ReportProperty? name = row.prop('.name');
    final ReportProperty? replace = row.prop('.replace');
    final ReportProperty? insert = row.prop('.insert');
    final ReportProperty? remove = row.prop('.remove');
    return <_Hit>[
      if (replace != null)
        _Hit(
          _HitKind.action,
          parts.thumb,
          property: replace,
          tip: _tr(replace.value),
        ),
      if (insert != null) _actionHit(insert, parts.icons[0]),
      if (remove != null) _actionHit(remove, parts.icons[1]),
      if (name != null) ..._fieldHits(name, parts.name),
    ];
  }

  ({Rect card, Rect preview, List<Rect> icons}) _fontParts(Rect row) {
    final Rect card = _cardRect(row);
    final List<Rect> icons = _iconRects(card.right - 6, card.top + 20, 2);
    final Rect preview = Rect.fromLTRB(
      card.left + 12,
      card.top + 8,
      icons.first.left - 6,
      card.top + 40,
    );
    return (card: card, preview: preview, icons: icons);
  }

  List<_Hit> _fontHits(_Row row) {
    final parts = _fontParts(row.rect);
    final ReportProperty? star = row.prop('.default');
    final ReportProperty? remove = row.prop('.remove');
    final bool on = star?.value == 'true';
    return <_Hit>[
      if (star != null)
        _Hit(
          _HitKind.toggle,
          parts.icons[0],
          property: star,
          tip: _s.t(on ? 'Report default' : 'Make report default'),
          icon: on ? Icons.star : Icons.star_border,
          active: on,
        ),
      if (remove != null) _actionHit(remove, parts.icons[1]),
    ];
  }

  Rect _emptyButton(_Row row) {
    final ReportProperty p = row.property!;
    final TextPainter tp = _text(
      _tr(p.value),
      _font,
      const Color(0xFFFFFFFF),
      220,
    );
    final double w = tp.width + 44;
    return Rect.fromCenter(
      center: Offset(size.width / 2, row.rect.bottom - 30),
      width: w,
      height: 30,
    );
  }

  List<_Hit> _fieldHits(ReportProperty p, Rect v, {String prefix = ''}) {
    switch (p.kind) {
      case ReportPropertyKind.toggle:
        return <_Hit>[_Hit(_HitKind.toggle, _switchRect(v), property: p)];
      case ReportPropertyKind.choice:
        final List<(String, Rect)>? segments = _segments(p, v);
        if (segments != null) {
          return <_Hit>[
            for (final (String option, Rect r) in segments)
              _Hit(
                _HitKind.segment,
                r,
                property: p,
                value: option,
                tip: ReportInspectorGlyphs.has(option)
                    ? _s.option(option)
                    : null,
              ),
          ];
        }
        return <_Hit>[_Hit(_HitKind.menu, v, property: p)];
      case ReportPropertyKind.action:
        return <_Hit>[_actionHit(p, v)];
      case ReportPropertyKind.note:
        return const <_Hit>[];
      case ReportPropertyKind.text:
      case ReportPropertyKind.multiline:
      case ReportPropertyKind.length:
      case ReportPropertyKind.number:
      case ReportPropertyKind.color:
      case ReportPropertyKind.expression:
        final _Field f = _field(p, v, prefix: prefix);
        final Rect? stepper = f.stepper;
        final Rect? drop = f.drop;
        final Rect? swatch = f.swatch;
        final bool color = p.kind == ReportPropertyKind.color;
        return <_Hit>[
          if (stepper != null) ...<_Hit>[
            _Hit(
              _HitKind.stepUp,
              Rect.fromLTRB(
                stepper.left,
                stepper.top,
                stepper.right,
                stepper.center.dy,
              ),
              property: p,
              tip: _s.t('Increase'),
            ),
            _Hit(
              _HitKind.stepDown,
              Rect.fromLTRB(
                stepper.left,
                stepper.center.dy,
                stepper.right,
                stepper.bottom,
              ),
              property: p,
              tip: _s.t('Decrease'),
            ),
          ],
          if (drop != null)
            _Hit(
              color ? _HitKind.palette : _HitKind.presets,
              drop,
              property: p,
              tip: _s.t(color ? 'Pick a color' : 'Suggestions'),
            ),
          if (swatch != null)
            _Hit(
              _HitKind.palette,
              swatch.inflate(3),
              property: p,
              tip: _s.t('Pick a color'),
            ),
          _Hit(_HitKind.edit, v, property: p),
        ];
    }
  }

  _Hit? _hitAt(Offset local) {
    final _Row? row = _rowAt(local);
    if (row == null) {
      return null;
    }
    for (final _Hit h in _hitsFor(row)) {
      if (h.rect.contains(local)) {
        return h;
      }
    }
    return null;
  }

  _Hit? _hoverHit() {
    final Offset? l = _hoverL;
    final Offset? p = _hover;
    if (l == null || p == null) {
      return null;
    }
    if ((_fontPopupRect?.contains(l) ?? false) ||
        (_paletteRect?.contains(l) ?? false) ||
        (_popupRect?.contains(p) ?? false)) {
      return null;
    }
    return _hitAt(l);
  }

  /// Field box, property, and prefix of the field editing [key].
  (ReportProperty, Rect, String)? _fieldFor(String key) {
    for (final _Row row in _rows) {
      switch (row.kind) {
        case _RowKind.property:
          final ReportProperty p = row.property!;
          if (p.key == key) {
            return (
              p,
              _valueRect(row.rect, trailing: row.text.isEmpty ? 0 : 28),
              '',
            );
          }
        case _RowKind.formatBox:
          final List<Rect> inner = _formatInner(row.rect, row.props.length);
          for (int i = 0; i < inner.length; i++) {
            final ReportProperty p = row.props[i];
            if (p.key == key) {
              return (p, _valueRect(inner[i]), '');
            }
          }
        case _RowKind.pair:
          final (Rect a, Rect b) = _pairRects(row.rect);
          for (int i = 0; i < 2; i++) {
            final ReportProperty p = row.props[i];
            if (p.key == key) {
              return (p, i == 0 ? a : b, _tr(p.label));
            }
          }
        case _RowKind.search:
          final ReportProperty p = row.property!;
          if (p.key == key) {
            return (p, _searchRect(row.rect), '');
          }
        case _RowKind.imageCard:
          final ReportProperty? p = row.prop('.name');
          if (p != null && p.key == key) {
            return (p, _imageParts(row.rect).name, '');
          }
        case _RowKind.title:
        case _RowKind.tabs:
        case _RowKind.group:
        case _RowKind.glyphs:
        case _RowKind.note:
        case _RowKind.node:
        case _RowKind.empty:
        case _RowKind.fontCard:
          break;
      }
    }
    return null;
  }

  /// Text area of the field editing [key], in logical coordinates.
  Rect? _textRectFor(String key) {
    final (ReportProperty, Rect, String)? f = _fieldFor(key);
    if (f == null) {
      return null;
    }
    return _field(f.$1, f.$2, prefix: f.$3).text;
  }

  // ------------------------------------------------------------ events

  @override
  MouseCursor get cursor {
    final Offset? l = _hoverL;
    if (l == null) {
      return SystemMouseCursors.basic;
    }
    final Rect? palette = _paletteRect;
    if (palette != null && palette.contains(l)) {
      return _swatches.any((_Swatch s) => s.rect.contains(l))
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic;
    }
    final Rect? fonts = _fontPopupRect;
    if (fonts != null && fonts.contains(l)) {
      return SystemMouseCursors.click;
    }
    final _Hit? hit = _hitAt(l);
    if (hit == null) {
      return SystemMouseCursors.basic;
    }
    return hit.kind == _HitKind.edit
        ? SystemMouseCursors.text
        : SystemMouseCursors.click;
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (_) {
    _hover = null;
    _hideTip();
    markNeedsPaint();
  };

  @override
  bool get validForMouseTracker => attached;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerHoverEvent) {
      _hover = event.localPosition;
      _updateTip();
      markNeedsPaint();
      return;
    }
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (
        PointerSignalEvent e,
      ) {
        if (e is PointerScrollEvent) {
          _wheel(e.localPosition, e.scrollDelta.dy);
        }
      });
      return;
    }
    if (event is PointerPanZoomUpdateEvent) {
      _scrollBy(-event.localPanDelta.dy);
      return;
    }
    if (event is PointerDownEvent && event.buttons == kPrimaryButton) {
      onActivate?.call();
      _onTap(event.localPosition);
    }
  }

  void _wheel(Offset position, double dy) {
    final Rect? fonts = _fontPopupRect;
    final ReportCompletionResult? r = _controller.completion;
    if (fonts != null && r != null && fonts.contains(_logical(position))) {
      final int max = math.max(0, r.items.length - _fontVisible);
      final int step = dy.abs() > 60 ? 3 : 1;
      _fontFirst = (_fontFirst + (dy > 0 ? step : -step)).clamp(0, max);
      markNeedsPaint();
      return;
    }
    _scrollBy(dy);
  }

  void _scrollBy(double dy) {
    _closePalette();
    _hideTip();
    final double max = math.max(0, _contentHeight - size.height);
    _scroll = (_scroll + dy).clamp(0, max).toDouble();
    markNeedsPaint();
  }

  void _closePalette() {
    if (_paletteKey != null) {
      _paletteKey = null;
      _paletteAnchor = null;
      markNeedsPaint();
    }
  }

  void _updateTip() {
    final _Hit? h = _hoverHit();
    final String? id = h?.tip == null ? null : h!.id;
    if (id == _tipId) {
      return;
    }
    _tipTimer?.cancel();
    _tipTimer = null;
    _tipShown = false;
    _tipId = id;
    if (id != null) {
      _tipTimer = Timer(_tipDelay, () {
        _tipTimer = null;
        _tipShown = true;
        markNeedsPaint();
      });
    }
  }

  void _hideTip() {
    _tipTimer?.cancel();
    _tipTimer = null;
    _tipShown = false;
    _tipId = null;
  }

  int? _fontItemAt(Offset l) {
    final Rect? rect = _fontPopupRect;
    final ReportCompletionResult? r = _controller.completion;
    if (rect == null || r == null || r.items.isEmpty) {
      return null;
    }
    final int k = ((l.dy - rect.top - 4) / _fontRowHeight).floor();
    if (k < 0 || k >= _fontVisible) {
      return null;
    }
    final int i = _fontFirst + k;
    return i < r.items.length ? i : null;
  }

  void _onTap(Offset position) {
    _hideTip();
    _buildRows();
    final Offset local = _logical(position);
    final Rect? popup = _popupRect;
    final ReportCompletionResult? suggestions = _controller.completion;
    if (popup != null && suggestions != null && popup.contains(position)) {
      final int? i = ReportCompletionPopup.hitIndex(
        popup,
        position,
        suggestions.items.length,
        _controller.completionIndex,
      );
      if (i != null) {
        _controller.acceptCompletion(i);
      }
      return;
    }
    final Rect? fonts = _fontPopupRect;
    if (fonts != null && fonts.contains(local)) {
      final int? i = _fontItemAt(local);
      if (i != null) {
        _controller.acceptCompletion(i);
      }
      return;
    }
    final String? paletteKey = _paletteKey;
    if (paletteKey != null) {
      final Rect? rect = _paletteRect;
      if (rect != null && rect.contains(local)) {
        for (final _Swatch s in _swatches) {
          if (s.rect.contains(local)) {
            _closePalette();
            _controller.setProperty(paletteKey, s.value);
            return;
          }
        }
        return;
      }
      _closePalette();
      return;
    }
    final _Hit? hit = _hitAt(local);
    final String? editing = _controller.editingProperty;
    final ReportProperty? p = hit?.property;
    if (hit == null) {
      if (editing != null) {
        _controller.commitPropertyEdit();
      }
      return;
    }
    if (hit.kind == _HitKind.edit && p != null && editing == p.key) {
      final Offset? origin = _editOrigin;
      if (origin != null) {
        final TextPainter tp = _editPainter(p, _multilineWidth);
        _controller.propertyEditor.setCaret(
          tp.getPositionForOffset(position - origin).offset,
          extend: HardwareKeyboard.instance.isShiftPressed,
        );
        tp.dispose();
      }
      return;
    }
    if (editing != null) {
      _controller.commitPropertyEdit();
    }
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    switch (hit.kind) {
      case _HitKind.group:
        setCollapsed(hit.value, !_collapsed.contains(hit.value));
      case _HitKind.edit:
        _controller.beginPropertyEdit(p!.key);
      case _HitKind.toggle:
      case _HitKind.glyph:
        _controller.setProperty(p!.key, p.value == 'true' ? 'false' : 'true');
      case _HitKind.menu:
        onChoose?.call(
          ReportInspectorChoice(
            property: p!,
            globalPosition: localToGlobal(_physical(hit.rect).bottomLeft),
          ),
        );
      case _HitKind.segment:
        _controller.setProperty(p!.key, hit.value);
      case _HitKind.stepUp:
        _controller.stepProperty(p!.key, 1, large: shift);
      case _HitKind.stepDown:
        _controller.stepProperty(p!.key, -1, large: shift);
      case _HitKind.presets:
        if (ReportDesignerController.isFontKey(p!.key)) {
          _controller.beginPropertyEdit(p.key);
          return;
        }
        final Rect text = _physical(_textRectFor(p.key) ?? hit.rect);
        onChoose?.call(
          ReportInspectorChoice(
            property: p,
            globalPosition: localToGlobal(
              Offset(text.left - 6, hit.rect.bottom + 2),
            ),
            options: p.presets,
            details: _presetDetails(p),
          ),
        );
      case _HitKind.palette:
        _paletteKey = p!.key;
        final Rect? text = _textRectFor(p.key);
        _paletteAnchor = text == null
            ? hit.rect
            : Rect.fromLTRB(text.left - 24, text.top, text.right, text.bottom);
        markNeedsPaint();
      case _HitKind.action:
        if (p!.key.startsWith('format.')) {
          _controller.toggleFormatBox(p.key.substring('format.'.length));
          return;
        }
        _controller.setProperty(p.key, p.value);
      case _HitKind.folderAction:
        _controller.selectedVariablePath = hit.value;
        _controller.setProperty(p!.key, p.value);
      case _HitKind.node:
        _controller.selectedVariablePath = hit.value;
      case _HitKind.nodeToggle:
        setFolderClosed(hit.value, !isFolderClosed(hit.value));
      case _HitKind.expandAll:
        _closedFolders.clear();
        markNeedsPaint();
      case _HitKind.collapseAll:
        _closedFolders.addAll(
          _controller.variableFolders.map((String f) => f.toLowerCase()),
        );
        markNeedsPaint();
      case _HitKind.tab:
        final ReportInspectorPage page = ReportInspectorPage.values.byName(
          hit.value,
        );
        if (page != _controller.inspectorPage) {
          _scroll = 0;
          _controller.inspectorPage = page;
        }
    }
  }

  static Map<String, String> _presetDetails(ReportProperty p) {
    final String leaf = p.key.split('.').last;
    if (leaf != 'format' && leaf != 'valueFormat') {
      return const <String, String>{};
    }
    return <String, String>{
      for (final (String spec, String sample) in ReportCompleter.formats)
        spec: sample,
    };
  }

  /// Starts editing the textual property after the one being edited.
  void editNext({bool backwards = false}) {
    _buildRows();
    final List<ReportProperty> props = <ReportProperty>[
      for (final _Row r in _rows)
        for (final ReportProperty p in r.props)
          if (p.isTextual) p,
    ];
    if (props.isEmpty) {
      return;
    }
    final String? current = _controller.editingProperty;
    var i = props.indexWhere((ReportProperty p) => p.key == current);
    _controller.commitPropertyEdit();
    i = backwards ? i - 1 : i + 1;
    if (i < 0) {
      i = props.length - 1;
    }
    if (i >= props.length) {
      i = 0;
    }
    _controller.beginPropertyEdit(props[i].key);
  }

  String? _markSeen;

  static bool _marks(_Row row, String key) =>
      row.props.any((ReportProperty p) => p.key == key);

  /// Scrolls the row of property [key] into view.
  void _scrollToMark(String? key) {
    if (key == null) {
      return;
    }
    for (final _Row row in _rows) {
      if (!_marks(row, key)) {
        continue;
      }
      final double top = titleHeight + tabsHeight;
      if (row.rect.top >= top && row.rect.bottom <= size.height) {
        return;
      }
      final double max = math.max(0, _contentHeight - size.height);
      _scroll = (_scroll + row.rect.top - top - size.height / 4)
          .clamp(0, max)
          .toDouble();
      _buildRows();
      return;
    }
  }

  // ------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    _buildRows();
    final double max = math.max(0, _contentHeight - size.height);
    if (_scroll > max) {
      _scroll = max.toDouble();
      _buildRows();
    }
    final String? mark = _controller.highlightProperty;
    if (mark != _markSeen) {
      _markSeen = mark;
      _scrollToMark(mark);
    }
    _editCaret = null;
    _editOrigin = null;
    canvas.save();
    if (_rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final _Hit? hot = _hoverHit();
    for (final _Row row in _rows) {
      if (row.rect.bottom < 0 || row.rect.top > size.height) {
        continue;
      }
      if (mark != null && _marks(row, mark)) {
        canvas.drawRect(
          row.rect,
          Paint()..color = _danger.withValues(alpha: _dark ? 0.16 : 0.08),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, row.rect.top, 3, row.rect.height),
          Paint()..color = _danger,
        );
      }
      switch (row.kind) {
        case _RowKind.title:
          _paintTitle(canvas, row);
        case _RowKind.tabs:
          _paintTabs(canvas, row, hot);
        case _RowKind.group:
          _paintGroup(canvas, row, hot);
        case _RowKind.note:
          ReportInspectorGlyphs.status(
            canvas,
            Offset(_pad + 7, row.rect.top + 13),
            row.severity,
          );
          _draw(
            canvas,
            _noteText(row.text),
            Offset(_pad + 22, row.rect.top + 6),
          );
        case _RowKind.property:
          _paintProperty(canvas, row, hot);
        case _RowKind.formatBox:
          _paintFormatBox(canvas, row, hot);
        case _RowKind.pair:
          final (Rect a, Rect b) = _pairRects(row.rect);
          _paintControl(
            canvas,
            row.props[0],
            a,
            hot,
            prefix: _tr(row.props[0].label),
          );
          _paintControl(
            canvas,
            row.props[1],
            b,
            hot,
            prefix: _tr(row.props[1].label),
          );
        case _RowKind.glyphs:
          _paintLabel(canvas, row.text, row.rect);
          final List<Rect> rects = _glyphRects(row.rect, row.props.length);
          for (int i = 0; i < rects.length; i++) {
            _paintGlyphButton(canvas, row.props[i], rects[i], hot);
          }
        case _RowKind.node:
          _paintNode(canvas, row, hot);
        case _RowKind.empty:
          _paintEmpty(canvas, row, hot);
        case _RowKind.search:
          _paintField(canvas, row.property!, _searchRect(row.rect), hot);
        case _RowKind.imageCard:
          _paintImageCard(canvas, row, hot);
        case _RowKind.fontCard:
          _paintFontCard(canvas, row, hot);
      }
    }
    if (_contentHeight > size.height) {
      final double frac = size.height / _contentHeight;
      final double h = math.max(24, size.height * frac);
      final double top = (size.height - h) * (_scroll / math.max(1, max));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - 5, top, 3, h),
          const Radius.circular(2),
        ),
        Paint()..color = _ink.withValues(alpha: 0.22),
      );
    }
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()..color = _theme.pageBorder,
    );
    _paintFontPopup(canvas);
    _paintPalette(canvas);
    _paintTooltip(canvas, hot);
    canvas.restore();
    _popupRect = null;
    final (Offset, Offset)? caret = _editCaret;
    final String? editing = _controller.editingProperty;
    final ReportCompletionResult? r =
        caret == null ||
            editing == null ||
            ReportDesignerController.isFontKey(editing)
        ? null
        : _controller.completion;
    if (caret != null && r != null) {
      final Rect rect = ReportCompletionPopup.place(
        caret.$1,
        caret.$2,
        size,
        r.items.length,
      );
      _popupRect = rect;
      _popup.paint(canvas, rect, r, _controller.completionIndex, _theme);
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ title

  static String _spaced(String name) {
    final String s = name.replaceAllMapped(
      RegExp('([a-z])([A-Z])'),
      (Match m) => '${m[1]} ${m[2]!.toLowerCase()}',
    );
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  static final RegExp _elementsTitle = RegExp(r'^(\d+) elements$');

  String get _titleText {
    final String raw = _controller.inspectorTitle;
    final RegExpMatch? many = _elementsTitle.firstMatch(raw);
    if (many != null) {
      return _s.count(int.parse(many[1]!), 'element');
    }
    final int colon = raw.indexOf(': ');
    if (colon > 0 && _controller.selectedElements.length != 1) {
      final String head = raw.substring(0, colon);
      final String tail = raw.substring(colon + 2);
      return '${_s.t(head)}: ${head == 'Band' ? _s.t(_spaced(tail)) : tail}';
    }
    return _s.t(raw);
  }

  (ReportToolbarIcon, String) get _titleBadge {
    switch (_controller.inspectorPage) {
      case ReportInspectorPage.variables:
        final int n = _controller.template.variables.length;
        return (
          ReportToolbarIcon.variables,
          '${_s.count(n, 'variable')} · {{Variables.name}}',
        );
      case ReportInspectorPage.images:
        final int n = _controller.images.length;
        return (
          ReportToolbarIcon.image,
          '${_s.count(n, 'image')} · ${_s.t('saved in the .qrep')}',
        );
      case ReportInspectorPage.fonts:
        final int n = _controller.embeddedFonts.length;
        return (
          ReportToolbarIcon.font,
          '${_s.count(n, 'family')} · ${_s.t('saved in the .qrep')}',
        );
      case ReportInspectorPage.properties:
        break;
    }
    if (_controller.mode == ReportDesignMode.data) {
      return (ReportToolbarIcon.table, _s.t('Sample data'));
    }
    final List<ReportElement> sel = _controller.selectedElements;
    if (sel.length > 1) {
      return (
        ReportToolbarIcon.duplicate,
        _s.t('Shared properties of the selection'),
      );
    }
    if (sel.length == 1) {
      final ReportElement e = sel.first;
      final String band = _spaced(
        _controller.template.findElement(e.id)?.$1.kind.xmlName ?? '',
      );
      final (ReportToolbarIcon icon, String kind) = switch (e) {
        ReportTextElement() => (ReportToolbarIcon.text, 'Text'),
        ReportImageElement() => (ReportToolbarIcon.image, 'Image'),
        ReportTableElement() => (ReportToolbarIcon.table, 'Table'),
        ReportBarcodeElement(:final ReportBarcodeType symbology) =>
          symbology == ReportBarcodeType.qr
              ? (ReportToolbarIcon.qr, 'QR code')
              : (ReportToolbarIcon.barcode, 'Barcode'),
        ReportShapeElement(:final ReportShapeKind kind) => switch (kind) {
          ReportShapeKind.line => (ReportToolbarIcon.line, 'Line'),
          ReportShapeKind.ellipse => (ReportToolbarIcon.ellipse, 'Ellipse'),
          ReportShapeKind.rectangle || ReportShapeKind.roundedRectangle => (
            ReportToolbarIcon.rectangle,
            'Rectangle',
          ),
        },
        ReportChartElement(:final ReportChartType chartType) =>
          chartType.isShapeMap
              ? (ReportToolbarIcon.map, 'Map')
              : (ReportToolbarIcon.chart, 'Chart'),
        ReportCrosstabElement() => (ReportToolbarIcon.chart, 'Crosstab'),
        ReportSubreportElement() => (ReportToolbarIcon.text, 'Subreport'),
      };
      return (
        icon,
        band.isEmpty ? _s.t(kind) : '${_s.t(kind)} · ${_s.t(band)}',
      );
    }
    final ReportBandKind? band = _controller.selectedBand;
    if (band != null && _controller.template.band(band) != null) {
      final int n = _controller.template.band(band)!.elements.length;
      return (
        ReportToolbarIcon.sameHeight,
        '${_s.t(_spaced(band.xmlName))} · ${_s.count(n, 'element')}',
      );
    }
    final ReportTemplate t = _controller.template;
    return (
      ReportToolbarIcon.templates,
      '${_s.t('Report settings')} · ${_s.option(t.pageSize.name)} '
          '${_s.option(t.orientation.name)}',
    );
  }

  void _paintTitle(Canvas canvas, _Row row) {
    final Rect r = row.rect;
    canvas.drawRect(r, Paint()..color = _theme.headerFill);
    final (ReportToolbarIcon icon, String subtitle) = _titleBadge;
    final Rect badge = Rect.fromLTWH(_pad, r.center.dy - 17, 34, 34);
    final RRect rr = RRect.fromRectAndRadius(badge, const Radius.circular(9));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(badge.topLeft, badge.bottomRight, <Color>[
          Color.lerp(_accent, const Color(0xFFFFFFFF), 0.18)!,
          _accent,
        ]),
    );
    _local(canvas, badge, (Canvas c, Size s) {
      RenderReportToolbar.paintIcon(
        c,
        icon,
        Rect.fromCenter(
          center: Offset(s.width / 2, s.height / 2),
          width: 17,
          height: 17,
        ),
        const Color(0xFFFFFFFF),
      );
    });
    final double textLeft = badge.right + 11;
    final double width = size.width - textLeft - _pad;
    final TextPainter title = _text(_titleText, 14, _ink, width, bold: true);
    final TextPainter sub = _text(subtitle, 11, _muted, width);
    final double top = r.center.dy - (title.height + sub.height + 2) / 2;
    _draw(canvas, title, Offset(textLeft, top));
    _draw(canvas, sub, Offset(textLeft, top + title.height + 2));
  }

  // ------------------------------------------------------------ tabs

  static const List<(ReportInspectorPage, ReportToolbarIcon)> _tabs =
      <(ReportInspectorPage, ReportToolbarIcon)>[
        (ReportInspectorPage.properties, ReportToolbarIcon.select),
        (ReportInspectorPage.variables, ReportToolbarIcon.variables),
        (ReportInspectorPage.images, ReportToolbarIcon.image),
        (ReportInspectorPage.fonts, ReportToolbarIcon.font),
      ];

  static String _tabLabel(ReportInspectorPage page) => switch (page) {
    ReportInspectorPage.properties => 'Properties',
    ReportInspectorPage.variables => 'Variables',
    ReportInspectorPage.images => 'Images',
    ReportInspectorPage.fonts => 'Fonts',
  };

  List<(ReportInspectorPage, Rect)> _tabRects(Rect row) {
    final double w = (size.width - 2 * _pad) / _tabs.length;
    return <(ReportInspectorPage, Rect)>[
      for (int i = 0; i < _tabs.length; i++)
        (
          _tabs[i].$1,
          Rect.fromLTWH(_pad + i * w, row.top + 4, w, row.height - 4),
        ),
    ];
  }

  int? _tabCount(ReportInspectorPage page) => switch (page) {
    ReportInspectorPage.properties => null,
    ReportInspectorPage.variables => _controller.template.variables.length,
    ReportInspectorPage.images => _controller.images.length,
    ReportInspectorPage.fonts => _controller.embeddedFonts.length,
  };

  void _paintTabs(Canvas canvas, _Row row, _Hit? hot) {
    final Rect r = row.rect;
    canvas.drawRect(r, Paint()..color = _theme.headerFill);
    canvas.drawLine(r.bottomLeft, r.bottomRight, Paint()..color = _line);
    final List<(ReportInspectorPage, Rect)> rects = _tabRects(r);
    const double icon = 14;
    var showIcon = true;
    var showLabel = true;
    for (int i = 0; i < rects.length; i++) {
      final int? count = _tabCount(rects[i].$1);
      final double badge = count == null || count == 0
          ? 0
          : math.max(16, _text('$count', 9.5, _ink, 40, bold: true).width + 8) +
                4;
      final double widest = _text(
        _s.t(_tabLabel(rects[i].$1)),
        11.5,
        _ink,
        rects[i].$2.width,
        bold: true,
      ).width;
      if (icon + 5 + widest + badge > rects[i].$2.width - 6) {
        showIcon = false;
      }
      if (widest + badge > rects[i].$2.width - 6) {
        showLabel = false;
      }
    }
    if (!showLabel) {
      showIcon = true;
    }
    for (int i = 0; i < rects.length; i++) {
      final (ReportInspectorPage page, Rect t) = rects[i];
      final bool active = page == _controller.inspectorPage;
      final bool h =
          hot != null && hot.kind == _HitKind.tab && hot.value == page.name;
      if (h && !active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(t.deflate(2), const Radius.circular(6)),
          Paint()..color = _ink.withValues(alpha: 0.06),
        );
      }
      final Color ink = active ? _accent : _muted;
      final TextPainter label = _text(
        _s.t(_tabLabel(page)),
        11.5,
        active ? _ink : _muted,
        t.width,
        bold: active,
      );
      final int? count = _tabCount(page);
      final TextPainter? badge = count == null || count == 0
          ? null
          : _text(
              '$count',
              9.5,
              active ? const Color(0xFFFFFFFF) : _ink,
              40,
              bold: true,
            );
      final double badgeW = badge == null ? 0 : math.max(16, badge.width + 8);
      final double contentW =
          (showIcon ? icon + (showLabel ? 5 : 0) : 0) +
          (showLabel ? label.width : 0) +
          (badge == null ? 0 : badgeW + 4);
      var x = t.center.dx - contentW / 2;
      final double cy = t.center.dy - 1;
      if (showIcon) {
        final Rect ir = Rect.fromLTWH(x, cy - icon / 2, icon, icon);
        _local(canvas, ir, (Canvas c, Size s) {
          RenderReportToolbar.paintIcon(c, _tabs[i].$2, Offset.zero & s, ink);
        });
        x += icon + (showLabel ? 5 : 4);
      }
      if (showLabel) {
        _draw(canvas, label, Offset(x, cy - label.height / 2));
        x += label.width + 4;
      }
      if (badge != null) {
        final Rect b = Rect.fromLTWH(x, cy - 8, badgeW, 16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(b, const Radius.circular(8)),
          Paint()..color = active ? _accent : _ink.withValues(alpha: 0.1),
        );
        _drawCentered(canvas, badge, b.center);
      }
      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(t.left + 8, t.bottom - 2.5, t.width - 16, 2.5),
            const Radius.circular(1.5),
          ),
          Paint()..color = _accent,
        );
      }
    }
  }

  // ------------------------------------------------------------ sections

  void _paintIconButton(Canvas canvas, _Hit h, _Hit? hot) {
    final bool on = hot != null && hot.id == h.id;
    if (on) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h.rect, const Radius.circular(6)),
        Paint()
          ..color = h.danger
              ? _danger.withValues(alpha: 0.13)
              : _ink.withValues(alpha: 0.08),
      );
    }
    final Color tone = h.active
        ? _starTone
        : on
        ? (h.danger ? _danger : _ink)
        : _muted;
    _icon(canvas, h.icon!, h.rect.center, 18, tone);
  }

  void _paintGroup(Canvas canvas, _Row row, _Hit? hot) {
    final Rect r = row.rect;
    final List<_Hit> hits = _groupHits(row);
    final bool hover =
        hot != null && hot.kind == _HitKind.group && hot.value == row.text;
    canvas.drawRect(
      r,
      Paint()..color = hover ? _ink.withValues(alpha: 0.05) : _headerBand,
    );
    canvas.drawLine(r.topLeft, r.topRight, Paint()..color = _line);
    final bool open = !_collapsed.contains(row.text);
    ReportInspectorGlyphs.chevron(
      canvas,
      Offset(_pad + 4, r.center.dy),
      _muted,
      open: open,
    );
    _icon(
      canvas,
      _groupIcon(row.text),
      Offset(_pad + 22, r.center.dy),
      15,
      _accent,
    );
    final double end = hits.length > 1
        ? hits.first.rect.left - 6
        : size.width - _pad;
    final TextPainter tp = _text(
      _tr(row.text),
      12,
      _ink,
      end - (_pad + 34),
      bold: true,
    );
    _draw(canvas, tp, Offset(_pad + 34, r.center.dy - tp.height / 2));
    for (final _Hit h in hits) {
      if (h.icon != null) {
        _paintIconButton(canvas, h, hot);
      }
    }
  }

  void _paintLabel(Canvas canvas, String label, Rect row) {
    final TextPainter tp = _text(
      _tr(label),
      _font,
      _ink,
      _labelWidth - _pad - 6,
    );
    _draw(canvas, tp, Offset(_pad, row.top + (rowHeight - tp.height) / 2));
  }

  void _paintProperty(Canvas canvas, _Row row, _Hit? hot) {
    final ReportProperty p = row.property!;
    final Rect r = row.rect;
    final Offset? hover = _hoverL;
    if (hover != null && r.contains(hover) && _paletteKey == null) {
      canvas.drawRect(r, Paint()..color = _ink.withValues(alpha: 0.03));
    }
    if (p.kind == ReportPropertyKind.note && p.label.isEmpty) {
      _draw(canvas, _wideNote(p), Offset(_pad, r.top + 6));
      return;
    }
    final bool format = row.text.isNotEmpty;
    _paintLabel(canvas, p.label, r);
    _paintControl(canvas, p, _valueRect(r, trailing: format ? 28 : 0), hot);
    if (format) {
      _paintFormatButton(canvas, row, hot);
    }
  }

  void _paintFormatButton(Canvas canvas, _Row row, _Hit? hot) {
    final Rect b = _formatButton(row.rect);
    final bool open = _controller.formatBox == row.text;
    final bool h =
        hot != null && hot.kind == _HitKind.action && hot.value == row.text;
    final RRect rr = RRect.fromRectAndRadius(b, const Radius.circular(6));
    canvas.drawRRect(
      rr,
      Paint()..color = open || h ? _accent.withValues(alpha: 0.16) : _fieldFill,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = open ? _accent : _line
        ..style = PaintingStyle.stroke,
    );
    _icon(
      canvas,
      Icons.format_size,
      b.center,
      16,
      open || h ? _accent : _muted,
    );
  }

  void _paintFormatBox(Canvas canvas, _Row row, _Hit? hot) {
    final RRect rr = RRect.fromRectAndRadius(
      row.rect.deflate(1),
      const Radius.circular(8),
    );
    canvas.drawRRect(rr, Paint()..color = _fieldFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
    final List<Rect> inner = _formatInner(row.rect, row.props.length);
    for (int i = 0; i < inner.length; i++) {
      final ReportProperty p = row.props[i];
      _paintLabel(canvas, p.label, inner[i]);
      _paintControl(canvas, p, _valueRect(inner[i]), hot);
    }
  }

  bool _isHot(_Hit? hot, _HitKind kind, ReportProperty p, [String? value]) =>
      hot != null &&
      hot.kind == kind &&
      hot.property?.key == p.key &&
      (value == null || hot.value == value);

  void _paintControl(
    Canvas canvas,
    ReportProperty p,
    Rect v,
    _Hit? hot, {
    String prefix = '',
  }) {
    switch (p.kind) {
      case ReportPropertyKind.action:
        _paintIconButton(canvas, _actionHit(p, v), hot);
      case ReportPropertyKind.note:
        final TextPainter tp = _text(_tr(p.value), _font, _muted, v.width);
        _draw(canvas, tp, Offset(v.left, v.center.dy - tp.height / 2));
      case ReportPropertyKind.toggle:
        _paintSwitch(
          canvas,
          _switchRect(v),
          p.value == 'true',
          _isHot(hot, _HitKind.toggle, p),
        );
      case ReportPropertyKind.choice:
        final List<(String, Rect)>? segments = _segments(p, v);
        if (segments != null) {
          _paintSegments(canvas, p, v, segments, hot);
        } else {
          _paintBox(canvas, v, hover: _isHot(hot, _HitKind.menu, p));
          final TextPainter tp = _text(
            _s.option(p.value),
            _font,
            _ink,
            v.width - 30,
          );
          _draw(canvas, tp, Offset(v.left + 9, v.center.dy - tp.height / 2));
          ReportInspectorGlyphs.chevron(
            canvas,
            Offset(v.right - 12, v.center.dy),
            _muted,
          );
        }
      case ReportPropertyKind.text:
      case ReportPropertyKind.multiline:
      case ReportPropertyKind.length:
      case ReportPropertyKind.number:
      case ReportPropertyKind.color:
      case ReportPropertyKind.expression:
        _paintField(canvas, p, v, hot, prefix: prefix);
    }
  }

  void _paintBox(
    Canvas canvas,
    Rect v, {
    bool hover = false,
    bool focus = false,
  }) {
    final RRect rr = RRect.fromRectAndRadius(v, const Radius.circular(6));
    if (focus) {
      canvas.drawRRect(
        rr.inflate(2.5),
        Paint()..color = _theme.focusRing.withValues(alpha: 0.18),
      );
    }
    canvas.drawRRect(rr, Paint()..color = _fieldFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = focus
            ? _theme.focusRing
            : hover
            ? _accent.withValues(alpha: 0.7)
            : _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = focus ? 1.5 : 1,
    );
  }

  void _paintField(
    Canvas canvas,
    ReportProperty p,
    Rect v,
    _Hit? hot, {
    String prefix = '',
  }) {
    final _Field f = _field(p, v, prefix: prefix);
    final bool editing = _controller.editingProperty == p.key;
    final bool hover =
        hot != null &&
        hot.property?.key == p.key &&
        v.contains(hot.rect.center);
    _paintBox(canvas, v, hover: hover, focus: editing);
    if (p.key == 'font.add') {
      _icon(canvas, Icons.search, Offset(v.left + 15, v.center.dy), 17, _muted);
    }
    if (prefix.isNotEmpty) {
      final TextPainter tp = _text(prefix, 10.5, _muted, 80, bold: true);
      _draw(canvas, tp, Offset(v.left + 8, v.center.dy - tp.height / 2));
    }
    final Rect? swatch = f.swatch;
    if (swatch != null) {
      final ReportColor c = _controller.template.resolveColor(
        p.value,
        ReportColor.transparent,
      );
      final RRect rr = RRect.fromRectAndRadius(
        swatch,
        const Radius.circular(3),
      );
      if (c.alpha == 0) {
        canvas.save();
        canvas.clipRRect(rr);
        ReportInspectorGlyphs.noColor(canvas, swatch);
        canvas.restore();
      } else {
        canvas.drawRRect(rr, Paint()..color = Color(c.argb));
      }
      canvas.drawRRect(
        rr,
        Paint()
          ..color = _ink.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke,
      );
    }
    final Rect? stepper = f.stepper;
    if (stepper != null) {
      canvas.drawLine(
        Offset(stepper.left, stepper.top + 4),
        Offset(stepper.left, stepper.bottom - 4),
        Paint()..color = _line,
      );
      final Rect up = Rect.fromLTRB(
        stepper.left,
        stepper.top,
        stepper.right,
        stepper.center.dy,
      );
      final Rect down = Rect.fromLTRB(
        stepper.left,
        stepper.center.dy,
        stepper.right,
        stepper.bottom,
      );
      for (final (Rect r, bool isUp, _HitKind kind) in <(Rect, bool, _HitKind)>[
        (up, true, _HitKind.stepUp),
        (down, false, _HitKind.stepDown),
      ]) {
        final bool h = _isHot(hot, kind, p);
        if (h) {
          canvas.drawRect(
            r.deflate(1),
            Paint()..color = _accent.withValues(alpha: 0.15),
          );
        }
        ReportInspectorGlyphs.stepArrow(
          canvas,
          r.center.translate(0, isUp ? 0.5 : -0.5),
          h ? _accent : _muted,
          up: isUp,
        );
      }
    }
    final Rect? drop = f.drop;
    if (drop != null) {
      final bool h =
          _isHot(hot, _HitKind.presets, p) ||
          (_isHot(hot, _HitKind.palette, p) && hot!.rect == drop);
      if (h) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(drop.deflate(2), const Radius.circular(4)),
          Paint()..color = _accent.withValues(alpha: 0.15),
        );
      }
      ReportInspectorGlyphs.chevron(canvas, drop.center, h ? _accent : _muted);
    }
    if (editing) {
      _paintEditing(canvas, p, f.text);
      return;
    }
    final String raw = p.kind == ReportPropertyKind.multiline
        ? p.value.replaceAll('\n', ' ⏎ ')
        : p.value.trim();
    final bool empty = raw.isEmpty;
    if (empty && p.hint.isEmpty) {
      return;
    }
    final TextPainter tp = _text(
      empty ? _tr(p.hint) : raw,
      _font,
      empty ? _faint : _ink,
      f.text.width - 2,
      italic: empty && p.key != 'font.add',
    );
    _draw(canvas, tp, Offset(f.text.left, f.text.center.dy - tp.height / 2));
  }

  void _paintSwitch(Canvas canvas, Rect r, bool on, bool hover) {
    final RRect track = RRect.fromRectAndRadius(
      r,
      Radius.circular(r.height / 2),
    );
    canvas.drawRRect(
      track,
      Paint()..color = on ? _accent : _ink.withValues(alpha: hover ? 0.3 : 0.2),
    );
    final double knob = r.height - 4;
    final Offset c = Offset(
      on ? r.right - 2 - knob / 2 : r.left + 2 + knob / 2,
      r.center.dy,
    );
    canvas.drawCircle(
      c.translate(0, 0.6),
      knob / 2,
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawCircle(c, knob / 2, Paint()..color = const Color(0xFFFFFFFF));
  }

  void _paintSegments(
    Canvas canvas,
    ReportProperty p,
    Rect v,
    List<(String, Rect)> segments,
    _Hit? hot,
  ) {
    double right = v.left;
    for (final (String _, Rect r) in segments) {
      right = math.max(right, r.right);
    }
    final Rect outer = Rect.fromLTRB(v.left, v.top, right, v.bottom);
    final RRect rr = RRect.fromRectAndRadius(outer, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = _fieldFill);
    canvas.save();
    canvas.clipRRect(rr);
    for (int i = 0; i < segments.length; i++) {
      final (String option, Rect r) = segments[i];
      final bool selected = option == p.value;
      final bool h = _isHot(hot, _HitKind.segment, p, option);
      if (selected) {
        canvas.drawRect(r, Paint()..color = _accent);
      } else if (h) {
        canvas.drawRect(r, Paint()..color = _accent.withValues(alpha: 0.12));
      }
      if (i > 0 && !selected && segments[i - 1].$1 != p.value) {
        canvas.drawLine(
          Offset(r.left, r.top + 5),
          Offset(r.left, r.bottom - 5),
          Paint()..color = _line,
        );
      }
      final Color ink = selected ? const Color(0xFFFFFFFF) : _ink;
      if (ReportInspectorGlyphs.has(option)) {
        _local(canvas, r, (Canvas c, Size s) {
          ReportInspectorGlyphs.paint(c, option, Offset.zero & s, ink);
        });
      } else {
        final TextPainter tp = _text(
          _s.option(option),
          10.5,
          ink,
          r.width - 4,
          bold: selected,
        );
        _drawCentered(canvas, tp, r.center);
      }
    }
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintGlyphButton(Canvas canvas, ReportProperty p, Rect r, _Hit? hot) {
    final bool on = p.value == 'true';
    final bool h = _isHot(hot, _HitKind.glyph, p);
    final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = on
            ? _accent.withValues(alpha: 0.16)
            : h
            ? _accent.withValues(alpha: 0.08)
            : _fieldFill,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = on ? _accent : _line
        ..style = PaintingStyle.stroke,
    );
    _local(canvas, r, (Canvas c, Size s) {
      ReportInspectorGlyphs.paint(
        c,
        p.glyph ?? '',
        Offset.zero & s,
        on ? _accent : _ink,
      );
    });
  }

  void _paintEditing(Canvas canvas, ReportProperty p, Rect text) {
    final bool multi = p.kind == ReportPropertyKind.multiline;
    final TextPainter tp = _editPainter(p, _multilineWidth);
    final int caretIndex = _controller.propertyEditor.caretIndex;
    final Offset caret = tp.getOffsetForCaret(
      TextPosition(offset: caretIndex),
      Rect.zero,
    );
    final double inner = text.width - 4;
    final bool rtlText = tp.textDirection == TextDirection.rtl;
    final double dx;
    if (multi || tp.width <= inner) {
      _editScrollX = 0;
      dx = rtlText ? 2 + math.max(0, inner - tp.width) : 2;
    } else {
      if (caret.dx - _editScrollX > inner) {
        _editScrollX = caret.dx - inner + 2;
      } else if (caret.dx < _editScrollX) {
        _editScrollX = caret.dx;
      }
      dx = 2 - _editScrollX;
    }
    final double dy = multi ? 4 : (text.height - tp.height) / 2;
    final Rect phys = _physical(text);
    final Offset origin = Offset(phys.left + dx, phys.top + dy);
    _editOrigin = origin;
    final int start = _controller.propertyEditor.selectionStart;
    final int end = _controller.propertyEditor.selectionEnd;
    _local(canvas, text, (Canvas c, Size s) {
      c.save();
      c.clipRect(Rect.fromLTWH(1, 1, s.width - 2, s.height - 2));
      final Offset o = Offset(dx, dy);
      if (end > start) {
        for (final TextBox b in tp.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )) {
          c.drawRect(
            b.toRect().shift(o),
            Paint()..color = _accent.withValues(alpha: 0.3),
          );
        }
      }
      tp.paint(c, o);
      c.drawRect(
        Rect.fromLTWH(
          o.dx + caret.dx,
          o.dy + caret.dy,
          1.2,
          tp.preferredLineHeight,
        ),
        Paint()..color = _editInk,
      );
      c.restore();
    });
    final double cx = (origin.dx + caret.dx - 24).clamp(
      phys.left,
      math.max(phys.left, phys.right - 24),
    );
    _editCaret = (
      Offset(cx, origin.dy + caret.dy),
      Offset(cx, phys.bottom + 3),
    );
    tp.dispose();
  }

  // ------------------------------------------------------------ explorer

  void _paintNode(Canvas canvas, _Row row, _Hit? hot) {
    final _VarNode n = row.node!;
    final Rect r = row.rect;
    final bool selected = _nodeSelected(n);
    final Offset? hover = _hoverL;
    final bool hovered = hover != null && r.contains(hover);
    final Rect band = Rect.fromLTRB(
      _pad / 2,
      r.top + 1,
      size.width - _pad / 2,
      r.bottom - 1,
    );
    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(6)),
        Paint()..color = _accent.withValues(alpha: _dark ? 0.24 : 0.13),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(band.left, band.top + 5, 3, band.height - 10),
          const Radius.circular(1.5),
        ),
        Paint()..color = _accent,
      );
    } else if (hovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(6)),
        Paint()..color = _ink.withValues(alpha: 0.05),
      );
    }
    for (int d = 0; d < n.depth; d++) {
      final double gx = _pad + d * _indent + 6;
      canvas.drawLine(
        Offset(gx, r.top),
        Offset(gx, r.bottom),
        Paint()..color = _line,
      );
    }
    final double x = _nodeStart(n);
    final bool icons = _nodeIconsVisible(row);
    final double end = icons
        ? size.width - _pad - 2 * (_iconButton + 2) - 4
        : size.width - _pad - 4;
    double nameX;
    if (n.isFolder) {
      final bool open = !isFolderClosed(n.path);
      ReportInspectorGlyphs.chevron(
        canvas,
        Offset(x + 6, r.center.dy),
        _muted,
        open: open,
      );
      _icon(
        canvas,
        open ? Icons.folder_open : Icons.folder,
        Offset(x + 24, r.center.dy),
        17,
        _folderTone,
      );
      nameX = x + 36;
    } else {
      _icon(
        canvas,
        _typeIcon(n.variable!.type),
        Offset(x + 24, r.center.dy),
        15,
        _accent,
      );
      nameX = x + 36;
    }
    final TextPainter name = _text(
      n.name,
      _font,
      _ink,
      math.max(20, end - nameX),
      bold: n.isFolder || selected,
    );
    _draw(canvas, name, Offset(nameX, r.center.dy - name.height / 2));
    final double tailStart = nameX + name.width + 10;
    if (!icons && end - tailStart > 24) {
      final String tail = n.isFolder
          ? '${n.count}'
          : n.variable!.value.replaceAll('\n', ' ');
      if (tail.isNotEmpty) {
        final TextPainter tp = _text(
          tail,
          n.isFolder ? 10 : 11,
          n.isFolder ? _muted : _faint,
          end - tailStart,
          bold: n.isFolder,
        );
        if (n.isFolder) {
          final Rect chip = Rect.fromLTWH(
            end - tp.width - 10,
            r.center.dy - 8,
            tp.width + 10,
            16,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(chip, const Radius.circular(8)),
            Paint()..color = _ink.withValues(alpha: 0.08),
          );
          _drawCentered(canvas, tp, chip.center);
        } else {
          _draw(
            canvas,
            tp,
            Offset(end - tp.width, r.center.dy - tp.height / 2),
          );
        }
      }
    }
    if (icons) {
      for (final _Hit h in _nodeHits(row)) {
        if (h.icon != null) {
          _paintIconButton(canvas, h, hot);
        }
      }
    }
  }

  void _paintEmpty(Canvas canvas, _Row row, _Hit? hot) {
    final Rect card = Rect.fromLTRB(
      _pad,
      row.rect.top + 8,
      size.width - _pad,
      row.rect.bottom - 4,
    );
    final RRect rr = RRect.fromRectAndRadius(card, const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = _cardFill.withValues(alpha: 0.6));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
    final Offset c = Offset(card.center.dx, card.top + 34);
    canvas.drawCircle(c, 22, Paint()..color = _accent.withValues(alpha: 0.12));
    _icon(canvas, row.icon ?? Icons.info_outline, c, 24, _accent);
    final double w = size.width - 2 * _pad - 32;
    final TextPainter t = _text(_s.t(row.text), 12.5, _ink, w, bold: true);
    final double ty = card.top + 66;
    _drawCentered(canvas, t, Offset(card.center.dx, ty + t.height / 2));
    final TextPainter d = _text(
      _s.t(row.detail),
      11,
      _muted,
      w,
      lines: 5,
      center: true,
    );
    _drawCentered(
      canvas,
      d,
      Offset(card.center.dx, ty + t.height + 6 + d.height / 2),
    );
    final ReportProperty? p = row.property;
    if (p == null) {
      return;
    }
    final Rect b = _emptyButton(row);
    final bool h = _isHot(hot, _HitKind.action, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(b, const Radius.circular(8)),
      Paint()
        ..color = h
            ? Color.lerp(_accent, const Color(0xFF000000), 0.12)!
            : _accent,
    );
    _icon(
      canvas,
      _actionIcon(p.key),
      Offset(b.left + 17, b.center.dy),
      17,
      const Color(0xFFFFFFFF),
    );
    final TextPainter label = _text(
      _tr(p.value),
      _font,
      const Color(0xFFFFFFFF),
      220,
      bold: true,
    );
    _draw(canvas, label, Offset(b.left + 30, b.center.dy - label.height / 2));
  }

  // ------------------------------------------------------------ cards

  void _paintCard(Canvas canvas, Rect card, bool hover) {
    final RRect rr = RRect.fromRectAndRadius(card, const Radius.circular(10));
    if (!_dark) {
      canvas.drawRRect(
        rr.shift(const Offset(0, 1)),
        Paint()..color = const Color(0x0F000000),
      );
    }
    canvas.drawRRect(rr, Paint()..color = _cardFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = hover ? _accent.withValues(alpha: 0.5) : _line
        ..style = PaintingStyle.stroke,
    );
  }

  ui.Image? _thumb(String name) {
    final Uint8List? bytes = _controller.images[name];
    if (bytes == null) {
      return null;
    }
    final _Thumb? have = _thumbs[name];
    if (have != null && identical(have.bytes, bytes)) {
      return have.image;
    }
    have?.image?.dispose();
    final _Thumb t = _Thumb(bytes);
    _thumbs[name] = t;
    if (_thumbs.length > 64) {
      final String first = _thumbs.keys.first;
      _thumbs.remove(first)?.image?.dispose();
    }
    unawaited(_decode(name, t));
    return null;
  }

  Future<void> _decode(String name, _Thumb t) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        t.bytes,
        targetWidth: 160,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      if (!identical(_thumbs[name], t)) {
        frame.image.dispose();
        return;
      }
      t.image = frame.image;
    } on Object {
      t.failed = true;
    }
    if (attached) {
      markNeedsPaint();
    }
  }

  void _paintChecker(Canvas canvas, Rect r) {
    canvas.drawRect(
      r,
      Paint()
        ..color = _dark ? const Color(0xFF3A3D42) : const Color(0xFFFFFFFF),
    );
    final Paint dark = Paint()
      ..color = _dark ? const Color(0xFF2E3135) : const Color(0xFFE9ECEF);
    const double cell = 8;
    for (double y = r.top; y < r.bottom; y += cell) {
      for (double x = r.left; x < r.right; x += cell) {
        if ((((x - r.left) / cell).round() + ((y - r.top) / cell).round())
            .isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  void _paintImageCard(Canvas canvas, _Row row, _Hit? hot) {
    final parts = _imageParts(row.rect);
    final Offset? hover = _hoverL;
    _paintCard(canvas, parts.card, hover != null && parts.card.contains(hover));
    final String name = row.text;
    final RRect thumbR = RRect.fromRectAndRadius(
      parts.thumb,
      const Radius.circular(7),
    );
    canvas.save();
    canvas.clipRRect(thumbR);
    _paintChecker(canvas, parts.thumb);
    final ui.Image? image = _thumb(name);
    if (image != null) {
      _local(canvas, parts.thumb, (Canvas c, Size s) {
        final double k = math.min(
          s.width / image.width,
          s.height / image.height,
        );
        final Size fit = Size(image.width * k, image.height * k);
        c.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromCenter(
            center: Offset(s.width / 2, s.height / 2),
            width: fit.width,
            height: fit.height,
          ),
          Paint()..filterQuality = FilterQuality.medium,
        );
      });
    } else {
      final bool failed = _thumbs[name]?.failed ?? false;
      _icon(
        canvas,
        failed ? Icons.insert_photo_outlined : Icons.hourglass_empty,
        parts.thumb.center,
        22,
        _faint,
      );
    }
    if (row.prop('.replace') != null &&
        hover != null &&
        parts.thumb.contains(hover)) {
      canvas.drawRect(parts.thumb, Paint()..color = const Color(0x8C000000));
      _icon(
        canvas,
        Icons.find_replace,
        parts.thumb.center.translate(0, -7),
        20,
        const Color(0xFFFFFFFF),
      );
      final TextPainter tp = _text(
        _s.t('Replace'),
        10,
        const Color(0xFFFFFFFF),
        parts.thumb.width - 6,
        bold: true,
      );
      _draw(
        canvas,
        tp,
        Offset(parts.thumb.center.dx - tp.width / 2, parts.thumb.center.dy + 6),
      );
    }
    canvas.restore();
    canvas.drawRRect(
      thumbR,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
    final ReportProperty? nameProp = row.prop('.name');
    if (nameProp != null) {
      _paintField(canvas, nameProp, parts.name, hot);
    }
    final String group = nameProp?.group ?? '';
    final String info = group.startsWith('$name · ')
        ? group.substring(name.length + 3)
        : '';
    final double x = parts.name.left + 2;
    final double w = parts.card.right - 10 - x;
    if (info.isNotEmpty) {
      final TextPainter tp = _text(info, 11, _muted, w);
      _draw(canvas, tp, Offset(x, parts.name.bottom + 7));
    }
    final TextPainter ref = _text('source="$name"', 10.5, _faint, w);
    _draw(canvas, ref, Offset(x, parts.name.bottom + 24));
    for (final _Hit h in _imageHits(row)) {
      if (h.icon != null) {
        _paintIconButton(canvas, h, hot);
      }
    }
  }

  void _paintFontCard(Canvas canvas, _Row row, _Hit? hot) {
    final parts = _fontParts(row.rect);
    final Offset? hover = _hoverL;
    _paintCard(canvas, parts.card, hover != null && parts.card.contains(hover));
    final String family = row.text;
    final TextPainter preview = _text(
      _controller.fontPreviewText(family),
      22,
      _ink,
      parts.preview.width,
      family: family,
    );
    canvas.save();
    canvas.clipRect(parts.preview);
    _draw(
      canvas,
      preview,
      Offset(parts.preview.left, parts.preview.center.dy - preview.height / 2),
    );
    canvas.restore();
    final double x = parts.card.left + 12;
    final double w = parts.card.right - 12 - x;
    final bool isDefault = row.prop('.default')?.value == 'true';
    final TextPainter name = _text(family, 12.5, _ink, w - 90, bold: true);
    final double ny = parts.card.top + 46;
    _draw(canvas, name, Offset(x, ny));
    if (isDefault) {
      final TextPainter chip = _text(
        _s.t('Report default'),
        9.5,
        _accent,
        120,
        bold: true,
      );
      final Rect cr = Rect.fromLTWH(
        x + name.width + 8,
        ny + name.height / 2 - 8,
        chip.width + 12,
        16,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cr, const Radius.circular(8)),
        Paint()..color = _accent.withValues(alpha: 0.14),
      );
      _drawCentered(canvas, chip, cr.center);
    }
    final String card = row.prop('.card')?.value ?? '';
    final int dot = card.indexOf(' · ');
    final String faces = dot < 0 ? card : card.substring(0, dot);
    final String bytes = dot < 0 ? '' : card.substring(dot + 3);
    final TextPainter info = _text(
      bytes.isEmpty ? _tr(faces) : '${_tr(faces)} · $bytes',
      11,
      _muted,
      w,
    );
    _draw(canvas, info, Offset(x, ny + 19));
    final TextPainter uses = _text(
      '${_s.t('Used by')}: ${_usesText(row.prop('.uses')?.value ?? '')}',
      11,
      _muted,
      w,
    );
    _draw(canvas, uses, Offset(x, ny + 36));
    for (final _Hit h in _fontHits(row)) {
      _paintIconButton(canvas, h, hot);
    }
  }

  String _usesText(String raw) {
    final int? n = int.tryParse(raw);
    if (n != null) {
      return _s.count(n, 'element');
    }
    final int plus = raw.indexOf(', +');
    if (plus > 0) {
      final int? more = int.tryParse(raw.substring(plus + 3));
      return '${_s.t(raw.substring(0, plus))} + '
          '${more == null ? raw.substring(plus + 3) : _s.count(more, 'element')}';
    }
    return _s.t(raw);
  }

  // ------------------------------------------------------------ font picker

  void _paintFontPopup(Canvas canvas) {
    _fontPopupRect = null;
    final String? key = _controller.editingProperty;
    if (key == null || !ReportDesignerController.isFontKey(key)) {
      return;
    }
    final (ReportProperty, Rect, String)? field = _fieldFor(key);
    if (field == null) {
      return;
    }
    final Rect box = field.$2;
    final List<ReportCompletionItem> items =
        _controller.completion?.items ?? const <ReportCompletionItem>[];
    final double w = math.min(size.width - 16, math.max(box.width, 270));
    final double left = math.max(8, math.min(box.left, size.width - 8 - w));
    final int want = items.isEmpty ? 1 : math.min(items.length, _fontMaxRows);
    final double rowH = items.isEmpty ? 36 : _fontRowHeight;
    final double below = size.height - 6 - (box.bottom + 4);
    final double above = box.top - 10;
    final bool down = want * rowH + 8 <= below || below >= above;
    final double room = down ? below : above;
    final int rows = ((room - 8) / rowH).floor().clamp(1, want);
    final double h = rows * rowH + 8;
    final Rect rect = Rect.fromLTWH(
      left,
      down ? box.bottom + 4 : box.top - 4 - h,
      w,
      h,
    );
    _fontPopupRect = rect;
    _fontVisible = items.isEmpty ? 0 : rows;
    final int index = _controller.completionIndex;
    if (index != _fontIndexSeen) {
      _fontIndexSeen = index;
      if (index < _fontFirst) {
        _fontFirst = index;
      } else if (index >= _fontFirst + rows) {
        _fontFirst = index - rows + 1;
      }
    }
    _fontFirst = _fontFirst.clamp(0, math.max(0, items.length - rows));
    final RRect rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rr.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(rr, Paint()..color = _popupFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
    if (items.isEmpty) {
      final bool loading =
          _controller.deviceFonts != null && _controller.deviceFamilies == null;
      final TextPainter tp = _text(
        _s.t(loading ? 'Looking for installed fonts…' : 'No matching fonts'),
        11.5,
        _muted,
        w - 24,
        italic: true,
      );
      _draw(canvas, tp, Offset(rect.left + 12, rect.center.dy - tp.height / 2));
      return;
    }
    canvas.save();
    canvas.clipRRect(rr);
    final Offset? hover = _hoverL;
    for (int k = 0; k < rows; k++) {
      final int i = _fontFirst + k;
      if (i >= items.length) {
        break;
      }
      final ReportCompletionItem item = items[i];
      final Rect r = Rect.fromLTWH(
        rect.left + 4,
        rect.top + 4 + k * _fontRowHeight,
        w - 8,
        _fontRowHeight,
      );
      final bool selected = i == index;
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(7)),
          Paint()..color = _accent.withValues(alpha: _dark ? 0.28 : 0.14),
        );
      } else if (hover != null && r.contains(hover)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(7)),
          Paint()..color = _ink.withValues(alpha: 0.06),
        );
      }
      final TextPainter detail = _text(_tr(item.detail), 9.5, _faint, w * 0.45);
      final TextPainter name = _text(
        item.label,
        11,
        selected ? _ink : _muted,
        r.width - detail.width - 30,
        bold: selected,
      );
      _draw(canvas, name, Offset(r.left + 10, r.top + 5));
      _draw(
        canvas,
        detail,
        Offset(
          r.right - 10 - detail.width,
          r.top + 5 + (name.height - detail.height) / 2,
        ),
      );
      final TextPainter preview = _text(
        _controller.fontPreviewText(item.insert),
        17,
        _ink,
        r.width - 20,
        family: item.insert,
      );
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(r.left, r.top + 5 + name.height, r.right, r.bottom),
      );
      _draw(canvas, preview, Offset(r.left + 10, r.top + 6 + name.height));
      canvas.restore();
    }
    if (items.length > rows) {
      final double track = h - 12;
      final double thumb = math.max(18, track * rows / items.length);
      final double top =
          rect.top +
          6 +
          (track - thumb) * (_fontFirst / math.max(1, items.length - rows));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.right - 5, top, 3, thumb),
          const Radius.circular(2),
        ),
        Paint()..color = _ink.withValues(alpha: 0.25),
      );
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ tooltip

  void _paintTooltip(Canvas canvas, _Hit? hot) {
    final String? tip = hot?.tip;
    if (!_tipShown || hot == null || tip == null || hot.id != _tipId) {
      return;
    }
    final Color fill = _dark
        ? const Color(0xFFE8EAED)
        : const Color(0xF2202428);
    final Color ink = _dark ? const Color(0xFF1F2328) : const Color(0xFFFFFFFF);
    final TextPainter tp = _text(tip, 11, ink, 240, lines: 3);
    final double w = tp.width + 16;
    final double h = tp.height + 10;
    final double x = (hot.rect.center.dx - w / 2).clamp(
      4,
      math.max(4, size.width - 4 - w),
    );
    var y = hot.rect.bottom + 6;
    if (y + h > size.height - 4) {
      y = hot.rect.top - 6 - h;
    }
    final RRect rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      rr.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    _draw(canvas, tp, Offset(x + 8, y + 5));
  }

  // ------------------------------------------------------------ palette

  static const List<int> _themeColors = <int>[
    0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4, //
    0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47,
  ];

  static const List<int> _standardColors = <int>[
    0xC00000, 0xFF0000, 0xFFC000, 0xFFFF00, 0x92D050, //
    0x00B050, 0x00B0F0, 0x0070C0, 0x002060, 0x7030A0,
  ];

  static int _shade(int rgb, int row) {
    if (row == 0) {
      return rgb;
    }
    final List<double> f;
    final bool lighten;
    if (rgb == 0xFFFFFF) {
      f = const <double>[0.05, 0.15, 0.25, 0.35, 0.5];
      lighten = false;
    } else if (rgb == 0x000000) {
      f = const <double>[0.5, 0.35, 0.25, 0.15, 0.05];
      lighten = true;
    } else {
      final double k = const <double>[0.8, 0.6, 0.4, 0.25, 0.5][row - 1];
      final bool up = row <= 3;
      return _mix(rgb, k, lighten: up);
    }
    return _mix(rgb, f[row - 1], lighten: lighten);
  }

  static int _mix(int rgb, double k, {required bool lighten}) {
    int ch(int c) => lighten
        ? (c + (255 - c) * k).round().clamp(0, 255)
        : (c * (1 - k)).round().clamp(0, 255);
    final int r = ch((rgb >> 16) & 0xFF);
    final int g = ch((rgb >> 8) & 0xFF);
    final int b = ch(rgb & 0xFF);
    return (r << 16) | (g << 8) | b;
  }

  static String _hex(int rgb) =>
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _layoutPalette() {
    _swatches = <_Swatch>[];
    _paletteRect = null;
    final String? key = _paletteKey;
    final Rect? text = key == null ? null : _textRectFor(key);
    final Rect? anchor =
        _paletteAnchor ??
        (text == null
            ? null
            : Rect.fromLTRB(text.left - 24, text.top, text.right, text.bottom));
    if (key == null || anchor == null) {
      return;
    }
    const double cell = 18;
    const double gap = 3;
    const double pad = 10;
    const double caption = 18;
    const int cols = 10;
    const double w = pad * 2 + cols * cell + (cols - 1) * gap;
    final List<MapEntry<String, String>> named = _controller
        .template
        .colors
        .entries
        .take(20)
        .toList();
    final int namedRows = (named.length / cols).ceil();
    final double h =
        pad +
        24 +
        8 +
        (named.isEmpty ? 0 : caption + namedRows * (cell + gap)) +
        caption +
        6 * (cell + gap) +
        caption +
        (cell + gap) +
        22;
    var x = anchor.left;
    x = x.clamp(4, math.max(4, size.width - w - 4)).toDouble();
    var y = anchor.bottom + 4;
    if (y + h > size.height - 4) {
      y = math.max(4, anchor.top - h - 4);
    }
    final Rect rect = Rect.fromLTWH(x, y, w, h);
    _paletteRect = rect;
    var top = rect.top + pad;
    _swatches.add(
      _Swatch(
        Rect.fromLTWH(rect.left + pad, top, w - 2 * pad, 24),
        '',
        null,
        _s.t('No color'),
      ),
    );
    top += 24 + 8;
    Rect at(int i, double rowTop) => Rect.fromLTWH(
      rect.left + pad + (i % cols) * (cell + gap),
      rowTop + (i ~/ cols) * (cell + gap),
      cell,
      cell,
    );
    if (named.isNotEmpty) {
      top += caption;
      for (int i = 0; i < named.length; i++) {
        final ReportColor c = _controller.template.resolveColor(
          named[i].value,
          ReportColor.transparent,
        );
        _swatches.add(
          _Swatch(
            at(i, top),
            named[i].key,
            Color(c.argb),
            '${named[i].key} · ${named[i].value}',
          ),
        );
      }
      top += namedRows * (cell + gap);
    }
    top += caption;
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < cols; col++) {
        final int rgb = _shade(_themeColors[col], row);
        _swatches.add(
          _Swatch(
            at(col, top + row * (cell + gap)),
            _hex(rgb),
            Color(0xFF000000 | rgb),
            _hex(rgb),
          ),
        );
      }
    }
    top += 6 * (cell + gap) + caption;
    for (int col = 0; col < cols; col++) {
      final int rgb = _standardColors[col];
      _swatches.add(
        _Swatch(at(col, top), _hex(rgb), Color(0xFF000000 | rgb), _hex(rgb)),
      );
    }
  }

  void _paintPalette(Canvas canvas) {
    _layoutPalette();
    final Rect? rect = _paletteRect;
    final String? key = _paletteKey;
    if (rect == null || key == null) {
      return;
    }
    String current = '';
    for (final ReportProperty p in _controller.properties) {
      if (p.key == key) {
        current = p.value.trim().toLowerCase();
      }
    }
    final RRect rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rr.shift(const Offset(0, 3)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(rr, Paint()..color = _popupFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke,
    );
    final Color ink = _ink;
    final Color soft = _muted;
    final Offset? hover = _hoverL;
    String footer = current.isEmpty ? _s.t('No color') : current;
    void caption(String text, double y) {
      _draw(
        canvas,
        _text(_s.t(text), 10, soft, rect.width - 20, bold: true),
        Offset(rect.left + 10, y),
      );
    }

    final List<_Swatch> swatches = _swatches;
    final _Swatch none = swatches.first;
    final bool namedPresent = _controller.template.colors.isNotEmpty;
    if (namedPresent) {
      caption('TEMPLATE PALETTE', none.rect.bottom + 10);
    }
    final int namedCount = math.min(20, _controller.template.colors.length);
    final _Swatch firstTheme = swatches[1 + namedCount];
    caption('THEME COLORS', firstTheme.rect.top - 15);
    final _Swatch firstStandard = swatches[1 + namedCount + 60];
    caption('STANDARD COLORS', firstStandard.rect.top - 15);
    for (final _Swatch s in swatches) {
      final bool hot = hover != null && s.rect.contains(hover);
      if (hot) {
        footer = s.label;
      }
      final bool selected =
          s.value.toLowerCase() == current &&
          (s.value.isNotEmpty || current.isEmpty);
      final Color? color = s.color;
      if (color == null) {
        final RRect b = RRect.fromRectAndRadius(
          s.rect,
          const Radius.circular(5),
        );
        canvas.drawRRect(
          b,
          Paint()..color = _ink.withValues(alpha: hot ? 0.08 : 0.04),
        );
        canvas.drawRRect(
          b,
          Paint()
            ..color = selected ? _accent : _line
            ..style = PaintingStyle.stroke,
        );
        final Rect icon = Rect.fromLTWH(
          s.rect.left + 6,
          s.rect.center.dy - 7,
          14,
          14,
        );
        ReportInspectorGlyphs.noColor(canvas, icon);
        canvas.drawRect(
          icon,
          Paint()
            ..color = const Color(0xFF9CA3AF)
            ..style = PaintingStyle.stroke,
        );
        final TextPainter tp = _text(_s.t('No color'), _font, ink, 120);
        _draw(
          canvas,
          tp,
          Offset(icon.right + 8, s.rect.center.dy - tp.height / 2),
        );
        continue;
      }
      canvas.drawRect(s.rect, Paint()..color = color);
      canvas.drawRect(
        s.rect,
        Paint()
          ..color = const Color(0x22000000)
          ..style = PaintingStyle.stroke,
      );
      if (hot || selected) {
        canvas.drawRect(
          s.rect.inflate(1.5),
          Paint()
            ..color = selected ? _accent : ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
    _draw(
      canvas,
      _text(footer, 10.5, soft, rect.width - 20),
      Offset(rect.left + 10, rect.bottom - 18),
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = _s.direction
      ..label = _s.t('Report properties')
      ..value = _titleText;
  }
}
