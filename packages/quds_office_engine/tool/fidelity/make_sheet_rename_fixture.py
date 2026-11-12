"""Author reference coverage as native OOXML, independently of the Dart writer.

The base is the committed openpyxl-authored native.xlsx. This adds explicit
formula owners that the compact editor model cannot fully represent.
"""
from pathlib import Path
from xml.etree import ElementTree as E
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
X = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
E.register_namespace('', X)
E.register_namespace('r', R)

FORMULAS = {
    'D1': 'Data!$B$2',
    'D2': "'Data'!$B$3",
    'D3': 'SUM(Data:Summary!B2)',
    'D4': "SUM('Data:Summary'!B2)",
    'D5': "SUM('Data':'Summary'!B2)",
    'D6': '[1]Data!B2',
    'D7': "'[Remote.xlsx]Data'!B2",
    'D8': 'IF(Data!B2>0,"Data!A1 ""quoted""","\'Data\'!B2")',
    'D9': 'RenameTable[Data!A1]',
    'D10': 'Data!LocalRange',
    'D11': "SUM('Data'!$A:$B)",
    'D12': 'SUM(Data!1:3)',
    'D13': 'INDIRECT("Data!B2")',
    'D14': 'dAtA!b2+Summary!B2',
}

def build():
    fixture = ROOT / 'test/fixtures/fidelity'
    with ZipFile(fixture / 'native.xlsx') as z:
        parts = {name: z.read(name) for name in z.namelist()}
    # Author schema-valid source XML independently: the older base contains
    # producer font-order defects and a redundant pivot r:id. The cache owner
    # already has its proper relationship, which remains byte-for-byte intact.
    font_order = 'b i strike condense extend outline shadow u vertAlign sz color name family charset scheme'.split()
    styles = E.fromstring(parts['xl/styles.xml'])
    for font in styles.find(f'{{{X}}}fonts'):
        font[:] = sorted(font, key=lambda child: font_order.index(child.tag.split('}')[-1]))
    parts['xl/styles.xml'] = E.tostring(styles)
    pivot = E.fromstring(parts['xl/pivotTables/pivotTable1.xml'])
    pivot.attrib.pop(f'{{{R}}}id', None)
    parts['xl/pivotTables/pivotTable1.xml'] = E.tostring(pivot)
    book = E.fromstring(parts['xl/workbook.xml'])
    names = book.find(f'{{{X}}}definedNames')
    definitions = [
        ({'name': 'NativeRange'}, "'Data'!$A$1:$B$3"),
        ({'name': 'Computed'}, 'SUM(Data!$B$2,Summary!$B$2)'),
        ({'name': 'LocalRange', 'localSheetId': '0', 'hidden': '1'}, 'Data!$B$2'),
        ({'name': 'LocalRange', 'localSheetId': '1'}, 'Summary!$B$2'),
        ({'name': 'ThreeD'}, 'SUM(Data:Summary!$B$2)'),
        ({'name': 'Literal'}, '"Data!A1"'),
        ({'name': '_xlnm.Print_Area', 'localSheetId': '0'}, "'Data'!$A$1:$C$5"),
        ({'name': '_xlnm.Print_Titles', 'localSheetId': '0'}, "'Data'!$1:$1"),
    ]
    for attrs, formula in definitions:
        E.SubElement(names, f'{{{X}}}definedName', attrs).text = formula
    refs = E.Element(f'{{{X}}}externalReferences')
    E.SubElement(refs, f'{{{X}}}externalReference', {f'{{{R}}}id': 'renameExternal'})
    book.insert(list(book).index(names), refs)
    parts['xl/workbook.xml'] = E.tostring(book)
    sheet = E.fromstring(parts['xl/worksheets/sheet2.xml'])
    data = sheet.find(f'{{{X}}}sheetData')
    for address, formula in FORMULAS.items():
        row_index = address[1:]
        row = data.find(f'{{{X}}}row[@r="{row_index}"]')
        if row is None:
            row = E.SubElement(data, f'{{{X}}}row', {'r': row_index})
        cell = E.SubElement(row, f'{{{X}}}c', {'r': address})
        E.SubElement(cell, f'{{{X}}}f').text = formula
        E.SubElement(cell, f'{{{X}}}v').text = '42'
    slot = list(sheet).index(sheet.find(f'{{{X}}}pageMargins'))
    consolidate = E.Element(f'{{{X}}}dataConsolidate')
    entries = E.SubElement(consolidate, f'{{{X}}}dataRefs', {'count': '1'})
    E.SubElement(entries, f'{{{X}}}dataRef', {'ref': 'A1:B3', 'sheet': 'Data'})
    conditional = E.Element(f'{{{X}}}conditionalFormatting', {'sqref': 'E1 E3:E4'})
    for index, formula in enumerate(['Data!B2>0', 'SUM(Data:Summary!B2)>1'], 1):
        rule = E.SubElement(conditional, f'{{{X}}}cfRule', {'type': 'expression', 'priority': str(index), 'stopIfTrue': '1'})
        E.SubElement(rule, f'{{{X}}}formula').text = formula
    validations = E.Element(f'{{{X}}}dataValidations', {'count': '2'})
    rule = E.SubElement(validations, f'{{{X}}}dataValidation', {
        'sqref': 'F1 F3:F4', 'type': 'whole', 'operator': 'between',
        'allowBlank': '1', 'showErrorMessage': '1', 'error': 'Data!A1 is literal help text',
    })
    E.SubElement(rule, f'{{{X}}}formula1').text = 'Data!$B$2'
    E.SubElement(rule, f'{{{X}}}formula2').text = "'Data'!$B$3"
    literal = E.SubElement(validations, f'{{{X}}}dataValidation', {'sqref': 'F5', 'type': 'list'})
    E.SubElement(literal, f'{{{X}}}formula1').text = '"Data!A1,Other"'
    links = E.Element(f'{{{X}}}hyperlinks')
    E.SubElement(links, f'{{{X}}}hyperlink', {'ref': 'G1', 'location': "'Data'!A1", 'display': 'Data!A1'})
    for offset, node in enumerate([consolidate, conditional, validations, links]):
        sheet.insert(slot + offset, node)
    parts['xl/worksheets/sheet2.xml'] = E.tostring(sheet)
    external = E.Element(f'{{{X}}}externalLink')
    external_book = E.SubElement(external, f'{{{X}}}externalBook', {f'{{{R}}}id': 'rId1'})
    sheets = E.SubElement(external_book, f'{{{X}}}sheetNames')
    E.SubElement(sheets, f'{{{X}}}sheetName', {'val': 'Data'})
    parts['xl/externalLinks/externalLink1.xml'] = E.tostring(external)
    external_rels = E.Element(f'{{{P}}}Relationships')
    E.SubElement(external_rels, f'{{{P}}}Relationship', {'Id': 'rId1', 'Type': R + '/externalLinkPath', 'Target': 'Remote.xlsx', 'TargetMode': 'External'})
    parts['xl/externalLinks/_rels/externalLink1.xml.rels'] = E.tostring(external_rels)
    rels = E.fromstring(parts['xl/_rels/workbook.xml.rels'])
    E.SubElement(rels, f'{{{P}}}Relationship', {'Id': 'renameExternal', 'Type': R + '/externalLink', 'Target': 'externalLinks/externalLink1.xml'})
    parts['xl/_rels/workbook.xml.rels'] = E.tostring(rels)
    types = E.fromstring(parts['[Content_Types].xml'])
    E.SubElement(types, f'{{{CT}}}Override', {'PartName': '/xl/externalLinks/externalLink1.xml', 'ContentType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.externalLink+xml'})
    # System.IO.Packaging requires the package content-types root to use
    # its default namespace. Do not serialize it with ElementTree's ns0 prefix.
    E.register_namespace('', CT)
    parts['[Content_Types].xml'] = E.tostring(types)
    E.register_namespace('', X)
    target = fixture / 'sheet-rename-native.xlsx'
    with ZipFile(target, 'w', ZIP_DEFLATED) as z:
        for name, data in parts.items():
            info = ZipInfo(name, (2026, 11, 12, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            z.writestr(info, data)
    return target

if __name__ == '__main__':
    print(build())
