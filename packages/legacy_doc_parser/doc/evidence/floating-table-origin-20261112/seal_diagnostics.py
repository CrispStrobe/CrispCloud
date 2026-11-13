#!/usr/bin/env python3
"""Seal this investigation's explicit input roots without rewriting evidence."""
import argparse, hashlib, json, lzma, tarfile
from pathlib import Path, PurePosixPath

def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def safe_path(value):
    if (not isinstance(value, str) or not value or '\\' in value or
            '\x00' in value or ':' in value):
        raise ValueError('Invalid evidence path')
    path = PurePosixPath(value)
    if (not path.parts or path.is_absolute() or path.as_posix() != value or
            any(part in {'', '.', '..'} for part in path.parts)):
        raise ValueError('Unsafe evidence path: ' + value)
    return value

def file_record(value):
    if not isinstance(value, dict):
        raise ValueError('Invalid file record')
    name = safe_path(value.get('path'))
    size, digest = value.get('bytes'), value.get('sha256')
    if type(size) is not int or size < 0:
        raise ValueError('Invalid byte count for ' + name)
    if (not isinstance(digest, str) or len(digest) != 64 or
            any(char not in '0123456789abcdef' for char in digest)):
        raise ValueError('Invalid SHA-256 for ' + name)
    return name

def verify(directory):
    """Verify the durable archive without extracting or modifying any file."""
    manifest = json.loads((directory / 'diagnostics.manifest.json').read_text())
    if (manifest.get('schema') != 'legacy-doc-parser/floating-table-origin-diagnostics'
            or manifest.get('version') != 1):
        raise ValueError('Unknown diagnostic manifest format')
    archive_record = manifest.get('archive')
    archive_name = file_record(archive_record)
    if len(PurePosixPath(archive_name).parts) != 1:
        raise ValueError('Archive must be in the manifest directory')
    archive_path = directory / archive_name
    if archive_path.is_symlink() or not archive_path.is_file():
        raise ValueError('Archive is not a regular local file')
    if (archive_path.stat().st_size != archive_record['bytes'] or
            sha(archive_path) != archive_record['sha256']):
        raise ValueError('Archive size or SHA-256 differs')
    entries, count = manifest.get('files'), manifest.get('fileCount')
    if not isinstance(entries, list) or type(count) is not int or count != len(entries):
        raise ValueError('Manifest file count differs')
    expected = {}
    for entry in entries:
        name = file_record(entry)
        if name in expected:
            raise ValueError('Duplicate manifest member: ' + name)
        expected[name] = entry
    seen = set()
    with tarfile.open(archive_path, 'r:xz') as archive:
        for member in archive:
            name = safe_path(member.name)
            if member.type not in {tarfile.REGTYPE, tarfile.AREGTYPE}:
                raise ValueError('Non-regular archive member: ' + name)
            if name in seen:
                raise ValueError('Duplicate archive member: ' + name)
            seen.add(name)
            if name not in expected:
                raise ValueError('Unexpected archive member: ' + name)
            if member.size != expected[name]['bytes']:
                raise ValueError('Member size differs: ' + name)
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError('Member has no regular file data: ' + name)
            with stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != expected[name]['sha256']:
                raise ValueError('Member SHA-256 differs: ' + name)
    if seen != set(expected) or len(seen) != count:
        raise ValueError('Archive member coverage differs')
    return {'verified': True, 'fileCount': count,
            'archiveSha256': archive_record['sha256']}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--source',type=Path,help='Seal the original measurement roots')
    modes.add_argument('--verify',type=Path,metavar='DIRECTORY',
                       help='Verify an existing manifest/archive without extraction')
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.verify is not None:
        if args.output is not None:
            parser.error('--output is only valid with --source')
        print(json.dumps(verify(args.verify)))
        return
    if args.output is None:
        parser.error('--source requires --output')
    roots=['table-origin-variants','table-origin-controls',
           'table-origin-controls-native','floating-controls',
           'floating-context-matrix','floating-edge-matrix',
           'table-margin-schema-controls']
    files={}
    for name in roots:
        for path in sorted((args.source/name).rglob('*')):
            if any(part in {'profile','tmp'} for part in path.relative_to(args.source).parts):
                continue
            if path.is_symlink():
                raise ValueError('Unexpected evidence link: '+str(path))
            if path.is_file():
                files[path.relative_to(args.source).as_posix()]=path
    singles=['table-origin-variants.py','floating-controls.dart',
             'floating-controls-probe.py','floating-baseline-probe.py',
             'floating-export-probe.py','floating-export.log',
             'floating-context-matrix.dart','floating-context-matrix-probe.py',
             'floating-context-matrix.log','floating-edge-matrix.dart',
             'floating-edge-matrix-probe.py','floating-edge-matrix.log',
             'measure-table-pdf.py','verify-edge-pdf.py',
             'verify-final-table-converter.py','final-table-converter-equivalence.json',
             'table-margin-schema-controls.dart','table-padding-controls-receipt.json',
             'table-context-compile.log','table-context-tests.log',
             'table-tests-final.log','table-tests.log','table-tests-valid.log',
             'table-origin-controls-native.log','word16-main.log',
             'word16-f70c4be.log','word16-model-properties.json',
             'word16-source-observations.json','tables.dart',
             'word16-final-76fa966.docx']
    for name in singles:
        path=args.source/name
        if not path.is_file():raise FileNotFoundError(path)
        files[name]=path
    inventory=[{'path':name,'bytes':path.stat().st_size,'sha256':sha(path)}
               for name,path in sorted(files.items())]
    output=args.output/'diagnostics.tar.xz'
    if output.exists():raise FileExistsError(output)
    with lzma.open(output,'wb',preset=6) as zipped:
        with tarfile.open(fileobj=zipped,mode='w|',format=tarfile.USTAR_FORMAT) as archive:
            for item in inventory:
                info=tarfile.TarInfo(item['path']);info.size=item['bytes'];info.mode=0o644
                info.mtime=0;info.uid=info.gid=0;info.uname=info.gname=''
                with files[item['path']].open('rb') as source:archive.addfile(info,source)
    for item in inventory:assert sha(files[item['path']])==item['sha256']
    manifest={'schema':'legacy-doc-parser/floating-table-origin-diagnostics','version':1,
              'finalTableSourceCommit':'76fa966d9b2b68cce69ebeba013705c5577ef8ba',
              'incompleteCandidateCommit':'f70c4bef610353ec81e208f51552df35569eecb5',
              'pdfMeasurementRenderer':'PyMuPDF 1.26.6',
              'archive':{'path':output.name,'bytes':output.stat().st_size,'sha256':sha(output)},
              'fileCount':len(inventory),'excludedDerivedFiles':['Office profiles','temporary directories','compiled converter (hash retained in equivalence receipts)'],
              'files':inventory}
    (args.output/'diagnostics.manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    receipt = verify(args.output)
    print(json.dumps({**receipt, 'archive':manifest['archive']}))
if __name__=='__main__':main()
