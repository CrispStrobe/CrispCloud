Option Explicit

' Synthetic source data: compilation never reads existing workbook values.
Sub Main()
    Dim row As Long, amount As Long
    Call WriteHeading(Worksheets("Summary"))
    row = 2
    Do
        amount = (row - 1) * 75
        With Worksheets("Summary")
            .Cells(row, 1).Value2 = "Batch " & (row - 1)
            .Cells(row, 2).Value2 = amount
            .Cells(row, 3).Value2 = Band(amount)
        End With
        row = row + 1
    Loop Until row > 7
    Call WriteTotal(Worksheets("Summary"), row)
End Sub

Private Sub WriteHeading(ByVal sheet As Worksheet)
    With sheet
        .Range("A1").Value2 = "Batch"
        .Range("B1").Value2 = "Amount"
        .Range("C1").Value2 = "Band"
        .Range("A1:C1").Font.Bold = True
        .Range("A1:C1").Interior.Color = RGB(31, 78, 121)
        .Range("A1:C1").Font.Color = RGB(255, 255, 255)
    End With
End Sub

Private Function Band(ByVal amount As Long) As String
    Select Case amount
        Case 0, 75
            Band = "Small"
        Case 76 To 225
            Band = "Standard"
        Case Is < 400
            Band = "Large"
        Case Else
            Band = "Review"
    End Select
End Function

Private Sub WriteTotal(ByVal sheet As Worksheet, ByVal row As Long)
    Dim column As Long
    sheet.Cells(row, 1).Value2 = "Total"
    sheet.Cells(row, 2).Formula = "=SUM(B2:B" & (row - 1) & ")"
    column = 1
    While column <= 3
        sheet.Cells(row, column).Font.Bold = True
        column = column + 1
    Wend
End Sub
