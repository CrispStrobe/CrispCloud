import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'FrameMargins',
    source:
        '''
Sub Main()
Dim frame As TextFrame
Set frame = ActivePresentation.Slides.Item(2).Shapes.Item("Title").TextFrame
$body
End Sub
''',
  ),
);

void main() {
  test('four margins and anchor retain independent ordered writes', () {
    final plan = _compile('''
With frame
  .MarginLeft = 0
  .MarginTop = 12.5
  .MarginRight = 0.1
  .MarginBottom = 1 / 12700
  .VerticalAnchor = msoAnchorMiddle
End With
''');
    expect(plan.steps.map((step) => step.toJson()), [
      for (final fields in <Map<String, Object?>>[
        {'marginLeft': 0},
        {'marginTop': 12.5},
        {'marginRight': 0.1},
        {'marginBottom': 1 / 12700},
        {'anchor': 'center'},
      ])
        {
          'tool': 'pptx.shapeTextFrame',
          'arguments': {
            'topLevel': true,
            'slide': 1,
            'shapeName': 'Title',
            ...fields,
          },
        },
    ]);
    expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
  });

  test('typed TextFrame helper preserves the target and zero margins', () {
    final plan = OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-powerpoint',
        format: OfficeMacroFormat.pptx,
        source: '''
Sub Inset(ByVal target As TextFrame, ByVal points As Double)
target.MarginLeft = points
target.MarginRight = points
End Sub
Sub Main()
Call Inset(Application.ActivePresentation.Slides(1).Shapes(3).TextFrame, 0)
End Sub
''',
      ),
    );
    expect(plan.steps.length, 2);
    expect(plan.steps.first.arguments, {
      'topLevel': true,
      'slide': 0,
      'shape': 2,
      'marginLeft': 0,
    });
    expect(plan.steps.last.arguments['marginRight'], 0);
  });

  for (final property in [
    'MarginLeft',
    'MarginTop',
    'MarginRight',
    'MarginBottom',
  ]) {
    test('$property accepts the exact signed Long EMU ceiling', () {
      final plan = _compile('frame.$property = 2147483647 / 12700');
      expect(plan.steps.single.arguments.values.last, 2147483647 / 12700);
    });
    for (final value in [
      '-0.1',
      '0.00001',
      '2147483648 / 12700',
      'True',
      '"12"',
    ]) {
      test(
        '$property refuses lossy or mistyped $value with source position',
        () {
          expect(
            () => _compile('frame.$property = $value'),
            throwsA(
              isA<OfficeVbaCompileException>()
                  .having((e) => e.code, 'code', 'vba_type_error')
                  .having((e) => e.line, 'line', greaterThan(0))
                  .having((e) => e.column, 'column', greaterThan(0)),
            ),
          );
        },
      );
    }
  }

  test('margin expressions remain write-only', () {
    expect(
      () => _compile('Dim points As Double\npoints = frame.MarginLeft'),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (e) => e.code,
          'code',
          'vba_unsupported',
        ),
      ),
    );
  });
}
