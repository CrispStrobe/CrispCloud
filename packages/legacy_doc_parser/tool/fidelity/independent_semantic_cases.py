#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Author bounded OOXML semantic probes independently of the binary parser.

The accompanying contracts are authored inputs, not converter snapshots or
automatic goldens. Native bridge observations must remain separate from them.
Existing output directories are never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'


def package(path, body, *, additional_parts=None, relationships=(), overrides=()):
    parts = {
        '[Content_Types].xml': f'<Types xmlns="{CT}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' + ''.join(f'<Override PartName="/{name}" ContentType="{kind}"/>' for name, kind in overrides) + '</Types>',
        '_rels/.rels': f'<Relationships xmlns="{REL}"><Relationship Id="office" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/_rels/document.xml.rels': f'<Relationships xmlns="{REL}"><Relationship Id="style" Type="{R}/styles" Target="styles.xml"/>' + ''.join(f'<Relationship Id="{rid}" Type="{R}/{kind}" Target="{target}"/>' for rid, kind, target in relationships) + '</Relationships>',
        'word/styles.xml': f'<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>',
        'word/document.xml': f'<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body>{body}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>',
        **(additional_parts or {}),
    }
    with zipfile.ZipFile(path, 'x') as archive:
        for name, xml in sorted(parts.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + xml).encode())


def text(value):
    from xml.sax.saxutils import escape
    return '<w:r><w:t xml:space="preserve">' + escape(value) + '</w:t></w:r>'


def paragraph(value):
    return '<w:p>' + text(value) + '</w:p>'


def character_controls(output):
    expected = ['NB:A\u2011B', 'SH:A\u00adB', 'TAB:A\tB',
                'UNICODE:é e\u0301 Ω 漢 🙂 \u200fאבג', 'SPACES:  before  after  ']
    body = '<w:p>' + text('NB:A') + '<w:r><w:noBreakHyphen/></w:r>' + text('B') + '</w:p>'
    body += '<w:p>' + text('SH:A') + '<w:r><w:softHyphen/></w:r>' + text('B') + '</w:p>'
    body += '<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>' + text('TAB:A') + '<w:r><w:tab/></w:r>' + text('B') + '</w:p>'
    body += ''.join(paragraph(value) for value in expected[3:])
    package(output, body)
    return {'mainParagraphs': expected, 'runControlCounts': {'noBreakHyphen': 1, 'softHyphen': 1, 'tab': 1},
            'reason': 'Literal nonbreaking/optional hyphen controls, actual tab versus tab-stop property, Unicode scalar/combining characters and preserved edge spaces.'}


def symbol_glyphs(output):
    glyphs = [('Symbol', 'F061'), ('Symbol', 'F057'), ('Wingdings', 'F0FC')]
    body = ''.join('<w:p>' + text(f'SYMBOL-{index}:[') + f'<w:r><w:sym w:font="{font}" w:char="{code}"/></w:r>' + text(']') + '</w:p>' for index, (font, code) in enumerate(glyphs, 1))
    body += paragraph('CONTROL:( α Ω ✓')
    package(output, body)
    return {'symbolGlyphs': [{'font': font, 'char': code} for font, code in glyphs],
            'literalControl': 'CONTROL:( α Ω ✓',
            'reason': 'Each source glyph is identified by its font and symbol operand; no font-dependent Unicode equivalence is assumed.'}


def locked_fields(output):
    field = lambda code, value: '<w:r><w:fldChar w:fldCharType="begin" w:fldLock="1"/></w:r><w:r><w:instrText xml:space="preserve">' + code + '</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>' + text(value) + '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
    body = '<w:p><w:bookmarkStart w:id="27" w:name="Target_A"/>' + text('ANCHOR-α') + '<w:bookmarkEnd w:id="27"/></w:p>'
    body += '<w:p>' + text('REF:[') + field(' REF Target_A \\h ', 'CACHED-REF') + text(']') + '</w:p>'
    body += '<w:p>' + text('LINK:[') + field(' HYPERLINK \\l "Target_A" ', 'CACHED-LINK') + text(']') + '</w:p>'
    body += '<w:p>' + text('QUOTE:[') + field(' QUOTE "LITERAL-β" ', 'CACHED-QUOTE') + text(']') + '</w:p>'
    package(output, body)
    return {'mainParagraphs': ['ANCHOR-α', 'REF:[CACHED-REF]', 'LINK:[CACHED-LINK]', 'QUOTE:[CACHED-QUOTE]'],
            'fields': [{'instruction': 'REF Target_A \\h', 'result': 'CACHED-REF'}, {'instruction': 'HYPERLINK \\l "Target_A"', 'result': 'CACHED-LINK'}, {'instruction': 'QUOTE "LITERAL-β"', 'result': 'CACHED-QUOTE'}],
            'bookmarks': [{'name': 'Target_A', 'text': 'ANCHOR-α'}],
            'reason': 'Distinct locked cached results separate literal source fields, bridge evaluation and parser field serialization.'}


def note_joins(output):
    body = '<w:p>' + text('MAIN-A[') + '<w:r><w:footnoteReference w:id="19"/></w:r>' + text('] MAIN-B[') + '<w:r><w:footnoteReference w:id="7"/></w:r>' + text(']') + '</w:p>'
    notes = f'<w:footnotes xmlns:w="{W}"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote><w:footnote w:id="7"><w:p><w:r><w:footnoteRef/></w:r>' + text('NOTE-B:β') + '</w:p></w:footnote><w:footnote w:id="19"><w:p><w:r><w:footnoteRef/></w:r>' + text('NOTE-A:α') + '</w:p></w:footnote></w:footnotes>'
    package(output, body, additional_parts={'word/footnotes.xml': notes}, relationships=[('notes', 'footnotes', 'footnotes.xml')], overrides=[('word/footnotes.xml', 'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml')])
    return {'mainParagraphs': ['MAIN-A[] MAIN-B[]'], 'footnoteReferenceTexts': ['NOTE-A:α', 'NOTE-B:β'],
            'reason': 'Source part order and numeric IDs disagree with reference order; preserve reference-to-note identity rather than a text multiset.'}


CASES = {'character-controls': character_controls, 'symbol-glyphs': symbol_glyphs,
         'locked-fields': locked_fields, 'note-joins': note_joins}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {'schema': 'legacy-doc-parser/independent-semantic-inputs', 'version': 1,
                'authoring': 'Literal OOXML plus independently written contracts; no parser result is used to derive expected values.', 'cases': []}
    for name, author in CASES.items():
        path = args.output / (name + '.docx')
        contract = author(path)
        manifest['cases'].append({'id': name, 'path': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'contract': contract})
    (args.output / 'contracts.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
