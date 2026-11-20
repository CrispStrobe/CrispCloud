import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}"';

String _picture({String crop = ''}) =>
    '<p:bg><p:bgPr><a:blipFill><a:blip r:embed="rImage"/>$crop'
    '<a:stretch><a:fillRect/></a:stretch></a:blipFill></p:bgPr></p:bg>';

String _solid(String color) =>
    '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="$color"/>'
    '</a:solidFill></p:bgPr></p:bg>';

String _decoration(String name, String color) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="9" name="$name"/><p:cNvSpPr/>'
    '<p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/>'
    '<a:ext cx="127000" cy="127000"/></a:xfrm><a:prstGeom prst="rect"/>'
    '<a:solidFill><a:srgbClr val="$color"/></a:solidFill></p:spPr></p:sp>';

String _part(
  String root,
  String background,
  String shapes, {
  bool showMaster = true,
}) =>
    '<p:$root $_ns${showMaster ? '' : ' showMasterSp="0"'}><p:cSld>'
    '$background<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
    '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>$shapes'
    '</p:spTree></p:cSld></p:$root>';

Uint8List _pixel(int red, int green, int blue) => PngBytes.rgb(
  width: 1,
  height: 1,
  plot: (x, y, rgb) {
    rgb[0] = red;
    rgb[1] = green;
    rgb[2] = blue;
  },
);

final _masterImage = _pixel(255, 0, 0);
final _layoutImage = _pixel(0, 255, 0);
final _slideImage = _pixel(0, 0, 255);

PmlPresentation _deck({
  String master = '',
  String layout = '',
  String slide = '',
  bool showMaster = true,
  bool layoutShowMaster = true,
  bool withLayout = true,
  bool externalSlideImage = false,
  String slideImageType = RelationshipTypes.image,
}) {
  final package = OpcPackage.create(OpcPackageKind.slide);
  void put(String uri, String type, String text) {
    final existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, type, utf8.encode(text));
    } else {
      existing.writeText(text);
    }
  }

  const presUri = '/ppt/presentation.xml';
  const masterUri = '/ppt/slideMasters/slideMaster1.xml';
  const layoutUri = '/ppt/slideLayouts/slideLayout1.xml';
  const slideUri = '/ppt/slides/slide1.xml';
  final presRels = package.relationshipsFor(presUri);
  for (final rel in presRels.items.toList()) {
    presRels.removeById(rel.id);
  }
  presRels
    ..add(
      type: RelationshipTypes.slideMaster,
      target: 'slideMasters/slideMaster1.xml',
      id: 'rMaster',
    )
    ..add(
      type: RelationshipTypes.slide,
      target: 'slides/slide1.xml',
      id: 'rSlide',
    );
  put(
    presUri,
    OfficeContentTypes.slideMain,
    '<p:presentation $_ns><p:sldMasterIdLst>'
    '<p:sldMasterId id="2147483648" r:id="rMaster"/></p:sldMasterIdLst>'
    '<p:sldIdLst><p:sldId id="256" r:id="rSlide"/></p:sldIdLst>'
    '<p:sldSz cx="9144000" cy="5143500"/></p:presentation>',
  );
  put(
    masterUri,
    OfficeContentTypes.slideMaster,
    _part('sldMaster', master, _decoration('Master decoration', 'AA0000')),
  );
  put(
    layoutUri,
    OfficeContentTypes.slideLayout,
    _part(
      'sldLayout',
      layout,
      _decoration('Layout decoration', '00AA00'),
      showMaster: layoutShowMaster,
    ),
  );
  put(
    slideUri,
    OfficeContentTypes.slide,
    _part('sld', slide, '', showMaster: showMaster),
  );
  package
      .relationshipsFor(masterUri)
      .add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout1.xml',
      );
  package
      .relationshipsFor(layoutUri)
      .add(
        type: RelationshipTypes.slideMaster,
        target: '../slideMasters/slideMaster1.xml',
      );
  if (withLayout) {
    package
        .relationshipsFor(slideUri)
        .add(
          type: RelationshipTypes.slideLayout,
          target: '../slideLayouts/slideLayout1.xml',
        );
  }
  for (final (owner, name, bytes) in [
    (masterUri, 'master', _masterImage),
    (layoutUri, 'layout', _layoutImage),
    (slideUri, 'slide', _slideImage),
  ]) {
    package.createPart('/ppt/media/$name.png', 'image/png', bytes);
    package
        .relationshipsFor(owner)
        .add(
          type: owner == slideUri ? slideImageType : RelationshipTypes.image,
          target: owner == slideUri && externalSlideImage
              ? 'https://example.invalid/background.png'
              : '../media/$name.png',
          id: 'rImage',
          targetMode: owner == slideUri && externalSlideImage
              ? RelationshipTargetMode.external
              : RelationshipTargetMode.internal,
        );
  }
  return SlideDeserializer().read(package);
}

List<PmlShape> _pictures(PmlSlide slide) => slide.backgroundShapes
    .where((shape) => shape.visual?.isPicture ?? false)
    .toList();

PmlPresentation _reopen(PmlPresentation deck) =>
    SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));

void main() {
  group('picture background ownership', () {
    test('slide picture wins over layout and master before decorations', () {
      final slide = _deck(
        master: _picture(),
        layout: _picture(),
        slide: _picture(),
      ).slides.single;
      expect(_pictures(slide), hasLength(1));
      expect(_pictures(slide).single.visual!.imageBytes, _slideImage);
      expect(slide.backgroundShapes.map((shape) => shape.name), [
        'Background',
        'Master decoration',
        'Layout decoration',
      ]);
    });

    test('layout picture replaces the master picture', () {
      final slide = _deck(master: _picture(), layout: _picture()).slides.single;
      expect(_pictures(slide), hasLength(1));
      expect(_pictures(slide).single.visual!.imageBytes, _layoutImage);
    });

    test('absent local backgrounds inherit the master picture', () {
      final slide = _deck(master: _picture()).slides.single;
      expect(_pictures(slide), hasLength(1));
      expect(_pictures(slide).single.visual!.imageBytes, _masterImage);
    });

    for (final owner in ['slide', 'layout']) {
      test('$owner solid fill suppresses the inherited picture', () {
        final slide = _deck(
          master: _picture(),
          layout: owner == 'layout' ? _solid('123456') : _picture(),
          slide: owner == 'slide' ? _solid('123456') : '',
        ).slides.single;
        expect(_pictures(slide), isEmpty);
        expect(slide.background, '123456');
      });
    }

    for (final owner in ['slide', 'layout']) {
      test(
        '$owner master-shape suppression preserves the inherited background',
        () {
          final slide = _deck(
            master: _picture(),
            showMaster: owner != 'slide',
            layoutShowMaster: owner != 'layout',
          ).slides.single;
          expect(_pictures(slide), hasLength(1));
          expect(_pictures(slide).single.visual!.imageBytes, _masterImage);
          expect(slide.backgroundShapes.map((shape) => shape.name), [
            'Background',
            'Layout decoration',
          ]);
        },
      );
    }

    test('slide-owned picture is loaded without a layout relationship', () {
      final slide = _deck(slide: _picture(), withLayout: false).slides.single;
      expect(_pictures(slide), hasLength(1));
      expect(_pictures(slide).single.visual!.imageBytes, _slideImage);
    });

    test('authored noFill does not reveal an inherited picture', () {
      final slide = _deck(
        master: _picture(),
        slide: '<p:bg><p:bgPr><a:noFill/></p:bgPr></p:bg>',
      ).slides.single;
      expect(_pictures(slide), isEmpty);
      expect(slide.background, 'FFFFFF');
    });

    test('external background image is not resolved as package content', () {
      final slide = _deck(
        master: _picture(),
        slide: _picture(),
        externalSlideImage: true,
      ).slides.single;
      expect(_pictures(slide), isEmpty);
    });

    test('a non-image relationship cannot become a picture background', () {
      final slide = _deck(
        slide: _picture(),
        slideImageType: RelationshipTypes.hyperlink,
      ).slides.single;
      expect(_pictures(slide), isEmpty);
    });

    test('first gradient stop is used consistently at every owner', () {
      const gradient =
          '<p:bg><p:bgPr><a:gradFill><a:gsLst>'
          '<a:gs pos="0"><a:srgbClr val="332211"/></a:gs>'
          '<a:gs pos="100000"><a:srgbClr val="ABCDEF"/></a:gs>'
          '</a:gsLst></a:gradFill></p:bgPr></p:bg>';
      for (final owner in ['master', 'layout', 'slide']) {
        final slide = _deck(
          master: owner == 'master' ? gradient : _solid('FFFFFF'),
          layout: owner == 'layout' ? gradient : '',
          slide: owner == 'slide' ? gradient : '',
        ).slides.single;
        expect(slide.background, '332211', reason: owner);
      }
    });

    test('an effect color never becomes the paper color', () {
      final slide = _deck(
        master:
            '<p:bg><p:bgPr><a:noFill/><a:effectLst><a:outerShdw>'
            '<a:srgbClr val="FF0000"/></a:outerShdw></a:effectLst>'
            '</p:bgPr></p:bg>',
      ).slides.single;
      expect(slide.background, 'FFFFFF');
    });
  });

  group('picture background publication', () {
    for (final owner in ['master', 'layout', 'slide']) {
      test('$owner picture survives two native saves without duplication', () {
        var deck = _deck(
          master: owner == 'master' ? _picture() : '',
          layout: owner == 'layout' ? _picture() : '',
          slide: owner == 'slide' ? _picture() : '',
        );
        final expected = switch (owner) {
          'master' => _masterImage,
          'layout' => _layoutImage,
          _ => _slideImage,
        };
        for (var save = 0; save < 2; save++) {
          deck = _reopen(deck);
          expect(_pictures(deck.slides.single), hasLength(1));
          expect(
            _pictures(deck.slides.single).single.visual!.imageBytes,
            expected,
          );
        }
      });
    }

    test('a copied slide retains its own background media relationship', () {
      final deck = _deck(master: _picture(), slide: _picture());
      deck.slides.add(deck.slides.single.copy(id: 257));
      final saved = _reopen(deck);
      expect(saved.slides, hasLength(2));
      for (final slide in saved.slides) {
        expect(_pictures(slide), hasLength(1));
        expect(_pictures(slide).single.visual!.imageBytes, _slideImage);
      }
      expect(
        saved.slides[0].sourcePartUri,
        isNot(saved.slides[1].sourcePartUri),
      );
    });

    test('cropping survives picture background import and save', () {
      final deck = _deck(
        slide: _picture(
          crop: '<a:srcRect l="10000" t="20000" r="30000" b="5000"/>',
        ),
      );
      for (final candidate in [deck, _reopen(deck)]) {
        final picture = _pictures(
          candidate.slides.single,
        ).single.visual!.picture;
        expect(picture.cropLeft, closeTo(.1, 1e-6));
        expect(picture.cropTop, closeTo(.2, 1e-6));
        expect(picture.cropRight, closeTo(.3, 1e-6));
        expect(picture.cropBottom, closeTo(.05, 1e-6));
      }
    });

    test('assigning a solid slide fill replaces its picture background', () {
      final deck = _deck(master: _picture(), slide: _picture());
      deck.slides.single.background = '112233';
      expect(_pictures(deck.slides.single), isEmpty);
      final saved = _reopen(deck).slides.single;
      expect(_pictures(saved), isEmpty);
      expect(saved.background, '112233');
    });
  });

  group('background integrity', () {
    test(
      'saving pictures never overwrites retained master or layout media',
      () {
        final source = _deck(master: _picture(), slide: _picture());
        final package = source.package!;
        for (final (owner, uri, bytes) in [
          (
            '/ppt/slideMasters/slideMaster1.xml',
            '/ppt/media/slide1_image1.png',
            _masterImage,
          ),
          (
            '/ppt/slideLayouts/slideLayout1.xml',
            '/ppt/media/slide1_image2.png',
            _layoutImage,
          ),
        ]) {
          package.createPart(uri, 'image/png', bytes);
          final rels = package.relationshipsFor(owner);
          rels.removeById('rImage');
          rels.add(
            type: RelationshipTypes.image,
            id: 'rImage',
            target: '../media/${uri.split('/').last}',
          );
        }
        final retained = <String, Uint8List>{
          for (final part in package.parts)
            if (part.uri.startsWith('/ppt/media/')) part.uri: part.readBytes(),
        };
        final deck = SlideDeserializer().read(package);
        deck.slides.single.shapes.add(
          PmlShape(
            id: 20,
            name: 'Editable picture',
            visual: OfficeVisual(
              kind: OfficeVisualKind.picture,
              imageBytes: _layoutImage,
            ),
          ),
        );
        int? mediaCount;
        for (var save = 0; save < 2; save++) {
          final saved = SlideSerializer().write(deck);
          for (final entry in retained.entries) {
            expect(
              saved.getPart(entry.key)!.readBytes(),
              entry.value,
              reason: entry.key,
            );
          }
          final reopened = SlideDeserializer().readBytes(saved.save());
          expect(
            _pictures(reopened.slides.single).single.visual!.imageBytes,
            _slideImage,
          );
          expect(
            reopened.slides.single.shapes.single.visual!.imageBytes,
            _layoutImage,
          );
          expect(
            saved
                .relationshipsFor('/ppt/slideMasters/slideMaster1.xml')
                .byId('rImage')!
                .target,
            '../media/slide1_image1.png',
          );
          final count = saved.parts
              .where((part) => part.uri.startsWith('/ppt/media/'))
              .length;
          if (mediaCount != null) expect(count, mediaCount);
          mediaCount = count;
        }
      },
    );

    for (final (name, crop, expected) in [
      (
        'deep and negative',
        '<a:srcRect l="75000" t="-10000" r="5000" b="0"/>',
        <double>[.75, -.1, .05, 0],
      ),
      (
        'negative only',
        '<a:srcRect l="-99000" t="0" r="0" b="-25000"/>',
        <double>[-.99, 0, 0, -.25],
      ),
    ]) {
      test('$name background crop survives repeated native saves', () {
        var deck = _deck(slide: _picture(crop: crop));
        for (var save = 0; save < 3; save++) {
          final picture = _pictures(deck.slides.single).single.visual!.picture;
          expect([
            picture.cropLeft,
            picture.cropTop,
            picture.cropRight,
            picture.cropBottom,
          ], expected);
          deck = _reopen(deck);
        }
      });
    }

    for (final color in ['112233', 'FFFFFF']) {
      test(
        'master solid $color replaces inherited pictures and stays inherited',
        () {
          var deck = _deck(master: _picture());
          deck.master.background = color;
          deck.slides.single.updateMasterBackground(color);
          expect(_pictures(deck.slides.single), isEmpty);
          expect(deck.slides.single.inheritsMasterBackground, isTrue);
          for (var save = 0; save < 2; save++) {
            deck = _reopen(deck);
            expect(deck.master.background, color);
            expect(deck.slides.single.background, color);
            expect(deck.slides.single.inheritsMasterBackground, isTrue);
            expect(_pictures(deck.slides.single), isEmpty);
            expect(
              deck.slides.single.backgroundShapes.map((shape) => shape.name),
              ['Master decoration', 'Layout decoration'],
            );
          }
        },
      );
    }

    test(
      'an unchanged master picture remains editable after save and copy',
      () {
        var deck = _reopen(_deck(master: _picture()));
        expect(deck.slides.single.inheritsMasterBackground, isTrue);
        deck.slides.add(deck.slides.single.copy(id: 257));
        deck = _reopen(deck);
        for (final slide in deck.slides) {
          expect(slide.inheritsMasterBackground, isTrue);
          expect(_pictures(slide).single.visual!.imageBytes, _masterImage);
        }
        deck.master.background = '445566';
        for (final slide in deck.slides) {
          slide.updateMasterBackground('445566');
        }
        deck = _reopen(deck);
        for (final slide in deck.slides) {
          expect(slide.inheritsMasterBackground, isTrue);
          expect(slide.background, '445566');
          expect(_pictures(slide), isEmpty);
        }
      },
    );

    test(
      'copied secondary-master picture retains its layout and inheritance',
      () {
        final package = _deck(master: _picture()).package!;
        const masterUri = '/ppt/slideMasters/slideMaster2.xml';
        const layoutUri = '/ppt/slideLayouts/slideLayout2.xml';
        package.createPart(
          masterUri,
          OfficeContentTypes.slideMaster,
          utf8.encode(_part('sldMaster', _picture(), '')),
        );
        package.createPart(
          layoutUri,
          OfficeContentTypes.slideLayout,
          utf8.encode(_part('sldLayout', '', '')),
        );
        package
            .relationshipsFor(masterUri)
            .add(
              type: RelationshipTypes.image,
              id: 'rImage',
              target: '../media/layout.png',
            );
        package
            .relationshipsFor(layoutUri)
            .add(
              type: RelationshipTypes.slideMaster,
              target: '../slideMasters/slideMaster2.xml',
            );
        final slideRels = package.relationshipsFor('/ppt/slides/slide1.xml');
        for (final rel
            in slideRels.byType(RelationshipTypes.slideLayout).toList()) {
          slideRels.removeById(rel.id);
        }
        slideRels.add(
          type: RelationshipTypes.slideLayout,
          target: '../slideLayouts/slideLayout2.xml',
        );
        var deck = SlideDeserializer().read(package);
        deck.slides.add(deck.slides.single.copy(id: 257));
        for (var save = 0; save < 2; save++) {
          deck = _reopen(deck);
          for (final slide in deck.slides) {
            expect(_pictures(slide).single.visual!.imageBytes, _layoutImage);
            expect(slide.inheritsMasterBackground, isTrue);
            final rels = deck.package!.relationshipsFor(slide.sourcePartUri!);
            expect(
              rels.resolve(rels.firstByType(RelationshipTypes.slideLayout)!),
              layoutUri,
            );
          }
        }
      },
    );

    for (final owner in ['slide', 'layout']) {
      test('master edits preserve explicit $owner picture backgrounds', () {
        var deck = _deck(
          master: _picture(),
          slide: owner == 'slide' ? _picture() : '',
          layout: owner == 'layout' ? _picture() : '',
        );
        final expected = owner == 'slide' ? _slideImage : _layoutImage;
        deck.master.background = '112233';
        deck.slides.single.updateMasterBackground('112233');
        deck = _reopen(deck);
        expect(
          _pictures(deck.slides.single).single.visual!.imageBytes,
          expected,
        );
        expect(deck.slides.single.inheritsMasterBackground, isFalse);
        expect(deck.master.background, '112233');
      });
    }

    test('a newly authored master solid fill is saved natively', () {
      final deck = PmlPresentation()..master.background = '123456';
      final saved = _reopen(deck);
      expect(saved.master.background, '123456');
      expect(saved.slides.single.background, '123456');
      expect(saved.slides.single.inheritsMasterBackground, isTrue);
    });
  });

  test(
    'PDF picture borders follow the image after its crop clip is restored',
    () {
      final canvas = PdfCanvas(200, 100);
      final images = <PdfEmbeddedImage>[];
      OfficePdfVisuals.paint(
        canvas,
        10,
        20,
        40,
        30,
        OfficeVisual(
          kind: OfficeVisualKind.picture,
          imageBytes: _slideImage,
          picture: PictureAdjust(
            cropLeft: .1,
            borderColor: '123456',
            borderWidth: 2,
          ),
        ),
        images,
        drawText: (text, x, y, size, color) =>
            fail('Unexpected image fallback'),
      );
      final stream = utf8.decode(canvas.toStream());
      expect(images, hasLength(1));
      expect(stream, contains('/Im1 Do'));
      expect(stream, contains('2 w'));
      expect(stream, contains('0.071 0.204 0.337 RG'));
      expect(stream, contains('10 20 40 30 re\nS'));
      expect(stream.indexOf('2 w'), greaterThan(stream.indexOf('/Im1 Do')));
      expect(
        stream.substring(stream.indexOf('/Im1 Do'), stream.indexOf('2 w')),
        contains('Q'),
      );
    },
  );

  for (final cropped in [false, true]) {
    test(
      'PDF picture border preserves caller graphics state crop=$cropped',
      () {
        final canvas = PdfCanvas(100, 100);
        canvas.setLineWidth(.5);
        canvas.setStrokeColor('00FF00');
        OfficePdfVisuals.paint(
          canvas,
          0,
          0,
          20,
          20,
          OfficeVisual(
            kind: OfficeVisualKind.picture,
            imageBytes: _slideImage,
            picture: PictureAdjust(
              cropLeft: cropped ? .1 : 0,
              borderColor: '123456',
              borderWidth: 7,
            ),
          ),
          <PdfEmbeddedImage>[],
          drawText: (text, x, y, size, color) =>
              fail('Unexpected image fallback'),
        );
        canvas.rect(30, 0, 20, 20);
        canvas.stroke();
        final states = _strokeStates(utf8.decode(canvas.toStream()));
        expect(states.map((state) => state.$1), [7, .5]);
        expect(states.last.$2, '0 1 0');
      },
    );
  }
}

List<(double, String)> _strokeStates(String stream) {
  var width = 1.0;
  var color = '0 0 0';
  final stack = <(double, String)>[];
  final strokes = <(double, String)>[];
  for (final line in stream.split('\n')) {
    if (line == 'q') {
      stack.add((width, color));
    } else if (line == 'Q') {
      final restored = stack.removeLast();
      width = restored.$1;
      color = restored.$2;
    } else if (line.endsWith(' w')) {
      width = double.parse(line.split(' ').first);
    } else if (line.endsWith(' RG')) {
      color = line.substring(0, line.length - 3);
    } else if (line == 'S') {
      strokes.add((width, color));
    }
  }
  return strokes;
}
