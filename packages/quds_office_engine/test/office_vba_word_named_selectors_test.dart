import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'NamedSelectors',
    source: source,
  ),
);

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final matcher = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'NamedSelectors')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? matcher
      : matcher.having((error) => error.code, 'code', code);
}

void main() {
  group('named document and story selectors', () {
    for (final root in [
      'ActiveDocument',
      'ThisDocument',
      'Application.ActiveDocument',
    ]) {
      for (final item in ['', '.Item']) {
        test('$root Paragraphs$item retains the one-based target', () {
          final plan = _body(
            '$root.Paragraphs$item(iNdEx:=3).Range.InsertBefore "Body: "',
          );
          expect(plan.steps.single.toJson(), {
            'tool': 'docx.replaceText',
            'arguments': {
              'paragraph': 2,
              'start': 0,
              'end': 0,
              'text': 'Body: ',
            },
          });
          expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
        });
      }
    }

    for (final item in ['', '.Item']) {
      test('Sections$item keeps page geometry attached to its section', () {
        final plan = _body(
          'ThisDocument.Sections$item(Index:=2).PageSetup.TopMargin = 36',
        );
        expect(plan.steps.single.toJson(), {
          'tool': 'docx.pageSetup',
          'arguments': {'section': 1, 'property': 'top', 'points': 36},
        });
      });
    }

    for (final (collection, index, story) in <(String, String, String)>[
      ('Headers', 'wdHeaderFooterPrimary', 'header'),
      ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
      ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
      ('Footers', 'wdHeaderFooterPrimary', 'footer'),
      ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
      ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
    ]) {
      for (final item in ['', '.Item']) {
        test('$collection$item selects only the named $story paragraph', () {
          final plan = _body(
            'ThisDocument.Sections$item(Index:=2).$collection$item'
            '(Index:=$index).Range.Paragraphs$item(Index:=3).Range.Font.Bold = True',
          );
          expect(plan.steps.single.toJson(), {
            'tool': 'docx.runFormat',
            'arguments': {
              'paragraph': 2,
              'story': story,
              'section': 1,
              'bold': true,
            },
          });
        });
      }
    }

    test('collection aliases and nested With retain the original story', () {
      final plan = _body('''
Dim sections As Sections, selected As Section
Dim stories As HeadersFooters, story As HeaderFooter, selectedParagraphs As Paragraphs
Dim retained As Range
Set sections = ThisDocument.Sections
Set selected = sections.Item(Index:=2)
Set stories = selected.Headers
Set story = stories.Item(Index:=wdHeaderFooterFirstPage)
Set selectedParagraphs = story.Range.Paragraphs
Set retained = selectedParagraphs.Item(Index:=3).Range
Set selected = sections.Item(Index:=1)
Set stories = selected.Footers
With stories
  With .Item(Index:=wdHeaderFooterEvenPages).Range.Paragraphs
    .Item(Index:=1).Range.Font.Italic = True
  End With
End With
retained.InsertBefore Text:="Retained: "
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'story': 'evenFooter', 'section': 0, 'italic': true},
        {
          'paragraph': 2,
          'story': 'firstHeader',
          'section': 1,
          'start': 0,
          'end': 0,
          'text': 'Retained: ',
        },
      ]);
    });

    test(
      'typed ByVal collections preserve caller identity after rebinding',
      () {
        final plan = _source('''
Sub Main()
  Dim selectedParagraphs As Paragraphs
  Set selectedParagraphs = ThisDocument.Sections(Index:=2).Footers(Index:=1).Range.Paragraphs
  Paint target:=selectedParagraphs
  selectedParagraphs.Item(Index:=2).Range.Font.Italic = True
End Sub
Sub Paint(ByVal target As Paragraphs)
  target.Item(Index:=3).Range.Font.Bold = True
  Set target = ThisDocument.Paragraphs
  target.Item(Index:=1).Range.Font.Bold = False
End Sub
''');
        expect(plan.steps.map((step) => step.arguments), [
          {'paragraph': 2, 'story': 'footer', 'section': 1, 'bold': true},
          {'paragraph': 0, 'bold': false},
          {'paragraph': 1, 'story': 'footer', 'section': 1, 'italic': true},
        ]);
      },
    );

    test(
      'each receiver and Index helper is evaluated once in source order',
      () {
        final plan = _source('''
Sub Main()
  ThisDocument.Sections(Index:=Pick("section", 2)).Headers(Index:=Pick("header", 2)).Range.Paragraphs(Index:=Pick("paragraph", 3)).Range.InsertBefore Text:=SuffixText()
End Sub
Function Pick(ByVal label As String, ByVal value As Long) As Long
  ThisDocument.Paragraphs(Index:=9).Range.InsertBefore Text:=label
  Pick = value
End Function
Function SuffixText() As String
  ThisDocument.Paragraphs(Index:=9).Range.InsertBefore Text:="text"
  SuffixText = "Final: "
End Function
''');
        expect(plan.steps.map((step) => step.arguments), [
          for (final label in ['section', 'header', 'paragraph', 'text'])
            {'paragraph': 8, 'start': 0, 'end': 0, 'text': label},
          {
            'paragraph': 2,
            'story': 'firstHeader',
            'section': 1,
            'start': 0,
            'end': 0,
            'text': 'Final: ',
          },
        ]);
      },
    );
  });

  group('projected paragraph identity', () {
    for (final item in ['', '.Item']) {
      test(
        'named body paragraph projection$item retains the outer paragraph',
        () {
          final plan = _body(
            'ThisDocument.Paragraphs(Index:=3).Range.Paragraphs$item(Index:=1)'
            '.Range.Font.Bold = True',
          );
          expect(plan.steps.single.arguments, {'paragraph': 2, 'bold': true});
        },
      );

      test(
        'named cell paragraph projection$item keeps all cell coordinates',
        () {
          final plan = _body(
            'ThisDocument.Tables(Index:=2).Cell(Column:=3, Row:=4).Range'
            '.Paragraphs$item(Index:=1).Range.Font.Bold = True',
          );
          expect(plan.steps.single.arguments, {
            'paragraph': 0,
            'story': 'tableCell',
            'table': 1,
            'row': 3,
            'column': 2,
            'bold': true,
          });
        },
      );
    }

    for (final root in [
      'ThisDocument.Paragraphs(Index:=3).Range',
      'ThisDocument.Tables(Index:=1).Cell(Row:=1, Column:=1).Range',
      'ThisDocument.Sections(Index:=2).Headers(Index:=1).Range'
          '.Paragraphs(Index:=3).Range',
    ]) {
      test('projected paragraphs still refuse a second member: $root', () {
        expect(
          () => _body('$root.Paragraphs(Index:=2).Range.Font.Bold = True'),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
  });

  group('selector boundaries', () {
    for (final (type, binding, member) in [
      (
        'Sections',
        'ThisDocument.Sections',
        '.Item(Index:=1).PageSetup.TopMargin = 36',
      ),
      (
        'Paragraphs',
        'ThisDocument.Paragraphs',
        '.Item(Index:=1).Range.Font.Bold = True',
      ),
    ]) {
      test('$type requires Set and preserves strict object types', () {
        for (final statement in [
          'Dim target As $type\ntarget = $binding',
          'Dim target As $type\nSet target = ThisDocument',
          'Dim target As $type\ntarget$member',
          'Dim target(1 To 2) As $type',
          'Dim target As Variant\nSet target = $binding',
        ]) {
          expect(() => _body(statement), throwsA(_error()));
        }
      });

      test('$type retains required ByVal helper boundaries', () {
        for (final parameter in [
          'ByRef target As $type',
          'Optional ByVal target As $type',
          'ByVal target() As $type',
        ]) {
          expect(
            () =>
                _source('Sub Main()\nEnd Sub\nSub Unused($parameter)\nEnd Sub'),
            throwsA(_error()),
          );
        }
        expect(
          () => _source(
            'Sub Main()\nEnd Sub\nFunction Unused() As $type\nEnd Function',
          ),
          throwsA(_error()),
        );
      });

      test('$type rejects scalar Variant bindings in all inactive source', () {
        for (final body in [
          'Dim target As $type, value As Variant\nSet target = value',
          'Dim value As Variant\nUseTarget target:=value',
        ]) {
          expect(
            () => _source('''
Sub Main()
End Sub
Sub Unused()
  $body
End Sub
Sub UseTarget(ByVal target As $type)
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        }
      });

      test('$type does not enable document collection enumeration', () {
        expect(
          () => _body('''
Dim target As $type, item As Variant
Set target = $binding
For Each item In target
Next item
'''),
          throwsA(_error()),
        );
      });

      test('$type is restricted to the Word adapter', () {
        for (final (language, format) in [
          ('vba-excel', OfficeMacroFormat.xlsx),
          ('vba-powerpoint', OfficeMacroFormat.pptx),
        ]) {
          expect(
            () => OfficeMacroLanguages().compile(
              OfficeMacroSource(
                language: language,
                format: format,
                source: 'Sub Main()\nDim target As $type\nEnd Sub',
              ),
            ),
            throwsA(isA<OfficeVbaCompileException>()),
          );
        }
      });
    }

    test(
      'cell Paragraphs aliases retain inactive-source list restrictions',
      () {
        for (final listTarget in [
          'selected.Item(Index:=1)',
          'retained.Item(Index:=1)',
        ]) {
          expect(
            () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim selected As Paragraphs, retained As Paragraphs
  Set selected = ThisDocument.Tables(1).Cell(1, 1).Range.Paragraphs
  Set retained = selected
  $listTarget.Range.ListFormat.ApplyBulletDefault
End Sub
'''),
            throwsA(_error('vba_unsupported')),
          );
        }
      },
    );

    test('cell-only alias cycles retain inactive-source list restrictions', () {
      for (final declaration in ['Range', 'Paragraph', 'Paragraphs']) {
        final initial = switch (declaration) {
          'Range' =>
            'ThisDocument.Tables(1).Cell(1, 1).Range.Paragraphs(1).Range',
          'Paragraph' =>
            'ThisDocument.Tables(1).Cell(1, 1).Range.Paragraphs(1)',
          _ => 'ThisDocument.Tables(1).Cell(1, 1).Range.Paragraphs',
        };
        final target = switch (declaration) {
          'Range' => 'retained',
          'Paragraph' => 'retained.Range',
          _ => 'retained.Item(Index:=1).Range',
        };
        for (final invoked in [false, true]) {
          expect(
            () => _source('''
Sub Main()
  ${invoked ? 'Apply' : ''}
End Sub
Sub Apply()
  Dim selected As $declaration, retained As $declaration
  Set selected = $initial
  Set retained = selected
  Set selected = retained
  $target.ListFormat.ApplyBulletDefault
End Sub
'''),
            throwsA(_error('vba_unsupported')),
            reason: '$declaration invoked=$invoked',
          );
        }
      }
    });

    final selectors = <(String, String)>[
      ('ThisDocument.Paragraphs', '.Range.Font.Bold = True'),
      ('ThisDocument.Paragraphs.Item', '.Range.Font.Bold = True'),
      ('ThisDocument.Sections', '.PageSetup.TopMargin = 36'),
      ('ThisDocument.Sections.Item', '.PageSetup.TopMargin = 36'),
      (
        'ThisDocument.Sections(1).Headers',
        '.Range.Paragraphs(1).Range.Font.Bold = True',
      ),
      (
        'ThisDocument.Sections(1).Footers.Item',
        '.Range.Paragraphs(1).Range.Font.Bold = True',
      ),
    ];
    for (final (selector, write) in selectors) {
      for (final arguments in [
        '',
        'Index:=1, Index:=2',
        '1, Index:=1',
        'Index:=1, 2',
        'Index:=',
        ',',
        'Index:=True',
        'Index:="1"',
        'Index:=Null',
        'Index:=Empty',
        'Index:=0',
        'Index:=-1',
        'Index:=1.5',
      ]) {
        test('$selector rejects malformed or invalid ($arguments)', () {
          expect(() => _body('$selector($arguments)$write'), throwsA(_error()));
        });
      }
      test('$selector rejects an unknown name even in an unused procedure', () {
        expect(
          () => _source('''
Sub Main()
End Sub
Sub Unused()
  $selector(Position:=1)$write
End Sub
'''),
          throwsA(_error('vba_name_error')),
        );
      });
    }

    for (final collection in ['Headers', 'Footers']) {
      test('$collection retains its WdHeaderFooterIndex range', () {
        expect(
          () => _body(
            'ThisDocument.Sections(Index:=1).$collection(Index:=4)'
            '.Range.Paragraphs(Index:=1).Range.Font.Bold = True',
          ),
          throwsA(_error()),
        );
      });
    }

    for (final statement in [
      'Dim count As Long\ncount = ThisDocument.Paragraphs.Count',
      'Dim text As String\ntext = ThisDocument.Paragraphs(Index:=1).Range.Text',
      'ThisDocument.Sections(Index:=1).Headers(Index:=1).Range.InsertBefore "story"',
      'ThisDocument.Tables(Index:=1).Cell(1, 1).Range.Paragraphs(Index:=1)'
          '.Range.InsertAfter "suffix"',
      'Dim selected As Paragraph\nSet selected = ThisDocument.Paragraphs.First',
    ]) {
      test(
        'named selectors do not admit unsupported object operations: $statement',
        () {
          expect(() => _body(statement), throwsA(_error()));
        },
      );
    }
  });
}
