import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:text-control-tests';

Uint8List _fixture({
  String paragraph = '',
  String run = '',
  String? body,
  String? styles,
  String prefix = 'w',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x">'
        '<$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:pPr>$paragraph</$prefix:pPr>'
                '<$prefix:r><$prefix:rPr>$run</$prefix:rPr>'
                '<$prefix:t>AVATAR</$prefix:t></$prefix:r></$prefix:p>'}'
        '<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);

XmlElement _paragraph(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!;

XmlElement _pPr(Uint8List bytes) =>
    _paragraph(bytes).firstChild('pPr', namespaceUri: _w)!;
XmlElement _rPr(Uint8List bytes) => _paragraph(
  bytes,
).firstChild('r', namespaceUri: _w)!.firstChild('rPr', namespaceUri: _w)!;
String? _val(XmlElement properties, String name) => properties
    .firstChild(name, namespaceUri: _w)
    ?.getAttribute('val', namespaceUri: _w);

void _run(WmlDocument document, Map<String, Object?> fields) =>
    native.applyStep(document, {'op': 'runFormat', 'paragraph': 0, ...fields});
void _format(WmlDocument document, Map<String, Object?> fields) => native
    .applyStep(document, {'op': 'paragraphFormat', 'paragraph': 0, ...fields});

void main() {
  for (final points in [0, 0.5, 1, 12, 1638]) {
    test('native kerning $points points persists as exact half-points', () {
      final document = _read(_fixture(run: '<w:sz w:val="22"/>'));
      _run(document, {'kerning': points});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_val(_rPr(bytes), 'kern'), '${(points * 2).toInt()}');
        final reread = _read(bytes);
        final props = reread.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties;
        expect(props.kerningHalfPoints, points * 2);
        expect(props.fontSizeHalfPoints, 22);
        expect(reread.paragraphs.single.text, 'AVATAR');
        bytes = WordSerializer().writeBytes(reread);
      }
    });
  }

  for (final value in [true, false]) {
    test('native proofing and hyphenation retain explicit $value', () {
      final document = _read(_fixture());
      _run(document, {'noProof': value});
      _format(document, {'suppressAutoHyphens': value});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_val(_rPr(bytes), 'noProof'), value ? '1' : '0');
        expect(_val(_pPr(bytes), 'suppressAutoHyphens'), value ? '1' : '0');
        final reread = _read(bytes);
        expect(reread.paragraphs.single.properties.suppressAutoHyphens, value);
        expect(
          reread.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .noProof,
          value,
        );
        bytes = WordSerializer().writeBytes(reread);
      }
    });
  }

  test('partial text controls split only the selected current text', () {
    final document = _read(_fixture());
    _run(document, {'start': 1, 'end': 4, 'noProof': true, 'kerning': 12});
    final runs = _read(
      WordSerializer().writeBytes(document),
    ).paragraphs.single.inlines.whereType<WmlRun>().toList();
    expect(runs.map((run) => run.text), ['A', 'VAT', 'AR']);
    expect(runs[1].properties.noProof, isTrue);
    expect(runs[1].properties.kerningHalfPoints, 24);
    expect(runs[0].properties.noProof, isNot(true));
    expect(runs[2].properties.noProof, isNot(true));
    expect(runs[0].properties.kerningHalfPoints, isNot(24));
    expect(runs[2].properties.kerningHalfPoints, isNot(24));
  });

  for (final value in <Object?>[
    -0.5,
    0.25,
    1638.5,
    double.nan,
    double.infinity,
    null,
    '12',
    true,
  ]) {
    test('invalid kerning $value fails before splitting or other writes', () {
      final document = _read(_fixture());
      final paragraph = document.paragraphs.single;
      final run = paragraph.inlines.whereType<WmlRun>().single;
      final before = WordSerializer().runPropertiesXml(run.properties);
      expect(
        () => _run(document, {
          'start': 1,
          'end': 4,
          'bold': true,
          'noProof': true,
          'kerning': value,
        }),
        throwsArgumentError,
      );
      expect(paragraph.inlines.whereType<WmlRun>().single, same(run));
      expect(WordSerializer().runPropertiesXml(run.properties), before);
    });
  }

  for (final value in <Object?>[null, 0, -1, 'true']) {
    test('proofing switches reject non-Boolean $value before mutation', () {
      final document = _read(_fixture());
      final paragraph = document.paragraphs.single;
      final run = paragraph.inlines.whereType<WmlRun>().single;
      final properties = paragraph.properties;
      final runBefore = WordSerializer().runPropertiesXml(run.properties);
      expect(
        () => _run(document, {'bold': true, 'noProof': value}),
        throwsArgumentError,
      );
      expect(WordSerializer().runPropertiesXml(run.properties), runBefore);
      expect(
        () => _format(document, {'before': 50, 'suppressAutoHyphens': value}),
        throwsArgumentError,
      );
      expect(paragraph.properties, same(properties));
    });
  }

  test('same inherited values become direct without pinning other styles', () {
    final document = _read(
      _fixture(
        paragraph: '<w:pStyle w:val="Body"/>',
        styles:
            '<w:style w:type="paragraph" w:styleId="Body">'
            '<w:name w:val="Body"/><w:pPr><w:suppressAutoHyphens w:val="0"/>'
            '</w:pPr><w:rPr><w:noProof w:val="0"/><w:kern w:val="24"/>'
            '<w:color w:val="112233"/></w:rPr></w:style>',
      ),
    );
    _run(document, {'noProof': false, 'kerning': 12});
    _format(document, {'suppressAutoHyphens': false});
    final bytes = WordSerializer().writeBytes(document);
    expect(_val(_rPr(bytes), 'noProof'), '0');
    expect(_val(_rPr(bytes), 'kern'), '24');
    expect(_val(_pPr(bytes), 'suppressAutoHyphens'), '0');
    expect(_rPr(bytes).firstChild('color', namespaceUri: _w), isNull);
    final package = OpcPackage.openBytes(bytes);
    final styles = package.getPart('/word/styles.xml')!;
    styles.writeText(
      styles
          .readText()
          .replaceAll('w:val="0"', 'w:val="1"')
          .replaceAll('w:val="24"', 'w:val="30"')
          .replaceAll('112233', '445566'),
    );
    final reopened = WordDeserializer().read(package);
    final paragraph = reopened.paragraphs.single;
    final props = paragraph.inlines.whereType<WmlRun>().single.properties;
    expect(props.noProof, isFalse);
    expect(props.kerningHalfPoints, 24);
    expect(paragraph.properties.suppressAutoHyphens, isFalse);
    expect(props.color, '445566');
  });

  for (final prefix in ['w', 'q']) {
    test('scalar writes retain $prefix aliases and independent XML metadata', () {
      final document = _read(
        _fixture(
          prefix: prefix,
          paragraph:
              '<$prefix:suppressAutoHyphens $prefix:val="1" '
              'x:val="foreign" x:keep="paragraph"><x:child/></$prefix:suppressAutoHyphens>'
              '<x:suppressAutoHyphens $prefix:val="1"/>'
              '<x:container><$prefix:suppressAutoHyphens $prefix:val="1"/></x:container>'
              '<$prefix:keepNext/>',
          run:
              '<$prefix:kern $prefix:val="28" x:val="foreign" x:keep="kern">'
              '<x:child/></$prefix:kern>'
              '<$prefix:noProof $prefix:val="1" x:val="foreign" x:keep="proof">'
              '<x:child/></$prefix:noProof>'
              '<x:kern $prefix:val="60"/><x:noProof $prefix:val="1"/>'
              '<x:container><$prefix:kern $prefix:val="60"/>'
              '<$prefix:noProof $prefix:val="1"/></x:container>',
        ),
      );
      _run(document, {'kerning': 0, 'noProof': false});
      _format(document, {'suppressAutoHyphens': false});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final rPr = _rPr(bytes);
        final pPr = _pPr(bytes);
        for (final (properties, name, marker) in [
          (rPr, 'kern', 'kern'),
          (rPr, 'noProof', 'proof'),
          (pPr, 'suppressAutoHyphens', 'paragraph'),
        ]) {
          final property = properties.firstChild(name, namespaceUri: _w)!;
          expect(property.getAttribute('val', namespaceUri: _w), '0');
          expect(property.getAttribute('val', namespaceUri: _x), 'foreign');
          expect(property.getAttribute('keep', namespaceUri: _x), marker);
          expect(property.firstChild('child', namespaceUri: _x), isNotNull);
          expect(properties.firstChild(name, namespaceUri: _x), isNotNull);
          expect(
            properties.firstChild('container', namespaceUri: _x),
            isNotNull,
          );
        }
        expect(pPr.firstChild('keepNext', namespaceUri: _w), isNotNull);
        final reread = _read(bytes);
        final paragraph = reread.paragraphs.single;
        final props = paragraph.inlines.whereType<WmlRun>().single.properties;
        expect(props.kerningHalfPoints, 0);
        expect(props.noProof, isFalse);
        expect(paragraph.properties.suppressAutoHyphens, isFalse);
        bytes = WordSerializer().writeBytes(reread);
      }
    });
  }

  test('foreign style controls and nested lookalikes stay opaque', () {
    final document = _read(
      _fixture(
        paragraph: '<w:pStyle w:val="Body"/>',
        styles:
            '<w:style w:type="paragraph" w:styleId="Body">'
            '<w:pPr><w:suppressAutoHyphens w:val="0"/>'
            '<x:suppressAutoHyphens w:val="1"/>'
            '<x:container><w:suppressAutoHyphens/></x:container></w:pPr>'
            '<w:rPr><w:noProof w:val="0"/><w:kern w:val="24"/>'
            '<x:noProof/><x:kern w:val="60"/><x:container>'
            '<w:noProof/><w:kern w:val="60"/></x:container></w:rPr>'
            '</w:style>',
      ),
    );
    final paragraph = document.paragraphs.single;
    final props = paragraph.inlines.whereType<WmlRun>().single.properties;
    expect(props.noProof, isFalse);
    expect(props.kerningHalfPoints, 24);
    expect(paragraph.properties.suppressAutoHyphens, isFalse);
  });

  for (final enabled in [true, false]) {
    for (final inherited in [true, false]) {
      test(
        'native values win over earlier foreign attributes ($enabled, inherited=$inherited)',
        () {
          final value = enabled ? '1' : '0';
          final other = enabled ? '0' : '1';
          final paragraph =
              '<w:suppressAutoHyphens x:val="$other" w:val="$value"/>';
          final run =
              '<w:noProof x:val="$other" w:val="$value"/>'
              '<w:kern x:val="60" w:val="24"/>';
          final document = _read(
            _fixture(
              paragraph: inherited ? '<w:pStyle w:val="Body"/>' : paragraph,
              run: inherited ? '' : run,
              styles: inherited
                  ? '<w:style w:type="paragraph" w:styleId="Body">'
                        '<w:pPr>$paragraph</w:pPr><w:rPr>$run</w:rPr></w:style>'
                  : null,
            ),
          );
          final target = document.paragraphs.single;
          final props = target.inlines.whereType<WmlRun>().single.properties;
          expect(props.noProof, enabled);
          expect(props.kerningHalfPoints, 24);
          expect(target.properties.suppressAutoHyphens, enabled);
        },
      );
    }
  }

  test('empty direct Boolean markers override inherited explicit false', () {
    final document = _read(
      _fixture(
        paragraph: '<w:pStyle w:val="Body"/><w:suppressAutoHyphens/>',
        run: '<w:noProof/>',
        styles:
            '<w:style w:type="paragraph" w:styleId="Body">'
            '<w:pPr><w:suppressAutoHyphens w:val="0"/></w:pPr>'
            '<w:rPr><w:noProof w:val="0"/></w:rPr></w:style>',
      ),
    );
    final paragraph = document.paragraphs.single;
    expect(paragraph.properties.suppressAutoHyphens, isTrue);
    expect(
      paragraph.inlines.whereType<WmlRun>().single.properties.noProof,
      isTrue,
    );
  });

  for (final name in ['kern', 'noProof', 'suppressAutoHyphens']) {
    test('native $name in markup alternatives refuses before mutation', () {
      final alternative =
          '<mc:AlternateContent xmlns:mc="${OfficeNamespaces.mc}">'
          '<mc:Choice Requires="x"><w:$name w:val="1"/></mc:Choice>'
          '<mc:Fallback><w:$name w:val="0"/></mc:Fallback></mc:AlternateContent>';
      final document = _read(
        _fixture(
          paragraph: name == 'suppressAutoHyphens' ? alternative : '',
          run: name == 'suppressAutoHyphens' ? '' : alternative,
        ),
      );
      final paragraph = document.paragraphs.single;
      final props = paragraph.properties;
      final run = paragraph.inlines.whereType<WmlRun>().single;
      final snapshot = WordSerializer().runPropertiesXml(run.properties);
      expect(
        () => name == 'suppressAutoHyphens'
            ? _format(document, {'before': 50, 'suppressAutoHyphens': false})
            : _run(document, {
                'start': 1,
                'bold': true,
                'kerning': 12,
                'noProof': false,
              }),
        throwsUnsupportedError,
      );
      expect(paragraph.properties, same(props));
      expect(paragraph.inlines.whereType<WmlRun>().single, same(run));
      expect(WordSerializer().runPropertiesXml(run.properties), snapshot);
    });
  }

  for (final name in ['kern', 'noProof']) {
    test('duplicate $name in a later run refuses before any run mutates', () {
      final document = _read(
        _fixture(
          body:
              '<w:p><w:r><w:t>First</w:t></w:r><w:r><w:rPr>'
              '<w:$name w:val="1"/><w:$name w:val="0"/>'
              '</w:rPr><w:t>Second</w:t></w:r></w:p>',
        ),
      );
      final paragraph = document.paragraphs.single;
      final runs = paragraph.inlines.whereType<WmlRun>().toList();
      final snapshots = runs
          .map((run) => WordSerializer().runPropertiesXml(run.properties))
          .toList();
      expect(
        () => _run(document, {
          'start': 1,
          'bold': true,
          'kerning': 12,
          'noProof': false,
        }),
        throwsUnsupportedError,
      );
      expect(paragraph.inlines.whereType<WmlRun>(), runs);
      expect(
        runs.map((run) => WordSerializer().runPropertiesXml(run.properties)),
        snapshots,
      );
    });
  }

  test('duplicate paragraph suppression refuses before publishing a copy', () {
    final document = _read(
      _fixture(
        paragraph: '<w:suppressAutoHyphens/><w:suppressAutoHyphens w:val="0"/>',
      ),
    );
    final properties = document.paragraphs.single.properties;
    expect(
      () => _format(document, {'before': 50, 'suppressAutoHyphens': false}),
      throwsUnsupportedError,
    );
    expect(document.paragraphs.single.properties, same(properties));
  });

  for (final name in ['kern', 'noProof']) {
    test(
      'source preflight includes runs reached by citation normalization ($name)',
      () {
        final document = WmlDocument.empty();
        final paragraph = document.paragraphs.single;
        final citation = ZoteroCitation(
          citationId: 'text-controls',
          plainCitation: 'Book 12',
          items: [
            ZoteroCitationItem.fromCsl(
              itemData: {'type': 'book', 'title': 'Book'},
              uris: ['http://zotero.org/users/42/items/ABCD1234'],
            ),
          ],
        );
        final formatted = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
        WordZotero.insertNativeCitation(
          paragraph,
          instruction: citation.fieldInstruction,
          text: formatted.plainText,
          formattedText: formatted,
          index: 0,
        );
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        final tail = runs.singleWhere((run) => run.text == ' 12');
        tail.properties.sourcePropertiesXml =
            '<w:rPr xmlns:w="$_w">'
            '<w:$name w:val="0"/><w:$name w:val="1"/></w:rPr>';
        expect(WmlRunEdit.normalizeRange(paragraph, 1, 2), (start: 0, end: 7));
        final inlines = List<WmlInline>.of(paragraph.inlines);
        final snapshots = runs
            .map((run) => WordSerializer().runPropertiesXml(run.properties))
            .toList();
        expect(
          () => _run(document, {
            'start': 1,
            'end': 2,
            'bold': true,
            'kerning': 12,
            'noProof': false,
          }),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines, inlines);
        expect(
          runs.map((run) => WordSerializer().runPropertiesXml(run.properties)),
          snapshots,
        );
      },
    );
  }

  test(
    'kerning threshold controls native glyph eligibility after reopening',
    () {
      for (final (threshold, expected) in [
        (0, false),
        (10, true),
        (11, true),
        (12, false),
      ]) {
        final document = _read(_fixture(run: '<w:sz w:val="22"/>'));
        _run(document, {'kerning': threshold});
        final reopened = _read(WordSerializer().writeBytes(document));
        final glyphs = WordLayoutEngine(font: null)
            .layout(reopened)
            .pages
            .expand((page) => page.lines)
            .expand((line) => line.glyphs);
        expect(glyphs, isNotEmpty);
        expect(glyphs.map((glyph) => glyph.kerning), everyElement(expected));
      }
    },
  );

  test(
    'hyphenation suppression affects layout while retaining document settings',
    () {
      final document = WmlDocument.empty(text: 'Silbentrennung')
        ..proofingLanguage = 'de-DE'
        ..autoHyphenation = true;
      document.sections.single
        ..pageSize = const WmlPageSize(width: 80, height: 180)
        ..margins = const WmlPageMargins(
          left: 10,
          right: 10,
          top: 10,
          bottom: 10,
        );
      for (final suppressed in [true, false]) {
        _format(document, {'suppressAutoHyphens': suppressed});
        final reopened = _read(WordSerializer().writeBytes(document));
        final hasHyphens = WordLayoutEngine(font: null)
            .layout(reopened)
            .pages
            .expand((page) => page.lines)
            .expand((line) => line.glyphs)
            .any((glyph) => glyph.glyph.isDiscretionaryHyphen);
        expect(hasHyphens, !suppressed);
        expect(reopened.autoHyphenation, isTrue);
        expect(reopened.paragraphs.single.text, 'Silbentrennung');
      }
      document.autoHyphenation = false;
      _format(document, {'suppressAutoHyphens': false});
      expect(
        WordLayoutEngine(font: null)
            .layout(document)
            .pages
            .expand((page) => page.lines)
            .expand((line) => line.glyphs)
            .any((glyph) => glyph.glyph.isDiscretionaryHyphen),
        isFalse,
      );
    },
  );

  test(
    'a later invalid control leaves session bytes and prior edits unpublished',
    () async {
      final bytes = _fixture();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      final plan = OfficeMacro(
        name: 'Atomic text controls',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 0, 'noProof': true},
          ),
          OfficeMacroStep(
            tool: 'docx.paragraphFormat',
            arguments: {'paragraph': 0, 'suppressAutoHyphens': true},
          ),
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 0, 'kerning': 0.25},
          ),
        ],
      );
      await expectLater(
        session.run(plan),
        throwsA(
          isA<OfficeMacroException>().having(
            (error) => error.stepIndex,
            'stepIndex',
            2,
          ),
        ),
      );
      expect(session.bytes, bytes);
    },
  );
}
