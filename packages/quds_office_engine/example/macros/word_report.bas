' Run against a Word template with six existing, empty body paragraphs.
' Paragraphs are selected explicitly; this module does not read the document.
' Running it again inserts a second report before the existing paragraph text.
Option Explicit

Sub Main()
    Dim doc As Document
    Dim p As Paragraph
    Dim target As Range
    Dim names(1 To 3) As String
    Dim units(1 To 3) As Long
    Dim i As Long, total As Long
    Dim note As Variant

    Set doc = ThisDocument
    names(1) = "Paper"
    names(2) = "Ink"
    names(3) = "Labels"
    units(1) = 5
    units(2) = 3
    units(3) = 6

    Set p = doc.Paragraphs(1)
    Set target = p.Range
    Call WriteLine(target, "Weekly supply report", True)
    With target
        .Font.Size = 18
        .Font.Color = RGB(31, 78, 121)
        .ParagraphFormat.Alignment = wdAlignParagraphCenter
        .ParagraphFormat.SpaceBefore = 0
    End With

    For i = 1 To 3
        Set target = doc.Paragraphs(i + 1).Range
        Call WriteLine(target, names(i) & ": " & CStr(units(i)), False)
        total = total + units(i)
    Next i

    Set target = doc.Paragraphs(5).Range
    Call WriteLine(target, "Total units: " & CStr(total), True)

    If IsEmpty(note) Then
        note = "Source values supplied by the macro."
    End If
    Set target = doc.Paragraphs(6).Range
    Call WriteLine(target, CStr(note) & " " & Mid$("A😀B", 2, 2), False)
End Sub

Sub WriteLine(ByVal target As Range, ByVal text As String, ByVal bold As Boolean)
    target.InsertBefore text
    With target.Font
        .Name = "Arial"
        .Size = 11
        .Bold = bold
        .Italic = False
    End With
    With target.ParagraphFormat
        .SpaceAfter = 6
        .Alignment = wdAlignParagraphLeft
    End With
End Sub
