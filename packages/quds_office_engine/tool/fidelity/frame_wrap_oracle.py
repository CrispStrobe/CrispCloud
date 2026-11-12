#!/usr/bin/env python3
"""Independent native frame geometry/wrapping oracle for three edit/save cycles."""
from pathlib import Path
import json
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
WPS = 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape'
W10 = 'urn:schemas-microsoft-com:office:word'
NS = {'a': 'http://schemas.openxmlformats.org/drawingml/2006/main', 'w': W, 'wp': WP, 'wps': WPS, 'w10': W10}
SOURCE = Path(__file__).resolve().parents[2] / 'test/fixtures/fidelity/frame_wrap_source.xml'
MODES = {'none': 'wrapNone', 'square': 'wrapSquare', 'topBottom': 'wrapTopAndBottom'}
EXPECTED_FILES = {f'{mode}-{cycle}.docx' for mode in MODES for cycle in range(1, 4)}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def body_text(root):
    return [''.join(t.text or '' for t in p.iter(f'{{{W}}}t'))
            for p in root.findall('w:body/w:p', NS)
            if p.find('.//wp:anchor', NS) is None]


def inspect_document(data: bytes, mode: str):
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
    text = anchor.findall('.//wps:txbx/w:txbxContent//w:t', NS)
    require([node.text for node in text] == ['Frame'], 'live frame text lost or duplicated')
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
    fallback = root.findall('.//w10:wrap', NS)
    if mode == 'topBottom':
        require(len(fallback) == 1 and fallback[0].get('type') == 'topAndBottom',
                'native top/bottom fallback changed')
    return {'mode': mode, 'frame_points': [100, 72], 'margin_points': 24}


def main():
    directory = Path('build/fidelity-frame-wrap')
    actual = {path.name for path in directory.glob('*.docx')}
    require(actual == EXPECTED_FILES, f'frame export inventory mismatch: {actual ^ EXPECTED_FILES}')
    for name in sorted(EXPECTED_FILES):
        with ZipFile(directory / name) as archive:
            require(len(archive.namelist()) == len(set(archive.namelist())), 'duplicate ZIP entries')
            require(archive.testzip() is None, 'invalid ZIP content')
            inspect_document(archive.read('word/document.xml'), name.rsplit('-', 1)[0])
    print(json.dumps({'status': 'passed', 'documents': len(EXPECTED_FILES)}))


if __name__ == '__main__':
    main()
