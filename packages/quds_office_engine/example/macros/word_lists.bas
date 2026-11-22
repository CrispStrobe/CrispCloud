Option Explicit

' Requires four existing body paragraphs. Empty paragraphs are supported.
' Default methods toggle a matching list; remove paragraph numbering first
' when the intended result must always be a new level-zero default list.
Sub ResetList(ByVal target As ListFormat, ByVal numbered As Boolean)
    With target
        .RemoveNumbers NumberType:=wdNumberParagraph
        If numbered Then
            .ApplyNumberDefault DefaultListBehavior:=wdWord8ListBehavior
        Else
            .ApplyBulletDefault
        End If
    End With
End Sub

Sub Main()
    Dim first As Paragraph
    Dim target As ListFormat
    Set first = Application.ActiveDocument.Paragraphs.Item(1)
    Set target = first.Range.ListFormat
    Call ResetList(numbered:=True, target:=target)

    Set target = ActiveDocument.Paragraphs(2).Range.ListFormat
    ResetList target, False

    With ThisDocument.Paragraphs(3).Range.ListFormat
        .ApplyNumberDefault
        Call .ApplyNumberDefault()
        .ApplyBulletDefault 0
    End With

    Call ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers(NumberType:=wdNumberAllNumbers)
End Sub
