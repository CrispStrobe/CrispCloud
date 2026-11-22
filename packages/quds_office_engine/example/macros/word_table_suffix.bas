Option Explicit

' Append status labels to an existing ordinary, unmerged 2 x 2 table.
' Original cell text and distinct run formatting survive; cell (2, 1) may
' start empty. Use direct Cell.Range, not a projected Paragraph.Range.
Sub AppendLabel(ByVal target As Range, ByVal label As String)
    target.InsertAfter Text:=label

    ' Rebinding the ByVal alias leaves the caller's cell selection intact.
    Set target = ActiveDocument.Tables.Item(1).Cell(1, 2).Range
    target.InsertAfter Text:=vbTab & "Peer"
End Sub

Sub Main()
    Dim report As Table
    Dim original As Range

    Set report = ActiveDocument.Tables(1)
    Set original = report.Cell(1, 1).Range
    AppendLabel label:=vbTab & "Ready", target:=original
    original.InsertAfter Text:=vbTab & "Reviewed"

    ' The original range includes the appended labels and original text.
    original.Font.Bold = True

    With report.Cell(1, 2)
        With .Range
            Call .InsertAfter(Text:=vbTab & "Owner")
        End With
    End With
    Call report.Cell(2, 1).Range.InsertAfter(Text:="New" & vbTab & "Ready")
End Sub
