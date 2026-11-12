"""Independent OOXML author for worksheet-local defined-name regressions.

No Quds importer, serializer, or formula evaluator is used. localSheetId is a
zero-based worksheet index, deliberately different from sheetId (41, 7, 99).
Microsoft's Names in formulas and MS-OE376 definedName documentation specify
local-before-global lookup and explicitly qualified worksheet-local names:
https://support.microsoft.com/en-us/excel/names-in-formulas
https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/ddfb7406-8921-4540-a4ed-8516b3d7d583
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
SHEETS = [('Alpha', 41), ("O'Brien Data", 7), ('Summary', 99)]
DEFINITIONS = [
    ('Price', None, 'Alpha!$B$2'),
    ('Price', 0, 'Alpha!$B$3'),
    ('Price', 1, "'O''Brien Data'!$B$2"),
    ('Points', 1, "'O''Brien Data'!$B$2:$B$3"),
    ('Foreign', 1, 'Alpha!$B$4'),
    ('Flag', 1, 'TRUE'),
    ('Text', 1, '"#REF!"'),
    ('Problem', 1, '#REF!'),
    ('Rate', 1, '-2.5'),
    ('_Local.Total', 1, "'O''Brien Data'!$B$3"),
    ('قيمة', 1, "'O''Brien Data'!$B$2"),
    ('Errors', 1, "'O''Brien Data'!$B$5:$B$6"),
    ('Computed', None, 'Alpha!$B$2'),
    ('Computed', 1, 'SUM(Alpha!$B$2,Alpha!$B$3)'),
    ('Outside', 1, "'[Remote.xlsx]Alpha'!$B$2"),
    ('Columns', 1, 'Alpha!$B:$B'),
    ('ThreeD', 1, 'Alpha:Summary!$B$2'),
    ('Relative', 1, 'Alpha!B2'),
    ('OnlyGlobal', None, 'Alpha!$B$2'),
]
# Formula, authored cache type, authored cache. Supported caches deliberately
# differ from their independent arithmetic result to expose skipped calculation.
FORMULAS = [
    ('Alpha!Price', None, '42'),
    ("'O''Brien Data'!pRiCe", None, '42'),
    ("SUM('O''Brien Data'!Points)", None, '42'),
    ("'O''Brien Data'!Foreign", None, '42'),
    ("'O''Brien Data'!Flag", 'b', '0'),
    ("'O''Brien Data'!Text", 'str', 'old'),
    ("'O''Brien Data'!Problem", 'e', '#N/A'),
    ("'O''Brien Data'!Rate", None, '42'),
    ("'O''Brien Data'!_Local.Total", None, '42'),
    ("'O''Brien Data'!قيمة", None, '42'),
    ('Price', None, '42'),
    ("SUM('O''Brien Data'!Errors)", None, '42'),
    ("SUM('O''Brien Data'!Computed)", None, '42'),
    ("'O''Brien Data'!Outside", 'b', '1'),
    ("'O''Brien Data'!Columns", 'str', '#REF!'),
    ("'O''Brien Data'!ThreeD", 'e', '#N/A'),
    ("'O''Brien Data'!Relative", None, '81'),
    ("'O''Brien Data'!OnlyGlobal", None, '73'),
]


def xml(element):
    return E.tostring(element, encoding='utf-8', xml_declaration=True)


def cell(row, address, value, kind=None, formula=None):
    attrs = {'r': address}
    if kind:
        attrs['t'] = kind
    node = E.SubElement(row, f'{{{X}}}c', attrs)
    if formula is not None:
        E.SubElement(node, f'{{{X}}}f').text = formula
    E.SubElement(node, f'{{{X}}}v').text = str(value)


def build():
    book = E.Element(f'{{{X}}}workbook')
    sheets = E.SubElement(book, f'{{{X}}}sheets')
    rels = E.Element(f'{{{P}}}Relationships')
    parts = {}
    for index, (name, sheet_id) in enumerate(SHEETS, 1):
        E.SubElement(sheets, f'{{{X}}}sheet', {
            'name': name, 'sheetId': str(sheet_id), f'{{{R}}}id': f'sheet{index}',
        })
        E.SubElement(rels, f'{{{P}}}Relationship', {
            'Id': f'sheet{index}', 'Type': R + '/worksheet',
            'Target': f'worksheets/sheet{index}.xml',
        })
        sheet = E.Element(f'{{{X}}}worksheet')
        data = E.SubElement(sheet, f'{{{X}}}sheetData')
        for row_number in range(1, len(FORMULAS) + 1):
            row = E.SubElement(data, f'{{{X}}}row', {'r': str(row_number)})
            if index == 1 and row_number in (2, 3, 4):
                cell(row, f'B{row_number}', {2: 11, 3: 13, 4: 17}[row_number])
            if index == 2 and row_number in (2, 3, 5, 6):
                value, kind = {2: (7, None), 3: (9, None),
                               5: ('#DIV/0!', 'e'), 6: ('#REF!', 'str')}[row_number]
                cell(row, f'B{row_number}', value, kind)
            if index in (1, 2) and row_number == 1:
                cell(row, 'D1', 42, formula='Price')
            if index == 3:
                formula, kind, value = FORMULAS[row_number - 1]
                cell(row, f'D{row_number}', value, kind, formula)
        parts[f'xl/worksheets/sheet{index}.xml'] = xml(sheet)
    names = E.SubElement(book, f'{{{X}}}definedNames')
    for name, scope, definition in DEFINITIONS:
        attrs = {'name': name}
        if scope is not None:
            attrs['localSheetId'] = str(scope)
        if name == 'Foreign':
            attrs.update(hidden='1', comment='scope owner differs from target')
        E.SubElement(names, f'{{{X}}}definedName', attrs).text = definition
    parts['xl/workbook.xml'] = xml(book)
    parts['xl/_rels/workbook.xml.rels'] = xml(rels)
    root_rels = E.Element(f'{{{P}}}Relationships')
    E.SubElement(root_rels, f'{{{P}}}Relationship', {
        'Id': 'book', 'Type': R + '/officeDocument', 'Target': 'xl/workbook.xml',
    })
    parts['_rels/.rels'] = xml(root_rels)
    types = E.Element(f'{{{CT}}}Types')
    for extension, content in [('rels', 'application/vnd.openxmlformats-package.relationships+xml'),
                               ('xml', 'application/xml')]:
        E.SubElement(types, f'{{{CT}}}Default', {'Extension': extension, 'ContentType': content})
    for part, kind in [('xl/workbook.xml', 'sheet.main'),
                       *[(f'xl/worksheets/sheet{i}.xml', 'worksheet') for i in range(1, 4)]]:
        E.SubElement(types, f'{{{CT}}}Override', {
            'PartName': '/' + part,
            'ContentType': f'application/vnd.openxmlformats-officedocument.spreadsheetml.{kind}+xml',
        })
    E.register_namespace('', CT)
    parts['[Content_Types].xml'] = xml(types)
    E.register_namespace('', X)
    target = ROOT / 'test/fixtures/fidelity/sheet-qualified-names-native.xlsx'
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for path, data in sorted(parts.items()):
            entry = ZipInfo(path, (2026, 11, 12, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, data)
    return target


if __name__ == '__main__':
    print(build())
