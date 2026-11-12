// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTableRevisionWriter on _StructuredWordWriter {
  bool _tableHeaderHistoryHasConditionalFormatting(LegacyWordTable table) {
    if (!table.rows.any((row) {
      final previous = row.formattingRevision?.previousProperties;
      return previous != null &&
          previous.isHeader != (row.sourceHeaderRequest ?? row.isHeader);
    })) {
      return false;
    }
    final styles = {
      for (final row in table.rows)
        if (row.tableStyleId case final id?) id,
    };
    for (final initial in styles) {
      int? id = initial;
      final seen = <int>{};
      while (id != null) {
        final style = _tableStyleDefinitions[id];
        if (style == null || !seen.add(id) || seen.length > 64) {
          throw const FormatException('Missing or cyclic Word table style.');
        }
        if (style.conditions.isNotEmpty || style.textConditions.isNotEmpty) {
          return true;
        }
        id = style.basedOn;
      }
    }
    return false;
  }

  void _tableRowProperties(
    LegacyWordTableRowProperties properties, {
    required int before,
    required int after,
    required int widthBefore,
    required int widthAfter,
  }) {
    if (before != 0) {
      _xml.add(
        '<w:gridBefore w:val="$before"/>'
        '<w:wBefore w:w="$widthBefore" w:type="dxa"/>',
      );
    }
    if (after != 0) {
      _xml.add(
        '<w:gridAfter w:val="$after"/>'
        '<w:wAfter w:w="$widthAfter" w:type="dxa"/>',
      );
    }
    if (properties.heightTwips case final height?) {
      if (height < -31680 || height > 31680) {
        throw const FormatException('Invalid Word table row height.');
      }
      final rule = height == 0
          ? 'auto'
          : height < 0
          ? 'exact'
          : 'atLeast';
      _xml.add('<w:trHeight w:val="${height.abs()}" w:hRule="$rule"/>');
    }
    if (properties.cantSplit case final value?) {
      _xml.add('<w:cantSplit w:val="${value ? 'on' : 'off'}"/>');
    }
    if (properties.isHeader) _xml.add('<w:tblHeader/>');
  }

  void _tableRowFormattingRevision(
    LegacyWordTableRow row, {
    required int tableStartCp,
    required int rowIndex,
    required bool gridKnown,
    required bool tableHasConditionalFormatting,
    required int before,
    required int after,
    required int widthBefore,
    required int widthAfter,
  }) {
    final change = row.formattingRevision;
    if (change == null) return;
    final previous = change.previousProperties;
    // Recheck public-model input too; it need not originate in our parser.
    final conditionalFormattingMayChange =
        change.conditionalFormattingMayChange ||
        (tableHasConditionalFormatting &&
            previous != null &&
            previous.isHeader != (row.sourceHeaderRequest ?? row.isHeader));
    if (!change.marked ||
        previous == null ||
        !change.previousPropertiesComplete ||
        conditionalFormattingMayChange ||
        change.unsupportedPropertyCodes.isNotEmpty ||
        !gridKnown) {
      limitations.add(LegacyWordConversionLimitation.revisions);
      if (_evidenceRecords.length >= 20000) _tooComplex();
      _evidenceRecords.add({
        'kind': 'tableRowFormattingRevision',
        'tableStartCp': tableStartCp,
        'rowIndex': rowIndex,
        'marked': change.marked,
        'previousPropertiesComplete': change.previousPropertiesComplete,
        'conditionalFormattingMayChange': conditionalFormattingMayChange,
        'currentHeaderRequest': row.sourceHeaderRequest ?? row.isHeader,
        'gridKnown': gridKnown,
        'unsupportedPropertyCodes': change.unsupportedPropertyCodes,
        'author': change.revision.author,
        'authorIndex': change.revision.authorIndex,
        'rawDate': change.revision.rawDate,
        'previousProperties': previous == null
            ? null
            : {
                'heightTwips': previous.heightTwips,
                'cantSplit': previous.cantSplit,
                'headerRequest': previous.isHeader,
              },
        'reason': conditionalFormattingMayChange
            ? 'header revision can change conditional cell/text formatting '
                  'and downstream header-prefix/banding; current flattened '
                  'child properties do not reconstruct the rejected state'
            : 'complete native row history unavailable; table/cell topology '
                  'and broader table changes are not inferred',
      });
      return;
    }
    _revisionElementStart('trPrChange', change.revision);
    _xml.add('<w:trPr>');
    _tableRowProperties(
      previous,
      before: before,
      after: after,
      widthBefore: widthBefore,
      widthAfter: widthAfter,
    );
    _xml.add('</w:trPr></w:trPrChange>');
    _count('tableRowFormattingRevisions');
  }
}
