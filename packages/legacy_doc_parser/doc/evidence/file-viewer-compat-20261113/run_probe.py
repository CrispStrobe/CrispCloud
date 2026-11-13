#!/usr/bin/env python3
"""Repeat the same 19 DOC/DOT inputs against this source and pinned File Viewer.

Build native_probe.dart and upstream_probe.mjs as described in README.md first.
This runner publishes counts/hashes only; input text and generated HTML remain
in process memory and are not written to the receipt.
"""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from html.parser import HTMLParser
from pathlib import Path
import argparse
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent


def digest(data):
    return sha256(data).hexdigest()


class HtmlText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, text):
        self.parts.append(text)

    def handle_starttag(self, tag, attrs):
        if tag in ('p', 'br', 'tr', 'td', 'th', 'div', 'li', 'section'):
            self.parts.append(' ')

    def handle_endtag(self, tag):
        self.handle_starttag(tag, [])


def normalized(html):
    parser = HtmlText()
    parser.feed(html)
    return re.sub(r'\s+', ' ', ''.join(parser.parts)).strip()


def invoke(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError(f'Probe exited {result.returncode}: {result.stderr[:2000]}')
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', type=Path, required=True)
    parser.add_argument('--upstream', type=Path, required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    expected = json.loads((HERE / 'source-hashes.json').read_text())
    roots = {'native': args.native / 'lib',
             'upstreamDoc': args.upstream / 'packages/renderers/doc/src'}

    def verify_sources():
        for label, entries in expected.items():
            for relative, wanted in entries.items():
                if digest((roots[label] / relative).read_bytes()) != wanted:
                    raise RuntimeError(f'Source differs: {label}/{relative}')

    verify_sources()
    cases = json.loads((HERE / 'fixture-manifest.json').read_text())

    def run(case):
        path = roots['native'].parent / case['path'] if case['origin'] == 'native' \
            else args.upstream / case['path']
        before = path.read_bytes()
        if digest(before) != case['sha256']:
            raise RuntimeError(f'Fixture differs: {case["id"]}')
        native = invoke([str(args.build / 'native_probe'), str(path)])
        upstream = invoke([args.node, str(args.build / 'upstream_probe.mjs'), str(path)])
        if path.read_bytes() != before:
            raise RuntimeError(f'Fixture changed: {case["id"]}')
        output = dict(case)
        for label, data in [('native', native), ('upstream', upstream)]:
            summary = {k: v for k, v in data.items()
                       if k not in ('html', 'plainText', 'stories', 'elapsedMs')}
            if data.get('ok'):
                html = data['html'] if label == 'native' else data['html']['all']
                text = normalized(html)
                summary.update(previewTextCodepoints=len(text),
                               previewTextSha256=digest(text.encode()),
                               previewImageTags=len(re.findall(r'<img\b', html)))
                if label == 'native':
                    summary['stories'] = [
                        {'kind': s['kind'], 'textCodepoints': len(s['plainText']),
                         'textSha256': digest(s['plainText'].encode())}
                        for s in data['stories']]
            output[label] = summary
        if native.get('ok') and upstream.get('ok'):
            output['sameNormalizedMainPreviewText'] = \
                normalized(native['html']) == normalized(upstream['html']['all'])
        return output

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(run, cases))
    verify_sources()
    receipt = {
        'scope': 'parser and generated HTML; no browser or native Office layout',
        'sourceIdentity': json.loads((HERE / 'provenance.json').read_text()),
        'sourceHashesSha256': digest((HERE / 'source-hashes.json').read_bytes()),
        'nativeExecutableSha256': digest((args.build / 'native_probe').read_bytes()),
        'nativeProbeSha256': digest((HERE / 'native_probe.dart').read_bytes()),
        'upstreamProbeSha256': digest((HERE / 'upstream_probe.mjs').read_bytes()),
        'nodeVersion': subprocess.check_output([args.node, '--version'], text=True).strip(),
        'nativeAccepted': sum(case['native'].get('ok', False) for case in results),
        'upstreamAccepted': sum(case['upstream'].get('ok', False) for case in results),
        'equalNormalizedMainPreviewText': sum(
            case.get('sameNormalizedMainPreviewText', False) for case in results),
        'cases': results,
    }
    args.output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: receipt[key] for key in
                      ['nativeAccepted', 'upstreamAccepted',
                       'equalNormalizedMainPreviewText']}))


if __name__ == '__main__':
    main()
