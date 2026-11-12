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
