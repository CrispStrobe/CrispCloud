import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}"';

String _sld(
  String shapes, {
  String root = 'sld',
  String name = '',
  String background = '',
}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:$root $_ns><p:cSld${name.isEmpty ? '' : ' name="$name"'}>$background'
    '<p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr><p:grpSpPr/>$shapes</p:spTree></p:cSld>'
    '${root == 'sldMaster' ? '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" '
              'tx2="dk2" accent1="accent1"/>' : ''}'
    '</p:$root>';

String _creationId() =>
    '<a:extLst><a:ext uri="{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236}">'
    '<a16:creationId xmlns:a16="http://schemas.microsoft.com/office/drawing/'
    '2014/main" id="{11111111-2222-3333-4444-555555555555}"/></a:ext>'
    '</a:extLst>';

String _textBox(int id, String text, {String xfrm = ''}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="TextBox $id"/>'
    '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>$xfrm'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
    '<p:txBody><a:bodyPr/><a:p><a:r><a:t>$text</a:t></a:r></a:p>'
    '</p:txBody></p:sp>';

String _xfrm(int x, int y, int cx, int cy) =>
    '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>';

String _placeholder(
  int id,
  String type, {
  int? idx,
  String xfrm = '',
  String text = '',
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$type $id">${_creationId()}'
    '</p:cNvPr><p:cNvSpPr/><p:nvPr><p:ph type="$type"'
    '${idx == null ? '' : ' idx="$idx"'}/></p:nvPr></p:nvSpPr>'
    '<p:spPr>$xfrm</p:spPr><p:txBody><a:bodyPr/><a:p>'
    '${text.isEmpty ? '' : '<a:r><a:t>$text</a:t></a:r>'}</a:p></p:txBody>'
    '</p:sp>';

const String _theme =
    '<a:theme xmlns:a="${OfficeNamespaces.a}" name="Office Theme">'
    '<a:themeElements><a:clrScheme name="Office">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
    '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
    '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
    '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    '</a:clrScheme></a:themeElements></a:theme>';

/// A deck with a primary master/layout and an optional second-slide master.
PmlPresentation _deck(
  List<String> slides, {
  List<int>? order,
  String masterBackground = '',
  String layoutBackground = '',
  String? secondaryMasterBackground,
  String layoutShapes = '',
}) {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.slide);
  final RelationshipCollection presRels = package.relationshipsFor(
    '/ppt/presentation.xml',
  );
  presRels.removeById('rId1');
  presRels.add(
    type: RelationshipTypes.slideMaster,
    target: 'slideMasters/slideMaster1.xml',
    id: 'rId1',
  );
  package.createPart(
    '/ppt/theme/theme1.xml',
    OfficeContentTypes.theme,
    utf8.encode(_theme),
  );
  package.createPart(
    '/ppt/slideMasters/slideMaster1.xml',
    OfficeContentTypes.slideMaster,
    utf8.encode(
      _sld(
        _placeholder(
              2,
              'title',
              xfrm: _xfrm(457200, 274638, 8229600, 1143000),
            ) +
            _placeholder(
              3,
              'body',
              idx: 1,
              xfrm: _xfrm(1371600, 3886200, 6400800, 1752600),
              text: 'Click to edit Master text styles',
            ),
        root: 'sldMaster',
        background: masterBackground,
      ),
    ),
  );
  package.relationshipsFor('/ppt/slideMasters/slideMaster1.xml')
    ..add(type: RelationshipTypes.theme, target: '../theme/theme1.xml')
    ..add(
      type: RelationshipTypes.slideLayout,
      target: '../slideLayouts/slideLayout1.xml',
    );
  package.createPart(
    '/ppt/slideLayouts/slideLayout1.xml',
    OfficeContentTypes.slideLayout,
    utf8.encode(
      _sld(
        _placeholder(
              2,
              'ctrTitle',
              xfrm: _xfrm(685800, 2130425, 7772400, 1470025),
              text: 'Click to edit Master title style',
            ) +
            _placeholder(3, 'subTitle', idx: 1, text: 'Click to add subtitle') +
            layoutShapes,
        root: 'sldLayout',
        name: 'Title Slide',
        background: layoutBackground,
      ),
    ),
  );
  package
      .relationshipsFor('/ppt/slideLayouts/slideLayout1.xml')
      .add(
        type: RelationshipTypes.slideMaster,
        target: '../slideMasters/slideMaster1.xml',
      );
  String? secondaryMasterId;
  if (secondaryMasterBackground != null) {
    secondaryMasterId = presRels
        .add(
          type: RelationshipTypes.slideMaster,
          target: 'slideMasters/slideMaster2.xml',
        )
        .id;
    package.createPart(
      '/ppt/slideMasters/slideMaster2.xml',
      OfficeContentTypes.slideMaster,
      utf8.encode(
        _sld('', root: 'sldMaster', background: secondaryMasterBackground),
      ),
    );
    package.relationshipsFor('/ppt/slideMasters/slideMaster2.xml')
      ..add(type: RelationshipTypes.theme, target: '../theme/theme1.xml')
      ..add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout2.xml',
      );
    package.createPart(
      '/ppt/slideLayouts/slideLayout2.xml',
      OfficeContentTypes.slideLayout,
      utf8.encode(_sld('', root: 'sldLayout', name: 'Secondary')),
    );
    package
        .relationshipsFor('/ppt/slideLayouts/slideLayout2.xml')
        .add(
          type: RelationshipTypes.slideMaster,
          target: '../slideMasters/slideMaster2.xml',
        );
  }
  final List<String> ids = <String>[];
  for (int i = 0; i < slides.length; i++) {
    final String uri = '/ppt/slides/slide${i + 1}.xml';
    if (package.getPart(uri) == null) {
      package.createPart(uri, OfficeContentTypes.slide, utf8.encode(''));
    }
    package.getPart(uri)!.writeText(slides[i]);
    package
        .relationshipsFor(uri)
        .add(
          type: RelationshipTypes.slideLayout,
          target: secondaryMasterBackground != null && i == 1
              ? '../slideLayouts/slideLayout2.xml'
              : '../slideLayouts/slideLayout1.xml',
        );
    ids.add(
      presRels
          .add(
            type: RelationshipTypes.slide,
            target: 'slides/slide${i + 1}.xml',
          )
          .id,
    );
  }
  final List<int> sequence =
      order ?? <int>[for (int i = 0; i < slides.length; i++) i];
  package
      .getPart('/ppt/presentation.xml')!
      .writeText(
        '<p:presentation $_ns><p:sldMasterIdLst><p:sldMasterId '
        'id="2147483648" r:id="rId1"/>'
        '${secondaryMasterId == null ? '' : '<p:sldMasterId id="2147483649" r:id="$secondaryMasterId"/>'}'
        '</p:sldMasterIdLst><p:sldIdLst>'
        '${sequence.map((int i) => '<p:sldId r:id="${ids[i]}" id="${256 + i}"/>').join()}'
        '</p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/></p:presentation>',
      );
  return SlideDeserializer().read(package);
}

void main() {
  group('shape import', () {
    test('text boxes stay text; only p:pic becomes a picture', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          <String>[
            _textBox(
              2,
              'Title text',
              xfrm: _xfrm(457200, 457200, 8229600, 914400),
            ),
            _textBox(3, 'Body text', xfrm: _xfrm(457200, 1600200, 8229600, 0)),
            '<p:sp><p:nvSpPr><p:cNvPr id="4" name="Shadowed"/><p:cNvSpPr/>'
                '<p:nvPr/></p:nvSpPr><p:spPr>'
                '${_xfrm(0, 0, 914400, 914400)}<a:effectLst><a:outerShdw '
                'blurRad="40000"><a:srgbClr val="000000"/></a:outerShdw>'
                '</a:effectLst></p:spPr></p:sp>',
          ].join(),
        ),
      ]);
      final List<PmlShape> shapes = deck.slides.single.shapes;
      expect(shapes[0].text, 'Title text');
      expect(shapes[0].visual, isNull);
      expect(shapes[0].fillColor, isEmpty);
      expect(shapes[1].transform.cy, 0);
      expect(shapes[2].visual, isNull);
    });

    test('extLst a:ext never overrides the xfrm extents', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:pic><p:nvPicPr><p:cNvPr id="2" name="Picture 1">${_creationId()}'
          '</p:cNvPr><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill>'
          '<a:blip r:embed="rId9">${_creationId()}</a:blip><a:stretch>'
          '<a:fillRect/></a:stretch></p:blipFill><p:spPr>'
          '${_xfrm(914400, 914400, 1828800, 1371600)}'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:extLst>'
          '<a:ext uri="{909E8E84-426E-40DD-AFC4-6F175D3DCCD1}"><a14:hiddenFill '
          'xmlns:a14="http://schemas.microsoft.com/office/drawing/2010/main">'
          '<a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>'
          '</a14:hiddenFill></a:ext></a:extLst></p:spPr></p:pic>',
        ),
      ]);
      final PmlShape picture = deck.slides.single.shapes.single;
      expect(picture.visual?.kind, OfficeVisualKind.picture);
      expect(picture.fillColor, isEmpty);
      expect(picture.strokeColor, isEmpty);
      expect(picture.transform.x, 914400);
      expect(picture.transform.cx, 1828800);
      expect(picture.transform.cy, 1371600);
    });

    test('picture srcRect keeps deep crops and edge expansion', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:pic><p:nvPicPr><p:cNvPr id="2" name="Cropped"/>'
          '<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill>'
          '<a:blip r:embed="rId9"/><a:srcRect l="10000" t="2739" '
          'r="67691" b="-1896"/><a:stretch/></p:blipFill><p:spPr>'
          '${_xfrm(0, 0, 914400, 914400)}</p:spPr></p:pic>',
        ),
      ]);
      final PictureAdjust crop =
          deck.slides.single.shapes.single.visual!.picture;
      expect(crop.cropLeft, closeTo(0.1, 0.00001));
      expect(crop.cropTop, closeTo(0.02739, 0.00001));
      expect(crop.cropRight, closeTo(0.67691, 0.00001));
      expect(crop.cropBottom, closeTo(-0.01896, 0.00001));
    });

    test('rich text keeps run styles, paragraph defaults, and anchor', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Rich"/>'
          '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>'
          '${_xfrm(0, 0, 9144000, 914400)}</p:spPr><p:txBody>'
          '<a:bodyPr anchor="ctr"/><a:p><a:pPr algn="ctr"/><a:r>'
          '<a:rPr sz="3300" b="1"><a:solidFill><a:prstClr val="white">'
          '<a:lumMod val="65000"/></a:prstClr></a:solidFill>'
          '<a:latin typeface="Microsoft Sans Serif"/></a:rPr>'
          '<a:t>Title</a:t></a:r></a:p><a:p><a:r><a:rPr b="1" i="1"/>'
          '<a:t>Date</a:t></a:r><a:endParaRPr sz="1100"/></a:p>'
          '</p:txBody></p:sp>',
        ),
      ]);
      final PmlShape shape = deck.slides.single.shapes.single;
      expect(shape.textAnchor, PmlTextAnchor.center);
      expect(shape.textAlign, PmlTextAlign.center);
      expect(shape.richText, hasLength(2));
      expect(shape.richText[0].runs.single.fontSizePt, 33);
      expect(shape.richText[0].runs.single.bold, isTrue);
      expect(shape.richText[0].runs.single.color, 'A6A6A6');
      expect(shape.richText[1].runs.single.fontSizePt, 0);
      expect(shape.richText[1].defaultFontSizePt, 11);
    });

    test('layout decorations paint behind slide content', () {
      final PmlPresentation deck = _deck(
        <String>[_sld(_textBox(2, 'Slide'))],
        layoutShapes:
            '<p:sp><p:nvSpPr><p:cNvPr id="9" name="Band"/><p:cNvSpPr/>'
            '<p:nvPr/></p:nvSpPr><p:spPr>${_xfrm(0, 0, 9144000, 6858000)}'
            '<a:solidFill><a:srgbClr val="FFB300"/></a:solidFill>'
            '</p:spPr></p:sp>',
      );
      final PmlSlide slide = deck.slides.single;
      expect(slide.backgroundShapes, hasLength(1));
      expect(slide.backgroundShapes.single.name, 'Band');
      expect(slide.backgroundShapes.single.fillColor, 'FFB300');
      expect(slide.shapes.single.name, 'TextBox 2');
    });

    test('block arrow presets survive import', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Arrow"/><p:cNvSpPr/>'
          '<p:nvPr/></p:nvSpPr><p:spPr>${_xfrm(0, 0, 914400, 914400)}'
          '<a:prstGeom prst="downArrow"><a:avLst/></a:prstGeom>'
          '<a:solidFill><a:srgbClr val="FFB300"/></a:solidFill>'
          '</p:spPr></p:sp>',
        ),
      ]);
      expect(deck.slides.single.shapes.single.preset, PmlShapePreset.downArrow);
    });

    test('flipped line connectors keep their slide direction', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="2" name="Connector"/>'
          '<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>'
          '<a:xfrm flipH="1" flipV="1"><a:off x="0" y="0"/>'
          '<a:ext cx="914400" cy="457200"/></a:xfrm>'
          '<a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
          '<a:ln w="12700"><a:solidFill><a:srgbClr val="C8C8C8"/>'
          '</a:solidFill></a:ln></p:spPr></p:cxnSp>',
        ),
      ]);
      final PmlShape connector = deck.slides.single.shapes.single;
      expect(connector.preset, PmlShapePreset.connector);
      expect(connector.transform.flipH, isTrue);
      expect(connector.transform.flipV, isTrue);
      expect(connector.strokeColor, 'C8C8C8');
    });

    test('master background resolves theme lumMod', () {
      final PmlPresentation deck = _deck(
        <String>[_sld(_textBox(2, 'Slide'))],
        masterBackground:
            '<p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg1">'
            '<a:lumMod val="95000"/></a:schemeClr></a:solidFill>'
            '<a:effectLst/></p:bgPr></p:bg>',
      );
      expect(deck.master.background, 'F2F2F2');
      expect(deck.slides.single.background, 'F2F2F2');
      expect(deck.slides.single.inheritsMasterBackground, isTrue);
      expect(deck.slides.single.copy().inheritsMasterBackground, isTrue);
    });

    test(
      'explicit slide and layout fills remain independent of the master',
      () {
        const String fill =
            '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/>'
            '</a:solidFill></p:bgPr></p:bg>';
        final PmlPresentation slideFill = _deck(<String>[
          _sld(_textBox(2, 'Own paper'), background: fill),
        ]);
        final PmlPresentation layoutFill = _deck(<String>[
          _sld(_textBox(2, 'Layout paper')),
        ], layoutBackground: fill);
        for (final PmlPresentation deck in <PmlPresentation>[
          slideFill,
          layoutFill,
        ]) {
          expect(deck.slides.single.background, 'FFFFFF');
          expect(deck.slides.single.inheritsMasterBackground, isFalse);
          expect(deck.slides.single.copy().inheritsMasterBackground, isFalse);
        }
      },
    );

    test(
      'imported secondary master paper survives until the master changes',
      () {
        String fill(String rgb) =>
            '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="$rgb"/>'
            '</a:solidFill></p:bgPr></p:bg>';
        final PmlPresentation deck = _deck(
          <String>[
            _sld(_textBox(2, 'Primary master')),
            _sld(_textBox(2, 'Secondary master')),
            _sld(_textBox(2, 'Explicit white'), background: fill('FFFFFF')),
          ],
          masterBackground: fill('AABBCC'),
          secondaryMasterBackground: fill('112233'),
        );
        expect(deck.master.background, 'AABBCC');
        expect(deck.slides.map((slide) => slide.background), <String>[
          'AABBCC',
          '112233',
          'FFFFFF',
        ]);
        expect(
          deck.slides.map((slide) => slide.inheritsMasterBackground),
          <bool>[true, true, false],
        );
        final PmlSlide copiedSecondary = deck.slides[1].copy(id: 999);
        expect(copiedSecondary.inheritsMasterBackground, isTrue);
        deck.master.background = 'aabbcc';
        expect(
          deck.slides[1].resolveBackground(deck.master.background),
          '112233',
        );
        expect(
          copiedSecondary.resolveBackground(deck.master.background),
          '112233',
        );
        deck.master.background = 'FF0000';
        expect(
          deck.slides.map(
            (slide) => slide.resolveBackground(deck.master.background),
          ),
          <String>['FF0000', 'FF0000', 'FFFFFF'],
        );
        expect(
          copiedSecondary.resolveBackground(deck.master.background),
          'FF0000',
        );
        expect(deck.slides[1].background, '112233');
        deck.master.background = '00FF00';
        expect(
          copiedSecondary.resolveBackground(deck.master.background),
          '00FF00',
        );
      },
    );

    test(
      'direct background assignments and copies preserve authored paper',
      () {
        final PmlSlide slide = PmlSlide(id: 256)
          ..setInheritedBackground('AABBCC', masterBackground: 'AABBCC');
        expect(slide.resolveBackground('112233'), '112233');
        slide.background = 'FFFFFF';
        expect(slide.inheritsMasterBackground, isFalse);
        expect(slide.resolveBackground('112233'), 'FFFFFF');
        final PmlSlide copy = slide.copy();
        expect(copy.inheritsMasterBackground, isFalse);
        expect(copy.resolveBackground('112233'), 'FFFFFF');
        slide.background = '';
        expect(slide.inheritsMasterBackground, isTrue);
        expect(slide.resolveBackground('445566'), '445566');
        expect(slide.resolveBackground(''), 'FFFFFF');
        expect(copy.resolveBackground('445566'), 'FFFFFF');
      },
    );

    test('scalar edits preserve imported rich styles and restore on undo', () {
      final PmlShape shape = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Rich"/>'
          '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
          '${_xfrm(0, 0, 9144000, 914400)}</p:spPr><p:txBody>'
          '<a:bodyPr/><a:p><a:r><a:rPr sz="1800" b="1"/>'
          '<a:t>Bold</a:t></a:r><a:r><a:rPr sz="2400" i="1"/>'
          '<a:t> Italic</a:t></a:r></a:p></p:txBody></p:sp>',
        ),
      ]).slides.single.shapes.single;
      final PmlTextSource source = shape.textSource!;
      shape
        ..fontSizePt = 32
        ..textColor = 'FF0000'
        ..textAlign = PmlTextAlign.right
        ..rightToLeft = true;
      final PmlTextParagraph edited = shape.resolvedRichText.single;
      expect(edited.runs.map((run) => run.fontSizePt), <double>[32, 32]);
      expect(edited.runs.map((run) => run.color), <String>['FF0000', 'FF0000']);
      expect(edited.runs.first.bold, isTrue);
      expect(edited.runs.last.italic, isTrue);
      expect(edited.align, PmlTextAlign.right);
      expect(edited.rightToLeft, isTrue);
      expect(shape.richText.single.runs.first.fontSizePt, 18);
      expect(shape.richText.single.runs.last.fontSizePt, 24);
      expect(shape.textSource, same(source));
      shape
        ..fontSizePt = source.fontSizePt
        ..textColor = source.textColor
        ..textAlign = source.textAlign
        ..rightToLeft = source.rightToLeft;
      expect(shape.resolvedRichText, same(shape.richText));
      shape.text = 'Replacement';
      expect(shape.resolvedRichText, isEmpty);
    });

    test('scheme colors and p:style refs resolve through the theme', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Rect"/><p:cNvSpPr/><p:nvPr/>'
          '</p:nvSpPr><p:spPr>${_xfrm(0, 0, 914400, 914400)}'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
          '<p:style><a:lnRef idx="2"><a:schemeClr val="accent1">'
          '<a:shade val="50000"/></a:schemeClr></a:lnRef><a:fillRef idx="1">'
          '<a:schemeClr val="accent1"/></a:fillRef><a:effectRef idx="0">'
          '<a:schemeClr val="accent1"/></a:effectRef><a:fontRef idx="minor">'
          '<a:schemeClr val="lt1"/></a:fontRef></p:style></p:sp>'
          '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Tinted"/><p:cNvSpPr/>'
          '<p:nvPr/></p:nvSpPr><p:spPr>${_xfrm(0, 0, 914400, 914400)}'
          '<a:solidFill><a:schemeClr val="bg1"><a:lumMod val="85000"/>'
          '</a:schemeClr></a:solidFill></p:spPr></p:sp>',
        ),
      ]);
      final List<PmlShape> shapes = deck.slides.single.shapes;
      expect(shapes[0].fillColor, '4472C4');
      expect(shapes[0].strokeColor, '223962');
      expect(shapes[0].textColor, 'FFFFFF');
      expect(shapes[1].fillColor, 'D9D9D9');
    });
  });

  group('layouts and placeholders', () {
    test('placeholders inherit layout geometry, then master geometry', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          _placeholder(2, 'ctrTitle', text: 'Quarterly review') +
              _placeholder(3, 'subTitle', idx: 1, text: 'Finance team'),
        ),
      ]);
      final PmlSlide slide = deck.slides.single;
      expect(slide.layoutName, 'Title Slide');
      final PmlShape title = slide.shapes[0];
      final PmlShape subtitle = slide.shapes[1];
      expect(title.placeholder, isTrue);
      expect(title.placeholderType, 'ctrTitle');
      expect(subtitle.placeholderIndex, 1);
      expect(
        <int>[
          title.transform.x,
          title.transform.y,
          title.transform.cx,
          title.transform.cy,
        ],
        <int>[685800, 2130425, 7772400, 1470025],
      );
      expect(
        <int>[
          subtitle.transform.x,
          subtitle.transform.y,
          subtitle.transform.cx,
          subtitle.transform.cy,
        ],
        <int>[1371600, 3886200, 6400800, 1752600],
      );
    });

    test('layouts are listed without their prompt text', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(_placeholder(2, 'ctrTitle')),
      ]);
      final PmlLayout layout = deck.layouts.single;
      expect(layout.name, 'Title Slide');
      expect(layout.placeholders, hasLength(2));
      expect(layout.placeholders.every((PmlShape s) => s.text.isEmpty), isTrue);
      expect(
        deck.resolveText(deck.slides.single.shapes.single, deck.slides.single),
        isEmpty,
      );
    });
  });

  group('slide order', () {
    test('follows sldIdLst through presentation.xml.rels', () {
      final PmlPresentation deck = _deck(
        <String>[
          _sld(_textBox(2, 'Slide A', xfrm: _xfrm(0, 0, 914400, 914400))),
          _sld(_textBox(2, 'Slide B', xfrm: _xfrm(0, 0, 914400, 914400))),
        ],
        order: <int>[1, 0],
      );
      expect(
        <String>[for (final PmlSlide s in deck.slides) s.shapes.single.text],
        <String>['Slide B', 'Slide A'],
      );
      expect(deck.slides.first.id, 257);
    });

    test('saving keeps the order and points sldId at real relationships', () {
      final PmlPresentation deck = _deck(
        <String>[
          _sld(_textBox(2, 'Slide A', xfrm: _xfrm(0, 0, 914400, 914400))),
          _sld(_textBox(2, 'Slide B', xfrm: _xfrm(0, 0, 914400, 914400))),
        ],
        order: <int>[1, 0],
      );
      final PmlPresentation reopened = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(deck),
      );
      expect(
        <String>[
          for (final PmlSlide s in reopened.slides) s.shapes.single.text,
        ],
        <String>['Slide B', 'Slide A'],
      );
    });
  });
}
