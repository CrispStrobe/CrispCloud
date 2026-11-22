Option Explicit

' Requires two existing slides. Slide 1 must contain an ungrouped text
' shape named exactly Title and an editable direct transition (or none).
' Slide 2 is an appendix: Hidden changes its slideshow visibility, not its order.

Sub StyleHeading(ByVal frame As TextFrame)
    Dim headingFont As Font
    Dim paragraph As ParagraphFormat
    Set headingFont = frame.TextRange.Font
    Set paragraph = frame.TextRange.ParagraphFormat

    With frame
        .VerticalAnchor = msoAnchorMiddle
        With .TextRange
            .Text = "Quarterly report"
        End With
    End With
    headingFont.Name = "Arial"
    headingFont.Size = 28
    headingFont.Bold = msoTrue
    headingFont.Color.RGB = RGB(31, 78, 121)
    paragraph.Alignment = ppAlignCenter
End Sub

Sub ConfigureTransition(ByVal movement As SlideShowTransition)
    With movement
        .EntryEffect = ppEffectFadeSmoothly
        .Duration = 1.25
        .AdvanceOnClick = msoTrue
        .Hidden = msoFalse
    End With
    ' Existing automatic-advance timing is retained by these property writes.
End Sub

Sub Main()
    Dim selected As Slide
    Dim frame As TextFrame
    Dim movement As SlideShowTransition
    Set selected = ActivePresentation.Slides(1)
    Set frame = selected.Shapes("Title").TextFrame
    Set movement = selected.SlideShowTransition
    Call StyleHeading(frame)
    Call ConfigureTransition(movement)
    ActivePresentation.Slides(2).SlideShowTransition.Hidden = msoTrue
End Sub
