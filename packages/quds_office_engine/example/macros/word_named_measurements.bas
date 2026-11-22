Option Explicit

' Requires two existing body paragraphs; leaves all later paragraphs alone.
' Use dimensions that land on Word's exact twentieth-point storage grid.
Sub ReportParagraph(ByVal target As ParagraphFormat, ByVal inset As Double, Optional ByVal after As Double = 6)
    With target
        .LeftIndent = inset
        .RightIndent = MillimetersToPoints(Millimeters:=12.7)
        .FirstLineIndent = -PicasToPoints(Picas:=1.5)
        .SpaceBefore = InchesToPoints(Inches:=0.125)
        .SpaceAfter = after
        .LineSpacingRule = wdLineSpaceExactly
        .LineSpacing = PicasToPoints(1.15)
    End With
End Sub

Sub Main()
    Dim centimeters As Double
    Dim millimeters As Double
    Dim inches As Double
    Dim picas As Double
    Dim lines As Double
    Dim layout As ParagraphFormat

    With Application
        centimeters = .PointsToCentimeters(Points:=72)
        millimeters = .PointsToMillimeters(72)
        inches = .PointsToInches(Points:=72)
        picas = .PointsToPicas(72)
        lines = .PointsToLines(Points:=13.8)
    End With

    Set layout = ThisDocument.Paragraphs(1).Range.ParagraphFormat
    ReportParagraph inset:=Application.InchesToPoints(0.5), target:=layout
    layout.TabStops.ClearAll
    layout.TabStops.Add Position:=CentimetersToPoints(Centimeters:=2.54), Alignment:=wdAlignTabCenter, Leader:=wdTabLeaderDots

    Set layout = ActiveDocument.Paragraphs.Item(2).Format
    With layout
        .LeftIndent = CentimetersToPoints(centimeters)
        .RightIndent = Application.MillimetersToPoints(millimeters)
        .SpaceBefore = PicasToPoints(picas)
        .SpaceAfter = InchesToPoints(inches)
        .LineSpacingRule = wdLineSpaceMultiple
        .LineSpacing = LinesToPoints(Lines:=lines)
    End With
End Sub
