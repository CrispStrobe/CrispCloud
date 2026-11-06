// lib/widgets/code_editor_status_bar.dart
//
// Status bar for the Re-Editor based code editor.
//
// The bar is deliberately responsive: on phones the line count and language
// are dropped first so cursor, encoding and line-ending controls still fit.

import 'package:flutter/material.dart';

import '../services/editor_document.dart';

class CodeEditorStatusBar extends StatelessWidget {
  const CodeEditorStatusBar({
    super.key,
    required this.cursorLine,
    required this.cursorColumn,
    required this.lineCount,
    required this.language,
    required this.lineEnding,
    required this.encoding,
    required this.isModified,
    required this.isSaving,
    required this.hadMixedLineEndings,
    required this.onLineEndingSelected,
    required this.onEncodingSelected,
    this.lineEndingPolicy = EditorLineEndingPolicy.preserve,
    this.onPolicySelected,
    this.onNewLineEndingSelected,
    this.writesBom = false,
    this.onToggleBom,
  });

  final EditorLineEndingPolicy lineEndingPolicy;
  final ValueChanged<EditorLineEndingPolicy>? onPolicySelected;
  final ValueChanged<EditorLineEnding>? onNewLineEndingSelected;
  final bool writesBom;
  final VoidCallback? onToggleBom;
  final int cursorLine;
  final int cursorColumn;
  final int lineCount;
  final String? language;
  final EditorLineEnding lineEnding;
  final EditorEncoding encoding;
  final bool isModified;
  final bool isSaving;
  final bool hadMixedLineEndings;
  final ValueChanged<EditorLineEnding> onLineEndingSelected;
  final ValueChanged<EditorEncoding> onEncodingSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = isSaving
        ? 'Saving…'
        : isModified
        ? 'Unsaved changes'
        : 'Saved';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Phones: keep the position and the two document-format controls.
        // Desktop: also show the document size and language.
        final showDocumentInfo = constraints.maxWidth >= 520;
        final showStatusText = constraints.maxWidth >= 420;

        return Container(
          height: 30,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // The left side may lose text to an ellipsis, but never makes
              // the fixed controls on the right overflow.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Ln $cursorLine, Col $cursorColumn',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (showDocumentInfo) ...[
                      const SizedBox(width: 12),
                      Text(
                        '$lineCount lines',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          language ?? 'Plain text',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hadMixedLineEndings)
                Tooltip(
                  message: lineEndingPolicy == EditorLineEndingPolicy.preserve
                      ? 'Mixed line endings are preserved individually. New breaks use ${lineEnding.label}.'
                      : 'Saving will explicitly convert every line ending to ${lineEnding.label}.',
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Line endings',
                onSelected: (value) {
                  if (value == 'preserve') { onPolicySelected?.call(EditorLineEndingPolicy.preserve); }
                  else if (value.startsWith('new:')) {
                    onNewLineEndingSelected?.call(EditorLineEnding.values.byName(value.substring(4)));
                  } else { onLineEndingSelected(EditorLineEnding.values.byName(value)); }
                },
                itemBuilder: (context) => [
                  if (onPolicySelected != null) PopupMenuItem(value: 'preserve',
                    child: Text('${lineEndingPolicy == EditorLineEndingPolicy.preserve ? '✓ ' : ''}Preserve existing line endings')),
                  for (final style in EditorLineEnding.values) PopupMenuItem(value: style.name,
                    child: Text('Convert ALL line endings to ${style.label}')),
                  if (onNewLineEndingSelected != null) ...[
                    const PopupMenuDivider(),
                    for (final style in EditorLineEnding.values) PopupMenuItem(value: 'new:${style.name}',
                      child: Text('${lineEnding == style ? '✓ ' : ''}New breaks: ${style.label}')),
                  ],
                ],
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(lineEnding.label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'File encoding',
                onSelected: (value) {
                  if (value == 'bom') { onToggleBom?.call(); }
                  else { onEncodingSelected(EditorEncoding.values.byName(value)); }
                },
                itemBuilder: (context) => [
                  for (final value in EditorEncoding.values) PopupMenuItem(value: value.name,
                    child: Text('${value == encoding ? '✓ ' : ''}${value.label}')),
                  if (onToggleBom != null) ...[const PopupMenuDivider(),
                    PopupMenuItem(value: 'bom', child: Text(writesBom ? 'Remove byte-order mark (BOM)' : 'Write byte-order mark (BOM)'))],
                ],
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(encoding.label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))),
              ),
              if (showStatusText) ...[
                const SizedBox(width: 12),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: isModified
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: status,
                  child: Icon(
                    isSaving
                        ? Icons.sync
                        : isModified
                        ? Icons.edit
                        : Icons.check,
                    size: 14,
                    color: isModified
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
