"""Independent ZIP/ElementTree assertions for native sheet rename exports."""
from pathlib import Path
from xml.etree import ElementTree as E
from zipfile import ZipFile

X = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
C = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
NAME = "O'Brien 2026"
FORMULAS = {
    'D1': "'O''Brien 2026'!$B$2",
    'D2': "'O''Brien 2026'!$B$3",
    'D3': "SUM('O''Brien 2026:Summary'!B2)",
    'D4': "SUM('O''Brien 2026:Summary'!B2)",
    'D5': "SUM('O''Brien 2026:Summary'!B2)",
    'D6': '[1]Data!B2',
    'D7': "'[Remote.xlsx]Data'!B2",
    'D8': 'IF(\'O\'\'Brien 2026\'!B2>0,"Data!A1 ""quoted""","\'Data\'!B2")',
    'D9': 'RenameTable[Data!A1]',
    'D10': "'O''Brien 2026'!LocalRange",
    'D11': "SUM('O''Brien 2026'!$A:$B)",
    'D12': "SUM('O''Brien 2026'!1:3)",
    'D13': 'INDIRECT("Data!B2")',
    'D14': "'O''Brien 2026'!b2+Summary!B2",
}
NAMES = {
    ('NativeRange', None): "'O''Brien 2026'!$A$1:$B$3",
    ('Computed', None): "SUM('O''Brien 2026'!$B$2,Summary!$B$2)",
    ('LocalRange', '0'): "'O''Brien 2026'!$B$2",
    ('LocalRange', '1'): 'Summary!$B$2',
    ('ThreeD', None): "SUM('O''Brien 2026:Summary'!$B$2)",
    ('Literal', None): '"Data!A1"',
    ('_xlnm.Print_Area', '0'): "'O''Brien 2026'!$A$1:$C$5",
    ('_xlnm.Print_Titles', '0'): "'O''Brien 2026'!$1:$1",
}
CHART = ["'O''Brien 2026'!B1", "'O''Brien 2026'!$A$2:$A$3", "'O''Brien 2026'!$B$2:$B$3"]
CONDITIONAL = ["'O''Brien 2026'!B2>0", "SUM('O''Brien 2026:Summary'!B2)>1"]

def read_zip(path):
    with ZipFile(path) as z:
        assert len(z.namelist()) == len(set(z.namelist())), 'Duplicate ZIP entries'
        return {name: z.read(name) for name in z.namelist()}

def verify(parts):
    book = E.fromstring(parts['xl/workbook.xml'])
    assert [s.get('name') for s in book.find(X+'sheets')] == [NAME, 'Summary'], 'Sheet names'
    names = book.find(X+'definedNames')
    assert {(n.get('name'), n.get('localSheetId')): n.text for n in names} == NAMES, 'Defined names/scopes/formulas'
    assert names.find(X+'definedName[@name="LocalRange"][@localSheetId="0"]').get('hidden') == '1', 'Native name metadata'
    sheet = E.fromstring(parts['xl/worksheets/sheet2.xml'])
    for address, expected in FORMULAS.items():
        assert sheet.find(f'.//{X}c[@r="{address}"]/{X}f').text == expected, f'Formula {address}'
    rules = sheet.find(X+'dataValidations')
    assert len(rules) == 2 and rules[0].get('sqref') == 'F1 F3:F4', 'Native validation scope'
    assert rules[0].get('operator') == 'between' and rules[0].get('showErrorMessage') == '1', 'Native validation metadata'
    assert rules[0].get('error') == 'Data!A1 is literal help text', 'Literal validation help'
    assert rules[0].find(X+'formula1').text == "'O''Brien 2026'!$B$2", 'Validation first formula'
    assert rules[0].find(X+'formula2').text == "'O''Brien 2026'!$B$3", 'Validation second formula'
    assert rules[1].find(X+'formula1').text == '"Data!A1,Other"', 'Literal list values'
    conditional = sheet.find(X+'conditionalFormatting')
    assert conditional.get('sqref') == 'E1 E3:E4', 'Native conditional scope'
    assert [n.text for n in conditional.findall(X+'cfRule/'+X+'formula')] == CONDITIONAL, 'All native conditional formulas'
    assert [n.get('priority') for n in conditional] == ['1', '2'], 'Conditional priorities'
    assert all(n.get('type') == 'expression' and n.get('stopIfTrue') == '1' for n in conditional), 'Conditional metadata'
    link = sheet.find(X+'hyperlinks/'+X+'hyperlink')
    assert link.get('location') == "'O''Brien 2026'!A1" and link.get('display') == 'Data!A1', 'Internal hyperlink vs display text'
    assert sheet.find(X+'dataConsolidate/'+X+'dataRefs/'+X+'dataRef').get('sheet') == NAME, 'Consolidation source'
    cache = E.fromstring(parts['xl/pivotCache/pivotCacheDefinition1.xml'])
    assert cache.find(X+'cacheSource/'+X+'worksheetSource').get('sheet') == NAME, 'Pivot source'
    chart = E.fromstring(parts['xl/charts/chart1.xml'])
    assert [n.text for n in chart.iter(C+'f')] == CHART, 'All native chart references'
    external = E.fromstring(parts['xl/externalLinks/externalLink1.xml'])
    assert external.find(X+'externalBook/'+X+'sheetNames/'+X+'sheetName').get('val') == 'Data', 'External workbook sheet name'

def main():
    output = Path('build/fidelity-sheet-rename')
    assert {p.name for p in output.glob('*.xlsx')} == {'source.xlsx', 'renamed-1.xlsx', 'renamed-2.xlsx', 'renamed-3.xlsx'}, 'Exact rename corpus'
    assert read_zip(output/'source.xlsx') == read_zip('test/fixtures/fidelity/sheet-rename-native.xlsx'), 'Authored source changed'
    for cycle in (1, 2, 3):
        verify(read_zip(output/f'renamed-{cycle}.xlsx'))
    print('Native sheet-rename references passed across all three saves.')

if __name__ == '__main__':
    main()
