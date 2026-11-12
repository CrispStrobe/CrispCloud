#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Validate reviewed source-DOC goldens. There is deliberately no update mode.

The manifest records an independent native render, never converter output.
Matching requires the same source bytes, Office build, font files, PDF tools,
resolution and color space. A different environment is unverified, not a pass.
"""
import json
from pathlib import Path

from oracle import ROOT, compare_layout, digest

MANIFEST = 'test/fixtures/fidelity/goldens/manifest.json'
ENVIRONMENT_KEYS = ('renderer', 'fontInventorySha256', 'fontFilesSha256',
                    'rasterizerVersion', 'textExtractorVersion')


def compare_render(reference, actual):
    result = compare_layout(reference['pages'], actual['pages'])
    settings_match = (reference.get('rasterColorSpace') == 'RGB' and
                      reference.get('rasterDpi', 0) > 0 and
                      all(reference.get(key) == actual.get(key)
                          for key in ('rasterDpi', 'rasterColorSpace')))
    result['rasterSettingsMatch'] = settings_match
    result['rasterExactlyMatches'] = (settings_match and
                                     reference['rasterSha256'] == actual['rasterSha256'])
    result['layoutTextExactlyMatches'] = reference['text'] == actual['text']
    result['exactOnThisRenderer'] = (result['rasterExactlyMatches'] and
                                    result['layoutTextExactlyMatches'] and
                                    result['maximumWordDriftPoints'] == 0 and
                                    result['pageDimensionsMatch'])
    return result


def load_goldens(root=ROOT):
    manifest = json.loads((root / MANIFEST).read_text())
    if manifest['schema'] != 'legacy-doc-parser/source-goldens' or manifest['version'] != 1:
        raise ValueError('Unknown source golden schema')
    if any(not manifest['environment'].get(key) for key in ENVIRONMENT_KEYS):
        raise ValueError('Source goldens require a complete renderer/font environment')
    cases = {}

    def verified(record):
        path = (root / record['path']).resolve()
        if not path.is_relative_to(root.resolve()) or digest(path) != record['sha256']:
            raise ValueError('Golden artifact changed: ' + record['path'])
        return path

    for case in manifest['cases']:
        if case['id'] in cases:
            raise ValueError('Duplicate golden case')
        if case['origin'] != 'independent-native-source-doc':
            raise ValueError('Converter output cannot be a source golden')
        source = verified(case['source'])
        if source.suffix != '.doc':
            raise ValueError('Source golden requires pinned binary DOC bytes')
        render = json.loads(verified(case['render']).read_text())
        if (render['rasterColorSpace'] != 'RGB' or render['rasterDpi'] <= 0 or
                len(render['pages']) != len(case['images']) or
                len(render['rasterSha256']) != len(case['images'])):
            raise ValueError('Incomplete source golden page evidence')
        for image in case['images']:
            if verified(image).suffix != '.png':
                raise ValueError('Expected a reviewable source page PNG')
        cases[case['id']] = {**case, 'expectedRender': render}
    return {'environment': manifest['environment'], 'cases': cases}


def compare_golden(case_id, source_sha256, render, environment, catalog):
    expected = catalog['cases'].get(case_id)
    if expected is None:
        return {'status': 'not-recorded'}
    if expected['source']['sha256'] != source_sha256:
        return {'status': 'source-mismatch'}
    mismatch = [key for key in ENVIRONMENT_KEYS
                if not environment.get(key) or
                environment.get(key) != catalog['environment'].get(key)]
    if mismatch:
        return {'status': 'environment-mismatch', 'differentFields': mismatch}
    comparison = compare_render(expected['expectedRender'], render)
    return {'status': 'matched' if comparison['exactOnThisRenderer'] else 'different',
            **comparison}


if __name__ == '__main__':
    catalog = load_goldens()
    print(f"Verified {len(catalog['cases'])} reviewed source-DOC golden records and page images")
