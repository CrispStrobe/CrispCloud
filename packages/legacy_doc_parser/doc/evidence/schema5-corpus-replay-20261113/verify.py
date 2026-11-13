"""Verify fresh XML replay records without running any document producer."""
from pathlib import Path, PurePosixPath
from collections import Counter
import argparse, copy, hashlib, io, json, sys, tarfile

BASE=Path(__file__).resolve().parent
sys.path.insert(0,str(BASE/'oracle-source'))
import oracle

CASES={'formatting','word','word-compatibility','table-borders','story-media',
       'comment-threads','note-markers','bookmarks','content-controls',
       'content-controls-legacy','word-altchunk','linked-textboxes',
       'officeart-shapes','linked-textboxes-native','emf-vectors','wmf-vectors',
       'linked-textboxes-compact','list-continue','list-restart',
       'word14-margin-origin','word16-page-origin','poi-simple-table2',
       'header-textbox-alias','header-textbox-first-enabled'}
RUNTIME='c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
ORACLE='c73749df59d0978c8bcd20710a2ae92184fab11a'

def sha(raw): return hashlib.sha256(raw).hexdigest()
def require(condition,message):
    if not condition: raise ValueError(message)
def read(path): return json.loads(path.read_text())
def identity(raw): return {'bytes':len(raw),'sha256':sha(raw)}
def snapshot_name(case,role): return case+'.'+role+'.json'
def overview(snapshot):
    counts=Counter();events=[]
    for story in snapshot['inlineContent']:
        counts.update(e['kind'] for e in story['items'])
        if story['items']: events.append(story)
    return {'eventCounts':dict(sorted(counts.items())),'inlineContent':events}
def note_anchors(row):
    return [(s['story'],e['kind'],e['at'],e['customMarkFollows'],e['unresolved'])
            for s in row['inlineContent'] for e in s['items']
            if e['kind'] in ('footnoteReference','endnoteReference')]

def summarize(report):
    roles={role:{'packages':0,'eventCounts':Counter()} for role in ('original','native','parser')}
    changed=[];anchor_changes=[]
    for case,row in report['cases'].items():
        for role,value in row['inputs'].items():
            roles[role]['packages']+=1;roles[role]['eventCounts'].update(value['eventCounts'])
        if row['edges']['sameBinaryNativeVsParser']['inlineContentEqual'] is False: changed.append(case)
        if note_anchors(row['inputs']['native'])!=note_anchors(row['inputs']['parser']):anchor_changes.append(case)
    for row in roles.values(): row['eventCounts']=dict(sorted(row['eventCounts'].items()))
    return {'cases':len(report['cases']),'packages':sum(r['packages'] for r in roles.values()),
            'roles':roles,'sameBinaryInlineDifferences':sorted(changed),
            'sameBinaryBodyNoteAnchorDifferences':sorted(anchor_changes),
            'scope':'Initial retained packages only; empty feature equality is not positive coverage.'}

def verify_records(report,snapshots,summary):
    require(report['measuredRuntime']==RUNTIME,'measured runtime')
    require(report['oracle']==read(BASE/'source-identity.json') and report['oracle']['commit']==ORACLE,'observer source')
    require(report['replaySourceSha256']==sha((BASE/'replay.py').read_bytes()),'replay helper identity')
    require(set(report['cases'])==CASES,'exact 24-case inventory')
    expected=set();packages=0
    for case,row in report['cases'].items():
        require({'native','parser'}<=set(row['inputs'])<={'native','parser','original'},'package roles')
        for role,value in row['inputs'].items():
            name=snapshot_name(case,role);expected.add(name);raw=snapshots[name];snap=json.loads(raw)
            require(snap['oracleSchemaVersion']==5,'snapshot schema')
            require(value['snapshot']['path']=='schema5-corpus-replay-20261113/snapshots/'+name,'snapshot path')
            require(identity(raw)=={k:value['snapshot'][k] for k in ('bytes','sha256')},'snapshot byte identity')
            derived=overview(snap)
            require(all(value[k]==v for k,v in derived.items()),'derived inline events and counts')
            packages+=1
        for a,b,label in [('original','native','originalThroughBinaryToNative'),('native','parser','sameBinaryNativeVsParser')]:
            edge=row['edges'][label]
            if a not in row['inputs']:
                require(edge=={'available':False,'reason':'No original OOXML for binary sources or an explicit reader error'},'missing original attribution')
                continue
            left=json.loads(snapshots[snapshot_name(case,a)]);right=json.loads(snapshots[snapshot_name(case,b)])
            require(edge=={'reference':a,'actual':b,
                           'changedProperties':[d['property'] for d in oracle.compare_semantics(left,right)],
                           'inlineContentEqual':left['inlineContent']==right['inlineContent']},'derived edge comparison')
    require(set(snapshots)==expected and packages==62,'62-package snapshot inventory')
    require(report['counts']=={'cases':24,'packages':62,'snapshotSuccesses':62,'readerErrors':0},'reader result counts')
    require(summary==summarize(report),'derived compact summary')
    require(summary['sameBinaryInlineDifferences']==['bookmarks','note-markers','word'],'observed differing cases')
    require(summary['sameBinaryBodyNoteAnchorDifferences']==[],'observed body note anchors')

def load():
    receipt=read(BASE/'receipt.json')
    for name,want in receipt['files'].items():require(identity((BASE/name).read_bytes())==want,'outer file '+name)
    source=read(BASE/'source-identity.json')
    for path,want in source['sources'].items():
        raw=(BASE/'oracle-source'/Path(path).name).read_bytes()
        require(identity(raw)=={k:want[k] for k in ('bytes','sha256')},'oracle source file')
        require(hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==want['gitBlob'],'oracle Git blob')
    snapshots={}
    with tarfile.open(BASE/'snapshots.tar.xz') as tar:
        for member in tar:
            p=PurePosixPath(member.name)
            require(member.isfile() and len(p.parts)==1 and not p.is_absolute() and '..' not in p.parts and member.name not in snapshots,'safe snapshot member')
            require(len(snapshots)<62 and member.size<=2*1024*1024,'snapshot bounds')
            snapshots[member.name]=tar.extractfile(member).read()
    require({k:identity(v) for k,v in snapshots.items()}==read(BASE/'snapshot-manifest.json'),'snapshot manifest')
    return read(BASE/'report.json'),snapshots,read(BASE/'summary.json')

def self_test(report,snapshots,summary):
    controls=[]
    def rejected(name,changed_report,changed_summary,guard):
        try: verify_records(changed_report,snapshots,changed_summary)
        except ValueError as error:
            require(guard in str(error),'wrong corruption rejection: '+name);controls.append(name)
        else:raise ValueError('Accepted semantic corruption: '+name)
    mutated=copy.deepcopy(report);mutated['cases']['word']['edges']['sameBinaryNativeVsParser']['inlineContentEqual']=True
    rejected('false inline equality',mutated,summary,'derived edge comparison')
    mutated=copy.deepcopy(report);mutated['cases']['formatting']['inputs']['parser']['inlineContent'][0]['items'][0]['at']['offset']+=1
    rejected('changed note anchor',mutated,summary,'derived inline events and counts')
    mutated=copy.deepcopy(report);mutated['cases']['word']['inputs']['native']['snapshot']['sha256']='0'*64
    rejected('wrong snapshot identity',mutated,summary,'snapshot byte identity')
    changed=copy.deepcopy(summary);changed['roles']['native']['eventCounts']['symbol']=1
    rejected('invented symbol coverage',report,changed,'derived compact summary')
    return controls

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--workspace',type=Path);parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args();report,snapshots,summary=load();verify_records(report,snapshots,summary)
    direct=0
    if args.workspace:
        def check(row):
            path=args.workspace/row['path'];require(identity(path.read_bytes())=={k:row[k] for k in ('bytes','sha256')},'direct input '+row['path']);return path
        check(report['originalNativeReport'])
        for case,row in report['cases'].items():
            receipt=read(check(row['retainedCaseReceipt']));check(row['binary'])
            require(row['binary']['sha256']==receipt['binaryDocSha256'],'binary/case receipt binding')
            for role,value in row['inputs'].items():
                path=check(value['input'])
                require(value['input']['sha256']==receipt[{'native':'nativeDocxSha256','parser':'convertedSha256','original':'sourceSha256'}[role]],'package/case receipt binding')
                require(oracle.snapshot(path)==json.loads(snapshots[snapshot_name(case,role)]),'direct XML snapshot '+case+' '+role);direct+=1
    controls=self_test(report,snapshots,summary) if args.self_test else []
    print(json.dumps({'verifiedSnapshots':len(snapshots),'directPackageReplays':direct,'cases':24,'semanticCorruptionControls':controls,'scope':'Read-only retained XML observations; no converter or native renderer execution.'},indent=2))

if __name__=='__main__': main()
