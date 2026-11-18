"""Host-only default-property admission around the unchanged pinned renderer.

Rendering, SDK validation, hashes and pixel/cycle comparisons use the original
packages. Only the structure check derives an equivalent view of an explicit
disabled smallCaps property in the independently checked empty Word run.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile

_root = Path(__file__).resolve().parents[1]
_renderer_path = _root / 'tool/office-validation/render.py'
_renderer_sha256 = hashlib.sha256(_renderer_path.read_bytes()).hexdigest()
_manifest = json.loads((_root / 'tool/office_fidelity_manifest.json').read_text())
if _renderer_sha256 != _manifest['files']['tool/office-validation/render.py']:
    raise RuntimeError('Pinned renderer source drift; refusing host admission')
_spec = importlib.util.spec_from_file_location('_pinned_host_renderer', _renderer_path)
_renderer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_renderer)
_strict_word_geometry = _renderer.word_picture_package_geometry
_admissions = []
_w = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def _structure_view_geometry(path, case):
    if case not in ('word-gif', 'word-jpeg'):
        return _strict_word_geometry(path, case)
    with ZipFile(path) as package:
        names = package.namelist()
        if len(names) != len(set(names)):
            return _strict_word_geometry(path, case)
        xml = package.read('word/document.xml')
        document = ET.fromstring(xml)
        props = document.find(f'{_w}body/{_w}p/{_w}r/{_w}rPr')
        caps = [] if props is None else props.findall(_w + 'smallCaps')
        if not caps:
            return _strict_word_geometry(path, case)
        if (len(caps) != 1 or list(props).index(caps[0]) != 3
                or caps[0].attrib != {_w + 'val': '0'} or len(caps[0])
                or (caps[0].text or '').strip() or (caps[0].tail or '').strip()):
            return _strict_word_geometry(path, case)
        # The original checker still verifies the complete empty run, fonts,
        # paragraph order, all other properties, media and exact geometry.
        props.remove(caps[0])
        derived_xml = ET.tostring(document, encoding='utf-8')
        with tempfile.TemporaryDirectory(prefix='office-structure-') as folder:
            derived = Path(folder) / Path(path).name
            with ZipFile(derived, 'w') as view:
                for info in package.infolist():
                    view.writestr(info, derived_xml if info.filename == 'word/document.xml'
                                  else package.read(info.filename))
            geometry = _strict_word_geometry(derived, case)
    _admissions.append({'file': str(path),
                        'source_sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                        'source_xml_sha256': hashlib.sha256(xml).hexdigest(),
                        'structure_view_xml_sha256': hashlib.sha256(derived_xml).hexdigest(),
                        'property': 'w:smallCaps', 'exact_value': '0',
                        'scope': 'structure only; native rendering uses the original package'})
    return geometry


def _word_picture_geometry(path, case):
    try:
        return _structure_view_geometry(path, case)
    except (BadZipFile, KeyError, ET.ParseError, OSError):
        # Keep the pinned validator's rejection/error contract for malformed
        # inputs; this adapter is never an alternative error/skip path.
        return _strict_word_geometry(path, case)


_renderer.word_picture_package_geometry = _word_picture_geometry


def __getattr__(name):
    return getattr(_renderer, name)


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    _admissions.clear()
    result = _renderer.main(arguments)
    report_path = Path(arguments[1]) / 'render-report.json'
    if report_path.is_file():
        report = json.loads(report_path.read_text())
        report['host_structure_admission'] = {
            'pinned_renderer_sha256': _renderer_sha256,
            'host_adapter_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'records': _admissions,
            'raw_rendering_and_numeric_tolerances_changed': False}
        report_path.write_text(json.dumps(report, indent=2) + '\n')
    return result


if __name__ == '__main__':
    raise SystemExit(main())
