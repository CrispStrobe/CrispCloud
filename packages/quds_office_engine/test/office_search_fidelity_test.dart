// Independent authored package graphs exercise the real bounded search reader.
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _zip(Map<String, String> parts) {
  final archive = ZipWriter();
  for (final part in parts.entries) {
    archive.addFile(part.key, utf8.encode(part.value));
  }
  return archive.close();
}

String _relationships(String body) =>
    '<Relationships xmlns="$_pr">$body</Relationships>';
String _rel(String id, String kind, String target, {bool external = false}) =>
    '<Relationship Id="$id" Type="$_r/$kind" Target="$target"${external ? ' TargetMode="External"' : ''}/>';
String _root(String target) =>
    _relationships(_rel('main', 'officeDocument', target));
String _word(String body) =>
    '<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>$body</w:body></w:document>';
String _paragraph(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';
String _note(String kind, String text, {String id = '7'}) =>
    '<w:${kind}s xmlns:w="$_w"><w:$kind w:id="$id">${_paragraph(text)}</w:$kind></w:${kind}s>';
String _sheet(String cells) =>
    '<s:worksheet xmlns:s="$_s"><s:sheetData><s:row r="1">$cells</s:row></s:sheetData></s:worksheet>';
String _slide(String text) =>
    '<p:sld xmlns:p="$_p" xmlns:a="$_a"><a:p><a:r><a:t>$text</a:t></a:r></a:p></p:sld>';
Future<String> _search(
  Map<String, String> parts,
  String name, {
  int limit = 65536,
}) => officeSearchText(_zip(parts), name, limit);

void main() {
  test(
    'search recognizes supported Office variants and excludes binary or disguised names',
    () {
      for (final extension in [
        'DOCX',
        'docm',
        'xlsx',
        'xlsm',
        'pptx',
        'pptm',
        'odt',
        'ods',
        'odp',
      ]) {
        expect(isSearchableOfficeDocument('Report.$extension'), isTrue);
      }
      for (final name in [
        'report.doc',
        'report.xls',
        'report.ppt',
        'report.docx.exe',
        'report.txt',
      ]) {
        expect(isSearchableOfficeDocument(name), isFalse);
      }
    },
  );

  test(
    'DOCX searches relocated referenced stories and note bodies within an exact byte budget',
    () async {
      final parts = {
        '_rels/.rels': _root('office/text/main.xml'),
        'office/text/main.xml': _word(
          '<w:p><w:r><w:t>Split</w:t></w:r><w:r><w:t>word</w:t><w:tab/><w:t>Body</w:t><w:br/><w:t>Next</w:t>'
          '<w:footnoteReference w:id="7"/><w:endnoteReference w:id="7"/></w:r></w:p>'
          '<w:sectPr><w:headerReference w:type="default" r:id="h"/><w:headerReference w:type="first" r:id="h"/>'
          '<w:footerReference w:type="default" r:id="f"/>'
          '<w:sectPrChange w:id="1"><w:sectPr><w:headerReference w:type="default" r:id="old"/></w:sectPr></w:sectPrChange></w:sectPr>',
        ),
        'office/text/_rels/main.xml.rels': _relationships(
          _rel('h', 'header', '../stories/header.xml') +
              _rel('f', 'footer', '../stories/footer.xml') +
              _rel('old', 'header', '../stories/obsolete.xml') +
              _rel('unused', 'header', '../stories/unreferenced.xml') +
              _rel('foot', 'footnotes', '../notes/foot.xml') +
              _rel('end', 'endnotes', '../notes/end.xml'),
        ),
        'office/stories/header.xml':
            '<w:hdr xmlns:w="$_w">${_paragraph('Header')}</w:hdr>',
        'office/stories/footer.xml':
            '<w:ftr xmlns:w="$_w">${_paragraph('Footer')}</w:ftr>',
        'office/notes/foot.xml':
            '<w:footnotes xmlns:w="$_w">'
            '<w:footnote w:id="7">${_paragraph('Footnote')}${_paragraph('Second paragraph')}</w:footnote>'
            '<w:footnote w:id="99">${_paragraph('Unreferenced note')}</w:footnote>'
            '<w:footnote w:id="-1" w:type="separator">${_paragraph('Separator text')}</w:footnote></w:footnotes>',
        'office/notes/end.xml': _note('endnote', 'Endnote'),
        'office/stories/obsolete.xml': '<invalid obsolete XML',
        'office/stories/unreferenced.xml': '<invalid unreferenced XML',
        'word/document.xml': _word(_paragraph('Wrong canonical main')),
        'customXml/huge.xml': 'x' * 100000,
        'word/vbaProject.bin': 'Macros are not document text',
      };
      const readParts = {
        '_rels/.rels',
        'office/text/main.xml',
        'office/text/_rels/main.xml.rels',
        'office/stories/header.xml',
        'office/stories/footer.xml',
        'office/notes/foot.xml',
        'office/notes/end.xml',
      };
      final budget = parts.entries
          .where((entry) => readParts.contains(entry.key))
          .fold<int>(
            0,
            (size, entry) => size + utf8.encode(entry.value).length,
          );
      expect(
        await _search(parts, 'notes.docm', limit: budget),
        'Splitword\tBody\nNext\nHeader\nFooter\nFootnote\nSecond paragraph\nEndnote',
      );
    },
  );

  test(
    'external escaping and encoded-backslash story targets never select fallback XML',
    () async {
      final body = _word(
        '<w:p><w:r><w:t>Visible body</w:t><w:footnoteReference w:id="7"/></w:r></w:p>'
        '<w:sectPr><w:headerReference w:type="default" r:id="escape"/><w:headerReference w:type="first" r:id="encoded"/>'
        '<w:footerReference w:type="default" r:id="network"/></w:sectPr>',
      );
      expect(
        await _search({
          'word/document.xml': body,
          'word/_rels/document.xml.rels': _relationships(
            _rel(
                  'foot',
                  'footnotes',
                  'https://example.invalid/notes.xml',
                  external: true,
                ) +
                _rel('escape', 'header', '../../outside.xml') +
                _rel('encoded', 'header', '%5Coutside.xml') +
                _rel('network', 'footer', 'https://example.invalid/footer.xml'),
          ),
          'outside.xml':
              '<w:hdr xmlns:w="$_w">${_paragraph('Wrong escaped header')}</w:hdr>',
          'word/footnotes.xml': _note('footnote', 'Wrong fallback note'),
        }, 'excluded.docx'),
        'Visible body',
      );
    },
  );

  test(
    'a declared external main part cannot fall back to an unrelated canonical document',
    () async {
      expect(
        await _search({
          '_rels/.rels': _relationships(
            _rel(
              'main',
              'officeDocument',
              'https://example.invalid/document.xml',
              external: true,
            ),
          ),
          'word/document.xml': _word(_paragraph('Unrelated canonical file')),
        }, 'external.docx'),
        isEmpty,
      );
    },
  );

  test(
    'package-root main and sibling relationships resolve for content search',
    () async {
      expect(
        await _search({
          '_rels/.rels': _root('main.xml'),
          'main.xml': _word(
            '<w:p><w:r><w:t>Root body</w:t><w:footnoteReference w:id="7"/></w:r></w:p>',
          ),
          '_rels/main.xml.rels': _relationships(
            _rel('n', 'footnotes', 'notes.xml'),
          ),
          'notes.xml': _note('footnote', 'Root note'),
        }, 'root.docx'),
        'Root body\nRoot note',
      );
    },
  );

  test(
    'canonical DOCX fallback retains referenced notes and old text-only fixture support',
    () async {
      expect(
        await _search({
          'word/document.xml': _word(
            '<w:p><w:r><w:t>Canonical</w:t><w:footnoteReference w:id="7"/></w:r></w:p>',
          ),
          'word/footnotes.xml': _note('footnote', 'Fallback note'),
        }, 'fallback.docx'),
        'Canonical\nFallback note',
      );
      expect(
        await _search({
          'word/document.xml': '<document><text>Grüße 東京</text></document>',
        }, 'text.docx'),
        'Grüße 東京',
      );
    },
  );

  test(
    'XLSX uses workbook order and names with relocated shared strings and only referenced cells',
    () async {
      expect(
        await _search({
          '_rels/.rels': _root('book/catalog.xml'),
          'book/catalog.xml':
              '<s:workbook xmlns:s="$_s" xmlns:alias="$_r"><s:sheets>'
              '<s:sheet name="Forecast" sheetId="9" alias:id="b"/><s:sheet name="Archive" sheetId="2" alias:id="a"/>'
              '<s:sheet name="Empty" sheetId="8" alias:id="empty"/><s:sheet name="External" sheetId="3" alias:id="external"/>'
              '</s:sheets></s:workbook>',
          'book/_rels/catalog.xml.rels': _relationships(
            _rel('a', 'worksheet', '/rows/a.xml') +
                _rel('b', 'worksheet', '../rows/b.xml') +
                _rel('empty', 'worksheet', '../rows/empty.xml') +
                _rel('strings', 'sharedStrings', '../strings/values.xml') +
                _rel(
                  'external',
                  'worksheet',
                  'https://example.invalid/sheet.xml',
                  external: true,
                ),
          ),
          'rows/b.xml': _sheet(
            '<s:c r="A1" t="s"><s:v>1</s:v></s:c><s:c r="B1" t="inlineStr"><s:is><s:r><s:t>Inline </s:t></s:r><s:r><s:t>cell</s:t></s:r></s:is></s:c><s:c r="C1"><s:v>42</s:v></s:c>',
          ),
          'rows/a.xml': _sheet('<s:c r="A1" t="s"><s:v>2</s:v></s:c>'),
          'rows/empty.xml': _sheet(''),
          'strings/values.xml':
              '<s:sst xmlns:s="$_s"><s:si><s:t>Unreferenced string</s:t></s:si><s:si><s:r><s:t>Joined</s:t></s:r><s:r><s:t>value</s:t></s:r></s:si><s:si><s:t>Second</s:t></s:si></s:sst>',
          'xl/worksheets/sheet1.xml': _sheet(
            '<s:c t="inlineStr"><s:is><s:t>Orphan worksheet</s:t></s:is></s:c>',
          ),
          'xl/sharedStrings.xml': '<invalid unrelated canonical strings',
        }, 'ordered.xlsm'),
        'Forecast\nJoinedvalue\nInline cell\n42\nArchive\nSecond\nEmpty',
      );
    },
  );

  test('missing workbook fallback sorts numbered sheets naturally', () async {
    expect(
      await _search({
        'xl/worksheets/sheet10.xml': _sheet(
          '<s:c t="inlineStr"><s:is><s:t>Ten</s:t></s:is></s:c>',
        ),
        'xl/worksheets/sheet2.xml': _sheet('<s:c t="s"><s:v>0</s:v></s:c>'),
        'xl/sharedStrings.xml':
            '<s:sst xmlns:s="$_s"><s:si><s:t>Two</s:t></s:si></s:sst>',
        'xl/worksheets/orphan.xml': '<invalid unrelated XML',
      }, 'fallback.xlsx'),
      'Two\nTen',
    );
  });

  test(
    'declared workbook with unusable relationships never scans orphan worksheets',
    () async {
      expect(
        await _search({
          'xl/workbook.xml':
              '<s:workbook xmlns:s="$_s" xmlns:r="$_r"><s:sheets><s:sheet name="Hidden" sheetId="1" r:id="bad"/></s:sheets></s:workbook>',
          'xl/_rels/workbook.xml.rels': _relationships(
            _rel('bad', 'worksheet', '../../outside.xml'),
          ),
          'outside.xml': _sheet(
            '<s:c t="inlineStr"><s:is><s:t>Escaped text</s:t></s:is></s:c>',
          ),
          'xl/worksheets/sheet1.xml': _sheet(
            '<s:c t="inlineStr"><s:is><s:t>Orphan text</s:t></s:is></s:c>',
          ),
        }, 'missing.xlsx'),
        isEmpty,
      );
    },
  );

  test('presentation order and owning slide notes select relocated parts', () async {
    expect(
      await _search({
        '_rels/.rels': _root('deck/catalog.xml'),
        'deck/catalog.xml':
            '<p:presentation xmlns:p="$_p" xmlns:r="$_r"><p:sldIdLst><p:sldId id="260" r:id="b"/><p:sldId id="256" r:id="a"/></p:sldIdLst></p:presentation>',
        'deck/_rels/catalog.xml.rels': _relationships(
          _rel('a', 'slide', '../slides/a.xml') +
              _rel('b', 'slide', '../slides/b.xml'),
        ),
        'slides/b.xml': _slide('First by presentation order'),
        'slides/a.xml': _slide('Second by presentation order'),
        'slides/_rels/b.xml.rels': _relationships(
          _rel('notes', 'notesSlide', '../notes/first.xml') +
              _rel(
                'external',
                'notesSlide',
                'https://example.invalid/notes.xml',
                external: true,
              ),
        ),
        'slides/_rels/a.xml.rels': _relationships(
          _rel('duplicate', 'notesSlide', '../notes/first.xml'),
        ),
        'notes/first.xml':
            '<p:notes xmlns:p="$_p" xmlns:a="$_a"><a:p><a:r><a:t>Speaker notes</a:t></a:r></a:p></p:notes>',
        'ppt/slides/slide1.xml': _slide('Orphan slide'),
        'ppt/notesSlides/notesSlide1.xml': '<invalid orphan notes',
      }, 'notes.pptm'),
      'First by presentation order\nSpeaker notes\nSecond by presentation order',
    );
  });

  test(
    'missing presentation fallback sorts numbered slides without guessing notes',
    () async {
      expect(
        await _search({
          'ppt/slides/slide10.xml': _slide('Ten'),
          'ppt/slides/slide2.xml': _slide('Two'),
          'ppt/notesSlides/notesSlide2.xml': '<invalid orphan notes',
        }, 'fallback.pptx'),
        'Two\nTen',
      );
    },
  );

  test('ODF extraction is restricted to content.xml', () async {
    for (final extension in ['odt', 'ods', 'odp']) {
      expect(
        await _search({
          'content.xml': '<document><text>Hello ODF</text></document>',
          'word/document.xml': _word(_paragraph('Unrelated Word text')),
          'styles.xml': '<invalid unrelated styles',
        }, 'document.$extension'),
        'Hello ODF',
      );
    }
  });

  test(
    'the cumulative budget includes note reads and rejects exhaustion',
    () async {
      final parts = {
        'word/document.xml': _word(
          '<w:p><w:r><w:t>Body</w:t><w:footnoteReference w:id="7"/></w:r></w:p>',
        ),
        'word/footnotes.xml': _note('footnote', 'Note body'),
      };
      final mainBytes = utf8.encode(parts['word/document.xml']!).length;
      for (final limit in [mainBytes, mainBytes + 1]) {
        await expectLater(
          _search(parts, 'limited.docx', limit: limit),
          throwsA(isA<FormatException>()),
        );
      }
      final total = parts.values.fold<int>(
        0,
        (size, text) => size + utf8.encode(text).length,
      );
      expect(
        await _search(parts, 'limited.docx', limit: total),
        'Body\nNote body',
      );
    },
  );

  test(
    'malformed selected XML and corrupt archives fail without reading unrelated XML',
    () async {
      await expectLater(
        _search({'word/document.xml': '<document>'}, 'malformed.docx'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        officeSearchText(Uint8List.fromList([1, 2, 3]), 'corrupt.docx', 1024),
        throwsA(isA<FormatException>()),
      );
      expect(
        await _search({
          'word/document.xml': _word(_paragraph('Still usable')),
          'customXml/unrelated.xml': '<broken',
        }, 'valid.docx'),
        'Still usable',
      );
    },
  );

  test(
    'escaped archive entry names cannot satisfy canonical Office parts',
    () async {
      expect(
        await _search({
          '../word/document.xml': _word(_paragraph('Escaping archive text')),
        }, 'escaped.docx'),
        isEmpty,
      );
    },
  );

  test(
    'shared-string expansion is bounded before concatenating repeated cells',
    () async {
      final value = 'é' * 4096;
      final parts = {
        'xl/worksheets/sheet1.xml': _sheet(
          List.generate(
            40,
            (index) => '<s:c r="A${index + 1}" t="s"><s:v>0</s:v></s:c>',
          ).join(),
        ),
        'xl/sharedStrings.xml':
            '<s:sst xmlns:s="$_s"><s:si><s:t>$value</s:t></s:si></s:sst>',
      };
      final inputBytes = parts.values.fold<int>(
        0,
        (size, text) => size + utf8.encode(text).length,
      );
      expect(inputBytes, lessThan(16000));
      await expectLater(
        _search(parts, 'repeated.xlsx', limit: 16000),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await _search(parts, 'repeated.xlsx', limit: 400000)).split('\n'),
        List.filled(40, value),
      );
    },
  );

  test(
    'Strict OOXML namespaces retain Word stories and workbook or presentation references',
    () async {
      Map<String, String> strict(Map<String, String> parts) => {
        for (final entry in parts.entries)
          entry.key: entry.value
              .replaceAll(
                _r,
                'http://purl.oclc.org/ooxml/officeDocument/relationships',
              )
              .replaceAll(
                _w,
                'http://purl.oclc.org/ooxml/wordprocessingml/main',
              )
              .replaceAll(_s, 'http://purl.oclc.org/ooxml/spreadsheetml/main')
              .replaceAll(_p, 'http://purl.oclc.org/ooxml/presentationml/main')
              .replaceAll(_a, 'http://purl.oclc.org/ooxml/drawingml/main'),
      };
      expect(
        await _search(
          strict({
            '_rels/.rels': _root('main.xml'),
            'main.xml': _word(
              '<w:p><w:r><w:t>Strict body</w:t><w:footnoteReference w:id="7"/></w:r></w:p>'
              '<w:sectPr><w:headerReference w:type="default" r:id="h"/></w:sectPr>',
            ),
            '_rels/main.xml.rels': _relationships(
              _rel('h', 'header', 'header.xml') +
                  _rel('n', 'footnotes', 'notes.xml'),
            ),
            'header.xml':
                '<w:hdr xmlns:w="$_w">${_paragraph('Strict header')}</w:hdr>',
            'notes.xml': _note('footnote', 'Strict note'),
          }),
          'strict.docx',
        ),
        'Strict body\nStrict header\nStrict note',
      );
      expect(
        await _search(
          strict({
            '_rels/.rels': _root('catalog.xml'),
            'catalog.xml':
                '<s:workbook xmlns:s="$_s" xmlns:r="$_r"><s:sheets><s:sheet name="Strict sheet" sheetId="1" r:id="sheet"/></s:sheets></s:workbook>',
            '_rels/catalog.xml.rels': _relationships(
              _rel('sheet', 'worksheet', 'sheet.xml'),
            ),
            'sheet.xml': _sheet(
              '<s:c t="inlineStr"><s:is><s:t>Strict cell</s:t></s:is></s:c>',
            ),
          }),
          'strict.xlsx',
        ),
        'Strict sheet\nStrict cell',
      );
      expect(
        await _search(
          strict({
            '_rels/.rels': _root('presentation.xml'),
            'presentation.xml':
                '<p:presentation xmlns:p="$_p" xmlns:r="$_r"><p:sldIdLst><p:sldId id="256" r:id="slide"/></p:sldIdLst></p:presentation>',
            '_rels/presentation.xml.rels': _relationships(
              _rel('slide', 'slide', 'slide.xml'),
            ),
            'slide.xml': _slide('Strict slide'),
          }),
          'strict.pptx',
        ),
        'Strict slide',
      );
    },
  );

  test(
    'search retains whitespace-only runs between visible Word runs',
    () async {
      expect(
        await _search({
          'word/document.xml': _word(
            '<w:p><w:r><w:t>Left</w:t></w:r><w:r><w:t> </w:t></w:r>'
            '<w:r><w:t>Right</w:t></w:r></w:p>',
          ),
        }, 'space.docx'),
        'Left Right',
      );
    },
  );

  test(
    'encoded main relationship selects the exact OPC key without aliasing',
    () async {
      expect(
        await _search({
          '_rels/.rels': _root('content/manuscript%20draft.xml'),
          'content/manuscript%20draft.xml': _word(
            _paragraph('Exact native key'),
          ),
          'content/manuscript draft.xml': _word(
            _paragraph('Wrong decoded alias'),
          ),
          'word/document.xml': _word(_paragraph('Wrong canonical fallback')),
        }, 'encoded.docx'),
        'Exact native key',
      );
    },
  );

  test(
    'foreign and ambiguous main graphs cannot select canonical fallback text',
    () async {
      for (final relationships in [
        '<Relationships xmlns="urn:foreign">'
            '${_rel('main', 'officeDocument', 'other.xml')}</Relationships>',
        _relationships(
          _rel('one', 'officeDocument', 'one.xml') +
              _rel('two', 'officeDocument', 'two.xml'),
        ),
        _relationships(
          _rel('same', 'officeDocument', 'one.xml') +
              _rel('same', 'officeDocument', 'two.xml'),
        ),
      ]) {
        await expectLater(
          _search({
            '_rels/.rels': relationships,
            'word/document.xml': _word(_paragraph('Unrelated canonical text')),
          }, 'ambiguous.docx'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'duplicate native ZIP members reject rather than selecting an alias',
    () async {
      final zip = ZipWriter()
        ..addFile('word/document.xml', utf8.encode(_word(_paragraph('First'))))
        ..addFile(
          'word/document.xml',
          utf8.encode(_word(_paragraph('Second'))),
        );
      await expectLater(
        officeSearchText(zip.close(), 'duplicate.docx', 65536),
        throwsFormatException,
      );
    },
  );

  test('entry-count budget is enforced before reading selected XML', () async {
    final bytes = _zip({
      'word/document.xml': _word(_paragraph('Visible')),
      'customXml/unused1.xml': 'Not selected',
      'customXml/unused2.xml': 'Not selected',
    });
    await expectLater(
      officeSearchText(bytes, 'many.docx', 65536, maxEntries: 2),
      throwsA(isA<OfficeSearchLimitException>()),
    );
    expect(
      await officeSearchText(bytes, 'many.docx', 65536, maxEntries: 3),
      'Visible',
    );
  });

  test(
    'malformed selected DEFLATE data reports a public format error',
    () async {
      final bytes = _zip({'word/document.xml': _word(_paragraph('Visible'))});
      expect(await officeSearchText(bytes, 'valid.docx', 65536), 'Visible');
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(8, Endian.little), 8);
      final payloadOffset =
          30 +
          data.getUint16(26, Endian.little) +
          data.getUint16(28, Endian.little);
      // BFINAL=1 and the reserved BTYPE=3 must fail in the actual inflater.
      bytes[payloadOffset] = 0x07;
      await expectLater(
        officeSearchText(bytes, 'corrupt-deflate.docx', 65536),
        throwsFormatException,
      );
    },
  );

  test(
    'actual inflation is capped even when ZIP declared sizes are tiny',
    () async {
      final value = 'x' * 20000;
      final bytes = _zip({'word/document.xml': _word(_paragraph(value))});
      expect(await officeSearchText(bytes, 'large.docx', 30000), value);
      final data = ByteData.sublistView(bytes);
      var central = -1;
      for (var offset = 0; offset <= bytes.length - 4; offset++) {
        if (data.getUint32(offset, Endian.little) == 0x02014b50) {
          central = offset;
          break;
        }
      }
      expect(central, greaterThanOrEqualTo(0));
      data.setUint32(22, 1, Endian.little);
      data.setUint32(central + 24, 1, Endian.little);
      await expectLater(
        officeSearchText(bytes, 'misleading.docx', 1024),
        throwsA(isA<OfficeSearchLimitException>()),
      );
    },
  );

  test('ZIP path aliases cannot satisfy canonical part selection', () async {
    for (final alias in [
      '/word/document.xml',
      'word/../word/document.xml',
      r'word\document.xml',
    ]) {
      expect(
        await _search({alias: _word(_paragraph('Aliased text'))}, 'alias.docx'),
        isEmpty,
        reason: alias,
      );
    }
  });

  test(
    'repeated UTF-8 output includes separators in its exact cumulative limit',
    () async {
      final value = 'é' * 128;
      final parts = {
        'xl/worksheets/sheet1.xml': _sheet(
          List.generate(32, (index) => '<s:c t="s"><s:v>0</s:v></s:c>').join(),
        ),
        'xl/sharedStrings.xml':
            '<s:sst xmlns:s="$_s"><s:si><s:t>$value</s:t></s:si></s:sst>',
      };
      final expected = List.filled(32, value).join('\n');
      final limit = utf8.encode(expected).length;
      expect(await _search(parts, 'exact.xlsx', limit: limit), expected);
      await expectLater(
        _search(parts, 'exact.xlsx', limit: limit - 1),
        throwsA(isA<OfficeSearchLimitException>()),
      );
    },
  );

  test(
    'invalid limits reject and unsupported extensions do not parse ZIP input',
    () async {
      final empty = Uint8List(0);
      await expectLater(
        officeSearchText(empty, 'document.docx', -1),
        throwsArgumentError,
      );
      await expectLater(
        officeSearchText(empty, 'document.docx', 1, maxEntries: -1),
        throwsArgumentError,
      );
      await expectLater(
        officeSearchText(empty, 'document.docx', 1, maxXmlDepth: 0),
        throwsArgumentError,
      );
      expect(await officeSearchText(empty, 'document.txt', 1), isEmpty);
    },
  );
}
