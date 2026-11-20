import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
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
  String? showMasterShapes,
}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:$root $_ns${showMasterShapes == null ? '' : ' showMasterSp="$showMasterShapes"'}>'
    '<p:cSld${name.isEmpty ? '' : ' name="$name"'}>$background'
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

const String _pictureBackground =
    '<p:bg><p:bgPr><a:blipFill><a:blip r:embed="rId99"/>'
    '<a:stretch><a:fillRect/></a:stretch></a:blipFill></p:bgPr></p:bg>';

String _solidBackground(String color) =>
    '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="$color"/>'
    '</a:solidFill></p:bgPr></p:bg>';

String _gradientBackground(String first, String second) =>
    '<p:bg><p:bgPr><a:gradFill><a:gsLst>'
    '<a:gs pos="0"><a:srgbClr val="$first"/></a:gs>'
    '<a:gs pos="100000"><a:srgbClr val="$second"/></a:gs>'
    '</a:gsLst><a:lin ang="0" scaled="1"/></a:gradFill></p:bgPr></p:bg>';

Uint8List _backgroundPng(int red, int green, int blue) => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 1, height: 1)..setPixelRgba(0, 0, red, green, blue, 255),
  ),
);

/// A deck with a primary master/layout and an optional second-slide master.
PmlPresentation _deck(
  List<String> slides, {
  List<int>? order,
  String masterBackground = '',
  String layoutBackground = '',
  String? secondaryMasterBackground,
  String layoutShapes = '',
  String masterShapes = '',
  String? layoutShowMasterShapes,
  Uint8List? backgroundImage,
  Uint8List? layoutBackgroundImage,
  Uint8List? masterBackgroundImage,
  bool linkSlideLayout = true,
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
            ) +
            masterShapes,
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
        showMasterShapes: layoutShowMasterShapes,
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
  if (backgroundImage != null) {
    package.createPart(
      '/ppt/media/background.png',
      'image/png',
      backgroundImage,
    );
  }
  for (final entry in <(String, String, Uint8List?)>[
    (
      '/ppt/slideLayouts/slideLayout1.xml',
      'layout-background.png',
      layoutBackgroundImage,
    ),
    (
      '/ppt/slideMasters/slideMaster1.xml',
      'master-background.png',
      masterBackgroundImage,
    ),
  ]) {
    if (entry.$3 == null) continue;
    package.createPart('/ppt/media/${entry.$2}', 'image/png', entry.$3!);
    package
        .relationshipsFor(entry.$1)
        .add(
          type: RelationshipTypes.image,
          id: 'rId99',
          target: '../media/${entry.$2}',
        );
  }
  final List<String> ids = <String>[];
  for (int i = 0; i < slides.length; i++) {
    final String uri = '/ppt/slides/slide${i + 1}.xml';
    if (package.getPart(uri) == null) {
      package.createPart(uri, OfficeContentTypes.slide, utf8.encode(''));
    }
    package.getPart(uri)!.writeText(slides[i]);
    final RelationshipCollection slideRels = package.relationshipsFor(uri);
    if (linkSlideLayout) {
      slideRels.add(
        type: RelationshipTypes.slideLayout,
        target: secondaryMasterBackground != null && i == 1
            ? '../slideLayouts/slideLayout2.xml'
            : '../slideLayouts/slideLayout1.xml',
      );
    }
    if (backgroundImage != null) {
      slideRels.add(
        type: RelationshipTypes.image,
        id: 'rId99',
        target: '../media/background.png',
      );
    }
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

    test('decorations retain ownership, ordering and independent copies', () {
      final PmlPresentation deck = _deck(
        <String>[_sld(_textBox(9, 'Slide A')), _sld(_textBox(9, 'Slide B'))],
        masterShapes: _textBox(9, 'Master decoration'),
        layoutShapes: _textBox(9, 'Layout decoration'),
        layoutBackground:
            '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/>'
            '</a:solidFill></p:bgPr></p:bg>',
      );
      final PmlSlide first = deck.slides.first;
      expect(first.backgroundShapes.map((shape) => shape.text), <String>[
        'Master decoration',
        'Layout decoration',
      ]);
      expect(first.backgroundShapesResolved, isTrue);
      expect(first.inheritsMasterBackground, isFalse);
      expect(first.resolveBackground('112233'), 'FFFFFF');
      final PmlSlide copy = first.copy(id: 999);
      expect(copy.backgroundShapesResolved, isTrue);
      expect(copy.inheritsMasterBackground, isFalse);
      expect(copy.resolveBackground('112233'), 'FFFFFF');
      copy.backgroundShapes.first.text = 'Changed copy';
      expect(first.backgroundShapes.first.text, 'Master decoration');
      first.backgroundShapes.last.text = 'Changed first';
      expect(deck.slides.last.backgroundShapes.last.text, 'Layout decoration');
      expect(first.shapes.single.text, 'Slide A');
    });

    test('showMasterSp honors both levels of decoration inheritance', () {
      final PmlPresentation hiddenSlide = _deck(
        <String>[_sld(_textBox(2, 'Slide'), showMasterShapes: '0')],
        masterShapes: _textBox(9, 'Master decoration'),
        layoutShapes: _textBox(9, 'Layout decoration'),
      );
      expect(
        hiddenSlide.slides.single.backgroundShapes.map((shape) => shape.text),
        <String>['Layout decoration'],
      );
      expect(hiddenSlide.slides.single.backgroundShapesResolved, isTrue);
      expect(hiddenSlide.slides.single.showMasterShapes, isFalse);
      expect(hiddenSlide.slides.single.copy(id: 999).showMasterShapes, isFalse);
      final PmlPresentation hiddenMaster = _deck(
        <String>[_sld(_textBox(2, 'Slide'))],
        masterShapes: _textBox(9, 'Master decoration'),
        layoutShapes: _textBox(9, 'Layout decoration'),
        layoutShowMasterShapes: '0',
      );
      expect(
        hiddenMaster.slides.single.backgroundShapes.map((shape) => shape.text),
        <String>['Layout decoration'],
      );
      final PmlPresentation reopened = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(hiddenSlide),
      );
      expect(
        reopened.slides.single.backgroundShapes.map((shape) => shape.text),
        <String>['Layout decoration'],
      );
      expect(reopened.slides.single.backgroundShapesResolved, isTrue);
      expect(reopened.slides.single.showMasterShapes, isFalse);
    });

    test('master decorations precede layout and copy independently', () {
      final PmlSlide slide = _deck(
        <String>[_sld(_textBox(2, 'Slide'), showMasterShapes: 'true')],
        masterShapes: _textBox(8, 'Master'),
        layoutShapes: _textBox(9, 'Layout'),
        layoutShowMasterShapes: '1',
      ).slides.single;
      expect(slide.backgroundShapes.map((shape) => shape.text), [
        'Master',
        'Layout',
      ]);
      final PmlSlide copied = slide.copy(id: 900);
      expect(copied.showMasterShapes, isTrue);
      copied.backgroundShapes.first.text = 'Copied master';
      expect(slide.backgroundShapes.first.text, 'Master');
      expect(copied.shapes.single.text, 'Slide');
    });

    for (final String hidden in ['0', 'false']) {
      test('slide showMasterSp=$hidden survives saving and copying', () {
        final PmlPresentation deck = _deck(
          <String>[_sld(_textBox(2, 'Slide'), showMasterShapes: hidden)],
          masterShapes: _textBox(8, 'Master'),
          layoutShapes: _textBox(9, 'Layout'),
        );
        final PmlSlide slide = deck.slides.single;
        expect(slide.showMasterShapes, isFalse);
        expect(slide.backgroundShapesResolved, isTrue);
        expect(slide.copy().backgroundShapesResolved, isTrue);
        expect(slide.copy().showMasterShapes, isFalse);
        expect(slide.backgroundShapes.map((shape) => shape.text), ['Layout']);
        final PmlSlide saved = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single;
        expect(saved.showMasterShapes, isFalse);
        expect(saved.backgroundShapesResolved, isTrue);
        expect(saved.backgroundShapes.map((shape) => shape.text), ['Layout']);
        expect(saved.shapes.single.text, 'Slide');
      });

      test('layout showMasterSp=$hidden retains its own decorations', () {
        final PmlPresentation deck = _deck(
          <String>[_sld(_textBox(2, 'Slide'))],
          masterShapes: _textBox(8, 'Master'),
          layoutShapes: _textBox(9, 'Layout'),
          layoutShowMasterShapes: hidden,
        );
        expect(deck.slides.single.showMasterShapes, isTrue);
        expect(deck.slides.single.backgroundShapes.map((shape) => shape.text), [
          'Layout',
        ]);
        final PmlSlide saved = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single;
        expect(saved.backgroundShapes.map((shape) => shape.text), ['Layout']);
        expect(saved.shapes.single.text, 'Slide');
      });
    }

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

    for (final (horizontal, vertical, flipH, flipV)
        in <(String, String, bool, bool)>[
          ('1', '0', true, false),
          ('true', 'false', true, false),
          ('0', '1', false, true),
          ('false', 'true', false, true),
          ('true', 'true', true, true),
        ]) {
      test(
        'connector flips $horizontal/$vertical survive a PPTX roundtrip',
        () {
          final PmlPresentation deck = _deck(<String>[
            _sld(
              '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="2" name="Connector"/>'
              '<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>'
              '<a:xfrm flipH="$horizontal" flipV="$vertical">'
              '<a:off x="127000" y="254000"/>'
              '<a:ext cx="914400" cy="457200"/></a:xfrm>'
              '<a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
              '<a:ln w="12700"><a:solidFill><a:srgbClr val="C8C8C8"/>'
              '</a:solidFill></a:ln></p:spPr></p:cxnSp>',
            ),
          ]);
          final PmlShape imported = deck.slides.single.shapes.single;
          expect(imported.transform.flipH, flipH);
          expect(imported.transform.flipV, flipV);
          final PmlSlide copied = deck.slides.single.copy();
          expect(copied.shapes.single.transform.flipH, flipH);
          expect(copied.shapes.single.transform.flipV, flipV);
          final PmlPresentation reopened = SlideDeserializer().readBytes(
            SlideSerializer().writeBytes(deck),
          );
          final PmlShape saved = reopened.slides.single.shapes.single;
          expect(saved.preset, PmlShapePreset.connector);
          expect(saved.transform.flipH, flipH);
          expect(saved.transform.flipV, flipV);
          expect(saved.transform.x, 127000);
          expect(saved.transform.y, 254000);
          expect(saved.transform.cx, 914400);
          expect(saved.transform.cy, 457200);
        },
      );
    }

    test('background blip becomes a full-slide decoration', () {
      final Uint8List png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lK3cNwAAAABJRU5ErkJggg==',
      );
      final PmlPresentation deck = _deck(<String>[
        _sld(
          _textBox(2, 'Slide'),
          background:
              '<p:bg><p:bgPr><a:blipFill><a:blip r:embed="rId99"/>'
              '<a:stretch><a:fillRect/></a:stretch></a:blipFill>'
              '</p:bgPr></p:bg>',
        ),
      ], backgroundImage: png);
      final PmlShape image = deck.slides.single.backgroundShapes.first;
      expect(image.name, 'Background');
      expect(image.visual?.kind, OfficeVisualKind.picture);
      expect(image.visual?.imageBytes, png);
      expect(image.transform.cx, deck.slideWidth);
      expect(image.transform.cy, deck.slideHeight);
    });

    test('common geometric presets survive import', () {
      for (final (String prst, PmlShapePreset preset)
          in <(String, PmlShapePreset)>[
            ('diamond', PmlShapePreset.diamond),
            ('hexagon', PmlShapePreset.hexagon),
            ('pentagon', PmlShapePreset.pentagon),
            ('chevron', PmlShapePreset.chevron),
            ('parallelogram', PmlShapePreset.parallelogram),
            ('trapezoid', PmlShapePreset.trapezoid),
          ]) {
        final PmlPresentation deck = _deck(<String>[
          _sld(
            '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Shape"/>'
            '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
            '${_xfrm(0, 0, 914400, 914400)}'
            '<a:prstGeom prst="$prst"><a:avLst/></a:prstGeom>'
            '</p:spPr></p:sp>',
          ),
        ]);
        expect(deck.slides.single.shapes.single.preset, preset);
      }
    });

    test('gradient background replaces inherited image exactly once', () {
      const gradient =
          '<p:bg><p:bgPr><a:gradFill><a:gsLst>'
          '<a:gs pos="0"><a:srgbClr val="112233"/></a:gs>'
          '<a:gs pos="100000"><a:srgbClr val="AABBCC"/></a:gs>'
          '</a:gsLst><a:lin ang="5400000"/></a:gradFill></p:bgPr></p:bg>';
      final deck = _deck(
        [_sld('', background: gradient)],
        masterBackground: _pictureBackground,
        masterBackgroundImage: _backgroundPng(0, 255, 0),
      );
      for (final slide in [
        deck.slides.single,
        SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single,
      ]) {
        expect(slide.backgroundShapes, hasLength(1));
        expect(slide.backgroundShapes.single.gradient?.stops, hasLength(2));
        expect(slide.backgroundShapes.single.gradient?.angleDegrees, 90);
        expect(slide.backgroundShapes.single.visual?.imageBytes, isNull);
      }
    });

    test(
      'authored slide image replaces inherited images behind decorations',
      () {
        final Uint8List slidePng = _backgroundPng(255, 0, 0);
        final PmlPresentation deck = _deck(
          <String>[_sld(_textBox(2, 'Slide'), background: _pictureBackground)],
          backgroundImage: slidePng,
          masterBackground: _pictureBackground,
          masterBackgroundImage: _backgroundPng(0, 255, 0),
          layoutBackground: _pictureBackground,
          layoutBackgroundImage: _backgroundPng(0, 0, 255),
          masterShapes: _textBox(8, 'Master decoration'),
          layoutShapes: _textBox(9, 'Layout decoration'),
        );
        for (final PmlSlide slide in <PmlSlide>[
          deck.slides.single,
          deck.slides.single.copy(),
          SlideDeserializer()
              .readBytes(SlideSerializer().writeBytes(deck))
              .slides
              .single,
        ]) {
          expect(slide.backgroundShapes.map((shape) => shape.name), <String>[
            'Background',
            'TextBox 8',
            'TextBox 9',
          ]);
          expect(slide.backgroundShapes.first.visual?.imageBytes, slidePng);
          expect(slide.inheritsMasterBackground, isFalse);
        }
      },
    );

    test(
      'copied authored background gets a valid new slide image relationship',
      () {
        final Uint8List png = _backgroundPng(240, 120, 20);
        final PmlPresentation deck = _deck(<String>[
          _sld('', background: _pictureBackground),
        ], backgroundImage: png);
        final PmlSlide original = deck.slides.single;
        final PmlSlide copy = original.copy(id: 999);
        expect(copy.sourcePartUri, isNull);
        expect(
          identical(copy.sourceBackground, original.sourceBackground),
          isFalse,
        );
        expect(
          identical(copy.backgroundPicture, original.backgroundPicture),
          isFalse,
        );
        deck.slides.add(copy);

        final PmlPresentation reopened = SlideDeserializer().readBytes(
          SlideSerializer().writeBytes(deck),
        );
        expect(reopened.slides, hasLength(2));
        expect(
          reopened.slides.map((slide) => slide.sourcePartUri).toSet(),
          hasLength(2),
        );
        for (final PmlSlide slide in reopened.slides) {
          expect(slide.backgroundPicture?.visual?.imageBytes, png);
          final RelationshipCollection rels = reopened.package!
              .relationshipsFor(slide.sourcePartUri!);
          final PackageRelationship? rel = rels.byId(
            slide.backgroundPicture!.embedRelId!,
          );
          expect(rel?.type, RelationshipTypes.image);
          expect(rel?.targetMode, RelationshipTargetMode.internal);
          expect(
            reopened.package!.getPart(rels.resolve(rel!))?.readBytes(),
            png,
          );
        }
      },
    );

    test(
      'explicit background edits clear imported fill and keep decorations',
      () {
        final PmlPresentation deck = _deck(
          <String>[_sld('', background: _pictureBackground)],
          backgroundImage: _backgroundPng(240, 120, 20),
          layoutBackground: _pictureBackground,
          layoutBackgroundImage: _backgroundPng(20, 120, 240),
          masterShapes: _textBox(8, 'Master decoration'),
        );
        final PmlSlide slide = deck.slides.single;
        final PmlSlide untouched = slide.copy();
        slide.background = '112233';
        expect(slide.sourceBackground, isNull);
        expect(slide.backgroundPicture, isNull);
        expect(slide.backgroundShapes.map((shape) => shape.text), <String>[
          'Master decoration',
        ]);
        expect(untouched.backgroundPicture, isNotNull);
        final PmlSlide saved = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single;
        expect(saved.background, '112233');
        expect(saved.backgroundPicture, isNull);
        expect(saved.inheritsMasterBackground, isFalse);

        slide.background = '';
        final PmlSlide inherited = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single;
        expect(inherited.sourceBackground, isNull);
        expect(
          inherited.backgroundPicture?.visual?.imageBytes,
          _backgroundPng(20, 120, 240),
        );
      },
    );

    test(
      'authored gradient retains all stops and inherited namespace bindings',
      () {
        final String xml = _sld(
          '',
          background: _gradientBackground(
            '123456',
            '654321',
          ).replaceAll('a:', 'ink:'),
        ).replaceFirst('<p:sld ', '<p:sld xmlns:ink="${OfficeNamespaces.a}" ');
        final PmlPresentation reopened = SlideDeserializer().readBytes(
          SlideSerializer().writeBytes(_deck(<String>[xml])),
        );
        final PmlSlide slide = reopened.slides.single;
        expect(slide.background, '123456');
        final XmlElement? stops = slide.sourceBackground
            ?.firstChild('bgPr', namespaceUri: OfficeNamespaces.p)
            ?.firstChild('gradFill', namespaceUri: OfficeNamespaces.a)
            ?.firstChild('gsLst', namespaceUri: OfficeNamespaces.a);
        expect(stops, isNotNull);
        expect(
          stops!.childElements.map(
            (stop) => stop
                .firstChild('srgbClr', namespaceUri: OfficeNamespaces.a)
                ?.getAttribute('val'),
          ),
          <String>['123456', '654321'],
        );
      },
    );

    test('authored noFill survives saving and suppresses inherited images', () {
      final PmlPresentation deck = _deck(
        <String>[
          _sld('', background: '<p:bg><p:bgPr><a:noFill/></p:bgPr></p:bg>'),
        ],
        masterBackground: _pictureBackground,
        masterBackgroundImage: _backgroundPng(20, 120, 240),
      );
      final PmlSlide slide = SlideDeserializer()
          .readBytes(SlideSerializer().writeBytes(deck))
          .slides
          .single;
      expect(slide.backgroundShapes, isEmpty);
      expect(slide.inheritsMasterBackground, isFalse);
      expect(
        slide.sourceBackground
            ?.firstChild('bgPr', namespaceUri: OfficeNamespaces.p)
            ?.firstChild('noFill', namespaceUri: OfficeNamespaces.a),
        isNotNull,
      );
    });

    for (final bool local in <bool>[true, false]) {
      test(
        '${local ? 'slide' : 'layout'} solid background suppresses inherited images',
        () {
          final PmlPresentation deck = _deck(
            <String>[
              _sld(
                _textBox(2, 'Slide'),
                background: local ? _solidBackground('FFFFFF') : '',
              ),
            ],
            masterBackground: _pictureBackground,
            masterBackgroundImage: _backgroundPng(0, 255, 0),
            layoutBackground: local
                ? _pictureBackground
                : _solidBackground('FFFFFF'),
            layoutBackgroundImage: local ? _backgroundPng(0, 0, 255) : null,
            masterShapes: _textBox(8, 'Master decoration'),
            layoutShapes: _textBox(9, 'Layout decoration'),
          );
          expect(deck.slides.single.background, 'FFFFFF');
          expect(deck.slides.single.inheritsMasterBackground, isFalse);
          expect(
            deck.slides.single.backgroundShapes.map((shape) => shape.text),
            <String>['Master decoration', 'Layout decoration'],
          );
        },
      );
    }

    test('layout image replaces master image below ordinary decorations', () {
      final Uint8List layoutPng = _backgroundPng(0, 0, 255);
      final PmlSlide slide = _deck(
        <String>[_sld(_textBox(2, 'Slide'))],
        masterBackground: _pictureBackground,
        masterBackgroundImage: _backgroundPng(0, 255, 0),
        layoutBackground: _pictureBackground,
        layoutBackgroundImage: layoutPng,
        masterShapes: _textBox(8, 'Master decoration'),
        layoutShapes: _textBox(9, 'Layout decoration'),
      ).slides.single;
      expect(slide.backgroundShapes.map((shape) => shape.name), <String>[
        'Background',
        'TextBox 8',
        'TextBox 9',
      ]);
      expect(slide.backgroundShapes.first.visual?.imageBytes, layoutPng);
      expect(slide.inheritsMasterBackground, isFalse);
    });

    for (final bool hideAtSlide in <bool>[true, false]) {
      test(
        '${hideAtSlide ? 'slide' : 'layout'} showMasterSp hides decorations but keeps background image',
        () {
          final Uint8List masterPng = _backgroundPng(0, 255, 0);
          final PmlSlide slide = _deck(
            <String>[
              _sld(
                _textBox(2, 'Slide'),
                showMasterShapes: hideAtSlide ? '0' : null,
              ),
            ],
            layoutShowMasterShapes: hideAtSlide ? null : 'false',
            masterBackground: _pictureBackground,
            masterBackgroundImage: masterPng,
            masterShapes: _textBox(8, 'Master decoration'),
            layoutShapes: _textBox(9, 'Layout decoration'),
          ).slides.single;
          expect(slide.backgroundShapes.map((shape) => shape.name), <String>[
            'Background',
            'TextBox 9',
          ]);
          expect(slide.backgroundShapes.first.visual?.imageBytes, masterPng);
          expect(slide.inheritsMasterBackground, isTrue);
        },
      );
    }

    test('authored image background does not need a layout relationship', () {
      final Uint8List png = _backgroundPng(255, 0, 0);
      final PmlSlide slide = _deck(
        <String>[_sld(_textBox(2, 'Slide'), background: _pictureBackground)],
        backgroundImage: png,
        linkSlideLayout: false,
      ).slides.single;
      expect(slide.backgroundShapes.single.visual?.imageBytes, png);
      expect(slide.inheritsMasterBackground, isFalse);
    });

    test(
      'gradient rendering follows slide layout and secondary master scope',
      () {
        final PmlPresentation masters = _deck(
          <String>[_sld(''), _sld('')],
          masterBackground: _gradientBackground('112233', '445566'),
          secondaryMasterBackground: _gradientBackground('778899', 'AABBCC'),
        );
        expect(masters.master.background, '112233');
        expect(masters.slides.map((slide) => slide.background), <String>[
          '112233',
          '778899',
        ]);
        final PmlPresentation overrides = _deck(
          <String>[
            _sld('', background: _gradientBackground('123456', '654321')),
          ],
          masterBackground: _pictureBackground,
          masterBackgroundImage: _backgroundPng(0, 255, 0),
          layoutBackground: _gradientBackground('ABCDEF', 'FEDCBA'),
        );
        expect(overrides.slides.single.background, '123456');
        expect(overrides.slides.single.backgroundShapes, hasLength(1));
        expect(
          overrides
              .slides
              .single
              .backgroundGradient
              ?.gradient
              ?.stops
              .first
              .color,
          '123456',
        );
        expect(overrides.slides.single.inheritsMasterBackground, isFalse);
        final PmlPresentation layout = _deck(
          <String>[_sld('')],
          masterBackground: _pictureBackground,
          masterBackgroundImage: _backgroundPng(0, 255, 0),
          layoutBackground: _gradientBackground('ABCDEF', 'FEDCBA'),
        );
        expect(layout.slides.single.background, 'ABCDEF');
        expect(layout.slides.single.backgroundShapes, hasLength(1));
        expect(
          layout.slides.single.backgroundGradient?.gradient?.stops.first.color,
          'ABCDEF',
        );
        expect(layout.slides.single.inheritsMasterBackground, isFalse);
      },
    );

    test('normal autofit keeps its authored scale and spacing reduction', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Fitted"/>'
          '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>'
          '${_xfrm(0, 0, 9144000, 914400)}</p:spPr><p:txBody>'
          '<a:bodyPr><a:normAutofit fontScale="80000" '
          'lnSpcReduction="10000"/></a:bodyPr><a:p><a:r>'
          '<a:rPr sz="1800"/><a:t>Fitted</a:t></a:r></a:p>'
          '</p:txBody></p:sp>',
        ),
      ]);
      final PmlShape shape = deck.slides.single.shapes.single;
      expect(shape.textScale, closeTo(0.8, 0.00001));
      expect(shape.lineSpacingReduction, closeTo(0.1, 0.00001));
    });

    test(
      'selected gradient survives copies and repeated saves then clears on edit',
      () {
        final PmlPresentation deck = _deck(
          <String>[
            _sld('', background: _gradientBackground('112233', 'AABBCC')),
          ],
          masterBackground: _pictureBackground,
          masterBackgroundImage: _backgroundPng(0, 255, 0),
          masterShapes: _textBox(8, 'Master decoration'),
        );
        final PmlSlide copy = deck.slides.single.copy(id: 999);
        expect(
          copy.backgroundGradient,
          isNot(same(deck.slides.single.backgroundGradient)),
        );
        expect(copy.backgroundGradient?.gradient?.stops, hasLength(2));
        deck.slides.add(copy);
        PmlPresentation saved = deck;
        for (var i = 0; i < 2; i++) {
          saved = SlideDeserializer().readBytes(
            SlideSerializer().writeBytes(saved),
          );
          for (final PmlSlide slide in saved.slides) {
            expect(slide.backgroundPicture, isNull);
            expect(
              slide.backgroundGradient?.gradient?.stops.first.color,
              '112233',
            );
            expect(slide.backgroundShapes.map((shape) => shape.name), [
              'Background',
              'TextBox 8',
            ]);
          }
        }
        saved.slides.first.background = '556677';
        final PmlSlide changed = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(saved))
            .slides
            .first;
        expect(changed.backgroundGradient, isNull);
        expect(changed.backgroundShapes.map((shape) => shape.name), [
          'TextBox 8',
        ]);
        expect(changed.background, '556677');
        expect(saved.slides.last.backgroundGradient, isNotNull);
      },
    );

    test(
      'master gradient survives hidden decorations and layout solid overrides it',
      () {
        final PmlSlide inherited = _deck(
          <String>[_sld('', showMasterShapes: '0')],
          masterBackground: _gradientBackground('112233', 'AABBCC'),
          masterShapes: _textBox(8, 'Hidden decoration'),
        ).slides.single;
        expect(inherited.backgroundShapes, hasLength(1));
        expect(
          inherited.backgroundGradient,
          same(inherited.backgroundShapes.single),
        );
        expect(inherited.inheritsMasterBackground, isTrue);
        inherited.updateMasterBackground('778899');
        expect(inherited.backgroundGradient, isNull);
        expect(inherited.backgroundShapes, isEmpty);
        final PmlSlide overridden = _deck(
          <String>[_sld('')],
          masterBackground: _gradientBackground('112233', 'AABBCC'),
          layoutBackground: _solidBackground('778899'),
        ).slides.single;
        expect(overridden.backgroundGradient, isNull);
        expect(overridden.backgroundShapes, isEmpty);
        expect(overridden.background, '778899');
      },
    );

    test('gradient fills retain stops and angle', () {
      final PmlPresentation deck = _deck(<String>[
        _sld(
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Gradient"/>'
          '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
          '${_xfrm(0, 0, 914400, 914400)}'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
          '<a:gradFill><a:gsLst>'
          '<a:gs pos="0"><a:srgbClr val="112233"/></a:gs>'
          '<a:gs pos="100000"><a:srgbClr val="AABBCC"/></a:gs>'
          '</a:gsLst><a:lin ang="5400000"/></a:gradFill>'
          '</p:spPr></p:sp>',
        ),
      ]);
      final PmlShape shape = deck.slides.single.shapes.single;
      expect(shape.gradient?.stops, hasLength(2));
      expect(shape.gradient!.stops.first.color, '112233');
      expect(shape.gradient!.stops.last.color, 'AABBCC');
      expect(shape.gradient!.angleDegrees, 90);
      expect(shape.fillColor, '112233');
      final PmlPresentation reopened = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(deck),
      );
      expect(
        reopened.slides.single.shapes.single.gradient?.stops,
        hasLength(2),
      );
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
