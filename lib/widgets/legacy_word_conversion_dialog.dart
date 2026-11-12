import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../l10n/legacy_word_conversion_strings.dart';

/// Prepares a text-only DOCX copy after describing the conversion losses.
/// The host retains responsibility for captured-source, create-new saving.
Future<LegacyWordDocxCopy?> showLegacyWordConversionDialog(
  BuildContext context, {
  required String sourceName,
  required Uint8List bytes,
  Future<void> Function(LegacyWordDocxCopy)? onSave,
  String Function(Object)? describeSaveError,
}) => showDialog<LegacyWordDocxCopy>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LegacyWordConversionDialog(
    sourceName: sourceName,
    bytes: bytes,
    onSave: onSave,
    describeSaveError: describeSaveError,
  ),
);

class LegacyWordConversionDialog extends StatefulWidget {
  const LegacyWordConversionDialog({
    super.key,
    required this.sourceName,
    required this.bytes,
    this.onSave,
    this.describeSaveError,
  });

  final String sourceName;
  final Uint8List bytes;
  final Future<void> Function(LegacyWordDocxCopy)? onSave;
  final String Function(Object)? describeSaveError;

  @override
  State<LegacyWordConversionDialog> createState() =>
      _LegacyWordConversionDialogState();
}

class _LegacyWordConversionDialogState
    extends State<LegacyWordConversionDialog> {
  late final TextEditingController _name = TextEditingController(
    text: suggestedLegacyWordDocxName(widget.sourceName),
  );
  bool _converting = false;
  bool _saving = false;
  bool _saveError = false;
  Object? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    if (_converting) return;
    try {
      final name = validateLegacyWordDocxName(_name.text);
      setState(() {
        _converting = true;
        _saving = false;
        _saveError = false;
        _error = null;
      });
      final bytes = await compute(convertLegacyWordToDocx, widget.bytes);
      if (!mounted) return;
      final copy = LegacyWordDocxCopy(fileName: name, bytes: bytes);
      if (widget.onSave case final save?) {
        setState(() => _saving = true);
        await save(copy);
        if (!mounted) return;
      }
      Navigator.of(context).pop(copy);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _converting = false;
        _saveError = _saving;
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = LegacyWordConversionStrings(
      Localizations.localeOf(context),
    );
    return PopScope(
      canPop: !_converting,
      child: AlertDialog(
        title: Text(strings.title),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sourceName),
                const SizedBox(height: 12),
                Text(strings.lossNotice),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !_converting,
                  autofocus: true,
                  decoration: InputDecoration(labelText: strings.fileName),
                  onSubmitted: (_) => _convert(),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    _saveError
                        ? widget.describeSaveError?.call(error) ??
                              error.toString()
                        : strings.error(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_converting) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(_saving ? strings.saving : strings.converting),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _converting ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: _converting ? null : _convert,
            child: Text(strings.create),
          ),
        ],
      ),
    );
  }
}
