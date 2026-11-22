Option Explicit

' Restore a source feed whose individual labels were stored in reverse order.
' Requires an existing ordinary 2x2 table in the supplied Word document.
' This reads local source data only; it never runs an embedded VBA project.
Function RestoreLabel(ByVal value As String) As String
    RestoreLabel = StrReverse(value)
End Function

Sub Main()
    Dim labels() As String
    Dim index As Long
    Dim target As Range

    labels = Split("metI|sutatS|troper ylretrauQ|ydaeR", "|")
    For index = 0 To UBound(labels)
        Set target = ThisDocument.Tables(1).Cell(index \ 2 + 1, index Mod 2 + 1).Range
        target.Text = RestoreLabel(labels(index))
        If index < 2 Then
            target.Font.Bold = True
        End If
    Next index

    ThisDocument.Tables(1).Cell(2, 2).Range.Font.Color = RGB(0, 128, 0)
End Sub
