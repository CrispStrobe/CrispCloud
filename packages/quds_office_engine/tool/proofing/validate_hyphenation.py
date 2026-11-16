#!/usr/bin/env python3
"""Run source-bound local hyphenation checks without GitHub Actions."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

PACKAGE = Path(__file__).resolve().parents[2]
REPO = PACKAGE.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dart', default='dart')
parser.add_argument('--output', type=Path, default=REPO / 'docs/validation/proofing-20261116')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
files = [
    'lib/src/bidi/line_breaker.dart', 'lib/src/bidi/german_hyphenator.dart',
    'lib/src/bidi/german_hyphenation_data.dart',
    'lib/src/bidi/english_hyphenator.dart', 'lib/src/bidi/office_hyphenator.dart',
    'lib/src/bidi/english_us_hyphenation_data.dart',
    'lib/src/bidi/english_gb_hyphenation_data.dart', 'lib/quds_office_engine.dart',
    'lib/src/word/layout/word_layout.dart', 'lib/src/word/layout/word_note_layout.dart',
    'lib/src/word/layout/word_table_row_layout.dart',
    'lib/src/word/model/wml_document.dart', 'lib/src/word/model/wml_run_edit.dart',
    'lib/src/word/properties/wml_properties.dart',
    'lib/src/word/serial/word_deserializer.dart', 'lib/src/word/serial/word_property_io.dart',
    'lib/src/word/serial/word_serializer.dart', 'lib/src/word/serial/word_settings_io.dart',
    'lib/src/word/serial/word_style_cascade.dart', 'test/proofing_hyphenation_test.dart',
    'third_party/hyphenation/hyph-de-1996.tex', 'third_party/hyphenation/README.md',
    'third_party/hyphenation/hyph-en-us.tex', 'third_party/hyphenation/hyph-en-gb.tex',
    'third_party/hyphenation/ENGLISH.md', 'third_party/hyphenation/english-manifest.json',
    'tool/proofing/generate_hyphenation.py', 'tool/proofing/generate_english_hyphenation.py',
    'tool/proofing/validate_hyphenation.py',
]
tests = [
    'proofing_hyphenation', 'english_hyphenation', 'variable_line_breaker', 'bidi', 'word_layout',
    'word_styles_layout', 'style_cascade', 'word_style_introduction',
    'styleless_import_fidelity', 'word_referenced_styles_and_breaks',
    'word_package_preservation', 'word_preserved_header', 'word_note_numbering',
    'word_footnote_reference', 'word_note_script_break', 'word_table_tall_frame_layout',
    'word_table_tall_toc_layout', 'word_table_nested_layout', 'word_small_caps',
    'office_pdf_export', 'arabic_pdf_export', 'word_zotero_bibliography_layout',
]
files += [f'test/{name}_test.dart' for name in tests if name != 'proofing_hyphenation']
def manifest():
    return {name: hashlib.sha256((PACKAGE / name).read_bytes()).hexdigest() for name in files}

before = manifest()
record = {
    'started_utc': datetime.now(timezone.utc).isoformat(),
    'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
    'dart_version': subprocess.check_output([args.dart, '--version'], text=True).strip(),
    'source_sha256': before,
    'checks': [],
    'github_actions': 'Not used or waited for.',
}
commands = [
    ('hyphenation-generator.log', [sys.executable, 'tool/proofing/generate_hyphenation.py']),
    ('english-hyphenation-generator.log', [sys.executable, 'tool/proofing/generate_english_hyphenation.py', '--check']),
    ('hyphenation-analysis.log', [args.dart, 'analyze', '--fatal-infos',
        *[name for name in files if name.endswith('.dart') and not name.endswith('_hyphenation_data.dart')]]),
    ('hyphenation-tests.log', [args.dart, 'test', '--concurrency=4', '--reporter=expanded',
        *[f'test/{name}_test.dart' for name in tests]]),
]
failed = False
for name, command in commands:
    path = args.output / name
    with path.open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=PACKAGE, stdout=log, stderr=subprocess.STDOUT)
    entry = {'command': command, 'exit_code': result.returncode,
             'log': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    record['checks'].append(entry)
    print(json.dumps(entry), flush=True)
    if result.returncode:
        print('\n'.join(path.read_text().splitlines()[-70:]), flush=True)
        failed = True
    else:
        print('\n'.join(path.read_text().splitlines()[-3:]), flush=True)
record['source_unchanged_after_checks'] = before == manifest()
record['finished_utc'] = datetime.now(timezone.utc).isoformat()
record['passed'] = not failed and record['source_unchanged_after_checks']
(args.output / 'hyphenation-validation.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'passed': record['passed'], 'receipt': str(args.output / 'hyphenation-validation.json')}), flush=True)
sys.exit(0 if record['passed'] else 1)
