Option Explicit
Option Base 1

' Synthetic source data: Null is missing; an unassigned slot is Empty.
Sub Main()
    Dim amounts() As Variant, item As Variant
    Dim row As Long, accepted As Long, total As Double
    ReDim amounts(4)
    amounts(1) = "125.5"
    amounts(2) = Null
    amounts(4) = "250.25"

    With Worksheets("Summary")
        .Range("A1").Value2 = "Record"
        .Range("B1").Value2 = "State"
        .Range("C1").Value2 = "Amount"
        .Range("D1").Value2 = "Rounded"
        For row = LBound(amounts) To UBound(amounts)
            item = CVar(amounts(row))
            .Cells(row + 1, 1).Value2 = row
            If IsNull(item) Then
                .Cells(row + 1, 2).Value2 = "Missing"
                .Cells(row + 1, 3).Value2 = Empty
                .Cells(row + 1, 4).Value2 = Empty
            ElseIf IsEmpty(item) Then
                .Cells(row + 1, 2).Value2 = "Unassigned"
                .Cells(row + 1, 3).Value2 = Empty
                .Cells(row + 1, 4).Value2 = Empty
            Else
                .Cells(row + 1, 2).Value2 = "Ready"
                .Cells(row + 1, 3).Value2 = CDbl(item)
                .Cells(row + 1, 4).Value2 = CLng(item)
                total = total + CDbl(item)
                accepted = accepted + 1
            End If
        Next row
        .Range("B7").Value2 = "Source total"
        .Range("C7").Value2 = total
        .Range("B8").Value2 = "Worksheet total"
        .Range("C8").Formula = "=SUM(C2:C5)"
        .Range("B10").Value2 = "Has accepted rows"
        .Range("C10").Value2 = CBool(accepted)
        .Range("B11").Value2 = "Invariant total text"
        .Range("C11").Value2 = CStr(total)
        Erase amounts
        ReDim amounts(1)
        .Range("B12").Value2 = "Reallocated Empty"
        .Range("C12").Value2 = IsEmpty(amounts(1))
        .Range("A1:D1").Font.Bold = True
        .Range("B7:C8").Font.Bold = True
    End With
End Sub
