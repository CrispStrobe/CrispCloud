from pathlib import Path
from html.parser import HTMLParser
import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess

HARNESS = Path(__file__).resolve().parent
argument_parser = argparse.ArgumentParser()
argument_parser.add_argument('--workspace', type=Path, required=True)
argument_parser.add_argument('--build', type=Path, required=True)
argument_parser.add_argument('--output', type=Path, required=True)
argument_parser.add_argument('--node', default='node')
arguments = argument_parser.parse_args()
ROOT = arguments.output.resolve()
BUILD = arguments.build.resolve()
WORKSPACE = arguments.workspace.resolve()
APP = WORKSPACE / 'CrispCloud'
UPSTREAM = WORKSPACE / 'file-viewer'
NATIVE = APP / 'packages/legacy_doc_parser'
NODE = arguments.node

CASES = [
    ('native-formatting', NATIVE / 'test/fixtures/word_native/formatting.doc'),
    ('native-list-continue', NATIVE / 'test/fixtures/word_native/list-continue.doc'),
    ('native-list-restart', NATIVE / 'test/fixtures/word_native/list-restart.doc'),
    ('native-linked-textboxes', NATIVE / 'test/fixtures/word_native/linked-textboxes-extended.doc'),
    ('native-note-table', NATIVE / 'test/fixtures/word_native/note-table-ending.doc'),
    ('native-header-table', NATIVE / 'test/fixtures/word_native/header-ending-table.doc'),
    ('native-footer-paragraph', NATIVE / 'test/fixtures/word_native/footer-ending-paragraph.doc'),
    ('native-bookmark-link', NATIVE / 'test/fixtures/word_native/bookmarks-native-hyperlink.doc'),
    ('native-officeart', NATIVE / 'test/fixtures/fidelity/officeart-shapes.doc'),
    ('native-word14-textbox', NATIVE / 'test/fixtures/word_native/word14-margin-origin.doc'),
    ('native-image-quarter', NATIVE / 'test/fixtures/fidelity/image-appearance/binary/floating-quarter.doc'),
    ('upstream-revisions', UPSTREAM / 'packages/renderers/doc/test/fixtures/native-revisions/native-revisions.doc'),
    ('upstream-revisions-final', UPSTREAM / 'packages/renderers/doc/test/fixtures/native-revisions/native-revisions-final.doc'),
    ('upstream-revisions-original', UPSTREAM / 'packages/renderers/doc/test/fixtures/native-revisions/native-revisions-original.doc'),
    ('upstream-image-embedded', UPSTREAM / 'packages/renderers/doc/test/fixtures/image-embedded.doc'),
    ('upstream-image-linked', UPSTREAM / 'packages/renderers/doc/test/fixtures/image-linked.doc'),
    ('upstream-template-dot', UPSTREAM / 'apps/viewer-demo/public/example/template.dot'),
    ('upstream-wps-table', UPSTREAM / 'packages/renderers/doc/test/fixtures/github-34-wps-table.doc'),
    ('upstream-textbox-resume', UPSTREAM / 'packages/renderers/doc/test/fixtures/github-171-textbox-resume.doc'),
]

class Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)
    def handle_starttag(self, tag, attrs):
        if tag in ('p','br','tr','td','th','div','li','section'): self.parts.append(' ')
    def handle_endtag(self, tag):
        if tag in ('p','br','tr','td','th','div','li','section'): self.parts.append(' ')

def normal_html(value):
    parser = Text()
    parser.feed(value)
    return re.sub(r'\s+', ' ', ''.join(parser.parts)).strip()

def digest(value):
    return hashlib.sha256(value).hexdigest()

def invoke(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        if result.returncode:
            return {'ok':False,'processError':result.returncode,'error':result.stderr[:2000]}
        return json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        return {'ok':False,'timeoutSeconds':20,'error':'Probe process exceeded timeout'}

def one(case):
    name, path = case
    source_hash = digest(path.read_bytes())
    native = invoke([str(BUILD/'native_probe'),str(path)])
    upstream = invoke([NODE,str(BUILD/'upstream_probe.mjs'),str(path)])
    if digest(path.read_bytes()) != source_hash: raise RuntimeError('Fixture changed')
    raw = {'id':name,'sourcePath':str(path.relative_to(WORKSPACE)),
           'sourceSha256':source_hash,'bytes':path.stat().st_size,
           'native':native,'upstream':upstream}
    (ROOT/'raw'/f'{name}.json').write_text(json.dumps(raw,ensure_ascii=False,indent=2)+'\n')
    summary = {k:v for k,v in raw.items() if k not in ('native','upstream')}
    for label, result in [('native',native),('upstream',upstream)]:
        safe = {k:v for k,v in result.items() if k not in ('html','plainText','stories','elapsedMs')}
        if result.get('ok'):
            html = result['html'] if label=='native' else result['html']['all']
            text = normal_html(html)
            safe.update({'previewTextCodepoints':len(text),'previewTextSha256':digest(text.encode()),
                         'previewTableTags':len(re.findall(r'<table\b',html)),
                         'previewImageTags':len(re.findall(r'<img\b',html)),
                         'previewSvgTags':len(re.findall(r'<svg\b',html))})
            if label=='native':
                safe['stories']=[{'kind':s['kind'],'textCodepoints':len(s['plainText']),
                                 'textSha256':digest(s['plainText'].encode())} for s in result['stories']]
        summary[label]=safe
    if native.get('ok') and upstream.get('ok'):
        summary['sameNormalizedPreviewText'] = normal_html(native['html'])==normal_html(upstream['html']['all'])
    return summary

expected = json.loads((HARNESS/'results.json').read_text())
source_roots = {
    'native': NATIVE / 'lib',
    'upstreamDoc': UPSTREAM / 'packages/renderers/doc/src',
    'upstreamWord': UPSTREAM / 'packages/renderers/word/src',
}
for label, sources in json.loads((HARNESS/'source-hashes.json').read_text()).items():
    for relative, expected_hash in sources.items():
        if digest((source_roots[label] / relative).read_bytes()) != expected_hash:
            raise RuntimeError('Source differs from retained identity: ' + label + '/' + relative)
expected_hashes = {case['id']: case['sourceSha256'] for case in expected['cases']}
for case_id, path in CASES:
    if digest(path.read_bytes()) != expected_hashes[case_id]:
        raise RuntimeError('Fixture differs from retained source: ' + case_id)
(ROOT/'raw').mkdir(parents=True, exist_ok=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    summaries = list(executor.map(one,CASES))
revision = json.loads((ROOT/'raw/upstream-revisions.json').read_text())['upstream']['html']
revision_checks = {}
for mode in ('final', 'original'):
    reference = json.loads((ROOT/f'raw/upstream-revisions-{mode}.json').read_text())
    actual_text = normal_html(revision[mode])
    expected_text = normal_html(reference['upstream']['html']['all'])
    revision_checks[mode + 'MatchesIndependentlySaved' + mode.title() + 'NormalizedText'] = actual_text == expected_text
    revision_checks[mode + 'NormalizedTextCodepoints'] = len(actual_text)
receipt = {'scope':'parser plus generated HTML; no browser/native Office rendering',
           'fileViewerCommit':'d264009ca6efb3daed79a39d1ae63133e0f25558',
           'nativeDeclaredGitPin':'fee9b84bdca8ae25a1839f7ef29690150115abe7',
           'nativeRuntime':'CrispCloud path override packages/legacy_doc_parser',
           'appReferenceCommit':'9b9af856d4352c0d9d8d51aaffcd70aeb7ff3aad',
           'nativePackageTree':'704da2021d56a963cbba46a095900d97d2b02ec3',
           'node':subprocess.check_output([NODE,'--version'],text=True).strip(),
           'nativeExecutableSha256':digest((BUILD/'native_probe').read_bytes()),
           'revisionProjectionChecks':revision_checks,
           'cases':summaries}
(ROOT/'results.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
for s in summaries:
    print(s['id'], 'native='+str(s['native'].get('ok')),'upstream='+str(s['upstream'].get('ok')),
          'text_equal='+str(s.get('sameNormalizedPreviewText')),
          'native_error='+s['native'].get('error',''), 'upstream_error='+s['upstream'].get('error',''))
