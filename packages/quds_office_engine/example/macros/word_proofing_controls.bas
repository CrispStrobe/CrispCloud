Option Explicit

Sub CheckedText(ByVal target As Range, Optional ByVal threshold As Double = 12)
    target.NoProofing = False
    target.ParagraphFormat.Hyphenation = True
    target.Font.Kerning = threshold
End Sub

Sub Main()
    Dim p As Paragraph
    Dim target As Range
    Dim font As Font
    Dim format As ParagraphFormat

    Set p = ActiveDocument.Paragraphs.Item(1)
    Set target = p.Range
    CheckedText threshold:=12.5, target:=target

    Set p = ActiveDocument.Paragraphs(2)
    Set font = p.Range.Font
    Set format = p.Format
    p.Range.NoProofing = True
    format.Hyphenation = False
    font.Kerning = 0

    With ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
        .NoProofing = True
        .ParagraphFormat.Hyphenation = False
        .Font.Kerning = 9.5
    End With
End Sub
