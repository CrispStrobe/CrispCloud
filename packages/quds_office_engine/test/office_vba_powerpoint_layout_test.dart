import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'DeckLayout',
    source: source,
  ),
);

String _module(String body) =>
    '''
Sub Main()
Dim target As Shape, selected As Slide
Set selected = ActivePresentation.Slides(2)
Set target = selected.Shapes("Title")
$body
End Sub
''';

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'DeckLayout')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

Map<String, Object?> _slideStep(
  String operation,
  Map<String, Object?> fields,
) => <String, Object?>{
  'tool': 'pptx.$operation',
  'arguments': <String, Object?>{'slide': 1, ...fields},
};

void main() {
  test(
    'typed frame, font, paragraph and transition aliases pass ByVal helpers',
    () {
      final plan = _compile('''
Sub Main()
Dim selected As Slide, frame As TextFrame, style As Font
Dim paragraph As ParagraphFormat, movement As SlideShowTransition
Set selected = Application.ActivePresentation.Slides(2)
Set frame = selected.Shapes("Title").TextFrame
Set style = frame.TextRange.Font
Set paragraph = frame.TextRange.ParagraphFormat
Set movement = selected.SlideShowTransition
Call Layout(frame, style, paragraph, movement)
End Sub
Sub Layout(ByVal frame As TextFrame, ByVal style As Font, ByVal paragraph As ParagraphFormat, ByVal movement As SlideShowTransition)
With frame
  .VerticalAnchor = msoAnchorMiddle
End With
style.Bold = msoTrue
paragraph.Alignment = ppAlignCenter
With movement
  .Hidden = msoFalse
  .AdvanceOnClick = False
  .Duration = 1.25
  .EntryEffect = ppEffectPushLeft
End With
End Sub
''');
      expect(plan.steps.map((step) => step.toJson()), <Object?>[
        for (final entry in <(String, Map<String, Object?>)>[
          ('shapeTextFrame', {'anchor': 'center'}),
          ('shapeFormat', {'bold': true}),
          ('shapeFormat', {'alignment': 'center'}),
        ])
          {
            'tool': 'pptx.${entry.$1}',
            'arguments': {
              'topLevel': true,
              'slide': 1,
              'shapeName': 'Title',
              ...entry.$2,
            },
          },
        _slideStep('slideHidden', {'hidden': false}),
        _slideStep('slideTransition', {'advanceOnClick': false}),
        _slideStep('slideTransition', {'durationMs': 1250}),
        _slideStep('slideTransition', {'kind': 'push', 'direction': 'left'}),
      ]);
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    },
  );

  for (final anchor in <String, String>{
    'msoAnchorTop': 'top',
    'msoAnchorMiddle': 'center',
    'msoAnchorBottom': 'bottom',
    '1': 'top',
    '3': 'center',
    '4': 'bottom',
  }.entries) {
    test('VerticalAnchor ${anchor.key} has exact native mapping', () {
      final plan = _compile(
        _module('target.TextFrame.VerticalAnchor = ${anchor.key}'),
      );
      expect(plan.steps.single.tool, 'pptx.shapeTextFrame');
      expect(plan.steps.single.arguments, {
        'topLevel': true,
        'slide': 1,
        'shapeName': 'Title',
        'anchor': anchor.value,
      });
    });
  }

  for (final entry in <String, (String, String?)>{
    'ppEffectNone': ('none', null),
    'ppEffectCut': ('cut', null),
    'ppEffectFadeSmoothly': ('fade', null),
    'ppEffectPushDown': ('push', 'down'),
    'ppEffectPushLeft': ('push', 'left'),
    'ppEffectPushRight': ('push', 'right'),
    'ppEffectPushUp': ('push', 'up'),
    'ppEffectWipeLeft': ('wipe', 'left'),
    'ppEffectWipeUp': ('wipe', 'up'),
    'ppEffectWipeRight': ('wipe', 'right'),
    'ppEffectWipeDown': ('wipe', 'down'),
  }.entries) {
    test('EntryEffect ${entry.key} specifies only effect fields', () {
      final plan = _compile(
        _module('selected.SlideShowTransition.EntryEffect = ${entry.key}'),
      );
      expect(
        plan.steps.single.toJson(),
        _slideStep('slideTransition', {
          'kind': entry.value.$1,
          if (entry.value.$2 != null) 'direction': entry.value.$2,
        }),
      );
    });
  }

  for (final value in <String, int>{
    '0.001': 1,
    '0.333': 333,
    '1.25': 1250,
    '2147483.647': 2147483647,
  }.entries) {
    test('Duration ${value.key} seconds becomes exact milliseconds', () {
      final plan = _compile(
        _module('selected.SlideShowTransition.Duration = ${value.key}'),
      );
      expect(
        plan.steps.single.toJson(),
        _slideStep('slideTransition', {'durationMs': value.value}),
      );
    });
  }

  for (final source in <String>[
    'target.TextFrame.VerticalAnchor = msoAnchorTopBaseline',
    'target.TextFrame.VerticalAnchor = msoAnchorBottomBaseLine',
    'target.TextFrame.VerticalAnchor = msoVerticalAnchorMixed',
    'target.TextFrame.VerticalAnchor = 0',
    'selected.SlideShowTransition.EntryEffect = 1793',
    'selected.SlideShowTransition.EntryEffect = -2',
  ]) {
    test('unsupported anchor/effect is positioned: $source', () {
      expect(
        () => _compile(_module(source)),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final source in <String>[
    'target.TextFrame.VerticalAnchor = True',
    'target.TextFrame.VerticalAnchor = "3"',
    'target.TextFrame.VerticalAnchor = 1.5',
    'selected.SlideShowTransition.Hidden = msoCTrue',
    'selected.SlideShowTransition.AdvanceOnClick = msoTriStateToggle',
    'selected.SlideShowTransition.Duration = 0',
    'selected.SlideShowTransition.Duration = -1',
    'selected.SlideShowTransition.Duration = 0.0001',
    'selected.SlideShowTransition.Duration = 2147483.648',
    'selected.SlideShowTransition.Duration = "1"',
    'selected.SlideShowTransition.EntryEffect = False',
  ]) {
    test('invalid typed property is refused: $source', () {
      expect(
        () => _compile(_module(source)),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  test('unused helper still rejects unsupported live reads', () {
    expect(
      () => _compile('''
Sub Main()
End Sub
Sub Unused(ByVal movement As SlideShowTransition)
Dim duration As Double
duration = movement.Duration
End Sub
'''),
      throwsA(_error('vba_unsupported')),
    );
  });

  test('bound frame cannot satisfy a font helper parameter', () {
    expect(
      () => _compile('''
Sub Main()
Dim frame As TextFrame
Set frame = ActivePresentation.Slides(1).Shapes(1).TextFrame
Call Style(frame)
End Sub
Sub Style(ByVal value As Font)
value.Bold = True
End Sub
'''),
      throwsA(_error('vba_type_error')),
    );
  });
}
