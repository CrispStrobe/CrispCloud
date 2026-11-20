Option Explicit

' Requires three existing body paragraphs. Each custom rule must be followed
' by LineSpacing on that same paragraph before another Word mutation.
Sub SetExact(ByVal target As ParagraphFormat, ByVal points As Double)
    Dim amount As Double
    target.LineSpacingRule = wdLineSpaceExactly
    amount = points
    target.LineSpacing = amount
    Set target = ActiveDocument.Paragraphs(3).Format
End Sub

Sub Main()
    Dim target As ParagraphFormat
    Dim savedFormat As ParagraphFormat
    Dim multiplePoints As Double
    Set target = Application.ActiveDocument.Paragraphs.Item(1).Format
    Set savedFormat = target
    target.Space1
    Call SetExact(points:=Application.LinesToPoints(1) + 2.25, target:=savedFormat)

    Set target = ThisDocument.Paragraphs(2).Range.ParagraphFormat
    Call target.Space15
    target.LineSpacingRule = wdLineSpaceAtLeast
    target.LineSpacing = LinesToPoints(PointsToLines(18))

    With ActiveDocument.Paragraphs(3).Range
        With .ParagraphFormat
            Call .Space2()
            .LineSpacingRule = wdLineSpaceMultiple
            multiplePoints = Application.LinesToPoints(PointsToLines(21))
            .LineSpacing = multiplePoints
        End With
    End With
End Sub
