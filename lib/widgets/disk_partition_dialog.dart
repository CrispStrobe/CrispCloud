import 'package:flutter/material.dart';

import '../l10n/disk_partition_strings.dart';
import '../services/binary_structure_service.dart';
import '../services/disk_partition_inspector.dart';

sealed class DiskPartitionDialogResult {
  const DiskPartitionDialogResult();
}

class DiskPartitionFieldSelected extends DiskPartitionDialogResult {
  const DiskPartitionFieldSelected(this.field);
  final BinaryStructureField field;
}

class DiskPartitionSectorSelected extends DiskPartitionDialogResult {
  const DiskPartitionSectorSelected(this.sectorBytes);
  final int? sectorBytes;
}

/// The host owns the source and reinspects after a sector-size choice. This
/// report owns no file handle and offers no partition or payload writes.
class DiskPartitionDialog extends StatelessWidget {
  const DiskPartitionDialog({
    super.key,
    required this.analysis,
    required this.filename,
    this.requestedSectorBytes,
  });

  final DiskPartitionAnalysis analysis;
  final String filename;
  final int? requestedSectorBytes;

  @override
  Widget build(BuildContext context) {
    final strings = DiskPartitionStrings(context);
    final theme = Theme.of(context);
    final scheme = switch (analysis.scheme) {
      DiskPartitionScheme.none => strings.text('unknown'),
      DiskPartitionScheme.mbr => 'MBR',
      DiskPartitionScheme.gpt => 'GPT',
    };
    return AlertDialog(
      scrollable: true,
      title: Text(strings.text('title')),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          children: [
            Text(
              filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(scheme, style: theme.textTheme.titleMedium),
            Text(strings.summary(analysis.inspectedBytes, analysis.totalBytes)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const ValueKey('partition-sector-size'),
              initialValue: requestedSectorBytes ?? 0,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.text('sectorSize'),
              ),
              items: [
                DropdownMenuItem(value: 0, child: Text(strings.text('auto'))),
                const DropdownMenuItem(value: 512, child: Text('512 B')),
                const DropdownMenuItem(value: 4096, child: Text('4096 B')),
              ],
              onChanged: (value) {
                if (value == null || value == (requestedSectorBytes ?? 0)) {
                  return;
                }
                Navigator.of(
                  context,
                ).pop(DiskPartitionSectorSelected(value == 0 ? null : value));
              },
            ),
            const SizedBox(height: 8),
            if (analysis.sectorBytes != null)
              Text('${strings.text('sectorSize')}: ${analysis.sectorBytes} B')
            else if (analysis.findings.any(
              (finding) =>
                  finding.code == DiskPartitionFindingCode.sectorSizeAmbiguous,
            ))
              Text(strings.text('ambiguous')),
            const SizedBox(height: 8),
            Text(strings.text('scope')),
            for (final header in analysis.headers)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _header(context, header),
              ),
            if (analysis.findings.isNotEmpty) ...[
              const Divider(height: 24),
              Text(strings.text('findings'), style: theme.textTheme.titleSmall),
              for (final finding in analysis.findings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    finding.severity == DiskPartitionFindingSeverity.information
                        ? Icons.info_outline
                        : Icons.warning_amber_outlined,
                    color:
                        finding.severity == DiskPartitionFindingSeverity.error
                        ? theme.colorScheme.error
                        : null,
                  ),
                  title: Text(finding.message),
                  onTap: finding.field == null
                      ? null
                      : () => Navigator.of(context)
                            .pop(DiskPartitionFieldSelected(finding.field!)),
                ),
            ],
            if (analysis.fields.isNotEmpty) ...[
              const Divider(height: 24),
              Text(strings.text('fields'), style: theme.textTheme.titleSmall),
              for (final field in analysis.fields)
                _PartitionFieldTile(field: field),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.common.text('close')),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, DiskGptHeaderInspection header) {
    final strings = DiskPartitionStrings(context);
    String status(DiskPartitionCheckStatus value) => strings.text(value.name);
    return Column(
      key: ValueKey('partition-header-${header.role.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.text(header.role.name),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (!header.present) Text(strings.text('missing')),
        Text('${strings.text('headerCrc')}: ${status(header.headerCrcStatus)}'),
        Text('${strings.text('tableCrc')}: ${status(header.tableCrcStatus)}'),
        if (header.diskGuid != null)
          Text(header.diskGuid!, textDirection: TextDirection.ltr),
      ],
    );
  }
}

/// Build a group's children only when expanded. A large but bounded partition
/// table therefore does not create thousands of hidden field widgets at once.
class _PartitionFieldTile extends StatefulWidget {
  const _PartitionFieldTile({required this.field});
  final BinaryStructureField field;

  @override
  State<_PartitionFieldTile> createState() => _PartitionFieldTileState();
}

class _PartitionFieldTileState extends State<_PartitionFieldTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    String hex(int value) => '0x${value.toRadixString(16).toUpperCase()}';
    final detail =
        '${field.type} · [${hex(field.start)}, ${hex(field.end)})'
        '${field.value == null ? '' : '\n${field.value}'}';
    if (field.children.isNotEmpty) {
      return ExpansionTile(
        key: ValueKey('partition-group-${field.start}-${field.name}'),
        title: Text(field.name),
        subtitle: Text(detail, textDirection: TextDirection.ltr),
        initiallyExpanded: _expanded,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        childrenPadding: const EdgeInsetsDirectional.only(start: 12),
        children: _expanded
            ? [
                for (final child in field.children)
                  _PartitionFieldTile(field: child),
              ]
            : const [],
      );
    }
    return ListTile(
      key: ValueKey('partition-field-${field.start}-${field.name}'),
      title: Text(field.name),
      subtitle: Text(detail, textDirection: TextDirection.ltr),
      trailing: const Icon(Icons.chevron_right),
      onTap: field.end > field.start
          ? () => Navigator.of(context).pop(DiskPartitionFieldSelected(field))
          : null,
    );
  }
}
