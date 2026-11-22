import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordHeadersFooters',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordHeadersFooters')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _header =
    'ActiveDocument.Sections(2).Headers(wdHeaderFooterPrimary).Range';
const _footer =
    'ActiveDocument.Sections(2).Footers(wdHeaderFooterEvenPages).Range';

void main() {
  // Microsoft WdHeaderFooterIndex specifies Primary=1, FirstPage=2,
  // EvenPages=3. Native story names and expected indices here are independent
  // expectations; no compiler dispatch data is imported by these tests.
  for (final (collection, index, story) in <(String, String, String)>[
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    for (final item in <String>['', '.Item']) {
      test('$collection$item($index) emits the explicit $story target', () {
        final plan = _compile('''
Application.ActiveDocument.Sections.Item(3).$collection$item($index).Range.Paragraphs.Item(2).Range.InsertBefore "Prepared: "
''');
        expect(plan.steps.single.tool, 'docx.replaceText');
        expect(plan.steps.single.arguments, {
          'paragraph': 1,
          'story': story,
          'section': 2,
          'start': 0,
          'end': 0,
          'text': 'Prepared: ',
        });
      });
    }
  }

  test(
    'numeric indices and case-insensitive members preserve exact targets',
    () {
      final plan = _compile('''
with aPpLiCaTiOn.AcTiVeDoCuMeNt.SeCtIoNs(2).hEaDeRs.ItEm(2).rAnGe
  .pArAgRaPhS(1).rAnGe.fOnT.bOlD = True
end with
ThisDocument.Sections(3).Footers(3).Range.Paragraphs(4).Format.Alignment = wdAlignParagraphRight
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'story': 'firstHeader', 'section': 1, 'bold': true},
        {
          'paragraph': 3,
          'story': 'evenFooter',
          'section': 2,
          'alignment': 'right',
        },
      ]);
    },
  );

  test(
    'typed aliases retain story and section when earlier bindings change',
    () {
      final plan = _compile('''
Dim selected As Section
Dim collection As HeadersFooters
Dim story As HeaderFooter
Dim whole As Range
Dim target As Paragraph
Dim text As Range
Set selected = ThisDocument.Sections(2)
Set collection = selected.Headers
Set story = collection.Item(wdHeaderFooterFirstPage)
Set whole = story.Range
Set target = whole.Paragraphs(2)
Set text = target.Range
Set selected = ThisDocument.Sections(3)
Set collection = selected.Footers
Set story = collection.Item(wdHeaderFooterEvenPages)
Set whole = story.Range
Set target = whole.Paragraphs(1)
text.InsertBefore "Original: "
target.Range.Font.Italic = True
''');
      expect(plan.steps.map((step) => step.arguments), [
        {
          'paragraph': 1,
          'story': 'firstHeader',
          'section': 1,
          'start': 0,
          'end': 0,
          'text': 'Original: ',
        },
        {'paragraph': 0, 'story': 'evenFooter', 'section': 2, 'italic': true},
      ]);
    },
  );

  test(
    'nested With handles collections, HeaderFooter, story and paragraph',
    () {
      final plan = _compile('''
With ThisDocument.Sections(2)
  With .Headers
    With .Item(wdHeaderFooterPrimary)
      With .Range
        With .Paragraphs
          With .Item(2)
            .Range.InsertBefore "Header: "
            With .Format
              .Alignment = wdAlignParagraphCenter
              .SpaceAfter = 6
            End With
          End With
        End With
      End With
    End With
  End With
End With
''');
      expect(plan.steps.map((step) => step.arguments), [
        {
          'paragraph': 1,
          'story': 'header',
          'section': 1,
          'start': 0,
          'end': 0,
          'text': 'Header: ',
        },
        {
          'paragraph': 1,
          'story': 'header',
          'section': 1,
          'alignment': 'center',
        },
        {'paragraph': 1, 'story': 'header', 'section': 1, 'after': 6},
      ]);
    },
  );

  test('named ByVal helpers retain caller aliases on local rebinding', () {
    final plan = _source('''
Sub Main()
  Dim collection As HeadersFooters
  Dim story As HeaderFooter
  Dim whole As Range
  Set collection = ThisDocument.Sections(2).Headers
  Set story = collection.Item(wdHeaderFooterPrimary)
  Set whole = story.Range
  CollectionHelper target:=collection
  StoryHelper target:=story
  RangeHelper target:=whole
  collection.Item(2).Range.Paragraphs(1).Range.Font.Bold = True
  story.Range.Paragraphs(1).Range.Font.Italic = True
  whole.Paragraphs(1).Range.Font.StrikeThrough = True
End Sub
Sub CollectionHelper(ByVal target As HeadersFooters)
  target.Item(1).Range.Paragraphs(1).Range.InsertBefore "C"
  Set target = ThisDocument.Sections(3).Footers
  target.Item(3).Range.Paragraphs(1).Range.InsertBefore "D"
End Sub
Sub StoryHelper(ByVal target As HeaderFooter)
  target.Range.Paragraphs(1).Range.InsertBefore "H"
  Set target = ThisDocument.Sections(4).Footers(2)
  target.Range.Paragraphs(1).Range.InsertBefore "F"
End Sub
Sub RangeHelper(ByVal target As Range)
  target.Paragraphs(1).Range.InsertBefore "R"
  Set target = ThisDocument.Paragraphs(3).Range
  target.Paragraphs(1).Range.InsertBefore "B"
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {
        'paragraph': 0,
        'story': 'header',
        'section': 1,
        'start': 0,
        'end': 0,
        'text': 'C',
      },
      {
        'paragraph': 0,
        'story': 'evenFooter',
        'section': 2,
        'start': 0,
        'end': 0,
        'text': 'D',
      },
      {
        'paragraph': 0,
        'story': 'header',
        'section': 1,
        'start': 0,
        'end': 0,
        'text': 'H',
      },
      {
        'paragraph': 0,
        'story': 'firstFooter',
        'section': 3,
        'start': 0,
        'end': 0,
        'text': 'F',
      },
      {
        'paragraph': 0,
        'story': 'header',
        'section': 1,
        'start': 0,
        'end': 0,
        'text': 'R',
      },
      {'paragraph': 2, 'start': 0, 'end': 0, 'text': 'B'},
      {'paragraph': 0, 'story': 'firstHeader', 'section': 1, 'bold': true},
      {'paragraph': 0, 'story': 'header', 'section': 1, 'italic': true},
      {'paragraph': 0, 'story': 'header', 'section': 1, 'strike': true},
    ]);
  });

  test(
    'direct whole-story Range is accepted by a required ByVal Range helper',
    () {
      final plan = _source('''
Sub Main()
  Mark target:=$_footer
End Sub
Sub Mark(ByVal target As Range)
  target.Paragraphs.Item(2).Range.HighlightColorIndex = wdYellow
End Sub
''');
      expect(plan.steps.single.arguments, {
        'paragraph': 1,
        'story': 'evenFooter',
        'section': 1,
        'highlight': 'FFFF00',
      });
    },
  );

  test('HeaderFooter and HeadersFooters type names can be local names', () {
    final plan = _compile('''
Dim headerFooter As HeaderFooter
Dim headersFooters As HeadersFooters
Set headersFooters = ThisDocument.Sections(1).Headers
Set headerFooter = headersFooters.Item(wdHeaderFooterPrimary)
headerFooter.Range.Paragraphs(1).Range.Font.Bold = True
''');
    expect(plan.steps.single.arguments, {
      'paragraph': 0,
      'story': 'header',
      'section': 0,
      'bold': true,
    });
  });

  test('whole-story Range and paragraph Range share typed helpers safely', () {
    final plan = _source('''
Sub Main()
  Apply target:=ThisDocument.Paragraphs(3).Range
  Apply target:=$_header
End Sub
Sub Apply(ByVal target As Range)
  target.Paragraphs(1).Range.Font.Bold = True
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 2, 'bold': true},
      {'paragraph': 0, 'story': 'header', 'section': 1, 'bold': true},
    ]);
  });

  test(
    'Paragraphs.Item(1) on a paragraph Range retains that exact paragraph',
    () {
      final plan = _compile('''
$_footer.Paragraphs(3).Range.Paragraphs.Item(1).Range.Paragraphs(1).Range.InsertBefore "Same"
''');
      expect(plan.steps.single.arguments, {
        'paragraph': 2,
        'story': 'evenFooter',
        'section': 1,
        'start': 0,
        'end': 0,
        'text': 'Same',
      });
    },
  );

  test(
    'paragraph Range does not reinterpret larger indices as story indices',
    () {
      expect(
        () => _compile(
          '$_header.Paragraphs(3).Range.Paragraphs(2).Range.Font.Bold = True',
        ),
        throwsA(_error('vba_unsupported')),
      );
      expect(
        () => _compile(
          'ThisDocument.Paragraphs(3).Range.Paragraphs.Item(2).Range.Font.Bold = True',
        ),
        throwsA(_error('vba_unsupported')),
      );
    },
  );

  test('existing body plans retain their exact argument shape', () {
    final plan = _compile('''
ThisDocument.Paragraphs(2).Range.InsertBefore "Body"
ThisDocument.Paragraphs(2).Range.Font.Bold = False
ThisDocument.Paragraphs(2).Format.SpaceBefore = 6
ThisDocument.Paragraphs(2).Range.ListFormat.ListIndent
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'start': 0, 'end': 0, 'text': 'Body'},
      {'paragraph': 1, 'bold': false},
      {'paragraph': 1, 'before': 6},
      {'paragraph': 1, 'delta': 1},
    ]);
  });

  test('all supported paragraph writes retain the selected story', () {
    final plan = _compile('''
Dim target As Paragraph
Dim text As Range
Set target = $_footer.Paragraphs(2)
Set text = target.Range
text.InsertBefore "Prepared"
text.Font.Name = "Arial"
text.Font.Size = 11
text.Font.Bold = False
text.Font.Italic = True
text.Font.StrikeThrough = True
text.Font.SmallCaps = True
text.Font.Superscript = False
text.Font.Subscript = True
text.Font.Underline = wdUnderlineDouble
text.Font.Color = RGB(31, 78, 121)
text.HighlightColorIndex = wdNoHighlight
With target.Format
  .Alignment = wdAlignParagraphLeft
  .SpaceBefore = 6
  .SpaceAfter = 3
  .LeftIndent = 12
  .RightIndent = 18
  .FirstLineIndent = -6
  .KeepTogether = False
  .PageBreakBefore = True
  .ReadingOrder = wdReadingOrderRtl
  .LineSpacingRule = wdLineSpaceDouble
  .Space1
  .Space15
  .Space2
  .OpenUp
  .CloseUp
  .OpenOrCloseUp
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = 14
  .TabStops.Add Position:=36, Alignment:=wdAlignTabRight, Leader:=wdTabLeaderDots
  .TabStops.ClearAll
End With
''');
    expect(plan.steps, hasLength(31));
    for (final step in plan.steps) {
      expect(step.arguments['paragraph'], 1);
      expect(step.arguments['story'], 'evenFooter');
      expect(step.arguments['section'], 1);
    }
    expect(plan.steps.map((step) => step.tool).toSet(), {
      'docx.replaceText',
      'docx.runFormat',
      'docx.paragraphFormat',
      'docx.paragraphSpaceBefore',
      'docx.lineSpacing',
      'docx.tabStop',
      'docx.clearTabStops',
    });
    expect(plan.steps[17].arguments, {
      'paragraph': 1,
      'story': 'evenFooter',
      'section': 1,
      'hanging': 6,
      'firstLine': 0,
    });
  });

  test(
    'line-spacing rule and amount can use independently bound equal selectors',
    () {
      final plan = _compile('''
$_header.Paragraphs(2).Format.LineSpacingRule = wdLineSpaceAtLeast
Application.ActiveDocument.Sections.Item(2).Headers.Item(1).Range.Paragraphs.Item(2).Format.LineSpacing = 12
''');
      expect(plan.steps.single.tool, 'docx.lineSpacing');
      expect(plan.steps.single.arguments, {
        'paragraph': 1,
        'story': 'header',
        'section': 1,
        'rule': 'atLeast',
        'points': 12,
      });
    },
  );

  for (final other in <String>[
    'ThisDocument.Paragraphs(1)',
    'ThisDocument.Sections(2).Footers(1).Range.Paragraphs(1)',
    'ThisDocument.Sections(2).Headers(2).Range.Paragraphs(1)',
    'ThisDocument.Sections(3).Headers(1).Range.Paragraphs(1)',
    'ThisDocument.Sections(2).Headers(1).Range.Paragraphs(2)',
  ]) {
    test('line spacing refuses mismatched story/section/paragraph $other', () {
      expect(
        () => _compile('''
$_header.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$other.Format.LineSpacing = 12
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final operation in <String>[
    '.ApplyBulletDefault',
    '.ApplyNumberDefault',
    '.ApplyOutlineNumberDefault',
    '.RemoveNumbers',
    '.ListIndent',
    '.ListOutdent',
    '.ListLevelNumber = 2',
  ]) {
    test(
      'header/footer ListFormat refuses $operation before body lowering',
      () {
        expect(
          () => _compile('$_footer.Paragraphs(1).Range.ListFormat$operation'),
          throwsA(_error('vba_unsupported')),
        );
      },
    );
  }

  test('ListFormat alias cannot be bound to a header/footer paragraph', () {
    expect(
      () => _compile('''
Dim list As ListFormat
Set list = $_header.Paragraphs(1).Range.ListFormat
'''),
      throwsA(_error('vba_unsupported')),
    );
  });

  test('selector helper evaluation order and count are retained', () {
    final plan = _source('''
Sub Main()
  ThisDocument.Sections(SectionIndex()).Headers(StoryIndex()).Range.Paragraphs(ParagraphIndex()).Range.InsertBefore "target"
End Sub
Function SectionIndex() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "section"
  SectionIndex = 3
End Function
Function StoryIndex() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "story"
  StoryIndex = wdHeaderFooterEvenPages
End Function
Function ParagraphIndex() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "paragraph"
  ParagraphIndex = 2
End Function
''');
    expect(plan.steps.map((step) => step.arguments['text']), [
      'section',
      'story',
      'paragraph',
      'target',
    ]);
    expect(plan.steps.last.arguments, {
      'paragraph': 1,
      'story': 'evenHeader',
      'section': 2,
      'start': 0,
      'end': 0,
      'text': 'target',
    });
  });

  test('With captures the complete header/footer selector once', () {
    final plan = _source('''
Sub Main()
  With ThisDocument.Sections(2).Footers(StoryIndex()).Range.Paragraphs(1).Range
    .Font.Bold = True
    .Font.Italic = True
  End With
End Sub
Function StoryIndex() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "select"
  StoryIndex = wdHeaderFooterFirstPage
End Function
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'start': 0, 'end': 0, 'text': 'select'},
      {'paragraph': 0, 'story': 'firstFooter', 'section': 1, 'bold': true},
      {'paragraph': 0, 'story': 'firstFooter', 'section': 1, 'italic': true},
    ]);
  });

  for (final index in <String>[
    '0',
    '-1',
    '4',
    '9007199254740991',
    '1.5',
    'True',
    '"1"',
    'Null',
  ]) {
    test('invalid header/footer selector $index has a source diagnostic', () {
      expect(
        () => _compile(
          'ThisDocument.Sections(1).Headers($index).Range.Paragraphs(1).Range.Font.Bold = True',
        ),
        throwsA(_error()),
      );
    });
  }
  for (final index in <String>['0', '-1', '1.5', 'True', '"1"', 'Null']) {
    test('invalid story paragraph selector $index has a source diagnostic', () {
      expect(
        () => _compile('$_header.Paragraphs($index).Range.Font.Bold = True'),
        throwsA(_error()),
      );
    });
  }

  for (final source in <String>[
    '$_header.Font.Bold = True',
    '$_header.ParagraphFormat.Alignment = wdAlignParagraphLeft',
    '$_header.HighlightColorIndex = wdYellow',
    '$_header.InsertBefore "whole story"',
    '$_header.Text = "whole story"',
    '$_header.Paragraphs.Count',
    'ThisDocument.Sections(1).Headers(1).Exists = True',
    'ThisDocument.Sections(1).Headers(1).LinkToPrevious = False',
    'ThisDocument.Sections(1).Headers(1).PageNumbers.Add',
    'ThisDocument.Sections(1).Headers(1).Range.Characters(1).Text = "x"',
    'ThisDocument.Headers(1).Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Paragraphs(1).Headers(1).Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers.Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers(1).Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers(Kind:=1).Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers.Item(Kind:=1).Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers().Range.Paragraphs(1).Range.Font.Bold = True',
    'ThisDocument.Sections(1).Headers(1, 2).Range.Paragraphs(1).Range.Font.Bold = True',
  ]) {
    test('unsupported member or shape is rejected: $source', () {
      expect(() => _compile(source), throwsA(_error()));
    });
  }

  for (final statement in <String>[
    'whole.InsertBefore "x"',
    'whole.Font.Bold = True',
    'whole.ParagraphFormat.SpaceBefore = 6',
    'whole.HighlightColorIndex = wdYellow',
    'With whole\n .Font.Bold = True\nEnd With',
  ]) {
    test('whole-story Range aliases refuse writes: $statement', () {
      expect(
        () => _compile('''
Dim whole As Range
Set whole = $_header
$statement
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final source in <String>[
    'Dim target As HeaderFooter\nSet target = ThisDocument.Sections(1).Headers',
    'Dim target As HeadersFooters\nSet target = ThisDocument.Sections(1).Headers(1)',
    'Dim target As Range\nSet target = ThisDocument.Sections(1).Headers(1)',
    'Dim target As HeaderFooter\nSet target = $_header',
    'Dim target As Variant\nSet target = ThisDocument.Sections(1).Headers(1)',
    'Dim target As HeaderFooter\ntarget = ThisDocument.Sections(1).Headers(1)',
    'Dim target As HeadersFooters\ntarget.Item(1).Range.Paragraphs(1).Range.Font.Bold = True',
    'Dim target As HeaderFooter\ntarget.Range.Paragraphs(1).Range.Font.Bold = True',
  ]) {
    test('object kinds and unbound objects remain checked: $source', () {
      expect(() => _compile(source), throwsA(_error()));
    });
  }

  test('unsupported members in unused helpers are still rejected', () {
    expect(
      () => _source('''
Sub Main()
End Sub
Sub Unused(ByVal story As HeaderFooter)
  story.LinkToPrevious = False
End Sub
'''),
      throwsA(_error('vba_unsupported')),
    );
  });

  for (final declaration in <String>[
    'Optional ByVal story As HeaderFooter',
    'ByRef story As HeaderFooter',
    'Optional ByVal collection As HeadersFooters',
  ]) {
    test('unsupported parameter form is rejected: $declaration', () {
      expect(
        () => _source('Sub Main()\nEnd Sub\nSub Unused($declaration)\nEnd Sub'),
        throwsA(_error()),
      );
    });
  }

  for (final (language, format) in <(String, OfficeMacroFormat)>[
    ('vba-excel', OfficeMacroFormat.xlsx),
    ('vba-powerpoint', OfficeMacroFormat.pptx),
  ]) {
    for (final declaration in <String>['HeaderFooter', 'HeadersFooters']) {
      test('$language refuses Word $declaration declarations', () {
        expect(
          () => OfficeMacroLanguages().compile(
            OfficeMacroSource(
              language: language,
              format: format,
              source: 'Sub Main()\nDim target As $declaration\nEnd Sub',
            ),
          ),
          throwsA(
            isA<OfficeVbaCompileException>().having(
              (error) => error.code,
              'code',
              'vba_unsupported',
            ),
          ),
        );
      });
    }
    test('$language does not import Word header/footer constants', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            source:
                'Option Explicit\nSub Main()\nDim index As Long\nindex = wdHeaderFooterPrimary\nEnd Sub',
          ),
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    });
  }
}
