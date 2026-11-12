// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.5.1/Fib, 2.7.1/Dop and 2.7.2–2.7.13/DopBase…Copts. Only the
// referenced, completely bounded blocks are read, never an inferred version.
extension _WordCompatibilitySource on _BinarySource {
  LegacyWordCompatibility _readCompatibility(int offset, int length) {
    final dop = _Bytes(table.slice(offset, length));
    final extensionOffset = 154 + pairCount * 8;
    final cswNew = word.u16(extensionOffset);
    if (!const {0, 2, 5}.contains(cswNew)) {
      throw const FormatException('Invalid Word FIB extension size.');
    }
    word.require(extensionOffset + 2, cswNew * 2);
    final newVersion = cswNew == 0 ? null : word.u16(extensionOffset + 2);
    if (newVersion != null &&
        (!const {0xd9, 0x101, 0x10c, 0x112}.contains(newVersion) ||
            (newVersion == 0x112 ? cswNew != 5 : cswNew != 2))) {
      throw const FormatException('Invalid Word FIB extension version.');
    }
    final issues = <LegacyWordCompatibilityIssue>[];
    final partialLegacy = cswNew == 0 && (length == 84 || length == 88);
    final expectedMinimum = switch (newVersion) {
      null => 500,
      0xd9 => 544,
      0x101 => 594,
      0x10c => 616,
      _ => 674,
    };
    if (!partialLegacy && length < expectedMinimum) {
      throw const FormatException('Truncated Word compatibility settings.');
    }
    if (partialLegacy) {
      issues.add(LegacyWordCompatibilityIssue.partialLegacyDop);
    }
    final blocks = <LegacyWordCompatibilityBlock>[
      LegacyWordCompatibilityBlock(
        kind: LegacyWordCompatibilityBlockKind.copts60,
        bytes: dop.slice(8, 2),
      ),
      if (length >= 88)
        LegacyWordCompatibilityBlock(
          kind: LegacyWordCompatibilityBlockKind.copts80,
          bytes: dop.slice(84, 4),
        ),
    ];
    // LibreOffice's WW8Dop::Write emits exactly 610 bytes and repeats the
    // complete options at 84 and 508 while its FIB advertises nFib=0x101,
    // cbRgFcLcb=136, cswNew=0. The independent native fixture exhibits this.
    // This exception does not classify arbitrary trailing bytes as Copts.
    final legacyExtended =
        cswNew == 0 && version == 0x101 && pairCount == 136 && length == 610;
    final hasExtended = newVersion != null || legacyExtended;
    if (hasExtended) {
      blocks.add(
        LegacyWordCompatibilityBlock(
          kind: LegacyWordCompatibilityBlockKind.copts,
          bytes: dop.slice(508, 32),
        ),
      );
    }
    // The reserved Copts60 bit 9 has no semantic value and is ignored even
    // when comparing repeated blocks. All non-reserved duplicates are checked.
    const meaningful = 0xfffffdff;
    final repeatedAgree =
        hasExtended &&
        (dop.u32(84) & meaningful) == (dop.u32(508) & meaningful);
    if (legacyExtended) {
      issues.add(
        repeatedAgree
            ? LegacyWordCompatibilityIssue.legacyExtendedBlockRecovered
            : LegacyWordCompatibilityIssue.ambiguousExtendedBlock,
      );
    } else if (length > expectedMinimum &&
        !(newVersion == 0x112 && const {690, 694}.contains(length))) {
      issues.add(LegacyWordCompatibilityIssue.unrecognizedExtension);
    }
    final recoverShiftReturn =
        legacyExtended &&
        repeatedAgree &&
        (dop.u16(8) & 0xfdff) == 0 &&
        (dop.u16(84) & 0xfdff) == 0x2000;
    final flags = <LegacyWordCompatibilityFlag, bool>{};
    final ambiguous = <LegacyWordCompatibilityFlag>{};
    for (final flag in LegacyWordCompatibilityFlag.values) {
      if (legacyExtended && !repeatedAgree && flag.sourceWord > 0) continue;
      final candidates = <bool>[];
      for (final block in blocks) {
        final byteOffset = flag.sourceWord * 4 + flag.sourceBit ~/ 8;
        if (byteOffset >= block.bytes.length) continue;
        final raw =
            (block.bytes[byteOffset] & (1 << (flag.sourceBit % 8))) != 0;
        candidates.add(flag.inverted ? !raw : raw);
      }
      if (candidates.isEmpty) continue;
      if (candidates.any((value) => value != candidates.first)) {
        issues.add(LegacyWordCompatibilityIssue.conflictingCopies);
        if (recoverShiftReturn &&
            flag == LegacyWordCompatibilityFlag.doNotExpandShiftReturn) {
          flags[flag] = candidates.last;
        } else {
          ambiguous.add(flag);
        }
      } else {
        flags[flag] = candidates.first;
      }
    }
    return LegacyWordCompatibility(
      flags: flags,
      sourceBlocks: blocks,
      issues: issues,
      ambiguousFlags: ambiguous,
      sourceDopOffset: offset,
      sourceDopLength: length,
      sourceFibVersion: version,
      sourceFibNewVersion: newVersion,
    );
  }
}
