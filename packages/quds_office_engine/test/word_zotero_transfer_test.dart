import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _instructions =
    'Open this document in the destination editor and refresh Zotero.';
const _url = WordZoteroTransfer.linkUrl;

String _preferences([String fieldType = 'Http']) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'transfer-test',
  'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'de-DE'},
  'prefs': {'fieldType': fieldType, 'noteType': 0},
  'future': {
    'preserve': ['unknown', 42],
  },
});

ZoteroCitation _citation(String id, {String text = '(Source)'}) =>
    ZoteroCitation.fromJson({
      'citationID': id,
      'properties': {
        'formattedCitation': text,
        'plainCitation': text,
        'noteIndex': 0,
      },
      'citationItems': [
        {
          'id': id,
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '13–15',
          'label': 'page',
          'prefix': 'see ',
          'suffix': ', especially',
          'itemData': {
            'id': id,
            'type': 'book',
            'title': 'Title ITEM CSL_CITATION {quoted}',
          },
          'future-item': {
            'data': [1, 'x'],
          },
        },
      ],
      'future-citation': true,
    });

String _code(String id, {String text = '(Source)'}) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text: text).toJson())}';

WmlParagraph _p(String text, {bool bold = false}) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(bold: bold),
    ),
  ],
);

WmlParagraph _linked(String text, {String url = _url}) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      hyperlink: WmlHyperlink(url: url),
    ),
  ],
);

WmlDocument _document(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

WmlDocument _active() {
  final paragraph = _p('Before after', bold: true);
  WordZotero.insertCitation(paragraph, _citation('first'), index: 7);
  return _document([paragraph])..zoteroDocumentData = _preferences('Field');
}

WordZoteroTransferPlan _export(WmlDocument source) =>
    WordZoteroTransfer.prepareExport(
      source,
      instructions: _instructions,
      documentData: _preferences(),
    );

WmlDocument _carrier({
  String marker = WordZoteroTransfer.marker,
  String? preferences,
  List<WmlBlock>? content,
}) => _document([
  _p(marker),
  _p(''),
  _p(_instructions),
  _p(''),
  ...content ?? [_linked(_code('first'))],
  _linked(
    '${WordZoteroTransfer.preferencesPrefix}${preferences ?? _preferences()}',
  ),
]);

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

void _refreshImported(
  WordZoteroTransferPlan plan, {
  String citationText = '<i>(Updated)</i>',
}) {
  final session = WordZoteroCitingSession(
    document: plan.document,
    documentId: 'model-transfer',
  );
  final fields =
      (session.handle('Document.getFields', ['model-transfer', 'Http'])!
              as List<Object?>)
          .cast<Map<String, Object?>>();
  for (final field in fields) {
    final bibliography = (field['code']! as String).startsWith('BIBL ');
    session.handle('Field.setText', [
      'model-transfer',
      field['id'],
      bibliography
          ? '<div><i>First entry</i></div><div>Second entry</div>'
          : citationText,
      true,
    ]);
  }
  session.handle('Document.complete', ['model-transfer']);
  session.apply();
}

void main() {
  test('removes observed LibreOffice navy only from its hyperlink style', () {
    final styled = _linked(_code('first'));
    (styled.inlines.single as WmlRun).properties = WmlRunProps(
      styleId: 'Hyperlink',
      color: '000080',
      underline: WmlUnderline.single,
    );
    final authored = _linked(_code('second'));
    (authored.inlines.single as WmlRun).properties = WmlRunProps(
      color: '000080',
      underline: WmlUnderline.single,
    );
    final source = _reopen(_carrier(content: [styled, authored]));
    final plan = WordZoteroTransfer.prepareImport(source);
    _refreshImported(plan);
    plan.apply();
    final fields = WordZotero.fields(_reopen(source));
    expect(fields[0].run!.properties.styleId, isNull);
    expect(fields[0].run!.properties.color, '000000');
    expect(fields[1].run!.properties.color, '000080');
  });

  for (final style in ['Hyperlink', 'FollowedHyperlink']) {
    test('removes $style carrier appearance while retaining rich output', () {
      final carrier = _linked(_code('first'));
      (carrier.inlines.single as WmlRun).properties = WmlRunProps(
        styleId: style,
        color: style == 'Hyperlink' ? '0000FF' : '954F72',
        underline: WmlUnderline.single,
        asciiFont: 'Georgia',
        csFont: 'Amiri',
        fontSizeHalfPoints: 28,
      );
      final ordinary = _linked('An ordinary link');
      (ordinary.inlines.single as WmlRun).properties = WmlRunProps(
        styleId: style,
        color: '0000FF',
        underline: WmlUnderline.single,
      );
      final source = _carrier(content: [carrier, ordinary]);
      final plan = WordZoteroTransfer.prepareImport(source);
      final placeholder = WordZotero.fields(plan.document).single.run!;
      expect(placeholder.properties.styleId, isNull);
      expect(placeholder.properties.color, '000000');
      expect(placeholder.properties.underline, WmlUnderline.none);
      expect((carrier.inlines.single as WmlRun).properties.styleId, style);
      _refreshImported(plan, citationText: '<i><u>(Updated)</u></i>');
      plan.apply();
      final result = WordZotero.fields(_reopen(source)).single.run!;
      expect(result.hyperlink, isNull);
      expect(result.properties.styleId, isNull);
      expect(result.properties.color, '000000');
      expect(result.properties.asciiFont, 'Georgia');
      expect(result.properties.csFont, 'Amiri');
      expect(result.properties.fontSizeHalfPoints, 28);
      expect(result.properties.italic, isTrue);
      expect(result.properties.underline, WmlUnderline.single);
      final ordinaryRun = ordinary.inlines.single as WmlRun;
      expect(ordinaryRun.hyperlink?.url, _url);
      expect(ordinaryRun.properties.styleId, style);
      expect(ordinaryRun.properties.color, '0000FF');
      expect(ordinaryRun.properties.underline, WmlUnderline.single);
    });
  }

  for (final style in [null, 'Hyperlink']) {
    test('styleless DOCX carrier with $style restores direct black', () {
      final source = _active();
      final original = WordZotero.fields(source).single.run!;
      original.properties
        ..asciiFont = 'Georgia'
        ..fontSizeHalfPoints = 28;
      _export(source).apply();
      if (style != null) {
        final run = source.paragraphs
            .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
            .firstWhere((run) => run.text.startsWith('ITEM CSL_CITATION '));
        run.properties.styleId = style;
      }
      final package = OpcPackage.openBytes(WordSerializer().writeBytes(source));
      final relationships = package.relationshipsFor('/word/document.xml');
      final styles = relationships.firstByType(RelationshipTypes.styles);
      if (styles != null) {
        package.deletePart(relationships.resolve(styles));
        relationships.removeById(styles.id);
      }
      final reopenedCarrier = WordDeserializer().readBytes(package.save());
      final linked = reopenedCarrier.paragraphs
          .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
          .firstWhere((run) => run.text.startsWith('ITEM CSL_CITATION '));
      expect(linked.properties.color, '0563C1');
      final plan = WordZoteroTransfer.prepareImport(reopenedCarrier);
      _refreshImported(plan);
      plan.apply();
      final result = WordZotero.fields(
        _reopen(_reopen(reopenedCarrier)),
      ).single.run!;
      expect(result.hyperlink, isNull);
      expect(result.properties.styleId, isNull);
      expect(result.properties.color, '000000');
      expect(result.properties.underline, WmlUnderline.none);
      expect(result.properties.italic, isTrue);
      expect(result.properties.asciiFont, 'Georgia');
      expect(result.properties.fontSizeHalfPoints, 28);
    });
  }

  for (final style in ['Hyperlink', 'AuthoredCharacterStyle']) {
    test('preserves authored color and fonts from a $style carrier', () {
      final carrier = _linked(_code('first'));
      (carrier.inlines.single as WmlRun).properties = WmlRunProps(
        styleId: style,
        color: 'A32137',
        underline: WmlUnderline.single,
        asciiFont: 'Georgia',
        csFont: 'Amiri',
        fontSizeHalfPoints: 30,
        complexScriptLanguage: 'ar-SA',
      );
      final source = _reopen(_carrier(content: [carrier]));
      final plan = WordZoteroTransfer.prepareImport(source);
      _refreshImported(plan);
      plan.apply();
      final result = WordZotero.fields(_reopen(source)).single.run!;
      expect(result.properties.styleId, style == 'Hyperlink' ? isNull : style);
      expect(result.properties.color, 'A32137');
      expect(result.properties.asciiFont, 'Georgia');
      expect(result.properties.csFont, 'Amiri');
      expect(result.properties.fontSizeHalfPoints, 30);
      expect(result.properties.complexScriptLanguage, 'ar-SA');
      expect(result.properties.italic, isTrue);
    });
  }

  test('retains authored direct blue and the paragraph baseline color', () {
    final authored = _linked(_code('first'));
    (authored.inlines.single as WmlRun).properties = WmlRunProps(
      color: '0563C1',
      underline: WmlUnderline.single,
    );
    final source = _reopen(_carrier(content: [authored]));
    final plan = WordZoteroTransfer.prepareImport(source);
    _refreshImported(plan);
    plan.apply();
    expect(
      WordZotero.fields(_reopen(source)).single.run!.properties.color,
      '0563C1',
    );

    final inherited = _linked(_code('second'));
    inherited.properties.styleId = 'AuthoredParagraph';
    (inherited.inlines.single as WmlRun).properties = WmlRunProps(
      styleId: 'Hyperlink',
      color: '0000FF',
      underline: WmlUnderline.single,
    );
    final document = _carrier(content: [inherited]);
    document.styles.add(
      const WmlStyle(
        id: 'AuthoredParagraph',
        name: 'Authored paragraph',
        nameAr: '',
        color: '3C5E2B',
      ),
    );
    final imported = WordZoteroTransfer.prepareImport(document);
    expect(
      WordZotero.fields(imported.document).single.run!.properties.color,
      '3C5E2B',
    );
  });

  test('imports pinned Google Docs keyed links and unkeyed preferences', () {
    const base = 'https://www.zotero.org/google-docs/?';
    final first = _code('first');
    final source = _carrier(
      content: [
        WmlParagraph(
          inlines: [
            WmlRun(
              text: first.substring(0, 12),
              hyperlink: const WmlHyperlink(url: '${base}Ab12z9'),
            ),
            WmlRun(
              text: first.substring(12),
              hyperlink: const WmlHyperlink(url: '${base}Ab12z9'),
              properties: WmlRunProps(italic: true),
            ),
            WmlRun(
              text: _code('second'),
              hyperlink: const WmlHyperlink(url: '${base}ZX98wq'),
            ),
          ],
        ),
      ],
    );
    (source.paragraphs.last.inlines.single as WmlRun).hyperlink =
        const WmlHyperlink(url: base);
    final plan = WordZoteroTransfer.prepareImport(_reopen(source));
    expect(
      WordZotero.fields(plan.document).map((f) => f.citation!.citationId),
      ['first', 'second'],
    );
    expect(WordZoteroDocumentData.read(plan.document), _preferences('Field'));
  });

  for (final url in [
    'https://www.zotero.org/google-docs/?short',
    'https://www.zotero.org/google-docs/?toolong',
    'https://www.zotero.org/google-docs/?ABC123&extra=1',
    'https://www.zotero.org/google-docs/?ABC123#fragment',
    'http://www.zotero.org/google-docs/?ABC123',
    'https://www.zotero.org.evil.example/google-docs/?ABC123',
    'https://user@www.zotero.org/google-docs/?ABC123',
    'https://www.zotero.org:443/google-docs/?ABC123',
    'https://www.zotero.org/google-docs/?',
  ]) {
    test('rejects unverified or unkeyed field target $url', () {
      expect(
        () => WordZoteroTransfer.prepareImport(
          _carrier(content: [_linked(_code('first'), url: url)]),
        ),
        throwsFormatException,
      );
    });
  }

  test('does not accept keyed Google Docs URL as document preferences', () {
    final source = _carrier();
    (source.paragraphs.last.inlines.single as WmlRun).hyperlink =
        const WmlHyperlink(url: 'https://www.zotero.org/google-docs/?ABC123');
    expect(
      () => WordZoteroTransfer.prepareImport(source),
      throwsFormatException,
    );
  });

  for (final entry in <String, void Function(WmlParagraphProps)>{
    'begin': (p) => p.fieldBegin = true,
    'separate': (p) => p.fieldSeparate = true,
    'end': (p) => p.fieldEnd = true,
  }.entries) {
    for (final framing in [true, false]) {
      test(
        'rejects orphaned paragraph ${entry.key} flag in ${framing ? 'framing' : 'carrier'}',
        () {
          final source = _carrier();
          final paragraph = source.paragraphs.elementAt(framing ? 0 : 4);
          entry.value(paragraph.properties);
          expect(
            () => WordZoteroTransfer.prepareImport(source),
            framing ? throwsFormatException : throwsUnsupportedError,
          );
          expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
        },
      );
    }
  }

  test(
    'export is detached, uses raw linked codes and preserves source identities on apply',
    () {
      final source = _active();
      final section = source.sections.single;
      final blocks = section.blocks;
      final paragraph = source.paragraphs.single;
      final originalText = paragraph.text;
      final plan = _export(source);
      expect(WordZoteroTransfer.isTransferDocument(source), isFalse);
      expect(paragraph.text, originalText);
      expect(WordZotero.fields(source), hasLength(1));
      expect(plan.paragraphFor(paragraph), isNot(same(paragraph)));
      expect(
        plan.originalParagraphFor(plan.paragraphFor(paragraph)!),
        same(paragraph),
      );
      expect(plan.document.paragraphs.take(4).map((p) => p.text), [
        WordZoteroTransfer.marker,
        '',
        _instructions,
        '',
      ]);
      final link = plan
          .paragraphFor(paragraph)!
          .inlines
          .whereType<WmlRun>()
          .singleWhere((run) => run.hyperlink?.url == _url);
      expect(link.text, _code('first'));
      expect(link.text, contains('future-citation'));
      expect(WordZotero.fields(plan.document), isEmpty);
      expect(
        plan.document.paragraphs.last.text,
        'DOCUMENT_PREFERENCES ${_preferences()}',
      );
      plan.apply();
      expect(source.sections.single, same(section));
      expect(section.blocks, same(blocks));
      expect(section.blocks[4], same(paragraph));
      expect(
        paragraph.inlines.whereType<WmlRun>().first.properties.bold,
        isTrue,
      );
      expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
      expect(() => plan.apply(), throwsStateError);
    },
  );

  for (final marker in [
    WordZoteroTransfer.marker,
    WordZoteroTransfer.legacyMarker,
  ]) {
    test('imports $marker before stale invalid native preferences', () {
      final source = _carrier(marker: marker)
        ..zoteroDocumentData = 'invalid stale preferences';
      final content = source.paragraphs.elementAt(4);
      final plan = WordZoteroTransfer.prepareImport(source);
      expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
      expect(WordZoteroTransfer.isTransferDocument(plan.document), isFalse);
      expect(WordZotero.fields(plan.document).single.cachedText, '{Citation}');
      expect(
        WordZotero.fields(plan.document).single.citation!.citationId,
        'first',
      );
      expect(WordZoteroDocumentData.read(plan.document), _preferences('Field'));
      _refreshImported(plan);
      plan.apply();
      expect(source.paragraphs.single, same(content));
      expect(source.paragraphs.single.text, '(Updated)');
      expect(
        source.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .italic,
        isTrue,
      );
      expect(
        WordZotero.fields(_reopen(source)).single.citation!.citationId,
        'first',
      );
    });
  }

  for (final format in ['Field', 'Http', 'ReferenceMark', 'Bookmark']) {
    test(
      'transfer normalizes $format preferences, retaining extension members',
      () {
        final data = WordZoteroDocumentData.fromTransfer(_preferences(format));
        expect(data, _preferences('Field'));
        final plan = WordZoteroTransfer.prepareImport(
          _carrier(preferences: _preferences(format)),
        );
        expect(WordZoteroDocumentData.read(plan.document), data);
        if (format == 'ReferenceMark' || format == 'Bookmark') {
          expect(
            () => WordZoteroDocumentData.toNative(_preferences(format)),
            throwsFormatException,
          );
        }
      },
    );
  }

  test(
    'native XML preferences from LibreOffice are normalized with unknown XML retained',
    () {
      const data =
          '<data data-version="4"><style id="apa"/><prefs>'
          '<pref name="fieldType" value="ReferenceMark"/><pref name="noteType" value="0"/>'
          '<pref name="unknown" value="kept"/></prefs><future key="value"/></data>';
      final result = WordZoteroDocumentData.fromTransfer(data);
      expect(result, contains('value="Field"'));
      expect(result, contains('name="unknown"'));
      expect(result, contains('<future key="value"'));
      final plan = WordZoteroTransfer.prepareImport(
        _carrier(preferences: data),
      );
      expect(WordZoteroDocumentData.read(plan.document), result);
    },
  );

  test(
    'rejoins formatted fragments and splits adjacent merged citation links without scanning inside JSON',
    () {
      final text = '${_code('first')}${_code('second')}';
      final content = WmlParagraph(
        inlines: [
          WmlRun(text: 'Before ', properties: WmlRunProps(bold: true)),
          for (final (start, end) in [(0, 7), (7, 23), (23, text.length)])
            WmlRun(
              text: text.substring(start, end),
              hyperlink: const WmlHyperlink(url: _url),
              properties: WmlRunProps(italic: start == 7),
            ),
          WmlRun(
            text: ' after',
            hyperlink: const WmlHyperlink(url: 'https://example.org/'),
          ),
        ],
      );
      final source = _carrier(content: [content]);
      final plan = WordZoteroTransfer.prepareImport(source);
      final fields = WordZotero.fields(plan.document);
      expect(fields.map((f) => f.citation!.citationId), ['first', 'second']);
      expect(
        fields.first.citation!.items.single.itemData!['title'],
        contains('ITEM CSL_CITATION'),
      );
      final paragraph = plan.paragraphFor(content)!;
      expect(
        paragraph.inlines.whereType<WmlRun>().first.properties.bold,
        isTrue,
      );
      expect(
        paragraph.inlines.whereType<WmlRun>().last.hyperlink?.url,
        'https://example.org/',
      );
      expect(content.text, 'Before $text after');
    },
  );

  test(
    'empty adjacent citation results retain order through export, DOCX and import',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(
            text: '',
            fieldInstruction: _citation('first', text: '').fieldInstruction,
          ),
          WmlRun(
            text: '',
            fieldInstruction: _citation('second', text: '').fieldInstruction,
          ),
        ],
      );
      final plan = _export(_document([paragraph]));
      final reopened = _reopen(plan.document);
      final imported = WordZoteroTransfer.prepareImport(reopened);
      expect(
        WordZotero.fields(imported.document).map((f) => f.citation!.citationId),
        ['first', 'second'],
      );
    },
  );

  test(
    'complex inline packets preserve rich surrounding runs and ordinary URLs',
    () {
      final citation = _citation('complex');
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'Left ', properties: WmlRunProps(bold: true)),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: citation.fieldInstruction,
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: '(Com', properties: WmlRunProps(italic: true)),
          WmlRun(text: 'plex)'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(
            text: ' Right',
            hyperlink: const WmlHyperlink(url: 'https://example.org/'),
          ),
        ],
      );
      final plan = _export(_document([paragraph]));
      final copy = plan.paragraphFor(paragraph)!;
      expect(copy.inlines, hasLength(3));
      expect((copy.inlines[0] as WmlRun).properties.bold, isTrue);
      expect(
        (copy.inlines[2] as WmlRun).hyperlink?.url,
        'https://example.org/',
      );
      expect(
        WordZotero.fields(
          WordZoteroTransfer.prepareImport(_reopen(plan.document)).document,
        ).single.citation!.citationId,
        'complex',
      );
    },
  );

  test(
    'complete rich bibliography entries transfer and refresh as an active multi-paragraph field',
    () {
      const raw =
          ' ADDIN ZOTERO_BIBL { "uncited": [["u"]], "omitted": [], "custom": [], "future": {"x":3} } CSL_BIBLIOGRAPHY ';
      final entries = WordZotero.nativeBibliographyParagraphs(
        instruction: raw,
        text: 'First\nSecond',
        formattedText: ZoteroFormattedText.fromHtml(
          '<div><i>First</i></div><div>Second</div>',
        ),
      );
      final source = _document([
        _p('Introduction'),
        ...entries,
        _p('Conclusion'),
      ]);
      final export = _export(source);
      expect(source.paragraphs.length, 4);
      expect(
        export.document.paragraphs.elementAt(5).text,
        'BIBL { "uncited": [["u"]], "omitted": [], "custom": [], "future": {"x":3} } CSL_BIBLIOGRAPHY',
      );
      export.apply();
      expect(source.sections.single.blocks[5], same(entries.first));
      final import = WordZoteroTransfer.prepareImport(source);
      _refreshImported(import);
      import.apply();
      final field = WordZotero.fields(source).single;
      expect(field.paragraphs, hasLength(2));
      expect(field.cachedText, 'First entry\nSecond entry');
      expect(field.metadata!['future'], {'x': 3});
      expect(source.paragraphs.first.text, 'Introduction');
      expect(source.paragraphs.last.text, 'Conclusion');
      expect(
        WordZotero.fields(_reopen(_reopen(source))).single.paragraphs,
        hasLength(2),
      );
    },
  );

  for (final endnote in [false, true]) {
    test(
      'table cells and authored ${endnote ? 'endnotes' : 'footnotes'} retain owners and prose',
      () {
        final cellParagraph = _p('Cell ');
        WordZotero.insertCitation(cellParagraph, _citation('cell'));
        final cell = WmlTableCell(
          blocks: [cellParagraph],
          gridSpan: 2,
          fillColor: 'EEF1F8',
        );
        final table = WmlTable(
          grid: [90, 90],
          rows: [
            WmlTableRow(cells: [cell]),
          ],
        );
        final body = _p('Body ');
        final source = _document([body, table]);
        final note = WordNotes.insert(source, body, endnote: endnote);
        final noteParagraph = note.paragraphs.single;
        noteParagraph.inlines.add(
          WmlRun(text: 'Authored note ', properties: WmlRunProps(italic: true)),
        );
        WordZotero.insertCitation(noteParagraph, _citation('note'));
        final noteBlocks = note.blocks;
        final cellBlocks = cell.blocks;
        final export = _export(source);
        export.apply();
        expect(source.sections.single.blocks[5], same(table));
        expect(cell.blocks, same(cellBlocks));
        expect(note.blocks, same(noteBlocks));
        final import = WordZoteroTransfer.prepareImport(source);
        _refreshImported(import);
        import.apply();
        expect(source.sections.single.blocks[1], same(table));
        expect(cell.blocks.single, same(cellParagraph));
        expect(note.blocks.single, same(noteParagraph));
        expect(cell.gridSpan, 2);
        expect(cell.fillColor, 'EEF1F8');
        expect(noteParagraph.text, startsWith('Authored note '));
        final reopened = _reopen(source);
        expect(
          WordZotero.fields(
            reopened,
          ).map((f) => f.citation!.citationId).toSet(),
          {'cell', 'note'},
        );
      },
    );
  }

  test(
    'inline picture bytes and source object survive transfer while cancellation stays isolated',
    () {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 3, height: 2)),
      );
      final picture = WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          imageBytes: bytes,
          width: 23,
          height: 17,
        ),
      );
      final source = _active();
      final paragraph = source.paragraphs.single;
      paragraph.inlines.add(WmlRun(text: '\ufffc', inlineVisual: picture));
      final plan = _export(source);
      final copiedPicture = plan
          .paragraphFor(paragraph)!
          .inlines
          .whereType<WmlRun>()
          .last
          .inlineVisual!;
      expect(copiedPicture, isNot(same(picture)));
      copiedPicture.visual.imageBytes![0] = 0;
      expect(picture.visual.imageBytes!.first, 137);
      final fresh = _export(source);
      fresh.apply();
      expect(
        paragraph.inlines.whereType<WmlRun>().last.inlineVisual,
        same(picture),
      );
      final reopened = _reopen(source);
      final import = WordZoteroTransfer.prepareImport(reopened);
      _refreshImported(import);
      import.apply();
      expect(
        reopened.inlineVisuals.single.visual.imageBytes,
        orderedEquals(bytes),
      );
    },
  );

  test('ODT carrier writer retains canonical links, prefs and marker', () {
    final export = _export(_active());
    final bytes = OdtDocumentWriter.writeBytes(export.document);
    final package = OpcPackage.openBytes(bytes);
    final xml = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    final links = _elements(xml, 'a')
        .where(
          (e) =>
              e.getAttribute(
                'href',
                namespaceUri: 'http://www.w3.org/1999/xlink',
              ) ==
              _url,
        )
        .toList();
    expect(links, hasLength(2));
    expect(links.map((e) => e.text).join(), contains('ITEM CSL_CITATION'));
    expect(links.map((e) => e.text).join(), contains('DOCUMENT_PREFERENCES'));
    expect(xml.text, contains(WordZoteroTransfer.marker));
  });

  final staleEdits = <String, void Function(WmlDocument)>{
    'text': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).text += 'changed',
    'run formatting': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).properties.bold =
            true,
    'paragraph formatting': (d) =>
        d.paragraphs.elementAt(4).properties.spacingAfter = 99,
    'hyperlink': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).hyperlink =
            const WmlHyperlink(url: 'https://example.org/'),
    'paragraph replacement': (d) =>
        d.sections.single.blocks[4] = _linked(_code('first')),
    'block-list replacement': (d) =>
        d.sections.single.blocks = List.of(d.sections.single.blocks),
    'auxiliary-story replacement': (d) =>
        d.sections.single.header = [_p('New header')],
    'preferences': (d) => d.zoteroDocumentData = _preferences('Field'),
    'restriction': (d) => d.restrictEditing = true,
  };
  for (final entry in staleEdits.entries) {
    test(
      'staged import rejects concurrent ${entry.key} changes before source mutation',
      () {
        final source = _carrier();
        final plan = WordZoteroTransfer.prepareImport(source);
        entry.value(source);
        expect(() => plan.assertUnchanged(), throwsStateError);
        expect(() => plan.apply(), throwsStateError);
        expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
        expect(WordZotero.fields(source), isEmpty);
      },
    );
  }

  final malformed = <String, void Function(WmlDocument)>{
    'missing preferences': (d) => d.sections.single.blocks.removeLast(),
    'duplicate preferences': (d) => d.sections.single.blocks.insert(
      5,
      _linked('DOCUMENT_PREFERENCES ${_preferences()}'),
    ),
    'preferences not last': (d) =>
        d.sections.single.blocks.add(_p('Keep this text')),
    'missing blank framing': (d) =>
        (d.sections.single.blocks[1] as WmlParagraph).inlines.add(
          WmlRun(text: 'authored text'),
        ),
    'framing bookmark': (d) =>
        d.paragraphs.first.properties.bookmarkName = 'keep',
    'framing comment': (d) =>
        (d.paragraphs.first.inlines.first as WmlRun).commentIds.add(42),
    'unlinked code': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).hyperlink = null,
    'redirected code': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).hyperlink =
            const WmlHyperlink(url: 'https://example.org/'),
    'empty preferences': (d) =>
        (d.paragraphs.last.inlines.first as WmlRun).text =
            'DOCUMENT_PREFERENCES ',
    'broken JSON': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).text =
            'ITEM CSL_CITATION {',
    'plain suffix in code link': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).text +=
            ' ordinary prose',
    'plain prefix in code link': (d) =>
        (d.paragraphs.elementAt(4).inlines.first as WmlRun).text =
            'ordinary prose ${_code('first')}',
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key} without deleting framing or authorship', () {
      final source = _carrier();
      entry.value(source);
      final blocks = List.of(source.sections.single.blocks);
      final text = source.paragraphs.map((p) => p.text).join('\n');
      expect(
        () => WordZoteroTransfer.prepareImport(source),
        throwsA(isA<Exception>()),
      );
      expect(source.sections.single.blocks, orderedEquals(blocks));
      expect(source.paragraphs.map((p) => p.text).join('\n'), text);
    });
  }

  test('lost hyperlink split across formatted runs is rejected', () {
    final code = _code('first');
    final source = _carrier(
      content: [
        WmlParagraph(
          inlines: [
            WmlRun(text: code.substring(0, 9)),
            WmlRun(
              text: code.substring(9),
              properties: WmlRunProps(italic: true),
            ),
          ],
        ),
      ],
    );
    expect(
      () => WordZoteroTransfer.prepareImport(source),
      throwsFormatException,
    );
  });

  test('ordinary homepage links remain prose when separate from fields', () {
    final source = _carrier(
      content: [_linked('Zotero homepage'), _linked(_code('first'))],
    );
    final plan = WordZoteroTransfer.prepareImport(source);
    expect(plan.document.paragraphs.first.text, 'Zotero homepage');
    expect(
      (plan.document.paragraphs.first.inlines.single as WmlRun).hyperlink?.url,
      _url,
    );
    expect(WordZotero.fields(plan.document), hasLength(1));
  });

  for (final location in [
    'header',
    'frame',
    'unanchored note',
    'duplicate paragraph',
  ]) {
    test('rejects $location transfer ownership', () {
      final source = _carrier();
      final link = source.sections.single.blocks.removeAt(4) as WmlParagraph;
      switch (location) {
        case 'header':
          source.sections.single.header.add(link);
        case 'frame':
          source.sections.single.blocks.insert(4, WmlFrame(blocks: [link]));
        case 'unanchored note':
          source.footnotes.add(WmlNote(id: 7, endnote: false, blocks: [link]));
        case 'duplicate paragraph':
          source.sections.single.blocks.insertAll(4, [link, link]);
      }
      expect(
        () => WordZoteroTransfer.prepareImport(source),
        throwsUnsupportedError,
      );
      expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
    });
  }

  test('rejects hidden opaque Zotero data and mixed active fields', () {
    final opaque = _carrier();
    opaque.sections.single.blocks.insert(
      4,
      WmlOpaqueBlock(
        xml: '<w:customXml>ADDIN ZOTERO_ITEM CSL_CITATION {}</w:customXml>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
      ),
    );
    expect(
      () => WordZoteroTransfer.prepareImport(opaque),
      throwsUnsupportedError,
    );
    final mixed = _carrier();
    mixed.sections.single.blocks.insert(4, _active().paragraphs.single);
    expect(
      () => WordZoteroTransfer.prepareImport(mixed),
      throwsUnsupportedError,
    );
  });

  test(
    'export rejects locked fields and protected source without changing it',
    () {
      final locked = _active();
      WordZotero.fields(locked).single.run!.fieldLocked = true;
      expect(() => _export(locked), throwsUnsupportedError);
      final protected = _active()..restrictEditing = true;
      expect(() => _export(protected), throwsUnsupportedError);
      final tracking = _active()..trackRevisions = true;
      expect(() => _export(tracking), throwsUnsupportedError);
    },
  );

  test(
    'marker detection cannot mistake a header or table cell for document framing',
    () {
      final source = _active();
      source.sections.single.header.add(_p(WordZoteroTransfer.marker));
      expect(WordZoteroTransfer.isTransferDocument(source), isFalse);
      source.sections.single.blocks.insert(
        0,
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [_p(WordZoteroTransfer.marker)]),
              ],
            ),
          ],
        ),
      );
      expect(WordZoteroTransfer.isTransferDocument(source), isFalse);
    },
  );

  test(
    'duplicate or unsupported preferences remain invalid in the transfer adapter',
    () {
      for (final data in [
        '{"prefs":{"fieldType":"Field","fieldType":"ReferenceMark"}}',
        '{"prefs":{"fieldType":"Unrecognized"}}',
        '<data><prefs><pref name="fieldType" value="Field"/><pref name="fieldType" value="Bookmark"/></prefs></data>',
      ]) {
        expect(
          () => WordZoteroDocumentData.fromTransfer(data),
          throwsFormatException,
        );
      }
    },
  );

  test('transfer rejects field-count and combined UTF-8 payload excess', () {
    final many = _document([
      WmlParagraph(
        inlines: [
          for (var i = 0; i <= WordZoteroTransfer.maxFields; i++)
            WmlRun(text: 'x', fieldInstruction: ' ADDIN ZOTERO_BIBL {} '),
        ],
      ),
    ]);
    expect(() => _export(many), throwsFormatException);
    final long = 'x' * (900 * 1024);
    final excess = _carrier(
      content: [
        for (var i = 0; i < 10; i++) _linked('BIBL {"unknown":"$long"}'),
      ],
    );
    expect(
      () => WordZoteroTransfer.prepareImport(excess),
      throwsFormatException,
    );
  });

  test(
    'invalid staged container surgery fails before publishing any paragraph',
    () {
      final source = _carrier(
        content: [
          _linked(_code('first')),
          WmlTable(
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(blocks: [_p('Cell')]),
                ],
              ),
            ],
          ),
        ],
      );
      final original = source.paragraphs.map((p) => p.text).toList();
      final plan = WordZoteroTransfer.prepareImport(source);
      final table = plan.document.sections.single.blocks
          .whereType<WmlTable>()
          .single;
      table.rows.single.cells.add(WmlTableCell(blocks: [_p('new')]));
      expect(() => plan.apply(), throwsStateError);
      expect(source.paragraphs.map((p) => p.text), original);
      expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
    },
  );

  test('publishes into covariant paragraph and run lists without widening', () {
    final source = _active();
    final paragraph = source.paragraphs.single;
    final blocks = <WmlParagraph>[paragraph];
    final inlines = List<WmlRun>.of(paragraph.inlines.whereType<WmlRun>());
    source.sections.single.blocks = blocks;
    paragraph.inlines = inlines;
    // Untouched empty note buckets need no mutation during publication.
    source.footnotes = const <WmlNote>[];
    source.endnotes = const <WmlNote>[];
    _export(source).apply();
    expect(source.sections.single.blocks, same(blocks));
    expect(paragraph.inlines, same(inlines));
    expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
    final imported = WordZoteroTransfer.prepareImport(source);
    _refreshImported(imported);
    imported.apply();
    expect(source.sections.single.blocks, same(blocks));
    expect(blocks, [same(paragraph)]);
    expect(paragraph.inlines, same(inlines));
    expect(WordZotero.fields(source).single.cachedText, '(Updated)');
  });

  test('incompatible final section refuses publication before any edit', () {
    final source = _active();
    final first = source.paragraphs.single;
    final originalText = first.text;
    final originalInlines = List<WmlInline>.of(first.inlines);
    final originalProperties = first.properties;
    final originalData = source.zoteroDocumentData;
    final cellParagraph = _p('Untouched cell');
    final table = WmlTable(
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: <WmlParagraph>[cellParagraph]),
          ],
        ),
      ],
    );
    final narrow = <WmlTable>[table];
    source.sections.add(WmlSection(blocks: narrow));
    final plan = _export(source);
    expect(() => plan.apply(), throwsUnsupportedError);
    expect(source.sections.first.blocks, [same(first)]);
    expect(source.sections.last.blocks, same(narrow));
    expect(narrow, [same(table)]);
    expect(first.text, originalText);
    expect(first.inlines, originalInlines);
    expect(first.properties, same(originalProperties));
    expect(cellParagraph.text, 'Untouched cell');
    expect(source.zoteroDocumentData, originalData);
    expect(WordZotero.fields(source), hasLength(1));
    plan.assertUnchanged();
  });

  for (final immutable in [false, true]) {
    for (final owner in ['blocks', 'inlines']) {
      test(
        '${immutable ? 'unmodifiable' : 'fixed-length'} $owner refuse before publication',
        () {
          final source = _active();
          final paragraph = source.paragraphs.single;
          if (owner == 'blocks') {
            source.sections.single.blocks = immutable
                ? List<WmlBlock>.unmodifiable([paragraph])
                : List<WmlBlock>.of([paragraph], growable: false);
          } else {
            paragraph.inlines = immutable
                ? List<WmlInline>.unmodifiable(paragraph.inlines)
                : List<WmlInline>.of(paragraph.inlines, growable: false);
          }
          final originalInlines = List<WmlInline>.of(paragraph.inlines);
          final originalProperties = paragraph.properties;
          final originalData = source.zoteroDocumentData;
          final plan = _export(source);
          expect(() => plan.apply(), throwsUnsupportedError);
          expect(source.sections.single.blocks, [same(paragraph)]);
          expect(paragraph.inlines, originalInlines);
          expect(paragraph.properties, same(originalProperties));
          expect(source.zoteroDocumentData, originalData);
          expect(WordZotero.fields(source), hasLength(1));
          plan.assertUnchanged();
        },
      );
    }
  }

  test('incompatible nested cell owner is checked before any publication', () {
    final paragraph = _linked(_code('first'));
    final cellParagraph = _p('Cell');
    final narrow = <WmlParagraph>[cellParagraph];
    final table = WmlTable(
      rows: [
        WmlTableRow(cells: [WmlTableCell(blocks: narrow)]),
      ],
    );
    final source = _carrier(content: [paragraph, table]);
    final originalText = paragraph.text;
    final plan = WordZoteroTransfer.prepareImport(source);
    final stagedTable = plan.document.sections.single.blocks
        .whereType<WmlTable>()
        .single;
    stagedTable.rows.single.cells.single.blocks.add(WmlTable());
    expect(() => plan.apply(), throwsUnsupportedError);
    expect(WordZoteroTransfer.isTransferDocument(source), isTrue);
    expect(paragraph.text, originalText);
    expect(narrow, [same(cellParagraph)]);
    expect(cellParagraph.text, 'Cell');
    plan.assertUnchanged();
  });
}
