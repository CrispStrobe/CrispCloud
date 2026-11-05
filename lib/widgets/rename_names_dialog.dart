import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/rename_name_list.dart';

/// Edit or import a complete ordered set of names before applying it to the
/// multi-rename preview. Nothing here performs a filesystem mutation.
class RenameNamesDialog extends StatefulWidget {
  const RenameNamesDialog({super.key, required this.names});

  final List<String> names;

  @override
  State<RenameNamesDialog> createState() => _RenameNamesDialogState();
}

class _RenameNamesDialogState extends State<RenameNamesDialog> {
  late final _input = TextEditingController(text: widget.names.join('\n'));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load(bool fromFile) async {
    setState(() => _busy = true);
    try {
      String? text;
      if (fromFile) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['txt', 'lst'],
          withData: true,
        );
        if (picked == null) return;
        final file = picked.files.single;
        if (file.size > 4 * 1024 * 1024 ||
            (file.bytes?.length ?? 0) > 4 * 1024 * 1024) {
          throw const FormatException('The name list exceeds 4 MiB.');
        }
        if (file.bytes == null) {
          throw StateError('The chosen file could not be read.');
        }
        text = utf8.decode(file.bytes!);
      } else {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        if (text == null) {
          throw const FormatException('The clipboard does not contain text.');
        }
      }
      if (mounted) {
        setState(() {
          _input.text = text!;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply() {
    try {
      final names = parseRenameNameList(
        _input.text,
        expectedCount: widget.names.length,
      );
      Navigator.pop(context, names);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit proposed names'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter ${widget.names.length} names, one per line, in preview order. '
              'Include extensions. Excluded rows are not included.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('rename-names-input'),
              controller: _input,
              enabled: !_busy,
              minLines: 5,
              maxLines: 12,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Proposed names',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _load(false),
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste names'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _load(true),
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Open .txt / .lst'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
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
        key: const ValueKey('rename-names-apply'),
        onPressed: _busy ? null : _apply,
        child: const Text('Update preview'),
      ),
    ],
  );
}
