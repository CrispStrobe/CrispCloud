"""Compile the unchanged validator with the pinned SDK's direct Roslyn entrypoint.

The regular SDK CLI cannot initialize NuGet's named migration mutex when the
sandbox has no /tmp. This local build uses official net8 reference assemblies
and the exact NuGet versions declared by the project and package manifests.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from zipfile import ZipFile

root = Path(__file__).resolve().parent
sdk_root = root.parent / 'dotnet'
source = (Path(sys.argv[1]) if len(sys.argv) > 1 else
          Path('/workspace/scratch/e445bd9b965c/quds_office_suite/tool/office-validation/Program.cs'))
packages = {
    'documentformat.openxml.3.3.0.nupkg': 'DocumentFormat.OpenXml.dll',
    'documentformat.openxml.framework.3.3.0.nupkg': 'DocumentFormat.OpenXml.Framework.dll',
    'system.io.packaging.8.0.1.nupkg': 'System.IO.Packaging.dll',
}
hashes = {}
for package, assembly in packages.items():
    archive = root / package
    hashes[package] = hashlib.sha256(archive.read_bytes()).hexdigest()
    with ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError('Corrupt package: ' + package)
        data = bundle.read('lib/net8.0/' + assembly)
    (root / assembly).write_bytes(data)
    hashes[assembly] = hashlib.sha256(data).hexdigest()

usings = root / 'ImplicitUsings.cs'
usings.write_text('\n'.join('global using global::' + name + ';' for name in (
    'System', 'System.Collections.Generic', 'System.IO', 'System.Linq',
    'System.Net.Http', 'System.Threading', 'System.Threading.Tasks')) + '\n')
references = sorted((sdk_root / 'packs/Microsoft.NETCore.App.Ref/8.0.34/ref/net8.0').glob('*.dll'))
references += [root / assembly for assembly in packages.values()]
command = [str(sdk_root / 'dotnet'),
           str(sdk_root / 'sdk/8.0.428/Roslyn/bincore/csc.dll'),
           '-nologo', '-target:exe', '-nullable:enable', '-langversion:12',
           '-out:' + str(root / 'OfficeValidation.dll')]
command += ['-reference:' + str(reference) for reference in references]
command += [str(usings), str(source)]
subprocess.run(command, check=True)
(root / 'OfficeValidation.runtimeconfig.json').write_text(json.dumps({
    'runtimeOptions': {'tfm': 'net8.0', 'framework': {
        'name': 'Microsoft.NETCore.App', 'version': '8.0.34'}}}, indent=2) + '\n')
(root / 'build-receipt.json').write_text(json.dumps({
    'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'sdk': '8.0.428', 'runtime': '8.0.34', 'dependencies_sha256': hashes,
    'assembly_sha256': hashlib.sha256((root / 'OfficeValidation.dll').read_bytes()).hexdigest(),
}, indent=2) + '\n')
print('Built validator from', source)
