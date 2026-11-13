#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Exercise semantic bindings after regenerating every inner file hash."""
import copy
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify


def put(files, path, change):
    value = verify.obj(files[path])
    change(value)
    files[path] = (json.dumps(value, indent=2) + '\n').encode()


def reseal(files):
    manifest = verify.obj(files['manifest.json'])
    manifest['files'] = [{'path': p, 'bytes': len(b), 'sha256': verify.sha(b)}
                         for p, b in sorted(files.items()) if p != 'manifest.json']
    manifest['fileCount'] = len(manifest['files'])
    manifest['totalBytes'] = sum(r['bytes'] for r in manifest['files'])
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()


def cases():
    yield 'wrong_runtime_source', lambda f: put(f, 'summary.json', lambda s: s.update(sourceCommit='0' * 40))
    yield 'substituted_native_command', lambda f: put(f, 'summary.json', lambda s: s.update(actualArguments=['true']))
    yield 'stale_checkout_hash', lambda f: put(f, 'source-inventory.json', lambda s: s['files'][0].update(sha256='0' * 64))
    yield 'omitted_control', lambda f: put(f, 'controls.json', lambda s: s['cases'].pop())
    yield 'rewritten_pre_run_hypothesis', lambda f: put(f, 'controls.json',
        lambda s: s['cases'][6]['sourceFormula']['points'][1].__setitem__(0, 100))
    yield 'false_unchanged_packet_receipt', lambda f: put(f, 'controls.json',
        lambda s: s['cases'][0]['unchangedRecords'][-1].update(sha256='0' * 64))
    def altered_packets(f):
        path = 'polyline-solid-baseline/input.isf'
        f[path] = f[path][:-1] + bytes([f[path][-1] ^ 1])
        put(f, 'summary.json', lambda s: s['cases'][0].update(inputSha256=verify.sha(f[path])))
    yield 'altered_source_packet_bytes', altered_packets
    def erase_collapse(f):
        path = 'translate-100-minus50-float-only/formula-observation.json'
        put(f, path, lambda d: d.update(coordinatesMatchSourceFormulaWithinTolerance=True,
                                      maximumCoordinateDeltaHimetric=0))
        put(f, 'summary.json', lambda s: s['cases'][6].update(sourceFormulaObservation=verify.obj(f[path])))
    yield 'erased_observed_collapse', erase_collapse
    yield 'false_baseline_pixel_equality', lambda f: put(f, 'summary.json',
        lambda s: s['cases'][2].update(baselineToReloadedChangedPixels=0))
    yield 'erased_pressure_metric_reload_difference', lambda f: put(f, 'pressure-explicit-0-2047/second-reloaded.json',
        lambda s: s['strokes'][0]['pressureMetric'].update(maximum=2047))
    yield 'false_pressure_roundtrip_pixels', lambda f: put(f, 'summary.json',
        lambda s: s['cases'][-1].update(reloadedToSecondChangedPixels=0))
    yield 'false_roundtrip_byte_equality', lambda f: put(f, 'summary.json',
        lambda s: s['cases'][2].update(bytesStableAfterReload=True))
    yield 'changed_native_paint', lambda f: put(f, 'isotropic-2-float-only/reloaded.json',
        lambda s: s['strokes'][0]['attributes'].update(colorArgb='#FFFF0000'))
    yield 'false_float_double_raster_difference', lambda f: put(f, 'summary.json',
        lambda s: s['comparisons'][0].update(changedPixels=1))
    yield 'omitted_pair_comparison', lambda f: put(f, 'summary.json', lambda s: s['comparisons'].pop())
    yield 'stale_png_pixel_hash', lambda f: put(f, 'summary.json',
        lambda s: s['cases'][0]['reloadedRender'].update(pixelSha256='0' * 64))
    yield 'second_reload_changed_raw_pressure', lambda f: put(f, 'pressure-explicit-0-2047/second-reloaded.json',
        lambda s: s['strokes'][0]['points'][0].update(pressurePropertyValue=1))
    yield 'second_reload_changed_implicit_metric', lambda f: put(f, 'polyline-solid-baseline/second-reloaded.json',
        lambda s: s['strokes'][0]['pressureMetric'].update(maximum=1024))


def main():
    archived = verify.prior.read_zip((verify.HERE / 'successful-run.zip').read_bytes())
    original = {n.removeprefix('ink-metrics/'): b for n, b in archived.items() if n.startswith('ink-metrics/')}
    verify.verify_payloads(original)
    results = []
    for name, mutate in cases():
        changed = dict(original)
        mutate(changed)
        reseal(changed)
        try:
            verify.verify_payloads(changed)
        except (ValueError, KeyError, IndexError) as exc:
            results.append({'control': name, 'rejected': True, 'reason': str(exc)})
        else:
            raise ValueError('Semantic corruption accepted: ' + name)
    print(json.dumps({'controlsRejected': len(results), 'results': results}, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
