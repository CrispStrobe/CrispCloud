Option Explicit

' Requires first-slide shapes named exactly Title and Body.
' The values are source data; this macro does not read a document.
Sub Heading(ByVal target As Shape, ByVal label As String)
    With target.TextFrame.TextRange
        .Text = label
        .Font.Name = "Arial"
        .Font.Size = 28.5
        .Font.Bold = msoTrue
        .Font.Italic = msoFalse
        .Font.Underline = msoFalse
        .Font.Color.RGB = RGB(31, 78, 121)
        .ParagraphFormat.Alignment = ppAlignCenter
    End With
    target.Left = 24
    target.Top = 36
    target.Width = 640
    target.Height = 72
End Sub

Sub Main()
    Dim deck As Presentation
    Dim title As Shape
    Dim amounts(1 To 3) As Long
    Dim index As Long
    Dim total As Long
    Set deck = Application.ActivePresentation
    Set title = deck.Slides.Item(1).Shapes.Item("Title")
    amounts(1) = 5
    amounts(2) = 3
    amounts(3) = 6
    For index = LBound(amounts) To UBound(amounts)
        total = total + amounts(index)
    Next index
    Call Heading(title, "Weekly supply report")
    With deck.Slides(1).Shapes("Body").TextFrame.TextRange
        .Text = "Source records: 3; total units: " & CStr(total)
        .Font.Name = "Arial"
        .Font.Size = 18
        .Font.Bold = False
        .Font.Underline = False
        .ParagraphFormat.Alignment = ppAlignLeft
    End With
End Sub
