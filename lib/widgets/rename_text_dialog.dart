import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/commander_strings.dart';

/// Editable text exchange for target-name lists and versioned rule presets.
class RenameTextDialog extends StatefulWidget {
  const RenameTextDialog({
    super.key,
    required this.title,
    required this.instructions,
    required this.initialText,
    required this.submitLabel,
    this.validate,
    this.fileExtensions = const ['txt'],
    this.filename = 'rename-names.txt',
  });
  final String title;
  final String instructions;
  final String initialText;
  final String submitLabel;
  final String? Function(String)? validate;
  final List<String> fileExtensions;
  final String filename;
  @override
  State<RenameTextDialog> createState() => _RenameTextDialogState();
}

class _RenameTextDialogState extends State<RenameTextDialog> {
  late final _text = TextEditingController(text: widget.initialText);
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.fileExtensions,
        withData: true,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      if (file.size > 2 * 1024 * 1024 || file.bytes == null) {
        throw const FormatException(
          'Choose a UTF-8 text file no larger than 2 MiB.',
        );
      }
      _text.text = utf8.decode(file.bytes!);
      setState(() => _error = widget.validate?.call(_text.text));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: context.commanderTr("Save {0}", [widget.title]),
        fileName: widget.filename,
        bytes: Uint8List.fromList(utf8.encode(_text.text)),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 650,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.instructions),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.sizeOf(context).height.clamp(180, 360) - 80,
            child: TextField(
              key: const ValueKey('rename-import-text'),
              controller: _text,
              expands: true,
              minLines: null,
              maxLines: null,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                labelText: context.commanderTr("Text"),
              ),
              onChanged: (value) =>
                  setState(() => _error = widget.validate?.call(value)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _read,
                icon: const Icon(Icons.upload_file),
                label: Text(context.commanderTr("Load file")),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: Text(context.commanderTr("Save file")),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (mounted && data?.text != null) {
                          _text.text = data!.text!;
                          setState(
                            () => _error = widget.validate?.call(_text.text),
                          );
                        }
                      },
                child: Text(context.commanderTr("Paste")),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: _text.text)),
                child: Text(context.commanderTr("Copy")),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.commanderTr("Cancel")),
      ),
      FilledButton(
        key: const ValueKey('rename-import-apply'),
        onPressed: _busy
            ? null
            : () {
                final error = widget.validate?.call(_text.text);
                if (error != null) {
                  setState(() => _error = error);
                  return;
                }
                Navigator.pop(context, _text.text);
              },
        child: Text(widget.submitLabel),
      ),
    ],
  );
}
