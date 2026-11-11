import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _richBody =
    '<p:txBody><a:bodyPr anchor="ctr" lIns="114300"/>'
    '<a:lstStyle/><a:p><a:pPr algn="r" rtl="1"><a:buChar char="•"/></a:pPr>'
    '<a:r><a:rPr sz="2400" b="1"><a:solidFill><a:srgbClr val="884422"/>'
    '</a:solidFill><a:latin typeface="Liberation Serif"/></a:rPr><a:t>Bold </a:t></a:r>'
    '<a:r><a:rPr sz="1800" i="1"><a:solidFill><a:srgbClr val="008844"/>'
    '</a:solidFill></a:rPr><a:t>italic</a:t></a:r><a:endParaRPr lang="en-US"/>'
    '</a:p></p:txBody>';

PmlPresentation _richDeck() {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.slide);
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
        'xmlns:r="${OfficeNamespaces.r}"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Rich text"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
        '<a:off x="914400" y="914400"/><a:ext cx="4000000" cy="1000000"/>'
        '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '$_richBody</p:sp></p:spTree></p:cSld></p:sld>',
      );
  return SlideDeserializer().read(package);
}

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final XmlElement child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

XmlElement _body(OpcPackage package) => _descendants(
  XmlDocument.parse(
    package.getPart('/ppt/slides/slide1.xml')!.readText(),
  ).root!,
  'txBody',
).first;

void main() {
  test(
    'native text point sizes survive unchanged asynchronous export',
    () async {
      PmlPresentation deck = SlideDeserializer().readBytes(
        File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
      );
      expect(deck.slides.first.shapes.first.fontSizePt, 24);
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.presentation(deck);
        final OpcPackage saved = OpcPackage.openBytes(bytes);
        expect(
          _descendants(_body(saved), 'rPr').first.getAttribute('sz'),
          '2400',
        );
        deck = SlideDeserializer().readBytes(bytes);
        expect(deck.slides.first.shapes.first.fontSizePt, 24);
      }
    },
  );

  test(
    'moving rich text keeps run formats body settings and bullets',
    () async {
      PmlPresentation deck = _richDeck();
      deck.slides.single.shapes.single.transform = const PmlTransform(
        x: 2000000,
      );
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.presentation(deck);
        final XmlElement body = _body(OpcPackage.openBytes(bytes));
        final List<XmlElement> runProps = _descendants(body, 'rPr').toList();
        expect(runProps.map((XmlElement p) => p.getAttribute('sz')), <String>[
          '2400',
          '1800',
        ]);
        expect(runProps.first.getAttribute('b'), '1');
        expect(runProps.last.getAttribute('i'), '1');
        expect(
          runProps.first.firstChild('latin')!.getAttribute('typeface'),
          'Liberation Serif',
        );
        expect(
          _descendants(
            body,
            'srgbClr',
          ).map((XmlElement e) => e.getAttribute('val')),
          <String>['884422', '008844'],
        );
        expect(body.firstChild('bodyPr')!.getAttribute('anchor'), 'ctr');
        expect(_descendants(body, 'buChar').single.getAttribute('char'), '•');
        Directory('build/fidelity-slide-text').createSync(recursive: true);
        File(
          'build/fidelity-slide-text/rich-imported-$cycle.pptx',
        ).writeAsBytesSync(bytes);
        deck = SlideDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'scalar font color and alignment edits keep other imported run properties',
    () async {
      PmlPresentation deck = _richDeck();
      deck.slides.single.shapes.single
        ..fontSizePt = 30
        ..textColor = '112233'
        ..textAlign = PmlTextAlign.center
        ..rightToLeft = false;
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.presentation(deck);
        final XmlElement body = _body(OpcPackage.openBytes(bytes));
        final List<XmlElement> runProps = _descendants(body, 'rPr').toList();
        expect(
          runProps.map((XmlElement p) => p.getAttribute('sz')),
          everyElement('3000'),
        );
        expect(
          _descendants(
            body,
            'srgbClr',
          ).map((XmlElement e) => e.getAttribute('val')),
          everyElement('112233'),
        );
        expect(runProps.first.getAttribute('b'), '1');
        expect(runProps.last.getAttribute('i'), '1');
        final XmlElement pPr = _descendants(body, 'pPr').single;
        expect(pPr.getAttribute('algn'), 'ctr');
        expect(pPr.getAttribute('rtl'), '0');
        Directory('build/fidelity-slide-text').createSync(recursive: true);
        File(
          'build/fidelity-slide-text/rich-edited-$cycle.pptx',
        ).writeAsBytesSync(bytes);
        deck = SlideDeserializer().readBytes(bytes);
        expect(deck.slides.single.shapes.single.fontSizePt, 30);
        expect(deck.slides.single.shapes.single.textColor, '112233');
      }
    },
  );

  test(
    'multiline text replacement retains first-run styling and paragraph boundaries',
    () async {
      PmlPresentation deck = _richDeck();
      deck.slides.single.shapes.single.text = 'Replacement\nSecond line';
      for (int cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.presentation(deck);
        final XmlElement body = _body(OpcPackage.openBytes(bytes));
        expect(body.childrenNamed('p'), hasLength(2));
        expect(
          _descendants(body, 'rPr').map((XmlElement p) => p.getAttribute('b')),
          everyElement('1'),
        );
        expect(
          _descendants(
            body,
            'latin',
          ).map((XmlElement e) => e.getAttribute('typeface')),
          everyElement('Liberation Serif'),
        );
        deck = SlideDeserializer().readBytes(bytes);
        expect(
          deck.slides.single.shapes.single.text,
          'Replacement\nSecond line',
        );
      }
    },
  );

  test(
    'spaces blank paragraphs and hard breaks survive text round trips',
    () async {
      PmlPresentation deck = _richDeck();
      deck.slides.single.shapes.single.text = '\nAlpha\n\nBeta\n';
      for (int cycle = 0; cycle < 3; cycle++) {
        deck = SlideDeserializer().readBytes(
          await OfficeIsolateSave.presentation(deck),
        );
        expect(deck.slides.single.shapes.single.text, '\nAlpha\n\nBeta\n');
      }
      final OpcPackage package = _richDeck().package!;
      final PackagePart slide = package.getPart('/ppt/slides/slide1.xml')!;
      slide.writeText(
        slide.readText().replaceFirst(
          '<a:t>Bold </a:t>',
          '<a:t xml:space="preserve"> </a:t><a:br/>',
        ),
      );
      deck = SlideDeserializer().read(package);
      final String original = deck.slides.single.shapes.single.text;
      expect(original, ' \nitalic');
      for (int cycle = 0; cycle < 3; cycle++) {
        deck = SlideDeserializer().readBytes(
          await OfficeIsolateSave.presentation(deck),
        );
        expect(deck.slides.single.shapes.single.text, original);
      }
    },
  );

  test(
    'chart frames transitions and source axis IDs have valid schema values',
    () async {
      final PmlPresentation deck = SlideDeserializer().readBytes(
        File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
      );
      deck.slides.first.transition = const PmlSlideTransition(
        kind: PmlTransitionKind.wipe,
        durationMs: 900,
      );
      final bytes = await OfficeIsolateSave.presentation(deck);
      final OpcPackage saved = OpcPackage.openBytes(bytes);
      final XmlElement slide = XmlDocument.parse(
        saved.getPart('/ppt/slides/slide1.xml')!.readText(),
      ).root!;
      final XmlElement transition = slide.firstChild('transition')!;
      expect(transition.getAttribute('dur', namespaceUri: ''), isNull);
      expect(
        transition.getAttribute(
          'dur',
          namespaceUri:
              'http://schemas.microsoft.com/office/powerpoint/2010/main',
        ),
        '900',
      );
      for (final XmlElement frame in _descendants(slide, 'graphicFrame')) {
        expect(frame.firstChild('xfrm')!.namespaceUri, OfficeNamespaces.p);
      }
      for (final PackagePart part in saved.parts) {
        if (part.contentType != OfficeContentTypes.drawingChart) continue;
        final XmlElement chart = XmlDocument.parse(
          saved.getPart(part.uri)!.readText(),
        ).root!;
        for (final String name in <String>['axId', 'crossAx']) {
          for (final XmlElement node in _descendants(chart, name)) {
            final int id = int.parse(node.getAttribute('val')!);
            expect(id, inInclusiveRange(0, 2147483647));
          }
        }
      }
      expect(
        SlideDeserializer().readBytes(bytes).slides.first.transition.durationMs,
        900,
      );
    },
  );
}
