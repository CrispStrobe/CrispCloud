Option Explicit

' Requires three body paragraphs and an independent primary header.
' Values are supplied by this selected module; it does not read document data.
' Running again prepends another report label; absolute formatting stays fixed.
Function WholeMagnitude(ByVal raw As Double) As Long
    WholeMagnitude = Abs(Fix(raw))
End Function

Sub Annotate(ByVal target As Range, ByVal raw As Double)
    target.InsertBefore "Abs=" & CStr(Abs(raw)) & "; Int=" & CStr(Int(raw)) & "; Fix=" & CStr(Fix(raw)) & "; Sgn=" & CStr(Sgn(raw)) & ": "
    target.Font.Bold = Sgn(raw) < 0
    target.ParagraphFormat.LeftIndent = WholeMagnitude(raw)
End Sub

Sub Main()
    Dim doc As Document
    Dim measurement As Variant
    Dim missingValue As Variant
    Set doc = ActiveDocument

    measurement = CVar(-8.25)
    Annotate doc.Paragraphs(Abs(-1)).Range, CDbl(measurement)
    Annotate doc.Paragraphs(Int(2.9)).Range, CDbl("8.25")

    ' Empty is zero. Abs, Int and Fix retain Null for explicit handling.
    If IsNull(Abs(Null)) And IsNull(Int(Null)) And IsNull(Fix(Null)) Then
        doc.Paragraphs(3).Range.InsertBefore "Missing; empty=" & CStr(Sgn(missingValue)) & ": "
    End If

    With doc.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
        .InsertBefore "Magnitude " & CStr(WholeMagnitude(-8.25)) & ": "
        ' Explicit conversion maps VBA True to -1 before Sgn is called.
        .Font.Position = Sgn(CDbl(True))
    End With
End Sub
