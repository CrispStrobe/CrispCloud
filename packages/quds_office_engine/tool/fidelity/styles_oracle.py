"""Independent checks that style references remain sparse and editable."""
from pathlib import Path
import sys
from xml.etree import ElementTree as E
from zipfile import ZipFile
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def verify(path):
    with ZipFile(path) as z:
        styles=E.fromstring(z.read('word/styles.xml'))
        by_id={s.get(W+'styleId'):s for s in styles.findall(W+'style')}
        assert by_id['Child'].find(W+'basedOn').get(W+'val')=='Base'
        assert by_id['Child'].find(W+'rPr') is None, 'Inherited values became direct style properties'
        accent=by_id['Accent'].find(W+'rPr/'+W+'color').get(W+'val')
        assert accent==('008844' if path.name.startswith('edited') else 'AA3300')
        assert by_id['Base'].find(W+'rPr/'+W+'color').get(W+'themeColor')=='accent1'
        body=E.fromstring(z.read('word/document.xml')).find(W+'body')
        paragraphs=body.findall(W+'p')
        assert paragraphs[0].find(W+'pPr/'+W+'pStyle').get(W+'val')=='Child'
        assert len(paragraphs[0].find(W+'r/'+W+'rPr'))==0, 'Run inherited formatting was flattened'
        runs=paragraphs[1].findall(W+'r')
        for run in runs: assert run.find(W+'rPr/'+W+'rStyle').get(W+'val')=='Accent'
        assert runs[0].find(W+'rPr/'+W+'color') is None
        assert runs[1].find(W+'rPr/'+W+'color').get(W+'val')=='000000'
        assert runs[1].find(W+'rPr/'+W+'b').get(W+'val')=='0'
        assert body.find(W+'tbl/'+W+'tblPr/'+W+'tblStyle').get(W+'val')=='Regional'
    print(f'{path}: PASS')
if __name__=='__main__':
    paths=sorted(Path(sys.argv[1] if len(sys.argv)>1 else 'build/fidelity-styles').glob('*.docx'))
    assert len(paths)==6, f'Expected six style exports, got {len(paths)}'
    for path in paths: verify(path)
