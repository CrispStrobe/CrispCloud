// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.6.3 TWall/TPropRMark. Capture scalar prior properties immediately;
// retaining the mutable evaluation map would let later operations overwrite
// history. A complete current grid can be reused only when no broader table
// operation occurs after the wall.
class _TableRowRevisionSnapshot {
  _TableRowRevisionSnapshot(_Props properties)
    : previous = LegacyWordTableRowProperties(
        heightTwips: properties['tableRowHeight'] as int?,
        cantSplit:
            properties['tableCantSplit'] as bool? ??
            properties['tableCantSplit90'] as bool?,
        isHeader: properties['rowHeader'] == true,
      ),
      complete =
          (properties['tableDefinition'] as _TableDefinition?)
                  ?.flags
                  .isNotEmpty ==
              true &&
          properties['tableRevisionUnknownProperties'] != true;

  final LegacyWordTableRowProperties previous;
  final bool complete;
}

void _trackTableRevisionOperation(_Sprm operation, _Props output) {
  if (operation.group != 5 ||
      output['tableRevisionSnapshot'] == null ||
      const {
        0x9407,
        0x3403,
        0x3466,
        0x3404,
        0x3668,
        0xd667,
      }.contains(operation.code)) {
    return;
  }
  output['tableRevisionUnsupportedOperations'] = Set<int>.unmodifiable({
    ...?output['tableRevisionUnsupportedOperations'] as Set<int>?,
    operation.code,
  });
}

extension _WordTableRevisions on _StructuredWordParser {
  bool _tableHeaderHistoryHasConditionalFormatting(
    List<LegacyWordTableRow> rows,
  ) {
    if (!rows.any((row) {
      final previous = row.formattingRevision?.previousProperties;
      return previous != null &&
          previous.isHeader != (row.sourceHeaderRequest ?? row.isHeader);
    })) {
      return false;
    }
    final styles = {
      for (final row in rows)
        if (row.tableStyleId case final id?) id,
    };
    return styles.any(
      (id) => _tableStyleChain(id).any(
        (style) =>
            style.conditions.isNotEmpty || style.textConditions.isNotEmpty,
      ),
    );
  }

  LegacyWordTableRowFormattingRevision? _guardConditionalTableRowHistory(
    LegacyWordTableRow row, {
    required bool conditionalFormatting,
  }) {
    final change = row.formattingRevision;
    final previous = change?.previousProperties;
    if (!conditionalFormatting ||
        change == null ||
        previous == null ||
        previous.isHeader == (row.sourceHeaderRequest ?? row.isHeader)) {
      return change;
    }
    // A header edit can alter conditional formatting on this row and later
    // rows. Consider the whole table and inherited rules, including dormant
    // header requests that another independent rejection can reactivate.
    // Keeping the current flattened cell/run properties is not a complete
    // rejected state. Preserve the source history without inventing edits to
    // those children or claiming a native, independently rejectable change.
    warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    return LegacyWordTableRowFormattingRevision(
      previousProperties: previous,
      revision: change.revision,
      marked: change.marked,
      previousPropertiesComplete: change.previousPropertiesComplete,
      conditionalFormattingMayChange: true,
      unsupportedPropertyCodes: change.unsupportedPropertyCodes,
    );
  }

  void _unplacedTableRowRevision(_Props properties) {
    if (properties['tableRevisionSnapshot'] != null ||
        properties['tableRevisionMarked'] == true) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
  }

  LegacyWordTableRowFormattingRevision? _tableRowRevision(_Props properties) {
    final snapshot =
        properties['tableRevisionSnapshot'] as _TableRowRevisionSnapshot?;
    final marked = properties['tableRevisionMarked'] == true;
    if (snapshot == null && !marked) return null;
    final codes = [
      ...?properties['tableRevisionUnsupportedOperations'] as Set<int>?,
    ]..sort();
    final complete = snapshot?.complete == true;
    if (!marked || !complete || codes.isNotEmpty) {
      warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
    }
    return LegacyWordTableRowFormattingRevision(
      previousProperties: snapshot?.previous,
      revision: marked
          ? _revisionInfo(properties, 'tableRevision')
          : const LegacyWordRevisionInfo(),
      marked: marked,
      previousPropertiesComplete: complete,
      unsupportedPropertyCodes: codes,
    );
  }
}
