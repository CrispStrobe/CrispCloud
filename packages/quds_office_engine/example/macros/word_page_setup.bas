Option Explicit

' Requires two existing sections. Dimensions and distances are in points.
' The supplied document is the only document addressed by these selectors.
Sub SetReportPage(ByVal page As PageSetup, ByVal width As Double, ByVal height As Double)
    With page
        .PageWidth = width
        .PageHeight = height
        .TopMargin = InchesToPoints(1)
        .BottomMargin = InchesToPoints(0.75)
        .LeftMargin = PicasToPoints(4.5)
        .RightMargin = PicasToPoints(4.5)
        .HeaderDistance = MillimetersToPoints(12.7)
        .FooterDistance = CentimetersToPoints(1.27)
    End With
End Sub

Sub SetSideMargins(ByVal section As Section, ByVal margin As Double)
    With section.PageSetup
        .LeftMargin = margin
        .RightMargin = margin
    End With
End Sub

Sub Main()
    Dim first As Section
    Dim page As PageSetup
    With Application
        Set first = .ActiveDocument.Sections.Item(1)
    End With
    Set page = first.PageSetup
    SetReportPage height:=InchesToPoints(12), page:=page, width:=InchesToPoints(9)
    SetSideMargins margin:=PicasToPoints(3), section:=ThisDocument.Sections(2)
End Sub
