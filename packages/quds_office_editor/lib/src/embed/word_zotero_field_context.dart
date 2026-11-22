import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';

/// Read-only source context for a native Zotero prompt. The editor's writing
/// selection stays independent of the temporary field highlight.
class WordZoteroFieldContextView extends StatelessWidget {
  const WordZoteroFieldContextView({
    super.key,
    required this.controller,
    required this.transaction,
    this.isCurrent,
    this.compact = false,
  });

  final WordEditorController controller;
  final WordZoteroTransaction transaction;
  final bool Function()? isCurrent;
  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!(isCurrent?.call() ?? true)) return const SizedBox.shrink();
      final selection = transaction.presentedFieldContext;
      if (selection == null) return const SizedBox.shrink();
      final title = switch (selection.kind) {
        ZoteroFieldKind.citation => 'Citation selected by Zotero',
        ZoteroFieldKind.bibliography => 'Bibliography selected by Zotero',
        null => 'Reference selected by Zotero',
      };
      final source = selection.sourceField;
      final note = selection.sourceNote;
      final sourceText = selection.sourceText;
      final paragraphs = note == null
          ? controller.document.paragraphs.toList()
          : note.allParagraphs.toList();
      final paragraph = source == null
          ? -1
          : paragraphs.indexOf(source.paragraph);
      final story = note == null
          ? 'Document body'
          : note.endnote
          ? 'Endnote'
          : 'Footnote';
      final location = paragraph < 0
          ? story
          : '$story · paragraph ${paragraph + 1}';
      final ranges = selection.sourceRanges;
      final before = ranges.isEmpty
          ? ''
          : _trailing(
              ranges.first.paragraph.text.substring(0, ranges.first.start),
              120,
            );
      final after = ranges.isEmpty
          ? ''
          : _leading(
              ranges.last.paragraph.text.substring(ranges.last.end),
              120,
            );
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DecoratedBox(
          key: const ValueKey('zotero-selected-field-context'),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (selection.source ==
                    WordZoteroFieldSelectionSource.document) ...[
                  Text(
                    ranges.length > 1
                        ? '$location · ${ranges.length} paragraphs'
                        : location,
                    key: const ValueKey('zotero-selected-field-location'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (source?.isValid == false)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'The stored reference metadata is damaged. The original text below is kept until this Zotero operation finishes.',
                        key: ValueKey('zotero-selected-field-damaged'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: compact ? 112 : 220),
                    child: SingleChildScrollView(
                      child: SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: before),
                            TextSpan(
                              text: sourceText == null || sourceText.isEmpty
                                  ? '(Empty reference)'
                                  : _leading(sourceText, 1800),
                              style: TextStyle(
                                backgroundColor: colors.tertiaryContainer,
                                color: colors.onTertiaryContainer,
                              ),
                            ),
                            TextSpan(text: after),
                          ],
                        ),
                        key: const ValueKey('zotero-selected-field-text'),
                      ),
                    ),
                  ),
                  if ((sourceText?.length ?? 0) > 1800)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Excerpt of the current document reference.'),
                    ),
                ] else
                  Text(
                    selection.source ==
                            WordZoteroFieldSelectionSource.importedDocument
                        ? 'Zotero is preparing this transferred reference. Its document position will be available when the import finishes.'
                        : 'Zotero is preparing a new reference. Its document position will be available when insertion finishes.',
                    key: const ValueKey('zotero-selected-field-pending'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  // Keep UTF-16 surrogate pairs intact at bounded excerpt edges.
  static String _leading(String text, int limit) {
    if (text.length <= limit) return text;
    var end = limit;
    final unit = text.codeUnitAt(end - 1);
    if (unit >= 0xd800 && unit <= 0xdbff) end--;
    return '${text.substring(0, end)}…';
  }

  static String _trailing(String text, int limit) {
    if (text.length <= limit) return text;
    var start = text.length - limit;
    final unit = text.codeUnitAt(start);
    if (unit >= 0xdc00 && unit <= 0xdfff) start++;
    return '…${text.substring(start)}';
  }
}
