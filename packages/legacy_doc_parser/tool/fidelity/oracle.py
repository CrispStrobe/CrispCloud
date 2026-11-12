#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independent package, text, and layout measurements. Never rewrites goldens.

Only stdlib is required. Source paths and expectations come from reviewed corpus
metadata, not from the Dart converter. External relationships are inspected as
strings; this module never follows them or executes document content.

Structural findings retain explicit/derived numbering and stored property
trees; they are not an implementation of Word's conditional-style layout or
an assertion that two differing representations render differently. Native
render comparisons remain separate. No snapshots become automatic goldens.

Primary behavior references: ISO/IEC29500-3 AlternateContent/Choice/Fallback;
Microsoft OpenXML LevelRestart, LevelOverride and NumberingInstance docs;
MS-ODRAWXML WordprocessingML Drawing; Microsoft VML MSO-Next-Textbox docs.
"""
from collections import Counter, deque
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import zipfile
import xml.etree.ElementTree as ET

from structure import StructureOracle, content_nodes, run_text

ROOT = Path(__file__).resolve().parents[2]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
NS = {'w': W, 'r': R, 'v': 'urn:schemas-microsoft-com:vml',
      'w15': 'http://schemas.microsoft.com/office/word/2012/wordml',
      'w14': 'http://schemas.microsoft.com/office/word/2010/wordml',
      'wps': 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape',
      'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'mc': 'http://schemas.openxmlformats.org/markup-compatibility/2006',
      'w10': 'urn:schemas-microsoft-com:office:word'}
MAX_BYTES = 64 * 1024 * 1024
MAX_NODES = 250000
MAX_DEPTH = 128
# Namespace URIs, not a document's arbitrary prefix spelling, determine which
# AlternateContent branch the oracle understands. Never concatenate fallback
# and choice text; alternative availability is measured separately.
MC_SUPPORTED = set(NS.values()) | {
    'http://schemas.microsoft.com/office/word/2010/wordprocessingGroup',
    'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing',
    'http://schemas.microsoft.com/office/drawing/2010/main',
}
REVISION_TAGS = {
    'ins', 'del', 'moveFrom', 'moveTo', 'rPrChange', 'pPrChange',
    'tblPrChange', 'tblGridChange', 'trPrChange', 'tcPrChange', 'sectPrChange',
    'numberingChange', 'cellIns', 'cellDel', 'cellMerge',
    'moveFromRangeStart', 'moveFromRangeEnd', 'moveToRangeStart', 'moveToRangeEnd',
    'customXmlInsRangeStart', 'customXmlInsRangeEnd',
    'customXmlDelRangeStart', 'customXmlDelRangeEnd',
    'customXmlMoveFromRangeStart', 'customXmlMoveFromRangeEnd',
    'customXmlMoveToRangeStart', 'customXmlMoveToRangeEnd',
}
ON_OFF_PROPERTIES = {
    'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', 'strike', 'dstrike', 'vanish',
    'webHidden', 'outline', 'shadow', 'emboss', 'imprint', 'rtl', 'cs',
    'keepNext', 'keepLines', 'pageBreakBefore', 'widowControl', 'contextualSpacing',
    'snapToGrid', 'bidi', 'suppressLineNumbers', 'suppressAutoHyphens',
    'cantSplit', 'tblHeader', 'noWrap', 'tcFitText', 'isLgl',
}


def _local(tag):
    return tag.rsplit('}', 1)[-1]


def _qname(tag):
    for prefix, uri in NS.items():
        if tag.startswith('{' + uri + '}'):
            return prefix + ':' + _local(tag)
    return tag


def _xml(data):
    """Bounded parse plus deterministic MC projection and availability record."""
    if re.search(br'<!\s*(DOCTYPE|ENTITY)', data, re.I):
        raise ValueError('DTD/entity declarations are not allowed')
    bindings, pending, scopes, required = {}, [], [], {}
    count = 0
    parser = ET.iterparse(io.BytesIO(data), events=('start', 'end', 'start-ns'))
    for event, value in parser:
        if event == 'start-ns':
            pending.append(value)
        elif event == 'start':
            count += 1
            if count > MAX_NODES or len(scopes) >= MAX_DEPTH:
                raise ValueError('XML exceeds oracle structural limits')
            prior = []
            for prefix, uri in pending:
                prior.append((prefix, bindings.get(prefix)))
                bindings[prefix] = uri
            scopes.append(prior)
            pending.clear()
            if value.tag == '{' + NS['mc'] + '}Choice':
                prefixes = value.get('Requires', '').split()
                required[value] = [bindings.get(prefix, 'unbound:' + prefix) for prefix in prefixes]
        else:
            for prefix, previous in reversed(scopes.pop()):
                if previous is None:
                    bindings.pop(prefix, None)
                else:
                    bindings[prefix] = previous
    root = parser.root
    alternatives = []

    def project(node):
        for index in range(len(node) - 1, -1, -1):
            child = node[index]
            if child.tag != '{' + NS['mc'] + '}AlternateContent':
                project(child)
                continue
            choices = [c for c in child if c.tag == '{' + NS['mc'] + '}Choice']
            fallback = child.find('mc:Fallback', NS)
            selected = next((c for c in choices if required[c] and
                             set(required[c]) <= MC_SUPPORTED), fallback)
            alternatives.append({
                'choices': [sorted(required[c]) for c in choices],
                'fallbackAvailable': fallback is not None,
                'selected': 'none' if selected is None else 'fallback' if selected is fallback else 'choice',
                'selectedNamespaces': [] if selected is None or selected is fallback else sorted(required[selected]),
            })
            # ISO/IEC29500-3 fallback semantics: without an understood Choice
            # or Fallback, process as if AlternateContent were absent. Retain
            # that absence in the availability findings, never display it.
            if selected is not None:
                project(selected)
            node[index:index + 1] = [] if selected is None else list(selected)

    project(root)
    return root, sorted(alternatives, key=lambda item: json.dumps(item, sort_keys=True))


def _on_off(value, default=True):
    if value is None:
        return default
    if value in ('1', 'true', 'on'):
        return True
    if value in ('0', 'false', 'off'):
        return False
    return value  # An invalid token remains a finding, not a fabricated value.


def _child_value(node, name, default=None):
    child = node.find('w:' + name, NS) if node is not None else None
    return child.get('{' + W + '}val', default) if child is not None else default


def _integer(value, default=None):
    if value is None:
        return default
    if not re.fullmatch(r'-?\d{1,10}', str(value)):
        raise ValueError('Invalid or excessive OOXML integer in oracle')
    return int(value)


def _paragraph_identifier(value):
    if value is None:
        return None
    if not re.fullmatch(r'[0-9A-Fa-f]{8}', value):
        raise ValueError('Invalid comment paragraph id')
    return value.upper()


def _json_fingerprint(value):
    """Bound canonical measurements before sorting or returning large reports."""
    digest = hashlib.sha256()
    length = 0
    for chunk in json.JSONEncoder(sort_keys=True, ensure_ascii=False).iterencode(value):
        data = chunk.encode('utf-8')
        length += len(data)
        if length > MAX_BYTES:
            raise ValueError('Semantic snapshot exceeds oracle output limit')
        digest.update(data)
    return digest.hexdigest()


def _text_marker(text):
    return {'sha256': hashlib.sha256(text.encode('utf-8')).hexdigest(),
            'length': len(text), 'excerpt': text[:256]}


class _Context:
    """Package-local resolution, independent of the Dart parser/converter."""
    def __init__(self, parts, main):
        self.parts, self.main = parts, main
        self.trees, self.rels = {}, {}
        self.styles, self.abstracts, self.nums = {}, {}, {}
        self.style_cache, self.level_cache = {}, {}
        self.level_active, self.comment_extras = set(), {}
        self.comment_ids, self.default_styles = {}, {}
        self.document_defaults = None
        for rel in self.relationships(main):
            if rel['external']:
                continue
            if rel['type'] == 'commentsExtended':
                tree, _ = self.tree(rel['target'])
                for node in tree.findall('w15:commentEx', NS):
                    identifier = _paragraph_identifier(node.get('{' + NS['w15'] + '}paraId'))
                    if not identifier or identifier in self.comment_extras:
                        raise ValueError('Missing or duplicate extended-comment paragraph id')
                    self.comment_extras[identifier] = node
            if rel['type'] == 'comments':
                tree, _ = self.tree(rel['target'])
                for node in tree.findall('w:comment', NS):
                    identifier = _integer(node.get('{' + W + '}id'))
                    if identifier is None or identifier in self.comment_ids:
                        raise ValueError('Missing or duplicate comment identity')
                    self.comment_ids[identifier] = len(self.comment_ids)
            if rel['type'] not in ('styles', 'numbering'):
                continue
            tree, _ = self.tree(rel['target'])
            targets = [('style', 'styleId', self.styles)] if rel['type'] == 'styles' else [
                ('abstractNum', 'abstractNumId', self.abstracts), ('num', 'numId', self.nums)]
            for tag, attr, target in targets:
                for node in tree.findall('w:' + tag, NS):
                    identifier = node.get('{' + W + '}' + attr)
                    if identifier is None or identifier in target or len(target) >= 4096:
                        raise ValueError('Missing, duplicate or excessive style/numbering identity')
                    target[identifier] = node
                    if tag == 'style' and _on_off(node.get('{' + W + '}default'), False) is True:
                        kind = node.get('{' + W + '}type')
                        if kind not in ('paragraph', 'character', 'table', 'numbering') or kind in self.default_styles:
                            raise ValueError('Invalid or duplicate default style type')
                        self.default_styles[kind] = identifier
            if rel['type'] == 'styles':
                self.document_defaults = tree.find('w:docDefaults', NS)

    def tree(self, owner):
        if owner not in self.trees:
            self.trees[owner] = _xml(self.parts[owner])
        return self.trees[owner]

    def relationships(self, owner):
        if owner not in self.rels:
            self.rels[owner] = relationships(self.parts, owner)
        return self.rels[owner]

    def style_chain(self, identifier):
        chain, seen = [], set()
        while identifier is not None:
            if identifier in seen or len(seen) >= 64:
                raise ValueError('Cyclic or excessive style inheritance')
            seen.add(identifier)
            node = self.styles.get(identifier)
            if node is None:
                break
            chain.append(node)
            identifier = _child_value(node, 'basedOn')
        return list(reversed(chain))

    def style(self, identifier, active=()):
        if identifier in active or len(active) >= 64:
            raise ValueError('Cyclic style-property reference')
        if identifier in self.style_cache:
            return self.style_cache[identifier]
        if identifier not in self.styles:
            return {'unresolvedStyle': identifier}
        result = []
        for style in self.style_chain(identifier):
            result.append({
                'type': style.get('{' + W + '}type'),
                'properties': [self.property(child, active=active + (identifier,))
                               for child in style if _local(child.tag) in
                               ('pPr', 'rPr', 'tblPr', 'trPr', 'tcPr', 'tblStylePr')],
            })
        self.style_cache[identifier] = result
        return result

    def property(self, node, *, active=(), current=False):
        if node is None:
            return None
        name = _local(node.tag)
        attrs = {_qname(key): value for key, value in sorted(node.attrib.items())
                 if not _local(key).startswith('rsid') and
                 key not in ('{' + NS['w14'] + '}paraId', '{' + NS['w14'] + '}textId') and
                 not (name in REVISION_TAGS and key == '{' + W + '}id')}
        # Target identities are measured separately against the referenced
        # story content. A relationship-id rename is not a layout change.
        if node.tag in ('{' + W + '}headerReference', '{' + W + '}footerReference'):
            attrs.pop('r:id', None)
        if node.tag in ('{' + W + '}pStyle', '{' + W + '}rStyle', '{' + W + '}tblStyle'):
            return {'tag': _qname(node.tag), 'resolvedStyle': self.style(_child_value_parent(node), active)}
        if node.tag == '{' + W + '}numId':
            identifier = node.get('{' + W + '}val')
            return {'tag': 'w:numId', 'disabled': identifier == '0',
                    'levels': [] if identifier == '0' else self.numbering_profile(identifier)}
        if node.tag.startswith('{' + W + '}') and name in ON_OFF_PROPERTIES:
            attrs['w:val'] = _on_off(node.get('{' + W + '}val'))
        return {'tag': _qname(node.tag), 'attributes': attrs,
                'text': node.text if node.text and node.text.strip() else None,
                'children': [self.property(child, active=active, current=current)
                             for child in node if not (current and _local(child.tag) in REVISION_TAGS)]}

    def numbering_profile(self, identifier):
        if identifier not in self.nums:
            return {'unresolvedNumbering': identifier}
        return [self.level(identifier, level) for level in range(9)
                if self.level(identifier, level) is not None]

    def level(self, identifier, level, active=()):
        key = (identifier, level)
        if key in active or len(active) >= 32:
            raise ValueError('Cyclic numbering style link')
        if key in self.level_cache:
            return self.level_cache[key]
        if key in self.level_active:
            raise ValueError('Cyclic numbering property reference')
        concrete = self.nums.get(identifier)
        if concrete is None:
            return None
        abstract = self.abstracts.get(_child_value(concrete, 'abstractNumId'))
        if abstract is None:
            return None
        self.level_active.add(key)
        base = None
        style_link = _child_value(abstract, 'numStyleLink')
        if style_link is not None:
            linked = self.paragraph_numbering(None, style_link)
            if linked is not None:
                base = self.level(linked[0], level, active + (key,))
        selected = next((node for node in abstract.findall('w:lvl', NS)
                         if _integer(node.get('{' + W + '}ilvl')) == level), None)
        override = next((node for node in concrete.findall('w:lvlOverride', NS)
                         if _integer(node.get('{' + W + '}ilvl')) == level), None)
        if override is not None and override.find('w:lvl', NS) is not None:
            selected = override.find('w:lvl', NS)
        if selected is not None:
            restart = _integer(_child_value(selected, 'lvlRestart'))
            base = {
                'level': level, 'start': _integer(_child_value(selected, 'start'), 0),
                'format': _child_value(selected, 'numFmt', 'decimal'),
                'template': _child_value(selected, 'lvlText'),
                'suffix': _child_value(selected, 'suff', 'tab'),
                'restartAfterLevel': (None if restart == 0 else
                                      restart - 1 if restart is not None and 0 < restart <= level else
                                      level - 1 if level else None),
                'properties': [self.property(child) for child in selected
                               if _local(child.tag) not in ('start', 'lvlRestart', 'numFmt', 'lvlText', 'suff', 'pStyle')],
            }
        if base is not None and override is not None:
            start = _child_value(override, 'startOverride')
            if start is not None:
                base = {**base, 'start': _integer(start)}
        self.level_cache[key] = base
        self.level_active.remove(key)
        return base

    def paragraph_numbering(self, properties, style_id=None):
        style_id = style_id or _child_value(properties, 'pStyle')
        values = {}
        for node in [*(style.find('w:pPr', NS) for style in self.style_chain(style_id)), properties]:
            num = node.find('w:numPr', NS) if node is not None else None
            if num is not None:
                for key in ('numId', 'ilvl'):
                    value = _child_value(num, key)
                    if value is not None:
                        values[key] = value
        if 'numId' not in values or values['numId'] == '0':
            return None
        level = _integer(values.get('ilvl'), 0)
        # A paragraph-style association can select the level when ilvl is
        # absent. Compare its resolved use, not arbitrary style identifiers.
        if 'ilvl' not in values and style_id is not None:
            concrete = self.nums.get(values['numId'])
            abstract = self.abstracts.get(_child_value(concrete, 'abstractNumId'))
            if abstract is not None:
                matches = [node for node in abstract.findall('w:lvl', NS)
                           if _child_value(node, 'pStyle') == style_id]
                if len(matches) > 1:
                    raise ValueError('Ambiguous paragraph-style numbering level')
                if matches:
                    level = _integer(matches[0].get('{' + W + '}ilvl'))
        if not 0 <= level < 9:
            raise ValueError('Invalid numbering level')
        return values['numId'], level


def _child_value_parent(node):
    return node.get('{' + W + '}val')


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
    result, content_end = [], 0
    for child, parent, in_properties in content_nodes(node):
        if in_properties:
            continue
        value = run_text(child, parent, deleted=deleted)
        if value is not None:
            if value:
                result.append(value)
                content_end = len(result)
        elif child.tag == '{' + W + '}p' and result:
            result.append('\n')
    # Drop only trailing paragraph separators synthesized by this summary.
    # str.strip() would also erase genuine run tabs, breaks and preserved spaces.
    return ''.join(result[:content_end])


def local_attrs(node):
    return {key.rsplit('}', 1)[-1]: value for key, value in sorted(node.attrib.items())}


def _direct_blocks(node, tag):
    """Allow content-control/revision wrappers, never descend into other blocks."""
    for child in node:
        if child.tag == '{' + W + '}' + tag:
            yield child
        elif child.tag not in {'{' + W + '}' + t for t in
                              ('p', 'tbl', 'tr', 'tc', 'txbxContent')}:
            yield from _direct_blocks(child, tag)


def _inline_text(node):
    return ''.join(value for item, parent, in_properties in content_nodes(node, inline=True)
                   if not in_properties and (value := run_text(item, parent)) is not None)


def _inline_offsets(node):
    offsets, position = {}, 0
    for item, parent, in_properties in content_nodes(node, inline=True):
        offsets[item] = position
        if not in_properties and (value := run_text(item, parent)) is not None:
            position += len(value)
    return offsets


def _nearest(node, parents, *tags):
    while node in parents:
        node = parents[node]
        if node.tag in tags:
            return node
    return None


def _flow(node, parents, flows):
    owner = _nearest(node, parents, *('{' + W + '}' + tag for tag in
                                     ('txbxContent', 'comment', 'footnote', 'endnote')))
    if owner is None:
        return 'body'
    if owner not in flows:
        flows[owner] = _local(owner.tag) + ':' + str(len(flows))
    return flows[owner]


def _revision_snapshot(tree, context, parents, paragraph_ids):
    result, range_ids, paragraph_markers, affected_markers, offsets = [], {}, {}, {}, {}
    for node in tree.iter():
        kind = _local(node.tag)
        if node.tag != '{' + W + '}' + kind or kind not in REVISION_TAGS:
            continue
        paragraph = _nearest(node, parents, '{' + W + '}p')
        parent = parents.get(node)
        scope = _local(parent.tag) if parent is not None else 'story'
        if scope == 'rPr' and parents.get(parent) is not None and parents[parent].tag == '{' + W + '}pPr':
            scope = 'paragraphMark'
        affected = node
        if kind.endswith('Change') or scope == 'paragraphMark':
            container = _nearest(node, parents, *('{' + W + '}' + tag for tag in
                                                  ('r', 'p', 'tbl', 'tr', 'tc', 'sectPr')))
            if container is not None:
                affected = container
        if paragraph is not None and paragraph not in paragraph_markers:
            paragraph_markers[paragraph] = _text_marker(_inline_text(paragraph))
            offsets[paragraph] = _inline_offsets(paragraph)
        if affected not in affected_markers:
            affected_markers[affected] = _text_marker(text_content(affected, deleted=True))
        record = {
            'kind': kind, 'scope': scope,
            'paragraph': paragraph_ids.get(paragraph),
            'offsetInParagraph': (paragraph_markers[paragraph]['length'] if scope == 'paragraphMark' else
                                  offsets[paragraph].get(node)) if paragraph is not None else None,
            'paragraphText': paragraph_markers.get(paragraph),
            'affectedText': affected_markers[affected],
            'author': node.get('{' + W + '}author'),
            'date': node.get('{' + W + '}date'),
            'metadata': {_qname(key): value for key, value in sorted(node.attrib.items())
                         if key not in ('{' + W + '}id', '{' + W + '}author', '{' + W + '}date')},
        }
        if kind.endswith('Change'):
            record['previousProperties'] = [context.property(child) for child in node]
        if kind.endswith(('RangeStart', 'RangeEnd')):
            family = re.sub('(?:Start|End)$', '', kind)
            raw_id = node.get('{' + W + '}id')
            key = (family, raw_id)
            if key not in range_ids:
                range_ids[key] = len(range_ids)
            record['range'] = range_ids[key]
        result.append(record)
    return result


def _paragraph_profile(node, context):
    runs = []
    for run, _, in_properties in content_nodes(node, inline=True):
        if in_properties or run.tag != '{' + W + '}r':
            continue
        text = _inline_text(run)
        properties = context.property(run.find('w:rPr', NS), current=True)
        if runs and runs[-1]['properties'] == properties:
            runs[-1]['fragments'].append(text)
        else:
            runs.append({'fragments': [text], 'properties': properties})
    return {'text': _inline_text(node), 'properties': context.property(node.find('w:pPr', NS), current=True),
            'runs': [{'text': ''.join(run['fragments']), 'properties': run['properties']} for run in runs]}


def _paragraph_snapshot(paragraphs, context, parents):
    flows = {}
    return [{'paragraph': index, 'flow': _flow(node, parents, flows),
             **_paragraph_profile(node, context)} for node, index in paragraphs.items()]


def _comment_anchor_snapshot(tree, context, parents, paragraphs):
    """Keep range joins and locations, independently of comment text/counts.

    ISO/IEC29500-1 17.13.4.5 links commentReference by id to both the comment
    and optional range markers. A point reference without range markers is
    valid. Incomplete/reversed/duplicate ranges remain explicit findings.
    """
    records, offsets, flows, unknown, groups = [], {}, {}, {}, {}
    preceding_paragraph = None
    kinds = {'commentRangeStart', 'commentRangeEnd', 'commentReference'}
    for node in tree.iter():
        if node in paragraphs:
            preceding_paragraph = paragraphs[node]
        kind = _local(node.tag)
        if node.tag != '{' + W + '}' + kind or kind not in kinds:
            continue
        identifier = _integer(node.get('{' + W + '}id'))
        paragraph = _nearest(node, parents, '{' + W + '}p')
        if paragraph is not None and paragraph not in offsets:
            offsets[paragraph] = _inline_offsets(paragraph)
        flow = _flow(node, parents, flows)
        comment = context.comment_ids.get(identifier)
        record = {'kind': kind, 'comment': comment,
                  'unresolvedIdentity': (unknown.setdefault(identifier, len(unknown))
                                         if comment is None else None),
                  'flow': flow, 'paragraph': paragraphs.get(paragraph),
                  'offsetInParagraph': offsets[paragraph].get(node) if paragraph is not None else None,
                  'precedingParagraph': preceding_paragraph if paragraph is None else None,
                  'ignoredInCommentStory': flow.startswith('comment:'),
                  'issues': ['unresolved-comment'] if comment is None else []}
        if identifier is None:
            record['issues'].append('missing-comment-id')
        groups.setdefault((flow, identifier), []).append(len(records))
        records.append(record)
    for indexes in groups.values():
        by_kind = {kind: [i for i in indexes if records[i]['kind'] == kind] for kind in kinds}
        starts, ends, refs = (by_kind[name] for name in
                              ('commentRangeStart', 'commentRangeEnd', 'commentReference'))
        issues = []
        if bool(starts) != bool(ends):
            issues.append('incomplete-comment-range')
        if (starts or ends) and not refs:
            issues.append('missing-comment-reference')
        if starts and ends and starts[0] > ends[0]:
            issues.append('reversed-comment-range')
        if any(len(values) > 1 for values in by_kind.values()):
            issues.append('duplicate-comment-anchor')
        for index in indexes:
            records[index]['issues'].extend(issues)
    return records


def _table_snapshot(tree, context, parents):
    tables = list(tree.iter('{' + W + '}tbl'))
    identifiers = {node: index for index, node in enumerate(tables)}
    result = []
    for table in tables:
        ancestor = _nearest(table, parents, '{' + W + '}tbl')
        depth, cursor = 0, ancestor
        while cursor is not None:
            depth += 1
            cursor = _nearest(cursor, parents, '{' + W + '}tbl')
        record = {'table': identifiers[table], 'parentTable': identifiers.get(ancestor), 'depth': depth,
                  'properties': context.property(table.find('w:tblPr', NS), current=True),
                  'grid': context.property(table.find('w:tblGrid', NS), current=True), 'rows': []}
        for row in _direct_blocks(table, 'tr'):
            cells = []
            for cell in _direct_blocks(row, 'tc'):
                cells.append({'properties': context.property(cell.find('w:tcPr', NS), current=True),
                              'paragraphs': [_paragraph_profile(p, context) for p in _direct_blocks(cell, 'p')],
                              'nestedTables': [identifiers[t] for t in _direct_blocks(cell, 'tbl')]})
            record['rows'].append({'properties': context.property(row.find('w:trPr', NS), current=True), 'cells': cells})
        result.append(record)
    return result


def _numbering_snapshot(tree, context, parents, paragraph_ids):
    result, flows, instances, states, previous = [], {}, {}, {}, {}
    for paragraph, index in paragraph_ids.items():
        selection = context.paragraph_numbering(paragraph.find('w:pPr', NS))
        if selection is None:
            continue
        identifier, level = selection
        flow = _flow(paragraph, parents, flows)
        key = (flow, identifier)
        if key not in instances:
            instances[key] = len(instances)
            states[key] = {}
        definition = context.level(identifier, level)
        value = None
        if definition is not None:
            state = states[key]
            value = state.get(level, definition['start'] - 1) + 1
            state[level] = value
            for deeper in range(level + 1, 9):
                child = context.level(identifier, deeper)
                if child is not None and child['restartAfterLevel'] == level:
                    state.pop(deeper, None)
        result.append({'paragraph': index, 'text': _inline_text(paragraph), 'flow': flow,
                       'instance': instances[key], 'previousParagraph': previous.get(key),
                       'level': level, 'resolvedLevel': definition, 'counter': value,
                       'unresolved': definition is None})
        previous[key] = index
    return result


def _css(value):
    result = {}
    for declaration in (value or '').split(';'):
        key, separator, val = declaration.partition(':')
        if separator:
            result[key.strip().lower()] = val.strip()
    return result


def _length(value):
    if value is None:
        return None
    match = re.fullmatch(r'\s*(-?(?:\d+(?:\.\d*)?|\.\d+))\s*(pt|in|cm|mm|pc)\s*', value)
    if not match:
        return value
    factors = {'pt': 12700, 'in': 914400, 'cm': 360000, 'mm': 36000, 'pc': 152400}
    try:
        number = Decimal(match[1]) * factors[match[2]]
        return int(number) if number == number.to_integral_value() else str(number.normalize())
    except InvalidOperation:
        return value


def _textbox_snapshot(tree, context, parents):
    records, aliases, groups = [], {}, {}
    v, wps = NS['v'], NS['wps']
    for node in tree.iter():
        if node.tag == '{' + v + '}textbox':
            shape = _nearest(node, parents, *('{' + v + '}' + tag for tag in
                                            ('shape', 'rect', 'roundrect', 'oval', 'group')))
            if shape is None:
                raise ValueError('VML textbox has no owning shape')
            index = len(records)
            for identifier in (shape.get('id'), shape.get('{urn:schemas-microsoft-com:office:office}spid')):
                if identifier:
                    if identifier in aliases and aliases[identifier] != index:
                        raise ValueError('Ambiguous VML textbox identity')
                    aliases[identifier] = index
            shape_style, text_style = _css(shape.get('style')), _css(node.get('style'))
            target = text_style.get('mso-next-textbox', shape_style.get('mso-next-textbox'))
            shape_style.pop('mso-next-textbox', None)
            text_style.pop('mso-next-textbox', None)
            # Shape IDs and relation IDs are not layout. Numeric z-index still
            # matters; native auto-generated IDs embedded in it are not guessed.
            z_order = shape_style.pop('z-index', None)
            records.append({'node': index, 'text': text_content(node, deleted=True),
                            'next': None, '_target': target,
                            '_zOrder': _integer(z_order) if z_order is not None and re.fullmatch(r'-?\d{1,10}', z_order) else z_order,
                            'layout': {'shape': _local(shape.tag),
                                       'shapeStyle': {k: _length(val) for k, val in sorted(shape_style.items())},
                                       'textStyle': dict(sorted(text_style.items())),
                                       'insets': [_length(val) for val in node.get('inset', '').split(',')] if node.get('inset') else None,
                                       'shapeAttributes': {k: val for k, val in local_attrs(shape).items()
                                                           if k not in ('id', 'spid', 'style', 'type')},
                                       'textAttributes': {k: val for k, val in local_attrs(node).items() if k not in ('id', 'style', 'inset')},
                                       'wrap': [context.property(child) for child in shape if child.tag == '{' + NS['w10'] + '}wrap']},
                            'issues': []})
        elif node.tag == '{' + wps + '}wsp':
            first, linked = node.find('wps:txbx', NS), node.find('wps:linkedTxbx', NS)
            if first is None and linked is None:
                continue
            box = first if first is not None else linked
            index = len(records)
            identifier = box.get('id')
            sequence = 0 if first is not None else _integer(box.get('seq'))
            if sequence is None or sequence < 0 or sequence > 65535:
                raise ValueError('Invalid DrawingML textbox chain sequence')
            anchor = _nearest(node, parents, '{' + NS['wp'] + '}anchor', '{' + NS['wp'] + '}inline')
            records.append({'node': index, 'text': text_content(box, deleted=True),
                            'next': None, '_target': None,
                            '_zOrder': _integer(anchor.get('relativeHeight')) if anchor is not None else None,
                            'layout': {'shapeProperties': context.property(node.find('wps:spPr', NS)),
                                       'textProperties': context.property(node.find('wps:bodyPr', NS)),
                                       'anchorKind': _local(anchor.tag) if anchor is not None else None,
                                       'anchorAttributes': {k: val for k, val in local_attrs(anchor).items()
                                                            if k not in ('anchorId', 'editId', 'relativeHeight')} if anchor is not None else {},
                                       'position': [context.property(child) for child in anchor
                                                    if _local(child.tag) in ('positionH', 'positionV', 'extent', 'effectExtent',
                                                                           'wrapNone', 'wrapSquare', 'wrapTight', 'wrapThrough', 'wrapTopAndBottom')]
                                                   if anchor is not None else []},
                            'issues': []})
            if identifier is not None:
                groups.setdefault(identifier, []).append((sequence, index))
    for record in records:
        target = record.pop('_target')
        if target:
            record['next'] = aliases.get(target.lstrip('#'))
            if record['next'] is None:
                record['issues'].append('dangling-next-textbox')
    for chain in groups.values():
        ordered = sorted(chain)
        if [seq for seq, _ in ordered] != list(range(len(ordered))):
            for _, index in ordered:
                records[index]['issues'].append('nonconsecutive-drawingml-chain')
        for (_, before), (_, after) in zip(ordered, ordered[1:]):
            records[before]['next'] = after
    # Canonical node IDs are document order; links keep graph topology even if
    # source shape ids, textbox chain ids, part names or rel ids are rewritten.
    z_values = sorted(set(record['_zOrder'] for record in records if isinstance(record['_zOrder'], int)))
    z_ranks = {value: index for index, value in enumerate(z_values)}
    for record in records:
        value = record.pop('_zOrder')
        record['stacking'] = {'order': z_ranks[value], 'negative': value < 0} if isinstance(value, int) else value
    incoming = Counter(record['next'] for record in records if record['next'] is not None)
    visited, cyclic = set(), set()
    for record in records:
        if incoming[record['node']] > 1:
            record['issues'].append('multiple-chain-predecessors')
        if record['node'] in visited:
            continue
        active, cursor = set(), record['node']
        while cursor is not None and cursor not in visited and cursor not in active:
            active.add(cursor)
            cursor = records[cursor]['next']
        if cursor in active or cursor in cyclic:
            cyclic.update(active)
        visited.update(active)
    for index in cyclic:
        records[index]['issues'].append('cyclic-textbox-chain')
    return records


def _comment_snapshot(tree, context):
    comments = list(tree.iter('{' + W + '}comment'))
    paragraph_ids = {}
    for index, comment in enumerate(comments):
        paragraphs = list(comment.iter('{' + W + '}p'))
        paragraph = _paragraph_identifier(paragraphs[-1].get('{' + NS['w14'] + '}paraId')) if paragraphs else None
        if paragraph is not None:
            if paragraph in paragraph_ids:
                raise ValueError('Duplicate final comment paragraph id')
            paragraph_ids[paragraph] = index
    result = []
    for index, comment in enumerate(comments):
        paragraphs = list(comment.iter('{' + W + '}p'))
        paragraph = _paragraph_identifier(paragraphs[-1].get('{' + NS['w14'] + '}paraId')) if paragraphs else None
        extra = context.comment_extras.get(paragraph)
        parent = _paragraph_identifier(extra.get('{' + NS['w15'] + '}paraIdParent')) if extra is not None else None
        result.append({'comment': index, 'text': text_content(comment, deleted=True),
                       'author': comment.get('{' + W + '}author'),
                       'initials': comment.get('{' + W + '}initials'),
                       'date': comment.get('{' + W + '}date'),
                       'parent': paragraph_ids.get(parent),
                       'unresolvedParent': parent is not None and parent not in paragraph_ids,
                       'done': _on_off(extra.get('{' + NS['w15'] + '}done'), False) if extra is not None else False})
    return result


def _story_semantics(tree, context):
    parents = {child: parent for parent in tree.iter() for child in parent}
    paragraphs = {node: index for index, node in enumerate(tree.iter('{' + W + '}p'))}
    return {'paragraphs': _paragraph_snapshot(paragraphs, context, parents),
            'revisions': _revision_snapshot(tree, context, parents, paragraphs),
            'tables': _table_snapshot(tree, context, parents),
            'numbering': _numbering_snapshot(tree, context, parents, paragraphs),
            'textboxes': _textbox_snapshot(tree, context, parents),
            'comments': _comment_snapshot(tree, context),
            'commentAnchors': _comment_anchor_snapshot(tree, context, parents, paragraphs)}


def _section_story_snapshot(tree, context, parents, story_facts):
    """Keep exact stored section/header/footer joins without raw part IDs.

    References not present in a section stay absent; this records the inputs
    to Word's inheritance and first/even-page rules, not a pagination guess.
    Previous section properties remain scoped separately from current ones.
    """
    all_sections = list(tree.iter('{' + W + '}sectPr'))
    current = {node: index for index, node in enumerate(
        node for node in all_sections
        if parents.get(node) is None or parents[node].tag != '{' + W + '}sectPrChange')}
    paragraphs = {node: index for index, node in enumerate(tree.iter('{' + W + '}p'))}
    rels = {rel['id']: rel for rel in context.relationships(context.main)}
    identities = {owner: _json_fingerprint(facts) for owner, facts in story_facts.items()}
    records = []
    for section in all_sections:
        previous = section not in current
        owner = _nearest(section, parents, '{' + W + '}sectPr') if previous else section
        references, slots = [], set()
        for child in section:
            kind = {'{' + W + '}headerReference': 'header',
                    '{' + W + '}footerReference': 'footer'}.get(child.tag)
            if kind is None:
                continue
            variant = child.get('{' + W + '}type')
            if variant not in ('default', 'first', 'even') or (kind, variant) in slots:
                raise ValueError('Invalid or duplicate section header/footer slot')
            slots.add((kind, variant))
            relation = rels.get(child.get('{' + R + '}id'))
            if (relation is None or relation['external'] or relation['type'] != kind or
                    relation['target'] not in story_facts):
                raise ValueError('Unresolved or invalid section header/footer reference')
            target, _ = context.tree(relation['target'])
            if target.tag != '{' + W + '}' + ('hdr' if kind == 'header' else 'ftr'):
                raise ValueError('Section header/footer has an invalid story root')
            references.append({'kind': kind, 'type': variant,
                               'storySha256': identities[relation['target']],
                               'text': _text_marker(text_content(target, deleted=True))})
        records.append({'section': current.get(owner), 'scope': 'previous' if previous else 'current',
                        'paragraph': paragraphs.get(_nearest(section, parents, '{' + W + '}p')),
                        'references': sorted(references, key=lambda item: (item['kind'], item['type']))})
    return records


def snapshot(path):
    """Describe every reachable story; ids/part paths need not be unchanged."""
    parts = read_package(path)
    roots = [rel for rel in relationships(parts, '') if rel['type'] == 'officeDocument' and not rel['external']]
    if len(roots) != 1:
        raise ValueError('Expected one internal officeDocument relationship')
    main = roots[0]['target']
    context = _Context(parts, main)
    queue, seen, stories, links = deque([(main, 'main')]), set(), [], []
    story_trees, story_facts = [], {}
    story_types = {'header', 'footer', 'footnotes', 'endnotes', 'comments'}
    counts = Counter()
    media, alternatives, compatibility = [], [], []
    semantic = {name: [] for name in ('paragraphs', 'revisions', 'tables', 'numbering', 'textboxes',
                                     'comments', 'commentAnchors')}
    while queue:
        owner, kind = queue.popleft()
        if owner in seen:
            continue
        seen.add(owner)
        tree, choices = context.tree(owner)
        story_trees.append((owner, kind, tree))
        stories.append({'kind': kind, 'text': text_content(tree),
                        'textWithDeletions': text_content(tree, deleted=True)})
        story_marker = _text_marker(stories[-1]['text'])
        if choices:
            alternatives.append({'story': kind, 'text': story_marker, 'availability': choices})
        features = _story_semantics(tree, context)
        story_facts[owner] = {**stories[-1], 'features': features, 'alternatives': choices,
                              'images': [], 'externalLinks': []}
        for feature, entries in features.items():
            if entries:
                semantic[feature].append({'story': kind, 'text': story_marker, 'items': entries})
        for tag in ('tbl', 'tr', 'tc', 'drawing', 'pict', 'txbxContent', 'footnote',
                    'endnote', 'comment', 'ins', 'del', 'moveFrom', 'moveTo',
                    'rPrChange', 'pPrChange', 'tblPrChange', 'trPrChange',
                    'tcPrChange', 'sectPrChange', 'numberingChange'):
            elements = list(tree.iter(f'{{{W}}}{tag}'))
            if tag in ('footnote', 'endnote'):
                elements = [e for e in elements if e.get(f'{{{W}}}type', 'normal') == 'normal']
            counts[tag] += len(elements)
        for node, parent, in_properties in content_nodes(tree):
            if (not in_properties and node.tag == '{' + W + '}br'
                    and run_text(node, parent) is not None):
                counts['break:' + node.get(f'{{{W}}}type', 'textWrapping')] += 1
        used_ids = {value for node in tree.iter() for attr, value in node.attrib.items()
                    if attr.startswith('{' + R + '}')}
        for rel in context.relationships(owner):
            if rel['external']:
                links.append({'kind': rel['type'], 'target': rel['target']})
                story_facts[owner]['externalLinks'].append(links[-1])
            elif rel['type'] in story_types:
                queue.append((rel['target'], rel['type']))
            elif rel['type'] == 'image' and rel['id'] in used_ids:
                media.append(hashlib.sha256(parts[rel['target']]).hexdigest())
                story_facts[owner]['images'].append(media[-1])
            elif rel['type'] == 'commentsExtended':
                ext, _ = context.tree(rel['target'])
                counts['commentThreads'] += sum(1 for e in ext if e.get('{'+NS['w15']+'}paraIdParent'))
            elif rel['type'] == 'settings':
                settings, _ = context.tree(rel['target'])
                compat = settings.find('w:compat', NS)
                if compat is not None:
                    compatibility.append(sorted([
                        {'name': _local(node.tag),
                         'value': (_on_off(node.get('{' + W + '}val')) if _local(node.tag) != 'compatSetting'
                                   else local_attrs(node))} for node in compat], key=lambda item: json.dumps(item, sort_keys=True)))
        story_facts[owner]['images'].sort()
        story_facts[owner]['externalLinks'].sort(key=lambda item: (item['kind'], item['target']))
    # Validate *all* relationships, including evidence and relocated stories.
    for name in parts:
        if name.endswith('.rels'):
            owner = '' if name == '_rels/.rels' else posixpath.join(posixpath.dirname(posixpath.dirname(name)), posixpath.basename(name)[:-5])
            relationships(parts, owner)
    tree, _ = context.tree(main)
    parents = {child: parent for parent in tree.iter() for child in parent}
    sections = []
    for section in tree.iter(f'{{{W}}}sectPr'):
        if parents.get(section) is not None and parents[section].tag == f'{{{W}}}sectPrChange':
            continue
        sections.append({child.tag.rsplit('}', 1)[-1]: local_attrs(child)
                         for child in section if child.tag.rsplit('}', 1)[-1] not in ('headerReference', 'footerReference')})
    result = {'oracleSchemaVersion': 4,
            'stories': sorted(stories, key=lambda item: (item['kind'], item['text'])),
            'counts': dict(sorted(counts.items())), 'sections': sections,
            'imageDigests': sorted(media), 'externalLinks': sorted(links, key=str),
            'alternatives': sorted(alternatives, key=_json_fingerprint),
            'compatibility': compatibility,
            'sectionStories': _section_story_snapshot(tree, context, parents, story_facts),
            'styleDefaults': {'document': context.property(context.document_defaults),
                              'types': {kind: context.style(identifier)
                                        for kind, identifier in sorted(context.default_styles.items())}},
            'structure': StructureOracle(parts, main, relationships,
                                         read_xml=lambda owner: context.tree(owner)[0]).snapshot(story_trees),
            **{feature: sorted(entries, key=_json_fingerprint)
               for feature, entries in semantic.items()}}
    _json_fingerprint(result)
    return result


def compare_semantics(reference, actual):
    """Report losses and changes, including a loss to zero. No tolerant pass."""
    differences = []
    for key in ('oracleSchemaVersion', 'stories', 'sections', 'imageDigests', 'externalLinks',
                'paragraphs', 'revisions', 'tables', 'numbering', 'textboxes', 'comments', 'commentAnchors',
                'alternatives', 'compatibility', 'sectionStories', 'styleDefaults',
                'structure'):
        if reference.get(key) != actual.get(key):
            differences.append({'property': key, 'reference': reference.get(key), 'actual': actual.get(key)})
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
