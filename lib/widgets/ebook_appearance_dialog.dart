import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';

/// One appearance form for every reader host. Capability flags describe the
/// open publication, so fixed-layout books do not offer ineffective controls.
class EbookAppearanceDialog extends StatefulWidget {
  const EbookAppearanceDialog({
    super.key,
    required this.appearance,
    required this.translate,
    this.supportsTextAppearance = true,
    this.supportsLayout = true,
    this.supportsPublisherStyles = true,
    this.portable = false,
  });

  final EbookAppearance appearance;
  final String Function(String) translate;
  final bool supportsTextAppearance;
  final bool supportsLayout;
  final bool supportsPublisherStyles;
  final bool portable;

  @override
  State<EbookAppearanceDialog> createState() => _EbookAppearanceDialogState();
}

class _EbookAppearanceDialogState extends State<EbookAppearanceDialog> {
  late EbookAppearance _value = widget.appearance.normalized.copyWith(
    flow: widget.portable ? 'scrolled' : null,
  );

  String _tr(String text) => widget.translate(text);
  void _change(EbookAppearance value) => setState(() => _value = value);

  Widget _choice(
    String label,
    String value,
    List<String> choices,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('ebook-appearance-$label'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: _tr(label)),
      items: choices
          .map((item) => DropdownMenuItem(value: item, child: Text(_tr(item))))
          .toList(),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    ),
  );

  Widget _slider(
    String label,
    double value,
    double minimum,
    double maximum,
    int divisions,
    ValueChanged<double> onChanged, {
    String? display,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${_tr(label)}: ${display ?? '${value.round()} px'}'),
      Slider(
        key: ValueKey('ebook-appearance-$label'),
        label: display ?? '${value.round()} px',
        value: value,
        min: minimum,
        max: maximum,
        divisions: divisions,
        onChanged: onChanged,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Appearance')),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _choice('Theme', _value.theme, [
              'light',
              'sepia',
              'dark',
            ], (theme) => _change(_value.copyWith(theme: theme))),
            if (widget.supportsTextAppearance) ...[
              if (widget.supportsPublisherStyles)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_tr('Use publisher styles')),
                  subtitle: Text(
                    _tr(
                      'Customizing text below overrides publisher fonts and spacing.',
                    ),
                  ),
                  value: _value.usePublisherStyles,
                  onChanged: (enabled) =>
                      _change(_value.copyWith(usePublisherStyles: enabled)),
                ),
              _slider(
                'Font size',
                _value.fontSize,
                10,
                48,
                38,
                (size) => _change(
                  _value.copyWith(fontSize: size, usePublisherStyles: false),
                ),
              ),
              _choice(
                'Font family',
                _value.fontFamily,
                ['serif', 'sans-serif', 'monospace'],
                (font) => _change(
                  _value.copyWith(fontFamily: font, usePublisherStyles: false),
                ),
              ),
              _slider(
                'Line spacing',
                _value.lineHeight,
                1,
                2.5,
                15,
                (height) => _change(
                  _value.copyWith(
                    lineHeight: height,
                    usePublisherStyles: false,
                  ),
                ),
                display: _value.lineHeight.toStringAsFixed(1),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _tr(
                    'This publication has a fixed layout. Its text and page geometry stay as published.',
                  ),
                ),
              ),
            if (widget.supportsLayout && !widget.portable) ...[
              const Divider(),
              _choice('Reading flow', _value.flow, [
                'paginated',
                'scrolled',
              ], (flow) => _change(_value.copyWith(flow: flow))),
              if (_value.flow == 'paginated')
                _choice(
                  'Maximum columns',
                  '${_value.maxColumnCount}',
                  ['1', '2', '3'],
                  (count) => _change(
                    _value.copyWith(maxColumnCount: int.parse(count)),
                  ),
                ),
              Text(_tr('Narrow windows use fewer columns automatically.')),
              const SizedBox(height: 12),
              _slider(
                'Page margin',
                _value.pageMargin,
                0,
                96,
                24,
                (margin) => _change(_value.copyWith(pageMargin: margin)),
              ),
              _slider(
                'Column width',
                _value.pageWidth,
                320,
                1600,
                32,
                (width) => _change(_value.copyWith(pageWidth: width)),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _value.normalized),
        child: Text(_tr('Apply')),
      ),
    ],
  );
}
