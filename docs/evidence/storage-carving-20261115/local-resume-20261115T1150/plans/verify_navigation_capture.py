#!/usr/bin/env python3
"""Verify and retain fresh worksheet outputs and font/source-bound captures."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--capture-receipt', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() and any(output.iterdir()):
        ap.error('output must be empty; retain prior/failed evidence separately')
    metadata = json.loads((args.capture_receipt/'metadata.json').read_text())
    summary = json.loads((args.capture_receipt/'summary.json').read_text())
    assert metadata['qualification_success'] and metadata['inputs_and_commit_stable']
    assert metadata['returncode'] == 0 and metadata['suite_count'] == 1
    assert summary['qualification_success'] and summary['totals']['passed'] == 12
    assert all(summary['totals'][key] == 0 for key in ['failed','errors','skipped','other_results'])
    assert not summary['missing_suites'] and not summary['unexpected_suites']
    expected_suite = 'test/widget/office_sheet_navigation_workflow_test.dart'
    assert (args.capture_receipt/'suites.txt').read_text().splitlines() == [expected_suite]

    helper = repo/'docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/integrity/verify_hosted_artifacts.py'
    spec = importlib.util.spec_from_file_location('worksheet_semantics', helper)
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    books = repo/'build/office-sheet-navigation-acceptance'
    images = repo/'build/office-sheet-navigation-preview'
    generation_path = args.capture_receipt/'produced-files.json'
    generation = json.loads(generation_path.read_text())
    assert generation['tested_head'] == metadata['after_git']['head']
    assert generation['source_resolution_sha256'] == metadata['after_entries_sha256']
    actual_files = {str(path.relative_to(repo/'build')):
                    {'sha256': digest(path), 'size': path.stat().st_size}
                    for folder in (books, images) for path in folder.iterdir() if path.is_file()}
    assert actual_files == generation['files'], 'Capture artifacts differ from the passed generator gate'
    assert {p.name for p in books.iterdir() if p.is_file()} == set(verifier.NAVIGATION)
    navigation = [verifier.semantic_workbook(books/name, *expectation)
                  for name, expectation in verifier.NAVIGATION.items()]
    expected_images = {'rename-validation.png': (1600,1000,'en'),
                       'worksheet-arabic-narrow.png': (390,1000,'ar')}
    assert {p.name for p in images.iterdir() if p.is_file()} == {
        name+suffix for name in expected_images for suffix in ['', '.json']}
    font_paths = {'assets/fonts/Roboto-Regular.ttf', 'assets/fonts/Roboto-Medium.ttf',
                  'assets/fonts/Roboto-Bold.ttf',
                  'packages/quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
                  'packages/quds_office_editor/fonts/NotoNaskhArabic-Bold.ttf',
                  'test/store_assets/fixtures/MaterialIcons-Regular.otf'}
    captures = []
    for name, (width,height,locale) in expected_images.items():
        png = images/name
        receipt = json.loads((images/(name+'.json')).read_text())
        assert receipt['file'] == name and receipt['sha256'] == digest(png)
        assert (receipt['width'],receipt['height'],receipt['locale']) == (width,height,locale)
        assert receipt['device_pixel_ratio'] == 1
        assert receipt['capture'] == 'complete host render view including modal overlays'
        with Image.open(png) as image:
            assert image.size == (width,height) and image.format == 'PNG'
            image.verify()
        typography = receipt['preview_only_typography']
        assert typography['material_font_family'] == typography['office_font_family'] == 'OfficeNavigationPreviewRoboto'
        assert typography['material_font_family_fallback'] == ['Noto Naskh Arabic']
        assert typography['icon_font_family'] == 'MaterialIcons'
        assert typography['visible_material_icon_code_points']
        fonts = typography['fonts']
        assert len(fonts) == len(font_paths) and {item['asset'] for item in fonts} == font_paths
        for item in fonts:
            path = repo/item['asset']
            assert digest(path) == item['sha256'] and path.stat().st_size == item['bytes']
        sources = receipt['capture_sources']
        assert {item['path'] for item in sources} == {expected_suite,'test/support/office_test_harness.dart'}
        assert len(sources) == 2
        for item in sources:
            assert digest(repo/item['path']) == item['sha256']
        captures.append({'file': name, 'sha256':digest(png), 'width':width,'height':height,
                         'locale':locale,'font_assets_verified':len(fonts),'source_inputs_verified':len(sources)})
    output.mkdir(parents=True,exist_ok=True)
    for source, folder in [(books,'workbooks'),(images,'previews')]:
        (output/folder).mkdir()
        for path in source.iterdir():
            if path.is_file():
                shutil.copyfile(path,output/folder/path.name)
    result={'schema':1,'at':datetime.now(timezone.utc).isoformat(),
            'capture_tested_head':metadata['before_git']['head'],
            'capture_produced_files_receipt_sha256':digest(generation_path),
            'capture_source_resolution_sha256':generation['source_resolution_sha256'],
            'review_head':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),
            'verifier_sha256':digest(Path(__file__)), 'semantic_helper_sha256':digest(helper),
            'capture_machine_tests':12,'navigation_workbooks':navigation,'captures':captures,
            'success':True,'visual_inspection':'Required separately; numeric/font/source verification does not inspect glyph appearance or layout.',
            'scope':'Six actual source/current edit/undo/redo workbooks checked with independent Python ZIP/XML/Decimal readers; two complete-host PNG captures verified against exact font/source hashes and dimensions. No external Office rendering or broad schema claim.'}
    (output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    manifest={str(path.relative_to(output)):{'sha256':digest(path),'size':path.stat().st_size}
              for path in sorted(output.rglob('*')) if path.is_file()}
    (output/'artifacts-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'success':True,'workbooks':len(navigation),'captures':len(captures)},indent=2))


if __name__=='__main__':
    main()
