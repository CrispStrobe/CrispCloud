#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Audit two hash-pinned note discrepancies without trusting native DOCX as source."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import tarfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
SOURCES = {
    'note-markers': ('07-note-markers', 'note-floating-table.doc',
                     '80c3e144945e40e90fc8dac11e9e039e2fc2eef47bac1b7ac7d6ec1ef338cd72',
                     '4f14d52d703cff7f85c46bbc266d225251057959fa62144d23d0dbc81faec6cb'),
    'word-compatibility': ('03-word-compatibility', 'word-compatibility.doc',
                           '6c45dd6233904fab4e3583af53d52ac06d294773c01da14992bf3782bfae17dc',
                           '8c9d08a04ad0b0d76b886b68679b38e7717adc2afa768f36aa887e51383f118b'),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def u16(data, at):
    return struct.unpack_from('<H', data, at)[0]


def u32(data, at):
    return struct.unpack_from('<I', data, at)[0]


def stream(data, name):
    """Small independent CFB decoder restricted to the two checked v3 sources."""
    require(data[:8] == bytes.fromhex('d0cf11e0a1b11ae1'), 'CFB signature changed.')
    require(u16(data, 26) == 3 and u16(data, 30) == 9, 'CFB layout changed.')
    require(u16(data, 32) == 6 and u32(data, 56) == 4096, 'Mini-stream layout changed.')
    require(u32(data, 72) == 0, 'Unexpected extended DIFAT.')

    def sector(index):
        offset = (index + 1) * 512
        require(0 <= offset <= len(data) - 512, 'CFB sector exceeds source.')
        return data[offset:offset + 512]

    fat = []
    for index in struct.unpack_from('<109I', data, 76):
        if index < 0xfffffffa:
            fat.extend(struct.unpack('<128I', sector(index)))

    def chain(start, allocation, reader):
        result, seen = bytearray(), set()
        while start < 0xfffffffa:
            require(start not in seen and start < len(allocation), 'Invalid CFB chain.')
            seen.add(start)
            result.extend(reader(start))
            start = allocation[start]
        return bytes(result)

    directory = chain(u32(data, 48), fat, sector)
    entries = {}
    for offset in range(0, len(directory), 128):
        entry = directory[offset:offset + 128]
        length = u16(entry, 64)
        if length:
            require(2 <= length <= 64 and length % 2 == 0, 'Invalid CFB name.')
            entries[entry[:length - 2].decode('utf-16le')] = (
                u32(entry, 116), struct.unpack_from('<Q', entry, 120)[0])
    start, size = entries[name]
    if size >= 4096:
        result = chain(start, fat, sector)
    else:
        root_start, root_size = entries['Root Entry']
        mini = chain(root_start, fat, sector)[:root_size]
        raw_fat = chain(u32(data, 60), fat, sector)
        mini_fat = struct.unpack('<%dI' % (len(raw_fat) // 4), raw_fat)
        result = chain(start, mini_fat, lambda index: mini[index * 64:index * 64 + 64])
    require(size <= len(result), 'Truncated CFB stream.')
    return result[:size]


def raw_records(data):
    word = stream(data, 'WordDocument')
    table_name = '1Table' if u16(word, 10) & 0x200 else '0Table'
    table = stream(data, table_name)
    require(u16(word, 32) == 14 and u16(word, 62) == 22, 'FIB dimensions changed.')
    require(u16(word, 152) == 136 and u16(word, 1242) == 0, 'FIB extension changed.')
    pair = lambda index: (u32(word, 154 + index * 8), u32(word, 158 + index * 8))
    lengths = [u32(word, 64 + 4 * index) for index in [3, 4, 5, 7, 8, 9, 10]]
    at, length = pair(33)
    require(table[at] == 2 and length == 21 and u32(table, at + 1) == 16,
            'Audit requires one CLX piece without extra properties.')
    start, end = u32(table, at + 5), u32(table, at + 9)
    packed_fc = u32(table, at + 15)
    require(start == 0 and packed_fc == 2048, 'Pinned Unicode piece changed.')
    text = word[packed_fc:packed_fc + 2 * end].decode('utf-16le')
    off, size = pair(2)
    require(size >= 4 and (size - 4) % 6 == 0, 'Invalid footnote-reference PLC.')
    count = (size - 4) // 6
    refs = [{'anchorCp': u32(table, off + 4 * index),
             'recordOffset': off + 4 * (count + 1) + 2 * index,
             'autoIndex': u16(table, off + 4 * (count + 1) + 2 * index)}
            for index in range(count)]
    story_off, story_size = pair(3)
    note_cps = [u32(table, story_off + 4 * index) for index in range(story_size // 4)]
    dop, dop_size = pair(31)
    sect, sect_size = pair(6)
    require((sect_size - 4) % 16 == 0, 'Invalid section PLC.')
    section_count = (sect_size - 4) // 16
    sections = []
    for index in range(section_count):
        fc = u32(table, sect + 4 * (section_count + 1) + 12 * index + 2)
        limit, cursor = fc + 2 + u16(word, fc), fc + 2
        operations = []
        while cursor < limit:
            opcode, offset = u16(word, cursor), cursor
            cursor += 2
            size = [1, 1, 2, 4, 2, 2, None, 3][opcode >> 13]
            if size is None:
                size = word[cursor]
                cursor += 1
            require(cursor + size <= limit, 'Truncated section property.')
            operations.append({'opcode': f'{opcode:04x}', 'wordOffset': offset,
                               'operand': word[cursor:cursor + size].hex()})
            cursor += size
        sections.append({'startCp': u32(table, sect + 4 * index),
                         'endCp': u32(table, sect + 4 * (index + 1)),
                         'sepxOffset': fc, 'operations': operations})
    return {'tableStream': table_name, 'nFib': u16(word, 2),
            'cswNew': 0, 'piece': {'startCp': start, 'endCp': end,
                                  'wordOffset': packed_fc, 'encoding': 'UTF-16LE'},
            'storyLengths': lengths, 'questionMarkCount': text.count('?'),
            'references': refs, 'noteRangePlcOffset': story_off, 'noteRangeCps': note_cps,
            'notes': [{'startCp': lengths[0] + note_cps[index],
                       'endCp': lengths[0] + note_cps[index + 1],
                       'text': text[lengths[0] + note_cps[index]:lengths[0] + note_cps[index + 1]]}
                      for index in range(len(note_cps) - 2)],
            'dop': {'offset': dop, 'length': dop_size, 'footnoteWordOffset': dop + 2,
                    'footnoteWord': u16(table, dop + 2),
                    'footnoteRestart': u16(table, dop + 2) & 3,
                    'footnoteStart': u16(table, dop + 2) >> 2}, 'sections': sections}


def xml(data, part):
    with zipfile.ZipFile(io.BytesIO(data)) as package:
        return ET.fromstring(package.read(part))


def collect():
    result = {'schema': 'legacy-doc-parser/note-source-attribution', 'version': 1,
              'sealedRuntime': '0c3e59682952cce0e11301afec789e7ae2a1256a',
              'newNativeExecution': False, 'cases': {}}
    for name, (directory, source_name, expected_source, expected_archive) in SOURCES.items():
        source = ROOT / 'test/fixtures/word_native' / source_name
        data = source.read_bytes()
        require(sha(data) == expected_source, 'Source hash changed: ' + source_name)
        archive = ROOT / 'doc/evidence/native-corpus-0c3e596/sealed' / directory / 'native-artifacts.tar.xz'
        require(sha(archive.read_bytes()) == expected_archive, 'Sealed archive hash changed.')
        raw = raw_records(data)
        records = {}
        with tarfile.open(archive) as stored:
            def read(member):
                content = stored.extractfile(member).read()
                records[member] = sha(content)
                return content
            base = f'run/{name}'
            require(read(f'{base}/bridge/{name}.doc') == data, 'Fixture differs from sealed source.')
            native = read(f'{base}/native-docx/{name}.docx')
            converted = read(f'{base}/converted.docx')
            binary_render = json.loads(read(f'{base}/binary-render.json'))
            parser_render = json.loads(read(f'{base}/converted-render.json'))
            native_notes = xml(native, 'word/footnotes.xml')
            parser_notes = xml(converted, 'word/footnotes.xml')
            observations = {'binaryLayoutText': binary_render['text'],
                            'parserLayoutText': parser_render['text']}
            if name == 'note-markers':
                require(raw['questionMarkCount'] == 0, 'A source question mark exists.')
                require(raw['references'][-1] == {'anchorCp': 48, 'recordOffset': 816, 'autoIndex': 6},
                        'Sixth footnote reference changed.')
                note = raw['notes'][-1]
                require(note == {'startCp': 167, 'endCp': 206,
                                 'text': '\x02Table before  tail\x07\x07\rAfter note table\r'},
                        'Sixth note source range changed.')
                question = [node.text for node in native_notes.iter(W + 't') if node.text == '?']
                # The same manufactured marker is stored in the DrawingML
                # choice and VML fallback; native playback displays it once.
                require(question == ['?', '?'], 'Native alternate representations changed.')
                output_note = parser_notes.findall(W + 'footnote')[-1]
                require([node.tag for node in output_note] == [W + 'tbl', W + 'p', W + 'p'],
                        'Parser note block sequence changed.')
                require(len(list(output_note.iter(W + 'footnoteRef'))) == 1,
                        'Parser did not preserve one automatic marker.')
                require('?' not in ''.join(node.text or '' for node in output_note.iter(W + 't')),
                        'Parser copied the manufactured question mark.')
                binary_words = [word['text'] for page in binary_render['pages'] for word in page['words']]
                parser_words = [word['text'] for page in parser_render['pages'] for word in page['words']]
                require(len(binary_words) == len(parser_words), 'Word count changed.')
                require([(left, right) for left, right in zip(binary_words, parser_words)
                         if left != right] == [('?Table', 'Table')],
                        'Word sequence differs beyond the manufactured question mark.')
                require(binary_render['text'].count('?') == 1 and '?' not in parser_render['text'],
                        'Rendered question-mark count changed.')
                observations.update({'sourceMarkerCp': 167, 'sourceMarkerWordOffset': 2382,
                                     'sourceMarkerCodeUnit': 2,
                                     'nativeQuestionMarkAlternativeRepresentations': 2,
                                     'nativeRenderedQuestionMarks': 1,
                                     'parserAutomaticMarkersInSixthNote': 1,
                                     'wordSequencesAgreeAfterRemovingOnlyNativeQuestionMark': True})
            else:
                require(raw['nFib'] == 0x101 and raw['dop']['footnoteStart'] == 4,
                        'Effective source version or reserved DOP number changed.')
                for section in raw['sections']:
                    operations = section['operations']
                    require([op['operand'] for op in operations if op['opcode'] == '303c'] == ['01'],
                            'Section is not each-section restart.')
                    require(not any(op['opcode'] == '503f' for op in operations), 'An SNFtn offset exists.')
                sections = list(xml(converted, 'word/document.xml').iter(W + 'sectPr'))
                starts = [section.find(W + 'footnotePr').find(W + 'numStart').get(W + 'val')
                          for section in sections]
                require(starts == ['1', '1'], 'Parser source-defined numbering changed.')
                require('textiv' in binary_render['text'] and 'texti\n' in parser_render['text'],
                        'Observed source/parser note labels changed.')
                observations.update({'reservedDopStart': 4, 'effectiveSourceStart': 1,
                                     'parserSectionStarts': starts,
                                     'sourceSectionOffsetsAbsent': True})
        result['cases'][name] = {'source': str(source.relative_to(ROOT)), 'sourceSha256': expected_source,
                                 'archive': str(archive.relative_to(ROOT)), 'archiveSha256': expected_archive,
                                 'members': records, 'rawSource': raw, 'observations': observations}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Write the reproducible derived receipt.')
    args = parser.parse_args()
    result = collect()
    if args.write:
        (HERE / 'receipt.json').write_text(json.dumps(result, indent=2, ensure_ascii=True) + '\n')
    else:
        require(json.loads((HERE / 'receipt.json').read_text()) == result, 'Derived receipt does not reproduce.')
    print(json.dumps({'passed': True, 'cases': list(result['cases']),
                      'nativeExecution': False, 'sourceBytesChanged': False}))


if __name__ == '__main__':
    main()
