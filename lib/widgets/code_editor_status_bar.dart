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
  });

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
                  message:
                      'Mixed line endings were normalized to '
                      '${lineEnding.label}. Saving writes the whole file with '
                      'that style.',
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              _StatusMenuButton<EditorLineEnding>(
                tooltip: 'Line endings',
                values: EditorLineEnding.values,
                label: (value) =>
                    value == lineEnding ? '✓ ${value.label}' : value.label,
                onSelected: onLineEndingSelected,
                text: lineEnding.label,
              ),
              const SizedBox(width: 6),
              _StatusMenuButton<EditorEncoding>(
                tooltip: 'File encoding',
                values: EditorEncoding.values,
                label: (value) =>
                    value == encoding ? '✓ ${value.label}' : value.label,
                onSelected: onEncodingSelected,
                text: encoding.label,
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

class _StatusMenuButton<T> extends StatelessWidget {
  const _StatusMenuButton({
    required this.tooltip,
    required this.values,
    required this.label,
    required this.onSelected,
    required this.text,
  });

  final String tooltip;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final value in values)
          PopupMenuItem<T>(value: value, child: Text(label(value))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
