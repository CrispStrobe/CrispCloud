import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_editor_strings.dart';
import 'office_modal.dart';

Future<double?> showOfficeDimensionDialog(
  BuildContext context, {
  required String title,
  required double points,
  required OfficeLengthUnit unit,
}) => showOfficeModal<double>(
  context: context,
  builder: (_) => _DimensionDialog(title: title, points: points, unit: unit),
);

class _DimensionDialog extends StatefulWidget {
  const _DimensionDialog({
    required this.title,
    required this.points,
    required this.unit,
  });
  final String title;
  final double points;
  final OfficeLengthUnit unit;
  @override
  State<_DimensionDialog> createState() => _DimensionDialogState();
}

class _DimensionDialogState extends State<_DimensionDialog> {
  late final _field = TextEditingController(
    text: widget.unit.fromPoints(widget.points).toStringAsFixed(4),
  );
  double? _value;
  bool _edited = false;
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr(widget.title)),
    content: SizedBox(
      width: 280,
      child: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: '${context.tr(widget.title)} (${widget.unit.suffix})',
          helperText: 'in / cm / mm / pt',
          errorText: _edited && _value == null
              ? context.tr('Enter a valid measurement.')
              : null,
        ),
        onChanged: (text) => setState(() {
          _edited = true;
          final value = widget.unit.parsePoints(text);
          _value = value != null && value > 0 && value <= 3072 ? value : null;
        }),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel')),
      ),
      ElevatedButton(
        onPressed: _edited && _value == null
            ? null
            : () => Navigator.pop(context, _edited ? _value : widget.points),
        child: Text(context.tr('Apply')),
      ),
    ],
  );
}
