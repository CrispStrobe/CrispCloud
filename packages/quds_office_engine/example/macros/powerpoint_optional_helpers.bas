Option Explicit

' Input: two slides, each with a text shape named Title.
Sub Main()
    StyleTitle ActivePresentation.Slides(1).Shapes("Title").TextFrame.TextRange, _
        text:="Optional helpers"
    Call StyleTitle(target:=ActivePresentation.Slides(2).Shapes("Title").TextFrame.TextRange, _
        strong:=True, size:=28)
End Sub

Private Sub StyleTitle(ByVal target As TextRange, _
    Optional ByVal strong As Boolean = False, _
    Optional ByVal size As Double = 20, Optional ByVal text As Variant)
    If Not IsMissing(text) Then
        target.Text = CStr(text)
    End If
    target.Font.Size = size
    target.Font.Bold = strong
End Sub
