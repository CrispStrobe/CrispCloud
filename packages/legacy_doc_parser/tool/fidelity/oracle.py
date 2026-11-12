#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independent package, text, and layout measurements. Never rewrites goldens.

Only stdlib is required. Source paths and expectations come from reviewed corpus
metadata, not from the Dart converter. External relationships are inspected as
strings; this module never follows them or executes document content.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
NS = {'w': W, 'r': R, 'v': 'urn:schemas-microsoft-com:vml',
      'w15': 'http://schemas.microsoft.com/office/word/2012/wordml'}
MAX_BYTES = 64 * 1024 * 1024


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_package(path):
    parts = {}
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) > 4096 or sum(e.file_size for e in entries) > MAX_BYTES:
            raise ValueError('Package exceeds oracle limits')
        for entry in entries:
            name = entry.filename
            if entry.is_dir():
                continue
            if (name in parts or name.startswith('/') or '\\' in name or
                    any(p in ('..', '.', '') for p in name.split('/'))):
                raise ValueError('Duplicate or unsafe package part')
            data = archive.read(entry)
            if name.endswith(('.xml', '.rels')):
                if re.search(br'<!\s*(DOCTYPE|ENTITY)', data, re.I):
                    raise ValueError('DTD/entity declarations are not allowed')
                ET.fromstring(data)
            parts[name] = data
    return parts


def relationships(parts, owner):
    directory, name = posixpath.split(owner)
    relpath = posixpath.join(directory, '_rels', name + '.rels') if owner else '_rels/.rels'
    if relpath not in parts:
        return []
    result, ids = [], set()
    for element in ET.fromstring(parts[relpath]):
        attrs = element.attrib
        rid = attrs.get('Id')
        if not rid or rid in ids:
            raise ValueError('Missing or duplicate relationship id')
        ids.add(rid)
        external = attrs.get('TargetMode') == 'External'
        target = attrs.get('Target', '')
        if not external:
            target = posixpath.normpath(posixpath.join(directory, target.lstrip('/')) if not target.startswith('/') else target[1:])
            if target.startswith('../') or target not in parts:
                raise ValueError(f'Unresolved relationship: {owner}: {target}')
        result.append({'id': rid, 'type': attrs.get('Type', '').split('/')[-1],
                       'target': target, 'external': external})
    return result


def text_content(node, *, deleted=False):
    result = []
    for child in node.iter():
        kind = child.tag.rsplit('}', 1)[-1]
        if child.tag == f'{{{W}}}t' or (deleted and child.tag == f'{{{W}}}delText'):
            result.append(child.text or '')
        elif child.tag == f'{{{W}}}tab':
            result.append('\t')
        elif child.tag == f'{{{W}}}br':
            result.append({'page': '\f', 'column': '\x0e'}.get(child.get(f'{{{W}}}type'), '\n'))
        elif child.tag == f'{{{W}}}cr':
            result.append('\n')
        elif kind == 'p' and result:
            result.append('\n')
    return ''.join(result).strip()


def local_attrs(node):
    return {key.rsplit('}', 1)[-1]: value for key, value in sorted(node.attrib.items())}


def snapshot(path):
    """Describe every reachable story; ids/part paths need not be unchanged."""
    parts = read_package(path)
    roots = [rel for rel in relationships(parts, '') if rel['type'] == 'officeDocument' and not rel['external']]
    if len(roots) != 1:
        raise ValueError('Expected one internal officeDocument relationship')
    main = roots[0]['target']
    queue, seen, stories, links = [(main, 'main')], set(), [], []
    story_types = {'header', 'footer', 'footnotes', 'endnotes', 'comments'}
    counts = Counter()
    media = []
    while queue:
        owner, kind = queue.pop(0)
        if owner in seen:
            continue
        seen.add(owner)
        tree = ET.fromstring(parts[owner])
        stories.append({'kind': kind, 'text': text_content(tree),
                        'textWithDeletions': text_content(tree, deleted=True)})
        for tag in ('tbl', 'tr', 'tc', 'drawing', 'pict', 'txbxContent', 'footnote',
                    'endnote', 'comment', 'ins', 'del', 'moveFrom', 'moveTo',
                    'rPrChange', 'pPrChange', 'tblPrChange', 'trPrChange',
                    'tcPrChange', 'sectPrChange', 'numberingChange'):
            elements = list(tree.iter(f'{{{W}}}{tag}'))
            if tag in ('footnote', 'endnote'):
                elements = [e for e in elements if e.get(f'{{{W}}}type', 'normal') == 'normal']
            counts[tag] += len(elements)
        for node in tree.iter(f'{{{W}}}br'):
            counts['break:' + node.get(f'{{{W}}}type', 'textWrapping')] += 1
        for rel in relationships(parts, owner):
            if rel['external']:
                links.append({'kind': rel['type'], 'target': rel['target']})
            elif rel['type'] in story_types:
                queue.append((rel['target'], rel['type']))
            elif rel['type'] == 'image':
                media.append(hashlib.sha256(parts[rel['target']]).hexdigest())
            elif rel['type'] == 'commentsExtended':
                ext = ET.fromstring(parts[rel['target']])
                counts['commentThreads'] += sum(1 for e in ext if e.get('{'+NS['w15']+'}paraIdParent'))
    # Validate *all* relationships, including evidence and relocated stories.
    for name in parts:
        if name.endswith('.rels'):
            owner = '' if name == '_rels/.rels' else posixpath.join(posixpath.dirname(posixpath.dirname(name)), posixpath.basename(name)[:-5])
            relationships(parts, owner)
    tree = ET.fromstring(parts[main])
    sections = []
    for section in tree.iter(f'{{{W}}}sectPr'):
        sections.append({child.tag.rsplit('}', 1)[-1]: local_attrs(child)
                         for child in section if child.tag.rsplit('}', 1)[-1] not in ('headerReference', 'footerReference')})
    return {'stories': sorted(stories, key=lambda item: (item['kind'], item['text'])),
            'counts': dict(sorted(counts.items())), 'sections': sections,
            'imageDigests': sorted(media), 'externalLinks': sorted(links, key=str)}


def compare_semantics(reference, actual):
    """Report losses and changes, including a loss to zero. No tolerant pass."""
    differences = []
    for key in ('stories', 'sections', 'imageDigests', 'externalLinks'):
        if reference[key] != actual[key]:
            differences.append({'property': key, 'reference': reference[key], 'actual': actual[key]})
    for key in sorted(set(reference['counts']) | set(actual['counts'])):
        before, after = reference['counts'].get(key, 0), actual['counts'].get(key, 0)
        if before != after:
            differences.append({'property': 'counts.' + key, 'reference': before, 'actual': after})
    return differences


def bbox_snapshot(path):
    tree = ET.parse(path)
    pages = []
    for page in tree.iter():
        if page.tag.rsplit('}', 1)[-1] != 'page':
            continue
        words = []
        for word in page.iter():
            if word.tag.rsplit('}', 1)[-1] == 'word':
                words.append({'text': word.text or '', 'box': [float(word.get(k)) for k in ('xMin', 'yMin', 'xMax', 'yMax')]})
        pages.append({'size': [float(page.get('width')), float(page.get('height'))], 'words': words})
    if not pages:
        raise ValueError('Native renderer produced no pages')
    return pages


def compare_layout(reference, actual, tolerance_points=0.25):
    same_text = len(reference) == len(actual) and all(
        [w['text'] for w in a['words']] == [w['text'] for w in b['words']]
        for a, b in zip(reference, actual))
    max_drift = None
    if same_text:
        max_drift = max([0.0] + [abs(x-y) for a, b in zip(reference, actual)
                        for wa, wb in zip(a['words'], b['words'])
                        for x, y in zip(wa['box'], wb['box'])])
    dimensions_match = len(reference) == len(actual) and all(a['size'] == b['size'] for a, b in zip(reference, actual))
    return {'referencePages': len(reference), 'actualPages': len(actual),
            'pageDimensionsMatch': dimensions_match, 'pageTextMatches': same_text,
            'maximumWordDriftPoints': max_drift, 'tolerancePoints': tolerance_points,
            'matchesWithinTolerance': dimensions_match and same_text and max_drift is not None and max_drift <= tolerance_points}


def load_corpus():
    manifest = json.loads((ROOT / 'tool/fidelity/corpus.json').read_text())
    ids = set()
    for case in manifest['cases'] + manifest.get('reference_expectations', []):
        case_id = case.get('id', case['path'])
        if case_id in ids:
            raise ValueError('Duplicate corpus id')
        ids.add(case_id)
        path = ROOT / case['path']
        if '..' in PurePosixPath(case['path']).parts or not path.resolve().is_relative_to(ROOT):
            raise ValueError('Corpus path escapes repository')
        if digest(path) != case['sha256']:
            raise ValueError('Corpus source changed: ' + case_id)
    return manifest


if __name__ == '__main__':
    manifest = load_corpus()
    for case in manifest['cases']:
        if case['path'].endswith('.docx'):
            snapshot(ROOT / case['path'])
    print(f"Verified {len(manifest['cases'])} source hashes and OOXML package graphs")
