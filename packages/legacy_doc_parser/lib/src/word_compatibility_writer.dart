// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordCompatibilityWriter on _StructuredWordWriter {
  void _writeCompatibility(_BoundedWordXml settings) {
    final compatibility = document.compatibility;
    if (compatibility.flags.isNotEmpty) {
      settings.add('<w:compat>');
      for (final flag in LegacyWordCompatibilityFlag.values) {
        final value = compatibility[flag];
        if (value == null) continue;
        // ISO/IEC 29500-1 doNotExpandShiftReturn defaults to false when
        // omitted. LibreOffice's pinned SettingsTable importer enables it
        // merely on presence, even with val=0. Preserve the default meaning
        // through omission only for this verified option; the source model
        // and compatibility evidence still retain the explicit false value.
        if (flag == LegacyWordCompatibilityFlag.doNotExpandShiftReturn &&
            !value) {
          continue;
        }
        settings.add('<w:${flag.name} w:val="${value ? 1 : 0}"/>');
        _count('compatibilityFlags');
      }
      settings.add('</w:compat>');
    }
    for (final block in compatibility.sourceBlocks) {
      _preserveEvidence('compatibilityOptions', block.bytes, {
        'sourceStructure': block.kind.name,
        'offsetInDop': block.offsetInDop,
        'tableDopOffset': compatibility.sourceDopOffset,
        'dopByteLength': compatibility.sourceDopLength,
        'fibVersion': compatibility.sourceFibVersion,
        'fibNewVersion': compatibility.sourceFibNewVersion,
        'issues': [for (final issue in compatibility.issues) issue.name],
        'ambiguousFlags': [
          for (final flag in compatibility.ambiguousFlags) flag.name,
        ],
        'interpretation':
            'Explicit layout options only; no compatibilityMode or pagination guarantee.',
      });
    }
  }
}
