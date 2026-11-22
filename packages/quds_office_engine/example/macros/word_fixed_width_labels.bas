Option Explicit

' Prepare source-known fixed-width labels, then fill an existing 2x2 table.
' Mid/Mid$ changes local strings; it never reads text from the document.
Function StatusLabel(ByVal template As String, ByVal firstPart As String, ByVal lastPart As String) As String
    StatusLabel = template
    Mid$(StatusLabel, 1, 4) = firstPart
    Mid(StatusLabel, 6, 4) = lastPart
End Function

Sub Main()
    Dim labels(1 To 4) As String
    Dim statusTemplate As String, i As Long
    Dim report As Table, target As Range

    labels(1) = "Item: ------"
    Mid$(labels(1), 7, 6) = "Widget"
    labels(2) = "State:        "
    Mid(labels(2), 8, 5) = "Ready"
    labels(3) = "Code: 0000"
    Mid$(labels(3), 7) = "0042"
    statusTemplate = "????/????"
    labels(4) = StatusLabel(template:=statusTemplate, firstPart:="OPEN", lastPart:="DONE")

    Set report = ActiveDocument.Tables(Index:=1)
    For i = LBound(labels) To UBound(labels)
        Set target = report.Cell(Row:=(i - 1) \ 2 + 1, Column:=(i - 1) Mod 2 + 1).Range
        target.Text = labels(i)
        target.Font.Bold = i <= 2
    Next i
End Sub
