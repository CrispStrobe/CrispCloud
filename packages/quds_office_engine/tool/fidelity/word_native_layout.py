#!/usr/bin/env python3
"""Explicit Word layout corpus and foreground-only visual qualification.

generate DIR [--font-map JSON]: create synthetic DOCX (never installs fonts).
word DIR: ask locally installed Microsoft Word to export only these fixtures.
reference DIR: freeze Word PDF page geometry/text and raster images (Poppler).
compare DIR --report JSON: compare actual WordCanvas page PNGs with Word.

Pillow is needed only for compare. Reference generation needs pdftotext and
pdftoppm. No native reference, empty corpus, missing page or changed geometry
can count as a pass. Ordinary test runs never invoke Word or replace references.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

FAMILIES = {
    'calibri': ('Calibri', '/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibri.ttf'),
    'aptos': ('Aptos', '/Applications/Microsoft Word.app/Contents/Resources/DFonts/Aptos.ttf'),
    'arial': ('Arial', '/System/Library/Fonts/Supplemental/Arial.ttf'),
    'times': ('Times New Roman', '/System/Library/Fonts/Supplemental/Times New Roman.ttf'),
}
NAME = re.compile(r'^[a-zA-Z0-9-]+$')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_cases(directory):
    cases = json.loads((directory / 'manifest.json').read_text())
    if not isinstance(cases, list) or not cases:
        raise ValueError('A nonempty, explicit corpus is required')
    names = set()
    for case in cases:
        name = case['name']
        if not NAME.fullmatch(name) or name in names:
            raise ValueError(f'Invalid or duplicate fixture name: {name}')
        names.add(name)
    return cases


def generate(directory, font_map):
    directory.mkdir(parents=True, exist_ok=True)
    fonts = json.loads(font_map.read_text()) if font_map else {}
    cases = []
    for key, (family, default) in FAMILIES.items():
        path = Path(fonts.get(family, default))
        if not path.is_file():
            raise FileNotFoundError(f'Required reference font: {path}')
        for rule, line in [('auto', 240), ('auto', 360), ('exact', 360), ('atLeast', 240)]:
            name = f'{key}-{rule}-{line}'
            text = '<w:br/>'.join(f'<w:t>Line {i:02d} AVATAR office German words.</w:t>' for i in range(1, 41))
            body = (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="{line}" w:lineRule="{rule}"/>'
                    '<w:widowControl w:val="0"/></w:pPr><w:r><w:rPr>'
                    f'<w:rFonts w:ascii="{family}" w:hAnsi="{family}"/><w:sz w:val="24"/></w:rPr>{text}'
                    '</w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                    '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/>'
                    '</w:sectPr>')
            parts = {
                '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
                '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
                'word/document.xml': f'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{body}</w:body></w:document>',
            }
            with ZipFile(directory / f'{name}.docx', 'w') as archive:
                for part, xml in parts.items():
                    entry = ZipInfo(part, date_time=(2026, 1, 1, 0, 0, 0))
                    entry.compress_type = ZIP_DEFLATED
                    archive.writestr(entry, xml)
            cases.append({'name': name, 'font': str(path.resolve()), 'family': family,
                          'rule': rule, 'line': line, 'fontSha256': digest(path)})
    (directory / 'manifest.json').write_text(json.dumps(cases, indent=2) + '\n')


def export_word(directory):
    for case in read_cases(directory):
        source = directory / f"{case['name']}.docx"
        target = directory / f"{case['name']}-word.pdf"
        # JSON string quoting is also valid for these AppleScript string values.
        source_arg, target_arg = json.dumps(str(source)), json.dumps(str(target))
        name_arg = json.dumps(source.name)
        script = f'''with timeout of 45 seconds
 tell application id "com.microsoft.Word"
 open file name {source_arg} add to recent files false repair false
 repeat 80 times
  if (name of every document) contains {name_arg} then exit repeat
  delay 0.25
 end repeat
 save as document {name_arg} file name {target_arg} file format format PDF add to recent files false
 return version
 end tell
end timeout'''
        result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, timeout=55)
        if result.returncode:
            raise RuntimeError(f"Word export failed for {case['name']}: {result.stderr.strip()}")
        if not target.is_file():
            raise FileNotFoundError(target)
        print(case['name'], result.stdout.strip(), flush=True)


def raster(pdf, prefix):
    subprocess.run([shutil.which('pdftoppm') or 'pdftoppm', '-r', '144', '-png', str(pdf), str(prefix)],
                   check=True, capture_output=True, timeout=60)


def freeze_reference(directory):
    cases = []
    for case in read_cases(directory):
        name = case['name']
        pdf = directory / f'{name}-word.pdf'
        result = subprocess.run([shutil.which('pdftotext') or 'pdftotext', '-bbox-layout', str(pdf), '-'],
                                check=True, capture_output=True, timeout=30)
        root = ET.fromstring(result.stdout)
        pages = []
        for page in root.findall('.//{*}page'):
            lines = []
            for line in page.findall('.//{*}line'):
                lines.append({'text': ' '.join(w.text or '' for w in line.findall('{*}word')),
                              'y': float(line.attrib['yMin'])})
            if not lines:
                raise ValueError(f'This text corpus must not have blank reference pages: {name}')
            pages.append({'width': float(page.attrib['width']), 'height': float(page.attrib['height']), 'lines': lines})
        if not pages:
            raise ValueError(f'No Word pages for {name}')
        raster(pdf, directory / f'{name}-word')
        cases.append({'name': name, 'docxSha256': digest(directory / f'{name}.docx'),
                      'wordPdfSha256': digest(pdf), 'fontSha256': digest(case['font']),
                      'pages': pages, 'pagePngSha256': [digest(directory / f'{name}-word-{i + 1}.png') for i in range(len(pages))]})
    (directory / 'word-reference.json').write_text(json.dumps({'renderer': 'Microsoft Word', 'rasterDpi': 144, 'cases': cases}, indent=2) + '\n')


def ink_score(reference, candidate):
    from PIL import ImageChops, ImageFilter
    if reference.size != candidate.size:
        raise ValueError('Page pixel geometry differs')
    # Only the 1.5 pt page outline is UI chrome; every document ink pixel counts.
    rect = (3, 3, reference.width - 3, reference.height - 3)
    a = reference.convert('L').crop(rect).point(lambda p: 255 if p < 200 else 0)
    b = candidate.convert('L').crop(rect).point(lambda p: 255 if p < 200 else 0)
    def count(image):
        return sum(image.histogram()[1:])
    na, nb = count(a), count(b)
    if not na or not nb:
        raise ValueError('Empty or missing text cannot qualify')
    precision = count(ImageChops.multiply(b, a.filter(ImageFilter.MaxFilter(3)))) / nb
    recall = count(ImageChops.multiply(a, b.filter(ImageFilter.MaxFilter(3)))) / na
    return {'precision': precision, 'recall': recall,
            'f1': 2 * precision * recall / (precision + recall) if precision + recall else 0}


def compare(directory):
    from PIL import Image
    manifest = read_cases(directory)
    references = json.loads((directory / 'word-reference.json').read_text())['cases']
    candidates = json.loads((directory / 'flutter-layout.json').read_text())
    names = [c['name'] for c in manifest]
    if [r['name'] for r in references] != names or [c['name'] for c in candidates] != names:
        raise ValueError('Reference, candidate and corpus inventories must agree exactly')
    results = []
    for entry, reference, candidate in zip(manifest, references, candidates):
        name = entry['name']
        if digest(directory / f'{name}.docx') != reference['docxSha256']:
            raise ValueError(f'Changed source fixture: {name}')
        if candidate['referenceFontSha256'] != reference['fontSha256']:
            raise ValueError(f'Changed reference font bytes: {name}')
        expected_files = {f'{name}-flutter-{i + 1}.png' for i in range(len(candidate['pages']))}
        actual_files = {p.name for p in directory.glob(f'{name}-flutter-*.png')}
        if actual_files != expected_files:
            raise ValueError(f'Candidate page file inventory differs: {name}')
        pages = []
        counts_match = len(reference['pages']) == len(candidate['pages'])
        for i, page in enumerate(reference['pages']):
            native = directory / f'{name}-word-{i + 1}.png'
            actual = directory / f'{name}-flutter-{i + 1}.png'
            if digest(native) != reference['pagePngSha256'][i]:
                raise ValueError(f'Changed Word reference page: {native.name}')
            with Image.open(native) as a, Image.open(actual) as b:
                score = ink_score(a, b)
                expected_pixels = (round(page['width'] * 2), round(page['height'] * 2))
                if a.size != expected_pixels:
                    raise ValueError(f'Wrong reference raster size: {name}')
            cp = candidate['pages'][i] if i < len(candidate['pages']) else None
            text_matches = cp is not None and [l['text'].strip() for l in cp['lines']] == [l['text'] for l in page['lines']]
            geometry_matches = cp is not None and cp['width'] == page['width'] and cp['height'] == page['height']
            pages.append({'page': i + 1, **score, 'textMatches': text_matches,
                          'geometryMatches': geometry_matches,
                          'passed': score['f1'] > .95 and text_matches and geometry_matches and counts_match})
        results.append({'name': name, 'requestedFamily': candidate['requestedFamily'],
                        'resolvedFamily': candidate['resolvedFamily'], 'pageCountsMatch': counts_match,
                        'pages': pages, 'passed': all(p['passed'] for p in pages)})
    return {'metric': 'foreground ink F1; threshold <200; 144 DPI; fixed 1px/0.5pt matching tolerance',
            'requiredF1StrictlyGreaterThan': .95, 'cases': results,
            'passedPages': sum(p['passed'] for r in results for p in r['pages']),
            'totalPages': sum(len(r['pages']) for r in results),
            'passed': all(r['passed'] for r in results)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['generate', 'word', 'reference', 'compare'])
    parser.add_argument('directory', type=Path)
    parser.add_argument('--font-map', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    if args.command == 'generate':
        generate(directory, args.font_map)
    elif args.command == 'word':
        export_word(directory)
    elif args.command == 'reference':
        freeze_reference(directory)
    else:
        report = compare(directory)
        output = json.dumps(report, indent=2) + '\n'
        if args.report:
            args.report.write_text(output)
        else:
            print(output, end='')
        raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
