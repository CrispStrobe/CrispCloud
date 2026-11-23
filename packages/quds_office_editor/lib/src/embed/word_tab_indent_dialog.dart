import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';
import 'office_units.dart';
import 'word_tab_stops_editor.dart';

/// Edit direct or style-based geometry in the host's preferred ruler units.
Future<void> showWordTabIndentDialog(
  BuildContext context, {
  required WordEditorController controller,
  required OfficeLengthUnit unit,
  String? styleId,
  String? styleName,
  String Function(String)? translate,
}) async {
  final document = controller.document;
  final revision = controller.contentRevision;
  final range = controller.caret.normalizedRange;
  final current = styleId == null
      ? controller.activeParagraphProperties.copy()
      : WordDeserializer().paragraphStyleProperties(document, styleId);
  if (current == null) return;
  String tr(String label) => translate?.call(label) ?? label;
  final values = [
    current.indent.left,
    current.indent.right,
    current.indent.firstLine,
    current.indent.hanging,
    document.defaultTabStop ?? kDefaultTabWidth,
  ];
  final drafts = values
      .map((value) => unit.fromPoints(value).toStringAsFixed(5))
      .toList();
  final edits = List.of(drafts);
  List<WmlTabStop>? tabs = current.tabs;
  final result = await showDialog<(WmlIndent, List<WmlTabStop>?, double?)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final points = <double?>[
          for (var i = 0; i < drafts.length; i++)
            edits[i] == drafts[i] ? values[i] : unit.parsePoints(edits[i]),
        ];
        final valid = [
          for (var i = 0; i < points.length; i++)
            points[i] != null &&
                points[i]!.abs() <= 1584 &&
                (i < 2 || points[i]! >= (i == 4 ? 0.05 : 0)),
        ];
        final conflicting = (points[2] ?? 0) > 0 && (points[3] ?? 0) > 0;
        final labels = [
          'Left indent',
          'Right indent',
          'First line indent',
          'Hanging indent',
          'Default tab interval',
        ];
        return AlertDialog(
          title: Text(
            styleName == null
                ? tr('Tabs and indents')
                : '${tr('Style tabs and indents')} · $styleName',
          ),
          scrollable: true,
          content: SizedBox(
            width: 480,
            child: Column(
              children: [
                for (var i = 0; i < (styleId == null ? 5 : 4); i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      initialValue: drafts[i],
                      autofocus: i == 0,
                      decoration: InputDecoration(
                        labelText: '${tr(labels[i])} (${unit.suffix})',
                        errorText: valid[i]
                            ? null
                            : tr('Enter a valid distance'),
                      ),
                      onChanged: (value) => setState(() => edits[i] = value),
                    ),
                  ),
                WordTabStopsEditor(
                  initialValue: current.tabs,
                  unit: unit,
                  translate: translate,
                  onChanged: (value) => setState(() => tabs = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: tabs == null || valid.contains(false) || conflicting
                  ? null
                  : () {
                      final first = points[2]!;
                      final hanging = points[3]!;
                      Navigator.pop(context, (
                        WmlIndent(
                          left: points[0]!,
                          right: points[1]!,
                          firstLine: first,
                          hanging: hanging,
                        ),
                        identical(tabs, current.tabs) ? null : tabs,
                        styleId == null ? points[4] : null,
                      ));
                    },
              child: Text(tr('Apply')),
            ),
          ],
        );
      },
    ),
  );
  if (!context.mounted ||
      result == null ||
      controller.isDisposed ||
      !identical(document, controller.document) ||
      revision != controller.contentRevision ||
      range != controller.caret.normalizedRange) {
    return;
  }
  final (indent, stops, interval) = result;
  if (styleId != null) {
    controller.setParagraphStyleGeometry(
      styleId,
      indent: indent,
      tabs: stops ?? current.tabs,
    );
    return;
  }
  final before = current.indent;
  final changed =
      indent.left != before.left ||
      indent.right != before.right ||
      indent.firstLine != before.firstLine ||
      indent.hanging != before.hanging;
  if (changed || stops != null) {
    controller.applyParagraphFormat((properties) {
      if (!changed) return;
      properties
        ..indent = properties.indent.copyWith(
          left: indent.left != before.left ? indent.left : null,
          right: indent.right != before.right ? indent.right : null,
          firstLine: indent.firstLine != before.firstLine
              ? indent.firstLine
              : null,
          hanging: indent.hanging != before.hanging ? indent.hanging : null,
        )
        ..explicitIndent = true;
    }, tabStops: stops);
  }
  if (interval != null) controller.setDefaultTabStop(interval);
}
