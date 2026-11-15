#!/usr/bin/env python3
"""Verify three actual XLSX comment outputs independently of the Dart engine.

This checks the generated plain-comment profile with lxml/zipfile and reads
comment text/author values with openpyxl. It is not full Open XML validation.
All observed failures are retained; one malformed cycle does not hide the rest.
"""
import argparse
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


def verify_file(path, expected):
    result = {'file': path.name, 'checks': 0, 'failures': [], 'comments': [], 'external_reader': {'name': 'openpyxl', 'version': openpyxl.__version__}}
    def check(ok, code, actual=None, wanted=None, location=None):
        result['checks'] += 1
        if not ok:
            result['failures'].append({'code': code, 'location': location or path.name, 'actual': actual, 'expected': wanted})
        return bool(ok)
    def parse(data):
        return ET.fromstring(data, parser=ET.XMLParser(resolve_entities=False, no_network=True, load_dtd=False, remove_blank_text=False))
    try:
        data = path.read_bytes()
        result['input'] = {'bytes': len(data), 'sha256': sha(data)}
    except Exception as error:
        check(False, 'input_read', repr(error), 'Readable XLSX output')
        result['success'] = False
        return result
    sheet_name = None
    try:
        with ZipFile(io.BytesIO(data)) as archive:
            names = archive.namelist()
            check(len(names) == len(set(names)), 'zip_unique_members', len(names), len(set(names)))
            check(archive.testzip() is None, 'zip_crc', archive.testzip(), None)
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
                sheets = book.findall('{'+S+'}sheets/{'+S+'}sheet')
                if check(len(sheets) == 1, 'fixture_worksheet_count', len(sheets), 1):
                    sheet_name = sheets[0].get('name')
                    sheet_uri = one_target(book_uri, relationships(book_uri), 'worksheet', sheets[0].get('{'+R+'}id'))
                    if sheet_uri is not None:
                        result.update(worksheet_name=sheet_name, worksheet_part=sheet_uri)
                        comments_uri = one_target(sheet_uri, relationships(sheet_uri), 'comments')
                        if comments_uri is not None:
                            result['comments_part'] = comments_uri
                            content_types = parse(archive.read('[Content_Types].xml'))
                            declared = [e.get('ContentType') for e in content_types.findall('{'+C+'}Override') if e.get('PartName') == '/'+comments_uri]
                            check(declared == [COMMENTS_TYPE], 'comments_content_type', declared, [COMMENTS_TYPE], comments_uri)
                            comment_root = parse(archive.read(comments_uri))
                            check(local(comment_root) == 'comments', 'comments_root_name', local(comment_root), 'comments', comments_uri)
                            for element in comment_root.iter():
                                if isinstance(element.tag, str):
                                    check(ET.QName(element).namespace == S, 'comments_element_namespace', element.tag, S, comments_uri+':'+local(element))
                            root_children = [local(e) for e in comment_root if isinstance(e.tag, str)]
                            check(root_children[:2] == ['authors', 'commentList'] and all(x == 'extLst' for x in root_children[2:]), 'comments_child_order', root_children, ['authors','commentList'], comments_uri)
                            author_roots = children(comment_root, 'authors')
                            author_values = []
                            if check(len(author_roots) == 1, 'authors_count', len(author_roots), 1, comments_uri):
                                author_values = [''.join(e.itertext()) for e in children(author_roots[0], 'author')]
                                wanted_authors = list(dict.fromkeys(row['author'] for row in expected))
                                check(author_values == wanted_authors, 'author_table_first_seen_identity', author_values, wanted_authors, comments_uri)
                            lists = children(comment_root, 'commentList')
                            if check(len(lists) == 1, 'comment_list_count', len(lists), 1, comments_uri):
                                comments = children(lists[0], 'comment')
                                actual_refs = [comment.get('ref') for comment in comments]
                                wanted_refs = [row['cell'] for row in expected]
                                check(actual_refs == wanted_refs, 'comment_cell_inventory', actual_refs, wanted_refs, comments_uri)
                                expected_by_ref = {row['cell']: row for row in expected}
                                for comment in comments:
                                    ref = comment.get('ref')
                                    location = comments_uri+':'+str(ref)
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
                                        check(not (container.text or '').strip(), 'rst_has_no_bare_text', container.text, 'Text in child t', location)
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
        if check(len(book.worksheets) == 1, 'openpyxl_sheet_count', len(book.worksheets), 1):
            sheet = book[sheet_name] if sheet_name in book.sheetnames else book.worksheets[0]
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
    files = [folder/f'comments-cycle-{cycle}.xlsx' for cycle in range(1,4)]
    inputs = [expected_path, *files]
    before = {p.name: fingerprint(p) for p in inputs if p.is_file()}
    report = {'schema':1,'started_at':datetime.now(timezone.utc).isoformat(),'oracle_script_sha256':sha(Path(__file__).read_bytes()),'input_directory':str(folder),'inputs_before':before,'tools':{'python':sys.version,'python_executable':str(Path(sys.executable).resolve()),'python_executable_sha256':sha(Path(sys.executable).read_bytes()),'platform':platform.platform(),'openpyxl':openpyxl.__version__,'lxml':'.'.join(map(str,ET.LXML_VERSION)),'libxml2':'.'.join(map(str,ET.LIBXML_VERSION))},'primary_sources':SOURCES,'setup_failures':[]}
    report['tool_module_hashes'] = {str(Path(module.__file__).resolve()):fingerprint(Path(module.__file__)) for module in [openpyxl,openpyxl.cell.text,openpyxl.comments.comment_sheet,openpyxl.reader.excel,ET]}
    expected = []
    try:
        expected = json.loads(expected_path.read_text())
        if not isinstance(expected,list) or len(expected)!=6 or any(not isinstance(row,dict) or any(not isinstance(row.get(k),str) for k in ['cell','text','author']) for row in expected) or len({row['cell'] for row in expected})!=len(expected):
            raise ValueError('Expected six unique {cell,text,author} string rows')
    except Exception as error:
        report['setup_failures'].append({'code':'expected_fixture_manifest','error':repr(error)})
    report['expected_comments'] = expected
    report['cycles'] = [verify_file(path,expected) for path in files] if not report['setup_failures'] else []
    after = {p.name: fingerprint(p) for p in inputs if p.is_file()}
    report['inputs_after'] = after
    report['inputs_unchanged'] = before == after
    report['failure_counts'] = dict(Counter(f['code'] for cycle in report['cycles'] for f in cycle['failures']))
    report['checks'] = sum(cycle['checks'] for cycle in report['cycles'])
    report['success'] = not report['setup_failures'] and len(report['cycles'])==3 and all(cycle['success'] for cycle in report['cycles']) and report['inputs_unchanged']
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    report['scope'] = 'Three actual generated XLSX files, each containing six authored plain comments. Independent ZIP/CRC, owning relationship, SpreadsheetML namespace, author-table and plain CT_Rst text checks plus openpyxl exact text/author reads. Byte hashes bind the checked outputs, not their generation source; use with a separate source-bound generator receipt. No rich text, VML geometry, external Excel execution or broad Open XML schema certification.'
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'success':report['success'],'cycles':len(report['cycles']),'checks':report['checks'],'failures':report['failure_counts'],'setup_failures':report['setup_failures'],'report':str(args.report)},indent=2))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
