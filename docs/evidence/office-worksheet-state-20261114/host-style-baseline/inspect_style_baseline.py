#!/usr/bin/env python3
"""Inspect original captured XLSX packages without using Quds or rewriting them."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import urljoin
import xml.etree.ElementTree as ET
import zipfile

S = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PR = 'http://schemas.openxmlformats.org/package/2006/relationships'
root = Path(sys.argv[1])
output = Path(sys.argv[2])
report = {'method': 'Read-only ZIP/XML inspection of exact captured uploads; no Quds import/export.', 'files': {}}
for path in sorted(root.glob('*.xlsx')):
    data = path.read_bytes()
    item = {'sha256': hashlib.sha256(data).hexdigest(), 'sheets': {}}
    with zipfile.ZipFile(path) as archive:
        def part(name):
            return ET.fromstring(archive.read(name))
        styles = part('xl/styles.xml')
        xfs = list(styles.find(f'{{{S}}}cellXfs'))
        fonts = list(styles.find(f'{{{S}}}fonts'))
        fills = list(styles.find(f'{{{S}}}fills'))
        relationships = {entry.attrib['Id']: entry.attrib['Target']
                         for entry in part('xl/_rels/workbook.xml.rels')}
        for sheet in part('xl/workbook.xml').findall(f'{{{S}}}sheets/{{{S}}}sheet'):
            sheet_path = urljoin('xl/workbook.xml', relationships[sheet.attrib[f'{{{R}}}id']]).lstrip('/')
            cells = {}
            for cell in part(sheet_path).findall(f'.//{{{S}}}c'):
                if cell.attrib['r'] not in ('A1', 'B1', 'C1', 'D1'):
                    continue
                style = xfs[int(cell.attrib.get('s', 0))]
                font = fonts[int(style.attrib['fontId'])]
                fill = fills[int(style.attrib['fillId'])]
                bold = font.find(f'{{{S}}}b')
                color = font.find(f'{{{S}}}color')
                cells[cell.attrib['r']] = {
                    'style_attribute': cell.attrib.get('s'),
                    'bold': bold is not None and bold.attrib.get('val', '1').lower() in ('1', 'true', 'on'),
                    'font_color': dict(color.attrib) if color is not None else None,
                    'fill_xml': ET.tostring(fill, encoding='unicode'),
                }
            item['sheets'][sheet.attrib['name']] = cells
    report['files'][path.name] = item
source = report['files']['source.xlsx']['sheets']
changes = {}
for name, item in report['files'].items():
    if name == 'source.xlsx':
        continue
    differences = {}
    for sheet, cells in item['sheets'].items():
        for address, fields in cells.items():
            delta = {field: {'source': source[sheet][address][field], 'saved': value}
                     for field, value in fields.items() if value != source[sheet][address][field]}
            if delta:
                differences[f'{sheet}!{address}'] = delta
    changes[name] = differences
report['differences_from_authored_source'] = changes
output.write_text(json.dumps(report, indent=2) + '\n')
for name, differences in changes.items():
    print(name)
    for address, delta in differences.items():
        print(' ', address, ', '.join(delta))
