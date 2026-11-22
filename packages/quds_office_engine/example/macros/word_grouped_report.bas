Option Explicit

' Fill an existing ordinary, unmerged 2 x 2 table from source data.
' Integer division selects the row; Mod selects the column and emphasis.
Function ColumnFor(ByVal ordinal As Long, Optional ByVal width As Long = 8 \ 4) As Long
    ColumnFor = ordinal Mod width + 1
End Function

Sub LabelGroup(ByVal target As Range, ByVal ordinal As Long)
    target.InsertAfter Text:=vbTab & "Group " & CStr(ordinal \ 2 + 1)
    target.Font.Bold = (ordinal Mod 2 = 0)
End Sub

Sub Main()
    Const Columns As Long = 7 \ 3
    Dim labels(0 To 3) As String
    Dim index As Long
    Dim report As Table
    Dim target As Range

    labels(0) = "Alpha"
    labels(1) = "Beta"
    labels(2) = "Prêt 😀"
    labels(3) = "Review"
    Set report = ActiveDocument.Tables(1)

    For index = 0 To 3
        Set target = report.Cell(index \ Columns + 1, ColumnFor(index)).Range
        target.Text = labels(index)
        LabelGroup ordinal:=index, target:=target
    Next index
End Sub
