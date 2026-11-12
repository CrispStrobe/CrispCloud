#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Author small independent OOXML probes; never call the DOC converter.

Use --output NEW_DIRECTORY to review new inputs. Existing committed fixtures
are not overwritten. These files are source inputs, not generated goldens.
Native DOC bridge losses must be measured before claiming binary coverage.
"""
import argparse
from pathlib import Path
import zipfile

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'


def package(path, body):
    parts = {
        '[Content_Types].xml': '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''',
        '_rels/.rels': f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="office" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/_rels/document.xml.rels': f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="styles" Type="{R}/styles" Target="styles.xml"/></Relationships>',
        'word/styles.xml': f'''<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>''',
        'word/document.xml': f'''<w:document xmlns:w="{W}" xmlns:r="{R}" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w10="urn:schemas-microsoft-com:office:word"><w:body>{body}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>''',
    }
    with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, xml in sorted(parts.items()):
            item = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100644 << 16
            archive.writestr(item, ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + xml).encode())


def linked_textboxes():
    words = ' '.join(f'FLOW-{index:02d}' for index in range(1, 25))
    first = f'''<w:r><w:pict><v:rect id="_x0000_s1025" o:spid="_x0000_s1025" style="position:absolute;margin-left:72pt;margin-top:144pt;width:150pt;height:42pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;mso-next-textbox:#_x0000_s1026;z-index:1" fillcolor="#EEF4FA" strokecolor="#224466"><v:textbox inset="6pt,3pt,6pt,3pt" style="mso-next-textbox:#_x0000_s1026;v-text-anchor:top;mso-fit-shape-to-text:f"><w:txbxContent><w:p><w:r><w:t>{words}</w:t></w:r></w:p></w:txbxContent></v:textbox><w10:wrap type="none" anchorx="page" anchory="page"/></v:rect></w:pict></w:r>'''
    second = '''<w:r><w:pict><v:rect id="_x0000_s1026" o:spid="_x0000_s1026" style="position:absolute;margin-left:300pt;margin-top:144pt;width:150pt;height:114pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;z-index:2" fillcolor="#FAF4EE" strokecolor="#664422"><v:textbox inset="12pt,6pt,3pt,9pt" style="v-text-anchor:top;mso-fit-shape-to-text:f"><w:txbxContent><w:p/></w:txbxContent></v:textbox><w10:wrap type="none" anchorx="page" anchory="page"/></v:rect></w:pict></w:r>'''
    return f'<w:p><w:r><w:t>Linked text boxes: the numbered words should flow into the second box.</w:t></w:r>{first}{second}</w:p>'


def officeart_shapes():
    rect = '''<v:rect id="_x0000_s1030" o:spid="_x0000_s1030" style="position:absolute;margin-left:72pt;margin-top:144pt;width:108pt;height:54pt;rotation:15;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;z-index:1" fillcolor="#EEDD88" strokecolor="#884422" strokeweight="2pt"><v:fill opacity="49152f"/><v:stroke dashstyle="dash" joinstyle="round" endcap="round"/><v:shadow on="t" type="single" color="#777777" opacity="32768f" offset="4pt,6pt"/><w10:wrap type="none" anchorx="page" anchory="page"/></v:rect>'''
    ellipse = '''<v:oval id="_x0000_s1031" o:spid="_x0000_s1031" style="position:absolute;margin-left:240pt;margin-top:144pt;width:108pt;height:72pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;z-index:2" fillcolor="#99CCDD" strokecolor="#224466" strokeweight="1.5pt"><w10:wrap type="none" anchorx="page" anchory="page"/></v:oval>'''
    custom = '''<v:shape id="_x0000_s1032" o:spid="_x0000_s1032" style="position:absolute;margin-left:72pt;margin-top:288pt;width:216pt;height:108pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;z-index:3" coordorigin="0,0" coordsize="21600,10800" path="m0,10800l5400,0c10800,0,10800,10800,16200,5400l21600,10800xe" fillcolor="#BBDD99" strokecolor="#336622" strokeweight="2pt"><w10:wrap type="none" anchorx="page" anchory="page"/></v:shape>'''
    return '<w:p><w:r><w:t>OfficeArt geometry, solid fill, dash, opacity, rotation and offset shadow probes.</w:t></w:r>' + ''.join('<w:r><w:pict>' + shape + '</w:pict></w:r>' for shape in (rect, ellipse, custom)) + '</w:p>'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    package(args.output / 'linked-textboxes.docx', linked_textboxes())
    package(args.output / 'officeart-shapes.docx', officeart_shapes())


if __name__ == '__main__':
    main()
