Option Explicit

' Requires two existing sections with independent primary, first-page and
' even-page headers/footers, each containing at least two paragraphs.
' These explicit story selectors do not create or unlink headers/footers.
Sub StampHeader(ByVal target As Range)
    With target
        .InsertBefore "Report: "
        .Font.Bold = True
        .ParagraphFormat.Alignment = wdAlignParagraphCenter
    End With
End Sub

Sub SetFirstFooter(ByVal story As HeaderFooter)
    story.Range.Paragraphs(1).Range.Font.Color = RGB(31, 78, 121)
End Sub

Sub Main()
    Dim header As HeaderFooter
    Dim line As Paragraph
    Set header = Application.ActiveDocument.Sections.Item(1).Headers.Item(wdHeaderFooterPrimary)
    StampHeader target:=header.Range.Paragraphs(1).Range

    Set line = ThisDocument.Sections(1).Footers(wdHeaderFooterPrimary).Range.Paragraphs.Item(2)
    line.Range.InsertBefore "Page: "
    line.Range.Font.Size = 10

    ActiveDocument.Sections(2).Headers(wdHeaderFooterFirstPage).Range.Paragraphs(1).Range.Font.Italic = True
    With ThisDocument.Sections(2).Footers(wdHeaderFooterEvenPages).Range.Paragraphs(2)
        .Range.InsertBefore "Appendix: "
        .Format.SpaceAfter = 6
        .TabStops.Add Position:=36, Alignment:=wdAlignTabCenter, Leader:=wdTabLeaderDots
    End With

    ThisDocument.Sections(1).Headers(wdHeaderFooterEvenPages).Range.Paragraphs(2).Format.SpaceBefore = 12
    SetFirstFooter story:=ThisDocument.Sections(2).Footers(wdHeaderFooterFirstPage)
End Sub
