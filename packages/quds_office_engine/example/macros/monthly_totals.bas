Attribute VB_Name = "MonthlyTotals"
Option Explicit

' Synthetic monthly data demonstrating the bounded vba-excel dialect.
' Run explicitly against the selected workbook. Worksheets(1) is one-based.
Public Sub Main()
    Dim row As Long
    Const firstRow As Long = 2
    Const lastRow As Long = 13

    With ThisWorkbook.Worksheets(1)
        .Range("A1").Value2 = "Month"
        .Range("B1").Value2 = "Revenue"
        .Range("C1").Value2 = "Cost"
        .Range("D1").Value2 = "Net"

        For row = firstRow To lastRow
            .Cells(row, 1).Value2 = "Month " & (row - 1)
            .Cells(row, 2).Value2 = 10000 + (row - 2) * 500
            .Cells(row, 3).Value2 = 6000 + (row - 2) * 200
            .Cells(row, 4).Formula = "=B" & row & "-C" & row
        Next row

        With .Range("A1:D1")
            .Font.Bold = True
            .Font.Size = 12
            .Font.Color = RGB(255, 255, 255)
            .Interior.Color = RGB(31, 78, 121)
        End With

        .Range("A14").Value2 = "Total"
        .Range("B14").Formula = "=SUM(B2:B13)"
        .Range("C14").Formula = "=SUM(C2:C13)"
        .Range("D14").Formula = "=SUM(D2:D13)"
        .Range("A14:D14").Font.Bold = True
    End With
End Sub
