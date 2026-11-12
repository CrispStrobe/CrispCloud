// lib/widgets/office_editor_dialogs.dart
//
// Small modal building blocks used by the Office ribbon: colour picker, font
// and paragraph dialogs, insert-table / hyperlink prompts and page setup.

import 'package:flutter/material.dart';

import '../l10n/misc_ui_strings.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_editor_strings.dart';

/// Office-like palette (RRGGBB, no leading '#').
const List<String> kOfficePalette = <String>[
  '000000', '1F1F1F', '3F3F3F', '5F5F5F', '7F7F7F', '9F9F9F', 'BFBFBF',
  'DFDFDF', 'FFFFFF', 'F2F2F2',
  'C00000', 'FF0000', 'FF7C80', 'FFC000', 'FFD966', 'FFF2CC', 'FFFF00',
  '92D050', '00B050', '00B0F0', '0070C0', '002060', '7030A0', 'C65911',
  'E36C0A', 'F4B183', 'A9D18E', '548235', '1F4E79', '2E75B6', 'BDD7EE',
  'D9E2F3', 'FCE4D6', 'E2EFDA', 'FFF2CC', 'EDEDED',
];

const List<String> kOfficeFontFamilies = <String>[
  'Arial',
  'Aptos',
  'Aptos Display',
  'Calibri',
  'Cambria',
  'Segoe UI',
  'Helvetica',
  'Garamond',
  'Book Antiqua',
  'Times New Roman',
  'Georgia',
  'Verdana',
  'Tahoma',
  'Trebuchet MS',
  'Courier New',
  'Consolas',
  'Roboto',
  'Liberation Sans',
  'Noto Sans',
];

const List<int> kOfficeFontSizes = <int>[
  6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 40, 44,
  48, 54, 60, 66, 72, 80, 88, 96,
];

String _normalizeHex(String raw) {
  var value = raw.trim().toUpperCase().replaceAll('#', '');
  if (value.length == 3) {
    value = value.split('').map((String c) => '$c$c').join();
  }
  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(value)) return '';
  return value;
}

Color _colorFromHex(String hex) {
  final String value = _normalizeHex(hex);
  if (value.isEmpty) return Colors.transparent;
  return Color(int.parse('FF$value', radix: 16));
}

/// Returns a hex colour, `''` for "automatic / none", or null on cancel.
Future<String?> showOfficeColorPicker(
  BuildContext context, {
  String? initial,
  bool allowNone = false,
  String noneLabel = 'Automatic',
}) {
  final TextEditingController hexController =
      TextEditingController(text: initial ?? '');
  String selected = _normalizeHex(initial ?? '');
  String error = '';

  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: Text(ctx.tr('Color')),
            content: SizedBox(
              width: 352,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final String hex in kOfficePalette)
                          InkWell(
                            onTap: () {
                              setState(() {
                                selected = hex;
                                hexController.text = hex;
                                error = '';
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _colorFromHex(hex),
                                border: Border.all(
                                  color: selected == hex
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).dividerColor,
                                  width: selected == hex ? 2 : 0.5,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: hexController,
                      decoration: InputDecoration(
                        labelText: ctx.tr('Hex color'),
                        prefixText: '#',
                        errorText: error.isEmpty ? null : error,
                        isDense: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      onChanged: (String value) {
                        final String normalized = _normalizeHex(value);
                        setState(() {
                          selected = normalized;
                          error = '';
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              if (allowNone)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: Text(noneLabel),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr('Cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  final String value = _normalizeHex(hexController.text);
                  if (value.isEmpty && !allowNone) {
                    setState(() => error = 'Enter a 6-digit hex color.');
                    return;
                  }
                  Navigator.pop(ctx, value);
                },
                child: Text(ctx.tr('OK')),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Font controls explicitly used while the dialog is open.
enum WordFontProperty {
  family,
  size,
  bold,
  italic,
  underline,
  strike,
  color,
  highlight,
  vertAlign,
}

/// Font settings returned by [showWordFontDialog].
typedef WordFontChoice = ({
  String family,
  double sizePt,
  bool bold,
  bool italic,
  WmlUnderline underline,
  bool strike,
  String color,
  String? highlight,
  WmlVertAlign vertAlign,
  Set<WordFontProperty> edited,
});

Future<WordFontChoice?> showWordFontDialog(
  BuildContext context, {
  required WmlRunProps current,
}) {
  String family = current.asciiFont.isEmpty ? 'Arial' : current.asciiFont;
  // Imported Word sizes use half-points and may be outside the preset list.
  // Keep that exact value visible and selectable when the dialog is unchanged.
  double size = current.fontSizeHalfPoints / 2;
  final List<double> sizes = <double>{
    size,
    for (final int preset in kOfficeFontSizes) preset.toDouble(),
  }.toList()..sort();
  bool bold = current.bold;
  bool italic = current.italic;
  WmlUnderline underline = current.underline;
  bool strike = current.strike;
  String color = current.color;
  String? highlight = current.highlight;
  WmlVertAlign vertAlign = current.vertAlign;
  final Set<WordFontProperty> edited = <WordFontProperty>{};

  return showDialog<WordFontChoice>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: Text(ctx.tr('Font')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Builder(
                          builder: (BuildContext context) {
                            final List<String> families = <String>[
                              if (!kOfficeFontFamilies.contains(family)) family,
                              ...kOfficeFontFamilies,
                            ];
                            return PopupMenuButton<String>(
                              tooltip: ctx.tr('Family'),
                              onSelected: (String value) => setState(() {
                                family = value;
                                edited.add(WordFontProperty.family);
                              }),
                              itemBuilder: (BuildContext context) =>
                                  <PopupMenuEntry<String>>[
                                for (final String f in families)
                                  PopupMenuItem<String>(
                                    value: f,
                                    height: 32,
                                    child: Text(
                                      f,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: f,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: ctx.tr('Family'),
                                  isDense: true,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        family,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: family,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, size: 18),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        ),
                        SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<double>(
                            initialValue: size,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: ctx.tr('Size'),
                              isDense: true,
                            ),
                            items: <DropdownMenuItem<double>>[
                              for (final double s in sizes)
                                DropdownMenuItem<double>(
                                  value: s,
                                  child: Text(s == s.roundToDouble()
                                      ? s.toInt().toString()
                                      : s.toString()),
                                ),
                            ],
                            onChanged: (double? value) {
                              if (value != null) {
                                setState(() {
                                  size = value;
                                  edited.add(WordFontProperty.size);
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        _ToggleChip(
                          label: 'B',
                          selected: bold,
                          bold: true,
                          onTap: () => setState(() {
                            bold = !bold;
                            edited.add(WordFontProperty.bold);
                          }),
                        ),
                        const SizedBox(width: 6),
                        _ToggleChip(
                          label: 'I',
                          selected: italic,
                          italic: true,
                          onTap: () => setState(() {
                            italic = !italic;
                            edited.add(WordFontProperty.italic);
                          }),
                        ),
                        const SizedBox(width: 6),
                        _ToggleChip(
                          label: 'U',
                          selected: underline != WmlUnderline.none,
                          underline: true,
                          onTap: () => setState(() {
                            underline = underline == WmlUnderline.none
                                ? WmlUnderline.single
                                : WmlUnderline.none;
                            edited.add(WordFontProperty.underline);
                          }),
                        ),
                        const SizedBox(width: 6),
                        _ToggleChip(
                          label: 'S',
                          selected: strike,
                          underline: true,
                          onTap: () => setState(() {
                            strike = !strike;
                            edited.add(WordFontProperty.strike);
                          }),
                        ),
                        const Spacer(),
                        DropdownButton<WmlVertAlign>(
                          value: vertAlign,
                          isDense: true,
                          items: <DropdownMenuItem<WmlVertAlign>>[
                            DropdownMenuItem<WmlVertAlign>(
                              value: WmlVertAlign.baseline,
                              child: Text(ctx.tr('Baseline')),
                            ),
                            DropdownMenuItem<WmlVertAlign>(
                              value: WmlVertAlign.superscript,
                              child: Text(ctx.tr('Superscript')),
                            ),
                            DropdownMenuItem<WmlVertAlign>(
                              value: WmlVertAlign.subscript,
                              child: Text(ctx.tr('Subscript')),
                            ),
                          ],
                          onChanged: (WmlVertAlign? value) {
                            if (value != null) {
                              setState(() {
                                vertAlign = value;
                                edited.add(WordFontProperty.vertAlign);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WmlUnderline>(
                      initialValue: underline,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: ctx.tr('Underline style'),
                        isDense: true,
                      ),
                      items: <DropdownMenuItem<WmlUnderline>>[
                        DropdownMenuItem<WmlUnderline>(
                          value: WmlUnderline.none,
                          child: Text(ctx.tr('None')),
                        ),
                        DropdownMenuItem<WmlUnderline>(
                          value: WmlUnderline.single,
                          child: Text(ctx.tr('Single')),
                        ),
                        DropdownMenuItem<WmlUnderline>(
                          value: WmlUnderline.double,
                          child: Text(ctx.tr('Double')),
                        ),
                        DropdownMenuItem<WmlUnderline>(
                          value: WmlUnderline.dotted,
                          child: Text(ctx.tr('Dotted')),
                        ),
                        DropdownMenuItem<WmlUnderline>(
                          value: WmlUnderline.wavy,
                          child: Text(ctx.tr('Wavy')),
                        ),
                      ],
                      onChanged: (WmlUnderline? value) {
                        if (value != null) {
                          setState(() {
                            underline = value;
                            edited.add(WordFontProperty.underline);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _ColorField(
                            label: ctx.tr('Text color'),
                            color: color,
                            onChanged: (String value) => setState(() {
                              color = value;
                              edited.add(WordFontProperty.color);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ColorField(
                            label: ctx.tr('Highlight'),
                            color: highlight ?? '',
                            allowNone: true,
                            onChanged: (String value) => setState(() {
                              highlight = value.isEmpty ? null : value;
                              edited.add(WordFontProperty.highlight);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr('Cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop<WordFontChoice>(ctx, (
                    family: family,
                    sizePt: size,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strike: strike,
                    color: color,
                    highlight: highlight,
                    vertAlign: vertAlign,
                    edited: Set<WordFontProperty>.unmodifiable(edited),
                  ));
                },
                child: Text(ctx.tr('Apply')),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 34,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: underline ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.label,
    required this.color,
    required this.onChanged,
    this.allowNone = false,
  });

  final String label;
  final String color;
  final ValueChanged<String> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final String? picked = await showOfficeColorPicker(
          context,
          initial: color,
          allowNone: allowNone,
          noneLabel: context.tr('No highlight'),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color.isEmpty ? Colors.transparent : _colorFromHex(color),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                color.isEmpty ? MiscUiStrings(context).text('none') : '#$color',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paragraph settings returned by [showWordParagraphDialog].
typedef WordParagraphChoice = ({
  WmlJustification align,
  double left,
  double right,
  double firstLine,
  double hanging,
  double spacingBefore,
  double spacingAfter,
  double lineSpacing,
  WmlLineSpacingRule lineSpacingRule,
  int dropCapLines,
  String borderColor,
  List<WmlTabStop> tabStops,
  bool keepTogether,
  bool pageBreakBefore,
});

Future<WordParagraphChoice?> showWordParagraphDialog(
  BuildContext context, {
  required WmlParagraphProps current,
}) {
  WmlJustification align = current.justification;
  final TextEditingController left = TextEditingController(
    text: current.indent.left.toString(),
  );
  final TextEditingController right = TextEditingController(
    text: current.indent.right.toString(),
  );
  final TextEditingController first = TextEditingController(
    text: current.indent.firstLine.toString(),
  );
  final TextEditingController hanging = TextEditingController(
    text: current.indent.hanging.toString(),
  );
  final TextEditingController before = TextEditingController(
    text: current.spacingBefore.toString(),
  );
  final TextEditingController after = TextEditingController(
    text: current.spacingAfter.toString(),
  );
  final TextEditingController line = TextEditingController(
    text: current.lineSpacing.toString(),
  );
  WmlLineSpacingRule lineSpacingRule = current.lineSpacingRule;
  final TextEditingController dropCap = TextEditingController(
    text: current.dropCapLines.toString(),
  );
  final TextEditingController border = TextEditingController(
    text: current.borderColor ?? '',
  );
  List<WmlTabStop>? tabStops = List<WmlTabStop>.unmodifiable(current.tabs);
  bool keepTogether = current.keepTogether;
  bool pageBreakBefore = current.pageBreakBefore;

  return showDialog<WordParagraphChoice>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: Text(ctx.tr('Paragraph')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      ctx.tr('Alignment'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<WmlJustification>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<WmlJustification>>[
                        ButtonSegment<WmlJustification>(
                          value: WmlJustification.left,
                          icon: Icon(Icons.format_align_left, size: 18),
                        ),
                        ButtonSegment<WmlJustification>(
                          value: WmlJustification.center,
                          icon: Icon(Icons.format_align_center, size: 18),
                        ),
                        ButtonSegment<WmlJustification>(
                          value: WmlJustification.right,
                          icon: Icon(Icons.format_align_right, size: 18),
                        ),
                        ButtonSegment<WmlJustification>(
                          value: WmlJustification.justify,
                          icon: Icon(Icons.format_align_justify, size: 18),
                        ),
                      ],
                      selected: <WmlJustification>{align},
                      onSelectionChanged: (Set<WmlJustification> value) {
                        setState(() => align = value.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _numberField(left, ctx.tr('Left indent (pt)')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numberField(
                            right,
                            ctx.tr('Right indent (pt)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _numberField(first, ctx.tr('First line (pt)')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numberField(hanging, ctx.tr('Hanging (pt)')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _numberField(
                            before,
                            ctx.tr('Space before (pt)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numberField(
                            after,
                            ctx.tr('Space after (pt)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numberField(line, ctx.tr('Line spacing')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<WmlLineSpacingRule>(
                      initialValue: lineSpacingRule,
                      decoration: InputDecoration(
                        labelText: ctx.tr('Line spacing rule'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<WmlLineSpacingRule>>[
                        DropdownMenuItem(
                          value: WmlLineSpacingRule.auto,
                          child: Text('Multiple / single'),
                        ),
                        DropdownMenuItem(
                          value: WmlLineSpacingRule.atLeast,
                          child: Text('At least (pt)'),
                        ),
                        DropdownMenuItem(
                          value: WmlLineSpacingRule.exact,
                          child: Text('Exactly (pt)'),
                        ),
                      ],
                      onChanged: (WmlLineSpacingRule? value) {
                        if (value != null) {
                          setState(() => lineSpacingRule = value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _numberField(
                            dropCap,
                            ctx.tr('Drop cap lines'),
                            integer: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: border,
                            decoration: InputDecoration(
                              labelText: ctx.tr('Paragraph border (RRGGBB)'),
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    WordTabStopsEditor(
                      initialValue: current.tabs,
                      translate: ctx.tr,
                      onChanged: (value) => tabStops = value,
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(ctx.tr('Keep lines together')),
                      value: keepTogether,
                      onChanged: (bool value) =>
                          setState(() => keepTogether = value),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(ctx.tr('Page break before')),
                      value: pageBreakBefore,
                      onChanged: (bool value) =>
                          setState(() => pageBreakBefore = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr('Cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  double parse(
                    TextEditingController c,
                    double fallback, {
                    bool nonnegative = false,
                    bool positive = false,
                  }) {
                    final value = double.tryParse(c.text.trim());
                    if (value == null ||
                        !value.isFinite ||
                        (nonnegative && value < 0) ||
                        (positive && value <= 0)) {
                      return fallback;
                    }
                    return value;
                  }

                  // The shared editor keeps invalid drafts visible. Applying
                  // an earlier valid value would silently discard current input.
                  final tabs = tabStops;
                  if (tabs == null) {
                    return;
                  }
                  final String borderColor = border.text
                      .trim()
                      .replaceAll('#', '')
                      .toUpperCase();
                  Navigator.pop<WordParagraphChoice>(ctx, (
                    align: align,
                    left: parse(left, current.indent.left),
                    right: parse(right, current.indent.right),
                    firstLine: parse(
                      first,
                      current.indent.firstLine,
                      nonnegative: true,
                    ),
                    hanging: parse(
                      hanging,
                      current.indent.hanging,
                      nonnegative: true,
                    ),
                    spacingBefore: parse(
                      before,
                      current.spacingBefore,
                      nonnegative: true,
                    ),
                    spacingAfter: parse(
                      after,
                      current.spacingAfter,
                      nonnegative: true,
                    ),
                    lineSpacing: parse(
                      line,
                      current.lineSpacing,
                      positive: true,
                    ),
                    lineSpacingRule: lineSpacingRule,
                    dropCapLines:
                        (int.tryParse(dropCap.text.trim()) ??
                                current.dropCapLines)
                            .clamp(0, 10),
                    borderColor:
                        borderColor.isEmpty ||
                            RegExp(r'^[0-9A-F]{6}$').hasMatch(borderColor)
                        ? borderColor
                        : current.borderColor ?? '',
                    tabStops: tabs,
                    keepTogether: keepTogether,
                    pageBreakBefore: pageBreakBefore,
                  ));
                },
                child: Text(ctx.tr('Apply')),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _numberField(
  TextEditingController controller,
  String label, {
  bool integer = false,
}) {
  return TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(labelText: label, isDense: true),
  );
}

Future<({int rows, int columns})?> showInsertTableDialog(
  BuildContext context, {
  int rows = 3,
  int columns = 3,
}) {
  final TextEditingController rowController =
      TextEditingController(text: '$rows');
  final TextEditingController colController =
      TextEditingController(text: '$columns');
  return showDialog<({int rows, int columns})>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(ctx.tr('Insert table')),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: rowController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ctx.tr('Rows'),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: colController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ctx.tr('Columns'),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            final int r = (int.tryParse(rowController.text) ?? rows).clamp(1, 50);
            final int c =
                (int.tryParse(colController.text) ?? columns).clamp(1, 20);
            Navigator.pop<({int rows, int columns})>(ctx, (rows: r, columns: c));
          },
          child: Text(ctx.tr('Insert')),
        ),
      ],
    ),
  );
}

Future<({String text, String url})?> showHyperlinkDialog(
  BuildContext context, {
  String text = '',
  String url = 'https://',
}) {
  final TextEditingController textController =
      TextEditingController(text: text);
  final TextEditingController urlController = TextEditingController(text: url);
  return showDialog<({String text, String url})>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(ctx.tr('Insert hyperlink')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: ctx.tr('Text'),
                helperText: ctx.tr('Leave empty to use the selected text'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: ctx.tr('Address'),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            final String address = urlController.text.trim();
            if (address.isEmpty) return;
            Navigator.pop<({String text, String url})>(
              ctx,
              (text: textController.text.trim(), url: address),
            );
          },
          child: Text(ctx.tr('Insert')),
        ),
      ],
    ),
  );
}

Future<({double top, double bottom, double left, double right})?>
showPageMarginsDialog(BuildContext context, {required WmlPageMargins current}) {
  String inchesText(double points) => (points / 72).toString();
  TextEditingController inches(double points) =>
      TextEditingController(text: inchesText(points));
  final TextEditingController top = inches(current.top);
  final TextEditingController bottom = inches(current.bottom);
  final TextEditingController left = inches(current.left);
  final TextEditingController right = inches(current.right);
  return showDialog<({double top, double bottom, double left, double right})>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(ctx.tr('Page margins')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _inchField(top, ctx.tr('Top (in)'))),
                const SizedBox(width: 8),
                Expanded(child: _inchField(bottom, ctx.tr('Bottom (in)'))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _inchField(left, ctx.tr('Left (in)'))),
                const SizedBox(width: 8),
                Expanded(child: _inchField(right, ctx.tr('Right (in)'))),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            double parse(TextEditingController c, double fallback) {
              final text = c.text.trim();
              // Keep unchanged imported geometry exact, including values
              // outside the dialog's range for newly entered margins.
              if (text == inchesText(fallback)) return fallback;
              final value = double.tryParse(text);
              if (value == null || !value.isFinite) return fallback;
              return (value * 72).clamp(0, 432).toDouble();
            }

            Navigator.pop<
              ({double top, double bottom, double left, double right})
            >(ctx, (
              top: parse(top, current.top),
              bottom: parse(bottom, current.bottom),
              left: parse(left, current.left),
              right: parse(right, current.right),
            ));
          },
          child: Text(ctx.tr('Apply')),
        ),
      ],
    ),
  );
}

Widget _inchField(TextEditingController controller, String label) {
  return TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
    ),
  );
}

Future<String?> showOfficePromptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? helper,
  bool multiline = false,
  bool trimResult = true,
  String confirmLabel = 'OK',
}) {
  final TextEditingController controller =
      TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            isDense: true,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            ctx, trimResult ? controller.text.trim() : controller.text,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<({String text, String author})?> showCommentDialog(
  BuildContext context, {
  String text = '',
  String author = 'CrispCloud',
}) {
  final TextEditingController textController =
      TextEditingController(text: text);
  final TextEditingController authorController =
      TextEditingController(text: author);
  return showDialog<({String text, String author})>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(ctx.tr('New comment')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: authorController,
              decoration: InputDecoration(
                labelText: ctx.tr('Author'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textController,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.tr('Comment'),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            final String body = textController.text.trim();
            if (body.isEmpty) return;
            Navigator.pop<({String text, String author})>(
              ctx,
              (text: body, author: authorController.text.trim()),
            );
          },
          child: Text(ctx.tr('Add')),
        ),
      ],
    ),
  );
}

Future<bool> showOfficeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('Cancel')),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showOfficeShortcuts(BuildContext context, String kind) {
  final List<(String, String)> rows = <(String, String)>[
    ('Ctrl/Cmd + S', 'Save'),
    ('Ctrl/Cmd + Z', 'Undo'),
    ('Ctrl/Cmd + Y', 'Redo'),
    ('Ctrl/Cmd + F', 'Find'),
    ('Ctrl/Cmd + A', 'Select all'),
    ('Ctrl/Cmd + C / X / V', 'Copy / cut / paste'),
    if (kind == 'word') ...<(String, String)>[
      ('Ctrl/Cmd + B', 'Bold'),
      ('Ctrl/Cmd + I', 'Italic'),
      ('Ctrl/Cmd + U', 'Underline'),
    ],
    ('Esc', 'Close find bar, then the editor'),
  ];
  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(ctx.tr('Keyboard shortcuts')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (String, String) row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 165,
                      child: Text(
                        row.$1,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text(context.tr(row.$2))),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('Close')),
        ),
      ],
    ),
  );
}
