#!/usr/bin/env python3
"""Independent authored goldens for the public DOCX/XLSX/PPTX step scripts.

Normal verification consumes actual script outputs and never refreshes goldens.
"""
import argparse
import hashlib
import json
from pathlib import Path
from xml.etree import ElementTree as E
from corpus import FIXTURES, NS, attrs, read_zip, validate, snapshot as word_snapshot
from native_oracle import target
from notes_oracle import pixels
W = '{' + NS['w'] + '}'
R = '{' + NS['r'] + '}'
A = '{' + NS['a'] + '}'
P = '{http://schemas.openxmlformats.org/presentationml/2006/main}'
X = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
C = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
EXPECTED = json.loads((FIXTURES/'scripts/expected.json').read_text())
REPLACEMENT = (2, 2, hashlib.sha256(bytes([11, 177, 59])*4).hexdigest())

def equal(actual, expected, label):
    assert actual == expected, f'{label}: expected {expected!r}, got {actual!r}'

def subset(actual, expected, label):
    equal({key: actual.get(key) for key in expected}, expected, label)

def verify_word(parts):
    expected = EXPECTED['word']
    snap = word_snapshot(parts)
    equal(snap['text'], expected['text'], 'body text/order')
    equal(snap['references'], expected['references'], 'note reference order/identity')
    equal({kind: {str(note['id']): note['paragraphs'] for note in notes}
           for kind, notes in snap['notes'].items()}, expected['notes'], 'note bodies')
    equal(snap['table_text'], expected['table'], 'table edit')
    equal(snap['image_extents'], [expected['extent']], 'picture geometry/count')
    root = E.fromstring(parts['word/document.xml'])
    paragraphs = root.findall(W+'body/'+W+'p')
    title = paragraphs[0]
    equal(attrs(title.find(W+'pPr/'+W+'outlineLvl')), {'val':str(expected['heading'])}, 'heading')
    ppr = title.find(W+'pPr')
    equal(attrs(ppr.find(W+'jc')).get('val'), 'center', 'alignment')
    subset(attrs(ppr.find(W+'spacing')), {'before':'0','after':'0','line':'360'}, 'spacing')
    assert ppr.find(W+'bidi') is not None, 'RTL paragraph flag lost'
    assert ppr.find(W+'keepLines') is not None, 'Keep-together flag lost'
    assert ppr.find(W+'pageBreakBefore') is not None, 'Page break lost'
    for run in title.findall(W+'r'):
        if run.find(W+'t') is None: continue
        props = run.find(W+'rPr')
        equal(attrs(props.find(W+'b')).get('val'), '0', 'explicit bold=false')
        equal(attrs(props.find(W+'color')).get('val'), '000000', 'direct black')
        equal(attrs(props.find(W+'sz')).get('val'), '22', 'direct 11pt')
        equal(attrs(props.find(W+'u')).get('val'), 'single', 'underline')
        equal(attrs(props.find(W+'rStyle')).get('val'), 'EmphasisCustom', 'character style')
    # Reference placement is semantic: note before title, footnote after "Script".
    sequence = []
    for run in title.findall(W+'r'):
        for child in run:
            if child.tag == W+'t': sequence.append(child.text or '')
            elif child.tag in [W+'footnoteReference', W+'endnoteReference']:
                sequence.append(child.tag.split('}')[-1]+':'+child.get(W+'id'))
    equal(sequence, ['endnoteReference:4','Script','footnoteReference:13',' headline'], 'caret note insertion')
    sections = root.findall('.//'+W+'sectPr')
    equal(len(sections),1,'section count')
    section = sections[0]
    subset(attrs(section.find(W+'pgSz')), expected['size'], 'page dimensions')
    subset(attrs(section.find(W+'pgMar')), expected['margins'], 'margins')
    subset(attrs(section.find(W+'cols')), expected['columns'], 'columns')
    for story in ['header','footer']:
        ref = section.find(W+story+'Reference')
        owner = target(parts,'word/document.xml',rid=ref.get(R+'id'))
        equal(''.join(E.fromstring(parts[owner]).itertext()), expected[story], story)
    for blip in root.findall('.//'+A+'blip'):
        owner = target(parts,'word/document.xml',rid=blip.get(R+'embed'))
        equal(pixels(parts[owner]),REPLACEMENT,'replacement picture pixels')
    equal([(''.join(link.itertext()), target(parts,'word/document.xml',rid=link.get(R+'id'))) for link in root.findall('.//'+W+'hyperlink')], [('Body','https://example.com/script'),(' link','https://example.com/script')], 'split hyperlink')
    styles = E.fromstring(parts['word/styles.xml'])
    emphasis = next(s for s in styles if s.get(W+'styleId')=='EmphasisCustom')
    equal(attrs(emphasis.find(W+'rPr/'+W+'color')).get('val'),'223344','style definition edit')
    note = E.fromstring(parts['word/footnotes.xml']).find(W+'footnote[@'+W+'id="12"]')
    for run in note.findall('.//'+W+'r'):
        # The exporter inserts a reference mark and its separate spacer. Only
        # authored note content belongs to the selected formatting range.
        if not (run.findtext(W+'t') or '').strip(): continue
        equal(attrs(run.find(W+'rPr/'+W+'color')).get('val'),'0077AA','rich note color')
        assert run.find(W+'rPr/'+W+'i') is not None, 'Rich note italic lost'
    list_paragraph = paragraphs[4]
    num = attrs(list_paragraph.find(W+'pPr/'+W+'numPr/'+W+'numId')).get('val')
    assert num is not None and num != '5', 'Scripted list collided with imported definition'
    equal(attrs(list_paragraph.find(W+'pPr/'+W+'numPr/'+W+'ilvl')).get('val'),'1','list level')
    numbering = E.fromstring(parts['word/numbering.xml'])
    instance = next(n for n in numbering.findall(W+'num') if n.get(W+'numId') == num)
    equal(attrs(instance.find(W+'lvlOverride[@'+W+'ilvl="1"]/'+W+'startOverride')).get('val'),'4','list restart')
    equal(parts['customXml/item1.xml'],read_zip(FIXTURES/'word.docx')['customXml/item1.xml'],'opaque XML')

def cell_value(parts, cell):
    value = cell.findtext(X+'v')
    typ = cell.get('t')
    if typ == 's':
        strings = E.fromstring(parts['xl/sharedStrings.xml'])
        value = ''.join(strings[int(value)].itertext())
    elif typ == 'inlineStr': value = ''.join(cell.find(X+'is').itertext())
    elif typ == 'b': value = value == '1'
    elif value is not None: value = float(value)
    return {'value':value, 'formula':cell.findtext(X+'f')}

def verify_sheet(parts):
    expected = EXPECTED['sheet']
    workbook = E.fromstring(parts['xl/workbook.xml'])
    sheets = workbook.find(X+'sheets')
    equal([s.get('name') for s in sheets],expected['names'],'worksheet order/names')
    owner = target(parts,'xl/workbook.xml',rid=sheets[1].get(R+'id'))
    sheet = E.fromstring(parts[owner])
    for ref, value in expected['cells'].items():
        equal(cell_value(parts,sheet.find('.//'+X+'c[@r="'+ref+'"]')),value,'cell '+ref)
    equal([m.get('ref') for m in sheet.findall(X+'mergeCells/'+X+'mergeCell')],expected['merges'],'merges')
    pane = sheet.find('.//'+X+'pane')
    equal(float(pane.get('ySplit')),expected['frozen_rows'],'freeze rows')
    equal(float(pane.get('xSplit')),expected['frozen_columns'],'freeze columns')
    equal(float(sheet.find(X+'sheetData/'+X+'row[@r="1"]').get('ht')),expected['row_height'],'row height')
    column = sheet.find(X+'cols/'+X+'col[@min="1"]')
    assert int(((256*float(column.get('width'))+int(128/7))/256)*7) == expected['column_width_pixels'], 'column width'
    cell = sheet.find('.//'+X+'c[@r="B2"]')
    styles = E.fromstring(parts['xl/styles.xml'])
    xf = styles.find(X+'cellXfs')[int(cell.get('s','0'))]
    font = styles.find(X+'fonts')[int(xf.get('fontId','0'))]
    assert font.find(X+'b') is not None, 'cell bold lost'
    equal(float(font.find(X+'sz').get('val')),15,'cell font size')
    equal(xf.find(X+'alignment').get('horizontal'),'center','cell alignment')
    equal(xf.get('numFmtId'),'2','imported numeric format')
    equal(font.find(X+'color').get('rgb')[-6:],'000000','cell font color')
    fill = styles.find(X+'fills')[int(xf.get('fillId','0'))]
    equal(fill.find(X+'patternFill/'+X+'fgColor').get('rgb')[-6:],'00FF00','cell fill')
    # A cell edit must update the existing chart data while keeping live formulas.
    drawing = target(parts,owner,'drawing')
    chart = target(parts,drawing,rid=E.fromstring(parts[drawing]).find('.//'+C+'chart').get(R+'id'))
    chart_root = E.fromstring(parts[chart])
    equal([float(v.text) for v in chart_root.findall('.//'+C+'val/'+C+'numRef/'+C+'numCache/'+C+'pt/'+C+'v')],[7,5],'live chart data')
    equal(chart_root.find('.//'+C+'val/'+C+'numRef/'+C+'f').text,"'Data'!$B$2:$B$3",'native absolute chart formula')
    equal(chart_root.find('.//'+C+'ser/'+C+'tx/'+C+'strRef/'+C+'f').text,"'Data'!B1",'native series-title formula')

def verify_slide(parts):
    expected = EXPECTED['slide']
    source = read_zip(FIXTURES/'native.pptx')
    presentation = E.fromstring(parts['ppt/presentation.xml'])
    slides = presentation.find(P+'sldIdLst')
    equal(len(slides),2,'slide count')
    for index, reference in enumerate(slides):
        owner = target(parts,'ppt/presentation.xml',rid=reference.get(R+'id'))
        slide = E.fromstring(parts[owner])
        title = slide.find(P+'cSld/'+P+'spTree/'+P+'sp')
        equal(''.join(t.text or '' for t in title.findall('.//'+A+'t')),expected['titles'][index],'slide title/order')
        equal(slide.get('show')=='0',expected['hidden'][index],'hidden slide')
        note_owner = target(parts,owner,'notesSlide')
        notes = E.fromstring(parts[note_owner])
        note_text = '\n'.join(''.join(t.text or '' for t in paragraph.findall('.//'+A+'t')) for paragraph in notes.findall('.//'+A+'p'))
        assert expected['notes'][index] in note_text, f'Speaker note lost: {note_text!r}'
        image = target(parts,owner,rid=slide.find('.//'+A+'blip').get(R+'embed'))
        expected_pixels = REPLACEMENT if index==1 else (6,4,hashlib.sha256(bytes([20,60,210])*24).hexdigest())
        equal(pixels(parts[image]),expected_pixels,'slide picture ownership/replacement')
        if index==1:
            transform = title.find(P+'spPr/'+A+'xfrm')
            equal(attrs(transform.find(A+'off')),expected['offset'],'shape position')
            equal(attrs(transform.find(A+'ext')),expected['extent'],'shape size')
            equal(transform.get('rot'),expected['rotation'],'shape rotation')
            props = title.find('.//'+A+'rPr')
            equal(props.get('sz'),expected['font_size'],'shape font')
            equal(props.find(A+'solidFill/'+A+'srgbClr').get('val'),expected['color'],'shape color')
            assert slide.find(P+'transition/'+P+expected['transition']) is not None, 'transition'
    for name in ['ppt/slideMasters/slideMaster1.xml','ppt/theme/theme1.xml']:
        equal(parts[name],source[name],'template preservation')

VERIFY = {'word':verify_word,'sheet':verify_sheet,'slide':verify_slide}
def verify_directory(directory):
    expected_paths = {f'{kind}/{name}.{extension}' for kind,extension in [('word','docx'),('sheet','xlsx'),('slide','pptx')]
                      for name in ['edited','roundtrip-1','roundtrip-2','roundtrip-3']}
    actual_paths = {str(p.relative_to(directory)) for p in directory.rglob('*') if p.suffix in ['.docx','.xlsx','.pptx']}
    equal(actual_paths,expected_paths,'exact scripted corpus inventory')
    failures = []
    for name in sorted(expected_paths):
        path = directory/name
        try:
            parts = read_zip(path)
            errors = validate(parts)
            assert not errors, errors
            VERIFY[path.parent.name](parts)
            print(f'{name}: PASS')
        except Exception as error:
            failures.append({'file':name,'error':str(error)})
            print(f'{name}: FAIL {error}')
    report = {'exports':len(expected_paths),'failures':failures}
    (directory/'oracle-report.json').write_text(json.dumps(report,indent=2)+'\n')
    assert not failures, failures
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path,nargs='?',default=Path('build/fidelity-scripted'))
    verify_directory(parser.parse_args().directory)
