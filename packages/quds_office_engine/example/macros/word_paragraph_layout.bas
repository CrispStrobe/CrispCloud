Option Explicit

' Requires three existing body paragraphs; paragraph 1 must contain text.
' Format aliases are explicit paragraph selectors, not live property reads.
Sub StyleHeading(ByVal face As Font, ByVal layout As ParagraphFormat)
    face.Bold = True
    face.Size = 16
    layout.SpaceAfter = 6
    layout.LineSpacingRule = wdLineSpaceSingle
End Sub

Sub Main()
    Dim heading As Paragraph
    Dim face As Font
    Dim layout As ParagraphFormat
    Set heading = Application.ActiveDocument.Paragraphs.Item(1)
    Set face = heading.Range.Font
    Set layout = heading.Format
    Call StyleHeading(face, layout)

    With ActiveDocument.Paragraphs(2).Format
        .ReadingOrder = wdReadingOrderRtl
        .Alignment = wdAlignParagraphRight
        .LineSpacingRule = wdLineSpace1pt5
    End With

    Set layout = ActiveDocument.Paragraphs(3).Range.ParagraphFormat
    With layout
        .ReadingOrder = wdReadingOrderLtr
        .LineSpacingRule = wdLineSpaceDouble
        .KeepTogether = True
    End With
End Sub
