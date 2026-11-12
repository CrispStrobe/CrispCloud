#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independent structural facts that cannot be established by element counts.

This module reads OOXML only. It neither imports the Dart implementation nor
accepts changes in a document. Its accepted/rejected text projections deliberately
cover text, paragraph marks and row visibility; property histories are inspected
separately. They are not a general Word revision-acceptance implementation.
"""
import hashlib
import json
import re
import xml.etree.ElementTree as ET

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
V = 'urn:schemas-microsoft-com:vml'
O = 'urn:schemas-microsoft-com:office:office'
W14 = 'http://schemas.microsoft.com/office/word/2010/wordml'
W15 = 'http://schemas.microsoft.com/office/word/2012/wordml'
WPS = 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = {'w': W, 'v': V, 'o': O, 'w14': W14, 'w15': W15, 'wps': WPS}
PROPERTY_TAGS = {'pPr', 'rPr', 'tblPr', 'tblPrEx', 'trPr', 'tcPr', 'sectPr'}
CHANGE_TAGS = {'ins', 'del', 'moveFrom', 'moveTo', 'rPrChange', 'pPrChange',
               'tblPrChange', 'tblPrExChange', 'trPrChange', 'tcPrChange',
               'sectPrChange', 'numberingChange', 'cellIns', 'cellDel',
               'cellMerge', 'customXmlInsRangeStart', 'customXmlInsRangeEnd',
               'customXmlDelRangeStart', 'customXmlDelRangeEnd',
               'moveFromRangeStart', 'moveFromRangeEnd',
               'moveToRangeStart', 'moveToRangeEnd'}


def tag(name):
    return '{' + W + '}' + name


def attr(node, name, default=None):
    return default if node is None else node.get(tag(name), default)


def qname(name):
    for prefix, namespace in NS.items():
        if name.startswith('{' + namespace + '}'):
            return prefix + ':' + name.split('}', 1)[1]
    return name


def properties(node, *, exclude=(), omit_attributes=()):
    """Preserve namespace, sparse properties, explicit false and child order."""
    if node is None:
        return None
    attrs = {qname(key): value for key, value in sorted(node.attrib.items())
             if key not in omit_attributes and not key.startswith('{' + W + '}rsid') and
             not (node.tag in (tag('headerReference'), tag('footerReference')) and key == '{' + R + '}id')}
    result = {'tag': qname(node.tag), 'attributes': attrs,
              'children': [properties(child, exclude=exclude,
                                      omit_attributes=omit_attributes)
                           for child in node if child.tag not in exclude]}
    if node.text and node.text.strip():
        result['text'] = node.text
    return result


def ordinary_text(node):
    return ''.join(child.text or '' for child in node.iter()
                   if child.tag in (tag('t'), tag('delText')))


def review_text(node, view):
    """Project text without flattening insertion/deletion or mark semantics."""
    if view not in ('accepted', 'rejected'):
        raise ValueError('Unknown review text view')
    accepted = view == 'accepted'

    def visit(element):
        local = element.tag.split('}')[-1]
        if element.tag.startswith('{' + W + '}'):
            if local in PROPERTY_TAGS:
                return ''
            if local in ('ins', 'moveTo') and not accepted:
                return ''
            if local in ('del', 'moveFrom') and accepted:
                return ''
            if local == 'tr':
                props = element.find(tag('trPr'))
                if props is not None and props.find(tag('del' if accepted else 'ins')) is not None:
                    return ''
            if local in ('t', 'delText'):
                return element.text or ''
            if local == 'tab':
                return '\t'
            if local == 'br':
                return {'page': '\f', 'column': '\x0e'}.get(attr(element, 'type'), '\n')
            if local == 'cr':
                return '\n'
        value = ''.join(visit(child) for child in element)
        if element.tag == tag('p'):
            mark = element.find('w:pPr/w:rPr', NS)
            removed = mark is not None and mark.find(tag('del' if accepted else 'ins')) is not None
            if not removed:
                value += '\n'
        return value

    return visit(node)


def indexed(nodes, attribute, label):
    result = {}
    for node in nodes:
        key = node.get(attribute)
        if key is None or key in result:
            raise ValueError('Missing or duplicate ' + label)
        result[key] = node
    return result


def css(style):
    result = {}
    for declaration in (style or '').split(';'):
        if ':' in declaration:
            name, value = declaration.split(':', 1)
            result[name.strip().lower()] = value.strip()
    return result


def validate_parents(parents, label):
    visited = set()
    for start in parents:
        if start in visited:
            continue
        seen, current = set(), start
        while current is not None and current not in visited:
            if current in seen:
                raise ValueError('Cyclic ' + label)
            seen.add(current)
            if current not in parents:
                raise ValueError('Unresolved ' + label)
            current = parents[current]
        visited.update(seen)


def paragraph_id(value):
    if value is None:
        return None
    if not re.fullmatch('[0-9A-Fa-f]{8}', value):
        raise ValueError('Invalid comment paragraph id')
    return value.upper()


def on_off(value, default=False):
    if value is None:
        return default
    if value in ('1', 'true', 'on'):
        return True
    if value in ('0', 'false', 'off'):
        return False
    raise ValueError('Invalid OOXML Boolean')


class StructureOracle:
    def __init__(self, parts, main, relationships, *, read_xml=None):
        self.parts, self.main, self.relationships = parts, main, relationships
        # The package oracle supplies its bounded, namespace-aware MC reader
        # for auxiliary parts too. Never reparse unselected Choice/Fallback
        # contents after the shared projection has selected one branch.
        self.read_xml = read_xml or (lambda owner: ET.fromstring(parts[owner]))
        self.styles_root = self.related(main, 'styles')
        self.styles = indexed([] if self.styles_root is None else self.styles_root.findall(tag('style')),
                              tag('styleId'), 'style id')
        self.numbers_root = self.related(main, 'numbering')
        root = self.numbers_root
        self.numbers = indexed([] if root is None else root.findall(tag('num')),
                               tag('numId'), 'numbering instance id')
        self.abstract = indexed([] if root is None else root.findall(tag('abstractNum')),
                                tag('abstractNumId'), 'abstract numbering id')
        self.style_cache = {}
        self.instance_order = {}

    def related(self, owner, kind):
        candidates = [r for r in self.relationships(self.parts, owner)
                      if r['type'] == kind and not r['external']]
        if len(candidates) > 1:
            raise ValueError('Duplicate ' + kind + ' relationship')
        return self.read_xml(candidates[0]['target']) if candidates else None

    def style_chain(self, identifier):
        chain, seen = [], set()
        while identifier is not None:
            if identifier in seen:
                raise ValueError('Cyclic style inheritance')
            seen.add(identifier)
            if identifier not in self.styles:
                raise ValueError('Unresolved style reference: ' + identifier)
            style = self.styles[identifier]
            chain.append(style)
            identifier = attr(style.find(tag('basedOn')), 'val')
        return list(reversed(chain))

    def style(self, identifier):
        if identifier is None:
            return None
        if identifier not in self.style_cache:
            self.style_cache[identifier] = [properties(node,
                exclude={tag('basedOn'), tag('next'), tag('link'), tag('aliases')},
                omit_attributes={tag('styleId')}) for node in self.style_chain(identifier)]
        return self.style_cache[identifier]

    def tables(self, tree):
        result = []
        for table in tree.iter(tag('tbl')):
            props = table.find(tag('tblPr'))
            style_id = attr(None if props is None else props.find(tag('tblStyle')), 'val')
            rows = []
            for row in table.findall(tag('tr')):
                rows.append({'properties': properties(row.find(tag('trPr'))),
                             'exceptions': properties(row.find(tag('tblPrEx'))),
                             'cells': [{'text': ordinary_text(cell),
                                        'properties': properties(cell.find(tag('tcPr')))}
                                       for cell in row.findall(tag('tc'))]})
            result.append({'properties': properties(props, exclude={tag('tblStyle')}),
                           'style': self.style(style_id),
                           'grid': properties(table.find(tag('tblGrid'))), 'rows': rows})
        return result

    def numbering(self, tree):
        result = []
        for paragraph in tree.iter(tag('p')):
            ppr = paragraph.find(tag('pPr'))
            style_id = attr(None if ppr is None else ppr.find(tag('pStyle')), 'val')
            sources = [style.find(tag('pPr')) for style in self.style_chain(style_id)] if style_id else []
            sources.append(ppr)
            values = {}
            for source in sources:
                numpr = None if source is None else source.find(tag('numPr'))
                if numpr is not None:
                    for key in ('numId', 'ilvl'):
                        value = attr(numpr.find(tag(key)), 'val')
                        if value is not None:
                            values[key] = value
            number_id = values.get('numId')
            if number_id is None or number_id == '0':
                continue
            if number_id not in self.numbers:
                raise ValueError('Unresolved numbering instance: ' + number_id)
            number = self.numbers[number_id]
            abstract_id = attr(number.find(tag('abstractNumId')), 'val')
            if abstract_id not in self.abstract:
                raise ValueError('Unresolved abstract numbering definition')
            definition = self.abstract[abstract_id]
            levels = indexed(definition.findall(tag('lvl')), tag('ilvl'), 'numbering level')
            overrides = indexed(number.findall(tag('lvlOverride')), tag('ilvl'), 'numbering override')
            level_id = values.get('ilvl', '0')
            override = overrides.get(level_id)
            level = None if override is None else override.find(tag('lvl'))
            if level is None:
                level = levels.get(level_id)
            if level is None:
                raise ValueError('Unresolved numbering level')
            # Identity is normalized by first use, but distinct instances stay
            # distinct even if their definitions/start overrides are equal.
            ordinal = self.instance_order.setdefault(number_id, len(self.instance_order))
            result.append({'text': ordinary_text(paragraph), 'instance': ordinal,
                           'level': level_id, 'definition': properties(level),
                           'startOverride': attr(None if override is None else override.find(tag('startOverride')), 'val'),
                           'allLevels': [properties(value) for value in levels.values()],
                           'allOverrides': [properties(value) for value in overrides.values()]})
        return result

    def revisions(self, tree):
        result = []
        ranges = {}

        def visit(node, path):
            if node.tag.startswith('{' + W + '}') and node.tag.split('}')[-1] in CHANGE_TAGS:
                kind = node.tag.split('}')[-1]
                attrs = {qname(key): value for key, value in sorted(node.attrib.items())
                         if key != tag('id')}
                if kind.endswith(('RangeStart', 'RangeEnd')):
                    family = re.sub('(?:Start|End)$', '', kind)
                    key = (family, attr(node, 'id'))
                    attrs['range'] = ranges.setdefault(key, len(ranges))
                result.append({'kind': kind, 'path': path, 'metadata': attrs,
                               'content': [properties(child, omit_attributes={tag('id')}) for child in node]})
            indices = {}
            for child in node:
                index = indices.get(child.tag, 0)
                indices[child.tag] = index + 1
                visit(child, path + '/' + qname(child.tag) + '[' + str(index) + ']')
        visit(tree, qname(tree.tag))
        return result

    def textboxes(self, tree):
        shapes = []
        for node in tree.iter():
            if node.tag.startswith('{' + V + '}') and node.find('v:textbox', NS) is not None:
                shapes.append(node)
        aliases, records, successors = {}, [], {}
        for index, shape in enumerate(shapes):
            box = shape.find('v:textbox', NS)
            for identifier in {shape.get('id'), box.get('id')} - {None}:
                if identifier in aliases:
                    raise ValueError('Duplicate textbox identifier')
                aliases[identifier] = index
            shape_style, box_style = css(shape.get('style')), css(box.get('style'))
            targets = {style['mso-next-textbox'].strip('"\'').lstrip('#')
                       for style in (shape_style, box_style) if style.get('mso-next-textbox')}
            if len(targets) > 1:
                raise ValueError('Conflicting textbox successors')
            successors[index] = next(iter(targets), None)
            shape_style.pop('mso-next-textbox', None)
            box_style.pop('mso-next-textbox', None)
            records.append({'format': 'vml', 'shape': qname(shape.tag), 'text': ordinary_text(box),
                            'shapeStyle': shape_style, 'textStyle': box_style,
                            'inset': box.get('inset'),
                            'geometryAndPaint': [properties(c) for c in shape if c is not box]})
        predecessors = {}
        for index, target in successors.items():
            if target is not None and target not in aliases:
                raise ValueError('Unresolved linked textbox')
            target_index = aliases.get(target)
            records[index]['next'] = target_index
            if target_index is not None:
                if target_index in predecessors:
                    raise ValueError('Multiple predecessors of linked textbox')
                predecessors[target_index] = index
        validate_parents({i: record['next'] for i, record in enumerate(records)}, 'textbox chain')
        drawing_groups = {}
        for shape in tree.iter('{' + WPS + '}wsp'):
            box = shape.find('wps:txbx', NS)
            linked = shape.find('wps:linkedTxbx', NS)
            if box is None and linked is None:
                continue
            value = box if box is not None else linked
            identifier = value.get('id')
            group = None if identifier is None else drawing_groups.setdefault(identifier, len(drawing_groups))
            records.append({'format': 'drawingml', 'group': group,
                            'sequence': value.get('seq', '0'), 'text': ordinary_text(value),
                            'body': properties(shape.find('wps:bodyPr', NS)),
                            'geometryAndPaint': properties(shape.find('wps:spPr', NS))})
        return records

    def comments(self):
        comments, extended = self.related(self.main, 'comments'), self.related(self.main, 'commentsExtended')
        if comments is None:
            if extended is not None and len(extended):
                raise ValueError('Comment extensions have no comments part')
            return []
        nodes = comments.findall(tag('comment'))
        indexed(nodes, tag('id'), 'comment id')
        paragraph_ids, records = {}, []
        for index, node in enumerate(nodes):
            paragraphs = list(node.iter(tag('p')))
            identifier = paragraph_id(paragraphs[-1].get('{' + W14 + '}paraId')) if paragraphs else None
            if identifier:
                if identifier in paragraph_ids:
                    raise ValueError('Duplicate final comment paragraph id')
                paragraph_ids[identifier] = index
            records.append({'author': attr(node, 'author'), 'initials': attr(node, 'initials'),
                            'date': attr(node, 'date'), 'text': review_text(node, 'accepted'),
                            'parent': None, 'done': False,
                            'ink': [properties(ink) for ink in node.iter('{' + O + '}ink')]})
        seen = set()
        for extension in [] if extended is None else extended:
            if extension.tag != '{' + W15 + '}commentEx':
                continue
            identifier = paragraph_id(extension.get('{' + W15 + '}paraId'))
            if identifier not in paragraph_ids or identifier in seen:
                raise ValueError('Unresolved or duplicate comment extension')
            seen.add(identifier)
            parent = paragraph_id(extension.get('{' + W15 + '}paraIdParent'))
            if parent is not None and parent not in paragraph_ids:
                raise ValueError('Unresolved comment parent')
            record = records[paragraph_ids[identifier]]
            record['parent'] = paragraph_ids.get(parent)
            record['done'] = on_off(extension.get('{' + W15 + '}done'))
        validate_parents({i: record['parent'] for i, record in enumerate(records)}, 'comment thread')
        return records

    def story(self, tree, kind):
        parents = {child: parent for parent in tree.iter() for child in parent}
        return {'kind': kind, 'acceptedText': review_text(tree, 'accepted'),
                'rejectedText': review_text(tree, 'rejected'),
                'tables': self.tables(tree), 'numbering': self.numbering(tree),
                'revisions': self.revisions(tree), 'textboxes': self.textboxes(tree),
                'sections': [properties(section) for section in tree.iter(tag('sectPr'))
                             if parents.get(section) is None or parents[section].tag != tag('sectPrChange')],
                'ink': [properties(ink) for ink in tree.iter('{' + O + '}ink')]}

    def snapshot(self, stories):
        return {'stories': sorted([self.story(tree, kind) for _, kind, tree in stories],
                                  key=lambda value: (value['kind'], value['acceptedText'])),
                'comments': self.comments(),
                'defaults': None if self.styles_root is None else properties(self.styles_root.find(tag('docDefaults'))),
                'compatibility': self.compatibility()}

    def compatibility(self):
        settings = self.related(self.main, 'settings')
        if settings is None:
            return None
        return [properties(child) for child in settings if child.tag in {
            tag('compat'), tag('defaultTabStop'), tag('evenAndOddHeaders'),
            tag('autoHyphenation'), tag('hyphenationZone'), tag('consecutiveHyphenLimit'),
            tag('mirrorMargins'), tag('gutterAtTop'), tag('doNotHyphenateCaps')}]


def structural_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
