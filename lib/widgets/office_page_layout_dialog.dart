import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_editor_strings.dart';
import 'office_modal.dart';

class OfficePageLayoutChoice {
  const OfficePageLayoutChoice({
    required this.size,
    required this.margins,
    required this.unit,
  });
  final WmlPageSize size;
  final WmlPageMargins margins;
  final OfficeLengthUnit unit;
}

Future<OfficePageLayoutChoice?> showOfficePageLayoutDialog(
  BuildContext context, {
  required WmlPageSize size,
  required WmlPageMargins margins,
  OfficeLengthUnit unit = OfficeLengthUnit.inches,
  int columns = 1,
  double columnSpace = 36,
  bool marginsOnly = false,
}) => showOfficeModal<OfficePageLayoutChoice>(
  context: context,
  builder: (_) => OfficePageLayoutDialog(
    size: size,
    margins: margins,
    unit: unit,
    columns: columns,
    columnSpace: columnSpace,
    marginsOnly: marginsOnly,
  ),
);

class OfficePageLayoutDialog extends StatefulWidget {
  const OfficePageLayoutDialog({
    super.key,
    required this.size,
    required this.margins,
    this.unit = OfficeLengthUnit.inches,
    this.columns = 1,
    this.columnSpace = 36,
    this.marginsOnly = false,
  });
  final WmlPageSize size;
  final WmlPageMargins margins;
  final OfficeLengthUnit unit;
  final int columns;
  final double columnSpace;
  final bool marginsOnly;
  @override
  State<OfficePageLayoutDialog> createState() => _OfficePageLayoutDialogState();
}

class _OfficePageLayoutDialogState extends State<OfficePageLayoutDialog> {
  late OfficeLengthUnit _unit = widget.unit;
  late final Map<String, double> _original = {
    'Width': widget.size.width,
    'Height': widget.size.height,
    'Top': widget.margins.top,
    'Bottom': widget.margins.bottom,
    'Left': widget.margins.left,
    'Right': widget.margins.right,
    'Header': widget.margins.header,
    'Footer': widget.margins.footer,
  };
  late final Map<String, double> _points = Map.of(_original);
  late final Map<String, TextEditingController> _fields = {
    for (final entry in _points.entries)
      entry.key: TextEditingController(text: _display(entry.value)),
  };
  final _invalid = <String>{};
  String _display(double points) => _unit
      .fromPoints(points)
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  WmlPageSize get _size =>
      WmlPageSize(width: _points['Width']!, height: _points['Height']!);
  WmlPageMargins get _margins => widget.margins.copyWith(
    top: _points['Top'],
    bottom: _points['Bottom'],
    left: _points['Left'],
    right: _points['Right'],
    header: _points['Header'],
    footer: _points['Footer'],
  );
  bool get _changed => _points.entries.any((e) => e.value != _original[e.key]);
  bool get _validGeometry =>
      !_changed ||
      widget.marginsOnly ||
      (_size.width > 0 &&
          _size.height > 0 &&
          _margins.left + _margins.right < _size.width &&
          _margins.top + _margins.bottom < _size.height &&
          (_size.width -
                  _margins.left -
                  _margins.right -
                  widget.columnSpace * (widget.columns - 1)) >
              0);

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _setUnit(OfficeLengthUnit? value) {
    if (value == null || _invalid.isNotEmpty) return;
    setState(() {
      _unit = value;
      _refreshFields();
    });
  }

  void _refreshFields() {
    for (final entry in _points.entries) {
      _fields[entry.key]!.text = _display(entry.value);
    }
  }

  void _paper(WmlPageSize size) => setState(() {
    _points['Width'] = size.width;
    _points['Height'] = size.height;
    for (final name in ['Width', 'Height']) {
      _fields[name]!.text = _display(_points[name]!);
    }
    _invalid.removeAll(['Width', 'Height']);
  });

  Widget _field(String name, {bool autofocus = false}) => Expanded(
    child: TextField(
      key: ValueKey('page-layout-${name.toLowerCase()}'),
      controller: _fields[name],
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '${context.tr(name)} (${_unit.suffix})',
        isDense: true,
        errorText: _invalid.contains(name)
            ? context.tr('Enter a valid measurement.')
            : null,
      ),
      onChanged: (text) => setState(() {
        final parsed = text == _display(_original[name]!)
            ? _original[name]
            : _unit.parsePoints(text);
        if (parsed == null ||
            parsed < 0 ||
            ((name == 'Width' || name == 'Height') && parsed == 0)) {
          _invalid.add(name);
        } else {
          _invalid.remove(name);
          _points[name] = parsed;
        }
      }),
    ),
  );
  Widget _pair(String first, String second, {bool autofocus = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(
          children: [
            _field(first, autofocus: autofocus),
            const SizedBox(width: 12),
            _field(second),
          ],
        ),
      );

  Widget _form() {
    final presets = <String, WmlPageSize>{
      'A4': WmlPageSize.a4(),
      'A3': WmlPageSize.a3(),
      'Letter': WmlPageSize.letter(),
      'Legal': WmlPageSize.legal(),
    };
    final paper =
        presets.entries
            .where((e) => e.value.matches(_size.portrait))
            .firstOrNull
            ?.key ??
        'Custom';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<OfficeLengthUnit>(
          key: ValueKey('page-layout-unit-${_unit.name}'),
          initialValue: _unit,
          decoration: InputDecoration(
            labelText: context.tr('Units'),
            isDense: true,
          ),
          items: [
            for (final unit in OfficeLengthUnit.values)
              DropdownMenuItem(value: unit, child: Text(unit.suffix)),
          ],
          onChanged: _invalid.isEmpty ? _setUnit : null,
        ),
        if (!widget.marginsOnly) ...[
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: ValueKey('page-layout-paper-$paper'),
            initialValue: paper,
            decoration: InputDecoration(
              labelText: context.tr('Paper size'),
              isDense: true,
            ),
            items: [
              for (final name in [...presets.keys, 'Custom'])
                DropdownMenuItem(value: name, child: Text(context.tr(name))),
            ],
            onChanged: (value) {
              final size = presets[value];
              if (size != null)
                _paper(_size.isLandscape ? size.landscape : size);
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<bool>(
            key: ValueKey('page-layout-orientation-${_size.isLandscape}'),
            initialValue: _size.isLandscape,
            decoration: InputDecoration(
              labelText: context.tr('Orientation'),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: false,
                child: Text(context.tr('Portrait')),
              ),
              DropdownMenuItem(
                value: true,
                child: Text(context.tr('Landscape')),
              ),
            ],
            onChanged: (value) {
              if (value != null)
                _paper(value ? _size.landscape : _size.portrait);
            },
          ),
          _pair('Width', 'Height'),
        ],
        _pair('Top', 'Bottom', autofocus: true),
        _pair('Left', 'Right'),
        if (!widget.marginsOnly) _pair('Header', 'Footer'),
        if (!_validGeometry)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              context.tr('Margins must leave room for the page content.'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _preview() => Semantics(
    label:
        '${context.tr('Layout preview')}: ${_display(_size.width)} × ${_display(_size.height)} ${_unit.suffix}',
    child: CustomPaint(
      key: const ValueKey('page-layout-preview'),
      painter: OfficePageLayoutPainter(
        size: _size,
        margins: _margins,
        columns: widget.columns,
        columnSpace: widget.columnSpace,
        invalid: !_validGeometry,
      ),
      child: const SizedBox.expand(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      title: Text(
        context.tr(widget.marginsOnly ? 'Page margins' : 'Page Setup'),
      ),
      content: SizedBox(
        width: 760,
        height: math.max(
          80,
          math.min(520, media.size.height - media.viewInsets.bottom - 190),
        ),
        child: LayoutBuilder(
          builder: (_, constraints) => constraints.maxWidth >= 580
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SingleChildScrollView(child: _form())),
                    const SizedBox(width: 20),
                    Expanded(child: _preview()),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: 160, child: _preview()),
                      _form(),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('page-layout-apply'),
          onPressed: _invalid.isNotEmpty || !_validGeometry
              ? null
              : () => Navigator.pop(
                  context,
                  OfficePageLayoutChoice(
                    size: _size,
                    margins: _margins,
                    unit: _unit,
                  ),
                ),
          child: Text(context.tr('Apply')),
        ),
      ],
    );
  }
}

/// A proportional preview of physical geometry, independent of display units.
class OfficePageLayoutPainter extends CustomPainter {
  OfficePageLayoutPainter({
    required this.size,
    required this.margins,
    this.columns = 1,
    this.columnSpace = 36,
    this.invalid = false,
  });
  final WmlPageSize size;
  final WmlPageMargins margins;
  final int columns;
  final double columnSpace;
  final bool invalid;
  @override
  void paint(Canvas canvas, Size viewport) {
    if (size.width <= 0 || size.height <= 0) return;
    final scale = math.min(
      (viewport.width - 24) / size.width,
      (viewport.height - 24) / size.height,
    );
    if (scale <= 0) return;
    final paper = Rect.fromCenter(
      center: viewport.center(Offset.zero),
      width: size.width * scale,
      height: size.height * scale,
    );
    canvas.drawShadow(Path()..addRect(paper), Colors.black26, 3, false);
    canvas.drawRect(paper, Paint()..color = Colors.white);
    final content = Rect.fromLTRB(
      paper.left + margins.left * scale,
      paper.top + margins.top * scale,
      paper.right - margins.right * scale,
      paper.bottom - margins.bottom * scale,
    );
    canvas.save();
    canvas.clipRect(paper);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(paper)
        ..addRect(content),
      Paint()..color = const Color(0xffe7edf4),
    );
    final guide = Paint()
      ..color = invalid ? Colors.red : const Color(0xff7187a0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(content, guide);
    if (content.width > 0 && content.height > 0 && !invalid) {
      final count = columns.clamp(1, 16);
      final gap = columnSpace * scale;
      final width = (content.width - gap * (count - 1)) / count;
      if (width > 0) {
        final ink = Paint()
          ..color = const Color(0xff89939f)
          ..strokeWidth = 1.5;
        for (var column = 0; column < count; column++) {
          for (var line = 0; line < 12; line++) {
            final y =
                content.top + 6 + line * math.min(10, content.height / 14);
            final x = content.left + column * (width + gap);
            canvas.drawLine(
              Offset(x + 3, y),
              Offset(x + width * (line == 11 ? .55 : .94), y),
              ink,
            );
          }
        }
      }
      for (final y in [
        paper.top + margins.header * scale,
        paper.bottom - margins.footer * scale,
      ]) {
        canvas.drawLine(
          Offset(content.left, y),
          Offset(content.right, y),
          guide,
        );
      }
    }
    canvas.restore();
    canvas.drawRect(paper, guide);
  }

  @override
  bool shouldRepaint(OfficePageLayoutPainter old) => true;
}
