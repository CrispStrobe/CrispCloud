"""Author native fill references without using the Quds parser or serializer.

The sheet has labelled, generously sized fill swatches. Source and expected
packages share only explicitly authored OOXML; no output from a Dart test is an
input to this builder. The complete theme comes from the existing independent
native workbook, so theme colors are meaningful to external Office renderers.
"""

from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "test/fixtures/fidelity"
X = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
P = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "http://schemas.openxmlformats.org/package/2006/content-types"

# These are native-format definitions, not modeled RGB expectations. In
# particular, native theme, pattern, gradient and indexed identity must survive
# a font-only edit even when the editor displays the same scalar fill color.
FILLS = [
    '<s:fill><s:patternFill patternType="none"/></s:fill>',
    '<s:fill><s:patternFill patternType="gray125"/></s:fill>',
    '<s:fill><s:patternFill patternType="solid"><s:fgColor rgb="FF000000"/></s:patternFill></s:fill>',
    '<s:fill><s:patternFill patternType="solid"><s:fgColor theme="1"/></s:patternFill></s:fill>',
    '<s:fill><s:patternFill patternType="darkGrid"><s:fgColor rgb="FF000000"/><s:bgColor rgb="FFFFFFFF"/></s:patternFill></s:fill>',
    '<s:fill><s:gradientFill degree="90"><s:stop position="0"><s:color rgb="FFFF0000"/></s:stop><s:stop position="1"><s:color rgb="FF0000FF"/></s:stop></s:gradientFill></s:fill>',
    '<s:fill><s:patternFill patternType="solid"><s:fgColor indexed="2"/></s:patternFill></s:fill>',
]
NATIVE_FILL_IDS = (3, 4, 5, 6, 2, 1)
LABELS = (
    "Theme black", "Dark grid", "Red to blue gradient", "Indexed red",
    "Direct black", "Gray125 pattern",
)


def xml(body):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + body).encode()


def styles(phase):
    font_bold = '<s:b/>' if phase == "unrelated" else ''
    fonts = (
        '<s:font><s:sz val="11"/><s:color rgb="FF000000"/><s:name val="Calibri"/></s:font>'
        f'<s:font>{font_bold}<s:sz val="11"/><s:color rgb="FFFFFFFF"/><s:name val="Calibri"/></s:font>'
    )
    fills = list(FILLS)
    fill_ids = list(NATIVE_FILL_IDS)
    if phase == "explicit":
        # Author a direct solid red and green independently of style derivation.
        # The expected swatches are black, black, no fill, red, green, no fill.
        # This includes equal displayed colors and a clear command on a gradient
        # whose modeled RGB is already empty.
        fills += [
            '<s:fill><s:patternFill patternType="solid"><s:fgColor rgb="FFFF0000"/></s:patternFill></s:fill>',
            '<s:fill><s:patternFill patternType="solid"><s:fgColor rgb="FF00A050"/></s:patternFill></s:fill>',
        ]
        fill_ids = [2, 2, 0, 7, 8, 0]
    swatches = ''.join(
        f'<s:xf numFmtId="0" fontId="1" fillId="{fill_id}" borderId="0" xfId="0" '
        'applyFont="1" applyFill="1" applyAlignment="1">'
        '<s:alignment horizontal="center" vertical="center"/></s:xf>'
        for fill_id in fill_ids
    )
    label = (
        '<s:xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" '
        'applyAlignment="1"><s:alignment vertical="center"/></s:xf>'
    )
    return xml(
        f'<s:styleSheet xmlns:s="{X}">'
        f'<s:fonts count="2">{fonts}</s:fonts>'
        f'<s:fills count="{len(fills)}">{"".join(fills)}</s:fills>'
        '<s:borders count="1"><s:border><s:left/><s:right/><s:top/><s:bottom/><s:diagonal/></s:border></s:borders>'
        '<s:cellStyleXfs count="1"><s:xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></s:cellStyleXfs>'
        f'<s:cellXfs count="7">{swatches}{label}</s:cellXfs>'
        '<s:cellStyles count="1"><s:cellStyle name="Normal" xfId="0" builtinId="0"/></s:cellStyles>'
        '</s:styleSheet>'
    )


def sheet():
    def label(address, text):
        return f'<s:c r="{address}" s="6" t="inlineStr"><s:is><s:t>{escape(text)}</s:t></s:is></s:c>'

    rows = [
        '<s:row r="1" ht="28" customHeight="1">'
        + label('A1', 'Native cell fills') + label('B1', 'Swatch') + '</s:row>',
        '<s:row r="2" ht="18" customHeight="1">'
        + label('A2', 'Native fill identity') + '</s:row>',
    ]
    for index, text in enumerate(LABELS):
        row = index + 3
        rows.append(
            f'<s:row r="{row}" ht="36" customHeight="1">'
            + label(f'A{row}', text)
            + f'<s:c r="B{row}" s="{index}"><s:v>{index + 1}</s:v></s:c></s:row>'
        )
    return xml(
        f'<s:worksheet xmlns:s="{X}">'
        '<s:sheetPr><s:pageSetUpPr fitToPage="1"/></s:sheetPr>'
        '<s:dimension ref="A1:B8"/>'
        '<s:sheetViews><s:sheetView workbookViewId="0" showGridLines="0"/></s:sheetViews>'
        '<s:sheetFormatPr defaultRowHeight="15"/>'
        '<s:cols><s:col min="1" max="1" width="28" customWidth="1"/>'
        '<s:col min="2" max="2" width="20" customWidth="1"/></s:cols>'
        f'<s:sheetData>{"".join(rows)}</s:sheetData>'
        '<s:pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>'
        '<s:pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="1"/>'
        '</s:worksheet>'
    )


def parts(phase, theme):
    return {
        '[Content_Types].xml': xml(
            f'<Types xmlns="{CT}">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '<Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
            '</Types>'
        ),
        '_rels/.rels': xml(
            f'<Relationships xmlns="{P}"><Relationship Id="office" Type="{R}/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        ),
        'xl/workbook.xml': xml(
            f'<s:workbook xmlns:s="{X}" xmlns:r="{R}">'
            '<s:bookViews><s:workbookView/></s:bookViews>'
            '<s:sheets><s:sheet name="Native fills" sheetId="1" r:id="sheet"/></s:sheets>'
            '<s:definedNames><s:definedName name="_xlnm.Print_Area" localSheetId="0">\'Native fills\'!$A$1:$B$8</s:definedName></s:definedNames>'
            '</s:workbook>'
        ),
        'xl/_rels/workbook.xml.rels': xml(
            f'<Relationships xmlns="{P}">'
            f'<Relationship Id="sheet" Type="{R}/worksheet" Target="worksheets/sheet1.xml"/>'
            f'<Relationship Id="styles" Type="{R}/styles" Target="styles.xml"/>'
            f'<Relationship Id="theme" Type="{R}/theme" Target="theme/theme1.xml"/>'
            '</Relationships>'
        ),
        'xl/styles.xml': styles(phase),
        'xl/worksheets/sheet1.xml': sheet(),
        'xl/theme/theme1.xml': theme,
    }


def build():
    with ZipFile(FIXTURES / 'sheet-rename-native.xlsx') as archive:
        theme = archive.read('xl/theme/theme1.xml')
    paths = []
    for phase, name in (
        ('source', 'sheet-fill-native.xlsx'),
        ('unrelated', 'sheet-fill-unrelated-expected.xlsx'),
        ('explicit', 'sheet-fill-explicit-expected.xlsx'),
    ):
        target = FIXTURES / name
        with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
            for path, content in sorted(parts(phase, theme).items()):
                info = ZipInfo(path, (2026, 11, 14, 0, 0, 0))
                info.compress_type = ZIP_DEFLATED
                archive.writestr(info, content)
        paths.append(target)
    return paths


if __name__ == '__main__':
    for target in build():
        print(target.relative_to(ROOT))
