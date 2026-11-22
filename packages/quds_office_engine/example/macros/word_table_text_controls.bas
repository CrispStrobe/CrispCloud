Option Explicit

' Requires an existing ordinary two-row, two-column main-story table.
' Each control applies to current nonempty cell text, excluding cell marks.
Sub ReviewCell(ByVal target As Range, ByVal label As String, ByVal language As Long, Optional ByVal highlight As Long = wdNoHighlight, Optional ByVal skipProof As Boolean = False)
    target.Text = label
    With target
        .LanguageID = language
        .NoProofing = skipProof
        .HighlightColorIndex = highlight
    End With
End Sub

Sub Main()
    Dim target As Range
    Set target = ActiveDocument.Tables(1).Cell(1, 1).Range
    ReviewCell target:=target, label:="Product", language:=wdEnglishUS
    Set target = ActiveDocument.Tables(1).Cell(1, 2).Range
    ReviewCell target:=target, label:="Artikel", language:=wdGerman, highlight:=wdYellow
    Set target = ActiveDocument.Tables(1).Cell(2, 1).Range
    ReviewCell target:=target, label:="SKU-042", language:=wdEnglishUS, skipProof:=True
    Set target = ActiveDocument.Tables(1).Cell(2, 2).Range
    ReviewCell target:=target, label:="Prêt 😀", language:=wdEnglishUS, highlight:=wdBrightGreen
    target.LanguageIDOther = wdFrench
End Sub
