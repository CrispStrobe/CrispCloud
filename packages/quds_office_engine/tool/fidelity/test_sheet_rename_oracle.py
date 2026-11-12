"""Tamper controls use explicitly authored expected XML, never Dart output."""
import unittest
from xml.etree import ElementTree as E
from sheet_rename_oracle import C, CACHES, CHART, CONDITIONAL, FORMULAS, NAME, NAMES, X, read_zip, verify

def authored():
    parts = read_zip('test/fixtures/fidelity/sheet-rename-native.xlsx')
    def edit(path, change):
        root = E.fromstring(parts[path]); change(root); parts[path] = E.tostring(root)
    def workbook(root):
        root.find(X+'sheets')[0].set('name', NAME)
        for node in root.find(X+'definedNames'):
            node.text = NAMES[(node.get('name'), node.get('localSheetId'))]
    edit('xl/workbook.xml', workbook)
    def worksheet(root):
        for address, formula in FORMULAS.items():
            root.find(f'.//{X}c[@r="{address}"]/{X}f').text = formula
        for address, (value, kind) in CACHES.items():
            cell = root.find(f'.//{X}c[@r="{address}"]')
            cell.find(X+'v').text = str(value)
            if kind: cell.set('t', kind)
            else: cell.attrib.pop('t', None)
        rules = root.find(X+'dataValidations')
        rules[0].find(X+'formula1').text = "'O''Brien 2026'!$B$2"
        rules[0].find(X+'formula2').text = "'O''Brien 2026'!$B$3"
        for node, text in zip(root.findall(X+'conditionalFormatting/'+X+'cfRule/'+X+'formula'), CONDITIONAL): node.text = text
        root.find(X+'hyperlinks/'+X+'hyperlink').set('location', "'O''Brien 2026'!A1")
        root.find(X+'dataConsolidate/'+X+'dataRefs/'+X+'dataRef').set('sheet', NAME)
    edit('xl/worksheets/sheet2.xml', worksheet)
    edit('xl/pivotCache/pivotCacheDefinition1.xml', lambda root: root.find(X+'cacheSource/'+X+'worksheetSource').set('sheet', NAME))
    def chart(root):
        for node, text in zip(root.iter(C+'f'), CHART): node.text = text
    edit('xl/charts/chart1.xml', chart)
    return parts

class SheetRenameOracleTest(unittest.TestCase):
    def test_accepts_independently_authored_expected_package(self):
        verify(authored())

    def reject(self, path, change):
        parts = authored(); root = E.fromstring(parts[path]); change(root); parts[path] = E.tostring(root)
        with self.assertRaises((AssertionError, AttributeError)): verify(parts)

    def test_rejects_stale_local_reference(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D1"]/{X}f'), 'text', 'Data!$B$2'))
    def test_rejects_external_reference_rewritten(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D6"]/{X}f'), 'text', "'[1]O''Brien 2026'!B2"))
    def test_rejects_literal_rewritten(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D13"]/{X}f'), 'text', 'INDIRECT("Next!B2")'))
    def test_rejects_dropped_computed_name(self):
        self.reject('xl/workbook.xml', lambda r: r.find(X+'definedNames').remove(r.find(X+'definedNames/'+X+'definedName[@name="Computed"]')))
    def test_rejects_local_name_scope_change(self):
        self.reject('xl/workbook.xml', lambda r: r.find(X+'definedNames/'+X+'definedName[@name="LocalRange"]').set('localSheetId', '1'))
    def test_rejects_missing_second_validation_formula(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: r.find(X+'dataValidations')[0].remove(r.find(X+'dataValidations')[0].find(X+'formula2')))
    def test_rejects_dropped_conditional_rule(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: r.find(X+'conditionalFormatting').remove(r.find(X+'conditionalFormatting')[1]))
    def test_rejects_stale_pivot_source(self):
        self.reject('xl/pivotCache/pivotCacheDefinition1.xml', lambda r: r.find(X+'cacheSource/'+X+'worksheetSource').set('sheet', 'Data'))
    def test_rejects_stale_chart_title_reference(self):
        self.reject('xl/charts/chart1.xml', lambda r: setattr(next(r.iter(C+'f')), 'text', "'Data'!B1"))

    def test_rejects_external_cache_recomputed_locally(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D7"]/{X}v'), 'text', '2'))
    def test_rejects_3d_cache_recomputed_locally(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D3"]/{X}v'), 'text', '0'))
    def test_rejects_whole_column_cache_zeroed(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D11"]/{X}v'), 'text', '0'))
    def test_rejects_whole_row_cache_zeroed(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D12"]/{X}v'), 'text', '0'))
    def test_rejects_missing_string_cache_type(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: r.find(f'.//{X}c[@r="D8"]').attrib.pop('t'))
    def test_rejects_truncated_escaped_quotes(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D8"]/{X}v'), 'text', 'Data!A1 '))
    def test_rejects_missing_error_cache_type(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: r.find(f'.//{X}c[@r="D13"]').attrib.pop('t'))
    def test_rejects_stale_supported_arithmetic_cache(self):
        self.reject('xl/worksheets/sheet2.xml', lambda r: setattr(r.find(f'.//{X}c[@r="D14"]/{X}v'), 'text', '42'))

if __name__ == '__main__': unittest.main()
