Option Explicit

' Requires two existing body paragraphs. Measurements are explicit source
' values; no live document reads or application discovery are performed.
Sub ApplyLayout(ByVal layout As ParagraphFormat, ByVal inset As Double)
    With layout
        .LeftIndent = InchesToPoints(inset)
        .RightIndent = CentimetersToPoints(PointsToCentimeters(72))
        .FirstLineIndent = -PicasToPoints(1.5)
        .SpaceBefore = PicasToPoints(0.5)
        .SpaceAfter = MillimetersToPoints(PointsToMillimeters(36))
        .LineSpacingRule = wdLineSpaceExactly
        .LineSpacing = PicasToPoints(PointsToPicas(18))
    End With
End Sub

Sub Main()
    Dim inset As Double
    With Application
        inset = .PointsToInches(.MillimetersToPoints(12.7))
        With .ActiveDocument.Paragraphs.Item(1)
            ApplyLayout inset:=inset, layout:=.Format
            .TabStops.Add Position:=InchesToPoints(1.5), _
                Alignment:=wdAlignTabRight, Leader:=wdTabLeaderDots
        End With
    End With
    ActiveDocument.Paragraphs(2).Format.LeftIndent = _
        CentimetersToPoints(PointsToCentimeters(7.2))
End Sub
