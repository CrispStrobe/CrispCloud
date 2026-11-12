"""Mutation controls start from independently authored expected XML."""
import unittest
from xml.etree import ElementTree as E
from sheet_qualified_names_oracle import X, cell, expected_parts, verify


class QualifiedNamesOracleTest(unittest.TestCase):
    def reject(self, path, mutate, renamed=False):
        parts = expected_parts(renamed)
        root = E.fromstring(parts[path])
        mutate(root)
        parts[path] = E.tostring(root)
        with self.assertRaises((AssertionError, AttributeError)):
            verify(parts, renamed)

    def test_accepts_both_independent_expected_states(self):
        verify(expected_parts())
        verify(expected_parts(True), True)

    def test_rejects_global_instead_of_local(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D1').find(X + 'v'), 'text', '11'))

    def test_rejects_stale_previously_unsupported_cache(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D2').find(X + 'v'), 'text', '42'))

    def test_rejects_wrong_scope_owner(self):
        self.reject('xl/workbook.xml', lambda r: r.find(X + 'definedNames/' + X + 'definedName[@name="Foreign"]').set('localSheetId', '0'))

    def test_rejects_lost_hidden_metadata(self):
        self.reject('xl/workbook.xml', lambda r: r.find(X + 'definedNames/' + X + 'definedName[@name="Foreign"]').attrib.pop('hidden'))

    def test_rejects_dropped_opaque_name(self):
        self.reject('xl/workbook.xml', lambda r: r.find(X + 'definedNames').remove(r.find(X + 'definedNames/' + X + 'definedName[@name="Outside"]')))

    def test_rejects_error_spelling_as_error_type_for_text(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: cell(r, 'D6').set('t', 'e'))

    def test_rejects_real_error_downgraded_to_text(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: cell(r, 'D7').set('t', 'str'))

    def test_rejects_boolean_downgraded_to_number(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: cell(r, 'D5').attrib.pop('t'))

    def test_rejects_error_ignored_by_aggregate(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D12').find(X + 'v'), 'text', '0'))

    def test_rejects_unsupported_name_coerced_to_zero(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D13').find(X + 'v'), 'text', '0'))

    def test_rejects_external_cache_recomputed(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D14').find(X + 'v'), 'text', '0'))

    def test_rejects_stale_renamed_qualifier(self):
        self.reject('xl/worksheets/sheet3.xml', lambda r: setattr(cell(r, 'D2').find(X + 'f'), 'text', "'O''Brien Data'!pRiCe"), True)

    def test_rejects_relative_definition_reinterpreted_as_absolute(self):
        self.reject('xl/workbook.xml', lambda r: setattr(r.find(X + 'definedNames/' + X + 'definedName[@name="Relative"]'), 'text', 'Alpha!$B$2'))


if __name__ == '__main__':
    unittest.main()
