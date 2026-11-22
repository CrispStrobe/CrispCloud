Option Explicit

' Requires three existing body paragraphs. Empty paragraphs are supported.
' List levels use Word's one-based values: 1 is the outermost, 9 the deepest.
' Remove paragraph numbering before applying a default when an outline must
' always be present: ApplyOutlineNumberDefault toggles an existing outline off.
Sub SetOutline(ByVal target As ListFormat, ByVal levelNumber As Long)
    With target
        .RemoveNumbers NumberType:=wdNumberParagraph
        .ApplyOutlineNumberDefault DefaultListBehavior:=wdWord8ListBehavior
        .ListLevelNumber = levelNumber
    End With
End Sub

Sub Main()
    Dim first As Paragraph
    Dim target As ListFormat
    Set first = Application.ActiveDocument.Paragraphs.Item(1)
    Set target = first.Range.ListFormat
    Call SetOutline(levelNumber:=2, target:=target)
    With target
        .ListIndent
        Call .ListOutdent()
    End With

    Set target = ThisDocument.Paragraphs(2).Range.ListFormat
    SetOutline target, 3

    With ActiveDocument.Paragraphs(3).Range
        With .ListFormat
            .RemoveNumbers NumberType:=wdNumberParagraph
            Call .ApplyOutlineNumberDefault()
            .ListLevelNumber = 9
            Call .ListOutdent
            .ListIndent()
        End With
    End With
End Sub
