Option Explicit
Option Base 1

' Synthetic source data. No existing workbook values are read during compilation.
Sub Main()
    Dim labels() As String, amounts() As Long
    Dim index As Long, total As Long, amount As Variant

    ReDim labels(2), amounts(2)
    labels(1) = "Paper"
    labels(2) = "Ink"
    amounts(1) = 75
    amounts(2) = 125

    ReDim Preserve labels(5), amounts(5)
    labels(3) = "Labels"
    labels(4) = "Folders"
    labels(5) = "Discarded"
    amounts(3) = 250
    amounts(4) = 400
    amounts(5) = 999

    ReDim Preserve labels(4), amounts(4)
    With Worksheets("Summary")
        .Range("A1").Value2 = "Item"
        .Range("B1").Value2 = "Amount"
        .Range("A1:B1").Font.Bold = True
        .Range("A1:B1").Interior.Color = RGB(31, 78, 121)
        .Range("A1:B1").Font.Color = RGB(255, 255, 255)
        For index = LBound(amounts) To UBound(amounts)
            Call WriteRow(Worksheets("Summary"), index + 1, labels(index), amounts(index))
        Next index
        For Each amount In amounts
            total = total + amount
        Next amount
        .Range("D1").Value2 = "Source total"
        .Range("D2").Value2 = total
        .Range("A6").Value2 = "Worksheet total"
        .Range("B6").Formula = "=SUM(B2:B5)"
        .Range("A6:B6").Font.Bold = True

        Erase labels, amounts
        ReDim amounts(1)
        .Range("D3").Value2 = "Reallocated default"
        .Range("D4").Value2 = amounts(1)
    End With
End Sub

Private Sub WriteRow(ByVal sheet As Worksheet, ByVal row As Long, ByVal label As String, ByVal amount As Long)
    sheet.Cells(row, 1).Value2 = label
    sheet.Cells(row, 2).Value2 = amount
End Sub
