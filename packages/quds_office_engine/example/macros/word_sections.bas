Option Explicit

' Requires two existing sections in the supplied document.
' Orientation changes retain the named margins and header/footer distances.
Sub ConfigureReport(ByVal page As PageSetup, ByVal start As Long)
    With page
        .Orientation = wdOrientLandscape
        .SectionStart = start
    End With
End Sub

Sub Main()
    Dim report As PageSetup
    Dim appendix As PageSetup
    Set report = Application.ActiveDocument.Sections.Item(1).PageSetup
    Set appendix = ThisDocument.Sections(2).PageSetup
    ConfigureReport start:=wdSectionNewPage, page:=report

    With appendix
        .SectionStart = wdSectionEvenPage
        .Orientation = wdOrientLandscape
        Call .TogglePortrait()
        .TogglePortrait
        .LeftMargin = InchesToPoints(0.75)
    End With
End Sub
