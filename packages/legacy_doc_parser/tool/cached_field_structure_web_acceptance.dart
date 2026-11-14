// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/cached_field_structure_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool result, String message) {
  if (!result) throw StateError(message);
}

LegacyWordStructuredConversion verifyCachedFieldStructureCase(
  String scope,
  String revision, {
  required bool privateResult,
}) {
  final input = cachedStructureDocument(
    scope,
    revision,
    privateResult: privateResult,
  );
  final converted = convertLegacyWordDocument(
    input,
    fieldMode: LegacyWordFieldMode.cachedResults,
  );
  final zip = ZipDecoder().decodeBytes(converted.bytes);
  final parts = <String, XmlDocument>{
    for (final part in zip)
      if (part.name.startsWith('word/') && part.name.endsWith('.xml'))
        part.name: XmlDocument.parse(utf8.decode(part.content)),
  };
  for (final xml in parts.values) {
    for (final name in ['fldChar', 'fldSimple', 'instrText']) {
      _check(
        xml.findAllElements(name, namespace: _w).isEmpty,
        '$scope active $name',
      );
    }
  }
  final path = switch (scope) {
    'header' || 'header-textbox' => 'word/header1.xml',
    'footer' => 'word/footer1.xml',
    'footnote' => 'word/footnotes.xml',
    'endnote' => 'word/endnotes.xml',
    'comment' => 'word/comments.xml',
    _ => 'word/document.xml',
  };
  final xml = parts[path]!;
  final target = xml
      .findAllElements('p', namespace: _w)
      .singleWhere(
        (p) =>
            _child(p, 'pPr')
                ?.getElement('spacing', namespace: _w)
                ?.getAttribute('before', namespace: _w) ==
            '123',
      );
  final ppr = _child(target, 'pPr')!;
  _check(
    _value(ppr, 'jc') == 'right' && _value(ppr, 'ind', 'left') == '360',
    '$scope lost paragraph properties',
  );
  _check(
    _value(ppr, 'spacing', 'line') == '240' &&
        _value(ppr, 'spacing', 'lineRule') == 'exact',
    '$scope lost exact line spacing',
  );
  _check(
    _value(_child(ppr, 'rPr')!, 'sz') == '30',
    '$scope lost terminal mark formatting',
  );
  final paragraphChange = _child(ppr, 'pPrChange')!;
  _check(
    paragraphChange.getAttribute('author', namespace: _w) == 'ParagraphEditor',
    '$scope lost paragraph revision author',
  );
  final previousParagraph = _child(paragraphChange, 'pPr')!;
  _check(
    _value(previousParagraph, 'spacing', 'before') == '12' &&
        _value(previousParagraph, 'spacing', 'lineRule') == 'auto',
    '$scope lost previous paragraph properties',
  );
  final texts = target.descendants.whereType<XmlElement>().where(
    (e) =>
        e.name.namespaceUri == _w &&
        const ['t', 'delText'].contains(e.name.local),
  );
  _check(
    texts.map((e) => e.innerText).join() == (privateResult ? 'AZ' : 'ACacheZ'),
    '$scope/$revision changed stored revision text',
  );
  if (!privateResult) {
    final text = texts.singleWhere((e) => e.innerText == 'Cache');
    final run = text.parentElement!;
    final rpr = _child(run, 'rPr')!;
    _check(
      _value(rpr, 'b') == '1' &&
          _value(rpr, 'i') == '1' &&
          _value(rpr, 'u') == 'double',
      '$scope lost character toggles',
    );
    _check(
      _value(rpr, 'color') == '2468AC' &&
          _value(rpr, 'sz') == '28' &&
          _value(rpr, 'spacing') == '5',
      '$scope lost character scalars',
    );
    _check(
      _value(rpr, 'rFonts', 'ascii') == 'Verdana',
      '$scope lost character font',
    );
    _check(
      run.getAttribute('rsidRPr', namespace: _w) == '10203040',
      '$scope lost formatting save id',
    );
    final formatChange = _child(rpr, 'rPrChange')!;
    _check(
      formatChange.getAttribute('author', namespace: _w) == 'Formatter',
      '$scope lost character revision author',
    );
    _check(
      _value(_child(formatChange, 'rPr')!, 'sz') == '22',
      '$scope lost previous character style',
    );
    final inserted = revision == 'inserted' || revision == 'both';
    final deleted = revision == 'deleted' || revision == 'both';
    final ancestors = text.ancestors
        .whereType<XmlElement>()
        .where((e) => e.name.namespaceUri == _w)
        .toList();
    for (final (name, enabled, author) in [
      ('ins', inserted, 'Inserter'),
      ('del', deleted, 'Deleter'),
    ]) {
      final wrappers = ancestors.where((e) => e.name.local == name).toList();
      _check(
        wrappers.length == (enabled ? 1 : 0),
        '$scope lost $name revision scope',
      );
      if (enabled) {
        _check(
          wrappers.single.getAttribute('author', namespace: _w) == author,
          '$scope lost $name author',
        );
      }
    }
    _check(
      text.name.local == (deleted ? 'delText' : 't'),
      '$scope accepted a deleted cache',
    );
  }
  if (scope == 'list') {
    _check(
      _value(_child(ppr, 'numPr')!, 'numId') != null &&
          parts.containsKey('word/numbering.xml'),
      'cached list lost numbering',
    );
  }
  if (scope == 'table') {
    _check(
      xml.findAllElements('tbl', namespace: _w).length == 1,
      'cached field lost table',
    );
  }
  if (scope == 'textbox' || scope == 'header-textbox') {
    _check(
      target.ancestors.whereType<XmlElement>().any(
        (e) => e.name.local == 'txbxContent',
      ),
      'cached field lost textbox',
    );
  }
  if (scope == 'coincident') {
    for (final name in [
      'bookmarkStart',
      'bookmarkEnd',
      'commentRangeStart',
      'commentRangeEnd',
      'commentReference',
      'footnoteReference',
    ]) {
      _check(
        target.findAllElements(name, namespace: _w).length ==
            (privateResult ? 0 : 1),
        'cached simultaneous $name changed',
      );
    }
    if (!privateResult) {
      final order = target.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.namespaceUri == _w)
          .toList();
      int at(String name) => order.indexWhere((e) => e.name.local == name);
      final cacheIndex = order.indexWhere(
        (e) =>
            const ['t', 'delText'].contains(e.name.local) &&
            e.innerText == 'Cache',
      );
      _check(
        at('bookmarkStart') < at('footnoteReference') &&
            at('commentRangeStart') < at('commentReference') &&
            at('footnoteReference') < cacheIndex &&
            at('commentReference') < cacheIndex &&
            at('bookmarkEnd') > cacheIndex &&
            at('commentRangeEnd') > cacheIndex,
        'same-CP event order changed',
      );
      _check(
        parts['word/footnotes.xml']!
            .findAllElements('footnote', namespace: _w)
            .any((n) => n.getAttribute('id', namespace: _w) == '11'),
        'coincident note target missing',
      );
      _check(
        parts['word/comments.xml']!
            .findAllElements('comment', namespace: _w)
            .any((n) => n.getAttribute('id', namespace: _w) == '21'),
        'coincident comment target missing',
      );
    } else {
      _check(
        !parts.containsKey('word/footnotes.xml') &&
            !parts.containsKey('word/comments.xml'),
        'private field activated auxiliary story',
      );
    }
  }
  final manifest =
      jsonDecode(
            utf8.decode(zip.findFile('word/evidence/manifest.json')!.content),
          )
          as Map;
  final record = (manifest['records'] as List).cast<Map>().singleWhere(
    (e) => e['kind'] == 'cachedField',
  );
  final field = input.fields.single;
  final expected = <String, Object?>{
    'id': field.id,
    'parentId': field.parentId,
    'story': field.storyId,
    'startCp': field.startCp,
    'separatorCp': field.separatorCp,
    'endCp': field.endCp,
    'instruction': field.instruction,
    'storedResult': field.storedResult,
    'type': field.type,
    'locked': field.locked,
    'dirty': field.dirty,
    'privateResult': field.privateResult,
    'beginHidden': field.beginHidden,
    'separatorHidden': field.separatorHidden,
    'endHidden': field.endHidden,
    'instructionHiddenRanges': [
      for (final range in field.instructionVisibility.hiddenRanges)
        [range.$1, range.$2],
    ],
  };
  for (final entry in expected.entries) {
    _check(
      jsonEncode(record[entry.key]) == jsonEncode(entry.value),
      '$scope lost field ${entry.key}',
    );
  }
  _check(
    converted.preservedCounts['cachedResultFields'] == 1 &&
        (converted.preservedCounts['fields'] ?? 0) == 0,
    'cached field counted as editable',
  );
  return converted;
}

Map<String, Object?> verifyCachedFieldStructureWebAcceptance() {
  var variants = 0;
  for (final scope in cachedStructureScopes) {
    for (final revision in cachedStructureRevisions) {
      for (final privateResult in [false, true]) {
        verifyCachedFieldStructureCase(
          scope,
          revision,
          privateResult: privateResult,
        );
        variants++;
      }
    }
  }
  var contradictions = 0, depths = 0;
  for (final mode in LegacyWordFieldMode.values) {
    convertLegacyWordDocument(cachedFieldDepthDocument(64), fieldMode: mode);
    try {
      convertLegacyWordDocument(cachedFieldDepthDocument(65), fieldMode: mode);
      throw StateError('Depth65 escaped $mode');
    } on LegacyWordConversionException catch (error) {
      _check(
        error.issue == LegacyWordConversionIssue.tooComplex,
        'wrong depth rejection',
      );
      depths++;
    }
    for (final bad in [
      'instruction',
      'cross-instruction',
      'private-result',
      'hidden-private',
    ]) {
      try {
        convertLegacyWordDocument(
          cachedStructureDocument(
            'body',
            'ordinary',
            privateResult: bad.contains('private'),
            contradictoryRun: bad,
          ),
          fieldMode: mode,
        );
        throw StateError('$bad escaped $mode');
      } on FormatException {
        contradictions++;
      }
    }
    convertLegacyWordDocument(
      cachedStructureDocument(
        'body',
        'ordinary',
        contradictoryRun: 'empty-instruction',
      ),
      fieldMode: mode,
    );
  }
  return {
    'structureVariants': variants,
    'contradictoryRunsRejected': contradictions,
    'excessiveDepthRejected': depths,
    'maximumDepthAccepted': 64,
    'activeFields': 0,
    'fieldEvidenceExact': true,
  };
}

XmlElement? _child(XmlElement element, String name) =>
    element.getElement(name, namespace: _w);
String? _value(XmlElement element, String name, [String attribute = 'val']) =>
    _child(element, name)?.getAttribute(attribute, namespace: _w);
