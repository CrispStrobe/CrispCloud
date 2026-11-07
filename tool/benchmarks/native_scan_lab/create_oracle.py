"""Independent read-only fixture truth, including every file's microsecond mtime."""
import hashlib
import json
import os
from pathlib import Path
import platform
import stat
import sys

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
records = []
directories = []
totals = {}
for directory, names, filenames in os.walk(root, followlinks=False):
    names.sort()
    directory = Path(directory)
    relative_directory = directory.relative_to(root).as_posix()
    if relative_directory == '.':
        relative_directory = ''
    info = directory.stat(follow_symlinks=False)
    assert stat.S_ISDIR(info.st_mode), directory
    directories.append([relative_directory, info.st_mtime_ns // 1000])
    totals[relative_directory] = [0, 0, 0]
    for name in names:
        info = (directory / name).stat(follow_symlinks=False)
        assert stat.S_ISDIR(info.st_mode), directory / name
    for name in filenames:
        file = directory / name
        info = file.stat(follow_symlinks=False)
        assert stat.S_ISREG(info.st_mode), file
        relative = file.relative_to(root).as_posix()
        records.append([relative, info.st_size, info.st_mtime_ns // 1000])
        totals[relative_directory][0] += info.st_size
        totals[relative_directory][1] += 1
for relative in sorted(totals, key=lambda item: item.count('/') + bool(item), reverse=True):
    if relative == '':
        continue
    parent = relative.rpartition('/')[0]
    totals[parent][0] += totals[relative][0]
    totals[parent][1] += totals[relative][1]
    totals[parent][2] += totals[relative][2] + 1
records.sort()
directories.sort()
digest = hashlib.sha256(json.dumps(records, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
manifest = {
    'root': str(root),
    'files': len(records),
    'foldersExcludingRoot': len(directories) - 1,
    'logicalBytes': sum(row[1] for row in records),
    'filesSizeMtimeDigest': digest,
    'mtimeUnit': 'microseconds since Unix epoch; Python st_mtime_ns // 1000',
    'records': records,
    'directories': directories,
    'directoryTotals': totals,
    'createdBy': f'Python {platform.python_version()} os.walk + os.stat(follow_symlinks=False)',
}
output.write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')) + '\n')
print(json.dumps({key: value for key, value in manifest.items() if key not in {'records', 'directories', 'directoryTotals'}}, indent=2))
