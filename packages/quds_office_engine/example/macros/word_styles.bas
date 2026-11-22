Option Explicit

' Requires three existing body paragraphs and existing paragraph styles named
' Heading 1, Report Body and Caption. Native execution validates those names.
Sub ApplyBody(ByVal target As Paragraph, Optional ByVal name As String = "Report Body")
    target.Style = name
End Sub

Sub Main()
    Dim title As Range
    Dim body As Paragraph
    Set title = ActiveDocument.Paragraphs.Item(1).Range
    Set body = ThisDocument.Paragraphs(2)

    title.Font.Bold = True
    title.Style = wdStyleHeading1
    ApplyBody target:=body
    With ActiveDocument.Paragraphs(3)
        .Style = wdStyleCaption
        .Range.Font.Italic = True
    End With
End Sub
