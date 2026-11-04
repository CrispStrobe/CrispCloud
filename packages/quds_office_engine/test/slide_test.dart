import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('serializes and reopens a slide with DrawingML geometry', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Title',
              text: 'مرحبا',
              transform: const PmlTransform(
                x: 0,
                y: 0,
                cx: 2000000,
                cy: 500000,
              ),
            ),
          ],
        ),
      ],
    );
    expect(
      pres.resolveText(pres.slides.first.shapes.first, pres.slides.first),
      'مرحبا',
    );
    final bytes = SlideSerializer().writeBytes(pres);
    final PmlPresentation opened = SlideDeserializer().readBytes(bytes);
    expect(opened.slides, isNotEmpty);
    expect(
      opened.slides.first.shapes.any((PmlShape s) => s.text.contains('مرحبا')),
      isTrue,
    );
  });

  test('round-trips shape text direction and alignment', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Card',
              text: 'بطاقة جديدة',
              rightToLeft: true,
              textAlign: PmlTextAlign.right,
              transform: const PmlTransform(
                x: 0,
                y: 0,
                cx: 2000000,
                cy: 500000,
              ),
            ),
          ],
        ),
      ],
    );
    final String xml = slideToXml(pres.slides.first);
    expect(xml, contains('rtl="1"'));
    expect(xml, contains('algn="r"'));
    final List<PmlShape> parsed = parseSlideShapes(xml);
    expect(parsed, isNotEmpty);
    expect(parsed.first.rightToLeft, isTrue);
    expect(parsed.first.textAlign, PmlTextAlign.right);
    expect(parsed.first.text, contains('بطاقة'));
  });

  test('round-trips an inserted slide table', () {
    final PmlTable table = PmlTable.grid(rows: 2, cols: 3, arabic: true);
    expect(table.rowCount, 2);
    expect(table.colCount, 3);
    expect(table.rightToLeft, isTrue);
    expect(table.cellAt(0, 0).text, contains('عمود'));
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Table',
              fillColor: '',
              table: table,
              transform: const PmlTransform(
                x: 600000,
                y: 1100000,
                cx: 7900000,
                cy: 2800000,
              ),
            ),
          ],
        ),
      ],
    );
    final String xml = slideToXml(pres.slides.first);
    expect(xml, contains('drawingml/2006/table'));
    expect(xml, contains('<a:tbl'));
    expect(xml, contains('rtl="1"'));
    final List<PmlShape> parsed = parseSlideShapes(xml);
    expect(parsed.single.table, isNotNull);
    expect(parsed.single.table!.rowCount, 2);
    expect(parsed.single.table!.colCount, 3);
    expect(parsed.single.table!.rightToLeft, isTrue);
    expect(parsed.single.table!.cellAt(0, 1).text, contains('عمود'));
    final PmlPresentation opened = SlideDeserializer().readBytes(
      SlideSerializer().writeBytes(pres),
    );
    expect(opened.slides.first.shapes.single.table?.colCount, 3);
  });

  test(
    'parseSlideShapes keeps noFill and run ink separate from shape fill',
    () {
      const String xml = '''
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:sp>
    <p:nvSpPr><p:cNvPr id="2" name="Box"/></p:nvSpPr>
    <p:spPr>
      <a:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></a:xfrm>
      <a:prstGeom prst="rect"/><a:solidFill><a:srgbClr val="2B579A"/></a:solidFill>
      <a:ln><a:noFill/></a:ln>
    </p:spPr>
    <p:txBody><a:p><a:r>
      <a:rPr sz="4000"><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill></a:rPr>
      <a:t>Title</a:t>
    </a:r></a:p></p:txBody>
  </p:sp>
  <p:sp>
    <p:nvSpPr><p:cNvPr id="3" name="Text"/></p:nvSpPr>
    <p:spPr>
      <a:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></a:xfrm>
      <a:prstGeom prst="rect"/><a:noFill/>
    </p:spPr>
    <p:txBody><a:p><a:r>
      <a:rPr><a:solidFill><a:srgbClr val="F4C542"/></a:solidFill></a:rPr>
      <a:t>Kicker</a:t>
    </a:r></a:p></p:txBody>
  </p:sp>
</p:sld>''';
      final List<PmlShape> shapes = parseSlideShapes(xml);
      expect(shapes, hasLength(2));
      expect(
        shapes[0].fillColor.toUpperCase(),
        '2B579A',
      ); // ln/noFill must not clear fill
      expect(shapes[0].textColor.toUpperCase(), 'FFFFFF');
      expect(shapes[0].text, 'Title');
      expect(shapes[0].fontSizePt, 40);
      expect(shapes[1].fillColor, isEmpty);
      expect(shapes[1].textColor.toUpperCase(), 'F4C542');
      expect(shapes[1].text, 'Kicker');
    },
  );

  test('parseChartVisual reads pie points and colors', () {
    const String xml = '''
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <c:chart>
    <c:title><c:tx><c:rich><a:p><a:r><a:t>Share</a:t></a:r></a:p></c:rich></c:tx></c:title>
    <c:plotArea>
      <c:pieChart>
        <c:ser>
          <c:dPt><c:idx val="0"/><c:spPr><a:solidFill><a:srgbClr val="2B579A"/></a:solidFill></c:spPr></c:dPt>
          <c:dPt><c:idx val="1"/><c:spPr><a:solidFill><a:srgbClr val="217346"/></a:solidFill></c:spPr></c:dPt>
          <c:cat><c:strLit>
            <c:pt idx="0"><c:v>A</c:v></c:pt>
            <c:pt idx="1"><c:v>B</c:v></c:pt>
          </c:strLit></c:cat>
          <c:val><c:numLit>
            <c:pt idx="0"><c:v>10</c:v></c:pt>
            <c:pt idx="1"><c:v>20</c:v></c:pt>
          </c:numLit></c:val>
        </c:ser>
      </c:pieChart>
    </c:plotArea>
  </c:chart>
</c:chartSpace>''';
    final OfficeVisual visual = parseChartVisual(xml);
    expect(visual.kind, OfficeVisualKind.chartPie);
    expect(visual.title, 'Share');
    expect(visual.points, hasLength(2));
    expect(visual.points[0].label, 'A');
    expect(visual.points[0].value, 10);
    expect(visual.points[0].color.toUpperCase(), '2B579A');
    expect(visual.points[1].label, 'B');
    expect(visual.points[1].value, 20);
  });

  test('round-trips slide transitions and shape animations', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.push,
            direction: PmlTransitionDir.right,
            durationMs: 1200,
          ),
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.flyIn,
              direction: PmlTransitionDir.left,
              trigger: PmlAnimTrigger.onClick,
            ),
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.fadeOut,
              trigger: PmlAnimTrigger.afterPrevious,
              order: 1,
            ),
          ],
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Title', text: 'Hello')],
        ),
      ],
    );
    final bytes = SlideSerializer().writeBytes(pres);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/ppt/slides/slide1.xml')!.readText();
    expect(xml, contains('<p:transition'));
    expect(xml, contains('<p:push'));
    expect(xml, contains('<p:timing'));
    expect(xml, contains('spid="2"'));
    final PmlPresentation opened = SlideDeserializer().readBytes(bytes);
    expect(opened.slides.first.transition.kind, PmlTransitionKind.push);
    expect(opened.slides.first.transition.direction, PmlTransitionDir.right);
    expect(opened.slides.first.animations, hasLength(2));
    expect(opened.slides.first.animations.first.preset, PmlAnimPreset.flyIn);
    expect(
      opened.slides.first.animations.last.trigger,
      PmlAnimTrigger.afterPrevious,
    );
    expect(
      opened.slides.first.animations.first.direction,
      PmlTransitionDir.left,
    );
  });

  test('preview-only slideshow never advances to the next slide', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.fade,
            durationMs: 200,
          ),
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(shapeId: 2, preset: PmlAnimPreset.peekIn),
          ],
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Title', text: 'A')],
        ),
        PmlSlide(id: 257, shapes: <PmlShape>[PmlShape(id: 2, name: 'Next')]),
      ],
    );
    final PmlSlideShow show = PmlSlideShow(pres)
      ..start(
        from: 0,
        withTransition: true,
        previewOnly: true,
        endAfterTransition: true,
      );
    expect(show.isTransitioning, isTrue);
    show.elapse(200);
    expect(show.isTransitioning, isFalse);
    expect(show.presenting, isTrue);
    show.elapse(PmlSlideShow.previewHoldMs);
    expect(show.presenting, isFalse);
    expect(show.slideIndex, 0);

    final PmlSlideShow anims = PmlSlideShow(pres)
      ..start(from: 0, previewOnly: true, autoPlayClicks: true);
    expect(anims.sample(2).visible, isTrue);
    anims.elapse(500);
    expect(anims.presenting, isTrue);
    anims.elapse(PmlSlideShow.previewHoldMs);
    expect(anims.presenting, isFalse);
    expect(anims.slideIndex, 0);
  });

  test('animation preview plays click groups in sequence then can restart', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.fade,
              durationMs: 200,
            ),
            PmlShapeAnimation(
              shapeId: 3,
              preset: PmlAnimPreset.fade,
              durationMs: 200,
            ),
          ],
          shapes: <PmlShape>[
            PmlShape(id: 2, name: 'A'),
            PmlShape(id: 3, name: 'B'),
          ],
        ),
      ],
    );

    void playThrough(PmlSlideShow show) {
      expect(show.sample(2).visible, isTrue);
      expect(show.sample(3).visible, isFalse);
      show.elapse(200);
      expect(show.presenting, isTrue);
      expect(show.sample(3).visible, isTrue);
      show.elapse(200);
      expect(show.presenting, isTrue);
      show.elapse(PmlSlideShow.previewHoldMs);
      expect(show.presenting, isFalse);
    }

    final PmlSlideShow first = PmlSlideShow(pres)
      ..start(from: 0, previewOnly: true, autoPlayClicks: true);
    playThrough(first);
    final PmlSlideShow second = PmlSlideShow(pres)
      ..start(from: 0, previewOnly: true, autoPlayClicks: true);
    playThrough(second);
  });

  test('slideshow hides entrance shapes until the click fires', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(shapeId: 2, preset: PmlAnimPreset.fade),
          ],
          shapes: <PmlShape>[
            PmlShape(id: 2, name: 'Title', text: 'A'),
            PmlShape(id: 3, name: 'Body', text: 'B'),
          ],
        ),
        PmlSlide(
          id: 257,
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.fade,
            durationMs: 400,
          ),
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Next', text: 'C')],
        ),
      ],
    );
    final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
    expect(show.sample(2).visible, isFalse);
    expect(show.sample(3).visible, isTrue);
    show.next();
    show.elapse(500);
    expect(show.sample(2).visible, isTrue);
    expect(show.sample(2).opacity, greaterThan(0.5));
    show.next();
    expect(show.isTransitioning, isTrue);
    expect(show.outgoingSlide, isNotNull);
    show.elapse(400);
    expect(show.isTransitioning, isFalse);
    expect(show.slideIndex, 1);
  });

  test('slideshow back rewinds the last click animation', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.fade,
              durationMs: 400,
            ),
          ],
          shapes: <PmlShape>[
            PmlShape(id: 2, name: 'Title', text: 'A'),
            PmlShape(id: 3, name: 'Body', text: 'B'),
          ],
        ),
      ],
    );
    final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
    expect(show.sample(2).visible, isFalse);
    show.next();
    show.elapse(400);
    expect(show.sample(2).visible, isTrue);
    expect(show.sample(2).opacity, closeTo(1, 0.05));
    show.previous();
    expect(show.isRewinding, isTrue);
    show.elapse(80);
    expect(show.sample(2).visible, isTrue);
    expect(show.sample(2).opacity, lessThan(1));
    show.elapse(200);
    expect(show.isRewinding, isTrue);
    expect(show.sample(2).opacity, lessThan(0.7));
    show.elapse(200);
    expect(show.isRewinding, isFalse);
    expect(show.sample(2).visible, isFalse);
  });

  test(
    'slideshow back during a slide transition reverses the remaining motion',
    () {
      final PmlPresentation pres = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256, shapes: <PmlShape>[PmlShape(id: 2, name: 'A')]),
          PmlSlide(
            id: 257,
            transition: const PmlSlideTransition(
              kind: PmlTransitionKind.fade,
              durationMs: 400,
            ),
            shapes: <PmlShape>[PmlShape(id: 2, name: 'B')],
          ),
        ],
      );
      final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
      show.next();
      expect(show.isTransitioning, isTrue);
      expect(show.slideIndex, 1);
      show.elapse(200);
      expect(show.transitionProgress, closeTo(0.5, 0.05));
      show.previous();
      expect(show.isTransitioning, isTrue);
      expect(show.isTransitionReverse, isTrue);
      expect(show.slideIndex, 1);
      expect(show.outgoingSlide?.id, 256);
      expect(show.transitionProgress, closeTo(0.5, 0.05));
      show.elapse(100);
      expect(show.transitionProgress, lessThan(0.4));
      expect(show.slideIndex, 1);
      show.elapse(200);
      expect(show.isTransitioning, isFalse);
      expect(show.slideIndex, 0);
      expect(show.currentSlide.id, 256);
    },
  );

  test(
    'slideshow back from a finished slide reverses that slide transition',
    () {
      final PmlPresentation pres = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256, shapes: <PmlShape>[PmlShape(id: 2, name: 'A')]),
          PmlSlide(
            id: 257,
            transition: const PmlSlideTransition(
              kind: PmlTransitionKind.push,
              direction: PmlTransitionDir.left,
              durationMs: 400,
            ),
            shapes: <PmlShape>[PmlShape(id: 2, name: 'B')],
          ),
        ],
      );
      final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
      show.next();
      show.elapse(400);
      expect(show.isTransitioning, isFalse);
      expect(show.slideIndex, 1);
      show.previous();
      expect(show.isTransitioning, isTrue);
      expect(show.isTransitionReverse, isTrue);
      expect(show.slideIndex, 1);
      expect(show.transitionProgress, closeTo(1, 0.01));
      expect(show.outgoingSlide?.id, 256);
      expect(show.playingTransition?.kind, PmlTransitionKind.push);
      show.elapse(100);
      expect(show.transitionProgress, closeTo(0.75, 0.05));
      expect(show.slideIndex, 1);
      show.elapse(400);
      expect(show.isTransitioning, isFalse);
      expect(show.isTransitionReverse, isFalse);
      expect(show.slideIndex, 0);
    },
  );

  test('slideshow back reverses fly-in along the same path', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.flyIn,
              direction: PmlTransitionDir.left,
              durationMs: 400,
            ),
          ],
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Title', text: 'A')],
        ),
      ],
    );
    final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
    show.next();
    show.elapse(400);
    expect(show.sample(2).visible, isTrue);
    expect(show.sample(2).dx, closeTo(0, 0.02));
    show.previous();
    expect(show.isRewinding, isTrue);
    show.elapse(200);
    expect(show.sample(2).visible, isTrue);
    expect(show.sample(2).dx, lessThan(-0.05));
    show.elapse(400);
    expect(show.isRewinding, isFalse);
    expect(show.sample(2).visible, isFalse);
  });

  test('slideshow back reverses later group items before earlier ones', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          animations: <PmlShapeAnimation>[
            PmlShapeAnimation(
              shapeId: 2,
              preset: PmlAnimPreset.fade,
              trigger: PmlAnimTrigger.onClick,
              durationMs: 200,
              order: 0,
            ),
            PmlShapeAnimation(
              shapeId: 3,
              preset: PmlAnimPreset.fade,
              trigger: PmlAnimTrigger.afterPrevious,
              durationMs: 200,
              order: 1,
            ),
          ],
          shapes: <PmlShape>[
            PmlShape(id: 2, name: 'First', text: 'A'),
            PmlShape(id: 3, name: 'Second', text: 'B'),
          ],
        ),
      ],
    );
    final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
    show.next();
    show.elapse(400);
    expect(show.sample(2).opacity, closeTo(1, 0.05));
    expect(show.sample(3).opacity, closeTo(1, 0.05));
    show.previous();
    expect(show.isRewinding, isTrue);
    show.elapse(80);
    expect(show.sample(3).opacity, lessThan(show.sample(2).opacity));
    show.elapse(400);
    expect(show.isRewinding, isFalse);
    expect(show.sample(2).visible, isFalse);
    expect(show.sample(3).visible, isFalse);
  });

  test(
    'Morph pairs unique names and interpolates position size and rotation',
    () {
      final PmlSlide outgoing = PmlSlide(
        id: 256,
        shapes: <PmlShape>[
          PmlShape(
            id: 2,
            name: 'Title',
            text: 'A',
            fillColor: '000000',
            transform: const PmlTransform(
              x: 0,
              y: 0,
              cx: 1000000,
              cy: 1000000,
              rot: 0,
            ),
          ),
          PmlShape(
            id: 3,
            name: 'Card',
            text: 'Old',
            fillColor: 'FF0000',
            transform: const PmlTransform(
              x: 0,
              y: 2000000,
              cx: 1000000,
              cy: 1000000,
            ),
          ),
        ],
      );
      final PmlSlide incoming = PmlSlide(
        id: 257,
        shapes: <PmlShape>[
          PmlShape(
            id: 2,
            name: 'Title',
            text: 'A',
            fillColor: 'FFFFFF',
            transform: const PmlTransform(
              x: 2000000,
              y: 0,
              cx: 2000000,
              cy: 1000000,
              rot: 10800000,
            ),
          ),
          PmlShape(
            id: 9,
            name: 'Card',
            text: 'New',
            fillColor: '00FF00',
            transform: const PmlTransform(
              x: 3000000,
              y: 2000000,
              cx: 1000000,
              cy: 1000000,
            ),
          ),
          PmlShape(id: 4, name: 'Fresh', text: 'In', fillColor: '0000FF'),
        ],
      );

      final List<PmlMorphPair> pairs = PmlMorph.pair(outgoing, incoming);
      expect(
        pairs.where((PmlMorphPair p) => p.role == PmlMorphRole.keep),
        hasLength(2),
      );
      expect(
        pairs.where((PmlMorphPair p) => p.role == PmlMorphRole.enter),
        hasLength(1),
      );
      expect(
        pairs.where((PmlMorphPair p) => p.role == PmlMorphRole.exit),
        isEmpty,
      );

      final List<PmlMorphFrame> start = PmlMorph.frames(outgoing, incoming, 0);
      final PmlMorphFrame title0 = start.firstWhere(
        (PmlMorphFrame f) => f.shape.name == 'Title',
      );
      expect(title0.transform.x, 0);
      expect(title0.transform.cx, 1000000);
      expect(title0.fillColor, '000000');
      expect(title0.opacity, 1);

      final List<PmlMorphFrame> mid = PmlMorph.frames(outgoing, incoming, 0.5);
      final PmlMorphFrame titleMid = mid.firstWhere(
        (PmlMorphFrame f) => f.shape.name == 'Title',
      );
      expect(titleMid.transform.x, 1000000);
      expect(titleMid.transform.cx, 1500000);
      expect(titleMid.transform.rot, 5400000);
      expect(titleMid.fillColor, '808080');
      expect(titleMid.opacity, 1);
      final PmlMorphFrame enter = mid.firstWhere(
        (PmlMorphFrame f) => f.role == PmlMorphRole.enter,
      );
      expect(enter.opacity, closeTo(PmlMorph.ease(0.5), 0.0001));
      expect(enter.transform.x, enter.shape.transform.x);

      final List<PmlMorphFrame> end = PmlMorph.frames(outgoing, incoming, 1);
      final PmlMorphFrame title1 = end.firstWhere(
        (PmlMorphFrame f) => f.shape.name == 'Title',
      );
      expect(title1.transform.x, 2000000);
      expect(title1.transform.cx, 2000000);
      expect(title1.transform.rot, 10800000);
      expect(title1.fillColor, 'FFFFFF');
      expect(title1.opacity, 1);
    },
  );

  test(
    'Morph ignores shapes that exist only on another slide column of ids',
    () {
      final PmlSlide outgoing = PmlSlide(
        id: 256,
        shapes: <PmlShape>[PmlShape(id: 2, name: 'OnlyHere', text: 'Stay')],
      );
      final PmlSlide incoming = PmlSlide(
        id: 257,
        shapes: <PmlShape>[PmlShape(id: 8, name: 'Other', text: 'Arrive')],
      );
      final List<PmlMorphPair> pairs = PmlMorph.pair(outgoing, incoming);
      expect(pairs, hasLength(2));
      expect(pairs.first.role, PmlMorphRole.exit);
      expect(pairs.last.role, PmlMorphRole.enter);
      final List<PmlMorphFrame> mid = PmlMorph.frames(outgoing, incoming, 0.5);
      expect(mid.first.opacity, lessThan(1));
      expect(mid.last.opacity, greaterThan(0));
      expect(mid.first.shape.name, 'OnlyHere');
      expect(mid.last.shape.name, 'Other');
    },
  );

  test('round-trips the Morph transition and reads prstTrans', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.morph,
            durationMs: 900,
          ),
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Title', text: 'Hi')],
        ),
      ],
    );
    final bytes = SlideSerializer().writeBytes(pres);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/ppt/slides/slide1.xml')!.readText();
    expect(xml, contains('<p:morph'));
    expect(xml, contains('option="byObject"'));
    final PmlPresentation opened = SlideDeserializer().readBytes(bytes);
    expect(opened.slides.first.transition.kind, PmlTransitionKind.morph);
    expect(opened.slides.first.transition.durationMs, 900);

    final PmlSlide imported = PmlSlide(id: 300);
    parseSlideMotion(
      '<p:sld><p:transition><p14:prstTrans prst="morph"/></p:transition></p:sld>',
      imported,
    );
    expect(imported.transition.kind, PmlTransitionKind.morph);
  });

  test('hidden slides persist and are skipped in a slide show', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(id: 256, shapes: <PmlShape>[PmlShape(id: 2, name: 'A')]),
        PmlSlide(
          id: 257,
          hidden: true,
          shapes: <PmlShape>[PmlShape(id: 2, name: 'Hidden')],
        ),
        PmlSlide(id: 258, shapes: <PmlShape>[PmlShape(id: 2, name: 'C')]),
      ],
    );
    expect(pres.visibleIndexAfter(0), 2);
    expect(pres.visibleIndexAfter(2, direction: -1), 0);

    final bytes = SlideSerializer().writeBytes(pres);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/ppt/slides/slide2.xml')!.readText();
    expect(xml, contains('show="0"'));
    final PmlPresentation opened = SlideDeserializer().readBytes(bytes);
    expect(opened.slides[1].hidden, isTrue);
    expect(opened.slides[0].hidden, isFalse);

    final PmlSlideShow show = PmlSlideShow(pres)..start(from: 0);
    expect(show.currentSlide.id, 256);
    show.next();
    expect(show.currentSlide.id, 258);
    show.previous();
    expect(show.currentSlide.id, 256);
  });
}
