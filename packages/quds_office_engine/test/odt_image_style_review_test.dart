import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Independent review of the bounded graphic-style contract. These cases use
// arbitrary style names and inherited values rather than the producer's names.
// ODF 1.3: stroke, shadow and vertical relation are distinct active properties.
// https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html#property-draw_stroke
// https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html#property-draw_shadow
// https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html#property-style_vertical-rel
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _ns =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:draw="$_draw" '
    'xmlns:svg="$_svg" xmlns:style="$_style" xmlns:fo="$_fo" '
    'xmlns:xlink="$_xlink"';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
const _floatingDefaults =
    'text:anchor-type="paragraph" svg:x="0in" svg:y="0in" '
    'style:wrap="dynamic" style:number-wrapped-paragraphs="no-limit" '
    'style:wrap-contour="false" style:vertical-pos="top" '
    'style:vertical-rel="paragraph" style:horizontal-pos="center" '
    'style:horizontal-rel="paragraph" draw:fill="none"';

const _frame =
    '<draw:frame draw:style-name="RasterOwn" text:anchor-type="as-char" '
    'svg:width="18pt" svg:height="12pt">'
    '<draw:image xlink:href="Pictures/review.png" xlink:type="simple"/>'
    '<svg:title>Accessibility title</svg:title>'
    '<svg:desc>Accessibility description</svg:desc></draw:frame>';

Uint8List _package({
  String body =
      '<text:p>A$_frame'
      'B</text:p>',
  String parent = '',
  String own = '',
  String defaults = '',
  String parentChildren = '',
  String textStyles = '',
}) {
  final archive = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile(
      'styles.xml',
      utf8.encode(
        '<office:document-styles $_ns><office:styles>'
        '<style:default-style style:family="graphic">'
        '<style:graphic-properties $defaults/></style:default-style>'
        '<style:style style:name="RasterParent" style:family="graphic">'
        '<style:graphic-properties $parent/>$parentChildren</style:style>'
        '$textStyles</office:styles></office:document-styles>',
      ),
    )
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content $_ns><office:automatic-styles>'
        '<style:style style:name="RasterOwn" style:family="graphic" '
        'style:parent-style-name="RasterParent">'
        '<style:graphic-properties $own/></style:style>'
        '</office:automatic-styles><office:body><office:text>$body'
        '</office:text></office:body></office:document-content>',
      ),
    )
    ..addFile('Pictures/review.png', base64Decode(_png));
  return archive.close();
}

WmlRun _picture(WmlDocument document) => document.paragraphs.single.inlines
    .whereType<WmlRun>()
    .singleWhere((run) => run.inlineVisual != null);

String _link(String contents, {String visited = 'AbsentVisitedStyle'}) =>
    '<text:a xlink:href="https://example.test/image" '
    'text:style-name="Primary" text:visited-style-name="$visited">'
    '$contents</text:a>';

const _primary =
    '<style:style style:name="Primary" style:family="text">'
    '<style:text-properties fo:color="#008800"/></style:style>';

final _refused = throwsA(
  anyOf(isA<UnsupportedError>(), isA<FormatException>()),
);

void main() {
  test(
    'inherited inactive paint and frame defaults retain a raw bitmap',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          parent: _floatingDefaults,
          defaults:
              'svg:stroke-color="#3465a4" draw:fill-color="#729fcf" '
              'draw:shadow-offset-x="0.1181in" draw:shadow-offset-y="0.1181in" '
              'draw:start-line-spacing-horizontal="0.1114in" '
              'draw:end-line-spacing-vertical="0.1114in"',
          own:
              'draw:stroke="none" draw:shadow="hidden" style:mirror="none" '
              'fo:clip="rect(0in, 0in, 0in, 0in)" draw:gamma="100%" '
              'draw:image-opacity="100%"',
        ),
      );
      expect(document.paragraphs.single.text, 'A\uFFFCB');
      final visual = _picture(document).inlineVisual!.visual;
      expect(visual.imageBytes, orderedEquals(base64Decode(_png)));
      expect((visual.width, visual.height), (18.0, 12.0));
      expect(visual.picture.altTitle, 'Accessibility title');
      expect(visual.picture.altDescription, 'Accessibility description');
    },
  );

  for (final entry in <String, String>{
    'stroke': 'draw:stroke="solid"',
    'fill': 'draw:fill="solid"',
    'shadow': 'draw:shadow="visible"',
    'fill opacity': 'draw:opacity="50%"',
    'bitmap opacity': 'draw:image-opacity="50%"',
    'gamma': 'draw:gamma="90%"',
    'red adjustment': 'draw:red="1%"',
    'greyscale': 'draw:color-mode="greyscale"',
    'mirror': 'style:mirror="horizontal"',
    'crop': 'fo:clip="rect(1pt, 0pt, 0pt, 0pt)"',
    'border': 'fo:border="1pt solid #000000"',
    'margin': 'fo:margin-left="1pt"',
    'outline shadow': 'style:shadow="#000000 1pt 1pt"',
    'baseline top alignment': 'style:vertical-rel="baseline"',
    'line alignment': 'style:vertical-rel="line" style:vertical-pos="bottom"',
    'explicit vertical positioning': 'style:vertical-pos="from-top"',
    'nonzero vertical offset': 'svg:y="1pt"',
    'nondefault horizontal position': 'style:horizontal-pos="left"',
    'relative size': 'style:rel-width="50%"',
    'printing suppression': 'style:print-content="false"',
    'content protection': 'style:protect="content"',
    'unknown graphic property': 'draw:unknown-effect="enabled"',
  }.entries) {
    test('effective ${entry.key} remains refused', () async {
      final bytes = _package(parent: _floatingDefaults, own: entry.value);
      final original = Uint8List.fromList(bytes);
      await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
      expect(bytes, orderedEquals(original));
    });
  }

  test(
    'effective child modes override active inherited paint values',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          defaults: 'draw:stroke="solid" draw:shadow="visible"',
          parent: 'draw:fill="solid"',
          own: 'draw:stroke="none" draw:shadow="hidden" draw:fill="none"',
        ),
      );
      expect(document.paragraphs.single.text, 'A\uFFFCB');
    },
  );

  test(
    'unoverridden inherited paint cannot be hidden by a child style',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(defaults: 'draw:stroke="solid"', own: 'draw:fill="none"'),
        ),
        _refused,
      );
    },
  );

  test(
    'declared fill color needs an explicitly inactive effective fill mode',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(defaults: 'draw:fill-color="#ff0000"'),
        ),
        _refused,
      );
    },
  );

  for (final entry in <String, (String, String)>{
    'vertical fallback without paragraph anchor': (
      '',
      'style:vertical-pos="top" style:vertical-rel="paragraph"',
    ),
    'vertical fallback under as-char style anchor': (
      'text:anchor-type="as-char"',
      'style:vertical-pos="top" style:vertical-rel="paragraph"',
    ),
    'incomplete vertical fallback': (
      'text:anchor-type="paragraph"',
      'style:vertical-pos="top"',
    ),
    'horizontal fallback without paragraph anchor': (
      '',
      'style:horizontal-pos="center" style:horizontal-rel="paragraph"',
    ),
  }.entries) {
    test('refuses ${entry.key}', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(parent: entry.value.$1, own: entry.value.$2),
        ),
        _refused,
      );
    });
  }

  test(
    'glyph defaults do not leak into an image or its surrounding text',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          parentChildren:
              '<style:paragraph-properties fo:margin-left="24pt">'
              '<style:tab-stops/></style:paragraph-properties>'
              '<style:text-properties fo:color="#ff0000" fo:font-size="44pt"/>',
        ),
      );
      expect(document.paragraphs.single.text, 'A\uFFFCB');
      expect(_picture(document).properties.fontSizePoints, 11);
      expect(document.paragraphs.single.properties.indent.left, 0);
      expect(
        _picture(document).inlineVisual!.visual.picture.altTitle,
        'Accessibility title',
      );
    },
  );

  test('graphic glyph roots cannot conceal nested document content', () async {
    for (final child in [
      '<style:text-properties><text:span>Hidden</text:span></style:text-properties>',
      '<style:paragraph-properties><text:p>Hidden</text:p></style:paragraph-properties>',
      '<style:paragraph-properties><style:tab-stops><style:tab-stop style:position="1in"/></style:tab-stops></style:paragraph-properties>',
    ]) {
      await expectLater(
        OdtDocumentReader.readBytes(_package(parentChildren: child)),
        _refused,
      );
    }
  });

  test(
    'undefined visited style is inactive only on a glyph-free image link',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          body: '<text:p>A${_link('<text:span>$_frame</text:span>')}B</text:p>',
          textStyles: _primary,
        ),
      );
      expect(document.paragraphs.single.text, 'A\uFFFCB');
      expect(_picture(document).hyperlink?.url, 'https://example.test/image');
    },
  );

  for (final entry in <String, String>{
    'visible text': 'Caption$_frame',
    'literal space': ' $_frame ',
    'nested literal space': '<text:span> $_frame </text:span>',
    'nonbreaking space': '\u00a0$_frame',
    'explicit space': '<text:s/>$_frame',
    'line break': '<text:line-break/>$_frame',
  }.entries) {
    test('image-link visited exemption refuses ${entry.key}', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(
            body: '<text:p>A${_link(entry.value)}B</text:p>',
            textStyles: _primary,
          ),
        ),
        _refused,
      );
    });
  }

  test('defined visited character style still undergoes validation', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(
          body: '<text:p>${_link(_frame, visited: 'DefinedVisited')}</text:p>',
          textStyles:
              '$_primary<style:style style:name="DefinedVisited" style:family="text">'
              '<style:text-properties fo:text-shadow="1pt 1pt"/></style:style>',
        ),
      ),
      _refused,
    );
  });
}
