Option Explicit

' Fill an existing ordinary two-row, two-column main-story table.
' All indexes and labels come from source; existing document values are not read.
Sub WriteLabel(ByVal target As Cells, ByVal index As Long, ByVal label As String)
    With target.Item(Index:=index).Range
        .Text = label
        .Font.Bold = True
    End With
End Sub

Sub Main()
    Dim report As Table, headings As Row, statusColumn As Column
    Dim status As Range

    Set report = ActiveDocument.Tables(Index:=1)
    Set headings = report.Rows.Item(Index:=1)
    WriteLabel target:=headings.Cells, index:=1, label:="Item"
    WriteLabel target:=headings.Cells, index:=2, label:="Status"

    report.Rows(2).Cells(1).Range.Text = "Quarterly report"
    Set statusColumn = report.Columns(Index:=2)
    Set status = statusColumn.Cells.Item(Index:=2).Range
    status.Text = "Ready"
    status.InsertAfter Text:=vbTab & "Reviewed"
    status.Font.ColorIndex = wdGreen
    status.ParagraphFormat.Alignment = wdAlignParagraphRight

    ' Named Cell arguments can appear in either named order.
    report.Cell(Column:=1, Row:=2).Range.InsertBefore Text:="Document: "
End Sub
