// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordFontWriter on _StructuredWordWriter {
  void _writeFontTable() {
    if (document.fontTable.isEmpty) return;
    if (document.fontTable.length > 4096) _tooComplex();
    final indices = <int>{};
    final groups = <String, List<LegacyWordFontDefinition>>{};
    for (final font in document.fontTable) {
      // Validate callers' metadata before using it in XML or evidence.
      font.hexadecimalCharset;
      if (!indices.add(font.sourceIndex)) {
        throw const FormatException('Duplicate Word source font index.');
      }
      groups.putIfAbsent(font.name.toLowerCase(), () => []).add(font);
    }
    final xml = _BoundedWordXml()
      ..add(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:fonts xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main">',
      );
    final decisions = <Map<String, Object?>>[];
    var emitted = 0;
    for (final entries in groups.values) {
      final name = entries.first.name;
      final charsets = entries.map((font) => font.charset).toSet();
      int? charset;
      String? reason;
      if (name.isEmpty) {
        reason = 'empty source font name';
      } else if (entries.any((font) => font.name != name)) {
        reason = 'case-variant font names are not merged';
      } else if (charsets.any((value) => !_wordFontCharsets.contains(value))) {
        reason = 'unrecognized source charset';
      } else if (charsets.length == 1) {
        charset = charsets.single;
      } else if (charsets.length == 2 &&
          charsets.contains(1) &&
          charsets.contains(2)) {
        // Bounded, independently qualified FFN alias case: an explicit symbol
        // face also occurs as DEFAULT_CHARSET. Keep the explicit symbol-font
        // property without mapping PUA text. DEFAULT_CHARSET is locale-based;
        // it is not generally equivalent to another explicit charset.
        charset = 2;
        reason = 'explicit symbol charset with a default-charset alias';
      } else {
        reason =
            'same-name source charsets cannot be represented unambiguously';
      }
      decisions.add({
        'name': name,
        'sourceIndices': entries.map((font) => font.sourceIndex).toList(),
        'emittedCharset': charset,
        if (reason != null) 'qualification': reason,
      });
      if (charset == null) {
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
        continue;
      }
      xml.add('<w:font w:name="');
      xml.text(name, attribute: true);
      xml.add(
        '"><w:charset w:val="'
        '${charset.toRadixString(16).padLeft(2, '0').toUpperCase()}"/>'
        '</w:font>',
      );
      emitted++;
    }
    xml.add('</w:fonts>');
    _evidenceRecords.add({
      'kind': 'sourceFontCharsets',
      'definitions': [
        for (final font in document.fontTable)
          {
            'sourceIndex': font.sourceIndex,
            'name': font.name,
            'charset': font.charset,
          },
      ],
      'decisions': decisions,
      'scope':
          'FFN primary name and charset; other font properties not emitted',
    });
    if (emitted == 0) return;
    _package.addXml(
      'word/fontTable.xml',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml',
      xml,
    );
    _package.relate(
      'word/document.xml',
      '$_relationshipNamespace/fontTable',
      'fontTable.xml',
    );
    _count('fontCharsets', emitted);
  }
}

// MS-DOC 2.9.82 FFN.chs, not an inferred encoding for document text.
const _wordFontCharsets = {
  0,
  1,
  2,
  77,
  128,
  129,
  130,
  134,
  136,
  161,
  162,
  163,
  177,
  178,
  186,
  204,
  222,
  238,
  255,
};
