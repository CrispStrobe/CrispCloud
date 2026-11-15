#!/usr/bin/env python3
"""Independently re-read retained outputs from one immutable saved Git source."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from PIL import Image

REPO = Path('/workspace/scratch/0b93849cdeb9/CrispCloud')
OUT = Path('/workspace/scratch/0b93849cdeb9/audit-notes')
HEAD = 'cc92423bb98789239380864d5e8343c19c25e815'
BASE = 'docs/evidence/storage-carving-20261115/local-resume-20261115T1150'
SNAP = OUT/'output-recheck-snapshot'


def raw(path):
    return subprocess.check_output(['git', '-C', str(REPO), 'show', HEAD + ':' + path])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw(source))
    return destination


def main():
    assert not SNAP.exists(), 'Use a fresh output directory'
    SNAP.mkdir(parents=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    records = []
    def run(label, argv, cwd=SNAP):
        result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True)
        (OUT/(label+'.stdout.log')).write_bytes(result.stdout)
        (OUT/(label+'.stderr.log')).write_bytes(result.stderr)
        records.append({'label': label, 'argv': [str(x) for x in argv], 'returncode': result.returncode, 'stdout_sha256': sha(result.stdout), 'stderr_sha256': sha(result.stderr)})
        assert result.returncode == 0, (label, result.stderr.decode())
    png_checker = copy('test/support/check_archive_png_carving.py', SNAP/'test/support/check_archive_png_carving.py')
    copy('test/fixtures/archives/png-carving-reference-manifest.json', SNAP/'test/fixtures/archives/png-carving-reference-manifest.json')
    png = {}
    for runtime in ['vm', 'javascript']:
        candidate = copy(BASE+'/png-portable-final-artifacts/'+runtime+'-candidates.json', SNAP/(runtime+'-candidates.json'))
        report = OUT/('rechecked-'+runtime+'-png.json')
        run(runtime+'-png-recheck', [sys.executable, str(png_checker), '--candidates', str(candidate), '--report', str(report)])
        data = json.loads(report.read_text())
        old = json.loads(raw(BASE+'/png-portable-final-artifacts/'+runtime+'-python.json'))
        assert data == old, (runtime, 'independent verification differs')
        png[runtime] = {'archives': data['passed'], 'decoded_images': data['verifiedPngs'], 'wrong_expected_hash_rejected': data['wrongExpectedHashRejected'], 'report_sha256': sha(report.read_bytes()), 'matches_original_report': True}

    engine = 'packages/quds_office_engine/'
    for name in ['scripted_oracle.py', 'corpus.py', 'native_oracle.py', 'notes_oracle.py']:
        copy(engine+'tool/fidelity/'+name, SNAP/engine/'tool/fidelity'/name)
    for name in ['scripts/expected.json', 'word.docx', 'native.pptx']:
        copy(engine+'test/fixtures/fidelity/'+name, SNAP/engine/'test/fixtures/fidelity'/name)
    outputs = SNAP/'office-produced'
    generation = json.loads(raw(BASE+'/engine-final/produced-files.json'))
    for kind, extension in [('word','docx'), ('sheet','xlsx'), ('slide','pptx')]:
        for stem in ['edited', 'roundtrip-1', 'roundtrip-2', 'roundtrip-3']:
            name = f'{kind}/{stem}.{extension}'
            target = copy(BASE+'/scripted-oracle-final-artifacts/produced/'+name, outputs/name)
            expected = generation['files'][name]
            assert {'sha256': sha(target.read_bytes()), 'size': target.stat().st_size} == expected
    run('office-outputs-recheck', [sys.executable, str(SNAP/engine/'tool/fidelity/scripted_oracle.py'), str(outputs)])
    office = json.loads((outputs/'oracle-report.json').read_text())
    assert office == {'exports': 12, 'failures': []}

    helper_source = 'docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/integrity/verify_hosted_artifacts.py'
    helper = copy(helper_source, SNAP/'worksheet_semantics.py')
    spec = importlib.util.spec_from_file_location('worksheet_semantics', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    nav = json.loads(raw(BASE+'/navigation-capture-final/produced-files.json'))
    navigation = []
    for name, expectation in module.NAVIGATION.items():
        target = copy(BASE+'/navigation-independent-review-final-artifacts/workbooks/'+name, SNAP/'workbooks'/name)
        assert {'sha256': sha(target.read_bytes()), 'size': target.stat().st_size} == nav['files']['office-sheet-navigation-acceptance/'+name]
        navigation.append(module.semantic_workbook(target, *expectation))
    images = []
    expected_images = {'rename-validation.png': (1600,1000,'en'), 'worksheet-arabic-narrow.png': (390,1000,'ar')}
    for name, expected in expected_images.items():
        png_data = raw(BASE+'/navigation-independent-review-final-artifacts/previews/'+name)
        receipt = json.loads(raw(BASE+'/navigation-independent-review-final-artifacts/previews/'+name+'.json'))
        assert receipt['sha256'] == sha(png_data)
        assert (receipt['width'],receipt['height'],receipt['locale']) == expected
        assert {'sha256': sha(png_data), 'size': len(png_data)} == nav['files']['office-sheet-navigation-preview/'+name]
        with Image.open(io.BytesIO(png_data)) as image:
            assert image.size == expected[:2] and image.format == 'PNG'
            image.verify()
        for font in receipt['preview_only_typography']['fonts']:
            data = raw(font['asset'])
            assert sha(data) == font['sha256'] and len(data) == font['bytes']
        for source in receipt['capture_sources']:
            assert sha(raw(source['path'])) == source['sha256']
        images.append({'file': name, 'sha256': sha(png_data), 'dimensions': expected[:2], 'locale': expected[2], 'fonts_verified': len(receipt['preview_only_typography']['fonts']), 'capture_sources_verified': len(receipt['capture_sources'])})

    report = {'schema': 1, 'at': datetime.now(timezone.utc).isoformat(), 'audited_commit': HEAD, 'review_script_sha256': sha(Path(__file__).read_bytes()), 'png_rechecks': png, 'office_output_oracle': office, 'navigation_workbooks': navigation, 'images': images, 'commands': records, 'success': True, 'scope': 'Fresh independent Python ZIP, XML, decimal, CRC and Pillow pixel checks over retained engine/VM/JavaScript output bytes. Exact generation receipt bindings retained. No regenerated Dart/Flutter outputs, new-source runtime claim, external application rendering or broad Open XML schema claim.'}
    (OUT/'retained-output-recheck.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'success': True, 'office_outputs': 12, 'navigation_workbooks': len(navigation), 'png_archives': sum(x['archives'] for x in png.values()), 'decoded_png_images': sum(x['decoded_images'] for x in png.values()), 'navigation_images': len(images)}))


if __name__ == '__main__':
    main()
