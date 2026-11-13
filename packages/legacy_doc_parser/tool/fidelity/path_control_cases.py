#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Author explicit Markdown metadata and alternate note-ID path controls."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from independent_semantic_cases import W, package, text

ROOT = Path(__file__).resolve().parents[2]
NOTE_SOURCE_SHA = 'add41f4c94e0329302c63b4f6839640a93b14651895995a784551452c2288914'


def author(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    metadata = directory / 'markdown-metadata.docx'
    styles = (f'<w:styles xmlns:w="{W}">'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Author"><w:name w:val="Author"/><w:basedOn w:val="Normal"/></w:style>'
              '</w:styles>')
    body = ''.join('<w:p><w:pPr><w:pStyle w:val="' + style + '"/></w:pPr>' + text(value) + '</w:p>'
                   for style, value in [('Title', 'KEPT-TITLE'), ('Author', 'KEPT-AUTHOR'), ('Normal', 'BODY')])
    package(metadata, body, additional_parts={'word/styles.xml': styles})

    # This is one explicitly labeled experimental input, not a general repair
    # or a rewrite of the original independent golden. No note text or anchor
    # changes: only both sides of each ID join are renamed 19→1 and 7→2.
    source = ROOT / 'test/fixtures/fidelity/semantic-contracts/note-joins.docx'
    if hashlib.sha256(source.read_bytes()).hexdigest() != NOTE_SOURCE_SHA:
        raise ValueError('Independent source note contract changed')
    notes = directory / 'note-identifiers.docx'
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(notes, 'x') as output:
        for info in original.infolist():
            raw = original.read(info)
            if info.filename in ('word/document.xml', 'word/footnotes.xml'):
                if raw.count(b'w:id="19"') != 1 or raw.count(b'w:id="7"') != 1:
                    raise ValueError('Unexpected authored note identifiers')
                raw = raw.replace(b'w:id="19"', b'w:id="1"').replace(b'w:id="7"', b'w:id="2"')
            output.writestr(info, raw)
    contracts = [
        {'path': metadata.name, 'contract': {'visibleParagraphs': ['KEPT-TITLE', 'KEPT-AUTHOR', 'BODY'],
          'styles': ['Title', 'Author', 'Normal'],
          'reason': 'Separate styled title/author metadata from body-only Markdown equality.'}},
        {'path': notes.name, 'source': {'path': source.relative_to(ROOT).as_posix(), 'sha256': NOTE_SOURCE_SHA},
         'contract': {'mainParagraph': 'MAIN-A[] MAIN-B[]', 'referenceTexts': ['NOTE-A:α', 'NOTE-B:β'],
                      'renamedIds': {'19': 1, '7': 2}, 'notePartOrder': ['NOTE-B:β', 'NOTE-A:α'],
                      'reason': 'Labeled alternative producer input; retain the original unordered-ID control separately.'}},
    ]
    for contract in contracts:
        raw = (directory / contract['path']).read_bytes()
        contract.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    result = {'schema': 'legacy-doc-parser/path-controls', 'version': 1,
              'authoring': 'Literal XML/explicit ID renaming and authored contracts, never derived from converter output.',
              'cases': contracts}
    (directory / 'contracts.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    print(json.dumps(author(parser.parse_args().output), ensure_ascii=False, indent=2))
