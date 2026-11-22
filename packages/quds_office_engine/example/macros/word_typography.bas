Option Explicit

' Input: three existing body paragraphs. Source text is prefixed on each run.
Sub Heading(ByVal target As Range)
    With target
        .InsertBefore "Research note"
        .Font.SmallCaps = True
        .Font.Bold = True
        .HighlightColorIndex = wdYellow
    End With
End Sub

Sub Main()
    Dim doc As Document
    Set doc = Application.ActiveDocument
    Call Heading(doc.Paragraphs.Item(1).Range)

    With ActiveDocument.Paragraphs(2).Range
        .InsertBefore "Reference marker"
        .Font.Superscript = True
        .Font.Subscript = False
        .HighlightColorIndex = wdNoHighlight
    End With

    With doc.Paragraphs.Item(3).Range
        .InsertBefore "Formula annotation"
        .Font.Subscript = True
        .Font.Superscript = False
        .HighlightColorIndex = wdGray25
    End With
End Sub
