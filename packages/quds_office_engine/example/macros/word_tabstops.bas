Option Explicit

' Requires three existing body paragraphs. Empty paragraphs are supported.
' Positions are points; supported values use exact twentieth-point increments.
Sub ReportTabs(ByVal stops As TabStops, Optional ByVal rightEdge As Double = 432)
    With stops
        .ClearAll
        .Add Position:=72, Alignment:=wdAlignTabLeft
        .Add rightEdge, wdAlignTabRight, wdTabLeaderDots
    End With
End Sub

Sub Main()
    Dim first As Paragraph
    Dim stops As TabStops
    Set first = Application.ActiveDocument.Paragraphs.Item(1)
    Set stops = first.TabStops
    Call ReportTabs(stops:=stops)

    With ActiveDocument.Paragraphs(2).Format.TabStops
        .Add Leader:=wdTabLeaderDashes, Position:=216, Alignment:=wdAlignTabCenter
        .Add 324, , wdTabLeaderLines
    End With

    Set stops = ThisDocument.Paragraphs(3).Range.ParagraphFormat.TabStops
    stops.ClearAll
    stops.Add -18, wdAlignTabDecimal
End Sub
