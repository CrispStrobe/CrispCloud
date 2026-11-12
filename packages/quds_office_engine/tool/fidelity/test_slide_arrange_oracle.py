"""Mutation controls against the native arrangement package oracle."""
from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import slide_arrange_oracle as oracle

P, A, NS = oracle.P, oracle.A, oracle.NS
ROOT = oracle.ROOT / 'build/fidelity-slide-arrange'


def shape(root, name):
    return next(node for node in root.findall('.//p:sp', NS)
                if node.find('p:nvSpPr/p:cNvPr', NS).get('name') == name)


class SlideArrangeOracleControls(unittest.TestCase):
    def reject(self, change):
        parts = oracle.read_parts(ROOT / 'direct-1.pptx')
        root = ET.fromstring(parts['ppt/slides/slide1.xml'])
        change(root)
        parts['ppt/slides/slide1.xml'] = ET.tostring(root)
        with self.assertRaises((AssertionError, ValueError)):
            oracle.inspect_parts(parts, grouped=True)

    def copy_corpus(self, target):
        for name in oracle.EXPECTED_FILES:
            shutil.copyfile(ROOT / name, target / name)

    def test_all_seven_actual_exports_match_authored_intent(self):
        self.assertEqual(oracle.verify(ROOT)['files_verified'], 7)

    def test_root_and_group_id_collision_is_rejected_by_numeric_value(self):
        def change(root):
            tree = root.find('p:cSld/p:spTree', NS)
            tree.find('p:grpSp/p:nvGrpSpPr/p:cNvPr', NS).set(
                'id', '000' + tree.find('p:nvGrpSpPr/p:cNvPr', NS).get('id'))
        self.reject(change)

    def test_group_and_shape_id_collision_is_rejected(self):
        def change(root):
            group = root.find('.//p:grpSp/p:nvGrpSpPr/p:cNvPr', NS)
            group.set('id', shape(root, 'Card 1').find('p:nvSpPr/p:cNvPr', NS).get('id'))
        self.reject(change)

    def test_duplicate_shape_id_is_rejected(self):
        def change(root):
            identity = shape(root, 'Card 2').find('p:nvSpPr/p:cNvPr', NS)
            identity.set('id', shape(root, 'Card 1').find('p:nvSpPr/p:cNvPr', NS).get('id'))
        self.reject(change)

    def test_non_uint32_native_ids_are_rejected(self):
        for value in ('-1', '4294967296', '2.5', 'NaN', ''):
            with self.subTest(value=value):
                self.reject(lambda root: root.find('.//p:grpSp/p:nvGrpSpPr/p:cNvPr', NS)
                            .set('id', value))

    def test_missing_root_identity_is_rejected(self):
        def change(root):
            properties = root.find('p:cSld/p:spTree/p:nvGrpSpPr', NS)
            properties.remove(properties.find('p:cNvPr', NS))
        self.reject(change)

    def test_changed_literal_position_is_rejected(self):
        self.reject(lambda root: shape(root, 'Card 3').find('p:spPr/a:xfrm/a:off', NS)
                    .set('x', '3654001'))

    def test_changed_literal_size_is_rejected(self):
        self.reject(lambda root: shape(root, 'Card 4').find('p:spPr/a:xfrm/a:ext', NS)
                    .set('cy', '999999'))

    def test_changed_text_is_rejected(self):
        def change(root):
            shape(root, 'Card 2').find('.//a:t', NS).text = 'Different card'
        self.reject(change)

    def test_changed_shape_name_is_rejected(self):
        self.reject(lambda root: shape(root, 'Card 5').find('p:nvSpPr/p:cNvPr', NS)
                    .set('name', 'Renamed card'))

    def test_changed_group_membership_is_rejected(self):
        def change(root):
            first, second = root.findall('p:cSld/p:spTree/p:grpSp', NS)
            card = shape(first, 'Card 2')
            first.remove(card)
            second.append(card)
        self.reject(change)

    def test_grouping_the_fifth_card_is_rejected(self):
        def change(root):
            tree = root.find('p:cSld/p:spTree', NS)
            card = shape(tree, 'Card 5')
            tree.remove(card)
            tree.findall('p:grpSp', NS)[1].append(card)
        self.reject(change)

    def test_changed_group_drawing_order_is_rejected(self):
        def change(root):
            tree = root.find('p:cSld/p:spTree', NS)
            first = tree.find('p:grpSp', NS)
            tree.remove(first)
            tree.append(first)
        self.reject(change)

    def test_nested_grouping_is_rejected(self):
        def change(root):
            tree = root.find('p:cSld/p:spTree', NS)
            first, second = tree.findall('p:grpSp', NS)
            tree.remove(first)
            second.append(first)
        self.reject(change)

    def test_group_transform_cannot_move_unchanged_child_coordinates(self):
        def change(root):
            properties = root.find('.//p:grpSp/p:grpSpPr', NS)
            transform = ET.SubElement(properties, '{' + A + '}xfrm')
            ET.SubElement(transform, '{' + A + '}off', x='1', y='0')
            ET.SubElement(transform, '{' + A + '}ext', cx='1', cy='1')
            ET.SubElement(transform, '{' + A + '}chOff', x='0', y='0')
            ET.SubElement(transform, '{' + A + '}chExt', cx='1', cy='1')
        self.reject(change)

    def test_rotated_shape_is_rejected(self):
        self.reject(lambda root: shape(root, 'Card 1').find('p:spPr/a:xfrm', NS)
                    .set('rot', '60000'))

    def test_valid_zip_with_source_byte_corruption_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as directory:
            target = Path(directory) / 'source.pptx'
            shutil.copyfile(oracle.FIXTURE, target)
            with ZipFile(target, 'a') as package:
                package.comment = b'Not the authored fixture bytes'
            with self.assertRaises(AssertionError):
                oracle.verify_source(target)

    def test_missing_save_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as directory:
            target = Path(directory)
            self.copy_corpus(target)
            (target / 'isolate-3.pptx').unlink()
            with self.assertRaises(AssertionError):
                oracle.verify(target)

    def test_unexpected_nested_export_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as directory:
            target = Path(directory)
            self.copy_corpus(target)
            (target / 'stale').mkdir()
            shutil.copyfile(oracle.FIXTURE, target / 'stale/extra.pptx')
            with self.assertRaises(AssertionError):
                oracle.verify(target)

    def test_legal_but_unstable_cycle_identity_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as directory:
            target = Path(directory)
            self.copy_corpus(target)
            path = target / 'isolate-3.pptx'
            parts = oracle.read_parts(path)
            root = ET.fromstring(parts['ppt/slides/slide1.xml'])
            root.find('.//p:grpSp/p:nvGrpSpPr/p:cNvPr', NS).set('id', '4294967295')
            parts['ppt/slides/slide1.xml'] = ET.tostring(root)
            oracle.inspect_parts(parts, grouped=True)  # Legal locally; unstable across saves.
            with ZipFile(path, 'w') as package:
                for name, data in parts.items():
                    package.writestr(name, data)
            with self.assertRaises(AssertionError):
                oracle.verify(target)


if __name__ == '__main__':
    unittest.main()
