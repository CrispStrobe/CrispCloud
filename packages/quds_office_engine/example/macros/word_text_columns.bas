Option Explicit

' Requires two existing sections. Settings apply to the selected section only.
Sub FormatColumns(ByVal target As TextColumns, Optional ByVal gap As Double = 18)
    With target
        .SetCount NumColumns:=2
        .Spacing = gap
        .LineBetween = True
    End With
End Sub

Sub Main()
    FormatColumns target:=ActiveDocument.Sections(1).PageSetup.TextColumns
    With ActiveDocument.Sections.Item(2).PageSetup.TextColumns
        .SetCount 3
        .Spacing = InchesToPoints(0.25)
        .LineBetween = False
    End With
End Sub
