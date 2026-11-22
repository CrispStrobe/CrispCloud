Option Explicit

' Requires two existing body paragraphs. Reapplying it keeps the same formatting.
Sub SetIndents(ByVal target As ParagraphFormat, ByVal width As Double)
    target.LeftIndent = width
    target.RightIndent = InchesToPoints(0.25)
    target.FirstLineIndent = -PicasToPoints(1.5)
End Sub

Sub Main()
    Dim first As ParagraphFormat
    Dim width As Double
    With Application
        Set first = .ActiveDocument.Paragraphs(1).Format
        width = .CentimetersToPoints(2.54)
    End With

    SetIndents width:=width, target:=first
    first.SpaceBefore = PicasToPoints(1)
    first.SpaceAfter = InchesToPoints(PointsToInches(6))

    With ActiveDocument.Paragraphs(2).Range.ParagraphFormat
        .LeftIndent = MillimetersToPoints(25.4)
        .RightIndent = PicasToPoints(PointsToPicas(18))
        .SpaceBefore = CentimetersToPoints(PointsToCentimeters(12))
        .SpaceAfter = MillimetersToPoints(PointsToMillimeters(6))
    End With
End Sub
