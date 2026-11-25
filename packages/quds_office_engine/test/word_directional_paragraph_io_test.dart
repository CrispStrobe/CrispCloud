import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _extension = 'urn:quds:test:directional-properties';

// These are authored OOXML fixtures, independent of the native serializer.
// ECMA-376-1 17.3.1.12/17.18.44 and Part 4 14.3.1.2/14.11.2 define
// start/end and their transitional left/right aliases relative to bidi.
OpcPackage _fixture(String properties, {String styles = '<w:docDefaults/>'}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Directional marker')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" '
        'xmlns:a="${OfficeNamespaces.w}" xmlns:e="$_extension">'
        '<w:body><w:p><w:pPr>$properties</w:pPr>'
        '<w:r><w:t>Directional marker</w:t></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText(
        '<w:styles xmlns:w="${OfficeNamespaces.w}" '
        'xmlns:a="${OfficeNamespaces.w}" xmlns:e="$_extension">'
        '$styles</w:styles>',
      );
  return package;
}

XmlElement _savedProperties(OpcPackage package) => XmlDocument.parse(
  package.getPart('/word/document.xml')!.readText(),
).root!.firstChild('body')!.firstChild('p')!.firstChild('pPr')!;

XmlElement? _native(XmlElement properties, String name) => properties
    .childrenNamed(name, namespaceUri: OfficeNamespaces.w)
    .firstOrNull;

Map<String, String> _attributes(XmlElement element) => {
  for (final attribute in element.attributes)
    if (attribute.namespaceUri == OfficeNamespaces.w)
      attribute.localName: attribute.value,
};

void _expectMargins(
  WmlParagraphProps properties, {
  required double left,
  required double right,
  double firstLine = 0,
  double hanging = 0,
}) {
  expect(properties.indent.left, left);
  expect(properties.indent.right, right);
  expect(properties.indent.firstLine, firstLine);
  expect(properties.indent.hanging, hanging);
}

WmlStyle _editStyle(WmlStyle source, {String? basedOn}) => WmlStyle(
  id: source.id,
  name: source.name,
  nameAr: source.nameAr,
  headingLevel: source.headingLevel,
  justification: source.justification,
  bold: source.bold,
  italic: source.italic,
  fontSizePoints: 14,
  color: source.color,
  spacingBefore: source.spacingBefore,
  spacingAfter: source.spacingAfter,
  font: source.font,
  csFont: source.csFont,
  basedOn: basedOn ?? source.basedOn,
  numId: source.numId,
  ilvl: source.ilvl,
  indent: source.indent,
);

void main() {
  group('authored paragraph direction and logical properties', () {
    for (final rtl in [false, true]) {
      for (final alignment in ['left', 'start', 'right', 'end']) {
        for (final legacy in [false, true]) {
          test('$rtl bidi, $alignment alignment, legacy indent $legacy', () {
            final start = legacy ? 'left' : 'start';
            final end = legacy ? 'right' : 'end';
            // Put bidi last deliberately: import must not depend on order.
            final document = WordDeserializer().read(
              _fixture(
                '<w:jc w:val="$alignment"/>'
                '<w:ind w:$start="1200" w:$end="300" w:firstLine="240"/>'
                '<w:bidi w:val="${rtl ? 1 : 0}"/>',
              ),
            );
            final properties = document.paragraphs.single.properties;
            expect(properties.rightToLeft, rtl);
            final startAligned = alignment == 'left' || alignment == 'start';
            expect(
              properties.justification,
              startAligned == rtl
                  ? WmlJustification.right
                  : WmlJustification.left,
            );
            _expectMargins(
              properties,
              left: rtl ? 15 : 60,
              right: rtl ? 60 : 15,
              firstLine: 12,
            );
          });
        }
      }
    }

    test('absent bidi keeps native logical margins in LTR order', () {
      final properties = WordDeserializer()
          .read(
            _fixture(
              '<w:jc w:val="end"/>'
              '<w:ind w:start="-120" w:end="1.5in" w:hanging="180"/>',
              styles: '',
            ),
          )
          .paragraphs
          .single
          .properties;
      expect(properties.rightToLeft, isNull);
      expect(properties.justification, WmlJustification.right);
      _expectMargins(properties, left: -6, right: 108, hanging: 9);
    });

    test(
      'legacy aliases win same-node conflicts regardless attribute order',
      () {
        for (final attributes in [
          'w:left="600" w:start="1200" w:right="180" w:end="360"',
          'w:end="360" w:right="180" w:start="1200" w:left="600"',
        ]) {
          final properties = WordDeserializer()
              .read(_fixture('<w:ind $attributes/><w:bidi/>'))
              .paragraphs
              .single
              .properties;
          _expectMargins(properties, left: 9, right: 30);
        }
      },
    );

    test('foreign or nested layout lookalikes stay outside the projection', () {
      final document = WordDeserializer().read(
        _fixture(
          '<a:ind a:left="1200" e:left="9999" a:right="300"/>'
          '<e:ind e:left="9999"/>'
          '<a:jc a:val="end" e:val="start"/>'
          '<e:jc e:val="start"/>'
          '<e:wrapper><w:jc w:val="start"/>'
          '<w:ind w:left="9999"/></e:wrapper><a:bidi/>',
          styles: '',
        ),
      );
      final properties = document.paragraphs.single.properties;
      expect(properties.rightToLeft, isTrue);
      expect(properties.justification, WmlJustification.left);
      _expectMargins(properties, left: 15, right: 60);
      final saved = _savedProperties(WordSerializer().write(document));
      expect(saved.firstChild('wrapper', namespaceUri: _extension), isNotNull);
      expect(saved.firstChild('ind', namespaceUri: _extension), isNotNull);
      expect(saved.firstChild('jc', namespaceUri: _extension), isNotNull);
    });
  });

  test('repeated paragraph XML preserves in-scope compatibility choices', () {
    const properties =
        '<w:pPr><mc:AlternateContent><mc:Choice Requires="x">'
        '<w:spacing w:after="120"/></mc:Choice><mc:Fallback>'
        '<w:spacing w:after="300"/></mc:Fallback></mc:AlternateContent>'
        '<x:packet/></w:pPr>';
    final package = _fixture('');
    final body = [
      '<w:p>$properties<w:r><w:t>One</w:t></w:r></w:p>',
      '<w:p>$properties<w:r><w:t>Two</w:t></w:r></w:p>',
      '<w:p xmlns:x="$_extension">$properties<w:r><w:t>Three</w:t></w:r></w:p>',
    ].join();
    package.getPart('/word/document.xml')!.writeText(
      '<w:document xmlns:w="${OfficeNamespaces.w}" '
      'xmlns:mc="${OfficeNamespaces.mc}" xmlns:x="${OfficeNamespaces.wps}">'
      '<w:body>$body<w:sectPr/></w:body></w:document>',
    );

    final paragraphs = WordDeserializer().read(package).paragraphs.toList();
    expect(paragraphs.map((p) => p.properties.spacingAfter), [6, 6, 15]);
    for (final (index, paragraph) in paragraphs.indexed) {
      final xml = XmlDocument.parse(paragraph.properties.sourcePropertiesXml!);
      expect(
        xml.root!.firstChild(
          'packet',
          namespaceUri: index == 2 ? _extension : OfficeNamespaces.wps,
        ),
        isNotNull,
      );
    }
  });

  group('effective style direction', () {
    const base =
        '<w:style w:type="paragraph" w:styleId="Base">'
        '<w:pPr><w:ind w:start="1200" w:end="300" w:hanging="180"/>'
        '<w:jc w:val="start"/><w:bidi w:val="0"/></w:pPr></w:style>';
    const derived =
        '<w:style w:type="paragraph" w:styleId="Derived">'
        '<w:basedOn w:val="Base"/>'
        '<w:pPr><w:ind w:left="900"/><w:bidi/></w:pPr></w:style>';

    test('late inherited bidi and cross-layer aliases resolve together', () {
      final package = _fixture(
        '<w:pStyle w:val="Derived"/>',
        styles: '$base$derived',
      );
      final originalStyles = XmlDocument.parse(
        package.getPart('/word/styles.xml')!.readText(),
      ).toXmlString();
      var document = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        final properties = document.paragraphs.single.properties;
        expect(properties.rightToLeft, isTrue);
        expect(properties.justification, WmlJustification.right);
        _expectMargins(properties, left: 15, right: 45, hanging: 9);
        final saved = WordSerializer().write(document);
        final direct = _savedProperties(saved);
        expect(direct.childElements.map((element) => element.localName), [
          'pStyle',
        ]);
        expect(
          XmlDocument.parse(
            saved.getPart('/word/styles.xml')!.readText(),
          ).toXmlString(),
          originalStyles,
        );
        document = WordDeserializer().readBytes(saved.save());
      }
    });

    test('direct modern aliases override inherited legacy sides and bidi', () {
      final document = WordDeserializer().read(
        _fixture(
          '<w:pStyle w:val="Derived"/>'
          '<w:ind w:start="1500" w:end="240"/><w:bidi w:val="0"/>',
          styles: '$base$derived',
        ),
      );
      final properties = document.paragraphs.single.properties;
      expect(properties.rightToLeft, isFalse);
      expect(properties.justification, WmlJustification.left);
      _expectMargins(properties, left: 75, right: 12, hanging: 9);
    });

    test('docDefaults direction and later style changes stay inherited', () {
      final package = _fixture(
        '<w:pStyle w:val="Body"/>',
        styles:
            '<w:docDefaults><w:pPrDefault><w:pPr>'
            '<w:bidi/><w:ind w:left="600" w:right="240"/>'
            '<w:jc w:val="end"/>'
            '</w:pPr></w:pPrDefault></w:docDefaults>'
            '<w:style w:type="paragraph" w:styleId="Body"/>',
      );
      final document = WordDeserializer().read(package);
      expect(
        document.paragraphs.single.properties.justification,
        WmlJustification.left,
      );
      _expectMargins(
        document.paragraphs.single.properties,
        left: 12,
        right: 30,
      );
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles.readText().replaceFirst('<w:bidi/>', '<w:bidi w:val="0"/>'),
      );
      WordDeserializer().refreshStyles(document);
      expect(document.paragraphs.single.properties.rightToLeft, isFalse);
      expect(
        document.paragraphs.single.properties.justification,
        WmlJustification.right,
      );
      _expectMargins(
        document.paragraphs.single.properties,
        left: 30,
        right: 12,
      );
      final direct = _savedProperties(WordSerializer().write(document));
      expect(_native(direct, 'ind'), isNull);
      expect(_native(direct, 'bidi'), isNull);
      expect(_native(direct, 'jc'), isNull);
    });

    for (final ownDirection in [false, true]) {
      for (final changeBase in [false, true]) {
        test(
          'style edit preserves layout, own bidi $ownDirection, new base $changeBase',
          () {
            final package = _fixture(
              '<w:pStyle w:val="Derived"/>',
              styles:
                  '<w:style w:type="paragraph" w:styleId="RtlBase">'
                  '<w:pPr><w:bidi/></w:pPr></w:style>'
                  '<w:style w:type="paragraph" w:styleId="LtrBase">'
                  '<w:pPr><w:bidi w:val="0"/></w:pPr></w:style>'
                  '<a:style a:type="paragraph" a:styleId="Derived" e:keep="style">'
                  '<a:basedOn a:val="RtlBase" e:keep="base"/>'
                  '<a:pPr e:keep="properties">'
                  '<a:ind a:left="900" a:right="240" e:keep="indent"/>'
                  '<a:jc a:val="start" e:keep="alignment"/>'
                  '${ownDirection ? '<a:bidi e:keep="direction"/>' : ''}'
                  '<e:packet e:val="opaque"/></a:pPr>'
                  '<a:rPr e:keep="runs"><a:color a:val="112233" e:keep="color"/>'
                  '<a:sz a:val="22"/><e:packet e:val="run"/></a:rPr>'
                  '<e:packet e:val="style"/></a:style>',
            );
            var document = WordDeserializer().read(package);
            final index = document.styles.indexWhere((s) => s.id == 'Derived');
            final original = document.styles[index];
            expect(original.justification, WmlJustification.right);
            expect(original.indent!.left, 12);
            expect(original.indent!.right, 45);
            document.styles[index] = _editStyle(
              original,
              basedOn: changeBase ? 'LtrBase' : null,
            );
            for (var cycle = 0; cycle < 2; cycle++) {
              final saved = WordSerializer().write(document);
              final styles = XmlDocument.parse(
                saved.getPart('/word/styles.xml')!.readText(),
              ).root!;
              final source = styles
                  .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
                  .singleWhere((s) => s.getAttribute('styleId') == 'Derived');
              expect(
                source.getAttribute('keep', namespaceUri: _extension),
                'style',
              );
              expect(
                source.firstChild('packet', namespaceUri: _extension),
                isNotNull,
              );
              expect(
                source
                    .firstChild('basedOn')!
                    .getAttribute('keep', namespaceUri: _extension),
                'base',
              );
              final properties = _native(source, 'pPr')!;
              expect(_native(properties, 'bidi') != null, ownDirection);
              if (ownDirection) {
                expect(
                  _native(
                    properties,
                    'bidi',
                  )!.getAttribute('keep', namespaceUri: _extension),
                  'direction',
                );
              }
              expect(
                _native(
                  properties,
                  'ind',
                )!.getAttribute('keep', namespaceUri: _extension),
                'indent',
              );
              expect(
                _native(
                  properties,
                  'jc',
                )!.getAttribute('keep', namespaceUri: _extension),
                'alignment',
              );
              expect(
                properties.firstChild('packet', namespaceUri: _extension),
                isNotNull,
              );
              expect(
                _native(
                  source,
                  'rPr',
                )!.firstChild('packet', namespaceUri: _extension),
                isNotNull,
              );
              final direct = _savedProperties(saved);
              expect(_native(direct, 'ind'), isNull);
              expect(_native(direct, 'bidi'), isNull);
              expect(_native(direct, 'jc'), isNull);
              document = WordDeserializer().readBytes(saved.save());
              final paragraph = document.paragraphs.single;
              expect(
                paragraph.properties.rightToLeft,
                ownDirection || !changeBase,
              );
              expect(
                paragraph.properties.justification,
                WmlJustification.right,
              );
              _expectMargins(paragraph.properties, left: 12, right: 45);
              expect(
                paragraph.inlines
                    .whereType<WmlRun>()
                    .single
                    .properties
                    .fontSizePoints,
                14,
              );
            }
          },
        );
      }
    }

    for (final owned in [0, 900]) {
      test(
        'rebasing a sparse style moves only its owned physical side ($owned twips)',
        () {
          var document = WordDeserializer().read(
            _fixture(
              '<w:pStyle w:val="Derived"/>',
              styles:
                  '<w:style w:type="paragraph" w:styleId="RtlBase">'
                  '<w:pPr><w:bidi/><w:ind w:left="1000" w:right="300"/>'
                  '</w:pPr></w:style>'
                  '<w:style w:type="paragraph" w:styleId="LtrBase">'
                  '<w:pPr><w:bidi w:val="0"/><w:ind w:left="700" w:right="400"/>'
                  '</w:pPr></w:style>'
                  '<w:style w:type="paragraph" w:styleId="Derived">'
                  '<w:basedOn w:val="RtlBase"/><w:pPr><w:ind w:left="$owned" '
                  'e:keep="partial"/></w:pPr></w:style>',
            ),
          );
          final at = document.styles.indexWhere((s) => s.id == 'Derived');
          document.styles[at] = _editStyle(
            document.styles[at],
            basedOn: 'LtrBase',
          );
          for (var cycle = 0; cycle < 2; cycle++) {
            final saved = WordSerializer().write(document);
            final style =
                XmlDocument.parse(saved.getPart('/word/styles.xml')!.readText())
                    .root!
                    .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
                    .singleWhere((s) => s.getAttribute('styleId') == 'Derived');
            final indent = _native(_native(style, 'pPr')!, 'ind')!;
            expect(_attributes(indent), {'right': '$owned'});
            expect(
              indent.getAttribute('keep', namespaceUri: _extension),
              'partial',
            );
            expect(_native(_native(style, 'pPr')!, 'jc'), isNull);
            expect(_native(_native(style, 'pPr')!, 'bidi'), isNull);
            document = WordDeserializer().readBytes(saved.save());
            expect(document.paragraphs.single.properties.rightToLeft, isFalse);
            _expectMargins(
              document.paragraphs.single.properties,
              left: 35,
              right: owned / 20,
            );
          }
        },
      );
    }

    test('native style edits leave a foreign style with the same ID intact', () {
      final document = WordDeserializer().read(
        _fixture(
          '<w:pStyle w:val="Body"/>',
          styles:
              '<e:style e:styleId="Body"><e:packet>Opaque style</e:packet></e:style>'
              '<a:style a:type="paragraph" a:styleId="Body">'
              '<a:pPr><a:bidi/><a:ind a:start="900" a:end="240"/>'
              '<a:jc a:val="start"/></a:pPr></a:style>',
        ),
      );
      final at = document.styles.indexWhere((s) => s.id == 'Body');
      document.styles[at] = _editStyle(document.styles[at]);
      final saved = WordSerializer().write(document);
      final styles = XmlDocument.parse(
        saved.getPart('/word/styles.xml')!.readText(),
      ).root!;
      expect(
        styles
            .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
            .where((s) => s.getAttribute('styleId') == 'Body'),
        hasLength(1),
      );
      expect(
        styles
            .firstChild('style', namespaceUri: _extension)!
            .firstChild('packet', namespaceUri: _extension)!
            .text,
        'Opaque style',
      );
      final reopened = WordDeserializer().readBytes(saved.save());
      expect(reopened.paragraphs.single.properties.rightToLeft, isTrue);
      expect(
        reopened.paragraphs.single.properties.justification,
        WmlJustification.right,
      );
      _expectMargins(
        reopened.paragraphs.single.properties,
        left: 12,
        right: 45,
      );
    });
  });

  group('physical native model serialization', () {
    for (final rtl in [false, true]) {
      for (final alignment in [WmlJustification.left, WmlJustification.right]) {
        test('$rtl bidi and physical $alignment write standard values', () {
          final document = WmlDocument.empty();
          document.paragraphs.single.properties = WmlParagraphProps(
            rightToLeft: rtl,
            justification: alignment,
            explicitJustification: true,
            indent: const WmlIndent(left: 15, right: 60, hanging: 9),
          );
          final saved = WordSerializer().write(document);
          final direct = _savedProperties(saved);
          expect(_attributes(_native(direct, 'ind')!), {
            'left': rtl ? '1200' : '300',
            'right': rtl ? '300' : '1200',
            'hanging': '180',
          });
          expect(
            _native(direct, 'jc')!.getAttribute('val'),
            (alignment == WmlJustification.left) == rtl ? 'right' : 'left',
          );
          final reopened = WordDeserializer().readBytes(saved.save());
          expect(
            reopened.paragraphs.single.properties.justification,
            alignment,
          );
          _expectMargins(
            reopened.paragraphs.single.properties,
            left: 15,
            right: 60,
            hanging: 9,
          );
        });
      }
    }

    test(
      'direction edit retains physical layout and native extension attrs',
      () {
        var document = WordDeserializer().read(
          _fixture(
            '<a:ind a:start="1200" a:end="300" a:hanging="180" '
            'e:start="opaque" e:keep="indent"/>'
            '<a:jc a:val="end" e:val="opaque" e:keep="alignment"/>'
            '<a:bidi e:keep="direction"/>',
          ),
        );
        for (final rtl in [false, true, false]) {
          document.paragraphs.single.properties.rightToLeft = rtl;
          final saved = WordSerializer().write(document);
          final direct = _savedProperties(saved);
          final indent = _native(direct, 'ind')!;
          expect(_attributes(indent), {
            'left': rtl ? '1200' : '300',
            'right': rtl ? '300' : '1200',
            'hanging': '180',
          });
          expect(
            indent.getAttribute('start', namespaceUri: _extension),
            'opaque',
          );
          expect(
            indent.getAttribute('keep', namespaceUri: _extension),
            'indent',
          );
          final alignment = _native(direct, 'jc')!;
          expect(
            alignment.getAttribute('val', namespaceUri: _extension),
            'opaque',
          );
          expect(
            alignment.getAttribute('keep', namespaceUri: _extension),
            'alignment',
          );
          expect(
            _native(
              direct,
              'bidi',
            )!.getAttribute('keep', namespaceUri: _extension),
            'direction',
          );
          document = WordDeserializer().readBytes(saved.save());
          expect(
            document.paragraphs.single.properties.justification,
            WmlJustification.left,
          );
          _expectMargins(
            document.paragraphs.single.properties,
            left: 15,
            right: 60,
            hanging: 9,
          );
        }
      },
    );

    test(
      'one physical side edit leaves other side and first line inherited',
      () {
        final document = WordDeserializer().read(
          _fixture(
            '<w:pStyle w:val="Body"/><w:ind e:keep="native"/>',
            styles:
                '<w:style w:type="paragraph" w:styleId="Body">'
                '<w:pPr><w:ind w:start="1200" w:end="300" w:firstLine="240"/>'
                '<w:jc w:val="start"/><w:bidi/></w:pPr></w:style>',
          ),
        );
        final properties = document.paragraphs.single.properties;
        properties.indent = properties.indent.copyWith(left: 21);
        final saved = WordSerializer().write(document);
        final direct = _savedProperties(saved);
        expect(_attributes(_native(direct, 'ind')!), {'right': '420'});
        expect(_native(direct, 'jc'), isNull);
        expect(_native(direct, 'bidi'), isNull);
        expect(
          _native(
            direct,
            'ind',
          )!.getAttribute('keep', namespaceUri: _extension),
          'native',
        );
        final reopened = WordDeserializer().readBytes(saved.save());
        _expectMargins(
          reopened.paragraphs.single.properties,
          left: 21,
          right: 60,
          firstLine: 12,
        );
      },
    );

    test('direction-only change emits only required inherited overrides', () {
      final document = WordDeserializer().read(
        _fixture(
          '<w:pStyle w:val="Body"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="Body">'
              '<w:pPr><w:ind w:start="1200" w:end="300" w:firstLine="240"/>'
              '<w:jc w:val="start"/><w:bidi/></w:pPr></w:style>',
        ),
      );
      document.paragraphs.single.properties.rightToLeft = false;
      final saved = WordSerializer().write(document);
      final direct = _savedProperties(saved);
      expect(_attributes(_native(direct, 'ind')!), {
        'left': '300',
        'right': '1200',
      });
      expect(_native(direct, 'jc')!.getAttribute('val'), 'right');
      expect(_native(direct, 'bidi')!.getAttribute('val'), '0');
      final reopened = WordDeserializer().readBytes(saved.save());
      expect(
        reopened.paragraphs.single.properties.justification,
        WmlJustification.right,
      );
      _expectMargins(
        reopened.paragraphs.single.properties,
        left: 15,
        right: 60,
        firstLine: 12,
      );
    });

    for (final inherited in ['firstLine', 'hanging']) {
      for (final current in ['firstLine', 'hanging', 'none']) {
        test(
          'native $inherited can be replaced by $current without stale inheritance',
          () {
            var document = WordDeserializer().read(
              _fixture(
                '<w:pStyle w:val="Body"/>',
                styles:
                    '<w:style w:type="paragraph" w:styleId="Body">'
                    '<w:pPr><w:bidi/><w:ind w:left="1200" w:right="300" '
                    'w:$inherited="240"/></w:pPr></w:style>',
              ),
            );
            final props = document.paragraphs.single.properties;
            props.indent = props.indent.copyWith(
              firstLine: current == 'firstLine' ? 18 : 0,
              hanging: current == 'hanging' ? 9 : 0,
            );
            for (var cycle = 0; cycle < 2; cycle++) {
              final saved = WordSerializer().write(document);
              expect(_attributes(_native(_savedProperties(saved), 'ind')!), {
                if (current == 'firstLine') 'firstLine': '360',
                if (current == 'hanging') 'hanging': '180',
                if (current == 'none') 'firstLine': '0',
              });
              document = WordDeserializer().readBytes(saved.save());
              _expectMargins(
                document.paragraphs.single.properties,
                left: 15,
                right: 60,
                firstLine: current == 'firstLine' ? 18 : 0,
                hanging: current == 'hanging' ? 9 : 0,
              );
            }
          },
        );
      }
    }

    test(
      'physical direction and indentation survive repeated DOCX and ODT',
      () async {
        var document = WordDeserializer().read(
          _fixture(
            '<w:ind w:start="1200" w:end="300" w:firstLine="240"/>'
            '<w:jc w:val="end"/><w:bidi/>',
          ),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(document.paragraphs.single.properties.rightToLeft, isTrue);
          expect(
            document.paragraphs.single.properties.justification,
            WmlJustification.left,
          );
          _expectMargins(
            document.paragraphs.single.properties,
            left: 15,
            right: 60,
            firstLine: 12,
          );
          document = await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeBytes(document),
          );
          expect(document.paragraphs.single.properties.rightToLeft, isTrue);
          expect(
            document.paragraphs.single.properties.justification,
            WmlJustification.left,
          );
          _expectMargins(
            document.paragraphs.single.properties,
            left: 15,
            right: 60,
            firstLine: 12,
          );
        }
      },
    );
  });
}
