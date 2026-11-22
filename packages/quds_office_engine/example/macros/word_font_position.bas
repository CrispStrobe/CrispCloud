Option Explicit

' Requires three existing body paragraphs and an independent primary header.
' Position raises or lowers current text without changing its font size.
Sub OffsetText(ByVal target As Font, ByVal points As Long)
    target.Position = points
End Sub

Sub Main()
    Dim raised As Font
    Set raised = ActiveDocument.Paragraphs(1).Range.Font
    OffsetText points:=3, target:=raised

    With ActiveDocument.Paragraphs(2).Range.Font
        .Position = -2
        .Bold = True
    End With

    ' An explicit zero overrides any inherited baseline displacement.
    ActiveDocument.Paragraphs(3).Range.Font.Position = 0

    With ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary)
        .Range.Paragraphs(1).Range.Font.Position = 1
    End With
End Sub
