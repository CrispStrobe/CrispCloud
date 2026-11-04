import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_reports.dart';

import '../embed/office_theme.dart';
import 'render_report_designer.dart';
import 'report_designer_controller.dart';
import 'report_designer_strings.dart';

/// Problems panel of the report designer: every error and warning in the
/// report ([ReportDesignerController.problems]) with what kind of problem
/// it is and where. Clicking one takes the user there
/// ([ReportDesignerController.revealDiagnostic]); the close button sets
/// [ReportDesignerController.problemsOpen] to false.
class ReportProblemsPanel extends LeafRenderObjectWidget {
  /// ReportProblemsPanel API.
  const ReportProblemsPanel({
    super.key,
    required this.controller,
    this.theme = OfficeTheme.light,
  });

  /// controller API.
  final ReportDesignerController controller;

  /// theme API.
  final OfficeTheme theme;

  @override
  RenderReportProblems createRenderObject(BuildContext context) =>
      RenderReportProblems(controller: controller, theme: theme);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportProblems renderObject,
  ) {
    renderObject
      ..controller = controller
      ..theme = theme;
  }
}

enum _Filter { all, errors, warnings }

/// RenderBox behind [ReportProblemsPanel].
class RenderReportProblems extends RenderBox implements MouseTrackerAnnotation {
  /// RenderReportProblems API.
  RenderReportProblems({required this._controller, required this._theme});

  /// Height of the title row.
  static const double headerHeight = 32;

  /// Height of one problem row.
  static const double rowHeight = 46;

  static const double _hintHeight = 18;
  static const double _pad = 12;
  static const double _textStart = 40;

  ReportDesignerController _controller;
  OfficeTheme _theme;
  double _scroll = 0;
  Offset? _hover;
  _Filter _filter = _Filter.all;
  final Map<String, TextPainter> _cache = <String, TextPainter>{};

  /// controller API.
  ReportDesignerController get controller => _controller;

  set controller(ReportDesignerController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(_onChanged);
      value.addListener(_onChanged);
    }
    _controller = value;
    _scroll = 0;
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

  void _onChanged() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onChanged);
  }

  @override
  void detach() {
    _controller.removeListener(_onChanged);
    super.detach();
  }

  @override
  void dispose() {
    _clearCache();
    super.dispose();
  }

  void _clearCache() {
    for (final TextPainter tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size s = constraints.biggest;
    return s.isFinite ? s : constraints.constrain(const Size(800, 180));
  }

  @override
  bool hitTestSelf(Offset position) {
    _hover = position;
    return true;
  }

  // ------------------------------------------------------------ text

  ReportDesignerStrings get _s => _controller.strings;

  bool get _rtl => _s.isRtl;

  String get _crumb => _rtl ? '  ‹  ' : '  ›  ';

  static final RegExp _arabicText = RegExp('[\u0600-\u06FF]');

  static const Map<ReportDiagnosticKind, String> _kindLabels =
      <ReportDiagnosticKind, String>{
        ReportDiagnosticKind.file: 'Unreadable file',
        ReportDiagnosticKind.expression: 'Formula error',
        ReportDiagnosticKind.unknownFunction: 'Unknown function',
        ReportDiagnosticKind.layout: 'Size or position',
        ReportDiagnosticKind.missing: 'Missing value',
        ReportDiagnosticKind.duplicate: 'Duplicate name',
        ReportDiagnosticKind.invalidValue: 'Invalid value',
        ReportDiagnosticKind.structure: 'Report structure',
        ReportDiagnosticKind.unsupported: 'Not supported',
      };

  static const Map<ReportDiagnosticKind, String> _kindHints =
      <ReportDiagnosticKind, String>{
        ReportDiagnosticKind.file:
            'The file is damaged or is not a Quds report.',
        ReportDiagnosticKind.expression:
            'Check the brackets, quotes, and operators of the formula.',
        ReportDiagnosticKind.unknownFunction:
            'Check the spelling of the function name.',
        ReportDiagnosticKind.layout:
            'Move or resize the element so it fits its band and the page.',
        ReportDiagnosticKind.missing: 'Fill in the missing value.',
        ReportDiagnosticKind.duplicate: 'Give each one a different name.',
        ReportDiagnosticKind.invalidValue:
            'Enter the value in the form the property expects.',
        ReportDiagnosticKind.structure:
            'Check which band holds the element and which data set it uses.',
        ReportDiagnosticKind.unsupported:
            'This version does not support this part of the file.',
      };

  /// What kind of problem [d] is, in the interface language.
  String kindLabel(ReportDiagnostic d) => _s.t(_kindLabels[d.kind]!);

  /// How to fix a problem like [d], in the interface language.
  String hint(ReportDiagnostic d) => _s.t(_kindHints[d.kind]!);

  /// Where [d] points (`Detail › Text "total" › Visible when`).
  String where(ReportDiagnostic d) {
    final ReportDiagnosticTarget t = d.target;
    final List<String> parts = <String>[];
    switch (t.place) {
      case ReportDiagnosticPlace.element || ReportDiagnosticPlace.band:
        final ReportBandKind? kind = t.band;
        if (kind != null) {
          parts.add(_s.t(RenderReportDesigner.bandName(kind)));
        }
        final ReportBand? band = kind == null
            ? null
            : _controller.template.band(kind);
        final int? i = t.element;
        if (i != null) {
          parts.add(
            band != null && i < band.elements.length
                ? _elementLabel(band.elements[i])
                : '#${i + 1}',
          );
        }
        final String? part = t.part;
        if (part != null) {
          final String label = _s.t(switch (part) {
            'FooterCell' => 'Footer cell',
            _ => part,
          });
          final int? n = t.partIndex;
          parts.add(n == null ? label : '$label ${n + 1}');
        }
        final String? attribute = t.attribute;
        if (attribute != null) {
          parts.add(_s.t(_attributeLabel(attribute)));
        }
      case ReportDiagnosticPlace.variable:
        parts.add(_s.t('Variables'));
        final String? name = t.name;
        if (name != null) {
          parts.add(name);
        }
      case ReportDiagnosticPlace.dataTable || ReportDiagnosticPlace.dataColumn:
        parts.add(_s.t('Data'));
        final String? name = t.name;
        if (name != null) {
          parts.add(name.isEmpty ? _s.t('Fields') : name);
        }
        final String? column = t.column;
        if (column != null) {
          parts.add(column);
        }
      case ReportDiagnosticPlace.settings:
        parts.add(_s.t('Report settings'));
        final String? name = t.name;
        if (name != null) {
          parts.add(_s.t(name));
        }
      case ReportDiagnosticPlace.bands:
        parts.add(_s.t('Bands'));
      case ReportDiagnosticPlace.file:
        parts.add(_s.t('File'));
    }
    return parts.join(_crumb);
  }

  String _elementLabel(ReportElement e) {
    final String kind = _s.t(switch (e.type) {
      ReportElementType.text => 'Text',
      ReportElementType.image => 'Image',
      ReportElementType.table => 'Table',
      ReportElementType.barcode => 'Barcode',
      ReportElementType.shape => 'Shape',
      ReportElementType.chart => 'Chart',
      ReportElementType.crosstab => 'Crosstab',
      ReportElementType.subreport => 'Subreport',
    });
    final String? name = e.name;
    return name == null || name.isEmpty ? kind : '$kind "$name"';
  }

  static String _attributeLabel(String attribute) => switch (attribute) {
    'visibleWhen' => 'Visible when',
    'dataSet' => 'Data set',
    'groupBy' => 'Group by',
    'filter' => 'Filter',
    'sortBy' => 'Sort by',
    'title' => 'Title',
    'category' => 'Category',
    'value' => 'Value',
    _ => attribute,
  };

  TextPainter _text(
    String text,
    double fontSize,
    Color color,
    double maxWidth, {
    bool bold = false,
  }) {
    final TextDirection dir = _arabicText.hasMatch(text)
        ? TextDirection.rtl
        : (_rtl && !RegExp('[A-Za-z]').hasMatch(text)
              ? TextDirection.rtl
              : TextDirection.ltr);
    final double width = math.max(10, maxWidth);
    final String key =
        '$text|$fontSize|${color.toARGB32()}|$width|$bold|${dir.index}';
    final TextPainter? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    if (_cache.length > 600) {
      _clearCache();
    }
    final String ui = _theme.fontFamily ?? 'Liberation Sans';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: ui,
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: dir,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
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

  // ------------------------------------------------------------ colors

  bool get _dark => _theme.chromeFill.computeLuminance() < 0.35;

  Color get _bg => _theme.chromeFill;

  Color get _ink => _theme.chromeText;

  Color get _muted => _ink.withValues(alpha: 0.62);

  Color get _line => _ink.withValues(alpha: _dark ? 0.14 : 0.12);

  Color get _accent => _theme.selectionStroke;

  Color get _headerBand => _dark
      ? Color.alphaBlend(const Color(0x0CFFFFFF), _bg)
      : Color.alphaBlend(const Color(0x07000000), _bg);

  Color get _danger =>
      _dark ? const Color(0xFFFF7A7A) : const Color(0xFFC62828);

  Color get _warning =>
      _dark ? const Color(0xFFFFC266) : const Color(0xFFB26A00);

  Color get _ok => _dark ? const Color(0xFF6FD08C) : const Color(0xFF2E7D32);

  // ------------------------------------------------------------ geometry

  /// Physical rect of logical [r] (mirrored in right-to-left layouts).
  Rect _phys(Rect r) => _rtl
      ? Rect.fromLTRB(
          size.width - r.right,
          r.top,
          size.width - r.left,
          r.bottom,
        )
      : r;

  Offset _logical(Offset p) => _rtl ? Offset(size.width - p.dx, p.dy) : p;

  /// Paints [tp] with its start at logical x [x], top [y].
  void _draw(Canvas canvas, TextPainter tp, double x, double y) {
    final Rect r = _phys(Rect.fromLTWH(x, y, tp.width, tp.height));
    tp.paint(canvas, r.topLeft);
  }

  void _icon(Canvas canvas, IconData icon, Offset logical, double s, Color c) {
    final TextPainter tp = _iconPainter(icon, s, c);
    final Offset p = _rtl
        ? Offset(size.width - logical.dx, logical.dy)
        : logical;
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  List<ReportDiagnostic> get _shown {
    final List<ReportDiagnostic> all = _controller.problems;
    return switch (_filter) {
      _Filter.all => all,
      _Filter.errors => <ReportDiagnostic>[
        for (final ReportDiagnostic d in all)
          if (d.isError) d,
      ],
      _Filter.warnings => <ReportDiagnostic>[
        for (final ReportDiagnostic d in all)
          if (!d.isError) d,
      ],
    };
  }

  bool _isActive(ReportDiagnostic d) {
    final ReportDiagnostic? a = _controller.activeProblem;
    return a != null && a.path == d.path && a.message == d.message;
  }

  double _heightOf(ReportDiagnostic d) =>
      rowHeight + (_isActive(d) ? _hintHeight : 0);

  double _contentHeight(List<ReportDiagnostic> shown) {
    var h = 0.0;
    for (final ReportDiagnostic d in shown) {
      h += _heightOf(d);
    }
    return h;
  }

  void _clampScroll(List<ReportDiagnostic> shown) {
    final double view = math.max(0, size.height - headerHeight);
    final double max = math.max(0, _contentHeight(shown) - view);
    _scroll = _scroll.clamp(0, max).toDouble();
  }

  ({Rect errors, Rect warnings, Rect close}) _header(int errors, int warns) {
    final TextPainter title = _text(_s.t('Problems'), 12.5, _ink, 200);
    var x = _pad + 22 + title.width + 16;
    Rect chip(String text) {
      final TextPainter tp = _text(text, 11.5, _ink, 200);
      final Rect r = Rect.fromLTWH(x, 5, 28 + tp.width, headerHeight - 10);
      x = r.right + 6;
      return r;
    }

    final Rect e = chip(_s.count(errors, 'error'));
    final Rect w = chip(_s.count(warns, 'warning'));
    final Rect close = Rect.fromLTWH(size.width - _pad - 24, 4, 24, 24);
    return (errors: e, warnings: w, close: close);
  }

  // ------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    final List<ReportDiagnostic> all = _controller.problems;
    final List<ReportDiagnostic> shown = _shown;
    _clampScroll(shown);
    final int errors = all.where((ReportDiagnostic d) => d.isError).length;
    final int warnings = all.length - errors;
    final Offset? hover = _hover == null ? null : _logical(_hover!);

    final Rect head = Rect.fromLTWH(0, 0, size.width, headerHeight);
    canvas.drawRect(head, Paint()..color = _headerBand);
    final Paint line = Paint()..color = _line;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), line);
    canvas.drawRect(Rect.fromLTWH(0, headerHeight - 1, size.width, 1), line);
    _icon(
      canvas,
      Icons.fact_check_outlined,
      const Offset(_pad + 8, headerHeight / 2),
      16,
      _muted,
    );
    final TextPainter title = _text(_s.t('Problems'), 12.5, _ink, 200);
    _draw(canvas, title, _pad + 22, (headerHeight - title.height) / 2);
    final ({Rect errors, Rect warnings, Rect close}) h = _header(
      errors,
      warnings,
    );
    void chip(Rect r, String text, IconData icon, Color tone, bool on) {
      final bool hot = hover != null && r.contains(hover);
      if (on || hot) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(_phys(r), const Radius.circular(11)),
          Paint()..color = tone.withValues(alpha: on ? 0.16 : 0.08),
        );
      }
      _icon(canvas, icon, Offset(r.left + 13, r.center.dy), 14, tone);
      final TextPainter tp = _text(text, 11.5, _ink, 200);
      _draw(canvas, tp, r.left + 24, r.center.dy - tp.height / 2);
    }

    chip(
      h.errors,
      _s.count(errors, 'error'),
      Icons.error_outline,
      _danger,
      _filter == _Filter.errors,
    );
    chip(
      h.warnings,
      _s.count(warnings, 'warning'),
      Icons.warning_amber_rounded,
      _warning,
      _filter == _Filter.warnings,
    );
    if (hover != null && h.close.contains(hover)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_phys(h.close), const Radius.circular(4)),
        Paint()..color = _ink.withValues(alpha: 0.08),
      );
    }
    _icon(canvas, Icons.close, h.close.center, 16, _muted);

    final Rect body = Rect.fromLTRB(0, headerHeight, size.width, size.height);
    canvas.save();
    canvas.clipRect(body);
    if (shown.isEmpty) {
      final TextPainter tp = _text(
        _s.t('No problems found.'),
        12.5,
        _muted,
        size.width - 2 * _pad,
      );
      final double cy = body.center.dy;
      _icon(
        canvas,
        Icons.verified_outlined,
        Offset(size.width / 2, cy - 12),
        22,
        _ok,
      );
      tp.paint(canvas, Offset((size.width - tp.width) / 2, cy + 4));
    }
    var y = headerHeight - _scroll;
    final double textWidth = size.width - _textStart - _pad - 8;
    for (final ReportDiagnostic d in shown) {
      final double rh = _heightOf(d);
      final Rect r = Rect.fromLTWH(0, y, size.width, rh);
      y += rh;
      if (r.bottom < headerHeight || r.top > size.height) {
        continue;
      }
      final bool active = _isActive(d);
      if (active) {
        canvas.drawRect(
          _phys(r),
          Paint()..color = _accent.withValues(alpha: 0.12),
        );
        canvas.drawRect(
          _phys(Rect.fromLTWH(0, r.top, 3, r.height)),
          Paint()..color = _accent,
        );
      } else if (hover != null &&
          hover.dy > headerHeight &&
          r.contains(hover)) {
        canvas.drawRect(
          _phys(r),
          Paint()..color = _ink.withValues(alpha: 0.05),
        );
      }
      final Color tone = d.isError ? _danger : _warning;
      _icon(
        canvas,
        d.isError ? Icons.error : Icons.warning_amber_rounded,
        Offset(_pad + 10, r.top + 15),
        17,
        tone,
      );
      final TextPainter message = _text(
        _s.diagnostic(d.summary),
        12.5,
        _ink,
        textWidth,
      );
      _draw(canvas, message, _textStart, r.top + 7);
      final TextPainter kind = _text(
        kindLabel(d),
        11.5,
        tone,
        textWidth,
        bold: true,
      );
      _draw(canvas, kind, _textStart, r.top + 26);
      final String detail =
          '${where(d)}${_controller.isFromFile(d) ? '$_crumb${_s.t('Found when the file was opened')}' : ''}';
      final TextPainter place = _text(
        detail,
        11.5,
        _muted,
        textWidth - kind.width - 14,
      );
      _draw(canvas, place, _textStart + kind.width + 14, r.top + 26);
      canvas.drawCircle(
        _phys(
          Rect.fromCircle(
            center: Offset(
              _textStart + kind.width + 7,
              r.top + 26 + kind.height / 2,
            ),
            radius: 1.5,
          ),
        ).center,
        1.5,
        Paint()..color = _muted,
      );
      if (active) {
        final TextPainter tip = _text(hint(d), 11.5, _muted, textWidth);
        _icon(
          canvas,
          Icons.lightbulb_outline,
          Offset(_textStart + 7, r.top + rowHeight + 5),
          13,
          _accent,
        );
        _draw(canvas, tip, _textStart + 18, r.top + rowHeight - 2);
      }
      canvas.drawRect(
        Rect.fromLTWH(_textStart, r.bottom - 1, size.width - _textStart, 1),
        line,
      );
    }
    final double content = _contentHeight(shown);
    final double view = body.height;
    if (content > view && view > 0) {
      final double thumb = math.max(24, view * view / content);
      final double top =
          headerHeight + (view - thumb) * _scroll / (content - view);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _phys(Rect.fromLTWH(size.width - 7, top + 2, 4, thumb - 4)),
          const Radius.circular(2),
        ),
        Paint()..color = _ink.withValues(alpha: 0.28),
      );
    }
    canvas.restore();
    canvas.restore();
  }

  // ------------------------------------------------------------ events

  ReportDiagnostic? _rowAt(Offset logical) {
    if (logical.dy < headerHeight) {
      return null;
    }
    var y = headerHeight - _scroll;
    for (final ReportDiagnostic d in _shown) {
      final double rh = _heightOf(d);
      if (logical.dy >= y && logical.dy < y + rh) {
        return d;
      }
      y += rh;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerHoverEvent) {
      _hover = event.localPosition;
      markNeedsPaint();
      return;
    }
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (
        PointerSignalEvent e,
      ) {
        if (e is PointerScrollEvent) {
          _scroll += e.scrollDelta.dy;
          _clampScroll(_shown);
          markNeedsPaint();
        }
      });
      return;
    }
    if (event is PointerPanZoomUpdateEvent) {
      _scroll -= event.localPanDelta.dy;
      _clampScroll(_shown);
      markNeedsPaint();
      return;
    }
    if (event is! PointerDownEvent || event.buttons != kPrimaryButton) {
      return;
    }
    final Offset p = _logical(event.localPosition);
    final List<ReportDiagnostic> all = _controller.problems;
    final int errors = all.where((ReportDiagnostic d) => d.isError).length;
    final ({Rect errors, Rect warnings, Rect close}) h = _header(
      errors,
      all.length - errors,
    );
    if (h.close.inflate(2).contains(p)) {
      _controller.problemsOpen = false;
      return;
    }
    if (h.errors.contains(p) || h.warnings.contains(p)) {
      final _Filter want = h.errors.contains(p)
          ? _Filter.errors
          : _Filter.warnings;
      _filter = _filter == want ? _Filter.all : want;
      _scroll = 0;
      markNeedsPaint();
      return;
    }
    final ReportDiagnostic? d = _rowAt(p);
    if (d != null) {
      _controller.revealDiagnostic(d);
    }
  }

  // ------------------------------------------------------------ mouse

  @override
  MouseCursor get cursor {
    final Offset? local = _hover;
    if (local == null || !hasSize) {
      return SystemMouseCursors.basic;
    }
    final Offset p = _logical(local);
    final List<ReportDiagnostic> all = _controller.problems;
    final int errors = all.where((ReportDiagnostic d) => d.isError).length;
    final ({Rect errors, Rect warnings, Rect close}) h = _header(
      errors,
      all.length - errors,
    );
    if (h.close.contains(p) ||
        h.errors.contains(p) ||
        h.warnings.contains(p) ||
        _rowAt(p) != null) {
      return SystemMouseCursors.click;
    }
    return SystemMouseCursors.basic;
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (_) {
    _hover = null;
    markNeedsPaint();
  };

  @override
  bool get validForMouseTracker => attached;

  // ------------------------------------------------------------ semantics

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final List<ReportDiagnostic> all = _controller.problems;
    final int errors = all.where((ReportDiagnostic d) => d.isError).length;
    config
      ..isSemanticBoundary = true
      ..label =
          '${_s.t('Problems')}: ${_s.count(errors, 'error')}, '
          '${_s.count(all.length - errors, 'warning')}'
      ..textDirection = _s.direction;
  }
}
