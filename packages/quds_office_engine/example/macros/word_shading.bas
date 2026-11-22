Option Explicit

' Requires three body paragraphs and independent primary header and footer.
' Only paragraph background shading changes; text and run formatting stay intact.
Sub SetShade(ByVal shade As Shading, Optional ByVal tone As Long = 5649426)
    shade.BackgroundPatternColor = tone
End Sub

Sub Main()
    Dim shade As Shading
    Set shade = ActiveDocument.Paragraphs.Item(1).Shading
    SetShade shade:=shade, tone:=RGB(18, 52, 86)

    With ThisDocument.Paragraphs(2).Range.Shading
        .BackgroundPatternColorIndex = wdYellow
        .BackgroundPatternColor = wdColorAutomatic
    End With

    ActiveDocument.Paragraphs(3).Shading.BackgroundPatternColorIndex = wdGray25

    With Application.ActiveDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Shading
        .BackgroundPatternColorIndex = wdTurquoise
    End With

    With ThisDocument.Sections(1).Footers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Shading
        .BackgroundPatternColor = RGB(18, 52, 86)
        .BackgroundPatternColorIndex = wdAuto
    End With
End Sub
