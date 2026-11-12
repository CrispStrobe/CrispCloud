#!/usr/bin/env python3
"""Independent authored native frame geometry/wrap and first-import oracle."""
from pathlib import Path
import json
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
WPS = 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape'
W10 = 'urn:schemas-microsoft-com:office:word'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
VML = 'urn:schemas-microsoft-com:vml'
NS = {'a': 'http://schemas.openxmlformats.org/drawingml/2006/main', 'w': W, 'wp': WP, 'wps': WPS, 'w10': W10, 'mc': MC, 'v': VML}
SOURCE = Path(__file__).resolve().parents[2] / 'test/fixtures/fidelity/frame_wrap_source.xml'
MODES = {'none': 'wrapNone', 'square': 'wrapSquare', 'topBottom': 'wrapTopAndBottom'}
EXPECTED_PHASES = {
    **{f'{mode}-source.docx': (mode, 'source') for mode in MODES},
    **{f'{mode}-{cycle}.docx': (mode, 'imported') for mode in MODES for cycle in range(1, 4)},
}
EXPECTED_FILES = set(EXPECTED_PHASES)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def body_text(root):
    return [''.join(t.text or '' for t in p.iter(f'{{{W}}}t'))
            for p in root.findall('w:body/w:p', NS)
            if p.find('.//wp:anchor', NS) is None]


def inspect_document(data: bytes, mode: str, phase='imported'):
    require(mode in MODES and phase in ('source', 'imported'), 'unknown frame mode or phase')
    root = ET.fromstring(data)
    anchors = root.findall('.//wp:anchor', NS)
    require(len(anchors) == 1, 'frame anchor lost or duplicated')
    anchor = anchors[0]
    wraps = [node for node in anchor if node.tag.startswith(f'{{{WP}}}wrap')]
    require([node.tag for node in wraps] == [f'{{{WP}}}{MODES[mode]}'],
            'native wrapping mode changed')
    if mode == 'square':
        require(wraps[0].get('wrapText') == 'bothSides', 'square wrapping side changed')
    for axis in ['H', 'V']:
        position = anchor.find(f'wp:position{axis}', NS)
        require(position is not None and position.get('relativeFrom') == 'margin',
                'frame anchor reference changed')
        require(position.findtext('wp:posOffset', namespaces=NS) == '0',
                'frame position changed')
    extent = anchor.find('wp:extent', NS)
    require(extent is not None and extent.attrib == {'cx': '1270000', 'cy': '914400'},
            'frame extent changed')
    for path, color in [('a:solidFill/a:srgbClr', 'E8F0FB'), ('a:ln/a:solidFill/a:srgbClr', '355C7D')]:
        value = anchor.find('.//wps:spPr/' + path, NS)
        require(value is not None and value.get('val') == color, 'frame fill/stroke changed')
    lines = anchor.findall('.//wps:spPr/a:ln', NS)
    require(len(lines) == 1 and not lines[0].attrib,
            'authored line-property omission changed')
    text = anchor.findall('.//wps:txbx/w:txbxContent//w:t', NS)
    require([node.text for node in text] == ['Frame'], 'live frame text lost or duplicated')
    body_properties = anchor.find('.//wps:bodyPr', NS)
    require(body_properties is not None and not body_properties.attrib and not list(body_properties),
            'native body-property omission and default insets changed')
    host = root.find('w:body/w:p', NS)
    require(host is not None and host.find('w:pPr', NS) is None,
            'native anchor paragraph acquired invented properties')
    source = ET.fromstring(SOURCE.read_bytes())
    require(body_text(root) == body_text(source), 'following body text changed')
    sect = root.find('w:body/w:sectPr', NS)
    require(sect is not None, 'section geometry missing')
    for name, attrs in [('pgSz', {'w': '7200', 'h': '5600'}),
                        ('pgMar', dict.fromkeys(['top', 'bottom', 'left', 'right'], '480'))]:
        node = sect.find('w:' + name, NS)
        require(node is not None and all(node.get(f'{{{W}}}{key}') == value
                                        for key, value in attrs.items()),
                'section geometry changed')
    fallbacks = root.findall('.//mc:Fallback', NS)
    alternatives = root.findall('.//mc:AlternateContent', NS)
    if phase == 'source':
        require(not alternatives and not root.findall('.//w:pict', NS),
                'authored native source contains an invented compatibility branch')
    else:
        require(len(alternatives) == 1 and len(fallbacks) == 1,
                'imported frame compatibility fallback missing or duplicated')
        choices = alternatives[0].findall('mc:Choice', NS)
        require(len(choices) == 1 and choices[0].get('Requires') == 'wps' and
                choices[0].find('w:drawing/wp:anchor', NS) is anchor,
                'native frame escaped compatibility choice owner')
        rect = fallbacks[0].find('w:pict/v:rect', NS)
        require(rect is not None, 'native frame fallback rectangle missing')
        textbox = rect.find('v:textbox', NS)
        require(textbox is not None and
                [''.join(n.itertext()) for n in textbox.findall('w:txbxContent//w:t', NS)] == ['Frame'],
                'native frame fallback text changed')
        insets = textbox.get('inset', '').split(',')
        require(len(insets) == 4 and all(value.endswith('pt') for value in insets) and
                [float(value[:-2]) for value in insets] == [7.2, 3.6, 7.2, 3.6],
                'native fallback insets disagree with DrawingML defaults')
        fallback = rect.findall('w10:wrap', NS)
        if mode == 'topBottom':
            require(len(fallback) == 1 and fallback[0].get('type') == 'topAndBottom',
                'native top/bottom fallback changed')
        else:
            require(not fallback, 'unexpected native top/bottom fallback')
        styles = dict(item.split(':', 1) for item in rect.get('style', '').split(';') if ':' in item)
        require(styles.get('mso-wrap-style') == ('square' if mode == 'square' else 'none'),
                'native fallback wrapping mode changed')
    return {'mode': mode, 'phase': phase, 'frame_points': [100, 72], 'margin_points': 24}


def inspect_directory(directory):
    directory = Path(directory)
    actual = {path.name for path in directory.glob('*.docx')}
    require(actual == EXPECTED_FILES, f'frame export inventory mismatch: {actual ^ EXPECTED_FILES}')
    for name in sorted(EXPECTED_FILES):
        with ZipFile(directory / name) as archive:
            require(len(archive.namelist()) == len(set(archive.namelist())), 'duplicate ZIP entries')
            require(archive.testzip() is None, 'invalid ZIP content')
            inspect_document(archive.read('word/document.xml'), *EXPECTED_PHASES[name])


def main():
    inspect_directory('build/fidelity-frame-wrap')
    print(json.dumps({'status': 'passed', 'documents': len(EXPECTED_FILES)}))


if __name__ == '__main__':
    main()
