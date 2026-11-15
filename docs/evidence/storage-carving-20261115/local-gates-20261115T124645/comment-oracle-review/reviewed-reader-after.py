#!/usr/bin/env python3
"""Verify actual XLSX comment outputs independently of the Dart engine.

This checks the generated plain-comment profile with lxml/zipfile and reads
comment text/author values with openpyxl. It is not full Open XML validation.
All observed failures are retained; one malformed cycle does not hide the rest.
"""
import argparse
import base64
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
import posixpath
import sys
from urllib.parse import unquote, urlsplit
import warnings
from zipfile import ZipFile

from lxml import etree as ET
import openpyxl
import openpyxl.cell.text
import openpyxl.comments.comment_sheet
import openpyxl.reader.excel

S = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P = 'http://schemas.openxmlformats.org/package/2006/relationships'
C = 'http://schemas.openxmlformats.org/package/2006/content-types'
XML = 'http://www.w3.org/XML/1998/namespace'
COMMENTS_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml'
SOURCES = [
    {'url': 'https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.comments?view=openxml-3.0.1', 'supports': 'A worksheet relationship identifies its comments part; comments contains authors and commentList.'},
    {'url': 'https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.commenttext?view=openxml-3.0.1', 'supports': 'SpreadsheetML x:text is an RstType container.'},
    {'url': 'https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.text?view=openxml-3.0.1', 'supports': 'SpreadsheetML x:t is the plain text leaf.'},
    {'url': 'https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.comment?view=openxml-3.0.1', 'supports': 'Comment ref and authorId identify the cell and the author table entry.'},
    {'url': 'https://www.w3.org/TR/xml/#sec-white-space', 'supports': 'xml:space preserve communicates whitespace preservation intent.'},
    {'url': 'https://openpyxl.readthedocs.io/en/3.1/comments.html', 'supports': 'Non-read-only loading exposes comment text and author; formatting and geometry are outside this reader scope.'},
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fingerprint(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': sha(data)}


def local(element):
    return ET.QName(element).localname


def children(element, name):
    return [child for child in element if isinstance(child.tag, str) and local(child) == name]


def relationship_path(owner):
    return '_rels/.rels' if not owner else posixpath.join(posixpath.dirname(owner), '_rels', posixpath.basename(owner)+'.rels')


def resolve(owner, target):
    parsed = urlsplit(unquote(target))
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or '\\' in parsed.path:
        raise ValueError('Relationship target must be an internal package path')
    result = posixpath.normpath(parsed.path.lstrip('/') if parsed.path.startswith('/') else posixpath.join(posixpath.dirname(owner), parsed.path))
    if result == '..' or result.startswith('../') or result in ('', '.'):
        raise ValueError('Relationship target escapes the package')
    return result


def verify_file(path, expected, *, sheet_name='Notes', sheet_names=None, collision=None):
    sheet_names = sheet_names or ['Notes']
    result = {'file': path.name, 'checks': 0, 'failures': [], 'comments': [], 'external_reader': {'name': 'openpyxl', 'version': openpyxl.__version__}}
    def check(ok, code, actual=None, wanted=None, location=None):
        result['checks'] += 1
        if not ok:
            result['failures'].append({'code': code, 'location': location or path.name, 'actual': actual, 'expected': wanted})
        return bool(ok)
    def parse(data):
        return ET.fromstring(data, parser=ET.XMLParser(resolve_entities=False, no_network=True, load_dtd=False, remove_blank_text=False))
    def no_bare_container_text(element, code, location):
        # XML element-only containers permit only XML whitespace between children.
        tails = [child.tail for child in element]
        return check(not (element.text or '').strip(' \t\r\n')
                     and all(not (tail or '').strip(' \t\r\n') for tail in tails),
                     code, {'text': element.text, 'tails': tails},
                     'Only XML whitespace outside child elements', location)
    try:
        data = path.read_bytes()
        result['input'] = {'bytes': len(data), 'sha256': sha(data)}
    except Exception as error:
        check(False, 'input_read', repr(error), 'Readable XLSX output')
        result['success'] = False
        return result
    try:
        with ZipFile(io.BytesIO(data)) as archive:
            names = archive.namelist()
            check(len(names) == len(set(names)), 'zip_unique_members', len(names), len(set(names)))
            bad_crc = archive.testzip()
            check(bad_crc is None, 'zip_crc', bad_crc, None)
            content_types = parse(archive.read('[Content_Types].xml'))
            check(content_types.tag == '{'+C+'}Types', 'content_types_namespace', content_types.tag, '{'+C+'}Types')
            if collision is not None:
                orphan = collision['orphan_part']
                orphan_relationships = collision['orphan_relationships_part']
                for part, key in [(orphan, 'orphan_base64'), (orphan_relationships, 'orphan_relationships_base64')]:
                    expected_bytes = base64.b64decode(collision[key], validate=True)
                    if check(part in names, 'unowned_part_retained', part, 'Existing unchanged ZIP member'):
                        observed = archive.read(part)
                        check(observed == expected_bytes, 'unowned_part_bytes_unchanged',
                              {'bytes': len(observed), 'sha256': sha(observed)},
                              {'bytes': len(expected_bytes), 'sha256': sha(expected_bytes)}, part)
                orphan_types = [e.get('ContentType') for e in content_types.findall('{'+C+'}Override') if e.get('PartName') == '/'+orphan]
                check(orphan_types == [collision['orphan_content_type']], 'unowned_part_content_type_unchanged', orphan_types, [collision['orphan_content_type']], orphan)
                # The orphan can deliberately have an invalid comments root. Its bytes
                # are preserved without treating it as an owned SpreadsheetML part.
            def relationships(owner):
                name = relationship_path(owner)
                root = parse(archive.read(name))
                check(root.tag == '{'+P+'}Relationships', 'relationships_namespace', root.tag, '{'+P+'}Relationships', name)
                rows = children(root, 'Relationship')
                ids = [row.get('Id') for row in rows]
                check(len(ids) == len(set(ids)), 'relationship_unique_ids', ids, 'Unique IDs', name)
                for row in rows:
                    check(row.tag == '{'+P+'}Relationship', 'relationship_element_namespace', row.tag, '{'+P+'}Relationship', name)
                return rows
            def one_target(owner, rows, relation_type, rid=None):
                matching = [r for r in rows if r.get('Type') == R+'/'+relation_type and (rid is None or r.get('Id') == rid)]
                if not check(len(matching) == 1, relation_type+'_relationship_count', len(matching), 1, relationship_path(owner)):
                    return None
                row = matching[0]
                if not check(row.get('TargetMode', 'Internal') == 'Internal', relation_type+'_relationship_internal', row.get('TargetMode', 'Internal'), 'Internal'):
                    return None
                try:
                    target = resolve(owner, row.get('Target', ''))
                except Exception as error:
                    check(False, relation_type+'_relationship_target', repr(error), 'Resolvable internal part')
                    return None
                if not check(target in names, relation_type+'_target_exists', target, 'Existing ZIP member'):
                    return None
                return target
            book_uri = one_target('', relationships(''), 'officeDocument')
            if book_uri is not None:
                book = parse(archive.read(book_uri))
                check(book.tag == '{'+S+'}workbook', 'workbook_namespace', book.tag, '{'+S+'}workbook', book_uri)
                sheets = book.findall('{'+S+'}sheets/{'+S+'}sheet')
                actual_names = [sheet.get('name') for sheet in sheets]
                check(actual_names == sheet_names, 'fixture_worksheet_names', actual_names, sheet_names)
                selected = [sheet for sheet in sheets if sheet.get('name') == sheet_name]
                if check(len(selected) == 1, 'selected_worksheet_count', len(selected), 1):
                    sheet_uri = one_target(book_uri, relationships(book_uri), 'worksheet', selected[0].get('{'+R+'}id'))
                    if sheet_uri is not None:
                        result.update(worksheet_name=sheet_name, worksheet_part=sheet_uri)
                        comments_uri = one_target(sheet_uri, relationships(sheet_uri), 'comments')
                        if comments_uri is not None:
                            result['comments_part'] = comments_uri
                            if collision is not None:
                                check(comments_uri != collision['orphan_part'], 'owned_comments_distinct_from_orphan', comments_uri, 'A separate owned comments part')
                            declared = [e.get('ContentType') for e in content_types.findall('{'+C+'}Override') if e.get('PartName') == '/'+comments_uri]
                            check(declared == [COMMENTS_TYPE], 'comments_content_type', declared, [COMMENTS_TYPE], comments_uri)
                            comment_root = parse(archive.read(comments_uri))
                            check(local(comment_root) == 'comments', 'comments_root_name', local(comment_root), 'comments', comments_uri)
                            no_bare_container_text(comment_root, 'comments_root_no_bare_container_text', comments_uri)
                            for element in comment_root.iter():
                                if isinstance(element.tag, str):
                                    check(ET.QName(element).namespace == S, 'comments_element_namespace', element.tag, S, comments_uri+':'+local(element))
                            root_children = [local(e) for e in comment_root if isinstance(e.tag, str)]
                            check(root_children[:2] == ['authors', 'commentList'] and all(x == 'extLst' for x in root_children[2:]), 'comments_child_order', root_children, ['authors','commentList'], comments_uri)
                            author_roots = children(comment_root, 'authors')
                            author_values = []
                            if check(len(author_roots) == 1, 'authors_count', len(author_roots), 1, comments_uri):
                                author_elements = [e for e in author_roots[0] if isinstance(e.tag,str)]
                                check(all(local(e)=='author' and len(e)==0 for e in author_elements), 'authors_only_author_leaves', [local(e) for e in author_elements], 'Only leaf author elements', comments_uri)
                                no_bare_container_text(author_roots[0], 'authors_no_bare_container_text', comments_uri)
                                author_values = [''.join(e.itertext()) for e in children(author_roots[0], 'author')]
                                wanted_authors = list(dict.fromkeys(row['author'] for row in expected))
                                check(author_values == wanted_authors, 'author_table_first_seen_identity', author_values, wanted_authors, comments_uri)
                            lists = children(comment_root, 'commentList')
                            if check(len(lists) == 1, 'comment_list_count', len(lists), 1, comments_uri):
                                list_elements = [e for e in lists[0] if isinstance(e.tag,str)]
                                check(all(local(e)=='comment' for e in list_elements), 'comment_list_only_comments', [local(e) for e in list_elements], 'Only comment elements', comments_uri)
                                no_bare_container_text(lists[0], 'comment_list_no_bare_container_text', comments_uri)
                                comments = children(lists[0], 'comment')
                                actual_refs = [comment.get('ref') for comment in comments]
                                wanted_refs = [row['cell'] for row in expected]
                                check(actual_refs == wanted_refs, 'comment_cell_inventory', actual_refs, wanted_refs, comments_uri)
                                expected_by_ref = {row['cell']: row for row in expected}
                                for comment in comments:
                                    ref = comment.get('ref')
                                    location = comments_uri+':'+str(ref)
                                    no_bare_container_text(comment, 'comment_no_bare_container_text', location)
                                    comment_children = [local(e) for e in comment if isinstance(e.tag,str)]
                                    check(comment_children == ['text'], 'plain_comment_child_inventory', comment_children, ['text'], location)
                                    author_id = comment.get('authorId')
                                    try:
                                        index = int(author_id)
                                    except (TypeError, ValueError):
                                        index = -1
                                    valid_author = check(author_id is not None and author_id.isdigit() and 0 <= index < len(author_values), 'comment_author_index', author_id, 'In-range zero-based author index', location)
                                    check(comment.get('author') is None, 'no_legacy_author_attribute', comment.get('author'), None, location)
                                    texts = children(comment, 'text')
                                    value = None
                                    if check(len(texts) == 1, 'comment_text_container_count', len(texts), 1, location):
                                        container = texts[0]
                                        no_bare_container_text(container, 'rst_has_no_bare_text', location)
                                        leaves = children(container, 't')
                                        child_names = [local(e) for e in container if isinstance(e.tag, str)]
                                        if check(child_names == ['t'] and len(leaves) == 1, 'plain_rst_text_leaf', child_names, ['t'], location):
                                            leaf = leaves[0]
                                            check(len(leaf) == 0, 'plain_text_leaf_has_no_children', len(leaf), 0, location)
                                            value = leaf.text or ''
                                            if value and (value[0] in ' \t\r\n' or value[-1] in ' \t\r\n'):
                                                check(leaf.get('{'+XML+'}space') == 'preserve', 'edge_whitespace_preserved', leaf.get('{'+XML+'}space'), 'preserve', location)
                                    want = expected_by_ref.get(ref)
                                    if want is not None:
                                        check(value == want['text'], 'xml_comment_text', value, want['text'], location)
                                        if valid_author:
                                            check(author_values[index] == want['author'], 'xml_comment_author', author_values[index], want['author'], location)
                                    result['comments'].append({'cell': ref, 'text': value, 'author_id': author_id, 'author': author_values[index] if valid_author else None})
    except Exception as error:
        check(False, 'package_parse_exception', repr(error), 'Readable relationship graph and comment XML')
    try:
        with warnings.catch_warnings(record=True) as recorded:
            warnings.simplefilter('always')
            book = openpyxl.load_workbook(io.BytesIO(data), read_only=False, data_only=False)
        result['external_reader']['warnings'] = [str(w.message) for w in recorded]
        check(book.sheetnames == sheet_names, 'openpyxl_sheet_names', book.sheetnames, sheet_names)
        if check(sheet_name in book.sheetnames, 'openpyxl_selected_sheet', sheet_name, 'Existing authored worksheet'):
            sheet = book[sheet_name]
            observed = {cell.coordinate: {'text': cell.comment.text, 'author': cell.comment.author} for row in sheet.iter_rows() for cell in row if cell.comment is not None}
            result['external_reader']['comments'] = observed
            check(set(observed) == {row['cell'] for row in expected}, 'openpyxl_comment_inventory', sorted(observed), sorted(row['cell'] for row in expected))
            for row in expected:
                actual = observed.get(row['cell'])
                check(actual == {'text':row['text'], 'author':row['author']}, 'openpyxl_comment_text_author', actual, {'text':row['text'], 'author':row['author']}, row['cell'])
        book.close()
    except Exception as error:
        check(False, 'openpyxl_load_exception', repr(error), 'External reader loads all expected comments')
    result['success'] = not result['failures']
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input-dir', required=True, type=Path)
    ap.add_argument('--report', required=True, type=Path)
    args = ap.parse_args()
    if args.report.exists():
        ap.error('report already exists; retain the original and select a fresh report path')
    folder = args.input_dir.resolve()
    expected_path = folder/'expected-comments.json'
    collisions_path = folder/'collision-cases.json'
    files = [folder/f'comments-cycle-{cycle}.xlsx' for cycle in range(1,4)]
    collision_names = {f'collision-{kind}-{phase}.xlsx' for kind in ('valid','malformed') for phase in ('empty','added','cleared')}
    inputs = [expected_path, collisions_path, *files, *(folder/name for name in sorted(collision_names))]
    before = {p.name: fingerprint(p) for p in inputs if p.is_file()}
    report = {'schema':2,'started_at':datetime.now(timezone.utc).isoformat(),'oracle_script_sha256':sha(Path(__file__).read_bytes()),'input_directory':str(folder),'inputs_before':before,'tools':{'python':sys.version,'python_executable':str(Path(sys.executable).resolve()),'python_executable_sha256':sha(Path(sys.executable).read_bytes()),'platform':platform.platform(),'openpyxl':openpyxl.__version__,'lxml':'.'.join(map(str,ET.LXML_VERSION)),'libxml2':'.'.join(map(str,ET.LIBXML_VERSION))},'primary_sources':SOURCES,'setup_failures':[]}
    report['tool_module_hashes'] = {str(Path(module.__file__).resolve()):fingerprint(Path(module.__file__)) for module in [openpyxl,openpyxl.cell.text,openpyxl.comments.comment_sheet,openpyxl.reader.excel,ET]}

    def valid_comments(rows, count):
        return (isinstance(rows,list) and len(rows)==count
                and all(isinstance(row,dict) and set(row)=={'cell','text','author'}
                        and all(isinstance(row[key],str) for key in row) for row in rows)
                and len({row['cell'] for row in rows})==len(rows))

    try:
        actual_paths = list(folder.iterdir())
        if ({path.name for path in actual_paths} != {path.name for path in inputs}
                or any(path.is_symlink() or not path.is_file() for path in actual_paths)):
            raise ValueError('Exactly eleven regular authored fixture files are required')
    except Exception as error:
        report['setup_failures'].append({'code':'input_inventory','error':repr(error)})
    expected = []
    try:
        expected = json.loads(expected_path.read_text())
        if not valid_comments(expected,6):
            raise ValueError('Expected six unique {cell,text,author} string rows')
    except Exception as error:
        report['setup_failures'].append({'code':'expected_fixture_manifest','error':repr(error)})
    collisions = []
    try:
        manifest = json.loads(collisions_path.read_text())
        collisions = manifest['cases']
        if (manifest.get('schema_version') != 1 or not isinstance(collisions,list)
                or len(collisions)!=6 or {row['file'] for row in collisions} != collision_names):
            raise ValueError('Expected all six authored collision lifecycle cases')
        shared_orphans = {}
        required = {'file','phase','sheet_name','orphan_part','orphan_base64','orphan_content_type',
                    'orphan_relationships_part','orphan_relationships_base64','comments',
                    'original_sheet_name','original_comments'}
        for row in collisions:
            phase = row['phase']
            kind = row['file'].split('-')[1]
            if (set(row) != required or row['file'] != f'collision-{kind}-{phase}.xlsx'
                    or phase not in ('empty','added','cleared')
                    or row['sheet_name'] != 'Added' or row['original_sheet_name'] != 'Original'
                    or row['orphan_part'] != 'xl/comments2.xml'
                    or row['orphan_relationships_part'] != relationship_path(row['orphan_part'])
                    or row['orphan_content_type'] != COMMENTS_TYPE
                    or not valid_comments(row['comments'],1 if phase=='added' else 0)
                    or not valid_comments(row['original_comments'],1)):
                raise ValueError('Unexpected collision fixture manifest shape or lifecycle phase')
            orphan = base64.b64decode(row['orphan_base64'],validate=True)
            rels = base64.b64decode(row['orphan_relationships_base64'],validate=True)
            if not orphan or not rels:
                raise ValueError('Original orphan XML and relationship bytes must be nonempty')
            shared = (orphan,rels,row['original_comments'])
            if kind in shared_orphans and shared_orphans[kind] != shared:
                raise ValueError('Original orphan bytes and original notes must remain the same across a lifecycle')
            shared_orphans[kind] = shared
            # Inspect the authored relationship sentinel only. Never resolve its URL.
            relationships = ET.fromstring(rels,parser=ET.XMLParser(resolve_entities=False,no_network=True,load_dtd=False))
            sentinels = list(relationships)
            if (relationships.tag != '{'+P+'}Relationships' or len(sentinels)!=1
                    or sentinels[0].tag != '{'+P+'}Relationship'
                    or dict(sentinels[0].attrib) != {'Id':'rIdAudit','Type':'urn:example:orphan-audit',
                                                    'Target':'https://example.test/orphan','TargetMode':'External'}):
                raise ValueError('Missing exact authored external orphan relationship sentinel')
        if shared_orphans['valid'][0] == shared_orphans['malformed'][0]:
            raise ValueError('Valid and invalid-root orphan cases need different authored payloads')
    except Exception as error:
        report['setup_failures'].append({'code':'collision_fixture_manifest','error':repr(error)})
    report['expected_comments'] = expected
    report['cycles'] = [verify_file(path,expected) for path in files] if not report['setup_failures'] else []
    report['collisions'] = []
    if not report['setup_failures']:
        for row in collisions:
            original = verify_file(folder/row['file'],row['original_comments'],sheet_name=row['original_sheet_name'],sheet_names=['Original','Added'],collision=row)
            added = verify_file(folder/row['file'],row['comments'],sheet_name=row['sheet_name'],sheet_names=['Original','Added'],collision=row)
            independent_parts = (original.get('comments_part') is not None
                                 and added.get('comments_part') is not None
                                 and original['comments_part'] != added['comments_part'])
            failures = [*original['failures'],*added['failures']]
            if not independent_parts:
                failures.append({'code':'worksheets_have_separate_comments_authority','location':row['file'],
                                 'actual':[original.get('comments_part'),added.get('comments_part')],
                                 'expected':'Distinct explicitly owned comments parts for Original and Added'})
            report['collisions'].append({'file':row['file'],'phase':row['phase'],
                'checks':original['checks']+added['checks']+1,'failures':failures,
                'worksheets':[original,added],
                'orphan':{'part':row['orphan_part'],'content_type':row['orphan_content_type'],
                          **{'bytes':len(base64.b64decode(row['orphan_base64'])), 'sha256':sha(base64.b64decode(row['orphan_base64']))}},
                'orphan_relationships':{'part':row['orphan_relationships_part'],
                          **{'bytes':len(base64.b64decode(row['orphan_relationships_base64'])), 'sha256':sha(base64.b64decode(row['orphan_relationships_base64']))}},
                'success':not failures})
    after = {p.name: fingerprint(p) for p in inputs if p.is_file()}
    report['inputs_after'] = after
    report['inputs_unchanged'] = before == after
    all_cases = [*report['cycles'],*report['collisions']]
    report['failure_counts'] = dict(Counter(f['code'] for case in all_cases for f in case['failures']))
    report['checks'] = sum(case['checks'] for case in all_cases)
    report['success'] = (not report['setup_failures'] and len(report['cycles'])==3
                         and len(report['collisions'])==6 and all(case['success'] for case in all_cases)
                         and report['inputs_unchanged'])
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    report['scope'] = 'Nine actual generated XLSX files: three six-comment repeated saves plus two orphan kinds through empty/add/clear save-reopen lifecycles. Independent ZIP/CRC, exact worksheet inventories, explicitly owned comments relationships, SpreadsheetML namespaces, author tables and plain CT_Rst checks plus openpyxl exact text/author reads. Collision cases also preserve original worksheet notes and unrelated XML/relationship bytes and content type, and require a distinct valid empty comments authority after clearing. The deliberately invalid orphan root is preserved without being treated as an owned comments part. Byte hashes bind checked outputs; the enclosing source-bound generator receipt proves their origin. No rich text, VML geometry, external Excel execution or broad Open XML schema certification.'
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'success':report['success'],'cycles':len(report['cycles']),'collisions':len(report['collisions']),'checks':report['checks'],'failures':report['failure_counts'],'setup_failures':report['setup_failures'],'report':str(args.report)},indent=2))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
