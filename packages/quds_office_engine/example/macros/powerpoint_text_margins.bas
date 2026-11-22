Option Explicit

' Requires an existing ungrouped text shape named Title on slide 1.
Sub LayoutTitle(ByVal target As TextFrame)
    With target
        .MarginLeft = 18
        .MarginTop = 6
        .MarginRight = 18
        .MarginBottom = 12
        .VerticalAnchor = msoAnchorMiddle
    End With
End Sub

Sub Main()
    Dim title As TextFrame
    Set title = ActivePresentation.Slides(1).Shapes("Title").TextFrame
    Call LayoutTitle(title)
End Sub
