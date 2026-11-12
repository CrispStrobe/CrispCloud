// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

// Independent MS-DOC bit-position oracles. These tables intentionally do not
// inspect the production enum's sourceWord/sourceBit/inverted metadata.
const _copts60 = <int, String>{
  0: 'noTabHangInd',
  1: 'noSpaceRaiseLower',
  2: 'suppressSpBfAfterPgBrk',
  3: 'wrapTrailSpaces',
  5: 'noColumnBalance',
  7: 'suppressTopSpacing',
  8: 'useSingleBorderforContiguousCells',
  10: 'showBreaksInFrames',
  11: 'swapBordersFacingPages',
  12: 'doNotLeaveBackslashAlone',
  13: 'doNotExpandShiftReturn',
  14: 'ulTrailSpace',
  15: 'balanceSingleByteDoubleByteWidth',
};
const _copts80 = <int, String>{
  16: 'suppressSpacingAtTopOfPage',
  17: 'spacingInWholePoints',
  18: 'printBodyTextBeforeHeader',
  19: 'noLeading',
  20: 'spaceForUL',
  21: 'mwSmallCaps',
  22: 'suppressTopSpacingWP',
  23: 'truncateFontHeightsLikeWP6',
  24: 'subFontBySize',
  25: 'lineWrapLikeWord6',
  26: 'doNotSuppressParagraphBorders',
  27: 'noExtraLineSpacing',
  28: 'suppressBottomSpacing',
  29: 'wpSpaceWidth',
  30: 'wpJustification',
  31: 'usePrinterMetrics',
};
const _copts = <int, String>{
  0: 'shapeLayoutLikeWW8',
  1: 'footnoteLayoutLikeWW8',
  2: 'doNotUseHTMLParagraphAutoSpacing',
  3: 'adjustLineHeightInTable',
  4: 'forgetLastTabAlignment',
  5: 'autoSpaceLikeWord95',
  6: 'alignTablesRowByRow',
  7: 'layoutRawTableWidth',
  8: 'layoutTableRowsApart',
  9: 'useWord97LineBreakRules',
  10: 'doNotBreakWrappedTables',
  11: 'doNotSnapToGridInCell',
  13: 'applyBreakingRules',
  14: 'doNotWrapTextWithPunct',
  15: 'doNotUseEastAsianBreakRules',
  16: 'useWord2002TableStyleRules',
  17: 'growAutofit',
  18: 'useNormalStyleForList',
  19: 'doNotUseIndentAsNumberingTabStop',
  20: 'useAltKinsokuLineBreakRules',
  21: 'allowSpaceOfSameStyleInTable',
  22: 'doNotSuppressIndentation',
  23: 'doNotAutofitConstrainedTables',
  24: 'autofitToFirstFixedWidthCell',
  25: 'underlineTabInNumList',
  26: 'displayHangulFixedWidth',
  27: 'splitPgBreakAndParaMark',
  28: 'doNotVertAlignCellWithSp',
  29: 'doNotBreakConstrainedForcedTable',
  30: 'doNotVertAlignInTxbx',
  31: 'useAnsiKerningPairs',
};
const _inverted = {
  'doNotLeaveBackslashAlone',
  'doNotExpandShiftReturn',
  'ulTrailSpace',
  'balanceSingleByteDoubleByteWidth',
  'spaceForUL',
  'adjustLineHeightInTable',
};

Uint8List _dop(
  int length, {
  int options = 0,
  int extended = 0,
  int cached = 0,
  int? baseCopy,
  int? extendedCopy,
}) {
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  if (length >= 10) data.setUint16(8, baseCopy ?? options, Endian.little);
  if (length >= 88) data.setUint32(84, options, Endian.little);
  if (length >= 540) {
    data.setUint32(508, extendedCopy ?? options, Endian.little);
    data.setUint32(512, extended, Endian.little);
    data.setUint32(516, cached, Endian.little);
  }
  return bytes;
}

Uint8List _source({
  Uint8List? dop,
  int baseVersion = 0xc1,
  int? newVersion,
  int? pairCount,
  bool empty = false,
  void Function(ByteData fib)? mutate,
}) =>
    StructuredWordFixture(
      pieces: const [WordFixturePiece('Text\r')],
      mainCharacterCount: empty ? 0 : null,
      extraTablePairs: {if (dop != null) 31: dop},
    ).build(
      mutate: (fib, _) {
        final count =
            pairCount ??
            switch (newVersion) {
              0xd9 => 108,
              0x101 => 136,
              0x10c => 164,
              0x112 => 183,
              _ => 93,
            };
        fib.setUint16(2, baseVersion, Endian.little);
        fib.setUint16(152, count, Endian.little);
        final at = 154 + count * 8;
        fib.setUint16(
          at,
          newVersion == null ? 0 : (newVersion == 0x112 ? 5 : 2),
          Endian.little,
        );
        if (newVersion != null) {
          fib.setUint16(at + 2, newVersion, Endian.little);
        }
        mutate?.call(fib);
      },
    );

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};
Map<String, bool> _settings(Map<String, Uint8List> files) {
  final xml = XmlDocument.parse(utf8.decode(files['word/settings.xml']!));
  expect(xml.findAllElements('compatSetting', namespace: _w), isEmpty);
  final compat = xml.findAllElements('compat', namespace: _w).toList();
  if (compat.isEmpty) return {};
  expect(compat, hasLength(1));
  return {
    for (final element in compat.single.childElements)
      element.name.local: element.getAttribute('val', namespace: _w) == '1',
  };
}

Map<String, bool> _resolved(LegacyWordDocument document) => {
  for (final flag in document.compatibility.flags.entries)
    flag.key.name: flag.value,
};
Map<String, bool> _baseline(Iterable<String> names) => {
  for (final name in names) name: _inverted.contains(name),
};
List<Map<String, dynamic>> _evidence(Map<String, Uint8List> files) =>
    (jsonDecode(utf8.decode(files['word/evidence/manifest.json']!))['records']
            as List)
        .cast<Map<String, dynamic>>()
        .where((record) => record['kind'] == 'compatibilityOptions')
        .toList();

void main() {
  test('absent settings differ from explicitly disabled source options', () {
    final absent = parseLegacyWordDocument(_source());
    expect(absent.compatibility.flags, isEmpty);
    expect(absent.compatibility.sourceBlocks, isEmpty);
    expect(_settings(_parts(convertLegacyWordDocument(absent).bytes)), isEmpty);

    final present = parseLegacyWordDocument(_source(dop: _dop(500)));
    expect(
      _resolved(present),
      _baseline([..._copts60.values, ..._copts80.values]),
    );
    expect(
      present.compatibility[LegacyWordCompatibilityFlag.wrapTrailSpaces],
      isFalse,
    );
    expect(
      present.compatibility[LegacyWordCompatibilityFlag.shapeLayoutLikeWW8],
      isNull,
    );
    final files = _parts(convertLegacyWordDocument(present).bytes);
    expect(_settings(files), _resolved(present));
    expect(utf8.decode(files['word/settings.xml']!), contains('w:val="0"'));
  });

  test('Copts60 fixture bit positions and opposite meanings are exact', () {
    for (final entry in _copts60.entries) {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(84, options: 1 << entry.key)),
      );
      final expected = _baseline(_copts60.values);
      expected[entry.value] = !_inverted.contains(entry.value);
      expect(_resolved(parsed), expected, reason: 'Copts60 bit ${entry.key}');
      expect(
        _settings(_parts(convertLegacyWordDocument(parsed).bytes)),
        expected,
        reason: 'Copts60 native XML bit ${entry.key}',
      );
      expect(parsed.compatibility.issues, [
        LegacyWordCompatibilityIssue.partialLegacyDop,
      ]);
    }
  });

  test('Copts80 font and line metrics use documented upper-word positions', () {
    for (final entry in _copts80.entries) {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(500, options: 1 << entry.key)),
      );
      final expected = _baseline([..._copts60.values, ..._copts80.values]);
      expected[entry.value] = !_inverted.contains(entry.value);
      expect(_resolved(parsed), expected, reason: 'Copts80 bit ${entry.key}');
      expect(
        _settings(_parts(convertLegacyWordDocument(parsed).bytes)),
        expected,
      );
      expect(parsed.compatibility.issues, isEmpty);
    }
  });

  test('Copts maps wrapping, table spacing, and later line-layout choices', () {
    for (final entry in _copts.entries) {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(544, extended: 1 << entry.key), newVersion: 0xd9),
      );
      final expected = _baseline([
        ..._copts60.values,
        ..._copts80.values,
        ..._copts.values,
        'cachedColBalance',
      ]);
      expected[entry.value] = !_inverted.contains(entry.value);
      expect(
        _resolved(parsed),
        expected,
        reason: 'Copts extended bit ${entry.key}',
      );
      expect(
        _settings(_parts(convertLegacyWordDocument(parsed).bytes)),
        expected,
      );
      expect(parsed.compatibility.issues, isEmpty);
    }
  });

  test('later DOP versions retain the same bounded common prefix', () {
    for (final (version, length) in [
      (0x101, 594),
      (0x10c, 616),
      (0x112, 674),
      (0x112, 690),
      (0x112, 694),
    ]) {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(length, cached: 1), newVersion: version),
      );
      expect(parsed.compatibility.flags, hasLength(61));
      expect(
        parsed.compatibility[LegacyWordCompatibilityFlag.cachedColBalance],
        isTrue,
      );
      expect(parsed.compatibility.sourceFibNewVersion, version);
      expect(parsed.compatibility.issues, isEmpty);
    }
  });

  test('non-layout and reserved bits never become native settings', () {
    final dop = _dop(544, options: 0x250, extended: 0x1000, cached: 0xfffffffe);
    final data = ByteData.sublistView(dop);
    // Reserved bit9 may differ between copies; the rest of the unused tail
    // may be nonzero and must not create arbitrary settings element names.
    data.setUint16(8, 0x50, Endian.little);
    data.setUint32(508, 0x50, Endian.little);
    dop.fillRange(520, 540, 0xff);
    final parsed = parseLegacyWordDocument(_source(dop: dop, newVersion: 0xd9));
    final native = _settings(_parts(convertLegacyWordDocument(parsed).bytes));
    expect(
      native,
      _baseline([
        ..._copts60.values,
        ..._copts80.values,
        ..._copts.values,
        'cachedColBalance',
      ]),
    );
    expect(parsed.compatibility.issues, isEmpty);
    expect(native.keys, isNot(contains('convMailMergeEsc')));
    expect(native.keys, isNot(contains('selectFldWithFirstOrLastChar')));
    expect(native.keys, isNot(contains('printColBlack')));
  });

  test(
    'conflicting copies suppress only disputed flags and retain raw evidence',
    () {
      final dop = _dop(544, options: 0x80008, baseCopy: 9, extendedCopy: 8);
      final parsed = parseLegacyWordDocument(
        _source(dop: dop, newVersion: 0xd9),
      );
      expect(parsed.plainText, 'Text');
      expect(parsed.compatibility.ambiguousFlags, {
        LegacyWordCompatibilityFlag.noTabHangInd,
        LegacyWordCompatibilityFlag.noLeading,
      });
      expect(
        parsed.compatibility[LegacyWordCompatibilityFlag.noTabHangInd],
        isNull,
      );
      expect(
        parsed.compatibility[LegacyWordCompatibilityFlag.noLeading],
        isNull,
      );
      expect(
        parsed.compatibility[LegacyWordCompatibilityFlag.wrapTrailSpaces],
        isTrue,
      );
      expect(parsed.compatibility.issues, [
        LegacyWordCompatibilityIssue.conflictingCopies,
      ]);
      expect(
        parsed.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
      final files = _parts(convertLegacyWordDocument(parsed).bytes);
      expect(_settings(files), _resolved(parsed));
      final records = _evidence(files);
      expect(records, hasLength(3));
      for (final record in records) {
        final at = record['offsetInDop'] as int;
        final payload = files[record['part']]!;
        expect(payload, dop.sublist(at, at + payload.length));
        expect(record['issues'], ['conflictingCopies']);
        expect(
          record['ambiguousFlags'],
          containsAll(['noTabHangInd', 'noLeading']),
        );
      }
    },
  );

  test('native LibreOffice fixture uses corroborated 610-byte recovery', () {
    final parsed = parseLegacyWordDocument(
      File('test/fixtures/word_native/formatting.doc').readAsBytesSync(),
    );
    expect(parsed.compatibility.sourceFibVersion, 0x101);
    expect(parsed.compatibility.sourceFibNewVersion, isNull);
    expect(parsed.compatibility.sourceDopLength, 610);
    expect(parsed.compatibility.flags, hasLength(61));
    expect(
      parsed.compatibility.issues,
      containsAll([
        LegacyWordCompatibilityIssue.legacyExtendedBlockRecovered,
        LegacyWordCompatibilityIssue.conflictingCopies,
      ]),
    );
    expect(parsed.compatibility.ambiguousFlags, isEmpty);
    expect(
      parsed.compatibility[LegacyWordCompatibilityFlag.doNotExpandShiftReturn],
      isFalse,
    );
    expect(
      parsed.compatibility[LegacyWordCompatibilityFlag.adjustLineHeightInTable],
      isFalse,
    );
    expect(
      parsed.compatibility[LegacyWordCompatibilityFlag
          .doNotVertAlignCellWithSp],
      isTrue,
    );
    expect(
      _settings(_parts(convertLegacyWordDocument(parsed).bytes)),
      _resolved(parsed),
    );
  });

  test(
    'unadvertised bytes and inconsistent recovery copies are not guessed',
    () {
      final trailing = parseLegacyWordDocument(
        _source(dop: _dop(610, extended: 0xffffffff)),
      );
      expect(trailing.compatibility.flags, hasLength(29));
      expect(trailing.compatibility.issues, [
        LegacyWordCompatibilityIssue.unrecognizedExtension,
      ]);
      expect(
        trailing.compatibility[LegacyWordCompatibilityFlag.shapeLayoutLikeWW8],
        isNull,
      );

      final conflict = parseLegacyWordDocument(
        _source(
          dop: _dop(
            610,
            options: 0x2000,
            baseCopy: 0,
            extendedCopy: 0,
            extended: 0xffffffff,
          ),
          baseVersion: 0x101,
          pairCount: 136,
        ),
      );
      expect(
        conflict.compatibility.issues,
        contains(LegacyWordCompatibilityIssue.ambiguousExtendedBlock),
      );
      expect(
        conflict.compatibility[LegacyWordCompatibilityFlag
            .doNotExpandShiftReturn],
        isNull,
      );
      expect(
        conflict.compatibility[LegacyWordCompatibilityFlag.shapeLayoutLikeWW8],
        isNull,
      );
      expect(conflict.compatibility.sourceBlocks, hasLength(3));
    },
  );

  test(
    'known complete prefixes are accepted but truncated blocks are rejected',
    () {
      expect(
        parseLegacyWordDocument(_source(dop: _dop(88))).compatibility.flags,
        hasLength(29),
      );
      for (final length in [83, 85, 86, 87, 89, 499]) {
        expect(
          () => parseLegacyWordDocument(_source(dop: _dop(length))),
          throwsFormatException,
          reason: 'DOP length $length',
        );
      }
      for (final length in [500, 507, 511, 539, 540, 543]) {
        expect(
          () => parseLegacyWordDocument(
            _source(dop: _dop(length), newVersion: 0xd9),
          ),
          throwsFormatException,
          reason: 'Dop2000 length $length',
        );
      }
      expect(
        () => parseLegacyWordDocument(
          _source(
            dop: _dop(500),
            mutate: (fib) => fib.setUint16(154 + 93 * 8, 0xffff, Endian.little),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseLegacyWordDocument(
          _source(
            dop: _dop(544),
            newVersion: 0xd9,
            mutate: (fib) =>
                fib.setUint32(64, 154 + 108 * 8 + 2, Endian.little),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('empty stories retain explicit options and native XML order', () {
    final parsed = parseLegacyWordDocument(
      _source(dop: _dop(500, options: 0x80080008), empty: true),
    );
    expect(parsed.blocks, isEmpty);
    expect(
      parsed.compatibility[LegacyWordCompatibilityFlag.usePrinterMetrics],
      isTrue,
    );
    final files = _parts(convertLegacyWordDocument(parsed).bytes);
    final xml = XmlDocument.parse(utf8.decode(files['word/settings.xml']!));
    expect(xml.rootElement.childElements.map((node) => node.name.local), [
      'updateFields',
      'compat',
    ]);
    expect(
      xml
          .findAllElements('updateFields', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      'false',
    );
    final compat = xml.findAllElements('compat', namespace: _w).single;
    final names = compat.childElements.map((node) => node.name.local).toList();
    expect(names.take(4), [
      'useSingleBorderforContiguousCells',
      'wpJustification',
      'noTabHangInd',
      'noLeading',
    ]);
    expect(names.last, 'noSpaceRaiseLower');
    expect(_settings(files), _resolved(parsed));
  });

  test(
    'public model copies collections and bytes without filling absent flags',
    () {
      final flags = {LegacyWordCompatibilityFlag.wrapTrailSpaces: false};
      final raw = Uint8List.fromList([8, 0]);
      final block = LegacyWordCompatibilityBlock(
        kind: LegacyWordCompatibilityBlockKind.copts60,
        bytes: raw,
      );
      final blocks = [block];
      final compatibility = LegacyWordCompatibility(
        flags: flags,
        sourceBlocks: blocks,
      );
      flags[LegacyWordCompatibilityFlag.wrapTrailSpaces] = true;
      raw[0] = 0;
      blocks.clear();
      expect(
        compatibility[LegacyWordCompatibilityFlag.wrapTrailSpaces],
        isFalse,
      );
      expect(compatibility.sourceBlocks.single.bytes, [8, 0]);
      expect(() => compatibility.flags.clear(), throwsUnsupportedError);
      expect(
        () => compatibility.sourceBlocks.single.bytes[0] = 0,
        throwsUnsupportedError,
      );
      final document = LegacyWordDocument(
        blocks: const [],
        sections: const [],
        plainText: '',
        safeHtml: '',
        compatibility: compatibility,
      );
      expect(_settings(_parts(convertLegacyWordDocument(document).bytes)), {
        'wrapTrailSpaces': false,
      });
      expect(
        () => LegacyWordCompatibilityBlock(
          kind: LegacyWordCompatibilityBlockKind.copts,
          bytes: Uint8List(31),
        ),
        throwsFormatException,
      );
      expect(
        () => LegacyWordCompatibility(
          flags: flags,
          ambiguousFlags: {LegacyWordCompatibilityFlag.wrapTrailSpaces},
        ),
        throwsFormatException,
      );
      expect(
        () => LegacyWordCompatibility(sourceBlocks: [block, block]),
        throwsFormatException,
      );
    },
  );
}
