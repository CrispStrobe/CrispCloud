Option Explicit

' Prefix existing text in an ordinary, unmerged 2 x 2 table.
' Each selected cell must contain one ordinary paragraph. Existing text and
' run formatting remain in place; cell (2, 1) may be empty.
Sub PrefixWithLabel(ByVal target As Range, ByVal label As String)
    target.InsertBefore Text:=Replace(label, vbCrLf, vbTab)

    ' Rebinding this ByVal alias does not change the caller's selected range.
    Set target = ActiveDocument.Tables.Item(1).Cell(1, 2).Range
    target.InsertBefore Text:="Peer" & vbTab
End Sub

Sub Main()
    Dim report As Table
    Dim original As Range
    Dim projected As Paragraph

    Set report = ActiveDocument.Tables(1)
    Set original = report.Cell(1, 1).Range
    PrefixWithLabel label:="Status" & vbCrLf, target:=original
    original.InsertBefore Text:="Review" & vbTab

    ' The retained cell range includes both prefixes and the original text.
    original.Font.Bold = True

    Set projected = report.Cell(1, 2).Range.Paragraphs.Item(1)
    With projected.Range
        .InsertBefore Text:="Owner" & vbTab
    End With
    Call report.Cell(2, 1).Range.InsertBefore(Text:="New" & vbTab)
End Sub
