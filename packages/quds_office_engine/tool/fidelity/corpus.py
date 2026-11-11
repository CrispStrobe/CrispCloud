#!/usr/bin/env python3
"""Independent, deterministic OOXML fixtures and semantic/package oracles.

Uses only Python's standard library. Expected goldens come from authored XML,
never from Quds output. `seed` is an explicit reviewed-corpus maintenance action.
"""
import argparse
import struct
import zlib
import hashlib
import json
from pathlib import Path
import posixpath
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = {'w': W, 'r': R, 'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
def fixture_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + b''.join(bytes((35, 100, 170, 255) if (x+y)%2 else (245, 180, 50, 255)) for x in range(4)) for y in range(4))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')

PNG = fixture_png()

def rels(entries):
    return '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(
        f'<Relationship Id="{rid}" Type="{R}/{kind}" Target="{target}"' +
        (' TargetMode="External"' if external else '') + '/>'
        for rid, kind, target, external in entries) + '</Relationships>'

def word_parts(edited=False):
    title = 'Revised heading' if edited else 'Imported heading'
    body = 'Edited body' if edited else 'Body text'
    note = 'Edited footnote' if edited else 'Footnote text'
    width = 914400 if edited else 457200
    return {
        '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="png" ContentType="image/png"/>' + ''.join(
            f'<Override PartName="/word/{name}.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.{kind}+xml"/>'
            for name, kind in [('document', 'document.main'), ('styles', 'styles'), ('footnotes', 'footnotes'),
                               ('endnotes', 'endnotes'), ('header1', 'header'), ('footer1', 'footer'), ('numbering', 'numbering')]) +
        '<Override PartName="/customXml/item1.xml" ContentType="application/xml"/></Types>',
        '_rels/.rels': rels([('root', 'officeDocument', 'word/document.xml', False)]),
        'word/_rels/document.xml.rels': rels([
            ('s', 'styles', 'styles.xml', False), ('n', 'numbering', 'numbering.xml', False),
            ('fn', 'footnotes', 'footnotes.xml', False), ('en', 'endnotes', 'endnotes.xml', False),
            ('h', 'header', 'header1.xml', False), ('f', 'footer', 'footer1.xml', False),
            ('img', 'image', 'media/source.png', False), ('link', 'hyperlink', 'https://example.com/body', True)]),
        'word/document.xml': f'''<w:document xmlns:w="{W}" xmlns:r="{R}"
 xmlns:wp="{NS['wp']}" xmlns:a="{NS['a']}" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>
<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:outlineLvl w:val="0"/></w:pPr><w:r><w:t>{title}</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="BodyCustom"/><w:spacing w:before="0" w:after="160"/><w:jc w:val="left"/></w:pPr><w:r><w:rPr><w:b w:val="0"/><w:i w:val="0"/><w:color w:val="000000"/><w:sz w:val="22"/><w:highlight w:val="yellow"/></w:rPr><w:t>{body}</w:t></w:r><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteReference w:id="12"/></w:r><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:endnoteReference w:id="3"/></w:r></w:p>
<w:p><w:hyperlink r:id="link"><w:r><w:t>Body link</w:t></w:r></w:hyperlink></w:p>
<w:p><w:pPr><w:pStyle w:val="ListCustom"/></w:pPr><w:r><w:t>List item</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblW w:w="2000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Cell text</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:drawing><wp:inline><wp:extent cx="{width}" cy="457200"/><wp:docPr id="1" name="Logo" descr="Fixture image"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="Logo"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="img"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{width}" cy="457200"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
<w:sectPr><w:headerReference w:type="default" r:id="h"/><w:footerReference w:type="default" r:id="f"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/></w:sectPr>
</w:body></w:document>''',
        'word/styles.xml': f'''<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="BodyCustom"><w:name w:val="Body Custom"/><w:pPr><w:spacing w:before="240" w:after="200"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:i/><w:color w:val="FF0000"/><w:sz w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListCustom"><w:name w:val="List Custom"/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="5"/></w:numPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:style>
<w:style w:type="character" w:styleId="EmphasisCustom"><w:name w:val="Emphasis Custom"/><w:rPr><w:i/><w:lang w:val="de-DE"/></w:rPr></w:style>
<w:style w:type="table" w:styleId="TableCustom"><w:name w:val="Table Custom"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="8" w:color="123456"/></w:tblBorders></w:tblPr></w:style></w:styles>''',
        'word/numbering.xml': f'<w:numbering xmlns:w="{W}"><w:abstractNum w:abstractNumId="5"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum><w:num w:numId="5"><w:abstractNumId w:val="5"/></w:num></w:numbering>',
        'word/footnotes.xml': f'<w:footnotes xmlns:w="{W}" xmlns:r="{R}"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id="12"><w:p><w:r><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> {note}</w:t></w:r></w:p><w:p><w:hyperlink r:id="noteLink"><w:r><w:t>Note link</w:t></w:r></w:hyperlink></w:p></w:footnote></w:footnotes>',
        'word/_rels/footnotes.xml.rels': rels([('noteLink', 'hyperlink', 'https://example.com/note', True)]),
        'word/endnotes.xml': f'<w:endnotes xmlns:w="{W}"><w:endnote w:id="3"><w:p><w:r><w:endnoteRef/></w:r><w:r><w:t xml:space="preserve"> Endnote text</w:t></w:r></w:p></w:endnote></w:endnotes>',
        'word/header1.xml': f'<w:hdr xmlns:w="{W}" xmlns:r="{R}"><w:p><w:hyperlink r:id="headerLink"><w:r><w:t>Header link</w:t></w:r></w:hyperlink></w:p></w:hdr>',
        'word/_rels/header1.xml.rels': rels([('headerLink', 'hyperlink', 'https://example.com/header', True)]),
        'word/footer1.xml': f'<w:ftr xmlns:w="{W}"><w:p><w:r><w:t>Footer text</w:t></w:r></w:p></w:ftr>',
        'word/media/source.png': PNG,
        'customXml/item1.xml': '<audit xmlns="urn:crispcloud:fidelity">preserve opaque parts</audit>',
    }

def write_zip(parts, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, value in sorted(parts.items()):
            info = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, value.encode() if isinstance(value, str) else value)

def read_zip(path):
    with zipfile.ZipFile(path) as z:
        assert len(z.namelist()) == len(set(z.namelist())), 'duplicate ZIP entries'
        return {name: z.read(name) for name in z.namelist()}

def attrs(e):
    return {k.split('}')[-1]: v for k, v in e.attrib.items()} if e is not None else {}

def relationship_map(parts, owner):
    name = posixpath.join(posixpath.dirname(owner), '_rels', posixpath.basename(owner) + '.rels')
    if name not in parts:
        return {}
    return {e.attrib['Id']: e.attrib for e in ET.fromstring(parts[name])}

def links(parts, owner, root):
    rel = relationship_map(parts, owner)
    return [( ''.join(e.itertext()).strip(), rel.get(e.get(f'{{{R}}}id'), {}).get('Target', e.get(f'{{{W}}}anchor')))
            for e in root.findall('.//w:hyperlink', NS)]

def snapshot(parts):
    root = ET.fromstring(parts['word/document.xml'])
    ps = root.findall('./w:body/w:p', NS)
    notes = {}
    for kind in ('footnote', 'endnote'):
        owner = f'word/{kind}s.xml'
        tree = ET.fromstring(parts[owner])
        notes[kind] = [{'id': int(e.get(f'{{{W}}}id')), 'paragraphs': [''.join(p.itertext()).strip() for p in e.findall('w:p', NS)],
                        'links': links(parts, owner, e)} for e in tree if e.get(f'{{{W}}}type') is None]
    styles = ET.fromstring(parts['word/styles.xml'])
    image_rels = relationship_map(parts, 'word/document.xml')
    image_digests = []
    for blip in root.findall('.//a:blip', NS):
        rel = image_rels[blip.get(f'{{{R}}}embed')]
        target = posixpath.normpath(posixpath.join('word', rel['Target']))
        image_digests.append(hashlib.sha256(parts[target]).hexdigest())
    numbering = ET.fromstring(parts['word/numbering.xml'])
    referenced = {e.get(f'{{{W}}}val') for tree in (root, styles) for e in tree.findall('.//w:numId', NS)}
    abstract = {e.get(f'{{{W}}}abstractNumId'): e for e in numbering.findall('w:abstractNum', NS)}
    definitions = {}
    for num in numbering.findall('w:num', NS):
        num_id = num.get(f'{{{W}}}numId')
        if num_id in referenced:
            definition = abstract.get(attrs(num.find('w:abstractNumId', NS)).get('val'))
            definitions[num_id] = [{c.tag.split('}')[-1]: attrs(c) for c in lvl if c.tag.split('}')[-1] in ('start', 'numFmt', 'lvlText')} for lvl in definition.findall('w:lvl', NS)] if definition is not None else None
    stories = {}
    for kind in ('header', 'footer'):
        ref = root.find(f'.//w:{kind}Reference', NS)
        rel = image_rels[ref.get(f'{{{R}}}id')]
        owner = posixpath.normpath(posixpath.join('word', rel['Target']))
        stories[kind] = (owner, ET.fromstring(parts[owner]))
    return {
        'numbering': definitions,
        'text': [''.join(p.findall('.//w:t', NS)[i].text or '' for i in range(len(p.findall('.//w:t', NS)))) for p in ps if p.findall('.//w:t', NS)],
        'heading_levels': [attrs(p.find('w:pPr/w:outlineLvl', NS)) for p in ps if p.find('w:pPr/w:outlineLvl', NS) is not None],
        'references': {kind: [int(e.get(f'{{{W}}}id')) for e in root.findall(f'.//w:{kind}Reference', NS)] for kind in ('footnote', 'endnote')},
        'notes': notes,
        'links': links(parts, 'word/document.xml', root),
        'table_text': [''.join(e.itertext()).strip() for e in root.findall('.//w:tc', NS)],
        'image_extents': [attrs(e) for e in root.findall('.//wp:extent', NS)],
        'image_sha256': image_digests,
        'styles': {e.get(f'{{{W}}}styleId'): {'type': e.get(f'{{{W}}}type'),
                    'numId': attrs(e.find('w:pPr/w:numPr/w:numId', NS)), 'indent': attrs(e.find('w:pPr/w:ind', NS))}
                   for e in styles.findall('w:style', NS)},
        'header_links': links(parts, *stories['header']),
        'footer_text': ''.join(stories['footer'][1].itertext()).strip(),
        'opaque_sha256': hashlib.sha256(parts['customXml/item1.xml']).hexdigest(),
    }

PPR_ORDER = 'pStyle keepNext keepLines pageBreakBefore framePr widowControl numPr suppressLineNumbers pBdr shd tabs suppressAutoHyphens kinsoku wordWrap overflowPunct topLinePunct autoSpaceDE autoSpaceDN bidi adjustRightInd snapToGrid spacing ind contextualSpacing mirrorIndents suppressOverlap jc textDirection textAlignment textboxTightWrap outlineLvl divId cnfStyle rPr sectPr pPrChange'.split()
RPR_ORDER = 'rStyle rFonts b bCs i iCs caps smallCaps strike dstrike outline shadow emboss imprint noProof snapToGrid vanish webHidden color spacing w kern position sz szCs highlight u effect bdr shd fitText vertAlign rtl cs em lang eastAsianLayout specVanish oMath rPrChange'.split()

def validate(parts):
    errors = []
    for name, data in parts.items():
        if not name.endswith(('.xml', '.rels')):
            continue
        root = ET.fromstring(data)
        if name.endswith('.rels'):
            ids = [r.get('Id') for r in root]
            if len(ids) != len(set(ids)):
                errors.append(f'{name}: duplicate relationship ids')
            owner_dir = '' if name == '_rels/.rels' else posixpath.dirname(posixpath.dirname(name))
            for rel in root:
                if rel.get('TargetMode') != 'External':
                    target = posixpath.normpath(posixpath.join(owner_dir, rel.get('Target', ''))).lstrip('/')
                    if target not in parts:
                        errors.append(f'{name}: dangling target {target}')
            continue
        rel = relationship_map(parts, name)
        for e in root.iter():
            for attr in ('id', 'embed', 'link'):
                rid = e.get(f'{{{R}}}{attr}')
                if rid and rid not in rel:
                    errors.append(f'{name}: unresolved r:{attr}={rid}')
            local = e.tag.split('}')[-1]
            order = PPR_ORDER if local == 'pPr' else RPR_ORDER if local == 'rPr' else None
            if order:
                ranks = [order.index(c.tag.split('}')[-1]) for c in e if c.tag.split('}')[-1] in order]
                if ranks != sorted(ranks):
                    errors.append(f'{name}: invalid {local} child order')
        if name in ('word/footnotes.xml', 'word/endnotes.xml'):
            marker = 'footnoteRef' if 'footnotes' in name else 'endnoteRef'
            for note in root:
                if note.get(f'{{{W}}}type') is None and len(note.findall(f'.//w:{marker}', NS)) != 1:
                    errors.append(f'{name}: expected one body reference for note {note.get(f"{{{W}}}id")}')
    return errors

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['seed', 'verify', 'inspect'])
    p.add_argument('directory', nargs='?', type=Path, default=ROOT/'build/fidelity')
    args = p.parse_args()
    if args.command == 'seed':
        FIXTURES.mkdir(parents=True, exist_ok=True)
        for edited, label in [(False, 'imported'), (True, 'edited')]:
            parts = word_parts(edited)
            if not edited:
                write_zip(parts, FIXTURES/'word.docx')
            raw = {k: v.encode() if isinstance(v, str) else v for k, v in parts.items()}
            (FIXTURES/f'{label}.json').write_text(json.dumps(snapshot(raw), indent=2, ensure_ascii=False)+'\n')
        print('Seeded independently authored fixture and goldens; review the diff.')
        return
    if args.command == 'inspect':
        print(json.dumps(snapshot(read_zip(args.directory)), indent=2, ensure_ascii=False))
        return
    files = sorted(args.directory.glob('*.docx'))
    if not files:
        raise SystemExit(f'No exports found in {args.directory}')
    failures = []
    for path in files:
        parts = read_zip(path)
        errors = validate(parts)
        label = 'edited' if path.name.startswith('edited') else 'imported'
        expected = json.loads((FIXTURES/f'{label}.json').read_text())
        actual = json.loads(json.dumps(snapshot(parts)))
        for key in expected:
            if actual[key] != expected[key]:
                errors.append(f'{key}: expected {expected[key]!r}, got {actual[key]!r}')
        (path.with_suffix('.actual.json')).write_text(json.dumps(actual, indent=2, ensure_ascii=False)+'\n')
        failures.extend(f'{path.name}: {error}' for error in errors)
        print(f'{path.name}: {"FAIL" if errors else "PASS"}')
    report = {'exports': len(files), 'failures': failures}
    (args.directory/'oracle-report.json').write_text(json.dumps(report, indent=2)+'\n')
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f'All {len(files)} exports match independent goldens and package oracles.')

if __name__ == '__main__':
    main()
