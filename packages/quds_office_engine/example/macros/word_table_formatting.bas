Option Explicit

' Requires an existing ordinary two-row, two-column main-story table.
' Cell text must be plain, nonempty text for Font formatting.
Sub FormatReportCell(ByVal target As Range, ByVal label As String, ByVal heading As Boolean)
    target.Text = label
    With target.Font
        .Name = "Calibri"
        .Size = 11
        .Bold = heading
        .AllCaps = heading
        .Color = RGB(31, 78, 121)
    End With
    With target.ParagraphFormat
        .Alignment = wdAlignParagraphLeft
        .SpaceBefore = 0
        .SpaceAfter = 4
        .KeepTogether = True
        .LineSpacingRule = wdLineSpaceExactly
        .LineSpacing = 14
        .TabStops.ClearAll
        .TabStops.Add Position:=72, Alignment:=wdAlignTabRight, Leader:=wdTabLeaderDots
    End With
End Sub

Sub Main()
    Dim rowIndex As Long, columnIndex As Long
    Dim target As Range, label As String
    For rowIndex = 1 To 2
        For columnIndex = 1 To 2
            If rowIndex = 1 Then
                If columnIndex = 1 Then
                    label = "Item"
                Else
                    label = "Quantity"
                End If
            Else
                If columnIndex = 1 Then
                    label = "Quds report"
                Else
                    label = CStr(42)
                End If
            End If
            Set target = ActiveDocument.Tables(1).Cell(rowIndex, columnIndex).Range
            FormatReportCell target, label, rowIndex = 1
        Next columnIndex
    Next rowIndex
End Sub
