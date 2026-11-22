Option Explicit

' Run against two existing body paragraphs and an independent primary header.
' Unicode construction is source-only; no document properties are read.
Function Badge(ByVal label As String) As String
    Badge = String$(2, ChrW(9733)) & Space$(1) & label & Space(1)
End Function

Sub Main()
    Dim face As String
    Dim signedCode As Long
    face = ChrW(55357) & ChrW(56832)
    signedCode = AscW(ChrW(32768))

    With ActiveDocument.Paragraphs(1).Range
        .InsertBefore Badge("READY")
        .Font.Bold = True
    End With
    ActiveDocument.Paragraphs(2).Range.InsertBefore _
        face & Space(2) & ChrW$(signedCode) & ": "
    With ActiveDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
        .InsertBefore String(3, "-+") & Space$(1)
        .Font.Italic = True
    End With
End Sub
