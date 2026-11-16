#!/usr/bin/env python3
"""Reproduce final adapters/targets from recorded source and committed prior target list."""
from pathlib import Path
import hashlib,json,re,difflib,subprocess,datetime
TC=Path(__file__).resolve().parent;R=TC.parent/'CrispCloud';B=TC/'evidence/final-acceptance'
B.mkdir(exist_ok=False)
def ident(p):
 d=p.read_bytes();return {'bytes':len(d),'sha256':hashlib.sha256(d).hexdigest(),'mode':oct(p.stat().st_mode&0o777)}
def sites(s):
 return {k:len(re.findall(r'\b'+k+r'\s*\(',s)) for k in ['test','testWidgets','expect','expectLater']}
eng='packages/quds_office_engine/test/'
names=['ods_sheet_reader_test.dart','sheet_formula_test.dart','zotero_client_test.dart','zotero_identity_client_test.dart','zotero_metadata_batch_test.dart','word_zotero_scaling_test.dart','word_zotero_citing_test.dart']
adapterdir=R/'build/final-incoming-tests';adapterdir.mkdir(parents=True,exist_ok=False)
adapters=[]
for name in names:
 original=eng+name;adapted='build/final-incoming-tests/'+name
 raw=(R/original).read_text();changes=[["import 'package:test/test.dart';","import 'package:flutter_test/flutter_test.dart';"]]
 if name=='ods_sheet_reader_test.dart':
  changes += [[f"'test/fixtures/fidelity/{fixture}'",f"'packages/quds_office_engine/test/fixtures/fidelity/{fixture}'"] for fixture in ['legacy-sheet.ods','legacy-sheet-edge.ods']]
 if name=='word_zotero_citing_test.dart':
  changes += [["'test/fixtures/zotero/citing/processor-output.json'","'packages/quds_office_engine/test/fixtures/zotero/citing/processor-output.json'"]]
 out=raw
 for old,new in changes:
  assert out.count(old)==1,(name,old,out.count(old))
  out=out.replace(old,new)
 reverse=out
 for old,new in reversed(changes):
  assert reverse.count(new)==1,(name,new)
  reverse=reverse.replace(new,old)
 assert reverse==raw
 assert sites(raw)==sites(out)
 (R/adapted).write_text(out)
 adapters.append({'original_path':original,'adapted_path':adapted,'original':ident(R/original),'adapted':ident(R/adapted),'substitutions':changes,'reverse_recovers_every_original_byte':True,'lexical_callsite_counts_unchanged':sites(raw),'diff':''.join(difflib.unified_diff(raw.splitlines(keepends=True),out.splitlines(keepends=True),fromfile=original,tofile=adapted))})
fixtures=[eng+'fixtures/fidelity/legacy-sheet.ods',eng+'fixtures/fidelity/legacy-sheet-edge.ods',eng+'fixtures/zotero/citing/processor-output.json']
protected=[*(a['original_path'] for a in adapters),'packages/quds_office_editor/test/word_zotero_dialog_test.dart','test/widget/ods_editor_workflow_test.dart',*fixtures,'pubspec.yaml','pubspec.lock','.fvmrc','.dart_tool/package_config.json','.dart_tool/package_graph.json','tool/office_fidelity_manifest.json']
prep={'accepted_source':'fdc262e112aa29dd1e60a76cff9a2dfb5f2d7b4f','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'qualification':'Immutable host test adapters only: package:test -> flutter_test and explicit fixture prefixes. Application, production graph, original assertions and vendor source are unchanged. Lexical counts are not runtime pass counts.','adapters':adapters,'editor_suite_original_unchanged':{'path':'packages/quds_office_editor/test/word_zotero_dialog_test.dart','identity':ident(R/'packages/quds_office_editor/test/word_zotero_dialog_test.dart'),'lexical_callsites':sites((R/'packages/quds_office_editor/test/word_zotero_dialog_test.dart').read_text())},'fixtures':fixtures,'protected_inputs_before':{p:ident(R/p) for p in protected}}
(B/'incoming-office').mkdir();(B/'incoming-office/preparation.json').write_text(json.dumps(prep,indent=2)+'\n')
baseline=json.loads((R/'docs/validation/terminal-workspace-recovery/recovered-worker/static-targets.json').read_text())
old=baseline['files']
assert len(old)==164,len(old)
added=['test/terminal_session_test.dart','packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart','packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart','packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart','packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart','packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart','packages/quds_office_engine/lib/src/zotero/zotero_client.dart','packages/quds_office_editor/test/word_zotero_dialog_test.dart',eng+'ods_sheet_reader_test.dart',eng+'word_zotero_scaling_test.dart',eng+'zotero_metadata_batch_test.dart']
originals=sorted(set(old+added));assert len(originals)==175,len(originals)
mapping={a['original_path']:a['adapted_path'] for a in adapters}
targets={'accepted_source':prep['accepted_source'],'original_semantic_targets':originals,'analysis_targets':[mapping.get(p,p) for p in originals],'format_targets':originals,'analysis_adapter_mappings':{p:mapping[p] for p in originals if p in mapping},'original_target_count':175,'previous_target_count':164,'added_targets':added,'formatter_reads_originals_without_writes':True}
(B/'static-targets.json').write_text(json.dumps(targets,indent=2)+'\n')
print('FINAL_PREPARATION '+json.dumps({'adapters':len(adapters),'protected_inputs':len(protected),'static_targets':175,'analysis_adapter_count':len(targets['analysis_adapter_mappings']),'source':prep['accepted_source']}))
