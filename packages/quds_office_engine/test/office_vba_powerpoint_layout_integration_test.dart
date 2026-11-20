import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart';
import 'package:test/test.dart';

const _presentation = OfficeNamespaces.p;
const _drawing = OfficeNamespaces.a;
const _compatibility = OfficeNamespaces.mc;
const _powerPoint2010 =
    'http://schemas.microsoft.com/office/powerpoint/2010/main';
const _foreign = 'urn:quds:test:foreign';
const _slidePart = '/ppt/slides/slide1.xml';

const _richBody = '''
<p:txBody>
  <a:bodyPr x:anchor="foreign-anchor" anchor="ctr" lIns="114300"
      rIns="228600" tIns="57150" bIns="76200" vert="vert270" x:custom="keep">
    <a:normAutofit fontScale="80000" lnSpcReduction="12000"/>
  </a:bodyPr>
  <a:lstStyle/>
  <a:p>
    <a:pPr algn="r"/>
    <a:r><a:rPr b="1" sz="1800"><a:hlinkClick r:id="rIdLink"/></a:rPr><a:t>Rich </a:t></a:r>
    <a:r><a:rPr i="1" sz="2400"/><a:t>title</a:t></a:r>
    <a:fld id="{11111111-1111-1111-1111-111111111111}" type="slidenum"><a:rPr lang="en-US"/><a:t>1</a:t></a:fld>
    <a:endParaRPr sz="1800"/>
  </a:p>
</p:txBody>
''';

const _transition = '''
<p:transition xmlns:p14="urn:quds:test:occupied"
    x:spd="foreign-speed" x:dur="foreign-duration"
    x:advClick="foreign-click" x:advTm="foreign-time"
    spd="med" q:dur="900" advClick="1" advTm="2500">
  <p:push x:dir="foreign-direction" dir="r"/>
  <p:sndAc><p:stSnd loop="1"><p:snd r:embed="rIdSound" name="chime"/></p:stSnd></p:sndAc>
  <p:extLst><p:ext uri="{fixture}"><x:payload keep="yes"/></p:ext></p:extLst>
</p:transition>
''';

const _unknownTransition = '''
<p:transition q:dur="900" advClick="1" advTm="2500">
  <q:reveal x:token="opaque-effect"/>
  <p:sndAc><p:endSnd/></p:sndAc>
  <p:extLst><p:ext uri="{fixture}"><x:payload keep="yes"/></p:ext></p:extLst>
</p:transition>
''';

const _alternateTransition = '''
<mc:AlternateContent x:container="keep">
  <mc:Choice Requires="p14 unused" x:choice="keep">
    <p:transition q:dur="900" advClick="0" advTm="2500">
      <p14:ripple dir="l"/>
      <p:sndAc><p:endSnd/></p:sndAc>
    </p:transition>
  </mc:Choice>
  <mc:Fallback>
    <p:transition spd="med"><p:fade/></p:transition>
  </mc:Fallback>
</mc:AlternateContent>
''';

Uint8List _authoredBytes({bool empty = false}) => SlideSerializer().writeBytes(
  PmlPresentation(
    slides: <PmlSlide>[
      PmlSlide(
        id: 256,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: empty ? '' : 'Original title'),
        ],
      ),
      PmlSlide(
        id: 257,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Other', text: 'Untouched second slide'),
        ],
      ),
    ],
  ),
);

Uint8List _nativeBytes({
  String body = _richBody,
  String transition = _transition,
  String extraShapes = '',
  String rootCompatibility = '',
}) {
  final package = OpcPackage.openBytes(_authoredBytes());
  package.getPart(_slidePart)!.writeText('''
<p:sld xmlns:p="$_presentation" xmlns:a="$_drawing"
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    xmlns:mc="$_compatibility" xmlns:p14="$_powerPoint2010"
    xmlns:q="$_powerPoint2010" xmlns:x="$_foreign"
    xmlns:unused="urn:quds:test:requires-only" mc:Ignorable="p14 q x unused"
    $rootCompatibility>
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="4000000" cy="2000000"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr>
        $body
      </p:sp>
      $extraShapes
    </p:spTree>
  </p:cSld>
  $transition
</p:sld>
''');
  return package.save();
}

OfficeMacro _plan(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'Slideshow',
    source:
        '''
Option Explicit
Sub Main()
Dim selected As Slide
Set selected = ActivePresentation.Slides(1)
$body
End Sub
''',
  ),
);

OfficeMacroSession _session(Uint8List bytes, {OfficeMacroPolicy? policy}) =>
    OfficeMacroSession(bytes, format: OfficeMacroFormat.pptx, policy: policy);

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

XmlElement _root(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart(_slidePart)!.readText(),
).root!;

XmlElement _textBody(Uint8List bytes) => _root(bytes)
    .firstChild('cSld', namespaceUri: _presentation)!
    .firstChild('spTree', namespaceUri: _presentation)!
    .firstChild('sp', namespaceUri: _presentation)!
    .firstChild('txBody', namespaceUri: _presentation)!;

XmlElement _bodyProperties(Uint8List bytes) =>
    _textBody(bytes).firstChild('bodyPr', namespaceUri: _drawing)!;

XmlElement _motion(Uint8List bytes) =>
    _root(bytes).firstChild('transition', namespaceUri: _presentation)!;

String _xml(XmlElement element) =>
    XmlDocument(root: element.copy()).toXmlString(declaration: false);

void _expectUnrelatedTransitionData(XmlElement motion) {
  expect(motion.getAttribute('spd', namespaceUri: _foreign), 'foreign-speed');
  expect(
    motion.getAttribute('dur', namespaceUri: _foreign),
    'foreign-duration',
  );
  expect(
    motion.getAttribute('advClick', namespaceUri: _foreign),
    'foreign-click',
  );
  expect(motion.getAttribute('advTm', namespaceUri: _foreign), 'foreign-time');
  expect(
    motion
        .firstChild('sndAc', namespaceUri: _presentation)!
        .firstChild('stSnd', namespaceUri: _presentation)!
        .getAttribute('loop', namespaceUri: ''),
    '1',
  );
  expect(
    motion
        .firstChild('extLst', namespaceUri: _presentation)!
        .firstChild('ext', namespaceUri: _presentation)!
        .firstChild('payload', namespaceUri: _foreign)!
        .getAttribute('keep', namespaceUri: ''),
    'yes',
  );
}

void main() {
  for (final entry in <PmlTextAnchor, String>{
    PmlTextAnchor.top: 't',
    PmlTextAnchor.center: 'ctr',
    PmlTextAnchor.bottom: 'b',
  }.entries) {
    final anchor = entry.key;
    test(
      'anchor $anchor preserves rich text and unrelated body properties',
      () {
        final bytes = _nativeBytes();
        final paragraphs = _textBody(
          bytes,
        ).childrenNamed('p', namespaceUri: _drawing).map(_xml).toList();
        final deck = SlideDeserializer().readBytes(bytes);
        expect(deck.slides.first.shapes.first.textAnchor, PmlTextAnchor.center);
        applySlideStep(deck, <String, Object?>{
          'op': 'shapeTextFrame',
          'slide': 0,
          'shapeName': 'Title',
          'topLevel': true,
          'anchor': anchor.name,
        });
        final shape = deck.slides.first.shapes.first;
        expect(shape.textAnchor, anchor);
        expect(shape.textAnchorOverride, isTrue);
        expect(shape.copy().textAnchorOverride, isTrue);
        expect(deck.slides.first.copy().shapes.first.textAnchor, anchor);

        var saved = SlideSerializer().writeBytes(deck);
        for (var cycle = 0; cycle < 2; cycle++) {
          final properties = _bodyProperties(saved);
          expect(
            properties.getAttribute('anchor', namespaceUri: ''),
            entry.value,
          );
          expect(
            properties.getAttribute('anchor', namespaceUri: _foreign),
            'foreign-anchor',
          );
          expect(properties.getAttribute('lIns', namespaceUri: ''), '114300');
          expect(properties.getAttribute('rIns', namespaceUri: ''), '228600');
          expect(properties.getAttribute('tIns', namespaceUri: ''), '57150');
          expect(properties.getAttribute('bIns', namespaceUri: ''), '76200');
          expect(properties.getAttribute('vert', namespaceUri: ''), 'vert270');
          expect(
            properties.getAttribute('custom', namespaceUri: _foreign),
            'keep',
          );
          final autofit = properties.firstChild(
            'normAutofit',
            namespaceUri: _drawing,
          )!;
          expect(autofit.getAttribute('fontScale', namespaceUri: ''), '80000');
          expect(
            autofit.getAttribute('lnSpcReduction', namespaceUri: ''),
            '12000',
          );
          expect(
            _textBody(
              saved,
            ).childrenNamed('p', namespaceUri: _drawing).map(_xml),
            paragraphs,
          );
          final reopened = SlideDeserializer().readBytes(saved);
          expect(reopened.slides.first.shapes.first.textAnchor, anchor);
          saved = SlideSerializer().writeBytes(reopened);
        }
      },
    );

    test('explicit $anchor creates an empty text body and survives copy', () {
      final deck = SlideDeserializer().readBytes(_authoredBytes(empty: true));
      final target = deck.slides.first.shapes.first;
      expect(target.textSource, isNull);
      applySlideStep(deck, <String, Object?>{
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'topLevel': true,
        'anchor': anchor.name,
      });
      deck.slides[0] = deck.slides.first.copy();
      final saved = SlideSerializer().writeBytes(deck);
      expect(
        _bodyProperties(saved).getAttribute('anchor', namespaceUri: ''),
        entry.value,
      );
      final reopened = SlideDeserializer().readBytes(saved);
      expect(reopened.slides.first.shapes.first.text, isEmpty);
      expect(reopened.slides.first.shapes.first.textAnchor, anchor);
      expect(
        _textBody(saved).childrenNamed('p', namespaceUri: _drawing),
        hasLength(1),
      );
    });
  }

  test(
    'same-value top replaces an unsupported source anchor explicitly',
    () async {
      final bytes = _nativeBytes(
        body: _richBody.replaceFirst('anchor="ctr"', 'anchor="just"'),
      );
      final imported = SlideDeserializer()
          .readBytes(bytes)
          .slides
          .first
          .shapes
          .first;
      expect(imported.textAnchor, PmlTextAnchor.top);
      final session = _session(bytes);
      await session.run(
        _plan(
          'selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorTop',
        ),
      );
      expect(
        _bodyProperties(session.bytes).getAttribute('anchor', namespaceUri: ''),
        't',
      );
      expect(
        _bodyProperties(
          session.bytes,
        ).getAttribute('anchor', namespaceUri: _foreign),
        'foreign-anchor',
      );
    },
  );

  for (final target in <String, PmlShape>{
    'picture': PmlShape(
      id: 2,
      name: 'Title',
      visual: OfficeVisual(kind: OfficeVisualKind.picture),
    ),
    'table': PmlShape(id: 2, name: 'Title', table: PmlTable()),
    'invalid anchor': PmlShape(id: 2, name: 'Title'),
  }.entries) {
    final name = target.key;
    test('native text frame rejects $name before changing the model', () {
      final shape = target.value;
      final deck = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256, shapes: <PmlShape>[shape]),
        ],
      );
      expect(
        () => applySlideStep(deck, <String, Object?>{
          'op': 'shapeTextFrame',
          'slide': 0,
          'shape': 0,
          'topLevel': true,
          'anchor': name == 'invalid anchor' ? 'baseline' : 'bottom',
        }),
        throwsArgumentError,
      );
      expect(shape.textAnchor, PmlTextAnchor.top);
      expect(shape.textAnchorOverride, isFalse);
    });
  }

  test('strict TextFrame selection refuses even an empty group', () async {
    final bytes = _nativeBytes(
      extraShapes: '''
<p:grpSp><p:nvGrpSpPr><p:cNvPr id="3" name="Empty group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:grpSp>
''',
    );
    final session = _session(bytes);
    final plan = _plan(
      'selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorBottom',
    );
    await expectLater(
      session.validate(plan),
      throwsA(_error('operation_failed')),
    );
    await expectLater(session.run(plan), throwsA(_error('operation_failed')));
    expect(session.bytes, bytes);
    expect(session.revision, 0);
  });

  test(
    'typed layout and transition helpers publish one saved result',
    () async {
      final bytes = _nativeBytes();
      final session = _session(bytes);
      final plan = OfficeMacroLanguages().compile(
        OfficeMacroSource(
          language: 'vba-powerpoint',
          format: OfficeMacroFormat.pptx,
          source: '''
Option Explicit
Sub Main()
Dim selected As Slide
Dim frame As TextFrame, movement As SlideShowTransition
Set selected = ActivePresentation.Slides(1)
Set frame = selected.Shapes("Title").TextFrame
Set movement = selected.SlideShowTransition
Call Configure(frame, movement)
End Sub
Sub Configure(ByVal frame As TextFrame, ByVal movement As SlideShowTransition)
With frame
  .VerticalAnchor = msoAnchorBottom
End With
With movement
  .Hidden = msoTrue
  .AdvanceOnClick = False
  .Duration = 1.25
  .EntryEffect = ppEffectWipeUp
End With
End Sub
''',
        ),
      );
      session.startRecording('Playback stays separate');
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, bytes);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
      expect(session.stopRecording().steps, isEmpty);
      final deck = SlideDeserializer().readBytes(session.bytes);
      expect(deck.slides.map((slide) => slide.id), <int>[256, 257]);
      expect(deck.slides.first.hidden, isTrue);
      expect(deck.slides[1].hidden, isFalse);
      expect(deck.slides[1].shapes.first.text, 'Untouched second slide');
      expect(deck.slides.first.shapes.first.textAnchor, PmlTextAnchor.bottom);
      final transition = deck.slides.first.transition;
      expect(transition.kind, PmlTransitionKind.wipe);
      expect(transition.direction, PmlTransitionDir.up);
      expect(transition.durationMs, 1250);
      expect(transition.advanceOnClick, isFalse);
      expect(transition.advanceAfterMs, 2500);
      expect(_root(session.bytes).getAttribute('show', namespaceUri: ''), '0');
      final motion = _motion(session.bytes);
      expect(motion.getAttribute('dur', namespaceUri: _powerPoint2010), '1250');
      expect(motion.getAttribute('advClick', namespaceUri: ''), '0');
      expect(motion.getAttribute('advTm', namespaceUri: ''), '2500');
      expect(
        motion
            .firstChild('wipe', namespaceUri: _presentation)!
            .getAttribute('dir', namespaceUri: ''),
        'u',
      );
      _expectUnrelatedTransitionData(motion);
    },
  );

  for (final example
      in <String, (String, PmlTransitionKind, PmlTransitionDir, int, bool)>{
        'duration': (
          '.Duration = 1.25',
          PmlTransitionKind.push,
          PmlTransitionDir.right,
          1250,
          true,
        ),
        'click': (
          '.AdvanceOnClick = False',
          PmlTransitionKind.push,
          PmlTransitionDir.right,
          900,
          false,
        ),
        'effect': (
          '.EntryEffect = ppEffectWipeUp',
          PmlTransitionKind.wipe,
          PmlTransitionDir.up,
          900,
          true,
        ),
        'hidden': (
          '.Hidden = True',
          PmlTransitionKind.push,
          PmlTransitionDir.right,
          900,
          true,
        ),
      }.entries) {
    final property = example.key;
    test(
      '$property alone preserves other transition fields and automatic advance',
      () async {
        final bytes = _nativeBytes();
        final session = _session(bytes);
        final assignment = example.value.$1;
        await session.run(
          _plan('With selected.SlideShowTransition\n$assignment\nEnd With'),
        );
        final slide = SlideDeserializer().readBytes(session.bytes).slides.first;
        expect(slide.transition.kind, example.value.$2);
        expect(slide.transition.direction, example.value.$3);
        expect(slide.transition.durationMs, example.value.$4);
        expect(slide.transition.advanceOnClick, example.value.$5);
        expect(slide.transition.advanceAfterMs, 2500);
        expect(slide.hidden, property == 'hidden');
        final saved = _motion(session.bytes);
        _expectUnrelatedTransitionData(saved);
        if (property != 'effect') {
          expect(
            saved
                .firstChild('push', namespaceUri: _presentation)!
                .getAttribute('dir', namespaceUri: _foreign),
            'foreign-direction',
          );
        }
      },
    );
  }

  for (final prefix in <String>['q', '']) {
    test(
      'effect writes use the imported transition namespace prefix "$prefix"',
      () async {
        final transition = prefix.isEmpty
            ? '<transition xmlns="$_presentation" p14:dur="900"><push dir="r"/></transition>'
            : '<q:transition xmlns:q="$_presentation" xmlns:p="$_foreign" p14:dur="900"><q:push dir="r"/></q:transition>';
        final session = _session(_nativeBytes(transition: transition));
        await session.run(
          _plan('selected.SlideShowTransition.EntryEffect = ppEffectWipeUp'),
        );
        final motion = _motion(session.bytes);
        final effect = motion.firstChild('wipe', namespaceUri: _presentation)!;
        expect(effect.prefix, prefix);
        expect(effect.getAttribute('dir', namespaceUri: ''), 'u');
        expect(motion.firstChild('wipe', namespaceUri: _foreign), isNull);
        final reopened = SlideDeserializer()
            .readBytes(session.bytes)
            .slides
            .first
            .transition;
        expect(reopened.kind, PmlTransitionKind.wipe);
        expect(reopened.direction, PmlTransitionDir.up);
        expect(reopened.durationMs, 900);
      },
    );
  }

  test(
    'same-value writes target native namespaces and retain foreign attributes',
    () async {
      final session = _session(_nativeBytes());
      final before = SlideDeserializer()
          .readBytes(session.bytes)
          .slides
          .first
          .transition;
      expect(before.durationMs, 900);
      expect(before.advanceOnClick, isTrue);
      expect(before.direction, PmlTransitionDir.right);
      await session.run(
        _plan('''
With selected.SlideShowTransition
  .Duration = 0.9
  .AdvanceOnClick = msoTrue
End With
'''),
      );
      final motion = _motion(session.bytes);
      _expectUnrelatedTransitionData(motion);
      expect(motion.getAttribute('dur', namespaceUri: _powerPoint2010), '900');
      expect(motion.getAttribute('advClick', namespaceUri: ''), '1');
      expect(
        motion.attributes.where(
          (attribute) =>
              attribute.localName == 'dur' &&
              attribute.namespaceUri == _powerPoint2010,
        ),
        hasLength(1),
      );
      expect(
        motion.attributes
            .singleWhere((attribute) => attribute.qualifiedName == 'xmlns:p14')
            .value,
        'urn:quds:test:occupied',
      );
      final duration = motion.attributes.singleWhere(
        (attribute) =>
            attribute.localName == 'dur' &&
            attribute.namespaceUri == _powerPoint2010,
      );
      expect(duration.prefix, isNot('p14'));
      expect(motion.getAttribute('spd', namespaceUri: ''), 'med');
      final reopened = SlideDeserializer()
          .readBytes(session.bytes)
          .slides
          .first
          .transition;
      expect(reopened.durationMs, 900);
      expect(reopened.advanceOnClick, isTrue);
    },
  );

  test(
    'inherited Ignorable merges by expanded name and original namespace meaning',
    () async {
      final transition = _transition.replaceFirst(
        '<p:transition ',
        '<p:transition xmlns:m="$_compatibility" xmlns:local="urn:quds:test:local" m:Ignorable="local" ',
      );
      final session = _session(_nativeBytes(transition: transition));
      await session.run(_plan('selected.SlideShowTransition.Duration = 1.25'));
      final motion = _motion(session.bytes);
      final ignorable = motion.attributes.where(
        (attribute) =>
            attribute.localName == 'Ignorable' &&
            attribute.namespaceUri == _compatibility,
      );
      expect(ignorable, hasLength(1));
      expect(ignorable.single.prefix, 'm');
      final reader = XmlPullReader(
        OpcPackage.openBytes(session.bytes).getPart(_slidePart)!.readText(),
      );
      var sawTransition = false;
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.namespaceUri == _presentation &&
            reader.localName == 'transition' &&
            reader.depth == 2) {
          sawTransition = true;
          final prefixes = reader
              .getAttribute('Ignorable', namespaceUri: _compatibility)!
              .split(RegExp(r'\s+'));
          final namespaces = prefixes.map(reader.lookupNamespace).toSet();
          expect(namespaces, <String>{
            'urn:quds:test:local',
            _powerPoint2010,
            _foreign,
            'urn:quds:test:requires-only',
          });
          expect(namespaces, isNot(contains('urn:quds:test:occupied')));
        }
      }
      expect(sawTransition, isTrue);
    },
  );

  test(
    'unsupported inherited MC directives refuse save before publication',
    () async {
      final bytes = _nativeBytes(
        rootCompatibility: 'mc:ProcessContent="x:payload"',
      );
      final deck = SlideDeserializer().readBytes(bytes);
      expect(
        deck.slides.first.transition.source!.unsupportedContext,
        isNotNull,
      );
      expect(() => SlideSerializer().writeBytes(deck), throwsUnsupportedError);
      final session = _session(bytes);
      final plan = _plan('selected.SlideShowTransition.Hidden = True');
      await expectLater(
        session.validate(plan),
        throwsA(_error('document_error')),
      );
      await expectLater(session.run(plan), throwsA(_error('document_error')));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
      expect(
        () => applySlideStep(deck, <String, Object?>{
          'op': 'slideTransition',
          'slide': 0,
          'durationMs': 1250,
        }),
        throwsUnsupportedError,
      );
      expect(deck.slides.first.transition.durationMs, 900);
    },
  );

  test('direct native advance-after removal retains foreign attribute', () {
    final deck = SlideDeserializer().readBytes(_nativeBytes());
    deck.slides.first.transition = deck.slides.first.transition.copyWith(
      clearAdvanceAfter: true,
    );
    final saved = SlideSerializer().writeBytes(deck);
    expect(_motion(saved).getAttribute('advTm', namespaceUri: ''), isNull);
    expect(
      _motion(saved).getAttribute('advTm', namespaceUri: _foreign),
      'foreign-time',
    );
    expect(
      SlideDeserializer()
          .readBytes(saved)
          .slides
          .first
          .transition
          .advanceAfterMs,
      isNull,
    );
  });

  test(
    'unknown direct effects survive partial writes, while explicit None owns the effect',
    () async {
      final session = _session(_nativeBytes(transition: _unknownTransition));
      await session.run(
        _plan('''
With selected.SlideShowTransition
  .Duration = 1.25
  .AdvanceOnClick = False
End With
'''),
      );
      var motion = _motion(session.bytes);
      expect(
        motion
            .firstChild('reveal', namespaceUri: _powerPoint2010)!
            .getAttribute('token', namespaceUri: _foreign),
        'opaque-effect',
      );
      var reopened = SlideDeserializer()
          .readBytes(session.bytes)
          .slides
          .first
          .transition;
      expect(reopened.durationMs, 1250);
      expect(reopened.advanceOnClick, isFalse);
      expect(reopened.advanceAfterMs, 2500);
      await session.run(
        _plan('selected.SlideShowTransition.EntryEffect = ppEffectNone'),
      );
      motion = _motion(session.bytes);
      expect(
        motion.firstChild('reveal', namespaceUri: _powerPoint2010),
        isNull,
      );
      expect(motion.firstChild('fade', namespaceUri: _presentation), isNull);
      expect(
        motion.firstChild('sndAc', namespaceUri: _presentation),
        isNotNull,
      );
      expect(
        motion.firstChild('extLst', namespaceUri: _presentation),
        isNotNull,
      );
      reopened = SlideDeserializer()
          .readBytes(session.bytes)
          .slides
          .first
          .transition;
      expect(reopened.kind, PmlTransitionKind.none);
      expect(reopened.durationMs, 1250);
      expect(reopened.advanceOnClick, isFalse);
      expect(reopened.advanceAfterMs, 2500);
    },
  );

  for (final milliseconds in <int>[1, 700, 1250]) {
    test(
      'duration-only $milliseconds ms persists on an authored no-effect slide',
      () async {
        final session = _session(_authoredBytes());
        final seconds = milliseconds / 1000;
        await session.run(
          _plan('selected.SlideShowTransition.Duration = $seconds'),
        );
        var bytes = session.bytes;
        for (var cycle = 0; cycle < 2; cycle++) {
          final motion = _motion(bytes);
          expect(
            motion.getAttribute('dur', namespaceUri: _powerPoint2010),
            '$milliseconds',
          );
          expect(motion.childElements, isEmpty);
          final deck = SlideDeserializer().readBytes(bytes);
          expect(deck.slides.first.transition.kind, PmlTransitionKind.none);
          expect(deck.slides.first.transition.durationMs, milliseconds);
          bytes = SlideSerializer().writeBytes(deck);
        }
      },
    );
  }

  test('no-effect imported transition retains click and automatic advance', () {
    final bytes = _nativeBytes(
      transition: '<p:transition q:dur="1250" advClick="0" advTm="2500"/>',
    );
    final deck = SlideDeserializer().readBytes(bytes);
    expect(deck.slides.first.transition.kind, PmlTransitionKind.none);
    expect(deck.slides.first.transition.durationMs, 1250);
    expect(deck.slides.first.transition.advanceOnClick, isFalse);
    expect(deck.slides.first.transition.advanceAfterMs, 2500);
    final saved = SlideSerializer().writeBytes(deck);
    expect(_motion(saved).childElements, isEmpty);
    expect(_motion(saved).getAttribute('advClick', namespaceUri: ''), '0');
    expect(_motion(saved).getAttribute('advTm', namespaceUri: ''), '2500');
  });

  for (final entry in <(String, String, String, PmlTransitionKind)>[
    (_powerPoint2010, 'reveal', '<effect:reveal/>', PmlTransitionKind.reveal),
    (
      'http://schemas.microsoft.com/office/powerpoint/2012/main',
      'prstTrans',
      '<effect:prstTrans prst="morph"/>',
      PmlTransitionKind.morph,
    ),
    (
      'http://schemas.microsoft.com/office/powerpoint/2015/09/main',
      'morph',
      '<effect:morph option="byObject"/>',
      PmlTransitionKind.morph,
    ),
  ]) {
    final namespace = entry.$1;
    final name = entry.$2;
    final effect = entry.$3;
    test(
      'direct Office $name projects and survives partial transition writes',
      () async {
        final bytes = _nativeBytes(
          transition:
              '''
<p:transition xmlns:effect="$namespace" q:dur="900" advClick="1" advTm="2500">
  $effect
  <p:sndAc><p:endSnd/></p:sndAc>
  <p:extLst><p:ext uri="{fixture}"><x:payload keep="yes"/></p:ext></p:extLst>
</p:transition>
''',
        );
        expect(
          SlideDeserializer().readBytes(bytes).slides.first.transition.kind,
          entry.$4,
        );
        final session = _session(bytes);
        await session.run(
          _plan('''
selected.SlideShowTransition.Duration = 1.25
selected.SlideShowTransition.AdvanceOnClick = False
'''),
        );
        var reopened = SlideDeserializer()
            .readBytes(session.bytes)
            .slides
            .first
            .transition;
        expect(reopened.kind, entry.$4);
        expect(reopened.durationMs, 1250);
        expect(reopened.advanceOnClick, isFalse);
        expect(reopened.advanceAfterMs, 2500);
        expect(
          _motion(session.bytes).firstChild(name, namespaceUri: namespace),
          isNotNull,
        );
        for (final replacement in <String, PmlTransitionKind>{
          'ppEffectNone': PmlTransitionKind.none,
          'ppEffectCut': PmlTransitionKind.cut,
        }.entries) {
          final edited = _session(session.bytes);
          final constant = replacement.key;
          await edited.run(
            _plan('selected.SlideShowTransition.EntryEffect = $constant'),
          );
          reopened = SlideDeserializer()
              .readBytes(edited.bytes)
              .slides
              .first
              .transition;
          expect(reopened.kind, replacement.value);
          expect(reopened.durationMs, 1250);
          expect(reopened.advanceOnClick, isFalse);
          expect(reopened.advanceAfterMs, 2500);
          final motion = _motion(edited.bytes);
          expect(motion.firstChild(name, namespaceUri: namespace), isNull);
          expect(
            motion.firstChild('sndAc', namespaceUri: _presentation),
            isNotNull,
          );
          expect(
            motion.firstChild('extLst', namespaceUri: _presentation),
            isNotNull,
          );
          expect(
            motion.firstChild('cut', namespaceUri: _presentation) != null,
            replacement.value == PmlTransitionKind.cut,
          );
        }
      },
    );
  }

  test(
    'Morph projection rejects foreign namespaces and nested effect lookalikes',
    () {
      for (final effect in <String>[
        '<x:morph option="byObject"/>',
        '<x:prstTrans prst="morph"/>',
        '<p:extLst><p:ext uri="{fixture}"><effect:morph option="byObject"/></p:ext></p:extLst>',
      ]) {
        final bytes = _nativeBytes(
          transition:
              '''
<p:transition xmlns:effect="http://schemas.microsoft.com/office/powerpoint/2015/09/main">
  $effect
</p:transition>
''',
        );
        expect(
          SlideDeserializer().readBytes(bytes).slides.first.transition.kind,
          PmlTransitionKind.none,
        );
      }
    },
  );

  test(
    'legacy motion fragments do not override explicit foreign prefix bindings',
    () {
      for (final xml in <String>[
        '<p:sld xmlns:p="$_foreign"><p:transition><p14:prstTrans prst="morph"/></p:transition></p:sld>',
        '<p:sld xmlns:p14="$_foreign"><p:transition><p14:prstTrans prst="morph"/></p:transition></p:sld>',
        '<x:sld><p:transition><p14:prstTrans prst="morph"/></p:transition></x:sld>',
      ]) {
        final slide = PmlSlide(id: 256);
        parseSlideMotion(xml, slide);
        expect(slide.transition.kind, PmlTransitionKind.none);
      }
    },
  );

  test(
    'a recognized Morph inside root AlternateContent remains opaque',
    () async {
      final bytes = _nativeBytes(
        transition: '''
<mc:AlternateContent xmlns:effect="http://schemas.microsoft.com/office/powerpoint/2015/09/main">
  <mc:Choice Requires="effect">
    <p:transition><effect:morph option="byObject"/></p:transition>
  </mc:Choice>
  <mc:Fallback><p:transition><p:fade/></p:transition></mc:Fallback>
</mc:AlternateContent>
''',
      );
      final transition = SlideDeserializer()
          .readBytes(bytes)
          .slides
          .first
          .transition;
      expect(transition.kind, PmlTransitionKind.none);
      expect(transition.source!.isOpaqueContainer, isTrue);
      final session = _session(bytes);
      await expectLater(
        session.run(_plan('selected.SlideShowTransition.Duration = 1.25')),
        throwsA(_error('operation_failed')),
      );
      expect(session.bytes, bytes);
      expect(session.revision, 0);
    },
  );

  test('nested and foreign transition elements are not slide transitions', () {
    final bytes = _nativeBytes(
      transition: '''
<p:extLst><p:ext uri="{fixture}">
  <x:transition q:dur="5000"><p:fade/></x:transition>
  <p:transition q:dur="6000"><p:push dir="r"/></p:transition>
</p:ext></p:extLst>
''',
    );
    final slide = SlideDeserializer().readBytes(bytes).slides.first;
    expect(slide.transition.source, isNull);
    expect(slide.transition.kind, PmlTransitionKind.none);
    expect(slide.transition.durationMs, 700);
  });

  test(
    'opaque AlternateContent survives save, shape edit and Hidden edit',
    () async {
      final bytes = _nativeBytes(transition: _alternateTransition);
      final imported = SlideDeserializer().readBytes(bytes);
      expect(
        imported.slides.first.transition.source!.isOpaqueContainer,
        isTrue,
      );
      expect(imported.slides.first.transition.kind, PmlTransitionKind.none);
      expect(
        imported.slides.first.copy().transition.source!.isOpaqueContainer,
        isTrue,
      );
      final session = _session(SlideSerializer().writeBytes(imported));
      for (final plan in <OfficeMacro>[
        _plan(
          'selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorBottom',
        ),
        _plan('selected.SlideShowTransition.Hidden = True'),
      ]) {
        await session.validate(plan);
        await session.run(plan);
        final root = _root(session.bytes);
        expect(
          root.firstChild('transition', namespaceUri: _presentation),
          isNull,
        );
        final container = root.firstChild(
          'AlternateContent',
          namespaceUri: _compatibility,
        )!;
        expect(
          container.getAttribute('container', namespaceUri: _foreign),
          'keep',
        );
        final choice = container.firstChild(
          'Choice',
          namespaceUri: _compatibility,
        )!;
        expect(choice.getAttribute('Requires', namespaceUri: ''), 'p14 unused');
        expect(choice.getAttribute('choice', namespaceUri: _foreign), 'keep');
        final chosen = choice.firstChild(
          'transition',
          namespaceUri: _presentation,
        )!;
        expect(
          chosen.getAttribute('dur', namespaceUri: _powerPoint2010),
          '900',
        );
        expect(chosen.getAttribute('advClick', namespaceUri: ''), '0');
        expect(chosen.getAttribute('advTm', namespaceUri: ''), '2500');
        expect(
          chosen.firstChild('ripple', namespaceUri: _powerPoint2010),
          isNotNull,
        );
        expect(
          chosen.firstChild('sndAc', namespaceUri: _presentation),
          isNotNull,
        );
        expect(
          container
              .firstChild('Fallback', namespaceUri: _compatibility)!
              .firstChild('transition', namespaceUri: _presentation)!
              .firstChild('fade', namespaceUri: _presentation),
          isNotNull,
        );
        final reader = XmlPullReader(
          OpcPackage.openBytes(session.bytes).getPart(_slidePart)!.readText(),
        );
        while (reader.next()) {
          if (reader.eventType == XmlEventType.startElement &&
              reader.namespaceUri == _compatibility &&
              reader.localName == 'Choice') {
            expect(
              reader.lookupNamespace('unused'),
              'urn:quds:test:requires-only',
            );
            expect(reader.lookupNamespace('p14'), _powerPoint2010);
          }
        }
        expect(
          SlideDeserializer()
              .readBytes(session.bytes)
              .slides
              .first
              .transition
              .source!
              .isOpaqueContainer,
          isTrue,
        );
      }
      expect(
        SlideDeserializer().readBytes(session.bytes).slides.first.hidden,
        isTrue,
      );
    },
  );

  for (final assignment in <String>[
    '.Duration = 0.7',
    '.AdvanceOnClick = msoTrue',
    '.EntryEffect = ppEffectNone',
  ]) {
    test('opaque-container $assignment refuses atomically', () async {
      final bytes = _nativeBytes(transition: _alternateTransition);
      final session = _session(bytes);
      final plan = _plan('''
selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorBottom
With selected.SlideShowTransition
  $assignment
End With
''');
      final failure = _error(
        'operation_failed',
      ).having((error) => error.stepIndex, 'step', 1);
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
    });
  }

  test(
    'opaque transition rejects native mutation and direct model override',
    () {
      final deck = SlideDeserializer().readBytes(
        _nativeBytes(transition: _alternateTransition),
      );
      final original = deck.slides.first.transition;
      expect(
        () => applySlideStep(deck, <String, Object?>{
          'op': 'slideTransition',
          'slide': 0,
          'durationMs': 700,
        }),
        throwsUnsupportedError,
      );
      expect(deck.slides.first.transition, same(original));
      deck.slides.first.transition = original.copyWith(durationMs: 700);
      expect(() => SlideSerializer().writeBytes(deck), throwsUnsupportedError);
    },
  );

  test(
    'a late missing slide rolls back successful text-frame and transition changes',
    () async {
      final bytes = _nativeBytes();
      final session = _session(bytes);
      final plan = _plan('''
selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorBottom
selected.SlideShowTransition.Duration = 1.25
ActivePresentation.Slides(99).SlideShowTransition.Hidden = True
''');
      final failure = _error(
        'operation_failed',
      ).having((error) => error.stepIndex, 'step', 2);
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
    },
  );

  for (final assignment in <String>[
    'selected.Shapes("Title").TextFrame.VerticalAnchor = msoAnchorBottom',
    'selected.SlideShowTransition.Duration = 1.25',
    'selected.SlideShowTransition.AdvanceOnClick = False',
    'selected.SlideShowTransition.EntryEffect = ppEffectPushLeft',
    'selected.SlideShowTransition.Hidden = True',
  ]) {
    test(
      'new property retains host permission boundary: $assignment',
      () async {
        final bytes = _nativeBytes();
        for (final policy in <OfficeMacroPolicy>[
          OfficeMacroPolicy(allowMutation: false),
          OfficeMacroPolicy(allowedTools: <String>{}),
        ]) {
          final session = _session(bytes, policy: policy);
          await expectLater(
            session.validate(_plan(assignment)),
            throwsA(_error('permission_denied')),
          );
          await expectLater(
            session.run(_plan(assignment)),
            throwsA(_error('permission_denied')),
          );
          expect(session.bytes, bytes);
          expect(session.revision, 0);
        }
      },
    );
  }

  test('new native calls record only successful publications', () async {
    final session = _session(_nativeBytes());
    session.startRecording('Slideshow changes');
    await session.callTool('pptx.shapeTextFrame', <String, Object?>{
      'slide': 0,
      'shapeName': 'Title',
      'topLevel': true,
      'anchor': 'bottom',
    });
    await session.callTool('pptx.slideTransition', <String, Object?>{
      'slide': 0,
      'advanceOnClick': false,
    });
    await expectLater(
      session.callTool('pptx.shapeTextFrame', <String, Object?>{
        'slide': 0,
        'shapeName': 'Missing',
        'topLevel': true,
        'anchor': 'top',
      }),
      throwsA(_error('operation_failed')),
    );
    expect(session.revision, 2);
    final recorded = session.stopRecording();
    expect(recorded.steps.map((step) => step.tool), <String>[
      'pptx.shapeTextFrame',
      'pptx.slideTransition',
    ]);
    final replay = _session(_nativeBytes());
    await replay.run(recorded);
    final reopened = SlideDeserializer().readBytes(replay.bytes);
    expect(reopened.slides.first.shapes.first.textAnchor, PmlTextAnchor.bottom);
    expect(reopened.slides.first.transition.advanceOnClick, isFalse);
    expect(reopened.slides.first.transition.durationMs, 900);
    expect(reopened.slides.first.transition.advanceAfterMs, 2500);
  });
}
