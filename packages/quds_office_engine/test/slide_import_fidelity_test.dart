import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}"';

String _sld(String shapes, {String root = 'sld', String name = ''}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:$root $_ns><p:cSld${name.isEmpty ? '' : ' name="$name"'}><p:spTree>'
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

/// A deck with one master, one "Title Slide" layout and the given slides.
PmlPresentation _deck(List<String> slides, {List<int>? order}) {
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
            _placeholder(3, 'subTitle', idx: 1, text: 'Click to add subtitle'),
        root: 'sldLayout',
        name: 'Title Slide',
      ),
    ),
  );
  package
      .relationshipsFor('/ppt/slideLayouts/slideLayout1.xml')
      .add(
        type: RelationshipTypes.slideMaster,
        target: '../slideMasters/slideMaster1.xml',
      );
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
          target: '../slideLayouts/slideLayout1.xml',
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
        'id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>'
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
      expect(picture.transform.x, 914400);
      expect(picture.transform.cx, 1828800);
      expect(picture.transform.cy, 1371600);
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
