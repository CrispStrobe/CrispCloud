#!/usr/bin/env python3
"""Fail if an exposed scripting operation has no checked-in executable scenario.

This measures scenario coverage, not correctness or full OOXML support. Semantic,
mutation, visual and external-schema oracles are separate required checks.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'test/fixtures/fidelity/scripts'

def audit(catalog):
    scenarios = {'docx':[FIXTURES/'word.json',ROOT/'tool/fidelity/example_steps.json'],
                 'xlsx':[FIXTURES/'sheet.json'],'pptx':[FIXTURES/'slide.json']}
    # Keep this list aligned with the executable phases in
    # word_structure_steps_test.dart. An unexecuted JSON file must not satisfy
    # coverage just because its filename matches a wildcard.
    scenarios['docx'].extend(FIXTURES/f'word-structure-{phase}.json'
                             for phase in ('create', 'edit', 'remove'))
    rows=[]
    for extension, operations in catalog.items():
        evidence={name:[] for name in operations}
        for script in scenarios[extension]:
            for index, step in enumerate(json.loads(script.read_text()),1):
                op=step['op']
                if op not in operations: raise AssertionError(f'{script}:{index}: unregistered operation {op}')
                unknown=set(step)-{'op'}-set(operations[op])
                if unknown: raise AssertionError(f'{script}:{index}: unknown fields {unknown}')
                evidence[op].append({'script':str(script.relative_to(ROOT)),'step':index})
        for op, sources in evidence.items():
            if not sources: raise AssertionError(f'Unexercised operation: {extension}/{op}')
            rows.append({'format':extension,'operation':op,'scenarios':sources})
    return {'schema_version':1,'operations':len(rows),'unexercised':[],
            'scope':'Operation-name inventory in the explicitly executed scenarios; parameter/edge-case coverage is not measured. Semantic correctness is checked by independent oracles.',
            'evidence':rows}

if __name__=='__main__':
    result=subprocess.run(['dart','run','tool/fidelity/office_steps.dart','operations'],cwd=ROOT,check=True,capture_output=True,text=True)
    report=audit(json.loads(result.stdout))
    out=ROOT/'build/fidelity-scripted/operation-coverage.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+'\n')
    print(f"All {report['operations']} public operations have committed executable scenarios.")
