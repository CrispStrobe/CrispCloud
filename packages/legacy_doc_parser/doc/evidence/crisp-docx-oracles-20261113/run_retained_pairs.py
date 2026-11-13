"""Read-only comparisons of already retained parser/native OOXML handoffs.

No binary conversion, app execution, or native rendering is performed here.
The native DOCX is another implementation's output, not an absolute golden.
"""
from pathlib import Path
import hashlib,json,subprocess
from ooxml_projection import project

BASE=Path(__file__).resolve().parent
ROOT=BASE.parent
CORPUS=ROOT/'final-native-c5ff75e7'
REPO=ROOT/'parser-combined-next'
ADAPTER=BASE/'isolated-build/target/debug/examples/oracle_adapter'
OUT=BASE/'retained-pairs'
OUT.mkdir(exist_ok=True)
CASES=['word','poi-simple-table2','bookmarks','note-markers','story-media','comment-threads','content-controls','linked-textboxes','word14-margin-origin']
manifest=json.loads((REPO/'tool/fidelity/corpus.json').read_text())
manifest_cases={c['id']:c for c in manifest['cases']}
sha=lambda data:hashlib.sha256(data).hexdigest()
def run(name,argv):
    r=subprocess.run([str(x) for x in argv],cwd=BASE,capture_output=True)
    (OUT/(name+'.stdout')).write_bytes(r.stdout)
    (OUT/(name+'.stderr')).write_bytes(r.stderr)
    return r,dict(argv=[str(x) for x in argv],cwd=str(BASE),exitCode=r.returncode,stdoutSha256=sha(r.stdout),stderrSha256=sha(r.stderr))
def summary(p):
    return {'parseErrorCount':len(p['parseErrors']),'issueCount':len(p['issues']),'stories':{s['part']:{'paragraphs':len(s['paragraphs']),'acceptedTexts':[a['acceptedText'] for a in s['paragraphs']],'tableCells':[[len(r) for r in t['rows']] for t in s['tables']],'revisions':s['revisions']} for s in p['stories']}}
report={'parserRuntime':'c5ff75e76163d9abbdd44a9f2a7c5ad210929289','nativeCorpusBundle':'doc/evidence/native-corpus-c5ff75e7','crispDocxCommit':'ddf7830d8d92e6b59b10874d144a59f163a256e1','sourceManifestSha256':sha((REPO/'tool/fidelity/corpus.json').read_bytes()),'sourceLicenses':manifest['sources'],'cases':{}}
for case in CASES:
    folder=CORPUS/case
    old=json.loads((folder/'result.json').read_text())
    native=list((folder/'native-docx').glob('*.docx'))
    if len(native)!=1: raise RuntimeError((case,native))
    binary=next((folder/'bridge').glob('*.doc')) if (folder/'bridge').exists() else folder/'source.doc'
    if sha(binary.read_bytes())!=old['binaryDocSha256']: raise RuntimeError((case,'binary hash'))
    item={'corpusEntry':manifest_cases[case],'retainedCaseReceiptSha256':sha((folder/'result.json').read_bytes()),'binary':{'path':str(binary.relative_to(CORPUS)),'sha256':sha(binary.read_bytes())},'inputs':{}}
    for role,path,expected in [('parser',folder/'converted.docx',old['convertedSha256']),('native',native[0],old['nativeDocxSha256'])]:
        if sha(path.read_bytes())!=expected: raise RuntimeError((case,role,'recorded input hash mismatch'))
        snap=project(path)
        label=case+'.'+role
        output,command=run(label+'.crisp',[ADAPTER,'inspect',path])
        crisp=json.loads(output.stdout) if output.returncode==0 else None
        pdoc,pcommand=run(label+'.pandoc',['pandoc','-f','docx','-t','json','--track-changes=all',path])
        pvalue=json.loads(pdoc.stdout) if pdoc.returncode==0 else None
        record={'inputPath':str(path.relative_to(CORPUS)),'sha256':snap['sha256'],'bytes':snap['bytes'],'projection':snap,'summary':summary(snap),'crispCommand':command,'crisp':crisp,'pandocCommand':pcommand,'pandoc':pvalue}
        (OUT/(label+'.json')).write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n')
        item['inputs'][role]={'record':label+'.json','recordSha256':sha((OUT/(label+'.json')).read_bytes()),'summary':record['summary'],'crispClean':crisp['check'].get('clean') if crisp else None,'crispIssues':crisp['check'].get('issues') if crisp else None,'crispTexts':crisp['publicBodyProjection']['texts'] if crisp else None,'crispRunText': [p['text'] for p in crisp['publicBodyProjection']['paragraphRuns']] if crisp and isinstance(crisp['publicBodyProjection']['paragraphRuns'],list) else None,'pandocExitCode':pdoc.returncode,'pandocCanonicalSha256':sha(json.dumps(pvalue,sort_keys=True,separators=(',',':')).encode()) if pvalue else None}
    a=item['inputs']['parser'];b=item['inputs']['native']
    item['comparison']={'crispTextArraysEqual':a['crispTexts']==b['crispTexts'],'crispRunTextArraysEqual':a['crispRunText']==b['crispRunText'],'pandocAstEqual':a['pandocCanonicalSha256']==b['pandocCanonicalSha256'],'projectionSummariesEqual':a['summary']==b['summary']}
    report['cases'][case]=item
(BASE/'retained-pair-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({c:{**i['comparison'],'parserCrispClean':i['inputs']['parser']['crispClean'],'nativeCrispClean':i['inputs']['native']['crispClean'],'paragraphs':{role:{p:s['paragraphs'] for p,s in v['summary']['stories'].items()} for role,v in i['inputs'].items()}} for c,i in report['cases'].items()},indent=2))
