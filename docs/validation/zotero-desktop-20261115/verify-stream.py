import collections
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
COMMIT = '3c4cd0e24ab36f4fd88363cbc8521455bda811c6'
SOURCE = 'https://codeload.github.com/CrispStrobe/CrispCloud/tar.gz/' + COMMIT
PREFIX = 'CrispCloud-' + COMMIT + '/'
manifest_bytes = (ROOT / 'office_fidelity_manifest.json').read_bytes()
manifest = json.loads(manifest_bytes)
metadata = json.loads((ROOT / 'git-managed-metadata.json').read_text())
manifest_git = json.loads((ROOT / 'manifest-git-metadata.json').read_text())
expected = {entry['path']:entry for entry in metadata['managed']}
if len(expected) != 2374 or metadata['git_failures']:
    raise RuntimeError('Incomplete or inconsistent Git metadata inventory')
local_manifest_blob = hashlib.sha1(b'blob '+str(len(manifest_bytes)).encode()+b'\0'+manifest_bytes).hexdigest()
if local_manifest_blob != manifest_git['sha']:
    raise RuntimeError('Fetched manifest bytes do not match exact Git tree blob')

class HashReader:
    def __init__(self, raw):
        self.raw = raw
        self.sha256 = hashlib.sha256()
        self.bytes_read = 0
    def read(self, size=-1):
        data = self.raw.read(size)
        self.sha256.update(data)
        self.bytes_read += len(data)
        return data

started = time.monotonic()
seen = collections.Counter()
all_seen = set()
failures = []
actual = []
tar_modes = collections.Counter()
total_members = 0
total_logical_bytes = 0
archived_manifest = None
request = urllib.request.Request(SOURCE, headers={'User-Agent':'Quds-Zotero-vendor-verification/1.0'})
print(json.dumps({'started':SOURCE,'managed_files':len(expected),'operation':'stream-only, no archive/extracted-file writes'}),flush=True)
with urllib.request.urlopen(request, timeout=60) as response:
    headers = {k:response.headers.get(k) for k in ['Content-Type','Content-Length','ETag','Last-Modified']}
    reader = HashReader(response)
    with tarfile.open(fileobj=reader, mode='r|gz') as archive:
        for member in archive:
            total_members += 1
            total_logical_bytes += member.size
            name = member.name
            if name in all_seen:
                failures.append({'kind':'duplicate_archive_path','path':name})
            all_seen.add(name)
            if name == PREFIX[:-1] and member.isdir():
                continue
            if not name.startswith(PREFIX):
                failures.append({'kind':'unexpected_archive_root','path':name})
                continue
            path = name[len(PREFIX):]
            if PurePosixPath(path).is_absolute() or '..' in PurePosixPath(path).parts:
                failures.append({'kind':'unsafe_archive_path','path':path})
                continue
            is_manifest = path == 'tool/office_fidelity_manifest.json'
            if path not in expected and not is_manifest:
                continue
            if not member.isfile() or member.issym() or member.islnk():
                failures.append({'kind':'non_regular_managed_file','path':path,'type':repr(member.type)})
                continue
            if member.mode & 0o7000:
                failures.append({'kind':'special_permission_bits','path':path,'mode':oct(member.mode)})
            git_mode = '100755' if member.mode & 0o111 else '100644'
            reference = manifest_git if is_manifest else expected[path]
            expected_mode = reference['mode'] if is_manifest else reference['git_mode']
            expected_blob = reference['sha'] if is_manifest else reference['git_blob']
            if git_mode != expected_mode:
                failures.append({'kind':'mode_mismatch','path':path,'archive_mode':oct(member.mode),'git_mode':expected_mode})
            if member.size != reference['size']:
                failures.append({'kind':'size_mismatch','path':path,'archive_size':member.size,'git_size':reference['size']})
            stream = archive.extractfile(member)
            sha256 = hashlib.sha256()
            git_sha1 = hashlib.sha1(b'blob '+str(member.size).encode()+b'\0')
            size = 0
            retained = [] if is_manifest else None
            while True:
                chunk = stream.read(1024*1024)
                if not chunk:
                    break
                sha256.update(chunk)
                git_sha1.update(chunk)
                size += len(chunk)
                if retained is not None:
                    retained.append(chunk)
            if size != member.size:
                failures.append({'kind':'short_file','path':path,'read':size,'expected':member.size})
            if git_sha1.hexdigest() != expected_blob:
                failures.append({'kind':'git_blob_mismatch','path':path,'actual':git_sha1.hexdigest(),'expected':expected_blob})
            if is_manifest:
                archived_manifest = b''.join(retained)
                if archived_manifest != manifest_bytes:
                    failures.append({'kind':'manifest_bytes_mismatch'})
                continue
            seen[path] += 1
            if seen[path] != 1:
                failures.append({'kind':'duplicate_managed_path','path':path})
            if sha256.hexdigest() != reference['sha256']:
                failures.append({'kind':'manifest_sha256_mismatch','path':path,'actual':sha256.hexdigest(),'expected':reference['sha256']})
            tar_modes[oct(member.mode)] += 1
            actual.append({'path':path,'size':size,'git_mode':git_mode,'tar_mode':oct(member.mode),'git_blob':git_sha1.hexdigest(),'sha256':sha256.hexdigest(),'source':reference['source']})
            if len(actual) % 500 == 0:
                print(json.dumps({'checked':len(actual),'archive_bytes_read':reader.bytes_read,'elapsed_seconds':round(time.monotonic()-started,1)}),flush=True)
    while reader.read(1024*1024):
        pass
    archive_sha256 = reader.sha256.hexdigest()
    archive_bytes = reader.bytes_read
missing = sorted(set(expected)-set(seen))
if missing:
    failures.append({'kind':'missing_managed_files','paths':missing})
if archived_manifest is None:
    failures.append({'kind':'missing_archived_manifest'})
actual.sort(key=lambda e:e['path'])
inventory_text = 'path\tsize\tgit_mode\ttar_mode\tgit_blob\tsha256\tsource\n' + ''.join('\t'.join(str(e[k]) for k in ['path','size','git_mode','tar_mode','git_blob','sha256','source'])+'\n' for e in actual)
(ROOT / 'verified-managed-files.tsv').write_text(inventory_text)
receipt = {
    'checked_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
    'crispcloud_commit':COMMIT,
    'crispcloud_tree':metadata['crispcloud']['root_tree'],
    'source_commit':manifest['source_commit'],
    'source_tree':metadata['quds']['root_tree'],
    'standalone_sources':manifest['standalone_sources'],
    'stream_source':SOURCE,
    'archive_sha256':archive_sha256,
    'compressed_archive_bytes_streamed':archive_bytes,
    'archive_response_headers':headers,
    'archive_members_read':total_members,
    'archive_logical_bytes_traversed':total_logical_bytes,
    'managed_count_expected':len(expected),
    'managed_count_verified':len(actual),
    'source_counts':dict(collections.Counter(e['source'] for e in actual)),
    'managed_bytes_verified':sum(e['size'] for e in actual),
    'mode_counts':dict(collections.Counter(e['git_mode'] for e in actual)),
    'archive_permission_counts':dict(tar_modes),
    'permission_check':'Regular files only; reject special permission bits; compare executable-bit class against exact Git mode (GitHub tar group-write bits do not change Git executable mode). Source and target Git modes also match exactly.',
    'manifest_sha256':hashlib.sha256(manifest_bytes).hexdigest(),
    'manifest_git_blob':local_manifest_blob,
    'manifest_matches_archived_bytes':archived_manifest==manifest_bytes,
    'inventory_sha256':hashlib.sha256(inventory_text.encode()).hexdigest(),
    'git_metadata_counts':{'quds':sum(e['source']=='quds' for e in expected.values()),'legacy':sum(e['source']=='legacy' for e in expected.values())},
    'git_metadata_result':'All managed target blobs, sizes, types and modes matched the pinned canonical source trees. All Git tree responses were nontruncated.',
    'elapsed_seconds':round(time.monotonic()-started,2),
    'archive_saved':False,
    'managed_files_extracted_to_disk':False,
    'failures':failures,
    'result':'passed' if not failures else 'failed',
}
(ROOT / 'vendor-stream-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2),flush=True)
if failures:
    raise SystemExit(1)
