from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import table_grid_oracle as oracle


def source(phase):
    name = 'table_grid_source.xml' if phase == 'source' else f'table_grid_{phase}_expected.xml'
    return ET.fromstring((oracle.FIXTURES / name).read_bytes())


def parts(root):
    return {'word/document.xml': ET.tostring(root)}


class TableGridOracleTest(unittest.TestCase):
    def test_independently_authored_positive_sources(self):
        for phase in ('source', *oracle.PHASES):
            with self.subTest(phase=phase):
                oracle.verify_parts(parts(source(phase)), phase)

    def test_corruption_controls(self):
        baseline = source('format')
        oracle.verify_parts(parts(baseline), 'format')
        for defect in ('physical-cell-confusion', 'lost-width', 'wrong-width-unit',
                       'rounded-width', 'stale-merged-content', 'orphan-continuation',
                       'wrong-span', 'wrong-fill-owner', 'lost-bold', 'lost-italic',
                       'lost-bookmark', 'nested-tail', 'nested-owner', 'grid-width',
                       'duplicate-width', 'property-order'):
            with self.subTest(defect=defect):
                root = deepcopy(baseline)
                outer = root.find('w:body/w:tbl', oracle.NS)
                rows = outer.findall('w:tr', oracle.NS)
                owner = rows[0].find('w:tc', oracle.NS)
                tail = rows[1].findall('w:tc', oracle.NS)[1]
                nested = outer.find('.//w:tbl', oracle.NS)
                if defect == 'physical-cell-confusion':
                    rows[1].find('w:tc/w:p', oracle.NS).append(deepcopy(tail.find('w:p/w:r', oracle.NS)))
                elif defect == 'lost-width':
                    prop = owner.find('w:tcPr', oracle.NS)
                    prop.remove(prop.find('w:tcW', oracle.NS))
                elif defect == 'wrong-width-unit':
                    rows[0].findall('w:tc', oracle.NS)[1].find('w:tcPr/w:tcW', oracle.NS).set(oracle.Q+'type', 'dxa')
                elif defect == 'rounded-width':
                    tail.find('w:tcPr/w:tcW', oracle.NS).set(oracle.Q+'w', '1460')
                elif defect == 'stale-merged-content':
                    owner.find('w:p/w:r/w:t', oracle.NS).text = 'Wrong '
                elif defect == 'orphan-continuation':
                    owner.find('w:tcPr', oracle.NS).remove(owner.find('w:tcPr/w:vMerge', oracle.NS))
                elif defect == 'wrong-span':
                    owner.find('w:tcPr/w:gridSpan', oracle.NS).set(oracle.Q+'val', '1')
                elif defect == 'wrong-fill-owner':
                    fill = owner.find('w:tcPr/w:shd', oracle.NS)
                    owner.find('w:tcPr', oracle.NS).remove(fill)
                    rows[1].find('w:tc/w:tcPr', oracle.NS).append(fill)
                elif defect == 'lost-bold':
                    owner.find('w:p/w:r/w:rPr/w:b', oracle.NS).set(oracle.Q+'val', '0')
                elif defect == 'lost-italic':
                    owner.findall('w:p', oracle.NS)[1].find('w:r/w:rPr/w:i', oracle.NS).set(oracle.Q+'val', '0')
                elif defect == 'lost-bookmark':
                    paragraph = owner.find('w:p', oracle.NS)
                    paragraph.remove(paragraph.find('w:bookmarkEnd', oracle.NS))
                elif defect == 'nested-tail':
                    nested.find('w:tr', oracle.NS).findall('w:tc', oracle.NS)[1].find('w:p/w:r/w:t', oracle.NS).text = 'Wrong nested cell'
                elif defect == 'nested-owner':
                    host = rows[2].find('w:tc', oracle.NS)
                    host.remove(nested)
                    rows[2].findall('w:tc', oracle.NS)[1].append(nested)
                elif defect == 'grid-width':
                    outer.find('w:tblGrid/w:gridCol', oracle.NS).set(oracle.Q+'w', '900')
                elif defect == 'duplicate-width':
                    owner.find('w:tcPr', oracle.NS).append(deepcopy(owner.find('w:tcPr/w:tcW', oracle.NS)))
                elif defect == 'property-order':
                    prop = owner.find('w:tcPr', oracle.NS)
                    width = prop.find('w:tcW', oracle.NS)
                    prop.remove(width)
                    prop.append(width)
                with self.assertRaises(AssertionError):
                    oracle.verify_parts(parts(root), 'format')

    def test_unmerge_rejects_width_duplication_and_bookmark_clones(self):
        for defect in ('width', 'bookmark'):
            with self.subTest(defect=defect):
                root = source('unmerge')
                oracle.verify_parts(parts(root), 'unmerge')
                cells = root.find('w:body/w:tbl/w:tr', oracle.NS).findall('w:tc', oracle.NS)
                if defect == 'width':
                    cells[1].find('w:tcPr/w:tcW', oracle.NS).set(oracle.Q+'w', '3600')
                else:
                    cells[1].find('w:p', oracle.NS).append(deepcopy(cells[0].find('w:p/w:bookmarkStart', oracle.NS)))
                with self.assertRaises(AssertionError):
                    oracle.verify_parts(parts(root), 'unmerge')

    def test_exact_inventory_cannot_succeed_on_missing_exports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path, phase in oracle.required_paths():
                target = root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                with ZipFile(target, 'w') as archive:
                    archive.writestr('word/document.xml', ET.tostring(source(phase)))
            self.assertEqual(len(oracle.verify_directory(root)), len(oracle.required_paths()))
            for path, _ in oracle.required_paths():
                target = root/path
                saved = target.read_bytes()
                target.unlink()
                with self.subTest(missing=path), self.assertRaises(AssertionError):
                    oracle.verify_directory(root)
                target.write_bytes(saved)


if __name__ == '__main__':
    unittest.main()
