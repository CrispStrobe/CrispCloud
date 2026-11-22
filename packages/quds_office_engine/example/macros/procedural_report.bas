Attribute VB_Name = "ProceduralReport"
Option Explicit

' Synthetic sales data: no live workbook values are read during compilation.
Sub Main()
    Dim sheet As Worksheet, item As Long
    Set sheet = ThisWorkbook.Worksheets(1)
    sheet.Range("A1").Value2 = "Item"
    sheet.Range("B1").Value2 = "Quantity"
    sheet.Range("C1").Value2 = "Unit price"
    sheet.Range("D1").Value2 = "Net"
    Call FormatHeading(sheet.Range("A1:D1"))

    For item = 1 To 6
        WriteItem sheet, item + 1, item * 5, UnitPrice(item)
    Next item

    sheet.Range("A8").Value2 = "Total"
    sheet.Range("D8").Formula = "=SUM(D2:D7)"
    sheet.Range("A8:D8").Font.Bold = True
End Sub

Private Sub FormatHeading(ByVal target As Range)
    With target
        .Font.Bold = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(31, 78, 121)
    End With
End Sub

Private Sub WriteItem(ByVal sheet As Worksheet, ByVal row As Long, _
                      ByVal quantity As Long, ByVal price As Double)
    If quantity <= 0 Then
        Exit Sub
    End If
    With sheet
        .Cells(row, 1).Value2 = "Item " & (row - 1)
        .Cells(row, 2).Value2 = quantity
        .Cells(row, 3).Value2 = price
        .Cells(row, 4).Value2 = NetAmount(quantity, price)
    End With
End Sub

Private Function UnitPrice(ByVal item As Long) As Double
    UnitPrice = 12.5 + item * 2.5
End Function

Private Function NetAmount(ByVal quantity As Long, ByVal price As Double) As Double
    NetAmount = quantity * price * (1 - DiscountRate(quantity))
End Function

Private Function DiscountRate(ByVal quantity As Long) As Double
    If quantity >= 20 Then
        DiscountRate = 0.15
        Exit Function
    End If
    If quantity >= 10 Then
        DiscountRate = 0.1
    End If
End Function
