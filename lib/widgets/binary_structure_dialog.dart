import 'package:flutter/material.dart';

import '../l10n/binary_structure_strings.dart';
import '../services/binary_structure_service.dart';

/// A read-only, bounded header tree. Selecting a field returns its exact byte
/// interval to the host's existing hex view; this dialog never owns the source.
class BinaryStructureDialog extends StatelessWidget {
  const BinaryStructureDialog({
    super.key,
    required this.analysis,
    required this.filename,
  });

  final BinaryStructureAnalysis analysis;
  final String filename;

  @override
  Widget build(BuildContext context) {
    final strings = BinaryStructureStrings(context);
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.text('title')),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          children: [
            Text(filename, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              strings.format(analysis.format),
              style: theme.textTheme.titleMedium,
            ),
            Text(strings.summary(analysis.inspectedBytes, analysis.byteLength)),
            const SizedBox(height: 12),
            Text(strings.text('scope')),
            for (final issue in analysis.issues)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  strings.issue(issue),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const Divider(height: 24),
            if (analysis.fields.isEmpty) Text(strings.text('empty')),
            for (final field in analysis.fields) _field(context, field),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('close')),
        ),
      ],
    );
  }

  Widget _field(BuildContext context, BinaryStructureField field) {
    String hex(int value) =>
        '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';
    final detail =
        '${field.type} · [${hex(field.start)}, ${hex(field.end)})'
        '${field.value == null ? '' : '\n${field.value}'}';
    if (field.children.isNotEmpty) {
      return ExpansionTile(
        key: PageStorageKey('binary-structure-${field.start}-${field.name}'),
        initiallyExpanded: true,
        title: Text(field.name),
        subtitle: Text(detail, textDirection: TextDirection.ltr),
        childrenPadding: const EdgeInsetsDirectional.only(start: 12),
        children: [for (final child in field.children) _field(context, child)],
      );
    }
    return ListTile(
      key: ValueKey('binary-field-${field.start}-${field.name}'),
      title: Text(field.name),
      subtitle: Text(detail, textDirection: TextDirection.ltr),
      trailing: const Icon(Icons.chevron_right),
      onTap: field.end > field.start
          ? () => Navigator.of(context).pop(field)
          : null,
    );
  }
}
