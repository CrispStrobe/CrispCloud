import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';

class KindleMetadataDraft {
  KindleMetadataDraft({required this.patch, Uint8List? cover})
    : cover = cover == null
          ? null
          : Uint8List.fromList(cover).asUnmodifiableView();

  final KindleMetadataPatch patch;
  final Uint8List? cover;
}

enum _FieldAction { keep, set, clear }

class _MetadataField {
  _MetadataField(
    this.name,
    this.label, {
    this.initial = '',
    this.multiline = false,
  });
  final String name;
  final String label;
  final String initial;
  final bool multiline;
  late final controller = TextEditingController(text: initial);
  _FieldAction action = _FieldAction.keep;
}

/// Only selected fields enter the patch. Unknown current values therefore
/// remain unchanged, including when the enhanced reader is unavailable.
class EbookKindleMetadataEditor extends StatefulWidget {
  const EbookKindleMetadataEditor({
    super.key,
    this.info,
    required this.translate,
    required this.exportLabel,
    required this.onApply,
    this.pickCover,
    this.onCancel,
    this.errorMessage,
  });

  final EbookBookInfo? info;
  final String Function(String) translate;
  final String exportLabel;
  final Future<bool> Function(KindleMetadataDraft) onApply;
  final Future<Uint8List?> Function()? pickCover;
  final VoidCallback? onCancel;
  final String Function(Object)? errorMessage;

  @override
  State<EbookKindleMetadataEditor> createState() =>
      _EbookKindleMetadataEditorState();
}

class _EbookKindleMetadataEditorState extends State<EbookKindleMetadataEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final _fields = <_MetadataField>[
    _MetadataField('title', 'Title', initial: widget.info?.title ?? ''),
    _MetadataField(
      'authors',
      'Authors (one per line)',
      initial: widget.info?.authors.join('\n') ?? '',
      multiline: true,
    ),
    _MetadataField('publisher', 'Publisher'),
    _MetadataField('description', 'Description', multiline: true),
    _MetadataField(
      'language',
      'Language',
      initial: widget.info?.language ?? '',
    ),
    _MetadataField('isbn', 'ISBN'),
    _MetadataField('asin', 'ASIN'),
    _MetadataField('publication_date', 'Publication date'),
    _MetadataField('subjects', 'Subjects (one per line)', multiline: true),
    _MetadataField('identifier', 'Identifier'),
  ];
  Uint8List? _cover;
  String? _error;
  bool _submitting = false;
  bool _picking = false;

  String _tr(String value) => widget.translate(value);
  bool get _busy => _submitting || _picking;
  bool get _hasChanges =>
      _cover != null ||
      _fields.any((field) => field.action != _FieldAction.keep);

  @override
  void dispose() {
    for (final field in _fields) {
      field.controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  KindleMetadataDraft _draft() {
    String? value(String name) {
      final field = _fields.firstWhere((field) => field.name == name);
      return switch (field.action) {
        _FieldAction.keep => null,
        _FieldAction.clear => '',
        _FieldAction.set => field.controller.text.trim(),
      };
    }

    List<String>? values(String name) =>
        value(name)
            ?.split('\n')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
    final patch = KindleMetadataPatch(
      title: value('title'),
      authors: values('authors'),
      publisher: value('publisher'),
      description: value('description'),
      language: value('language'),
      isbn: value('isbn'),
      asin: value('asin'),
      publicationDate: value('publication_date'),
      subjects: values('subjects'),
      identifier: value('identifier'),
    );
    // Leave room for the native job envelope beneath its 128 KiB JSON bound.
    if (utf8.encode(jsonEncode(patch.toJson())).length > 120 * 1024) {
      throw StateError(
        _tr(
          'The selected metadata is too large. Shorten the text and try again.',
        ),
      );
    }
    return KindleMetadataDraft(patch: patch, cover: _cover);
  }

  Future<void> _submit() async {
    if (_busy || !_hasChanges || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = await widget.onApply(_draft());
      if (!mounted) return;
      if (saved) {
        setState(() => _submitting = false);
        Navigator.of(context).pop(true);
      } else {
        _showError(_tr('Export was canceled. Your changes are still here.'));
      }
    } catch (error) {
      _showError(widget.errorMessage?.call(error) ?? '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickCover() async {
    if (_busy || widget.pickCover == null) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await widget.pickCover!();
      if (mounted && bytes != null) {
        setState(() => _cover = Uint8List.fromList(bytes).asUnmodifiableView());
      }
    } catch (error) {
      _showError(widget.errorMessage?.call(error) ?? '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _field(_MetadataField field) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _tr(field.label),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<_FieldAction>(
              key: ValueKey('kindle-metadata-mode-${field.name}'),
              value: field.action,
              items: [
                DropdownMenuItem(
                  value: _FieldAction.keep,
                  child: Text(_tr('Keep')),
                ),
                DropdownMenuItem(
                  value: _FieldAction.set,
                  child: Text(_tr('Set')),
                ),
                DropdownMenuItem(
                  value: _FieldAction.clear,
                  child: Text(_tr('Clear')),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (action) => setState(() {
                      field.action = action!;
                      _error = null;
                    }),
            ),
          ],
        ),
        if (field.action == _FieldAction.set)
          TextFormField(
            key: ValueKey('kindle-metadata-value-${field.name}'),
            controller: field.controller,
            enabled: !_busy,
            minLines: field.multiline ? 2 : 1,
            maxLines: field.multiline ? 5 : 1,
            maxLength: field.name == 'description' ? 65536 : 4096,
            decoration: InputDecoration(
              labelText: _tr(field.label),
              counterText: '',
            ),
            validator: (text) => text == null || text.trim().isEmpty
                ? _tr('Enter a value, or choose Clear to remove it.')
                : null,
          )
        else if (field.action == _FieldAction.clear)
          Text(_tr('This field will be removed where the format allows.'))
        else if (field.initial.isNotEmpty)
          Text(field.initial, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(_tr('Edit Kindle metadata')),
      content: SizedBox(
        width: 620,
        height: (MediaQuery.sizeOf(context).height * .62).clamp(160, 640),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Text(
                  _tr(
                    'Keep preserves the existing value, including values not shown here.',
                  ),
                ),
                const SizedBox(height: 16),
                for (final field in _fields) _field(field),
                if (widget.pickCover != null) ...[
                  Text(
                    _tr('Cover'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _pickCover,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(_tr('Replace cover')),
                      ),
                      if (_cover != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _cover = null),
                          child: Text(_tr('Remove replacement')),
                        ),
                    ],
                  ),
                  if (_cover != null)
                    Image.memory(
                      _cover!,
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Text(_tr('Replacement cover selected')),
                    ),
                ],
                const SizedBox(height: 12),
                Text(
                  _tr(
                    'Exports a new file with updated metadata and the existing Kindle content.',
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _picking
              ? null
              : _submitting
              ? widget.onCancel
              : () => Navigator.of(context).pop(false),
          child: Text(_tr(_submitting ? 'Cancel operation' : 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('kindle-metadata-export'),
          onPressed: _busy || !_hasChanges ? null : _submit,
          child: Text(_tr(widget.exportLabel)),
        ),
      ],
    ),
  );
}
