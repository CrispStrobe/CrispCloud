Option Explicit

' Template: two unmerged body tables; the first has two rows and two columns,
' the second has one cell. Each selected cell contains one plain paragraph.
Sub Main()
    Dim report As Table
    Dim selected As Cell
    Dim text As Range
    Dim labels(1 To 2) As String
    Dim row As Long

    Set report = Application.ActiveDocument.Tables.Item(1)
    labels(1) = "Item"
    labels(2) = "Total"
    For row = 1 To 2
        PutCell report, row, 1, labels(row)
    Next row

    Set selected = report.Cell(1, 2)
    Set text = selected.Range
    text.Text = Trim$("  Quds report  ")
    PutCell value:=CStr(Abs(-42)), column:=2, row:=2, target:=report

    With ThisDocument.Tables(2).Cell(1, 1).Range
        .Text = "Prepared " & ChrW(10003)
    End With
End Sub

Sub PutCell(ByVal target As Table, ByVal row As Long, ByVal column As Long, ByVal value As String)
    target.Cell(row, column).Range.Text = value
End Sub
