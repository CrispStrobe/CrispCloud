#!/usr/bin/env python3
"""Run the actual POSIX attach body before/after the Screen tab delimiter fix."""

from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
SOURCE = 'lib/models/screen_session_options.dart'
BASELINE = 'bb300164'
OUTPUT = Path(__file__).with_suffix('.json')


def attach_script(source):
    return source.split("static const _attachScript = r'''", 1)[1].split("'''", 1)[0]


baseline_sha = subprocess.check_output(
    ['git', 'rev-parse', BASELINE], cwd=ROOT, text=True
).strip()
baseline = subprocess.check_output(
    ['git', 'show', baseline_sha + ':' + SOURCE], cwd=ROOT, text=True
)
fixed = (ROOT / SOURCE).read_text()
scripts = {'before': attach_script(baseline), 'after': attach_script(fixed)}
cases = []


def add(label, target, rows, expected, expected_arguments=None):
    cases.append({
        'case': label,
        'target': target,
        'listing': 'There are screens on:\n'
        + ''.join('\t' + row + '\n' for row in rows)
        + str(len(rows)) + ' Sockets in /run/screen/S-alice.\n',
        'expected_exit': expected,
        'expected_arguments': expected_arguments,
    })


for dated, stamp in [('undated', ''), ('dated', '\t(11/15/26 20:15:00)')]:
    add('exact ' + dated, 'work', ['123.work' + stamp + '\t(Detached)'],
        0, ['-x', '123.work'])
    for label, suffix in [('trailing tab', '\t'), ('repeated tabs', '\t\t'),
                          ('tab and space', '\t '), ('space and tab', ' \t')]:
        for target in ['work', '123.work']:
            add(label + ' ' + dated + ' ' + target, target,
                ['123.work' + suffix + stamp + '\t(Detached)'], 44)
        add('prefix collision ' + label + ' ' + dated, '123.work',
            ['123.work' + stamp + '\t(Detached)',
             '456.123.work' + suffix + stamp + '\t(Detached)'], 47)
    add('exact and trailing tab coexist ' + dated, 'work',
        ['123.work' + stamp + '\t(Detached)',
         '456.work\t' + stamp + '\t(Detached)'], 0, ['-x', '123.work'])

for suffix in ['\t(11/15/26 20:15:00)', '\t\t(11/15/26 20:15:00)']:
    for target in ['work', '123.work']:
        add('timestamp text in dated name ' + repr(suffix) + ' ' + target,
            target, ['123.work' + suffix + '\t(11/15/26 20:16:00)\t(Detached)'], 44)

with tempfile.TemporaryDirectory(prefix='screen-tab-proof-', dir=ROOT.parent) as tmp:
    directory = Path(tmp)
    screen = directory / 'screen'
    screen.write_text('''#!/bin/sh
if [ "$1" = '-ls' ]; then
  cat "$CRISP_SCREEN_LISTING"
  exit 0
fi
printf '%s\\n' "$@" > "$CRISP_SCREEN_ARGUMENTS"
''')
    screen.chmod(0o700)
    listing = directory / 'listing'
    arguments = directory / 'arguments'
    environment = dict(os.environ, PATH=str(directory) + ':' + os.environ['PATH'],
                       CRISP_SCREEN_LISTING=str(listing),
                       CRISP_SCREEN_ARGUMENTS=str(arguments))
    for case in cases:
        listing.write_text(case['listing'])
        for stage, script in scripts.items():
            arguments.unlink(missing_ok=True)
            result = subprocess.run(
                ['/bin/sh', '-c', script, 'crispcloud-screen', case['target']],
                cwd=ROOT, env=environment, text=True, capture_output=True, timeout=5
            )
            actual_arguments = arguments.read_text().splitlines() if arguments.exists() else None
            case[stage] = {'exit_code': result.returncode, 'arguments': actual_arguments,
                           'stderr': result.stderr}
            case[stage]['passed'] = (
                result.returncode == case['expected_exit']
                and actual_arguments == case['expected_arguments']
            )

receipt = {
    'baseline_commit': baseline_sha,
    'source_path': SOURCE,
    'baseline_sha256': hashlib.sha256(baseline.encode()).hexdigest(),
    'fixed_sha256': hashlib.sha256(fixed.encode()).hexdigest(),
    'command': ['python3', str(Path(__file__).relative_to(ROOT))],
    'shell': '/bin/sh',
    'case_count': len(cases),
    'baseline_failed': sum(not case['before']['passed'] for case in cases),
    'fixed_passed': sum(case['after']['passed'] for case in cases),
    'fixed_failed': sum(not case['after']['passed'] for case in cases),
    'source_review': [
        {
            'url': 'https://sources.debian.org/src/screen/4.9.1-3/screen.c/',
            'finding': 'The -S handler checks length and emptiness. Socket-name construction copies the supplied name without tab normalization; slash handling is separate.'
        },
        {
            'url': 'https://sources.debian.org/src/screen/4.9.1-3/socket.c/',
            'finding': 'FindSocket emits one literal tab before the name, timestamp and state. A name ending with tabs therefore retains those bytes before the timestamp separator.'
        }
    ],
    'scope': 'Real command body with controlled producer output; this is not a live GNU Screen daemon test. No Flutter/Dart or GitHub CI process was run.',
    'cases': cases,
}
OUTPUT.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'cases'}, indent=2))
assert receipt['baseline_failed'] > 0
assert receipt['fixed_failed'] == 0
