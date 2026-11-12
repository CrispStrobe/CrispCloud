"""Independent OOXML oracle and native expected fixtures for FID-027 names.

Expected values are authored arithmetic and scalar literals, never imported
from an engine export or calculated by Quds. Unsupported owners remain exact.
"""
import argparse
from pathlib import Path
from xml.etree import ElementTree as E
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

X = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
SOURCE = Path('test/fixtures/fidelity/sheet-qualified-names-native.xlsx')
OLD = "O'Brien Data"
NEW = "Next's Sheet"
OLD_PREFIX = "'O''Brien Data'!"
NEW_PREFIX = "'Next''s Sheet'!"
# Data: Alpha B2=11, B3=13, B4=17; O'Brien Data B2=7, B3=9.
# local Price shadows global Price; Foreign's owner differs from its target.
EXPECTED = {
    'D1': (None, '13'), 'D2': (None, '7'), 'D3': (None, '16'),
    'D4': (None, '17'), 'D5': ('b', '1'), 'D6': ('str', '#REF!'),
    'D7': ('e', '#REF!'), 'D8': (None, '-2.5'), 'D9': (None, '9'),
    'D10': (None, '7'), 'D11': (None, '11'), 'D12': ('e', '#DIV/0!'),
    # Unsupported computation/external/whole-column/3D/relative/global fallback.
    'D13': (None, '42'), 'D14': ('b', '1'), 'D15': ('str', '#REF!'),
    'D16': ('e', '#N/A'), 'D17': (None, '81'), 'D18': (None, '73'),
}


def read_zip(path):
    with ZipFile(path) as archive:
        assert len(archive.namelist()) == len(set(archive.namelist())), 'Duplicate ZIP entries'
        return {name: archive.read(name) for name in archive.namelist()}


def write_zip(path, parts):
    path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(path, 'w', ZIP_DEFLATED) as archive:
        for name, data in sorted(parts.items()):
            entry = ZipInfo(name, (2026, 11, 12, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, data)


def cell(root, address):
    return root.find(f'.//{X}sheetData/{X}row/{X}c[@r="{address}"]')


def set_cache(node, kind, value):
    if kind is None:
        node.attrib.pop('t', None)
    else:
        node.set('t', kind)
    node.find(X + 'v').text = value


def expected_parts(renamed=False):
    parts = read_zip(SOURCE)
    book = E.fromstring(parts['xl/workbook.xml'])
    if renamed:
        book.find(X + 'sheets')[1].set('name', NEW)
        for name in book.find(X + 'definedNames'):
            name.text = name.text.replace(OLD_PREFIX, NEW_PREFIX)
    parts['xl/workbook.xml'] = E.tostring(book)
    for index in (1, 2, 3):
        path = f'xl/worksheets/sheet{index}.xml'
        sheet = E.fromstring(parts[path])
        if index == 3:
            for address, (kind, value) in EXPECTED.items():
                node = cell(sheet, address)
                set_cache(node, kind, value)
                if renamed:
                    node.find(X + 'f').text = node.find(X + 'f').text.replace(OLD_PREFIX, NEW_PREFIX)
        else:
            set_cache(cell(sheet, 'D1'), None, '13' if index == 1 else '7')
        parts[path] = E.tostring(sheet)
    return parts


def verify(parts, renamed=False):
    expected = expected_parts(renamed)
    book = E.fromstring(parts['xl/workbook.xml'])
    reference = E.fromstring(expected['xl/workbook.xml'])
    assert [(s.get('name'), s.get('sheetId')) for s in book.find(X + 'sheets')] == [
        (s.get('name'), s.get('sheetId')) for s in reference.find(X + 'sheets')
    ], 'Worksheet scope owners'
    names = [(dict(n.attrib), n.text) for n in book.find(X + 'definedNames')]
    assert names == [(dict(n.attrib), n.text) for n in reference.find(X + 'definedNames')], 'Exact definitions/scopes/metadata'
    for index in (1, 2, 3):
        path = f'xl/worksheets/sheet{index}.xml'
        sheet = E.fromstring(parts[path])
        reference = E.fromstring(expected[path])
        refs = EXPECTED if index == 3 else {'D1': (None, '13' if index == 1 else '7')}
        for address, (kind, value) in refs.items():
            actual = cell(sheet, address)
            wanted = cell(reference, address)
            assert actual is not None, f'Missing cell {index}!{address}'
            assert actual.find(X + 'f').text == wanted.find(X + 'f').text, f'Formula {index}!{address}'
            assert actual.get('t') == kind, f'Cache type {index}!{address}'
            if kind is None:
                assert float(actual.find(X + 'v').text) == float(value), f'Numeric cache {index}!{address}'
            else:
                assert actual.find(X + 'v').text == value, f'Typed cache {index}!{address}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write-expected', type=Path)
    args = parser.parse_args()
    if args.write_expected:
        for phase in ('recalculated', 'renamed'):
            parts = expected_parts(phase == 'renamed')
            verify(parts, phase == 'renamed')
            write_zip(args.write_expected / f'sheet-qualified-names-{phase}-expected.xlsx', parts)
        # Current independent rename oracle explicitly recalculates D10=2.
        # Historical 42-cell reports and their fixture remain untouched.
        from test_sheet_rename_oracle import authored
        from sheet_rename_oracle import verify as verify_rename
        parts = authored()
        verify_rename(parts)
        write_zip(args.write_expected / 'sheet-rename-qualified-expected.xlsx', parts)
        print(f'Wrote three independently authored expected fixtures to {args.write_expected}')
        return
    output = Path('build/fidelity-sheet-qualified-names')
    expected_files = {'source.xlsx', 'expected-recalculated.xlsx', 'expected-renamed.xlsx'} | {
        f'{phase}-{cycle}.xlsx'
        for phase in ('recalculated', 'renamed') for cycle in (1, 2, 3)
    }
    assert {p.name for p in output.glob('*.xlsx')} == expected_files, 'Exact nine-file cohort'
    assert read_zip(output / 'source.xlsx') == read_zip(SOURCE), 'Authored source changed'
    for phase in ('recalculated', 'renamed'):
        fixture = SOURCE.parent / f'sheet-qualified-names-{phase}-expected.xlsx'
        assert read_zip(output / f'expected-{phase}.xlsx') == read_zip(fixture), 'Authored expected fixture changed'
        assert read_zip(fixture) == expected_parts(phase == 'renamed'), 'Expected fixture does not reproduce'
        for cycle in (1, 2, 3):
            verify(read_zip(output / f'{phase}-{cycle}.xlsx'), phase == 'renamed')
    print('Qualified names: 120 typed caches, exact definitions/scopes, six save cycles, and two authored references passed.')


if __name__ == '__main__':
    main()
