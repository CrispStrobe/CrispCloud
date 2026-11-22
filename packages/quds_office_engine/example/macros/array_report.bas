Option Explicit

' Synthetic source data: compilation never reads existing workbook values.
Const FirstItem As Long = 1, LastItem As Long = 4

Sub Main()
    Dim labels(FirstItem To LastItem) As String
    Dim amounts(FirstItem To LastItem) As Long
    Dim index As Long, total As Long, amount As Variant
    Dim target As Range

    labels(1) = "Paper"
    labels(2) = "Ink"
    labels(3) = "Labels"
    labels(4) = "Folders"
    amounts(1) = 75
    amounts(2) = 125
    amounts(3) = 250
    amounts(4) = 400

    With Worksheets("Summary")
        .Range("A1").Value2 = "Item"
        .Range("B1").Value2 = "Amount"
        For Each target In .Range("A1:B1")
            target.Font.Bold = True
            target.Interior.Color = RGB(31, 78, 121)
            target.Font.Color = RGB(255, 255, 255)
        Next target

        For index = LBound(labels) To UBound(labels)
            Call WriteRow(Worksheets("Summary"), index + 1, labels(index), amounts(index))
        Next index

        For Each amount In amounts
            total = total + amount
        Next amount
        .Range("D1").Value2 = "Source total"
        .Range("D2").Value2 = total
        .Range("A6").Value2 = "Worksheet total"
        .Range("B6").Formula = "=SUM(B2:B5)"
        For Each target In .Range("A6:B6")
            target.Font.Bold = True
            target.Interior.Color = RGB(230, 240, 250)
        Next target
    End With
End Sub

Private Sub WriteRow(ByVal sheet As Worksheet, ByVal row As Long, ByVal label As String, ByVal amount As Long)
    sheet.Cells(row, 1).Value2 = label
    sheet.Cells(row, 2).Value2 = amount
End Sub
