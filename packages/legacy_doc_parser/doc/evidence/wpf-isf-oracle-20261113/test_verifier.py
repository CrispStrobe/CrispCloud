#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reject contradictions after the outer manifest byte receipts are resealed."""
import json
import verify


def change_json(files, name, callback):
    value = verify.obj(files[name])
    callback(value)
    files[name] = (json.dumps(value, indent=2) + '\n').encode()


def reseal_manifest(files):
    manifest = verify.obj(files['manifest.json'])
    manifest['files'] = [{'path': name, 'bytes': len(data), 'sha256': verify.sha(data)}
                         for name, data in sorted(files.items()) if name != 'manifest.json']
    manifest['fileCount'] = len(manifest['files'])
    manifest['totalBytes'] = sum(item['bytes'] for item in manifest['files'])
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()


def main():
    archived = verify.read_zip((verify.HERE / 'successful-run.zip').read_bytes())
    original = {name[len('ink-oracle/'):]: data for name, data in archived.items() if name.startswith('ink-oracle/')}
    verify.verify_oracle(original)
    results = []

    def rejects(name, mutation):
        files = dict(original)
        mutation(files)
        reseal_manifest(files)
        try:
            verify.verify_oracle(files)
        except (ValueError, KeyError) as error:
            results.append({'control': name, 'rejected': True, 'reason': str(error)})
        else:
            raise RuntimeError('Accepted contradictory oracle evidence: ' + name)

    rejects('wrong runtime commit', lambda f: change_json(
        f, 'summary.json', lambda d: d.update(sourceCommit='0' * 40)))
    rejects('missing ISF input', lambda f: f.pop('single-dot/compressed.isf'))
    rejects('forged coordinate comparison', lambda f: change_json(
        f, 'summary.json', lambda d: d['cases'][0]['encodings'][0]['originalToReloaded'].update(
            maximumCoordinateDeltaDip=1)))
    rejects('stale reloaded coordinate', lambda f: change_json(
        f, 'polyline-solid/compressed.reloaded.json', lambda d: d['strokes'][0]['points'][0].update(x=123)))
    rejects('changed authored paint', lambda f: change_json(
        f, 'paint-ellipse-alpha/authored.json', lambda d: d['strokes'][0].update(colorArgb='#FF000000')))
    rejects('forged changed pixel count', lambda f: change_json(
        f, 'summary.json', lambda d: d['cases'][4]['encodings'][0].update(originalToReloadedChangedPixels=0)))
    rejects('stale original raw pixel hash', lambda f: change_json(
        f, 'summary.json', lambda d: d['cases'][0]['originalRender'].update(pixelSha256='0' * 64)))
    rejects('false compression distinction', lambda f: change_json(
        f, 'summary.json', lambda d: d['cases'][1].update(compressionChangesBytes=True)))
    rejects('false roundtrip byte instability', lambda f: change_json(
        f, 'summary.json', lambda d: d['cases'][0]['encodings'][0].update(bytesStableAfterReload=False)))
    rejects('changed pressure normalization', lambda f: change_json(
        f, 'pressure-ramp/uncompressed.reloaded.json',
        lambda d: d['strokes'][0]['points'][1].update(pressureFactor=0.5)))
    print(json.dumps({'validOracleAccepted': True, 'corruptionsRejected': len(results),
                      'pythonOptimizationEnabled': __debug__ is False, 'controls': results}, indent=2))


if __name__ == '__main__':
    main()
