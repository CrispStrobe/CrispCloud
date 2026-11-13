"""Independently authored OOXML controls, not copied from crisp-docx fixtures."""
from pathlib import Path
import hashlib, json, zipfile
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent
OUT = BASE / 'controls'
OUT.mkdir(exist_ok=True)
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
styles = f'<w:styles xmlns:w="{W}"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
def run(text): return '<w:r><w:t xml:space="preserve">'+escape(text)+'</w:t></w:r>'
def para(text): return '<w:p>'+run(text)+'</w:p>'
def relationships(rows):
    return '<Relationships xmlns="'+REL+'">'+''.join('<Relationship Id="'+rid+'" Type="'+R+'/'+kind+'" Target="'+escape(target, {'"':'&quot;'})+'"'+(' TargetMode="External"' if external else '')+'/>' for rid,kind,target,external in rows)+'</Relationships>'
def write(name, body, extras=None, relations=None, section='', prefix='w'):
    parts = dict(extras or {})
    document = f'<w:document xmlns:w="{W}" xmlns:r="{R}" xmlns:v="urn:schemas-microsoft-com:vml"><w:body>{body}<w:sectPr>{section}</w:sectPr></w:body></w:document>'
    if prefix != 'w': document = document.replace('w:',prefix+':').replace('xmlns:w=', 'xmlns:'+prefix+'=')
    parts['word/document.xml'] = document
    parts['word/styles.xml'] = styles
    rows = [('rIdStyles','styles','styles.xml',False)] + list(relations or [])
    parts['word/_rels/document.xml.rels'] = relationships(rows)
    parts['_rels/.rels'] = relationships([('rIdDocument','officeDocument','word/document.xml',False)])
    overrides = {'word/document.xml':'document.main','word/styles.xml':'styles'}
    for part in parts:
        for prefix_, kind in [('word/footnotes.xml','footnotes'),('word/endnotes.xml','endnotes'),('word/header','header'),('word/footer','footer')]:
            if part.startswith(prefix_) and part.endswith('.xml'):
                overrides[part] = kind
    parts['[Content_Types].xml'] = '<Types xmlns="'+CT+'"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'+''.join('<Override PartName="/'+part+'" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.'+kind+'+xml"/>' for part,kind in sorted(overrides.items()))+'</Types>'
    path = OUT / (name+'.docx')
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as package:
        for part, content in sorted(parts.items()):
            info = zipfile.ZipInfo(part, (2026,11,13,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(info, content.encode() if isinstance(content,str) else content)
    return path

def footnotes(content):
    return f'<w:footnotes xmlns:w="{W}" xmlns:r="{R}"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:r><w:footnoteRef/></w:r>{content}</w:p></w:footnote></w:footnotes>'
def endnotes(content):
    return footnotes(content).replace('footnote','endnote')

cases = {}
def case(name, expected, *args, **kwargs):
    p=write(name,*args,**kwargs)
    cases[name]={'path':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'authoredExpected':expected}

case('plain',{'bodyTexts':['Alpha β','Second'],'paragraphCount':2},para('Alpha β')+para('Second'))
case('empty-paragraph',{'bodyTexts':['Before','','After'],'paragraphCount':3},para('Before')+'<w:p/>'+para('After'))
case('tabs-breaks',{'bodyTexts':['A\tB\nC'],'tabCount':1,'breakCount':1},'<w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t><w:br/><w:t>C</w:t></w:r></w:p>')
case('bookmark-position',{'bodyTexts':['ABC'],'bookmarkStartOffsets':[1],'bookmarkEndOffsets':[2]},'<w:p>'+run('A')+'<w:bookmarkStart w:id="7" w:name="middle"/>'+run('B')+'<w:bookmarkEnd w:id="7"/>'+run('C')+'</w:p>')
note_body='<w:p><w:r><w:t>A</w:t><w:footnoteReference w:id="1"/><w:t>B</w:t><w:endnoteReference w:id="1"/><w:t>C</w:t></w:r><w:hyperlink r:id="rIdLink">'+run('LINK')+'</w:hyperlink></w:p>'
case('notes-and-link',{'bodyTexts':['ABCLINK'],'footnoteOffsets':[1],'endnoteOffsets':[2],'hyperlinks':1},note_body,extras={'word/footnotes.xml':footnotes(run('Footnote body')),'word/endnotes.xml':endnotes(run('Endnote body'))},relations=[('rIdFoot','footnotes','footnotes.xml',False),('rIdEnd','endnotes','endnotes.xml',False),('rIdLink','hyperlink','https://example.test/a',True)])
table='<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:tcPr/>'+para('Cell A')+'</w:tc><w:tc><w:tcPr/>'+para('Cell B')+'</w:tc></w:tr></w:tbl>'
case('table-and-stories',{'bodyTexts':['Body','Cell A','Cell B'],'tableRows':[2],'headerTexts':['Header text'],'footerTexts':['Footer text']},para('Body')+table,extras={'word/header1.xml':f'<w:hdr xmlns:w="{W}">{para("Header text")}</w:hdr>','word/footer1.xml':f'<w:ftr xmlns:w="{W}">{para("Footer text")}</w:ftr>'},relations=[('rIdHead','header','header1.xml',False),('rIdFoot','footer','footer1.xml',False)],section='<w:headerReference w:type="default" r:id="rIdHead"/><w:footerReference w:type="default" r:id="rIdFoot"/>')
case('revisions',{'acceptedText':'BaseNEW','rejectedText':'BaseOLD','insertionCount':1,'deletionCount':1},'<w:p>'+run('Base')+'<w:ins w:id="11" w:author="Audit" w:date="2026-11-13T00:00:00Z">'+run('NEW')+'</w:ins><w:del w:id="12" w:author="Audit" w:date="2026-11-13T00:00:00Z"><w:r><w:delText>OLD</w:delText></w:r></w:del></w:p>')
textbox='<w:p>'+run('Before')+'<w:r><w:pict><v:shape id="AuditBox" style="width:72pt;height:36pt"><v:textbox><w:txbxContent>'+para('Textbox')+'</w:txbxContent></v:textbox></v:shape></w:pict></w:r>'+run('After')+'</w:p>'
case('textbox-story',{'bodyOwnText':'BeforeAfter','textboxText':'Textbox','paragraphCount':2},textbox)
case('namespace-alias',{'bodyTexts':['Alpha β','Second'],'namespaceEquivalentTo':'plain'},para('Alpha β')+para('Second'),prefix='x')
case('dangling-custom-rid',{'deliberatelyInvalid':'unresolved customLink relationship','mustRejectAsFullValidator':True},'<w:p><w:hyperlink r:id="customLink">'+run('Lost link')+'</w:hyperlink></w:p>')
case('dangling-note',{'deliberatelyInvalid':'reference to absent footnote id2','mustRejectAsFullValidator':True},'<w:p><w:r><w:footnoteReference w:id="2"/></w:r></w:p>',extras={'word/footnotes.xml':footnotes(run('Only note one'))},relations=[('rIdFoot','footnotes','footnotes.xml',False)])
case('unclosed-bookmark',{'deliberatelyInvalid':'bookmarkStart7 without bookmarkEnd7','mustRejectAsFullValidator':True},'<w:p><w:bookmarkStart w:id="7" w:name="open"/>'+run('Text')+'</w:p>')
case('notes-conversion-link',{'bodyTexts':['Literal FootnoteText'], 'noteHyperlinkTarget':'https://example.test/note','convertMustPreserveLiteralText':True},'<w:p>'+run('Literal FootnoteText')+'<w:r><w:footnoteReference w:id="1"/></w:r></w:p>',extras={'word/footnotes.xml':footnotes('<w:hyperlink r:id="noteLink">'+run('Note link')+'</w:hyperlink>'),'word/_rels/footnotes.xml.rels':relationships([('noteLink','hyperlink','https://example.test/note',True)])},relations=[('rIdFoot','footnotes','footnotes.xml',False)])
case('transplant-source-link',{'bodyTexts':['Source link'],'mustCarryHyperlink':'https://example.test/source'},'<w:p><w:hyperlink r:id="rId9">'+run('Source link')+'</w:hyperlink></w:p>',relations=[('rId9','hyperlink','https://example.test/source',True)])
(BASE/'control-manifest.json').write_text(json.dumps({'provenance':'Independently authored minimal OOXML; expected semantic constants written by audit author. No upstream DOCX or implementation copied. Cases explicitly labeled invalid are negative validator probes.','cases':cases},indent=2,ensure_ascii=False)+'\n')
print('Authored',len(cases),'controls')
