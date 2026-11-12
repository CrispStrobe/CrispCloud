import 'package:flutter/material.dart';

import '../services/ebook_annotations.dart';

/// A preview belongs to the exact local state used to calculate it. The service
/// checks that binding again at commit time, after this dialog returns.
class EbookReadingDataDialog extends StatefulWidget {
  const EbookReadingDataDialog({
    super.key,
    required this.annotations,
    required this.encoded,
    required this.translate,
  });
  final EbookAnnotations annotations;
  final String encoded;
  final String Function(String) translate;

  @override
  State<EbookReadingDataDialog> createState() => _EbookReadingDataDialogState();
}

class _EbookReadingDataDialogState extends State<EbookReadingDataDialog> {
  EbookReadingDataMergeMode _mode = EbookReadingDataMergeMode.mergeKeepExisting;
  EbookReadingDataImportPlan? _plan;
  String? _error;
  String _tr(String text) => widget.translate(text);

  @override
  void initState() {
    super.initState();
    _preview();
  }

  void _preview() {
    try {
      _plan = widget.annotations.previewReadingDataImport(
        widget.encoded,
        mode: _mode,
      );
      _error = null;
    } catch (error) {
      _plan = null;
      _error = error.toString();
    }
  }

  String _label(EbookReadingDataMergeMode mode) => _tr(switch (mode) {
    EbookReadingDataMergeMode.mergeKeepExisting => 'Merge, keep local conflicts',
    EbookReadingDataMergeMode.mergePreferImported => 'Merge, use imported conflicts',
    EbookReadingDataMergeMode.replace => 'Replace local reading data',
  });

  Widget _count(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(_tr(label))), Text('$value')]),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Import reading data')),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tr('Reading data contains positions, bookmarks, highlights and appearance settings for this exact book.')),
            const SizedBox(height: 16),
            DropdownButtonFormField<EbookReadingDataMergeMode>(
              key: const ValueKey('ebook-reading-data-merge-mode'),
              initialValue: _mode,
              isExpanded: true,
              decoration: InputDecoration(labelText: _tr('Import behavior')),
              items: [for (final mode in EbookReadingDataMergeMode.values)
                DropdownMenuItem(value: mode, child: Text(_label(mode)))],
              onChanged: (mode) {
                if (mode != null) setState(() { _mode = mode; _preview(); });
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              SelectableText(_tr(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_plan case final plan?) ...[
              _count('New bookmarks', plan.addedBookmarks),
              _count('New highlights', plan.addedHighlights),
              _count('Conflicting bookmarks', plan.bookmarkConflicts),
              _count('Conflicting highlights', plan.highlightConflicts),
              const Divider(),
              _count('Resulting bookmarks', plan.result.bookmarks.length),
              _count('Resulting highlights', plan.result.highlights.length),
              Text(_tr(plan.progressChanged ? 'Reading position will change.' : 'Reading position will stay the same.')),
              Text(_tr(plan.appearanceChanged ? 'Appearance settings will change.' : 'Appearance settings will stay the same.')),
              if (_mode == EbookReadingDataMergeMode.replace)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_tr('Local bookmarks and highlights absent from the imported file will be removed.')),
                ),
              if (!plan.hasChanges)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_tr('This import makes no changes.'))),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(_tr('Cancel'))),
      FilledButton(
        key: const ValueKey('ebook-apply-reading-data'),
        onPressed: _plan?.hasChanges == true ? () => Navigator.pop(context, _plan) : null,
        child: Text(_tr('Apply import')),
      ),
    ],
  );
}
