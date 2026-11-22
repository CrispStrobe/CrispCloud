Option Explicit
Option Base 1

' Fill an existing supported 2x2 table from source-local delimited records.
' Split always returns zero-based arrays, independently of Option Base.
Sub Main()
    Dim report As Table
    Dim records() As String, fields() As String
    Dim row As Long, column As Long
    Dim target As Range

    Set report = ActiveDocument.Tables(Index:=1)
    records = Split("Item|Status;Quarterly report|Ready", ";")
    For row = LBound(records) To UBound(records)
        fields = Split(records(row), "|", 2, vbBinaryCompare)
        For column = LBound(fields) To UBound(fields)
            Set target = report.Cell(Row:=row + 1, Column:=column + 1).Range
            target.Text = fields(column)
            If row = 0 Then
                target.Font.Bold = True
            End If
        Next column
    Next row
    report.Cell(2, 2).Range.Font.ColorIndex = wdGreen
End Sub
