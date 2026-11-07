"""Deterministic scratch ABI checks, separate from timed warm-cache scans."""
import ctypes as c
import json
import os
from pathlib import Path
import struct
import sys
import tempfile


if os.name != 'posix':
    raise SystemExit('This contract verifier requires POSIX symlinks and FIFOs; run on Linux/macOS.')

api = c.CDLL(sys.argv[1])
api.cc_create.restype = c.c_void_p
api.cc_run.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t, c.c_uint32]
api.cc_run.restype = c.c_int32
api.cc_cancel.argtypes = [c.c_void_p]
api.cc_metric.argtypes = [c.c_void_p, c.c_size_t]
api.cc_metric.restype = c.c_uint64
api.cc_pages.argtypes = [c.c_void_p]
api.cc_pages.restype = c.c_size_t
api.cc_page_ptr.argtypes = [c.c_void_p, c.c_size_t]
api.cc_page_ptr.restype = c.c_void_p
api.cc_page_len.argtypes = [c.c_void_p, c.c_size_t]
api.cc_page_len.restype = c.c_size_t
api.cc_destroy.argtypes = [c.c_void_p]


def scan(root, cancel=False):
    root = Path(root)
    encoded = os.fsencode(root)
    buffer = c.create_string_buffer(encoded)
    job = api.cc_create()
    assert job
    try:
        if cancel:
            api.cc_cancel(job)
        assert api.cc_run(job, buffer, len(encoded), 1) == 0
        metrics = [api.cc_metric(job, i) for i in range(10)]
        nodes, issues, lengths = [], [], []
        pages = api.cc_pages(job)
        assert 1 <= pages <= 2048
        for page in range(pages):
            length = api.cc_page_len(job, page)
            assert 16 <= length <= 65536
            lengths.append(length)
            data = c.string_at(api.cc_page_ptr(job, page), length)
            magic, version, kind, count = struct.unpack_from('<IIII', data)
            assert (magic, version) == (0x4353434e, 1)
            assert 1 <= count <= 500
            offset = 16
            for _ in range(count):
                if kind == 1:
                    fields = struct.unpack_from('<iBB2xQqQIIIII', data, offset)
                    parent, typ, flags, size, mtime, total, files, folders, unknown, links, name_len = fields
                    offset += 52
                    name = data[offset:offset + name_len].decode('utf-8')
                    offset += name_len
                    assert (not nodes) == (parent == -1)
                    assert -1 <= parent < len(nodes)
                    path = str(root) if parent < 0 else os.path.join(nodes[parent]['path'], name)
                    nodes.append(dict(parent=parent, type=typ, flags=flags,
                        size=size if flags & 2 else None,
                        mtime=mtime if flags & 4 else None,
                        bytes=total, files=files, folders=folders,
                        unknown=unknown, links=links, name=name, path=path))
                else:
                    assert kind == 2
                    code, path_len, message_len = struct.unpack_from('<III', data, offset)
                    offset += 12
                    path = data[offset:offset + path_len].decode('utf-8')
                    offset += path_len
                    message = data[offset:offset + message_len].decode('utf-8')
                    offset += message_len
                    issues.append(dict(code=code, path=path, message=message))
            assert offset == length
        assert len(nodes) == metrics[5]
        assert len(issues) == metrics[6]
        assert sum(lengths) == metrics[9]
        return nodes, issues, metrics
    finally:
        api.cc_destroy(job)


checks = []
base = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='ffi-contract-', dir=base) as temporary:
    home = Path(temporary)
    root, outside = home / 'root', home / 'outside'
    root.mkdir()
    outside.mkdir()
    (root / 'payload').write_bytes(b'data')
    (root / '.hidden').write_bytes(b'abc')
    (root / 'empty').mkdir()
    (root / 'unicode-é🙂').write_bytes(b'xy')
    (root / 'back\\slash').write_bytes(b'z')
    (outside / 'must-not-appear').write_bytes(b'x' * 1000)
    (root / 'dir-link').symlink_to(outside, target_is_directory=True)
    (root / 'file-link').symlink_to(outside / 'must-not-appear')
    (root / 'broken-link').symlink_to(outside / 'absent')
    os.mkfifo(root / 'unsupported-fifo')

    nodes, issues, metrics = scan(root)
    n = nodes[0]
    assert (n['bytes'], n['files'], n['folders'], n['unknown'], n['links']) == (10, 5, 1, 1, 3)
    assert not n['flags'] & 1
    assert len(issues) == 1 and issues[0]['code'] == 2
    assert issues[0]['path'].endswith('/unsupported-fifo')
    assert not any('must-not-appear' in node['path'] for node in nodes)
    assert all(node['size'] is None for node in nodes if node['type'] == 2)
    by_name = {node['name']: node for node in nodes}
    assert by_name['back\\slash']['size'] == 1
    assert by_name['unicode-é🙂']['size'] == 2
    assert by_name['empty']['flags'] & 1
    checks.append('links skipped; FIFO retained unknown; partial diagnostics; hidden/Unicode/backslash/empty preserved')

    link_root = home / 'linked-root'
    link_root.symlink_to(outside, target_is_directory=True)
    nodes, issues, metrics = scan(link_root)
    assert len(nodes) == 1 and nodes[0]['files'] == 0
    assert not nodes[0]['flags'] & 1
    assert issues[0]['code'] == 0
    checks.append('symlink root rejected without traversal')

    nodes, issues, metrics = scan(home / 'missing-root')
    assert len(nodes) == 1 and issues[0]['code'] == 0
    assert not nodes[0]['flags'] & 1
    checks.append('missing root retained as incomplete diagnostic')

    nodes, issues, metrics = scan(root, cancel=True)
    assert len(nodes) == 1 and metrics[8] & 1
    assert not nodes[0]['flags'] & 1
    checks.append('pre-cancelled job returns partial root and cancellation flag')

    deep = home / 'deep'
    deep.mkdir()
    path = deep
    for _ in range(202):
        path = path / 'd'
        path.mkdir()
    (path / 'too-deep').write_bytes(b'no')
    nodes, issues, metrics = scan(deep)
    assert metrics[8] & 2 and not nodes[0]['flags'] & 1
    assert nodes[0]['folders'] == 201 and nodes[0]['files'] == 0
    assert any(issue['code'] == 3 for issue in issues)
    checks.append('depth limit retains discovered directory boundary and marks partial')

    errors = home / 'many-errors'
    errors.mkdir()
    for i in range(1100):
        os.mkfifo(errors / f'fifo-{i:04}')
    nodes, issues, metrics = scan(errors)
    assert nodes[0]['unknown'] == 1100 and nodes[0]['bytes'] == 0
    assert len(issues) == 1000 and metrics[7] == 100
    assert not nodes[0]['flags'] & 1
    checks.append('diagnostic cap preserves suppressed count and all unknown nodes')

print(json.dumps(dict(passed=len(checks), checks=checks,
    limitations=['No permission-denial oracle while running as root.',
        'No concurrent replacement-race test; prototype is not race-proof.',
        'Entry and memory limits inspected but not stress-tested here.',
        'macOS/Windows/mobile scope and ABI builds not tested.']), indent=2))
