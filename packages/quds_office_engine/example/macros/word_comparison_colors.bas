Option Explicit

' Template: three nonempty body paragraphs, independent primary header/footer,
' and one unmerged body table with a single row and two plain cells.
' The comparisons use source data; no existing document text is read.
Sub Main()
    Dim statuses(1 To 2) As String
    Dim selected As Font
    Dim row As Long

    statuses(1) = "  Ready  "
    statuses(2) = "Review"
    For row = 1 To 2
        Set selected = ActiveDocument.Paragraphs(row).Range.Font
        MarkStatus status:=Trim$(statuses(row)), target:=selected
    Next row

    With ThisDocument.Paragraphs(3).Range.Font
        .ColorIndex = wdBlue
        .Color = wdColorAutomatic
    End With

    Set selected = ActiveDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Font
    selected.ColorIndex = wdDarkBlue
    With ActiveDocument.Sections(1).Footers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Font
        .ColorIndex = wdRed
        .ColorIndex = wdAuto
    End With

    With ActiveDocument.Tables(1)
        .Cell(1, 1).Range.Text = CStr(StrComp("Ready", "Ready", vbBinaryCompare))
        .Cell(1, 2).Range.Text = CStr(StrComp("A", "a"))
    End With
End Sub

Sub MarkStatus(ByVal target As Font, ByVal status As String)
    If StrComp(status, "Ready", vbBinaryCompare) = 0 Then
        target.ColorIndex = wdGreen
    Else
        target.ColorIndex = wdDarkRed
    End If
End Sub
