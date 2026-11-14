import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/csv_spreadsheet_strings.dart';
import '../services/csv_spreadsheet_import.dart';
import '../services/editor_document.dart';

List<List<String>> _parseImport(
  (String, Uint8List?, String?, EditorEncoding?) request,
) {
  final text = request.$2 == null
      ? request.$1
      : EditorDocument.decode(request.$2!, encodingOverride: request.$4).text;
  return parseSpreadsheetText(text, delimiter: request.$3);
}

Future<bool?> showCsvSpreadsheetImportDialog(
  BuildContext context, {
  required String sourceName,
  required String text,
  Uint8List? sourceBytes,
  required Future<void> Function(String, Uint8List) onCreate,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CsvSpreadsheetImportDialog(
    sourceName: sourceName,
    text: text,
    sourceBytes: sourceBytes,
    onCreate: onCreate,
  ),
);

class CsvSpreadsheetImportDialog extends StatefulWidget {
  const CsvSpreadsheetImportDialog({
    super.key,
    required this.sourceName,
    required this.text,
    this.sourceBytes,
    required this.onCreate,
  });
  final String sourceName, text;
  final Uint8List? sourceBytes;
  final Future<void> Function(String, Uint8List) onCreate;
  @override
  State<CsvSpreadsheetImportDialog> createState() =>
      _CsvSpreadsheetImportDialogState();
}

class _CsvSpreadsheetImportDialogState
    extends State<CsvSpreadsheetImportDialog> {
  late final TextEditingController _name;
  String? _delimiter, _error;
  EditorEncoding? _encoding;
  List<List<String>>? _rows;
  bool _numbers = false, _loading = true, _saving = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: '${p.basenameWithoutExtension(widget.sourceName)}-imported.xlsx',
    );
    if (widget.sourceName.toLowerCase().endsWith('.tsv')) _delimiter = '\t';
    unawaited(_preview());
  }

  @override
  void dispose() {
    _generation++;
    _name.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await compute(_parseImport, (
        widget.text,
        widget.sourceBytes,
        _delimiter,
        _encoding,
      ));
      if (mounted && generation == _generation) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = null;
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _create() async {
    if (_saving || _rows == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await compute(buildSpreadsheetCopy, (_rows!, _numbers));
      if (!mounted) return;
      await widget.onCreate(_name.text, bytes);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = CsvSpreadsheetStrings(context);
    final rows = _rows ?? const <List<String>>[];
    final columns = rows.fold<int>(
      0,
      (n, row) => row.length > n ? row.length : n,
    );
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(strings.text('action')),
        content: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.sourceName),
              const SizedBox(height: 8),
              Text(strings.text('explain')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_delimiter ?? 'auto'),
                initialValue: _delimiter ?? 'auto',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: strings.text('delimiter'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text(strings.text('auto')),
                  ),
                  DropdownMenuItem(
                    value: ',',
                    child: Text(strings.text('comma')),
                  ),
                  DropdownMenuItem(
                    value: ';',
                    child: Text(strings.text('semicolon')),
                  ),
                  DropdownMenuItem(
                    value: '\t',
                    child: Text(strings.text('tab')),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(
                          () => _delimiter = value == 'auto' ? null : value,
                        );
                        unawaited(_preview());
                      },
              ),
              if (widget.sourceBytes != null)
                DropdownButtonFormField<String>(
                  key: ValueKey('encoding-${_encoding?.name ?? "auto"}'),
                  initialValue: _encoding?.name ?? 'auto',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: strings.text('encoding'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(strings.text('auto')),
                    ),
                    for (final value in EditorEncoding.values)
                      DropdownMenuItem(
                        value: value.name,
                        child: Text(value.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(
                            () => _encoding = value == 'auto'
                                ? null
                                : EditorEncoding.values.byName(value!),
                          );
                          unawaited(_preview());
                        },
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _numbers,
                title: Text(strings.text('numbers')),
                subtitle: Text(strings.text('numbersHelp')),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _numbers = value ?? false),
              ),
              TextField(
                controller: _name,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: strings.text('filename'),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading || _saving) const LinearProgressIndicator(),
              if (!_loading) Text(strings.dimensions(rows.length, columns)),
              if (!_loading && rows.isNotEmpty) ...[
                Text(strings.text('preview')),
                SizedBox(
                  height: 220,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: [
                          const DataColumn(label: Text('#')),
                          for (var c = 0; c < columns && c < 10; c++)
                            DataColumn(label: Text('${c + 1}')),
                        ],
                        rows: [
                          for (var r = 0; r < rows.length && r < 20; r++)
                            DataRow(
                              cells: [
                                DataCell(Text('${r + 1}')),
                                for (var c = 0; c < columns && c < 10; c++)
                                  DataCell(
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        c < rows[r].length ? rows[r][c] : '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null)
                SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: _loading || _saving || _rows == null ? null : _create,
            child: Text(strings.text('create')),
          ),
        ],
      ),
    );
  }
}
