Option Explicit
Const StandardSize As Long = 12

' Input: a Word document with at least three main-story paragraphs.
Sub Main()
    Call StyleParagraph(target:=ActiveDocument.Paragraphs(1).Range, _
        size:=18, caption:="Heading")
    StyleParagraph ActiveDocument.Paragraphs(2).Range, bold:=True
    Call StyleParagraph(ActiveDocument.Paragraphs(3).Range, , 10, Empty)
End Sub

Private Sub StyleParagraph(ByVal target As Range, _
    Optional ByVal bold As Boolean = False, _
    Optional ByVal size As Double = StandardSize, _
    Optional ByVal caption As Variant)
    If Not IsMissing(caption) Then
        If Not IsEmpty(caption) Then
            target.InsertBefore CStr(caption) & ": "
        End If
    End If
    target.Font.Bold = bold
    target.Font.Size = size
End Sub
