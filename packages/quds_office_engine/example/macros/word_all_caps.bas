Option Explicit

' Requires two nonempty body paragraphs and an independent primary header.
' AllCaps and SmallCaps change display only; source text stays unchanged.
Sub SetCapitals(ByVal face As Font, Optional ByVal enabled As Boolean = True)
    face.AllCaps = enabled
End Sub

Sub Main()
    Dim title As Font
    Set title = ActiveDocument.Paragraphs.Item(1).Range.Font
    SetCapitals face:=title

    With ThisDocument.Paragraphs(2).Range.Font
        .AllCaps = False
        .SmallCaps = True
        .AllCaps = True
        .AllCaps = False
    End With

    With ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Font
        .SmallCaps = True
        .AllCaps = True
    End With
End Sub
