"""Execute the pinned external tool against independent authored controls."""
from pathlib import Path
import hashlib, json, subprocess, sys, time, zipfile
from ooxml_projection import project, W

BASE=Path(__file__).resolve().parent
BIN=BASE/'isolated-build/target/debug'
ADAPTER=BIN/'examples/oracle_adapter'
CLI=BIN/'crisp-docx'
OUT=BASE/'results'
OUT.mkdir(exist_ok=True)
commands=[]
def execute(name,argv):
    start=time.time()
    r=subprocess.run([str(a) for a in argv],capture_output=True,cwd=BASE)
    (OUT/(name+'.stdout')).write_bytes(r.stdout)
    (OUT/(name+'.stderr')).write_bytes(r.stderr)
    record={'name':name,'argv':[str(a) for a in argv],'cwd':str(BASE),'exitCode':r.returncode,'seconds':time.time()-start,'stdoutSha256':hashlib.sha256(r.stdout).hexdigest(),'stderrSha256':hashlib.sha256(r.stderr).hexdigest()}
    commands.append(record)
    return r
def story(snapshot,part='word/document.xml'):
    return next(s for s in snapshot['stories'] if s['part']==part)
def event_offsets(snapshot,kind):
    return [e['offset'] for p in story(snapshot)['paragraphs'] for e in p['events'] if e['type']==kind]
def semantic(snapshot):
    return [{k:v for k,v in s.items() if k!='expandedXmlSha256'} for s in snapshot['stories']]
def assert_expected(name,snapshot,expected):
    if snapshot['parseErrors']: raise ValueError((name,'input XML invalid'))
    body=story(snapshot)
    checks=[]
    def require(condition,label):
        if not condition: raise ValueError((name,label))
        checks.append(label)
    if 'bodyTexts' in expected: require([p['acceptedText'] for p in body['paragraphs']]==expected['bodyTexts'],'authored body texts')
    if 'paragraphCount' in expected: require(len(body['paragraphs'])==expected['paragraphCount'],'authored paragraph count')
    for key,kind in [('bookmarkStartOffsets','bookmarkStart'),('bookmarkEndOffsets','bookmarkEnd'),('footnoteOffsets','footnoteReference'),('endnoteOffsets','endnoteReference')]:
        if key in expected: require(event_offsets(snapshot,kind)==expected[key],'authored '+key)
    for key,kind in [('tabCount','tab'),('breakCount','br'),('hyperlinks','hyperlink')]:
        if key in expected: require(len(event_offsets(snapshot,kind))==expected[key],'authored '+key)
    if 'tableRows' in expected: require([len(row) for t in body['tables'] for row in t['rows']]==expected['tableRows'],'authored table cell counts')
    for key,part in [('headerTexts','word/header1.xml'),('footerTexts','word/footer1.xml')]:
        if key in expected: require([p['acceptedText'] for p in story(snapshot,part)['paragraphs']]==expected[key],'authored '+key)
    for key,field in [('acceptedText','acceptedText'),('rejectedText','rejectedText')]:
        if key in expected: require(''.join(p[field] for p in body['paragraphs'])==expected[key],'authored '+key)
    for key,kind in [('insertionCount','ins'),('deletionCount','del')]:
        if key in expected: require(body['revisions'][kind]==expected[key],'authored '+key)
    if 'bodyOwnText' in expected: require(body['paragraphs'][0]['acceptedText']==expected['bodyOwnText'],'authored outer paragraph text')
    if 'textboxText' in expected: require(body['paragraphs'][1]['acceptedText']==expected['textboxText'],'authored textbox text')
    if expected.get('mustRejectAsFullValidator'): require(bool(snapshot['issues']),'authored negative structural condition detected')
    else: require(not snapshot['issues'],'no input graph/range failures in limited projector')
    return checks

manifest=json.loads((BASE/'control-manifest.json').read_text())
report={'sourceCommit':'ddf7830d8d92e6b59b10874d144a59f163a256e1','sourceScope':'Current core/CLI source; narrowed isolated workspace. Published wheel excluded.','toolIdentities':{str(p.relative_to(BASE)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [ADAPTER,CLI,BASE/'oracle_adapter.rs',BASE/'ooxml_projection.py',BASE/'make_controls.py',BASE/'run_probes.py']},'cases':{}}
for name,entry in manifest['cases'].items():
    path=BASE/'controls'/entry['path']
    before=project(path)
    checks=assert_expected(name,before,entry['authoredExpected'])
    inspect=execute(name+'.inspect',[ADAPTER,'inspect',path])
    if inspect.returncode: raise RuntimeError(inspect.stderr.decode())
    observed=json.loads(inspect.stdout)
    result={'input':before,'authoredAssertionsPassed':checks,'crisp':observed,'rewrites':{}}
    for mode in ['save','runs','text']:
        output=OUT/(name+'.'+mode+'.docx')
        r=execute(name+'.'+mode,[ADAPTER,mode,path,output])
        item={'exitCode':r.returncode}
        if r.returncode==0:
            after=project(output)
            item.update(projection=after,allPartBytesEqual=before['parts']==after['parts'],semanticProjectionEqual=semantic(before)==semantic(after))
        result['rewrites'][mode]=item
    pandoc=execute(name+'.pandoc',['pandoc','-f','docx','-t','json','--track-changes=all',path])
    if pandoc.returncode==0:
        (OUT/(name+'.pandoc.json')).write_bytes(pandoc.stdout)
    result['pandocExitCode']=pandoc.returncode
    report['cases'][name]=result

plain=story(report['cases']['plain']['input'])['expandedXmlSha256']
aliased=story(report['cases']['namespace-alias']['input'])['expandedXmlSha256']
if plain!=aliased: raise RuntimeError('namespace aliases were not independently equivalent')
report['namespaceSemanticEquality']=True
for direction,source,output in [('endnotes',BASE/'controls/notes-conversion-link.docx',OUT/'notes-converted-endnotes.docx'),('footnotes',OUT/'notes-converted-endnotes.docx',OUT/'notes-converted-back.docx')]:
    r=execute('convert-'+direction,[CLI,'notes-kind',source,'--to',direction,'-o',output])
    if r.returncode: raise RuntimeError(r.stderr.decode())
    report['convertTo'+direction.title()]={'projection':project(output),'crisp':json.loads(execute('inspect-converted-'+direction,[ADAPTER,'inspect',output]).stdout)}
transplant=OUT/'transplanted-link.docx'
r=execute('transplant-link',[CLI,'transplant',BASE/'controls/plain.docx',BASE/'controls/transplant-source-link.docx','-o',transplant])
if r.returncode: raise RuntimeError(r.stderr.decode())
report['transplant']={'projection':project(transplant),'crisp':json.loads(execute('inspect-transplant',[ADAPTER,'inspect',transplant]).stdout)}
report['commands']=commands
(BASE/'probe-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
summary={name:{'crispClean':r['crisp']['check'].get('clean'),'sourceParagraphs':len(story(r['input'])['paragraphs']),'crispTextParagraphs':len(r['crisp']['publicBodyProjection']['texts']),'crispRunParagraphs':len(r['crisp']['publicBodyProjection']['paragraphRuns']),'runRewriteSame':r['rewrites']['runs'].get('semanticProjectionEqual'),'runRewriteXmlErrors':r['rewrites']['runs'].get('projection',{}).get('parseErrors'),'textRewriteSame':r['rewrites']['text'].get('semanticProjectionEqual')} for name,r in report['cases'].items()}
print(json.dumps(summary,indent=2,ensure_ascii=False))
print('Commands',len(commands))
