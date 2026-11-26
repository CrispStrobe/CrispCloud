import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_units.dart';

/// Edits custom paragraph tab stops without changing the document.
///
/// Hosts provide their translations and apply the returned values through their
/// normal paragraph-format command. A null callback value means that a draft is
/// invalid: keep the editor open rather than applying the last valid value.
/// Opening or cancelling the editor never changes [initialValue]. Positions
/// accept a dot or comma decimal separator without digit grouping.
class WordTabStopsEditor extends StatefulWidget {
  const WordTabStopsEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.translate,
    this.unit,
    this.enabled = true,
  });

  /// Initial stops, copied when this widget is mounted.
  final List<WmlTabStop> initialValue;

  /// Immutable valid draft, or null while any position cannot be saved safely.
  final ValueChanged<List<WmlTabStop>?> onChanged;

  /// Translates the English labels and validation messages for the host.
  final String Function(String english)? translate;

  final OfficeLengthUnit? unit;
  final bool enabled;

  @override
  State<WordTabStopsEditor> createState() => _WordTabStopsEditorState();
}

class _WordTabStopsEditorState extends State<WordTabStopsEditor> {
  late final List<_TabDraft> _drafts = <_TabDraft>[
    for (final tab in widget.initialValue) _draft(tab),
  ];

  String _text(String english) => widget.translate?.call(english) ?? english;

  double? _parsePosition(String text) => widget.unit == null
      ? double.tryParse(text.trim().replaceAll(',', '.'))
      : widget.unit!.parsePoints(text);

  _TabDraft _draft(WmlTabStop tab) => _TabDraft(
    tab,
    widget.unit?.fromPoints(tab.position).toStringAsFixed(5) ??
        tab.position.toString(),
  );

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.position.dispose();
    }
    super.dispose();
  }

  void _changed() {
    final values = <WmlTabStop>[];
    final positions = <int, _TabDraft>{};
    var valid = true;
    for (final draft in _drafts) {
      draft.error = null;
      final position = draft.position.text == draft.display
          ? draft.originalPosition
          : _parsePosition(draft.position.text);
      // w:pos is a signed 32-bit twip value. Also reject distinct input values
      // which would collapse onto the same serialized stop after rounding.
      if (position == null ||
          !position.isFinite ||
          position < 0 ||
          position * 20 > 2147483647) {
        draft.error = 'Enter a finite, nonnegative position.';
        valid = false;
        continue;
      }
      final twips = (position * 20).round();
      final previous = positions[twips];
      if (previous != null) {
        previous.error = draft.error = 'Tab positions must be distinct.';
        valid = false;
      } else {
        positions[twips] = draft;
      }
      values.add(
        WmlTabStop(
          position: position,
          alignment: draft.alignment,
          leader: draft.leader,
        ),
      );
    }
    setState(() {});
    widget.onChanged(valid ? List<WmlTabStop>.unmodifiable(values) : null);
  }

  void _add() {
    var position = 0.0;
    for (final draft in _drafts) {
      final value = _parsePosition(draft.position.text);
      if (value != null && value.isFinite && value > position) {
        position = value;
      }
    }
    _drafts.add(_draft(WmlTabStop(position: position + 36)));
    _changed();
  }

  void _remove(_TabDraft draft) {
    _drafts.remove(draft);
    // A focused TextField may still listen until its element is unmounted.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => draft.position.dispose(),
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _text('Custom tab stops'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        for (var index = 0; index < _drafts.length; index++)
          _row(context, _drafts[index], index),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('word-tab-add'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: widget.enabled ? _add : null,
            icon: const Icon(Icons.add),
            label: Text(_text('Add tab stop')),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, _TabDraft draft, int index) {
    return Padding(
      key: ObjectKey(draft),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ValueKey<String>('word-tab-position-$index'),
                  controller: draft.position,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _text(
                      'Tab position (pt)',
                    ).replaceFirst('(pt)', '(${widget.unit?.suffix ?? 'pt'})'),
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    errorText: draft.error == null ? null : _text(draft.error!),
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _changed(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey<String>('word-tab-remove-$index'),
                onPressed: widget.enabled ? () => _remove(draft) : null,
                tooltip: _text('Remove tab stop'),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final alignment = _alignment(draft, index);
              final leader = _leader(draft, index);
              if (constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    alignment,
                    const SizedBox(height: 10),
                    leader,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: alignment),
                  const SizedBox(width: 10),
                  Expanded(child: leader),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _alignment(_TabDraft draft, int index) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<WmlTabAlignment>(
      key: ValueKey<String>('word-tab-alignment-$index'),
      initialValue: draft.alignment,
      isExpanded: true,
      // The dropdown route paints its menu with theme.canvasColor and the
      // selected text with the button style. Both are explicit here so a
      // translated/host theme cannot produce white text on a white menu.
      dropdownColor: scheme.surfaceContainerHigh,
      style: TextStyle(color: scheme.onSurface),
      iconEnabledColor: scheme.onSurfaceVariant,
      decoration: InputDecoration(
        labelText: _text('Tab alignment'),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<WmlTabAlignment>>[
        for (final (value, label) in const <(WmlTabAlignment, String)>[
          (WmlTabAlignment.left, 'Left'),
          (WmlTabAlignment.center, 'Center'),
          (WmlTabAlignment.right, 'Right'),
          (WmlTabAlignment.decimal, 'Decimal'),
        ])
          DropdownMenuItem(value: value, child: Text(_text(label))),
      ],
      onChanged: widget.enabled
          ? (value) {
              if (value != null) {
                draft.alignment = value;
                _changed();
              }
            }
          : null,
    );
  }

  Widget _leader(_TabDraft draft, int index) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<WmlTabLeader>(
      key: ValueKey<String>('word-tab-leader-$index'),
      initialValue: draft.leader,
      isExpanded: true,
      dropdownColor: scheme.surfaceContainerHigh,
      style: TextStyle(color: scheme.onSurface),
      iconEnabledColor: scheme.onSurfaceVariant,
      decoration: InputDecoration(
        labelText: _text('Tab leader'),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<WmlTabLeader>>[
        for (final (value, label) in const <(WmlTabLeader, String)>[
          (WmlTabLeader.none, 'None'),
          (WmlTabLeader.dot, 'Dots'),
          (WmlTabLeader.hyphen, 'Dashes'),
          (WmlTabLeader.underscore, 'Underline'),
        ])
          DropdownMenuItem(value: value, child: Text(_text(label))),
      ],
      onChanged: widget.enabled
          ? (value) {
              if (value != null) {
                draft.leader = value;
                _changed();
              }
            }
          : null,
    );
  }
}

class _TabDraft {
  _TabDraft(WmlTabStop tab, this.display)
    : position = TextEditingController(text: display),
      originalPosition = tab.position,
      alignment = tab.alignment,
      leader = tab.leader;

  final TextEditingController position;
  final String display;
  final double originalPosition;
  WmlTabAlignment alignment;
  WmlTabLeader leader;
  String? error;
}
