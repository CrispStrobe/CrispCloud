"""Read retained packages only; no conversion, rendering, or old-evidence edit."""
from pathlib import Path
from collections import Counter
import hashlib, json, subprocess, sys

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
CORPUS = ROOT / 'final-native-c5ff75e7'
REPO = ROOT / 'parser-combined-next'
RUNTIME = 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
sys.path.insert(0, str(BASE / 'oracle-source'))
import oracle

def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_text())
def write(path, value): path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n')
def identity(path):
    raw = path.read_bytes()
    return {'path':str(path.relative_to(ROOT)), 'bytes':len(raw), 'sha256':sha(raw)}
def overview(snapshot):
    counts = Counter()
    events = []
    for story in snapshot['inlineContent']:
        for item in story['items']:
            counts[item['kind']] += 1
        if story['items']:
            events.append(story)
    return {'eventCounts':dict(sorted(counts.items())), 'inlineContent':events}

def main():
    raw_manifest = subprocess.check_output(['git','show',RUNTIME+':tool/fidelity/corpus.json'],cwd=REPO)
    manifest = json.loads(raw_manifest)
    native = read(CORPUS/'report.json')
    if native['parserCommit'] != RUNTIME or native['corpusSha256'] != sha(raw_manifest):
        raise ValueError('Measured runtime/corpus identity differs')
    entries={row['id']:row for row in manifest['cases']}
    result={'schema':'legacy-doc-parser/schema5-retained-replay-v1',
            'scope':'Fresh XML observations of retained inputs, no producer rerun; differences are not automatically parser defects.',
            'oracle':read(BASE/'source-identity.json'), 'measuredRuntime':RUNTIME,
            'replaySourceSha256':sha(Path(__file__).read_bytes()),
            'originalNativeReport':identity(CORPUS/'report.json'),
            'corpusManifestSha256':sha(raw_manifest), 'cases':{}}
    (BASE/'snapshots').mkdir(exist_ok=True)
    for case in native['cases']:
        name=case['id'];folder=CORPUS/name;receipt=read(folder/'result.json')
        if receipt['status'] != 'measured': raise ValueError(name+' not measured')
        paths={'native':(next((folder/'native-docx').glob('*.docx')),receipt['nativeDocxSha256']),
               'parser':(folder/'converted.docx',receipt['convertedSha256'])}
        if receipt['sourceFormat']=='docx':
            paths['original']=(REPO/entries[name]['path'],receipt['sourceSha256'])
        stages={s['name']:s for s in receipt['stages']}
        binary=folder/stages['binary-bridge']['artifact'] if 'binary-bridge' in stages else folder/'source.doc'
        if sha(binary.read_bytes())!=receipt['binaryDocSha256']: raise ValueError(name+' binary hash')
        row={'retainedCaseReceipt':identity(folder/'result.json'),'binary':identity(binary),'inputs':{},'edges':{}}
        snapshots={}
        for role,(path,expected) in paths.items():
            ident=identity(path)
            if ident['sha256']!=expected: raise ValueError(name+' '+role+' hash')
            try:
                snap=oracle.snapshot(path)
                if snap['oracleSchemaVersion']!=5: raise ValueError('unexpected oracle version')
                target=BASE/'snapshots'/(name+'.'+role+'.json');write(target,snap)
                row['inputs'][role]={'input':ident,'snapshot':identity(target),**overview(snap)}
                snapshots[role]=snap
            except Exception as error:
                row['inputs'][role]={'input':ident,'error':type(error).__name__+': '+str(error)}
        for a,b,label in [('original','native','originalThroughBinaryToNative'),('native','parser','sameBinaryNativeVsParser')]:
            if a in snapshots and b in snapshots:
                diff=oracle.compare_semantics(snapshots[a],snapshots[b])
                row['edges'][label]={'reference':a,'actual':b,'changedProperties':[x['property'] for x in diff],
                                    'inlineContentEqual':snapshots[a]['inlineContent']==snapshots[b]['inlineContent']}
            else:
                row['edges'][label]={'available':False,'reason':'No original OOXML for binary sources or an explicit reader error'}
        result['cases'][name]=row
    result['counts']={'cases':len(result['cases']), 'packages':sum(len(r['inputs']) for r in result['cases'].values()),
                      'snapshotSuccesses':sum('snapshot' in v for r in result['cases'].values() for v in r['inputs'].values()),
                      'readerErrors':sum('error' in v for r in result['cases'].values() for v in r['inputs'].values())}
    write(BASE/'report.json',result)
    print(json.dumps(result['counts']))
    for case,row in result['cases'].items():
        print(case, {r:v.get('eventCounts',v.get('error')) for r,v in row['inputs'].items()})

if __name__=='__main__': main()
