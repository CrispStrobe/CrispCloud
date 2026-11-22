Option Explicit
Option Base 1

' Synthetic source records. Compilation does not read existing workbook cells.
Sub Main()
    Dim records() As String, index As Long, total As Long
    ReDim records(3)
    records(1) = "INV-1042|Paper"
    records(2) = "INV-2088|Ink"
    records(3) = "INV-3099|Labels"

    With Worksheets("Summary")
        .Range("A1").Value2 = "Record code"
        .Range("B1").Value2 = "Item"
        .Range("C1").Value2 = "ID suffix"
        .Range("D1").Value2 = "Item units"
        .Range("A1:D1").Font.Bold = True
        For index = LBound(records) To UBound(records)
            Call WriteRecord(Worksheets("Summary"), index + 1, records(index))
            total = total + Len(ItemName(records(index)))
        Next index
        .Range("A5").Value2 = "Worksheet total"
        .Range("D5").Formula = "=SUM(D2:D4)"
        .Range("F1").Value2 = "Source total"
        .Range("F2").Value2 = total
        .Range("F3").Value2 = "UTF-16 units"
        .Range("F4").Value2 = Len("A😀B")
        .Range("G3").Value2 = "Emoji"
        .Range("G4").Value2 = Mid$("A😀B", 2, 2)
    End With
    Erase records
End Sub

Private Function ItemName(ByVal record As String) As String
    ItemName = Mid$(record, 10)
End Function

Private Sub WriteRecord(ByVal sheet As Worksheet, ByVal row As Long, ByVal record As String)
    Dim code As String, label As String
    code = Left$(record, 8)
    label = ItemName(record)
    sheet.Cells(row, 1).Value2 = code
    sheet.Cells(row, 2).Value2 = label
    sheet.Cells(row, 3).Value2 = Right$(code, 4)
    sheet.Cells(row, 4).Value2 = Len(label)
End Sub
