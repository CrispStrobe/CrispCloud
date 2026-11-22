import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _cell = 'ActiveDocument.Tables(2).Cell(3, 4).Range';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellAliasGraph',
    source: source,
  ),
);

OfficeMacro _body(String body) =>
    _source('Option Explicit\nSub Main()\n$body\nEnd Sub');

Matcher _unsupported() => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', 'vba_unsupported')
    .having((error) => error.moduleName, 'module', 'CellAliasGraph')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0));

void _expectWrites(OfficeMacro plan, String tool, int count) {
  expect(plan.steps, hasLength(count));
  for (final step in plan.steps) {
    expect(step.tool, tool);
    expect(step.arguments, {
      'table': 1,
      'row': 2,
      'column': 3,
      'text': 'value',
    });
  }
  expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
}

void main() {
  for (final (label, statement, tool) in [
    ('suffix', 'InsertAfter Text:="value"', 'docx.tableCellRangeInsertAfter'),
    ('Text', 'Text = "value"', 'docx.tableCellRangeText'),
  ]) {
    group('$label direct-cell alias graph', () {
      test('all aliases in an anchored cycle retain the original selector', () {
        _expectWrites(
          _body('''
Dim first As Range, second As Range, third As Range
Set first = $_cell
Set second = first
Set third = second
Set first = third
first.$statement
second.$statement
third.$statement
'''),
          tool,
          3,
        );
      });

      test('self-assignment cannot erase an established cell origin', () {
        _expectWrites(
          _body('''
Dim target As Range
Set target = $_cell
Set target = target
target.$statement
'''),
          tool,
          1,
        );
      });

      test('a cell origin captured inside With survives a later cycle', () {
        _expectWrites(
          _body('''
Dim first As Range, second As Range
With ActiveDocument.Tables(2)
  With .Cell(3, 4)
    Set first = .Range
  End With
End With
Set second = first
Set first = second
With second
  .$statement
End With
'''),
          tool,
          1,
        );
      });

      for (final root in ['first', 'second']) {
        for (final (origin, value) in [
          ('body', 'ActiveDocument.Paragraphs(1).Range'),
          ('projected cell', '$_cell.Paragraphs(1).Range'),
          (
            'header',
            'ActiveDocument.Sections(1).Headers(1).Range.Paragraphs(1).Range',
          ),
          ('unbound alias', 'unbound'),
        ]) {
          test('$root cannot hide an inactive $origin origin in its cycle', () {
            expect(
              () => _body('''
Dim first As Range, second As Range, unbound As Range
Set first = $_cell
Set second = first
Set first = second
If False Then
  Set first = $value
End If
$root.$statement
'''),
              throwsA(_unsupported()),
            );
          });
        }
      }

      for (final cycle in [
        'Set first = first',
        'Set first = second\n  Set second = first',
      ]) {
        test(
          'an inactive rootless cycle cannot borrow a disconnected origin: $cycle',
          () {
            expect(
              () => _body('''
Dim first As Range, second As Range, unrelated As Range
Set unrelated = $_cell
If False Then
  $cycle
  first.$statement
End If
'''),
              throwsA(_unsupported()),
            );
          },
        );
      }

      String helper(String actual) =>
          '''
Option Explicit
Sub Mutate(ByVal target As Range)
  Dim saved As Range
  Set saved = target
  Set target = saved
  saved.$statement
  target.$statement
End Sub
Sub Main()
  Mutate $actual
End Sub
''';

      test('an incoming ByVal cell anchors its local alias cycle', () {
        _expectWrites(_source(helper(_cell)), tool, 2);
      });

      for (final (label, actual) in [
        ('body', 'ActiveDocument.Paragraphs(1).Range'),
        ('projected cell', '$_cell.Paragraphs(1).Range'),
        ('whole header', 'ActiveDocument.Sections(1).Headers(1).Range'),
      ]) {
        test('the generic helper still refuses an actual $label range', () {
          expect(() => _source(helper(actual)), throwsA(_unsupported()));
        });
      }

      test('a generic parameter cannot hide a noncell local binding', () {
        expect(
          () => _source('''
Option Explicit
Sub Mutate(ByVal target As Range)
  Dim saved As Range
  Set saved = target
  Set target = saved
  If False Then
    Set saved = ActiveDocument.Paragraphs(1).Range
  End If
  target.$statement
End Sub
Sub Main()
  Mutate $_cell
End Sub
'''),
          throwsA(_unsupported()),
        );
      });

      test(
        'explicit helper rebinding uses the current direct cell selector',
        () {
          _expectWrites(
            _source('''
Option Explicit
Sub Mutate(ByVal target As Range)
  Set target = $_cell
  target.$statement
End Sub
Sub Main()
  Mutate ActiveDocument.Paragraphs(1).Range
End Sub
'''),
            tool,
            1,
          );
        },
      );

      test(
        'a long anchored cycle terminates without recursive graph expansion',
        () {
          const count = 128;
          final source = StringBuffer();
          for (var index = 0; index < count; index++) {
            source.writeln('Dim target$index As Range');
          }
          source.writeln('Set target0 = $_cell');
          for (var index = 1; index < count; index++) {
            source.writeln('Set target$index = target${index - 1}');
          }
          source
            ..writeln('Set target0 = target${count - 1}')
            ..writeln('target${count ~/ 2}.$statement');
          _expectWrites(_body(source.toString()), tool, 1);
        },
      );
    });
  }
}
