Option Explicit

' Requires an existing ordinary two-row, two-column main-story table.
' Join evaluates local source arrays; cell controls affect current text only.
Sub FillCell(ByVal target As Range, ByVal label As String, ByVal language As Long, Optional ByVal skipProof As Boolean = False, Optional ByVal highlight As Long = wdNoHighlight)
    target.Text = label
    target.LanguageID = language
    target.NoProofing = skipProof
    target.HighlightColorIndex = highlight
End Sub

Sub Main()
    Dim fields(1 To 3) As String
    Dim pair() As String
    Dim target As Range

    fields(1) = "Quds"
    fields(2) = "monthly"
    fields(3) = "report"
    Set target = ActiveDocument.Tables(1).Cell(1, 1).Range
    FillCell target:=target, label:=Join(fields), language:=wdEnglishUS

    fields(1) = "SKU"
    fields(2) = "2026"
    fields(3) = "042"
    Set target = ActiveDocument.Tables(1).Cell(1, 2).Range
    FillCell target:=target, label:=Join(fields, "-"), language:=wdEnglishUS, skipProof:=True

    ReDim pair(4 To 5)
    pair(4) = "Prêt"
    pair(5) = "😀"
    Set target = ActiveDocument.Tables(1).Cell(2, 1).Range
    FillCell target:=target, label:=Join(pair), language:=wdEnglishUS, highlight:=wdBrightGreen
    target.LanguageIDOther = wdFrench

    pair(4) = "Review"
    pair(5) = "complete"
    Set target = ActiveDocument.Tables(1).Cell(2, 2).Range
    FillCell target:=target, label:=Join(pair, " / "), language:=wdEnglishUS, highlight:=wdYellow
End Sub
