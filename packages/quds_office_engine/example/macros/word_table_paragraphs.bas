Option Explicit

' Format an existing 2 x 2 table without replacing its cell paragraphs.
' The template must contain paragraph styles named "Report Label", "Normal"
' and "heading 1". Cell (2, 1) may be empty; it is still an existing paragraph.
Sub Decorate(ByVal target As Paragraph, ByVal styleName As String, ByVal tone As Long)
    target.Style = styleName
    With target.Shading
        .BackgroundPatternColor = tone
    End With
End Sub

Sub Main()
    Dim report As Table
    Dim heading As Paragraph
    Dim blank As Paragraph
    Dim cellText As Range
    Dim background As Shading

    Set report = ActiveDocument.Tables.Item(1)
    Set heading = report.Cell(1, 1).Range.Paragraphs(1)
    Decorate target:=heading, styleName:="Report Label", tone:=RGB(31, 78, 121)
    With heading.Range
        .Font.ColorIndex = wdWhite
        .ParagraphFormat.SpaceAfter = 6
    End With

    Set cellText = report.Cell(1, 2).Range
    With cellText.Paragraphs.Item(1)
        .Style = wdStyleHeading1
        .Shading.BackgroundPatternColorIndex = wdYellow
    End With

    Set blank = report.Cell(2, 1).Range.Paragraphs(1)
    blank.Range.Style = wdStyleNormal
    Set background = blank.Range.Shading
    background.BackgroundPatternColor = wdColorAutomatic
End Sub
