Option Explicit

Sub Main()
    Dim code As Variant
    Dim sections As Sections
    Dim targets As Paragraphs

    code = "INV-0042-DE"
    Set sections = ActiveDocument.Sections

    Set targets = sections.Item(Index:=2).Headers.Item(Index:=wdHeaderFooterPrimary).Range.Paragraphs
    Prefix label:=ReferenceLabel(code) & ": ", items:=targets, ordinal:=1
    targets.Item(Index:=1).Range.Font.Bold = True

    Set targets = sections.Item(Index:=2).Footers(Index:=wdHeaderFooterEvenPages).Range.Paragraphs
    Call Prefix(items:=targets, ordinal:=2, label:=Right(code, 2) & " ")

    Set targets = ActiveDocument.Paragraphs
    Prefix targets, 1, Left(code, 3) & " "

    Set targets = sections.Item(Index:=3).Headers(Index:=wdHeaderFooterFirstPage).Range.Paragraphs
    Prefix targets, 1, ReferenceLabel(Null) & ": "
End Sub

Sub Prefix(ByVal items As Paragraphs, ByVal ordinal As Long, ByVal label As String)
    items.Item(Index:=ordinal).Range.InsertBefore Text:=label
End Sub

Function ReferenceLabel(ByVal code As Variant) As String
    Dim number As Variant
    number = Mid(code, 5, 4)
    If IsNull(number) Then
        ReferenceLabel = "Pending"
    Else
        ReferenceLabel = Left(code, 3) & " " & number & " / " & Right(code, 2)
    End If
End Function
