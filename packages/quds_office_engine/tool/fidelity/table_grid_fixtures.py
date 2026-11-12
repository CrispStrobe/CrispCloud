#!/usr/bin/env python3
"""Deliberately author the expected native XML for table-grid scenarios.

Maintenance command only: normal validation reads committed expected files.
This uses the authored source and explicit Office XML operations; it never reads
Quds output or imports the Dart model. New text is prescribed as Arial 11pt,
black, unbold/unitalic, left aligned, 8pt after and 1.15 line spacing.
"""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
Q = '{' + W + '}'


def element(parent, name, **attributes):
    return ET.SubElement(parent, Q + name, {Q + key: str(value) for key, value in attributes.items()})


def set_width(cell, value):
    width = cell.find('w:tcPr/w:tcW', NS)
    width.set(Q + 'w', str(value))
    width.set(Q + 'type', 'dxa')


def set_fill(cell, fill):
    element(cell.find('w:tcPr', NS), 'shd', val='clear', fill=fill)


def replace_text(cell, text):
    for child in list(cell):
        if child.tag != Q + 'tcPr':
            cell.remove(child)
    paragraph = element(cell, 'p')
    properties = element(paragraph, 'pPr')
    element(properties, 'spacing', before=0, after=160, line=276, lineRule='auto')
    element(properties, 'ind', left=0, right=0)
    element(properties, 'jc', val='left')
    run = element(paragraph, 'r')
    properties = element(run, 'rPr')
    element(properties, 'rFonts', ascii='Arial', hAnsi='Arial', cs='Arial')
    element(properties, 'b', val=0)
    element(properties, 'i', val=0)
    element(properties, 'color', val='000000')
    element(properties, 'sz', val=22)
    value = element(run, 't')
    value.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    value.text = text


def split_first(row, width):
    cell = row.find('w:tc', NS)
    properties = cell.find('w:tcPr', NS)
    for name in ('gridSpan', 'vMerge'):
        for child in properties.findall('w:' + name, NS):
            properties.remove(child)
    set_width(cell, width)
    empty = deepcopy(cell)
    # New empty cells inherit paragraph/run formatting, never identities.
    for child in list(empty):
        if child.tag == Q + 'tcPr':
            continue
        if child.tag != Q + 'p':
            empty.remove(child)
            continue
        for inline in list(child):
            if inline.tag in (Q + 'pPr', Q + 'r'):
                if inline.tag == Q + 'r':
                    for item in list(inline):
                        if item.tag != Q + 'rPr':
                            inline.remove(item)
                    element(inline, 't').text = ''
            else:
                child.remove(inline)
    row.insert(list(row).index(cell) + 1, empty)


def expected_xml(phase):
    root = ET.fromstring((FIXTURES / 'table_grid_source.xml').read_bytes())
    outer = root.find('w:body/w:tbl', NS)
    rows = outer.findall('w:tr', NS)
    nested = outer.find('.//w:tbl', NS)
    nested_row = nested.find('w:tr', NS)
    set_fill(rows[0].find('w:tc', NS), 'DDEEFF')
    tail = rows[1].findall('w:tc', NS)[1]
    replace_text(tail, 'Edited middle right')
    set_width(tail, 1465)
    set_fill(nested_row.find('w:tc', NS), 'EEDDCC')
    replace_text(nested_row.findall('w:tc', NS)[1], 'Edited nested tail')
    if phase == 'replace':
        replace_text(rows[0].find('w:tc', NS), 'Replaced merged owner')
    elif phase == 'unmerge':
        split_first(rows[0], 1800)
        split_first(rows[1], 1800)
        split_first(nested_row, 600)
    elif phase != 'format':
        raise ValueError('Expected format, replace or unmerge')
    ET.register_namespace('w', W)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    for phase in ('format', 'replace', 'unmerge'):
        target = FIXTURES / f'table_grid_{phase}_expected.xml'
        target.write_bytes(expected_xml(phase) + b'\n')
        print(target.relative_to(ROOT))
