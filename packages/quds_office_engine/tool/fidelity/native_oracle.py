"""ZIP/XML and decoded-pixel oracles for independently produced XLSX/PPTX."""
import hashlib
import json
from pathlib import Path
import posixpath
from xml.etree import ElementTree as E
from corpus import read_zip, relationship_map, validate
from notes_oracle import pixels
X='{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
P='{http://schemas.openxmlformats.org/presentationml/2006/main}'
A='{http://schemas.openxmlformats.org/drawingml/2006/main}'
C='{http://schemas.openxmlformats.org/drawingml/2006/chart}'
R='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'

def target(parts,owner,kind=None,rid=None):
    rels=relationship_map(parts,owner)
    rel=rels[rid] if rid else next(r for r in rels.values() if r['Type'].endswith('/'+kind))
    if rel.get('TargetMode')=='External': return rel['Target']
    return posixpath.normpath(posixpath.join(posixpath.dirname(owner),rel['Target'])).lstrip('/')

def sheet_style(parts,cell_ref):
    root=E.fromstring(parts['xl/worksheets/sheet1.xml'])
    cell=root.find(f'.//{X}c[@r="{cell_ref}"]')
    styles=E.fromstring(parts['xl/styles.xml'])
    xf=styles.find(X+'cellXfs')[int(cell.get('s','0'))]
    font=styles.find(X+'fonts')[int(xf.get('fontId','0'))]
    border=styles.find(X+'borders')[int(xf.get('borderId','0'))]
    return cell,xf,font,border

def verify_sheet_schema(parts):
    # Open XML SDK CT_Font order; preserve names, borders and number formats
    # while repairing source producer order and modified font records.
    order = 'b i strike condense extend outline shadow u vertAlign sz color name family charset scheme'.split()
    styles = E.fromstring(parts['xl/styles.xml']) if 'xl/styles.xml' in parts else None
    for font in ([] if styles is None else styles.find(X+'fonts')):
        ranks = [order.index(e.tag[len(X):]) for e in font if e.tag[len(X):] in order]
        assert ranks == sorted(ranks), 'Font properties out of schema order'
    for name, data in parts.items():
        if name.startswith('xl/worksheets/') and name.endswith('.xml'):
            drawings = [r for r in relationship_map(parts, name).values() if r['Type'].endswith('/drawing')]
            assert len(drawings) <= 1, f'Duplicate drawing relationship: {name}'
        if name.startswith('xl/drawings/') and name.endswith('.xml'):
            ns = '{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}'
            for frame in E.fromstring(data).findall('.//'+ns+'graphicFrame'):
                assert frame.find(ns+'xfrm') is not None, name
        if name.startswith('xl/pivotTables/') and name.endswith('.xml'):
            assert R+'id' not in E.fromstring(data).attrib, name

def verify_sheet(parts,edited):
    cell,xf,font,border=sheet_style(parts,'A1')
    assert font.find(X+'name').get('val')=='Arial'
    assert font.find(X+'b') is not None and font.find(X+'sz').get('val')=='14'
    cell,xf,font,border=sheet_style(parts,'B2')
    assert xf.get('numFmtId')=='2', 'Lost 0.00 number format'
    assert border.find(X+'bottom').get('style')=='thin', 'Lost cell border'
    assert float(cell.find(X+'v').text)==(7 if edited else 2)
    assert (font.find(X+'b') is not None)==edited
    root=E.fromstring(parts['xl/worksheets/sheet1.xml'])
    link=root.find(X+'hyperlinks/'+X+'hyperlink')
    assert target(parts,'xl/worksheets/sheet1.xml',rid=link.get(R+'id'))=='https://example.com/north'
    drawing=target(parts,'xl/worksheets/sheet1.xml','drawing')
    chart=target(parts,drawing,rid=E.fromstring(parts[drawing]).find('.//'+C+'chart').get(R+'id'))
    ch=E.fromstring(parts[chart])
    values=[float(v.text) for v in ch.findall('.//'+C+'val/'+C+'numRef/'+C+'numCache/'+C+'pt/'+C+'v')]
    assert values==[7 if edited else 2,5], f'Chart values: {values}'
    assert ch.find('.//'+C+'val/'+C+'numRef/'+C+'f').text=="'Data'!B2:B3"
    pivot=target(parts,'xl/worksheets/sheet2.xml','pivotTable')
    assert E.fromstring(parts[pivot]).get('name')=='NativePivot'
    cache=target(parts,pivot,'pivotCacheDefinition')
    source=E.fromstring(parts[cache]).find(X+'cacheSource/'+X+'worksheetSource')
    assert source.attrib=={'ref':'A1:B3','sheet':'Data'}
    wb=E.fromstring(parts['xl/workbook.xml'])
    cache_ref=wb.find(X+'pivotCaches/'+X+'pivotCache')
    assert target(parts,'xl/workbook.xml',rid=cache_ref.get(R+'id'))==cache

def verify_slides(parts,edited):
    root=E.fromstring(parts['ppt/presentation.xml'])
    assert root.find(P+'notesSz') is not None
    source=read_zip(Path('test/fixtures/fidelity/native.pptx'))
    for name, data in parts.items():
        if name.startswith('ppt/charts/') and name.endswith('.xml'):
            chart = E.fromstring(data)
            for tag in ('axId', 'crossAx'):
                assert all(0 <= int(e.get('val')) <= 2147483647 for e in chart.iter(C+tag)), name
    for name in ['ppt/slideMasters/slideMaster1.xml','ppt/theme/theme1.xml']:
        assert parts[name]==source[name], f'Template changed: {name}'
    for index,s in enumerate(root.find(P+'sldIdLst')):
        owner=target(parts,'ppt/presentation.xml',rid=s.get(R+'id'))
        slide=E.fromstring(parts[owner])
        transition=slide.find(P+'transition')
        assert transition.get('dur') is None
        assert int(transition.get('{http://schemas.microsoft.com/office/powerpoint/2010/main}dur')) > 0
        for frame in slide.findall('.//'+P+'graphicFrame'):
            assert frame.find(P+'xfrm') is not None
            assert frame.find(A+'xfrm') is None
        text=''.join(t.text or '' for t in slide.findall('.//'+A+'t'))
        assert (f'Edited native slide {index+1}' if edited else f'Native slide {index+1}') in text
        image=target(parts,owner,rid=slide.find('.//'+A+'blip').get(R+'embed'))
        rgb=(210,30,40) if index==0 else (20,60,210)
        assert pixels(parts[image])==(6,4,hashlib.sha256(bytes(rgb)*24).hexdigest())
        chart=target(parts,owner,rid=slide.find('.//'+C+'chart').get(R+'id'))
        chart_root=E.fromstring(parts[chart])
        values=[float(v.text) for v in chart_root.findall('.//'+C+'val//'+C+'pt/'+C+'v')]
        assert values==[index+(10 if edited else 2),index+5]
        notes=target(parts,owner,'notesSlide')
        assert target(parts,notes,'slide')==owner
        assert target(parts,notes,'notesMaster') in parts
        expected=f'Edited speaker note {index+1}' if edited else f'Speaker note {index+1}'
        assert expected in ''.join(E.fromstring(parts[notes]).itertext())
        if edited:
            assert slide.find(P+'timing') is not None
            assert slide.find(P+'transition/'+P+'wipe') is not None

def main():
    folder=Path('build/fidelity-native'); files=sorted([*folder.glob('*.xlsx'),*folder.glob('*.pptx')])
    assert len(files)==15, f'Expected fifteen native/new pivot exports, got {len(files)}'
    failures=[]
    for path in files:
        try:
            parts=read_zip(path);errors=validate(parts);assert not errors, errors
            if path.suffix == '.xlsx': verify_sheet_schema(parts)
            if path.name.startswith('native-sheet'): verify_sheet(parts,'edited' in path.name)
            elif path.name.startswith('native-slides'): verify_slides(parts,'edited' in path.name)
            else:
                pivot=target(parts,'xl/worksheets/sheet1.xml','pivotTable')
                assert E.fromstring(parts[pivot]).get('name')=='CreatedPivot'
                assert target(parts,pivot,'pivotCacheDefinition') in parts
            print(f'{path.name}: PASS')
        except Exception as error:
            failures.append(f'{path.name}: {error}'); print(f'{path.name}: FAIL {error}')
    (folder/'oracle-report.json').write_text(json.dumps({'files':len(files),'failures':failures},indent=2)+'\n')
    if failures: raise SystemExit('\n'.join(failures))
if __name__=='__main__': main()
