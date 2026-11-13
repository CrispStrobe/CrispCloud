"""Small namespace-aware audit projection, independent of both document parsers.

This is a structural observation tool, not a complete OOXML validator or renderer.
It keeps story/paragraph/cell paths and typed inline events instead of flattening
all text. It does not resolve style inheritance, fields, layout, or revisions of
paragraph/table properties. Expected test values are separately authored.
"""
from collections import Counter
from pathlib import Path
import hashlib, json, posixpath, zipfile
import xml.etree.ElementTree as ET

W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL='http://schemas.openxmlformats.org/package/2006/relationships'
def local(tag): return tag.rsplit('}',1)[-1]
def sha(data): return hashlib.sha256(data).hexdigest()
def expanded_tree(node):
    return [node.tag,sorted(node.attrib.items()),node.text or '',[[expanded_tree(c),c.tail or ''] for c in node]]
def relation_owner(part):
    if part=='_rels/.rels': return ''
    return part.replace('/_rels/','/').removesuffix('.rels')
def relationship_part(owner):
    folder,name=posixpath.split(owner)
    return posixpath.join(folder,'_rels',name+'.rels')

def project(path):
    path=Path(path)
    with zipfile.ZipFile(path) as z:
        if len(z.namelist())!=len(set(z.namelist())):
            raise ValueError('duplicate ZIP members')
        data={name:z.read(name) for name in z.namelist()}
    roots={}
    errors=[]
    for name,content in sorted(data.items()):
        if name.endswith(('.xml','.rels')):
            try: roots[name]=ET.fromstring(content)
            except ET.ParseError as e: errors.append({'part':name,'error':str(e)})
    rels={}
    issues=[]
    for part,root in roots.items():
        if not part.endswith('.rels'): continue
        owner=relation_owner(part)
        if owner and owner not in data: issues.append({'kind':'orphanRelationships','part':part,'owner':owner})
        entries={}
        for r in root:
            if r.tag!='{'+REL+'}Relationship': continue
            rid=r.get('Id');target=r.get('Target','');external=r.get('TargetMode')=='External'
            resolved=target if external else posixpath.normpath(posixpath.join(posixpath.dirname(owner),target)).lstrip('/')
            if rid in entries: issues.append({'kind':'duplicateRelationshipId','part':part,'id':rid})
            entries[rid]={'type':r.get('Type'),'target':target,'external':external,'resolved':resolved}
            if not external and resolved not in data: issues.append({'kind':'missingRelationshipTarget','part':part,'id':rid,'target':resolved})
        rels[owner]=entries
    for part,root in roots.items():
        if part.endswith('.rels'): continue
        for node in root.iter():
            for attr,value in node.attrib.items():
                if attr in ['{'+R+'}id','{'+R+'}embed','{'+R+'}link'] and value not in rels.get(part,{}):
                    issues.append({'kind':'unresolvedInlineRelationship','part':part,'attribute':local(attr),'id':value})
    notes={kind:{node.get('{'+W+'}id') for node in roots.get('word/'+kind+'.xml',[]) if node.tag=='{'+W+'}'+singular} for kind,singular in [('footnotes','footnote'),('endnotes','endnote')]}
    observations=[]
    for part,root in sorted(roots.items()):
        if part.endswith('.rels') or not any(n.tag=='{'+W+'}p' for n in root.iter()): continue
        paths={}
        ancestry={}
        def index(node,path,ancestors):
            paths[id(node)]=path;ancestry[id(node)]=ancestors
            counts=Counter()
            for child in node:
                k=local(child.tag);idx=counts[k];counts[k]+=1
                index(child,path+'/'+k+'['+str(idx)+']',ancestors+[node])
        index(root,local(root.tag),[])
        paragraphs=[]
        for p in root.iter('{'+W+'}p'):
            events=[];accepted=[];rejected=[];raw=[];offset=0
            def walk(node,revision=None):
                nonlocal offset
                if node is not p and node.tag=='{'+W+'}p': return
                name=local(node.tag)
                if node.tag.startswith('{'+W+'}') and name in ['ins','del','moveFrom','moveTo']:
                    revision=name
                if node.tag in ['{'+W+'}t','{'+W+'}delText','{'+W+'}tab','{'+W+'}br','{'+W+'}cr']:
                    value=node.text or ''
                    if name=='tab': value='\t'
                    elif name in ['br','cr']: value='\n'
                    events.append({'type':name,'text':value,'offset':offset,'revision':revision,'attrs':dict(sorted(node.attrib.items()))})
                    raw.append(value);offset+=len(value)
                    if revision not in ['del','moveFrom'] and name!='delText': accepted.append(value)
                    if revision not in ['ins','moveTo']: rejected.append(value)
                elif node.tag.startswith('{'+W+'}') and name in ['footnoteReference','endnoteReference','bookmarkStart','bookmarkEnd','fldChar','instrText','drawing','pict']:
                    events.append({'type':name,'offset':offset,'revision':revision,'attrs':dict(sorted(node.attrib.items())),'text':node.text or ''})
                    if name in ['footnoteReference','endnoteReference']:
                        kind='footnotes' if name=='footnoteReference' else 'endnotes'
                        if node.get('{'+W+'}id') not in notes[kind]: issues.append({'kind':'unresolvedNote','part':part,'noteKind':kind,'id':node.get('{'+W+'}id')})
                elif node.tag=='{'+W+'}hyperlink':
                    events.append({'type':name,'offset':offset,'revision':revision,'attrs':dict(sorted(node.attrib.items()))})
                for child in node: walk(child,revision)
            walk(p)
            ancestors=ancestry[id(p)]
            paragraphs.append({'path':paths[id(p)],'containers':[{'type':local(a.tag),'id':a.get('{'+W+'}id')} for a in ancestors if local(a.tag) in ['tc','tr','tbl','txbxContent','footnote','endnote','comment']], 'rawText':''.join(raw),'acceptedText':''.join(accepted),'rejectedText':''.join(rejected),'events':events})
        tables=[]
        for table in root.iter('{'+W+'}tbl'):
            rows=[]
            for row in table.findall('{'+W+'}tr'):
                rows.append([{'path':paths[id(cell)],'gridSpan':[(n.get('{'+W+'}val')) for n in cell.findall('./{'+W+'}tcPr/{'+W+'}gridSpan')],'vMerge':[(n.get('{'+W+'}val','continue')) for n in cell.findall('./{'+W+'}tcPr/{'+W+'}vMerge')]} for cell in row.findall('{'+W+'}tc')])
            tables.append({'path':paths[id(table)],'rows':rows})
        starts=Counter(n.get('{'+W+'}id') for n in root.iter('{'+W+'}bookmarkStart'))
        ends=Counter(n.get('{'+W+'}id') for n in root.iter('{'+W+'}bookmarkEnd'))
        if starts!=ends: issues.append({'kind':'unmatchedBookmark','part':part,'starts':dict(starts),'ends':dict(ends)})
        observations.append({'part':part,'paragraphs':paragraphs,'tables':tables,'revisions':{name:sum(1 for _ in root.iter('{'+W+'}'+name)) for name in ['ins','del','moveFrom','moveTo']},'expandedXmlSha256':sha(json.dumps(expanded_tree(root),ensure_ascii=False,separators=(',',':')).encode())})
    return {'file':path.name,'bytes':path.stat().st_size,'sha256':sha(path.read_bytes()),'parts':{n:{'bytes':len(b),'sha256':sha(b)} for n,b in sorted(data.items())},'parseErrors':errors,'issues':issues,'stories':observations,'relationships':rels}

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('path');parser.add_argument('--out',type=Path)
    args=parser.parse_args();result=json.dumps(project(args.path),ensure_ascii=False,indent=2)+'\n'
    if args.out: args.out.write_text(result)
    else: print(result,end='')
