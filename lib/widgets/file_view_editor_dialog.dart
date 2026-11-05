import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/file_view_configuration.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';

Future<void> showPanelViewDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  final panel = ref.read(panelProvider(side));
  final value = await showDialog<FileViewConfiguration>(
    context: context,
    builder: (_) => FileViewEditorDialog(
      initial: panel.captureViewConfiguration(),
      samples: panel.files ?? const [],
    ),
  );
  if (value != null && context.mounted) {
    await panel.applyViewConfiguration(value);
  }
}

class FileViewEditorDialog extends StatefulWidget {
  const FileViewEditorDialog({
    super.key,
    required this.initial,
    this.samples = const [],
  });
  final FileViewConfiguration initial;
  final List<FileItem> samples;
  @override
  State<FileViewEditorDialog> createState() => _FileViewEditorDialogState();
}

class _FileViewEditorDialogState extends State<FileViewEditorDialog> {
  final _form = GlobalKey<FormState>();
  late var _display = widget.initial.display;
  late var _hidden = widget.initial.showHidden;
  late final _columns = List<FileColumnDefinition>.of(widget.initial.columns);
  late final _widths = Map<String, double>.of(widget.initial.widths);
  late var _primary = widget.initial.sortColumnId == null
      ? widget.initial.sortBy.name
      : 'column:${widget.initial.sortColumnId}';
  late var _secondary = widget.initial.secondarySortColumnId == null
      ? widget.initial.secondarySortBy?.name ?? 'none'
      : 'column:${widget.initial.secondarySortColumnId}';
  late var _primaryOrder = widget.initial.sortOrder;
  late var _secondaryOrder = widget.initial.secondarySortOrder;
  late final _filter = TextEditingController(text: widget.initial.filter);
  String? _error;
  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  FileViewConfiguration _configuration() => FileViewConfiguration(
    display: _display,
    columns: _columns,
    widths: _widths,
    sortBy: _primary.startsWith('column:')
        ? SortBy.name
        : SortBy.values.byName(_primary),
    sortColumnId: _primary.startsWith('column:') ? _primary.substring(7) : null,
    sortOrder: _primaryOrder,
    secondarySortBy: _secondary == 'none' || _secondary.startsWith('column:')
        ? null
        : SortBy.values.byName(_secondary),
    secondarySortColumnId: _secondary.startsWith('column:')
        ? _secondary.substring(7)
        : null,
    secondarySortOrder: _secondaryOrder,
    showHidden: _hidden,
    filter: _filter.text,
  );

  void _move(int index, int delta) => setState(() {
    final item = _columns.removeAt(index);
    _columns.insert(index + delta, item);
  });

  Future<void> _addColumn() async {
    final column = await showDialog<FileColumnDefinition>(
      context: context,
      builder: (_) => _AddColumnDialog(
        existingIds: _columns.map((column) => column.id).toSet(),
      ),
    );
    if (column != null && mounted) {
      setState(() {
        _columns.add(column);
        _widths[column.id] = column.defaultWidth;
      });
    }
  }

  Widget _sort(
    String label,
    String selected,
    ValueChanged<String> change,
    SortOrder order,
    ValueChanged<SortOrder> changeOrder, {
    bool optional = false,
  }) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      SizedBox(
        width: 230,
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            '$label:$selected:${_columns.map((column) => column.id).join(',')}',
          ),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (optional)
              const DropdownMenuItem(value: 'none', child: Text('None')),
            for (final value in SortBy.values)
              DropdownMenuItem(value: value.name, child: Text(value.name)),
            for (final column in _columns)
              DropdownMenuItem(
                value: 'column:${column.id}',
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => change(value));
          },
        ),
      ),
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<SortOrder>(
          key: ValueKey('$label:${order.name}'),
          initialValue: order,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Direction'),
          items: [
            for (final value in SortOrder.values)
              DropdownMenuItem(value: value, child: Text(value.name)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => changeOrder(value));
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Columns and view'),
    content: Form(
      key: _form,
      child: SizedBox(
        width: 690,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<FileViewDisplay>(
              initialValue: _display,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Display'),
              items: [
                for (final mode in FileViewDisplay.values)
                  DropdownMenuItem(value: mode, child: Text(mode.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _display = value);
              },
            ),
            const SizedBox(height: 12),
            _sort(
              'Primary sort',
              _primary,
              (value) => _primary = value,
              _primaryOrder,
              (value) => _primaryOrder = value,
            ),
            const SizedBox(height: 12),
            _sort(
              'Secondary sort',
              _secondary,
              (value) => _secondary = value,
              _secondaryOrder,
              (value) => _secondaryOrder = value,
              optional: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filter,
              decoration: const InputDecoration(
                labelText: 'Saved name filter',
                helperText: 'A manual filter is saved with this view. Temporary type-ahead is not.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show hidden files'),
              value: _hidden,
              onChanged: (value) => setState(() => _hidden = value ?? false),
            ),
            const Divider(),
            const Text(
              'Columns in Full view',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'The name column stays visible. Narrow panes reveal fewer columns; resize the pane to show the rest.',
            ),
            for (var index = 0; index < _columns.length; index++)
              _columnCard(index),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _columns.length >= 24 ? null : _addColumn,
                icon: const Icon(Icons.add),
                label: const Text('Add column'),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('apply-view'),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          try {
            Navigator.pop(context, _configuration());
          } catch (error) {
            setState(() => _error = error.toString());
          }
        },
        child: const Text('Apply view'),
      ),
    ],
  );

  Widget _columnCard(int index) {
    final column = _columns[index];
    final width = _widths[column.id] ?? column.defaultWidth;
    final sample = widget.samples
        .where((file) => file.name != '..')
        .firstOrNull;
    return Card(
      key: ValueKey('view-column-${column.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  value: width > 0,
                  onChanged: (_) => setState(() => _widths[column.id] = -width),
                ),
                Expanded(
                  child: Text(
                    column.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Move ${column.label} up',
                  onPressed: index == 0 ? null : () => _move(index, -1),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Move ${column.label} down',
                  onPressed: index == _columns.length - 1
                      ? null
                      : () => _move(index, 1),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove ${column.label}',
                  onPressed: () => setState(() {
                    _columns.removeAt(index);
                    _widths.remove(column.id);
                    if (_primary == 'column:${column.id}') _primary = 'name';
                    if (_secondary == 'column:${column.id}') {
                      _secondary = 'none';
                    }
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 105,
                  child: TextFormField(
                    key: ValueKey('column-width-${column.id}'),
                    initialValue: '${width.abs().round()}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width (px)'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (text) {
                      final value = double.tryParse(text ?? '');
                      return value == null ||
                              value < 24 ||
                              value > 600 ||
                              !value.isFinite
                          ? '24–600'
                          : null;
                    },
                    onChanged: (text) {
                      final value = double.tryParse(text);
                      if (value != null) {
                        _widths[column.id] = width > 0 ? value : -value;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    column.kind == FileColumnKind.metadata
                        ? 'Field: ${column.metadataKey}\n${sample == null ? '' : column.displayValue(sample)}'
                        : sample == null
                        ? ''
                        : column.displayValue(sample),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddColumnDialog extends StatefulWidget {
  const _AddColumnDialog({required this.existingIds});
  final Set<String> existingIds;
  @override
  State<_AddColumnDialog> createState() => _AddColumnDialogState();
}

class _AddColumnDialogState extends State<_AddColumnDialog> {
  var _kind = FileColumnKind.metadata;
  final _label = TextEditingController();
  final _field = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Add column'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<FileColumnKind>(
            initialValue: _kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Value'),
            items: [
              for (final kind in FileColumnKind.values)
                DropdownMenuItem(value: kind, child: Text(kind.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _kind = value);
            },
          ),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Column title'),
          ),
          if (_kind == FileColumnKind.metadata)
            TextField(
              controller: _field,
              decoration: const InputDecoration(
                labelText: 'Metadata field',
                helperText: 'A supplied key such as mimeType or image.width. No file downloads or external programs are run.',
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          var id = _kind.name;
          var number = 2;
          while (widget.existingIds.contains(id)) {
            id = '${_kind.name}_${number++}';
          }
          final value = FileColumnDefinition(
            id: id,
            label: _label.text.trim().isEmpty ? _kind.name : _label.text.trim(),
            kind: _kind,
            metadataKey: _kind == FileColumnKind.metadata
                ? _field.text.trim()
                : null,
          );
          try {
            value.validate();
            Navigator.pop(context, value);
          } catch (error) {
            setState(() => _error = error.toString());
          }
        },
        child: const Text('Add'),
      ),
    ],
  );
}
