import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _presentationNs =
    'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';
const _smilNs = 'urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  test('writes modeled slides, text, tables and pictures as ODP', () {
    final presentation = PmlPresentation(
      properties: OfficeDocumentProperties(
        title: 'Deck smoke',
        subject: 'Slides',
        creator: 'Author',
      ),
      slides: [
        PmlSlide(
          id: 1,
          notes: 'Speaker note',
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.push,
            direction: PmlTransitionDir.left,
            durationMs: 800,
            advanceAfterMs: 5000,
          ),
          shapes: [
            PmlShape(
              id: 2,
              name: 'Title',
              transform: const PmlTransform(
                x: 457200,
                y: 457200,
                cx: 4572000,
                cy: 914400,
              ),
              text: 'Hello deck',
              fillColor: 'FFFFFF',
              textColor: '000000',
              fontSizePt: 28,
              textAlign: PmlTextAlign.center,
              hyperlinkUrl: 'https://example.com/deck',
            ),
            PmlShape(
              id: 3,
              name: 'Table',
              transform: const PmlTransform(
                x: 457200,
                y: 1600200,
                cx: 5486400,
                cy: 1600200,
              ),
              table: PmlTable(
                rows: [
                  [PmlTableCell(text: 'A'), PmlTableCell(text: 'B')],
                  [PmlTableCell(text: '1'), PmlTableCell(text: '2')],
                ],
              ),
            ),
            PmlShape(
              id: 4,
              name: 'Logo',
              transform: const PmlTransform(
                x: 6400800,
                y: 457200,
                cx: 914400,
                cy: 914400,
              ),
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Logo',
                imageBytes: _png,
                width: 72,
                height: 72,
              ),
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdpPresentationWriter.writeBytes(presentation),
    );
    final content = package.getPart('/content.xml')!.readText();
    final styles = package.getPart('/styles.xml')!.readText();
    final meta = package.getPart('/meta.xml')!.readText();
    expect(meta, contains('<dc:title>Deck smoke</dc:title>'));
    expect(meta, contains('<dc:subject>Slides</dc:subject>'));
    expect(meta, contains('<dc:creator>Author</dc:creator>'));
    expect(content, contains('<draw:page'));
    expect(content, contains('Hello deck'));
    expect(content, contains('<table:table'));
    expect(content, contains('Pictures/image1.png'));
    expect(content, contains('xlink:type="simple"'));
    expect(content, contains('Speaker note'));
    expect(content, contains('<text:a xlink:href="https://example.com/deck">'));
    final pageProperties = _pageProperties(XmlDocument.parse(content), 0);
    expect(
      pageProperties.getAttribute('type', namespaceUri: _smilNs),
      'pushWipe',
    );
    expect(
      pageProperties.getAttribute('subtype', namespaceUri: _smilNs),
      'fromRight',
    );
    expect(
      pageProperties.getAttribute('duration', namespaceUri: _presentationNs),
      'PT5S',
    );
    expect(styles, contains('fo:page-width'));
    expect(package.getPart('/Pictures/image1.png'), isNotNull);
  });

  test(
    'page styles keep independent transitions and reuse equivalent properties',
    () {
      final document = _transitionDocument(const [
        PmlSlideTransition(
          kind: PmlTransitionKind.push,
          direction: PmlTransitionDir.left,
          durationMs: 800,
          advanceAfterMs: 5000,
        ),
        PmlSlideTransition(kind: PmlTransitionKind.fade, durationMs: 500),
        PmlSlideTransition(advanceAfterMs: 1250),
        PmlSlideTransition(
          kind: PmlTransitionKind.fade,
          durationMs: -1,
          advanceAfterMs: -1,
        ),
        PmlSlideTransition(kind: PmlTransitionKind.fade, durationMs: 500),
      ], fixture: 'slide-transitions.odp');
      final pages = _elements(document.root!, 'page', _drawNs).toList();
      expect(pages, hasLength(5));
      for (final page in pages) {
        expect(
          page.attributes.where(
            (attribute) =>
                const {'presentation', 'smil'}.contains(attribute.prefix),
          ),
          isEmpty,
          reason: 'Transition attributes belong on the referenced page style.',
        );
      }
      final push = _pageProperties(document, 0);
      expect(push.getAttribute('type', namespaceUri: _smilNs), 'pushWipe');
      expect(push.getAttribute('subtype', namespaceUri: _smilNs), 'fromRight');
      expect(
        push.getAttribute('transition-speed', namespaceUri: _presentationNs),
        'medium',
      );
      expect(
        push.getAttribute('transition-type', namespaceUri: _presentationNs),
        'automatic',
      );
      expect(
        push.getAttribute('duration', namespaceUri: _presentationNs),
        'PT5S',
      );
      final fade = _pageProperties(document, 1);
      expect(fade.getAttribute('type', namespaceUri: _smilNs), 'fade');
      expect(fade.getAttribute('subtype', namespaceUri: _smilNs), 'crossfade');
      expect(
        fade.getAttribute('transition-speed', namespaceUri: _presentationNs),
        'fast',
      );
      expect(
        fade.getAttribute('duration', namespaceUri: _presentationNs),
        isNull,
      );
      final timed = _pageProperties(document, 2);
      expect(timed.getAttribute('type', namespaceUri: _smilNs), isNull);
      expect(
        timed.getAttribute('transition-speed', namespaceUri: _presentationNs),
        isNull,
      );
      expect(
        timed.getAttribute('transition-type', namespaceUri: _presentationNs),
        'automatic',
      );
      expect(
        timed.getAttribute('duration', namespaceUri: _presentationNs),
        'PT1.25S',
      );
      final invalid = _pageProperties(document, 3);
      expect(invalid.getAttribute('type', namespaceUri: _smilNs), isNull);
      expect(
        invalid.getAttribute('duration', namespaceUri: _presentationNs),
        isNull,
      );
      expect(
        invalid.getAttribute('transition-type', namespaceUri: _presentationNs),
        isNull,
      );
      final names = pages
          .map((page) => page.getAttribute('style-name', namespaceUri: _drawNs))
          .toList();
      expect(names.take(4).toSet(), hasLength(4));
      expect(names[4], names[1]);
    },
  );

  for (final kind in [
    PmlTransitionKind.push,
    PmlTransitionKind.cover,
    PmlTransitionKind.uncover,
  ]) {
    test('${kind.name} preserves the four cardinal movement directions', () {
      final document = _transitionDocument([
        for (final direction in [
          PmlTransitionDir.left,
          PmlTransitionDir.right,
          PmlTransitionDir.up,
          PmlTransitionDir.down,
        ])
          PmlSlideTransition(kind: kind, direction: direction),
      ]);
      const incomingEdges = ['fromRight', 'fromLeft', 'fromBottom', 'fromTop'];
      for (var index = 0; index < incomingEdges.length; index++) {
        final properties = _pageProperties(document, index);
        expect(
          properties.getAttribute('type', namespaceUri: _smilNs),
          kind == PmlTransitionKind.push ? 'pushWipe' : 'slideWipe',
        );
        expect(
          properties.getAttribute('subtype', namespaceUri: _smilNs),
          incomingEdges[index],
        );
        expect(
          properties.getAttribute('direction', namespaceUri: _smilNs),
          kind == PmlTransitionKind.uncover ? 'reverse' : isNull,
        );
      }
    });
  }

  test('wipe directions retain the shared renderer reveal edge', () {
    final document = _transitionDocument([
      for (final direction in [
        PmlTransitionDir.left,
        PmlTransitionDir.right,
        PmlTransitionDir.up,
        PmlTransitionDir.down,
      ])
        PmlSlideTransition(kind: PmlTransitionKind.wipe, direction: direction),
    ]);
    const subtypes = [
      'leftToRight',
      'leftToRight',
      'topToBottom',
      'topToBottom',
    ];
    for (var index = 0; index < subtypes.length; index++) {
      final properties = _pageProperties(document, index);
      expect(properties.getAttribute('type', namespaceUri: _smilNs), 'barWipe');
      expect(
        properties.getAttribute('subtype', namespaceUri: _smilNs),
        subtypes[index],
      );
      expect(
        properties.getAttribute('direction', namespaceUri: _smilNs),
        index.isOdd ? 'reverse' : isNull,
      );
    }
  });

  test('split strips retain the shared renderer axis and inward reveal', () {
    final document = _transitionDocument(const [
      PmlSlideTransition(
        kind: PmlTransitionKind.split,
        direction: PmlTransitionDir.horizontal,
      ),
      PmlSlideTransition(
        kind: PmlTransitionKind.split,
        direction: PmlTransitionDir.vertical,
      ),
    ]);
    for (var index = 0; index < 2; index++) {
      final properties = _pageProperties(document, index);
      expect(
        properties.getAttribute('type', namespaceUri: _smilNs),
        'barnDoorWipe',
      );
      expect(
        properties.getAttribute('subtype', namespaceUri: _smilNs),
        index == 0 ? 'vertical' : 'horizontal',
      );
      expect(
        properties.getAttribute('direction', namespaceUri: _smilNs),
        'reverse',
      );
    }
  });

  test('legacy effects use defined ODF transition-style values', () {
    final document = _transitionDocument(const [
      PmlSlideTransition(kind: PmlTransitionKind.dissolve),
      PmlSlideTransition(kind: PmlTransitionKind.checkerboard),
      PmlSlideTransition(kind: PmlTransitionKind.blinds),
      PmlSlideTransition(
        kind: PmlTransitionKind.blinds,
        direction: PmlTransitionDir.vertical,
      ),
      PmlSlideTransition(kind: PmlTransitionKind.randomBars),
      PmlSlideTransition(
        kind: PmlTransitionKind.randomBars,
        direction: PmlTransitionDir.vertical,
      ),
    ]);
    const values = [
      'dissolve',
      'horizontal-checkerboard',
      'horizontal-stripes',
      'vertical-stripes',
      'horizontal-lines',
      'vertical-lines',
    ];
    for (var index = 0; index < values.length; index++) {
      final properties = _pageProperties(document, index);
      expect(
        properties.getAttribute(
          'transition-style',
          namespaceUri: _presentationNs,
        ),
        values[index],
      );
      expect(properties.getAttribute('type', namespaceUri: _smilNs), isNull);
    }
  });

  test('unsupported visual effects use the documented crossfade fallback', () {
    final document = _transitionDocument([
      for (final kind in [
        PmlTransitionKind.morph,
        PmlTransitionKind.fadeThroughBlack,
        PmlTransitionKind.shapePlus,
        PmlTransitionKind.newsflash,
        PmlTransitionKind.zoom,
        PmlTransitionKind.flash,
        PmlTransitionKind.comb,
        PmlTransitionKind.strips,
        PmlTransitionKind.reveal,
        PmlTransitionKind.gallery,
      ])
        PmlSlideTransition(kind: kind),
    ]);
    for (var index = 0; index < 10; index++) {
      final properties = _pageProperties(document, index);
      expect(properties.getAttribute('type', namespaceUri: _smilNs), 'fade');
      expect(
        properties.getAttribute('subtype', namespaceUri: _smilNs),
        'crossfade',
      );
      expect(
        properties.getAttribute(
          'transition-style',
          namespaceUri: _presentationNs,
        ),
        isNull,
      );
    }
  });

  test(
    'automatic advance preserves milliseconds independently of an effect',
    () {
      const timings = {
        1: 'PT0.001S',
        10: 'PT0.01S',
        999: 'PT0.999S',
        1001: 'PT1.001S',
        1250: 'PT1.25S',
        5000: 'PT5S',
        0: null,
        -1: null,
      };
      final document = _transitionDocument([
        for (final milliseconds in timings.keys)
          PmlSlideTransition(
            advanceAfterMs: milliseconds,
            advanceOnClick: false,
          ),
      ]);
      var index = 0;
      for (final expected in timings.values) {
        final properties = _pageProperties(document, index++);
        expect(
          properties.getAttribute('duration', namespaceUri: _presentationNs),
          expected,
        );
        expect(
          properties.getAttribute(
            'transition-type',
            namespaceUri: _presentationNs,
          ),
          expected == null ? isNull : 'automatic',
        );
        expect(properties.getAttribute('type', namespaceUri: _smilNs), isNull);
      }
    },
  );

  test('effect speed buckets and instantaneous durations stay separate from advance', () {
    const speeds = {
      -1: null,
      0: null,
      1: 'fast',
      500: 'fast',
      501: 'medium',
      999: 'medium',
      1000: 'slow',
      2500: 'slow',
    };
    final document = _transitionDocument([
      for (final duration in speeds.keys)
        PmlSlideTransition(kind: PmlTransitionKind.fade, durationMs: duration),
    ]);
    var index = 0;
    for (final expected in speeds.values) {
      final properties = _pageProperties(document, index++);
      expect(
        properties.getAttribute(
          'transition-speed',
          namespaceUri: _presentationNs,
        ),
        expected,
      );
      expect(
        properties.getAttribute('type', namespaceUri: _smilNs),
        expected == null ? isNull : 'fade',
      );
      expect(
        properties.getAttribute('duration', namespaceUri: _presentationNs),
        isNull,
      );
    }
  });

  test(
    'cut and none keep automatic timing without inventing an effect name',
    () {
      final document = _transitionDocument(const [
        PmlSlideTransition(advanceAfterMs: 1001),
        PmlSlideTransition(kind: PmlTransitionKind.cut, advanceAfterMs: 1001),
      ]);
      for (var index = 0; index < 2; index++) {
        final properties = _pageProperties(document, index);
        expect(properties.getAttribute('type', namespaceUri: _smilNs), isNull);
        expect(
          properties.getAttribute(
            'transition-style',
            namespaceUri: _presentationNs,
          ),
          isNull,
        );
        expect(
          properties.getAttribute(
            'transition-speed',
            namespaceUri: _presentationNs,
          ),
          isNull,
        );
        expect(
          properties.getAttribute('duration', namespaceUri: _presentationNs),
          'PT1.001S',
        );
      }
    },
  );
}

XmlDocument _transitionDocument(
  List<PmlSlideTransition> transitions, {
  String? fixture,
}) {
  final presentation = PmlPresentation(
    slides: [
      for (var index = 0; index < transitions.length; index++)
        PmlSlide(
          id: index + 1,
          transition: transitions[index],
          shapes: [
            PmlShape(
              id: 1,
              name: 'Transition ${index + 1}',
              text: 'Transition ${index + 1}',
              transform: const PmlTransform(cx: 4572000, cy: 914400),
            ),
          ],
        ),
    ],
  );
  final bytes = OdpPresentationWriter.writeBytes(presentation);
  final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
  if (fixture != null && output != null && output.isNotEmpty) {
    Directory(output).createSync(recursive: true);
    File('$output/$fixture').writeAsBytesSync(bytes);
  }
  final package = OpcPackage.openBytes(bytes);
  return XmlDocument.parse(package.getPart('/content.xml')!.readText());
}

Iterable<XmlElement> _elements(
  XmlElement root,
  String name,
  String namespaceUri,
) sync* {
  if (root.localName == name && root.namespaceUri == namespaceUri) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespaceUri);
  }
}

XmlElement _pageProperties(XmlDocument document, int index) {
  final page = _elements(document.root!, 'page', _drawNs).elementAt(index);
  final name = page.getAttribute('style-name', namespaceUri: _drawNs);
  final style = _elements(document.root!, 'style', _styleNs).singleWhere(
    (element) => element.getAttribute('name', namespaceUri: _styleNs) == name,
  );
  expect(style.getAttribute('family', namespaceUri: _styleNs), 'drawing-page');
  return style
      .childrenNamed('drawing-page-properties', namespaceUri: _styleNs)
      .single;
}
