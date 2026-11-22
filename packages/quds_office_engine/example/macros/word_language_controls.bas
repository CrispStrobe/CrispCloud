Option Explicit

' Requires two nonempty body paragraphs and an independent primary header.
' Language setters target the normal proofing slot; Arabic and East Asian
' language metadata is preserved. NameBi changes the complex-script font.
Sub ConfigureLatin(ByVal target As Range, Optional ByVal language As Long = wdEnglishUK)
    target.LanguageID = language
    target.NoProofing = False
End Sub

Sub Main()
    Dim header As Range
    ConfigureLatin language:=wdGerman, target:=ActiveDocument.Paragraphs(1).Range

    With ActiveDocument.Paragraphs(2).Range
        .LanguageIDOther = wdEnglishUK
        .Font.NameBi = "Amiri"
    End With

    Set header = ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
    header.LanguageIDOther = wdFrench
    header.Font.NameBi = "Noto Naskh Arabic"
    header.Font.Name = "Calibri"
End Sub
