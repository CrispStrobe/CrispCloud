Option Explicit

' Requires three existing body paragraphs. Reset each target before toggling
' so the example can run again on its own output with the same result.
Sub OpenParagraph(ByVal target As Paragraph)
    target.OpenUp
    Set target = ActiveDocument.Paragraphs(3)
End Sub

Sub FlipFormat(ByVal target As ParagraphFormat)
    target.OpenOrCloseUp
End Sub

Sub Main()
    Dim first As Paragraph
    Dim saved As Paragraph
    Dim format As ParagraphFormat
    Set first = Application.ActiveDocument.Paragraphs.Item(1)
    Set saved = first
    first.CloseUp
    Call OpenParagraph(target:=saved)
    Call first.OpenOrCloseUp()
    first.OpenUp

    Set format = ThisDocument.Paragraphs(2).Range.ParagraphFormat
    format.OpenUp
    Call FlipFormat(target:=format)

    With ActiveDocument.Paragraphs(3)
        .CloseUp
        With .Format
            .OpenOrCloseUp
            Call .OpenOrCloseUp()
            Call .OpenUp
        End With
    End With
End Sub
