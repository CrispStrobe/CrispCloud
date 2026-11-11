#!/usr/bin/env python3
"""Independent XLSX/PPTX ZIP/XML oracles with authored expected values."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from corpus import read_zip, validate, attrs

X = {'x': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
P = {'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
     'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}

def snapshot(parts, kind):
    if kind == '.xlsx':
        root = ET.fromstring(parts['xl/worksheets/sheet1.xml'])
        strings = []
        if 'xl/sharedStrings.xml' in parts:
            strings = [''.join(si.itertext()) for si in ET.fromstring(parts['xl/sharedStrings.xml'])]
        cells = {}
        for cell in root.findall('.//x:c', X):
            ref = cell.get('r')
            if ref not in ['A1', 'B1', 'C1', 'D1']: continue
            value = cell.findtext('x:v', namespaces=X)
            typ = cell.get('t')
            if typ == 's': value = strings[int(value)]
            elif typ == 'inlineStr': value = ''.join(cell.find('x:is', X).itertext())
            elif typ == 'b': value = value == '1'
            elif value is not None: value = float(value)
            cells[ref] = {'value': value, 'formula': cell.findtext('x:f', namespaces=X)}
        return {'cells': cells, 'merges': [m.get('ref') for m in root.findall('.//x:mergeCell', X)],
                'frozen_rows': float(attrs(root.find('.//x:pane', X)).get('ySplit', 0))}
    root = ET.fromstring(parts['ppt/slides/slide1.xml'])
    shapes = []
    for shape in root.findall('.//p:sp', P):
        transform = shape.find('p:spPr/a:xfrm', P)
        shapes.append({'text': ''.join(t.text or '' for t in shape.findall('.//a:t', P)),
                       'offset': attrs(transform.find('a:off', P)),
                       'extent': attrs(transform.find('a:ext', P))})
    return {'shapes': shapes}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=Path('build/fidelity'))
    args = parser.parse_args()
    failures = []
    paths = sorted([*args.directory.glob('*.xlsx'), *args.directory.glob('*.pptx')])
    if len(paths) != 12: raise SystemExit(f'Expected 12 cross-format exports, found {len(paths)}')
    for path in paths:
        parts = read_zip(path)
        actual = snapshot(parts, path.suffix)
        label = 'edited' if '-edited-' in path.name else 'imported'
        kind = 'sheet' if path.suffix == '.xlsx' else 'slide'
        golden = Path(__file__).resolve().parents[2]/f'test/fixtures/fidelity/{kind}_{label}.json'
        expected = json.loads(golden.read_text())
        errors = validate(parts)
        if actual != expected: errors.append(f'expected {expected!r}, got {actual!r}')
        failures.extend(f'{path.name}: {e}' for e in errors)
        path.with_suffix('.actual.json').write_text(json.dumps(actual, indent=2)+'\n')
        print(f'{path.name}: {"FAIL" if errors else "PASS"}')
    (args.directory/'cross-oracle-report.json').write_text(json.dumps({'exports':len(paths), 'failures':failures},indent=2)+'\n')
    if failures: raise SystemExit('\n'.join(failures))

if __name__ == '__main__': main()
