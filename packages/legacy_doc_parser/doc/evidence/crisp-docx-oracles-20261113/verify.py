"""Verify the retained audit without executing any document producer."""
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
import argparse, hashlib, io, json, re, subprocess, tarfile, tomllib
import ooxml_projection

HEAD='ddf7830d8d92e6b59b10874d144a59f163a256e1'
TREE='5dde3ca46e07f063534abdf2ff117a5e9b205918'
ORIGINAL_BASE='/workspace/scratch/c1ca2a1344e9/crisp-docx-audit-20261113/'
sha=lambda data:hashlib.sha256(data).hexdigest()
def require(condition,message):
    if not condition: raise ValueError(message)
def js(records,name): return json.loads(records[name])
def local_name(path):
    require(path.startswith(ORIGINAL_BASE),'unexpected recorded audit root')
    return path[len(ORIGINAL_BASE):]
def semantic_projection(snapshot):
    return [{key:value for key,value in story.items() if key!='expandedXmlSha256'}
            for story in snapshot['stories']]
def projection_summary(snapshot):
    return {'parseErrorCount':len(snapshot['parseErrors']),
            'issueCount':len(snapshot['issues']),
            'stories':{story['part']:{
                'paragraphs':len(story['paragraphs']),
                'acceptedTexts':[p['acceptedText'] for p in story['paragraphs']],
                'tableCells':[[len(row) for row in table['rows']] for table in story['tables']],
                'revisions':story['revisions']} for story in snapshot['stories']}}
def verify_records(records,temporary_root):
    source=js(records,'source-and-tools.json')
    require(source['commit']==HEAD and source['tree']==TREE and source['checkoutClean'] is True,'source identity')
    require(len(source['trackedSources'])==source['trackedSourceCount']==68,'tracked source count')
    bypath={r['path']:r for r in source['trackedSources']}
    metadata=js(records,'github-metadata.json')
    require(metadata['repository']['full_name']=='CrispStrobe/crisp-docx','repository identity')
    require(metadata['branch']['commit']['sha']==HEAD and metadata['branch']['commit']['commit']['tree']['sha']==TREE,'API source identity')
    for name in ['Cargo.toml','Cargo.lock']:
        require(sha(records['upstream-'+name])==bypath[name]['sha256'],'upstream '+name)
    original=records['upstream-Cargo.toml'].decode()
    narrowed=re.sub(r'members = \[[\s\S]*?\n\]','members = [\n    "crates/crisp-docx-core",\n    "crates/crisp-docx-cli",\n]',original,count=1)
    require(narrowed.encode()==records['isolated-Cargo.toml'],'isolated manifest changed beyond members')
    old=tomllib.loads(records['upstream-Cargo.lock'].decode())['package']
    new=tomllib.loads(records['resolved-Cargo.lock'].decode())['package']
    require(len(old)==225 and len(new)==70,'lock package inventory')
    identities=lambda row:tuple(row.get(k) for k in ['name','version','source','checksum'])
    require({identities(r) for r in new}<={identities(r) for r in old},'dependency identities changed')
    require(js(records,'dependency-lock-comparison.json')['versionsAndChecksumsUnchanged'] is True,'dependency claim')
    inputs=js(records,'isolated-build-inputs.json')
    require(len(inputs['copiedFiles'])==34,'copied source count')
    for row in inputs['copiedFiles']:
        require(all(row[k]==bypath[row['path']][k] for k in ['bytes','sha256','gitBlob']),'copied source binding')
    for path,data in records.items():
        if path.endswith('.command.json'):
            command=json.loads(data)
            log=command.get('log',path.removesuffix('.command.json')+'.log')
            require(sha(records[log])==command['logSha256'],'command log binding: '+path)
            if 'logBytes' in command: require(len(records[log])==command['logBytes'],'command log size')
    require(js(records,'cargo-test-locked.command.json')['exitCode']==101,'original lock rejection retained')
    for name in ['cargo-test-current','cargo-build-adapter','cargo-live-authored','authored-probes','retained-pairs','markdown-authoring','cli-note-authoring','note-authoring-schema']:
        require(js(records,name+'.command.json')['exitCode']==0,'required successful command: '+name)
    log=records['cargo-test-current.log'].decode()
    for count in [102,13,5,6,1]: require(f'test result: ok. {count} passed; 0 failed;' in log,'default test count')
    require(log.count('— skipping')==11,'printed skip count')
    live=records['cargo-live-authored.log'].decode()
    require('test result: ok. 5 passed; 0 failed;' in live and '— skipping' not in live,'authored live execution')
    report=js(records,'probe-report.json')
    manifest=js(records,'control-manifest.json')
    require(report['sourceCommit']==HEAD and len(report['cases'])==len(manifest['cases'])==14,'authored cohort identity')
    require(set(report['cases'])==set(manifest['cases']),'authored names')
    require(len(report['commands'])==76 and len({c['name'] for c in report['commands']})==76,'probe command inventory')
    adapter=ORIGINAL_BASE+'isolated-build/target/debug/examples/oracle_adapter'
    cli=ORIGINAL_BASE+'isolated-build/target/debug/crisp-docx'
    expected_commands={}
    for name in manifest['cases']:
        input_=ORIGINAL_BASE+'controls/'+name+'.docx'
        expected_commands[name+'.inspect']=[adapter,'inspect',input_]
        for mode in ['runs','text','save']:
            expected_commands[name+'.'+mode]=[adapter,mode,input_,ORIGINAL_BASE+'results/'+name+'.'+mode+'.docx']
        expected_commands[name+'.pandoc']=['pandoc','-f','docx','-t','json','--track-changes=all',input_]
    converted=ORIGINAL_BASE+'results/notes-converted-endnotes.docx'
    back=ORIGINAL_BASE+'results/notes-converted-back.docx'
    transplanted=ORIGINAL_BASE+'results/transplanted-link.docx'
    expected_commands.update({
        'convert-endnotes':[cli,'notes-kind',ORIGINAL_BASE+'controls/notes-conversion-link.docx','--to','endnotes','-o',converted],
        'inspect-converted-endnotes':[adapter,'inspect',converted],
        'convert-footnotes':[cli,'notes-kind',converted,'--to','footnotes','-o',back],
        'inspect-converted-footnotes':[adapter,'inspect',back],
        'transplant-link':[cli,'transplant',ORIGINAL_BASE+'controls/plain.docx',ORIGINAL_BASE+'controls/transplant-source-link.docx','-o',transplanted],
        'inspect-transplant':[adapter,'inspect',transplanted],
    })
    require({c['name'] for c in report['commands']}==set(expected_commands),'exact probe command names')
    for command in report['commands']:
        require(command['argv']==expected_commands[command['name']] and command['cwd']==ORIGINAL_BASE.rstrip('/'),'exact producer argv/cwd')
        require(command['exitCode']==(63 if command['name']=='namespace-alias.pandoc' else 0),'exact producer result')
        for stream in ['stdout','stderr']:
            require(sha(records['results/'+command['name']+'.'+stream])==command[stream+'Sha256'],'probe output binding')
        require(command['argv'][0].endswith(('/oracle_adapter','/crisp-docx')) or command['argv'][0]=='pandoc','unexpected producer executable')
    def projection(key):
        p=Path(temporary_root)/PurePosixPath(key).name
        p.write_bytes(records[key])
        return ooxml_projection.project(p)
    for name,c in report['cases'].items():
        control='controls/'+name+'.docx'
        require(sha(records[control])==manifest['cases'][name]['sha256'],'authored input bytes')
        require(projection(control)==c['input'],'authored input projection: '+name)
        require(js(records,'results/'+name+'.inspect.stdout')==c['crisp'],'crisp report binding')
        for mode in ['runs','text','save']:
            key='results/'+name+'.'+mode+'.docx'
            rewritten=projection(key)
            require(rewritten==c['rewrites'][mode]['projection'],'rewrite projection: '+name+' '+mode)
            require(c['rewrites'][mode]['allPartBytesEqual'] is
                    (c['input']['parts']==rewritten['parts']),
                    'derived part equality: '+name+' '+mode)
            require(c['rewrites'][mode]['semanticProjectionEqual'] is
                    (semantic_projection(c['input'])==semantic_projection(rewritten)),
                    'derived semantic equality: '+name+' '+mode)
        require(c['rewrites']['save']['allPartBytesEqual'] is True,'raw part transport')
    def body(p): return next(s for s in p['stories'] if s['part']=='word/document.xml')
    def offsets(p,kind): return [e['offset'] for para in body(p)['paragraphs'] for e in para['events'] if e['type']==kind]
    c=report['cases']
    require(c['namespace-alias']['crisp']['publicBodyProjection']['texts']==[],'namespace omission changed')
    require(body(c['plain']['input'])['expandedXmlSha256']==body(c['namespace-alias']['input'])['expandedXmlSha256'],'namespace control equivalence')
    require(c['empty-paragraph']['crisp']['publicBodyProjection']['texts']==['Before','After'],'empty paragraph observation')
    require(offsets(c['bookmark-position']['input'],'bookmarkStart')==[1] and offsets(c['bookmark-position']['input'],'bookmarkEnd')==[2],'authored bookmark offsets')
    require(offsets(c['bookmark-position']['rewrites']['runs']['projection'],'bookmarkStart')==[3] and offsets(c['bookmark-position']['rewrites']['runs']['projection'],'bookmarkEnd')==[3],'observed bookmark relocation')
    require(offsets(c['notes-and-link']['input'],'footnoteReference')==[1] and offsets(c['notes-and-link']['rewrites']['runs']['projection'],'footnoteReference')==[3],'note offset observation')
    require(offsets(c['notes-and-link']['rewrites']['text']['projection'],'footnoteReference')==[7],'text-only note offset')
    require(not offsets(c['notes-and-link']['rewrites']['runs']['projection'],'endnoteReference'),'endnote omission')
    for mode in ['runs','text']:
        require(bool(c['textbox-story']['rewrites'][mode]['projection']['parseErrors']),'textbox malformed XML observation')
    for name in ['dangling-custom-rid','dangling-note','unclosed-bookmark']:
        require(c[name]['crisp']['check']['clean'] is True,'limited checker observation')
    for name,key in [('convertToEndnotes','results/notes-converted-endnotes.docx'),('convertToFootnotes','results/notes-converted-back.docx'),('transplant','results/transplanted-link.docx')]:
        require(projection(key)==report[name]['projection'],'mutation output binding: '+name)
    require(report['convertToFootnotes']['projection']['parts']==c['notes-conversion-link']['input']['parts'],'exact endpoint metamorphism')
    require({x['kind'] for x in report['convertToEndnotes']['projection']['issues']}=={'orphanRelationships','unresolvedInlineRelationship'},'intermediate note relationship break')
    require(body(report['convertToEndnotes']['projection'])['paragraphs'][0]['acceptedText']=='Literal EndnoteText','intermediate literal mutation')
    schema_sets=[('authored-schema-controls.json','controls',14,2),('authored-schema-rewrites.json','results',45,8),('note-authoring-schema.json','note-schema',2,0)]
    for name,folder,count,failures in schema_sets:
        schema=js(records,name)
        expected={p for p in records if p.startswith(folder+'/') and p.endswith('.docx')}
        require(schema['Files']==count==len(expected) and schema['Failures']==failures,'SDK inventory '+name)
        found=set();errors=0
        for row in schema['Reports']:
            require(set(row)=={'File','Sha256','Errors'},'SDK success/error row shape')
            key=local_name(row['File']);found.add(key)
            require(key in expected and sha(records[key])==row['Sha256'],'SDK exact input '+name)
            errors+=bool(row['Errors'])
        require(found==expected and len(schema['Reports'])==len(found) and errors==failures,'SDK coverage '+name)
        command=js(records,name.removesuffix('.json')+'.command.json')
        expected_argv=['/workspace/scratch/c1ca2a1344e9/toolchains/dotnet-8.0.428/dotnet','/workspace/scratch/c1ca2a1344e9/final-schema-c5ff75e7/validator/OfficeValidation.dll',ORIGINAL_BASE+folder,ORIGINAL_BASE+name]
        require(command['argv']==expected_argv and command['exitCode']==(1 if failures else 0),'SDK executable/target/result binding')
    sdk=js(records,'sdk-validator-provenance.json')
    require(sdk['sourceRuntime']=='c5ff75e76163d9abbdd44a9f2a7c5ad210929289','SDK source runtime')
    for artifact,want in sdk['validatorBuild']['artifacts'].items():
        if artifact.endswith('.dll'):
            candidates=[x for x in source['tools'] if x['path'].endswith('/'+artifact)]
            require(len(candidates)==1 and candidates[0]['sha256']==want,'SDK tool identity '+artifact)
    input_schema={Path(x['File']).stem:x for x in js(records,'authored-schema-controls.json')['Reports']}
    require([x['Id'] for x in input_schema['dangling-custom-rid']['Errors']]==['Sem_InvalidRelationshipId'],'independent relationship control')
    require([x['Id'] for x in input_schema['dangling-note']['Errors']]==['Sem_MissingReferenceElement'],'independent note control')
    require(not input_schema['textbox-story']['Errors'] and not input_schema['namespace-alias']['Errors'],'independent valid-input controls')
    pairs=js(records,'retained-pair-report.json')
    require(pairs['parserRuntime']=='c5ff75e76163d9abbdd44a9f2a7c5ad210929289' and pairs['crispDocxCommit']==HEAD and len(pairs['cases'])==9,'retained corpus identity')
    for case,row in pairs['cases'].items():
        require(set(row['inputs'])=={'native','parser'},'retained pair roles')
        for role,input_ in row['inputs'].items():
            key='retained-pairs/'+input_['record'];raw=records[key];detail=json.loads(raw)
            require(sha(raw)==input_['recordSha256'],'retained pair observation binding')
            require(detail['sha256']==detail['projection']['sha256'],'retained input identity')
            require(projection_summary(detail['projection'])==detail['summary']==input_['summary'],
                    'retained projection summary')
            require(detail['crisp']['check']['clean'] is True,'retained clean observation')
            for stem,command in [('crisp',detail['crispCommand']),('pandoc',detail['pandocCommand'])]:
                absolute='/workspace/scratch/c1ca2a1344e9/final-native-c5ff75e7/'+detail['inputPath']
                expected=[adapter,'inspect',absolute] if stem=='crisp' else ['pandoc','-f','docx','-t','json','--track-changes=all',absolute]
                require(command['argv']==expected and command['cwd']==ORIGINAL_BASE.rstrip('/') and command['exitCode']==0,'retained pair exact argv')
                for stream in ['stdout','stderr']:
                    require(sha(records['retained-pairs/'+case+'.'+role+'.'+stem+'.'+stream])==command[stream+'Sha256'],'retained command output')
            require(detail['crisp']==js(records,'retained-pairs/'+case+'.'+role+'.crisp.stdout'),'retained Rust result binding')
            require(detail['pandoc']==js(records,'retained-pairs/'+case+'.'+role+'.pandoc.stdout'),
                    'retained Pandoc result binding')
            crisp=detail['crisp'];paragraph_runs=crisp['publicBodyProjection']['paragraphRuns']
            derived={'crispClean':crisp['check'].get('clean'),
                     'crispIssues':crisp['check'].get('issues'),
                     'crispTexts':crisp['publicBodyProjection']['texts'],
                     'crispRunText':[p['text'] for p in paragraph_runs] if isinstance(paragraph_runs,list) else None,
                     'pandocExitCode':detail['pandocCommand']['exitCode'],
                     'pandocCanonicalSha256':sha(json.dumps(detail['pandoc'],sort_keys=True,separators=(',',':')).encode()) if detail['pandoc'] else None}
            for name,expected in derived.items():
                require(input_[name]==expected,'retained derived observation: '+name)
        a=row['inputs']['parser'];b=row['inputs']['native']
        expected_comparison={'crispTextArraysEqual':a['crispTexts']==b['crispTexts'],
                             'crispRunTextArraysEqual':a['crispRunText']==b['crispRunText'],
                             'pandocAstEqual':a['pandocCanonicalSha256']==b['pandocCanonicalSha256'],
                             'projectionSummariesEqual':a['summary']==b['summary']}
        require(set(row['comparison'])==set(expected_comparison),'retained comparison keys')
        for name,expected in expected_comparison.items():
            require(row['comparison'][name] is expected,'retained derived comparison: '+name)
    require(sum(r['comparison']['crispTextArraysEqual'] for r in pairs['cases'].values())==6,'flat-text pair count')
    require(sum(r['comparison']['crispRunTextArraysEqual'] for r in pairs['cases'].values())==7,'run-text pair count')
    require(sum(r['comparison']['pandocAstEqual'] for r in pairs['cases'].values())==1,'Pandoc pair count')
    require(sum(r['comparison']['projectionSummariesEqual'] for r in pairs['cases'].values())==3,'projection-summary pair count')
    notes=js(records,'note-authoring-report.json')
    require(notes['crisp']['references']==['1','1'] and len(notes['crisp']['notes'])==1,'CLI note identity')
    require(len(set(notes['pandoc']['references']))==2 and len(notes['pandoc']['notes'])==2,'Pandoc note identity')
    for producer,row in notes.items():
        require(projection('note-authoring-'+producer+'.docx')==row['projection'],'note authoring bytes')
        require(all(n['boldRuns']==n['italicRuns']==n['hyperlinks']==1 for n in row['notes']),'note formatting controls')
    binary=js(records,'binary-type-confusion.json')
    require(binary['first16Hex'].startswith('d0cf11e0a1b11ae1') and binary['zipfileIsZipFile'] and not binary['hasMainWordDocument'],'binary handoff observation')
    require(js(records,'binary-input-control.command.json')['exitCode']==0 and js(records,'binary-check-control.command.json')['exitCode']==1,'binary inspect/check scope')
    return source,pairs

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source-repository',type=Path);parser.add_argument('--native-corpus',type=Path)
    args=parser.parse_args();base=Path(__file__).resolve().parent
    receipt=json.loads((base/'receipt.json').read_text())
    for name,want in receipt['files'].items():
        raw=(base/name).read_bytes();require(len(raw)==want['bytes'] and sha(raw)==want['sha256'],'outer file: '+name)
    archive=(base/'records.tar.xz').read_bytes();manifest=json.loads((base/'record-manifest.json').read_text())
    records={}
    with tarfile.open(fileobj=io.BytesIO(archive),mode='r:xz') as tar:
        for item in tar:
            p=PurePosixPath(item.name)
            require(item.isfile() and not p.is_absolute() and '..' not in p.parts and item.name not in records,'unsafe/duplicate member')
            records[item.name]=tar.extractfile(item).read()
    require(set(records)==set(manifest) and len(records)==receipt['recordCount'],'record inventory')
    for name,data in records.items(): require({'bytes':len(data),'sha256':sha(data)}==manifest[name],'record bytes: '+name)
    probe=js(records,'probe-report.json')
    for name,row in probe['toolIdentities'].items():
        if '/' not in name:
            raw=(base/name).read_bytes()
            require(len(raw)==row['bytes'] and sha(raw)==row['sha256'],'measured adapter/projection source '+name)
    with TemporaryDirectory(prefix='crisp-oracle-verify-',dir=base.parent) as temp:
        source,pairs=verify_records(records,temp)
    source_count=native_count=0
    if args.source_repository:
        actual=subprocess.check_output(['git','rev-parse','HEAD'],cwd=args.source_repository,text=True).strip()
        require(actual==HEAD,'source checkout head')
        for row in source['trackedSources']:
            raw=subprocess.check_output(['git','show',HEAD+':'+row['path']],cwd=args.source_repository)
            require(len(raw)==row['bytes'] and sha(raw)==row['sha256'],'source Git object '+row['path']);source_count+=1
    if args.native_corpus:
        for case,row in pairs['cases'].items():
            raw=(args.native_corpus/row['binary']['path']).read_bytes()
            require(sha(raw)==row['binary']['sha256'],'retained binary '+case)
            for input_ in row['inputs'].values():
                detail=js(records,'retained-pairs/'+input_['record'])
                p=args.native_corpus/detail['inputPath']
                require(ooxml_projection.project(p)==detail['projection'],'retained native/parser input '+str(p));native_count+=1
    print(json.dumps({'verifiedRecords':len(records),'authoredInputs':14,'rewrittenOutputs':45,'sdkInputControls':14,'sdkAuthoringOutputs':2,'retainedPairs':9,'directSourceGitObjects':source_count,'directRetainedDocxInputs':native_count,'scope':'Retained artifact/semantic bindings; no Rust, Pandoc, SDK or native workflow rerun.'},indent=2))

if __name__=='__main__': main()
