#!/usr/bin/env python3
"""Build the repository validator directly with the official Roslyn compiler.

The .NET CLI's optional first-use NuGet migration requires an unavailable global
mutex in this workspace. This uses the SDK compiler and exact official NuGet
assemblies, without modifying the validator source or the SDK.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent
SOURCE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT.parent / 'quds_office_suite/tool/office-validation/Program.cs'
OUT = ROOT / 'validator'
OUT.mkdir(parents=True, exist_ok=True)
PACKAGES = [
    ('documentformat.openxml', '3.3.0', 'DocumentFormat.OpenXml.dll', '53a74167552d886f0e312540db12c86a6133a83bd698795f3be6e25fc091b9e7'),
    ('documentformat.openxml.framework', '3.3.0', 'DocumentFormat.OpenXml.Framework.dll', '5f539f1602b642198ec6ed3ec567eac3fff62309f6ec65e28db2751a488ec30d'),
    ('system.io.packaging', '8.0.1', 'System.IO.Packaging.dll', 'c5fd0101fa90bc84e89a906cbdfa7188bb6cffab11404cdd8cd0377ffabfbd8e'),
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

source_hash = digest(SOURCE)
dependencies = {}
urls = {}
for package, version, assembly, expected in PACKAGES:
    archive = ROOT / 'downloads' / f'{package}.{version}.nupkg'
    url = f'https://api.nuget.org/v3-flatcontainer/{package}/{version}/{archive.name}'
    if not archive.exists():
        subprocess.run(['curl', '-fL', '--connect-timeout', '20', '--max-time', '120', url, '-o', str(archive)], check=True)
    if digest(archive) != expected:
        raise RuntimeError(f'NuGet package hash mismatch: {archive.name}')
    with ZipFile(archive) as content:
        (OUT / assembly).write_bytes(content.read(f'lib/net8.0/{assembly}'))
    dependencies[archive.name] = expected
    dependencies[assembly] = digest(OUT / assembly)
    urls[archive.name] = url

sdk = '8.0.428'
runtime = '8.0.34'
dotnet = ROOT / 'dotnet/dotnet'
compiler = ROOT / f'dotnet/sdk/{sdk}/Roslyn/bincore/csc.dll'
reference_dir = ROOT / f'dotnet/packs/Microsoft.NETCore.App.Ref/{runtime}/ref/net8.0'
implicit = OUT / 'GlobalUsings.cs'
implicit.write_text('\n'.join(f'global using {name};' for name in [
    'System', 'System.Collections.Generic', 'System.IO', 'System.Linq',
    'System.Net.Http', 'System.Threading', 'System.Threading.Tasks',
]) + '\n')
output = OUT / 'OfficeValidation.dll'
response = OUT / 'compiler.rsp'
arguments = [
    '-nologo', '-target:exe', '-nostdlib+', '-langversion:12',
    '-nullable:enable', '-deterministic+', f'-out:{output}',
]
arguments += [f'-r:{p}' for p in sorted(reference_dir.glob('*.dll'))]
arguments += [f'-r:{OUT / assembly}' for _, _, assembly, _ in PACKAGES]
arguments += [str(implicit), str(SOURCE)]
response.write_text('\n'.join(json.dumps(arg) for arg in arguments) + '\n')
command = [str(dotnet), str(compiler), '@' + str(response)]
result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(OUT / 'build.log').write_text(result.stdout)
print(result.stdout, end='')
result.check_returncode()
if digest(SOURCE) != source_hash:
    raise RuntimeError('Validator source changed while compiling')
(OUT / 'OfficeValidation.runtimeconfig.json').write_text(json.dumps({
    'runtimeOptions': {'tfm': 'net8.0', 'framework': {'name': 'Microsoft.NETCore.App', 'version': runtime}}
}, indent=2) + '\n')
check = subprocess.run([str(dotnet), str(output), '--self-test'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(OUT / 'self-test.log').write_text(check.stdout)
print(check.stdout, end='')
check.check_returncode()
receipt = {
    'source': str(SOURCE), 'source_sha256': source_hash,
    'sdk': sdk, 'runtime': runtime,
    'compiler_sha256': digest(compiler),
    'dependencies_sha256': dependencies, 'dependency_urls': urls,
    'assembly_sha256': digest(output),
    'command': command, 'self_test_exit_code': check.returncode,
    'build_method': 'official SDK Roslyn compiler, unchanged source; CLI first-use mutex unavailable',
}
(OUT / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(f'Validator ready: {output}')
