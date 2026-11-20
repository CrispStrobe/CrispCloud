import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart';
import 'package:test/test.dart';

const _body =
    '<p:txBody><a:bodyPr anchor="ctr" lIns="114300"><a:normAutofit fontScale="80000"/></a:bodyPr>'
    '<a:lstStyle/><a:p><a:pPr algn="r" rtl="1" marL="127000">'
    '<a:buChar char="•"/><a:defRPr b="1" i="1" u="dbl"/></a:pPr>'
    '<a:r><a:rPr sz="2400" b="1" i="1" u="dbl" lang="de-DE">'
    '<a:solidFill><a:srgbClr val="884422"/></a:solidFill>'
    '<a:latin typeface="Old Latin" charset="1"/><a:ea typeface="Old East Asian"/>'
    '<a:cs typeface="Old Complex"/><a:sym typeface="Symbol"/>'
    '<a:hlinkClick r:id="rIdLink"/><a:rtl val="1"/></a:rPr><a:t>First </a:t></a:r>'
    '<a:fld id="{11111111-2222-3333-4444-555555555555}" type="slidenum">'
    '<a:rPr sz="1800" b="0" i="0" u="none"/><a:t>7</a:t></a:fld>'
    '<a:endParaRPr lang="en-US" b="1" i="1"/></a:p>'
    '<a:p><a:pPr algn="l"/><a:r><a:rPr sz="3200" b="0"/>'
    '<a:t>Second</a:t></a:r></a:p></p:txBody>';

String _shape(int id, String name, {String body = _body}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/>'
    '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
    '<a:off x="0" y="0"/><a:ext cx="4000000" cy="2000000"/>'
    '</a:xfrm><a:prstGeom prst="rect"/></p:spPr>$body</p:sp>';

OpcPackage _package({String? shapes}) {
  final package = OpcPackage.create(OpcPackageKind.slide);
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
        'xmlns:r="${OfficeNamespaces.r}"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr/>${shapes ?? _shape(2, 'Title')}'
        '</p:spTree></p:cSld></p:sld>',
      );
  package
      .relationshipsFor('/ppt/slides/slide1.xml')
      .add(
        id: 'rIdLink',
        type: '${OfficeNamespaces.r}/hyperlink',
        target: 'https://example.test/preserved',
        targetMode: RelationshipTargetMode.external,
      );
  return package;
}

PmlPresentation _deck({String? shapes}) =>
    SlideDeserializer().read(_package(shapes: shapes));

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.a) {
      yield child;
    }
    yield* _descendants(child, name);
  }
}

XmlElement _savedBody(PmlPresentation deck) {
  final package = OpcPackage.openBytes(SlideSerializer().writeBytes(deck));
  return XmlDocument.parse(
        package.getPart('/ppt/slides/slide1.xml')!.readText(),
      ).root!
      .firstChild('cSld', namespaceUri: OfficeNamespaces.p)!
      .firstChild('spTree', namespaceUri: OfficeNamespaces.p)!
      .firstChild('sp', namespaceUri: OfficeNamespaces.p)!
      .firstChild('txBody', namespaceUri: OfficeNamespaces.p)!;
}

void _format(PmlPresentation deck, Map<String, Object?> values) =>
    applySlideStep(deck, <String, Object?>{
      'op': 'shapeFormat',
      'slide': 0,
      'shape': 0,
      ...values,
    });

void main() {
  test(
    'authored display runs cannot outlive native scalar text replacement',
    () {
      for (final format in [false, true]) {
        final target = PmlShape(
          id: 2,
          name: 'Authored',
          text: 'Original',
          fontSizePt: 18,
          textColor: '112233',
          richText: [
            PmlTextParagraph(
              align: PmlTextAlign.right,
              runs: [
                PmlTextRun(
                  text: 'Old display text',
                  fontSizePt: 40,
                  color: 'AA0000',
                  fontFamily: 'Old face',
                  bold: true,
                  italic: true,
                  underline: true,
                ),
              ],
            ),
          ],
        );
        final deck = PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [target]),
          ],
        );
        applySlideStep(deck, {
          'op': 'shapeText',
          'shape': 0,
          'text': 'Replacement\nNext',
        });
        if (format) {
          _format(deck, {'font': 'Liberation Sans', 'bold': false});
        }
        final live = target.copy().resolvedRichText;
        final saved = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single
            .shapes
            .single
            .richText;
        expect(live.map((p) => p.runs.single.text), ['Replacement', 'Next']);
        expect(target.richText.single.runs.single.text, 'Old display text');
        for (var index = 0; index < live.length; index++) {
          final before = live[index].runs.single;
          final after = saved[index].runs.single;
          expect(live[index].align, PmlTextAlign.left);
          expect(saved[index].align, live[index].align);
          expect(
            (
              before.text,
              before.fontSizePt,
              before.color,
              before.fontFamily,
              before.bold,
              before.italic,
              before.underline,
            ),
            (
              index == 0 ? 'Replacement' : 'Next',
              18.0,
              '112233',
              format ? 'Liberation Sans' : '',
              false,
              false,
              false,
            ),
          );
          expect(
            (
              after.text,
              after.fontSizePt,
              after.color,
              after.fontFamily,
              after.bold,
              after.italic,
              after.underline,
            ),
            (
              before.text,
              before.fontSizePt,
              before.color,
              before.fontFamily,
              before.bold,
              before.italic,
              before.underline,
            ),
          );
        }
      }
    },
  );

  test(
    'default authored shape reopens and accepts native text replacement',
    () {
      final original = PmlPresentation(
        slides: [
          PmlSlide(
            id: 256,
            shapes: [PmlShape(id: 2, name: 'Title', text: 'Original')],
          ),
        ],
      );
      final deck = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(original),
      );
      expect(deck.slides.single.shapes.single.text, 'Original');
      applySlideStep(deck, {
        'op': 'shapeText',
        'shapeName': 'Title',
        'topLevel': true,
        'text': 'Replacement',
      });
      expect(
        deck
            .slides
            .single
            .shapes
            .single
            .resolvedRichText
            .single
            .runs
            .single
            .text,
        'Replacement',
      );
      final saved = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(deck),
      );
      expect(saved.slides.single.shapes.single.text, 'Replacement');
    },
  );

  test(
    'whole-text style preserves field, hyperlink, paragraph and body XML',
    () {
      var deck = _deck();
      final original = deck.slides.single.shapes.single;
      final snapshot = original.textSource!.xml;
      _format(deck, {
        'bold': false,
        'italic': false,
        'underline': false,
        'font': 'Liberation Sans',
      });
      expect(original.textSource!.xml, snapshot);
      final rendered = original.resolvedRichText.expand(
        (paragraph) => paragraph.runs,
      );
      expect(rendered.map((run) => run.text), ['First ', '7', 'Second']);
      expect(
        rendered.every((run) => !run.bold && !run.italic && !run.underline),
        isTrue,
      );
      expect(
        rendered.every((run) => run.fontFamily == 'Liberation Sans'),
        isTrue,
      );
      expect(original.richText.first.runs.first.bold, isTrue);
      expect(original.copy().textBold, isFalse);
      expect(original.copy().resolvedRichText.first.runs.first.bold, isFalse);
      for (var cycle = 0; cycle < 3; cycle++) {
        final body = _savedBody(deck);
        expect(
          body
              .firstChild('bodyPr', namespaceUri: OfficeNamespaces.a)!
              .getAttribute('anchor'),
          'ctr',
        );
        expect(
          _descendants(body, 'normAutofit').single.getAttribute('fontScale'),
          '80000',
        );
        expect(_descendants(body, 'buChar').single.getAttribute('char'), '•');
        expect(
          _descendants(body, 'fld').single.getAttribute('type'),
          'slidenum',
        );
        expect(
          _descendants(body, 'fld').single.getAttribute('id'),
          '{11111111-2222-3333-4444-555555555555}',
        );
        expect(
          _descendants(
            body,
            'hlinkClick',
          ).single.getAttribute('id', namespaceUri: OfficeNamespaces.r),
          'rIdLink',
        );
        final properties = <XmlElement>[
          ..._descendants(body, 'rPr'),
          ..._descendants(body, 'defRPr'),
          ..._descendants(body, 'endParaRPr'),
        ];
        expect(properties, hasLength(7));
        for (final props in properties) {
          expect(props.getAttribute('b'), '0');
          expect(props.getAttribute('i'), '0');
          expect(props.getAttribute('u'), 'none');
          for (final script in ['latin', 'ea', 'cs']) {
            expect(
              props
                  .firstChild(script, namespaceUri: OfficeNamespaces.a)!
                  .getAttribute('typeface'),
              'Liberation Sans',
            );
          }
        }
        final first = _descendants(body, 'rPr').first;
        expect(first.childElements.map((node) => node.localName), [
          'solidFill',
          'latin',
          'ea',
          'cs',
          'sym',
          'hlinkClick',
          'rtl',
        ]);
        expect(first.getAttribute('lang'), 'de-DE');
        expect(
          first
              .firstChild('latin', namespaceUri: OfficeNamespaces.a)!
              .getAttribute('charset'),
          '1',
        );
        final bytes = SlideSerializer().writeBytes(deck);
        final package = OpcPackage.openBytes(bytes);
        expect(
          package
              .relationshipsFor('/ppt/slides/slide1.xml')
              .items
              .singleWhere((relationship) => relationship.id == 'rIdLink')
              .target,
          'https://example.test/preserved',
        );
        deck = SlideDeserializer().readBytes(bytes);
        expect(
          deck.slides.single.shapes.single.richText.first.runs.first.bold,
          isFalse,
        );
      }
    },
  );

  test(
    'same representative size, color and alignment still format every run',
    () {
      final deck = _deck();
      final target = deck.slides.single.shapes.single;
      final size = target.fontSizePt;
      final color = target.textColor;
      final alignment = target.textAlign;
      _format(deck, {
        'size': size,
        'color': color,
        'alignment': alignment.name,
      });
      expect(
        target.resolvedRichText
            .expand((p) => p.runs)
            .every((run) => run.fontSizePt == size && run.color == color),
        isTrue,
      );
      expect(
        target.resolvedRichText.every(
          (paragraph) => paragraph.align == alignment,
        ),
        isTrue,
      );
      final body = _savedBody(deck);
      for (final props in _descendants(body, 'rPr')) {
        expect(props.getAttribute('sz'), '${(size * 100).round()}');
        expect(
          _descendants(props, 'srgbClr').single.getAttribute('val'),
          color,
        );
      }
      expect(_descendants(body, 'rPr').first.getAttribute('b'), '1');
    },
  );

  for (final restoreOriginal in [false, true]) {
    test(
      restoreOriginal
          ? 'replacement then original text cannot revive imported fields or runs'
          : 'same-value native text assignment replaces imported fields and runs',
      () {
        const body =
            '<p:txBody><a:bodyPr anchor="ctr"/><a:lstStyle/><a:p>'
            '<a:pPr algn="r"/>'
            '<a:fld id="{field}" type="slidenum">'
            '<a:rPr sz="4000" i="1"/><a:t>7</a:t></a:fld>'
            '<a:r><a:rPr sz="1000" i="0"/><a:t>Original</a:t></a:r>'
            '<a:r><a:rPr sz="2000" i="1"><a:hlinkClick r:id="rIdLink"/>'
            '</a:rPr><a:t> linked</a:t></a:r></a:p></p:txBody>';
        var deck = _deck(shapes: _shape(2, 'Title', body: body));
        final target = deck.slides.single.shapes.single;
        final originalText = target.text;
        final sourceSnapshot = target.textSource!.xml;
        expect(originalText, '7Original linked');
        expect(target.richText.single.runs, hasLength(3));
        expect(target.hasCurrentRichText, isTrue);
        if (restoreOriginal) {
          applySlideStep(deck, {
            'op': 'shapeText',
            'shapeName': 'Title',
            'topLevel': true,
            'text': 'Temporary replacement',
          });
        }
        applySlideStep(deck, {
          'op': 'shapeText',
          'shapeName': 'Title',
          'topLevel': true,
          'text': originalText,
        });
        final live = target.copy().resolvedRichText.single.runs.single;
        expect(target.hasCurrentRichText, isFalse);
        expect(
          (live.text, live.fontSizePt, live.italic),
          (originalText, 10.0, false),
        );
        expect(target.textSource!.xml, sourceSnapshot);
        expect(target.richText.single.runs, hasLength(3));
        for (var cycle = 0; cycle < 2; cycle++) {
          final savedBody = _savedBody(deck);
          expect(_descendants(savedBody, 'fld'), isEmpty);
          expect(_descendants(savedBody, 'hlinkClick'), isEmpty);
          expect(_descendants(savedBody, 'r'), hasLength(1));
          expect(_descendants(savedBody, 't').single.text, originalText);
          expect(
            _descendants(savedBody, 'bodyPr').single.getAttribute('anchor'),
            'ctr',
          );
          expect(
            _descendants(savedBody, 'pPr').single.getAttribute('algn'),
            'r',
          );
          deck = SlideDeserializer().readBytes(
            SlideSerializer().writeBytes(deck),
          );
          final saved =
              deck.slides.single.shapes.single.richText.single.runs.single;
          expect(
            (saved.text, saved.fontSizePt, saved.italic),
            (live.text, live.fontSizePt, live.italic),
          );
        }
      },
    );
  }

  test(
    'new and replaced text display overrides and save consecutive assignments',
    () {
      for (final imported in [false, true]) {
        var deck = imported
            ? _deck()
            : PmlPresentation(
                slides: [
                  PmlSlide(id: 256, shapes: [PmlShape(id: 2, name: 'Title')]),
                ],
              );
        _format(deck, {
          'bold': true,
          'italic': true,
          'underline': true,
          'font': 'Liberation Serif',
        });
        applySlideStep(deck, {
          'op': 'shapeText',
          'shape': 0,
          'text': 'New\nNext',
        });
        final target = deck.slides.single.shapes.single;
        expect(target.resolvedRichText.map((p) => p.runs.single.text), [
          'New',
          'Next',
        ]);
        expect(
          target.resolvedRichText
              .expand((p) => p.runs)
              .every(
                (run) =>
                    run.bold &&
                    run.italic &&
                    run.underline &&
                    run.fontFamily == 'Liberation Serif',
              ),
          isTrue,
        );
        _format(deck, {'bold': false});
        deck = SlideDeserializer().readBytes(
          SlideSerializer().writeBytes(deck),
        );
        expect(deck.slides.single.shapes.single.text, 'New\nNext');
        expect(
          deck.slides.single.shapes.single.richText
              .expand((p) => p.runs)
              .every(
                (run) =>
                    !run.bold &&
                    run.italic &&
                    run.underline &&
                    run.fontFamily == 'Liberation Serif',
              ),
          isTrue,
        );
      }
    },
  );

  test('formatting an empty shape creates a persistent text body', () {
    var deck = _deck(shapes: _shape(2, 'Empty', body: ''));
    _format(deck, {'bold': false, 'font': 'Liberation Sans', 'size': 20});
    final body = _savedBody(deck);
    expect(_descendants(body, 'p'), hasLength(1));
    expect(_descendants(body, 'endParaRPr').single.getAttribute('b'), '0');
    deck = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));
    applySlideStep(deck, {
      'op': 'shapeText',
      'shapeName': 'Empty',
      'text': 'Later',
    });
    final rendered =
        deck.slides.single.shapes.single.resolvedRichText.single.runs.single;
    expect(rendered.bold, isFalse);
    expect(rendered.fontFamily, 'Liberation Sans');
    expect(rendered.fontSizePt, 20);
    final saved = SlideDeserializer().readBytes(
      SlideSerializer().writeBytes(deck),
    );
    final run = saved.slides.single.shapes.single.richText.single.runs.single;
    expect(run.bold, isFalse);
    expect(run.fontFamily, 'Liberation Sans');
    expect(run.fontSizePt, 20);
  });

  for (final (label, prefix, expectedSize, expectedItalic)
      in <(String, String, double, bool)>[
        (
          'field',
          '<a:fld id="{field}" type="slidenum"><a:rPr sz="4000" i="1"/><a:t>7</a:t></a:fld>',
          10,
          false,
        ),
        ('break', '<a:br><a:rPr sz="4000" i="1"/></a:br>', 10, false),
        ('empty run', '<a:r><a:rPr sz="4000" i="1"/><a:t/></a:r>', 40, true),
      ]) {
    test(
      'replacement uses the same live and saved template after a leading $label',
      () {
        final body =
            '<p:txBody><a:bodyPr/><a:lstStyle/><a:p>$prefix'
            '<a:r><a:rPr sz="1000" i="0"/><a:t>Ordinary</a:t></a:r></a:p></p:txBody>';
        final deck = _deck(shapes: _shape(2, 'Title', body: body));
        applySlideStep(deck, {
          'op': 'shapeText',
          'shape': 0,
          'text': 'Replacement',
        });
        _format(deck, {'bold': true});
        final live = deck
            .slides
            .single
            .shapes
            .single
            .resolvedRichText
            .single
            .runs
            .single;
        expect(live.fontSizePt, expectedSize);
        expect(live.italic, expectedItalic);
        expect(live.bold, isTrue);
        final saved = SlideDeserializer()
            .readBytes(SlideSerializer().writeBytes(deck))
            .slides
            .single
            .shapes
            .single
            .richText
            .single
            .runs
            .single;
        expect(saved.fontSizePt, live.fontSizePt);
        expect(saved.italic, live.italic);
        expect(saved.bold, live.bold);
      },
    );
  }

  test(
    'existing empty paragraph retains explicit defaults after reopen and replacement',
    () {
      var deck = _deck(
        shapes: _shape(
          2,
          'Empty',
          body:
              '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr b="1"/></a:p></p:txBody>',
        ),
      );
      _format(deck, {
        'bold': false,
        'italic': true,
        'underline': true,
        'font': 'Liberation Serif',
        'size': 22,
      });
      deck = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));
      applySlideStep(deck, {'op': 'shapeText', 'shape': 0, 'text': 'Later'});
      final live =
          deck.slides.single.shapes.single.resolvedRichText.single.runs.single;
      expect(
        (
          live.bold,
          live.italic,
          live.underline,
          live.fontFamily,
          live.fontSizePt,
        ),
        (false, true, true, 'Liberation Serif', 22.0),
      );
      final saved = SlideDeserializer()
          .readBytes(SlideSerializer().writeBytes(deck))
          .slides
          .single
          .shapes
          .single
          .richText
          .single
          .runs
          .single;
      expect(
        (
          saved.bold,
          saved.italic,
          saved.underline,
          saved.fontFamily,
          saved.fontSizePt,
        ),
        (
          live.bold,
          live.italic,
          live.underline,
          live.fontFamily,
          live.fontSizePt,
        ),
      );
    },
  );

  test(
    'exact names select independently of order and reject ambiguous names',
    () {
      final deck = _deck(shapes: '${_shape(2, 'Title')}${_shape(3, 'title')}');
      applySlideStep(deck, {
        'op': 'shapeText',
        'shapeName': 'Title',
        'topLevel': true,
        'text': 'Selected',
      });
      expect(deck.slides.single.shapes.first.text, 'Selected');
      expect(deck.slides.single.shapes.last.text, 'First 7\nSecond');
      for (final selector in <Map<String, Object?>>[
        {},
        {'shape': 0, 'shapeName': 'Title'},
        {'shapeName': 'TITLE'},
        {'shapeName': ''},
      ]) {
        expect(
          () => applySlideStep(deck, {
            'op': 'shapeText',
            ...selector,
            'text': 'No',
          }),
          throwsArgumentError,
        );
      }
      deck.slides.single.shapes.last.name = 'Title';
      expect(
        () => applySlideStep(deck, {
          'op': 'shapeText',
          'shapeName': 'Title',
          'text': 'No',
        }),
        throwsArgumentError,
      );
    },
  );

  test('picture and table formatting refuses text operations', () {
    final deck = PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Picture',
              visual: OfficeVisual(kind: OfficeVisualKind.picture),
            ),
            PmlShape(id: 3, name: 'Table', table: PmlTable()),
          ],
        ),
      ],
    );
    for (final name in ['Picture', 'Table']) {
      for (final op in ['shapeText', 'shapeFormat']) {
        expect(
          () => applySlideStep(deck, {
            'op': op,
            'shapeName': name,
            if (op == 'shapeText') 'text': 'No' else 'bold': false,
          }),
          throwsArgumentError,
        );
      }
    }
  });

  for (final prefix in <String>[
    '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="9" name="Empty group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:grpSp>',
    '<p:contentPart r:id="rIdUnknown"/>',
    '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="9" name="OLE"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><a:graphic><a:graphicData uri="urn:unmodeled"/></a:graphic></p:graphicFrame>',
    '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="9" name="Group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>${_shape(10, 'Child')}</p:grpSp>',
  ]) {
    test(
      'strict Office shape collection refuses ${prefix.substring(0, prefix.indexOf('>') + 1)} before a target',
      () async {
        final Uint8List bytes = _package(
          shapes: '$prefix${_shape(2, 'Title')}',
        ).save();
        final session = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.pptx,
        );
        final macro = OfficeMacro(
          name: 'Reject shifted index',
          format: OfficeMacroFormat.pptx,
          steps: [
            OfficeMacroStep(
              tool: 'pptx.shapeText',
              arguments: {
                'slide': 0,
                'shape': 0,
                'topLevel': true,
                'text': 'Wrong target',
              },
            ),
          ],
        );
        await expectLater(
          session.run(macro),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, bytes);
        expect(session.revision, 0);
      },
    );
  }

  test(
    'strict selectors reject stale model order and duplicate native IDs',
    () {
      final deck = _deck(shapes: '${_shape(2, 'First')}${_shape(3, 'Second')}');
      deck.slides.single.shapes = deck.slides.single.shapes.reversed.toList();
      expect(
        () => applySlideStep(deck, {
          'op': 'shapeGeometry',
          'shape': 0,
          'topLevel': true,
          'x': 10,
        }),
        throwsUnsupportedError,
      );
      final duplicate = _deck(
        shapes: '${_shape(2, 'First')}${_shape(2, 'Second')}',
      );
      expect(
        () => applySlideStep(duplicate, {
          'op': 'shapeText',
          'shape': 0,
          'topLevel': true,
          'text': 'No',
        }),
        throwsUnsupportedError,
      );
    },
  );
}
