Option Explicit

' All text comes from this explicitly selected module, not document reads.
Function ReportTitle(ByVal raw As String) As String
    Dim cleaned As String
    cleaned = Trim$(Replace(raw, "_", " "))
    If InStr(1, cleaned, "DRAFT", vbBinaryCompare) > 0 Then
        cleaned = Replace(cleaned, "DRAFT", "FINAL", 1, 1, vbBinaryCompare)
    End If
    ReportTitle = cleaned
End Function

Sub Main()
    Dim doc As Document
    Dim target As Range
    Dim path As String
    Dim fileName As String
    Dim separator As Long
    Set doc = ActiveDocument

    path = "C:\Reports\2026\Annual_😀_report.docx"
    separator = InStrRev(path, "\", -1, vbBinaryCompare)
    fileName = Mid$(path, separator + 1)
    fileName = Left$(fileName, InStrRev(fileName, ".") - 1)
    fileName = Replace(fileName, "_", " ")

    Set target = doc.Paragraphs(1).Range
    target.InsertBefore ReportTitle("  DRAFT_summary  ") & ": "
    target.Font.Bold = True

    Set target = doc.Paragraphs(2).Range
    target.InsertBefore fileName & " | " & LTrim$("  prepared") & RTrim$(" for review  ") & ": "
    target.Font.Color = RGB(31, 78, 121)

    With doc.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
        .InsertBefore Trim("  INTERNAL  ") & ": "
        .Font.Italic = True
    End With
End Sub
